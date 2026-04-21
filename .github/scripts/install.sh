#!/usr/bin/env bash

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

require_cmd "helm"
require_cmd "kubectl"

# Check if ArgoCD is already installed
if helm list -n "$ARGOCD_HELM_NAMESPACE" 2>/dev/null | grep -q "^argocd"; then
  success "ArgoCD v${ARGOCD_HELM_VERSION} is already installed"
else
  success "Installing ArgoCD v${ARGOCD_HELM_VERSION}..."
  helm repo add argo "$ARGOCD_HELM_REPO" || warn "ArgoCD helm repo may already exist"
  helm repo update || fail "Failed to update helm repos"

  helm upgrade --install argocd "$ARGOCD_HELM_CHART" \
    --version "$ARGOCD_HELM_VERSION" \
    --namespace "$ARGOCD_HELM_NAMESPACE" \
    --create-namespace \
    --set "server.service.type=NodePort" \
    --set "server.service.nodePortHttps=${ARGOCD_NODE_PORT_HTTPS}" \
    --set 'configs.cm."kustomize\.buildOptions"="--enable-helm"' \
    --set 'configs.cm."application\.sync\.impersonation\.enabled"="true"' \
    || fail "Failed to install ArgoCD"

  success "ArgoCD installed successfully"
fi

# Check if kubeseal is already installed
if command -v kubeseal &> /dev/null; then
  INSTALLED_VERSION=$(kubeseal --version 2>/dev/null | grep -oP 'v\K[\d.]+' || echo "unknown")
  success "kubeseal v${INSTALLED_VERSION} is already installed"
else
  success "Installing kubeseal v${KUBESEAL_VERSION}..."
  KUBESEAL_URL="https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-${KUBESEAL_PLATFORM}.tar.gz"
  KUBESEAL_TMP=$(mktemp -d) || fail "Failed to create temp directory"
  trap "rm -rf $KUBESEAL_TMP" EXIT

  curl -fsSL "$KUBESEAL_URL" -o "$KUBESEAL_TMP/kubeseal.tar.gz" || fail "Failed to download kubeseal"
  tar -xzf "$KUBESEAL_TMP/kubeseal.tar.gz" -C "$KUBESEAL_TMP" kubeseal || fail "Failed to extract kubeseal"
  sudo install -m 755 "$KUBESEAL_TMP/kubeseal" /usr/local/bin/kubeseal || fail "Failed to install kubeseal"

  success "kubeseal installed successfully"
fi

# Check if ArgoCD CLI is already installed
if command -v argocd &> /dev/null; then
  INSTALLED_VERSION=$(argocd version --client 2>/dev/null | grep -oP 'Version:\s+v\K[\d.]+' || echo "unknown")
  success "ArgoCD CLI v${INSTALLED_VERSION} is already installed"
else
  success "Installing ArgoCD CLI v${ARGOCD_CLI_VERSION}..."
  ARGOCD_CLI_URL="https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_CLI_VERSION}/argocd-${ARGOCD_CLI_PLATFORM}"
  curl -fsSL "$ARGOCD_CLI_URL" -o /tmp/argocd || fail "Failed to download ArgoCD CLI"
  sudo install -m 755 /tmp/argocd /usr/local/bin/argocd || fail "Failed to install ArgoCD CLI"
  rm /tmp/argocd

  success "ArgoCD CLI installed successfully"
fi

success "All tools ready"

