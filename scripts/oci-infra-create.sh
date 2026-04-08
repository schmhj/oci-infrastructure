# !/bin/bash

set -e  # exit on any error

oci ce cluster create-kubeconfig \
--cluster-id ocid1.cluster.oc1.iad.aaaaaaaahf7oa65zcbnnqjfggf7wpiijrduwiimigegsinbdvcfkznpqe6da \
--file ~/.kube/config \
--region us-ashburn-1 \
--token-version 2.0.0 \
--kube-endpoint PUBLIC_ENDPOINT

export KUBECONFIG=~/.kube/config

# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d