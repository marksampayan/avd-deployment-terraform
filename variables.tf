variable "subscription_id" {
  description = "Target Azure subscription ID"
  type        = string
  default     = "6598dd7c-4f8f-4a24-9dfa-31a6fb73c32b"
}

variable "tenant_id" {
  description = "Azure Entra tenant ID"
  type        = string
  default     = "490c3a5e-c1b8-43f7-9104-e28e6f7bc536"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "FIT-AVD-Prod"
}

variable "location" {
  description = "Azure region for the India AVD deployment"
  type        = string
  default     = "centralindia"
}

# ── Network ────────────────────────────────────────────────────────────────────

variable "vnet_name" {
  type    = string
  default = "FIT-AVD-India"
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.1.2.0/24"]
}

variable "subnet_address_prefix" {
  type    = string
  default = "10.1.2.0/24"
}

variable "dns_servers" {
  description = "Custom DNS servers (Entra DS / AD domain controllers in target env)"
  type        = list(string)
  default     = ["10.2.0.4", "10.2.0.5"]
}

variable "enable_hub_peering" {
  description = "Set to true to create a VNet peering to the hub/Entra DS VNet"
  type        = bool
  default     = false
}

variable "hub_vnet_id" {
  description = "Resource ID of the hub VNet to peer with (required when enable_hub_peering = true)"
  type        = string
  default     = null
}

# ── Host Pool ──────────────────────────────────────────────────────────────────

variable "host_pool_name" {
  type    = string
  default = "FIT AVD Desktop NEW"
}

variable "host_pool_friendly_name" {
  type    = string
  default = "FIT India Desktop NEW"
}

variable "host_pool_description" {
  type    = string
  default = "New Host Pool managed with nerdio"
}

variable "max_sessions_per_host" {
  type    = number
  default = 4
}

variable "registration_token_validity_hours" {
  description = "Hours the host pool registration token stays valid"
  type        = number
  default     = 24
}

# ── Session Hosts ──────────────────────────────────────────────────────────────

variable "session_host_count" {
  type    = number
  default = 3
}

variable "session_host_prefix" {
  type    = string
  default = "FIT-AVDN"
}

variable "session_host_start_index" {
  type    = number
  default = 101
}

variable "vm_size" {
  type    = string
  default = "Standard_E4s_v5"
}

variable "vm_admin_username" {
  type    = string
  default = "DefaultAdmin"
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
  description = "Use a Shared Image Gallery image instead of the marketplace image"
  type        = bool
  default     = false
}

variable "custom_image_id" {
  description = "Full resource ID of the Shared Image Gallery image version"
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
  description = "Windows 11 24H2 multi-session + M365 (matches source environment OS)"
  type        = string
  default     = "win11-24h2-avd-m365"
}

variable "marketplace_image_version" {
  type    = string
  default = "latest"
}

# ── FSLogix / Storage ──────────────────────────────────────────────────────────

variable "fslogix_share_name" {
  type    = string
  default = "profiles"
}

variable "fslogix_share_quota_gb" {
  type    = number
  default = 237
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
