variable "compartment_id" {
  type        = string
  description = "The compartment to create the resources in"
}

variable "region" {
  type        = string
  description = "The region to provision the resources in"
}

variable "project" {
  type        = string
  description = "Project short name to use in resource names (kebab-case)"
}

variable "env" {
  type        = string
  description = "Environment name to use in resource names (kebab-case, e.g. dev, staging, prod)"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version"
  default     = "v1.31.10"
}

variable "allow_destroy" {
  type        = string
  description = "allow destory flag"
  default     = "false"
}

variable "tenancy_ocid" {
  type        = string
  description = "OCI tenancy OCID (used for remote runs)"
  default     = ""
}

variable "user_ocid" {
  type        = string
  description = "OCI user OCID (used for remote runs)"
  default     = ""
}

variable "fingerprint" {
  type        = string
  description = "OCI API key fingerprint (used for remote runs)"
  default     = ""
}

variable "private_key" {
  type        = string
  description = "OCI API private key contents (PEM) - set as sensitive in remote workspace"
  default     = ""
}

variable "oci_config_profile" {
  type        = string
  description = "Optional OCI config profile name (falls back to DEFAULT)"
  default     = ""
}