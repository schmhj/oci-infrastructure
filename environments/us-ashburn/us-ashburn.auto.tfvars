org = "schmhj"
region = "us-ashburn-1"
cluster_name = "oke-prod-ashburn"
vcn_cidr = "10.0.0.0/16"
availability_domain = "mMVr:US-ASHBURN-1-AD-1"
kubernetes_version = "v1.32.10"
node_count = 2
node_memory_in_gb = 16
node_ocpus = 2
node_shape = "VM.Standard.A1.Flex"
node_port = 30443
tags = {
  "environment" = "production"
  region = "us-ashburn-1"
  managed_by = "terraform"
}