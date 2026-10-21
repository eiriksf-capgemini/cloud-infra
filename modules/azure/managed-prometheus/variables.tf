variable "name" {
  description = "Base name for the workspace and collection resources, e.g. 'cloudinfra-poc'. Produces amw-<name>, dce-<name>-prom, dcr-<name>-prom."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name))
    error_message = "name must be 3-40 chars of lowercase letters, digits and hyphens."
  }
}

variable "location" {
  description = "Azure region. The workspace, DCE, DCR and rule groups must share it."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the workspace and collection resources."
  type        = string
}

variable "cluster_id" {
  description = "Resource ID of the AKS cluster whose metrics add-on sends data here. The cluster must have monitor_metrics enabled (modules/azure/aks: azure_monitor_metrics_enabled)."
  type        = string
}

variable "cluster_name" {
  description = "AKS cluster name; used in rule group names and as the cluster filter on recording rules."
  type        = string
}

variable "recording_rules_enabled" {
  description = "Create the default node / Kubernetes / UX recording rule groups the community dashboards depend on. Rule evaluation is free."
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Allow ingestion and queries over public endpoints. Private link needs a Premium-style setup that is out of scope for the POC."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
