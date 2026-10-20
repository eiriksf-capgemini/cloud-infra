variable "subscription_id" {
  description = "Azure subscription ID. Leave null to use ARM_SUBSCRIPTION_ID / az CLI default."
  type        = string
  default     = null
}

variable "location" {
  type    = string
  default = "norwayeast"
}

variable "name_prefix" {
  type    = string
  default = "cloudinfra-poc"
}

variable "address_space" {
  type    = list(string)
  default = ["10.10.0.0/16"]
}

variable "aks_subnet_cidr" {
  type    = string
  default = "10.10.0.0/22"
}

variable "tags" {
  type    = map(string)
  default = {}
}
