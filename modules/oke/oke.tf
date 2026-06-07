data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_containerengine_cluster_option" "oke_options" {
  cluster_option_id = "all"
  compartment_id    = var.compartment_id
}

data "oci_containerengine_node_pool_option" "oke_node_pool_options" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_id
}

# Fetch kubeconfig via dedicated data source (used by k8s/ stage to extract endpoint and CA)
data "oci_containerengine_cluster_kube_config" "oke_kubeconfig" {
  cluster_id    = oci_containerengine_cluster.oke.id
  token_version = "2.0.0"
}

# Per-pool data sources: one node each, queried by index [0].
# Used by NLB and the CI taint step. The infra data source is skipped
# when create_infra_pool = false.
data "oci_containerengine_node_pool" "np_infra" {
  count        = var.create_infra_pool ? 1 : 0
  node_pool_id = oci_containerengine_node_pool.infra[0].id
}

data "oci_containerengine_node_pool" "np_workload" {
  node_pool_id = oci_containerengine_node_pool.workload.id
}

resource "oci_containerengine_cluster" "oke" {
  compartment_id     = var.compartment_id
  name               = local.name_oke
  kubernetes_version = var.kubernetes_version
  vcn_id             = module.vcn.vcn_id

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = oci_core_subnet.vcn_public_subnet.id
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.vcn_public_subnet.id]

    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }

    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
  }
}

# ============================================================
# Infra node pool (Node 1)
# - Small (1 OCPU / 8 GB by default)
# - Label tier=<infra_node_label_value> (default: infra)
# - Taint applied post-provisioning (OCI API does not support
#   taints at node-pool creation time)
# ============================================================
resource "oci_containerengine_node_pool" "infra" {
  count              = var.create_infra_pool ? 1 : 0
  cluster_id         = oci_containerengine_cluster.oke.id
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = "${local.name_np}-infra"
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
    size = var.infra_node_count
  }

  node_shape = var.node_shape

  node_shape_config {
    memory_in_gbs = var.infra_node_memory_in_gb
    ocpus         = var.infra_node_ocpus
  }

  node_source_details {
    image_id    = local.latest_oke_image_id
    source_type = "image"
  }

  initial_node_labels {
    key   = "name"
    value = local.name_oke
  }

  initial_node_labels {
    key   = "tier"
    value = var.infra_node_label_value
  }
}

# ============================================================
# Workload node pool (Node 2)
# - Larger (3 OCPUs / 16 GB by default)
# - Label tier=<workload_node_label_value> (default: workload)
# - No taint; workload apps nodeSelector this label
# ============================================================
resource "oci_containerengine_node_pool" "workload" {
  cluster_id         = oci_containerengine_cluster.oke.id
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = "${local.name_np}-workload"
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
    size = var.workload_node_count
  }

  node_shape = var.node_shape

  node_shape_config {
    memory_in_gbs = var.workload_node_memory_in_gb
    ocpus         = var.workload_node_ocpus
  }

  node_source_details {
    image_id    = local.latest_oke_image_id
    source_type = "image"
  }

  initial_node_labels {
    key   = "name"
    value = local.name_oke
  }

  initial_node_labels {
    key   = "tier"
    value = var.workload_node_label_value
  }
}

# State migration: rename the pool from `functional` to `workload` without
# destroying/recreating it. Terraform 1.1+ records the rename in state on
# the next plan/apply. Remove these blocks after the first successful apply.
moved {
  from = oci_containerengine_node_pool.functional
  to   = oci_containerengine_node_pool.workload
}

moved {
  from = data.oci_containerengine_node_pool.np_functional
  to   = data.oci_containerengine_node_pool.np_workload
}
