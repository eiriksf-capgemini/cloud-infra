# Azure Monitor managed service for Prometheus for one AKS cluster:
#   Azure Monitor workspace (the Prometheus TSDB, 18 months retention)
#   + data collection endpoint / rule that accept Prometheus samples
#   + association that points the cluster's metrics add-on at that rule
#   + the default recording rule groups (rules.tf).
#
# Nothing here runs in the cluster. The scraping agent (ama-metrics) is the AKS
# add-on enabled by modules/azure/aks with azure_monitor_metrics_enabled = true.
# Dashboards come for free from "Azure Monitor > Dashboards with Grafana" in the
# portal; no Grafana instance is created (ADR 0008).

resource "azurerm_monitor_workspace" "this" {
  name                          = "amw-${var.name}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  public_network_access_enabled = var.public_network_access_enabled
  tags                          = var.tags
}

resource "azurerm_monitor_data_collection_endpoint" "this" {
  name                          = "dce-${var.name}-prom"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  kind                          = "Linux"
  public_network_access_enabled = var.public_network_access_enabled
  tags                          = var.tags
}

resource "azurerm_monitor_data_collection_rule" "this" {
  name                        = "dcr-${var.name}-prom"
  location                    = var.location
  resource_group_name         = var.resource_group_name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.this.id
  kind                        = "Linux"
  description                 = "Prometheus metrics from ${var.cluster_name} to ${azurerm_monitor_workspace.this.name} (managed by OpenTofu)"
  tags                        = var.tags

  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.this.id
      name               = "MonitoringAccount1"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount1"]
  }

  data_sources {
    prometheus_forwarder {
      streams = ["Microsoft-PrometheusMetrics"]
      name    = "PrometheusDataSource"
    }
  }
}

# Deleting this association stops collection for the cluster.
resource "azurerm_monitor_data_collection_rule_association" "cluster" {
  name                    = "dcra-${var.name}-prom"
  target_resource_id      = var.cluster_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.this.id
  description             = "Routes ${var.cluster_name} Prometheus metrics to ${azurerm_monitor_workspace.this.name}"
}
