#!/bin/bash

set -e  # exit on any error

PROFILE=$1

if [ -z "$PROFILE" ]; then
  echo "Usage: $0 <tenant-name>     # tenant-a or tenant-b"
  exit 1
fi

# Cluster OCIDs are placeholders; replace with the real ones after first apply.
# Using case instead of an associative array so this script works on macOS's
# bash 3.2 (which lacks `declare -A`).
case "$PROFILE" in
  tenant-a)
    CLUSTER_OCID="ocid1.cluster.oc1.iad.aaaaaaaa3b7xrtifia2qthawm676o5yrigvo4oerxlwhgmczqck446qkqqfa"
    ;;
  tenant-b)
    CLUSTER_OCID="ocid1.cluster.oc1.iad.aaaaaaaaz4qxywbff74tozv2hhnrstutk3oedznvwfbbabv4xcviotz3ak7q"
    ;;
  *)
    echo "Error: Unknown profile '$PROFILE'. Expected 'tenant-a' or 'tenant-b'."
    exit 1
    ;;
esac

export OCI_CLI_PROFILE=$(echo "$PROFILE" | tr 'a-z-' 'A-Z_')
oci ce cluster create-kubeconfig \
  --cluster-id "$CLUSTER_OCID" \
  --file ~/.kube/${PROFILE}-config \
  --region us-ashburn-1 \
  --token-version 2.0.0 \
  --kube-endpoint PUBLIC_ENDPOINT

export KUBECONFIG=~/.kube/${PROFILE}-config

# Get initial ArgoCD password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
