# ADR 0007: Namespace layout, the `platform` namespace, and Tekton via the operator

Date: 2026-10-20
Status: Accepted

## Context

Workloads are grouped by namespace (ADR 0005). The team wants: namespaces declared in Git
and never auto-created; a `platform` namespace for developer-facing tooling (Argo CD,
Tekton, dashboards); three team namespaces that start empty; and a path towards a fully
hosted build system on Tekton.

## Decisions

1. **No implicit namespaces for workloads.** The workloads ApplicationSet no longer sets
   `CreateNamespace=true`. Every `gitops/apps/<namespace>/` folder must contain a
   `namespace` app declaring the `Namespace` (with Pod Security Admission labels), a
   `LimitRange`, and a per-environment `ResourceQuota`. Apps in a new namespace fail their
   first sync until the namespace app has synced, then succeed on retry (limit 10).
   Third-party platform services installed from upstream charts/YAML (ingress-nginx,
   cert-manager, tekton-operator) keep their upstream namespaces and may still create them.
2. **`platform` namespace** hosts Argo CD (moved from `argocd`) and Tekton. Its quota is
   deliberately generous so GitOps can never be blocked by its own quota.
3. **Team namespaces** `sogeti`, `invent`, `i-and-d` exist with only a `namespace` app.
   Kubernetes requires lowercase DNS labels, so "I & D" is spelled `i-and-d`.
4. **`infra` namespace for cluster plumbing** (ingress-nginx, cert-manager, external-dns) is
   endorsed but not done yet: moving ingress-nginx recreates its LoadBalancer and changes
   the public IP used by the nip.io dev hosts. Do it in a dedicated change, ideally with a
   static public IP first.
5. **Tekton through the Tekton Operator.** Upstream Tekton release YAML hardcodes the
   `tekton-pipelines` namespace; the operator's `TektonConfig.spec.targetNamespace` is the
   supported way to install into `platform`. The operator itself is a cluster-level
   platform app (`gitops/platform/tekton-operator`, pinned release, own `tekton-operator`
   namespace). `TektonConfig` lives in `gitops/apps/platform/tekton/` with profile `all`
   (Pipelines + Triggers + read-only Dashboard; Chains and Results explicitly disabled,
   since the operator installs them under any profile unless told not to). A standalone
   `TektonDashboard` object does not survive: the operator deletes it when the profile is
   not `all`, so the Dashboard is configured through `TektonConfig.spec.dashboard`.
6. **Dashboard is read-only and unauthenticated** on a dev-only nip.io host. Before a
   writable dashboard or any non-dev exposure, put an authenticating proxy (oauth2-proxy
   with Entra ID) in front.

## Consequences

- Argo CD UI/CLI now use namespace `platform` (`kubectl -n platform port-forward svc/argocd-server 8080:443`).
- Enabling Chains or Results is a one-line change in
  `gitops/apps/platform/tekton/base/tektonconfig.yaml`; Results brings its own Postgres.
- Next steps for hosted builds: Triggers + a GitHub webhook interceptor, a `Pipeline` per
  repo type under `gitops/apps/platform/tekton-pipelines/`, image pushes to a registry
  (ACR) using workload identity, and Argo CD Image Updater or a Git-write step to promote.
