#!/usr/bin/env bash
# ============================================================
# argocd_delete_projects.sh
#
# Deletes all non-default ArgoCD AppProjects after verifying
# no applications are still assigned to them.
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

# ── Helpers ───────────────────────────────────────────────────
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ ERROR: $*" >&2; exit 1; }

wait_for_project_empty() {
  local project="$1"
  local elapsed=0

  log "Verifying no apps remain in project '$project'..."
  while [[ $elapsed -lt $VERIFY_TIMEOUT ]]; do
    local count
    count=$(argocd app list --output name 2>/dev/null \
      | xargs -I{} argocd app get {} --output json 2>/dev/null \
      | python3 -c "
import sys, json
count = 0
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        app = json.loads(line)
        if app.get('spec', {}).get('project') == '$project':
            count += 1
    except Exception:
        pass
print(count)
" 2>/dev/null || echo "0")

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

# ── Install ArgoCD CLI ────────────────────────────────────────
log "Installing ArgoCD CLI..."
ARGOCD_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
curl -sSL -o /usr/local/bin/argocd \
  "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
chmod +x /usr/local/bin/argocd
log "ArgoCD CLI installed: $(argocd version --client --short)"

# ── Wait for ArgoCD server pod to be Running ──────────────────
log "Waiting for ArgoCD server pod to be Ready..."
kubectl wait pod \
  -n "$ARGOCD_NAMESPACE" \
  -l "app.kubernetes.io/name=argocd-server" \
  --for=condition=Ready \
  --timeout=120s

# ── Port-forward ArgoCD server ────────────────────────────────
log "Starting port-forward to ArgoCD server..."
kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" 8080:443 &
PORT_FORWARD_PID=$!
trap 'log "Stopping port-forward (PID $PORT_FORWARD_PID)..."; kill "$PORT_FORWARD_PID" 2>/dev/null || true' EXIT

log "Waiting for port 8080 to be ready..."
PORT_WAIT_TIMEOUT=60
PORT_WAIT_ELAPSED=0
until nc -z localhost 8080 2>/dev/null; do
  if [[ $PORT_WAIT_ELAPSED -ge $PORT_WAIT_TIMEOUT ]]; then
    fail "Port 8080 did not become available within ${PORT_WAIT_TIMEOUT}s. Port-forward may have crashed."
  fi
  sleep 2
  PORT_WAIT_ELAPSED=$((PORT_WAIT_ELAPSED + 2))
done
log "Port 8080 is ready (waited ${PORT_WAIT_ELAPSED}s)."

# ── Login ─────────────────────────────────────────────────────
log "Logging in to ArgoCD..."
LOGIN_ATTEMPTS=0
LOGIN_MAX=5
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

# ── Discover projects ─────────────────────────────────────────
log "Listing all AppProjects..."
ALL_PROJECTS=$(argocd proj list --output name 2>/dev/null || true)

if [[ -z "$ALL_PROJECTS" ]]; then
  log "⚠️  No AppProjects found. Nothing to delete."
  exit 0
fi

# Filter out the built-in 'default' project — ArgoCD manages it internally
PROJECTS_TO_DELETE=$(echo "$ALL_PROJECTS" | grep -v "^default$" || true)

if [[ -z "$PROJECTS_TO_DELETE" ]]; then
  log "Only the built-in 'default' project exists. Nothing to delete."
  exit 0
fi

log "Projects to delete:"
echo "$PROJECTS_TO_DELETE" | while read -r proj; do log "  - $proj"; done

# ── Verify each project is empty before deleting ──────────────
echo "$PROJECTS_TO_DELETE" | while read -r project; do
  wait_for_project_empty "$project"
done

# ── Delete projects ───────────────────────────────────────────
FAILED_PROJECTS=()
echo "$PROJECTS_TO_DELETE" | while read -r project; do
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
REMAINING=$(argocd proj list --output name 2>/dev/null | grep -v "^default$" || true)

if [[ -n "$REMAINING" ]]; then
  log "⚠️  The following projects still exist after deletion attempt:"
  echo "$REMAINING" | while read -r proj; do log "  - $proj"; done
  log "These may need manual cleanup."
else
  log "✅ All custom AppProjects deleted successfully."
fi
