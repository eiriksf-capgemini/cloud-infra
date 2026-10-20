# ADR 0005: Workload app-of-apps with dev / test / prod environments

Date: 2026-10-20
Status: Accepted

## Context

Platform services (ingress, cert-manager) are already managed by the per-cluster app-of-apps
chart. Application workloads need the same GitOps treatment, must support three environments
(dev, test, prod), and adding an application should not require editing a central list.
Today there is one cluster and it is **dev**.

## Decision

1. **Environment is a property of the cluster.** `gitops/clusters/<cluster>/values.yaml`
   declares `environment: dev|test|prod`. The current cluster chart is renamed
   `gitops/clusters/azure-dev`. Test and prod will be separate clusters
   (`azure-test`, `azure-prod`, or another cloud) with their own chart directories; the
   OpenTofu stacks are reusable as-is with a different `name_prefix`.
2. **Namespace folder, then application folder, then environments.**
   `gitops/apps/<namespace>/<app>/` holds a kustomize `base/` and `overlays/{dev,test,prod}/`.
   Environment differences (replicas, config, hosts, image pins) live only in overlays.
   Namespace-level configuration (the `Namespace` object with PSA labels, `LimitRange`,
   per-environment `ResourceQuota`) is itself an app named `namespace` inside the folder.
3. **Discovery by ApplicationSet.** Each cluster chart renders one `ApplicationSet`
   (`workloads-<env>`) with a Git directory generator matching
   `gitops/apps/*/*/overlays/<env>`. Each match becomes an `Application` named
   `<namespace>-<app>`, deployed to that namespace, auto-synced with prune and self-heal.
   Removing an overlay directory removes the app from that environment.
4. **Platform first, workloads later.** The ApplicationSet carries sync-wave 30; platform
   apps are wave 10, so ingress-nginx exists before workload Ingresses are applied.

## Alternatives considered

- **Branch per environment**: rejected; merges between environment branches drift and are
  hard to review. Directory-per-environment keeps one history.
- **One cluster hosting all environments in namespaces**: possible later with the same
  layout (several ApplicationSets on one cluster, names suffixed with the environment), but
  for now each environment is a cluster, which is also what the quota allows.
- **Helm chart per app** instead of kustomize: fine for third-party software (that is what
  `gitops/platform` does); kustomize keeps first-party manifests plain and diff-friendly.

## Consequences

- `gitops/apps/README.md` is the how-to for developers.
- `demo/podinfo` is the reference app; its dev overlay exposes a nip.io host on the ingress
  IP. `demo/namespace` is the reference namespace configuration.
- Argo CD `AppProject`s (platform vs workloads, with namespace and repo allow-lists) are the
  natural next hardening step once more than one team commits to the repo.
