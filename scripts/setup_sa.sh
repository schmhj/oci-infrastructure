#!/bin/bash

set -e  # exit on any error

export KUBECONFIG=$HOME/.kube/config

# Check if service account already exists
if kubectl get serviceaccount tfc-deployer -n kube-system &>/dev/null; then
  echo "Service account 'tfc-deployer' already exists in kube-system namespace"
else
  echo "Creating service account 'tfc-deployer'..."
  kubectl create serviceaccount tfc-deployer -n kube-system
fi

# Check if cluster role binding already exists
if kubectl get clusterrolebinding tfc-admin-binding &>/dev/null; then
  echo "Cluster role binding 'tfc-admin-binding' already exists"
else
  echo "Creating cluster role binding 'tfc-admin-binding'..."
  kubectl create clusterrolebinding tfc-admin-binding \
    --clusterrole=cluster-admin \
    --serviceaccount=kube-system:tfc-deployer
fi

# Check if secret already exists
if kubectl get secret tfc-deployer-token -n kube-system &>/dev/null; then
  echo "Secret 'tfc-deployer-token' already exists in kube-system namespace"
else
  echo "Creating secret 'tfc-deployer-token'..."
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: tfc-deployer-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: tfc-deployer
type: kubernetes.io/service-account-token
EOF
fi

echo "Retrieving token..."

export K8S_TOKEN=$(kubectl get secret tfc-deployer-token -n kube-system -o jsonpath='{.data.token}' | base64 --decode)
