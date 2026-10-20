variable "subscription_id" {
  description = "Azure subscription ID. Leave null to use ARM_SUBSCRIPTION_ID / az CLI default."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for the state storage."
  type        = string
  default     = "norwayeast"
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
