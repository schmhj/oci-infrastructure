#!/usr/bin/env bash

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

require_cmd "helm"
require_cmd "kubectl"

# Install ArgoCD
success "Installing ArgoCD v${ARGOCD_HELM_VERSION}..."
helm repo add argo "$ARGOCD_HELM_REPO" || warn "ArgoCD helm repo may already exist"
helm repo update || fail "Failed to update helm repos"

helm install argocd "$ARGOCD_HELM_CHART" \
  --version "$ARGOCD_HELM_VERSION" \
  --namespace "$ARGOCD_HELM_NAMESPACE" \
  --create-namespace \
  --set "server.service.type=NodePort" \
  --set "server.service.nodePortHttps=${ARGOCD_NODE_PORT_HTTPS}" \
  --set 'configs.cm."kustomize\.buildOptions"="--enable-helm"' \
  --set 'configs.cm."application\.sync\.impersonation\.enabled"="true"' \
  || fail "Failed to install ArgoCD"

success "ArgoCD installed successfully"

# Install kubeseal
success "Installing kubeseal v${KUBESEAL_VERSION}..."
KUBESEAL_URL="https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-${KUBESEAL_PLATFORM}.tar.gz"
KUBESEAL_TMP=$(mktemp -d) || fail "Failed to create temp directory"
trap "rm -rf $KUBESEAL_TMP" EXIT

curl -fsSL "$KUBESEAL_URL" -o "$KUBESEAL_TMP/kubeseal.tar.gz" || fail "Failed to download kubeseal"
tar -xzf "$KUBESEAL_TMP/kubeseal.tar.gz" -C "$KUBESEAL_TMP" kubeseal || fail "Failed to extract kubeseal"
sudo install -m 755 "$KUBESEAL_TMP/kubeseal" /usr/local/bin/kubeseal || fail "Failed to install kubeseal"

success "kubeseal installed successfully"

# Install ArgoCD CLI
success "Installing ArgoCD CLI v${ARGOCD_CLI_VERSION}..."
ARGOCD_CLI_URL="https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_CLI_VERSION}/argocd-${ARGOCD_CLI_PLATFORM}"
curl -fsSL "$ARGOCD_CLI_URL" -o /tmp/argocd || fail "Failed to download ArgoCD CLI"
sudo install -m 755 /tmp/argocd /usr/local/bin/argocd || fail "Failed to install ArgoCD CLI"
rm /tmp/argocd

success "ArgoCD CLI installed successfully"
success "All tools deployed"
