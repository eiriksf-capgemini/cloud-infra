variable "subscription_id" {
  description = "Azure subscription ID. Leave null to use ARM_SUBSCRIPTION_ID / az CLI default."
  type        = string
  default     = null
}

variable "location" {
  type    = string
  default = "swedencentral"
}

variable "name_prefix" {
  description = "Must match 10-network and 20-cluster; used to look up the resource group and cluster by name."
  type        = string
  default     = "cloudinfra-poc"
}

variable "organization" {
  description = "Organization label the registry name is derived from: acr<organization>.azurecr.io. Lowercase alphanumerics only; must be globally unique."
  type        = string
  default     = "madbadgerbadger"

  validation {
    condition     = can(regex("^[a-z0-9]{2,47}$", var.organization))
    error_message = "organization must be 2-47 lowercase letters and digits (no hyphens): acr<organization> must be a 5-50 char DNS label."
  }
}

variable "registry_name" {
  description = "Explicit registry name. null = acr<organization>."
  type        = string
  default     = null

  validation {
    condition     = var.registry_name == null || can(regex("^[a-z0-9]{5,50}$", var.registry_name))
    error_message = "registry_name must be 5-50 lowercase letters and digits."
  }
}

variable "sku" {
  description = "Basic is the cheapest tier (~$5/month) and enough for the POC (ADR 0006)."
  type        = string
  default     = "Basic"
}

variable "grant_aks_pull" {
  description = "Grant AcrPull to the kubelet identity of aks-<name_prefix>. Set false if 20-cluster is not deployed."
  type        = bool
  default     = true
}

variable "push_principals" {
  description = "Extra principals (e.g. a CI identity) granted AcrPush, keyed by label: { label = { object_id = \"<id>\", principal_type = \"ServicePrincipal\" } }."
  type = map(object({
    object_id      = string
    principal_type = optional(string, "ServicePrincipal")
  }))
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
