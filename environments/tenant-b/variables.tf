variable "org" {
  description = "The organisation value"
  type        = string
}

variable "environment" {
  description = "The deployment environment (development, production)"
  type        = string
}

variable "compartment_id" {
  description = "The OCID of the compartment where the resources will be created."
  type        = string
}

variable "region" {
  description = "The region where the resources will be created."
  type        = string
}

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

variable "availability_domain" {
  description = "The availability domain where the cluster will be created."
  type        = string
}

variable "node_shape" {
  description = "The shape of the compute instances for both node pools."
  type        = string
  default     = "VM.Standard.A1.Flex"
}

# Infra pool (Node 1)
variable "infra_node_count" {
  description = "Number of nodes in the infra node pool."
  type        = number
  default     = 1
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
  description = "Value of the workload= label applied to infra nodes."
  type        = string
  default     = "infra"
}

variable "infra_node_taint_key" {
  description = "Taint key applied to infra nodes to repel functional apps."
  type        = string
  default     = "workload"
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
}

# Functional pool (Node 2)
variable "functional_node_count" {
  description = "Number of nodes in the functional node pool."
  type        = number
  default     = 1
}

variable "functional_node_ocpus" {
  description = "OCPUs per functional node."
  type        = number
  default     = 3
}

variable "functional_node_memory_in_gb" {
  description = "Memory (GB) per functional node."
  type        = number
  default     = 16
}

variable "functional_node_label_value" {
  description = "Value of the workload= label applied to functional nodes."
  type        = string
  default     = "functional"
}

variable "node_port" {
  description = "The node port exposed to the nbl"
  type        = number
  default     = 30443
}

variable "tags" {
  description = "A map of tags to apply to the resources."
  type        = map(string)
  default     = {}
}

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

variable "nlb_allowed_cidr_blocks" {
  description = "CIDR blocks allowed for NLB ingress (TCP 443, 6443). REQUIRED - secure by default."
  type        = list(string)
  validation {
    condition     = length(var.nlb_allowed_cidr_blocks) > 0
    error_message = "nlb_allowed_cidr_blocks must contain at least one CIDR block. Use [\"0.0.0.0/0\"] to allow all traffic (not recommended for production)."
  }
}
