# modules/azure/acr

Azure Container Registry with Entra ID authentication only (admin user disabled) and
`AcrPull` / `AcrPush` role assignments for the identities that need them.

The registry name is a **global** DNS label (`<name>.azurecr.io`), so it is derived from
the organization rather than from `name_prefix` (ADR 0006). One registry serves every
environment; environments differ by image tag, pinned in the GitOps overlays.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | – | 5-50 lowercase alphanumerics, globally unique |
| `location` | string | – | Azure region |
| `resource_group_name` | string | – | Resource group |
| `sku` | string | `"Basic"` | `Basic`, `Standard` or `Premium` |
| `admin_enabled` | bool | `false` | Shared admin user; keep off |
| `pull_principal_ids` | map(string) | `{}` | label → object ID granted `AcrPull` |
| `push_principal_ids` | map(string) | `{}` | label → object ID granted `AcrPush` |
| `tags` | map(string) | `{}` | Tags |

Role assignments need the deployer to hold Owner or User Access Administrator on the
registry's resource group.

## Outputs

`id`, `name`, `login_server`

## Cost note

Basic is a flat ~$0.167/day (~$5/month) including 10 GB of storage; extra storage is
~$0.003/GB/day. There is no stop/start for a registry, so this is a standing cost.
Standard is ~$20/month, Premium ~$50/month; neither is needed until you want private
endpoints, geo-replication or retention policies.
