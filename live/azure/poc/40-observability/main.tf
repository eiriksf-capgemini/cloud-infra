locals {
  tags = merge({
    environment = "poc"
    managed_by  = "opentofu"
    repo        = "cloud-infra"
    stack       = "azure/poc/40-observability"
  }, var.tags)
}

# Coupled to 10-network and 20-cluster by naming convention (ADR 0002), not remote state.
data "azurerm_resource_group" "this" {
  name = "rg-${var.name_prefix}"
}

data "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${var.name_prefix}"
  resource_group_name = data.azurerm_resource_group.this.name
}

# Destination side of Azure Monitor managed Prometheus (ADR 0008). The cluster side,
# the ama-metrics add-on, is switched on in 20-cluster (azure_monitor_metrics_enabled).
module "prometheus" {
  source = "../../../../modules/azure/managed-prometheus"

  name                    = var.name_prefix
  location                = var.location
  resource_group_name     = data.azurerm_resource_group.this.name
  cluster_id              = data.azurerm_kubernetes_cluster.this.id
  cluster_name            = data.azurerm_kubernetes_cluster.this.name
  recording_rules_enabled = var.recording_rules_enabled
  tags                    = local.tags
}
