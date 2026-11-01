#!/usr/bin/env bash
# Credentials for the OpenChoreo install are generated here, never committed.
#
# Sourced by install.sh / observability.sh (ensure_secrets, render_values) and
# usable on its own:
#   ./secrets.sh show      print the generated credentials
#   ./secrets.sh render    rebuild .rendered/ from upstream/ templates
#
# Storage: .secrets.env (git-ignored) next to this file, mirrored into the
# Kubernetes Secret openchoreo-kind-credentials in the control-plane namespace
# so a fresh checkout can recover them from a running cluster. The upstream
# values files keep their structure and carry @@NAME@@ tokens where the k3d
# quick start has literal demo secrets; render_values substitutes them into
# .rendered/ (git-ignored).
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then set -euo pipefail; cd "$(dirname "${BASH_SOURCE[0]}")"; fi
[[ -n ${KCTX:-} ]] || source ./env.sh
SECRETS_FILE="${SECRETS_FILE:-.secrets.env}"
SECRETS_K8S_NAME=openchoreo-kind-credentials
RENDER_DIR=.rendered

# Every generated value. Passwords satisfy Thunder's and OpenSearch's
# complexity rules (upper, lower, digit, symbol, >= 12 chars).
SECRET_VARS=(
  BAO_ROOT_TOKEN
  BACKSTAGE_BACKEND_SECRET BACKSTAGE_CLIENT_SECRET
  OBSERVER_CLIENT_SECRET RCA_CLIENT_SECRET FINOPS_CLIENT_SECRET
  OPENSEARCH_PASSWORD OPENOBSERVE_PASSWORD SAMPLE_PASSWORD
  CUSTOMER_PORTAL_CLIENT_SECRET SYSTEM_APP_CLIENT_SECRET SERVICE_MCP_CLIENT_SECRET
  WORKLOAD_PUBLISHER_CLIENT_SECRET MCP_E2E_CLIENT_SECRET
  ADMIN_PASSWORD DEVELOPER_PASSWORD PE_PASSWORD SRE_PASSWORD
)

_rand() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-32}"; }
_password() { printf 'Aa1!%s' "$(_rand 20)"; }

_generate() {
  local v
  for v in "${SECRET_VARS[@]}"; do
    case $v in
      *_PASSWORD) printf -v "$v" '%s' "$(_password)" ;;
      *)          printf -v "$v" '%s' "$(_rand 40)" ;;
    esac
  done
}

_write_file() {
  local v; : > "$SECRETS_FILE"; chmod 600 "$SECRETS_FILE"
  for v in "${SECRET_VARS[@]}"; do printf '%s=%s\n' "$v" "${!v}" >> "$SECRETS_FILE"; done
}

_load_file() { # shellcheck disable=SC1090
  set -a; source "$SECRETS_FILE"; set +a
  local v; for v in "${SECRET_VARS[@]}"; do [[ -n ${!v:-} ]] || return 1; done
}

_load_k8s() {
  local json v; json=$(K -n "$CP_NS" get secret "$SECRETS_K8S_NAME" -o json 2>/dev/null) || return 1
  for v in "${SECRET_VARS[@]}"; do
    printf -v "$v" '%s' "$(python3 -c 'import sys,json,base64; d=json.load(sys.stdin)["data"]; print(base64.b64decode(d.get(sys.argv[1],"")).decode())' "$v" <<<"$json")"
    [[ -n ${!v} ]] || return 1
  done
}

_store_k8s() {
  K create namespace "$CP_NS" --dry-run=client -o yaml | K apply -f - >/dev/null
  K -n "$CP_NS" create secret generic "$SECRETS_K8S_NAME" --from-env-file="$SECRETS_FILE" --dry-run=client -o yaml | K apply -f - >/dev/null
}

# Load (file, then cluster) or generate; always leaves both copies in place.
ensure_secrets() {
  if [[ -f $SECRETS_FILE ]] && _load_file; then
    :
  elif _load_k8s; then
    warn "credentials recovered from Secret $CP_NS/$SECRETS_K8S_NAME into $SECRETS_FILE"
    _write_file
  else
    log "Generating credentials ($SECRETS_FILE, Secret $CP_NS/$SECRETS_K8S_NAME)"
    _generate; _write_file
  fi
  local v; for v in "${SECRET_VARS[@]}"; do export "$v"; done
  _store_k8s
}

# upstream/<name>.yaml with @@VAR@@ tokens -> .rendered/<name>.yaml
render_values() {
  mkdir -p "$RENDER_DIR"
  local f out
  for f in upstream/*.yaml; do
    out="$RENDER_DIR/$(basename "$f")"
    python3 - "$f" "$out" <<'PY' || die "rendering $f failed"
import os, re, sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
missing = set()
def sub(m):
    v = os.environ.get(m.group(1))
    if v is None: missing.add(m.group(1)); return m.group(0)
    return v
text = re.sub(r'@@([A-Z_]+)@@', sub, text)
if missing: sys.exit(f"{src}: no value for {', '.join(sorted(missing))}")
open(dst, 'w').write(text); os.chmod(dst, 0o600)
PY
  done
}

show() {
  ensure_secrets
  cat <<TXT
Console users (Thunder):
  admin@openchoreo.dev              ${ADMIN_PASSWORD}
  developer@openchoreo.dev          ${DEVELOPER_PASSWORD}
  platform-engineer@openchoreo.dev  ${PE_PASSWORD}
  sre@openchoreo.dev                ${SRE_PASSWORD}
OpenBao dev root token:             ${BAO_ROOT_TOKEN}
OpenSearch admin:                   admin / ${OPENSEARCH_PASSWORD}
Thunder client secrets:
  openchoreo-backstage-client       ${BACKSTAGE_CLIENT_SECRET}
  openchoreo-system-app             ${SYSTEM_APP_CLIENT_SECRET}
  service_mcp_client                ${SERVICE_MCP_CLIENT_SECRET}
  openchoreo-workload-publisher     ${WORKLOAD_PUBLISHER_CLIENT_SECRET}
  observer / rca / finops           ${OBSERVER_CLIENT_SECRET} / ${RCA_CLIENT_SECRET} / ${FINOPS_CLIENT_SECRET}
  customer-portal / mcp-e2e         ${CUSTOMER_PORTAL_CLIENT_SECRET} / ${MCP_E2E_CLIENT_SECRET}
Stored in ${SECRETS_FILE} and Secret ${CP_NS}/${SECRETS_K8S_NAME}.
TXT
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  case "${1:-show}" in
    show)   show ;;
    render) ensure_secrets; render_values; ok "rendered upstream/*.yaml into $RENDER_DIR/" ;;
    *) die "usage: $0 show|render" ;;
  esac
fi
