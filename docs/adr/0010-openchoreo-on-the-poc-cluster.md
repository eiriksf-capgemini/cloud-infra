# ADR 0010: OpenChoreo on the POC cluster, behind one IP, on a 4-vCPU node

Date: 2026-10-21
Status: Accepted

## Context

The POC should run [OpenChoreo](https://openchoreo.dev) (CNCF Sandbox internal developer
platform, v1.3.1) so teams can try its project/component/environment model on top of the
existing cluster. OpenChoreo is not one chart: the documented single-cluster install is a
control plane (API, controller, Backstage portal, cluster-gateway, event-forwarder), a data
plane (cluster-agent plus a Gateway), the ThunderID identity provider, and prerequisites it
does not ship itself: Gateway API CRDs 1.5.1, cert-manager, External Secrets Operator 2.0.1,
kgateway 2.3.1 and OpenBao 0.25.6. Optional workflow (Argo Workflows) and observability
(OpenSearch) planes exist too.

Measured requests of the minimal install, rendered from the charts with this repo's values:

| Component | CPU | Memory | Notes |
|---|---|---|---|
| openchoreo-control-plane 1.3.1 | 750m | 896Mi | 5 deployments; hostnames hard-coded to `openchoreo-*` namespaces (302 references) |
| openchoreo-data-plane 1.3.1 | 50m | 128Mi | cluster-agent; the Gateway proxy is sized by GatewayParameters (50m) |
| thunderid 1.0.1 | 50m | 128Mi | SQLite on three small PVCs |
| kgateway, External Secrets, OpenBao (upstream sets none) | ~190m | ~450Mi | values here set them |
| KEDA 2.21 + HTTP add-on 0.16, trimmed from 1550m | ~200m | ~360Mi | scale-to-zero, see below |

Before this change the single `Standard_B2s_v2` node (1900m allocatable) already had 1736m
requested (ADR 0004, runbook item 4). Two more constraints shaped the design:

- **Free Trial quota: 4 vCPU per region and 3 public IPs per region.** The cluster's egress
  IP and the ingress IP take two of the three. Every in-place path to a 4-vCPU node needs
  more than 4 vCPU for a moment (the azurerm provider rotates through a temporary pool).
- OpenChoreo's charts create one Gateway each for the control and data planes, i.e. two
  more LoadBalancer Services by default.

## Decision

1. **Scope: control plane + data plane + ThunderID, in one cluster.** No workflow plane (Argo
   Workflows would add the "8 GB / 4 CPU" the upstream quick start asks for; Tekton is the
   POC's CI) and no observability plane (ADR 0008 already gives metrics; OpenSearch is far
   too heavy for this node). Everything is GitOps: 15 Argo CD Applications in
   `gitops/clusters/azure-dev/values.yaml`, ordered by sync wave, values in
   `gitops/platform/<name>/`.
2. **Upstream namespaces, not `platform`.** The charts hard-code `openchoreo-control-plane`
   and `openchoreo-data-plane`; Thunder, OpenBao, External Secrets and KEDA get their own
   namespaces as in the reference install. ADR 0007's `platform` namespace keeps Argo CD and
   Tekton only.
3. **One public IP, made static.** `10-network` creates `pip-cloudinfra-poc-ingress`
   (Standard, static); ingress-nginx is pinned to it with the `azure-pip-name` annotation and
   the cluster identity gets Network Contributor on the IP. Both OpenChoreo Gateways are
   `ClusterIP` (kgateway `GatewayParameters`, `gitops/platform/openchoreo-gateway-params`)
   and ingress-nginx routes `api.`, `console.`, `thunder.openchoreo.<ip>.nip.io` and
   `*.openchoreoapis.<ip>.nip.io` to them (`gitops/platform/openchoreo-ingress`). Plain
   HTTP, like the rest of the POC (ADR 0009: no TLS, no DNS zone yet), reachable only from the
   ADR 0009 allowlists. Hostnames therefore survive a cluster recreate.
4. **Node: one `Standard_B4s_v2` (4 vCPU / 16 GB), reached by recreating the cluster.**
   The 8 GB `B4ls_v2` would not hold the memory (current 4.5 GiB + ~2 GiB). A second
   `B2s_v2` pool was rejected: AKS daemonsets cost ~555m per node, leaving ~110m headroom. A
   Spot pool was rejected: evictable and tainted, OpenChoreo's charts do not tolerate it.
   The recreate is codified in `docs/runbooks/recreate-cluster.md`.
5. **Secrets and identity exactly as the reference install, flagged as development-grade.**
   OpenBao runs in dev mode (in-memory, root token `root`, placeholder secrets seeded by a
   postStart hook); External Secrets reads it through `ClusterSecretStore/default`; Thunder
   ships the reference users (`admin@openchoreo.dev` / `Admin@123` and friends). Fine for a
   POC behind the allowlists, not for anything real.
6. **Two things the install script does by hand are Kubernetes objects here.** The
   cluster-gateway CA copy is an Argo CD Sync hook Job (`openchoreo-gateway-ca`) and the
   `ClusterDataPlane` registration uses the CRD's `clientCA.secretKeyRef` instead of pasting
   the certificate (`openchoreo-config`). No secret material lives in Git.
7. **Scale to zero with KEDA + HTTP add-on, applied where it saves something.** The
   interceptor fronts HTTP workloads that may sit at zero replicas; `demo/podinfo` is the
   reference (`HTTPScaledObject`, ingress backend = interceptor). Pattern documented in
   `gitops/apps/README.md`. Platform controllers (Argo CD, Tekton, OpenChoreo, KEDA itself)
   cannot scale to zero without stopping reconciliation; the nightly cluster stop (ADR 0004)
   remains the real saver. OpenChoreo 1.3.1 has no scale-to-zero of its own.

## Alternatives considered

- **Separate public IPs for the OpenChoreo gateways**: impossible on the Free Trial (3 per
  region), and they would have bypassed the single allowlisted entry point.
- **Knative for scale to zero**: heavier control plane than what it saves on this node.
- **Workflow / observability planes now**: revisit when a bigger quota or a second cluster
  exists; the Applications are additive.
- **Keeping the 2-vCPU node and trimming further**: everything already idles at a few
  millicores; the add-on budget does not fit without disabling platform services.

## Consequences

- **Cost** at ~11 h × 22 d: node $21 → ~$42/month (`B4s_v2` $0.173/h); the static IP ~$3.65
  (replaces the dynamic one, so ~neutral); three Thunder PVCs < $1. Nothing else bills.
- **Quota is saturated**: 4 of 4 vCPU and 2 of 3 public IPs in use. A Kubernetes upgrade
  needs a surge node the quota does not allow; use `az aks nodepool update --max-surge 0
  --max-unavailable 1` out of band (the azurerm 5.x provider has no `max_unavailable`), or
  recreate the cluster. Scaling out is not possible without leaving the Free Trial.
- **`make apply STACK=live/azure/poc/20-cluster` from a 2-vCPU cluster will fail**: the
  provider tries a temporary 4-vCPU pool next to the 2-vCPU one. Follow the runbook.
- **The cluster recreate changes** the AKS egress IP (ADR 0009 allowlists pick it up via data
  lookups), the kubelet identity (`25-registry` re-grants AcrPull) and the DCR association
  (`40-observability` replaces it). The ingress IP and every nip.io hostname stay.
- **Node budget after everything** (requests): ~3.0 of 3.8 allocatable cores, ~7 of 14.5 GiB.
  Memory is now the more likely limit. Measure with `kubectl describe node`.
- **Login and secrets are development defaults.** Change Thunder's users and move OpenBao
  out of dev mode before the portal is shown to anyone outside the POC.
- **Two upstream charts needed workarounds on first sync (2026-10-21):** kgateway's CRDs
  (v2.3.1 through v2.4.1) are rejected by Kubernetes 1.36's CEL cost budget, so they are
  vendored with length/item bounds added (`scripts/kgateway-crds-patch.py`, re-run on bumps);
  ThunderID creates its PVCs as Helm pre-install hooks, which deadlocks Argo CD on AKS's
  WaitForFirstConsumer disk classes, so it uses `managed-csi-immediate`
  (`gitops/platform/storage-classes`). Node disk pressure during the initial image pull was
  transient (cleared in 5 minutes). The CA copy is a CronJob, not a Sync hook: Argo CD does
  not assess child-Application health by default, so the root app's waves did not order the
  OpenChoreo Applications and the hook ran before the control plane existed. Health
  assessment is now enabled in the bootstrap module (`30-gitops`), and workload Deployments
  ignore `/spec/replicas` so self-heal does not undo KEDA.
- **Pod Security**: OpenChoreo's namespaces carry no PSA labels (unlike ADR 0007 namespaces);
  kgateway's proxies and OpenBao need `baseline`. Revisit when the charts document it.
