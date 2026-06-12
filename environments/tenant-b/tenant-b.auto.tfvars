org          = "schmhj"
region       = "us-ashburn-1"
cluster_name = "oke-prod-tenant-b"
vcn_cidr     = "10.2.0.0/16"

availability_domain = "mMVr:US-ASHBURN-1-AD-1"
kubernetes_version  = "v1.36.0"
node_shape          = "VM.Standard.A1.Flex"
node_port           = 30443

# ============================================================
# tenant-b has NO infra node — fully managed by tenant-a's ArgoCD.
# The infra pool is omitted from the OKE cluster entirely.
# ============================================================
create_infra_pool = false

# ============================================================
# Functional pool: 2 nodes, 2 OCPUs / 12 GB each
# ============================================================
workload_node_count        = 2
workload_node_ocpus        = 2
workload_node_memory_in_gb = 12

# Taint defaults are not used (no infra pool); uncomment to override
# if create_infra_pool is ever flipped back to true.
# infra_node_count             = 1
# infra_node_ocpus             = 1
# infra_node_memory_in_gb      = 8
# infra_node_taint_key         = "tier"
# infra_node_taint_value       = "infra"
# infra_node_taint_effect      = "NoSchedule"

# Network security - restrict NLB and API access to specific CIDR blocks
# For production, replace with specific office/VPN CIDR blocks
nlb_allowed_cidr_blocks = ["0.0.0.0/0"]

# Cross-tenant pod communication (optional, via DRG)
# Uncomment and set these to enable cross-tenant pod communication
# enable_drg = true
# drg_id = "ocid1.drg.oc1.iad..."  # Shared DRG ID
# peer_tenant_pods_cidr = "10.1.244.0/22"  # tenant-a pods CIDR

tags = {
  "environment" = "production"
  region        = "us-ashburn-1"
  tenant        = "tenant-b"
  managed_by    = "terraform"
}
