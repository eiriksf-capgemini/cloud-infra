output "resource_group_name" {
  description = "Name of the resource group that holds the network."
  value       = azurerm_resource_group.this.name
}

output "location" {
  description = "Azure region of the network."
  value       = azurerm_resource_group.this.location
}

output "vnet_id" {
  description = "ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the virtual network."
  value       = azurerm_virtual_network.this.name
}

output "aks_subnet_id" {
  description = "ID of the subnet reserved for AKS nodes."
  value       = azurerm_subnet.aks.id
}

output "aks_subnet_name" {
  description = "Name of the subnet reserved for AKS nodes."
  value       = azurerm_subnet.aks.name
}
