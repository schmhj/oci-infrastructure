# IAM setup for tenant-a (acceptor)
# Creates a group for LPG admins and the cross-tenancy policy
# Reads tenant-b's group OCID via terraform_remote_state

terraform {
  required_version = ">= 1.5"

  cloud {
    organization = "schmhj"
    workspaces {
      name = "iam-tenant-a"
    }
  }
}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.fingerprint
  private_key  = var.private_key
  region       = var.region
}

# ============================================================
# Read tenant-b's IAM state to get the group OCID
# ============================================================

variable "tfc_organization" {
  description = "Terraform Cloud organization name"
  type        = string
  default     = "schmhj"
}

variable "tfc_workspace_tenant_b" {
  description = "TFC workspace name for tenant-b IAM"
  type        = string
  default     = "iam-tenant-b"
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

# The admin user's OCID in THIS tenancy (tenant-a)
variable "admin_user_ocid" {
  type = string
}

# Requestor tenancy details (tenant-b)
variable "requestor_tenancy_ocid" {
  description = "OCID of the requestor tenancy (tenant-b)"
  type        = string
}

# ============================================================
# Read tenant-b's group OCID via terraform_remote_state
# ============================================================
data "terraform_remote_state" "tenant_b" {
  backend = "remote"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = var.tfc_workspace_tenant_b
    }
  }
}

# ============================================================
# Group for local LPG management
# ============================================================
resource "oci_identity_group" "lpg_admins" {
  compartment_id = var.tenancy_ocid
  description    = "Group for managing Local Peering Gateways"
  name           = "lpg-admins"
}

# Add admin user to the group
resource "oci_identity_user_group_membership" "admin_membership" {
  user_id  = var.admin_user_ocid
  group_id = oci_identity_group.lpg_admins.id
}

# ============================================================
# Cross-tenancy policy: admit requestor group to manage LPGs
# Uses remote state to get tenant-b's group OCID
# ============================================================
resource "oci_identity_policy" "admit_requestor_lpg" {
  compartment_id = var.tenancy_ocid
  description    = "Allow requestor tenancy to manage LPGs for cross-tenancy peering"
  name           = "admit-requestor-lpg-peering"

  statements = [
    "Define tenancy Requestor as ${var.requestor_tenancy_ocid}",
    "Define group requestor-admins as ${data.terraform_remote_state.tenant_b.outputs.lpg_admins_group_ocid}",
    "Admit group requestor-admins of tenancy Requestor to manage local-peering-to in tenancy",
    "Admit group requestor-admins of tenancy Requestor to manage local-peering-from in tenancy",
  ]
}

# ============================================================
# Outputs
# ============================================================
output "lpg_admins_group_ocid" {
  value = oci_identity_group.lpg_admins.id
}
