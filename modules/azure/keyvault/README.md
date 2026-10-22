# modules/azure/keyvault

Azure Key Vault (RBAC, firewall default-deny, soft delete 7 days, no purge protection) plus
optional generated secrets. Used by `live/azure/poc/35-secrets` as the source of the platform
admin password that External Secrets distributes to Argo CD and ThunderID (ADR 0011).

| Input | Type | Default | |
|---|---|---|---|
| `name` | string | – | 3-24 chars, globally unique |
| `allowed_ip_rules` | list(string) | `[]` | firewall allowlist (operators, cluster egress) |
| `reader_principal_ids` / `officer_principal_ids` | map(string) | `{}` | Secrets User / Secrets Officer grants |
| `generated_secrets` | map(number) | `{}` | name => password length |

Outputs: `id`, `name`, `vault_uri`, `secret_names`.
