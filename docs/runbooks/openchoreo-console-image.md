# OpenChoreo console image (AI usage widget)

Status as of 2026-10-23. Decision in ADR 0013; this page is how to (re)build the image the
control plane runs.

## What runs

| Piece | Source | Deployed by |
|---|---|---|
| Console image `openchoreo-ui:1.3.1-ai-usage.<sha>` | fork of `openchoreo/backstage-plugins`, branch `feat/ai-usage-home-widget` (off tag `v1.3.1`) | `backstage.image` in `gitops/platform/openchoreo-control-plane/values.yaml` |
| Anthropic credentials | Key Vault `kv-cloudinfra-poc`: `anthropic-admin-api-key`, `anthropic-member-email` | `ExternalSecret/anthropic-admin` (`gitops/platform/openchoreo-secrets`) → env vars via `backstage.extraEnv` |
| Feature flag | `OPENCHOREO_FEATURES_AI_USAGE_ENABLED=true` in `backstage.extraEnv` | same values file |

The fork is a local checkout (`~/code/openchoreo-backstage-plugins`) until it is pushed; the
intended home is `github.com/eiriksf-capgemini/openchoreo-backstage-plugins`. The image tag
embeds the fork's short commit SHA, so a tag always names a reproducible source.

## Secrets (once, from an allowlisted egress; ADR 0009)

```sh
az keyvault secret set --vault-name kv-cloudinfra-poc --name anthropic-admin-api-key --value 'sk-ant-admin...'   # Admin API key from the Claude Console
az keyvault secret set --vault-name kv-cloudinfra-poc --name anthropic-member-email  --value 'you@example.com'  # the Anthropic member all portal users map to
kubectl -n openchoreo-control-plane get externalsecret anthropic-admin                                         # SecretSynced within 1h, or annotate force-sync
kubectl -n openchoreo-control-plane rollout restart deployment backstage                                       # env vars are read at start
```

Without the secrets the portal runs and the widget shows "AI usage is not configured".

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

## Check

```sh
kubectl -n platform get application openchoreo-control-plane openchoreo-secrets     # Synced / Healthy
kubectl -n openchoreo-control-plane get deploy backstage -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl -n openchoreo-control-plane logs deploy/backstage | grep -i "ai usage"       # "plugin initialized"
curl -s --cacert poc-root-ca.crt https://console.openchoreo.20.91.237.179.nip.io/api/openchoreo-ai-usage/summary   # 401 without a login: the route exists
```

On the home page the card "AI usage & cost" appears in the default layout; existing users
who customised their home layout add it with **Edit → Add widget**.

## Clean up

Superseded tags cost registry storage: `az acr repository delete --name acrmadbadgerbadger --image openchoreo-ui:<old tag>`.
