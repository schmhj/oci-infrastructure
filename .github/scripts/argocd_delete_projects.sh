#!/usr/bin/env bash
# ============================================================
# argocd_delete_projects.sh
#
# Deletes all non-default ArgoCD AppProjects after verifying
# no applications are still assigned to them.
#
# Idempotent: safe to re-run if a previous execution failed
# partway through. Each step checks current state before acting.
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
PORT_WAIT_TIMEOUT=60
LOGIN_MAX=5

# ── Helpers ───────────────────────────────────────────────────
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ ERROR: $*" >&2; exit 1; }

namespace_exists() {
  kubectl get namespace "$1" &>/dev/null
}

project_exists() {
  argocd proj get "$1" &>/dev/null 2>&1
}

# Counts apps still assigned to a given project using a single
# argocd app list call (avoids N sequential app get calls)
apps_in_project() {
  local project="$1"
  argocd app list --output json 2>/dev/null \
    | python3 -c "
import sys, json
apps = json.load(sys.stdin)
count = sum(1 for a in apps if a.get('spec', {}).get('project') == '$project')
print(count)
" 2>/dev/null || echo "0"
}

wait_for_project_empty() {
  local project="$1"
  local elapsed=0

  log "Verifying no apps remain in project '$project'..."
  while [[ $elapsed -lt $VERIFY_TIMEOUT ]]; do
    local count
    count=$(apps_in_project "$project")
    if [[ "$count" -eq 0 ]]; then
      log "✅ No apps remaining in project '$project'."
      return 0
    fi
    log "  → $count app(s) still in project '$project'. Waiting ${VERIFY_INTERVAL}s..."
    sleep "$VERIFY_INTERVAL"
    elapsed=$((elapsed + VERIFY_INTERVAL))
  done

  log "⚠️  Timed out waiting for project '$project' to empty. Attempting deletion anyway."
  return 0
}

# ── Pre-flight ────────────────────────────────────────────────
[[ -z "${ARGOCD_ADMIN_PASSWORD:-}" ]] && fail "ARGOCD_ADMIN_PASSWORD is not set."

namespace_exists "$ARGOCD_NAMESPACE" \
  || { log "ArgoCD namespace '$ARGOCD_NAMESPACE' does not exist — nothing to do."; exit 0; }

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

# ── Wait for ArgoCD server to be Ready ───────────────────────
# 'kubectl wait pod' fails immediately with "no matching resources"
# when no pod exists yet (e.g. deployment still creating it).
# 'kubectl rollout status' correctly blocks until the deployment
# has at least one Ready replica, regardless of current pod count.
log "Waiting for ArgoCD server deployment to be Available..."
kubectl rollout status deployment/argocd-server \
  -n "$ARGOCD_NAMESPACE" \
  --timeout=120s

# ── Port-forward (skip if port already open) ──────────────────
PORT_FORWARD_PID=""
if nc -z localhost 8080 2>/dev/null; then
  log "Port 8080 already open — skipping port-forward."
else
  log "Starting port-forward to ArgoCD server..."
  kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" 8080:443 &
  PORT_FORWARD_PID=$!
  trap 'log "Stopping port-forward (PID $PORT_FORWARD_PID)..."; kill "$PORT_FORWARD_PID" 2>/dev/null || true' EXIT

  log "Waiting for port 8080 to accept connections..."
  PORT_WAIT_ELAPSED=0
  until nc -z localhost 8080 2>/dev/null; do
    if [[ $PORT_WAIT_ELAPSED -ge $PORT_WAIT_TIMEOUT ]]; then
      fail "Port 8080 did not become available within ${PORT_WAIT_TIMEOUT}s. Port-forward may have crashed."
    fi
    sleep 2
    PORT_WAIT_ELAPSED=$((PORT_WAIT_ELAPSED + 2))
  done
  log "Port 8080 is ready (waited ${PORT_WAIT_ELAPSED}s)."
fi

# ── Login (skip if session token already valid) ───────────────
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
      fail "ArgoCD login failed after ${LOGIN_MAX} attempts."
    fi
    log "  Login attempt $LOGIN_ATTEMPTS failed, retrying in 5s..."
    sleep 5
  done
  log "✅ Logged in to ArgoCD successfully."
fi

# ── Discover projects ─────────────────────────────────────────
log "Listing all AppProjects..."
# mapfile keeps results in the current shell (no subshell scoping issue)
mapfile -t ALL_PROJECTS < <(argocd proj list --output name 2>/dev/null || true)

if [[ ${#ALL_PROJECTS[@]} -eq 0 ]]; then
  log "No AppProjects found — already deleted or never existed. Exiting cleanly."
  exit 0
fi

# Filter out the built-in 'default' project — ArgoCD manages it internally
mapfile -t PROJECTS_TO_DELETE < <(printf '%s\n' "${ALL_PROJECTS[@]}" | grep -v "^default$" || true)

if [[ ${#PROJECTS_TO_DELETE[@]} -eq 0 ]]; then
  log "Only the built-in 'default' project exists — nothing to delete."
  exit 0
fi

log "Projects to delete (${#PROJECTS_TO_DELETE[@]}):"
for proj in "${PROJECTS_TO_DELETE[@]}"; do log "  - $proj"; done

# ── Verify each project is empty, then delete ─────────────────
FAILED_PROJECTS=()

for project in "${PROJECTS_TO_DELETE[@]}"; do
  # Idempotency: skip if already gone
  if ! project_exists "$project"; then
    log "Project '$project' no longer exists — skipping."
    continue
  fi

  wait_for_project_empty "$project"

  log "Deleting project: $project"
  if argocd proj delete "$project" 2>/dev/null; then
    log "  ✅ Deleted: $project"
  else
    log "  ⚠️  argocd CLI deletion failed for '$project'. Attempting kubectl fallback..."
    if kubectl delete appproject "$project" -n "$ARGOCD_NAMESPACE" --timeout=60s 2>/dev/null; then
      log "  ✅ Deleted via kubectl: $project"
    else
      log "  ❌ Failed to delete project '$project'. It may need manual cleanup."
      FAILED_PROJECTS+=("$project")
    fi
  fi
done

# ── Final verification ────────────────────────────────────────
log "Verifying projects have been removed..."
mapfile -t REMAINING < <(argocd proj list --output name 2>/dev/null | grep -v "^default$" || true)

if [[ ${#REMAINING[@]} -gt 0 ]]; then
  log "⚠️  The following projects still exist after deletion attempt:"
  for proj in "${REMAINING[@]}"; do log "  - $proj"; done
  log "These may need manual cleanup."
else
  log "✅ All custom AppProjects deleted successfully."
fi

if [[ ${#FAILED_PROJECTS[@]} -gt 0 ]]; then
  log "❌ ${#FAILED_PROJECTS[@]} project(s) could not be deleted: ${FAILED_PROJECTS[*]}"
  exit 1
fi
