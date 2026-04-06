terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
      version = ">= 4.41.0, <= 6.18.0"
    }
  }
}

provider "oci" {
  region = var.region
  config_file_profile = "DEFAULT"
}

locals {
  base_name = "${var.project}-${var.env}-${var.region}"

  prefixes = {
    vcn      = "vcn"
    snet_pub = "snet-pub"
    snet_priv= "snet-priv"
    oke      = "oke"
    np       = "np"
    nsg      = "nsg"
    nlb      = "nlb"
    repo     = "container-repo"
  }

  name_vcn      = "${local.prefixes.vcn}-${var.project}-${var.env}-${var.region}"
  name_vcn_dns  = "${local.prefixes.vcn}-${var.project}-${var.env}"
  name_snet_pub = "${local.prefixes.snet_pub}-${var.project}-${var.env}-${var.region}"
  name_snet_priv= "${local.prefixes.snet_priv}-${var.project}-${var.env}-${var.region}"
  name_oke      = "${local.prefixes.oke}-${var.project}-${var.env}-${var.region}"
  name_np       = "${local.prefixes.np}-${var.project}-${var.env}-${var.region}"
  name_nsg      = "${local.prefixes.nsg}-${var.project}-${var.env}-${var.region}"
  name_nlb      = "${local.prefixes.nlb}-${var.project}-${var.env}-${var.region}"
  name_repo     = "${local.prefixes.repo}-${var.project}-${var.env}-${var.region}"
}

module "vcn" {
  source  = "oracle-terraform-modules/vcn/oci"
  version = "3.6.0"

  compartment_id = var.compartment_id
  region         = var.region

  internet_gateway_route_rules = null
  local_peering_gateways       = null
  nat_gateway_route_rules      = null

  vcn_name      = local.name_vcn
  vcn_dns_label = lower(replace(local.name_vcn_dns, "-", ""))
  vcn_cidrs     = ["10.0.0.0/16"]

  create_internet_gateway = true
  create_nat_gateway      = true
  create_service_gateway  = true
}

resource "oci_core_security_list" "private_subnet_sl" {
  compartment_id = var.compartment_id
  vcn_id         = module.vcn.vcn_id

  display_name = "${local.name_nsg}-private-subnet-sl"

  egress_security_rules {
    stateless        = false
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }
  
  ingress_security_rules {
    stateless   = false
    source      = "10.0.0.0/16"
    source_type = "CIDR_BLOCK"
    protocol    = "all"
  }

  ingress_security_rules {
    stateless   = false
    source      = "10.0.0.0/24"
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    tcp_options {
      min = 10256
      max = 10256
    }
  }

  ingress_security_rules {
    stateless   = false
    source      = "10.0.0.0/24"
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    tcp_options {
      min = 30443
      max = 30443
    }
  }
}

resource "oci_core_security_list" "public_subnet_sl" {
  compartment_id = var.compartment_id
  vcn_id         = module.vcn.vcn_id

  display_name = "${local.name_nsg}-public-subnet-sl"

  egress_security_rules {
    stateless        = false
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }

  egress_security_rules {
    stateless        = false
    destination      = "10.0.1.0/24"
    destination_type = "CIDR_BLOCK"
    protocol         = "6"
    tcp_options {
      min = 30443
      max = 30443
    }
  }

  egress_security_rules {
    stateless        = false
    destination      = "10.0.1.0/24"
    destination_type = "CIDR_BLOCK"
    protocol         = "6"
    tcp_options {
      min = 10256
      max = 10256
    }
  }

  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false

    tcp_options {
      max = 443
      min = 443
    }
  } 

  ingress_security_rules {
    stateless   = false
    source      = "10.0.0.0/16"
    source_type = "CIDR_BLOCK"
    protocol    = "all"
  }

  ingress_security_rules {
    stateless   = false
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    tcp_options {
      min = 6443
      max = 6443
    }
  }
}

resource "oci_core_subnet" "vcn_private_subnet" {
  compartment_id = var.compartment_id
  vcn_id         = module.vcn.vcn_id
  cidr_block     = "10.0.1.0/24"

  route_table_id             = module.vcn.nat_route_id
  security_list_ids          = [oci_core_security_list.private_subnet_sl.id]
  display_name               = local.name_snet_priv
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_subnet" "vcn_public_subnet" {
  compartment_id = var.compartment_id
  vcn_id         = module.vcn.vcn_id
  cidr_block     = "10.0.0.0/24"

  route_table_id    = module.vcn.ig_route_id
  security_list_ids = [oci_core_security_list.public_subnet_sl.id]
  display_name      = local.name_snet_pub
}

resource "oci_containerengine_cluster" "k8s_cluster" {
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = local.name_oke
  vcn_id             = module.vcn.vcn_id

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = oci_core_subnet.vcn_public_subnet.id
  }

  options {
    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }
    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
    service_lb_subnet_ids = [oci_core_subnet.vcn_public_subnet.id]
  }
}

data "oci_containerengine_node_pool_option" "oke_node_pool_options" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_id
}

locals {
  latest_oke_image_id = [
    for source in data.oci_containerengine_node_pool_option.oke_node_pool_options.sources :
    source.image_id
    if can(regex(trimprefix(var.kubernetes_version, "v"), source.source_name)) && can(regex("aarch64", source.source_name))
  ][0]
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

resource "oci_containerengine_node_pool" "k8s_node_pool" {
  cluster_id         = oci_containerengine_cluster.k8s_cluster.id
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = local.name_np
  node_config_details {
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = oci_core_subnet.vcn_private_subnet.id
    }
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[1].name
      subnet_id           = oci_core_subnet.vcn_private_subnet.id
    }
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[2].name
      subnet_id           = oci_core_subnet.vcn_private_subnet.id
    }
    size = 2
  }
  
  node_shape = "VM.Standard.A1.Flex"

  node_shape_config {
    memory_in_gbs = 12
    ocpus         = 2
  }

  node_source_details {
    image_id    = local.latest_oke_image_id
    source_type = "image"
  }

  initial_node_labels {
    key   = "name"
    value = local.name_oke
  }

}
