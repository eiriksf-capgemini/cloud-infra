module "argocd" {
  source = "../../../../modules/k8s/argocd-bootstrap"

  gitops_repo_url = var.gitops_repo_url
  gitops_revision = var.gitops_revision
  gitops_path     = "gitops/clusters/azure-poc"
  chart_version   = var.argocd_chart_version
}
