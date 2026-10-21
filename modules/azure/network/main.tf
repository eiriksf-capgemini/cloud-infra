# Azure network foundation for a single environment:
# resource group, VNet, one subnet for AKS nodes, and an NSG on that subnet.

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name_prefix}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.address_space
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.aks_subnet_cidr]
}

# Subnet NSG. AKS only manages the NSG on its own node NICs (in the node resource
# group); a subnet NSG's default DenyAllInBound still blocks Internet traffic to
# LoadBalancer services, so public ingress ports must be allowed here explicitly.
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-${var.name_prefix}-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

locals {
  # A single service tag ("Internet") must go in source_address_prefix; a list of CIDRs in
  # source_address_prefixes. Azure allows up to 4000 prefixes per rule.
  ingress_single_source = length(var.ingress_allowed_sources) == 1 ? var.ingress_allowed_sources[0] : null
}

resource "azurerm_network_security_rule" "ingress" {
  count = length(var.ingress_allowed_ports) == 0 ? 0 : 1

  name                    = "AllowIngressInbound"
  priority                = 1100 # not 1000/1001: lets this rule coexist with the per-port rules it replaced during an upgrade apply
  direction               = "Inbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_address_prefix   = local.ingress_single_source
  source_address_prefixes = local.ingress_single_source == null ? var.ingress_allowed_sources : null
  source_port_range       = "*"
  # "*" not the subnet CIDR: AKS load balancer rules use floating IP (DSR), so packets
  # arrive at the node NIC with the LB's public IP as destination.
  destination_address_prefix  = "*"
  destination_port_ranges     = [for p in var.ingress_allowed_ports : tostring(p)]
  description                 = "Ingress ports from ${length(var.ingress_allowed_sources)} allowed source(s); everything else stays on DenyAllInBound (ADR 0009)."
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.aks.name
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# Static public IPs for LoadBalancer Services. Created here, not in the AKS node resource
# group, so they survive `tofu destroy` of 20-cluster; the cluster identity is granted
# Network Contributor on each one by the AKS module (public_ip_ids).
resource "azurerm_public_ip" "this" {
  for_each = toset(var.public_ips)

  name                = "pip-${var.name_prefix}-${each.value}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"
  allocation_method   = "Static"
  tags                = var.tags
}
