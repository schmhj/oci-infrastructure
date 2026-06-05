#!/bin/bash

PROFILE=$1

if [ -z "$PROFILE" ]; then
  echo "Usage: $0 <tenant-name>     # tenant-a or tenant-b"
  exit 1
fi

if [ "$PROFILE" = "tenant-a" ]; then
  export OCI_CLI_PROFILE=TENANT_A
  export KUBECONFIG=~/.kube/tenant-a-config

elif [ "$PROFILE" = "tenant-b" ]; then
  export OCI_CLI_PROFILE=TENANT_B
  export KUBECONFIG=~/.kube/tenant-b-config
else
  echo "Error: Unknown profile '$PROFILE'. Expected 'tenant-a' or 'tenant-b'."
  exit 1
fi
