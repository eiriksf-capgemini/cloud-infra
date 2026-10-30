# ADR 0015: Azure resources in the OpenChoreo catalog through an entity provider (AKS first)

Date: 2026-10-25
Status: Proposed

## Context

The OpenChoreo console's catalog is fed by two things only: the `OpenChoreoEntityProvider`
(every OpenChoreo CR: project types, component types, environments, the data plane, the
sample resource types) and a fixed list of `type: file` locations baked into the image
(the `openchoreo-users` group and the fifteen "create-*" scaffolder templates). Nothing from
the Azure side is in it. The AKS cluster `aks-cloudinfra-poc` exists only indirectly as
`clusterdataplane:openchoreo-cluster/default`; the registry, Key Vault, VNet, public IP,
Monitor workspace and Automation account (everything OpenTofu creates in `rg-cloudinfra-poc`)
are invisible to portal users. The ask is automatic ingestion of those Azure resources, with
the AKS cluster first.

Facts that constrain the design (verified 2026-10-25 against the running cluster, the chart
values for 1.3.1 and the fork):

1. **Config cannot append a location.** `backstage.appConfig` is rendered to
   `app-config.extra.yaml`, but Backstage replaces arrays between config files, so a
   `catalog.locations` entry there would drop the image's fifteen file locations unless the
   whole list is repeated. That list is version-specific. There is no `catalog.providers`
   entry for plain URLs, and the portal backend bundles no GitHub or Kubernetes discovery
   module.
2. **Nothing registered at runtime survives a restart.** The portal's SQLite files live on an
   `emptyDir` (`backstage-db`), so a location registered through the catalog API (or the
   "Register existing component" page) disappears with the pod. The same volume holds the
   AI usage rows of ADR 0014; see Consequences.
3. **There is no off-the-shelf provider.** `@backstage/plugin-catalog-backend-module-azure`
   discovers `catalog-info.yaml` in Azure DevOps repositories, not cloud resources.
   `@vippsno/plugin-azure-resources-backend` wraps Resource Graph queries for entity cards
   and does not ingest anything.
4. **Pods already reach Azure through the kubelet identity** (ADR 0011: External Secrets
   authenticates to Key Vault with `authType: ManagedIdentity` over IMDS; the identity is
   `aks-cloudinfra-poc-agentpool`, holding AcrPull and Key Vault Secrets User). The cluster
   has its OIDC issuer on and the `workload_identity_enabled` flag in `20-cluster`, currently
   off.
5. **We already own a console image pipeline** (ADR 0013: fork of
   `openchoreo/backstage-plugins`, image `openchoreo-ui:1.3.1-ai-usage.<sha>` in ACR,
   runbook `docs/runbooks/openchoreo-console-image.md`). Adding a backend module is the same
   motion as the AI usage plugin. Backstage in the fork is 1.51.
6. `Microsoft.ResourceGraph` is registered on the subscription, and the catalog rules already
   allow the `Resource` kind.

## Decision

1. **A catalog entity provider in the fork, not a location.** New backend module
   `plugins/catalog-backend-module-azure-resources` with an `AzureResourceGraphEntityProvider`
   registered in `packages/portal-backend/src/features.ts`. On a schedule (default every
   10 minutes) it runs one Azure Resource Graph query over the configured subscriptions and
   resource groups and applies a **full** mutation, so resources deleted in Azure leave the
   catalog on the next run. It self-disables when `azureResources` is absent from config,
   like the portal-assistant backend.
2. **Resources become Backstage `Resource` entities** in the catalog namespace `azure`
   (no collision with OpenChoreo names), owned by `openchoreo.defaultOwner`
   (`openchoreo-users`). `spec.type` is derived from the Azure type:
   `Microsoft.ContainerService/managedClusters` → `kubernetes-cluster`,
   `Microsoft.ContainerRegistry/registries` → `container-registry`,
   `Microsoft.KeyVault/vaults` → `key-vault`, `Microsoft.Network/virtualNetworks` →
   `virtual-network`, `Microsoft.Monitor/accounts` → `monitoring-workspace`, anything else →
   the lowercased last path segment. Annotations: `azure.com/resource-id`,
   `azure.com/subscription-id`, `azure.com/resource-group`, `azure.com/location`,
   `backstage.io/view-url` (the Azure portal page for the resource), and Azure tags as
   labels after sanitising. AKS entities additionally get `kubernetes.io/api-server` and
   `kubernetes.io/auth-provider: aks` (the Kubernetes plugin's convention, should it ever be
   added) and a `dependencyOf` relation to the OpenChoreo data plane named in config
   (`azureResources.dataPlanes: [{cluster: aks-cloudinfra-poc, dataPlane: default}]`), so the
   cluster page links to `clusterdataplane:openchoreo-cluster/default` and back.
3. **Scope grows in two steps.** Step one ingests `managedClusters` only (the priority);
   step two opens the type list to everything in `rg-cloudinfra-poc` and the nodes group.
   Both are config (`azureResources.types`), not code.
4. **Identity: kubelet identity first, workload identity later.** The module authenticates
   with `DefaultAzureCredential` (`@azure/identity`), which resolves to the Azure CLI on a
   laptop and to IMDS on the node. `20-cluster` grants the kubelet identity the built-in
   `Reader` role on `rg-cloudinfra-poc` and on the nodes resource group, the same pattern
   ADR 0011 uses for Key Vault. When a second consumer needs Azure, or before anything beyond
   the POC, flip `workload_identity_enabled`, create a user-assigned identity with a
   federated credential for `openchoreo-control-plane/openchoreo-backstage`, and set
   `backstage.serviceAccount.annotations` (`azure.workload.identity/client-id`); the module
   needs no change because `DefaultAzureCredential` handles both.
5. **Configuration lives in `gitops/platform/openchoreo-control-plane/values.yaml`** under
   `backstage.appConfig.azureResources` (subscription ids, resource groups, types, schedule,
   data-plane mapping). No secrets: identity is the managed identity.

## Alternatives considered

- **Static `catalog-info.yaml` in this repo plus a `catalog.locations` override.** Gets the
  AKS cluster into the catalog in an hour, but is hand-maintained (not "automatic"), and the
  override must mirror the image's location list on every upgrade. Acceptable as a stop-gap
  for a demo, not as the mechanism.
- **CronJob renders entity YAML into Git or a ConfigMap, catalog reads a URL/file location.**
  Two moving parts, still needs the location override above, and a Git-writing job needs the
  GitHub App credential in the cluster.
- **Model Azure resources as OpenChoreo `Resource`/`ResourceType`.** A ResourceType must emit
  data-plane manifests and a Resource must belong to a Project; the model is for provisioned,
  project-scoped resources (postgres, valkey), not shared pre-existing infrastructure.
  Revisit if OpenChoreo adds external resources.
- **Backstage Kubernetes plugin with catalog cluster discovery.** Not installed in the portal;
  adds a plugin, a cluster credential and the 2026 advisory about catalog-driven cluster
  auth. Out of scope; the `kubernetes.io/*` annotations above keep the door open.

## Consequences

- One more plugin in the fork and an image rebuild per change (runbook). The module is
  generic (any subscription, no OpenChoreo dependency beyond the optional data-plane link) so
  it can be proposed upstream.
- The kubelet identity can read resource metadata for the two resource groups, from any pod on
  the node. ADR 0011 already accepts this exposure for secrets, which is far more sensitive;
  workload identity (decision 4) removes it.
- Resource Graph allows 15 requests per 5 seconds per tenant; one query every 10 minutes is
  negligible. The query is free.
- After a pod restart the provider repopulates within one cycle, so the `emptyDir` is not a
  problem for this feature. It **is** a problem for ADR 0014: AI usage rows are lost on every
  restart (the pod was recreated today). Give `backstage-db` a PVC (`managed-csi`) in a
  follow-up; the chart's `extraVolumes`/`extraVolumeMounts` cannot replace a named volume,
  so this needs a chart value or a kustomize patch on the Application.

## Plan

| # | Step | Where | Done when |
|---|---|---|---|
| 0 | Prove the query and the mapping from a laptop: `az graph query -q "resources \| where resourceGroup in~ ('rg-cloudinfra-poc', 'rg-cloudinfra-poc-aks-cloudinfra-poc-nodes') \| project id, name, type, location, tags, properties.oidcIssuerProfile.issuerURL"` | shell | Done 2026-10-25: 23 rows (16 in the main group, 7 in the nodes group: disks, scale set, load balancer, NSG, public IP, kubelet identity). Resource Graph lowercases `type`; the mapping compares case-insensitively |
| 1 | Scaffold `catalog-backend-module-azure-resources` (`yarn new` → backend-module), implement provider + Resource Graph client + unit tests on a recorded response, `config.d.ts` schema, register in `features.ts`, run the portal locally with `az login` credentials | fork `~/code/openchoreo-backstage-plugins`, branch off `feat/ai-usage-home-widget` | Done 2026-10-25: module `plugins/catalog-backend-module-azure-resources` (fork commit on `feat/ai-usage-home-widget`), 16 unit tests; a dev backend with Azure CLI credentials produced `resource:azure/aks-cloudinfra-poc` with the Kubernetes annotations, portal link and `dependencyOf` → `clusterdataplane:openchoreo-cluster/default`; with `types: ['*']` all 23 resources processed without catalog errors. Verified through the catalog API, not yet in the portal UI |
| 2 | Grant `Reader` on `rg-cloudinfra-poc` and the nodes RG to the kubelet identity (`azurerm_role_assignment`, variable `catalog_reader_scopes` in `20-cluster`) | this repo, `live/azure/poc/20-cluster` | Code written 2026-10-25 (`catalog_reader_enabled`, two `azurerm_role_assignment`s); `tofu plan` shows exactly 2 to add for them. **Apply pending**: the full plan also carries unrelated drift (OS disk 32→64 GB, two missing API-server allowlist ranges) that would cycle the node, so apply with `tofu apply -target=azurerm_role_assignment.kubelet_reader` and settle the drift separately. The assignments resolve the kubelet identity and node group through data sources (naming convention), not `module.aks` outputs, so the target does not include the cluster resource; a first attempt that did so failed with `OperationNotAllowed` because the cluster was stopped (ADR 0004 schedule) |
| 3 | Build and push the amd64 image, bump `backstage.image.tag`, add `backstage.appConfig.azureResources` (types: managedClusters only), PR through the GitHub App | this repo, `gitops/platform/openchoreo-control-plane/values.yaml` | Argo CD synced; pod log shows the provider's "applied N entities" line |
| 4 | Verify on the console: the AKS cluster is in the catalog, portal link works, relation to the data plane in both directions, search finds it | console | Screenshot in the PR; status of this ADR set to Accepted |
| 5 | Open `azureResources.types` to the whole resource group; add the nodes RG; update the runbook with the new config block | this repo | All 23 resources visible; runbook updated |
| 6 | (Later) Workload identity: flip the flag, UAMI + federated credential, SA annotation; remove Reader from the kubelet identity | `20-cluster`, values | Provider logs show the UAMI client id; kubelet identity back to AcrPull + Key Vault only |
| 7 | (Separate, urgent for ADR 0014) PVC for `backstage-db` | chart value or kustomize patch | Done 2026-10-30: the chart has `backstage.database.sqlite.persistence.enabled`; 2 Gi Azure disk, default storage class. Rows written before the switch were already lost with the emptyDir |
