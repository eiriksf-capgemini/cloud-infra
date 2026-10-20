# Azure Container Registry plus the data-plane role assignments that let
# workloads pull from it. Authentication is Entra ID only (admin user off):
# humans use `az acr login`, clusters use their kubelet managed identity.

resource "azurerm_container_registry" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  admin_enabled       = var.admin_enabled
  tags                = var.tags
}

# Managed identities are service principals in Entra ID. Setting principal_type
# avoids the "principal not found" race right after an identity is created.
resource "azurerm_role_assignment" "pull" {
  for_each = var.pull_principal_ids

  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
  description          = "AcrPull for ${each.key} (managed by OpenTofu)"
}

resource "azurerm_role_assignment" "push" {
  for_each = var.push_principal_ids

  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPush"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
  description          = "AcrPush for ${each.key} (managed by OpenTofu)"
}
