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

# Check if password was already updated (try new password first)
success "Checking if admin password needs updating..."
LOGIN_CHECK_LOG=$(mktemp)
trap 'rm -f "$LOGIN_CHECK_LOG" 2>/dev/null || true' EXIT

MAX_RETRIES=10
RETRY_DELAY=5
REACHABLE=false
ALREADY_CONFIGURED=false

for i in $(seq 1 "$MAX_RETRIES"); do
  if argocd login "${NLB_PUBLIC_IP}" \
    --insecure \
    --username admin \
    --password "$ARGOCD_ADMIN_PASSWORD" \
    --grpc-web \
    >"$LOGIN_CHECK_LOG" 2>&1; then
    success "ArgoCD admin password already configured"
    REACHABLE=true
    ALREADY_CONFIGURED=true
    break
  else
    # Check if the failure was due to connection error rather than authentication
    if grep -qE "connection refused|dial tcp|context deadline exceeded|no such host" "$LOGIN_CHECK_LOG"; then
      echo "  Attempt $i/$MAX_RETRIES - ArgoCD server not reachable at ${NLB_PUBLIC_IP}. Retrying in ${RETRY_DELAY}s..."
      sleep "$RETRY_DELAY"
    else
      # Server is reachable, but authentication failed (expected if password needs update)
      REACHABLE=true
      ALREADY_CONFIGURED=false
      break
    fi
  fi
done

if [ "$REACHABLE" = "false" ]; then
  echo "❌ Network error during ArgoCD login check:"
  cat "$LOGIN_CHECK_LOG"
  fail "ArgoCD server at ${NLB_PUBLIC_IP} remained unreachable after $((MAX_RETRIES * RETRY_DELAY)) seconds"
fi

if [ "$ALREADY_CONFIGURED" = "false" ]; then
  # Login with initial password and update
  success "Logging in with initial password to ArgoCD..."
  argocd login "${NLB_PUBLIC_IP}" \
    --insecure \
    --username admin \
    --password "$ARGOCD_INITIAL_PASS" \
    --grpc-web \
    || {
      echo "❌ Login failed. Initial login logs:"
      cat "$LOGIN_CHECK_LOG"
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

success "ArgoCD configured at: $ARGOCD_URL"
