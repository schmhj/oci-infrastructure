region = "us-chicago-1"
cluster_name = "oke-prod-chicago"
vcn_cidr = "10.1.0.0/16"
availability_domain = "noZa:US-CHICAGO-1-AD-1"
kubernetes_version = "v1.32.10"
node_count = 2
node_memory_in_gb = 16
node_ocpus = 2
node_shape = "VM.Standard.A1.Flex"
node_port = 30443
tags = {
  "environment" = "production"
  region = "us-chicago-1"
  managed_by = "terraform"
}