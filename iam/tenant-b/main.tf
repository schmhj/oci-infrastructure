# IAM setup for tenant-b (requestor)
# Creates a group for LPG admins and the cross-tenancy policy

terraform {
  required_version = ">= 1.5"

  cloud {
    organization = "schmhj"
    workspaces {
      name = "iam-tenant-b"
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

# The admin user's OCID in THIS tenancy (tenant-b)
variable "admin_user_ocid" {
  type = string
}

# Acceptor tenancy details (tenant-a)
variable "acceptor_tenancy_ocid" {
  description = "OCID of the acceptor tenancy (tenant-a)"
  type        = string
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
# Cross-tenancy policy: endorse group to manage LPGs in acceptor
# ============================================================
resource "oci_identity_policy" "endorse_lpg_peering" {
  compartment_id = var.tenancy_ocid
  description    = "Endorse group to manage LPGs in acceptor tenancy for cross-tenancy peering"
  name           = "endorse-lpg-peering"

  statements = [
    "Define tenancy Acceptor as ${var.acceptor_tenancy_ocid}",
    "Endorse group ${oci_identity_group.lpg_admins.name} to manage local-peering-to in tenancy Acceptor",
    "Endorse group ${oci_identity_group.lpg_admins.name} to manage local-peering-from in tenancy Acceptor",
  ]
}

# ============================================================
# Outputs
# ============================================================
output "lpg_admins_group_ocid" {
  value = oci_identity_group.lpg_admins.id
}

output "lpg_admins_group_name" {
  value = oci_identity_group.lpg_admins.name
}
