#!/usr/bin/env bash
# Centralized configuration for CI/CD pipeline
# Source this file in workflow scripts: source ./.github/config.sh

set -euo pipefail

# ============================================================
# ArgoCD Helm Chart Configuration
# ============================================================
export ARGOCD_HELM_VERSION="7.8.26"
export ARGOCD_HELM_REPO="https://argoproj.github.io/argo-helm"
export ARGOCD_HELM_CHART="argo/argo-cd"
export ARGOCD_HELM_NAMESPACE="argocd"
export ARGOCD_NODE_PORT=30443
export ARGOCD_NODE_PORT_HTTPS=30443

# ============================================================
# Kubeseal (Sealed Secrets) Configuration
# ============================================================
export KUBESEAL_VERSION="0.34.0"
export KUBESEAL_PLATFORM="linux-amd64"
export KUBESEAL_NAMESPACE="kube-system"

# ============================================================
# Kubernetes Configuration
# ============================================================
export KUBE_TOKEN_VERSION="2.0.0"
export KUBE_ENDPOINT_TYPE="PUBLIC_ENDPOINT"

# ============================================================
# Timeouts and Retry Configuration
# ============================================================
export ROLLOUT_TIMEOUT="300s"
export HEALTH_CHECK_RETRIES=60
export HEALTH_CHECK_INTERVAL=3

# ============================================================
# Script Utility Functions
# ============================================================

# Fail with error message
fail() {
  echo "❌ ERROR: $*" >&2
  exit 1
}

# Success message
success() {
  echo "✅ $*"
}

# Warning message
warn() {
  echo "⚠️  WARNING: $*" >&2
}

# Validate required environment variable
require_env() {
  local var_name="$1"
  local var_value="${!var_name:-}"
  if [ -z "$var_value" ]; then
    fail "Required environment variable not set: $var_name"
  fi
}

# Validate required command exists
require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" &> /dev/null; then
    fail "Required command not found: $cmd"
  fi
}

success "CI/CD configuration loaded"
