#!/bin/bash

PROFILE=$1

if [ -z "$PROFILE" ]; then
  echo "Usage: $0 <OCI_CLI_PROFILE>"
  exit 1
fi

if [ "$PROFILE"=="ashburn" ]; then
  export OCI_CLI_PROFILE=ASHBURN
  export KUBECONFIG=~/.kube/us-ashburn-config

elif [ "$PROFILE"=="chicago" ]; then
  export OCI_CLI_PROFILE=CHICAGO
  export KUBECONFIG=~/.kube/us-chicago-config
else
  echo "Error: Unknown profile '$PROFILE'. Expected 'ashburn' or 'chicago'."
  exit 1
fi