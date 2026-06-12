org          = "schmhj"
region       = "us-ashburn-1"
cluster_name = "oke-prod-tenant-a"
vcn_cidr     = "10.1.0.0/16"

availability_domain = "mMVr:US-ASHBURN-1-AD-1"
kubernetes_version  = "v1.36.0"
node_shape          = "VM.Standard.A1.Flex"
node_port           = 30443

# ============================================================
# Two-pool node layout
# Node 1 (infra):    1 OCPU  / 8 GB  — taint tier=infra:NoSchedule
# Node 2 (workload): 3 OCPUs / 16 GB — no taint
# ============================================================
infra_node_count        = 1
infra_node_ocpus        = 1
infra_node_memory_in_gb = 8

workload_node_count        = 1
workload_node_ocpus        = 3
workload_node_memory_in_gb = 16

# Taint defaults match the module; uncomment to override.
# infra_node_taint_key    = "tier"
# infra_node_taint_value  = "infra"
# infra_node_taint_effect = "NoSchedule"

# Network security - restrict NLB and API access to specific CIDR blocks
# For production, replace with specific office/VPN CIDR blocks
nlb_allowed_cidr_blocks = ["0.0.0.0/0"]

# Cross-tenant pod communication (optional, via DRG)
# Uncomment and set these to enable cross-tenant pod communication
# enable_drg = true
# drg_id = "ocid1.drg.oc1.iad..."  # Shared DRG ID
# peer_tenant_pods_cidr = "10.2.244.0/22"  # tenant-b pods CIDR

tags = {
  "environment" = "production"
  region        = "us-ashburn-1"
  tenant        = "tenant-a"
  managed_by    = "terraform"
}
