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

ARGOCD_SERVER="localhost:${ARGOCD_NODE_PORT_HTTPS}"

# Login to ArgoCD
argocd login --insecure \
  --username admin \
  --password "$ARGOCD_INITIAL_PASS" \
  --grpc-web "$ARGOCD_SERVER" \
  || fail "Failed to login to ArgoCD"

# Update password
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
