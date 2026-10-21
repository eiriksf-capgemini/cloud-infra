locals {
  tags = merge({
    environment = "poc"
    managed_by  = "opentofu"
    repo        = "cloud-infra"
    stack       = "azure/poc/20-cluster"
  }, var.tags)

  cluster_name = "aks-${var.name_prefix}"

  # Operators' egress ranges (ADR 0009); the API server accepts at most 200, so the full
  # Norway list used by the ingress NSG does not fit here.
  trusted_egress = [
    for line in split("\n", file("${path.module}/../allowlist/trusted-egress-ipv4.txt")) : trimspace(line)
    if trimspace(line) != "" && !startswith(trimspace(line), "#")
  ]
  # AKS wants CIDR notation; accept bare IPs too and normalise, so the same value works
  # here and in 00-tfstate (which wants bare IPs).
  api_server_sources = var.api_server_restricted ? distinct(concat(
    [for s in concat(local.trusted_egress, var.api_server_extra_sources) : strcontains(s, "/") ? s : "${s}/32"],
    [for ip in local.cluster_egress_ips : "${ip}/32"],
  )) : []

  # Pods reach the API server through the cluster's own outbound IP(s), which must stay
  # authorised or Argo CD and every controller lose the API. AKS adds them itself at
  # creation; on later applies we add them explicitly from the node resource group.
  cluster_egress_ips = var.api_server_restricted && var.api_server_include_cluster_egress ? [
    for pip in data.azurerm_public_ip.cluster_egress : pip.ip_address
  ] : []

  autostop_enabled = length(var.auto_stop_times) > 0
}

# Coupled to 10-network by naming convention (ADR 0002) rather than remote state,
# so this stack can be planned without reading another stack's state file.
data "azurerm_resource_group" "network" {
  name = "rg-${var.name_prefix}"
}

data "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  virtual_network_name = "vnet-${var.name_prefix}"
  resource_group_name  = data.azurerm_resource_group.network.name
}

# The cluster's standard load balancer lives in the node resource group AKS manages; its
# frontends include the outbound (egress) IP. Only readable once the cluster exists.
data "azurerm_lb" "kubernetes" {
  count = var.api_server_restricted && var.api_server_include_cluster_egress ? 1 : 0

  name                = "kubernetes"
  resource_group_name = "${data.azurerm_resource_group.network.name}-${local.cluster_name}-nodes"
}

data "azurerm_public_ip" "cluster_egress" {
  for_each = var.api_server_restricted && var.api_server_include_cluster_egress ? toset([
    for f in data.azurerm_lb.kubernetes[0].frontend_ip_configuration : f.public_ip_address_id if f.public_ip_address_id != null && f.public_ip_address_id != ""
  ]) : toset([])

  name                = element(split("/", each.value), 8)
  resource_group_name = element(split("/", each.value), 4)
}

# Static public IPs from 10-network (ADR 0010), by naming convention.
data "azurerm_public_ip" "static" {
  for_each = toset(var.public_ip_names)

  name                = "pip-${var.name_prefix}-${each.value}"
  resource_group_name = data.azurerm_resource_group.network.name
}

module "aks" {
  source = "../../../../modules/azure/aks"

  # common interface
  name               = local.cluster_name
  location           = var.location
  kubernetes_version = var.kubernetes_version
  system_node_pool   = var.system_node_pool
  user_node_pools    = var.user_node_pools
  tags               = local.tags

  # azure specific
  resource_group_name    = data.azurerm_resource_group.network.name
  subnet_id              = data.azurerm_subnet.aks.id
  admin_group_object_ids = var.admin_group_object_ids

  api_server_authorized_ip_ranges = local.api_server_sources
  public_ip_ids                   = [for p in data.azurerm_public_ip.static : p.id]

  # Nothing in the POC uses Entra Workload ID yet (external-dns is disabled, Tekton pushes
  # are a to-do); its webhook alone would request 200m of the node's 1900m CPU (ADR 0004).
  # Set true in tfvars when the first federated credential is created; in-place update.
  workload_identity_enabled = var.workload_identity_enabled

  # Managed Prometheus agent (ADR 0008); destination is the 40-observability stack.
  azure_monitor_metrics_enabled = var.azure_monitor_metrics_enabled
}

# Cost control: stop the cluster at the end of the working day, and again late in the
# evening in case it was started for late work (ADR 0004). Start it again with
# `make aks-start`, or set auto_start_time for weekday mornings.
module "autostop" {
  count  = local.autostop_enabled ? 1 : 0
  source = "../../../../modules/azure/aks-autostop"

  name                        = local.cluster_name
  location                    = var.automation_location
  resource_group_name         = data.azurerm_resource_group.network.name
  cluster_id                  = module.aks.cluster_id
  cluster_name                = module.aks.cluster_name
  cluster_resource_group_name = module.aks.resource_group_name
  stop_times                  = var.auto_stop_times
  start_time                  = var.auto_start_time
  timezone                    = "Europe/Oslo"
  timezone_utc_offset         = var.timezone_utc_offset
  tags                        = local.tags
}
