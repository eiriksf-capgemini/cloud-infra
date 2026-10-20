# gitops/apps — workloads, grouped by namespace

```
gitops/apps/<namespace>/<app>/
├── base/                 # environment-agnostic manifests
│   └── kustomization.yaml
└── overlays/
    ├── dev/              # deployed on clusters whose environment is dev   (azure-dev today)
    ├── test/             # deployed on clusters whose environment is test  (none yet)
    └── prod/             # deployed on clusters whose environment is prod  (none yet)
```

- **Namespace folder** = one Kubernetes namespace. Everything inside deploys there.
- **App folder** = one Argo CD `Application`, named `<namespace>-<app>`.
- **Environments live inside the app** as kustomize overlays. An environment without an
  overlay directory is simply not deployed there.

A cluster declares its environment in `gitops/clusters/<cluster>/values.yaml`
(`environment: dev`). Its `workloads-<env>` ApplicationSet scans
`gitops/apps/*/*/overlays/<env>` and creates the Applications. Nothing to register.

## Namespace-level configuration

Put it in a `namespace` app inside the namespace folder: `gitops/apps/<namespace>/namespace/`.
Its base holds the `Namespace` object itself (labels such as Pod Security Admission levels) and
a `LimitRange`; each overlay holds the environment's `ResourceQuota`. It is discovered and
promoted like any other app, as `<namespace>-namespace`. See `demo/namespace` for the pattern.

Namespaces are **not** auto-created (no `CreateNamespace`). A namespace folder without a
`namespace` app will have all its other apps fail with "namespace not found" until one is
added. Apps added together with a new namespace fail their first sync and succeed on retry.

## Add an application

1. `mkdir -p gitops/apps/<namespace>/<app>/{base,overlays/{dev,test,prod}}`
2. Put manifests and a `kustomization.yaml` in `base/`.
3. In each overlay, a `kustomization.yaml` with `resources: [../../base]`,
   `namespace: <namespace>`, and environment-specific patches (replicas, config, ingress host).
4. Check it renders: `kubectl kustomize gitops/apps/<namespace>/<app>/overlays/dev`
5. Commit and push. Argo CD picks it up within its poll interval (3 min) or on refresh.

## Promote a change dev → test → prod

Promotion is a Git change to the next overlay (or to `base/` when it should land everywhere).
Pin images by tag or digest in the overlay so each environment is explicit and reviewable.

## Conventions

- Set resource requests; the dev node is small. The namespace `LimitRange` adds defaults.
- Prefer kustomize for your own apps and Helm (via `gitops/platform`) for third-party charts.
- Dev-only conveniences (nip.io ingress hosts, debug flags) live in `overlays/dev` only.

## Current namespaces

| Folder | Purpose |
|---|---|
| `platform` | developer tooling: Argo CD (bootstrapped by OpenTofu), Tekton incl. read-only Dashboard (`tekton` app) |
| `demo` | reference app `podinfo` |
| `sogeti`, `invent`, `i-and-d` | team namespaces, empty apart from their `namespace` app |

`demo/podinfo` and `demo/namespace` are the reference examples.
