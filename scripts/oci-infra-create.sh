#!/bin/bash

set -e  # exit on any error

PROFILE=$1

if [ -z "$PROFILE" ]; then
  echo "Usage: $0 <tenant-name>     # tenant-a or tenant-b"
  exit 1
fi

# Cluster OCIDs are placeholders; replace with the real ones after first apply.
declare -A CLUSTER_OCIDS=(
  ["tenant-a"]="ocid1.cluster.oc1.iad.<tenant-a-ocid>"
  ["tenant-b"]="ocid1.cluster.oc1.iad.<tenant-b-ocid>"
)

if [ -z "${CLUSTER_OCIDS[$PROFILE]:-}" ]; then
  echo "Error: Unknown profile '$PROFILE'. Expected 'tenant-a' or 'tenant-b'."
  exit 1
fi

export OCI_CLI_PROFILE=$(echo "$PROFILE" | tr 'a-z-' 'A-Z_')
oci ce cluster create-kubeconfig \
  --cluster-id "${CLUSTER_OCIDS[$PROFILE]}" \
  --file ~/.kube/${PROFILE}-config \
  --region us-ashburn-1 \
  --token-version 2.0.0 \
  --kube-endpoint PUBLIC_ENDPOINT

export KUBECONFIG=~/.kube/${PROFILE}-config

# Get initial ArgoCD password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
