# ADR 0006: One Basic container registry per organization, pulled via managed identity

Date: 2026-10-20
Status: Accepted

## Context

Workloads deployed through `gitops/apps` need somewhere to publish first-party images.
The environment is a Free Trial POC (ADR 0004), the cluster uses managed identities and
Entra ID everywhere, and ADR 0005 pins images per environment in kustomize overlays.

## Decision

1. **Azure Container Registry, Basic SKU.** `modules/azure/acr` + `live/azure/poc/25-registry`.
   Basic costs ~$5/month flat for 10 GB and cannot be stopped; it is the only standing
   cost added by this decision. Standard/Premium features (private link, geo-replication,
   retention policies, more throughput) are not needed for a POC.
2. **Name derived from the organization, not `name_prefix`.** ACR names are global DNS
   labels, so `acr-cloudinfra-poc`-style names are both invalid (no hyphens) and likely
   taken. The stack takes `organization` (default `madbadgerbadger`) and produces
   `acr<organization>.azurecr.io`. `registry_name` overrides it.
3. **One registry for all environments.** dev/test/prod differ by image tag or digest in
   the overlay (ADR 0005), not by registry. A later test/prod cluster only needs an
   `AcrPull` assignment, which is one more entry in `pull_principal_ids`.
4. **No admin user, no pull secrets.** The registry stack looks up `aks-<name_prefix>` and
   grants its **kubelet** managed identity `AcrPull` at registry scope. Humans use
   `az acr login`; a future CI identity gets `AcrPush` through `push_principal_ids`.
5. **Stack ordering.** `25-registry` sits between `20-cluster` and `30-gitops` because the
   role assignment depends on the cluster's identity, and the GitOps layer is the consumer.
   `grant_aks_pull = false` lets the registry exist without a cluster.

## Alternatives considered

- **GitHub Container Registry (ghcr.io)**: free for public images and already next to the
  repo; would avoid the $5/month. Rejected for now because the goal is to exercise the
  Azure-native path (managed identity pull, same subscription, future private endpoint).
  Still the right choice if cost matters more than that.
- **Registry inside `20-cluster`**: the cluster can be destroyed for long breaks (ADR 0004)
  while images should survive; separate state keeps them independent.
- **`attach-acr` / `azurerm_kubernetes_cluster` ACR integration**: it is the same AcrPull
  role assignment, just hidden; doing it explicitly keeps the module reusable for other
  principals.

## Consequences

- Image references are `acrmadbadgerbadger.azurecr.io/<repo>:<tag>`; pods on the POC
  cluster pull without secrets.
- The registry is public-endpoint only (Basic). Access still requires Entra ID auth.
- Destroying `25-registry` deletes all images. There is deliberately no `prevent_destroy`:
  ADR 0004 wants idle stacks to be destroyable with `make destroy`.
- While `20-cluster` is destroyed, `25-registry` can only be planned with
  `grant_aks_pull = false` (the cluster lookup fails otherwise). After the cluster is
  recreated, set it back to `true` and apply: the kubelet identity has a new object ID and
  the `AcrPull` assignment is replaced. Images are untouched throughout.
- `pull_principals` / `push_principals` default to `ServicePrincipal`; a human user or
  group needs `principal_type` set, or Azure rejects the assignment.
