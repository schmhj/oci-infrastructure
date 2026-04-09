#!/bin/bash

set -e  # exit on any error

# Redirect all standard logging to stderr so it doesn't pollute the token output
log() {
  echo "$@" >&2
}

export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}

# Check if service account already exists
if kubectl get serviceaccount tfc-deployer -n kube-system &>/dev/null; then
  log "Service account 'tfc-deployer' already exists in kube-system namespace"
else
  log "Creating service account 'tfc-deployer'..."
  kubectl create serviceaccount tfc-deployer -n kube-system
fi

# Check if cluster role binding already exists
if kubectl get clusterrolebinding tfc-admin-binding &>/dev/null; then
  log "Cluster role binding 'tfc-admin-binding' already exists"
else
  log "Creating cluster role binding 'tfc-admin-binding'..."
  kubectl create clusterrolebinding tfc-admin-binding \
    --clusterrole=cluster-admin \
    --serviceaccount=kube-system:tfc-deployer
fi

# Check if secret already exists (Required for long-lived tokens in K8s 1.24+)
if kubectl get secret tfc-deployer-token -n kube-system &>/dev/null; then
  log "Secret 'tfc-deployer-token' already exists in kube-system namespace"
else
  log "Creating secret 'tfc-deployer-token'..."
  cat <<EOF | kubectl apply -f - >&2
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

log "Retrieving token..."
 
# Use TokenRequest if available (K8s 1.22+), otherwise read secret
# Note: 'kubectl create token' creates a short-lived token (default 1h). 
# If you need this token to last for TFC runs later, reading the Secret is more persistent.
if kubectl create token --help >/dev/null 2>&1; then
  K8S_TOKEN=$(kubectl create token tfc-deployer -n kube-system --duration=24h)
else
  TOKEN_B64=""
  for i in $(seq 1 30); do
    TOKEN_B64=$(kubectl get secret tfc-deployer-token -n kube-system -o jsonpath='{.data.token}' 2>/dev/null || true)
    if [ -n "$TOKEN_B64" ]; then
      break
    fi
    sleep 1
  done
  
  if [ -z "$TOKEN_B64" ]; then
    log "ERROR: token not populated after wait"
    exit 1
  fi
  K8S_TOKEN=$(echo "$TOKEN_B64" | base64 --decode)
fi

# Final Output Logic
# Print to stdout so Job 2 can capture it via K8S_TOKEN=$(...)
# We use printf to avoid trailing newlines that might break the GH API call
printf '%s' "$K8S_TOKEN"
