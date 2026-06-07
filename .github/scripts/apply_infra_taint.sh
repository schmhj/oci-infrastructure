#!/usr/bin/env bash

# Apply the infra node taint and patch OKE-managed DaemonSets (kube-proxy,
# vpc-cni) to tolerate it. The taint repels workload apps; the patches
# keep the cluster's networking plugins running on the infra node.
#
# Required env:
#   INFRA_NODE_NAME  - Kubernetes node name of the infra-pool node.
#                      May be empty when the cluster has create_infra_pool = false;
#                      the script then exits 0 without doing any kubectl work.
#   TAINT            - Taint spec in the form "key=value:effect"
#                      (e.g., "tier=infra:NoSchedule"). Unused when
#                      INFRA_NODE_NAME is empty.
#
# Idempotent: safe to re-run on every CI apply. --overwrite=true updates
# the existing taint in place; toleration patches skip if already present.

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

# No infra node (cluster has create_infra_pool = false, or the pool is
# empty). Nothing to taint; DaemonSets run on untainted workload nodes
# and don't need patching. Exit cleanly. Must run before any require_env /
# require_cmd so tenant-b's first deploy doesn't fail on missing kubectl
# or an unset TAINT.
if [[ -z "${INFRA_NODE_NAME:-}" ]]; then
  warn "INFRA_NODE_NAME is empty (cluster has no infra pool); skipping taint + DaemonSet patches"
  exit 0
fi

require_cmd "kubectl"
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

# Wait for the node to be visible in the Kubernetes API. OCI may return
# the node name from the data source before kubelet has finished
# registering the node with the API server; this race condition causes
# "nodes not found" errors on first apply after cluster creation.
success "Waiting for node '${INFRA_NODE_NAME}' to be visible in Kubernetes..."
WAIT_RETRIES=30
WAIT_DELAY=10
for ((i = 1; i <= WAIT_RETRIES; i++)); do
  if kubectl get node "$INFRA_NODE_NAME" >/dev/null 2>&1; then
    success "Node is visible (attempt $i/$WAIT_RETRIES)"
    break
  fi
  if [[ $i -eq $WAIT_RETRIES ]]; then
    fail "Node '${INFRA_NODE_NAME}' not visible in Kubernetes after $((WAIT_RETRIES * WAIT_DELAY))s"
  fi
  warn "Node not yet visible; retrying in ${WAIT_DELAY}s (attempt $i/$WAIT_RETRIES)..."
  sleep "$WAIT_DELAY"
done

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
