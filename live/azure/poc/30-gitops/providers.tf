provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Looks the cluster up by name (ADR 0002) and uses its admin credential for the
# one-time bootstrap. Everything after this is reconciled by Argo CD from Git.
data "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${var.name_prefix}"
  resource_group_name = "rg-${var.name_prefix}"
}

provider "helm" {
  kubernetes = {
    host                   = data.azurerm_kubernetes_cluster.this.kube_admin_config[0].host
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.this.kube_admin_config[0].client_certificate)
    client_key             = base64decode(data.azurerm_kubernetes_cluster.this.kube_admin_config[0].client_key)
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.this.kube_admin_config[0].cluster_ca_certificate)
  }
}
