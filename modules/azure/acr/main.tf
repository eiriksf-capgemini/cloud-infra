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

# principal_type is passed to ARM so it does not have to look the principal up in
# Microsoft Graph; without it, assignments for a just-created managed identity can
# fail with "principal not found" until the directory has replicated.
resource "azurerm_role_assignment" "pull" {
  for_each = var.pull_principals

  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = each.value.object_id
  principal_type       = each.value.principal_type
  description          = "AcrPull for ${each.key} (managed by OpenTofu)"
}

resource "azurerm_role_assignment" "push" {
  for_each = var.push_principals

  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPush"
  principal_id         = each.value.object_id
  principal_type       = each.value.principal_type
  description          = "AcrPush for ${each.key} (managed by OpenTofu)"
}
