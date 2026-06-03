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
LOGIN_CHECK_LOG=$(mktemp)
kubectl port-forward -n "$ARGOCD_HELM_NAMESPACE" svc/argocd-server ${ARGOCD_NODE_PORT_HTTPS}:443 \
  --address 127.0.0.1 >"$PF_LOG" 2>&1 &
PORT_FORWARD_PID=$!
trap 'kill $PORT_FORWARD_PID 2>/dev/null || true; rm -f "$PF_LOG" "$LOGIN_CHECK_LOG" 2>/dev/null || true' EXIT

# Wait for port forward to be ready
sleep 2
if ! kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
  echo "❌ kubectl port-forward failed to start or died immediately. Log output:"
  cat "$PF_LOG"
  fail "Port forwarding setup failed"
fi

# Check if password was already updated (try new password first)
success "Checking if admin password needs updating..."
if argocd login "127.0.0.1:${ARGOCD_NODE_PORT_HTTPS}" \
  --insecure \
  --username admin \
  --password "$ARGOCD_ADMIN_PASSWORD" \
  --grpc-web \
  >"$LOGIN_CHECK_LOG" 2>&1; then
  success "ArgoCD admin password already configured"
else
  # Check if the failure was due to connection error rather than authentication
  if grep -qE "connection refused|dial tcp|context deadline exceeded|no such host" "$LOGIN_CHECK_LOG"; then
    echo "❌ Network error during ArgoCD login check:"
    cat "$LOGIN_CHECK_LOG"
    echo "=== Port Forward Log ==="
    cat "$PF_LOG"
    echo "========================"
    fail "ArgoCD server is unreachable"
  fi

  # Login with initial password and update
  success "Logging in with initial password to ArgoCD..."
  argocd login "127.0.0.1:${ARGOCD_NODE_PORT_HTTPS}" \
    --insecure \
    --username admin \
    --password "$ARGOCD_INITIAL_PASS" \
    --grpc-web \
    || {
      echo "❌ Login failed. Port-forward logs:"
      cat "$PF_LOG"
      fail "Failed to login to ArgoCD"
    }

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

success "ArgoCD configured at: $ARGOCD_URL:${ARGOCD_NODE_PORT_HTTPS}"
