output "workspace_name" {
  value = module.prometheus.workspace_name
}

output "workspace_id" {
  value = module.prometheus.workspace_id
}

output "query_endpoint" {
  description = "PromQL endpoint for any Grafana (Entra ID auth). The portal dashboards need no configuration."
  value       = module.prometheus.query_endpoint
}

output "dashboards" {
  description = "Where to look."
  value       = "Azure portal > Monitor > Dashboards with Grafana (select workspace ${module.prometheus.workspace_name}); or the AKS resource > Monitoring > Insights."
}
