#!/usr/bin/env bash
# OpenChoreo observability plane on the EXISTING kind cluster. Mirrors what the
# upstream quick start does for --with-observability (install/quick-start/.helpers.sh,
# release-v1.3): CA ConfigMap, ExternalSecrets, the plane chart, the four community
# modules (logs/OpenSearch, traces, metrics/Prometheus, k8s events), the
# ClusterObservabilityPlane resource and the data-plane reference. Called by
# install.sh (WITH_OBSERVABILITY=true, the default); safe to re-run.
#   observability.sh install | remove
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"; source ./env.sh; source ./secrets.sh

install() {
  K get clusterdataplane default >/dev/null 2>&1 || die "ClusterDataPlane default missing; run install.sh first"
  ensure_secrets

  log "Observability plane: machine-id for Fluent Bit"
  docker exec "$KIND_NODE" sh -c '[ -s /etc/machine-id ] || cat /proc/sys/kernel/random/uuid | tr -d "-" > /etc/machine-id'

  log "Observability plane: namespace, cluster-gateway CA, ExternalSecrets"
  K create namespace "$OP_NS" --dry-run=client -o yaml | K apply -f - >/dev/null
  CA_CRT=$(K get configmap cluster-gateway-ca -n "$CP_NS" -o jsonpath='{.data.ca\.crt}')
  [[ -n $CA_CRT ]] || die "cluster-gateway-ca ConfigMap in $CP_NS is empty"
  K create configmap cluster-gateway-ca --from-literal=ca.crt="$CA_CRT" -n "$OP_NS" --dry-run=client -o yaml | K apply -f - >/dev/null
  K apply --server-side -f - >/dev/null <<YAML
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: opensearch-admin-credentials
  namespace: ${OP_NS}
spec:
  refreshInterval: 1h
  secretStoreRef: {kind: ClusterSecretStore, name: default}
  target: {name: opensearch-admin-credentials}
  data:
    - secretKey: username
      remoteRef: {key: opensearch-username, property: value}
    - secretKey: password
      remoteRef: {key: opensearch-password, property: value}
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: observer-secret
  namespace: ${OP_NS}
spec:
  refreshInterval: 1h
  secretStoreRef: {kind: ClusterSecretStore, name: default}
  target: {name: observer-secret}
  data:
    - secretKey: UID_RESOLVER_OAUTH_CLIENT_SECRET
      remoteRef: {key: observer-oauth-client-secret, property: value}
YAML
  K wait -n "$OP_NS" --for=condition=Ready externalsecret/opensearch-admin-credentials externalsecret/observer-secret --timeout=120s >/dev/null

  log "GatewayParameters (NodePort ${OP_HTTP_NODEPORT})"
  K apply -f gateway-parameters.yaml >/dev/null

  log "OpenChoreo Observability Plane chart ${OPENCHOREO_VERSION}"
  reset_failed_release openchoreo-observability-plane "$OP_NS"
  H upgrade --install openchoreo-observability-plane "${OC_CHARTS}/openchoreo-observability-plane" \
    -n "$OP_NS" --version "$OPENCHOREO_VERSION" --values values-op.yaml \
    --set observer.audit.enabled=true --wait --timeout 30m >/dev/null

  log "Module: logs (OpenSearch + Fluent Bit) ${OBS_LOGS_VERSION}"
  reset_failed_release observability-logs-opensearch "$OP_NS"
  # OpenSearch's initial admin password must equal the one OpenBao seeds for the setup
  # jobs and adapters (generated, secrets.sh); the module default is a public literal.
  # OpenSearch's chart default requests a full CPU; the kind VM is small. The Fluent
  # Bit image comes from Docker Hub: the kind node's containerd rejects cr.fluentbit.io's
  # certificate chain (x509 unknown authority) while the same pull works from the Mac.
  H upgrade --install observability-logs-opensearch "${OC_CHARTS}/observability-logs-opensearch" \
    -n "$OP_NS" --version "$OBS_LOGS_VERSION" \
    --set fluent-bit.image.repository=docker.io/fluent/fluent-bit \
    --set-string 'openSearch.extraEnvs[0].name=OPENSEARCH_INITIAL_ADMIN_PASSWORD' \
    --set-string "openSearch.extraEnvs[0].value=${OPENSEARCH_PASSWORD}" \
    --set openSearchSetup.openSearchSecretName=opensearch-admin-credentials \
    --set adapter.openSearchSecretName=opensearch-admin-credentials \
    --set auditLogs.enabled=true \
    --set fluentBitCustomizations.clusterInstance="$CLUSTER_INSTANCE" \
    --set openSearch.resources.requests.cpu=250m \
    --wait --timeout 20m >/dev/null

  log "Module: traces ${OBS_TRACES_VERSION}"
  reset_failed_release observability-traces-opensearch "$OP_NS"
  H upgrade --install observability-traces-opensearch "${OC_CHARTS}/observability-tracing-opensearch" \
    -n "$OP_NS" --version "$OBS_TRACES_VERSION" \
    --set openSearch.enabled=false \
    --set openSearchSetup.openSearchSecretName=opensearch-admin-credentials \
    --wait --timeout 10m >/dev/null

  log "Module: metrics (kube-prometheus-stack) ${OBS_METRICS_VERSION}"
  reset_failed_release observability-metrics-prometheus "$OP_NS"
  H upgrade --install observability-metrics-prometheus "${OC_CHARTS}/observability-metrics-prometheus" \
    -n "$OP_NS" --version "$OBS_METRICS_VERSION" --wait --timeout 15m >/dev/null
  for sts in prometheus-openchoreo-observability alertmanager-openchoreo-observability; do
    for _ in $(seq 1 30); do K get statefulset "$sts" -n "$OP_NS" >/dev/null 2>&1 && break; sleep 2; done
    K rollout status statefulset "$sts" -n "$OP_NS" --timeout=300s >/dev/null || warn "$sts not rolled out yet"
  done

  log "Module: Kubernetes events (OTel collector -> OpenSearch) ${OBS_EVENTS_VERSION}"
  reset_failed_release observability-events-kubernetes "$OP_NS"
  H upgrade --install observability-events-kubernetes "${OC_CHARTS}/observability-events-otel-collector" \
    -n "$OP_NS" --version "$OBS_EVENTS_VERSION" --wait --timeout 10m -f - >/dev/null <<'YAML'
collector:
  extraEnv:
    - name: OPENSEARCH_USERNAME
      valueFrom: {secretKeyRef: {name: opensearch-admin-credentials, key: username}}
    - name: OPENSEARCH_PASSWORD
      valueFrom: {secretKeyRef: {name: opensearch-admin-credentials, key: password}}
extraExtensions:
  basicauth/opensearch:
    client_auth:
      username: ${env:OPENSEARCH_USERNAME}
      password: ${env:OPENSEARCH_PASSWORD}
exporters:
  opensearch:
    logs_index: k8s-events
    # Daily indices (k8s-events-YYYY-MM-DD): the module's index template only
    # matches k8s-events-*, a plain k8s-events index gets no mappings or retention.
    logs_index_time_format: "yyyy-MM-dd"
    http:
      endpoint: https://opensearch:9200
      auth: {authenticator: basicauth/opensearch}
      tls: {insecure_skip_verify: true}
pipelineExporters: [opensearch]
YAML

  log "ClusterObservabilityPlane 'default'"
  for _ in $(seq 1 60); do K get secret cluster-agent-tls -n "$OP_NS" >/dev/null 2>&1 && break; sleep 2; done
  AGENT_CA=$(K get secret cluster-agent-tls -n "$OP_NS" -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d || true)
  [[ -n $AGENT_CA ]] || die "cluster-agent-tls secret missing in $OP_NS"
  K apply -f - >/dev/null <<YAML
apiVersion: openchoreo.dev/v1alpha1
kind: ClusterObservabilityPlane
metadata:
  name: default
spec:
  planeID: default
  clusterAgent:
    clientCA:
      value: |
$(sed 's/^/        /' <<<"$AGENT_CA")
  observerURL: http://observer.openchoreo.localhost:${OP_HTTP_PORT}
YAML
  K patch clusterdataplane default --type merge -p '{"spec":{"observabilityPlaneRef":{"kind":"ClusterObservabilityPlane","name":"default"}}}' >/dev/null

  log "Verifying observer"
  code=""
  for _ in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://observer.openchoreo.localhost:${OP_HTTP_PORT}/health" || true)
    [[ $code == 200 ]] && break; sleep 3
  done
  [[ $code == 200 ]] || die "observer not reachable at http://observer.openchoreo.localhost:${OP_HTTP_PORT}/health (got '${code:-n/a}'); check the forwarder (start-lb.sh) and: kubectl --context $KCTX get pods -n $OP_NS"
  K get clusterobservabilityplane default -o wide
  ok "observability plane installed (namespace $OP_NS); observer answers 200"
}

remove() {
  log "Removing observability plane"
  K patch clusterdataplane default --type json -p '[{"op":"remove","path":"/spec/observabilityPlaneRef"}]' >/dev/null 2>&1 || true
  # The CRD may already be gone (uninstall.sh --crds, control plane removed).
  K delete clusterobservabilityplane default --ignore-not-found --timeout=60s 2>/dev/null || true
  for rel in observability-events-kubernetes observability-metrics-prometheus observability-traces-opensearch observability-logs-opensearch openchoreo-observability-plane; do
    H uninstall "$rel" -n "$OP_NS" 2>/dev/null || true
  done
  K delete ns "$OP_NS" --ignore-not-found --timeout=180s
  ok "observability plane removed"
}

case "${1:-install}" in
  install) install ;;
  remove)  remove ;;
  *) die "usage: $0 install|remove" ;;
esac
