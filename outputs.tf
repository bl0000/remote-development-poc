output "resource_group_name" {
  description = "RG name"
  value       = azurerm_resource_group.this.name
}

output "workspace_name" {
  description = "AVD workspace name"
  value       = azurerm_virtual_desktop_workspace.this.name
}

output "host_pool_name" {
  description = "AVD host pool name."
  value       = azurerm_virtual_desktop_host_pool.this.name
}

output "session_host_names" {
  description = "Session Hosts"
  value       = azurerm_windows_virtual_machine.host[*].name
}

output "profile_storage_account_name" {
  description = "Storage Account with FSLogix profile containers"
  value       = azurerm_storage_account.profiles.name
}

output "profile_share_name" {
  description = "Premium file share holding FSLogix profile containers"
  value       = azurerm_storage_share.profiles.name
}

output "admin_password" {
  description = "Generated local admin password for the session host (for testing / break-glass)"
  value       = random_password.admin.result
  sensitive   = true
}
