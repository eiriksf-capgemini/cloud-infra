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

variable "recording_rules_enabled" {
  description = "Create the default recording rule groups the portal's Kubernetes dashboards depend on. Free; disable only to debug."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
