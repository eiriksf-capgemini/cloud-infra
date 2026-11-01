#!/usr/bin/env bash
# In-cluster DNS: pods (Backstage, Thunder, API) talk to each other through the public
# *.openchoreo.localhost:8080 URLs. k3d rewrites those to host.k3d.internal; kind's
# kubeadm CoreDNS has no import hook, so we patch the Corefile and point the names
# straight at the kgateway Services (whose ports equal the public ports).
#   coredns.sh apply   | coredns.sh remove
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"; source ./env.sh
MARK_BEGIN="    # BEGIN openchoreo-kind"
MARK_END="    # END openchoreo-kind"
BACKUP=".coredns-corefile.backup"

current() { K -n kube-system get cm coredns -o jsonpath='{.data.Corefile}'; }
write()   { K -n kube-system create cm coredns --from-file=Corefile=/dev/stdin --dry-run=client -o yaml | K apply -f - >/dev/null; }

case "${1:-apply}" in
  apply)
    cf=$(current)
    [[ -f $BACKUP ]] || printf '%s\n' "$cf" > "$BACKUP"
    if grep -q "openchoreo-kind" <<<"$cf"; then
      if grep -q "gateway-default.${OP_NS}.svc" <<<"$cf"; then ok "CoreDNS rewrite already present"; exit 0; fi
      warn "CoreDNS rewrite present without the observability rule; replacing it"
      cf=$(sed "/$(sed 's/[][\/.*^$]/\\&/g' <<<"$MARK_BEGIN")/,/$(sed 's/[][\/.*^$]/\\&/g' <<<"$MARK_END")/d" <<<"$cf")
    fi
    # Order matters: rewrite stop is first-match, so the observability names must
    # precede the generic *.openchoreo.localhost rule (the observer listens on 11080
    # on its own gateway, not on the control-plane gateway).
    block="$MARK_BEGIN
    rewrite stop {
      name regex (observer|rca-agent|finops-agent)\.openchoreo\.localhost gateway-default.${OP_NS}.svc.cluster.local
      answer auto
    }
    rewrite stop {
      name regex (.*\.)?openchoreo\.localhost gateway-default.${CP_NS}.svc.cluster.local
      answer auto
    }
    rewrite stop {
      name regex (.*\.)?openchoreoapis\.localhost gateway-default.${DP_NS}.svc.cluster.local
      answer auto
    }
$MARK_END"
    # insert right after the "ready" plugin line (python: BSD awk cannot take multi-line -v vars)
    new_cf=$(BLOCK="$block" python3 -c '
import os,sys,re
cf=sys.stdin.read(); blk=os.environ["BLOCK"]
out=[]; done=False
for line in cf.splitlines():
    out.append(line)
    if not done and re.match(r"^\s*ready\s*$", line):
        out.append(blk); done=True
if not done: sys.exit("no `ready` line found in Corefile")
print("\n".join(out))' <<<"$cf")
    [[ -n $new_cf ]] || die "failed to build new Corefile; original left untouched"
    write <<<"$new_cf"
    K -n kube-system rollout restart deployment coredns >/dev/null
    K -n kube-system rollout status deployment coredns --timeout=120s >/dev/null
    ok "CoreDNS rewrite for *.openchoreo.localhost / *.openchoreoapis.localhost / observer applied"
    ;;
  remove)
    cf=$(current)
    grep -q "openchoreo-kind" <<<"$cf" || { ok "CoreDNS rewrite not present"; exit 0; }
    sed "/$(sed 's/[][\/.*^$]/\\&/g' <<<"$MARK_BEGIN")/,/$(sed 's/[][\/.*^$]/\\&/g' <<<"$MARK_END")/d" <<<"$cf" | write
    K -n kube-system rollout restart deployment coredns >/dev/null
    ok "CoreDNS rewrite removed"
    ;;
  *) die "usage: $0 apply|remove" ;;
esac
