output "argocd_namespace" {
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
  description = "ArgoCD namespace"
}

output "argocd_nodeport_url" {
  value       = "https://<NLB_IP>:${var.node_port}"
  description = "ArgoCD access URL (replace NLB_IP with load balancer public IP from infra/ output)"
}

