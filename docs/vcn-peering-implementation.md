# Cross-Tenancy VCN Peering — LPG Implementation

## Overview

This document describes the implementation of cross-tenancy VCN peering between tenant-a (acceptor) and tenant-b (requestor) using Local Peering Gateways (LPG). LPG is free-tier OCI networking with no additional charges.

## Architecture

```
┌─────────────────────────────────────┐         ┌─────────────────────────────────────┐
│  TENANT-A (Acceptor)                │         │  TENANT-B (Requestor)               │
│  OCI Tenancy: schmhj-a              │         │  OCI Tenancy: schmhj-b              │
│  Region: us-ashburn-1               │  LPG    │  Region: us-ashburn-1               │
│                                     │◄───────►│                                     │
│  VCN: 10.1.0.0/16                   │  Peered │  VCN: 10.2.0.0/16                   │
│  ┌──────────────┐                   │         │  ┌──────────────┐                   │
│  │ Traefik/NLB  │◄──── Private ─────┼─────────┼─►│ OKE Apps     │                   │
│  │ (ArgoCD)     │     10.x.x.x      │         │  │ (Workload)   │                   │
│  └──────────────┘                   │         │  └──────────────┘                   │
│  Pods: 10.244.0.0/16                │         │  Pods: 10.245.0.0/16 (changed)      │
└─────────────────────────────────────┘         └─────────────────────────────────────┘
```

## CIDR Allocation

| Component | tenant-a | tenant-b |
|-----------|----------|----------|
| VCN CIDR | `10.1.0.0/16` | `10.2.0.0/16` |
| Public Subnet | `10.1.0.0/24` | `10.2.0.0/24` |
| Private Subnet | `10.1.1.0/24` | `10.2.1.0/24` |
| Pod CIDR | `10.244.0.0/16` | `10.245.0.0/16` (changed) |
| Service CIDR | `10.96.0.0/16` | `10.96.0.0/16` |

## Pre-Requisites (Manual — Not Terraform)

### IAM Policies

Create these policies in **both** OCI tenancies before running Terraform. The `associate` statement is critical — it grants the `ConnectLocalPeeringGateways` API permission required to establish the peering connection.

**Requestor tenancy (tenant-b) — in the root compartment:**
```
Define tenancy Acceptor as <acceptor-tenancy-ocid>
Define group requestor-admins as <requestor-group-ocid>
Allow group requestor-admins to manage local-peering-from in tenancy
Endorse group requestor-admins to manage local-peering-to in tenancy Acceptor
Endorse group requestor-admins to associate local-peering-gateways in tenancy with local-peering-gateways in tenancy Acceptor
```

**Acceptor tenancy (tenant-a) — in the root compartment:**
```
Define tenancy Requestor as <requestor-tenancy-ocid>
Define group requestor-admins as <requestor-group-ocid>
Allow group lpg-admins to manage local-peering-from in tenancy
Admit group requestor-admins of tenancy Requestor to manage local-peering-to in tenancy
Admit group requestor-admins of tenancy Requestor to associate local-peering-gateways in tenancy Requestor with local-peering-gateways in tenancy
```

Replace `<acceptor-tenancy-ocid>`, `<requestor-tenancy-ocid>`, and `<requestor-group-ocid>` with actual values.

### TFC Workspace Variables (tenant-b)

Set these as **sensitive workspace variables** in the tenant-b TFC workspace (not in `.auto.tfvars`):

| Variable | Value | Source |
|----------|-------|--------|
| `peer_lpg_ocid` | tenant-a's LPG OCID | Output from tenant-a's Terraform apply |
| `peer_tenancy_id` | tenant-a's tenancy OCID | Manual — from OCI console |

## Files Changed

### Module (`modules/oke/`)

| File | Change |
|------|--------|
| `variables.tf` | Added `pods_cidr`, `enable_vcn_peering`, `peer_lpg_ocid`, `peer_vcn_cidr`, `peer_tenancy_id` |
| `oke.tf:53` | Changed hardcoded `pods_cidr` to `var.pods_cidr` |
| `network.tf` | Added LPG resource, peering connection, data source for OCI services, route table with LPG route, updated private subnet route table, added peer VCN ingress rules to both security lists |
| `outputs.tf` | Added `lpg_ocid` output |

### Tenant-A (`environments/tenant-a/`)

| File | Change |
|------|--------|
| `variables.tf` | Added `enable_vcn_peering`, `peer_vcn_cidr` |
| `main.tf` | Pass `enable_vcn_peering`, `peer_vcn_cidr` to module |
| `tenant-a.auto.tfvars` | Added `enable_vcn_peering = true`, `peer_vcn_cidr = "10.2.0.0/16"`, removed old DRG comments |
| `outputs.tf` | Added `lpg_ocid` output |

### Tenant-B (`environments/tenant-b/`)

| File | Change |
|------|--------|
| `variables.tf` | Added `enable_vcn_peering`, `peer_lpg_ocid`, `peer_vcn_cidr`, `peer_tenancy_id` |
| `main.tf` | Pass `enable_vcn_peering`, `peer_lpg_ocid`, `peer_vcn_cidr`, `peer_tenancy_id` to module |
| `tenant-b.auto.tfvars` | Added `pods_cidr = "10.245.0.0/16"`, `enable_vcn_peering = true`, `peer_vcn_cidr = "10.1.0.0/16"`, removed old DRG comments |

## Terraform Resources Created

### Per-Tenant (when `enable_vcn_peering = true`)

1. **`oci_core_local_peering_gateway.vcn_lpg`** — The LPG attached to the VCN
2. **`oci_core_route_table.private_subnet_rt_with_lpg`** — Route table with NAT GW + SGW + LPG routes
3. **`oci_core_security_list` updates** — Added dynamic ingress rules allowing all traffic from peer VCN CIDR

### Requestor Only (when `peer_lpg_ocid != null`)

4. **`oci_core_local_peering_connection.peering`** — Establishes the peering connection to the acceptor's LPG

## Deployment Steps

### Step 1: Create IAM Policies (Manual)

Create the cross-tenancy IAM policies in both OCI tenancies as described in Pre-Requisites.

### Step 2: Deploy tenant-a (Acceptor)

```bash
cd environments/tenant-a
terraform init
terraform plan -input=false
terraform apply -auto-approve -input=false
```

After apply, capture the LPG OCID:

```bash
terraform output lpg_ocid
```

Output will look like:
```
"ocid1.localpeeringgateway.oc1.iad.aaaaaaaa..."
```

### Step 3: Set TFC Variables for tenant-b

In the Terraform Cloud UI for the tenant-b workspace, add these **workspace variables**:

- `peer_lpg_ocid` = the LPG OCID from Step 2 (mark as **sensitive**)
- `peer_tenancy_id` = tenant-a's tenancy OCID (mark as **sensitive**)

### Step 4: Deploy tenant-b (Requestor)

```bash
cd environments/tenant-b
terraform init
terraform plan -input=false
terraform apply -auto-approve -input=false
```

### Step 5: Verify Peering

1. **OCI Console** → Networking → Virtual Cloud Networks → tenant-a's VCN → Resources → Local Peering Gateways
   - Status should show **"Peered — Connected to a peer"**

2. **OCI Console** → Networking → Virtual Cloud Networks → tenant-b's VCN → Resources → Local Peering Gateways
   - Status should show **"Peered — Connected to a peer"**

3. **Test connectivity** from a tenant-b worker node:
   ```bash
   # From a pod in tenant-b, ping a pod IP in tenant-a
   ping <tenant-a-pod-ip>
   ```

## How It Works

1. **LPG Creation**: Both tenants create an LPG attached to their VCN
2. **Peering Connection**: tenant-b (requestor) initiates the connection to tenant-a's LPG using its OCID
3. **Route Tables**: Both VCNs get route rules directing peer VCN traffic through the LPG
4. **Security Lists**: Both VCNs allow all traffic from the peer VCN CIDR
5. **Private Communication**: Traffic flows privately between VCNs without traversing the public internet

## Troubleshooting

### Peering Connection Fails

- **IAM Policy Error**: Ensure cross-tenancy IAM policies are created in both tenancies, including the `associate` statement (required for `ConnectLocalPeeringGateways`)
- **LPG OCID Mismatch**: Verify `peer_lpg_ocid` matches tenant-a's actual LPG OCID
- **Region Mismatch**: Both VCNs must be in the same region (`us-ashburn-1`)

### Traffic Not Routing

- **Check Route Tables**: Verify the private subnet route table has the LPG route for the peer VCN CIDR
- **Check Security Lists**: Verify ingress rules allow traffic from the peer VCN CIDR
- **Pod CIDR Overlap**: If pod CIDRs overlap, traffic will be misrouted. tenant-b uses `10.245.0.0/16`.

### Destroying the Peering

To remove the peering:
1. Destroy tenant-b first (removes the peering connection)
2. Destroy tenant-a (removes the LPG)

Or manually delete the LPGs from the OCI Console.

## Cost

**Free.** LPG and peered traffic within the same region have no additional charges in OCI.

## References

- [OCI Local VCN Peering using LPGs](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/localVCNpeering.htm)
- [OCI IAM Policies for VCN Peering](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/drg-iam.htm)
- [OCI Connecting to Another LPG](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/connect-lpg.htm)
- [OCI Access Control for LPGs](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/accesscontrol.htm)
- [oracle-quickstart Cross-Tenancies Example](https://github.com/oracle-quickstart/oci-arch-cross-tenancies/blob/master/iam.tf)
- [Terraform OCI Provider — Local Peering Gateway](https://registry.terraform.io/providers/hashicorp/oci/latest/docs/resources/core_local_peering_gateway)
