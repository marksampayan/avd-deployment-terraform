# AVD Deployment — Terraform IaC + GitHub Actions CI/CD

Terraform code to deploy an **Azure Virtual Desktop** environment (Pooled host pool, Central India)  
with a full GitHub Actions CI/CD pipeline featuring PR-based approval before any deployment.

---

## Architecture

```
GitHub PR → terraform plan (posted as PR comment) → PR Approval
     ↓
Merge to main → "production" environment gate → terraform apply
     ↓
Azure (Subscription: 6598dd7c-4f8f-4a24-9dfa-31a6fb73c32b)
     ├── Resource Group: FIT-AVD-Prod  (centralindia)
     ├── VNet + Subnet (10.1.2.0/24) + NSG
     ├── AVD Host Pool    — Pooled, DepthFirst, 4 sessions/host
     ├── AVD App Group    — Desktop type
     ├── AVD Workspace
     ├── Storage Account  — avdprofile<random> (Premium, FSLogix profiles)
     │    └── File Share: profiles (237 GiB, SMB, AADKERB)
     └── Session Hosts x3 — Standard_E4s_v5, Win11 multi-session + M365
          ├── Entra ID Join extension
          ├── AVD DSC agent extension
          └── Azure Monitor Agent extension
```

---

## CI/CD Flow

```
1. Developer creates branch → makes .tf changes → opens Pull Request to main
        ↓
2. GitHub Actions runs terraform plan automatically
   Posts plan output as a comment on the PR ← Reviewer reads this
        ↓
3. Reviewer approves the PR → Developer merges to main
        ↓
4. GitHub Actions triggers terraform apply
   Waits for "production" environment approval ← Optional second gate
        ↓
5. Resources deployed to Azure → outputs printed (FSLogix UNC path, VM names, etc.)
```

---

## One-Time Bootstrap

Run this **once** before the first GitHub Actions run. Requires Azure CLI and Owner access on the target subscription.

```bash
export GITHUB_ORG=marksampayan
export GITHUB_REPO=avd-deployment-terraform

chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
```

Creates:
- Azure Storage Account for Terraform remote state
- App Registration with OIDC federated credentials (no stored client secrets)
- Service Principal with `Contributor` + `User Access Administrator` roles
- Prints all values needed for GitHub Secrets and Variables

---

## GitHub Repository Setup

### Step 1 — GitHub Secrets
`Settings → Secrets and variables → Actions → New repository secret`

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | From bootstrap output |
| `AZURE_TENANT_ID` | `490c3a5e-c1b8-43f7-9104-e28e6f7bc536` |
| `AZURE_SUBSCRIPTION_ID` | `6598dd7c-4f8f-4a24-9dfa-31a6fb73c32b` |
| `TF_VAR_VM_ADMIN_PASSWORD` | Secure local admin password for session host VMs |

### Step 2 — GitHub Variables
`Settings → Secrets and variables → Actions → New repository variable`

| Variable | Value (from bootstrap output) |
|----------|-------------------------------|
| `TF_STATE_RESOURCE_GROUP` | `rg-terraform-state` |
| `TF_STATE_STORAGE_ACCOUNT` | `stfitavdtfstate<random>` |
| `TF_STATE_CONTAINER` | `tfstate` |

### Step 3 — Production Environment (Approval Gate)
`Settings → Environments → New environment → Name: production`
- Enable **Required reviewers** → add yourself or your team
- This blocks `terraform apply` until a human clicks Approve in GitHub

### Step 4 — Branch Protection on `main`
`Settings → Branches → Add branch protection rule → Branch: main`
- ✅ Require a pull request before merging
- ✅ Require approvals (minimum 1)
- ✅ Require status checks to pass: `Terraform Plan / Terraform Plan`
- ✅ Require branches to be up to date before merging

---

## Local Development

```bash
az login
az account set --subscription "6598dd7c-4f8f-4a24-9dfa-31a6fb73c32b"

terraform init \
  -backend-config="resource_group_name=rg-terraform-state" \
  -backend-config="storage_account_name=<from bootstrap output>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=avd-deployment.tfstate"

export TF_VAR_vm_admin_password="YourPassword"
terraform plan
terraform apply
```

---

## Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `session_host_count` | `3` | Number of session host VMs |
| `vm_size` | `Standard_E4s_v5` | 4 vCPU / 32 GB RAM |
| `max_sessions_per_host` | `4` | Max concurrent sessions per VM |
| `fslogix_share_quota_gb` | `237` | FSLogix profile share size in GiB |
| `enable_hub_peering` | `false` | Enable VNet peering to Entra DS / hub VNet |
| `use_custom_image` | `false` | Use Shared Image Gallery instead of marketplace |
| `avd_users_group_object_id` | — | Entra group that can log into AVD |

Sensitive values (`vm_admin_password`) are **never** in committed files — always via `TF_VAR_VM_ADMIN_PASSWORD` GitHub Secret.

---

## Post-Deployment: FSLogix

After `terraform apply`, configure FSLogix via Intune or GPO on session hosts:

| Setting | Value |
|---------|-------|
| `VHDLocations` | Printed in apply output as `fslogix_share_unc_path` |
| `Enabled` | `1` |
| `DeleteLocalProfileWhenVHDShouldApply` | `1` |
| `FlipFlopProfileDirectoryName` | `1` |
