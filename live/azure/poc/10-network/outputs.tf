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
  value       = var.ingress_allow_internet ? 1 : length(local.ingress_sources)
}

output "public_ips" {
  description = "Static public IPs by short name; paste the addresses into the gitops hostnames (see ADR 0010)."
  value       = { for k, v in module.network.public_ips : k => v.ip_address }
}
