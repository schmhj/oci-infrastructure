# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Stack

- **Terraform** `>= 1.5`, Oracle OCI provider `~> 5.45`, state in **Terraform Cloud** (org: `schmhj`)
- **GitHub Actions** for CI/CD (deploy, destroy, node pool scheduling)
- **ArgoCD** `7.8.26` (Helm), **Kubeseal** `0.34.0`, **ArgoCD CLI** `2.14.1`
- Node shape `VM.Standard.A1.Flex` (Ampere ARM); node image filter enforces `aarch64` only

## Commands

All Terraform commands are run **per-environment** from within the environment directory:

```bash
# Plan (dry-run) — run from environment dir
cd environments/tenant-a && terraform init && terraform plan -input=false

# Apply
cd environments/tenant-a && terraform apply -auto-approve -input=false

# Destroy
cd environments/tenant-a && terraform destroy -auto-approve -input=false
```

There is no local testing, linting (`terraform fmt`/`validate`), or pre-commit hook. All validation happens in CI.

## Architecture (Non-Obvious)

- **Two-stage deployment**: (1) Terraform provisions OCI infra (VCN, OKE, NLB) → (2) GitHub Actions installs ArgoCD + Kubeseal via shell scripts. The `argocd-deploy` job depends on `oke-deploy` and passes cluster IDs/NLB IPs through job outputs.
- **Terraform Cloud remote state**: state is in TFC, not local or S3. Each environment maps to a TFC workspace (`oke-tenant-a`, `oke-tenant-b`). CI sets `TF_TOKEN_app_terraform_io`.
- **`check_changes.sh` gates plan/apply**: on PRs → plan only; on push to main → apply; on `workflow_dispatch` → manual choice. Change detection uses `git diff HEAD^ HEAD` filtered by path prefixes.

## Conventions & Gotchas

- **Subnet CIDRs are auto-derived**, not read from `.auto.tfvars`. [`locals.tf`](modules/oke/locals.tf:40-41) extracts VCN's first two octets and appends `.0.0/24` (public) and `.1.0/24` (private). Setting `public_subnet_cidr` in tfvars has no effect.
- **Node port `30443` is the ArgoCD ingress entry point** and must stay in sync across [`config.sh`](.github/config.sh:12), [`nlb.tf`](modules/oke/nlb.tf:29) (`var.node_port`), and the ArgoCD Helm install flags. NLB listens on TCP 443 → forwards to node port 30443 on workers.
- **3 placement configs are always created** in the node pool regardless of `node_count`. Nodes are distributed across ADs 0/1/2, but the placement blocks are unconditional. If `node_count < 3`, some ADs will simply have zero nodes.
- **`install.sh` intentionally disables `set -euo pipefail`** (line 3 is commented out) because the script uses `||` fallback patterns (e.g., `helm repo add ... || warn "..."`) that would exit prematurely under strict mode.
- **All `.github/scripts/*.sh` source [`config.sh`](.github/config.sh)** by resolving `$(dirname "${BASH_SOURCE[0]}")/..` — they depend on being invoked from the repo root so the relative path to `config.sh` resolves correctly.
- **`.auto.tfvars` files are committed** (`.gitignore` has `!*.auto.tfvars`). Non-sensitive defaults (CIDRs, shapes, sizes) live there. **Sensitive values** (tenancy_ocid, user_ocid, fingerprint, private_key) come from **Terraform Cloud workspace variables**, not committed files.
- **`setup_oci_credentials.sh`** writes the private key to a `.tmp` file first then `mv`s it — prevents consuming a partially written key if the process is interrupted. Uses a `trap` for cleanup.
- **Node pool scheduling** (`oke-nodepool-schedule.yaml`) uses per-tenant timezones (`America/New_York` for both — both tenants now live in `us-ashburn-1`) with a cron that runs every 15 minutes. Scale-to-zero at 10 PM local, scale-back at 8 AM local. Uses `oci ce node-pool update` directly (not Terraform) for speed.
- **Destroy workflow requires literal `"DESTROY"`** as input and validates the cluster OCID format (`^ocid1\.cluster\.oc1\..+`) before proceeding. Also checks that the cluster isn't already DELETING/DELETED via OCI CLI.
- **Cross-tenancy LPG peering requires 3 IAM statements per tenancy** (not 2). The `associate` statement is critical for `ConnectLocalPeeringGateways` API. See [`vcn-peering-implementation.md`](docs/vcn-peering-implementation.md) for the exact policy syntax. Omitting `associate` causes HTTP 404 `NotAuthorizedOrNotFound` on `peer_id` update.

## Secrets & Environment Variables

All sensitive values go through **GitHub Environment secrets** (two environments: `oke-tenant-a`, `oke-tenant-b`):

| Secret | Used By |
|--------|---------|
| `TF_CLOUD_TOKEN` | Terraform Cloud auth |
| `OCI_TENANCY_OCID`, `OCI_USER_OCID`, `OCI_FINGERPRINT`, `OCI_PRIVATE_KEY` | OCI CLI + Terraform provider |
| `ARGOCD_ADMIN_PASSWORD` | ArgoCD admin password update |
| `TLS_KEY_PEM`, `TLS_CERT_PEM` | TLS secret for ArgoCD ingress |
| `OCI_REGION`, `OCI_DEFAULT_REGION` | GitHub Actions vars (not secrets) |