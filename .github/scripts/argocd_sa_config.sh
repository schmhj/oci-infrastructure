#!/usr/bin/env bash

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

require_cmd "kubectl"

# Determine path to ArgoCD config file
if [ -n "${GITHUB_WORKSPACE:-}" ]; then
  ARGOCD_CONFIG="${GITHUB_WORKSPACE}/.github/argocd/config-update.yaml"
else
  ARGOCD_CONFIG="$SCRIPT_DIR/argocd/config-update.yaml"
fi

if [ ! -f "$ARGOCD_CONFIG" ]; then
  fail "ArgoCD configuration file not found: $ARGOCD_CONFIG"
fi

success "Applying ArgoCD configuration from: $ARGOCD_CONFIG"
kubectl apply -f "$ARGOCD_CONFIG" || fail "Failed to apply ArgoCD configuration"

success "ArgoCD configuration applied successfully"
