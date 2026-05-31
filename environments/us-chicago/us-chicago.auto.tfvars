org = "schmhj"
region = "us-chicago-1"
cluster_name = "oke-prod-chicago"
vcn_cidr = "10.2.0.0/16"
availability_domain = "noZa:US-CHICAGO-1-AD-1"
kubernetes_version = "v1.36"
node_count = 2
node_memory_in_gb = 16
node_ocpus = 2
node_shape = "VM.Standard.A1.Flex"
node_port = 30443

# Network security - restrict NLB and API access to specific CIDR blocks
# For production, replace with specific office/VPN CIDR blocks
nlb_allowed_cidr_blocks = ["0.0.0.0/0"]

# Multi-region DRG configuration (optional)
# Uncomment and set these to enable cross-region pod communication
# enable_drg = true
# drg_id = "ocid1.drg.oc1.iad..."  # Shared DRG ID
# peer_region_pods_cidr = "10.1.244.0/22"  # Ashburn pods CIDR

tags = {
  "environment" = "production"
  region = "us-chicago-1"
  managed_by = "terraform"
}