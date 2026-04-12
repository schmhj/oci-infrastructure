#!/usr/bin/env bash

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

require_cmd "kubectl"

# Wait for ArgoCD to be ready
success "Waiting for ArgoCD to be ready (timeout: ${ROLLOUT_TIMEOUT})..."
kubectl rollout status -n "$ARGOCD_HELM_NAMESPACE" sts/argocd-application-controller \
  --timeout="$ROLLOUT_TIMEOUT" \
  || fail "ArgoCD application controller failed to become ready"

# Health check loop for API server readiness
success "Performing health checks..."
for i in $(seq 1 "$HEALTH_CHECK_RETRIES"); do
  if kubectl rollout status -n "$ARGOCD_HELM_NAMESPACE" deployment/argocd-server \
    --timeout=5s >/dev/null 2>&1; then
    success "ArgoCD is ready!"
    exit 0
  fi
  if [ "$i" -lt "$HEALTH_CHECK_RETRIES" ]; then
    echo "  Attempt $i/$HEALTH_CHECK_RETRIES - waiting ${HEALTH_CHECK_INTERVAL}s..."
    sleep "$HEALTH_CHECK_INTERVAL"
  fi
done

fail "ArgoCD failed to become ready after $((HEALTH_CHECK_RETRIES * HEALTH_CHECK_INTERVAL)) seconds"
