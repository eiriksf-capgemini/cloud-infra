# gitops/apps — workloads, one directory per application

Each application is a kustomize **base** plus one **overlay per environment**:

```
gitops/apps/<app>/
├── base/                 # environment-agnostic manifests
│   └── kustomization.yaml
└── overlays/
    ├── dev/              # deployed on clusters whose environment is dev   (azure-dev today)
    ├── test/             # deployed on clusters whose environment is test  (none yet)
    └── prod/             # deployed on clusters whose environment is prod  (none yet)
```

A cluster declares its environment in `gitops/clusters/<cluster>/values.yaml`
(`environment: dev`). Its `workloads-<env>` ApplicationSet scans
`gitops/apps/*/overlays/<env>` and creates one Argo CD `Application` per match, named after
the app, deployed into a namespace of the same name. Nothing else to register.

## Add an application

1. `mkdir -p gitops/apps/<app>/{base,overlays/{dev,test,prod}}`
2. Put manifests and a `kustomization.yaml` in `base/`.
3. In each overlay, a `kustomization.yaml` with `resources: [../../base]`, `namespace: <app>`,
   and environment-specific patches (replicas, config, ingress host).
   An environment with no overlay directory is simply not deployed there.
4. Check it renders: `kubectl kustomize gitops/apps/<app>/overlays/dev`
5. Commit and push. Argo CD picks it up within its poll interval (3 min) or on refresh.

## Promote a change dev → test → prod

Promotion is a Git change to the next overlay (or to `base/` when it should land everywhere).
Pin images by tag or digest in the overlay so each environment is explicit and reviewable.

## Conventions

- Namespace = app name. Keep one app per namespace.
- Set resource requests; the dev node is small.
- Prefer kustomize for your own apps and Helm (via `gitops/platform`) for third-party charts.
- Dev-only conveniences (nip.io ingress hosts, debug flags) live in `overlays/dev` only.

`podinfo` is the reference example.
