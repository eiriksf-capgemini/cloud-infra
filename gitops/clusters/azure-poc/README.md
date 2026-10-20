# gitops/clusters/azure-poc

Helm chart rendered **by Argo CD** (not by you) as the root app-of-apps for the azure-poc
cluster. One `Application` per entry in `values.yaml` → `apps`.

- Enable/disable a platform service: flip `enabled`.
- Bump a chart: change `chartVersion`.
- Tune a service: edit `gitops/platform/<name>/values.yaml`.

`repoURL` and `targetRevision` are injected by the root Application created in
`modules/k8s/argocd-bootstrap`. Render locally with:

```sh
helm template root gitops/clusters/azure-poc --namespace argocd \
  --set repoURL=https://github.com/<org>/cloud-infra.git
```
