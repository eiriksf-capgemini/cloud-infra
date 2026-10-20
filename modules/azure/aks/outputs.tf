# ---- common interface -----------------------------------------------------

output "cluster_name" {
  description = "Cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_id" {
  description = "Cloud resource ID of the cluster."
  value       = azurerm_kubernetes_cluster.this.id
}

output "cluster_endpoint" {
  description = "Kubernetes API server URL."
  # Built from the FQDN rather than kube_config[0].host so the output is not tainted sensitive.
  value = "https://${azurerm_kubernetes_cluster.this.fqdn}:443"
}

output "cluster_ca_certificate" {
  description = "PEM-encoded cluster CA certificate."
  value       = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity federation."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

# ---- azure specific -------------------------------------------------------

output "resource_group_name" {
  description = "Resource group containing the cluster resource."
  value       = azurerm_kubernetes_cluster.this.resource_group_name
}

output "node_resource_group" {
  description = "Auto-managed resource group with nodes, load balancer, disks."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "cluster_identity_principal_id" {
  description = "Principal ID of the cluster's user-assigned identity."
  value       = azurerm_user_assigned_identity.cluster.principal_id
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet identity (needed for ACR pull, etc.)."
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

output "kube_admin_config" {
  description = "Admin credentials (client cert auth). Only populated while local accounts are enabled."
  value = var.local_account_disabled ? null : {
    host                   = azurerm_kubernetes_cluster.this.kube_admin_config[0].host
    client_certificate     = azurerm_kubernetes_cluster.this.kube_admin_config[0].client_certificate
    client_key             = azurerm_kubernetes_cluster.this.kube_admin_config[0].client_key
    cluster_ca_certificate = azurerm_kubernetes_cluster.this.kube_admin_config[0].cluster_ca_certificate
  }
  sensitive = true
}
