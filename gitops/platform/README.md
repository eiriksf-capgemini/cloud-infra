# gitops/platform

Per-service Helm values consumed by the Applications rendered from
`gitops/clusters/<cluster>/`. Files here are cloud-agnostic except where an annotation is
clearly provider-specific (commented inline).

Directories without `values.yaml` are kustomize apps (upstream release YAML or small glue).
The `openchoreo-*`, `kgateway*`, `thunder`, `openbao`, `external-secrets`, `gateway-api-crds` and
`keda*` entries belong together; ADR 0010 explains the order and the one-IP design.
