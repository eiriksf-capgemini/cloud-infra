# gitops/clusters/azure-dev

Helm chart rendered **by Argo CD** (not by you) as the root app-of-apps for the azure-dev
cluster (environment `dev`). It creates:

- one `Application` per platform service in `values.yaml` → `apps`;
- one `ApplicationSet` that turns every `gitops/apps/<namespace>/<app>/overlays/dev` directory
  into an `Application` named `<namespace>-<app>` (see `gitops/apps/README.md` and ADR 0005).

- Enable/disable a platform service: flip `enabled`.
- Bump a chart: change `chartVersion`.
- Tune a service: edit `gitops/platform/<name>/values.yaml`.

`repoURL` and `targetRevision` are injected by the root Application created in
`modules/k8s/argocd-bootstrap`. Render locally with:

```sh
helm template root gitops/clusters/azure-dev --namespace argocd \
  --set repoURL=https://github.com/<org>/cloud-infra.git
```
