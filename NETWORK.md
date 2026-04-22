# OCI Network Configuration Guide

This document describes the network architecture, CIDR allocation, security policies, and multi-region connectivity for the OCI Kubernetes infrastructure.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [CIDR Allocation Strategy](#cidr-allocation-strategy)
3. [Security Configuration](#security-configuration)
4. [Multi-Region Connectivity (DRG)](#multi-region-connectivity-drg)
5. [Network Security Lists](#network-security-lists)
6. [Routing Configuration](#routing-configuration)
7. [NLB Configuration](#nlb-configuration)
8. [Deployment Examples](#deployment-examples)

---

## Architecture Overview

The OCI infrastructure is deployed across two regions (us-ashburn-1 and us-chicago-1) with isolated VCNs and Kubernetes clusters. Each region has:

- **VCN** (Virtual Cloud Network): Isolated network per region
- **Public Subnet**: Hosts the Network Load Balancer (NLB), routes to Internet Gateway
- **Private Subnet**: Hosts OKE worker nodes, routes to NAT Gateway for egress
- **OKE Cluster**: Kubernetes cluster with dynamic subnet CIDR allocation
- **NLB**: Network Load Balancer exposing ArgoCD and Kubernetes API

### Network Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                   Internet (0.0.0.0/0)                      │
└─────────────────────────────────────────────────────────────┘
                            │
                    [Security Groups]
                            │
              ┌─────────────────────────────┐
              │   NLB (Public Subnet)       │
              │   Port 443 → Node 30443     │
              │   Port 6443 → Node 30443    │
              └─────────────────────────────┘
                            │
              ┌─────────────────────────────┐
              │   VCN CIDR                  │
              │   ├─ Public Subnet          │
              │   │  (X.Y.0.0/24)           │
              │   │  └─ Internet Gateway    │
              │   │                         │
              │   └─ Private Subnet         │
              │      (X.Y.1.0/24)           │
              │      ├─ OKE Nodes           │
              │      ├─ Pod CIDR            │
              │      │  (10.244.0.0/16)     │
              │      └─ NAT Gateway         │
              └─────────────────────────────┘
                   │           │
              (Multi-Region)   │
                   │           │
              ┌────────────────────────┐
              │  DRG (Optional)        │
              │  (Inter-Region Routes) │
              └────────────────────────┘
                   │
         ┌─────────┴─────────┐
         │                   │
    [Ashburn]           [Chicago]
   10.1.0.0/16          10.2.0.0/16
```

---

## CIDR Allocation Strategy

### VCN CIDR Blocks

Each region has a unique VCN CIDR block:

| Region | VCN CIDR | Public Subnet | Private Subnet |
|--------|----------|---------------|----------------|
| Ashburn | 10.1.0.0/16 | 10.1.0.0/24 | 10.1.1.0/24 |
| Chicago | 10.2.0.0/16 | 10.2.0.0/24 | 10.2.1.0/24 |

**Key Feature**: Subnet CIDRs are **automatically derived** from the VCN CIDR. If you change the VCN CIDR in `us-ashburn.auto.tfvars`, the subnets will automatically align:

```hcl
# us-ashburn.auto.tfvars
vcn_cidr = "10.1.0.0/16"  # → Subnets: 10.1.0.0/24, 10.1.1.0/24

# us-chicago.auto.tfvars
vcn_cidr = "10.2.0.0/16"  # → Subnets: 10.2.0.0/24, 10.2.1.0/24
```

### Kubernetes Network CIDRs

These are fixed across all regions for consistency:

| Component | CIDR | Across Regions |
|-----------|------|---|
| Pod CIDR | 10.244.0.0/16 | Same in all regions |
| Service CIDR | 10.96.0.0/16 | Same in all regions |

**Important**: Pod CIDRs are the same in both regions. For multi-region pod communication, use DRG peering (see [Multi-Region Connectivity](#multi-region-connectivity-drg)).

### CIDR Overlap Check

- **Public/Private Subnets**: Non-overlapping within each VCN ✓
- **Pod CIDRs**: Same across regions (OK for DRG peering) ✓
- **Service CIDRs**: Same across regions (use DNS for cross-region discovery)

---

## Security Configuration

### Network Security Lists

Security is enforced at two levels:

1. **Public Subnet Security List** - Controls ingress from Internet
2. **Private Subnet Security List** - Controls inter-subnet and NLB health checks

#### Public Subnet Security List

**Ingress Rules:**

| Protocol | Port | Source | Purpose |
|----------|------|--------|---------|
| TCP | 443 | `nlb_allowed_cidr_blocks` (default: 0.0.0.0/0) | NLB HTTPS (ArgoCD) |
| TCP | 6443 | `nlb_allowed_cidr_blocks` (default: 0.0.0.0/0) | Kubernetes API |
| All | All | VCN CIDR | Full VCN access |

**Egress Rules:**

| Protocol | Port | Destination | Purpose |
|----------|------|-------------|---------|
| All | All | 0.0.0.0/0 | Full outbound |
| TCP | 30443 | Private Subnet | NodePort routing |
| TCP | 10256 | Private Subnet | Kubelet health checks |

#### Private Subnet Security List

**Ingress Rules:**

| Protocol | Port | Source | Purpose |
|----------|------|--------|---------|
| All | All | VCN CIDR | Full VCN access |
| TCP | 10256 | Public Subnet | NLB health checks |
| TCP | 30443 | Public Subnet | NodePort traffic |

**Egress Rules:**

| Protocol | Port | Destination | Purpose |
|----------|------|-------------|---------|
| All | All | 0.0.0.0/0 | Full outbound (NAT Gateway) |

### IP Allowlisting (NLB Access Control)

#### Default Configuration (Open)

```hcl
# us-ashburn.auto.tfvars
nlb_allowed_cidr_blocks = ["0.0.0.0/0"]  # Allow all traffic
```

#### Production Configuration (Restricted)

To restrict NLB and API access to specific networks:

```hcl
# us-ashburn.auto.tfvars
nlb_allowed_cidr_blocks = [
  "203.0.113.0/24",   # Office network
  "198.51.100.0/24",  # VPN network
]
```

#### Migration from Current Setup

If currently using `0.0.0.0/0` (open), add to tfvars:

```hcl
nlb_allowed_cidr_blocks = ["0.0.0.0/0"]
```

Then gradually restrict by replacing with specific CIDR blocks.

### Egress Control (Optional)

By default, all outbound traffic is allowed. To restrict egress:

```hcl
# us-ashburn.auto.tfvars
enable_strict_egress = true
allowed_egress_cidrs = [
  "0.0.0.0/0",              # Allow all (default)
  # Or restrict to specific services:
  # "ocid.oras.iad",         # Oracle Cloud Registry
  # "10.0.0.0/8",            # Internal networks
  # "8.8.8.8/32",            # Specific IPs
]
```

---

## Multi-Region Connectivity (DRG)

### Overview

Dynamic Routing Gateway (DRG) enables:
- Pod-to-pod communication between Ashburn and Chicago clusters
- Service discovery across regions
- Multi-region failover patterns

### Architecture

```
┌────────────────────┐          ┌────────────────────┐
│  Ashburn Cluster   │          │  Chicago Cluster   │
│  VCN: 10.1.0.0/16  │          │  VCN: 10.2.0.0/16  │
│  Pods: 10.244.0/16 │          │  Pods: 10.244.0/16 │
└─────────┬──────────┘          └──────────┬─────────┘
          │                                 │
          │ DRG Attachment                  │ DRG Attachment
          │                                 │
          └────────────┬────────────────────┘
                       │
                   ┌───────────┐
                   │   DRG     │
                   │ (Shared)  │
                   └───────────┘
```

### Activation Steps

#### Step 1: Provision Shared DRG (Terraform)

Create a DRG in your tenancy (outside of this module):

```hcl
# Example: In your root module
resource "oci_core_drg" "shared_drg" {
  compartment_id = var.compartment_id
  display_name   = "multi-region-drg"
}

output "drg_id" {
  value = oci_core_drg.shared_drg.id
}
```

Then retrieve the DRG ID from outputs or OCI console.

#### Step 2: Enable DRG in Terraform

Update both region environment files:

```hcl
# environments/us-ashburn/us-ashburn.auto.tfvars
enable_drg               = true
drg_id                   = "ocid1.drg.oc1.iad..."
peer_region_pods_cidr    = "10.2.244.0/22"  # Chicago pods

# environments/us-chicago/us-chicago.auto.tfvars
enable_drg               = true
drg_id                   = "ocid1.drg.oc1.iad..."
peer_region_pods_cidr    = "10.1.244.0/22"  # Ashburn pods
```

#### Step 3: Create Kubectl Secret for Cross-Region Communication

```bash
# Export both clusters' endpoints
export ASHBURN_ENDPOINT="<ashburn-api-endpoint>"
export CHICAGO_ENDPOINT="<chicago-api-endpoint>"

# Create secret in Ashburn cluster
kubectl --context ashburn create secret generic chicago-endpoint \
  --from-literal=endpoint=$CHICAGO_ENDPOINT

# Create secret in Chicago cluster
kubectl --context chicago create secret generic ashburn-endpoint \
  --from-literal=endpoint=$ASHBURN_ENDPOINT
```

#### Step 4: Verify Connectivity

```bash
# Deploy a test pod in Ashburn
kubectl --context ashburn run -it test-ashburn --image=busybox -- sh

# From within the pod, ping a service in Chicago
# (requires DNS resolution setup - see deployment examples)
```

### Routing Details

When `enable_drg = true`, the module creates:

1. **DRG Attachment**: Connects VCN to shared DRG
2. **Custom Route Rules** (via `internet_gateway_route_rules`): Routes peer region pods to DRG
   - Ashburn: Route `10.2.244.0/22` (Chicago pods) → DRG
   - Chicago: Route `10.1.244.0/22` (Ashburn pods) → DRG

To add DRG routes, update your environment tfvars:

```hcl
# environments/us-ashburn/us-ashburn.auto.tfvars
enable_drg              = true
drg_id                  = "ocid1.drg.oc1.iad..."
peer_region_pods_cidr   = "10.2.244.0/22"  # Chicago pods CIDR

internet_gateway_route_rules = [
  {
    destination       = "10.2.244.0/22"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = "ocid1.drg.oc1.iad..."  # DRG ID
  }
]
```

**Note**: You must also create matching DRG route table attachments on the DRG side (not in this module) to complete the route path. The DRG needs to be configured to route traffic back to both regions.

---

## Network Security Lists

### Security List Design Principles

1. **Least Privilege**: Only allow necessary traffic
2. **Explicit Rules**: No implicit allow rules
3. **Dynamic Computation**: Use `local.public_subnet_cidr` and `local.private_subnet_cidr` for maintainability
4. **Regional Isolation**: Rules reference only subnets within the same VCN

### Modifying Security Rules

To add custom ingress rules to the public subnet:

```hcl
# In modules/oke/network.tf
ingress_security_rules {
  stateless   = false
  source      = "10.0.0.0/8"  # Your custom source
  source_type = "CIDR_BLOCK"
  protocol    = "6"
  tcp_options {
    min = 8080
    max = 8080
  }
}
```

---

## Routing Configuration

### Default Routes

**Public Subnet Route Table** (Internet Gateway):
- `0.0.0.0/0` → Internet Gateway (outbound to Internet)
- `<Oracle-Services>` → Service Gateway (Oracle Cloud services)

**Private Subnet Route Table** (NAT Gateway):
- `0.0.0.0/0` → NAT Gateway (outbound via public IP)
- `<Oracle-Services>` → Service Gateway

### Custom Routes

Add custom routes for DRG or on-premises connectivity:

```hcl
# environments/us-ashburn/us-ashburn.auto.tfvars
internet_gateway_route_rules = [
  {
    destination       = "10.2.0.0/16"  # Chicago VCN
    destination_type  = "CIDR_BLOCK"
    network_entity_id = "ocid1.drg.oc1.iad..."  # DRG ID
  }
]

nat_gateway_route_rules = [
  {
    destination       = "192.168.0.0/16"  # On-premises
    destination_type  = "CIDR_BLOCK"
    network_entity_id = "ocid1.drg.oc1.iad..."  # DRG ID (via IPSec tunnel)
  }
]
```

---

## NLB Configuration

### Load Balancer Details

The Network Load Balancer (NLB) provides public access to ArgoCD and Kubernetes API:

| Component | Configuration |
|-----------|---|
| **Listener Port** | 443 (HTTPS/TCP) |
| **Backend Port** | 30443 (NodePort) |
| **Policy** | FIVE_TUPLE (connection-oriented) |
| **Health Check** | TCP port 10256 (kubelet) |
| **Public IP** | Automatic (from NLB) |
| **Subnet** | Public Subnet |

### NLB Health Checks

The NLB monitors worker node health via kubelet port (10256):

- **Protocol**: TCP
- **Port**: 10256 (kubelet health check port)
- **Interval**: 10 seconds (OCI default)
- **Timeout**: 3 seconds

If health checks fail, the node is marked unhealthy and traffic is no longer routed to it.

### Accessing Services

#### ArgoCD Access

```bash
# Get NLB public IP
NLB_IP=$(terraform output -raw nlb_public_ip)

# Access ArgoCD
https://${NLB_IP}:30443
```

#### Kubernetes API Access

```bash
# Extract from kubeconfig
export KUBE_API=$(terraform output -raw cluster_endpoint)

# Or via NLB
kubectl --server https://${NLB_IP}:30443 ...
```

### TLS Termination (Optional - Deferred)

The current setup uses TCP pass-through on the NLB. TLS termination is handled by ArgoCD.

To add TLS termination at the NLB layer (future enhancement):

1. Provision a certificate in OCI Certificate Manager
2. Update NLB listener to `protocol = "TLS_V1_2"`
3. Attach certificate to NLB via `ssl_configuration`

This would require certificate provisioning automation (separate from this module).

---

## Deployment Examples

### Single Region Deployment (Ashburn Only)

```bash
cd modules/oke
terraform apply -var-file=../../environments/us-ashburn/us-ashburn.auto.tfvars
```

**Configuration** (minimal):
```hcl
# environments/us-ashburn/us-ashburn.auto.tfvars
nlb_allowed_cidr_blocks = ["0.0.0.0/0"]  # Allow all (for demo)
enable_drg              = false           # No multi-region
```

### Multi-Region Deployment (Both Regions, No DRG)

```bash
# Ashburn
cd modules/oke
terraform apply -var-file=../../environments/us-ashburn/us-ashburn.auto.tfvars

# Chicago
terraform apply -var-file=../../environments/us-chicago/us-chicago.auto.tfvars
```

**Configuration**:
```hcl
# Both regions
nlb_allowed_cidr_blocks = ["0.0.0.0/0"]
enable_drg              = false
```

**Result**: Two isolated clusters, no network communication between regions.

### Multi-Region Deployment with DRG (Cross-Region Pods)

#### Step 1: Create Shared DRG

```bash
oci core drg create --compartment-id <COMPARTMENT_ID> \
  --display-name multi-region-drg
# Output: drg_id = "ocid1.drg.oc1.iad..."
```

#### Step 2: Configure Terraform

```hcl
# environments/us-ashburn/us-ashburn.auto.tfvars
nlb_allowed_cidr_blocks = ["203.0.113.0/24"]  # Your office CIDR
enable_drg              = true
drg_id                  = "ocid1.drg.oc1.iad..."
peer_region_pods_cidr   = "10.2.244.0/22"

internet_gateway_route_rules = [
  {
    destination       = "10.2.244.0/22"  # Chicago pods CIDR
    destination_type  = "CIDR_BLOCK"
    network_entity_id = "ocid1.drg.oc1.iad..."
  }
]

# environments/us-chicago/us-chicago.auto.tfvars
nlb_allowed_cidr_blocks = ["203.0.113.0/24"]  # Your office CIDR
enable_drg              = true
drg_id                  = "ocid1.drg.oc1.iad..."
peer_region_pods_cidr   = "10.1.244.0/22"

internet_gateway_route_rules = [
  {
    destination       = "10.1.244.0/22"  # Ashburn pods CIDR
    destination_type  = "CIDR_BLOCK"
    network_entity_id = "ocid1.drg.oc1.iad..."
  }
]
```

#### Step 3: Apply Terraform

```bash
cd modules/oke

# Ashburn
terraform apply -var-file=../../environments/us-ashburn/us-ashburn.auto.tfvars

# Chicago
terraform apply -var-file=../../environments/us-chicago/us-chicago.auto.tfvars
```

#### Step 4: Verify Routing

```bash
# Check DRG attachments
oci core drg-attachment list --drg-id <DRG_ID>

# Check route tables
oci core route-table list --vcn-id <ASHBURN_VCN_ID>
oci core route-table list --vcn-id <CHICAGO_VCN_ID>

# Test pod connectivity
kubectl exec -it <ashburn-pod> -- ping <chicago-pod-ip>
```

### Restricted NLB Access (Production)

```hcl
# environments/us-ashburn/us-ashburn.auto.tfvars
nlb_allowed_cidr_blocks = [
  "203.0.113.0/24",    # Office network
  "198.51.100.0/24",   # VPN network
  "10.1.0.0/16",       # VCN (internal access)
]
enable_drg              = true
drg_id                  = "ocid1.drg.oc1.iad..."
peer_region_pods_cidr   = "10.2.244.0/22"

internet_gateway_route_rules = [
  {
    destination       = "10.2.244.0/22"  # Chicago pods CIDR
    destination_type  = "CIDR_BLOCK"
    network_entity_id = "ocid1.drg.oc1.iad..."
  }
]
```

**Result**:
- NLB accessible only from office, VPN, or within VCN
- DRG enabled for cross-region pod communication
- Internet access blocked (except via NAT for pod egress)

---

## Troubleshooting

### Subnet CIDR Mismatch

**Problem**: Terraform error about subnet CIDR outside VCN CIDR.

**Cause**: Hardcoded subnet CIDR doesn't match VCN CIDR.

**Solution**: Ensure VCN CIDR is set correctly in tfvars (fixed in v1.1.0+).

```hcl
# Verify alignment:
# If vcn_cidr = "10.1.0.0/16"
# Then public subnet should be "10.1.0.0/24"
# And private subnet should be "10.1.1.0/24"
```

### NLB Health Check Failures

**Problem**: NLB backend marked unhealthy.

**Cause**: Security list rules blocking port 10256, or kubelet not running.

**Solution**:

```bash
# Check kubelet status on worker node
kubectl get nodes -o wide

# Check security list rules
oci core security-list get --security-list-id <SL_ID>

# Verify port 10256 is open in private subnet security list
```

### DRG Routes Not Working

**Problem**: Pods can't reach peer region pods.

**Cause**: Route table rules not configured on DRG side, or peer region pods CIDR incorrect.

**Solution**:

```bash
# Check if route exists
oci core route-table get --route-table-id <ROUTE_TABLE_ID>

# Verify peer region pods CIDR
kubectl --context chicago get pods -o wide | grep <POD_NAME>

# Update peer_region_pods_cidr in tfvars if needed
```

### NLB Public IP Not Accessible

**Problem**: Can't reach NLB public IP on port 443.

**Cause**: IP allowlist blocking your CIDR, or NLB not in public subnet.

**Solution**:

```bash
# Verify your public IP
curl -s https://api.ipify.org

# Update nlb_allowed_cidr_blocks to include your IP
nlb_allowed_cidr_blocks = ["YOUR_IP/32"]

# Re-apply Terraform
terraform apply
```

---

## References

- [OCI VCN Documentation](https://docs.oracle.com/en-us/iaas/Content/Network/home.htm)
- [OCI DRG Documentation](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/DRG.htm)
- [OCI NLB Documentation](https://docs.oracle.com/en-us/iaas/Content/NetworkLoadBalancer/home.htm)
- [OKE Networking](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengnetworking.htm)
