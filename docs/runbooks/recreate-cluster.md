# Runbook: recreate the AKS cluster (node size change on a saturated quota)

Why this exists: on the Free Trial the regional quota is 4 vCPU. Resizing the system node
from 2 to 4 vCPU through OpenTofu rotates through a temporary pool, which needs 6 vCPU for a
few minutes and fails. The only in-code path is destroy and recreate. Everything below is
GitOps or OpenTofu; the ingress IP is static (ADR 0010), so URLs do not change.

Budget ~60 minutes with the cluster unreachable for ~30. Do it inside the auto-stop window
(before 17:00 Europe/Oslo) so the new cluster is stopped tonight like the old one.

## Before

```sh
cd /Users/eiriksf/code/cloud-infra && git pull            # main must contain ADR 0010
make aks-status                                             # Running (start it if not)
kubectl get applications -n platform | grep -v Synced       # nothing unexpected mid-sync
az vm list-usage -l swedencentral -o table | grep -E 'Bsv2|cores'   # 2/4 before, 4/4 after
```

What is lost: nothing in Git. Argo CD's admin password (re-rotated below), Tekton run history
(Results is off), PVC data of OpenBao (dev mode, re-seeded) and Thunder (SQLite users, re-seeded
by its bootstrap). Images stay in ACR.

## 1. Tear down the stacks that live on the cluster

```sh
make destroy STACK=live/azure/poc/30-gitops          # Argo CD Helm release; the cluster goes next anyway
make destroy STACK=live/azure/poc/20-cluster         # ~10 min; also removes the autostop link and role grants
```

`40-observability` and `25-registry` stay: the workspace, rules and registry are not cluster
resources. Their cluster-bound pieces (DCR association, AcrPull grant) are re-pointed in step 3.

## 2. Create the cluster with the new size

```sh
cd live/azure/poc/20-cluster
cp terraform.tfvars.example terraform.tfvars   # if you do not have one
# first apply of a brand-new cluster: the egress LB does not exist yet (see tfvars.example)
echo 'api_server_include_cluster_egress = false' >> terraform.tfvars
cd -
make plan apply STACK=live/azure/poc/20-cluster        # ~10 min, Standard_B4s_v2
sed -i '' '/api_server_include_cluster_egress/d' live/azure/poc/20-cluster/terraform.tfvars
make plan apply STACK=live/azure/poc/20-cluster        # adds the new egress IP to the API allowlist
make output STACK=live/azure/poc/20-cluster            # run get_credentials_command
az aks get-credentials -g rg-cloudinfra-poc -n aks-cloudinfra-poc --overwrite-existing && kubelogin convert-kubeconfig -l azurecli
kubectl get nodes -o wide                               # one Standard_B4s_v2, Ready
```

## 3. Re-point the stacks that reference the cluster

```sh
make plan apply STACK=live/azure/poc/25-registry       # AcrPull -> new kubelet identity (replace)
make plan apply STACK=live/azure/poc/40-observability  # DCR association -> new cluster ID (replace)
make plan apply STACK=live/azure/poc/30-gitops         # Argo CD + root app; ~5 min
make plan apply STACK=live/azure/poc/35-secrets        # Key Vault grant -> new kubelet identity, firewall -> new egress IP
```

Argo CD now installs everything from `gitops/`: ingress-nginx picks up the static IP, then
cert-manager, Tekton, External Secrets, OpenBao, KEDA, kgateway, Thunder, OpenChoreo in wave
order. Expect 10–15 minutes until all Applications are Synced/Healthy.

## 4. Verify

```sh
kubectl get applications -n platform                                   # all Synced / Healthy
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'  # 20.91.237.179
kubectl describe node | sed -n '/Allocated resources/,/Events/p'       # CPU < ~85%, memory < ~60%
curl -sI http://podinfo.20.91.237.179.nip.io/ | head -1                # 200 (after a cold start of a few seconds)
curl -sI https://console.openchoreo.20.91.237.179.nip.io/ | head -1    # 200 / 302 to Thunder
kubectl -n kube-system get pods | grep ama-                            # metrics add-on back
```

Then rotate the Argo CD admin password (README, "Day-to-day") and delete the stale kube
context if `kubectl config get-contexts` shows two.

## If something fails

- `Only one account is allowed for your subscription per Region` on the Automation account:
  the old one is soft-deleted and blocks that region for 30 days; the REST API has no restore.
  Either recover it in the portal (Automation Accounts > Manage deleted accounts) and
  `tofu import` it, or point `automation_location` at another allowed region (default now
  `eastus2`) and re-run `make plan apply`.

- `AllocationFailed` on create: regional capacity, not quota. Retry in a few minutes or pick
  another Bsv2 size (ADR 0004 has the price table). Do not switch family: Basv2 has failed
  twice here.
- `20-cluster` apply stops on the API allowlist: your egress is not in
  `live/azure/poc/allowlist/trusted-egress-ipv4.txt`; see README "Locked out?".
- Node `DiskPressure` taint right after the gitops apply or after every `make aks-start`:
  image pulls of ~50 pods into the OS disk; clears by itself within 5–15 minutes once image
  GC has run. The 64 GB default (ADR 0004) removes it; a cluster still on 32 GB gets it at
  the next recreate.
- `kgateway-crds` OutOfSync with "estimated rule cost exceeds budget": the vendored CRDs are
  stale for the running Kubernetes version; regenerate with `scripts/kgateway-crds-patch.py`.
- `thunder` waiting for PVC hooks: the PVCs are not on `managed-csi-immediate`; check the
  values and that the `storage-classes` app synced.
- `thunder` re-sync stuck on "waiting for deletion of hook PersistentVolumeClaim": the chart's
  PVCs are PreSync hooks with `before-hook-creation`, so every manual sync deletes and
  recreates them (Thunder's SQLite is reset and re-seeded from the bootstrap; nothing of
  value is lost). The running pod holds them: `kubectl -n thunder delete pod -l
  app.kubernetes.io/name=thunderid` releases them and the sync completes in ~30 s. Hook-only
  changes (setup job env, bootstrap users) never show as drift, so changing the admin
  password source or the seeded users needs that manual sync (`argocd app sync thunder`).
- Data-plane `cluster-agent` stuck in ContainerCreating (`configmap "cluster-gateway-ca" not
  found`): the `gateway-ca-sync` CronJob in `openchoreo-control-plane` copies it every 5 min once
  cert-manager has issued the CA; check `kubectl -n openchoreo-control-plane get certificate,cronjob,job`.
- The 22:00 auto-stop fires during a long evening session too; `make aks-start` and Argo CD
  resumes where it was.
