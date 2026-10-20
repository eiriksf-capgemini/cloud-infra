#!/usr/bin/env python3
"""Print the IPv4 prefixes registered to a country (ISO 3166-1 alpha-2), one per line,
collapsed into the smallest equivalent set. Source: RIPEstat country-resource-list, which
aggregates all five RIRs' delegated statistics.

    scripts/country-prefixes.py NO > live/azure/poc/allowlist/no-ipv4.txt

Registration country is not geolocation: cloud and proxy egress ranges (e.g. Zscaler's
Oslo datacenters) are often registered elsewhere. Add those explicitly in the stack's
`ingress_extra_sources`; do not hand-edit the generated file.
"""
import ipaddress, json, sys, urllib.request, datetime

if len(sys.argv) != 2 or len(sys.argv[1]) != 2:
    sys.exit(__doc__)
country = sys.argv[1].upper()
url = f"https://stat.ripe.net/data/country-resource-list/data.json?resource={country}&v4_format=prefix"
try:
    with urllib.request.urlopen(url, timeout=60) as r:
        body = json.load(r)
    data = body["data"]
    raw = [ipaddress.ip_network(p, strict=True) for p in data["resources"]["ipv4"]]
except Exception as e:  # network error, non-JSON, unexpected shape, non-CIDR entry
    sys.exit(f"country-prefixes: failed to fetch or parse RIPEstat data for {country}: {e!r}")
if body.get("status") != "ok" or len(raw) < 10:
    sys.exit(f"country-prefixes: implausible result for {country}: status={body.get('status')} prefixes={len(raw)}; nothing written")
nets = sorted(ipaddress.collapse_addresses(raw), key=lambda n: (int(n.network_address), n.prefixlen))
print(f"# IPv4 prefixes registered to {country}: {len(raw)} allocations collapsed to {len(nets)} prefixes.")
print(f"# Generated {datetime.date.today().isoformat()} by scripts/country-prefixes.py from {url}")
print(f"# RIPEstat data time: {data.get('query_time')}. Refresh: make allowlist-refresh COUNTRY={country}")
for n in nets:
    print(n)
