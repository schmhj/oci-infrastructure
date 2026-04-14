#!/usr/bin/env bash
# ============================================================
# argocd_delete_root_app.sh
#
# Gracefully shuts down the ArgoCD root app and all its
# cascaded child applications before deletion.
#
# Two-path design:
#   PRIMARY   — argocd CLI via port-forward (graceful cascade delete)
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
ROOT_APP_NAME="root-app"
ARGOCD_SERVER="localhost:8080"
GRACEFUL_TIMEOUT=300   # seconds to wait for workload pods to terminate
DELETE_TIMEOUT=180     # seconds to wait for root-app deletion to complete
PORT_WAIT_TIMEOUT=30   # seconds to wait for port-forward to be ready
LOGIN_MAX=5            # max argocd login attempts

# ── Helpers ───────────────────────────────────────────────────
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ ERROR: $*" >&2; exit 1; }

namespace_exists() {
  kubectl get namespace "$1" &>/dev/null
}

# Returns 0 if the argocd-server pod is Running and Ready
argocd_server_ready() {
  local ready
  ready=$(kubectl get pods \
    -n "$ARGOCD_NAMESPACE" \
    -l "app.kubernetes.io/name=argocd-server" \
    --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | wc -l)
  [[ "$ready" -gt 0 ]]
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

# Removes finalizers from all Application CRs in a namespace and
# deletes them directly via kubectl — used as fallback when the
# ArgoCD API server is unreachable.
kubectl_delete_applications() {
  local namespace="$1"

  log "  Checking for Application CRs in namespace '$namespace'..."
  mapfile -t APPS < <(kubectl get applications.argoproj.io \
    -n "$namespace" \
    --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)

  if [[ ${#APPS[@]} -eq 0 ]]; then
    log "  No Application CRs found in '$namespace'."
    return 0
  fi

  log "  Found ${#APPS[@]} Application CR(s) in '$namespace'. Removing finalizers and deleting..."
  for app in "${APPS[@]}"; do
    [[ -z "$app" ]] && continue

    FINALIZERS=$(kubectl get application.argoproj.io "$app" \
      -n "$namespace" \
      -o jsonpath='{.metadata.finalizers}' 2>/dev/null || echo "")
    if [[ -n "$FINALIZERS" && "$FINALIZERS" != "[]" ]]; then
      log "    Removing finalizers from Application/$app"
      kubectl patch application.argoproj.io "$app" \
        -n "$namespace" \
        --type=merge \
        -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    fi

    log "    Deleting Application/$app"
    kubectl delete application.argoproj.io "$app" \
      -n "$namespace" \
      --timeout=60s 2>/dev/null || true
  done
}

# Scales down all deployments and statefulsets in a namespace
# that still have replicas > 0
scale_down_namespace() {
  local namespace="$1"

  DEPLOY_NONZERO=$(kubectl get deployment -n "$namespace" -o json 2>/dev/null \
    | python3 -c "
import sys,json
items=[d for d in json.load(sys.stdin)['items'] if d.get('spec',{}).get('replicas',0)>0]
print(len(items))" 2>/dev/null || echo "0")

  if [[ "$DEPLOY_NONZERO" -gt 0 ]]; then
    log "  Scaling down $DEPLOY_NONZERO deployment(s) in namespace: $namespace"
    kubectl scale deployment --all -n "$namespace" --replicas=0 2>/dev/null || true
  else
    log "  All deployments in '$namespace' already at 0 replicas — skipping."
  fi

  STS_NONZERO=$(kubectl get statefulset -n "$namespace" -o json 2>/dev/null \
    | python3 -c "
import sys,json
items=[d for d in json.load(sys.stdin)['items'] if d.get('spec',{}).get('replicas',0)>0]
print(len(items))" 2>/dev/null || echo "0")

  if [[ "$STS_NONZERO" -gt 0 ]]; then
    log "  Scaling down $STS_NONZERO statefulset(s) in namespace: $namespace"
    kubectl scale statefulset --all -n "$namespace" --replicas=0 2>/dev/null || true
  else
    log "  All statefulsets in '$namespace' already at 0 replicas — skipping."
  fi
}

# ── Pre-flight ────────────────────────────────────────────────
[[ -z "${ARGOCD_ADMIN_PASSWORD:-}" ]] && fail "ARGOCD_ADMIN_PASSWORD is not set."

# If the namespace is already gone, all CRs are gone too — nothing to do
if ! namespace_exists "$ARGOCD_NAMESPACE"; then
  log "ArgoCD namespace '$ARGOCD_NAMESPACE' does not exist — already cleaned up. Exiting cleanly."
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
# We use the argocd CLI path only when the server pod is genuinely
# Running. We check this BEFORE attempting port-forward to avoid
# the failure mode where:
#   - rollout status reports success (deployment spec is satisfied)
#   - but the pod is CrashLoopBackOff / OOMKilled / Terminating
#   - causing port-forward to bind but immediately drop the tunnel
#
ARGOCD_CLI_AVAILABLE=false
PORT_FORWARD_PID=""

if argocd_server_ready; then
  log "ArgoCD server pod is Running. Attempting CLI path..."

  # ── Port-forward (skip if port already open) ────────────────
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
      # Check the port-forward process is still alive
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

  # ── Login ────────────────────────────────────────────────────
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
if [[ "$ARGOCD_CLI_AVAILABLE" == "true" ]]; then
  log "Using ArgoCD CLI path."

  # Check root app exists
  if ! app_exists "$ROOT_APP_NAME"; then
    log "⚠️  Root app '$ROOT_APP_NAME' not found — already deleted or never existed."
    # Still run fallback to clean up any orphaned CRs
    ARGOCD_CLI_AVAILABLE=false
  fi
fi

if [[ "$ARGOCD_CLI_AVAILABLE" == "true" ]]; then
  # Discover child apps
  log "Discovering child applications managed by '$ROOT_APP_NAME'..."
  mapfile -t CHILD_APPS < <(argocd app list --output name 2>/dev/null | grep -v "^${ROOT_APP_NAME}$" || true)

  if [[ ${#CHILD_APPS[@]} -gt 0 ]]; then
    log "Found ${#CHILD_APPS[@]} child app(s):"
    for app in "${CHILD_APPS[@]}"; do log "  - $app"; done

    # Disable auto-sync on all child apps
    log "Disabling auto-sync on child apps..."
    for app in "${CHILD_APPS[@]}"; do
      app_exists "$app" || { log "  Skipping '$app' — no longer exists."; continue; }
      local_policy=$(app_sync_policy "$app")
      if [[ "$local_policy" == "none" ]]; then
        log "  Auto-sync already disabled for '$app' — skipping."
      else
        log "  Disabling auto-sync: $app"
        argocd app set "$app" --sync-policy none 2>/dev/null \
          || warn "Could not disable auto-sync for '$app'."
      fi
    done

    # Disable auto-sync on root app
    log "Disabling auto-sync on root app '$ROOT_APP_NAME'..."
    root_policy=$(app_sync_policy "$ROOT_APP_NAME")
    if [[ "$root_policy" == "none" ]]; then
      log "  Auto-sync already disabled on root app — skipping."
    else
      argocd app set "$ROOT_APP_NAME" --sync-policy none 2>/dev/null || true
    fi

    # Scale down workloads in child namespaces
    log "Scaling down workloads in child app namespaces..."
    for app in "${CHILD_APPS[@]}"; do
      app_exists "$app" || { log "  Skipping '$app' — no longer exists."; continue; }
      NAMESPACE=$(argocd app get "$app" --output json 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['spec']['destination']['namespace'])" \
        2>/dev/null || echo "")
      if [[ -z "$NAMESPACE" ]]; then
        warn "Could not determine namespace for '$app' — skipping scale-down."
        continue
      fi
      scale_down_namespace "$NAMESPACE"
    done

    # Wait for workload pods to terminate
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

  # Delete root app with cascade
  if ! app_exists "$ROOT_APP_NAME"; then
    log "Root app '$ROOT_APP_NAME' no longer exists — skipping CLI delete."
  else
    log "Deleting root app '$ROOT_APP_NAME' with cascade..."
    argocd app delete "$ROOT_APP_NAME" --cascade --yes
    wait_for_app_deleted "$ROOT_APP_NAME" "$DELETE_TIMEOUT"
  fi

  # Force-delete any surviving child apps
  mapfile -t REMAINING < <(argocd app list --output name 2>/dev/null | grep -v "^${ROOT_APP_NAME}$" || true)
  if [[ ${#REMAINING[@]} -gt 0 ]]; then
    warn "${#REMAINING[@]} app(s) still present after cascade delete. Force-deleting..."
    for app in "${REMAINING[@]}"; do
      log "  Force-deleting: $app"
      argocd app delete "$app" --cascade --yes 2>/dev/null \
        || warn "Could not delete '$app' via CLI — will attempt kubectl cleanup below."
    done
  else
    log "✅ No surviving child apps found."
  fi
fi

# ══════════════════════════════════════════════════════════════
# FALLBACK PATH — direct kubectl CR deletion
# Runs when: CLI unavailable, login failed, or root app not found.
# Also runs after CLI path as a safety net to catch any orphaned
# Application CRs that survived cascade delete or were in
# namespaces other than argocd (app-in-any-namespace).
# ══════════════════════════════════════════════════════════════
log "Running kubectl CR cleanup pass (catches orphaned or app-in-any-namespace CRs)..."

# Check if the Application CRD still exists before trying to list CRs
if ! kubectl get crd applications.argoproj.io &>/dev/null; then
  log "Application CRD not found — no CRs to clean up."
else
  # Collect all namespaces that have Application CRs
  mapfile -t APP_NAMESPACES < <(kubectl get applications.argoproj.io \
    --all-namespaces \
    --no-headers -o custom-columns=":metadata.namespace" 2>/dev/null \
    | sort -u || true)

  if [[ ${#APP_NAMESPACES[@]} -eq 0 ]]; then
    log "No Application CRs found in any namespace — nothing to clean up via kubectl."
  else
    log "Found Application CRs in namespace(s): ${APP_NAMESPACES[*]}"
    for ns in "${APP_NAMESPACES[@]}"; do
      [[ -z "$ns" ]] && continue
      kubectl_delete_applications "$ns"
    done
  fi
fi

log "✅ Root app and all child applications deleted successfully."
