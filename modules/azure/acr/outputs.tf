output "id" {
  description = "Resource ID of the registry."
  value       = azurerm_container_registry.this.id
}

output "name" {
  description = "Registry name."
  value       = azurerm_container_registry.this.name
}

output "login_server" {
  description = "Registry hostname used in image references, e.g. <name>.azurecr.io."
  value       = azurerm_container_registry.this.login_server
}

output "pull_principal_ids" {
  description = "Object IDs that actually hold AcrPull on the registry, keyed by label."
  value       = { for k, ra in azurerm_role_assignment.pull : k => ra.principal_id }
}

output "push_principal_ids" {
  description = "Object IDs that actually hold AcrPush on the registry, keyed by label."
  value       = { for k, ra in azurerm_role_assignment.push : k => ra.principal_id }
}
