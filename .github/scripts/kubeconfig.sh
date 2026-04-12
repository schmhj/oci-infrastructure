#!/usr/bin/env bash

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

# This script is primarily for local development
# GitHub Actions CI/CD uses exec-based Kubernetes authentication instead

# Validate required environment variables
require_env "CLUSTER_ID"
require_env "REGION"

require_cmd "oci"

success "Generating kubeconfig for cluster: $CLUSTER_ID"

mkdir -p "$HOME/.kube"

oci ce cluster create-kubeconfig \
  --cluster-id "$CLUSTER_ID" \
  --file "$HOME/.kube/config" \
  --region "$REGION" \
  --token-version "$KUBE_TOKEN_VERSION" \
  --kube-endpoint "$KUBE_ENDPOINT_TYPE" \
  || fail "Failed to generate kubeconfig"

if [ -f "$HOME/.kube/config" ]; then
  chmod 600 "$HOME/.kube/config"
  success "Kubeconfig generated at $HOME/.kube/config"
else
  fail "Failed to create kubeconfig file at $HOME/.kube/config"
fi
