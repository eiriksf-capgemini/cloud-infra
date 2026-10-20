locals {
  tags = merge({
    environment = "poc"
    managed_by  = "opentofu"
    repo        = "cloud-infra"
    stack       = "azure/poc/10-network"
  }, var.tags)
}

module "network" {
  source = "../../../../modules/azure/network"

  name_prefix     = var.name_prefix
  location        = var.location
  address_space   = var.address_space
  aks_subnet_cidr = var.aks_subnet_cidr
  tags            = local.tags
}
