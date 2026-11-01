#!/usr/bin/env bash
# Publishes the OpenChoreo gateway NodePorts on the host (like kind extraPortMappings,
# but added after cluster creation). Runs a tiny socat container on the kind docker
# network with --restart unless-stopped, so it survives reboots.
# Ports are bound to 0.0.0.0 (IPv4) only: with a dual-stack docker network Colima/Lima
# forwards the host port to the guest IPv6 listener, which cannot reach the container.
# Idempotent: the container is only replaced when the desired port map, node or
# image changed (label openchoreo-kind.spec), so re-running install.sh does not drop
# connections. uninstall.sh removes it; platform-gitops/scripts/down.sh does not know it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"; source ./env.sh

SPEC="${SOCAT_IMAGE}|${KIND_NODE}|${CP_HTTP_PORT}:${CP_HTTP_NODEPORT}|${DP_HTTP_PORT}:${DP_HTTP_NODEPORT}|${OP_HTTP_PORT}:${OP_HTTP_NODEPORT}|${REMOTE_PORT}:${REMOTE_NODEPORT}"
if [[ $(docker inspect -f '{{.State.Running}} {{index .Config.Labels "openchoreo-kind.spec"}}' "$LB_CONTAINER" 2>/dev/null) == "true $SPEC" ]]; then
  ok "forwarder '$LB_CONTAINER' already running with the current port map"; exit 0
fi
docker rm -f "$LB_CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$LB_CONTAINER" --restart unless-stopped --label "openchoreo-kind.spec=$SPEC" \
  --network "$KIND_DOCKER_NET" \
  -p "0.0.0.0:${CP_HTTP_PORT}:${CP_HTTP_PORT}" \
  -p "0.0.0.0:${DP_HTTP_PORT}:${DP_HTTP_PORT}" \
  -p "0.0.0.0:${REMOTE_PORT}:${REMOTE_PORT}" \
  -p "0.0.0.0:${OP_HTTP_PORT}:${OP_HTTP_PORT}" \
  --entrypoint sh "$SOCAT_IMAGE" -c "
    socat TCP-LISTEN:${CP_HTTP_PORT},fork,reuseaddr TCP:${KIND_NODE}:${CP_HTTP_NODEPORT} &
    socat TCP-LISTEN:${DP_HTTP_PORT},fork,reuseaddr TCP:${KIND_NODE}:${DP_HTTP_NODEPORT} &
    socat TCP-LISTEN:${OP_HTTP_PORT},fork,reuseaddr TCP:${KIND_NODE}:${OP_HTTP_NODEPORT} &
    exec socat TCP-LISTEN:${REMOTE_PORT},fork,reuseaddr TCP:${KIND_NODE}:${REMOTE_NODEPORT}
  " >/dev/null
ok "forwarder '$LB_CONTAINER' running: host :$CP_HTTP_PORT -> $KIND_NODE:$CP_HTTP_NODEPORT, :$DP_HTTP_PORT -> :$DP_HTTP_NODEPORT, :$OP_HTTP_PORT -> :$OP_HTTP_NODEPORT, :$REMOTE_PORT -> :$REMOTE_NODEPORT"
