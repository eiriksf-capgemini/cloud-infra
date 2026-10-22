# One admin password for every platform login (ADR 0011): generated here, stored in Key
# Vault, read by External Secrets with the AKS kubelet identity and written into the
# Secrets Argo CD and ThunderID consume (gitops/platform/platform-secrets). Rotate with
# `tofu taint` on the random_password or `az keyvault secret set`; External Secrets refreshes
# within an hour.

locals {
  tags = merge({
    environment = "poc"
    managed_by  = "opentofu"
    repo        = "cloud-infra"
    stack       = "azure/poc/35-secrets"
  }, var.tags)

  operator_sources = distinct(concat(flatten([
    for f in var.allowlist_files : [
      for line in split("\n", file("${path.module}/${f}")) : trimspace(line)
      if trimspace(line) != "" && !startswith(trimspace(line), "#")
    ]
  ]), var.extra_sources))

  # Key Vault ip_rules take IPv4 addresses or CIDRs; /32 must be written as a bare address.
  ip_rules = distinct(concat(
    [for s in local.operator_sources : endswith(s, "/32") ? trimsuffix(s, "/32") : s],
    [for pip in data.azurerm_public_ip.cluster_egress : pip.ip_address],
  ))
}

# Coupled to 10-network and 20-cluster by naming convention (ADR 0002), not remote state.
data "azurerm_resource_group" "this" {
  name = "rg-${var.name_prefix}"
}

data "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${var.name_prefix}"
  resource_group_name = data.azurerm_resource_group.this.name
}

data "azurerm_client_config" "current" {}

# The nodes reach the vault through the cluster's outbound load balancer IP(s).
data "azurerm_lb" "kubernetes" {
  name                = "kubernetes"
  resource_group_name = data.azurerm_kubernetes_cluster.this.node_resource_group
}

data "azurerm_public_ip" "cluster_egress" {
  for_each = toset([
    for f in data.azurerm_lb.kubernetes.frontend_ip_configuration : f.public_ip_address_id
    if f.public_ip_address_id != null && f.public_ip_address_id != ""
  ])

  name                = element(split("/", each.value), 8)
  resource_group_name = element(split("/", each.value), 4)
}

module "keyvault" {
  source = "../../../../modules/azure/keyvault"

  name                = var.key_vault_name
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = local.tags

  allowed_ip_rules = local.ip_rules

  # External Secrets authenticates with the node's (kubelet) managed identity over IMDS.
  reader_principal_ids = {
    aks-kubelet = data.azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  }
  officer_principal_ids = {
    deployer = data.azurerm_client_config.current.object_id
  }

  generated_secrets = {
    platform-admin-password = var.admin_password_length
  }
}
