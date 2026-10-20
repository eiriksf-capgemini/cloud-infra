locals {
  tags = merge({
    environment = "poc"
    managed_by  = "opentofu"
    repo        = "cloud-infra"
    stack       = "azure/poc/10-network"
  }, var.tags)

  # Who may reach the ingress load balancer (ADR 0009): the prefixes in the allowlist files
  # (../allowlist/*.txt, '#' comments and blank lines ignored) plus any extra CIDRs. An
  # empty result means "Internet" so the variable defaults can be cleared to reopen.
  allowlist_prefixes = flatten([
    for f in var.ingress_allowlist_files : [
      for line in split("\n", file("${path.module}/${f}")) : trimspace(line)
      if trimspace(line) != "" && !startswith(trimspace(line), "#")
    ]
  ])
  ingress_sources = distinct(concat(local.allowlist_prefixes, var.ingress_extra_sources))
}

module "network" {
  source = "../../../../modules/azure/network"

  name_prefix     = var.name_prefix
  location        = var.location
  address_space   = var.address_space
  aks_subnet_cidr = var.aks_subnet_cidr
  tags            = local.tags

  ingress_allowed_ports   = var.ingress_allowed_ports
  ingress_allowed_sources = length(local.ingress_sources) == 0 ? ["Internet"] : local.ingress_sources
}
