# =============================================================================
# AVD Deployment — Azure Virtual Desktop Host Pool (Pooled, Central India)
# Source: Discovered from Levelcloud subscription
# Target: 6598dd7c-4f8f-4a24-9dfa-31a6fb73c32b
# =============================================================================

# ── Random suffix for globally-unique resource names ──────────────────────────

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

locals {
  # Storage account: "avdprofile" + 8-char random alphanumeric = 18 chars
  # Example: avdprofilem3k9xz2a
  storage_account_name = "avdprofile${random_string.suffix.result}"
}

# ── Resource Group ─────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "avd" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ── Network Security Group ─────────────────────────────────────────────────────
# Source had no custom rules. Session hosts connect OUTBOUND to AVD on 443.

resource "azurerm_network_security_group" "avd" {
  name                = "FIT-AVD-India"
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
  # DNS servers point to Entra DS / AD DCs — required for FSLogix AADKERB auth
  dns_servers = var.dns_servers
  tags        = var.tags
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
# Set enable_hub_peering = true and provide hub_vnet_id once Entra DS / hub
# VNet exists in the target subscription.

resource "azurerm_virtual_network_peering" "avd_to_hub" {
  count = var.enable_hub_peering ? 1 : 0

  name                         = "FIT-AVD-India-to-Hub"
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
  load_balancer_type       = "DepthFirst" # Fill one host fully before moving to next
  maximum_sessions_allowed = var.max_sessions_per_host
  preferred_app_group_type = "Desktop"
  start_vm_on_connect      = false
  validate_environment     = true # Receives AVD updates before production ring

  # RDP properties discovered from source — full device redirect + Entra ID auth
  custom_rdp_properties = join(";", [
    "targetisaadjoined:i:1",
    "enablerdsaadauth:i:1",
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

# Registration token consumed by the DSC extension to register session hosts
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
  name                = "FIT-AVD-India"
  friendly_name       = "FIT India Workspace"
  description         = "Workspace for users working from the India and Philippines region"
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
  account_kind             = "FileStorage" # Required for Premium file shares
  account_tier             = "Premium"
  account_replication_type = "LRS"

  # AADKERB — Azure AD Kerberos auth, required for Entra-joined VMs using FSLogix
  azure_files_authentication {
    directory_type = "AADKERB"
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

  # Azure Hybrid Benefit — reduces Windows licensing cost
  license_type = "Windows_Client"

  # System-assigned managed identity required for Entra ID join extension
  identity {
    type = "SystemAssigned"
  }

  # TrustedLaunch matches source (SecureBoot/vTPM off as discovered)
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

  boot_diagnostics {} # Uses managed storage account

  tags = merge(var.tags, {
    WAP_OBJECT_TYPE               = "SESSION_HOST"
    WAP_OS_DESCRIPTION            = "Windows 11 Enterprise multi-session + Microsoft 365 Apps"
    WAP_OS_SUPPORTS_ENTRA_ID_JOIN = "True"
    WAP_VM_DOMAIN                 = "Entra ID"
  })
}

# ── VM Extension: Entra ID Join ────────────────────────────────────────────────

resource "azurerm_virtual_machine_extension" "entra_join" {
  count                      = var.session_host_count
  name                       = "${azurerm_windows_virtual_machine.session_host[count.index].name}-join-aad"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_host[count.index].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    mdmId = "" # Leave blank unless enrolling in Intune MDM
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
      aadJoin               = true
    }
  })

  depends_on = [azurerm_virtual_machine_extension.entra_join]
  tags       = var.tags
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

# ── RBAC: Desktop Virtualization User (App Group) ─────────────────────────────
# Required for users to see the published desktop in the AVD client

resource "azurerm_role_assignment" "avd_user_appgroup" {
  scope                = azurerm_virtual_desktop_application_group.avd.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = var.avd_users_group_object_id
  principal_type       = "Group"
}

# ── RBAC: Virtual Machine User Login (Resource Group) ─────────────────────────
# Required for Entra ID joined VMs — users authenticate to the VM OS via Entra

resource "azurerm_role_assignment" "vm_user_login" {
  scope                = azurerm_resource_group.avd.id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = var.avd_users_group_object_id
  principal_type       = "Group"
}

# ── RBAC: Storage File Data SMB Share Contributor (FSLogix) ───────────────────
# Required for users to read/write their FSLogix profile container

resource "azurerm_role_assignment" "fslogix_share" {
  scope                = azurerm_storage_account.fslogix.id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = var.avd_users_group_object_id
  principal_type       = "Group"
}
