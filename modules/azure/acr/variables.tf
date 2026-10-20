variable "name" {
  description = "Registry name. Globally unique, 5-50 lowercase alphanumerics; becomes <name>.azurecr.io."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{5,50}$", var.name))
    error_message = "name must be 5-50 lowercase letters and digits (no hyphens); it is part of a public DNS name."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create the registry in."
  type        = string
}

variable "sku" {
  description = "Basic (10 GB, ~$5/month) is enough for a POC. Standard adds storage/throughput; Premium adds private link, geo-replication, retention policies."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be Basic, Standard or Premium."
  }
}

variable "admin_enabled" {
  description = "Enable the shared admin user (username/password). Keep false; use Entra ID (`az acr login`) and managed identities instead."
  type        = bool
  default     = false
}

variable "pull_principal_ids" {
  description = "Principals granted AcrPull, keyed by a stable label (e.g. { aks-kubelet = \"<object-id>\" }). Use for cluster kubelet identities."
  type        = map(string)
  default     = {}
}

variable "push_principal_ids" {
  description = "Principals granted AcrPush (push + pull), keyed by a stable label. Use for CI identities."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
