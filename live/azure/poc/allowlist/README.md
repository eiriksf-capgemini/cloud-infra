# live/azure/poc/allowlist

Source-IP allowlists shared by the stacks in this environment (ADR 0009).

| File | Content | Used by |
|---|---|---|
| `no-ipv4.txt` | every IPv4 prefix registered to Norway (RIPE/NRO delegated stats, collapsed) | `10-network` NSG ingress rule |
| `trusted-egress-ipv4.txt` | operator egress ranges (Zscaler Oslo); hand-maintained | `10-network`, `20-cluster` API server, `00-tfstate` storage firewall |

Refresh the country list with `make allowlist-refresh COUNTRY=NO` and commit the diff.
Lines starting with `#` and blank lines are ignored by the stacks.

Registration country is not geolocation. Cloud and proxy egress (Zscaler, Azure, AWS) is
usually registered to the company's home country, so people physically in Norway can still
be outside the country list; that is what the trusted-egress file is for.
