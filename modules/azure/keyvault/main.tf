# Key Vault as the single source of the platform's shared credentials (ADR 0011).
# RBAC authorisation (no access policies), firewall default-deny with an allowlist, soft
# delete at the minimum, no purge protection so `tofu destroy` really destroys.

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = var.soft_delete_retention_days

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.allowed_ip_rules
  }

  tags = var.tags
}

resource "azurerm_role_assignment" "readers" {
  for_each = var.reader_principal_ids

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "officers" {
  for_each = var.officer_principal_ids

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value
}

resource "random_password" "generated" {
  for_each = var.generated_secrets

  length           = each.value
  special          = true
  override_special = "!#%+-=?@_" # safe in shells, YAML and HTTP basic auth
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 1
}

resource "azurerm_key_vault_secret" "generated" {
  for_each = var.generated_secrets

  name         = each.key
  value        = random_password.generated[each.key].result
  key_vault_id = azurerm_key_vault.this.id
  content_type = "password"
  tags         = var.tags

  # The deployer needs the Officer role before the first secret write.
  depends_on = [azurerm_role_assignment.officers]
}
