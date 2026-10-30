# ADR 0016: Azure subscription cost in the console's Cost Insights

Date: 2026-10-25
Status: Accepted (2026-10-30). Live on the console since PR #28; verified through the backend and the MCP
`azure_cost` tool (month to date 140 NOK on 2026-10-30). The Azure tab itself was checked by the
operator, not by the agent.

## Context

The console's **Cost Insights** page (`page:openchoreo-observability/cost-insights`) is
OpenChoreo's own FinOps view: namespace → project → component → environment, with CPU and
memory cost, efficiency and right-sizing recommendations, read from the observability plane's
observer API and the FinOps agent. On this cluster the observability plane is not installed
(ADR 0010), so the page shows "Cost Insights have not been enabled" and the summary card on
component pages is empty.

The ask is to show what the platform actually costs in Azure: the subscription, each resource
group and each resource, next to the resources ADR 0015 just put in the catalog.

Facts (verified 2026-10-25 from the operator's laptop):

1. **Azure Cost Management's query API works on this Free Trial subscription.**
   `POST /subscriptions/<id>/providers/Microsoft.CostManagement/query` returns actual cost
   grouped by `ResourceGroupName`, `ResourceId`, `ServiceName`, `ResourceType`, with `Daily`
   granularity and a 30-day window in one page (93 rows). Month to date: 55 NOK across three
   resource groups; the node pool scale set, the registry and the two public IPs lead. Rate
   limit headers show ~1100 requests remaining per window; the data refreshes about daily.
   The `forecast` endpoint works with `timeframe: Custom` over the calendar month and no
   grouping, but with six days of history it returns actual points only (or HTTP 424), so
   the plugin falls back to a linear projection until Azure has enough data. The API
   throttles after a handful of calls per minute (HTTP 429), which fixes the design: one
   query and one forecast call per hour, everything else derived.
2. **The identity story is already settled.** The console pod reaches Azure through the
   kubelet identity over IMDS (ADR 0015). Cost queries need the built-in
   **Cost Management Reader** role on the subscription (role id `72fafb9e-...`), one more
   `azurerm_role_assignment` in `20-cluster`.
3. **The page is extensible.** `CostInsightsPage` already has two tabs (Insights, Cost
   Analysis) and lazy-loads the heavy one; adding a tab is a local change in the fork's
   `openchoreo-observability` plugin. The Resource entity page has no cost card today.
4. **Resource groups are not entities.** ADR 0015 emits resources only; a per-group view
   needs either group entities or a grouping in the cost view.
5. The Backstage community `cost-insights` plugin exists (groups → projects → products with
   daily charts and a per-entity cost card) but would be a second cost page beside the
   OpenChoreo one, and the portal's sidebar is curated.

## Decision

1. **A small backend plugin, `openchoreo-azure-cost-backend`**, in the fork. It wraps the Cost
   Management query API with the same `DefaultAzureCredential`, serves
   `GET /api/openchoreo-azure-cost/summary?from&to&granularity&groupBy=resourceGroup|resource|service`
   and `GET /api/openchoreo-azure-cost/resource?id=<resource id>&days=30`, caches responses
   for an hour in the Backstage cache (the data moves daily; the limit is per tenant), and
   returns amounts in the subscription's billing currency (NOK here) with the currency in the
   payload. Scope comes from `azureResources.subscriptions` (shared with ADR 0015).
2. **An "Azure" tab on the existing Cost Insights page**, in the fork's observability plugin:
   summary cards (month to date, last 30 days, projected month end once forecast works),
   a daily stacked chart by resource group, a resource-group table with drill-down, and a
   resource table (name, type, service, resource group, 30-day cost, trend vs the previous
   30 days) whose rows link to the catalog entity from ADR 0015. The tab renders whether or
   not the observability plane exists; the other tabs keep their current behaviour.
3. **A cost card on Azure Resource entities.** An `EntityCardBlueprint` shown when
   `azure.com/resource-id` is present: 30-day cost, daily sparkline, link to the Azure tab
   filtered to that resource.
4. **Resource groups become entities.** ADR 0015's provider also emits
   `resource:azure/<group>` with `spec.type: resource-group`; every resource in the group
   gets `dependsOn` → its group, so the group page lists its members and carries the same
   cost card at group scope. The subscription itself stays a filter, not an entity. With
   this the catalog's `types` filter opens to `['*']` (ADR 0015 step 5).
5. **Role:** `catalog_reader_enabled` in `20-cluster` also assigns **Cost Management Reader**
   at subscription scope to the kubelet identity (Workload ID later, as in ADR 0015).

## Alternatives considered

- **Community `@backstage-community/plugin-cost-insights`** with a `CostInsightsApi` fed by
  the same backend: more UI for free (alerts, products, team groups), but a parallel page,
  its own vocabulary (teams, billing projects) that does not match subscription/group/resource,
  and a sidebar entry the portal does not curate. Revisit if the Azure tab outgrows one page.
- **Azure cost exports to a storage account, read by the portal**: the documented path for
  heavy use, but another resource, daily batch latency, and parsing CSVs for a 50 NOK/month
  subscription.
- **Annotate entities with cost on each catalog sync**: makes cost searchable but stale by
  up to a sync interval and couples the provider to a second API; the card reads live data
  instead.

## Consequences

- One more plugin in the fork and a UI change in the observability plugin (both fork-local;
  the tab is upstreamable as "cloud cost" if the project wants it).
- Cost Management Reader on the subscription for the node identity: read-only billing data,
  readable from any pod on the node; same acceptance as ADR 0015 until Workload ID.
- Amounts are the billing currency, not USD; the AI usage widget (ADR 0014) shows USD. The
  tab labels the currency and does not sum across the two.

## Plan

| # | Step | Where | Done when |
|---|---|---|---|
| 0 | Confirm the forecast call shape and the per-resource daily query from a laptop; record the JSON shapes as test fixtures | shell | Done 2026-10-25: fixtures `query-daily-by-resource.json` (93 rows) and `forecast-month.json` in the plugin |
| 1 | Backend plugin: Cost Management client (REST + `DefaultAzureCredential`), two routes, cache, config schema, tests; run locally with Azure CLI credentials | fork | Done 2026-10-25: `openchoreo-azure-cost-backend`, 24 tests; `/snapshot` against the subscription returned 97 rows, 42 resources, 3 groups, 56.34 NOK; `/resource` for the registry 7.82 NOK |
| 2 | ADR 0015 provider: resource-group entities + `dependsOn` relations | fork | Done 2026-10-25 (fork commit 37a26354): groups from `resourcecontainers`, synthesized when that query fails |
| 3 | Azure tab + entity cost card in the observability plugin; unit tests on the aggregation; local portal run with the dev backend | fork | Done 2026-10-25: tab, charts, tables, card; 9 component tests (181 in the plugin). Not rendered in a full local portal (needs the OpenChoreo API and IDP); verified on the console in step 5 |
| 4 | `20-cluster`: Cost Management Reader for the kubelet identity (targeted apply, as in ADR 0015) | this repo | Code in `catalog_reader_enabled` (`kubelet_cost_reader`); `tofu plan -target=azurerm_role_assignment.kubelet_cost_reader` = 1 to add. **Apply pending** (operator) |
| 5 | Image build and push, values bump, PR, verify on the console | this repo | Done: PR #28 merged 2026-10-25; cost backend answers on the cluster via the kubelet identity (first call after a cold start can hit Cost Management's 429 and is served on retry) |
