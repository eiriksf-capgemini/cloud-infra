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
         Microsoft.ContainerService Microsoft.ContainerRegistry Microsoft.Automation; do \
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
```

Open https://localhost:8080. The `root` Application syncs `gitops/clusters/azure-dev`, which
installs ingress-nginx and cert-manager and discovers every workload under
`gitops/apps/*/*/overlays/dev`. From here on, change the cluster by committing to `gitops/`.
Adding an application is described in `gitops/apps/README.md`.

Tear down in reverse: `30-gitops` → `25-registry` → `20-cluster` → `10-network`; keep `00-tfstate`.
Destroying the registry deletes every image in it.

## Tech stack

- **Provisioning:** OpenTofu 1.13 (`hashicorp/azurerm` 5.x, `hashicorp/helm` 3.x), plain stacks + Makefile, remote state in Azure Storage
- **Cloud:** Azure (Sweden Central): AKS 1.36 on one `Standard_B2as_v2` node, Azure CNI Overlay, Entra ID + Azure RBAC, ACR Basic, Azure Automation for auto-stop
- **GitOps:** Argo CD 3.5 (chart 10.10.5), app-of-apps Helm chart per cluster, ApplicationSet-discovered kustomize workloads
- **Platform services:** ingress-nginx 4.15, cert-manager 1.21, Tekton Operator 0.77 (Pipelines, Triggers, read-only Dashboard)
- **Local tooling:** kubectl 1.36, Helm 4.3, kubelogin, pinned in `.tool-versions`; `pre-commit` for `tofu fmt`/`validate`

## Layout

```
modules/            reusable building blocks
  azure/network     RG, VNet, AKS subnet, NSG
  azure/aks         AKS cluster implementing the common cluster interface (ADR 0002)
  azure/aks-autostop  Azure Automation schedules that stop the cluster daily (ADR 0004)
  azure/acr         Container registry + AcrPull/AcrPush role assignments (ADR 0006)
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

scripts/            helpers (country-prefixes.py regenerates the country allowlist; gh-app-token.mjs mints the agents' GitHub App token)

gitops/             what Argo CD reconciles INTO the cluster
  clusters/azure-dev      Helm chart: platform Applications + workload ApplicationSet (environment: dev)
  apps/<namespace>/<app>/ workloads: kustomize base + overlays/{dev,test,prod}; every namespace
                          folder has a `namespace` app (Namespace, LimitRange, quotas); no auto-create
  apps/platform/          Argo CD (bootstrapped) + Tekton (Pipelines, Triggers, read-only Dashboard)
  platform/<service>      Helm values (ingress-nginx, cert-manager, external-dns) or kustomize dir (tekton-operator)
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

- Region is **Sweden Central**, node size `Standard_B2as_v2`; ADR 0004 explains why.
- The cluster **auto-stops daily at 17:00 and again at 22:00 Europe/Oslo** (Azure
  Automation, free tier); the second stop catches evenings it was started for late work.
  Start it with `make aks-start`, check with `make aks-status`, stop early with `make aks-stop`.
  Set `auto_start_time = "08:00"` in `20-cluster` tfvars for weekday auto-start, change the
  times with `auto_stop_times`, or set it to `[]` to disable auto-stop.
- A **subscription budget alert** (default 500 in billing currency) is created by `00-tfstate`
  and mails subscription Owners at 80% actual / 100% forecast.
- Extra capacity should be a **Spot user pool with `min_count = 0`**; see
  `live/azure/poc/20-cluster/terraform.tfvars.example`.
- Unused for days? `make destroy STACK=live/azure/poc/20-cluster`. Network and state stay.
- The container registry (`25-registry`, Basic SKU) is a flat ~$5/month and cannot be
  stopped. Destroy it too if the environment is idle for weeks; images are the only state.

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

## Access control

See [`docs/adr/0009-network-access-and-authentication.md`](docs/adr/0009-network-access-and-authentication.md).

- **Ingress (80/443)** accepts traffic only from IPv4 prefixes registered to Norway plus the
  operators' Zscaler Oslo egress (`live/azure/poc/allowlist/`). Everything else is dropped
  by the NSG. Refresh the country list with `make allowlist-refresh` and apply `10-network`.
- **AKS API server and the state storage account** accept only the trusted-egress ranges
  (`20-cluster`: `api_server_extra_sources`, `00-tfstate`: `storage_extra_sources` for a
  home IP). Entra ID is still required on top.
- **Dashboards are not public.** Argo CD and the Tekton Dashboard are reached through the
  Kubernetes API, i.e. after Entra ID login:

  ```sh
  kubectl -n platform port-forward svc/argocd-server 8080:443        # https://localhost:8080, user admin
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
  next apply does not remove it.
- Not restricted (Entra ID only): ACR (Basic SKU has no firewall), Azure Monitor workspace,
  Automation account.

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
