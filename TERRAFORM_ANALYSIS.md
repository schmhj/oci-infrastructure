# Terraform Analysis: OCI Infrastructure Issues & Fixes

**Date**: 2026-04-06
**Analysis of**: `oci-infra/` directory unified configuration
**Status**: Multiple critical issues identified requiring fixes

---

## Executive Summary

Terraform plan execution reveals **4 critical issues** preventing infrastructure deployment:

1. ❌ **CA Certificate Attribute Mismatch** (CRITICAL)
2. ❌ **Helm Provider Kubernetes Configuration** (CRITICAL)
3. ✅ **NLB FQDN Attribute** (FIXED)
4. ✅ **OKE Node Placement Dynamic ADs** (FIXED)

---

## Issue #1: CA Certificate Attribute Not Found

### Problem
```
Error: Unsupported attribute
on providers.tf line 14 & outputs.tf line 17:
  value = data.oci_containerengine_cluster.created_cluster.metadata[0].certificate_authority_data

This object does not have an attribute named "certificate_authority_data"
```

### Root Cause
- The OCI Terraform provider (v8.8.0) on Terraform Cloud (v1.14.8) does not expose `certificate_authority_data` on the cluster metadata
- When accessing a **data source** created cluster vs. a **resource** created cluster, the attributes may differ
- The `k8s-infra/infra.tf` references show `certificate_authority_data` exists in their setup, but they query an existing cluster by ID

### Current Configuration (FAILS)
```hcl
data "oci_containerengine_cluster" "created_cluster" {
  cluster_id = oci_containerengine_cluster.k8s_cluster.id
}

cluster_ca_certificate = base64decode(
  data.oci_containerengine_cluster.created_cluster.metadata[0].certificate_authority_data
)
```

### Solutions to Investigate

#### Solution 1A: Check OCI Provider Version Compatibility
- Current: OCI provider `v8.8.0` (specified as `>= 4.41.0`)
- **Action**: Verify if `certificate_authority_data` is available in this version
- Check: https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/containerengine_cluster

#### Solution 1B: Use Alternative Attribute Path
Possible attribute locations:
- `clustercert_data`
- `certificate_authority_cert`
- `metadata[0].ca_certificate`
- `cluster_ca_certificate` (directly on cluster resource)

**Action**: Test each path against the remote state or use `terraform state show` to inspect actual attributes

#### Solution 1C: Skip TLS Verification (Temporary/Dev Only)
```hcl
provider "kubernetes" {
  host  = oci_containerengine_cluster.k8s_cluster.endpoints[0].public_endpoint
  insecure_skip_tls_verify = true

  # But the kubernetes provider doesn't support this argument!
}
```
**Status**: Not viable - kubernetes provider doesn't support `insecure_skip_tls_verify`

#### Solution 1D: Use Token-Based Authentication
Some Kubernetes providers support token-based auth without certificate verification:
```hcl
provider "kubernetes" {
  host  = oci_containerengine_cluster.k8s_cluster.endpoints[0].public_endpoint
  token = "..."  # Generate from OCI API
}
```
**Status**: Requires generating token separately; not ideal for IaC

#### Solution 1E: Query Terraform Cloud Remote State
If the cluster was previously created in k8s-infra workspace:
```hcl
data "terraform_remote_state" "k8s_infra" {
  backend = "remote"
  config = {
    organization = "schmhj"
    workspaces = {
      name = "cloud-workspace-k8s"  # Or appropriate workspace name
    }
  }
}

cluster_ca_certificate = base64decode(
  data.terraform_remote_state.k8s_infra.outputs.oke_cluster_ca_certificate
)
```
**Best Approach**: Merges infrastructure properly without duplication

### Recommended Fix
**Use Solution 1E** - Reference the CA certificate from the existing k8s-infra workspace since both clusters are the same resource.

---

## Issue #2: Helm Provider Kubernetes Configuration

### Problem
```
Error: Unsupported block type
on providers.tf line 25:
  kubernetes {
      ...
  }

Blocks of type "kubernetes" are not expected here.
Did you mean to define argument "kubernetes"?
If so, use the equals sign to assign it a value.
```

### Root Cause
- Terraform Cloud v1.14.8 with Helm provider v3.1.1 has a schema/parsing issue
- Block syntax `kubernetes { }` is not recognized
- Object syntax `kubernetes = { }` causes issues with nested exec blocks
- The `k8s-infra/infra.tf` syntax suggests it works elsewhere, but the parsing differs between environments

### Current Attempts (ALL FAIL)

#### Attempt 1: Block Syntax ❌
```hcl
provider "helm" {
  kubernetes {
    host = "..."
    exec { ... }
  }
}
```
**Error**: "kubernetes block is not expected here"

#### Attempt 2: Object Syntax ❌
```hcl
provider "helm" {
  kubernetes = {
    host = "..."
    exec { ... }
  }
}
```
**Error**: "Missing key/value separator" on exec block

#### Attempt 3: Flatten Attributes ❌
```hcl
provider "helm" {
  host = "..."
  exec { ... }
}
```
**Error**: Helm provider doesn't have top-level `host` and `exec` arguments

### Solutions

#### Solution 2A: Use Separate Kubernetes Data Source
```hcl
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}
```
**Limitation**: Requires pre-configured kubeconfig file; not suitable for Terraform Cloud

#### Solution 2B: Use Remote State from k8s-infra
Delegate Helm provider to k8s-infra workspace where it's already configured.

#### Solution 2C: Upgrade Terraform/Provider Versions
Update `versions.tf`:
```hcl
terraform {
  required_version = ">= 1.5.0"  # Instead of ">= 1.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.14.0"  # Check latest stable version
    }
  }
}
```

#### Solution 2D: Use Null Provider Temporarily
Comment out Helm provider and use null provider placeholder:
```hcl
terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.11.0"
    }
  }
}

# provider "helm" { ... } # COMMENTED OUT TEMPORARILY
```

### Recommended Fix
**Use Solution 2C** - Upgrade Terraform to v1.5+ and Helm provider to v2.14+

---

## Issue #3: NLB FQDN Attribute ✅ FIXED

### Problem
```
Error: Unsupported attribute
outputs.tf line 70: value = oci_network_load_balancer_network_load_balancer.nlb.fqdn
This object has no argument named "fqdn"
```

### Solution Applied
Replaced `nlb.fqdn` with alternative output:
```hcl
output "nlb_private_ip" {
  description = "The private IP address(es) of the Network Load Balancer"
  value       = [for ip in oci_network_load_balancer_network_load_balancer.nlb.ip_addresses
                 : ip.ip_address if ip.is_public == false]
}
```

**Status**: ✅ FIXED - `fqdn` attribute doesn't exist; use IP addresses instead

---

## Issue #4: OKE Node Placement ✅ FIXED

### Problem
```hcl
# HARDCODED INDICES - Will fail if region has < 3 ADs
placement_configs {
  availability_domain = data.oci_identity_availability_domains.availability_domains.availability_domains[0].name
}
placement_configs {
  availability_domain = data.oci_identity_availability_domains.availability_domains.availability_domains[1].name
}
placement_configs {
  availability_domain = data.oci_identity_availability_domains.availability_domains.availability_domains[2].name
}
```

### Solution Applied
```hcl
# DYNAMIC - Works with 1, 2, 3, or more ADs
dynamic "placement_configs" {
  for_each = slice(
    data.oci_identity_availability_domains.availability_domains.availability_domains,
    0,
    min(3, length(data.oci_identity_availability_domains.availability_domains.availability_domains))
  )
  content {
    availability_domain = placement_configs.value.name
    subnet_id           = oci_core_subnet.private_subnet.id
  }
}
```

**Status**: ✅ FIXED - Now supports 1-3+ availability domains dynamically

---

## Files Modified

| File | Changes | Status |
|------|---------|--------|
| `providers.tf` | CA cert & Helm syntax fixes | ⚠️ PENDING |
| `outputs.tf` | Fixed NLB FQDN, CA cert output | ✅ PARTIAL |
| `oke_cluster.tf` | Dynamic placement_configs | ✅ FIXED |
| `nlb.tf` | No changes needed | ✅ OK |

---

## Next Steps & Recommendations

### Immediate Actions
1. **Test in local environment** (if possible):
   ```bash
   terraform plan  # Run locally to get actual error details
   ```

2. **Check OCI provider documentation**:
   - https://registry.terraform.io/providers/oracle/oci/latest/docs

3. **Verify Terraform Cloud workspace config**:
   - Check if provider versions are pinned differently

### Strategic Recommendations

1. **Reconcile Dual Workspaces**:
   - Currently have separate `oci-infra` and `k8s-infra`
   - Consider keeping separate OR merging properly
   - **If merging**: Ensure state migration is planned

2. **Version Management**:
   - Pin exact provider versions (not just min versions)
   - Use `.terraform.lock.hcl` consistently across environments
   - Document why specific versions are required

3. **Architecture Decision**:
   - **Option A**: Keep separate workspaces (cleaner, but duplication)
   - **Option B**: Unified workspace (simpler, but complex state management)
   - **Option C**: Separate workspaces with remote state data sources (balanced)

---

## Testing Checklist

After implementing fixes:

- [ ] `terraform plan` succeeds with no syntax errors
- [ ] All resources are in `plan` output
- [ ] No attribute not found errors
- [ ] Provider configurations accepted by Terraform Cloud
- [ ] `terraform apply` succeeds (in dev environment first)
- [ ] K8s cluster accessible via kubeconfig
- [ ] ArgoCD deploys successfully via Helm
- [ ] Network Load Balancer routes traffic correctly

---

## References

- [OCI Terraform Provider Docs](https://registry.terraform.io/providers/oracle/oci/latest/docs)
- [Helm Provider Docs](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)
- [Kubernetes Provider Docs](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)
- [Existing k8s-infra Configuration](./k8s-infra/infra.tf)
