# Two-Stage Terraform Deployment Guide

This infrastructure uses a **two-stage** approach to separate infrastructure provisioning from Kubernetes configuration.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  Stage 1: infra/          Stage 2: k8s/                        │
│  (OCI Infrastructure)     (Kubernetes + Helm)                  │
│                                                                 │
│  └─ OKE Cluster ────┐      ┌──────────────────────┐           │
│  └─ VCN/Networking  │      │  Kubernetes Provider │           │
│  └─ Node Pool       │─────→│  (exec-based auth)   │           │
│  └─ NLB             │      │                      │           │
│  └─ Outputs         │      │  Helm Provider       │           │
│                     │      │  (for ArgoCD)        │           │
│                     │      └──────────────────────┘           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Stage 1: OCI Infrastructure (`infra/`)

Provisions all OCI resources needed for a functioning OKE cluster.

### Files
- **versions.tf** - Terraform requirements & Terraform Cloud backend
- **providers.tf** - OCI provider configuration
- **variables.tf** - All OCI-related variables
- **locals.tf** - Computed values (resource names, CIDRs, cluster info)
- **network.tf** - VCN, subnets, security lists
- **oke.tf** - OKE cluster and node pool configuration
- **nlb.tf** - Network Load Balancer for ArgoCD access
- **outputs.tf** - Exports cluster details needed by Stage 2

### Outputs
The `infra/` stage outputs:
- `cluster_id` - OKE cluster ID
- `cluster_endpoint` - Kubernetes API endpoint
- `cluster_ca_cert` - CA certificate for cluster authentication
- `kubeconfig_content` - Full kubeconfig for reference
- `nlb_public_ip` - NLB IP for accessing ArgoCD

### Deployment
```bash
cd infra/
terraform init
terraform plan
terraform apply

# Save these outputs - you'll need them for Stage 2:
terraform output -raw cluster_id
terraform output -raw cluster_endpoint
terraform output -raw cluster_ca_cert
terraform output -raw nlb_public_ip
```

## Stage 2: Kubernetes Configuration (`k8s/`)

Configures Kubernetes resources and deploys applications.

### Files
- **version.tf** - Terraform requirements (Kubernetes & Helm providers)
- **providers.tf** - Kubernetes & Helm provider configuration
- **variables.tf** - Inputs from Stage 1 + additional k8s config
- **kubernetes.tf** - Namespaces and RBAC setup
- **helm.tf** - Helm releases (ArgoCD)
- **outputs.tf** - Kubernetes resource outputs
- **terraform.tfvars.example** - Example variable values

### Requirements
- `oci` CLI v2+ installed and configured
- Outputs from Stage 1 (`cluster_id`, `cluster_endpoint`, `cluster_ca_cert`)

### Authentication
Stage 2 uses **exec-based authentication** - the Kubernetes provider calls:
```bash
oci ce cluster generate-token --cluster-id <CLUSTER_ID> --region <REGION>
```

This requires:
1. OCI CLI v2+ installed: `brew install oci-cli` (macOS)
2. OCI CLI configured with valid credentials
3. User has permissions to generate tokens for the cluster

### Deployment

**Step 1: Prepare variables**
```bash
cd k8s/
cp terraform.tfvars.example terraform.tfvars
```

**Step 2: Fill in Stage 1 outputs**
```bash
# Edit terraform.tfvars with outputs from infra/ apply:
# - cluster_id
# - cluster_endpoint
# - cluster_ca_cert (base64 decoded output value)
# - region, project, env, user_ocid, node_port
```

**Step 3: Deploy**
```bash
terraform init
terraform plan
terraform apply
```

### Get ArgoCD Access

After k8s/ deployment completes:
```bash
# Get NLB IP from infra/ outputs
NLB_IP=$(cd ../infra && terraform output -raw nlb_public_ip)

# ArgoCD is accessible at:
# https://${NLB_IP}:30443

# Get initial admin password:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

## Local Development Setup

To run both stages locally:

### Prerequisites
```bash
# Install OCI CLI
brew install oci-cli

# Configure OCI CLI
oci setup config
# Follow prompts to create  ~/.oci/config

# Verify OCI CLI works
oci ce cluster list --compartment-id <COMPARTMENT_ID>
```

### Deployment Flow
```bash
# Stage 1: Build infrastructure
cd infra/
terraform apply

# Stage 2: Configure Kubernetes
cd ../k8s/
# Update terraform.tfvars with Stage 1 outputs
terraform apply

# Verify
kubectl cluster-info
kubectl get nodes
```

## Terraform Cloud Deployment

Both stages use the `schmhj` organization in Terraform Cloud:
- **Stage 1 workspace**: `cloud-workspace-oci`
- **Stage 2 workspace**: Create a separate workspace

### Setup
1. Set TF_TOKEN_APP_TERRAFORM_IO environment variable
2. Terraform will automatically use remote state
3. VCS integration runs apply on git push (with approval)

## Troubleshooting

### Error: "executable oci not found"
**Cause**: OCI CLI not installed or not in PATH
**Solution**:
```bash
brew install oci-cli
which oci  # Should print /opt/homebrew/bin/oci or similar
```

### Error: "cluster_ca_certificate is required"
**Cause**: Missing cluster_ca_cert variable
**Solution**: Ensure `cluster_ca_cert` is set in k8s/terraform.tfvars and properly base64 decoded

### Error: "kubectl: not found"
**Cause**: kubectl not installed
**Solution**:
```bash
brew install kubectl
# or use the kubeconfig to set up context manually
```

## When to Use Each Stage

| Task | Stage |
|------|-------|
| Create/modify OKE cluster | Stage 1 |
| Change node pool size/shape | Stage 1 |
| Add/remove subnets | Stage 1 |
| Modify NLB configuration | Stage 1 |
| Create Kubernetes namespaces | Stage 2 |
| Deploy Helm charts | Stage 2 |
| Configure RBAC | Stage 2 |
| Deploy applications | Stage 2 |

## Directory Structure
```
oci-infrastructure/
├── infra/                    # Stage 1 - OCI Resources
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── locals.tf
│   ├── network.tf
│   ├── oke.tf
│   ├── nlb.tf
│   ├── outputs.tf
│   └── terraform.tfstate (local) or remote (TC)
│
├── k8s/                      # Stage 2 - Kubernetes + Helm
│   ├── version.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── kubernetes.tf
│   ├── helm.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── terraform.tfstate (local) or remote (TC)
```

## Security Notes

1. **Cluster CA Certificate** is stored as a `sensitive` output - never commit to git
2. **OCI CLI credentials** sourced from `~/.oci/config` - must be secured
3. **exec plugin** runs `oci ce cluster generate-token` for short-lived tokens (best practice)
4. **RBAC** configured for Terraform user - adjust `user_ocid` as needed

## Next Steps

After successful deployment:
1. Access ArgoCD at `https://<NLB_IP>:30443`
2. Set up GitOps workflows with ArgoCD
3. Deploy applications through ArgoCD
4. Monitor with node observability tools
