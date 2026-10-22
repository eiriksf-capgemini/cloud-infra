output "key_vault_name" {
  value = module.keyvault.name
}

output "vault_uri" {
  description = "Must match spec.provider.azurekv.vaultUrl in gitops/platform/platform-secrets/clustersecretstore.yaml."
  value       = module.keyvault.vault_uri
}

output "read_admin_password_command" {
  description = "How an operator reads the shared admin password (needs Key Vault Secrets Officer/User and an allowlisted egress)."
  value       = "az keyvault secret show --vault-name ${module.keyvault.name} --name platform-admin-password --query value -o tsv"
}

output "vault_allowed_sources" {
  value = local.ip_rules
}
