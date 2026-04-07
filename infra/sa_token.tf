resource "kubernetes_service_account_v1" "terraform_sa" {
  metadata {
    name      = "terraform-admin"
    namespace = "kube-system"
  }
  depends_on = [oci_containerengine_node_pool.workers]
}

# Bind it to cluster-admin
resource "kubernetes_cluster_role_binding_v1" "terraform_sa_binding" {
  metadata {
    name = "terraform-admin-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.terraform_sa.metadata[0].name
    namespace = "kube-system"
  }
}

# Create a long-lived token secret for the service account
resource "kubernetes_secret_v1" "terraform_sa_token" {
  metadata {
    name      = "terraform-admin-token"
    namespace = "kube-system"
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.terraform_sa.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"

  depends_on = [kubernetes_cluster_role_binding_v1.terraform_sa_binding]
}