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

variable "public_subnet_id" {
  type = string
  description = "The public subnet's OCID"
}

variable "node_pool_id" {
  type = string
  description = "The OCID of the Node Pool where the compute instances reside"
}