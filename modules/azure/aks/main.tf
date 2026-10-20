# Managed AKS cluster sized for a proof of concept.
#
# Design choices:
# - User-assigned identity created first and granted Network Contributor on the
#   node subnet, so AKS can plumb the load balancer into a bring-your-own VNet.
# - Azure CNI Overlay: nodes get VNet IPs, pods get a private overlay CIDR, so a
#   /22 subnet is plenty.
# - OIDC issuer + workload identity on from day one; external-dns, cert-manager
#   and friends should authenticate to Azure with federated credentials, not keys.
# - Entra ID authentication with Azure RBAC for kubectl users; local accounts
#   left enabled so the GitOps bootstrap stack has a credential to use.

data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "cluster" {
  name                = "id-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "cluster_identity_subnet" {
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  node_resource_group = "${var.resource_group_name}-${var.name}-nodes"

  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  local_account_disabled            = var.local_account_disabled
  role_based_access_control_enabled = true

  default_node_pool {
    name                        = "system"
    vm_size                     = var.system_node_pool.vm_size
    node_count                  = var.system_node_pool.node_count
    os_disk_size_gb             = var.system_node_pool.os_disk_gb
    vnet_subnet_id              = var.subnet_id
    temporary_name_for_rotation = "systemtmp"
    tags                        = var.tags

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  # Required since azurerm 5.0. "Manual" = classic node pools; "Auto" = Node Auto Provisioning (Karpenter).
  node_provisioning_profile {
    mode = "Manual"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    load_balancer_sku   = "standard"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  tags = var.tags

  depends_on = [azurerm_role_assignment.cluster_identity_subnet]

  lifecycle {
    # Let AKS auto-patch within the minor; do not fight it on every plan.
    ignore_changes = [kubernetes_version, default_node_pool[0].orchestrator_version]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  for_each = var.user_node_pools

  name                  = each.key
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  mode                  = "User"
  vm_size               = each.value.vm_size
  node_count            = each.value.node_count
  os_disk_size_gb       = each.value.os_disk_gb
  vnet_subnet_id        = var.subnet_id
  node_labels           = each.value.labels
  node_taints           = each.value.taints
  tags                  = var.tags

  lifecycle {
    ignore_changes = [orchestrator_version]
  }
}

# Lets whoever ran `tofu apply` use kubectl immediately via `az aks get-credentials`.
resource "azurerm_role_assignment" "deployer_cluster_admin" {
  count = var.grant_deployer_cluster_admin ? 1 : 0

  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}
