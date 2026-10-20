locals {
  tags = merge({
    environment = "poc"
    managed_by  = "opentofu"
    repo        = "cloud-infra"
    stack       = "azure/poc/25-registry"
  }, var.tags)

  registry_name = coalesce(var.registry_name, "acr${var.organization}")
}

# Coupled to 10-network and 20-cluster by naming convention (ADR 0002), not remote state.
data "azurerm_resource_group" "this" {
  name = "rg-${var.name_prefix}"
}

data "azurerm_kubernetes_cluster" "this" {
  count = var.grant_aks_pull ? 1 : 0

  name                = "aks-${var.name_prefix}"
  resource_group_name = data.azurerm_resource_group.this.name
}

module "acr" {
  source = "../../../../modules/azure/acr"

  name                = local.registry_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  sku                 = var.sku
  tags                = local.tags

  # The kubelet identity is what pulls images on the nodes; it is created by AKS,
  # so it is looked up rather than passed from 20-cluster.
  pull_principal_ids = var.grant_aks_pull ? {
    aks-kubelet = data.azurerm_kubernetes_cluster.this[0].kubelet_identity[0].object_id
  } : {}
  push_principal_ids = var.push_principal_ids
}
