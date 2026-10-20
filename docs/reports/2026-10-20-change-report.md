# Change report: 2026-10-20

Everything created, changed, decided and verified in the `cloud-infra` repository and the
Azure POC on 20 October 2026, the day the environment went from an empty repository to a
running, cost-controlled, access-restricted AKS platform. Sources: the 25 commits on `main`
that day, pull requests #1 to #4, and the live subscription at 23:00 Oslo.

## 1. Summary

| | Start of day | End of day |
|---|---|---|
| Repository | empty | 25 commits on `main`, 2 merged PRs, 2 open PRs, 9 ADRs, 1 runbook |
| Azure | Free Trial subscription, nothing deployed | 14 resources in 2 resource groups (table in §4) |
| Cluster | – | AKS 1.36.4, one `Standard_B2as_v2` node, Argo CD, ingress-nginx, cert-manager, Tekton, podinfo |
| Cost controls | – | auto-stop 17:00 + 22:00 Oslo, budget alert, Free tiers everywhere |
| Access | – | ingress Norway-only, API server and state storage operator-egress-only, all logins Entra ID |
| Metrics | – | Azure Monitor managed Prometheus destination deployed; add-on off pending node capacity decision (PR #2) |

The one incident of the day: enabling the Azure Monitor metrics add-on on the 4 GB node
preempted every workload (§6). It was rolled back within minutes and led to the node resize.

## 2. Timeline of changes on `main`

Times are Oslo. Lines marked **PR** were merged through a pull request; the rest were
committed directly.

| Time | Commit | Change |
|---|---|---|
| 14:12 | `b72a13a` | Scaffold: OpenTofu modules (`azure/network`, `azure/aks`, `k8s/argocd-bootstrap`), stacks `00-tfstate` … `30-gitops`, Argo CD cluster chart, Makefile. ADR 0001–0003 |
| 14:41–14:59 | `e4bfbf6` `c54fed9` `1261cd1` `aa6bd4f` `03f4a91` | Cost controls (ADR 0004): nightly auto-stop via Azure Automation, budget alert, Spot/scale-to-zero pools. Region moved to Sweden Central and node size adjusted twice to fit Free Trial restrictions and capacity (`B2als_v2` → `B2ls_v2`) |
| 15:53–16:09 | `3f2eb74` `0642599` `41146c4` `784b0c2` `e654b96` `7d62497` | First real applies: Argo CD root Application as an embedded Helm chart, auto-stop anchored to the Oslo UTC offset, drift fixes for the Automation runbook type and cert-manager webhook mutations |
| 17:19 | `7ab6abb` | Workload app-of-apps with dev/test/prod overlays and an ApplicationSet per environment (ADR 0005) |
| 17:21–17:25 | `3ac9d46` `14e3354` | NSG opened for 80/443; destination `*` because the AKS load balancer uses floating IP |
| 17:31 | `699f23c` | Workloads grouped by namespace: `gitops/apps/<namespace>/<app>/overlays/<env>` |
| 17:43 | `4840c73` **PR #1** | Azure Container Registry module and `25-registry` stack, AcrPull to the kubelet identity (ADR 0006) |
| 17:47–17:57 | `edbfd68` `b92b9fd` | Namespace apps with LimitRange/ResourceQuota, `platform` namespace, Tekton via the operator, profile basic (ADR 0007) |
| 18:12 | `4eac96b` | Makefile: `plan` saves `tfplan`, `apply` applies it non-interactively |
| 18:25 | `2ec2948` | System node resized to `Standard_B2as_v2` (8 GB): 4 GB could not schedule Argo CD + Tekton |
| 18:45 | `dc4f934` | Tekton Dashboard via `TektonConfig` profile `all`, read-only |
| 19:06 | `1f7a870` | Argo CD explicit resources per component (controller 1 GiB limit; was OOM-killed at the namespace default of 256 MiB) |
| 19:21 | `5c9d599` **PR #3** | Auto-stop at 17:00 and again at 22:00; schedules may start the same day |
| 20:31 | `6d76b48` | Tekton deployment runbook (`docs/runbooks/tekton.md`) |

Open at end of day:

| PR | State | Content |
|---|---|---|
| [#2](https://github.com/eiriksf-capgemini/cloud-infra/pull/2) | draft | Azure Monitor managed Prometheus + portal Grafana (ADR 0008). Destination stack is applied; the cluster add-on is off after the incident in §6. Needs corrected memory numbers before merge |
| [#4](https://github.com/eiriksf-capgemini/cloud-infra/pull/4) | open, **applied** | Reachability limited to Norway + operator egress; Tekton Dashboard ingress removed (ADR 0009). All three stacks applied and verified (§5) |

## 3. Decisions recorded

| ADR | Title | One line |
|---|---|---|
| 0001 | Use OpenTofu | Terraform-compatible, open licence |
| 0002 | Per-cloud modules behind a common interface | no cloud-agnostic HCL; same inputs/outputs per cloud; stacks coupled by naming convention |
| 0003 | Argo CD for GitOps | bootstrapped once from OpenTofu, everything in-cluster reconciled from Git |
| 0004 | Cost controls | auto-stop, smallest viable node, Free tiers, Spot for extra capacity, budget alert; Free Trial quota is 4 vCPU/region |
| 0005 | Workload app-of-apps and environments | environment is a property of the cluster; one overlay per environment; ApplicationSet discovery |
| 0006 | Container registry | one Basic ACR per organisation (`acrmadbadgerbadger`), name from the organisation not the prefix, pull via kubelet managed identity, no admin user |
| 0007 | Namespaces, `platform`, Tekton | namespace apps own Namespace/LimitRange/quota; Tekton via operator in `platform` |
| 0008 | Managed Prometheus + portal Grafana (PR #2) | hosted TSDB at ~$2–6/month, free portal dashboards, no Managed Grafana (~$40–70/month), no self-hosted stack |
| 0009 | Network access and authentication (PR #4) | Norway-registered prefixes + Zscaler Oslo on the ingress; operator egress only on API server and state storage; nothing unauthenticated through the ingress |

## 4. What exists in Azure now

Subscription "Azure subscription 1" (Free Trial), Capgemini tenant. Resource group
`rg-cloudinfra-poc` unless noted.

| Resource | Type | Stack | Notes |
|---|---|---|---|
| `stcloudinfrapocec8e` (rg `rg-cloudinfra-poc-tfstate`) | Storage account | `00-tfstate` | remote state; Entra ID only; firewall Deny + operator egress |
| `budget-cloudinfra-poc` | Subscription budget | `00-tfstate` | 500 in billing currency, 80 % actual / 100 % forecast |
| `vnet-cloudinfra-poc`, `snet-aks`, `nsg-cloudinfra-poc-aks` | Network | `10-network` | NSG: one rule, 80/443 from 1249 sources |
| `aks-cloudinfra-poc`, `id-aks-cloudinfra-poc` | AKS + identity | `20-cluster` | 1.36.4, `Standard_B2as_v2` × 1, Free tier, CNI overlay, Entra ID + Azure RBAC, 10 authorised IP ranges |
| `aa-aks-cloudinfra-poc-autostop` (North Europe) | Automation account + runbook | `20-cluster` | schedules `stop-daily-1700`, `stop-daily-2200`; first 22:00 run completed 20:00:49 UTC tonight |
| `acrmadbadgerbadger` | Container registry, Basic | `25-registry` | AcrPull → kubelet identity; contains `podinfo:6.9.2` |
| `amw-cloudinfra-poc`, `dce-…-prom`, `dcr-…-prom`, 3 rule groups | Azure Monitor managed Prometheus | `40-observability` (PR #2) | destination ready; cluster add-on currently off |

In the cluster (Argo CD, namespace `platform`): `ingress-nginx`, `cert-manager`,
`tekton-operator`, `platform-tekton`, namespace apps `demo`, `sogeti`, `invent`, `i-and-d`,
`platform`, and the reference workload `demo-podinfo` at `http://podinfo.57.174.156.100.nip.io`.

## 5. Verification evidence

- **ACR (PR #1)**: `az acr import` of podinfo, then a pod on the cluster pulled
  `acrmadbadgerbadger.azurecr.io/podinfo:6.9.2` in 1.6 s with no pull secret.
- **Auto-stop (PR #3)**: schedules created with next runs 22:00 today and 17:00 tomorrow;
  the 22:00 job ran (`Completed`, 20:00:49–20:01:11 UTC) and the cluster is `Stopped`.
- **Access control (PR #4)**: podinfo `200` from Zscaler Oslo, `Connection timed out` from
  Tokyo, Moscow and Stockholm; API server TCP 443 timed out from Moscow, Istanbul, New York
  while kubectl worked locally and in-cluster controllers logged no API errors; state blob
  listing `403` from Spain and the USA while `tofu plan` worked locally. All three stacks
  showed no drift after apply.
- **Managed Prometheus (PR #2)**: 7 resources applied, no drift; add-on enablement
  verified the data path negatively (see §6) and was rolled back.

## 6. Incident: metrics add-on preempted the platform (18:1x–18:3x Oslo)

Enabling the Azure Monitor metrics add-on on the 4 GB `B2ls_v2` node placed 1350 MiB of
`system-node-critical` requests (two 530 MiB collector replicas pinned by an HPA, a 180 MiB
DaemonSet pod, kube-state-metrics, targets operator). The scheduler preempted cert-manager,
ingress-nginx, podinfo, retina and all Tekton pods; 13 pods were Pending and the ingress
returned nothing. Rolled back by switching the add-on off in place (gitignored tfvars).
Follow-ups: the node was resized to 8 GB (`2ec2948`), and ADR 0008's memory estimate must be
corrected before PR #2 merges. The same evening Argo CD's controller was OOM-killed at the
namespace LimitRange default; fixed by `1f7a870`.

## 7. Cost picture (Sweden Central retail, USD)

| Item | Per month | Note |
|---|---|---|
| `Standard_B2as_v2` node | ~$0.078/h → ~$17 with 17:00 stop on weekdays, ~$57 at 24/7 | largest item; stopped nightly |
| Load balancer rules + 2 public IPs, OS disk | ~$8–10 | bills while stopped |
| ACR Basic | ~$5 | flat, cannot stop |
| Managed Prometheus ingestion | ~$2–6 at 24/7 when the add-on is on | $0 today |
| Automation, Monitor workspace, budget, state storage | ~$0 | free tiers / cents |

Month-to-date consumption reported by the API: 0 (Free Trial credit). The budget alert is
the guardrail.

## 8. Open items

1. **PR #2**: correct ADR 0008 memory numbers (add-on needs ~1.35 GiB of requests, now
   affordable on 8 GB), decide default for `azure_monitor_metrics_enabled`, apply, verify
   dashboards.
2. **PR #4**: merge so Argo CD prunes the Tekton Dashboard ingress (it currently answers
   nginx `503` from Norway and nothing from elsewhere).
3. `00-tfstate` state is a local file in the main checkout only; move it to the remote
   backend or back it up.
4. `local_account_disabled = false` on AKS remains for the GitOps bootstrap.
5. No TLS on the nip.io hosts; needs a DNS zone, DNS-01 ClusterIssuer and external-dns
   (ingress is Norway-only, so HTTP-01 would be blocked anyway).
6. Allowlist drift: `make allowlist-refresh` monthly; Zscaler failover to Stockholm or
   Copenhagen locks operators out until the range is added (README "Locked out?").
7. Tekton runbook open items: see `docs/runbooks/tekton.md`.
8. Clean up merged worktrees (`../cloud-infra-autostop`, and `../cloud-infra-sec`,
   `../cloud-infra-obs` after their PRs merge).

## 9. How to operate (pointers)

`README.md` sections: *First deployment* (stack order), *Cost controls* (`make aks-start`,
`aks-stop`, `aks-status`), *Container images*, *Metrics and dashboards* (PR #2),
*Access control* with lockout recovery (PR #4). Decisions: `docs/adr/`. Operations:
`docs/runbooks/`.
