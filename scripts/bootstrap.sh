#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — One-time setup for AVD Deployment Terraform CI/CD
#
# Run this ONCE from your local machine BEFORE the first GitHub Actions run.
# Creates:
#   1. Azure Storage Account for Terraform remote state
#   2. App Registration with OIDC federated credentials (no client secrets)
#   3. Service Principal with required RBAC roles on the target subscription
#
# Prerequisites:
#   - Azure CLI installed and logged in (az login)
#   - Owner or Contributor + User Access Administrator on target subscription
#
# Usage:
#   export GITHUB_ORG=your-github-org
#   export GITHUB_REPO=avd-deployment-terraform
#   chmod +x scripts/bootstrap.sh
#   ./scripts/bootstrap.sh
# =============================================================================

set -euo pipefail

# ── Required inputs ───────────────────────────────────────────────────────────
GITHUB_ORG="${GITHUB_ORG:?ERROR: Set GITHUB_ORG. Example: export GITHUB_ORG=myorg}"
GITHUB_REPO="${GITHUB_REPO:?ERROR: Set GITHUB_REPO. Example: export GITHUB_REPO=avd-deployment-terraform}"
TARGET_SUBSCRIPTION_ID="${TARGET_SUBSCRIPTION_ID:?ERROR: Set TARGET_SUBSCRIPTION_ID. Example: export TARGET_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000}"
TENANT_ID="${TENANT_ID:?ERROR: Set TENANT_ID. Example: export TENANT_ID=00000000-0000-0000-0000-000000000000}"
STATE_LOCATION="${STATE_LOCATION:?ERROR: Set STATE_LOCATION. Example: export STATE_LOCATION=eastus}"

# ── Optional overrides ────────────────────────────────────────────────────────
STATE_RESOURCE_GROUP="${STATE_RESOURCE_GROUP:-rg-terraform-state}"
STATE_CONTAINER="${STATE_CONTAINER:-tfstate}"
SP_NAME="${SP_NAME:-sp-avd-deployment-terraform}"

echo ""
echo "================================================================"
echo " AVD Deployment — Terraform Bootstrap"
echo " Target Subscription : $TARGET_SUBSCRIPTION_ID"
echo " Tenant              : $TENANT_ID"
echo " State Location      : $STATE_LOCATION"
echo " GitHub Repo         : $GITHUB_ORG/$GITHUB_REPO"
echo "================================================================"
echo ""

# ── Step 1: Set subscription ──────────────────────────────────────────────────
echo "[1/5] Setting active subscription..."
az account set --subscription "$TARGET_SUBSCRIPTION_ID"
echo "      Done."

# ── Step 2: Create Terraform state storage backend ────────────────────────────
RAND=$(cat /dev/urandom 2>/dev/null | tr -dc 'a-z0-9' | head -c 6 || \
       LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6)
STATE_STORAGE_ACCOUNT="stavdtfstate${RAND}"

echo "[2/5] Creating Terraform state backend..."
echo "      Resource Group  : $STATE_RESOURCE_GROUP"
echo "      Storage Account : $STATE_STORAGE_ACCOUNT"
echo "      Container       : $STATE_CONTAINER"

az group create \
  --name "$STATE_RESOURCE_GROUP" \
  --location "$STATE_LOCATION" \
  --output none

az storage account create \
  --name "$STATE_STORAGE_ACCOUNT" \
  --resource-group "$STATE_RESOURCE_GROUP" \
  --location "$STATE_LOCATION" \
  --sku "Standard_LRS" \
  --kind "StorageV2" \
  --min-tls-version "TLS1_2" \
  --allow-blob-public-access false \
  --output none

az storage container create \
  --name "$STATE_CONTAINER" \
  --account-name "$STATE_STORAGE_ACCOUNT" \
  --auth-mode login \
  --output none

echo "      Done."

# ── Step 3: Create App Registration + Service Principal ───────────────────────
echo "[3/5] Creating App Registration and Service Principal..."

APP_ID=$(az ad app create \
  --display-name "$SP_NAME" \
  --query appId \
  --output tsv)

SP_OBJECT_ID=$(az ad sp create \
  --id "$APP_ID" \
  --query id \
  --output tsv)

echo "      App (Client) ID : $APP_ID"
echo "      SP Object ID    : $SP_OBJECT_ID"
echo "      Done."

# ── Step 4: Create OIDC Federated Credentials ─────────────────────────────────
echo "[4/5] Creating OIDC federated credentials for GitHub Actions..."

# Federated credential for push to main (terraform apply workflow)
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "{
    \"name\": \"github-main\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main\",
    \"description\": \"GitHub Actions - main branch (terraform apply)\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" \
  --output none

# Federated credential for pull requests (terraform plan workflow)
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "{
    \"name\": \"github-prs\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request\",
    \"description\": \"GitHub Actions - pull requests (terraform plan)\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" \
  --output none

# Federated credential for production environment (terraform apply workflow)
# Required because jobs with 'environment: production' use a different OIDC subject
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "{
    \"name\": \"github-production-env\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:production\",
    \"description\": \"GitHub Actions - production environment (terraform apply)\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" \
  --output none

echo "      Done."

# ── Step 5: Assign RBAC roles ─────────────────────────────────────────────────
echo "[5/5] Assigning RBAC roles to Service Principal..."
SCOPE="/subscriptions/${TARGET_SUBSCRIPTION_ID}"

# Contributor — create/manage all AVD, VM, network, storage resources
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type "ServicePrincipal" \
  --role "Contributor" \
  --scope "$SCOPE" \
  --output none

# User Access Administrator — needed for azurerm_role_assignment in main.tf
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type "ServicePrincipal" \
  --role "User Access Administrator" \
  --scope "$SCOPE" \
  --output none

# Storage Blob Data Contributor — read/write Terraform state blobs
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type "ServicePrincipal" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/${TARGET_SUBSCRIPTION_ID}/resourceGroups/${STATE_RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STATE_STORAGE_ACCOUNT}" \
  --output none

echo "      Done."

# ── Print configuration summary ───────────────────────────────────────────────
echo ""
echo "================================================================"
echo " Bootstrap complete! Configure your GitHub repository now:"
echo "================================================================"
echo ""
echo " STEP A — Add GitHub SECRETS"
echo " (Settings → Secrets and variables → Actions → New repository secret)"
echo ""
echo "   Name                    Value"
echo "   ─────────────────────── ────────────────────────────────────────"
echo "   AZURE_CLIENT_ID         $APP_ID"
echo "   AZURE_TENANT_ID         $TENANT_ID"
echo "   AZURE_SUBSCRIPTION_ID   $TARGET_SUBSCRIPTION_ID"
echo "   TF_VAR_VM_ADMIN_PASSWORD <your-secure-vm-local-admin-password>"
echo ""
echo " STEP B — Add GitHub VARIABLES"
echo " (Settings → Secrets and variables → Actions → New repository variable)"
echo ""
echo "   Name                     Value"
echo "   ──────────────────────── ─────────────────────────────────"
echo "   TF_STATE_RESOURCE_GROUP  $STATE_RESOURCE_GROUP"
echo "   TF_STATE_STORAGE_ACCOUNT $STATE_STORAGE_ACCOUNT"
echo "   TF_STATE_CONTAINER       $STATE_CONTAINER"
echo ""
echo " STEP C — Create 'production' Environment with required reviewers"
echo " (Settings → Environments → New environment → name: production)"
echo "   - Enable 'Required reviewers' and add yourself / your team"
echo "   - This is the final gate before terraform apply executes"
echo ""
echo " STEP D — Enable Branch Protection on 'main'"
echo " (Settings → Branches → Add rule → Branch name pattern: main)"
echo "   ✅ Require a pull request before merging"
echo "   ✅ Require approvals (minimum: 1)"
echo "   ✅ Require status checks: 'Terraform Plan / Terraform Plan'"
echo "   ✅ Require branches to be up to date before merging"
echo ""
echo "================================================================"
