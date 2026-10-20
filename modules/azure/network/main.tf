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

resource "azurerm_network_security_rule" "ingress" {
  for_each = { for p in var.ingress_allowed_ports : tostring(p) => p }

  name                  = "AllowIngress${each.key}Inbound"
  priority              = 1000 + index(var.ingress_allowed_ports, each.value)
  direction             = "Inbound"
  access                = "Allow"
  protocol              = "Tcp"
  source_address_prefix = var.ingress_source
  source_port_range     = "*"
  # "*" not the subnet CIDR: AKS load balancer rules use floating IP (DSR), so packets
  # arrive at the node NIC with the LB's public IP as destination.
  destination_address_prefix  = "*"
  destination_port_range      = each.key
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.aks.name
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}
