# ADR 0008: Azure Monitor managed Prometheus with the free portal Grafana dashboards

Date: 2026-10-20
Status: Accepted

## Context

The POC needs cluster and application metrics. The cluster is one `Standard_B2ls_v2` node
with 2.85 GiB allocatable memory, of which ~1.6 GiB is already requested by Argo CD,
ingress-nginx, cert-manager, Tekton and the AKS system pods. It is stopped every night
(ADR 0004). Spend must stay close to zero.

Options compared on 2026-10-20 (Sweden Central retail prices, cluster on ~11 h/weekday):

| Option | ~USD/month | Notes |
|---|---|---|
| kube-prometheus-stack on the current node | 2.4 (PV) | ~1 GiB RSS on a node with a few hundred MiB left; evictions likely; no dashboards while stopped |
| kube-prometheus-stack + 8 GB node (`B2as_v2`) | 14–28 | Stable, portable, full Grafana; doubles the node price |
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
   rules use. The add-on costs roughly 300–500 MiB of node memory, about half of a
   self-hosted stack.
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
  the add-on on and no destination, the agent pods run but ship nothing.
- Azure-only. The GitOps layer carries one Azure-specific ConfigMap under `gitops/platform`,
  flagged as such in the cluster chart values.
- The portal Grafana is preview and lacks alerts, reports, library panels and app plugins.
