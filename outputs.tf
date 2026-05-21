output "resource_group_id" {
  value = azurerm_resource_group.avd.id
}

output "host_pool_id" {
  value = azurerm_virtual_desktop_host_pool.avd.id
}

output "host_pool_name" {
  value = azurerm_virtual_desktop_host_pool.avd.name
}

output "application_group_id" {
  value = azurerm_virtual_desktop_application_group.avd.id
}

output "workspace_id" {
  value = azurerm_virtual_desktop_workspace.avd.id
}

output "workspace_name" {
  value = azurerm_virtual_desktop_workspace.avd.name
}

output "storage_account_name" {
  description = "Auto-generated FSLogix storage account name (avdprofile + 8-char suffix)"
  value       = azurerm_storage_account.fslogix.name
}

output "fslogix_share_unc_path" {
  description = "UNC path to configure in FSLogix VHDLocations policy"
  value       = "\\\\${azurerm_storage_account.fslogix.name}.file.core.windows.net\\${azurerm_storage_share.fslogix_profiles.name}"
}

output "session_host_names" {
  value = azurerm_windows_virtual_machine.session_host[*].name
}

output "vnet_id" {
  value = azurerm_virtual_network.avd.id
}

output "subnet_id" {
  value = azurerm_subnet.avd.id
}

output "registration_token" {
  value       = azurerm_virtual_desktop_host_pool_registration_info.avd.token
  sensitive   = true
  description = "AVD registration token — use to manually add additional session hosts"
}
