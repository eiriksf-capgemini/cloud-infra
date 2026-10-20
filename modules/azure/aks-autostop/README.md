# modules/azure/aks-autostop

Azure Automation account + PowerShell runbook + schedules that stop an AKS cluster every
evening and optionally start it on weekday mornings. Runs on the Automation free tier.

| Input | Default | Notes |
|---|---|---|
| `cluster_id`, `cluster_name`, `cluster_resource_group_name` | – | from `modules/azure/aks` |
| `stop_time` | `19:00` | every day |
| `start_time` | `null` | set e.g. `08:00` to auto-start; null = start by hand |
| `start_week_days` | Mon–Fri | only used when `start_time` is set |
| `timezone` | `Europe/Oslo` | IANA name |

Manual control from the repo root: `make aks-stop`, `make aks-start`, `make aks-status`.

While stopped you still pay for the load balancer rules/IP and node OS disks (a few USD a
month). For breaks longer than a few days, `tofu destroy` the `20-cluster` stack instead;
AKS does not guarantee a cluster stopped for more than 30 days can be restarted.
