#!/usr/bin/env bash
# ============================================================
# argocd_delete_root_app.sh
#
# Gracefully shuts down the ArgoCD root app and all its
# cascaded child applications before deletion.
#
# Required env vars:
#   ARGOCD_ADMIN_PASSWORD  - ArgoCD admin password
#
# Assumes kubeconfig is already configured.
# ============================================================

set -euo pipefail

# ── Config ────────────────────────────────────────────────────
ARGOCD_NAMESPACE="argocd"
ROOT_APP_NAME="root-app"
ARGOCD_SERVER="localhost:8080"
GRACEFUL_TIMEOUT=300   # seconds to wait for each app to become Suspended
DELETE_TIMEOUT=180     # seconds to wait for root-app deletion to complete

# ── Helpers ───────────────────────────────────────────────────
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ ERROR: $*" >&2; exit 1; }

wait_for_app_health() {
  local app="$1"
  local target_health="$2"
  local timeout="$3"
  local interval=10
  local elapsed=0

  log "Waiting for app '$app' to reach health status: $target_health (timeout: ${timeout}s)"
  while [[ $elapsed -lt $timeout ]]; do
    local health
    health=$(argocd app get "$app" --output json 2>/dev/null \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status']['health']['status'])" 2>/dev/null || echo "Unknown")

    if [[ "$health" == "$target_health" ]]; then
      log "✅ App '$app' reached health: $target_health"
      return 0
    fi

    log "  → Current health: $health. Retrying in ${interval}s..."
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  log "⚠️  Timed out waiting for '$app' to reach '$target_health'. Proceeding anyway."
  return 0
}

wait_for_app_deleted() {
  local app="$1"
  local timeout="$2"
  local interval=10
  local elapsed=0

  log "Waiting for app '$app' to be fully deleted (timeout: ${timeout}s)"
  while [[ $elapsed -lt $timeout ]]; do
    if ! argocd app get "$app" &>/dev/null; then
      log "✅ App '$app' has been deleted."
      return 0
    fi
    log "  → App still exists. Retrying in ${interval}s..."
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  fail "Timed out waiting for app '$app' to be deleted."
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

# ── Port-forward ArgoCD server ────────────────────────────────
log "Starting port-forward to ArgoCD server..."
kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" 8080:443 &
PORT_FORWARD_PID=$!
trap 'log "Stopping port-forward (PID $PORT_FORWARD_PID)..."; kill "$PORT_FORWARD_PID" 2>/dev/null || true' EXIT
sleep 5

# ── Login ─────────────────────────────────────────────────────
log "Logging in to ArgoCD..."
argocd login "$ARGOCD_SERVER" \
  --username admin \
  --password "$ARGOCD_ADMIN_PASSWORD" \
  --insecure \
  --grpc-web

# ── Check root app exists ─────────────────────────────────────
if ! argocd app get "$ROOT_APP_NAME" &>/dev/null; then
  log "⚠️  Root app '$ROOT_APP_NAME' not found. Nothing to delete."
  exit 0
fi

# ── Discover all child apps ───────────────────────────────────
log "Discovering child applications managed by '$ROOT_APP_NAME'..."
CHILD_APPS=$(argocd app list --output name 2>/dev/null | grep -v "^${ROOT_APP_NAME}$" || true)

if [[ -n "$CHILD_APPS" ]]; then
  log "Found child apps:"
  echo "$CHILD_APPS" | while read -r app; do log "  - $app"; done

  # ── Step 1: Disable auto-sync on all child apps ───────────
  log "Disabling auto-sync on all child apps to prevent reconciliation..."
  echo "$CHILD_APPS" | while read -r app; do
    log "  Disabling auto-sync: $app"
    argocd app set "$app" --sync-policy none 2>/dev/null || \
      log "  ⚠️  Could not disable auto-sync for '$app' — may already be manual."
  done

  # ── Step 2: Disable auto-sync on root app ─────────────────
  log "Disabling auto-sync on root app '$ROOT_APP_NAME'..."
  argocd app set "$ROOT_APP_NAME" --sync-policy none 2>/dev/null || true

  # ── Step 3: Scale down workloads in child app namespaces ──
  log "Scaling down deployments and statefulsets in child app namespaces..."
  echo "$CHILD_APPS" | while read -r app; do
    NAMESPACE=$(argocd app get "$app" --output json 2>/dev/null \
      | python3 -c "import sys,json; print(json.load(sys.stdin)['spec']['destination']['namespace'])" 2>/dev/null || echo "")

    if [[ -n "$NAMESPACE" ]]; then
      log "  Scaling down workloads in namespace: $NAMESPACE"
      kubectl scale deployment --all -n "$NAMESPACE" --replicas=0 2>/dev/null || true
      kubectl scale statefulset --all -n "$NAMESPACE" --replicas=0 2>/dev/null || true
    fi
  done

  # ── Step 4: Wait for child apps to show Suspended/Healthy ─
  echo "$CHILD_APPS" | while read -r app; do
    wait_for_app_health "$app" "Healthy" "$GRACEFUL_TIMEOUT" || true
  done

else
  log "No child apps found. Proceeding with root app deletion only."

  # Still disable auto-sync on root before deleting
  log "Disabling auto-sync on root app '$ROOT_APP_NAME'..."
  argocd app set "$ROOT_APP_NAME" --sync-policy none 2>/dev/null || true
fi

# ── Step 5: Delete root app with cascade ─────────────────────
log "Deleting root app '$ROOT_APP_NAME' with cascade (this will delete all child apps and their resources)..."
argocd app delete "$ROOT_APP_NAME" \
  --cascade \
  --yes

# ── Step 6: Wait for root app to be fully gone ────────────────
wait_for_app_deleted "$ROOT_APP_NAME" "$DELETE_TIMEOUT"

# ── Step 7: Confirm all child apps are gone ───────────────────
if [[ -n "$CHILD_APPS" ]]; then
  log "Verifying all child apps have been removed..."
  REMAINING=$(argocd app list --output name 2>/dev/null | grep -v "^${ROOT_APP_NAME}$" || true)
  if [[ -n "$REMAINING" ]]; then
    log "⚠️  Some apps still present after cascade delete. Force-deleting..."
    echo "$REMAINING" | while read -r app; do
      log "  Force-deleting: $app"
      argocd app delete "$app" --cascade --yes 2>/dev/null || true
    done
  fi
fi

log "✅ Root app and all child applications deleted successfully."
