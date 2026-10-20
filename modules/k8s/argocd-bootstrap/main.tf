# Installs Argo CD, then the root "app-of-apps" Application as a second, tiny Helm
# release from a chart embedded in this module (charts/root-app).
#
# Why two releases: the Application CRD is created by the Argo CD release. Helm cannot
# build (REST-map) an object of a kind the API server does not know yet, so shipping the
# Application inside the same release fails on first install, and kubernetes_manifest
# cannot even plan it. A dependent release sidesteps both, and keeps this module down to
# the helm provider only.
#
# This module is cloud-agnostic: it only needs a working Kubernetes connection
# configured on the helm provider by the calling stack.

locals {
  default_values = {
    # Keep the footprint small for a one-node POC.
    dex           = { enabled = false }
    notifications = { enabled = false }
    redis-ha      = { enabled = false }
    server = {
      service = { type = "ClusterIP" }
    }
    configs = {
      params = {
        # TLS is terminated by the ingress later; until then use `kubectl port-forward`.
        "server.insecure" = false
      }
    }
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true

  wait    = true
  timeout = 600

  values = [
    yamlencode(local.default_values),
    yamlencode(var.values),
  ]
}

resource "helm_release" "root_app" {
  count = var.create_root_app ? 1 : 0

  name      = "argocd-root-app"
  chart     = "${path.module}/charts/root-app"
  namespace = var.namespace

  values = [yamlencode({
    name              = "root"
    project           = "default"
    repoURL           = var.gitops_repo_url
    targetRevision    = var.gitops_revision
    path              = var.gitops_path
    destinationServer = "https://kubernetes.default.svc"
  })]

  depends_on = [helm_release.argocd]
}
