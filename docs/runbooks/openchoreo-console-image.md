# OpenChoreo console image (AI usage widget, Azure resources and cost, AI skills)

Status as of 2026-10-25. Decisions in ADR 0013 (forked image), ADR 0014 (telemetry data
source) and ADR 0015 (Azure resources in the catalog); this page is how to run, configure and
rebuild it.

## What runs

| Piece | Source | Deployed by |
|---|---|---|
| Console image `openchoreo-ui:1.3.1-ai-usage.<sha>` | fork of `openchoreo/backstage-plugins`, branch `feat/ai-usage-home-widget` (off tag `v1.3.1`) | `backstage.image` in `gitops/platform/openchoreo-control-plane/values.yaml` |
| Ingest token (ADR 0014) | generated in-cluster: `Password/ai-usage-ingest-token` → `Secret/ai-usage-ingest` | `gitops/platform/openchoreo-secrets/externalsecret-ai-usage-ingest.yaml` → env `AI_USAGE_INGEST_TOKEN` |
| Identity mapping | Key Vault `anthropic-member-email` (ADR 0013) | `ExternalSecret/anthropic-admin` → env `ANTHROPIC_MEMBER_EMAIL` → `openchoreo.aiUsage.users` |
| Feature flag + source | `OPENCHOREO_FEATURES_AI_USAGE_ENABLED=true`, `openchoreo.aiUsage.source: telemetry` | `backstage.extraEnv` / `backstage.appConfig` in the same values file |

The fork is a local checkout (`~/code/openchoreo-backstage-plugins`) until it is pushed; the
intended home is `github.com/eiriksf-capgemini/openchoreo-backstage-plugins`. The image tag
embeds the fork's short commit SHA, so a tag always names a reproducible source.

## Configure a reporter (each laptop, once)

```sh
TOKEN=$(kubectl -n openchoreo-control-plane get secret ai-usage-ingest -o jsonpath='{.data.token}' | base64 -d)
kubectl -n cert-manager get secret poc-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > ~/.config/poc-root-ca.crt
```

Then in `~/.claude/settings.json` (`env` block) or the shell:

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_METRICS_EXPORTER": "none",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/json",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "https://console.openchoreo.20.91.237.179.nip.io/api/openchoreo-ai-usage",
    "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Bearer <TOKEN>",
    "OTEL_RESOURCE_ATTRIBUTES": "enduser.id=<your e-mail, the one in Key Vault>,api_key.name=<a name for this key>",
    "NODE_EXTRA_CA_CERTS": "/Users/<you>/.config/poc-root-ca.crt"
  }
}
```

`enduser.id` is what ties API-key sessions to you (OAuth sessions carry `user.email` by
themselves); `api_key.name` fills the "My API key tokens" row. Only `http/json` is accepted.
Exports go out every 5 s while Claude Code runs; the home page shows them from the next
full UTC day on ("last day" = yesterday). The cluster must be running for exports to land;
Claude Code drops batches it cannot deliver, it does not queue them.

Smoke test without Claude Code:

```sh
curl -s --cacert ~/.config/poc-root-ca.crt -X POST \
  https://console.openchoreo.20.91.237.179.nip.io/api/openchoreo-ai-usage/v1/logs \
  -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' -d '{"resourceLogs":[]}'
# {"partialSuccess":{}}   (401 = wrong token; 404 = source not telemetry or image too old)
```

## Rotate or recover the token

`kubectl -n openchoreo-control-plane delete secret ai-usage-ingest` → External Secrets
recreates it with a new value within a minute; `kubectl rollout restart deployment backstage`
so the backend reads it; reconfigure every reporter. A cluster recreate does the same
implicitly.

## Rebuild the image (chart bump or widget change)

```sh
cd ~/code/openchoreo-backstage-plugins
git fetch origin && git rebase v<new chart version>          # only on a chart bump
nvm use 22 && yarn install && yarn tsc && yarn test          # isolated-vm needs Node 22
git status --short                                           # must be empty: the tag embeds HEAD
TAG="<chart version>-ai-usage.$(git rev-parse --short=8 HEAD)"
IMAGE="acrmadbadgerbadger.azurecr.io/openchoreo-ui:$TAG"
docker buildx build . -f packages/backend/Dockerfile --platform linux/amd64 --tag "$IMAGE" --load
az acr login --name acrmadbadgerbadger && docker push "$IMAGE"
az acr repository show-tags --name acrmadbadgerbadger --repository openchoreo-ui -o table
```

The node is x86, so `--platform linux/amd64` is mandatory; on Apple silicon the build runs
under emulation (enable Rosetta in Docker Desktop, QEMU is several times slower) and takes
well over an hour because `isolated-vm` compiles from source. `az acr build` is not available:
ACR Tasks are not permitted on the Free Trial subscription (ADR 0013). The Dockerfile's
build stage sets `NODE_OPTIONS=--max-old-space-size=4096`; give the Docker VM at least 8 GB.

Then change `backstage.image.tag` (and `chartVersion` in `gitops/clusters/azure-dev/values.yaml`
on a bump) in a PR. A merged PR is the deployment; Argo CD rolls the Backstage Deployment.

## Azure resources in the catalog (ADR 0015)

The same image carries `catalog-backend-module-azure-resources`. It is driven by
`backstage.appConfig.azureResources` in the values file (subscriptions, resource groups,
`types`, `dataPlanes`) and authenticates over IMDS with the kubelet identity, which
`live/azure/poc/20-cluster` grants `Reader` on both resource groups
(`catalog_reader_enabled`). Apply that stack before or after the image rolls; until the role
exists the provider logs `query failed: 403` every 10 minutes and keeps the catalog as it is.

```sh
kubectl -n openchoreo-control-plane logs deploy/backstage | grep AzureResourceGraph   # "registered", then "applied N entities"
az role assignment list --all --assignee $(az aks show -g rg-cloudinfra-poc -n aks-cloudinfra-poc --query identityProfile.kubeletidentity.objectId -o tsv) -o table
```

In the console, Catalog → kind **Resource** → namespace `azure`; the AKS cluster's page has
the Azure portal link and a relation to the data plane `default`. Widen `types` to `['*']`
for the whole resource groups (23 resources as of 2026-10-25).

## Azure cost in Cost Insights (ADR 0016)

The image also carries `openchoreo-azure-cost-backend` and the Cost Insights **Azure** tab.
Scope is `azureResources.subscriptions`; the identity needs **Cost Management Reader** on
the subscription (`kubelet_cost_reader` in `live/azure/poc/20-cluster`, same
`catalog_reader_enabled` switch). One Cost Management query and one forecast call per hour;
Azure throttles after a few calls a minute, so do not lower `azureResources.cost.cacheTtlSeconds`
much. Until the role exists the tab shows the backend's error (502 `AuthorizationFailed`).

```sh
kubectl -n openchoreo-control-plane logs deploy/backstage | grep -i "azure cost"   # "initialized", then "snapshot: N rows"
```

Console → Cost Insights → **Azure**: month to date, 30-day window, projection, resource groups
and resources (names link to the catalog entities). Each Azure `Resource` entity page has an
"Azure cost" card. Amounts are in the subscription's billing currency (NOK here), not USD.

## AI skills in the catalog (ADR 0017)

The image carries `catalog-backend-module-ai-elements`: every repository under
`backstage.appConfig.aiElements.repositories` is read every 30 minutes (Backstage URL
reader; public repositories need no token, private ones need `integrations.github[].token`
from Key Vault) and its `skills/`, `agents/`, `prompts/` and `hooks/` become `Skill` entities
in namespace `ai`, plus one `System` per repository. Catalog → kind **AI Skill**; each page
shows the rendered definition, the install command, bundled files and example prompts.

```sh
kubectl -n openchoreo-control-plane logs deploy/backstage | grep AiElements   # "registered", then "applied N entities"
```

## Check

```sh
kubectl -n platform get application openchoreo-control-plane openchoreo-secrets     # Synced / Healthy
kubectl -n openchoreo-control-plane get externalsecret ai-usage-ingest anthropic-admin  # SecretSynced
kubectl -n openchoreo-control-plane get deploy backstage -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl -n openchoreo-control-plane logs deploy/backstage | grep -i "ai usage"       # "OTLP ingest enabled", "initialized (source: telemetry)"
kubectl -n openchoreo-control-plane logs deploy/backstage | grep "ai-usage/v1/logs"  # 200s from reporters
```

On the home page the card "AI usage & cost" appears in the default layout; existing users
who customised their home layout add it with **Edit → Add widget**.

## Optional: Anthropic Admin API source

If an Admin API key (or a personal key not scoped to a workspace) becomes available, store
it in Key Vault as `anthropic-admin-api-key` (from an allowlisted egress, ADR 0009) and set
`openchoreo.aiUsage.source: anthropic` in the values file; the widget then shows the
organization's billed cost and per-key usage from Anthropic instead.

## Clean up

Superseded tags cost registry storage: `az acr repository delete --name acrmadbadgerbadger --image openchoreo-ui:<old tag>`.
