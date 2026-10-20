locals {
  tags = merge({
    environment = "poc"
    managed_by  = "opentofu"
    repo        = "cloud-infra"
    stack       = "azure/poc/20-cluster"
  }, var.tags)

  cluster_name = "aks-${var.name_prefix}"
}

# Coupled to 10-network by naming convention (ADR 0002) rather than remote state,
# so this stack can be planned without reading another stack's state file.
data "azurerm_resource_group" "network" {
  name = "rg-${var.name_prefix}"
}

data "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  virtual_network_name = "vnet-${var.name_prefix}"
  resource_group_name  = data.azurerm_resource_group.network.name
}

module "aks" {
  source = "../../../../modules/azure/aks"

  # common interface
  name               = local.cluster_name
  location           = var.location
  kubernetes_version = var.kubernetes_version
  system_node_pool   = var.system_node_pool
  user_node_pools    = var.user_node_pools
  tags               = local.tags

  # azure specific
  resource_group_name    = data.azurerm_resource_group.network.name
  subnet_id              = data.azurerm_subnet.aks.id
  admin_group_object_ids = var.admin_group_object_ids
}

# Cost control: stop the cluster every evening (ADR 0004). Start it again with
# `make aks-start`, or set auto_start_time for weekday mornings.
module "autostop" {
  count  = var.auto_stop_time == null ? 0 : 1
  source = "../../../../modules/azure/aks-autostop"

  name                        = local.cluster_name
  location                    = var.location
  resource_group_name         = data.azurerm_resource_group.network.name
  cluster_id                  = module.aks.cluster_id
  cluster_name                = module.aks.cluster_name
  cluster_resource_group_name = module.aks.resource_group_name
  stop_time                   = var.auto_stop_time
  start_time                  = var.auto_start_time
  timezone                    = "Europe/Oslo"
  tags                        = local.tags
}
