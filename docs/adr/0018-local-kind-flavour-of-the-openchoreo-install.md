# ADR 0018: The local kind flavour of the OpenChoreo install lives here

Date: 2026-11-01
Status: Accepted

## Context

OpenChoreo 1.3.1 runs on the POC AKS cluster from this repository (ADR 0010), with a forked
console image (ADR 0013 to 0017). A second instance runs on a laptop: the kind cluster that
the [platform-gitops](https://github.com/eiriksf-capgemini/platform-gitops) repository
creates (Colima, Cilium, a local registry, Argo CD for its own workloads). It uses the same
charts, the same console image and, since 2026-10-31, the observability plane too, which the
AKS install does not have yet. It exists to try OpenChoreo changes (console plugins, catalog
kinds, MCP, observability) without the AKS cluster's cost and start-up time.

The install is imperative: the upstream quick start only knows how to create its own k3d
cluster, so a set of idempotent scripts runs the same steps (Helm releases from the
OpenChoreo OCI registry, NodePort gateways published by a `socat` container, a CoreDNS
rewrite for the `*.openchoreo.localhost` names, generated credentials). The question was
which repository owns those scripts:

- platform-gitops owns the cluster they run on (name, node, registry, CPU budget) and already
  carries two imperative exceptions to its app-of-apps rule. A first version landed there.
- cloud-infra owns everything OpenChoreo: the decisions (ADRs), the AKS values for the same
  charts, the console-image runbook, and the configuration the console shares between the two
  installs (AI elements repositories, MCP server, platform facts).

## Decision

The scripts live in this repository under `local/kind/openchoreo/`, as the laptop flavour of
the AKS install. platform-gitops keeps only a pointer (what the install touches on its
cluster: Colima CPU, the `kind-registry`, host ports, CoreDNS) and the bead for bringing the
releases under that cluster's Argo CD (`pgops-xa9`), since that Argo CD is theirs.

Rules the directory follows:

- **No credentials in the repo.** `secrets.sh` generates every password and client secret the
  k3d quick start ships as literals, keeps them in a git-ignored file mirrored into a cluster
  Secret, and renders the upstream values files (which carry `@@name@@` placeholders) into a
  git-ignored directory. `install.sh` prints the generated console passwords.
- **Pinned.** Chart versions, the samples tag and the forwarder image are pinned in `env.sh`
  and must match `gitops/platform/openchoreo-*` for the shared charts.
- **Images through the local registry**, never `kind load`; a pinned tag the registry no
  longer has is refused before deploying.
- **Idempotent and re-runnable**; `uninstall.sh` tears down in an order that can finish
  (Components before the data plane, namespaces before the operators owning their finalizers).

## Consequences

- One place to read about OpenChoreo, two targets (AKS from `gitops/`, kind from
  `local/kind/`). The README's OpenChoreo section links both.
- The console's shared configuration is duplicated today between
  `gitops/platform/openchoreo-control-plane/values.yaml` and `local/kind/openchoreo/console.sh`
  (`aiElements`, `platformFacts`, `docs`, feature flags). Follow-up: extract one values
  fragment both consume. Until then, change both.
- `local/kind/` is the first non-cloud tree in a repository shaped around `live/<cloud>/<env>`
  and `gitops/`; it is tooling, not a stack: no state, no Argo CD, no CI beyond shell syntax.
- The kind install's credentials differ from the AKS ones (ADR 0011's shared admin password
  is Key Vault-backed and does not exist on the laptop); `./secrets.sh show` prints them.
