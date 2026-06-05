output "cluster_id" {
  description = "OKE cluster ID"
  value       = module.oke.cluster_id
}

output "cluster_endpoint" {
  description = "OKE Cluster Endpoint URL"
  value       = module.oke.cluster_endpoint
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = module.oke.public_subnet_id
}

output "node_pool_id" {
  description = "Worker node pool ID"
  value       = module.oke.node_pool_id
}

output "nlb_public_ip" {
  description = "NLB public IP for accessing ArgoCD via NodePort"
  value       = module.oke.nlb_public_ip
}

output "kubeconfig_content" {
  description = "Raw kubeconfig content from OCI"
  value       = module.oke.kubeconfig_content
  sensitive   = true
}
