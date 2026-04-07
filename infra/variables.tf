variable "project" {
    type = string
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

variable "region" {
  type    = string
  default = "us-ashburn-1"
}

variable "compartment_id" {
  type = string
}

# --- Cluster Configuration ---
variable "cluster_name" {
  type    = string
  default = "oke-cluster"
}

variable "kubernetes_version" {
  type    = string
  default = "v1.31.10"
}

variable "env" {
  type    = string
  default = "prod"
}

# --- Node Pool Configuration ---
variable "node_shape" {
  type    = string
  default = "VM.Standard.A1.Flex"
}

variable "node_ocpus" {
  type    = number
  default = 2
}

variable "node_memory_gb" {
  type    = number
  default = 16
}

variable "node_pool_size" {
  type    = number
  default = 2
}

variable "node_port" {
  type = number
  default = 30443
}