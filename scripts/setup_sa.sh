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
 
  # Prefer TokenRequest if available (immediate), otherwise read populated secret
  if kubectl create token --help >/dev/null 2>&1; then
    K8S_TOKEN=$(kubectl create token tfc-deployer -n kube-system)
  else
    # Wait for the secret to be populated and decode it
    TOKEN_B64=""
    for i in $(seq 1 30); do
      TOKEN_B64=$(kubectl get secret tfc-deployer-token -n kube-system -o jsonpath='{.data.token}' 2>/dev/null || true)
      if [ -n "$TOKEN_B64" ]; then
        break
      fi
      sleep 1
    done
    if [ -z "$TOKEN_B64" ]; then
      echo "ERROR: token not populated after wait" >&2
      exit 1
    fi
    K8S_TOKEN=$(echo "$TOKEN_B64" | base64 --decode)
  fi

  # Export for in-process use
  export K8S_TOKEN

  # If running inside GitHub Actions, write the step output so the workflow can capture it
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    # GITHUB_OUTPUT expects 'name=value' lines
    printf 'k8s_token=%s\n' "$K8S_TOKEN" >> "$GITHUB_OUTPUT"
  else
    # Otherwise print the token to stdout for debugging
    printf '%s\n' "$K8S_TOKEN"
  fi
