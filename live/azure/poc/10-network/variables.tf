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

variable "ingress_allowed_ports" {
  description = "TCP ports open on the ingress load balancer. [] closes public ingress entirely."
  type        = list(number)
  default     = [80, 443]
}

variable "ingress_allowlist_files" {
  description = "Files (relative to this stack) whose CIDRs may reach the ingress ports. Default: every prefix registered to Norway plus the operators' Zscaler Oslo egress (ADR 0009). Set to [] together with ingress_extra_sources = [] to allow the whole Internet again."
  type        = list(string)
  default     = ["../allowlist/no-ipv4.txt", "../allowlist/trusted-egress-ipv4.txt"]
}

variable "ingress_allow_internet" {
  description = "Explicitly open the ingress ports to the whole Internet, ignoring the allowlists. The allowlists being empty does NOT reopen the ports; this flag is the only way."
  type        = bool
  default     = false
}

variable "ingress_extra_sources" {
  description = "Extra CIDRs allowed in addition to the files, e.g. a home IP as x.x.x.x/32."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
