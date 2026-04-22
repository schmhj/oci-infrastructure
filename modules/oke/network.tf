module "vcn" {
  source  = "oracle-terraform-modules/vcn/oci"
  version = "3.6.0"

  compartment_id = var.compartment_id
  region         = var.region

  internet_gateway_route_rules = var.internet_gateway_route_rules
  local_peering_gateways       = null  # DRG used instead for multi-region
  nat_gateway_route_rules      = var.nat_gateway_route_rules

  vcn_name      = local.name_vcn
  vcn_dns_label = lower(replace(local.name_vcn_dns, "-", ""))
  vcn_cidrs     = [var.vcn_cidr]

  create_internet_gateway = true
  create_nat_gateway      = true
  create_service_gateway  = true
}

# Dynamic Routing Gateway (DRG) - Optional multi-region connectivity
resource "oci_core_drg_attachment" "vcn_attachment" {
  count         = var.enable_drg ? 1 : 0
  drg_id        = var.drg_id
  vcn_id        = module.vcn.vcn_id
  display_name  = "${local.name_vcn}-drg-attachment"
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
    source      = var.vcn_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "all"
  }

  ingress_security_rules {
    stateless   = false
    source      = local.public_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    tcp_options {
      min = 10256
      max = 10256
    }
  }

  ingress_security_rules {
    stateless   = false
    source      = local.public_subnet_cidr
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

  # Egress rules
  egress_security_rules {
    stateless        = false
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }

  egress_security_rules {
    stateless        = false
    destination      = local.private_subnet_cidr
    destination_type = "CIDR_BLOCK"
    protocol         = "6"
    tcp_options {
      min = 30443
      max = 30443
    }
  }

  egress_security_rules {
    stateless        = false
    destination      = local.private_subnet_cidr
    destination_type = "CIDR_BLOCK"
    protocol         = "6"
    tcp_options {
      min = 10256
      max = 10256
    }
  }

  # Ingress rules - HTTPS (443) from allowed CIDR blocks
  dynamic "ingress_security_rules" {
    for_each = var.nlb_allowed_cidr_blocks
    content {
      protocol    = "6"
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"
      stateless   = false

      tcp_options {
        max = 443
        min = 443
      }
    }
  }

  # Ingress rule - Full VCN access
  ingress_security_rules {
    stateless   = false
    source      = var.vcn_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "all"
  }

  # Ingress rules - Kubernetes API (6443) from allowed CIDR blocks
  dynamic "ingress_security_rules" {
    for_each = var.nlb_allowed_cidr_blocks
    content {
      stateless   = false
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"
      protocol    = "6"
      tcp_options {
        min = 6443
        max = 6443
      }
    }
  }
}

resource "oci_core_subnet" "vcn_private_subnet" {
  compartment_id = var.compartment_id
  vcn_id         = module.vcn.vcn_id
  cidr_block     = local.private_subnet_cidr

  route_table_id             = module.vcn.nat_route_id
  security_list_ids          = [oci_core_security_list.private_subnet_sl.id]
  display_name               = local.name_snet_priv
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_subnet" "vcn_public_subnet" {
  compartment_id = var.compartment_id
  vcn_id         = module.vcn.vcn_id
  cidr_block     = local.public_subnet_cidr

  route_table_id    = module.vcn.ig_route_id
  security_list_ids = [oci_core_security_list.public_subnet_sl.id]
  display_name      = local.name_snet_pub
}
