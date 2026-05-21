terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.50"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "azurerm" {
    # Populated via -backend-config flags during `terraform init`.
    # Values are stored as GitHub Actions Variables (non-sensitive).
    # Run scripts/bootstrap.sh once to create the state backend before first init.
    # See README.md for full setup instructions.
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  use_oidc        = true   # OIDC / Workload Identity Federation (no client secrets)
  features {}
}

provider "azuread" {
  tenant_id = var.tenant_id
  use_oidc  = true
}

provider "random" {}
