variable "name" {
  description = "Base name for the automation account, e.g. the cluster name."
  type        = string
}

variable "location" {
  description = "Region for the Automation account. Independent of the cluster region; Free Trial / Student subscriptions may only use eastus, eastus2, westus, northeurope, southeastasia, japanwest."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "cluster_id" {
  description = "Resource ID of the AKS cluster to stop/start."
  type        = string
}

variable "cluster_name" {
  type = string
}

variable "cluster_resource_group_name" {
  type = string
}

variable "timezone" {
  description = "IANA timezone for the schedules."
  type        = string
  default     = "Europe/Oslo"
}

variable "stop_time" {
  description = "Daily stop time, HH:MM in `timezone`."
  type        = string
  default     = "19:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.stop_time))
    error_message = "stop_time must be HH:MM (24h)."
  }
}

variable "start_time" {
  description = "Optional daily start time, HH:MM in `timezone`. null = never auto-start (start manually with `make aks-start`)."
  type        = string
  default     = null

  validation {
    condition     = var.start_time == null || can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.start_time))
    error_message = "start_time must be HH:MM (24h) or null."
  }
}

variable "start_week_days" {
  description = "Days the start schedule fires (only when start_time is set). Stop fires every day."
  type        = list(string)
  default     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
