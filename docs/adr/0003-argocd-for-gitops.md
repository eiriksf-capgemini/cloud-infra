# ADR 0003: Argo CD for GitOps, bootstrapped once from OpenTofu

Date: 2026-10-20
Status: Accepted

## Context

Everything that runs *inside* the cluster (ingress, cert-manager, apps) should be reconciled
from Git, not applied by hand or by OpenTofu. Candidates: Argo CD and Flux.

## Decision

- Use **Argo CD**, installed via the official `argo-cd` Helm chart from the
  `modules/k8s/argocd-bootstrap` module. OpenTofu's job ends there.
- The **root Application** (app-of-apps) is a second, tiny Helm release from a chart
  embedded in the module (`charts/root-app`), installed after the Argo CD release. Shipping
  it inside the Argo CD release fails on first install because Helm cannot REST-map a kind
  the API server does not know yet, and `kubernetes_manifest` cannot plan it for the same
  reason. The dependent release avoids both and keeps the module on the `helm` provider only.
- `gitops/clusters/<cluster>/` is a tiny Helm chart that renders one Argo CD `Application`
  per platform service. The Git repo URL and revision are chart values, passed as Helm
  parameters from the root Application, so the URL is never hardcoded in manifests.
- Platform services use **multi-source Applications**: chart from the upstream Helm repo,
  values from this repo under `gitops/platform/<service>/values.yaml`.

## Rationale

Argo CD has a UI, which helps while learning, and the `argocd` CLI was already installed.
Flux has a cleaner OpenTofu provider but no UI by default; it remains a fine alternative.

## Consequences

- Day-2 changes to in-cluster workloads are Git commits, not `tofu apply`.
- The GitOps repo URL must be reachable by Argo CD. For a private repo, add repository
  credentials (SSH key or GitHub App) as a secret in the `argocd` namespace.
