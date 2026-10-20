# ADR 0002: Per-cloud modules behind a common interface, not cloud-agnostic HCL

Date: 2026-10-20
Status: Accepted

## Context

The repo must support Azure first, then AWS and GCP. HCL has no good way to write a single
module that provisions a managed Kubernetes cluster on three clouds; attempts to do so end up
as giant conditionals that are harder to read than three honest modules.

## Decision

1. **One module per cloud per concern**, e.g. `modules/azure/aks`, later `modules/aws/eks` and
   `modules/gcp/gke`. Each exposes the *same conceptual inputs and outputs*:
   - inputs: `name`, `location`/region, `kubernetes_version`, `system_node_pool`,
     `user_node_pools`, `tags`
   - outputs: `cluster_name`, `cluster_endpoint`, `cluster_ca_certificate`,
     `oidc_issuer_url`, plus credentials the next layer needs
2. **The cloud-agnostic layer starts at the Kubernetes API.** `modules/k8s/*` only use the
   `helm` provider, so they are identical on every cloud.
3. **Stacks are small and layered** under `live/<cloud>/<env>/NN-<name>/`, each with its own
   state file. Apply order is by number prefix. Stacks reference each other by naming
   convention and data sources rather than `terraform_remote_state`, which keeps each stack
   independently plannable.

## Consequences

- Adding a cloud = new modules + new `live/<cloud>/poc/*` stacks. Nothing in `modules/k8s`
  or `gitops/` changes.
- Some duplication between cloud modules is accepted on purpose.
- Naming conventions matter; they are documented in each module README.
