output "id" {
  value = azurerm_key_vault.this.id
}

output "name" {
  value = azurerm_key_vault.this.name
}

output "vault_uri" {
  description = "https://<name>.vault.azure.net/ ; External Secrets' vaultUrl."
  value       = azurerm_key_vault.this.vault_uri
}

output "secret_names" {
  value = keys(azurerm_key_vault_secret.generated)
}
