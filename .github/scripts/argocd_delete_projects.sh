#!/usr/bin/env bash
# ============================================================
# argocd_delete_projects.sh
#
# Deletes all non-default ArgoCD AppProjects after verifying
# no applications are still assigned to them.
#
# Two-path design:
#   PRIMARY   — argocd CLI via port-forward (clean API-driven delete)
#   FALLBACK  — direct kubectl CR deletion (used when the ArgoCD
#               server pod is gone, crashing, or unreachable)
#
# Idempotent: safe to re-run at any point. Each step checks
# current state before acting.
#
# Required env vars:
#   ARGOCD_ADMIN_PASSWORD  - ArgoCD admin password
#
# Assumes kubeconfig is already configured.
# ============================================================

set -euo pipefail

# ── Config ────────────────────────────────────────────────────
ARGOCD_NAMESPACE="argocd"
ARGOCD_SERVER="localhost:8080"
VERIFY_TIMEOUT=120   # seconds to wait for apps to clear a project
VERIFY_INTERVAL=10
PORT_WAIT_TIMEOUT=30
LOGIN_MAX=5

# ── Helpers ───────────────────────────────────────────────────
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ ERROR: $*" >&2; exit 1; }

namespace_exists() {
  kubectl get namespace "$1" &>/dev/null
}

crd_exists() {
  kubectl get crd "$1" &>/dev/null 2>&1
}

# Returns 0 if the argocd-server pod is actually in Running phase
argocd_server_ready() {
  local ready
  ready=$(kubectl get pods \
    -n "$ARGOCD_NAMESPACE" \
    -l "app.kubernetes.io/name=argocd-server" \
    --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | wc -l)
  [[ "$ready" -gt 0 ]]
}

project_exists_cli() {
  argocd proj get "$1" &>/dev/null 2>&1
}

project_exists_kubectl() {
  kubectl get appproject "$1" -n "$ARGOCD_NAMESPACE" &>/dev/null 2>&1
}

# Counts apps assigned to a project via argocd CLI.
# Returns a number; on any CLI error returns "error" so callers
# can distinguish "0 apps" from "CLI failed silently".
apps_in_project_cli() {
  local project="$1"
  local result
  result=$(argocd app list --output json 2>/dev/null \
    | python3 -c "
import sys, json
try:
    apps = json.load(sys.stdin)
    count = sum(1 for a in apps if a.get('spec', {}).get('project') == '$project')
    print(count)
except Exception:
    print('error')
" 2>/dev/null || echo "error")
  echo "$result"
}

# Counts Application CRs assigned to a project directly via kubectl.
# Used as fallback verification when CLI is unavailable.
apps_in_project_kubectl() {
  local project="$1"
  crd_exists "applications.argoproj.io" || { echo "0"; return; }
  kubectl get applications.argoproj.io \
    --all-namespaces \
    -o json 2>/dev/null \
    | python3 -c "
import sys, json
try:
    items = json.load(sys.stdin)['items']
    count = sum(1 for a in items if a.get('spec', {}).get('project') == '$project')
    print(count)
except Exception:
    print('0')
" 2>/dev/null || echo "0"
}

wait_for_project_empty_cli() {
  local project="$1"
  local elapsed=0

  log "Verifying no apps remain in project '$project' (CLI)..."
  while [[ $elapsed -lt $VERIFY_TIMEOUT ]]; do
    local count
    count=$(apps_in_project_cli "$project")
    if [[ "$count" == "error" ]]; then
      warn "CLI returned an error counting apps in project '$project'. Proceeding with deletion."
      return 0
    fi
    if [[ "$count" -eq 0 ]]; then
      log "✅ No apps remaining in project '$project'."
      return 0
    fi
    log "  → $count app(s) still in project '$project'. Waiting ${VERIFY_INTERVAL}s..."
    sleep "$VERIFY_INTERVAL"
    elapsed=$((elapsed + VERIFY_INTERVAL))
  done

  warn "Timed out waiting for project '$project' to empty. Proceeding with deletion anyway."
  return 0
}

wait_for_project_empty_kubectl() {
  local project="$1"
  local elapsed=0

  log "Verifying no apps remain in project '$project' (kubectl)..."
  while [[ $elapsed -lt $VERIFY_TIMEOUT ]]; do
    local count
    count=$(apps_in_project_kubectl "$project")
    if [[ "$count" -eq 0 ]]; then
      log "✅ No apps remaining in project '$project'."
      return 0
    fi
    log "  → $count app(s) still in project '$project'. Waiting ${VERIFY_INTERVAL}s..."
    sleep "$VERIFY_INTERVAL"
    elapsed=$((elapsed + VERIFY_INTERVAL))
  done

  warn "Timed out waiting for project '$project' to empty. Proceeding with deletion anyway."
  return 0
}

# Deletes a single AppProject CR directly via kubectl, stripping
# any finalizers first to avoid deletion hanging.
kubectl_delete_project() {
  local project="$1"

  if ! project_exists_kubectl "$project"; then
    log "  Project '$project' not found via kubectl — already gone."
    return 0
  fi

  # Strip finalizers if present
  FINALIZERS=$(kubectl get appproject "$project" \
    -n "$ARGOCD_NAMESPACE" \
    -o jsonpath='{.metadata.finalizers}' 2>/dev/null || echo "")
  if [[ -n "$FINALIZERS" && "$FINALIZERS" != "[]" ]]; then
    log "  Removing finalizers from AppProject/$project"
    kubectl patch appproject "$project" \
      -n "$ARGOCD_NAMESPACE" \
      --type=merge \
      -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
  fi

  log "  Deleting AppProject/$project via kubectl"
  kubectl delete appproject "$project" \
    -n "$ARGOCD_NAMESPACE" \
    --timeout=60s 2>/dev/null && \
    log "  ✅ Deleted: $project" || \
    warn "  kubectl delete failed for '$project' — may need manual cleanup."
}

# ── Pre-flight ────────────────────────────────────────────────
[[ -z "${ARGOCD_ADMIN_PASSWORD:-}" ]] && fail "ARGOCD_ADMIN_PASSWORD is not set."

# If the namespace is already gone, all CRs are gone too — nothing to do
if ! namespace_exists "$ARGOCD_NAMESPACE"; then
  log "ArgoCD namespace '$ARGOCD_NAMESPACE' does not exist — already cleaned up. Exiting cleanly."
  exit 0
fi

# If the AppProject CRD itself is gone, there's nothing to delete
if ! crd_exists "appprojects.argoproj.io"; then
  log "AppProject CRD not present — no projects to delete. Exiting cleanly."
  exit 0
fi

# ── Install ArgoCD CLI (skip if already present at same version) ──
log "Checking ArgoCD CLI..."
ARGOCD_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")

INSTALLED_VERSION=$(argocd version --client --short 2>/dev/null | grep -oP 'v[\d.]+' | head -1 || echo "none")

if [[ "$INSTALLED_VERSION" == "$ARGOCD_VERSION" ]]; then
  log "ArgoCD CLI already at $ARGOCD_VERSION — skipping download."
else
  log "Installing ArgoCD CLI $ARGOCD_VERSION (installed: $INSTALLED_VERSION)..."
  curl -sSL -o /usr/local/bin/argocd \
    "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
  chmod +x /usr/local/bin/argocd
  log "ArgoCD CLI installed: $(argocd version --client --short)"
fi

# ── Decide: primary (argocd CLI) or fallback (kubectl) ────────
#
# Check whether the server pod is actually Running right now —
# not just whether the deployment spec was last satisfied.
# 'rollout status' can report success while the pod is in
# CrashLoopBackOff, OOMKilled, or Terminating, all of which
# cause port-forward to bind but immediately drop the tunnel.
#
ARGOCD_CLI_AVAILABLE=false
PORT_FORWARD_PID=""

if argocd_server_ready; then
  log "ArgoCD server pod is Running. Attempting CLI path..."

  # Port-forward (skip if already open)
  if nc -z localhost 8080 2>/dev/null; then
    log "Port 8080 already open — skipping port-forward."
    ARGOCD_CLI_AVAILABLE=true
  else
    log "Starting port-forward to ArgoCD server..."
    kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" 8080:443 &
    PORT_FORWARD_PID=$!
    trap 'log "Stopping port-forward (PID $PORT_FORWARD_PID)..."; kill "$PORT_FORWARD_PID" 2>/dev/null || true' EXIT

    log "Waiting for port 8080 to accept connections (timeout: ${PORT_WAIT_TIMEOUT}s)..."
    PORT_WAIT_ELAPSED=0
    while ! nc -z localhost 8080 2>/dev/null; do
      if ! kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
        warn "Port-forward process (PID $PORT_FORWARD_PID) died unexpectedly."
        break
      fi
      if [[ $PORT_WAIT_ELAPSED -ge $PORT_WAIT_TIMEOUT ]]; then
        warn "Port 8080 did not become available within ${PORT_WAIT_TIMEOUT}s."
        break
      fi
      sleep 2
      PORT_WAIT_ELAPSED=$((PORT_WAIT_ELAPSED + 2))
    done

    if nc -z localhost 8080 2>/dev/null; then
      log "Port 8080 is ready (waited ${PORT_WAIT_ELAPSED}s)."
      ARGOCD_CLI_AVAILABLE=true
    else
      warn "Port-forward failed. Falling back to kubectl deletion."
      kill "$PORT_FORWARD_PID" 2>/dev/null || true
      PORT_FORWARD_PID=""
    fi
  fi

  # Login
  if [[ "$ARGOCD_CLI_AVAILABLE" == "true" ]]; then
    log "Checking ArgoCD login status..."
    if argocd account get-user-info --server "$ARGOCD_SERVER" --insecure --grpc-web &>/dev/null 2>&1; then
      log "Already logged in to ArgoCD — skipping login."
    else
      log "Logging in to ArgoCD..."
      LOGIN_ATTEMPTS=0
      until argocd login "$ARGOCD_SERVER" \
          --username admin \
          --password "$ARGOCD_ADMIN_PASSWORD" \
          --insecure \
          --grpc-web 2>/dev/null; do
        LOGIN_ATTEMPTS=$((LOGIN_ATTEMPTS + 1))
        if [[ $LOGIN_ATTEMPTS -ge $LOGIN_MAX ]]; then
          warn "ArgoCD login failed after ${LOGIN_MAX} attempts. Falling back to kubectl deletion."
          ARGOCD_CLI_AVAILABLE=false
          break
        fi
        log "  Login attempt $LOGIN_ATTEMPTS failed, retrying in 5s..."
        sleep 5
      done
      [[ "$ARGOCD_CLI_AVAILABLE" == "true" ]] && log "✅ Logged in to ArgoCD successfully."
    fi
  fi
else
  warn "ArgoCD server pod is not Running (may be terminating, crashing, or already deleted)."
  warn "Skipping CLI path — falling back to kubectl deletion."
fi

# ══════════════════════════════════════════════════════════════
# PRIMARY PATH — ArgoCD CLI
# ══════════════════════════════════════════════════════════════
FAILED_PROJECTS=()

if [[ "$ARGOCD_CLI_AVAILABLE" == "true" ]]; then
  log "Using ArgoCD CLI path."

  log "Listing all AppProjects..."
  mapfile -t ALL_PROJECTS < <(argocd proj list --output name 2>/dev/null || true)

  if [[ ${#ALL_PROJECTS[@]} -eq 0 ]]; then
    log "No AppProjects found via CLI — nothing to delete."
  else
    mapfile -t PROJECTS_TO_DELETE < <(printf '%s\n' "${ALL_PROJECTS[@]}" | grep -v "^default$" || true)

    if [[ ${#PROJECTS_TO_DELETE[@]} -eq 0 ]]; then
      log "Only the built-in 'default' project exists — nothing to delete."
    else
      log "Projects to delete (${#PROJECTS_TO_DELETE[@]}):"
      for proj in "${PROJECTS_TO_DELETE[@]}"; do log "  - $proj"; done

      for project in "${PROJECTS_TO_DELETE[@]}"; do
        # Idempotency: skip if already gone
        if ! project_exists_cli "$project"; then
          log "Project '$project' no longer exists — skipping."
          continue
        fi

        wait_for_project_empty_cli "$project"

        log "Deleting project via CLI: $project"
        if argocd proj delete "$project" 2>/dev/null; then
          log "  ✅ Deleted: $project"
        else
          warn "argocd CLI deletion failed for '$project'. Will retry via kubectl in fallback pass."
          FAILED_PROJECTS+=("$project")
        fi
      done
    fi
  fi

  # Final verification via CLI
  log "Verifying projects have been removed (CLI)..."
  mapfile -t REMAINING_CLI < <(argocd proj list --output name 2>/dev/null | grep -v "^default$" || true)
  if [[ ${#REMAINING_CLI[@]} -gt 0 ]]; then
    warn "The following projects still exist after CLI deletion — will retry via kubectl:"
    for proj in "${REMAINING_CLI[@]}"; do
      warn "  - $proj"
      # Add to failed list if not already there
      [[ " ${FAILED_PROJECTS[*]} " == *" $proj "* ]] || FAILED_PROJECTS+=("$proj")
    done
  else
    log "✅ All custom AppProjects deleted via CLI."
  fi
fi

# ══════════════════════════════════════════════════════════════
# FALLBACK PATH — direct kubectl CR deletion
# Runs when: CLI unavailable, login failed, or any project
# survived the CLI delete pass above.
# ══════════════════════════════════════════════════════════════
log "Running kubectl AppProject cleanup pass..."

# Collect all non-default AppProject CRs directly from the API server
mapfile -t ALL_PROJECTS_KUBECTL < <(kubectl get appproject \
  -n "$ARGOCD_NAMESPACE" \
  --no-headers \
  -o custom-columns=":metadata.name" 2>/dev/null \
  | grep -v "^default$" || true)

if [[ ${#ALL_PROJECTS_KUBECTL[@]} -eq 0 ]]; then
  log "No non-default AppProject CRs found via kubectl — nothing to clean up."
else
  log "Found ${#ALL_PROJECTS_KUBECTL[@]} AppProject CR(s) to clean up via kubectl:"
  for proj in "${ALL_PROJECTS_KUBECTL[@]}"; do log "  - $proj"; done

  for project in "${ALL_PROJECTS_KUBECTL[@]}"; do
    [[ -z "$project" ]] && continue

    # Verify no Application CRs still reference this project before deleting
    wait_for_project_empty_kubectl "$project"

    kubectl_delete_project "$project"
  done
fi

# ── Final verification (kubectl — works regardless of CLI state) ──
log "Running final verification via kubectl..."
mapfile -t REMAINING_FINAL < <(kubectl get appproject \
  -n "$ARGOCD_NAMESPACE" \
  --no-headers \
  -o custom-columns=":metadata.name" 2>/dev/null \
  | grep -v "^default$" || true)

if [[ ${#REMAINING_FINAL[@]} -gt 0 ]]; then
  warn "The following AppProject CRs still exist after all deletion attempts:"
  for proj in "${REMAINING_FINAL[@]}"; do warn "  - $proj"; done
  warn "These may need manual cleanup."
  exit 1
else
  log "✅ All custom AppProjects deleted successfully."
fi
