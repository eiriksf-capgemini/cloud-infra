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
