variable "subscription_id" {
  description = "Target Azure subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure Entra tenant ID"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for the deployment. Must be a region that supports AVD host pool metadata — see https://aka.ms/avd-data-locations for the full list."
  type        = string
}

# ── Network ────────────────────────────────────────────────────────────────────

variable "vnet_name" {
  type = string
}

variable "vnet_address_space" {
  type = list(string)
}

variable "subnet_address_prefix" {
  type = string
}

variable "dns_servers" {
  description = "Custom DNS servers — point to domain controllers (AADDS or traditional DC IPs)"
  type        = list(string)
}

variable "enable_hub_peering" {
  type    = bool
  default = false
}

variable "hub_vnet_id" {
  description = "Resource ID of the hub VNet to peer with (required when enable_hub_peering = true)"
  type        = string
  default     = null
}

# ── Host Pool ──────────────────────────────────────────────────────────────────

variable "host_pool_name" {
  type = string
}

variable "host_pool_friendly_name" {
  type = string
}

variable "host_pool_description" {
  type    = string
  default = ""
}

variable "max_sessions_per_host" {
  type    = number
  default = 4
}

variable "registration_token_validity_hours" {
  type    = number
  default = 24
}

# ── Workspace ──────────────────────────────────────────────────────────────────

variable "workspace_name" {
  type = string
}

variable "workspace_friendly_name" {
  type    = string
  default = ""
}

variable "workspace_description" {
  type    = string
  default = ""
}

# ── Session Hosts ──────────────────────────────────────────────────────────────

variable "session_host_count" {
  description = "Number of session host VMs to deploy. Scale up or down per deployment needs."
  type        = number

  validation {
    condition     = var.session_host_count >= 1 && var.session_host_count <= 50
    error_message = "session_host_count must be between 1 and 50."
  }
}

variable "session_host_prefix" {
  type = string
}

variable "session_host_start_index" {
  type    = number
  default = 1
}

variable "vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}

variable "vm_admin_username" {
  type    = string
  default = "LocalAdmin"
}

variable "vm_admin_password" {
  description = "Local admin password — supply via TF_VAR_vm_admin_password secret in CI/CD"
  type        = string
  sensitive   = true
}

variable "os_disk_size_gb" {
  type    = number
  default = 128
}

variable "os_disk_storage_type" {
  type    = string
  default = "StandardSSD_LRS"
}

variable "use_custom_image" {
  type    = bool
  default = false
}

variable "custom_image_id" {
  description = "Full resource ID of the Shared Image Gallery image version (required when use_custom_image = true)"
  type        = string
  default     = null
}

variable "marketplace_image_publisher" {
  type    = string
  default = "MicrosoftWindowsDesktop"
}

variable "marketplace_image_offer" {
  type    = string
  default = "office-365"
}

variable "marketplace_image_sku" {
  description = "Windows 11 24H2 multi-session + M365"
  type        = string
  default     = "win11-24h2-avd-m365"
}

variable "marketplace_image_version" {
  type    = string
  default = "latest"
}

# ── Domain Join ────────────────────────────────────────────────────────────────

variable "domain_join_type" {
  description = "How session hosts join a domain: 'entra' = Entra ID join (AADDS or native), 'traditional_dc' = on-prem / IaaS Active Directory"
  type        = string
  default     = "entra"

  validation {
    condition     = contains(["entra", "traditional_dc"], var.domain_join_type)
    error_message = "domain_join_type must be 'entra' or 'traditional_dc'."
  }
}

variable "domain_name" {
  description = "FQDN of the domain (required when domain_join_type = 'traditional_dc')"
  type        = string
  default     = null
}

variable "domain_join_username" {
  description = "Username with domain join rights (required when domain_join_type = 'traditional_dc')"
  type        = string
  default     = null
}

variable "domain_join_password" {
  description = "Password for the domain join account (required when domain_join_type = 'traditional_dc')"
  type        = string
  sensitive   = true
  default     = null
}

variable "domain_ou_path" {
  description = "OU path for computer accounts e.g. 'OU=AVD,DC=corp,DC=com' (optional)"
  type        = string
  default     = ""
}

# ── FSLogix / Storage ──────────────────────────────────────────────────────────

variable "fslogix_share_name" {
  type    = string
  default = "profiles"
}

variable "fslogix_share_quota_gb" {
  type    = number
  default = 100
}

variable "fslogix_auth_type" {
  description = "Azure Files auth for FSLogix: 'AADKERB' for Entra-joined VMs, 'AD' for traditional domain-joined VMs"
  type        = string
  default     = "AADKERB"

  validation {
    condition     = contains(["AADKERB", "AD", "AADDS"], var.fslogix_auth_type)
    error_message = "fslogix_auth_type must be 'AADKERB', 'AD', or 'AADDS'."
  }
}

# ── App Install ────────────────────────────────────────────────────────────────

variable "app_install_script_url" {
  description = "URL to a PowerShell script that installs LOB applications. Leave null to skip."
  type        = string
  default     = null
}

# ── RBAC ───────────────────────────────────────────────────────────────────────

variable "avd_users_group_object_id" {
  description = "Object ID of the Entra group that will access AVD desktops"
  type        = string
}

# ── Tags ───────────────────────────────────────────────────────────────────────

variable "tags" {
  type    = map(string)
  default = {}
}
