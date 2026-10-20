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
  description = "Must match 10-network; used to look up the RG, VNet and subnet by name."
  type        = string
  default     = "cloudinfra-poc"
}

variable "kubernetes_version" {
  description = "null = AKS default for the region."
  type        = string
  default     = null
}

variable "system_node_pool" {
  type = object({
    vm_size    = optional(string, "Standard_B2als_v2") # cheapest x86 size AKS accepts for a system pool (ADR 0004)
    node_count = optional(number, 1)
    os_disk_gb = optional(number, 32) # P4 tier; AKS minimum is 30
  })
  default = {}
}

variable "user_node_pools" {
  type = map(object({
    vm_size    = string
    node_count = optional(number, 1)
    min_count  = optional(number)
    max_count  = optional(number)
    os_disk_gb = optional(number, 64)
    labels     = optional(map(string), {})
    taints     = optional(list(string), [])
    spot       = optional(bool, false)
  }))
  default = {}
}

variable "auto_stop_time" {
  description = "Daily time (HH:MM, Europe/Oslo) to stop the cluster. null disables auto-stop."
  type        = string
  default     = "19:00"
}

variable "auto_start_time" {
  description = "Weekday time (HH:MM, Europe/Oslo) to start the cluster. null = start manually with `make aks-start`."
  type        = string
  default     = null
}

variable "admin_group_object_ids" {
  description = "Entra ID groups that get cluster-admin. Empty is fine for a POC; the deployer is granted admin anyway."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
