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
kubectl port-forward -n "$ARGOCD_HELM_NAMESPACE" svc/argocd-server 30443:443 \
  >/dev/null 2>&1 &
PORT_FORWARD_PID=$!
trap "kill $PORT_FORWARD_PID 2>/dev/null || true" EXIT

# Wait for port forward to be ready
sleep 2

# Login to ArgoCD via port forward
success "Logging in to ArgoCD..."
argocd login --insecure \
  --username admin \
  --password "$ARGOCD_INITIAL_PASS" \
  --grpc-web "localhost:${ARGOCD_NODE_PORT_HTTPS}" \
  || fail "Failed to login to ArgoCD"

# Update password
success "Updating admin password..."
argocd account update-password \
  --insecure \
  --current-password "$ARGOCD_INITIAL_PASS" \
  --new-password "$ARGOCD_ADMIN_PASSWORD" \
  || fail "Failed to update ArgoCD password"

success "ArgoCD password updated"

# Patch ArgoCD ConfigMap with external URL
success "Patching ArgoCD ConfigMap with external URL..."
ARGOCD_URL="https://${NLB_PUBLIC_IP}"

kubectl patch configmap/argocd-cm \
  -n "$ARGOCD_HELM_NAMESPACE" \
  --type=json \
  -p="[{\"op\": \"replace\", \"path\": \"/data/url\", \"value\":\"${ARGOCD_URL}\"}]" \
  || warn "Failed to patch ArgoCD URL (may already be set)"

success "ArgoCD configured at: $ARGOCD_URL:${ARGOCD_NODE_PORT_HTTPS}"
