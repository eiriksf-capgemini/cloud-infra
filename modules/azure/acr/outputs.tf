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
