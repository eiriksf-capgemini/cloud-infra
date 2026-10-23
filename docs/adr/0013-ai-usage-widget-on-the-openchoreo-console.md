# ADR 0013: an "AI usage & cost" widget on the OpenChoreo console, from a forked console image

Date: 2026-10-23
Status: Accepted

## Context

The portal (OpenChoreo's Backstage console, ADR 0010) should show on its home page what the
Anthropic usage costs: the organization's bill for the last day and the last week, and the
signed-in user's token consumption, both under their own account (Claude Code over OAuth)
and under the API keys they created.

OpenChoreo 1.3.1 has nothing for this. Its "Cost Insights" is infrastructure FinOps fed by the
observability plane, which the POC does not run (ADR 0010), and no OpenChoreo component
meters LLM tokens. The only source with per-member and per-key token counts is the
[Anthropic Usage and Cost Admin API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api):
`cost_report` (daily, organization-wide), `usage_report/messages` (filterable by
`account_ids[]` and `api_key_ids[]`), plus the member and API-key lists to resolve a portal
user to an Anthropic member. It needs an **Admin API key**; a regular key is rejected.

Two platform facts shape the design. The console image is upstream's `openchoreo-ui`, so new
UI needs a rebuilt image. And the portal users are Thunder's seeded demo accounts
(`admin@openchoreo.dev` and friends, ADR 0011), which are not Anthropic organization members,
so a catalog e-mail lookup alone would never match anyone.

## Decision

1. **The widget is upstream-shaped code in a fork of `openchoreo/backstage-plugins`**, branch
   `feat/ai-usage-home-widget` off tag `v1.3.1`: a new backend plugin
   (`plugins/openchoreo-ai-usage-backend`, one `GET /summary` endpoint, per-user cache) and a
   home page widget in `packages/portal-app`, behind the opt-in feature flag
   `openchoreo.features.aiUsage`. Written as a changeset-carrying contribution so it can be
   offered upstream; until then it is a fork the POC maintains.
2. **A console image per chart version, in the POC registry.** `backstage.image` in
   `gitops/platform/openchoreo-control-plane/values.yaml` points at
   `acrmadbadgerbadger.azurecr.io/openchoreo-ui:<chart version>-ai-usage.<fork sha>`, built
   for `linux/amd64` (the node is x86) with `docker buildx --platform linux/amd64` on the
   operator's laptop and pushed with an Entra ID login (ADR 0006). ACR Tasks would be the
   natural builder but the Free Trial subscription is not permitted to use them
   ("ACR Tasks requests for the registry ... are not permitted", 2026-10-23). Procedure:
   `docs/runbooks/openchoreo-console-image.md`. Everything else in the chart stays upstream.
3. **Credentials from Key Vault, nothing in Git** (ADR 0011 pattern). Two secrets set by hand
   with `az keyvault secret set`, never generated: `anthropic-admin-api-key` and
   `anthropic-member-email`. The `anthropic-admin` ExternalSecret
   (`gitops/platform/openchoreo-secrets`) delivers them; the chart's `backstage.extraEnv`
   exposes them as `ANTHROPIC_ADMIN_API_KEY` and `ANTHROPIC_MEMBER_EMAIL` with `optional: true`,
   so the portal starts, and the widget shows its setup notice, before the secrets exist.
4. **One Anthropic identity for all portal users, by environment substitution.** The plugin's
   `openchoreo.aiUsage.users` mapping is rendered through `backstage.appConfig` as
   `[{ email: ${ANTHROPIC_MEMBER_EMAIL} }]`: an entry without `entityRef` applies to everyone.
   The e-mail is personal data and this repo is public, hence Key Vault rather than YAML.
   When Thunder carries real users with real e-mails, drop the mapping and the catalog
   `User` entity e-mail resolves each person individually.

## Alternatives considered

- **OpenChoreo's own Cost Insights / observability plane**: infrastructure cost, no tokens,
  and far too heavy for the node (ADR 0010).
- **Claude Code's OpenTelemetry export into Azure Monitor**: per-session tokens but no
  billed cost, needs every laptop configured, and still no API-key usage.
- **Wait for upstream**: nothing on the roadmap; the fork is the way to propose it.
- **ACR Tasks** (`az acr build`): the preferred builder, blocked on this subscription; revisit
  when the subscription changes or CI with OIDC to Azure exists (README status).
- **Tekton on the cluster**: the pipelines do not exist yet (`docs/runbooks/tekton.md`) and a
  Backstage build needs more memory than the node has to spare.

## Consequences

- **A chart bump means an image rebuild**: rebase the fork on the new `vX.Y.Z` tag, build,
  change the tag in the values file. Until the widget is upstream, `openchoreo-control-plane`
  cannot be bumped by changing `chartVersion` alone (runbook).
- **The fork must be published** for the image to be rebuildable by someone else; it is a
  local checkout today (`docs/runbooks/openchoreo-console-image.md` says where it should go).
- **Builds are laptop builds under emulation** until ACR Tasks or CI is available: the tag's
  fork SHA is what makes them reproducible; always build from a clean, committed tree.
- **The Admin API key is powerful** (it can list members and keys for the whole Anthropic
  organization). The plugin only reads, caches five minutes, and the key is reachable only
  from the Backstage pod; rotate it in Key Vault, External Secrets follows within an hour.
- **Cost**: the Admin API is free; the ACR build is a few cents; the image adds ~1 GB to the
  registry's 10 GB included storage, so delete superseded tags.
- **Data semantics**: "last day" is the last complete UTC day and "last 7 days" the seven
  before today, because the Cost API is daily-bucketed; Claude Code usage on claude.ai
  subscription plans is not visible to the Console organization's Admin API.
