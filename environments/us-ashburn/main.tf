module "oke" {
  source = "../../modules/oke"
  
  org = var.org
  environment = var.environment
  compartment_id = var.compartment_id
  cluster_name   = var.cluster_name
  region = var.region
  kubernetes_version = var.kubernetes_version
  vcn_cidr = var.vcn_cidr
  availability_domain = var.availability_domain
  node_shape = var.node_shape 
  node_count = var.node_count
  node_ocpus = var.node_ocpus
  node_memory_in_gb = var.node_memory_in_gb
  node_port = var.node_port
  tags = var.tags
}
