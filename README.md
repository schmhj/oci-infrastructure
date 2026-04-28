# OCI Kubernetes Infrastructure (OKE)

A production-ready, multi-region Terraform infrastructure for deploying Oracle Kubernetes Engine (OKE) clusters with ArgoCD, Kubeseal, and GitOps automation.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Project Structure](#project-structure)
3. [Terraform Architecture](#terraform-architecture)
   - [Directory Structure](#directory-structure)
   - [Environments](#environments)
   - [Common Module](#common-module)
4. [OCI Infrastructure](#oci-infrastructure)
5. [Network Configuration](#network-configuration)
6. [GitHub Actions Workflows](#github-actions-workflows)
7. [ArgoCD Installation & Configuration](#argocd-installation--configuration)
8. [Helper Scripts Reference](#helper-scripts-reference)
9. [Prerequisites](#prerequisites)
10. [Quick Start](#quick-start)
11. [Deployment Guide](#deployment-guide)

---

## Project Overview

This project automates the deployment of:

- **Multi-region OKE Clusters** - Kubernetes clusters in us-ashburn-1 and us-chicago-1
- **VCN Networking** - Virtual Cloud Networks with public/private subnets, security lists, and multi-region DRG support
- **Network Load Balancer (NLB)** - Public load balancing for ArgoCD and Kubernetes API
- **ArgoCD** - GitOps continuous deployment framework
- **Kubeseal** - Sealed secrets for encrypted secret management
- **RBAC Configuration** - Kubernetes role-based access control for Terraform and GitOps
- **CI/CD Automation** - GitHub Actions workflows for automated provisioning and deployment

**Key Features:**
- ✅ Infrastructure as Code (Terraform) with remote state management (Terraform Cloud)
- ✅ Multi-region deployment support
- ✅ Automated ArgoCD setup with sealed secrets
- ✅ GitOps-ready bootstrapping
- ✅ Complete CI/CD pipeline with GitHub Actions
- ✅ Modular architecture for reusability

---

## Project Structure

```
oci-infrastructure/
├── modules/                           # Reusable Terraform modules
│   └── oke/                          # OKE cluster + networking module
│       ├── versions.tf               # Provider versions
│       ├── providers.tf              # OCI provider configuration
│       ├── variables.tf              # Input variables
│       ├── locals.tf                 # Local computed values (naming, CIDRs)
│       ├── network.tf                # VCN, subnets, security lists
│       ├── oke.tf                    # OKE cluster and node pool
│       ├── nlb.tf                    # Network Load Balancer
│       └── outputs.tf                # Cluster ID, endpoints, NLB IP, kubeconfig
│
├── environments/                      # Environment-specific configurations
│   ├── us-ashburn/                   # Ashburn region deployment
│   │   ├── backend.tf                # Terraform Cloud state backend
│   │   ├── versions.tf               # Provider versions
│   │   ├── variables.tf              # Environment variables
│   │   ├── main.tf                   # Module instantiation
│   │   ├── outputs.tf                # Environment-level outputs
│   │   └── us-ashburn.auto.tfvars    # Ashburn-specific configuration
│   │
│   └── us-chicago/                   # Chicago region deployment
│       ├── backend.tf                # Terraform Cloud state backend
│       ├── versions.tf               # Provider versions
│       ├── variables.tf              # Environment variables
│       ├── main.tf                   # Module instantiation
│       ├── outputs.tf                # Environment-level outputs
│       └── us-chicago.auto.tfvars    # Chicago-specific configuration
│
├── .github/                           # GitHub automation
│   ├── workflows/
│   │   ├── oke-deploy.yaml           # Main CI/CD pipeline
│   │   └── destroy.yaml              # Cleanup workflow
│   │
│   ├── scripts/                       # Helper and setup scripts
│   │   ├── check_changes.sh          # Change detection for targeted deployment
│   │   ├── setup_oci_credentials.sh  # OCI CLI credential setup
│   │   ├── kubeconfig.sh             # Kubeconfig generation
│   │   ├── configure_tls_secret.sh   # TLS secret configuration
│   │   ├── install.sh                # ArgoCD & Kubeseal installation
│   │   ├── argocd_start.sh           # ArgoCD service startup
│   │   ├── argocd_updatepwd.sh       # Admin password configuration
│   │   ├── argocd_sa_config.sh       # Service account & RBAC setup
│   │   ├── argocd_patch.sh           # ArgoCD patches and customizations
│   │   └── kubeconfig.sh             # Local kubeconfig generation (dev only)
│   │
│   ├── argocd/
│   │   ├── config-update.yaml        # ArgoCD RBAC and configuration
│   │   └── argocd-server-service-patch.yaml  # Service customizations
│   │
│   └── config.sh                      # Centralized CI/CD configuration (versions, functions)
│
├── docs/                              # Documentation
│   └── NETWORK.md                     # Network architecture, CIDR planning, DRG setup
│
├── README.md                          # This file
└── .gitignore                         # Git ignore rules

```

---

## Terraform Architecture

### Directory Structure

```
Two-Stage Deployment Model:

┌─────────────────────────────────────────────────────────────┐
│ Stage 1: OCI Infrastructure (modules/oke)                   │
├─────────────────────────────────────────────────────────────┤
│ • OKE Cluster                                               │
│ • VCN + Subnets                                             │
│ • Security Lists                                            │
│ • Network Load Balancer                                     │
│ • Output: cluster_id, endpoint, ca_cert, kubeconfig        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ├─→ Terraform Cloud Remote State
                     │
┌────────────────────▼────────────────────────────────────────┐
│ Stage 2: Kubernetes + GitOps (GitHub Actions)              │
├─────────────────────────────────────────────────────────────┤
│ • ArgoCD Installation via Helm                             │
│ • Kubeseal (Sealed Secrets)                                │
│ • RBAC Configuration                                        │
│ • Bootstrap AppProjects & Root App                         │
│ • Source: Stage 1 outputs via remote state                 │
└─────────────────────────────────────────────────────────────┘
```

### Environments

Each environment is deployed independently and can manage its own region(s). The architecture supports a matrix strategy in GitHub Actions.

#### Ashburn Region (`environments/us-ashburn/`)

**Configuration File**: `us-ashburn.auto.tfvars`

```hcl
# Core OCI Settings
tenancy_ocid           = "ocid1.tenancy.oc1..."
compartment_id         = "ocid1.compartment.oc1..."
region                 = "us-ashburn-1"
availability_domain    = "AD-1"

# Kubernetes Configuration
kubernetes_version     = "v1.29.1"
node_pool_initial_size = 3
node_pool_name         = "oke-worker-pool-ashburn"
node_shape             = "VM.Standard.E4.Flex"  # Supports autoscaling

# Networking
vcn_cidr                = "10.1.0.0/16"    # VCN for Ashburn
public_subnet_cidr      = "10.1.0.0/24"    # NLB subnet
private_subnet_cidr     = "10.1.1.0/24"    # Worker nodes subnet

# Network Load Balancer Access Control
nlb_allowed_cidr_blocks = ["0.0.0.0/0"]    # Allow all (restrict for production)

# Multi-Region DRG (Optional)
enable_drg              = false
# drg_id                = "ocid1.drg.oc1..."
# peer_region_pods_cidr = "10.2.244.0/22"  # Chicago pods CIDR
```

#### Chicago Region (`environments/us-chicago/`)

**Configuration File**: `us-chicago.auto.tfvars`

```hcl
# Similar structure to Ashburn with region-specific values
vcn_cidr                = "10.2.0.0/16"
public_subnet_cidr      = "10.2.0.0/24"
private_subnet_cidr     = "10.2.1.0/24"
```

**Backend Configuration** (`backend.tf`):
- Uses Terraform Cloud for state management
- Organization: `schmhj`
- Workspaces: `cloud-workspace-oke-ashburn`, `cloud-workspace-oke-chicago`

### Common Module

The `modules/oke/` module is a reusable, production-grade Terraform module that encapsulates:

#### 1. **VCN & Networking** (`network.tf`)
- Virtual Cloud Network (VCN) creation
- Public subnet (for NLB)
- Private subnet (for worker nodes)
- Internet Gateway (IGW) - for public subnet egress
- NAT Gateway (NAT GW) - for private subnet egress to internet
- Service Gateway (SGW) - for OCI service access (e.g., Object Storage)
- Security Lists - ingress/egress rules for both subnets
- Route tables with automatic CIDR computation

**Key Configuration:**
```hcl
# VCN CIDR derives subnet CIDRs automatically
vcn_cidr = "10.1.0.0/16"    # Subnets: .0.0/24 (public), .1.0/24 (private)

# Multi-region DRG peering (optional)
enable_drg = true
drg_id = "ocid1.drg.oc1.iad..."
```

#### 2. **OKE Cluster & Node Pool** (`oke.tf`)
- Kubernetes cluster creation (configurable version)
- Automatic kubeconfig generation via data source
- Node pool with autoscaling (min/max nodes)
- Kubernetes network CIDRs (pods: 10.244.0.0/16, services: 10.96.0.0/16)

**Key Configuration:**
```hcl
kubernetes_version       = "v1.29.1"
node_pool_initial_size   = 3          # Starting node count
node_pool_min_size       = 1          # Autoscaling minimum
node_pool_max_size       = 10         # Autoscaling maximum
node_shape               = "VM.Standard.E4.Flex"
```

#### 3. **Network Load Balancer** (`nlb.tf`)
- Public-facing load balancer for ArgoCD and Kubernetes API
- Listener on port 443 (HTTPS/TCP) → backends port 30443 (NodePort)
- Health checks via kubelet port (10256)
- IP allowlist control via `nlb_allowed_cidr_blocks`

**Key Configuration:**
```hcl
nlb_allowed_cidr_blocks = ["0.0.0.0/0"]  # Restrict for production
# For production: ["203.0.113.0/24", "198.51.100.0/24"]
```

#### 4. **Variables & Locals** (`variables.tf`, `locals.tf`)
- **Inputs**: OCI credentials, compartment ID, node shape, CIDR blocks, etc.
- **Locals**: Computed naming conventions, resource labels, derived CIDR values
- **Outputs**: cluster_id, cluster_endpoint, ca_cert, kubeconfig_content, nlb_public_ip

---

## OCI Infrastructure

### Infrastructure Components

#### 1. **Virtual Cloud Network (VCN)**
- Isolated network boundary for the Kubernetes cluster
- CIDR block: 10.1.0.0/16 (Ashburn) or 10.2.0.0/16 (Chicago)
- Supports DRG peering for multi-region communication

#### 2. **Subnets**
- **Public Subnet**: Hosts the NLB, routes to Internet Gateway
  - CIDR: 10.1.0.0/24 (Ashburn) / 10.2.0.0/24 (Chicago)
  - Internet access: Outbound to 0.0.0.0/0

- **Private Subnet**: Hosts OKE worker nodes, routes to NAT Gateway
  - CIDR: 10.1.1.0/24 (Ashburn) / 10.2.1.0/24 (Chicago)
  - Egress-only (no inbound from internet)

#### 3. **Security Lists**
Define ingress/egress rules for network traffic:

**Public Subnet Security List:**
```
Ingress:
  ├─ TCP 443 from nlb_allowed_cidr_blocks → NLB HTTPS (ArgoCD)
  ├─ TCP 6443 from nlb_allowed_cidr_blocks → Kubernetes API
  └─ All protocols from VCN CIDR → Internal traffic

Egress:
  ├─ All protocols to 0.0.0.0/0 → Internet
  ├─ TCP 30443 to private subnet → NodePort traffic
  └─ TCP 10256 to private subnet → Kubelet health checks
```

**Private Subnet Security List:**
```
Ingress:
  ├─ All protocols from VCN CIDR → Internal traffic
  ├─ TCP 10256 from public subnet → NLB health checks
  └─ TCP 30443 from public subnet → NodePort traffic

Egress:
  └─ All protocols to 0.0.0.0/0 → NAT Gateway (egress-only)
```

#### 4. **Network Load Balancer (NLB)**
- **Purpose**: Public endpoint for ArgoCD UI and Kubernetes API
- **Port Mapping**: 443 (public) → 30443 (NodePort)
- **Health Checks**: TCP port 10256 (kubelet)
- **Access Control**: Configurable via `nlb_allowed_cidr_blocks`

**Accessing Services:**
```bash
# Get NLB public IP
NLB_IP=$(terraform output -raw nlb_public_ip)

# Access ArgoCD
https://${NLB_IP}:30443

# Kubernetes API (via NLB)
kubectl --server=https://${NLB_IP}:6443 get nodes
```

#### 5. **OKE Cluster**
- **Kubernetes Version**: v1.29.1 (configurable)
- **Worker Nodes**: Compute instances in private subnet
- **Pod CIDR**: 10.244.0.0/16 (same across regions)
- **Service CIDR**: 10.96.0.0/16 (same across regions)
- **Kubeconfig**: Generated via data source, used by argocd-deploy job

---

## Network Configuration

For comprehensive network architecture, CIDR planning, security policies, and multi-region DRG setup, refer to:

📖 **[docs/NETWORK.md](docs/NETWORK.md)**

**Key Topics Covered:**
- Network architecture diagram
- CIDR allocation strategy (VCN, subnets, pods, services)
- Security configuration and IP allowlisting
- Multi-region connectivity with DRG
- Network security lists in detail
- Routing configuration
- NLB configuration and health checks
- Troubleshooting network issues

---

## GitHub Actions Workflows

### Main Deployment Workflow (`oke-deploy.yaml`)

This is the primary CI/CD pipeline that automates OKE provisioning and ArgoCD setup.

#### **Workflow Triggers**

```yaml
on:
  pull_request:              # Run on PRs to main
    branches: [main]
    paths:                   # Only if these paths changed
      - 'environments/**'
      - 'modules/**'
      - '.github/scripts/**'
      - '.github/argocd/**'
      - '.github/config.sh'

  push:                      # Run on merges to main
    branches: [main]
    paths: [same as above]

  workflow_dispatch:         # Manual trigger with options
    inputs:
      action:
        description: 'Choose action'
        type: choice
        options:
          - plan          # Only preview changes
          - apply         # Apply infrastructure
          - plan_and_apply # Plan then apply
```

#### **Job 1: OKE Provisioning** (`oke-deploy`)

**Purpose**: Deploy OCI infrastructure (VCN, OKE cluster, NLB) for each region.

**Matrix Strategy**: Runs for both regions in parallel
- **us-ashburn-1**: `environments/us-ashburn` → `oke-us-ashburn` environment
- **us-chicago-1**: `environments/us-chicago` → `oke-us-chicago` environment

**Steps Breakdown:**

##### 1. **Checkout Code**
```yaml
- Checkout
  uses: actions/checkout@v4
  fetch-depth: 0  # Full history for change detection
```
Downloads the repository code into the runner.

##### 2. **Check for Changes**
```yaml
- Check for changes in oke
  run: ./.github/scripts/check_changes.sh
```
Determines whether to run plan/apply based on:
- File changes in the watched paths
- GitHub event type (PR, push, manual dispatch)
- Outputs: `run_plan=true/false`, `run_apply=true/false`

**Logic:**
- PR: Always run plan, never apply
- Push to main: Run plan + apply
- Manual dispatch: Use selected action

##### 3. **Setup Terraform**
```yaml
- Setup Terraform
  if: steps.filter.outputs.run_plan == 'true'
  uses: hashicorp/setup-terraform@v3
```
Configures Terraform CLI with credentials from `TF_TOKEN_app_terraform_io` secret.

##### 4. **Cache Terraform Plugins**
```yaml
- Cache Terraform Plugins
  uses: actions/cache@v4
  key: ${{ runner.os }}-terraform-plugin-${{ hashFiles('**/.terraform.lock.hcl') }}
```
Caches downloaded provider plugins to speed up subsequent runs.

##### 5. **Verify Module Paths** (Debug)
```yaml
- Debug - Verify Module Path
  run: cd ${{ matrix.working_dir }} && ls -la ../../modules/oke/
```
Ensures module can be found from environment working directory.

##### 6. **Terraform Init**
```yaml
- Terraform Init
  working-directory: ${{ matrix.working_dir }}
  run: |
    mkdir -p ~/.terraform.d/plugin-cache
    terraform init -input=false  # Use TF_TOKEN for backend auth
```
- Creates `.terraform/` directory
- Downloads provider plugins
- Configures Terraform Cloud remote state backend
- **Retry Logic**: Attempts init up to 3 times on failure

##### 7. **Terraform Plan**
```yaml
- Terraform Plan
  working-directory: ${{ matrix.working_dir }}
  run: terraform plan -no-color -input=false
```
- Generates execution plan without applying
- Output shown in logs for manual review
- `-no-color`: Strip ANSI colors for GitHub display

##### 8. **Terraform Apply**
```yaml
- Terraform Apply
  if: steps.filter.outputs.run_apply == 'true'
  working-directory: ${{ matrix.working_dir }}
  run: terraform apply -auto-approve -input=false
```
- Only runs if `run_apply=true` (push to main or manual apply)
- `-auto-approve`: Skip confirmation prompt
- Creates/updates OCI resources (VCN, OKE, NLB)

##### 9. **Export Cluster Outputs**
```yaml
- Export Cluster ID
  id: get_cluster_id
  run: |
    CLUSTER_ID=$(terraform output -raw cluster_id)
    NLB_PUBLIC_IP=$(terraform output -raw nlb_public_ip)
    echo "cluster_id_${REGION}=${CLUSTER_ID}" >> $GITHUB_OUTPUT
    echo "nlb_public_ip_${REGION}=${NLB_PUBLIC_IP}" >> $GITHUB_OUTPUT
```
- Extracts OKE cluster ID and NLB public IP from Terraform outputs
- Stores as job outputs for downstream jobs (argocd-deploy)
- Enables multi-region orchestration

##### 10. **Job Summary**
```yaml
- Job Summary
  run: echo "## OCI Provisioning Summary" >> $GITHUB_STEP_SUMMARY
```
Displays results in GitHub Actions job summary UI.

---

#### **Job 2: ArgoCD Deployment & Bootstrap** (`argocd-deploy`)

**Purpose**: Configure Kubernetes, deploy ArgoCD, and bootstrap GitOps applications.

**Dependencies**: Runs only after `oke-deploy` succeeds and outputs cluster IDs.

**Matrix Strategy**: Runs for each region (same as oke-deploy)

**Steps Breakdown:**

##### 1. **Checkout Code & Checkout cluster-config Repo**
```yaml
- Checkout main repo (this repository)
- Checkout cluster-config repo (separate repo with bootstrap apps)
  repository: schmhj/cluster-config
  token: ${{ secrets.GH_PAT_SECRET_ADMIN }}
```
Prepares both the infrastructure code and the GitOps application definitions.

##### 2. **Install OCI CLI & kubectl**
```yaml
- Install OCI CLI & kubectl
  run: |
    sudo apt-get update && sudo apt-get install -y python3-pip
    pip3 install --upgrade oci-cli
```
Installs tools needed for:
- OCI CLI: Generate short-lived Kubernetes tokens
- kubectl: Deploy applications to cluster

##### 3. **Setup OCI Credentials**
```yaml
- Setup OCI credentials
  run: ./.github/scripts/setup_oci_credentials.sh
  env:
    OCI_TENANCY: ${{ secrets.OCI_TENANCY_OCID }}
    OCI_USER: ${{ secrets.OCI_USER_OCID }}
    OCI_FINGERPRINT: ${{ secrets.OCI_FINGERPRINT }}
    OCI_PRIVATE_KEY: ${{ secrets.OCI_PRIVATE_KEY }}
```
- Creates `~/.oci/config` file from GitHub secrets
- Configures OCI CLI with authentication
- Enables `oci ce cluster generate-token` command

##### 4. **Generate Kubeconfig**
```yaml
- Generate Kubeconfig
  run: ./.github/scripts/kubeconfig.sh
  env:
    CLUSTER_ID: ${{ needs.oke-deploy.outputs.cluster_id_us-ashburn-1 }}
    REGION: ${{ vars.OCI_REGION }}
```
- Uses OCI CLI to generate kubeconfig
- Configures `~/.kube/config` with cluster endpoint and auth
- Uses exec-based authentication (short-lived tokens)

##### 5. **Setup TLS Secret**
```yaml
- Setup TLS Secret
  run: ./.github/scripts/configure_tls_secret.sh
  env:
    SECRETS_PRIVATE_KEY: ${{ secrets.TLS_KEY_PEM }}
    SECRETS_PUBLIC_KEY: ${{ secrets.TLS_CERT_PEM }}
```
- Creates TLS certificate secret for Kubeseal
- Stored in `kube-system` namespace
- Used for encrypting Kubernetes secrets

##### 6. **Install ArgoCD and Kubeseal**
```yaml
- Install ArgoCD and Kubeseal Sealed Secrets
  run: ./.github/scripts/install.sh
```
- Adds Helm repositories (ArgoCD)
- Installs ArgoCD Helm chart (v7.8.26)
- Installs Kubeseal binary and sealed-secrets controller

**ArgoCD Installation Details:**
```bash
helm upgrade --install argocd argo/argo-cd \
  --version 7.8.26 \
  --namespace argocd \
  --create-namespace \
  --set "server.extraArgs={--insecure}" \
  --set "server.service.type=NodePort" \
  --set "server.service.nodePortHttps=30179"
```

##### 7. **Start ArgoCD**
```yaml
- Start Argocd
  run: ./.github/scripts/argocd_start.sh
```
- Waits for ArgoCD deployment to be ready
- Polls until argocd-server is available
- Enables ArgoCD CLI commands

##### 8. **Update ArgoCD Admin Password**
```yaml
- Update ArgoCD Initial Admin Password
  run: ./.github/scripts/argocd_updatepwd.sh
  env:
    NLB_PUBLIC_IP: ${{ needs.oke-deploy.outputs.nlb_public_ip_us-ashburn-1 }}
    ARGOCD_ADMIN_PASSWORD: ${{ secrets.ARGOCD_ADMIN_PASSWORD }}
```
- Retrieves initial admin password from Kubernetes secret
- Logs into ArgoCD via port-forward
- Updates password to configured value
- Patches ConfigMap with NLB external URL

##### 9. **ArgoCD Configuration (RBAC & Service Account)**
```yaml
- Argocd Configuration
  run: ./.github/scripts/argocd_sa_config.sh
```
- Applies RBAC configuration from `config-update.yaml`
- Creates service accounts for Terraform and GitOps
- Configures ArgoCD project permissions

**Configuration Details:**
- Creates `argocd` AppProject for app management
- Sets up read/write permissions for service accounts
- Enables application sync impersonation

##### 10. **ArgoCD Patching**
```yaml
- Argocd Patching
  run: ./.github/scripts/argocd_patch.sh
```
- Applies ArgoCD server service patch
- Enables Helm support in Kustomize
- Configures insecure mode for self-signed certificates
- Restarts ArgoCD server deployment

##### 11. **Bootstrap ArgoCD Projects & Apps**
```yaml
- Apply AppProjects App
  run: kubectl apply -f bootstrap/prod/appprojects-app.yaml
  
- Apply Root App
  run: kubectl apply -f bootstrap/prod/root-app.yaml
```
- Checks out `cluster-config` repository
- Applies bootstrap ArgoCD Applications
- AppProjects app: Manages application projects and RBAC
- Root app: Bootstraps core infrastructure applications

---

### Destroy Workflow (`destroy.yaml`)

Safely removes all infrastructure with confirmation steps.

**Workflow**: Manual trigger only
**Steps**: Terraform destroy with `-auto-approve`
**Cleanup**: Removes OKE clusters, VCN, and NLB

---

## ArgoCD Installation & Configuration

### Overview

ArgoCD is installed and configured through the CI/CD pipeline to enable GitOps continuous deployment. The installation process includes multiple stages:

```
┌─────────────────────────────────────────────────────┐
│ 1. Helm Installation                                │
│    └─ Deploy ArgoCD server, controller, dex, etc.  │
├─────────────────────────────────────────────────────┤
│ 2. Initial Setup                                    │
│    └─ Wait for deployment readiness                │
├─────────────────────────────────────────────────────┤
│ 3. Admin Password Update                            │
│    └─ Configure initial password                   │
├─────────────────────────────────────────────────────┤
│ 4. RBAC & Service Accounts                          │
│    └─ Create accounts for automation               │
├─────────────────────────────────────────────────────┤
│ 5. ArgoCD Patching                                  │
│    └─ Apply customizations and configs             │
├─────────────────────────────────────────────────────┤
│ 6. Application Bootstrap                           │
│    └─ Deploy seed applications (AppProjects, Root) │
└─────────────────────────────────────────────────────┘
```

### Stage 1: ArgoCD Helm Installation (`install.sh`)

**Purpose**: Install ArgoCD using Helm chart.

**Configuration**:
```bash
# Version
ARGOCD_HELM_VERSION="7.8.26"
ARGOCD_HELM_REPO="https://argoproj.github.io/argo-helm"
ARGOCD_HELM_CHART="argo/argo-cd"

# Kubernetes
ARGOCD_HELM_NAMESPACE="argocd"
ARGOCD_NODE_PORT_HTTPS=30179  # NodePort for UI access
```

**Installation Command**:
```bash
helm upgrade --install argocd argo/argo-cd \
  --version 7.8.26 \
  --namespace argocd \
  --create-namespace \
  --set "server.extraArgs={--insecure}" \
  --set "server.service.type=NodePort" \
  --set "server.service.nodePortHttps=30179" \
  --set "configs.cm.kustomize.buildOptions=--enable-helm" \
  --set "configs.cm.application.sync.impersonation.enabled=true"
```

**Key Settings**:
- `--insecure`: Skip SSL verification (self-signed cert from NLB)
- `service.type=NodePort`: Expose via node port 30443
- `kustomize.buildOptions`: Enable Helm plugin for Kustomize
- `application.sync.impersonation.enabled`: Allow service accounts to sync apps

**Installation Checks**:
```bash
# Already installed? Skip and proceed
helm list -n argocd | grep "^argocd"

# Fresh install
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

### Stage 2: ArgoCD Startup (`argocd_start.sh`)

**Purpose**: Wait for ArgoCD deployment to be ready.

**Process**:
```bash
# Poll deployment status
kubectl rollout status deployment/argocd-server \
  -n argocd \
  --timeout=5m
```

**Readiness Checks**:
- All pods running (server, controller, dex, redis)
- Service port exposed
- Health endpoint responding

---

### Stage 3: Admin Password Update (`argocd_updatepwd.sh`)

**Purpose**: Configure initial admin password and external URL.

**Process**:

#### 3.1 Retrieve Initial Password
```bash
ARGOCD_INITIAL_PASS=$(kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath='{.data.password}' | base64 -d)
```
- Kubernetes secret created during Helm installation
- Contains auto-generated admin password

#### 3.2 Port-Forward for CLI Access
```bash
kubectl port-forward -n argocd svc/argocd-server 30179:443 &
PORT_FORWARD_PID=$!
sleep 2  # Wait for tunnel to establish
```
- Enables local ArgoCD CLI access
- Runs in background
- Cleaned up after password update

#### 3.3 Attempt Login with New Password
```bash
argocd login --insecure \
  --username admin \
  --password "$ARGOCD_ADMIN_PASSWORD" \
  --grpc-web "localhost:30179"
```
- Checks if password already configured
- If successful, skip update (idempotent)

#### 3.4 Update Password (if needed)
```bash
argocd account update-password \
  --insecure \
  --current-password "$ARGOCD_INITIAL_PASS" \
  --new-password "$ARGOCD_ADMIN_PASSWORD"
```
- Uses initial password to authenticate
- Updates to GitHub secret value
- Password stored in Kubernetes secret

#### 3.5 Configure External URL
```bash
ARGOCD_URL="https://${NLB_PUBLIC_IP}"

kubectl patch configmap/argocd-cm \
  -n argocd \
  --type=json \
  -p="[{\"op\": \"replace\", \"path\": \"/data/url\", \"value\":\"${ARGOCD_URL}\"}]"
```
- Sets ArgoCD's external URL in ConfigMap
- Used for webhooks, SSO redirects, etc.
- Format: `https://NLB_IP:30443`

---

### Stage 4: RBAC & Service Account Configuration (`argocd_sa_config.sh`)

**Purpose**: Configure Kubernetes RBAC and service accounts for automation.

**Configuration File**: `.github/argocd/config-update.yaml`

**Resources Created**:

#### 4.1 Namespace
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
```

#### 4.2 AppProject for Application Management
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: argocd
  namespace: argocd
spec:
  destinations:
    - namespace: 'argocd'
      server: https://kubernetes.default.svc
  sourceRepos:
    - 'https://github.com/schmhj/*'
    - 'https://argoproj.github.io/argo-helm'
  roles:
    - name: admin
      policies:
        - p, proj:argocd:admin, applications, *, argocd/*, allow
    - name: terraform
      policies:
        - p, proj:argocd:terraform, applications, create, argocd/*, allow
        - p, proj:argocd:terraform, applications, delete, argocd/*, allow
        - p, proj:argocd:terraform, applications, update, argocd/*, allow
```

#### 4.3 Service Accounts
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: terraform
  namespace: argocd

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitops
  namespace: argocd
```

#### 4.4 RBAC Roles
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: terraform-role
  namespace: argocd
rules:
  - apiGroups: ['argoproj.io']
    resources: ['applications', 'appprojects']
    verbs: ['get', 'list', 'create', 'update', 'patch', 'delete']

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: terraform-rolebinding
  namespace: argocd
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: terraform-role
subjects:
  - kind: ServiceAccount
    name: terraform
    namespace: argocd
```

---

### Stage 5: ArgoCD Patching (`argocd_patch.sh`)

**Purpose**: Apply customizations and patches to ArgoCD deployment.

**Patch File**: `.github/argocd/argocd-server-service-patch.yaml`

**Patches Applied**:

#### 5.1 Service Patch
```yaml
apiVersion: v1
kind: Service
metadata:
  name: argocd-server
  namespace: argocd
spec:
  type: NodePort
  ports:
    - name: http
      port: 80
      targetPort: 8080
      nodePort: 30180
    - name: https
      port: 443
      targetPort: 8443
      nodePort: 30443
```
- Exposes ArgoCD on NodePort 30443
- Accessible via NLB on port 443

#### 5.2 ConfigMap Patch
```bash
kubectl patch configmap argocd-cm -n argocd --type merge \
  -p '{"data":{"kustomize.buildOptions":"--enable-helm", "application.sync.impersonation.enabled":"true"}}'
```
- Enables Helm support in Kustomize
- Allows sync impersonation for RBAC isolation

#### 5.3 Deployment Patch
```bash
kubectl patch deployment argocd-server -n argocd --type json \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--insecure"}]'
```
- Adds `--insecure` flag for SSL verification bypass
- Necessary for self-signed certificates

#### 5.4 Restart Deployment
```bash
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=5m
```
- Restarts pods to apply patches
- Waits for deployment to be ready

---

### Stage 6: Application Bootstrap

**Purpose**: Deploy seed applications from GitOps repository.

**Source Repository**: `schmhj/cluster-config`

#### 6.1 AppProjects Application
```bash
kubectl apply -f bootstrap/prod/appprojects-app.yaml
```
- Creates ArgoCD AppProject resource
- Manages project-level RBAC and source repositories
- Enables multi-team application deployments

#### 6.2 Root Application
```bash
kubectl apply -f bootstrap/prod/root-app.yaml
```
- Master ArgoCD Application that syncs all cluster state
- Uses App-of-Apps pattern
- Automatically syncs child applications on commit

**Structure**:
```
Root App (cluster-config repo)
├── AppProjects App
│   ├── Project 1
│   │   ├── App A
│   │   └── App B
│   └── Project 2
│       └── App C
└── Infrastructure App
    ├── Ingress
    ├── Storage
    └── Monitoring
```

---

## Helper Scripts Reference

All scripts are located in `.github/scripts/` and are sourced from `.github/config.sh`.

### Configuration & Utilities (`config.sh`)

**Purpose**: Centralized configuration for all CI/CD scripts.

**Exports**:
```bash
# ArgoCD Helm Configuration
ARGOCD_HELM_VERSION="7.8.26"
ARGOCD_HELM_REPO="https://argoproj.github.io/argo-helm"
ARGOCD_HELM_NAMESPACE="argocd"
ARGOCD_NODE_PORT_HTTPS=30179

# Kubeseal Configuration
KUBESEAL_VERSION="0.34.0"
KUBESEAL_NAMESPACE="kube-system"

# Helper Functions
fail()          # Exit with error
success()       # Print success message
warn()          # Print warning message
require_env()   # Validate environment variable
require_cmd()   # Validate command exists
```

**Usage in Scripts**:
```bash
#!/usr/bin/env bash
source ./.github/config.sh

require_cmd "kubectl"
require_env "CLUSTER_ID"
success "Proceeding with deployment"
```

---

### Change Detection (`check_changes.sh`)

**Purpose**: Determine whether to run plan/apply based on file changes.

**Logic**:
```bash
GITHUB_EVENT_NAME     # push, pull_request, workflow_dispatch
WORKFLOW_INPUT_ACTION # plan, apply, plan_and_apply

# Decision Matrix:
# PR + changes → run_plan=true, run_apply=false
# Push + changes → run_plan=true, run_apply=true
# No changes → run_plan=false, run_apply=false
# Manual + plan → run_plan=true, run_apply=false
# Manual + apply → run_plan=true, run_apply=true
# Manual + plan_and_apply → run_plan=true, run_apply=true
```

**Outputs**:
```bash
echo "run_plan=true" >> $GITHUB_OUTPUT
echo "run_apply=true" >> $GITHUB_OUTPUT
```

---

### OCI Credentials Setup (`setup_oci_credentials.sh`)

**Purpose**: Configure OCI CLI with authentication from GitHub secrets.

**Process**:
```bash
mkdir -p ~/.oci
cat > ~/.oci/config << EOF
[DEFAULT]
tenancy=$OCI_TENANCY
user=$OCI_USER
fingerprint=$OCI_FINGERPRINT
key_file=~/.oci/oci_api_key.pem
region=$OCI_REGION
EOF

# Write private key
cat > ~/.oci/oci_api_key.pem << 'EOF'
$OCI_PRIVATE_KEY
EOF
chmod 600 ~/.oci/oci_api_key.pem
```

**Enables**:
```bash
# Short-lived token generation
oci ce cluster generate-token --cluster-id <CLUSTER_ID>

# Cluster details
oci ce cluster get --cluster-id <CLUSTER_ID>
```

---

### Kubeconfig Generation (`kubeconfig.sh`)

**Purpose**: Generate kubeconfig for Kubernetes access.

**Process**:
```bash
oci ce cluster create-kubeconfig \
  --cluster-id $CLUSTER_ID \
  --file ~/.kube/config \
  --region $REGION
```

**Authentication Method**: Exec-based (OCI CLI generates short-lived tokens)

**kubeconfig Entry**:
```yaml
- name: exec-cred
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: oci
      args: ["ce", "cluster", "generate-token", "--cluster-id", "<CLUSTER_ID>"]
```

---

### TLS Secret Configuration (`configure_tls_secret.sh`)

**Purpose**: Create Kubernetes TLS secret for Kubeseal.

**Process**:
```bash
# Write certificate and key from secrets
cat > /tmp/cert.pem << EOF
$SECRETS_PUBLIC_KEY
EOF

cat > /tmp/key.pem << EOF
$SECRETS_PRIVATE_KEY
EOF

# Create secret
kubectl create secret tls sealed-secrets-key \
  --cert=/tmp/cert.pem \
  --key=/tmp/key.pem \
  -n kube-system \
  --dry-run=client -o yaml | kubectl apply -f -

# Cleanup
rm -f /tmp/cert.pem /tmp/key.pem
```

**Secret Usage**: Kubeseal uses this key to encrypt/decrypt sealed secrets.

---

### ArgoCD & Kubeseal Installation (`install.sh`)

**Purpose**: Install ArgoCD Helm chart and Kubeseal CLI.

**Tools Installed**:
1. **ArgoCD Helm Chart** (v7.8.26)
   - Server, controller, dex, redis containers
   - RBAC, ConfigMaps, services

2. **Kubeseal Binary** (v0.34.0)
   - Downloaded from GitHub releases
   - Installed to `/usr/local/bin/kubeseal`

3. **ArgoCD CLI** (v2.14.1)
   - Command-line interface for ArgoCD
   - Used for login, password update, app management

**Idempotency**: All tools are checked before installation; skips if already present.

---

### ArgoCD Startup (`argocd_start.sh`)

**Purpose**: Wait for ArgoCD deployment to be ready.

**Process**:
```bash
kubectl rollout status deployment/argocd-server \
  -n argocd \
  --timeout=5m
```

**Exit Codes**:
- `0`: Deployment ready
- Non-zero: Timeout or error (causes workflow to fail)

---

### Admin Password Update (`argocd_updatepwd.sh`)

**Purpose**: Configure ArgoCD admin password and external URL.

**Process**: (Covered in ArgoCD Installation section)

---

### RBAC Configuration (`argocd_sa_config.sh`)

**Purpose**: Apply RBAC and service account configuration.

**File**: `.github/argocd/config-update.yaml`

**Process**:
```bash
kubectl apply -f .github/argocd/config-update.yaml
```

**Resources Managed**:
- ServiceAccounts (terraform, gitops)
- Roles (admin, terraform)
- RoleBindings
- AppProjects

---

### ArgoCD Patching (`argocd_patch.sh`)

**Purpose**: Apply customizations and patches.

**Patches**:
1. Service patch (NodePort configuration)
2. ConfigMap patch (Kustomize + sync impersonation)
3. Deployment patch (--insecure flag)
4. Deployment restart

---

### ArgoCD Utilities

**Delete Projects** (`argocd_delete_projects.sh`):
```bash
# Delete all ArgoCD projects
kubectl delete appproject -n argocd --all
```

**Delete Root App** (`argocd_delete_root_app.sh`):
```bash
# Delete root application
kubectl delete application root-app -n argocd
```

**Uninstall ArgoCD** (`argocd_uninstall.sh`):
```bash
# Remove Helm release
helm uninstall argocd -n argocd
# Delete namespace
kubectl delete namespace argocd
```

---

## Prerequisites

### Local Development Environment

```bash
# OCI CLI
brew install oci-cli

# Terraform
brew install terraform

# Kubectl
brew install kubectl

# Helm
brew install helm

# kubeseal (optional for local secret encryption)
brew install sealed-secrets

# argocd CLI (optional for local access)
brew install argocd
```

### GitHub Secrets Configuration

Create the following secrets in your GitHub repository:

| Secret | Description |
|--------|-------------|
| `TF_CLOUD_TOKEN` | Terraform Cloud API token |
| `OCI_TENANCY_OCID` | OCI tenancy OCID |
| `OCI_USER_OCID` | OCI user OCID |
| `OCI_FINGERPRINT` | OCI API key fingerprint |
| `OCI_PRIVATE_KEY` | OCI private key (PEM format) |
| `TLS_CERT_PEM` | TLS certificate (PEM format) |
| `TLS_KEY_PEM` | TLS private key (PEM format) |
| `ARGOCD_ADMIN_PASSWORD` | Initial ArgoCD admin password |
| `GH_PAT_SECRET_ADMIN` | GitHub PAT for cluster-config repo access |

### GitHub Environment Variables

| Variable | Description |
|----------|-------------|
| `OCI_REGION` | OCI region (e.g., us-ashburn-1) |
| `OCI_DEFAULT_REGION` | Default region for OCI CLI |

---

## Quick Start

### 1. Local Setup

```bash
# Clone repository
git clone https://github.com/schmhj/oci-infrastructure.git
cd oci-infrastructure

# Initialize Terraform for Ashburn
cd environments/us-ashburn
terraform init

# Preview changes
terraform plan -var-file=us-ashburn.auto.tfvars

# Apply infrastructure
terraform apply -var-file=us-ashburn.auto.tfvars
```

### 2. Access ArgoCD

```bash
# Get NLB public IP
NLB_IP=$(cd environments/us-ashburn && terraform output -raw nlb_public_ip)

# Generate kubeconfig
oci ce cluster create-kubeconfig \
  --cluster-id $(cd environments/us-ashburn && terraform output -raw cluster_id) \
  --file ~/.kube/config

# Access ArgoCD
open https://${NLB_IP}:30443

# Or via port-forward
kubectl port-forward -n argocd svc/argocd-server 8080:443
open http://localhost:8080
```

### 3. Test kubectl Access

```bash
# Verify cluster access
kubectl get nodes

# Check ArgoCD
kubectl get deployments -n argocd
```

---

## Deployment Guide

### Single Region Deployment (Ashburn)

```bash
# Navigate to environment
cd environments/us-ashburn

# Initialize (first time only)
terraform init

# Plan
terraform plan -var-file=us-ashburn.auto.tfvars

# Apply
terraform apply -var-file=us-ashburn.auto.tfvars

# Verify
terraform output
```

### Multi-Region Deployment

```bash
# Both regions can be deployed in parallel
# The GitHub Actions workflow handles this via matrix strategy

# Manual deployment:
cd environments/us-ashburn && terraform apply -var-file=us-ashburn.auto.tfvars &
cd environments/us-chicago && terraform apply -var-file=us-chicago.auto.tfvars &
wait
```

### Infrastructure Cleanup

```bash
# Destroy single region
cd environments/us-ashburn
terraform destroy -var-file=us-ashburn.auto.tfvars

# Destroy all
for region in us-ashburn us-chicago; do
  cd environments/$region
  terraform destroy -var-file=${region}.auto.tfvars
  cd ../..
done
```

---

## Troubleshooting

### Terraform State Issues

```bash
# Refresh state
terraform refresh

# Remove problematic resource
terraform state rm <resource>

# See full state
terraform state show
```

### Kubernetes Access Issues

```bash
# Verify kubeconfig
cat ~/.kube/config

# Test cluster connectivity
kubectl cluster-info

# Check node status
kubectl get nodes -o wide
```

### ArgoCD Issues

```bash
# Check deployment status
kubectl get deployments -n argocd

# View logs
kubectl logs -n argocd deployment/argocd-server

# Describe pod
kubectl describe pod -n argocd <pod-name>

# Port-forward for debugging
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

### Network Issues

For detailed network troubleshooting, refer to [docs/NETWORK.md#troubleshooting](docs/NETWORK.md#troubleshooting).

---

## Support & Documentation

- **OKE Documentation**: https://docs.oracle.com/en-us/iaas/Content/ContEng/home.htm
- **Terraform OCI Provider**: https://registry.terraform.io/providers/oracle/oci/latest/docs
- **ArgoCD Documentation**: https://argo-cd.readthedocs.io/
- **Kubeseal Documentation**: https://github.com/bitnami-labs/sealed-secrets

---

## License

[Specify your license]

---

**Last Updated**: 2026-04-28
