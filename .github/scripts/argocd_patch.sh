#!/usr/bin/env bash

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

require_cmd "kubectl"

# Determine path to ArgoCD config file
if [ -n "${GITHUB_WORKSPACE:-}" ]; then
  ARGOCD_SERVER_PATCH="${GITHUB_WORKSPACE}/.github/argocd/argocd-server-service-patch.yaml"
else
  ARGOCD_SERVER_PATCH="$SCRIPT_DIR/argocd/argocd-server-service-patch.yaml"
fi

if [ ! -f "$ARGOCD_SERVER_PATCH" ]; then
  fail "ArgoCD server patch file not found: $ARGOCD_SERVER_PATCH"
fi

success "Applying ArgoCD server patch from: $ARGOCD_SERVER_PATCH"
kubectl apply -f "$ARGOCD_SERVER_PATCH" || fail "Failed to apply ArgoCD server patch"
success "ArgoCD server patch applied successfully"

success "Patching ArgoCD configmap and deployment..."
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"kustomize.buildOptions":"--enable-helm", "application.sync.impersonation.enabled":"true"}}' || fail "Failed to patch ArgoCD configmap"
kubectl patch deployment argocd-server -n argocd --type json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--insecure"}]' || fail "Failed to patch ArgoCD deployment"
success "ArgoCD configmap and deployment patched successfully"

success "Restarting ArgoCD server deployment to apply changes..."
kubectl rollout restart deployment argocd-server -n argocd || fail "Failed to restart ArgoCD server deployment"

success "Waiting for ArgoCD server deployment to become available..."
kubectl rollout status deployment argocd-server -n argocd --timeout=5m || fail "ArgoCD server deployment failed to become ready"

success "ArgoCD server deployment restarted and is now available"