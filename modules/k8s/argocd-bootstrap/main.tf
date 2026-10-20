# Installs Argo CD and, in the same Helm release, the root "app-of-apps" Application.
#
# Why extraObjects instead of kubernetes_manifest: the Application CRD is created by
# this very release, so a separate kubernetes_manifest resource cannot be planned
# before the first apply. Shipping the root Application through the chart's
# `extraObjects` value sidesteps that and keeps this module down to one provider.
#
# This module is cloud-agnostic: it only needs a working Kubernetes connection
# configured on the helm provider by the calling stack.

locals {
  root_application = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "root"
      namespace  = var.namespace
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_revision
        path           = var.gitops_path
        helm = {
          parameters = [
            { name = "repoURL", value = var.gitops_repo_url },
            { name = "targetRevision", value = var.gitops_revision },
          ]
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }

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
    extraObjects = var.create_root_app ? [local.root_application] : []
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
