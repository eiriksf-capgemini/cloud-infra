#!/usr/bin/env bash
# Install OpenChoreo (control plane + data plane) into an EXISTING kind cluster.
# Mirrors install/quick-start/install.sh + install/k3d/single-cluster/README.md
# (release-v1.3) using the published OCI charts, minus cluster creation, plus the
# kind-specific bits: NodePort gateways, a host port forwarder, CoreDNS rewrite.
# Idempotent: safe to re-run.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"; source ./env.sh; source ./secrets.sh
RAW="https://raw.githubusercontent.com/openchoreo/openchoreo/${OPENCHOREO_REF}"

K cluster-info >/dev/null 2>&1 || die "cannot reach context $KCTX"
docker inspect "$KIND_NODE" >/dev/null 2>&1 || die "kind node container $KIND_NODE not found"
log "Installing OpenChoreo ${OPENCHOREO_VERSION} into context ${KCTX}"

# Generated credentials (never committed) and the upstream values rendered with them.
ensure_secrets; render_values

# ---------------------------------------------------------------- prerequisites
log "Gateway API CRDs ${GATEWAY_API_VERSION}"
K apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml" >/dev/null

log "cert-manager ${CERT_MANAGER_VERSION}"
reset_failed_release cert-manager cert-manager
H upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  -n cert-manager --create-namespace --version "$CERT_MANAGER_VERSION" --set crds.enabled=true --wait --timeout 5m >/dev/null
K wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=180s >/dev/null

log "External Secrets Operator ${ESO_VERSION}"
reset_failed_release external-secrets external-secrets
H upgrade --install external-secrets oci://ghcr.io/external-secrets/charts/external-secrets \
  -n external-secrets --create-namespace --version "$ESO_VERSION" --set installCRDs=true --wait --timeout 5m >/dev/null

log "OpenBao ${OPENBAO_VERSION} (dev mode, seeds platform secrets)"
reset_failed_release openbao "$OPENBAO_NS"
H upgrade --install openbao oci://ghcr.io/openbao/charts/openbao \
  -n "$OPENBAO_NS" --create-namespace --version "$OPENBAO_VERSION" --values .rendered/values-openbao.yaml --wait --timeout 10m >/dev/null
K wait -n "$OPENBAO_NS" --for=condition=Ready pod -l app.kubernetes.io/name=openbao,component=server --timeout=300s >/dev/null
K apply --server-side -f - >/dev/null <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets-openbao
  namespace: ${OPENBAO_NS}
---
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: default
spec:
  provider:
    vault:
      server: "http://openbao.${OPENBAO_NS}.svc:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "openchoreo-secret-writer-role"
          serviceAccountRef:
            name: "external-secrets-openbao"
            namespace: "${OPENBAO_NS}"
YAML

log "kgateway ${KGATEWAY_VERSION}"
reset_failed_release kgateway-crds "$CP_NS"
H upgrade --install kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
  -n "$CP_NS" --create-namespace --version "$KGATEWAY_VERSION" >/dev/null
reset_failed_release kgateway "$CP_NS"
H upgrade --install kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  -n "$CP_NS" --version "$KGATEWAY_VERSION" --wait --timeout 5m >/dev/null

log "ThunderID ${THUNDER_VERSION}"
reset_failed_release thunder "$THUNDER_NS"
H upgrade --install thunder oci://ghcr.io/thunder-id/helm-charts/thunderid \
  -n "$THUNDER_NS" --create-namespace --version "$THUNDER_VERSION" --values .rendered/values-thunder.yaml --values values-thunder-kind.yaml --timeout 10m >/dev/null

log "CoreDNS rewrite (kind replacement for k3d coredns-custom)"
./coredns.sh apply

# ---------------------------------------------------------------- control plane
log "GatewayParameters (NodePort) + Backstage ExternalSecret"
# gateway-parameters.yaml also holds the observability-plane entry, so that
# namespace must exist even when the plane is installed later.
for ns in "$DP_NS" "$OP_NS"; do K create namespace "$ns" --dry-run=client -o yaml | K apply -f - >/dev/null; done
K apply -f gateway-parameters.yaml >/dev/null
K apply --server-side -f - >/dev/null <<YAML
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: backstage-secrets
  namespace: ${CP_NS}
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: default
  target:
    name: backstage-secrets
  data:
    - secretKey: backend-secret
      remoteRef: {key: backstage-backend-secret, property: value}
    - secretKey: client-secret
      remoteRef: {key: backstage-client-secret, property: value}
    - secretKey: jenkins-api-key
      remoteRef: {key: backstage-jenkins-api-key, property: value}
    - secretKey: github-actions-token
      remoteRef: {key: backstage-github-actions-token, property: value}
    - secretKey: github-oauth-client-secret
      remoteRef: {key: backstage-github-oauth-client-secret, property: value}
YAML
K wait -n "$CP_NS" --for=condition=Ready externalsecret/backstage-secrets --timeout=120s >/dev/null

log "OpenChoreo Control Plane chart ${OPENCHOREO_VERSION}"
# no --wait here: upstream notes a deadlock with webhook cert hooks
# --server-side=false: Helm 4 defaults to server-side apply, which conflicts with the
# cluster-gateway-ca ConfigMap below (chart ships a placeholder, we write the real CA
# with kubectl). Client-side apply (Helm 3 behaviour) leaves the populated value alone.
reset_failed_release openchoreo-control-plane "$CP_NS"
# values-console.yaml (written by console.sh) switches to the console image built from
# the fork and configures its plugins; absent, the stock image is used. The pinned tag
# must still be in the registry (a recreated kind-registry or colima VM empties it):
# otherwise the new pod would sit in ImagePullBackOff behind the still-serving old one.
EXTRA_CP_VALUES=()
if [[ -f values-console.yaml ]]; then
  CONSOLE_TAG=$(sed -nE 's/^[[:space:]]*tag:[[:space:]]*([^[:space:]]+).*/\1/p' values-console.yaml | head -1)   # BSD sed: no \s
  [[ -n $CONSOLE_TAG ]] || die "could not read backstage.image.tag from values-console.yaml"

  registry_ok || die "values-console.yaml present but the kind-registry at ${UI_REGISTRY} does not answer (platform-gitops/scripts/up.sh starts it)"
  registry_has_tag "$CONSOLE_TAG" || die "values-console.yaml pins ${UI_IMAGE_REPO}:${CONSOLE_TAG} but the registry does not have it; run ./console.sh build (or delete values-console.yaml for the stock image)"
  EXTRA_CP_VALUES+=(--values values-console.yaml)
fi
# Audit events go to the observability plane; only configure them when it is installed
# (the upstream quick start does the same), otherwise the API would reference a plane
# that never exists.
AUDIT_FLAGS=()
[[ $WITH_OBSERVABILITY == true ]] && AUDIT_FLAGS=(--set openchoreoApi.config.audit.enabled=true
  --set openchoreoApi.config.audit.observabilityPlaneRef.kind=ClusterObservabilityPlane
  --set openchoreoApi.config.audit.observabilityPlaneRef.name=default)
H upgrade --install openchoreo-control-plane "${OC_CHARTS}/openchoreo-control-plane" \
  -n "$CP_NS" --version "$OPENCHOREO_VERSION" --values values-cp.yaml ${EXTRA_CP_VALUES[@]+"${EXTRA_CP_VALUES[@]}"} \
  ${AUDIT_FLAGS[@]+"${AUDIT_FLAGS[@]}"} --server-side=false --timeout 30m >/dev/null
# The portal keeps SQLite on a ReadWriteOnce PVC (values-console.yaml); the chart has no
# strategy knob, and the default RollingUpdate would run two writers on the same files.
# Helm's three-way merge leaves this field alone because the chart does not set it.
K patch deployment backstage -n "$CP_NS" --type merge -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}' >/dev/null
# rollout status (not condition=Available): on a re-run the old pods keep the
# Deployment Available while the new ones may still be pulling or crash-looping.
for d in cluster-gateway openchoreo-api backstage; do
  K rollout status deployment/"$d" -n "$CP_NS" --timeout=900s >/dev/null || die "deployment $d did not roll out; check: kubectl --context $KCTX get pods -n $CP_NS"
done
for d in $(K get deployment -n "$CP_NS" -o name); do
  K rollout status "$d" -n "$CP_NS" --timeout=300s >/dev/null || warn "$d has not finished rolling out yet"
done

log "cluster-gateway CA -> ConfigMaps"
K wait -n "$CP_NS" --for=condition=Ready certificate/cluster-gateway-ca --timeout=180s >/dev/null
CA_CRT=$(K get secret cluster-gateway-ca -n "$CP_NS" -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d || true)
[[ -n $CA_CRT ]] || die "cluster-gateway-ca secret has empty ca.crt"
for ns in "$CP_NS" "$DP_NS"; do
  K create configmap cluster-gateway-ca --from-literal=ca.crt="$CA_CRT" -n "$ns" --dry-run=client -o yaml | K apply -f - >/dev/null
done

# ------------------------------------------------------------------- data plane
log "OpenChoreo Data Plane chart ${OPENCHOREO_VERSION}"
reset_failed_release openchoreo-data-plane "$DP_NS"
H upgrade --install openchoreo-data-plane "${OC_CHARTS}/openchoreo-data-plane" \
  -n "$DP_NS" --version "$OPENCHOREO_VERSION" --values values-dp.yaml --wait --timeout 30m >/dev/null

log "ClusterDataPlane 'default'"
for _ in $(seq 1 60); do K get secret cluster-agent-tls -n "$DP_NS" >/dev/null 2>&1 && break; sleep 2; done
AGENT_CA=$(K get secret cluster-agent-tls -n "$DP_NS" -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d || true)
[[ -n $AGENT_CA ]] || die "cluster-agent-tls secret missing in $DP_NS"
K apply -f - >/dev/null <<YAML
apiVersion: openchoreo.dev/v1alpha1
kind: ClusterDataPlane
metadata:
  name: default
spec:
  planeID: default
  clusterAgent:
    clientCA:
      value: |
$(sed 's/^/        /' <<<"$AGENT_CA")
  secretStoreRef:
    name: default
  gateway:
    ingress:
      external:
        http:
          host: openchoreoapis.localhost
          listenerName: http
          port: ${DP_HTTP_PORT}
        name: gateway-default
        namespace: ${DP_NS}
YAML

log "Default resources (project, environments, component types, pipeline)"
for _ in $(seq 1 30); do K get crd projects.openchoreo.dev >/dev/null 2>&1 && break; sleep 2; done
applied=false
for i in 1 2 3; do
  if K apply -f "${RAW}/samples/getting-started/all.yaml" >/dev/null; then applied=true; break; fi
  [[ $i -lt 3 ]] && { warn "applying ${RAW}/samples/getting-started/all.yaml failed (attempt $i/3), retrying"; sleep 5; }
done
$applied || die "could not apply the default resources from ${RAW}/samples/getting-started/all.yaml"
K label namespace default openchoreo.dev/control-plane=true --overwrite >/dev/null

# ----------------------------------------------------------------- host access
log "Host port forwarder"
./start-lb.sh

# --------------------------------------------------------- observability plane
if [[ $WITH_OBSERVABILITY == true ]]; then
  ./observability.sh install
else
  warn "WITH_OBSERVABILITY=false: observability plane skipped"
fi

log "Verifying"
for _ in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://openchoreo.localhost:${CP_HTTP_PORT}/" || true)
  [[ $code =~ ^(200|302|304)$ ]] && break; sleep 3
done
echo "  Backstage HTTP: ${code:-n/a}   API: $(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://api.openchoreo.localhost:${CP_HTTP_PORT}/health || true)   Thunder: $(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://thunder.openchoreo.localhost:${CP_HTTP_PORT}/health/liveness || true)"
K get clusterdataplane default -o wide 2>/dev/null || true

THUNDER_PW=$(K get secret -n "$THUNDER_NS" thunder-admin-credentials -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || true)
cat <<TXT

OpenChoreo installed on ${KCTX}.
  Console (Backstage):  http://openchoreo.localhost:${CP_HTTP_PORT}/    admin@openchoreo.dev / ${ADMIN_PASSWORD}
                        developer@openchoreo.dev / ${DEVELOPER_PASSWORD}
                        platform-engineer@openchoreo.dev / ${PE_PASSWORD}
                        sre@openchoreo.dev / ${SRE_PASSWORD}
                        (generated; ./secrets.sh show prints them again)
  OpenChoreo API:       http://api.openchoreo.localhost:${CP_HTTP_PORT}/
  ThunderID console:    http://thunder.openchoreo.localhost:${CP_HTTP_PORT}/console   admin / ${THUNDER_PW:-<see secret thunder-admin-credentials in ns $THUNDER_NS>}
  Workload endpoints:   http://<component>.openchoreoapis.localhost:${DP_HTTP_PORT}/
  Observer API:         http://observer.openchoreo.localhost:${OP_HTTP_PORT}/   (WITH_OBSERVABILITY=${WITH_OBSERVABILITY})

Sample app:  kubectl --context ${KCTX} apply -f ${RAW}/samples/from-image/react-starter-web-app/react-starter.yaml
TXT
