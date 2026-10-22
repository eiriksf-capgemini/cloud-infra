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
  # Explicit resources for every component. The chart sets none, so a namespace
  # LimitRange default (256Mi in `platform`) would cap the application controller and
  # OOM-kill it mid-sync. Sized for a small dev cluster; raise with the app count.
  resources = {
    controller  = { requests = { cpu = "100m", memory = "256Mi" }, limits = { memory = "1Gi" } }
    repo_server = { requests = { cpu = "50m", memory = "128Mi" }, limits = { memory = "512Mi" } }
    server      = { requests = { cpu = "25m", memory = "64Mi" }, limits = { memory = "256Mi" } }
    appset      = { requests = { cpu = "25m", memory = "64Mi" }, limits = { memory = "256Mi" } }
    redis       = { requests = { cpu = "25m", memory = "32Mi" }, limits = { memory = "128Mi" } }
  }

  default_values = {
    # Keep the footprint small for a one-node POC.
    dex            = { enabled = false }
    notifications  = { enabled = false }
    redis-ha       = { enabled = false }
    controller     = { resources = local.resources.controller }
    repoServer     = { resources = local.resources.repo_server }
    applicationSet = { resources = local.resources.appset }
    redis          = { resources = local.resources.redis }
    server = {
      service   = { type = "ClusterIP" }
      resources = local.resources.server
    }
    configs = {
      params = {
        # TLS is terminated by the ingress later; until then use `kubectl port-forward`.
        "server.insecure" = false
      }
      cm = {
        # Argo CD stopped assessing the health of child Applications by default, which
        # means the root app's sync waves do not wait for one Application before creating
        # the next. The OpenChoreo chain (ADR 0010) depends on that ordering. Standard Lua
        # from the Argo CD docs (operator-manual/health).
        "resource.customizations.health.argoproj.io_Application" = <<-LUA
          hs = {}
          hs.status = "Progressing"
          hs.message = ""
          if obj.status ~= nil then
            if obj.status.health ~= nil then
              hs.status = obj.status.health.status
              if obj.status.health.message ~= nil then
                hs.message = obj.status.health.message
              end
            end
          end
          return hs
        LUA
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
