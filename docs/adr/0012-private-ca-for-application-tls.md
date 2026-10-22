# ADR 0012: a private CA for application TLS until a DNS zone exists

Date: 2026-10-22
Status: Accepted

## Context

Everything on the POC is reachable over plain HTTP on nip.io hostnames (ADR 0009, 0010),
with one exception: Argo CD, which terminates TLS itself with the self-signed certificate
it generated at install. The owner wants TLS on the applications. There is no DNS zone, so
publicly trusted certificates would have to come from Let's Encrypt for `*.nip.io` names,
whose rate limit (50 certificates a week) is shared by every nip.io user worldwide and
cannot be relied on. cert-manager is already installed (OpenChoreo needs it).

## Decision

1. **cert-manager keeps a private root CA** (`gitops/platform/cluster-issuers`): a
   `selfsigned` ClusterIssuer signs one 10-year CA certificate, `poc-root-ca`, in
   cert-manager's namespace; the `poc-ca` ClusterIssuer signs everything else with it.
2. **Applications ask for certificates the standard way**: an Ingress annotated with
   `cert-manager.io/cluster-issuer: poc-ca` plus a `tls` block (podinfo), or a `Certificate`
   where the application terminates TLS itself (Argo CD's `argocd-server-tls`, which it picks
   up automatically; the ingress passthrough is unchanged). Swapping the CA for a real one
   later is a one-line issuerRef change.
3. **podinfo and Argo CD first, OpenChoreo the same day (2026-10-22).** OpenChoreo's three
   control-plane hosts share one certificate and `*.openchoreoapis.<ip>.nip.io` gets a
   wildcard one, both terminated at ingress-nginx; kgateway behind stays HTTP. Its public
   URLs (API, Backstage base URL and redirect, OIDC issuer/JWKS/authorize/token, Thunder's
   gate client and allowed origins, the Backstage client's redirect URI, the MCP resource
   server identifier) are https. Two trust workarounds from the upstream HTTPS install stay
   until a publicly trusted CA exists: the API skips TLS verification when fetching Thunder's
   JWKS, and Backstage runs with Node's certificate check disabled. Both only affect
   in-cluster calls to hostnames behind the ADR 0009 allowlist.
4. **Trusting the CA is a one-time import on each operator laptop** (README "TLS"). Until
   then browsers warn; the connection is still encrypted.

## Consequences

- argocd-server does not reload `argocd-server-tls` while running (verified 2026-10-22: it kept
  serving the old certificate for minutes until restarted). One `rollout restart` after the
  first issuance; watch the same after renewals.
- HTTP on podinfo redirects to HTTPS; the KEDA interceptor path is unchanged (TLS ends at
  ingress-nginx).
- The root key lives in the `poc-root-ca` Secret in `cert-manager`. Anyone with read access
  there can mint certificates browsers that imported the CA will trust; that is the same
  group that already has cluster-admin. Rotation: delete the Secret, cert-manager re-issues
  the root, re-import.
- Cluster recreate: the root is re-generated (new key), so laptops must import it again.
- Let's Encrypt remains the plan once a zone exists; nothing here blocks it.
