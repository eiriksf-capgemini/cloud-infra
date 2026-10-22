variable "name" {
  description = "Key Vault name. Globally unique, 3-24 alphanumerics and hyphens; becomes <name>.vault.azure.net."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 3-24 chars, start with a letter, letters/digits/hyphens only."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create the vault in."
  type        = string
}

variable "allowed_ip_rules" {
  description = "CIDRs/IPs allowed through the vault firewall (operators' egress, the cluster's egress IP). Everything else is denied; trusted Azure services bypass."
  type        = list(string)
  default     = []
}

variable "reader_principal_ids" {
  description = "Object IDs granted Key Vault Secrets User (read secrets), e.g. the AKS kubelet identity External Secrets runs with."
  type        = map(string)
  default     = {}
}

variable "officer_principal_ids" {
  description = "Object IDs granted Key Vault Secrets Officer (read/write secrets), e.g. the deployer."
  type        = map(string)
  default     = {}
}

variable "generated_secrets" {
  description = "Secrets to generate with random_password and store: name => length. Values live in the vault and in this stack's state (ADR 0011)."
  type        = map(number)
  default     = {}
}

variable "soft_delete_retention_days" {
  description = "7-90. Purge protection stays off so a POC can be torn down."
  type        = number
  default     = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
