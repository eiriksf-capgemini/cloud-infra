# ADR 0004: Cost controls for the development environment

Date: 2026-10-20
Status: Accepted

## Context

This is a development / proof-of-concept environment on a **Free Trial** subscription
(spending limit on). Nothing needs to run outside working hours, and the owner wants the
bill as close to zero as possible without losing the ability to iterate.

Where AKS money goes, roughly in order: node VMs (by far the largest), the Standard load
balancer rules and public IP, node OS disks, log/metrics ingestion if enabled. The Free tier
control plane is free.

## Decision

1. **Auto-stop every evening.** `modules/azure/aks-autostop` creates an Azure Automation
   account with a runbook that stops the cluster daily at 17:00 Europe/Oslo, and again at
   22:00 for evenings it was started for late work (one schedule per entry in `stop_times`). The account
   lives in North Europe because Free Trial subscriptions can only create Automation
   accounts in six regions; it controls the cluster through ARM, so the region is irrelevant. Start is
   manual by default (`make aks-start`), with an optional weekday morning start schedule.
   A stopped cluster bills no node compute; nodes, workloads and Argo CD state survive.
2. **One small burstable node, Free control plane, nothing optional enabled.** Region is
   **Sweden Central**: the Free Trial marks every common size `NotAvailableForSubscription`
   in Norway East, West Europe and North Europe (only FX/L/isolated families remain), while
   Sweden Central and UK South expose the full catalogue. Cheapest AKS-eligible x86 sizes
   there are `Standard_B2als_v2` (AMD, $0.039/h) and `Standard_B2ls_v2` (Intel, $0.043/h), both
   2 vCPU / 4 GB. The first apply of `B2als_v2` failed with `AllocationFailed` (no capacity in
   the region at that moment), so `B2ls_v2` was used first. With Argo CD, Tekton (Pipelines + Triggers), ingress-nginx
   and cert-manager the 4 GB node ran out of schedulable memory, so the default moved to
   `Standard_B2as_v2` (2 vCPU / 8 GB, $0.078/h, ~$17/month with auto-stop). On 2026-10-21
   that size too failed to allocate on a routine start (`AllocationFailed`, capacity not
   quota, repeated for 15 minutes), so the default is now its Intel twin
   **`Standard_B2s_v2`** (2 vCPU / 8 GB, $0.086/h, ~$19/month with auto-stop): same series,
   same shape, 11% more, in a separate quota family (`Bsv2`, 4 vCPU free). It was chosen over
   Azure's suggested `D2as_v5`/`D2s_v5` (non-burstable, 18–31% more) because the POC's load
   is bursty and the price gap is smaller. The AMD `Basv2` family has now failed allocation
   twice in this region (`B2als_v2` on 2026-10-20, `B2as_v2` on 2026-10-21). A 4-vCPU size
   would consume the whole regional quota and leave no room for upgrade surge nodes.
   On 2026-10-21 that trade was made anyway for OpenChoreo (ADR 0010): the default is now
   **`Standard_B4s_v2`** (4 vCPU / 16 GB, $0.173/h, ~$42/month with auto-stop), the quota is
   saturated, upgrades need `--max-surge 0 --max-unavailable 1` out of band, and a size change
   means recreating the cluster (`docs/runbooks/recreate-cluster.md`). The Free Trial also
   caps public IPs at 3 per region; one is the cluster egress, one the static ingress IP. `Standard_B2pls_v2` (arm64) is
   $0.034/h and was skipped only to avoid arm64 image surprises. With auto-stop the node
   costs roughly $9/month; the load balancer and public IP add a similar amount. No Log Analytics,
   no Defender, no Azure Policy add-on in the POC cluster. Enable them deliberately later.
3. **Spot + scale-to-zero for extra capacity.** `user_node_pools` support `spot = true`
   and `min_count = 0`, so burst workloads run on Spot VMs and disappear when idle.
4. **Subscription budget alert** in `00-tfstate`: 80% actual and 100% forecast of a
   monthly amount, e-mailed to subscription Owners.
5. **Destroy for long breaks.** `tofu destroy` the `20-cluster` stack if the cluster is
   unused for more than a few days. `00-tfstate` and `10-network` cost cents and stay.

## What was considered and not done

- **Native AKS scheduled stop/start**: does not exist. Hence Automation.
- **GitHub Actions cron** for stop/start: works, but needs CI + OIDC federation first.
  Reasonable to switch to later when CI exists.
- **Stopping Argo CD from scaling things**: not needed; a stopped cluster runs nothing.
- **Ephemeral OS disks**: need a VM size with a local cache; the default `B2ls_v2` has
  none. Revisit if the node size changes to a `*ds*` family.

## Consequences

- The cluster is **off** when you arrive in the morning unless `auto_start_time` is set.
  Start takes 2–4 minutes.
- Azure does not guarantee a cluster stopped for >30 days will start again. Destroy
  instead for long gaps.
- While stopped, the load balancer rules/IP and OS disks still bill a few USD a month.
- **CPU requests, not memory, are the binding constraint on a 2-vCPU node.** AKS's own
  kube-system pods request ~1.3 of the 1.9 allocatable cores (metrics-server, CoreDNS and
  the workload-identity webhook run two replicas each). Everything the POC adds is sized
  for idle use: Tekton's three 100m deployments and ingress-nginx are trimmed in Git,
  metrics-server is pinned through the AKS `metrics-server-config` ConfigMap, CoreDNS runs
  one replica, and the Entra Workload ID webhook (2 × 100m) stays off until a workload needs
  a federated credential. Details and the live budget: `docs/runbooks/tekton.md`, item 4.
- Free Trial quota is small. Measured in `norwayeast` and `swedencentral` on 2026-10-20 (identical): **4 regular vCPUs and
  3 Spot vCPUs for the whole region**, 4 per VM family. That means: one 2-vCPU system node,
  room for one surge node during upgrades, and at most one 2-vCPU Spot node. A 4-vCPU size
  would leave no surge capacity. Check with `az vm list-usage -l <region> -o table` before
  changing `vm_size` or `node_count`.
