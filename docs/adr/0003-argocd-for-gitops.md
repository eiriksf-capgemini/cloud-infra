# ADR 0003: Argo CD for GitOps, bootstrapped once from OpenTofu

Date: 2026-10-20
Status: Accepted

## Context

Everything that runs *inside* the cluster (ingress, cert-manager, apps) should be reconciled
from Git, not applied by hand or by OpenTofu. Candidates: Argo CD and Flux.

## Decision

- Use **Argo CD**, installed via the official `argo-cd` Helm chart from the
  `modules/k8s/argocd-bootstrap` module. OpenTofu's job ends there.
- The **root Application** (app-of-apps) is created in the same Helm release through the
  chart's `extraObjects` value. This avoids the classic failure where `kubernetes_manifest`
  cannot plan because the Application CRD does not exist yet, and means no `kubernetes`
  provider is needed. Helm's own pre-install OpenAPI validation has the same objection, so
  the release sets `disable_openapi_validation = true`; Helm's kind ordering then installs
  the CRDs before the Application.
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
