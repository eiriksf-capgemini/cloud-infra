output "resource_group_name" {
  value = module.network.resource_group_name
}

output "vnet_name" {
  value = module.network.vnet_name
}

output "aks_subnet_id" {
  value = module.network.aks_subnet_id
}
