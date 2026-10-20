module "argocd" {
  source = "../../../../modules/k8s/argocd-bootstrap"

  gitops_repo_url = var.gitops_repo_url
  gitops_revision = var.gitops_revision
  gitops_path     = "gitops/clusters/azure-dev"
  # Argo CD lives in the shared `platform` namespace together with Tekton and other
  # developer-facing tooling (ADR 0007). The namespace object itself is managed by
  # gitops/apps/platform/namespace once Argo CD is up.
  namespace     = "platform"
  chart_version = var.argocd_chart_version
}
