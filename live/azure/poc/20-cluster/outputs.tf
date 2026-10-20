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
  value = length(var.auto_stop_times) == 0 ? "disabled" : module.autostop[0].stop_schedule
}

output "auto_start" {
  value = length(var.auto_stop_times) == 0 ? "disabled" : module.autostop[0].start_schedule
}
