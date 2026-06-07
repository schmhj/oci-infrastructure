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

  # Infra pool (vars passed as null when create_infra_pool = false so the
  # module silently uses its own defaults; the resource itself is gated
  # on create_infra_pool inside the module).
  create_infra_pool       = var.create_infra_pool
  infra_node_count        = var.create_infra_pool ? var.infra_node_count : null
  infra_node_ocpus        = var.create_infra_pool ? var.infra_node_ocpus : null
  infra_node_memory_in_gb = var.create_infra_pool ? var.infra_node_memory_in_gb : null
  infra_node_label_value  = var.create_infra_pool ? var.infra_node_label_value : null
  infra_node_taint_key    = var.create_infra_pool ? var.infra_node_taint_key : null
  infra_node_taint_value  = var.create_infra_pool ? var.infra_node_taint_value : null
  infra_node_taint_effect = var.create_infra_pool ? var.infra_node_taint_effect : null

  # Workload pool
  workload_node_count        = var.workload_node_count
  workload_node_ocpus        = var.workload_node_ocpus
  workload_node_memory_in_gb = var.workload_node_memory_in_gb
  workload_node_label_value  = var.workload_node_label_value

  tags                    = var.tags
  nlb_allowed_cidr_blocks = var.nlb_allowed_cidr_blocks
}
