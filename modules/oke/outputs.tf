output "cluster_id" {
  value       = oci_containerengine_cluster.oke.id
  description = "OKE cluster ID"
}

output "cluster_endpoint" {
  value       = local.cluster_endpoint
  description = "OKE cluster endpoint URL"
}

output "public_subnet_id" {
  value = oci_core_subnet.vcn_public_subnet.id
}

# Backward-compatible alias: existing scripts and the (paused) schedule
# workflow read node_pool_id. Maps to the infra pool (always-on, 1 node)
# when create_infra_pool = true; empty otherwise.
output "node_pool_id" {
  value       = var.create_infra_pool ? oci_containerengine_node_pool.infra[0].id : ""
  description = "Infra node pool OCID (alias for backward compatibility). Empty when create_infra_pool = false."
}

output "infra_node_pool_id" {
  value       = var.create_infra_pool ? oci_containerengine_node_pool.infra[0].id : ""
  description = "Infra node pool OCID (small node, taint tier=infra:NoSchedule). Empty when create_infra_pool = false."
}

output "workload_node_pool_id" {
  value       = oci_containerengine_node_pool.workload.id
  description = "Workload node pool OCID (larger node, no taint)."
}

output "workload_node_name" {
  value       = local.workload_node_name
  description = "Kubernetes node name of the workload-pool node."
}

output "infra_node_label" {
  value       = local.infra_node_label
  description = "Value of the tier= label applied to infra-pool nodes (e.g., \"infra\"). The CI taint step uses this to discover the K8s node(s) via `kubectl get nodes -l tier=<label>`. Empty when create_infra_pool = false."
}

output "workload_node_label" {
  value       = var.workload_node_label_value
  description = "Value of the tier= label applied to workload-pool nodes (e.g., \"workload\"). Used by the CI labeling step to derive per-node labels."
}

output "infra_taint" {
  value       = local.infra_taint
  description = "Taint spec applied to the infra node post-provisioning (e.g., tier=infra:NoSchedule)."
}

output "nlb_public_ip" {
  value       = [for ip in oci_network_load_balancer_network_load_balancer.nlb.ip_addresses : ip.ip_address if ip.is_public == true][0]
  description = "NLB public IP for accessing ArgoCD via NodePort"
}

output "kubeconfig_content" {
  value       = data.oci_containerengine_cluster_kube_config.oke_kubeconfig.content
  description = "Raw kubeconfig content from OCI"
  sensitive   = true
}

output "lpg_ocid" {
  value       = var.enable_vcn_peering ? oci_core_local_peering_gateway.vcn_lpg[0].id : ""
  description = "Local Peering Gateway OCID (for cross-tenancy peering). Empty when enable_vcn_peering = false."
}
