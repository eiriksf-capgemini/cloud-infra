# Tekton on the azure-dev cluster

Status as of 2026-10-20 evening. Decisions are in ADR 0007; this page is the operational summary.

## What is deployed and where

| Piece | Lives in Git | Deployed by | Namespace |
|---|---|---|---|
| Tekton Operator v0.77.0 (upstream release YAML, pinned) | `gitops/platform/tekton-operator/kustomization.yaml` | Argo CD app `tekton-operator` (cluster chart, sync-wave 20) | `tekton-operator` |
| `TektonConfig` (Pipelines, Triggers, Dashboard; pruner) | `gitops/apps/platform/tekton/base/tektonconfig.yaml` | Argo CD app `platform-tekton` (workloads ApplicationSet) | components in `platform` |
| Dashboard dev ingress (read-only, nip.io) | `gitops/apps/platform/tekton/overlays/dev/dashboard-ingress.yaml` | same app | `platform` |

Environment overlays `test` and `prod` exist for `tekton` but contain no differences yet.

### TektonConfig summary

```yaml
profile: all              # Pipelines + Triggers + Dashboard (Kubernetes)
targetNamespace: platform
dashboard: { readonly: true }
chain:  { disabled: true } # artifact signing, off
result: { disabled: true } # run archive + Postgres, off
pruner: keep 20 PipelineRuns/TaskRuns, nightly 03:00
pipeline: enable-api-fields: beta, disable-affinity-assistant: true
```

Why these settings:

- Upstream Tekton YAML hardcodes the `tekton-pipelines` namespace; the operator's
  `targetNamespace` is the supported way to install into `platform`.
- The operator installs Chains and Results under **any** profile unless explicitly disabled.
  Results brings its own Postgres; together they cost ~6 pods / ~600m CPU requests.
- The Dashboard must come from `TektonConfig` with profile `all`: the operator deletes a
  standalone `TektonDashboard` object whenever the profile is not `all`, and its installer
  needs the Triggers aggregate ClusterRoles (so `lite` cannot host a dashboard).
- Operator 0.77.0 is the newest version published as `release.yaml`; later versions ship only
  as a Helm chart tarball on GitHub releases without a chart repository.

## Access

```sh
# Dashboard (read-only), dev only, unauthenticated:
open http://tekton.57.174.156.100.nip.io/
# Argo CD view of the Tekton apps:
kubectl -n platform port-forward svc/argocd-server 8080:443   # https://localhost:8080
# Tekton CLI (optional): brew install tektoncd-cli ; tkn pipelinerun list -n platform
```

The dashboard has no authentication of its own. Keep `readonly: true` until an
authenticating proxy (oauth2-proxy with Entra ID) sits in front of it.

## Current state and open items (2026-10-20)

1. **Live `TektonConfig` still reports `profile: basic`.** The change to `all` + read-only
   dashboard is in Git (`platform-tekton` shows OutOfSync) but its sync was stuck while the
   Argo CD application controller was crash-looping (see 3). The controller is healthy now;
   the next sync (automatic, or `argocd app sync platform-tekton`) should apply it. Expected
   result: `kubectl get tektondashboard` → Ready, dashboard URL returns 200. Verify.
2. **Pods expected in `platform`** after the sync: `tekton-pipelines-{controller,webhook,remote-resolvers}`,
   `tekton-triggers-{controller,webhook,core-interceptors}`, `tekton-events-controller`,
   `tekton-operator-proxy-webhook`, `tekton-dashboard`. No `tekton-chains-*` / `tekton-results-*`.
3. **Argo CD Helm release revision 2 is marked `failed`** (upgrade deadline exceeded) even
   though all Argo CD pods now run with the new explicit resources. Reconcile with
   `make plan apply STACK=live/azure/poc/30-gitops`; expect an in-place update, no downtime.
   Root cause of the stall: the `platform` LimitRange gave the controller a 256Mi limit and
   it was OOM-killed mid-sync (12 restarts). The bootstrap module now sets resources for
   every Argo CD component (controller limit 1Gi).
4. **Node capacity.** System node is `Standard_B2s_v2` (2 vCPU / 8 GB, 1900m allocatable).
   Measured 2026-10-21 before trimming: memory requests 44%, **CPU requests 1877m (98%)**,
   Argo CD controller (100m) and server (25m) Pending. kube-system alone took 1277m
   (metrics-server 2×151m, CoreDNS 2×100m, workload-identity webhook 2×100m, kube-proxy and
   retina 100m each); Tekton's webhook, remote-resolvers and operator proxy webhook 100m
   each; ingress-nginx 100m. Trims in Git (this repo): `TektonConfig`
   `spec.pipeline.options.deployments` sets those three to 20m, ingress-nginx to 50m, and
   `gitops/platform/aks-metrics-server` pins metrics-server to 60m per replica. Two more
   are AKS-owned objects, applied by hand on the live cluster (Argo CD does not manage
   kube-system defaults):
   ```sh
   # CoreDNS: one replica on a one-node cluster (AKS ladder default is 2)
   kubectl -n kube-system patch cm coredns-autoscaler --type merge -p '{"data":{"ladder":"{\"coresToReplicas\":[[1,1],[512,3],[1024,4],[2048,5]],\"nodesToReplicas\":[[1,1],[8,3],[16,4],[32,5]]}"}}'
   # metrics-server: pick up the ConfigMap once after its first sync
   kubectl -n kube-system rollout restart deployment metrics-server
   ```
   Measured after all five (2026-10-21 10:36): the managed Prometheus add-on requests
   **426m**, not ~300m (2 × 170m collectors, 70m node agent, 5m kube-state-metrics, 11m
   targets operator; 1350Mi memory), and it preempted the ingress controller (50m). Actual
   use is tiny everywhere (`kubectl top pods -A`: the whole node runs on ~150m), so the next
   lever is the Entra Workload ID webhook, 2 × 100m with nothing using it:
   `workload_identity_enabled = false` in `20-cluster` (default since this change). With it
   off: ~1740m requested incl. ingress, ~160m free. A second node is not an option: the regular pool uses the
   whole 4-vCPU Free Trial quota; a Spot pool has its own 3-vCPU quota but is tainted, so
   only workloads with tolerations land there.
5. **Helm/Argo gotchas recorded for next time**: `make apply` must use the saved plan
   (interactive prompts fail in the `!` shell); cluster-scoped Helm leftovers (CRDs,
   ClusterRoles) need `meta.helm.sh/release-namespace` re-pointed when a release moves
   namespace; Argo `SkipDryRunOnMissingResource=true` + retries handle CRs whose CRD arrives
   in a later sync wave.

## Towards hosted builds (next steps, in order)

1. Verify item 1 above; then run a smoke `PipelineRun` in `platform`
   (`tkn hub` / catalog `git-clone` + `kaniko` or `buildah` task).
2. Pipelines in Git: `gitops/apps/platform/tekton-pipelines/` with reusable `Pipeline`s and
   `Task`s per repo type; environment overlays for parameters.
3. Image registry: push to `acrmadbadgerbadger.azurecr.io` (ADR 0006) using workload
   identity — federated credential for the pipeline ServiceAccount against the cluster's
   OIDC issuer, `AcrPush` role on the registry.
4. Webhooks: Tekton Triggers `EventListener` + GitHub interceptor, exposed through
   ingress-nginx with TLS from cert-manager (needs a DNS zone). Until then, manual
   `PipelineRun`s or `tkn` from a laptop.
5. Promotion: a final pipeline task that updates the image tag in
   `gitops/apps/<ns>/<app>/overlays/<env>` and opens a PR; Argo CD does the rest.
6. Later: Results (build history), Chains (signing/SLSA), an authenticating proxy for the
   dashboard, and a Spot node pool for build pods (toleration + `podTemplate`).
