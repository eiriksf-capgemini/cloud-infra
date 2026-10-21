# ADR 0008: Azure Monitor managed Prometheus with the free portal Grafana dashboards

Date: 2026-10-20
Status: Accepted

## Context

The POC needs cluster and application metrics. The cluster is one small burstable node
that also runs Argo CD, ingress-nginx, cert-manager, Tekton and the AKS system pods. When
this was decided it was a `Standard_B2ls_v2` (4 GB, 2.85 GiB allocatable, ~1.6 GiB already
requested); it has since been resized to `Standard_B2as_v2` (8 GB, ADR 0004) because the
platform set alone did not fit. It is stopped outside working hours (ADR 0004). Spend must
stay close to zero.

Options compared on 2026-10-20 (Sweden Central retail prices, cluster on ~11 h/weekday):

| Option | ~USD/month | Notes |
|---|---|---|
| kube-prometheus-stack on the 4 GB node | 2.4 (PV) | ~1 GiB RSS on a node with a few hundred MiB left; evictions likely; no dashboards while stopped |
| kube-prometheus-stack on an 8 GB node (`B2as_v2`) | 14–28 | Stable, portable, full Grafana; at decision time this meant doubling the node price (the node was later resized for other reasons) |
| **Managed Prometheus + Azure Monitor dashboards with Grafana** | **2–6** | Ingestion only; Grafana UI in the portal is free (preview); no Grafana alerting/plugins |
| Managed Prometheus + Azure Managed Grafana Standard | 40–70 | $0.043/h per Standard unit (X1 = 2 units) + $6/active user; Essential tier is deprecated |
| Grafana Cloud Free + Alloy remote_write | 0 | 10k series / 14 days / 3 users; data leaves Azure; another vendor account |

## Decision

1. **Azure Monitor managed service for Prometheus** is the metrics store.
   `modules/azure/managed-prometheus` creates the Azure Monitor workspace, a Linux data
   collection endpoint and rule for the `Microsoft-PrometheusMetrics` stream, and the
   association to the cluster. `live/azure/poc/40-observability` wires it up by looking
   the cluster up by name.
2. **The scraper is the AKS metrics add-on** (`ama-metrics`), enabled through the AKS module
   (`azure_monitor_metrics_enabled`, default `true` in `20-cluster`). It keeps the default
   *minimal ingestion profile*, which collects only the metrics the standard dashboards and
   rules use. **Measured footprint (2026-10-21): 1350 MiB of memory and 426m of CPU
   requests**, not the 300–500 MiB first estimated: two collector replicas at 530 MiB /
   170m each (an add-on managed HPA pins the minimum to 2), a node DaemonSet pod at
   180 MiB / 70m, kube-state-metrics (50 MiB / 5m) and the targets operator (60 MiB /
   11m), all but the last at `system-node-critical` priority. Actual use is ~50m. That is comparable to
   a self-hosted stack; what is saved is the storage, Grafana and upkeep, not node memory.
3. **Default recording rules are managed in code.** Portal and CLI onboarding create them
   silently; OpenTofu must create them or the community dashboards show nothing. The three
   Linux rule groups are copied verbatim from Microsoft's reference template
   (`Azure/prometheus-collector`, `AddonTerraformTemplate/main.tf`). Windows groups are
   omitted.
4. **No Grafana instance.** Dashboards are **Azure Monitor > Dashboards with Grafana**, free,
   zero configuration, Entra ID auth. Azure Managed Grafana is deliberately not created: it
   would cost more than the whole cluster. Alerting, when needed, is Prometheus rule groups
   in Azure Monitor (same resource type as the recording rules) with action groups, not
   Grafana alerts.
5. **Application metrics via pod annotations.** The `ama-metrics-settings-configmap` in
   `gitops/platform/azure-monitor-metrics/` turns on `prometheus.io/scrape` annotation
   scraping for the workload namespaces only, so platform noise stays out of the bill.

## Alternatives considered

- **kube-prometheus-stack via Argo CD**: the cloud-agnostic choice (ADR 0002) and the one
  to revisit when a second cluster or a bigger node exists. Rejected now because it needs
  the node upgrade to be stable and is unavailable exactly when the cluster is stopped.
- **Grafana Cloud Free**: free and portable, with real Grafana alerting. Rejected for now to
  keep the POC single-vendor and the data inside the subscription; it remains the fallback
  if the portal Grafana preview proves too limited.
- **Azure Managed Grafana**: only if Grafana-native alerting, reports or non-Azure data
  sources become a requirement. The 30-day free instance can be used to evaluate.
- **Container insights (logs)**: not enabled; Log Analytics ingestion is the expensive part
  of Azure Monitor and logs are out of scope here.

## Consequences

- Metrics cost scales with samples: keep the minimal ingestion profile on, be careful with
  high-cardinality app metrics, and check **Cost analysis > Azure Monitor** monthly.
- Nothing to upgrade or back up; 18 months retention for free.
- Two stacks must agree: `20-cluster` (add-on) and `40-observability` (destination). With
  the add-on on and no destination, the agent pods run but ship nothing. Apply order on a
  fresh environment is `20-cluster` → `40-observability` (the association needs the cluster
  ID); the agent idles in between. Turning the add-on off in `20-cluster` leaves the
  workspace and rules in place at no cost; destroy `40-observability` to remove them.
- If the cluster is recreated, its resource ID changes and the association is orphaned:
  `make apply STACK=live/azure/poc/40-observability` replaces it (the cluster is looked up
  by name). Until then, metrics silently stop.
- The add-on's `system-node-critical` requests (1350 MiB, 426m) **preempt** ordinary
  workloads when the node is full. On a 2-vCPU node CPU requests, not memory, are what
  runs out (ADR 0004, runbook item 4); the POC trims its own requests to make room. On the 4 GB node (2026-10-20) it evicted cert-manager, ingress-nginx,
  Tekton and the demo app; the add-on was switched off in-place
  (`azure_monitor_metrics_enabled = false`, no node rotation) and the node resized to 8 GB.
  Before enabling it on a new or smaller node, confirm the free requests with
  `kubectl describe node` (memory and CPU both). If pods start pending, the fallback order
  is: turn the add-on off, then drop Tekton, then a larger node.
- Azure-only. The GitOps layer carries one Azure-specific ConfigMap under `gitops/platform`,
  flagged as such in the cluster chart values.
- The portal Grafana is preview and lacks alerts, reports, library panels and app plugins.
