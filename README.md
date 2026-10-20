# cloud-infra

Proof-of-concept infrastructure as code. Azure first, structured so AWS and GCP slot in
later. Provisioning is done with **OpenTofu**; everything inside Kubernetes is reconciled by
**Argo CD** from this repo.

Decisions and their reasoning live in [`docs/adr/`](docs/adr/). Read those three pages first.

## Layout

```
modules/            reusable building blocks
  azure/network     RG, VNet, AKS subnet, NSG
  azure/aks         AKS cluster implementing the common cluster interface (ADR 0002)
  azure/aks-autostop  Azure Automation schedule that stops the cluster nightly (ADR 0004)
  aws/, gcp/        placeholders: same interface, not implemented yet
  k8s/argocd-bootstrap  Argo CD + root app-of-apps; cloud-agnostic (helm provider only)

live/<cloud>/<env>/ one directory per stack, each with its own state
  azure/poc/backend.hcl   shared remote-state settings for the environment
  azure/poc/00-tfstate    state storage account + subscription budget alert (local state itself)
  azure/poc/10-network    uses modules/azure/network
  azure/poc/20-cluster    uses modules/azure/aks
  azure/poc/30-gitops     uses modules/k8s/argocd-bootstrap

gitops/             what Argo CD reconciles INTO the cluster
  clusters/azure-poc      Helm chart: one Application per platform service
  platform/<service>      values.yaml per service (ingress-nginx, cert-manager, external-dns)
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

## Prerequisites

```sh
brew install opentofu azure-cli kubectl helm argocd kubelogin
tofu version        # pinned in .tool-versions (1.13.x)
```

An **Azure subscription** with Owner (or Contributor + User Access Administrator) rights.
On a fresh subscription, register the resource providers once; this saves minutes on the
first apply:

```sh
for p in Microsoft.Compute Microsoft.Network Microsoft.Storage Microsoft.ManagedIdentity \
         Microsoft.ContainerService Microsoft.Automation; do az provider register -n $p --wait; done
```

## First deployment (when a subscription is available)

```sh
az login
az account set --subscription <subscription-id>
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# 1. state backend (local state for this stack only)
make init  STACK=live/azure/poc/00-tfstate
make apply STACK=live/azure/poc/00-tfstate
make output STACK=live/azure/poc/00-tfstate      # paste backend_hcl into live/azure/poc/backend.hcl

# 2. network
make init apply STACK=live/azure/poc/10-network

# 3. cluster (~10 min)
make init apply STACK=live/azure/poc/20-cluster
make output STACK=live/azure/poc/20-cluster      # run get_credentials_command
kubectl get nodes

# 4. argo cd
cp live/azure/poc/30-gitops/terraform.tfvars.example live/azure/poc/30-gitops/terraform.tfvars
#    -> set gitops_repo_url to this repo's clone URL (push the repo first)
make init apply STACK=live/azure/poc/30-gitops
kubectl -n argocd port-forward svc/argocd-server 8080:443
#    admin password: make output STACK=live/azure/poc/30-gitops
```

Open https://localhost:8080. The `root` Application syncs `gitops/clusters/azure-poc`, which
installs ingress-nginx and cert-manager. From here on, change the cluster by committing to
`gitops/`.

Tear down in reverse: `30-gitops` → `20-cluster` → `10-network`; keep `00-tfstate`.

## Cost controls (dev environment)

See [`docs/adr/0004-cost-controls.md`](docs/adr/0004-cost-controls.md).

- The cluster **auto-stops daily at 19:00 Europe/Oslo** (Azure Automation, free tier).
  Start it with `make aks-start`, check with `make aks-status`, stop early with `make aks-stop`.
  Set `auto_start_time = "08:00"` in `20-cluster` tfvars for weekday auto-start, or
  `auto_stop_time = null` to disable auto-stop.
- A **subscription budget alert** (default 500 in billing currency) is created by `00-tfstate`
  and mails subscription Owners at 80% actual / 100% forecast.
- Extra capacity should be a **Spot user pool with `min_count = 0`**; see
  `live/azure/poc/20-cluster/terraform.tfvars.example`.
- Unused for days? `make destroy STACK=live/azure/poc/20-cluster`. Network and state stay.

## Day-to-day

```sh
make validate-all     # init -backend=false + validate every module and stack; no credentials needed
make fmt              # tofu fmt -recursive
make plan  STACK=live/azure/poc/20-cluster
helm template root gitops/clusters/azure-poc --namespace argocd   # render the app-of-apps
```

Optional: `pre-commit install` to run fmt/validate on commit.

## Status

- [x] Repo scaffold, modules, stacks, GitOps chart (validated with `tofu validate`, never applied)
- [ ] First `tofu apply` on Azure (blocked on a subscription)
- [ ] AWS: `modules/aws/{network,eks}`, `live/aws/poc/*`
- [ ] GCP: `modules/gcp/{network,gke}`, `live/gcp/poc/*`
- [ ] CI: GitHub Actions with OIDC to Azure running `plan` on PRs
- [ ] DNS zone, ClusterIssuers, external-dns
- [ ] Consider Terragrunt if `live/` outgrows the Makefile + backend.hcl approach
