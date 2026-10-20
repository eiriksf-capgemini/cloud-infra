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
}

variable "registry_name" {
  description = "Explicit registry name. null = acr<organization>."
  type        = string
  default     = null
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

variable "push_principal_ids" {
  description = "Extra principals (e.g. a CI identity) granted AcrPush, keyed by label."
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
