# cloud-infra

Provisions an AKS dev platform on Azure with OpenTofu and runs everything inside it from Git with Argo CD.

Proof of concept, Azure first, structured so AWS and GCP slot in later. Decisions live in
[`docs/adr/`](docs/adr/), operational summaries in [`docs/runbooks/`](docs/runbooks/)
(currently: [Tekton](docs/runbooks/tekton.md)), dated change reports in
[`docs/reports/`](docs/reports/) (first: [2026-10-20](docs/reports/2026-10-20-change-report.md)).

## Contents

- [Quick start](#quick-start)
- [Tech stack](#tech-stack)
- [Layout](#layout)
- [Multi-cloud approach](#multi-cloud-approach)
- [Cost controls (dev environment)](#cost-controls-dev-environment)
- [Container images](#container-images)
- [Access control](#access-control)
- [Metrics and dashboards](#metrics-and-dashboards)
- [OpenChoreo](#openchoreo)
- [TLS](#tls)
- [Day-to-day](#day-to-day)
- [Status](#status)
- [Contributing](#contributing)
- [Team](#team)
- [License](#license)

## Quick start

### Prerequisites

```sh
brew install opentofu azure-cli kubectl helm argocd
brew install azure/kubelogin/kubelogin   # NOT the core "kubelogin" formula; that is a different tool
tofu version                              # pinned in .tool-versions (1.13.x)
```

An **Azure subscription** with Owner (or Contributor + User Access Administrator) rights.
On a fresh subscription, register the resource providers once; this saves minutes on the
first apply:

```sh
for p in Microsoft.Compute Microsoft.Network Microsoft.Storage Microsoft.ManagedIdentity \
         Microsoft.ContainerService Microsoft.ContainerRegistry Microsoft.Automation \
         Microsoft.Monitor Microsoft.Insights Microsoft.AlertsManagement Microsoft.KeyVault; do \
  az provider register -n $p --wait; done
```

### First deployment

The `azure/poc` environment is already deployed from this repo. These are the steps to
recreate it, or to stand up a second environment with another `name_prefix`.

```sh
az login
az account set --subscription <subscription-id>
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# 1. state backend (local state for this stack only)
make init plan apply STACK=live/azure/poc/00-tfstate
make output STACK=live/azure/poc/00-tfstate      # paste backend_hcl into live/azure/poc/backend.hcl

# 2. network
make init plan apply STACK=live/azure/poc/10-network

# 3. cluster (~10 min)
make init plan apply STACK=live/azure/poc/20-cluster
make output STACK=live/azure/poc/20-cluster      # run get_credentials_command
kubectl get nodes

# 4. container registry (~1 min; needs the cluster for the AcrPull grant, or set grant_aks_pull = false)
make init plan apply STACK=live/azure/poc/25-registry
make output STACK=live/azure/poc/25-registry     # login_server, login_command

# 5. argo cd
cp live/azure/poc/30-gitops/terraform.tfvars.example live/azure/poc/30-gitops/terraform.tfvars
#    -> set gitops_repo_url to this repo's clone URL (push the repo first)
make init plan apply STACK=live/azure/poc/30-gitops
kubectl -n platform port-forward svc/argocd-server 8080:443
#    admin password: make output STACK=live/azure/poc/30-gitops

# 6. metrics (~2 min): Azure Monitor workspace + collection rule; the cluster's ama-metrics add-on
#    is on by default in 20-cluster and starts shipping as soon as this exists
make init plan apply STACK=live/azure/poc/40-observability
#    dashboards: portal > Monitor > Dashboards with Grafana (nothing to install)

# 7. shared admin password (~1 min): Key Vault + generated secret; External Secrets delivers it
make init plan apply STACK=live/azure/poc/35-secrets
make output STACK=live/azure/poc/35-secrets           # read_admin_password_command
```

Open https://localhost:8080. The `root` Application syncs `gitops/clusters/azure-dev`, which
installs ingress-nginx and cert-manager and discovers every workload under
`gitops/apps/*/*/overlays/dev`. From here on, change the cluster by committing to `gitops/`.
Adding an application is described in `gitops/apps/README.md`.

Tear down in reverse: `35-secrets` → `40-observability` → `30-gitops` → `25-registry` → `20-cluster` → `10-network`; keep `00-tfstate`.
Destroying the registry deletes every image in it.

## Tech stack

- **Provisioning:** OpenTofu 1.13 (`hashicorp/azurerm` 5.x, `hashicorp/helm` 3.x), plain stacks + Makefile, remote state in Azure Storage
- **Cloud:** Azure (Sweden Central): AKS 1.36 on one `Standard_B4s_v2` node, Azure CNI Overlay, Entra ID + Azure RBAC, ACR Basic, Azure Monitor managed Prometheus (portal Grafana dashboards), Azure Automation for auto-stop
- **GitOps:** Argo CD 3.5 (chart 10.10.5), app-of-apps Helm chart per cluster, ApplicationSet-discovered kustomize workloads
- **Platform services:** ingress-nginx 4.15, cert-manager 1.21, Tekton Operator 0.77 (Pipelines, Triggers, read-only Dashboard), KEDA 2.21 + HTTP add-on (scale to zero)
- **Developer platform:** OpenChoreo 1.3.1 (control + data plane, ThunderID, kgateway, External Secrets, OpenBao) behind the same ingress (ADR 0010)
- **Local tooling:** kubectl 1.36, Helm 4.3, kubelogin, pinned in `.tool-versions`; `pre-commit` for `tofu fmt`/`validate`

## Layout

```
modules/            reusable building blocks
  azure/network     RG, VNet, AKS subnet, NSG, static public IP for ingress (ADR 0010)
  azure/aks         AKS cluster implementing the common cluster interface (ADR 0002)
  azure/aks-autostop  Azure Automation schedules that stop the cluster daily (ADR 0004)
  azure/acr         Container registry + AcrPull/AcrPush role assignments (ADR 0006)
  azure/managed-prometheus  Azure Monitor workspace + DCR/DCE + default recording rules (ADR 0008)
  azure/keyvault    Key Vault + generated secrets; source of the shared admin password (ADR 0011)
  aws/, gcp/        placeholders: same interface, not implemented yet
  k8s/argocd-bootstrap  Argo CD + root app-of-apps; cloud-agnostic (helm provider only)

live/<cloud>/<env>/ one directory per stack, each with its own state
  azure/poc/backend.hcl   shared remote-state settings for the environment
  azure/poc/allowlist/    source-IP allowlists shared by the stacks (Norway prefixes, operator egress; ADR 0009)
  azure/poc/00-tfstate    state storage account + subscription budget alert (local state itself)
  azure/poc/10-network    uses modules/azure/network
  azure/poc/20-cluster    uses modules/azure/aks
  azure/poc/25-registry   uses modules/azure/acr; grants AcrPull to the cluster's kubelet identity
  azure/poc/30-gitops     uses modules/k8s/argocd-bootstrap
  azure/poc/35-secrets    uses modules/azure/keyvault; grants the kubelet identity read access (ADR 0011)
  azure/poc/40-observability  uses modules/azure/managed-prometheus; cluster add-on is switched on in 20-cluster

scripts/            helpers (country-prefixes.py regenerates the country allowlist; gh-app-token.mjs mints the agents' GitHub App token)

local/kind/openchoreo/  the laptop flavour of the OpenChoreo install (ADR 0018): the same charts and console image on the
                        kind cluster from platform-gitops; idempotent scripts, generated credentials, observability plane included

gitops/             what Argo CD reconciles INTO the cluster
  clusters/azure-dev      Helm chart: platform Applications + workload ApplicationSet (environment: dev)
  apps/<namespace>/<app>/ workloads: kustomize base + overlays/{dev,test,prod}; every namespace
                          folder has a `namespace` app (Namespace, LimitRange, quotas); no auto-create
  apps/platform/          Argo CD (bootstrapped) + Tekton (Pipelines, Triggers, read-only Dashboard)
  platform/<service>      Helm values (ingress-nginx, cert-manager, keda, openchoreo-*, ...) or kustomize dirs
                          (tekton-operator, gateway-api-crds, openchoreo-{gateway-params,secrets,gateway-ca,ingress,config})
  bootstrap/root-app.yaml manual fallback for the root Application
```

Stacks are coupled by **naming convention** (`rg-<prefix>`, `vnet-<prefix>`, `aks-<prefix>`)
and data sources, not by reading each other's state. Default prefix: `cloudinfra-poc`.

## Multi-cloud approach

No cloud-agnostic HCL. Each cloud gets its own modules that expose the **same inputs and
outputs** (`name`, `kubernetes_version`, `system_node_pool`, `user_node_pools`, `tags` →
`cluster_name`, `cluster_endpoint`, `cluster_ca_certificate`, `oidc_issuer_url`). The
cloud-agnostic layer starts at the Kubernetes API: `modules/k8s/*` and `gitops/` do not change
when a cloud is added.

## Cost controls (dev environment)

See [`docs/adr/0004-cost-controls.md`](docs/adr/0004-cost-controls.md).

- Region is **Sweden Central**, node size `Standard_B4s_v2` (~$42/month at 11 h × 22 d); ADR 0004
  and ADR 0010 explain why. The Free Trial quota (4 vCPU, 3 public IPs per region) is now fully
  used: a node size change means recreating the cluster (`docs/runbooks/recreate-cluster.md`).
- The cluster **auto-stops daily at 17:00 and again at 22:00 Europe/Oslo** (Azure
  Automation, free tier); the second stop catches evenings it was started for late work.
  Start it with `make aks-start` (polls until the console answers and prints each stage), check
  with `make aks-status` or `make aks-wait`, stop early with `make aks-stop`.
  Set `auto_start_time = "08:00"` in `20-cluster` tfvars for weekday auto-start, change the
  times with `auto_stop_times`, or set it to `[]` to disable auto-stop.
- A **subscription budget alert** (default 500 in billing currency) is created by `00-tfstate`
  and mails subscription Owners at 80% actual / 100% forecast.
- Extra capacity should be a **Spot user pool with `min_count = 0`**; see
  `live/azure/poc/20-cluster/terraform.tfvars.example`.
- Unused for days? `make destroy STACK=live/azure/poc/20-cluster`. Network and state stay.
- The container registry (`25-registry`, Basic SKU) is a flat ~$5/month and cannot be
  stopped. Destroy it too if the environment is idle for weeks; images are the only state.
- HTTP demo workloads **scale to zero** through KEDA's HTTP add-on (podinfo is the reference, ADR
  0010); platform controllers cannot, so the nightly stop stays the main saver.
- Managed Prometheus (`40-observability`) bills only samples ingested (~$0.11 per 10 M in
  Sweden Central), roughly $2–6/month for this cluster running 24/7 and nothing while it is
  stopped. The portal Grafana dashboards are free. See ADR 0008.

## Container images

`25-registry` creates `acr<organization>.azurecr.io` (default `acrmadbadgerbadger`) and grants
the AKS kubelet identity `AcrPull`, so pods can reference images from it without an
`imagePullSecret`. No admin user: authenticate with Entra ID.

```sh
az acr login --name acrmadbadgerbadger                              # docker/podman client
docker build -t acrmadbadgerbadger.azurecr.io/myapp:0.1.0 . && docker push acrmadbadgerbadger.azurecr.io/myapp:0.1.0
az acr import --name acrmadbadgerbadger --source ghcr.io/stefanprodan/podinfo:6.9.2 --image podinfo:6.9.2   # no local docker needed
az acr repository list --name acrmadbadgerbadger -o table
```

Pin `image:` in `gitops/apps/<namespace>/<app>/overlays/<env>` to `acrmadbadgerbadger.azurecr.io/<repo>:<tag>`.
The one platform image built here is the OpenChoreo console (`openchoreo-ui`, ADR 0013); see
`docs/runbooks/openchoreo-console-image.md`.

## Access control

See [`docs/adr/0009-network-access-and-authentication.md`](docs/adr/0009-network-access-and-authentication.md).

- **Ingress (80/443)** accepts traffic only from IPv4 prefixes registered to Norway plus the
  operators' Zscaler Oslo egress (`live/azure/poc/allowlist/`). Everything else is dropped
  by the NSG. Refresh the country list with `make allowlist-refresh` and apply `10-network`.
- **AKS API server and the state storage account** accept only the trusted-egress ranges
  (`20-cluster`: `api_server_extra_sources`, `00-tfstate`: `storage_extra_sources` for a
  home IP). Entra ID is still required on top.
- **One admin password** for Argo CD `admin`, Thunder's admin console and the seeded OpenChoreo
  users, generated into Key Vault `kv-cloudinfra-poc` and delivered by External Secrets (ADR
  0011). Read it with `make output STACK=live/azure/poc/35-secrets` → `read_admin_password_command`.
- **Argo CD** is at https://argo.20.91.237.179.nip.io (its own login, user `admin`; TLS
  passthrough with a certificate from the POC's private CA, see [TLS](#tls)). The **Tekton Dashboard** has no login and stays behind the
  Kubernetes API:

  ```sh
  kubectl -n platform port-forward svc/tekton-dashboard 9097:9097    # http://localhost:9097 (read-only)
  ```

- **Locked out?** Your egress moved (new Zscaler datacenter, home network). ARM still
  works, so add the range and re-apply, or patch directly:

  ```sh
  curl -s ifconfig.co                                                                   # what Azure sees
  az aks update -g rg-cloudinfra-poc -n aks-cloudinfra-poc --api-server-authorized-ip-ranges <existing>,<ip>/32
  az storage account network-rule add -g rg-cloudinfra-poc-tfstate -n stcloudinfrapocec8e --ip-address <ip>
  ```

  then add the range to `trusted-egress-ipv4.txt` (or the stack's `*_extra_sources`) so the
  next apply does not remove it. Note that not everything leaves through Zscaler: calls to
  some Microsoft data-plane endpoints (Key Vault, 2026-10-22) exit from the Capgemini
  corporate range `198.184.231.0/24`, which is therefore in the list too.
- Not restricted (Entra ID only): ACR (Basic SKU has no firewall), Azure Monitor workspace,
  Automation account.
- **OpenChoreo** (portal, API, Thunder, workload gateway) shares the ingress IP and allowlist. It
  ships the reference install's default users and passwords (ADR 0010); change them before
  showing it to anyone outside the POC.

## Metrics and dashboards

Azure Monitor managed Prometheus scrapes the cluster (kubelet, cAdvisor, node-exporter,
kube-state-metrics with the *minimal ingestion profile*) and stores 18 months in the
`amw-cloudinfra-poc` workspace. Dashboards are the free **Azure Monitor > Dashboards with
Grafana** experience; the standard Kubernetes / Node Exporter community dashboards work out
of the box because `40-observability` also installs the recording rules they need.

```sh
az aks show -g rg-cloudinfra-poc -n aks-cloudinfra-poc --query azureMonitorProfile.metrics.enabled   # add-on on?
kubectl -n kube-system get pods -l rsName=ama-metrics                                             # agent healthy?
make output STACK=live/azure/poc/40-observability                                                  # query endpoint
```

Application metrics: pods in the workload namespaces annotated with
`prometheus.io/scrape: "true"` (plus `prometheus.io/port`, optional `prometheus.io/path`) are
scraped too; the allow-list of namespaces is the `ama-metrics-settings-configmap` in
`gitops/platform/azure-monitor-metrics/`. Query anything with PromQL in **Monitor > Metrics
explorer with PromQL**, or point any Grafana at the `query_endpoint` output with Entra ID auth.

## OpenChoreo

[OpenChoreo](https://openchoreo.dev) 1.3.1 runs on the cluster as the developer platform
(ADR 0010): control plane, data plane and the ThunderID identity provider, with kgateway,
External Secrets, OpenBao (dev mode) and the Gateway API CRDs as prerequisites. All of it is
Argo CD Applications under `gitops/platform/`, fronted by ingress-nginx on the static IP.

| What | URL | Login |
|---|---|---|
| Argo CD | https://argo.20.91.237.179.nip.io | `admin` + the shared admin password (ADR 0011) |
| Portal (Backstage) | https://console.openchoreo.20.91.237.179.nip.io | `admin@openchoreo.dev` (also `developer@`, `platform-engineer@`, `sre@`) with the shared admin password (ADR 0011) |
| API | https://api.openchoreo.20.91.237.179.nip.io | OIDC via Thunder |
| ThunderID | https://thunder.openchoreo.20.91.237.179.nip.io | same users |
| Deployed components | https://`<component>-<env>`.openchoreoapis.20.91.237.179.nip.io | per component |

```sh
kubectl get clusterdataplane,environments,projects -A                    # registered plane + sample resources
kubectl -n openchoreo-control-plane get pods                              # api, controller, backstage, gateways
kubectl -n openchoreo-control-plane get certificate,job                   # CA issued; CA-sync hook Succeeded
```

The getting-started sample (environments dev/staging/prod, a pipeline, the default project and
component types) is installed from upstream, pinned to v1.3.1 (`gitops/platform/openchoreo-config`).
Workflow and observability planes are not installed on AKS; see ADR 0010.

The same install also runs on a laptop: [`local/kind/openchoreo/`](local/kind/openchoreo/)
puts the same charts and console image, plus the observability plane, on the kind cluster
that [platform-gitops](https://github.com/eiriksf-capgemini/platform-gitops) creates
(ADR 0018). Credentials there are generated per install (`./secrets.sh show`).

The portal's home page carries an **AI usage & cost** widget (ADR 0013, 0014): estimated
Claude cost plus the signed-in user's token usage for the last day and the last 7 days, fed
by Claude Code's OpenTelemetry export pushed to the portal (no Anthropic admin access needed).
It needs a forked console image (`acrmadbadgerbadger.azurecr.io/openchoreo-ui`, built per
chart version), an in-cluster generated ingest token, and the Key Vault secret
`anthropic-member-email` for the identity mapping; reporter setup and procedures in
[`docs/runbooks/openchoreo-console-image.md`](docs/runbooks/openchoreo-console-image.md).

## TLS

See [`docs/adr/0012-private-ca-for-application-tls.md`](docs/adr/0012-private-ca-for-application-tls.md).

cert-manager keeps a private root CA (`poc-root-ca`) and the `poc-ca` ClusterIssuer signs
application certificates with it: podinfo and the OpenChoreo hosts (TLS at ingress-nginx, HTTP
redirects) and Argo CD (its own server certificate). Browsers trust the certificates after a
one-time import of the root:

```sh
kubectl -n cert-manager get secret poc-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > poc-root-ca.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain poc-root-ca.crt   # macOS
curl --cacert poc-root-ca.crt https://podinfo.20.91.237.179.nip.io/                                   # check
```

Argo CD loads `argocd-server-tls` at start-up only: after the first issuance (and if a renewed
certificate is not picked up) run `kubectl -n platform rollout restart deployment argocd-server`.

New app: add `cert-manager.io/cluster-issuer: poc-ca` and a `tls` block to its dev Ingress
(see `gitops/apps/demo/podinfo/overlays/dev/ingress.yaml`). Let's Encrypt replaces the CA once
a DNS zone exists; the Ingress annotations stay the same.

## Day-to-day

```sh
make validate-all     # init -backend=false + validate every module and stack; no credentials needed
make fmt              # tofu fmt -recursive
make plan  STACK=live/azure/poc/20-cluster
helm template root gitops/clusters/azure-dev --namespace platform   # render the app-of-apps
```

Optional: `pre-commit install` to run fmt/validate on commit.

## Status

- [x] Repo scaffold, modules, stacks, GitOps chart
- [x] `azure/poc` deployed: state backend, network, AKS, Argo CD, platform services, Tekton (2026-10-20)
- [x] Container registry (`modules/azure/acr`, `live/azure/poc/25-registry`)
- [x] Access control: Norway + operator-egress allowlists on ingress, API server and state storage; dashboards via port-forward only (ADR 0009)
- [x] Metrics: Azure Monitor managed Prometheus + portal Grafana dashboards (`40-observability`)
- [x] OpenChoreo 1.3.1 (control + data plane) behind the static ingress IP; KEDA scale-to-zero for HTTP demos (ADR 0010)
- [x] One admin password from Key Vault via External Secrets (ADR 0011); private CA TLS for podinfo + Argo CD (ADR 0012)
- [x] OpenChoreo console with the AI usage & cost widget from a forked image in ACR, fed by Claude Code telemetry (ADR 0013, 0014)
- [ ] AWS: `modules/aws/{network,eks}`, `live/aws/poc/*`
- [ ] GCP: `modules/gcp/{network,gke}`, `live/gcp/poc/*`
- [ ] CI: GitHub Actions with OIDC to Azure running `plan` on PRs
- [ ] DNS zone, ClusterIssuers, external-dns
- [ ] SSO (oauth2-proxy + Entra ID) in front of dashboards if they must be published
- [ ] Consider Terragrunt if `live/` outgrows the Makefile + backend.hcl approach

Open operational items are tracked per topic in [`docs/runbooks/`](docs/runbooks/).

## Contributing

1. Branch from `main` (`feat/<topic>`, `docs/<topic>`); never commit to `main` directly.
2. Record a non-obvious decision as a new ADR in `docs/adr/` (next free number).
3. Before pushing: `make fmt validate-all`, and `kubectl kustomize` / `helm template` for anything under `gitops/`.
4. Open a PR; one reviewer; squash-merge. Argo CD applies `gitops/` changes within minutes of merge, so a merged PR is a deployment.
5. Never commit `*.tfstate`, `*.tfvars` (except `*.example`) or credentials; they are gitignored on purpose.
6. **Coding agents push and open PRs as `hal9000-agent-bot[bot]`**, never as the human they run for, so author and
   reviewer are different principals. In the same shell call as the commit, push or `gh pr create`:
   `eval "$(node scripts/gh-app-token.mjs --env)"`, then push over HTTPS
   (`git push https://github.com/eiriksf-capgemini/cloud-infra.git HEAD:<branch>`) and check
   `gh pr view <n> --json author -q .author.login` prints `app/hal9000-agent-bot`. Needs the gitignored
   `.gh-app-identity.json` at the repo root; setup in
   [common-ai/skills/github-app-agent-identity](https://github.com/eiriksf-capgemini/common-ai/tree/main/skills/github-app-agent-identity).

## Team

- **Owner:** Eirik Sander-Fjeld ([@eiriksf-capgemini](https://github.com/eiriksf-capgemini))
- **Contact:** [GitHub issues](https://github.com/eiriksf-capgemini/cloud-infra/issues)
- **Azure:** subscription "Azure subscription 1" (Free Trial), tenant Capgemini

## License

[MIT](LICENSE)
