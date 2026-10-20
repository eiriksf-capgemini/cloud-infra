output "resource_group_name" {
  value = module.network.resource_group_name
}

output "vnet_name" {
  value = module.network.vnet_name
}

output "aks_subnet_id" {
  value = module.network.aks_subnet_id
}

output "ingress_allowed_source_count" {
  description = "Number of CIDRs allowed to reach the ingress ports (1 = a service tag such as Internet)."
  value       = length(local.ingress_sources) == 0 ? 1 : length(local.ingress_sources)
}
