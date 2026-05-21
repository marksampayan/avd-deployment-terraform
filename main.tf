module "avd" {
  source = "github.com/marksampayan/avd-terraform-modules//modules/avd-core?ref=v1.0.1"

  # ── Core ──────────────────────────────────────────────────────────────────────
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  # ── Network ───────────────────────────────────────────────────────────────────
  vnet_name             = var.vnet_name
  vnet_address_space    = var.vnet_address_space
  subnet_address_prefix = var.subnet_address_prefix
  dns_servers           = var.dns_servers
  enable_hub_peering    = var.enable_hub_peering
  hub_vnet_id           = var.hub_vnet_id

  # ── Host Pool ─────────────────────────────────────────────────────────────────
  host_pool_name                    = var.host_pool_name
  host_pool_friendly_name           = var.host_pool_friendly_name
  host_pool_description             = var.host_pool_description
  max_sessions_per_host             = var.max_sessions_per_host
  registration_token_validity_hours = var.registration_token_validity_hours

  # ── Workspace ─────────────────────────────────────────────────────────────────
  workspace_name          = var.workspace_name
  workspace_friendly_name = var.workspace_friendly_name
  workspace_description   = var.workspace_description

  # ── Session Hosts ─────────────────────────────────────────────────────────────
  session_host_count       = var.session_host_count
  session_host_prefix      = var.session_host_prefix
  session_host_start_index = var.session_host_start_index
  vm_size                  = var.vm_size
  vm_admin_username        = var.vm_admin_username
  vm_admin_password        = var.vm_admin_password
  os_disk_size_gb          = var.os_disk_size_gb
  os_disk_storage_type     = var.os_disk_storage_type

  use_custom_image            = var.use_custom_image
  custom_image_id             = var.custom_image_id
  marketplace_image_publisher = var.marketplace_image_publisher
  marketplace_image_offer     = var.marketplace_image_offer
  marketplace_image_sku       = var.marketplace_image_sku
  marketplace_image_version   = var.marketplace_image_version

  # ── Domain Join ───────────────────────────────────────────────────────────────
  domain_join_type     = var.domain_join_type
  domain_name          = var.domain_name
  domain_join_username = var.domain_join_username
  domain_join_password = var.domain_join_password
  domain_ou_path       = var.domain_ou_path

  # ── FSLogix ───────────────────────────────────────────────────────────────────
  fslogix_share_name     = var.fslogix_share_name
  fslogix_share_quota_gb = var.fslogix_share_quota_gb
  fslogix_auth_type      = var.fslogix_auth_type

  # ── App Install ───────────────────────────────────────────────────────────────
  app_install_script_url = var.app_install_script_url

  # ── RBAC ──────────────────────────────────────────────────────────────────────
  avd_users_group_object_id = var.avd_users_group_object_id
}
