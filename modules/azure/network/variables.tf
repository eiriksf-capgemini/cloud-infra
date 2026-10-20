variable "name_prefix" {
  description = "Prefix used for all resource names, e.g. 'cloudinfra-poc'. Produces rg-<prefix>, vnet-<prefix>."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name_prefix))
    error_message = "name_prefix must be 3-40 chars of lowercase letters, digits and hyphens."
  }
}

variable "location" {
  description = "Azure region, e.g. 'norwayeast' or 'westeurope'."
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

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
