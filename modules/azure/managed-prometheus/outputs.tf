output "workspace_id" {
  description = "Resource ID of the Azure Monitor workspace (Prometheus store)."
  value       = azurerm_monitor_workspace.this.id
}

output "workspace_name" {
  description = "Name of the Azure Monitor workspace."
  value       = azurerm_monitor_workspace.this.name
}

output "query_endpoint" {
  description = "PromQL query endpoint; use as a Prometheus data source URL (Entra ID auth)."
  value       = azurerm_monitor_workspace.this.query_endpoint
}

output "data_collection_rule_id" {
  description = "DCR the cluster is associated with."
  value       = azurerm_monitor_data_collection_rule.this.id
}
