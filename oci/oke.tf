data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_containerengine_cluster_option" "oke_options" {
  cluster_option_id = "all"
  compartment_id      = var.compartment_id
}

data "oci_containerengine_node_pool_option" "oke_node_pool_options" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_id
}

# Fetch kubeconfig via dedicated data source
data "oci_containerengine_cluster_kube_config" "oke_kubeconfig" {
  cluster_id = oci_containerengine_cluster.oke.id
  token_version = "2.0.0"
}

data "oci_containerengine_node_pool" "oke_np" {
  node_pool_id = oci_containerengine_node_pool.workers.id
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

resource "oci_containerengine_node_pool" "workers" {
  cluster_id         = oci_containerengine_cluster.oke.id
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
    size = var.node_pool_size
  }
  
  node_shape = var.node_shape

  node_shape_config {
    memory_in_gbs = var.node_memory_gb
    ocpus         = var.node_ocpus
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

resource "local_file" "kubeconfig" {
  content         = data.oci_containerengine_cluster_kube_config.oke_kubeconfig.content
  filename        = pathexpand("~/.kube/oke-config")
  file_permission = "0600"
}