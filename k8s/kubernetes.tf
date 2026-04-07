# ArgoCD Namespace
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

# Cluster admin binding for Terraform user
# Grants access to deploy applications via Terraform
resource "kubernetes_cluster_role_binding" "terraform_admin" {
  metadata {
    name = "terraform-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "User"
    name      = var.user_ocid
    api_group = "rbac.authorization.k8s.io"
  }
}
