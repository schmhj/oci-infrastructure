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