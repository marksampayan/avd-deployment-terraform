# =============================================================================
# AVD Deployment — Terraform Variable Values
# Non-sensitive values only — safe to commit to source control.
# Sensitive values (vm_admin_password) are injected via GitHub Actions Secrets
# using the TF_VAR_VM_ADMIN_PASSWORD environment variable — never stored here.
# =============================================================================

subscription_id     = "6598dd7c-4f8f-4a24-9dfa-31a6fb73c32b"
tenant_id           = "490c3a5e-c1b8-43f7-9104-e28e6f7bc536"
resource_group_name = "FIT-AVD-Prod"
location            = "centralindia"

# ── Network ───────────────────────────────────────────────────────────────────
vnet_name             = "FIT-AVD-India"
vnet_address_space    = ["10.1.2.0/24"]
subnet_address_prefix = "10.1.2.0/24"

# DNS servers: Entra DS DCs primary, Azure default DNS as fallback
# Fallback (168.63.129.16) ensures Azure AD endpoints resolve while AADDS initialises
dns_servers = ["10.2.0.4", "10.2.0.5", "168.63.129.16"]

# Hub VNet peering — enable once Entra DS / hub VNet exists in target subscription
enable_hub_peering = false
hub_vnet_id        = null

# ── Host Pool ─────────────────────────────────────────────────────────────────
host_pool_name                    = "FIT AVD Desktop NEW"
host_pool_friendly_name           = "FIT India Desktop NEW"
host_pool_description             = "New Host Pool managed with nerdio"
max_sessions_per_host             = 4
registration_token_validity_hours = 24

# ── Session Hosts ─────────────────────────────────────────────────────────────
session_host_count       = 3
session_host_prefix      = "FIT-AVDN"
session_host_start_index = 101
vm_size                  = "Standard_E4s_v5"
vm_admin_username        = "DefaultAdmin"
# vm_admin_password is set via GitHub Secret TF_VAR_VM_ADMIN_PASSWORD

os_disk_size_gb      = 128
os_disk_storage_type = "StandardSSD_LRS"

# Marketplace image: Windows 11 24H2 multi-session + M365 (matches source OS)
use_custom_image            = false
marketplace_image_publisher = "MicrosoftWindowsDesktop"
marketplace_image_offer     = "office-365"
marketplace_image_sku       = "win11-24h2-avd-m365"
marketplace_image_version   = "latest"

# ── FSLogix Storage ───────────────────────────────────────────────────────────
# Storage account name is auto-generated: avdprofile<8-char-random>
fslogix_share_name     = "profiles"
fslogix_share_quota_gb = 237

# ── RBAC ──────────────────────────────────────────────────────────────────────
# Object ID of the Entra group for India AVD users in the TARGET tenant
# Find it: az ad group show --group "FIT-AVD-Users-India" --query id -o tsv
avd_users_group_object_id = "1992fb97-d4e5-49fb-8d81-e575271a8be4"

# ── Tags ──────────────────────────────────────────────────────────────────────
# test: workflow verification PR - safe to merge
tags = {
  Environment = "Production"
  ManagedBy   = "Terraform"
  Project     = "FIT-AVD-India"
  CostCenter  = "IT"
}
