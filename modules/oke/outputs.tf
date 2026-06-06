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
# workflow read node_pool_id. Maps to the infra pool (always-on, 1 node).
output "node_pool_id" {
  value       = oci_containerengine_node_pool.infra.id
  description = "Infra node pool OCID (alias for backward compatibility)."
}

output "infra_node_pool_id" {
  value       = oci_containerengine_node_pool.infra.id
  description = "Infra node pool OCID (small node, taint workload=infra:NoSchedule)."
}

output "functional_node_pool_id" {
  value       = oci_containerengine_node_pool.functional.id
  description = "Functional node pool OCID (larger node, no taint)."
}

output "infra_node_name" {
  value       = local.infra_node_name
  description = "Kubernetes node name of the infra-pool node. Used by the CI taint step."
}

output "functional_node_name" {
  value       = local.functional_node_name
  description = "Kubernetes node name of the functional-pool node."
}

output "infra_taint" {
  value       = local.infra_taint
  description = "Taint spec applied to the infra node post-provisioning (e.g., workload=infra:NoSchedule)."
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
