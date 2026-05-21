# AVD Deployment — Terraform IaC + GitHub Actions CI/CD

Reusable Terraform template for deploying **Azure Virtual Desktop** (pooled host pool) to any Azure region and subscription, with a full GitHub Actions CI/CD pipeline and production approval gate.

---

## Repository structure

```
.
├── main.tf                    ← calls modules/avd-core with deployment values
├── variables.tf               ← all input variables
├── outputs.tf                 ← deployment outputs
├── providers.tf               ← Azure provider + backend config
├── terraform.tfvars           ← THIS deployment's values (not committed for new deployments)
├── terraform.tfvars.example   ← blank template — copy and fill in for each new deployment
├── modules/
│   └── avd-core/              ← reusable AVD module (all Azure resources)
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── scripts/
│   └── bootstrap.sh           ← one-time Azure + GitHub setup script
└── .github/workflows/
    ├── terraform-plan.yml     ← runs on pull requests
    └── terraform-apply.yml    ← runs on merge to main (with approval gate)
```

---

## Architecture

```
GitHub PR → terraform plan (posted as PR comment) → PR Approval
     ↓
Merge to main → "production" environment gate → terraform apply
     ↓
Azure Subscription
     ├── Resource Group (your region)
     ├── VNet + Subnet + NSG
     ├── AVD Host Pool    — Pooled, DepthFirst
     ├── AVD App Group    — Desktop type
     ├── AVD Workspace
     ├── Storage Account  — Premium FSLogix profiles (SMB)
     └── Session Hosts (N × your VM size)
          ├── Domain join extension  (Entra ID or traditional AD)
          ├── AVD DSC agent extension
          ├── Azure Monitor Agent extension
          └── App install extension  (optional, for LOB apps)
```

---

## Starting a new deployment

### Step 1 — Create your repo from the template

Go to `github.com/marksampayan/avd-deployment-terraform` → click **"Use this template"** → **"Create a new repository"** under your GitHub account.

Clone it locally:
```bash
git clone https://github.com/<your-account>/<your-repo>.git
cd <your-repo>
```

### Step 2 — Create your terraform.tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` — fill in your subscription ID, tenant ID, location, VM count, naming, etc. See `terraform.tfvars.example` for all available options and comments.

**Key values to set for every new deployment:**

| Variable | What to set |
|----------|-------------|
| `subscription_id` | Your Azure subscription ID |
| `tenant_id` | Your Azure Entra tenant ID |
| `location` | Azure region (must support AVD — see [supported regions](https://aka.ms/avd-data-locations)) |
| `session_host_count` | Number of VMs (1–50) |
| `avd_users_group_object_id` | Object ID of the Entra group for AVD users |
| `domain_join_type` | `"entra"` for Entra ID join, `"traditional_dc"` for on-prem AD |

### Step 3 — Run the bootstrap script

Run **once** from your local machine. Requires Azure CLI and Owner access on the target subscription.

```bash
export GITHUB_ORG=<your-github-username-or-org>
export GITHUB_REPO=<your-repo-name>
export TARGET_SUBSCRIPTION_ID=<your-subscription-id>
export TENANT_ID=<your-tenant-id>
export STATE_LOCATION=<azure-region>   # e.g. eastus — where state storage is created

chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
```

The script creates:
- Azure Storage Account for Terraform remote state
- App Registration with OIDC federated credentials (no stored client secrets)
- Service Principal with `Contributor` + `User Access Administrator` roles
- Prints all values needed for GitHub Secrets and Variables

### Step 4 — Configure GitHub repository

#### Secrets
`Settings → Secrets and variables → Actions → New repository secret`

| Secret | Value |
|--------|-------|
| `AZURE_CLIENT_ID` | From bootstrap output |
| `AZURE_TENANT_ID` | Your tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Your subscription ID |
| `TF_VAR_VM_ADMIN_PASSWORD` | Secure local admin password for session host VMs |
| `TF_VAR_DOMAIN_JOIN_PASSWORD` | Domain join account password *(only if using `traditional_dc`)* |

#### Variables
`Settings → Secrets and variables → Actions → New repository variable`

| Variable | Value (from bootstrap output) |
|----------|-------------------------------|
| `TF_STATE_RESOURCE_GROUP` | `rg-terraform-state` |
| `TF_STATE_STORAGE_ACCOUNT` | `stavdtfstate<random>` |
| `TF_STATE_CONTAINER` | `tfstate` |

#### Production environment (approval gate)
`Settings → Environments → New environment → Name: production`
- Enable **Required reviewers** → add yourself or your team
- This blocks `terraform apply` until a human clicks Approve in GitHub

#### Branch protection on `main`
`Settings → Branches → Add rule → Branch name pattern: main`
- ✅ Require a pull request before merging
- ✅ Require approvals (minimum 1)
- ✅ Require status checks to pass: `Terraform Plan / Terraform Plan`
- ✅ Require branches to be up to date before merging

### Step 5 — Deploy

Push to main (or merge a PR) — GitHub Actions handles the rest.

---

## Domain join options

| `domain_join_type` | Extension used | Additional variables required |
|--------------------|---------------|-------------------------------|
| `entra` *(default)* | `AADLoginForWindows` | None |
| `traditional_dc` | `JsonADDomainExtension` | `domain_name`, `domain_join_username`, `domain_join_password` (via secret) |

When switching to `traditional_dc`, also set:
- `fslogix_auth_type = "AD"` (instead of `"AADKERB"`)
- `dns_servers` pointing to your DC IPs

---

## LOB application install

Set `app_install_script_url` in `terraform.tfvars` to a publicly reachable PowerShell script URL. The script runs on every session host after the AVD agent registers. Leave it `null` (or commented out) to skip.

```hcl
app_install_script_url = "https://your-storage.blob.core.windows.net/scripts/install-apps.ps1"
```

---

## Key variables reference

| Variable | Default | Description |
|----------|---------|-------------|
| `location` | *(required)* | Azure region — must support AVD metadata |
| `session_host_count` | *(required)* | Number of session host VMs (1–50) |
| `vm_size` | `Standard_D4s_v5` | VM size for session hosts |
| `max_sessions_per_host` | `4` | Max concurrent sessions per VM |
| `domain_join_type` | `entra` | `entra` or `traditional_dc` |
| `fslogix_auth_type` | `AADKERB` | `AADKERB` or `AD` |
| `fslogix_share_quota_gb` | `100` | FSLogix profile share size in GiB |
| `app_install_script_url` | `null` | Optional LOB app install script URL |
| `use_custom_image` | `false` | Use Shared Image Gallery instead of marketplace |

---

## Post-deployment: FSLogix

After `terraform apply`, configure FSLogix on session hosts via Intune or GPO:

| Setting | Value |
|---------|-------|
| `VHDLocations` | Printed in apply output as `fslogix_share_unc_path` |
| `Enabled` | `1` |
| `DeleteLocalProfileWhenVHDShouldApply` | `1` |
| `FlipFlopProfileDirectoryName` | `1` |
