#!/usr/bin/env bash

# Apply per-node labels derived from the node pool index.
# Label format: <tier>-<index> (e.g., infra-0, workload-0, workload-1)
#
# The OCI API returns each node with a pool-level index. This script
# queries OCI for nodes in each pool, maps them to Kubernetes node names
# via private IP, and applies the label with kubectl.
#
# Required env:
#   INFRA_POOL_OCID      - OCID of the infra node pool (empty when
#                          create_infra_pool = false; script skips it).
#   WORKLOAD_POOL_OCID   - OCID of the workload node pool.
#   INFRA_NODE_LABEL     - Tier label value for infra nodes (e.g. "infra").
#   WORKLOAD_NODE_LABEL  - Tier label value for workload nodes (e.g. "workload").
#
# Optional env:
#   OCI_REGION           - OCI region for API calls (falls back to
#                          OCI_DEFAULT_REGION or ~/.oci/config).
#
# Idempotent: safe to re-run on every CI apply. --overwrite updates
# existing labels in place.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

require_cmd "kubectl"
require_cmd "oci"

# ── helpers ──────────────────────────────────────────────────────

# Query OCI for nodes in a pool and return "index private_ip" lines.
# Output is sorted by index so positions are deterministic.
list_pool_nodes() {
  local pool_ocid="$1"
  oci ce node-pool list-nodes \
    --node-pool-id "$pool_ocid" \
    --query "data[*].[\"index\",\"private-ip\"]" \
    --output tsv 2>/dev/null | sort -n
}

# Build a map of private_ip → k8s_node_name from `kubectl get nodes`.
declare -A IP_TO_NODE

build_ip_map() {
  local raw
  raw=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null)
  while IFS=' ' read -r ip name; do
    [[ -z "$ip" || -z "$name" ]] && continue
    IP_TO_NODE["$ip"]="$name"
  done <<< "$raw"
}

# Apply label <tier>-<index> to a Kubernetes node.
label_node() {
  local tier="$1"
  local index="$2"
  local node_name="$3"
  local label="${tier}-${index}"

  kubectl label node "$node_name" "${label}=" --overwrite >/dev/null
  success "Labeled node '${node_name}' with '${label}'"
}

# Process a single pool: query OCI, map to K8s, apply labels.
label_pool() {
  local pool_ocid="$1"
  local tier="$2"

  if [[ -z "$pool_ocid" ]]; then
    warn "Pool OCID is empty for tier '${tier}'; skipping"
    return 0
  fi

  success "Listing nodes in pool '${pool_ocid}' (tier=${tier})..."
  local nodes
  nodes=$(list_pool_nodes "$pool_ocid")

  if [[ -z "$nodes" ]]; then
    warn "No nodes found in pool '${pool_ocid}'; skipping"
    return 0
  fi

  local count
  count=$(printf '%s' "$nodes" | grep -c . || true)
  success "Found ${count} node(s) in pool (tier=${tier})"

  while IFS=$'\t' read -r index private_ip; do
    [[ -z "$index" || -z "$private_ip" ]] && continue

    local k8s_node="${IP_TO_NODE[$private_ip]:-}"
    if [[ -z "$k8s_node" ]]; then
      warn "No Kubernetes node found for private IP '${private_ip}' (index=${index}); skipping"
      continue
    fi

    label_node "$tier" "$index" "$k8s_node"
  done <<< "$nodes"
}

# ── main ─────────────────────────────────────────────────────────

success "Building private-IP → K8s-node map..."
build_ip_map

node_count=${#IP_TO_NODE[@]}
if [[ "$node_count" -eq 0 ]]; then
  fail "No Kubernetes nodes found; is kubectl configured?"
fi
success "Mapped ${node_count} Kubernetes node(s)"

label_pool "${INFRA_POOL_OCID:-}" "${INFRA_NODE_LABEL:-}"
label_pool "${WORKLOAD_POOL_OCID:-}" "${WORKLOAD_NODE_LABEL:-}"

success "Node labeling complete"
