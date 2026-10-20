variable "subscription_id" {
  description = "Azure subscription ID. Leave null to use ARM_SUBSCRIPTION_ID / az CLI default."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Must match 10-network / 20-cluster."
  type        = string
  default     = "cloudinfra-poc"
}

variable "gitops_repo_url" {
  description = "Git URL of this repository as Argo CD should clone it, e.g. https://github.com/<org>/cloud-infra.git"
  type        = string
}

variable "gitops_revision" {
  type    = string
  default = "main"
}

variable "argocd_chart_version" {
  type    = string
  default = "10.10.5"
}
