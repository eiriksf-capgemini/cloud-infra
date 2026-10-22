variable "subscription_id" {
  description = "Azure subscription ID. Leave null to use ARM_SUBSCRIPTION_ID / az CLI default."
  type        = string
  default     = null
}

variable "name_prefix" {
  type    = string
  default = "cloudinfra-poc"
}

variable "key_vault_name" {
  description = "Globally unique vault name; External Secrets' vaultUrl in gitops/platform/platform-secrets must match."
  type        = string
  default     = "kv-cloudinfra-poc"
}

variable "allowlist_files" {
  description = "Files (relative to this stack) whose CIDRs may reach the vault: the operators' egress (ADR 0009). The cluster's egress IP is added automatically."
  type        = list(string)
  default     = ["../allowlist/trusted-egress-ipv4.txt"]
}

variable "extra_sources" {
  description = "Extra CIDRs/IPs allowed through the vault firewall, e.g. a home IP."
  type        = list(string)
  default     = []
}

variable "admin_password_length" {
  description = "Length of the generated platform admin password."
  type        = number
  default     = 24
}

variable "tags" {
  type    = map(string)
  default = {}
}
