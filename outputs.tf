output "resource_group_id" {
  value = module.avd.resource_group_id
}

output "host_pool_id" {
  value = module.avd.host_pool_id
}

output "host_pool_name" {
  value = module.avd.host_pool_name
}

output "application_group_id" {
  value = module.avd.application_group_id
}

output "workspace_id" {
  value = module.avd.workspace_id
}

output "workspace_name" {
  value = module.avd.workspace_name
}

output "storage_account_name" {
  value = module.avd.storage_account_name
}

output "fslogix_share_unc_path" {
  description = "UNC path to configure in FSLogix VHDLocations policy"
  value       = module.avd.fslogix_share_unc_path
}

output "session_host_names" {
  value = module.avd.session_host_names
}

output "vnet_id" {
  value = module.avd.vnet_id
}

output "subnet_id" {
  value = module.avd.subnet_id
}

output "registration_token" {
  value       = module.avd.registration_token
  sensitive   = true
  description = "AVD registration token — use to manually add additional session hosts"
}
