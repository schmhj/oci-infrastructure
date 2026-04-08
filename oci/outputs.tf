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

output "node_pool_id" {
  value = oci_containerengine_node_pool.workers.id
}

output "nlb_public_ip" {
  value       = [for ip in oci_network_load_balancer_network_load_balancer.nlb.ip_addresses : ip.ip_address if ip.is_public == true][0]
  description = "NLB public IP for accessing ArgoCD via NodePort"
}

output "kubeconfig_content" {
  value = local.kubeconfig
  description = "K8s configuration"
}