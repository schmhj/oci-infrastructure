# TFC variables for OKE module
variable "org" {
  description = "The organisation value"
  type        = string
}

variable "environment" {
  description = "The deployment environment (development, production)"
  type        = string
}


# Github Environment variables for OKE module
variable "tenancy_ocid" {
  type = string
}

variable "user_ocid" {
  type = string
}

variable "fingerprint" {
  type = string
}

variable "private_key" {
  type      = string
  sensitive = true
}

variable "compartment_id" {
  description = "The OCID of the compartment where the resources will be created."
  type        = string
}

variable "region" {
  description = "The region where the resources will be created."
  type        = string
}


# Region-specific variables for OKE module
variable "cluster_name" {
  description = "The name of the Kubernetes cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "The version of Kubernetes to use for the cluster."
  type        = string
}

variable "vcn_cidr" {
  description = "The CIDR block for the VCN."
  type        = string
}

variable "pods_cidr" {
  description = "CIDR block for Kubernetes pods. Must not overlap with the peer VCN's pod CIDR when VCN peering is enabled."
  type        = string
  default     = "10.244.0.0/16"
}

variable "availability_domain" {
  description = "The availability domain where the cluster will be created."
  type        = string
}

variable "node_shape" {
  description = "The shape of the compute instances for both node pools."
  type        = string
  default     = "VM.Standard.A1.Flex"
}

# ============================================================
# Infra node pool (Node 1) — small, tained, hosts infrastructure apps
# ============================================================
variable "infra_node_count" {
  description = "Number of nodes in the infra node pool."
  type        = number
  default     = 1
}

variable "create_infra_pool" {
  description = "Whether to create the infra node pool. Set to false for clusters that only run workload apps (e.g., tenant-b). When false, the infra pool resource, its data source, the infra NLB backends, and the taint step are all skipped."
  type        = bool
  default     = true
}

variable "infra_node_ocpus" {
  description = "OCPUs per infra node."
  type        = number
  default     = 1
}

variable "infra_node_memory_in_gb" {
  description = "Memory (GB) per infra node."
  type        = number
  default     = 8
}

variable "infra_node_label_value" {
  description = "Value of the tier= label applied to infra nodes."
  type        = string
  default     = "infra"
}

variable "infra_node_taint_key" {
  description = "Taint key applied to infra nodes to repel workload apps."
  type        = string
  default     = "tier"
}

variable "infra_node_taint_value" {
  description = "Taint value applied to infra nodes."
  type        = string
  default     = "infra"
}

variable "infra_node_taint_effect" {
  description = "Taint effect on infra nodes (NoSchedule, PreferNoSchedule, NoExecute)."
  type        = string
  default     = "NoSchedule"

  validation {
    # Null is allowed because callers (e.g., tenant-b) pass null when
    # create_infra_pool = false; the value is unused in that case.
    # `contains` rejects null arguments in Terraform 1.5+, hence the guard.
    condition     = var.infra_node_taint_effect == null || contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], var.infra_node_taint_effect)
    error_message = "infra_node_taint_effect must be one of: NoSchedule, PreferNoSchedule, NoExecute."
  }
}

# ============================================================
# Workload node pool (Node 2) — larger, hosts business/workload apps
# ============================================================
variable "workload_node_count" {
  description = "Number of nodes in the workload node pool."
  type        = number
  default     = 1
}

variable "workload_node_ocpus" {
  description = "OCPUs per workload node."
  type        = number
  default     = 3
}

variable "workload_node_memory_in_gb" {
  description = "Memory (GB) per workload node."
  type        = number
  default     = 16
}

variable "workload_node_label_value" {
  description = "Value of the tier= label applied to workload nodes. Workload apps nodeSelector this value."
  type        = string
  default     = "workload"
}

variable "node_port" {
  description = "The node port exposed to the nbl"
  type        = number
  default     = 30443
}

# Network security variables
variable "nlb_allowed_cidr_blocks" {
  description = "CIDR blocks allowed for NLB ingress (TCP 443, 6443). REQUIRED - secure by default."
  type        = list(string)
  validation {
    condition     = length(var.nlb_allowed_cidr_blocks) > 0
    error_message = "nlb_allowed_cidr_blocks must contain at least one CIDR block. Use [\"0.0.0.0/0\"] to allow all traffic (not recommended for production)."
  }
}

variable "enable_strict_egress" {
  description = "Enable strict egress filtering (only allowed destinations instead of 0.0.0.0/0)"
  type        = bool
  default     = false
}

variable "allowed_egress_cidrs" {
  description = "CIDR blocks allowed for egress when enable_strict_egress is true"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# VCN Peering variables (cross-tenancy LPG)
variable "enable_vcn_peering" {
  description = "Enable Local Peering Gateway for cross-tenancy VCN peering (same region, free tier)"
  type        = bool
  default     = false
}

variable "peer_lpg_ocid" {
  description = "OCID of the peer's Local Peering Gateway. Required on the requestor side when enable_vcn_peering = true."
  type        = string
  default     = null
}

variable "peer_vcn_cidr" {
  description = "CIDR block of the peer VCN for routing (e.g., '10.1.0.0/16'). Required when enable_vcn_peering = true."
  type        = string
  default     = null
}

variable "peer_tenancy_id" {
  description = "OCID of the peer tenancy. Required for cross-tenancy peering when enable_vcn_peering = true."
  type        = string
  default     = null
}

# Multi-region networking variables
variable "enable_drg" {
  description = "Enable Dynamic Routing Gateway for inter-region peering"
  type        = bool
  default     = false
}

variable "drg_id" {
  description = "DRG ID for inter-region connectivity (required if enable_drg = true)"
  type        = string
  default     = null
}

variable "peer_region_pods_cidr" {
  description = "Pod CIDR of peer region for DRG routing (e.g., '10.2.244.0/22' for Chicago pods when in Ashburn)"
  type        = string
  default     = null
}

# Custom routing variables
variable "internet_gateway_route_rules" {
  description = "Custom routes for internet gateway route table (for DRG, hybrid, or custom routing)"
  type = list(object({
    destination       = string
    destination_type  = string
    network_entity_id = string
  }))
  default = []
}

variable "nat_gateway_route_rules" {
  description = "Custom routes for NAT gateway route table (for DRG, hybrid, or custom routing)"
  type = list(object({
    destination       = string
    destination_type  = string
    network_entity_id = string
  }))
  default = []
}

variable "tags" {
  description = "A map of tags to apply to the resources."
  type        = map(string)
  default     = {}
}
