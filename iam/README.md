# IAM Setup for Cross-Tenancy VCN Peering

This directory contains Terraform configurations for creating the IAM groups and policies required for cross-tenancy LPG peering between tenant-a and tenant-b.

Tenant-a reads tenant-b's group OCID automatically via `terraform_remote_state` — no manual OCID passing required.

## Architecture

```
┌─────────────────────────────────────┐         ┌─────────────────────────────────────┐
│  TENANT-A (Acceptor)                │         │  TENANT-B (Requestor)               │
│                                     │         │                                     │
│  Group: lpg-admins                  │         │  Group: lpg-admins                  │
│  ├── admin-user                     │         │  ├── admin-user                     │
│                                     │         │                                     │
│  Policy: admit-requestor-lpg        │         │  Policy: endorse-lpg-peering        │
│  └── Admit tenant-b's group to      │         │  └── Endorse group to manage LPGs   │
│      manage LPGs in tenant-a        │         │      in tenant-a                    │
│                                     │         │                                     │
│  Reads group OCID via ──────────────┼────────►│  Outputs lpg_admins_group_ocid      │
│  terraform_remote_state             │         │                                     │
└─────────────────────────────────────┘         └─────────────────────────────────────┘
```

## Prerequisites

1. Terraform >= 1.5
2. OCI provider configured with admin credentials for each tenancy
3. Your user OCID from each tenancy (available in OCI Console → Identity → Users)
4. Terraform Cloud accounts in the `schmhj` organization (or update `tfc_organization`)

## TFC Workspace Setup

### 1. Create Workspaces

Create two workspaces in Terraform Cloud:

| Workspace | Purpose |
|-----------|---------|
| `iam-tenant-b` | tenant-b IAM |
| `iam-tenant-a` | tenant-a IAM |

### 2. Set Workspace Variables

All sensitive values must be set as **TFC workspace variables** (not in `.auto.tfvars` files which are committed to git). Mark sensitive values as **sensitive** in the TFC UI.

#### iam-tenant-b Required Variables

| Variable | Description | Sensitive |
|----------|-------------|-----------|
| `tenancy_ocid` | tenant-b's tenancy OCID | No |
| `user_ocid` | Your user OCID in tenant-b | No |
| `fingerprint` | Your API key fingerprint | No |
| `private_key` | Your private key (PEM format) | Yes |
| `region` | OCI region (default: `us-ashburn-1`) | No |
| `admin_user_ocid` | Your user OCID in tenant-b | No |
| `acceptor_tenancy_ocid` | tenant-a's tenancy OCID | No |

#### iam-tenant-a Required Variables

| Variable | Description | Sensitive |
|----------|-------------|-----------|
| `tenancy_ocid` | tenant-a's tenancy OCID | No |
| `user_ocid` | Your user OCID in tenant-a | No |
| `fingerprint` | Your API key fingerprint | No |
| `private_key` | Your private key (PEM format) | Yes |
| `region` | OCI region (default: `us-ashburn-1`) | No |
| `admin_user_ocid` | Your user OCID in tenant-a | No |
| `requestor_tenancy_ocid` | tenant-b's tenancy OCID | No |
| `tfc_organization` | TFC org name (default: `schmhj`) | No |
| `tfc_workspace_tenant_b` | TFC workspace for tenant-b (default: `iam-tenant-b`) | No |

Note: `requestor_group_ocid` is **not required** — it's read automatically from tenant-b's workspace via `terraform_remote_state`.

## How to Find Your OCIDs

### Tenancy OCID
OCI Console → Administration → Tenancy Details → OCID

### User OCID
OCI Console → Identity → Users → click your user → OCID

### Group OCID
Automatically read from tenant-b's workspace — no manual input needed.

## Deployment Steps

### Step 1: Deploy tenant-b IAM first (requestor)

Tenant-b's policy uses `endorse` with the local group name, so it can be deployed first.

```bash
cd iam/tenant-b
terraform init
terraform plan -input=false
terraform apply -auto-approve -input=false
```

### Step 2: Deploy tenant-a IAM (acceptor)

Tenant-a reads tenant-b's group OCID automatically via `terraform_remote_state`.

```bash
cd iam/tenant-a
terraform init
terraform plan -input=false
terraform apply -auto-approve -input=false
```

### Step 3: Deploy VCN Peering

After IAM is set up, deploy the networking:

```bash
# Deploy tenant-a VCN
cd environments/tenant-a
terraform init && terraform apply -auto-approve -input=false

# Capture LPG OCID
terraform output lpg_ocid

# Deploy tenant-b VCN (set peer_lpg_ocid in TFC workspace)
cd environments/tenant-b
terraform init && terraform apply -auto-approve -input=false
```

## What Gets Created

### Per Tenancy
- **Group**: `lpg-admins` — for managing LPGs
- **Membership**: Your admin user added to the group
- **Policy**: Cross-tenancy policy for LPG peering

### Policy Details

**tenant-a (acceptor):**
```
Define tenancy Requestor as <tenant-b-tenancy-ocid>
Define group requestor-admins as <tenant-b-group-ocid-from-remote-state>
Admit group requestor-admins of tenancy Requestor to manage local-peering-to in tenancy
Admit group requestor-admins of tenancy Requestor to manage local-peering-from in tenancy
```

**tenant-b (requestor):**
```
Define tenancy Acceptor as <tenant-a-tenancy-ocid>
Endorse group lpg-admins to manage local-peering-to in tenancy Acceptor
Endorse group lpg-admins to manage local-peering-from in tenancy Acceptor
```

## Cleanup

To remove all IAM resources:

```bash
# Destroy tenant-a IAM first (has dependency on tenant-b)
cd iam/tenant-a && terraform destroy -auto-approve -input=false

# Then destroy tenant-b IAM
cd iam/tenant-b && terraform destroy -auto-approve -input=false
```

## Troubleshooting

### "NotAuthorizedOrNotFound" error during LPG peering

1. Verify both policies exist in the correct tenancies
2. Verify policies are attached to the **tenancy root compartment** (not a sub-compartment)
3. Verify the group OCID in tenant-a matches the actual group OCID from tenant-b
4. Verify your user is a member of the `lpg-admins` group in both tenancies

### terraform_remote_state fails

1. Verify the TFC workspace `iam-tenant-b` exists and has been applied
2. Verify the TFC organization name matches `tfc_organization` variable
3. Ensure the TFC token has access to read the workspace

### Policy creation fails

- Ensure you're using an admin user with tenancy-level IAM permissions
- Check that the OCIDs are correct (copy-paste from OCI Console)
