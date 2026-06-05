variable "org" {
  description = "The organisation value"
  type = string
}

variable "environment" {
  description = "The deployment environment (development, production)"
  type = string
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
  description = "The shape of the compute instances for the cluster nodes."
  type        = string
  default = "VM.Standard.A1.Flex"
}

variable "node_count" {
  description = "The number of nodes in the cluster."
  type        = number
  default     = 2 
}

variable "node_ocpus" {
  description = "The number of OCPUs for each node."
  type        = number
}

variable "node_memory_in_gb" {
  description = "The amount of memory in GBs for each node."
  type        = number
  default = 16
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