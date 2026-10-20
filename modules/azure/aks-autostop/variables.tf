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

variable "timezone_utc_offset" {
  description = "UTC offset of `timezone` at the moment of the first apply, e.g. '+02:00' (CEST) or '+01:00' (CET). Azure derives the schedule's wall-clock time from start_time, so a 'Z' time would be read as UTC. Only the first apply uses it; later plans ignore start_time."
  type        = string
  default     = "+01:00"

  validation {
    condition     = can(regex("^[+-]([01][0-9]):[0-5][0-9]$", var.timezone_utc_offset))
    error_message = "timezone_utc_offset must look like +02:00 or -05:00."
  }
}

variable "stop_times" {
  description = "Daily stop times, HH:MM in `timezone`. Several entries give several schedules, e.g. [\"17:00\", \"22:00\"] for end of day plus a late-work safety net. Must not be empty."
  type        = list(string)
  default     = ["19:00"]

  validation {
    condition     = length(var.stop_times) > 0 && alltrue([for t in var.stop_times : can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", t))])
    error_message = "stop_times must be a non-empty list of HH:MM (24h) strings."
  }

  validation {
    condition     = length(distinct(var.stop_times)) == length(var.stop_times)
    error_message = "stop_times must not contain duplicates."
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
