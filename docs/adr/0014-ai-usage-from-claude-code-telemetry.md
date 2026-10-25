# ADR 0014: AI usage from Claude Code telemetry, not the Anthropic Admin API

Date: 2026-10-25
Status: Accepted. Supersedes the data-source decision of ADR 0013 (the forked console image,
Key Vault for human-managed secrets and the e-mail mapping stand).

## Context

ADR 0013 fed the console's "AI usage & cost" widget from the Anthropic Usage and Cost
Admin API. That API accepts only an Admin API key, an `org:admin` OAuth token, or a
personal key not scoped to a workspace. The operator has no access to the Anthropic Console
of the organization that owns the key, so none of those can be obtained; the stored key is a
workspace key and every report endpoint answers `401 ... requires an Admin API key or an
organization-scoped API key` (verified 2026-10-23). The widget deployed fine and showed that
error.

What the operator does control is the client: Claude Code can export OpenTelemetry. Its
`claude_code.api_request` event carries, per API call, the model, Claude Code's estimated
cost, the four token counts, a server request id, and the signed-in e-mail for OAuth
sessions. API-key sessions carry no identity, but the OTel-standard `enduser.id` resource
attribute can be attached by the reporter, and any custom attribute (here `api_key.name`) is
copied onto every event.

## Decision

1. **The portal is the OTLP receiver.** The `openchoreo-ai-usage-backend` plugin (fork
   branch `feat/ai-usage-home-widget`) gains `POST /api/openchoreo-ai-usage/v1/logs`
   (OTLP/HTTP JSON; metrics and traces accepted and ignored), authenticated with a bearer
   token, storing one row per `api_request` event in Backstage's database (SQLite on the
   console's PVC here), de-duplicated on the request id, pruned after 90 days. The summary
   keeps its shape: "cost" becomes Claude Code's estimate summed over every reporter, "my
   tokens" the events whose owner (`user.email` or `enduser.id`) is the portal user's
   mapped e-mail, "my API key tokens" the subset tagged with `api_key.name`.
   `openchoreo.aiUsage.source: telemetry` selects it; the Anthropic source stays available.
2. **The ingest token is generated in the cluster**, not in Key Vault: an External Secrets
   `Password` generator with `refreshPolicy: CreatedOnce` writes
   `Secret/ai-usage-ingest` in `openchoreo-control-plane` (`gitops/platform/openchoreo-secrets`).
   It is a machine credential nobody needs to manage by hand; Key Vault stays the source
   for human-managed secrets (ADR 0011). Rotation = delete the Secret and reconfigure
   reporters. The Key Vault data plane is also unreachable from the operator's networks
   without a firewall exception (ADR 0009 notes), which made the Key Vault path the wrong
   place for a token the operator must read back anyway.
3. **Reporters are configured per laptop.** Claude Code exports to
   `https://console.openchoreo.<ip>.nip.io/api/openchoreo-ai-usage` through the existing
   ingress and private CA (`NODE_EXTRA_CA_CERTS`), with
   `OTEL_RESOURCE_ATTRIBUTES="enduser.id=<e-mail>,api_key.name=<name>"`. The e-mail is the
   one in Key Vault (`anthropic-member-email`, ADR 0013), which the mapping already applies
   to every portal user.

## Alternatives considered

- **Obtain an Admin API key**: not possible for this operator; the code path stays for
  organizations that have one.
- **OpenTelemetry Collector + Azure Monitor managed Prometheus** (ADR 0008): the
  collector is another deployment on a full node, the plugin would need Entra ID auth to the
  Monitor query API, and Claude Code's counters would have to be re-derived; the plugin as
  receiver is ~300 lines and needs nothing new on the cluster.
- **Parsing Claude Code's local transcripts** (`~/.claude/projects/**/*.jsonl`): laptop-only,
  cannot reach the portal.

## Consequences

- **Numbers are estimates and only for reporters.** No organization bill; anything not
  exporting telemetry (other people, scripts using the API key directly) is invisible. The
  widget says so ("Estimated cost", "Source: Claude Code telemetry").
- **The endpoint is reachable from the allowlisted networks only** (ADR 0009) and needs the
  token; a leaked token lets someone inject usage rows, nothing more.
- **Storage** grows by one row per API request (tens of KB per day per user); retention
  90 days; SQLite on the existing PVC.
- **Cluster recreate** regenerates the token; the runbook lists the reconfiguration step.
- **Image rebuild** required (new fork commit); tag convention unchanged.
