# OpenChoreo on a local kind cluster

The laptop flavour of the OpenChoreo install this repo runs on AKS (ADR 0010, 0018): the same
charts (1.3.1), the same console image from the `openchoreo/backstage-plugins` fork, the same
observability modules, installed on the kind cluster that the
[platform-gitops](https://github.com/eiriksf-capgemini/platform-gitops) repository creates
(`kind-platform-gitops`, Colima). The upstream quick start always creates its own k3d
cluster; these scripts run the same v1.3.1 steps with the published OCI charts against the
existing cluster.

Unlike the AKS install, nothing here is reconciled by Argo CD: idempotent scripts run Helm
and a few `kubectl` patches. The kind cluster's own Argo CD belongs to platform-gitops; moving
these releases under it is tracked there (bead `pgops-xa9`).

## What you get

| Component | URL | Credentials |
|---|---|---|
| Console (Backstage, fork image) | http://openchoreo.localhost:8080 | `admin@openchoreo.dev`, `developer@`, `platform-engineer@`, `sre@openchoreo.dev`; passwords are generated at install (`install.sh` prints them, `./secrets.sh show` again) |
| OpenChoreo API | http://api.openchoreo.localhost:8080 | Thunder OAuth |
| ThunderID console | http://thunder.openchoreo.localhost:8080/console | `admin` / Secret `thunder-admin-credentials` in `thunder` |
| Workloads (data plane) | http://<route-host>.openchoreoapis.localhost:19080 | hostnames from `kubectl get httproute -A` |
| Observer API (observability plane) | http://observer.openchoreo.localhost:11080 | Thunder OAuth |
| MCP servers | console `/api/openchoreo-ai-elements/mcp`, API `/mcp` | Thunder (`user_mcp_client`) or Secret `ai-elements-mcp` |
| `occ remote` tunnels | 127.0.0.1:30443 | mTLS from the CLI |

## Prerequisites

- The platform-gitops stack is up (`platform-gitops/scripts/up.sh`): colima, the kind
  cluster, Cilium, the `kind-registry`.
- Colima with **6 CPUs** (`COLIMA_CPU=6 scripts/up.sh` there, or `colima start --cpu 6`); the
  observability plane's OpenSearch and Prometheus do not schedule reliably on 4.
- Host ports 8080, 19080, 11080 and 30443 free (published by a `socat` container).
- The `kind-registry` container answering on `localhost:5001` (platform-gitops `scripts/up.sh` starts it).
  The console image reaches the node only through it; there is no `kind load` fallback.
- For the console image: the fork checkout `../../../../openchoreo-backstage-plugins`
  (branch `feat/ai-usage-home-widget`) and Docker Desktop for the build.
- Tools: `kubectl`, `helm` 4, `docker`, `curl`, `python3`.

## Commands

```bash
./install.sh                              # everything; idempotent, re-run after any values change
WITH_OBSERVABILITY=false ./install.sh     # control plane + data plane only
BUILD_DOCKER_CONTEXT=desktop-linux ./console.sh   # build + push the fork console image, Secrets, values-console.yaml
./observability.sh install|remove         # the observability plane on its own
./secrets.sh show|render                  # the generated credentials; re-render upstream/ values
./start-lb.sh                             # (re)create the host port forwarder; no-op when unchanged
./coredns.sh apply|remove                 # the in-cluster DNS rewrite
./uninstall.sh [--crds]                   # remove everything install.sh added
```

Run them from this directory. `env.sh` holds every tunable (context, namespaces, ports,
chart versions); override through the environment.

### Credentials

Nothing in this directory is a credential. `secrets.sh` generates every password and
client secret the k3d quick start ships as literals (demo users, OpenBao root token,
Thunder OAuth clients, OpenSearch admin) on the first `install.sh`, keeps them in the
git-ignored `.secrets.env`, mirrors them into Secret `openchoreo-kind-credentials` in
`openchoreo-control-plane` (a fresh checkout recovers them from there), and renders
`upstream/*.yaml`, which carry `@@name@@` placeholders, into the git-ignored `.rendered/`.
`uninstall.sh` keeps `.secrets.env`, so a re-install reuses the same values.

Run `console.sh` (Secrets, values) **before** `install.sh` when you want the fork image: the
Skill provider reads all its repositories in one run and skips the whole run if any of them
fails, and its schedule is kept in the portal database, so a token added after the first
start only takes effect on the next run, up to 30 minutes later (or after
`kubectl -n openchoreo-control-plane delete pod -l app.kubernetes.io/name=backstage`
followed by that wait).

## What is different from the k3d quick start

| k3d quick start | here (kind) | why |
|---|---|---|
| k3d maps host ports 8080/19080/30443 to its load balancer at cluster creation | `gateway-parameters.yaml` pins the kgateway proxy Services to NodePorts 30080/30190/31080 (+30443), and `start-lb.sh` runs a `socat` container on the `kind` docker network publishing 8080/19080/11080/30443 on the host | kind's `extraPortMappings` cannot be changed after creation and the cluster has no LoadBalancer provider |
| `coredns-custom` ConfigMap rewrites `*.openchoreo.localhost` to `host.k3d.internal` | `coredns.sh` patches the kubeadm Corefile to rewrite `*.openchoreo.localhost` to the control-plane gateway Service, `*.openchoreoapis.localhost` to the data-plane gateway Service, and the observer names to the observability gateway Service | kubeadm CoreDNS has no `import` hook; pointing at the Services avoids a hairpin through the Mac |
| Thunder issuer `http://thunder.openchoreo.localhost:8080` | issuer / public URL `http://localhost:8080` (`values-thunder-kind.yaml`, `security.oidc` in `values-cp.yaml`); Thunder's HTTPRoute also serves `localhost` | Claude Code refuses plain-HTTP OAuth token endpoints unless the host is literally `localhost`; `*.localhost` does not count. In-cluster JWKS/token URLs keep the routable name |
| Gateway Service type LoadBalancer | NodePort via `spec.infrastructure.parametersRef` on the Gateway (`values-*.yaml`) | see above |
| Images pulled from the cluster | the console image is pushed to the `kind-registry` (`localhost:5001`), never `kind load`; `install.sh` refuses a pinned tag the registry no longer has | platform-gitops policy: images reach the node through the local registry |
| Demo credentials as literals in the values files | generated per install (`secrets.sh`), rendered into git-ignored copies | no literal credential in the repo (README > Contributing) |
| Samples from the moving `release-v1.3` branch | samples from the `v1.3.1` tag (`OPENCHOREO_REF`) | what `install.sh` applies and `uninstall.sh` deletes must not change under a pinned chart |

Everything else (Gateway API CRDs, cert-manager, ESO, OpenBao dev mode, kgateway,
ThunderID, Backstage ExternalSecret, ClusterDataPlane, default sample resources) is the
upstream sequence. `upstream/` holds the k3d Thunder and OpenBao values files from
`openchoreo/openchoreo` v1.3.1, structurally unchanged, with each literal credential
replaced by an `@@name@@` placeholder.

## Console image from the fork

The stock console works as-is. `console.sh` swaps it for an image built from a local
checkout of the `openchoreo/backstage-plugins` fork (branch `feat/ai-usage-home-widget`),
which adds what was built in the standalone Backstage POC (platform-gitops
`workloads/backstage`) and on the AKS install (ADRs 0013 to 0017, runbook
`docs/runbooks/openchoreo-console-image.md`):

| Feature | Where it comes from | Conflict check |
|---|---|---|
| `Skill` kind: Claude Code skills, agents, prompts, hooks read from Git (`common-ai` and the POC's `.claude/skills`), catalog pages per skill | `catalog-backend-module-ai-elements` | replaces the POC's `AiResource` kind and its `~/.claude/skills` filesystem provider (a pod cannot read the laptop) |
| MCP server at `/api/openchoreo-ai-elements/mcp`: catalog, platform facts, skills as prompts, docs as resources; Thunder OAuth or a shared token | `openchoreo-ai-elements-backend` | the POC's `mcp-actions` endpoint and its auto-approving OAuth shim were **not** ported |
| `AIProduct` kind + Governance Scorecard card, `SharePointSite` kind (14 sites), `API` type `mcp-server` + MCP Remotes card, department groups | `catalog-backend-module-portal-kinds`, `catalog-entities/` | new kinds only; no OpenChoreo kind, policy, auth or router touched |
| AI usage & cost home widget (Claude Code OpenTelemetry pushed to the portal) | `openchoreo-ai-usage-backend` | opt-in flag |
| Azure resources / Azure cost | fork plugins, **unconfigured** on kind (no managed identity) | inactive without `azureResources` config |

Not ported from the POC because they conflict with OpenChoreo: GitHub-based sign-in and
the allow-all permission policy (OpenChoreo owns sign-in via ThunderID and ships its own
policy), GitHub/Entra org providers (Users and Groups come from ThunderID), notifications,
signals, kubernetes backend (not wanted yet), theme, home page, templates.

```bash
export GITHUB_TOKEN=github_pat_...               # optional, explicit only: a read-only token for the private POC repo's skills
export ANTHROPIC_MEMBER_EMAIL=you@example.com    # optional; identity the usage widget reports for the demo users
BUILD_DOCKER_CONTEXT=desktop-linux ./console.sh  # build (on Docker Desktop), push to localhost:5001, Secrets, values-console.yaml
./install.sh                                     # redeploys the control plane with the fork image
```

The image is tagged `<chart version>-<fork sha>` (plus `-dirty-<hash>` when the fork
has uncommitted changes, so a rebuild never reuses a tag the node has cached) and pushed
to the `kind-registry` container that platform-gitops `scripts/up.sh` provisions (the node
mirrors it as `localhost:5001`).
`values-console.yaml` (generated, git-ignored) pins the image, gives the portal a 2 Gi PVC
for its SQLite, and renders the plugin configuration as `backstage.appConfig` (lists are
replaced between config files, so `catalog.locations` stay in the image). Secrets in
`openchoreo-control-plane`, all generated or read at run time and never committed:
`ai-elements-mcp` (MCP shared token), `ai-usage-ingest` (telemetry token), `github-token`
(only written when `GITHUB_TOKEN` is set; the script never borrows the `gh` login's token).
Delete `values-console.yaml` and re-run `./install.sh` to go back to the stock image.

### Connecting an MCP client

```bash
claude mcp add --transport http --client-id user_mcp_client --callback-port 8075 \
  platform http://openchoreo.localhost:8080/api/openchoreo-ai-elements/mcp   # login via Thunder
claude mcp add --transport http openchoreo http://api.openchoreo.localhost:8080/mcp
# non-interactive clients / Claude Desktop (mcp-remote): shared token
kubectl --context kind-platform-gitops -n openchoreo-control-plane get secret ai-elements-mcp -o jsonpath='{.data.token}' | base64 -d
```

Claude Desktop setup (`mcp-remote` with the token) is in the fork's
`plugins/openchoreo-ai-elements-backend/README.md`. Both servers are catalogued as `API`
entities of type `mcp-server`.

## Observability plane

`install.sh` installs the observability plane by default (`WITH_OBSERVABILITY=false` to
skip, `./observability.sh remove` to take it out again). It follows the upstream quick
start's `--with-observability` (v1.3.1): the `openchoreo-observability-plane` chart
(`values-op.yaml`) plus the pinned community modules `observability-logs-opensearch`
(OpenSearch single node, Fluent Bit), `observability-tracing-opensearch`,
`observability-metrics-prometheus` and `observability-events-otel-collector`, then
`ClusterObservabilityPlane default` and `spec.observabilityPlaneRef` on the data plane.
The control plane emits audit events to it (`openchoreoApi.config.audit` in `values-cp.yaml`).

| k3d quick start | here (kind) |
|---|---|
| host 11080 to the observability gateway | GatewayParameters in `openchoreo-observability-plane` pins the gateway Service to NodePort 31080; `start-lb.sh` publishes host 11080 |
| 11081/11082/11085 (Dashboards, OpenSearch, HTTPS) | not mapped: nothing listens behind them in v1.3 (Dashboards and Grafana are not installed, OpenSearch is ClusterIP) |
| `observer.openchoreo.localhost` resolves to `host.k3d.internal` in pods | `coredns.sh` rewrites `observer`, `rca-agent`, `finops-agent` `.openchoreo.localhost` to this plane's gateway Service **before** the generic rule (the observer lives on its own gateway, port 11080, not on the control-plane one) |

The console's Runtime Logs / Metrics / Traces tabs, Audit Logs and Cost Insights resolve
the observer URL through the API (`ClusterObservabilityPlane.spec.observerURL`), so
`http://observer.openchoreo.localhost:11080` must work from the browser and from pods.
Capacity: about 19 Gi of PVCs (OpenSearch 8, Prometheus 10, Alertmanager 1) on kind's
`standard` storage class; OpenSearch's CPU request is lowered to 250m. If OpenSearch fails
its bootstrap checks: `colima ssh -- sudo sysctl -w vm.max_map_count=262144`.

## Not included

- Workflow plane (`--with-build`): needs host ports 10081/10082; add them to
  `gateway-parameters.yaml` / `start-lb.sh` the same way.
- Argo CD management of these charts (backlog).

## Gotchas

- The `socat` forwarder restarts with Docker (`--restart unless-stopped`) and survives
  platform-gitops `scripts/down.sh`; `uninstall.sh` removes it. `start-lb.sh` only replaces it when the
  port map changed. Its ports are bound to IPv4 only on purpose: the `kind` network is
  dual-stack and Colima forwards a dual-stack host port to the guest IPv6 listener, which
  yields "Empty reply from server" from the Mac.
- OpenBao runs in dev mode, in memory. If its pod restarts, the seeded secrets are gone
  and the ExternalSecrets fail on their next refresh: re-run `./install.sh` (it reseeds
  the same generated values).
- `helm upgrade --install` is retried in place for a release that failed an upgrade;
  only a release whose first revision failed is uninstalled first (`reset_failed_release`
  in `env.sh`), so the portal's `backstage-db` PVC survives a transient timeout.
- The control-plane chart is upgraded with `--server-side=false`. Helm 4's default
  server-side apply conflicts with the `cluster-gateway-ca` ConfigMap (chart placeholder vs.
  the real CA written by `install.sh`) and would reset it to the placeholder.
- `coredns.sh` keeps a copy of the original Corefile in `.coredns-corefile.backup` (git-ignored).
- kgateway is pinned to v2.3.11 instead of the upstream v2.3.1: the v2.3.1 CRDs fail the CEL
  cost-budget check on Kubernetes 1.37 (this cluster), v2.3.11 passes.
- Fluent Bit's image is pulled from Docker Hub (`observability.sh`): the kind node's
  containerd rejects `cr.fluentbit.io`'s certificate chain (x509 unknown authority) although
  the same pull works from the Mac.
- When testing the CoreDNS rewrite from a pod, do not use `curl`: it resolves every
  `*.localhost` name to loopback itself and never asks DNS (connection refused, exit 7).
  `wget` (busybox), Go and Node use the resolver and get the gateway Service.
- `console.sh` builds on Docker Desktop when `BUILD_DOCKER_CONTEXT=desktop-linux` is set
  (more RAM and the layer cache) and streams the image into Colima. Docker Desktop's buildx
  occasionally answers `failed to list workers: EOF`; re-run the build. `console.sh values`
  refuses to point at a tag that is not in the registry.
- `colima start` switches the active docker context to `colima`; the kind node, the
  `kind-registry` and the socat forwarder all live there.
- The platform is a laptop setup: plain HTTP, dev-mode OpenBao, demo users. Not for
  anything exposed beyond your machine.
- Verified on kind v0.33 / Kubernetes v1.37 / Colima, 2026-10-20 (planes) and 2026-10-31
  (fork console image, observability plane).

## Versions

Every chart and image version is pinned in `env.sh` (`*_VERSION`, `OPENCHOREO_REF`,
`SOCAT_IMAGE`); there is no second hand-written copy. They match the AKS values under
`gitops/platform/openchoreo-*` (same 1.3.1 charts); bump both together.
