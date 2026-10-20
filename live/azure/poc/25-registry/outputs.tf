output "registry_name" {
  value = module.acr.name
}

output "login_server" {
  description = "Use as the image prefix: <login_server>/<repo>:<tag>."
  value       = module.acr.login_server
}

output "login_command" {
  description = "Authenticate the local docker/podman client with Entra ID (no admin password)."
  value       = "az acr login --name ${module.acr.name}"
}

output "aks_pull_granted_to" {
  description = "Kubelet identity object ID that holds AcrPull, or 'disabled'."
  value       = var.grant_aks_pull ? data.azurerm_kubernetes_cluster.this[0].kubelet_identity[0].object_id : "disabled"
}
