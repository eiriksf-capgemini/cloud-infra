variable "namespace" {
  description = "Namespace for Argo CD."
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "argo-cd Helm chart version (https://artifacthub.io/packages/helm/argo/argo-cd)."
  type        = string
  default     = "10.10.5"
}

variable "gitops_repo_url" {
  description = "Git URL Argo CD should reconcile from, e.g. https://github.com/<org>/cloud-infra.git"
  type        = string
}

variable "gitops_revision" {
  description = "Branch, tag or commit of the GitOps repo."
  type        = string
  default     = "main"
}

variable "gitops_path" {
  description = "Path inside the repo to the cluster's app-of-apps Helm chart."
  type        = string
  default     = "gitops/clusters/azure-dev"
}

variable "create_root_app" {
  description = "Create the root (app-of-apps) Application in the same Helm release."
  type        = bool
  default     = true
}

variable "values" {
  description = "Extra argo-cd chart values merged over the module defaults (last wins)."
  type        = any
  default     = {}
}
