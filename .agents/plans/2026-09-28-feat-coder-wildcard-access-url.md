# 2026-09-28 feat — coder wildcard access URL

## Goal

Enable Coder subdomain-based workspace app access / dashboard port forwarding
by setting `CODER_WILDCARD_ACCESS_URL` on the Coder deployment (gpu cluster).

## Context

- Coder is deployed in gpu as an **external chart** (`https://helm.coder.com/v2`
  v2.35.2, `charts.coder` in `services/gpu/prod/values.yaml`).
- Its config arrives via `envFrom: coder-secrets`, an ExternalSecret rendered
  by `services/gpu/prod/templates/secrets-coder.yaml` (domain references live
  in the secret template per repo convention, since app-template subcharts
  can't see top-level `.Values.domain`).

## Change

`services/gpu/prod/templates/secrets-coder.yaml` — one line added to the
ExternalSecret template `data:` block, right after `CODER_ACCESS_URL`:

```yaml
CODER_WILDCARD_ACCESS_URL: "*.{{ $.Values.domain }}"
```

Format notes (per Coder docs, coder.com/docs/admin/networking/wildcard-access-url):

- Exactly one `*` at the start of the hostname, no scheme.
- `*.{{ domain }}` (not `*.coder.{{ domain }}`) chosen deliberately: the base
  chart's `wildcard-cert` covers `*.{{ domain }}` (see
  `charts/base/templates/cert-manager-wildcard-cert.yaml`), so existing TLS
  covers the app subdomains. A `*.coder.<domain>` URL would need a second
  wildcard cert + DNS record.

## Validation

- `helm lint services/gpu/prod` — passes (one pre-existing, unrelated warning
  about `cluster-OVERRIDE_VIA_APPSET-ingress` naming, resolved by the appset
  at deploy time).
- `helm template gpu services/gpu/prod --set domain=example.com --show-only
  templates/secrets-coder.yaml` — renders
  `CODER_WILDCARD_ACCESS_URL: "*.example.com"`; the escaped ExternalSecret
  template expressions (`{{ .pg_username }}` etc.) preserved intact; no
  `OVERRIDE_*` sentinels in the output.

## Follow-ups NOT done (out of scope, user-owned)

- **DNS/ingress routing for app subdomains**: for `app--agent--ws--user.<domain>`
  to actually reach the Coder service, the proxy chain (proxy-remote →
  proxy-local → gpu traefik) needs a wildcard route for `*.<domain>` → coder
  (or a dedicated wildcard ingress on gpu). Verify/ add when testing.
- Rollout: ArgoCD syncs the gpu Application; pod restarts via reloader when
  the secret changes.

---

# Revision 2026-09-28 — pivot to coder-chart env + wildcard ingress

The secret-based `CODER_WILDCARD_ACCESS_URL` (above) landed in `main` via
`ac99347fc`, then got superseded the same day per user request:

## New design

1. **`services/gpu/prod/templates/secrets-coder.yaml`** —
   `CODER_WILDCARD_ACCESS_URL: "*-coder.{{ $.Values.domain }}"` in the
   ExternalSecret template (next to `CODER_ACCESS_URL`). The umbrella
   context CAN template `.Values.domain`, so no domain string is hardcoded.
   (History: ac99347fc first shipped `*.{{ domain }}` here; it was briefly
   moved into the coder chart's `env` as `*-coder.spencerslab.com`, then
   moved back here — the secret/envFrom is the single source of truth;
   apps resolve at `<app>--<agent>--<ws>--<user>-coder.<domain>`.)
2. **`services/gpu/prod/values.yaml`** `coder.coder`:
   - `ingress.enable: true` + `ingress.tls.{enable,secretName}` =
     `wildcard-cert` (all domain-independent, so they stay here)
3. **`custom-values/gpu/prod-values.yaml`** new top-level block:
   `coder.coder.ingress.host: "*.spencerslab.com"` — the domain string comes
   from custom-values because the external coder chart's values slice is raw
   JSON (appset `index $.Values "coder" | toJson`), never templated, so
   `.Values.domain` is unavailable there. Mechanism: the custom-values URL
   already rides the umbrella appset's `valueFiles` (service-wide
   `customValuesUrls` annotation), merges into the umbrella/base `.Values`,
   and the per-app appset slices `index $.Values "coder"` — same proven path
   as hivetools' `bitwardenIds`. Helm merge semantics: maps merge (ingress
   keys combine), lists replace (which is why `env` stays in the service
   values — a custom-values `env` list would have replaced it whole).

   **Carrying the wildcard in `host` (not `wildcardHost`)**: the chart
   renders the `ingress.host` rule + paired TLS entry unconditionally, so an
   empty `host` would produce an invalid TLS entry (empty host rejected by
   the API). Setting `host: "*.spencerslab.com"` is a legal Ingress wildcard
   host and renders exactly what the chart's own wildcard rule renders — one
   rule + one TLS entry. The plain `coder.<domain>` host is covered by the
   gpu generic-ingress, so it deliberately does NOT appear in the coder
   chart's ingress (user revision: "remove host, covered elsewhere");
   `tls.wildcardSecretName` and `wildcardHost` are therefore unused.

## Coder chart specifics (verified against coder-2.35.2, helm.coder.com/v2)

- Ingress is gated on `coder.ingress.enable` (default `false`).
- The `coder.ingressWildcardHost` helper strips any `-suffix` after `*`, so
  `*-coder.<domain>` and `*.<domain>` both render the ingress host
  `*.spencerslab.com` — a legal Ingress host that `wildcard-cert` covers.
- Chart renders Service `coder` :80; ingress backend is `name: http`.
- The `host: coder.spencerslab.com` rule duplicates the umbrella
  generic-ingress rule for the same host — harmless (identical backend).

## Validation

- Rendered the real coder-2.35.2 chart with the merged slices
  (`helm template /tmp/opencode/coder -f slice-svc.yaml -f slice-cust.yaml`):
  Ingress has exactly one rule `*.spencerslab.com` → `coder:http` and one TLS
  entry on `wildcard-cert` (no `coder.<domain>` host — covered by the gpu
  generic-ingress); Deployment has no wildcard env of its own — it arrives via
  `envFrom: coder-secrets`, which the umbrella render shows templating to
  `CODER_WILDCARD_ACCESS_URL: "*-coder.spencerslab.com"` from `.Values.domain`.
- `helm lint services/gpu/prod` ✅, `helm template` of the umbrella ✅
  (single CODER_WILDCARD hit = the values blob inside the appset generator).

## Still user-owned (unchanged)

- **Wildcard DNS**: `*.spencerslab.com` must resolve at the edge
  (proxy-remote) for app subdomains to arrive — check the DNS provider.
- Verify TLS/proxy chain accepts the app subdomains end-to-end once synced.
