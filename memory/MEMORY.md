# OCI Infrastructure Project - Unified Terraform Configuration

## Project Summary
Unified OKE cluster creation and Kubernetes/Helm configuration into single Terraform workflow (merged from separate oci-infra and k8s-infra).

## Directory Structure
All configuration is now in: `/Users/autumn/Projects/schmhj/oci-infrastructure/oci-infra/`

### Core Files (by concern)
- `versions.tf` - Provider version constraints (Terraform >= 1.0, OCI >= 4.41.0)
- `providers.tf` - OCI, Kubernetes, and Helm provider configuration
- `variables.tf` - All 40+ input variables (compartment, region, node config, ArgoCD settings)
- `locals.tf` - Naming conventions, CIDRs, suffixes
- `vcn.tf` - VCN module + public/private subnets
- `security.tf` - Security lists (firewall rules for public/private subnets)
- `oke_cluster.tf` - OKE cluster, node pool, availability domain placement
- `kubernetes_config.tf` - Kubernetes namespaces (ArgoCD)
- `helm.tf` - Helm releases (ArgoCD 7.8.26)
- `nlb.tf` - Network Load Balancer routing to ArgoCD NodePort
- `outputs.tf` - 20+ outputs (cluster ID, endpoint, NLB IP, kubeconfig instructions)
- `backend.tf` - Terraform Cloud backend: `cloud-workspace-unified`

### Supporting Files
- `terraform.tfvars.example` - Template with all variable definitions
- `README.md` - Complete usage guide, troubleshooting, access instructions
- `REFACTORING_SUMMARY.md` - Migration guide and consolidation details

## Key Variables (retain existing values)
- `kubernetes_version` - default: `v1.31.10`
- `node_shape` - default: `VM.Standard.A1.Flex`
- `node_ocpus` - default: `2`
- `node_memory_gbs` - default: `12`
- `argocd_chart_version` - default: `7.8.26`
- `argocd_nodeport_https` - default: `30443`

## Terraform Cloud Setup
- **Organization**: schmhj
- **Workspace**: cloud-workspace-unified (replaces cloud-workspace-oci and cloud-workspace-k8s)
- **Sensitive Variables**: tenancy_ocid, user_ocid, fingerprint, private_key

## Architecture
1. **Networking**: VCN with public subnet (API/LB) and private subnet (workers)
2. **Cluster**: OKE with nodes across 3 availability domains for HA
3. **K8s**: ArgoCD deployed via Helm in namespace
4. **Access**: Network Load Balancer exposes ArgoCD on HTTPS port 443

## Important Notes
- Kubernetes and Helm providers depend on OKE cluster (automatic dependency in providers.tf)
- Nodes use latest compatible arm64 image for specified K8s version
- All resources automatically get descriptive names using project/env/region
- Outputs include kubeconfig and access instructions

## Usage
```bash
cd oci-infra
terraform init
terraform plan
terraform apply
terraform output kubeconfig_instructions  # Copy and run to get kubeconfig
```
