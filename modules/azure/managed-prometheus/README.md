# modules/azure/managed-prometheus

Azure Monitor managed service for Prometheus for one AKS cluster: an Azure Monitor
workspace, the data collection endpoint + rule that accept Prometheus samples, the
association that points the cluster at it, and the default recording rule groups the
community Kubernetes dashboards expect. No Grafana instance: dashboards are the free
**Azure Monitor > Dashboards with Grafana** experience in the portal (ADR 0008).

The scraping agent is the AKS metrics add-on. Enable it on the cluster with
`azure_monitor_metrics_enabled = true` in `modules/azure/aks`; this module only provides the
destination. Both halves are needed before data flows.

| Resource | Name |
|---|---|
| Azure Monitor workspace | `amw-<name>` |
| Data collection endpoint | `dce-<name>-prom` |
| Data collection rule | `dcr-<name>-prom` |
| Rule groups | `NodeRecordingRulesRuleGroup-<cluster>`, `KubernetesRecordingRulesRuleGroup-<cluster>`, `UXRecordingRulesRuleGroup-<cluster>` |

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | – | Base name, e.g. `cloudinfra-poc` |
| `location` | string | – | Region shared by all resources |
| `resource_group_name` | string | – | Resource group |
| `cluster_id` | string | – | AKS cluster resource ID |
| `cluster_name` | string | – | AKS cluster name (rule group scope) |
| `recording_rules_enabled` | bool | `true` | Create the default recording rule groups |
| `public_network_access_enabled` | bool | `true` | Public ingestion/query endpoints |
| `tags` | map(string) | `{}` | Tags |

## Outputs

`workspace_id`, `workspace_name`, `query_endpoint`, `data_collection_rule_id`

## Cost note

The workspace, endpoints, rule groups and 18 months of retention are free. You pay for
samples ingested (list $0.16 per 10 M, $0.11 in Sweden Central at the time of writing) and
queries ($0.10 per 1 G samples processed). With the default *minimal ingestion profile* a
one-node cluster produces roughly 3–5k series, i.e. a few hundred million samples a month
when running 24/7: about $2–6/month, and proportionally less with the nightly auto-stop.
Turning the minimal ingestion profile off multiplies that volume several times; keep it on.

`rules.tf` is copied from Microsoft's reference template
(`Azure/prometheus-collector`, `AddonTerraformTemplate/main.tf`, Linux groups only). Re-sync
rather than hand-edit.
