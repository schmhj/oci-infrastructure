provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}

provider "oci" {
  region = var.region
}

locals {
  base_name = "${var.project}-${var.env}-${var.region}"

  prefixes = {
    namespace = "ns"
    release   = "release"
    nlb       = "nlb"
    snet_pub  = "snet-pub"
    snet_priv = "snet-priv"
    np        = "np"
  }

  name_namespace = "${local.prefixes.namespace}-${var.project}-${var.env}-${var.region}"
  name_release   = "${local.prefixes.release}-${var.project}-${var.env}-${var.region}"
  name_nlb       = "${local.prefixes.nlb}-${var.project}-${var.env}-${var.region}"
}

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "${local.name_namespace}-argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "${local.name_release}-argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  version    = "7.8.26"

  set = [
    {
      name  = "server.service.type"
      value = "NodePort"
    },
    {
      name  = "server.service.nodePortHttps"
      value = "30443"
    }
  ]

  depends_on = [kubernetes_namespace_v1.argocd]
}


data "oci_containerengine_node_pool" "k8s_np" {
  node_pool_id = var.node_pool_id
}

locals {
  active_nodes = [for node in data.oci_containerengine_node_pool.k8s_np.nodes : node if node.state == "ACTIVE"]
}

resource "oci_network_load_balancer_network_load_balancer" "nlb" {
  compartment_id = var.compartment_id
  display_name   = local.name_nlb
  subnet_id      = var.public_subnet_id

  is_private                     = false
  is_preserve_source_destination = false
}

resource "oci_network_load_balancer_backend_set" "nlb_backend_set" {
  health_checker {
    protocol = "TCP"
    port     = 10256
  }
  name                     = "${local.name_nlb}-backend-set"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.nlb.id
  policy                   = "FIVE_TUPLE"

  is_preserve_source = false
}

resource "oci_network_load_balancer_backend" "nlb_backend" {
  count                    = length(local.active_nodes)
  backend_set_name         = oci_network_load_balancer_backend_set.nlb_backend_set.name
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.nlb.id
  port                     = 30443
  target_id                = local.active_nodes[count.index].id
}

resource "oci_network_load_balancer_listener" "nlb_listener" {
  default_backend_set_name = oci_network_load_balancer_backend_set.nlb_backend_set.name
  name                     = "${local.name_nlb}-listener"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.nlb.id
  port                     = "443"
  protocol                 = "TCP"
}
