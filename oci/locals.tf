locals {
  # Naming convention base
  base_name = "${var.project}-${var.env}-${var.region}"

  # Resource name prefixes for consistent naming
  prefixes = {
    vcn       = "vcn"
    snet_pub  = "snet-pub"
    snet_priv = "snet-priv"
    oke       = "oke"
    np        = "np"
    nsg       = "nsg"
    nlb       = "nlb"
  }

  # VCN resources
  name_vcn       = "${local.prefixes.vcn}-${var.project}-${var.env}-${var.region}"
  name_vcn_dns   = "${local.prefixes.vcn}-${var.project}-${var.env}"
  name_snet_pub  = "${local.prefixes.snet_pub}-${var.project}-${var.env}-${var.region}"
  name_snet_priv = "${local.prefixes.snet_priv}-${var.project}-${var.env}-${var.region}"

  # OKE resources
  name_oke = "${local.prefixes.oke}-${var.project}-${var.env}-${var.region}"
  name_np  = "${local.prefixes.np}-${var.project}-${var.env}-${var.region}"
  name_nsg = "${local.prefixes.nsg}-${var.project}-${var.env}-${var.region}"

  # Load balancer
  name_nlb = "${local.prefixes.nlb}-${var.project}-${var.env}-${var.region}"

  # Kubernetes network configuration
  pods_cidr     = "10.244.0.0/16"
  services_cidr = "10.96.0.0/16"

  # VCN CIDR
  vcn_cidr = "10.0.0.0/16"

  # Subnet CIDRs
  public_subnet_cidr  = "10.0.0.0/24"
  private_subnet_cidr = "10.0.1.0/24"

  # Latest OKE compatible image
  latest_oke_image_id = [
    for source in data.oci_containerengine_node_pool_option.oke_node_pool_options.sources :
    source.image_id
    if can(regex(trimprefix(var.kubernetes_version, "v"), source.source_name)) && can(regex("aarch64", source.source_name))
  ][0]

  # Cluster kubeconfig
  kubeconfig = yamldecode(data.oci_containerengine_cluster_kube_config.oke_kubeconfig.content)

  # Cluster endpoint
  cluster_endpoint = local.kubeconfig["clusters"][0]["cluster"]["server"]

  # Cluster CA certificate
  cluster_ca_cert = base64decode(local.kubeconfig["clusters"][0]["cluster"]["certificate-authority-data"])
}