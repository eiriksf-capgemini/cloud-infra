#!/usr/bin/env bash
# Remove everything install.sh added. CRDs are left in place unless you ask:
#   --crds       OpenChoreo, kgateway and prometheus-operator CRDs (nothing else uses them)
#   --all-crds   also Gateway API, cert-manager and External Secrets CRDs, which another
#                tenant of the same cluster may depend on (platform-gitops shares it)
# The generated credentials (.secrets.env) are kept so a re-install reuses them.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"; source ./env.sh
REMOVE_CRDS=false; REMOVE_SHARED_CRDS=false
case "${1:-}" in
  --crds) REMOVE_CRDS=true ;;
  --all-crds) REMOVE_CRDS=true; REMOVE_SHARED_CRDS=true ;;
  "") ;;
  *) die "usage: $0 [--crds|--all-crds]" ;;
esac

log "Stopping host forwarder"; docker rm -f "$LB_CONTAINER" >/dev/null 2>&1 || true
# Order matters: workloads and their Releases are torn down by the controller
# through the data plane, so Components go first, then the sample project /
# environments / pipeline, and only then the ClusterDataPlane. Deleting the
# plane first leaves every Release finalizer waiting forever.
log "Removing OpenChoreo resources"
./observability.sh remove
K delete components.openchoreo.dev --all -A --ignore-not-found --timeout=300s >/dev/null 2>&1 || warn "some Components did not finish deleting"
K delete -f "https://raw.githubusercontent.com/openchoreo/openchoreo/${OPENCHOREO_REF}/samples/getting-started/all.yaml" --ignore-not-found --timeout=300s >/dev/null 2>&1 || warn "some default resources did not finish deleting"
K delete clusterdataplane default --ignore-not-found --timeout=120s
# Anything still terminating now can never finalize (its plane is gone); drop the
# finalizers so the namespaces below can go and the next install.sh is not blocked
# by objects stuck in deletion.
strip_openchoreo_finalizers() { # kubectl's jsonpath cannot filter on field presence, hence python
  local round kind ns name stuck
  for round in 1 2 3 4 5; do
    stuck=$(for k in $(K get crd -o json | python3 -c 'import sys,json; print(" ".join(i["metadata"]["name"] for i in json.load(sys.stdin)["items"] if i["spec"]["group"]=="openchoreo.dev"))'); do
      K get "$k" -A -o json 2>/dev/null | python3 -c 'import sys,json
for it in json.load(sys.stdin).get("items", []):
    m = it["metadata"]
    if m.get("deletionTimestamp") and m.get("finalizers"):
        print(it["kind"], m.get("namespace", "-"), m["name"])'
    done)
    [[ -n $stuck ]] || return 0
    while read -r kind ns name; do
      [[ -n $kind ]] || continue
      warn "removing finalizers from stuck ${kind} ${ns}/${name}"
      if [[ $ns == "-" ]]; then K patch "$kind" "$name" --type merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
      else K patch "$kind" "$name" -n "$ns" --type merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true; fi
    done <<<"$stuck"
    sleep 3
  done
}
strip_openchoreo_finalizers
K label namespace default openchoreo.dev/control-plane- >/dev/null 2>&1 || true
log "Uninstalling OpenChoreo Helm releases"
H uninstall openchoreo-data-plane -n "$DP_NS" 2>/dev/null || true
H uninstall openchoreo-control-plane -n "$CP_NS" 2>/dev/null || true
H uninstall thunder -n "$THUNDER_NS" 2>/dev/null || true
H uninstall kgateway -n "$CP_NS" 2>/dev/null || true
H uninstall kgateway-crds -n "$CP_NS" 2>/dev/null || true
# Namespaces go while External Secrets Operator and cert-manager still run: their
# finalizers (externalsecret-cleanup, certificate cleanup) are cleared by the
# operators, and a namespace holding such objects after the operator is gone
# never finishes terminating.
log "Deleting OpenChoreo namespaces"
K delete ns "$DP_NS" "$CP_NS" "$THUNDER_NS" --ignore-not-found --timeout=300s || warn "a namespace is still terminating; check: kubectl --context $KCTX get ns"
K delete clustersecretstore default --ignore-not-found
H uninstall openbao -n "$OPENBAO_NS" 2>/dev/null || true
K delete ns "$OPENBAO_NS" --ignore-not-found --timeout=180s
log "Uninstalling prerequisites"
H uninstall external-secrets -n external-secrets 2>/dev/null || true
H uninstall cert-manager -n cert-manager 2>/dev/null || true
K delete ns external-secrets cert-manager --ignore-not-found --timeout=180s
./coredns.sh remove
if $REMOVE_CRDS; then
  log "Deleting OpenChoreo, kgateway and prometheus-operator CRDs"
  K get crd -o name | grep -E 'openchoreo\.dev|gateway\.kgateway\.dev|monitoring\.coreos\.com' | xargs -r kubectl --context "$KCTX" delete
  if $REMOVE_SHARED_CRDS; then
    log "Deleting Gateway API, cert-manager and External Secrets CRDs"
    K get crd -o name | grep -E 'gateway\.networking\.k8s\.io|cert-manager\.io|external-secrets\.io|generators\.external-secrets\.io' | xargs -r kubectl --context "$KCTX" delete
  else
    warn "Gateway API, cert-manager and External Secrets CRDs left in place (shared cluster); --all-crds removes them"
  fi
fi
ok "done"
