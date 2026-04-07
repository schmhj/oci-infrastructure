variable "region" {
  type        = string
  description = "OCI region"
  default     = "us-ashburn-1"
}

variable "project" {
  type        = string
  description = "Project name prefix"
}

variable "env" {
  type        = string
  description = "Environment"
  default     = "prod"
}

variable "user_ocid" {
  type        = string
  description = "OCI user OCID for RBAC setup"
}

variable "node_port" {
  type        = number
  description = "NodePort for ArgoCD service"
  default     = 30443
}
