output "cluster_id" {
  value       = oci_containerengine_cluster.oke.id
  description = "OKE cluster ID"
}

output "cluster_endpoint" {
  value       = local.cluster_endpoint
  description = "OKE cluster endpoint URL"
}

output "kubeconfig_content" {
  value       = data.oci_containerengine_cluster_kube_config.oke_kubeconfig.content
  description = "Raw kubeconfig content from OCI"
  sensitive   = true
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

output "kubeconfig_path" {
  value = local_file.kubeconfig.filename
}

# This is the permanent token — store it as a sensitive TFC workspace variable
# output "terraform_sa_token" {
#   value     = kubernetes_secret_v1.terraform_sa_token.data["token"]
#   sensitive = true
# }