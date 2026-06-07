#!/usr/bin/env bash

# set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

require_cmd "helm"
require_cmd "kubectl"

EXISTING_TYPE=$(kubectl get svc argocd-server \
  -n "$ARGOCD_HELM_NAMESPACE" \
  -o jsonpath='{.spec.type}' 2>/dev/null)
EXISTING_TYPE=${EXISTING_TYPE:-None}

SERVICE_FLAGS=()
if [[ "$EXISTING_TYPE" == "ClusterIP" ]]; then
  success "argocd-server is already ClusterIP (previously patched); skipping NodePort allocation"
  SERVICE_FLAGS+=(--set "server.service.type=ClusterIP")
else
  SERVICE_FLAGS+=(
    --set "server.service.type=NodePort"
    --set "server.service.nodePortHttps=${ARGOCD_NODE_PORT_HTTPS}"
  )
fi

# Infra node (Node 1) carries taint tier=infra:NoSchedule. ArgoCD must
# tolerate it AND prefer the infra node so the four components (server,
# controller, repoServer, applicationsetController) all land there.
# Workload apps use nodeSelector tier=workload to land on Node 2.
INFRA_TAINT_KEY="tier"
INFRA_TAINT_VALUE="infra"
INFRA_TAINT_EFFECT="NoSchedule"
INFRA_NODE_LABEL="infra"

INFRA_TOLERATIONS=(
  --set "server.tolerations[0].key=${INFRA_TAINT_KEY}"
  --set "server.tolerations[0].operator=Equal"
  --set "server.tolerations[0].value=${INFRA_TAINT_VALUE}"
  --set "server.tolerations[0].effect=${INFRA_TAINT_EFFECT}"
  --set "controller.tolerations[0].key=${INFRA_TAINT_KEY}"
  --set "controller.tolerations[0].operator=Equal"
  --set "controller.tolerations[0].value=${INFRA_TAINT_VALUE}"
  --set "controller.tolerations[0].effect=${INFRA_TAINT_EFFECT}"
  --set "repoServer.tolerations[0].key=${INFRA_TAINT_KEY}"
  --set "repoServer.tolerations[0].operator=Equal"
  --set "repoServer.tolerations[0].value=${INFRA_TAINT_VALUE}"
  --set "repoServer.tolerations[0].effect=${INFRA_TAINT_EFFECT}"
  --set "applicationsetController.tolerations[0].key=${INFRA_TAINT_KEY}"
  --set "applicationsetController.tolerations[0].operator=Equal"
  --set "applicationsetController.tolerations[0].value=${INFRA_TAINT_VALUE}"
  --set "applicationsetController.tolerations[0].effect=${INFRA_TAINT_EFFECT}"
)

INFRA_NODESELECTORS=(
  --set "server.nodeSelector.tier=${INFRA_NODE_LABEL}"
  --set "controller.nodeSelector.tier=${INFRA_NODE_LABEL}"
  --set "repoServer.nodeSelector.tier=${INFRA_NODE_LABEL}"
  --set "applicationsetController.nodeSelector.tier=${INFRA_NODE_LABEL}"
)

success "Installing/upgrading ArgoCD to v${ARGOCD_HELM_VERSION}..."
helm repo add argo "$ARGOCD_HELM_REPO" || warn "ArgoCD helm repo may already exist"
helm repo update || fail "Failed to update helm repos"

run_helm_upgrade() {
  helm upgrade --install argocd "$ARGOCD_HELM_CHART" \
    --version "$ARGOCD_HELM_VERSION" \
    --namespace "$ARGOCD_HELM_NAMESPACE" \
    --create-namespace \
    "${SERVICE_FLAGS[@]}" \
    "${INFRA_TOLERATIONS[@]}" \
    "${INFRA_NODESELECTORS[@]}" \
    --set "configs.cm.kustomize\.buildOptions=--enable-helm" \
    --set "configs.cm.application\.sync\.impersonation\.enabled=true"
}

if ! run_helm_upgrade; then
  warn "Helm upgrade failed; checking for stale argocd-server holding nodePort ${ARGOCD_NODE_PORT_HTTPS}..."
  if kubectl get svc argocd-server -n "$ARGOCD_HELM_NAMESPACE" \
     -o jsonpath='{.spec.ports[*].nodePort}' 2>/dev/null | tr ' ' '\n' | grep -qx "${ARGOCD_NODE_PORT_HTTPS}"; then
    warn "argocd-server holds nodePort ${ARGOCD_NODE_PORT_HTTPS} (stale from interrupted patch); deleting and retrying..."
    kubectl delete svc argocd-server -n "$ARGOCD_HELM_NAMESPACE" --wait=true --timeout=60s
    run_helm_upgrade || fail "Failed to install/upgrade ArgoCD after recovery"
  else
    fail "Helm upgrade failed; nodePort ${ARGOCD_NODE_PORT_HTTPS} not held by argocd-server"
  fi
fi

success "ArgoCD installed/upgraded to v${ARGOCD_HELM_VERSION}"

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

