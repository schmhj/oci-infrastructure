#!/usr/bin/env bash

# Apply the infra node taint and patch OKE-managed DaemonSets (kube-proxy,
# vpc-cni) to tolerate it. The taint repels workload apps; the patches
# keep the cluster's networking plugins running on the infra node.
#
# Required env:
#   INFRA_NODE_LABEL  - Value of the tier= kubelet label applied to
#                       infra-pool nodes (e.g., "infra"). The script
#                       uses this to discover the K8s node(s) via
#                       `kubectl get nodes -l tier=<label>`; we do NOT
#                       use the OCI-generated node name because OKE
#                       registers K8s nodes using the node's private
#                       IP, not the OCI control-plane identifier
#                       (`oke-xxx-0` format). May be empty when the
#                       cluster has create_infra_pool = false; the
#                       script then exits 0 without doing any kubectl
#                       work.
#   TAINT             - Taint spec in the form "key=value:effect"
#                       (e.g., "tier=infra:NoSchedule"). Unused when
#                       INFRA_NODE_LABEL is empty.
#
# Idempotent: safe to re-run on every CI apply. --overwrite=true updates
# the existing taint in place; toleration patches skip if already present.
# Taints ALL nodes with the matching label, so works for infra_node_count > 1.

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

# No infra node (cluster has create_infra_pool = false, or the pool is
# empty). Nothing to taint; DaemonSets run on untainted workload nodes
# and don't need patching. Exit cleanly. Must run before any require_env /
# require_cmd so tenant-b's first deploy doesn't fail on missing kubectl
# or an unset TAINT.
if [[ -z "${INFRA_NODE_LABEL:-}" ]]; then
  warn "INFRA_NODE_LABEL is empty (cluster has no infra pool); skipping taint + DaemonSet patches"
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
# 1. Apply the taint to infra node(s)
# ============================================================

# Find infra nodes by the kubelet `tier=<label>` label. OKE applies
# this via `initial_node_labels` in the node-pool config, so it is
# present as soon as kubelet registers with the API server.
LABEL_SELECTOR="tier=${INFRA_NODE_LABEL}"

# Wait for at least one node with the label to be visible. OKE may
# complete cloud-init before kubelet has finished registering the node
# with the API server; this race causes "nodes not found" errors on
# first apply after cluster creation. The `|| true` on kubectl lets
# us retry on transient errors (e.g., token refresh) instead of
# failing the whole script.
success "Waiting for node(s) with label '${LABEL_SELECTOR}' to be visible in Kubernetes..."
WAIT_RETRIES=30
WAIT_DELAY=10
INFRA_NODES=""
for ((i = 1; i <= WAIT_RETRIES; i++)); do
  INFRA_NODES=$(kubectl get nodes -l "$LABEL_SELECTOR" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  if [[ -n "$INFRA_NODES" ]]; then
    NODE_COUNT=$(printf '%s' "$INFRA_NODES" | grep -c .)
    success "Found ${NODE_COUNT} node(s) with label '${LABEL_SELECTOR}' (attempt $i/$WAIT_RETRIES)"
    break
  fi
  if [[ $i -eq $WAIT_RETRIES ]]; then
    fail "No node with label '${LABEL_SELECTOR}' visible in Kubernetes after $((WAIT_RETRIES * WAIT_DELAY))s"
  fi
  warn "No labeled node yet; retrying in ${WAIT_DELAY}s (attempt $i/$WAIT_RETRIES)..."
  sleep "$WAIT_DELAY"
done

# Apply taint to each matching node. Looping (rather than tainting
# just nodes[0]) supports infra_node_count > 1 in the future.
while IFS= read -r NODE; do
  [[ -z "$NODE" ]] && continue
  success "Applying taint '${TAINT}' to node '${NODE}'..."
  kubectl taint node "$NODE" "$TAINT" --overwrite=true

  # Verify — jsonpath outputs each taint as key=value:effect per line
  if ! kubectl get node "$NODE" \
       -o jsonpath='{range .spec.taints[*]}{.key}={.value}:{.effect}{"\n"}{end}' \
       | grep -qxF "$TAINT"; then
    fail "Taint '${TAINT}' not found on node '${NODE}' after apply"
  fi
  success "Taint '${TAINT}' verified on '${NODE}'"
done <<< "$INFRA_NODES"

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
