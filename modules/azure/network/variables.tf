variable "name_prefix" {
  description = "Prefix used for all resource names, e.g. 'cloudinfra-poc'. Produces rg-<prefix>, vnet-<prefix>."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name_prefix))
    error_message = "name_prefix must be 3-40 chars of lowercase letters, digits and hyphens."
  }
}

variable "location" {
  description = "Azure region, e.g. 'swedencentral' or 'westeurope'."
  type        = string
}

variable "address_space" {
  description = "VNet address space."
  type        = list(string)
  default     = ["10.10.0.0/16"]
}

variable "aks_subnet_cidr" {
  description = "CIDR for the AKS node subnet. Must be inside address_space."
  type        = string
  default     = "10.10.0.0/22"
}

variable "ingress_allowed_ports" {
  description = "TCP ports allowed inbound from `ingress_allowed_sources` to the AKS subnet (for LoadBalancer services such as ingress-nginx). Empty list = nothing from the Internet."
  type        = list(number)
  default     = [80, 443]
}

variable "ingress_allowed_sources" {
  description = "Sources allowed to reach the ingress ports: either exactly one service tag (e.g. [\"Internet\"]) or a list of CIDRs (up to 4000, e.g. a country's registered prefixes). Everything else is denied by the NSG default rule."
  type        = list(string)
  default     = ["Internet"]

  validation {
    condition     = length(var.ingress_allowed_sources) > 0
    error_message = "ingress_allowed_sources must not be empty; set ingress_allowed_ports = [] to close the ports instead."
  }

  validation {
    condition     = length(var.ingress_allowed_sources) == 1 || alltrue([for s in var.ingress_allowed_sources : can(cidrhost(s, 0))])
    error_message = "With more than one entry every source must be a CIDR; service tags cannot be mixed into a list."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "public_ips" {
  description = "Names of Standard static public IPs to create as pip-<prefix>-<name>. They outlive the cluster, so LoadBalancer Services pinned to them (ingress-nginx) keep their address across a cluster recreate (ADR 0010). ~$3.65/month each, billed whether or not the cluster runs; Free Trial quota is 3 public IPs per region including the cluster egress IP."
  type        = list(string)
  default     = []
}
