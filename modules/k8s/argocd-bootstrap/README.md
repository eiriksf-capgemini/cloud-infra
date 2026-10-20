# modules/k8s/argocd-bootstrap

Installs Argo CD from the official Helm chart and creates the root app-of-apps `Application`
inside the same release (see ADR 0003). Cloud-agnostic: requires only a configured `helm`
provider.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `gitops_repo_url` | string | – | Git URL Argo CD reconciles from |
| `gitops_revision` | string | `main` | Branch/tag/commit |
| `gitops_path` | string | `gitops/clusters/azure-poc` | Path to the cluster chart |
| `namespace` | string | `argocd` | |
| `chart_version` | string | `10.10.5` | argo-cd chart version |
| `create_root_app` | bool | `true` | Create the root Application |
| `values` | any | `{}` | Extra chart values merged last |

## Outputs

`namespace`, `release_name`, `chart_version`, `initial_admin_password_command`, `port_forward_command`

## After apply

```sh
kubectl -n argocd port-forward svc/argocd-server 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
argocd login localhost:8080 --username admin --insecure
```
