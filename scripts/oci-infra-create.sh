# !/bin/bash

set -e  # exit on any error

PROFILE=$1

if [ -z "$PROFILE" ]; then
  echo "Usage: $0 <OCI_CLI_PROFILE>"
  exit 1
fi

if [ "$PROFILE"=="ashburn" ]; then
  export OCI_CLI_PROFILE=ASHBURN

  oci ce cluster create-kubeconfig \
  --cluster-id ocid1.cluster.oc1.iad.aaaaaaaacjhwnmzwsjh2iha2cnrpgbbv72x4h3xs3ijnw2h33c2dxiqesnea \
  --file ~/.kube/us-ashburn-config \
  --region us-ashburn-1 \
  --token-version 2.0.0 \
  --kube-endpoint PUBLIC_ENDPOINT
  export KUBECONFIG=~/.kube/us-ashburn-config

elif [ "$PROFILE"=="chicago" ]; then
  export OCI_CLI_PROFILE=CHICAGO

  oci ce cluster create-kubeconfig \
  --cluster-id ocid1.cluster.oc1.us-chicago-1.aaaaaaaa7rdhrnlg64wb7qnm67fjymg2nuvnreed4vrbsmvxdc2kam2n3y3a \
  --file ~/.kube/us-chicago-config \
  --region us-chicago-1 \
  --token-version 2.0.0 \
  --kube-endpoint PUBLIC_ENDPOINT

  export KUBECONFIG=~/.kube/us-chicago-config

else
  echo "Error: Unknown profile '$PROFILE'. Expected 'ashburn' or 'chicago'."
  exit 1
fi

# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d