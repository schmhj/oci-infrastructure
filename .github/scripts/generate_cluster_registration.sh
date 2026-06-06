#!/usr/bin/env bash

# Generate a cluster-registration Secret manifest for tenant-a's ArgoCD.
# The manifest is saved as a workflow artifact and manually committed to
# the cluster-config repo as a SealedSecret (rotation is not yet
# automated in v1).
#
# Required env:
#   TENANT_NAME  - "tenant-a" or "tenant-b" (used in resource names)
#   OUTPUT_DIR   - Directory to write the manifest
#
# Output files:
#   $OUTPUT_DIR/cluster-secret.yaml  - Secret manifest (apply in tenant-a's argocd ns)

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

require_cmd "kubectl"
require_env "TENANT_NAME"
require_env "OUTPUT_DIR"

# Mint the bearer token
TOKEN=$(./.github/scripts/mint_argocd_token.sh)

# Cluster CA cert (from the same Secret the token came from)
CA_DATA=$(kubectl get secret argocd-cluster-admin-token -n kube-system \
  -o jsonpath='{.data.ca\.crt}')
if [[ -z "$CA_DATA" ]]; then
  fail "Failed to read ca.crt from argocd-cluster-admin-token secret"
fi

# Cluster endpoint (server URL from current kubeconfig)
SERVER=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')
if [[ -z "$SERVER" ]]; then
  fail "Failed to determine cluster server URL from kubeconfig"
fi

mkdir -p "$OUTPUT_DIR"

# Write Secret manifest. Use single-quoted heredoc with $TOKEN/$CA_DATA/$SERVER
# expanded; the bearer token contains no shell metacharacters when base64-decoded
# from a kubernetes.io/service-account-token Secret.
cat > "$OUTPUT_DIR/cluster-secret.yaml" <<EOF
# Cluster registration for tenant-a's ArgoCD.
# Apply this manifest in tenant-a's argocd namespace after sealing with kubeseal.
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
apiVersion: v1
kind: Secret
metadata:
  name: cluster-${TENANT_NAME}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: ${TENANT_NAME}
  server: ${SERVER}
  config: |
    {
      "bearerToken": "${TOKEN}",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "${CA_DATA}"
      }
    }
EOF

success "Cluster registration manifest written to ${OUTPUT_DIR}/cluster-secret.yaml"
echo ""
echo "Server: ${SERVER}"
echo "CA data length: ${#CA_DATA}"
echo "Token length: ${#TOKEN}"
