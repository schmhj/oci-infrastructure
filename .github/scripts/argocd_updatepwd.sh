#!/usr/bin/env bash

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

# Validate required environment variables
require_env "NLB_PUBLIC_IP"
require_env "ARGOCD_ADMIN_PASSWORD"

require_cmd "kubectl"
require_cmd "argocd"

success "Updating ArgoCD admin password..."

# Get initial admin password
ARGOCD_INITIAL_PASS=$(kubectl get secret argocd-initial-admin-secret \
  -n "$ARGOCD_HELM_NAMESPACE" \
  -o jsonpath='{.data.password}' \
  | base64 -d) \
  || fail "Failed to retrieve initial ArgoCD password"

# Setup port forwarding in background for argocd CLI access
success "Setting up port forwarding to ArgoCD server..."
PF_LOG=$(mktemp)
kubectl port-forward -n "$ARGOCD_HELM_NAMESPACE" svc/argocd-server ${ARGOCD_NODE_PORT_HTTPS}:443 \
  --address 127.0.0.1 >"$PF_LOG" 2>&1 &
PORT_FORWARD_PID=$!

# Wait for port forward to be ready
sleep 2
if ! kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
  echo "❌ kubectl port-forward failed to start or died immediately. Log output:"
  cat "$PF_LOG"
  fail "Port forwarding setup failed"
fi

HOST="127.0.0.1:${ARGOCD_NODE_PORT_HTTPS}"
LOGIN_LOG=$(mktemp)
trap 'kill $PORT_FORWARD_PID 2>/dev/null || true; rm -f "$PF_LOG" "$LOGIN_LOG" 2>/dev/null || true' EXIT

try_login() {
  local host="$1"
  local user="$2"
  local pass="$3"
  local mode="$4"
  local log_file="$5"

  if [ "$mode" = "plaintext" ]; then
    argocd login "$host" \
      --plaintext \
      --username "$user" \
      --password "$pass" \
      --grpc-web \
      >"$log_file" 2>&1
  else
    argocd login "$host" \
      --insecure \
      --username "$user" \
      --password "$pass" \
      --grpc-web \
      >"$log_file" 2>&1
  fi
}

# 1. Determine the protocol mode (TLS vs Plaintext) and check if already configured
MODE=""
ALREADY_CONFIGURED=false

success "Detecting ArgoCD server protocol and configuration state..."

# Try TLS first
if try_login "$HOST" "admin" "$ARGOCD_ADMIN_PASSWORD" "tls" "$LOGIN_LOG"; then
  success "ArgoCD admin password already configured (via TLS)"
  ALREADY_CONFIGURED=true
  MODE="tls"
else
  # If it failed, let's see if it's a bad credentials error or a connection/reset/EOF error
  if grep -qE "connection refused|dial tcp|context deadline exceeded|no such host|connection reset by peer|EOF" "$LOGIN_LOG"; then
    # TLS failed with a connection/reset/EOF error, try Plaintext
    if try_login "$HOST" "admin" "$ARGOCD_ADMIN_PASSWORD" "plaintext" "$LOGIN_LOG"; then
      success "ArgoCD admin password already configured (via Plaintext)"
      ALREADY_CONFIGURED=true
      MODE="plaintext"
    else
      # If plaintext login also failed, check if it's a bad credentials error or network error
      if grep -qE "connection refused|dial tcp|context deadline exceeded|no such host|connection reset by peer|EOF" "$LOGIN_LOG"; then
        echo "❌ Network error: ArgoCD server is unreachable via TLS and Plaintext:"
        cat "$LOGIN_LOG"
        echo "=== Port Forward Log ==="
        cat "$PF_LOG"
        echo "========================"
        fail "ArgoCD server is unreachable"
      else
        # Plaintext connected, but bad credentials (meaning it needs password update)
        MODE="plaintext"
      fi
    fi
  else
    # TLS connected, but bad credentials (meaning it needs password update)
    MODE="tls"
  fi
fi

if [ "$ALREADY_CONFIGURED" = "false" ]; then
  success "Server detected running in $MODE mode. Updating password..."

  # Login with initial password
  success "Logging in with initial password to ArgoCD..."
  if ! try_login "$HOST" "admin" "$ARGOCD_INITIAL_PASS" "$MODE" "$LOGIN_LOG"; then
    echo "❌ Failed to login with initial password. Logs:"
    cat "$LOGIN_LOG"
    echo "=== Port Forward Log ==="
    cat "$PF_LOG"
    echo "========================"
    fail "Initial login failed"
  fi

  # Update password
  success "Updating admin password..."
  argocd account update-password \
    --insecure \
    --current-password "$ARGOCD_INITIAL_PASS" \
    --new-password "$ARGOCD_ADMIN_PASSWORD" \
    || fail "Failed to update ArgoCD password"

  success "ArgoCD password updated"
fi

# Patch ArgoCD ConfigMap with external URL
success "Patching ArgoCD ConfigMap with external URL..."
ARGOCD_URL="https://${NLB_PUBLIC_IP}"

kubectl patch configmap/argocd-cm \
  -n "$ARGOCD_HELM_NAMESPACE" \
  --type=json \
  -p="[{\"op\": \"replace\", \"path\": \"/data/url\", \"value\":\"${ARGOCD_URL}\"}]" \
  || warn "Failed to patch ArgoCD URL (may already be set)"

success "ArgoCD configured at: $ARGOCD_URL"
