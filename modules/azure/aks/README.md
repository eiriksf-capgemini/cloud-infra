# modules/azure/aks

POC-sized AKS cluster: Free tier control plane, one small system node, Azure CNI Overlay,
OIDC issuer + workload identity, Entra ID auth with Azure RBAC.

Implements the **common cluster interface** from ADR 0002. The AWS and GCP modules must
expose the same `cluster_*` / `oidc_issuer_url` outputs and the same `name`,
`kubernetes_version`, `system_node_pool`, `user_node_pools`, `tags` inputs.

## Inputs (common)

| Name | Type | Default |
|---|---|---|
| `name` | string | – |
| `location` | string | – |
| `kubernetes_version` | string | `null` (region default) |
| `system_node_pool` | object | 1× `Standard_B2as_v2`, 32 GB disk |
| `user_node_pools` | map(object) | `{}` |
| `tags` | map(string) | `{}` |

## Inputs (Azure)

| Name | Type | Default |
|---|---|---|
| `resource_group_name` | string | – |
| `subnet_id` | string | – |
| `sku_tier` | string | `Free` |
| `admin_group_object_ids` | list(string) | `[]` |
| `grant_deployer_cluster_admin` | bool | `true` |
| `local_account_disabled` | bool | `false` |
| `pod_cidr` / `service_cidr` / `dns_service_ip` | string | `10.244.0.0/16` / `10.0.0.0/16` / `10.0.0.10` |

## Outputs

Common: `cluster_name`, `cluster_id`, `cluster_endpoint`, `cluster_ca_certificate` (sensitive), `oidc_issuer_url`.
Azure: `resource_group_name`, `node_resource_group`, `cluster_identity_principal_id`,
`kubelet_identity_object_id`, `kube_admin_config` (sensitive object).

## Cost note

A single `Standard_B2as_v2` node (2 vCPU / 8 GB, about $0.08/h in Sweden Central) plus a
standard load balancer is the floor for a cluster running Argo CD, Tekton, ingress-nginx and
cert-manager. The 4 GB `Standard_B2ls_v2` ran out of schedulable memory with that set. `tofu destroy` the `20-cluster` stack when not in use.
