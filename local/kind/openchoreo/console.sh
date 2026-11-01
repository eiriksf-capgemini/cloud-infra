#!/usr/bin/env bash
# Console image from the fork of openchoreo/backstage-plugins (branch
# feat/ai-usage-home-widget, default checkout ../../../../openchoreo-backstage-plugins) for the
# kind install: AI usage widget, Skill kind + MCP server (ai-elements), AIProduct /
# SharePointSite / mcp-server kinds (portal-kinds), Azure plugins (left unconfigured).
#
# build   docker build the image, tag <chart version>-<fork sha> (plus -dirty-<tree hash>
#         when the fork has uncommitted changes, so a rebuild always gets a new tag), push
#         to the kind-registry (localhost:5001, provisioned by platform-gitops/scripts/up.sh
#         and mirrored by the kind node). No kind-load fallback: the registry is required.
# secrets Secrets in the control-plane namespace: ai-elements-mcp (MCP shared token),
#         ai-usage-ingest (Claude Code telemetry token), github-token (only when GITHUB_TOKEN
#         is set explicitly; a read-only token is enough; needed because
#         eiriksf-capgemini/backstage is private).
# values  write values-console.yaml; install.sh layers it on top of values-cp.yaml.
# all     build + secrets + values (default). Then run ./install.sh.
#
# Env: ANTHROPIC_MEMBER_EMAIL (optional; maps the demo IDP users to one telemetry identity),
#      GITHUB_TOKEN (optional, explicit only), BUILD_DOCKER_CONTEXT (optional, build on another engine,
#      e.g. desktop-linux, and stream the image into Colima), UI_SRC / UI_REGISTRY /
#      UI_IMAGE_REPO (env.sh).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"; source ./env.sh

sha() { git -C "$UI_SRC" rev-parse --short=8 HEAD; }
# Dirty trees get a content suffix: the same tag must never be pushed twice, because
# pullPolicy IfNotPresent and an unchanged values file would both keep the old image.
tree_suffix() {
  [[ -n $(git -C "$UI_SRC" status --porcelain) ]] || return 0
  printf -- '-dirty-%s' "$(git -C "$UI_SRC" diff HEAD | git hash-object --stdin | cut -c1-8)"
}
tag() { echo "${OPENCHOREO_VERSION}-$(sha)$(tree_suffix)"; }

build() {
  [[ -d $UI_SRC/packages/backend ]] || die "fork checkout not found at $UI_SRC (set UI_SRC)"
  registry_ok || die "kind-registry at ${UI_REGISTRY} does not answer; start the platform first (scripts/up.sh). Images reach the node only through the registry."
  local t; t=$(tag)
  [[ $t == *-dirty-* ]] && warn "fork working tree is dirty; tagging the build ${t}"
  local local_ref="${UI_IMAGE_REPO}:${t}"
  log "Building console image ${local_ref} from ${UI_SRC} ($(git -C "$UI_SRC" rev-parse --abbrev-ref HEAD))"
  # The build needs ~4 GB for the Node heap. BUILD_DOCKER_CONTEXT (e.g. desktop-linux)
  # builds on another engine and streams the image into the engine that runs kind.
  if [[ -n ${BUILD_DOCKER_CONTEXT:-} && ${BUILD_DOCKER_CONTEXT} != $(docker context show) ]]; then
    docker --context "$BUILD_DOCKER_CONTEXT" buildx build "$UI_SRC" -f "$UI_SRC/packages/backend/Dockerfile" --tag "$local_ref" --load
    log "Copying ${local_ref} from ${BUILD_DOCKER_CONTEXT} to $(docker context show)"
    docker --context "$BUILD_DOCKER_CONTEXT" save "$local_ref" | docker load >/dev/null
  else
    docker buildx build "$UI_SRC" -f "$UI_SRC/packages/backend/Dockerfile" --tag "$local_ref" --load
  fi
  local remote_ref="${UI_REGISTRY}/${UI_IMAGE_REPO}:${t}"
  docker tag "$local_ref" "$remote_ref"
  docker push "$remote_ref" >/dev/null
  ok "pushed ${remote_ref} (kind node pulls it through its localhost:5001 mirror)"
}

rand_token() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48; }

secret_if_missing() { # name key value
  if K get secret "$1" -n "$CP_NS" >/dev/null 2>&1; then ok "secret $1 exists"; return; fi
  K create secret generic "$1" -n "$CP_NS" --from-literal="$2=$3" >/dev/null; ok "created secret $1"
}

secrets() {
  K create namespace "$CP_NS" --dry-run=client -o yaml | K apply -f - >/dev/null
  secret_if_missing ai-elements-mcp token "$(rand_token)"
  secret_if_missing ai-usage-ingest token "$(rand_token)"
  # Explicit only: the human's `gh auth token` carries repo/workflow/org scopes and must
  # not end up in a cluster Secret by accident. A fine-grained read-only token is enough.
  if [[ -n ${GITHUB_TOKEN:-} ]]; then
    K create secret generic github-token -n "$CP_NS" --from-literal=token="$GITHUB_TOKEN" --dry-run=client -o yaml | K apply -f - >/dev/null
    ok "secret github-token written (private repositories readable by the catalog)"
  elif K get secret github-token -n "$CP_NS" >/dev/null 2>&1; then
    ok "secret github-token exists (set GITHUB_TOKEN to replace it)"
  else
    warn "GITHUB_TOKEN not set: private repositories (eiriksf-capgemini/backstage) will not be read; export a read-only token and re-run ./console.sh secrets"
  fi
}

values() {
  local t; t=$(tag)
  local repo="${UI_REGISTRY}/${UI_IMAGE_REPO}" pull="IfNotPresent"
  # Never point the chart at a tag that was not built (a failed build must not take
  # the console down on the next install.sh). install.sh re-checks this before deploying.
  registry_ok || die "kind-registry at ${UI_REGISTRY} does not answer"
  registry_has_tag "$t" || die "image ${repo}:${t} is not in the registry; run ./console.sh build first"
  local email="${ANTHROPIC_MEMBER_EMAIL:-}"
  {
    cat <<YAML
# Written by console.sh; layered on top of values-cp.yaml by install.sh.
# Console image from the fork (${UI_SRC}, $(git -C "$UI_SRC" rev-parse --abbrev-ref HEAD) @ $(sha)).
backstage:
  image:
    repository: ${repo}
    tag: ${t}
    pullPolicy: ${pull}
  # The portal's SQLite (catalog, AI usage rows, user settings) survives pod restarts.
  database:
    type: sqlite
    sqlite:
      persistence:
        enabled: true
        size: 2Gi
  extraEnv:
    # AI usage & cost widget, fed by Claude Code OpenTelemetry pushed to the portal
    # (POST /api/openchoreo-ai-usage/v1/logs, bearer = Secret ai-usage-ingest).
    - name: OPENCHOREO_FEATURES_AI_USAGE_ENABLED
      value: "true"
    - name: OPENCHOREO_AI_USAGE_SOURCE
      value: telemetry
    - name: AI_USAGE_INGEST_TOKEN
      valueFrom: {secretKeyRef: {name: ai-usage-ingest, key: token, optional: true}}
    # MCP server shared token (interactive clients log in through Thunder instead).
    - name: AI_ELEMENTS_MCP_TOKEN
      valueFrom: {secretKeyRef: {name: ai-elements-mcp, key: token, optional: true}}
    # GitHub token for private repositories read by the catalog (aiElements).
    - name: GITHUB_TOKEN
      valueFrom: {secretKeyRef: {name: github-token, key: token, optional: true}}
  # Rendered as app-config.extra.yaml (last config file, overrides the image's).
  # Lists are replaced, not merged: do not put catalog.locations here.
  appConfig:
    integrations:
      github:
        - host: github.com
          token: \${GITHUB_TOKEN}
YAML
    if [[ -n $email ]]; then
      cat <<YAML
    openchoreo:
      aiUsage:
        users:
          - email: ${email}
YAML
    fi
    cat <<'YAML'
    # Skills, agents, prompts and hooks from Git as `Skill` entities (namespace ai).
    aiElements:
      repositories:
        - url: https://github.com/eiriksf-capgemini/common-ai
          title: Common AI
          description: Agents, instructions, prompts, skills and hooks for GitHub Copilot and Claude Code, shared by AI developers at Capgemini Bergen.
YAML
    # The private POC repository is listed only when a token exists: the provider
    # skips a whole run if any repository fails to read, which would hide common-ai too.
    if K get secret github-token -n "$CP_NS" >/dev/null 2>&1; then
      cat <<'YAML'
        # The standalone Backstage POC's own skills (private repository, read with Secret github-token).
        - url: https://github.com/eiriksf-capgemini/backstage
          name: backstage-poc
          title: Backstage POC skills
          description: Skills written while building the standalone Backstage proof of concept (Entra directory insights, SharePoint catalog investigation).
          paths:
            skills: .claude/skills
YAML
    else
      warn "no Secret github-token: the private POC repository is left out of aiElements.repositories"
    fi
    cat <<'YAML'
      # MCP server at http://openchoreo.localhost:8080/api/openchoreo-ai-elements/mcp
      mcp:
        token: ${AI_ELEMENTS_MCP_TOKEN}
        oauth:
          # Thunder's public issuer on kind is plain-HTTP localhost (values-thunder-kind.yaml);
          # the JWKS is fetched in-cluster through the routable name.
          issuer: http://localhost:8080
          jwksUrl: http://thunder.openchoreo.localhost:8080/oauth2/jwks
        platformFacts:
          cluster: kind cluster platform-gitops on Colima (one node, Cilium CNI), created by the platform-gitops repository (Argo CD app-of-apps); OpenChoreo is installed by cloud-infra/local/kind/openchoreo/install.sh, the laptop flavour of the AKS install in the same repository
          console: http://openchoreo.localhost:8080
          openchoreoApi: http://api.openchoreo.localhost:8080 (MCP for OpenChoreo objects at /mcp, OAuth via Thunder)
          thunder: http://thunder.openchoreo.localhost:8080 (issuer http://localhost:8080, console /console)
          workloadDomain: openchoreoapis.localhost:19080
          observer: http://observer.openchoreo.localhost:11080 (observability plane, when installed)
          registry: localhost:5001 (kind-registry container, mirrored by the node)
          gitopsRepo: https://github.com/eiriksf-capgemini/platform-gitops
          prsBy: GitHub App hal9000-agent-bot (scripts/gh-app-token.mjs), never the human login
        docs:
          - name: cloud-infra
            title: cloud-infra ADRs, runbooks and reports
            url: https://github.com/eiriksf-capgemini/cloud-infra/tree/main/docs
          - name: platform-gitops
            title: platform-gitops docs
            url: https://github.com/eiriksf-capgemini/platform-gitops/tree/main/docs
YAML
  } > values-console.yaml
  ok "wrote values-console.yaml (image ${repo}:${t})"
  [[ -n $email ]] || warn "ANTHROPIC_MEMBER_EMAIL not set: the AI usage widget's per-user rows stay empty for the demo IDP users"
}

case "${1:-all}" in
  build)   build ;;
  secrets) secrets ;;
  values)  values ;;
  all)     build; secrets; values
           echo; echo "Now run ./install.sh to (re)deploy the control plane with the new console image." ;;
  *) die "usage: $0 [build|secrets|values|all]" ;;
esac
