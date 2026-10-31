# ADR 0017: AI skills in the catalog, served to agents over MCP

Date: 2026-10-25
Status: Accepted (2026-10-30). Steps 1-4 live since PR #29: 31 Skill entities and the System in the
catalog; the MCP server verified through the ingress with the official client (8 tools, 31
prompts, 61 resources). Step 5 (Thunder OAuth) landed 2026-10-30.

## Context

`eiriksf-capgemini/common-ai` (public) holds 25 Claude Code skills (`skills/<name>/SKILL.md`
with frontmatter `name`, `description`, `license`, `metadata.domain`, `metadata.tags`, plus a
`metadata.json` with `description`, `domain`, `tags`, `examples`, sometimes `references`),
4 agents, hooks and prompts. The ask: list them in the console catalog and make them
available to Claude Code through an MCP server, and the question whether putting the catalog
behind MCP is worth it.

Facts (verified 2026-10-25):

1. **Claude Code cannot load skills or agents from an MCP server.** MCP gives it tools,
   resources and prompts; skills and subagents are read from the filesystem and from plugins
   only (`common-ai/docs/PLAN-claude-code-distribution.md`). An MCP prompt built from a
   SKILL.md does land the skill's text in the session as `/mcp__<server>__<skill>`, but it
   does not auto-trigger on the description and bundled files need to be served as
   resources. Installation stays the plugin marketplace's job.
2. **OpenChoreo already runs an MCP server.** `openchoreo-api` serves `/mcp` with OAuth
   against Thunder (RFC 9728 protected-resource metadata at
   `/.well-known/oauth-protected-resource`, verified live) and the toolsets namespace,
   project, component, deployment, build, pe, resource. Everything that is an OpenChoreo
   object is already reachable by an agent; what is not is what only the Backstage catalog
   knows: Azure resources (ADR 0015), cost (ADR 0016), the skills, ownership and relations
   across them, and free-text search.
3. **The catalog can hold custom kinds.** The OpenChoreo module emits kinds such as
   `ClusterDataplane` and `ClusterComponentType` through its provider, the Azure resources
   land as `Resource`, and the portal's kind picker lists whatever kinds exist. A new kind
   needs an entity page in the portal to be useful; `Resource` with a type renders today.
4. **Adding a catalog location through config is not possible** (ADR 0015, Backstage array
   semantics), so ingestion is again an entity provider.
5. The portal's Backstage backend already authenticates service-to-service and has the
   catalog in-process; the AI usage plugin shows a bearer-token endpoint pattern
   (`Secret/ai-usage-ingest`, ADR 0014).

## Decision

1. **A provider for AI elements, `catalog-backend-module-ai-elements`**, in the fork. It reads
   any number of Git repositories (`aiElements.repositories[]`: URL, ref, display name,
   owner; `common-ai` first, company-wide or per-team repos later) with the Backstage URL
   reader (`readTree`; public repos need no token, private ones use the portal's GitHub
   integration token from Key Vault), parses `skills/*/SKILL.md` frontmatter plus
   `metadata.json`, `agents/*/<name>.md`, `prompts/*.prompt.md` and `hooks/*/*.hook.json`,
   and emits entities every 30 minutes as a full mutation.
   Kind: **`Skill`** (`apiVersion: ai.openchoreo.dev/v1alpha1`, `spec.type: skill | agent |
   prompt | hook`, `spec.domain`, `spec.license`, `spec.examples`, `spec.references`,
   `spec.installCommand`, `spec.body` holding the markdown, `spec.system` = the repo) if
   step 0 confirms the catalog accepts a new kind from a provider as it does for
   OpenChoreo's; otherwise `Resource` with `spec.type: ai-skill` and the same fields under
   annotations. Namespace `ai`, owner `openchoreo-users`.
   **No `catalog-info.yaml` per skill in the source repos**: the SKILL.md frontmatter and
   `metadata.json` are the source of truth, skill authors should not need Backstage's entity
   format, and the portal could not consume a location anyway (ADR 0015 facts 1 and 2). The
   provider emits one **System** per repository (name, owner, description, links) that every
   element points at through `spec.system`; a root-level `catalog-info.yaml` in a repo may
   override that System's metadata, nothing else.
2. **A portal page for the kind**: list with domain/tag filters and a detail page rendering
   the SKILL.md, the examples, the install command (`/plugin install <pack>@common-ai`) and
   the source link. Minimal, in `packages/portal-app`.
3. **An MCP server inside the Backstage backend**, `openchoreo-ai-elements-backend`, exposing
   Streamable HTTP MCP at `/api/openchoreo-ai-elements/mcp` with the official TypeScript SDK:
   - tools, in order of value to an agent working on this platform:
     `platform_facts()` (cluster, ingress IP and domain, registry, namespaces and quotas,
     private CA: what `gitops-app-deploy` rediscovers by hand every run),
     `search_catalog(query, kind?)` and `get_entity(ref)` with relations,
     `azure_cost(scope)` and `azure_resources(type?, resourceGroup?)` (ADR 0015/0016),
     `list_skills(type?, domain?, tag?)` and `get_skill(name)` with the install command,
     `ai_usage()` (ADR 0014), `list_templates()` (scaffolder);
     deliberately **no** OpenChoreo object tools, which `openchoreo-api`'s `/mcp` already
     provides;
   - the cloud-infra ADR index and runbooks as MCP **resources**, so an agent reads the
     house conventions instead of guessing;
   - one MCP **prompt** per skill and agent (name = skill name, text = SKILL.md body) so
     `/mcp__platform__<skill>` pulls a skill into a session on demand; bundled reference
     files as MCP **resources**.
   Auth: a bearer token generated in-cluster (`Secret/ai-elements-mcp`, External Secrets
   `Password` generator, as ADR 0014) for non-interactive clients, and Thunder OAuth with the
   same protected-resource metadata as `openchoreo-api` for interactive ones, so one login
   covers both servers. Reached through the existing console ingress and private CA.
4. **Claude Code configuration**: two servers, `openchoreo` (`/mcp` on the API, OAuth) and
   `platform` (the Backstage one); shipped in the `common-ai-platform` plugin's `.mcp.json`
   so installing the pack configures them.

## Is the catalog behind MCP worth it?

Yes, narrowly. The value is in what only the catalog knows and in the join: an agent asked
"what does the registry cost and who owns the cluster it serves" needs Azure resources, cost
and relations in one answer, which no `kubectl`/`az` call gives and `openchoreo-api`'s MCP
does not model. For OpenChoreo objects themselves the answer is no: that server exists and
duplicating its toolsets would create two sources of truth. So the Backstage MCP server is
scoped to Azure resources, cost, skills and cross-entity search, and nothing else.

Two caveats. First, MCP is discovery and on-demand content for skills, not installation; the
marketplace plan in `common-ai` stays. Second, an MCP server is a second credential surface on
the console; the bearer-token phase is acceptable only behind the ADR 0009 allowlist, and
Thunder OAuth should follow before any wider audience.

## Alternatives considered

- **Add a "skills" or "catalog" toolset to `openchoreo-api`'s Go MCP server**: one server,
  one login, but it means a second fork (the API image, rebuilt per OpenChoreo release), the
  server registers tools only (no prompts or resources; `pkg/mcp/tools`, verified 2026-10-25),
  every toolset is wired into OpenChoreo's authorization model, and the Go code would have
  to call Git or Backstage, reversing the dependency. Worth an upstream proposal for a
  generic "prompts from a Git repository" toolset, on a separate track.
- **Standalone MCP service on the cluster** (TypeScript, deployed with `gitops-app-deploy`):
  decoupled from the fork, but it needs a catalog service token, its own ingress and image,
  and duplicates auth that the backend plugin gets from Backstage.
- **GitHub discovery provider + `catalog-info.yaml` per skill in `common-ai`**: forces the
  skills repo to carry Backstage files and still needs a module we do not ship.

## Consequences

- Two more plugins in the fork (provider, MCP backend) and a small frontend page.
- The SKILL.md bodies live in the catalog (`spec.body`); 26 skills are a few hundred KB,
  fine for SQLite. Search indexes them.
- A new kind needs a processor that validates it (learned in step 0); the same will hold
  for any further custom kind.
- The console gains an agent-facing API; audit it like the AI usage ingest (token in a
  Secret, rotated by deleting it).

## Plan

| # | Step | Where | Done when |
|---|---|---|---|
| 0 | Prove a custom kind from a provider passes the catalog rules in the dev backend (emit one `Skill`; else fall back to `Resource`/`ai-skill`) | fork, dev backend | Done 2026-10-25: the rules are not the obstacle; Backstage rejects a kind no processor validates (`No processor recognized the entity`). A `SkillEntityProcessor` (validate + ownedBy/partOf relations) makes `Skill` a first-class kind; no fallback needed |
| 1 | `catalog-backend-module-ai-elements`: URL reader tree read, frontmatter parser, entity mapping, tests on a fixture copy of three skills; run against `common-ai` | fork | Done 2026-10-25 (fork commit after 37a26354): 31 `Skill` entities (26 skills, 4 agents, 1 hook) plus `system:ai/common-ai` with 31 hasPart relations, read from GitHub without a token; 13 tests |
| 2 | Portal page for the kind (list + detail) | fork | Done 2026-10-26 (fork commit d92fba25): "AI" kind category and icon, Type column, overview cards (rendered definition with source link; type/domain/license, install command, agent tools, hook events, bundled files; example prompts). 4 component tests |
| 3 | `openchoreo-ai-elements-backend`: MCP Streamable HTTP, tools, per-skill prompts, bearer token; test with `claude mcp add --transport http` locally | fork | Done 2026-10-26 (fork commit after d92fba25): 8 tools (platform_facts, search_catalog, get_entity, list_skills, get_skill, azure_resources, list_templates, azure_cost), 31 prompts, docs and skill files as resources; verified with the official MCP client against a dev backend reading the live repos; 13 tests |
| 4 | `Secret/ai-elements-mcp` generator, values (`aiElements`, token env), image, PR; `.mcp.json` in the `common-ai-platform` pack | this repo, common-ai | In this PR: generator + ExternalSecret, `AI_ELEMENTS_MCP_TOKEN`, `aiElements.mcp` with platform facts and two docs sources; common-ai gets a root `.mcp.json` (both servers, token from `PLATFORM_MCP_TOKEN`) since the packs do not exist yet |
| 5 | Thunder OAuth for the Backstage MCP endpoint | fork, Thunder client | Done 2026-10-30: the plugin verifies Thunder JWTs (JWKS, issuer, expiry; audience optional) next to the shared token, serves RFC 9728 metadata and the `WWW-Authenticate` challenge. Thunder advertises PKCE and dynamic client registration, which Claude Code's flow uses. Verified with a client-credentials token from the portal's service client; the interactive browser flow is verified by the operator on first connect |
