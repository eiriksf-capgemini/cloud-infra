#!/usr/bin/env bash
# Start the POC AKS cluster and keep polling until it is usable, reporting each stage.
# Usage: scripts/aks-start-wait.sh [--rg <rg>] [--name <cluster>] [--timeout <seconds>] [--no-start]
# Exit 0 when the console is reachable, 1 on timeout (with the latest status printed), 2 on usage.
#
# A cold start takes several minutes beyond `az aks start` returning: the node registers,
# then Argo CD, ingress-nginx, kgateway and its proxy, Thunder and Backstage come up in that
# order. During that window the console answers 503 or shows login and catalog errors, which
# is what this script waits out (ADR 0004 cost controls stop the cluster twice a day).
set -euo pipefail

RG="${AKS_RG:-rg-cloudinfra-poc}"
NAME="${AKS_NAME:-aks-cloudinfra-poc}"
TIMEOUT="${AKS_START_TIMEOUT:-1200}"
START=1
while [ $# -gt 0 ]; do
  case "$1" in
    --rg) RG="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --no-start) START=0; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

T0=$(date +%s)
elapsed() { echo "$(( $(date +%s) - T0 ))s"; }
say()  { printf '\033[1;34m==>\033[0m %s  (%s)\n' "$*" "$(elapsed)"; }
ok()   { printf '\033[1;32m ✓\033[0m %s  (%s)\n' "$*" "$(elapsed)"; }
fail() { printf '\033[1;31m ✗\033[0m %s  (%s)\n' "$*" "$(elapsed)" >&2; }
left() { echo $(( TIMEOUT - ($(date +%s) - T0) )); }

# wait <label> <command...>: poll every 10 s until the command succeeds or the budget is spent.
wait_for() {
  local label="$1"; shift
  local last=""
  while :; do
    if last=$("$@" 2>&1); then ok "$label${last:+: $last}"; return 0; fi
    if [ "$(left)" -le 0 ]; then fail "timed out waiting for $label; last status: ${last:-none}"; return 1; fi
    sleep 10
  done
}

power() { az aks show -g "$RG" -n "$NAME" --query 'powerState.code' -o tsv 2>/dev/null; }

if [ "$START" -eq 1 ]; then
  case "$(power)" in
    Running) say "cluster $NAME already reports Running; checking that it is usable" ;;
    *) say "starting $NAME in $RG (az aks start blocks until the control plane is up)"
       az aks start -g "$RG" -n "$NAME" --only-show-errors >/dev/null
       ok "control plane started" ;;
  esac
fi

say "waiting for the API server (DNS + auth), the node, and the platform workloads"
wait_for "API server reachable"  kubectl get --raw /readyz
wait_for "node Ready" sh -c 'kubectl get nodes --no-headers | awk "\$2==\"Ready\"{n++} END{if(n<1) exit 1; print n\" node(s) Ready\"}"'

# Workloads that gate the console, in the order they usually come up. Each prints ready/desired.
deploy_ready() { # ns name
  kubectl -n "$1" get deploy "$2" -o jsonpath='{.status.readyReplicas}/{.spec.replicas}' 2>/dev/null \
    | awk -F/ -v l="$1/$2" '{ if ($1=="" || $1=="0" || $1!=$2) { print l": "$0; exit 1 } print l": "$0 }'
}
wait_for "Argo CD controller" sh -c 'kubectl -n platform get statefulset argocd-application-controller -o jsonpath="{.status.readyReplicas}" | grep -qx 1 && echo "platform/argocd-application-controller: 1/1"'
wait_for "ingress-nginx"     deploy_ready ingress-nginx ingress-nginx-controller
wait_for "kgateway"          deploy_ready openchoreo-control-plane kgateway
wait_for "gateway proxy"     deploy_ready openchoreo-control-plane gateway-default
wait_for "Thunder"           deploy_ready thunder thunder-deployment
wait_for "OpenChoreo API"    deploy_ready openchoreo-control-plane openchoreo-api
wait_for "Backstage"         deploy_ready openchoreo-control-plane backstage

CONSOLE="https://console.openchoreo.20.91.237.179.nip.io"
CA="${POC_ROOT_CA:-$HOME/.config/poc-root-ca.crt}"
CURL=(curl -s --max-time 15 -o /dev/null -w '%{http_code}')
[ -f "$CA" ] && CURL+=(--cacert "$CA") || CURL+=(-k)
wait_for "console answers"   sh -c "code=\$(${CURL[*]} $CONSOLE/.backstage/health/v1/readiness); [ \"\$code\" = 200 ] && echo \"$CONSOLE -> 200\""
wait_for "Thunder answers"   sh -c "code=\$(${CURL[*]} https://thunder.openchoreo.20.91.237.179.nip.io/.well-known/openid-configuration); [ \"\$code\" = 200 ] && echo \"thunder -> 200\""

# Pods left behind by the stop (ContainerStatusUnknown) are cosmetic but confusing; report them.
stale=$(kubectl get pods -A --no-headers 2>/dev/null | awk '$4 ~ /ContainerStatusUnknown|Unknown/ {print $1"/"$2}' | tr '\n' ' ')
[ -n "$stale" ] && say "stale pods from the stop (safe to delete): $stale"

printf '\033[1;32m==> ready\033[0m %s  node %s  total %s\n' "$CONSOLE" "$(kubectl get nodes --no-headers | awk '{print $1}' | head -1)" "$(elapsed)"
