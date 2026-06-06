#!/usr/bin/env bash

# Apply the infra node taint and patch OKE-managed DaemonSets (kube-proxy,
# vpc-cni) to tolerate it. The taint repels functional apps; the patches
# keep the cluster's networking plugins running on the infra node.
#
# Required env:
#   INFRA_NODE_NAME  - Kubernetes node name of the infra-pool node.
#   TAINT            - Taint spec in the form "key=value:effect"
#                      (e.g., "workload=infra:NoSchedule").
#
# Idempotent: safe to re-run on every CI apply. --overwrite=true updates
# the existing taint in place; toleration patches skip if already present.

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

require_cmd "kubectl"
require_env "INFRA_NODE_NAME"
require_env "TAINT"

# Sanity: taint spec must look like key=value:effect
if [[ ! "$TAINT" =~ ^[^=]+=[^:]+:[^:]+$ ]]; then
  fail "TAINT must be in the form key=value:effect (got: '$TAINT')"
fi

# Parse taint spec
TAINT_KEY="${TAINT%%=*}"
REST="${TAINT#*=}"
TAINT_VALUE="${REST%%:*}"
TAINT_EFFECT="${REST#*:}"

# ============================================================
# 1. Apply the taint to the infra node
# ============================================================
success "Applying taint '${TAINT}' to node '${INFRA_NODE_NAME}'..."
kubectl taint node "$INFRA_NODE_NAME" "$TAINT" --overwrite=true

# Verify
if ! kubectl get node "$INFRA_NODE_NAME" -o jsonpath='{.spec.taints}' \
     | grep -qF "$TAINT"; then
  fail "Taint '${TAINT}' not found on node '${INFRA_NODE_NAME}' after apply"
fi
success "Taint '${TAINT}' verified on '${INFRA_NODE_NAME}'"

# ============================================================
# 2. Patch OKE-managed DaemonSets to tolerate the taint
# Without this, kube-proxy / vpc-cni avoid Node 1 and the node
# loses network connectivity.
# ============================================================
TOLERATION_PAYLOAD=$(cat <<EOF
[{"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"${TAINT_KEY}","operator":"Equal","value":"${TAINT_VALUE}","effect":"${TAINT_EFFECT}"}}]
EOF
)

# Check whether a DaemonSet already tolerates this exact taint.
ds_has_toleration() {
  local ds="$1"
  kubectl get daemonset "$ds" -n kube-system \
    -o jsonpath='{range .spec.template.spec.tolerations[*]}{.key}={.value}:{.effect}{"\n"}{end}' \
    2>/dev/null | grep -qxF "$TAINT"
}

for ds in kube-proxy vpc-cni oci-vcn-cni oci-cni; do
  if ! kubectl get daemonset "$ds" -n kube-system >/dev/null 2>&1; then
    echo "Daemonset ${ds} not present in kube-system; skipping"
    continue
  fi

  if ds_has_toleration "$ds"; then
    success "Daemonset ${ds} already tolerates '${TAINT}'; skipping"
    continue
  fi

  echo "Patching daemonset ${ds} to tolerate '${TAINT}'..."
  if kubectl patch daemonset "$ds" -n kube-system \
       --type=json -p="$TOLERATION_PAYLOAD" >/dev/null; then
    success "Patched daemonset ${ds}"
  else
    warn "Failed to patch daemonset ${ds}; node network may be affected"
  fi
done

success "Taint application complete"
