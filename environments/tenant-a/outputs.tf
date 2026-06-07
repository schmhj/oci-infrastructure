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
  description = "Worker node pool ID (alias for infra_node_pool_id; empty when create_infra_pool = false)"
  value       = module.oke.node_pool_id
}

output "infra_node_pool_id" {
  description = "Infra node pool OCID (small node, taint tier=infra:NoSchedule). Empty when create_infra_pool = false."
  value       = module.oke.infra_node_pool_id
}

output "workload_node_pool_id" {
  description = "Workload node pool OCID (larger node, no taint)"
  value       = module.oke.workload_node_pool_id
}

output "infra_node_name" {
  description = "Kubernetes node name of the infra-pool node. Empty when create_infra_pool = false."
  value       = module.oke.infra_node_name
}

output "workload_node_name" {
  description = "Kubernetes node name of the workload-pool node"
  value       = module.oke.workload_node_name
}

output "infra_taint" {
  description = "Taint spec applied to the infra node post-provisioning (e.g., tier=infra:NoSchedule). Empty when create_infra_pool = false."
  value       = module.oke.infra_taint
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
