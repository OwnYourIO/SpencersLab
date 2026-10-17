# 2026-09-07 — Traefik OIDC login loop (cluster.proxy-local & friends)

## Status: INVESTIGATED — fix is a Keycloak runtime config change (not repo code)

## Symptom

Every visit to `https://cluster.proxy-local.spencerslab.com/` (and all other
subdomains protected by the `oidc-keycloak` Traefik middleware, e.g.
`torrents.spencerslab.com` — the user-facing alias of qbittorrent) redirects
to `login.spencerslab.com` and never completes, even after logging in.

## Root cause

**Keycloak was upgraded to v26.7.2 on 2026-08-20** (commits `2ecf33ba`,
`d0e3020f`, merge `90037d80`). Keycloak 26 added an audience check to the
token introspection endpoint (upstream PR #49131, fixing CVE-2026-37979):
introspection now returns `active: false` unless the client performing the
introspection is present in the token's `aud` claim.

The `keycloakopenid` Traefik plugin (jmcarbo/keycloakopenid v0.1.40,
`verifyToken()` in main.go) validates every request by POSTing the cookie
token to `/realms/SpencersLab/protocol/openid-connect/token/introspect`
authenticated as client `traefik`. The `traefik` client has **no Audience
protocol mapper**, so issued tokens carry no `traefik` audience → every
introspection fails → plugin treats the user as unauthenticated → redirect
to Keycloak again → infinite login loop.

## Evidence (Keycloak event log, Loki `{cluster="infra", service_name="keycloakx"}`)

Per attempt, in order:

1. `LOGIN` — user `thehackmeister` authenticates, clientId=traefik,
   redirect_uri=`https://cluster.proxy-local.spencerslab.com/` ✓
2. `CODE_TO_TOKEN` — from 10.0.77.54 (proxy-local traefik), grant
   authorization_code ✓ (secret + connectivity are fine)
3. `INTROSPECT_TOKEN_ERROR` — `error="invalid_token"`,
   `reason="Client 'traefik' is not in the token audience"`,
   `token_issued_for="traefik"` ← **the failure**
4. `LOGIN_ERROR` — `error="invalid_redirect_uri"`,
   redirect_uri=`https://cluster.proxy-local.spencerslab.com/?iss=...`
   (secondary symptom, see below)

Same loop recorded for `torrents.spencerslab.com`.

## The fix (Keycloak admin — not in this repo; clients are UI-managed)

Add an Audience protocol mapper to the `traefik` client so its own ID lands
in `aud`:

Admin console → realm **SpencersLab** → Clients → **traefik** →
*Client scopes* tab → **traefik-dedicated** → *Add mapper* →
*By configuration* → **Audience**:

- Included Client Audience: `traefik`
- Add to access token: ON

(Equivalent admin API: POST a protocolMapper of type
`oidc-audience-mapper` with `included.client.audience: "traefik"`,
`access.token.claim: "true"` to the `traefik-dedicated` client scope.)

Existing browser sessions must re-login once; fresh tokens then carry the
audience and introspection returns active.

## Secondary (latent) plugin bug — no action required for this fix

`redirectToKeycloak()` builds `redirect_uri` from `req.RequestURI`
(full query string included). Keycloak 26 appends `?iss=...` (RFC 9207) to
auth responses, so any retry while query params are present produces a
redirect_uri Keycloak rejects (`invalid_redirect_uri`). With the audience
fix the happy path never retries, so this stops surfacing. It remains a
latent edge case (e.g. token expiry while on a URL with query params) and
is an upstream plugin concern (jmcarbo/keycloakopenid).

## Verified not the cause

- `traefik-sso` ExternalSecret: Ready/SecretSynced; client-id/client-secret
  valid (CODE_TO_TOKEN succeeds).
- Keycloak client `traefik` + redirect_uri `https://cluster.proxy-local.spencerslab.com/`
  registered (auth endpoint renders the login form, 200).
- Network path traefik pod → login.spencerslab.com (10.0.77.59, infra LB) works.
- `qbittorrent.spencerslab.com` itself: 200 from LAN, no auth middleware on
  its ingress — the redirect the user saw there is `torrents.spencerslab.com`
  (qbittorrent's OIDC-protected alias) or the same loop.

## Unrelated issues observed (separate follow-ups)

- Traefik logs TLS errors: `secret kube-system/cluster-wildcard-cert does
  not exist` (traefik dashboard ingress) and `secret default/scifi-farm-cert
  does not exist` (scifi.farm ingress).
- proxy-remote has no router for `qbittorrent.spencerslab.com` → public
  access 404s (LAN split-DNS only today).

## Validation (after applying the mapper)

1. `curl -skI https://cluster.proxy-local.spencerslab.com/` → 307 to Keycloak (unchanged).
2. Browser: log in once → lands on ArgoCD, no bounce-back.
3. Loki: `{cluster="infra", service_name="keycloakx"} |~ "org.keycloak.events"`
   shows `INTROSPECT_TOKEN` without the audience error and no `LOGIN_ERROR
   invalid_redirect_uri` for clientId=traefik.
