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
    vm_size    = optional(string, "Standard_B4s_v2") # 4 vCPU / 16 GB, Intel; uses the whole Free Trial quota, see ADR 0004 / 0010
    node_count = optional(number, 1)
    os_disk_gb = optional(number, 64) # P6 (~$10/month); 32 GB hit DiskPressure on every start, see ADR 0004
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

variable "auto_stop_times" {
  description = "Daily times (HH:MM, Europe/Oslo) to stop the cluster: end of the working day plus a late safety net for evenings it was started again. Empty list disables auto-stop. (Replaces the former auto_stop_time string; an old tfvars still setting that only produces a warning.)"
  type        = list(string)
  default     = ["17:00", "22:00"]

  validation {
    condition     = alltrue([for t in var.auto_stop_times : can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", t))]) && length(distinct(var.auto_stop_times)) == length(var.auto_stop_times)
    error_message = "auto_stop_times must be distinct HH:MM (24h) strings."
  }
}

variable "automation_location" {
  description = "Region for the auto-stop Automation account. Free Trial subscriptions are limited to eastus, eastus2, westus, northeurope, southeastasia, japanwest, and to ONE account per region; a deleted account blocks its region for 30 days (soft delete, portal-only restore). northeurope is blocked since the 2026-10-21 cluster recreate."
  type        = string
  default     = "eastus2"
}

variable "timezone_utc_offset" {
  description = "UTC offset of Europe/Oslo at first apply: +02:00 (CEST, until 25 Oct 2026) or +01:00 (CET). Only used to anchor the schedules."
  type        = string
  default     = "+02:00"
}

variable "auto_start_time" {
  description = "Weekday time (HH:MM, Europe/Oslo) to start the cluster. null = start manually with `make aks-start`."
  type        = string
  default     = null
}

variable "api_server_restricted" {
  description = "Limit the public API server endpoint to ../allowlist/trusted-egress-ipv4.txt plus api_server_extra_sources (ADR 0009). false = reachable from anywhere, Entra ID still required."
  type        = bool
  default     = true
}

variable "api_server_include_cluster_egress" {
  description = "Also authorise the cluster's own outbound IP(s), read from its load balancer, so in-cluster controllers keep reaching the API server. Set false for the very first apply (the load balancer does not exist yet; AKS adds the IP itself at creation)."
  type        = bool
  default     = true
}

variable "api_server_extra_sources" {
  description = "Extra CIDRs allowed to reach the API server, e.g. a home IP as x.x.x.x/32. Max 200 in total."
  type        = list(string)
  default     = []
}

variable "admin_group_object_ids" {
  description = "Entra ID groups that get cluster-admin. Empty is fine for a POC; the deployer is granted admin anyway."
  type        = list(string)
  default     = []
}

variable "public_ip_names" {
  description = "Short names of the static public IPs created by 10-network (pip-<prefix>-<name>) that LoadBalancer Services may use. Looked up by name (ADR 0002)."
  type        = list(string)
  default     = ["ingress"]
}

variable "workload_identity_enabled" {
  description = "Entra Workload ID webhook on the cluster. Off until something needs it; costs 200m CPU requests on the single node (ADR 0004)."
  type        = bool
  default     = false
}

variable "azure_monitor_metrics_enabled" {
  description = "Run the Azure Monitor metrics add-on (ama-metrics) on the cluster. Pair with live/azure/poc/40-observability, which creates the workspace it sends to (ADR 0008)."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
