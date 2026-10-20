variable "subscription_id" {
  description = "Azure subscription ID. Leave null to use ARM_SUBSCRIPTION_ID / az CLI default."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region. swedencentral: nearest EU region where this Free Trial can use cheap B-series sizes."
  type        = string
  default     = "swedencentral"
}

variable "name_prefix" {
  description = "Prefix shared with the other poc stacks."
  type        = string
  default     = "cloudinfra-poc"
}

variable "tags" {
  description = "Extra tags merged over the defaults."
  type        = map(string)
  default     = {}
}

variable "monthly_budget_amount" {
  description = "Monthly budget in the subscription's billing currency. Alerts at 80% actual and 100% forecast."
  type        = number
  default     = 500
}

variable "budget_contact_emails" {
  description = "Extra e-mail recipients for budget alerts. Subscription Owners are always notified."
  type        = list(string)
  default     = []
}

variable "storage_restricted" {
  description = "Limit the state storage account to ../allowlist/trusted-egress-ipv4.txt plus storage_extra_sources (ADR 0009). false = reachable from anywhere, Entra ID still required."
  type        = bool
  default     = true
}

variable "storage_extra_sources" {
  description = "Extra public IPs or CIDRs allowed to reach the state storage account. /32 may be given for consistency with 20-cluster; it is stripped because Azure wants bare IPs."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.storage_extra_sources : can(cidrhost(strcontains(s, "/") ? s : "${s}/32", 0))])
    error_message = "storage_extra_sources entries must be IPv4 addresses or CIDRs."
  }
}
