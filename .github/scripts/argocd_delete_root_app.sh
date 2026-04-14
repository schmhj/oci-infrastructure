#!/usr/bin/env bash
# ============================================================
# argocd_delete_root_app.sh
#
# Gracefully shuts down the ArgoCD root app and all its
# cascaded child applications before deletion.
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
ROOT_APP_NAME="root-app"
ARGOCD_SERVER="localhost:8080"
GRACEFUL_TIMEOUT=300   # seconds to wait for workload pods to terminate
DELETE_TIMEOUT=180     # seconds to wait for root-app deletion to complete
PORT_WAIT_TIMEOUT=60   # seconds to wait for port-forward to be ready
LOGIN_MAX=5            # max argocd login attempts

# ── Helpers ───────────────────────────────────────────────────
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ ERROR: $*" >&2; exit 1; }

namespace_exists() {
  kubectl get namespace "$1" &>/dev/null
}

app_exists() {
  argocd app get "$1" &>/dev/null 2>&1
}

app_sync_policy() {
  argocd app get "$1" --output json 2>/dev/null \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
policy = d.get('spec', {}).get('syncPolicy', {})
print('automated' if 'automated' in policy else 'none')
" 2>/dev/null || echo "unknown"
}

wait_for_app_deleted() {
  local app="$1"
  local timeout="$2"
  local interval=10
  local elapsed=0

  log "Waiting for app '$app' to be fully deleted (timeout: ${timeout}s)..."
  while [[ $elapsed -lt $timeout ]]; do
    if ! app_exists "$app"; then
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

namespace_exists "$ARGOCD_NAMESPACE" \
  || fail "ArgoCD namespace '$ARGOCD_NAMESPACE' does not exist. Nothing to do."

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

# ── Wait for ArgoCD server pod to be Ready ────────────────────
# Port-forwarding against a non-Running pod binds the local port
# but immediately drops the tunnel, causing "connection refused".
log "Waiting for ArgoCD server pod to be Ready..."
kubectl wait pod \
  -n "$ARGOCD_NAMESPACE" \
  -l "app.kubernetes.io/name=argocd-server" \
  --for=condition=Ready \
  --timeout=120s

# ── Port-forward (skip if port already open) ──────────────────
# The port may already be bound if this script is re-run in the
# same shell session or a previous background job is still alive.
PORT_FORWARD_PID=""
if nc -z localhost 8080 2>/dev/null; then
  log "Port 8080 already open — skipping port-forward."
else
  log "Starting port-forward to ArgoCD server..."
  kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" 8080:443 &
  PORT_FORWARD_PID=$!
  # Only kill the port-forward we started; leave pre-existing ones alone
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

# ── Check root app exists ─────────────────────────────────────
if ! app_exists "$ROOT_APP_NAME"; then
  log "⚠️  Root app '$ROOT_APP_NAME' not found — already deleted or never existed. Exiting cleanly."
  exit 0
fi

# ── Discover all child apps ───────────────────────────────────
log "Discovering child applications managed by '$ROOT_APP_NAME'..."
# mapfile avoids subshell scoping — array is visible to the rest of this script
mapfile -t CHILD_APPS < <(argocd app list --output name 2>/dev/null | grep -v "^${ROOT_APP_NAME}$" || true)

if [[ ${#CHILD_APPS[@]} -gt 0 ]]; then
  log "Found ${#CHILD_APPS[@]} child app(s):"
  for app in "${CHILD_APPS[@]}"; do log "  - $app"; done

  # ── Step 1: Disable auto-sync on child apps ───────────────
  log "Disabling auto-sync on child apps to prevent reconciliation during teardown..."
  for app in "${CHILD_APPS[@]}"; do
    if ! app_exists "$app"; then
      log "  Skipping '$app' — no longer exists."
      continue
    fi
    local_policy=$(app_sync_policy "$app")
    if [[ "$local_policy" == "none" ]]; then
      log "  Auto-sync already disabled for '$app' — skipping."
    else
      log "  Disabling auto-sync: $app"
      argocd app set "$app" --sync-policy none 2>/dev/null \
        || log "  ⚠️  Could not disable auto-sync for '$app'."
    fi
  done

  # ── Step 2: Disable auto-sync on root app ─────────────────
  log "Disabling auto-sync on root app '$ROOT_APP_NAME'..."
  root_policy=$(app_sync_policy "$ROOT_APP_NAME")
  if [[ "$root_policy" == "none" ]]; then
    log "  Auto-sync already disabled on root app — skipping."
  else
    argocd app set "$ROOT_APP_NAME" --sync-policy none 2>/dev/null || true
  fi

  # ── Step 3: Scale down workloads in child namespaces ──────
  log "Scaling down workloads in child app namespaces..."
  for app in "${CHILD_APPS[@]}"; do
    if ! app_exists "$app"; then
      log "  Skipping '$app' — no longer exists."
      continue
    fi

    NAMESPACE=$(argocd app get "$app" --output json 2>/dev/null \
      | python3 -c "import sys,json; print(json.load(sys.stdin)['spec']['destination']['namespace'])" \
      2>/dev/null || echo "")

    if [[ -z "$NAMESPACE" ]]; then
      log "  Could not determine namespace for '$app' — skipping scale-down."
      continue
    fi

    # Only scale deployments that are not already at 0
    DEPLOY_NONZERO=$(kubectl get deployment -n "$NAMESPACE" -o json 2>/dev/null \
      | python3 -c "
import sys,json
items=[d for d in json.load(sys.stdin)['items'] if d.get('spec',{}).get('replicas',0)>0]
print(len(items))" 2>/dev/null || echo "0")

    if [[ "$DEPLOY_NONZERO" -gt 0 ]]; then
      log "  Scaling down $DEPLOY_NONZERO deployment(s) in namespace: $NAMESPACE"
      kubectl scale deployment --all -n "$NAMESPACE" --replicas=0 2>/dev/null || true
    else
      log "  All deployments in '$NAMESPACE' already at 0 replicas — skipping."
    fi

    # Only scale statefulsets that are not already at 0
    STS_NONZERO=$(kubectl get statefulset -n "$NAMESPACE" -o json 2>/dev/null \
      | python3 -c "
import sys,json
items=[d for d in json.load(sys.stdin)['items'] if d.get('spec',{}).get('replicas',0)>0]
print(len(items))" 2>/dev/null || echo "0")

    if [[ "$STS_NONZERO" -gt 0 ]]; then
      log "  Scaling down $STS_NONZERO statefulset(s) in namespace: $NAMESPACE"
      kubectl scale statefulset --all -n "$NAMESPACE" --replicas=0 2>/dev/null || true
    else
      log "  All statefulsets in '$NAMESPACE' already at 0 replicas — skipping."
    fi
  done

  # ── Step 4: Wait for pods to terminate ────────────────────
  log "Waiting for workload pods to terminate (timeout: ${GRACEFUL_TIMEOUT}s)..."
  GRACE_ELAPSED=0
  GRACE_INTERVAL=15
  while [[ $GRACE_ELAPSED -lt $GRACEFUL_TIMEOUT ]]; do
    PENDING_PODS=0
    for app in "${CHILD_APPS[@]}"; do
      app_exists "$app" || continue
      NAMESPACE=$(argocd app get "$app" --output json 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['spec']['destination']['namespace'])" \
        2>/dev/null || echo "")
      [[ -z "$NAMESPACE" ]] && continue
      COUNT=$(kubectl get pods -n "$NAMESPACE" \
        --field-selector=status.phase=Running \
        --no-headers 2>/dev/null | wc -l || echo 0)
      PENDING_PODS=$((PENDING_PODS + COUNT))
    done

    if [[ "$PENDING_PODS" -eq 0 ]]; then
      log "✅ All workload pods terminated."
      break
    fi
    log "  → $PENDING_PODS running pod(s) remaining. Waiting ${GRACE_INTERVAL}s..."
    sleep "$GRACE_INTERVAL"
    GRACE_ELAPSED=$((GRACE_ELAPSED + GRACE_INTERVAL))
  done

else
  log "No child apps found."
  log "Disabling auto-sync on root app '$ROOT_APP_NAME'..."
  root_policy=$(app_sync_policy "$ROOT_APP_NAME")
  if [[ "$root_policy" == "none" ]]; then
    log "  Auto-sync already disabled — skipping."
  else
    argocd app set "$ROOT_APP_NAME" --sync-policy none 2>/dev/null || true
  fi
fi

# ── Step 5: Delete root app with cascade ─────────────────────
# Re-check: a previous run may have already completed this step
if ! app_exists "$ROOT_APP_NAME"; then
  log "Root app '$ROOT_APP_NAME' no longer exists — skipping delete."
else
  log "Deleting root app '$ROOT_APP_NAME' with cascade..."
  argocd app delete "$ROOT_APP_NAME" --cascade --yes
  wait_for_app_deleted "$ROOT_APP_NAME" "$DELETE_TIMEOUT"
fi

# ── Step 6: Force-delete any surviving child apps ─────────────
mapfile -t REMAINING < <(argocd app list --output name 2>/dev/null | grep -v "^${ROOT_APP_NAME}$" || true)

if [[ ${#REMAINING[@]} -gt 0 ]]; then
  log "⚠️  ${#REMAINING[@]} app(s) still present after cascade delete. Force-deleting..."
  for app in "${REMAINING[@]}"; do
    log "  Force-deleting: $app"
    argocd app delete "$app" --cascade --yes 2>/dev/null \
      || log "  ⚠️  Could not delete '$app' — may need manual cleanup."
  done
else
  log "✅ No surviving child apps found."
fi

log "✅ Root app and all child applications deleted successfully."
