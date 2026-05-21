resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

locals {
  storage_account_name = "avdprofile${random_string.suffix.result}"
  is_entra_join        = var.domain_join_type == "entra"
}

# ── Resource Group ─────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "avd" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ── Network Security Group ─────────────────────────────────────────────────────

resource "azurerm_network_security_group" "avd" {
  name                = var.vnet_name
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  tags                = var.tags
}

# ── Virtual Network ────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "avd" {
  name                = var.vnet_name
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  address_space       = var.vnet_address_space
  dns_servers         = var.dns_servers
  tags                = var.tags
}

resource "azurerm_subnet" "avd" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.avd.name
  virtual_network_name = azurerm_virtual_network.avd.name
  address_prefixes     = [var.subnet_address_prefix]
}

resource "azurerm_subnet_network_security_group_association" "avd" {
  subnet_id                 = azurerm_subnet.avd.id
  network_security_group_id = azurerm_network_security_group.avd.id
}

# ── VNet Peering to Hub (optional) ────────────────────────────────────────────

resource "azurerm_virtual_network_peering" "avd_to_hub" {
  count = var.enable_hub_peering ? 1 : 0

  name                         = "${var.vnet_name}-to-Hub"
  resource_group_name          = azurerm_resource_group.avd.name
  virtual_network_name         = azurerm_virtual_network.avd.name
  remote_virtual_network_id    = var.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# ── AVD Host Pool ──────────────────────────────────────────────────────────────

resource "azurerm_virtual_desktop_host_pool" "avd" {
  name                = var.host_pool_name
  friendly_name       = var.host_pool_friendly_name
  description         = var.host_pool_description
  resource_group_name = azurerm_resource_group.avd.name
  location            = azurerm_resource_group.avd.location

  type                     = "Pooled"
  load_balancer_type       = "DepthFirst"
  maximum_sessions_allowed = var.max_sessions_per_host
  preferred_app_group_type = "Desktop"
  start_vm_on_connect      = false
  validate_environment     = true

  custom_rdp_properties = join(";", [
    "targetisaadjoined:i:${local.is_entra_join ? 1 : 0}",
    "enablerdsaadauth:i:${local.is_entra_join ? 1 : 0}",
    "audiomode:i:0",
    "audiocapturemode:i:1",
    "redirectclipboard:i:1",
    "redirectprinters:i:1",
    "use multimon:i:1",
    "videoplaybackmode:i:1",
    "compression:i:1",
    "encode redirected video capture:i:1",
    "redirected video capture encoding quality:i:2",
    "redirectsmartcards:i:1",
    "redirectlocation:i:1",
    "smart sizing:i:1",
    "redirectcomports:i:1",
    "drivestoredirect:s:*",
    "camerastoredirect:s:*",
    "usbdevicestoredirect:s:*",
    "devicestoredirect:s:*",
  ])

  tags = var.tags
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "avd" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.avd.id
  expiration_date = timeadd(timestamp(), "${var.registration_token_validity_hours}h")

  lifecycle {
    ignore_changes = [expiration_date]
  }
}

# ── AVD Application Group ──────────────────────────────────────────────────────

resource "azurerm_virtual_desktop_application_group" "avd" {
  name                = "${replace(var.host_pool_name, " ", "-")}-AppGroup"
  resource_group_name = azurerm_resource_group.avd.name
  location            = azurerm_resource_group.avd.location
  type                = "Desktop"
  host_pool_id        = azurerm_virtual_desktop_host_pool.avd.id
  friendly_name       = var.host_pool_friendly_name
  tags                = var.tags
}

# ── AVD Workspace ──────────────────────────────────────────────────────────────

resource "azurerm_virtual_desktop_workspace" "avd" {
  name                = var.workspace_name
  friendly_name       = var.workspace_friendly_name
  description         = var.workspace_description
  resource_group_name = azurerm_resource_group.avd.name
  location            = azurerm_resource_group.avd.location
  tags                = var.tags
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "avd" {
  workspace_id         = azurerm_virtual_desktop_workspace.avd.id
  application_group_id = azurerm_virtual_desktop_application_group.avd.id
}

# ── FSLogix Profile Storage ────────────────────────────────────────────────────

resource "azurerm_storage_account" "fslogix" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.avd.name
  location                 = azurerm_resource_group.avd.location
  account_kind             = "FileStorage"
  account_tier             = "Premium"
  account_replication_type = "LRS"

  azure_files_authentication {
    directory_type = var.fslogix_auth_type
  }

  large_file_share_enabled         = true
  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false

  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  tags = merge(var.tags, {
    WAP_OBJECT_TYPE = "FILE_STORAGE_ACCOUNT"
  })
}

resource "azurerm_storage_share" "fslogix_profiles" {
  name                 = var.fslogix_share_name
  storage_account_name = azurerm_storage_account.fslogix.name
  quota                = var.fslogix_share_quota_gb
  enabled_protocol     = "SMB"
  access_tier          = "Premium"
}

# ── Session Host Network Interfaces ───────────────────────────────────────────

resource "azurerm_network_interface" "session_host" {
  count               = var.session_host_count
  name                = "${var.session_host_prefix}-${format("%03d", var.session_host_start_index + count.index)}-nic"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name

  accelerated_networking_enabled = true

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.avd.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}

# ── Session Host VMs ───────────────────────────────────────────────────────────

resource "azurerm_windows_virtual_machine" "session_host" {
  count               = var.session_host_count
  name                = "${var.session_host_prefix}-${format("%03d", var.session_host_start_index + count.index)}"
  resource_group_name = azurerm_resource_group.avd.name
  location            = azurerm_resource_group.avd.location
  size                = var.vm_size
  admin_username      = var.vm_admin_username
  admin_password      = var.vm_admin_password

  network_interface_ids = [azurerm_network_interface.session_host[count.index].id]

  license_type = "Windows_Client"

  identity {
    type = "SystemAssigned"
  }

  secure_boot_enabled = false
  vtpm_enabled        = false

  os_disk {
    name                 = "${var.session_host_prefix}-${format("%03d", var.session_host_start_index + count.index)}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_storage_type
    disk_size_gb         = var.os_disk_size_gb
  }

  dynamic "source_image_reference" {
    for_each = var.use_custom_image ? [] : [1]
    content {
      publisher = var.marketplace_image_publisher
      offer     = var.marketplace_image_offer
      sku       = var.marketplace_image_sku
      version   = var.marketplace_image_version
    }
  }

  source_image_id = var.use_custom_image ? var.custom_image_id : null

  patch_mode               = "AutomaticByOS"
  enable_automatic_updates = true
  provision_vm_agent       = true

  boot_diagnostics {}

  tags = merge(var.tags, {
    WAP_OBJECT_TYPE               = "SESSION_HOST"
    WAP_OS_DESCRIPTION            = "Windows 11 Enterprise multi-session + Microsoft 365 Apps"
    WAP_OS_SUPPORTS_ENTRA_ID_JOIN = tostring(local.is_entra_join)
    WAP_VM_DOMAIN                 = local.is_entra_join ? "Entra ID" : coalesce(var.domain_name, "unknown")
  })
}

# ── VM Extension: Entra ID Join (entra mode only) ─────────────────────────────

resource "azurerm_virtual_machine_extension" "entra_join" {
  count                      = local.is_entra_join ? var.session_host_count : 0
  name                       = "${azurerm_windows_virtual_machine.session_host[count.index].name}-join-aad"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_host[count.index].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    mdmId = ""
  })

  tags = var.tags
}

# ── VM Extension: Traditional Domain Join (traditional_dc mode only) ──────────

resource "azurerm_virtual_machine_extension" "domain_join" {
  count                      = local.is_entra_join ? 0 : var.session_host_count
  name                       = "${azurerm_windows_virtual_machine.session_host[count.index].name}-join-domain"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_host[count.index].id
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    Name    = var.domain_name
    OUPath  = var.domain_ou_path
    User    = "${var.domain_name}\\${var.domain_join_username}"
    Restart = "true"
    Options = "3"
  })

  protected_settings = jsonencode({
    Password = var.domain_join_password
  })

  tags = var.tags
}

# ── VM Extension: AVD Session Host Agent ──────────────────────────────────────

resource "azurerm_virtual_machine_extension" "avd_agent" {
  count                      = var.session_host_count
  name                       = "${azurerm_windows_virtual_machine.session_host[count.index].name}-join-arm-wvd-ext"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_host[count.index].id
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.73"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    modulesUrl            = "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02714.342.zip"
    configurationFunction = "Configuration.ps1\\AddSessionHost"
    properties = {
      hostPoolName          = azurerm_virtual_desktop_host_pool.avd.name
      registrationInfoToken = azurerm_virtual_desktop_host_pool_registration_info.avd.token
      aadJoin               = local.is_entra_join
    }
  })

  depends_on = [
    azurerm_virtual_machine_extension.entra_join,
    azurerm_virtual_machine_extension.domain_join,
  ]
  tags = var.tags
}

# ── VM Extension: Azure Monitor Agent ─────────────────────────────────────────

resource "azurerm_virtual_machine_extension" "azure_monitor" {
  count                      = var.session_host_count
  name                       = "${azurerm_windows_virtual_machine.session_host[count.index].name}-azure-monitoring"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_host[count.index].id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  tags                       = var.tags
}

# ── VM Extension: LOB App Install (optional) ──────────────────────────────────
# Set app_install_script_url to a publicly reachable PowerShell script URL to
# install custom line-of-business applications on every session host.

resource "azurerm_virtual_machine_extension" "app_install" {
  count                      = var.app_install_script_url != null ? var.session_host_count : 0
  name                       = "${azurerm_windows_virtual_machine.session_host[count.index].name}-app-install"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_host[count.index].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    fileUris         = [var.app_install_script_url]
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -File ${basename(var.app_install_script_url)}"
  })

  depends_on = [azurerm_virtual_machine_extension.avd_agent]
  tags       = var.tags
}

# ── RBAC ──────────────────────────────────────────────────────────────────────

resource "azurerm_role_assignment" "avd_user_appgroup" {
  scope                = azurerm_virtual_desktop_application_group.avd.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = var.avd_users_group_object_id
  principal_type       = "Group"
}

resource "azurerm_role_assignment" "vm_user_login" {
  scope                = azurerm_resource_group.avd.id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = var.avd_users_group_object_id
  principal_type       = "Group"
}

resource "azurerm_role_assignment" "fslogix_share" {
  scope                = azurerm_storage_account.fslogix.id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = var.avd_users_group_object_id
  principal_type       = "Group"
}
