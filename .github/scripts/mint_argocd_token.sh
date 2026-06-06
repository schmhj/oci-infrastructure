#!/usr/bin/env bash

# Mint a long-lived bearer token for the argocd-cluster-admin ServiceAccount.
# Used by tenant-a's ArgoCD to authenticate to tenant-b's API server.
#
# Required env:
#   SA_NAMESPACE  - Namespace of the SA (default: kube-system)
#   SA_NAME       - ServiceAccount name (default: argocd-cluster-admin)
#   TOKEN_SECRET  - Secret name to create (default: argocd-cluster-admin-token)
#
# Prints the bearer token to stdout.
#
# Note: Kubernetes 1.24+ populates ServiceAccount-token Secrets with a
# default TTL (typically 1 hour, controlled by kube-apiserver flags). On
# OKE this means tokens must be rotated frequently. A follow-up CronJob
# will handle rotation; this script is for initial bootstrap only.

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

require_cmd "kubectl"

SA_NAMESPACE="${SA_NAMESPACE:-kube-system}"
SA_NAME="${SA_NAME:-argocd-cluster-admin}"
TOKEN_SECRET="${TOKEN_SECRET:-argocd-cluster-admin-token}"

# Verify the SA exists
if ! kubectl get serviceaccount "$SA_NAME" -n "$SA_NAMESPACE" >/dev/null 2>&1; then
  fail "ServiceAccount ${SA_NAMESPACE}/${SA_NAME} not found; apply the bootstrap config first"
fi

# Create or refresh the long-lived token Secret
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${TOKEN_SECRET}
  namespace: ${SA_NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: ${SA_NAME}
type: kubernetes.io/service-account-token
EOF

# Wait briefly for the controller to populate .data.token
TOKEN=""
for _ in $(seq 1 15); do
  TOKEN=$(kubectl get secret "$TOKEN_SECRET" -n "$SA_NAMESPACE" \
    -o jsonpath='{.data.token}' 2>/dev/null || true)
  if [[ -n "$TOKEN" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$TOKEN" ]]; then
  fail "Token not populated in secret ${SA_NAMESPACE}/${TOKEN_SECRET} after 15s"
fi

echo "$TOKEN" | base64 --decode
