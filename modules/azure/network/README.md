# modules/azure/network

Resource group, VNet, AKS node subnet and an NSG that allows public ingress ports (80/443 by default) and nothing else inbound from the Internet.

Naming convention (other stacks look resources up by these names):

| Resource | Name |
|---|---|
| Resource group | `rg-<name_prefix>` |
| VNet | `vnet-<name_prefix>` |
| AKS subnet | `snet-aks` |
| NSG | `nsg-<name_prefix>-aks` |

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name_prefix` | string | – | Prefix for all names |
| `location` | string | – | Azure region |
| `address_space` | list(string) | `["10.10.0.0/16"]` | VNet CIDRs |
| `aks_subnet_cidr` | string | `"10.10.0.0/22"` | AKS node subnet |
| `ingress_allowed_ports` | list(number) | `[80, 443]` | TCP ports allowed in from `ingress_source` |
| `ingress_source` | string | `"Internet"` | service tag or CIDR |
| `tags` | map(string) | `{}` | Tags |

## Outputs

`resource_group_name`, `location`, `vnet_id`, `vnet_name`, `aks_subnet_id`, `aks_subnet_name`
