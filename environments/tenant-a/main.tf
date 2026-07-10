module "oke" {
  source = "../../modules/oke"

  user_ocid           = var.user_ocid
  tenancy_ocid        = var.tenancy_ocid
  fingerprint         = var.fingerprint
  private_key         = var.private_key
  org                 = var.org
  environment         = var.environment
  compartment_id      = var.compartment_id
  cluster_name        = var.cluster_name
  region              = var.region
  kubernetes_version  = var.kubernetes_version
  vcn_cidr            = var.vcn_cidr
  availability_domain = var.availability_domain
  node_shape          = var.node_shape
  node_port           = var.node_port

  # Infra pool
  create_infra_pool       = var.create_infra_pool
  infra_node_count        = var.infra_node_count
  infra_node_ocpus        = var.infra_node_ocpus
  infra_node_memory_in_gb = var.infra_node_memory_in_gb
  infra_node_label_value  = var.infra_node_label_value
  infra_node_taint_key    = var.infra_node_taint_key
  infra_node_taint_value  = var.infra_node_taint_value
  infra_node_taint_effect = var.infra_node_taint_effect

  # Workload pool
  workload_node_count        = var.workload_node_count
  workload_node_ocpus        = var.workload_node_ocpus
  workload_node_memory_in_gb = var.workload_node_memory_in_gb
  workload_node_label_value  = var.workload_node_label_value

  tags                    = var.tags
  nlb_allowed_cidr_blocks = var.nlb_allowed_cidr_blocks

  # VCN Peering (acceptor side — creates LPG, does NOT initiate connection)
  enable_vcn_peering = var.enable_vcn_peering
  peer_vcn_cidr      = var.peer_vcn_cidr
}
