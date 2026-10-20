output "cluster_name" {
  value = module.aks.cluster_name
}

output "resource_group_name" {
  value = module.aks.resource_group_name
}

output "cluster_endpoint" {
  value = module.aks.cluster_endpoint
}

output "oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}

output "node_resource_group" {
  value = module.aks.node_resource_group
}

output "get_credentials_command" {
  description = "Configure kubectl (Entra ID login via kubelogin)."
  value       = "az aks get-credentials --resource-group ${module.aks.resource_group_name} --name ${module.aks.cluster_name} && kubelogin convert-kubeconfig -l azurecli"
}

output "auto_stop" {
  value = local.autostop_enabled ? module.autostop[0].stop_schedule : "disabled"
}

output "auto_start" {
  value = local.autostop_enabled ? module.autostop[0].start_schedule : "disabled"
}

output "api_server_allowed_sources" {
  description = "CIDRs that may reach the API server, or 'any'."
  value       = length(local.api_server_sources) == 0 ? ["any"] : local.api_server_sources
}
