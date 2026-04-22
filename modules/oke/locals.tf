locals {
  # Naming convention base
  base_name = "${var.org}-${var.region}"

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
  name_vcn       = "${local.prefixes.vcn}-${var.org}-${var.region}"
  name_vcn_dns   = "${local.prefixes.vcn}-${var.region}"
  name_snet_pub  = "${local.prefixes.snet_pub}-${var.org}-${var.region}"
  name_snet_priv = "${local.prefixes.snet_priv}-${var.org}-${var.region}"

  # OKE resources
  name_oke = "${local.prefixes.oke}-${var.org}-${var.region}"
  name_np  = "${local.prefixes.np}-${var.org}-${var.region}"
  name_nsg = "${local.prefixes.nsg}-${var.org}-${var.region}"

  # Load balancer
  name_nlb = "${local.prefixes.nlb}-${var.org}-${var.region}"

  # Kubernetes network configuration
  pods_cidr     = "10.244.0.0/16"
  services_cidr = "10.96.0.0/16"

  # VCN CIDR - compute subnet CIDRs from VCN CIDR
  # Extract VCN prefix (first two octets) to align subnets with VCN
  # Example: VCN 10.1.0.0/16 → subnets 10.1.0.0/24 and 10.1.1.0/24
  vcn_cidr_parts      = split(".", var.vcn_cidr)
  vcn_prefix          = "${local.vcn_cidr_parts[0]}.${local.vcn_cidr_parts[1]}"

  # Subnet CIDRs derived from VCN CIDR
  public_subnet_cidr  = "${local.vcn_prefix}.0.0/24"
  private_subnet_cidr = "${local.vcn_prefix}.1.0/24"

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
