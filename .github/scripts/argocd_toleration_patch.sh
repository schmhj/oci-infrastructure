#!/usr/bin/env bash

# Patch ArgoCD deployments that are missing the infra-node toleration and
# nodeSelector.  The Helm install (install.sh) covers server, controller,
# repoServer, and applicationsetController via --set flags, but four
# workloads still land on the untainted workload node:
#   - argocd-applicationset-controller
#   - argocd-dex-server
#   - argocd-notifications-controller
#   - argocd-redis
#
# This script adds the toleration + nodeSelector so all ArgoCD components
# run on the infra node.
#
# Required env:
#   INFRA_NODE_LABEL - tier label value (e.g. "infra")
#   TAINT            - taint spec "key=value:effect" (e.g. "tier=infra:NoSchedule")
#
# Idempotent: skips workloads that already tolerate the taint.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

require_cmd "kubectl"

if [[ -z "${INFRA_NODE_LABEL:-}" ]]; then
  warn "INFRA_NODE_LABEL is empty; skipping ArgoCD toleration patch"
  exit 0
fi

require_env "TAINT"

if [[ ! "$TAINT" =~ ^[^=]+=[^:]+:[^:]+$ ]]; then
  fail "TAINT must be in the form key=value:effect (got: '$TAINT')"
fi

TAINT_KEY="${TAINT%%=*}"
REST="${TAINT#*=}"
TAINT_VALUE="${REST%%:*}"
TAINT_EFFECT="${REST#*:}"

DEPLOYMENTS=(
  argocd-applicationset-controller
  argocd-dex-server
  argocd-notifications-controller
  argocd-redis
)

# ── helpers ──────────────────────────────────────────────────────

deploy_has_toleration() {
  local deploy="$1"
  kubectl get deploy "$deploy" -n argocd \
    -o jsonpath='{range .spec.template.spec.tolerations[*]}{.key}={.value}:{.effect}{"\n"}{end}' \
    2>/dev/null | grep -qxF "$TAINT"
}

deploy_tolerations_exist() {
  local deploy="$1"
  local count
  count=$(kubectl get deploy "$deploy" -n argocd \
    -o jsonpath='{range .spec.template.spec.tolerations[*]}{.key}{"\n"}{end}' \
    2>/dev/null | grep -c . || true)
  [[ "$count" -gt 0 ]]
}

deploy_has_node_selector() {
  local deploy="$1"
  local current
  current=$(kubectl get deploy "$deploy" -n argocd \
    -o jsonpath='{.spec.template.spec.nodeSelector.tier}' 2>/dev/null || true)
  [[ "$current" == "$INFRA_NODE_LABEL" ]]
}

# ── main ─────────────────────────────────────────────────────────

for deploy in "${DEPLOYMENTS[@]}"; do
  if ! kubectl get deploy "$deploy" -n argocd >/dev/null 2>&1; then
    warn "Deployment ${deploy} not found in argocd namespace; skipping"
    continue
  fi

  patched=false

  # ── toleration ──
  if deploy_has_toleration "$deploy"; then
    success "${deploy} already tolerates '${TAINT}'; skipping"
  else
    echo "Patching ${deploy} to tolerate '${TAINT}'..."
    if deploy_tolerations_exist "$deploy"; then
      # Tolerations array exists; append to it
      kubectl patch deploy "$deploy" -n argocd --type=json \
        -p="[{\"op\":\"add\",\"path\":\"/spec/template/spec/tolerations/-\",\"value\":{\"key\":\"${TAINT_KEY}\",\"operator\":\"Equal\",\"value\":\"${TAINT_VALUE}\",\"effect\":\"${TAINT_EFFECT}\"}}]"
    else
      # No tolerations array; create it via merge patch
      kubectl patch deploy "$deploy" -n argocd --type=merge \
        -p="{\"spec\":{\"template\":{\"spec\":{\"tolerations\":[{\"key\":\"${TAINT_KEY}\",\"operator\":\"Equal\",\"value\":\"${TAINT_VALUE}\",\"effect\":\"${TAINT_EFFECT}\"}]}}}}"
    fi
    patched=true
  fi

  # ── nodeSelector ──
  if deploy_has_node_selector "$deploy"; then
    success "${deploy} already has nodeSelector tier=${INFRA_NODE_LABEL}; skipping"
  else
    echo "Patching ${deploy} nodeSelector to tier=${INFRA_NODE_LABEL}..."
    kubectl patch deploy "$deploy" -n argocd --type=merge \
      -p="{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"tier\":\"${INFRA_NODE_LABEL}\"}}}}}"
    patched=true
  fi

  # ── rollout ──
  if $patched; then
    echo "Waiting for ${deploy} rollout..."
    kubectl rollout status deploy "$deploy" -n argocd --timeout=5m
    success "${deploy} patched and rolled out"
  fi
done

success "ArgoCD toleration + nodeSelector patch complete"
