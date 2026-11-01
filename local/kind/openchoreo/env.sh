# Shared settings for the OpenChoreo-on-kind scripts. Override via environment.
KCTX="${KCTX:-kind-platform-gitops}"               # kube context of the existing kind cluster
KIND_NODE="${KIND_NODE:-platform-gitops-control-plane}"  # docker container name of a kind node
KIND_DOCKER_NET="${KIND_DOCKER_NET:-kind}"
LB_CONTAINER="${LB_CONTAINER:-openchoreo-kind-lb}"

OPENCHOREO_VERSION="${OPENCHOREO_VERSION:-1.3.1}"   # chart version (appVersion v1.3.1)
OPENCHOREO_REF="${OPENCHOREO_REF:-v${OPENCHOREO_VERSION}}"  # git tag the samples are fetched from (pinned, not the moving release branch)
OC_CHARTS="oci://cr.openchoreo.dev/openchoreo/helm-charts"

# Prerequisite versions, same as install/k3d/single-cluster/README.md on release-v1.3
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.5.1}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.19.4}"
ESO_VERSION="${ESO_VERSION:-2.0.1}"
# v2.3.1 (upstream pin) CRDs are rejected by Kubernetes >=1.37 (CEL cost budget); v2.3.11 is the same API line and passes.
KGATEWAY_VERSION="${KGATEWAY_VERSION:-v2.3.11}"
THUNDER_VERSION="${THUNDER_VERSION:-1.0.1}"
OPENBAO_VERSION="${OPENBAO_VERSION:-0.25.6}"

CP_NS=openchoreo-control-plane
DP_NS=openchoreo-data-plane
OP_NS=openchoreo-observability-plane
THUNDER_NS=thunder
OPENBAO_NS=openbao

# Observability plane (observability.sh). WITH_OBSERVABILITY=false skips it.
WITH_OBSERVABILITY="${WITH_OBSERVABILITY:-true}"
# Module chart versions pinned by install/quick-start/.config.sh on release-v1.3
OBS_LOGS_VERSION="${OBS_LOGS_VERSION:-0.7.0}"       # observability-logs-opensearch
OBS_TRACES_VERSION="${OBS_TRACES_VERSION:-0.8.0}"   # observability-tracing-opensearch
OBS_METRICS_VERSION="${OBS_METRICS_VERSION:-0.8.0}" # observability-metrics-prometheus
OBS_EVENTS_VERSION="${OBS_EVENTS_VERSION:-0.1.2}"   # observability-events-otel-collector
CLUSTER_INSTANCE="${CLUSTER_INSTANCE:-platform-gitops}"  # Fluent Bit cluster label

# Console image built from the fork (console.sh); pushed to the kind-registry that
# platform-gitops/scripts/up.sh provisions, which the kind node mirrors as localhost:5001.
UI_SRC="${UI_SRC:-../../../../openchoreo-backstage-plugins}"   # sibling of this repo
UI_REGISTRY="${UI_REGISTRY:-localhost:5001}"
UI_IMAGE_REPO="${UI_IMAGE_REPO:-openchoreo-ui}"
SOCAT_IMAGE="${SOCAT_IMAGE:-alpine/socat:1.8.1.3}"   # host port forwarder (start-lb.sh)

# The kind-registry (platform-gitops/scripts/up.sh) must answer; images reach the
# node only through it (repo policy: no kind load).
registry_ok() { docker inspect kind-registry >/dev/null 2>&1 && curl -fs "http://${UI_REGISTRY}/v2/" >/dev/null 2>&1; }
registry_has_tag() { curl -fs "http://${UI_REGISTRY}/v2/${UI_IMAGE_REPO}/tags/list" 2>/dev/null | grep -q "\"$1\""; }

# Host ports published by the forwarder container -> kind node NodePorts
CP_HTTP_PORT=8080;   CP_HTTP_NODEPORT=30080
DP_HTTP_PORT=19080;  DP_HTTP_NODEPORT=30190
OP_HTTP_PORT=11080;  OP_HTTP_NODEPORT=31080
REMOTE_PORT=30443;   REMOTE_NODEPORT=30443

K() { kubectl --context "$KCTX" "$@"; }
H() { helm --kube-context "$KCTX" "$@"; }
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m ✗\033[0m %s\n' "$*" >&2; exit 1; }

# helm upgrade --install cannot recover a release whose FIRST revision failed or
# hung (failed / pending-install with a single revision); remove such a release so
# the install can be retried. A release that has been deployed before and then had
# a failed upgrade is left alone: upgrade --install retries it in place, and
# uninstalling it would delete chart-owned state such as the backstage-db PVC.
reset_failed_release() { # name ns
  local st revs
  st=$(H status "$1" -n "$2" -o json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["info"]["status"])' 2>/dev/null || true)
  [[ $st == "failed" || $st == "pending-install" ]] || return 0
  revs=$(H history "$1" -n "$2" -o json 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
  if [[ $revs -le 1 ]]; then
    warn "removing $st first-revision release $1 in $2"; H uninstall "$1" -n "$2" --wait >/dev/null 2>&1 || true
  else
    warn "release $1 in $2 is $st after $revs revisions; retrying the upgrade in place"
  fi
}
