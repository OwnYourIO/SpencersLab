# RESEARCH — SSO-backed git auth for Coder workspaces (Forgejo as OAuth issuer, Keycloak backing)

Research pass for the replan of `feat-forgejo-auth-support` (C01–C03 shipped the shared-Bitwarden-PAT model; the user now wants, in their words, "SSO approval of sorts ... going against forgejo, but that's backed by keycloak" for the Coder side).
Method: STORM — 5 grounded perspectives, live lab probes, primary docs/source only. All research performed 2026-10-24; citation keys `[n]` → Sources table at the bottom. STORM trail (raw notes/sources per perspective) in `/tmp/opencode/storm-forgejo-sso-run/sso-backed-git-auth-for-coder-workspaces-via-forgejo-as/` (ephemeral scratch; the numbering matches).

## TL;DR

1. The requested flow **exists natively in the deployed Coder v2.35.2**: a `gitea`-type External Auth Provider turns Forgejo into the OAuth issuer, the browser approval chain completes on coderd itself, tokens are per-user, auto-refreshed, and auto-injected into workspace git over HTTPS via `GIT_ASKPASS` [2,7,24,25].
2. **Coder hard-caps Community licenses at ONE external-auth provider** (source-enforced) — full OAuth for both lab forges is a paid-tier feature; the realistic open-source shape is OAuth-for-one-instance + PAT-for-the-other hybrid [1,9,10].
3. Forgejo 15.0.9 (live-verified) does authorization_code + PKCE + refresh but has **no device flow** (open issue #4830) and **no OAuth scopes — a grant is the user's full account**, unlike the current scoped PATs [12,16,19,27]; the human approval is one consent click through the existing Keycloak sessions [24,28].
4. The `fj` CLI already contains an **OAuth `fj auth login`** that stores a self-refreshing token chain on the home PVC — a vault-free per-user alternative that bootstraps on a laptop only, not in the workspace [33,34].
5. Keep the shipped PAT path for bootstrapping, OpenChamber and any second forge; it and the OAuth path **layer deterministically per host** (git consults credential helpers before askpass), so the hybrid costs ~one conditional in the existing script [38,40].

## Key findings

### A. Deployed-version facts (live-verified 2026-10-24, this lab)

- Coder server image `ghcr.io/coder/coder:v2.35.2` (dev cluster, `default/coder` Deployment) — matches charts/coder appVersion [32-class repo evidence; cluster read via readonly-dev-kubernetes].
- Forgejo **15.0.9+gitea-1.22.0** on both instances (`/api/v1/version` on git.scifi.farm and git.spencerslab.com; pod images `code.forgejo.org/forgejo/forgejo:15.0.9-rootless`). Current Forgejo docs line is v17.0.0; **v15 is the active LTS (15.0.10 published)** — the lab is one LTS patch behind [12,23].
- Keycloak 26.7.2 (infra cluster, realm SpencersLab) backs Coder OIDC + both forges' `oauth:` source today (charts/coder `secret-coder.yaml`, charts/forgejo values, services/dev header) [31].
- Live OAuth endpoint probes on both forges [27,28]:
  - `/.well-known/openid-configuration` → **200** — Forgejo 15 **is an OIDC provider**: `grant_types_supported: [authorization_code, refresh_token]`, `code_challenge_methods_supported: [plain, S256]`, `scopes_supported: [openid, profile, email, groups]`, no `device_authorization_endpoint`.
  - `/.well-known/oauth-authorization-server` → 404 (no RFC 8414 metadata; OIDC-style discovery only).
  - `POST /login/oauth/access_token` → "Only refresh_token or authorization_code grant type is supported" (device grant rejected in the error itself); `/login/oauth/revoke*` → 404; `/login/oauth/device*` → 404.
  - `GET /login/oauth/authorize?client_id=x` → 303 → `/user/login` (Keycloak-backed) — authorize endpoint live.
  - `/login/oauth/userinfo` → 401 unauthenticated; `/login/oauth/introspect` exists (POST).

### B. Coder-side: what "SSO approval of sorts" concretely is (all confirmed at tag v2.35.2)

1. **Mechanism = External Auth Providers, and it has a first-class Gitea type.** Server env `CODER_EXTERNAL_AUTH_0_ID/TYPE=gitea/CLIENT_ID/CLIENT_SECRET` (+ optional `AUTH_URL/REGEX/DISPLAY_*`) [2]. `giteaDefaults()` derives: PKCE **S256 on by default**, Regex auto-matching the AUTH_URL host, TokenURL `<host>/login/oauth/access_token`, ValidateURL `<host>/login/oauth/userinfo` — every URL matches what the live forges actually serve (§A) [7]. `type=gitea` is in the "enhanced Git provider" set, i.e. the set Coder intercepts for git operations [6]. Self-hosted Gitea precedent with Coder: coder discussion #10451 — terminal `git clone/push` worked over https+ssh (Dec 2023) [5].
2. **In-workspace delivery is three distinct paths with different hygiene:**
   - **GIT_ASKPASS auto** (preferred per Coder's own docs): agent sets `GIT_ASKPASS=/tmp/coder.<rand>/coder`; git HTTPS ops matching a provider's REGEX get the per-user token injected; **Coder stores and refreshes tokens server-side** [2,25]. On an unauthenticated provider the askpass prints **"Open the following URL to authenticate with Git: …"** to stderr (headless-safe — shows up in `coder ssh`/pod logs) and fails the op cleanly; a 404 (no provider matches) falls back to default git behavior = credential helpers [24].
   - **`coder external-auth access-token <id>`** — "validated token to stdout exit 0; else **the authentication URL to stdout with exit 1**" + `--extra` token properties; documented for startup scripts [4]. This is the direct drop-in for `wire_forgejo`/fj seeding without persisting anything (same use-time-expansion posture the shipped script already has [40]).
   - **`data.coder_external_auth.<x>.access_token` at build time** — Coder's docs mark it "hard coded tokens **do not auto-refresh**" [25]; a maintainer confirms env-injected tokens expire while askpass stays authed [5]. Conflicts with this ticket's no-server-stored-values constraint anyway [32] → rule it out.
3. **Hard constraint: >1 provider = paid.** Docs section is literally "Multiple External Providers (Premium)" [1]; enforcement in source: `featureArguments.ExternalAuthCount > 1` without `FeatureMultipleExternalAuth` → error-level entitlement "…Enterprise feature. **Reduce to one.**" [9]; pricing page confirms tiers [10]. Two lab forges ⇒ two providers ⇒ Community license (the lab's posture) covers **exactly one** OAuth-ified git host via Coder.
4. **Token custody in Coder is plaintext-at-rest BY DEFAULT**: "By default, Coder stores external user tokens … in plaintext in the database"; opt-in `--external-token-encryption-keys` (AES-256-GCM) encrypts `external_auth_links.oauth_access_token/oauth_refresh_token` (+ `user_secrets.value`, `gitsshkeys.private_key`) [29]. The docs phrase "stores securely" [1] — the encryption doc is the more specific, authoritative statement. Adopting this design ⇒ enable encryption ⇒ the encryption keys become *another* secret to custody (Bitwarden/ExternalSecret per repo rules [31]) — a small circularity worth a decision.
5. **Per-user links have real lifecycle semantics**: `ExternalAuthLink{ProviderID, HasRefreshToken, Expires, Authenticated, ValidateError}`, unlink attempts remote revoke only when supported [6] — Forgejo has no revoke endpoint (§A), so unlink = Coder-local; the forge-side grant must be revoked by the user (Settings → Applications; `RevokeOAuth2Grant` handler present in v15.0.9 [18]).
6. **Adjacent but relevant Coder surface**: (a) *User Secrets* (Beta, v2.35.2): per-user secret values in Coder's DB, injected as env/file into all of that user's workspaces at start — could carry per-user **scoped PATs** with zero repo/Bitwarden change (middle option; check licensing/feature tier; docs warn workspace shell readers see them) [30]. (b) `coder gitssh` + per-user Coder SSH key (`coder publickey`) — the SSH-side counterpart already documented [2]. (c) VS Code / code-server historically override GIT_ASKPASS (fixed by Coder extension or `git.terminalAuthentication=false`, `git.useIntegratedAskPass=false`) [5,25] — live-verify against the lab's code-server module 1.6.0.

### C. Forgejo-side: the OAuth issuer's real limits (v15.0 docs + v1.5.0.9 source + live)

1. **Grants**: authorization_code + PKCE + refresh_token only; **device flow = open feature request** (codeberg issue #4830, open) [12,19]; git-credential-oauth's README corroborates with that issue linked and marks forgejo device flow ✗ [20]. This kills every "human-less approval" design (and Coder's device-flow endpoints [8] can't be used against these forges).
2. **Clients**: confidential AND **public (PKCE)** both supported; for public clients, `http://127.0.0.1/` redirect allows **any port** (RFC 8252 style) [12]. Registration: **per-user** `/user/settings/applications` (no admin needed) or instance-wide `/admin/applications` [12].
3. **Scopes: not implemented for OAuth2** — docs verbatim: tokens from third-party apps execute "**any actions on behalf of the user**", instance-wide-app wording even "will have administrative rights"; official advice: "**Scoped application tokens or SSH keys … should be preferred in environments where security is a concern**"; `EnableAdditionalGrantScopes:false` in v15.0.9 source (nascent plumbing) [12,14,17]. **The shipped PATs' `write:repository/write:issue/read:user` scoping is stronger containment than any OAuth grant Forgejo can currently issue.**
4. **Lifetimes** (v15.0.9 source): access token **3600s** default; refresh token **730h ≈ 30.4 days**; `InvalidateRefreshTokens: true` = **refresh rotation** (one-time-use refresh tokens → duplicate token copies across devices/PVCs race and can stale each other) [16,17]. Both tunable via `[oauth2]` app.ini (chart's `FORGEJO__OAUTH2__…` additionalConfigFromEnvs pattern would carry it) [15,17].
5. **The official container story exists but is loopback-bound**: every Forgejo pre-registers `git-credential-oauth`, `git-credential-manager` and `tea` OAuth apps (`DefaultApplications`, shared constant client id `a4792ccc-…` on all instances) [12,13,17]; git-credential-oauth refreshes headlessly **once a refresh token is in a storage helper** [20,21] — but the *first* grant opens a local browser + loopback listener, which cannot complete for a remote pod from a laptop browser [20,38].
6. **Discovery**: no RFC 8414 metadata (404) but full OIDC discovery (§A) — clients that speak OIDC-discovery can configure themselves; Coder does not need either (URLs derived/overridable by env) [7].
7. **Git/API acceptance**: OAuth access token works as git-over-HTTPS basic-auth password and for the REST API ("alternative to … basic authentication"; userinfo/introspection endpoints live) [12,27]. Whether Forgejo's consent screen re-appears on every authorize or is remembered per app+user — UNVERIFIED (no doc found; cheap live check).

### D. `fj` CLI (the already-baked third path) — v0.7.0, the image pin

1. `fj auth login` **is an OAuth login**: PKCE public client (S256), fixed redirect `http://127.0.0.1:26218/`, opens the system browser and **aborts if it can't** (no print-URL fallback in code) [33]. v0.7.0 shipped 2026-10-16 — the pinned version already includes it [36].
2. On success it stores `LoginInfo::OAuth{token, refresh_token, expires_at}` in `keys.json` on the home PVC (`~/.local/share/forgejo-cli/keys.json`; legacy `~/.config` read as fallback) and **transparently refreshes + persists the rotated refresh token before every command** [33,34]. A laptop-minted keys.json copied into a workspace would self-maintain across boots — per-user, vault-free, no Coder premium.
3. Catch: the lab hosts are not in its built-in instance allowlist; per-host `client_ids` config file (or `/etc/fj/client_ids`) supplies the registered app's client id — requires a one-time per-instance OAuth app registration anyway [35]. Loopback bootstrap makes it **laptop-only**, and refresh-rotation means the laptop copy and the PVC copy must not both be used [33,34,17].
4. `fj auth add-token` (current wiring) and git credential helpers remain separate stores — unchanged facts for the shipped model [40].

### E. Git mechanics that decide the hybrid's shape

- Git consults `credential.helper` chains first; **askpass/terminal prompting is only for what helpers fail to supply** [38]. Therefore: with the shipped `wire_forgejo` helper active for a host (PAT env present), **Coder's OAuth for the same host is silently shadowed**; without it, askpass answers. One per-host toggle, deterministically ordered — no race. (Empirical corollary for the plan's tests: OAuth on host X requires *removing* X's PAT helper line.)
- The shipped script's `if [ -n "$FORGEJO_TOKEN*" ]` guards already give the bootstrap/fallback surface for free [40].

### F. Contradictions (and how to weigh them)

| # | Clash | Resolution used |
|---|---|---|
| F1 | Coder "stores tokens securely" [1] vs plaintext-by-default [29] | [29] is specific+normative → treat encryption-enable as a precondition, not a given |
| F2 | "scoped shared PAT safer" [12] vs "unscoped per-user bounded safer" (1h TTL, per-grant revoke [16,18]) | Both true on different axes → the matrix must present scope-vs-identity as THE trade, no blanket winner |
| F3 | Feature-rich docs [1,2] vs provider-count paywall in code [9] | Code wins: plan one provider per Community license, or price the cap as a user decision |
| F4 | Browser-approval elegance [24] vs unattended-boot contract [40] | Approved state survives boot untouched; first-ever boot of an unapproved user fails loud with URL — spec it as the UX, don't hide it |
| F5 | Forgejo's "official" loopback helpers [12,20] vs dead-in-pod topology | coderd callback is the only completable interactive route; helpers stay a laptop story only |
| Consensus | No device flow, no OAuth scopes, PKCE works, askpass auto-auth, 1h/30d lifetimes, hybrid needed | Multiple independent lenses + live probes agree |
| Blind spot | Nobody answered: **which forge gets the ONE provider**, where the **Coder encryption keys** live, **who the shared-PAT account actually is** today, consent re-prompt cadence | → Open questions |

## Recommendation matrix (for the planner to chunk from)

| Option | Approval UX | Headless boot | Scoped? | Per-user identity | Cost/complexity | Verdict |
|---|---|---|---|---|---|---|
| **A. Keep shipped PATs** (status quo) | none | ✅ zero-touch | ✅ (3 scopes) | ❌ shared | 0 | Keep as bootstrap + second-forge + OpenChamber floor |
| **B. Coder external-auth `gitea` for ONE forge** (recommend canonical git.spencerslab.com — "the lab's own repos live there" [40]) | one browser click via printed coderd URL or Coder UI; Keycloak session already present [24,28] | ✅ once approved; refresh by coderd [25] | ❌ full-account [12] | ✅ | server env + OAuth app + template `data` decl (or pure askpass) + optional fj-seed via access-token [4]; **≤1 provider on Community** [9]; enable DB encryption [29] | **The feature the user asked for.** Land for one host; PAT stays for the other |
| **C. Coder external-auth for BOTH forges** | as B | as B | ❌ | ✅ | needs Premium/Enterprise license [9] | User-priced decision; defer unless they buy |
| **D. `fj auth login` per user (keys.json on PVC)** | laptop click once | ✅ self-refresh ≤30d chains [34]; boot git-over-https still needs the helper trick (fj token ≠ git credential auto-wiring for https — would be seeded from keys.json or via ssh-alias path) [33] | ❌ | ✅ | app registration per instance + client_ids config; laptop bootstrap; no Coder change | Good *fj-API-side* complement to B; weaker as the git story |
| **E. Coder User Secrets per-user PAT** (Beta [30]) | none (paste own PAT into Coder) | ✅ injected env → current script unchanged | ✅ | ✅ | zero Bitwarden items; per-user scoped tokens; Beta + DB-custody as in F1 [30] | Not "SSO approval", but the cheapest per-user+scoped hybrid; offer as the pragmatic middle |
| **F. git-credential-oauth in image** | **cannot complete in pod** (loopback) [20,21,38] | after seeding ✅ | ❌ | ✅ | — | ✗ rejected for workspace use (fine on laptops) |
| **G. Device flow anything** | — | — | — | — | Forgejo issue #4830 OPEN [19] | ✗ dead today; revisit if it lands (then fj/GCM headless logins light up) |
| Drop PATs entirely | — | ✗ OpenChamber needs PATs [39]; unapproved first boots have no floor | — | — | — | ✗ keep PAT surface for canonical-for-OpenChamber + dev-forge (or vice versa per user choice) |

**Recommended replan shape (B+A+E as fallback ladder):** OAuth-ify the **canonical** instance through Coder native external-auth (gitea type; confidential client with secret in a new Bitwarden item via the existing coder-secrets ExternalSecret pattern, public+PKCE if empty-secret proves accepted — UNVERIFIED, §G below); flip workspace-startup.sh to *skip the PAT helper for OAuth-covered hosts* and seed fj from `coder external-auth access-token` (exit-1 → print approval URL in the boot banner); enable Coder database encryption [29]; dev instance + OpenChamber stay on the shipped PAT plumbing unchanged; document the consent cadence (access 1h, refresh ~30d, one click per re-approval [16,17]). No premium needed at one provider; a later Coder license unlocks C trivially since B's config is N=0..M-indexed env slots [2].

## Implications for the plan

1. **Scope reversal is explicit**: the original plan's "OAuth/SSO … user declined" out-of-scope line is now the requested feature [32] — DECISIONS should record the flip before chunking.
2. **Provider-cap decision belongs to the user first**: which host gets the free OAuth slot (research recommends canonical; alternative = user accepts Premium or Option E per-user PATs). This is a question, not an assumption.
3. **New validation surface** for tests (this repo's "tests" = helm/grep/script checks): coder-secrets ExternalSecret gains `CODER_EXTERNAL_AUTH_*` keys; charts/coder values gains static env entries; services/dev ExternalSecrets/template env blocks for the OAuth host may become *optional* (PAT stays as fallback floor); workspace-startup.sh keeps sh/dash -n + suite gates with the new per-host toggle; a grep contract like dev-git-auth's c6 can pin that the OAuth host's PAT helper is NOT configured when the toggle env is present.
4. **OpenChamber stays PAT** — already user-accepted [39,32]; OAuth access tokens are structurally incompatible (1h life, no client refresh) (§C4).
5. **The legacy `forgejo-token` question**: dev-vs-canonical scoping of Option B decides whether `forgejo-token` (dev PAT, live in prod) or `forgejo-token-canonical` (OVERRIDE_NEEDED slot, user action pending [32]) becomes the *fallback-only* item — coordinate with the still-open Bitwarden user action.
6. **Device-flow hook exists but is inert**: Coder's device endpoints [8] + gitea type's absent DeviceAuth [7] + Forgejo #4830 [19] ⇒ nothing to build now; note it as a future upgrade path only.

## Open questions (planner MUST ask the user)

1. **One OAuth provider (Community) — which instance, canonical git.spencerslab.com or dev git.scifi.farm?** (Research leans canonical.) Or is a Coder Premium license acceptable to cover both?
2. Is the current `forgejo-token` a **bot/dedicated account or a personal account's PAT**? (Blast-radius math changes; plan says canonical "dedicated account is fine" — dev unknown.)
3. Accept that OAuth grants are **full-account rights** (no scopes in Forgejo OAuth) [12] as the price of per-user identity?
4. Enable **Coder database encryption** (`--external-token-encryption-keys`) as part of this feature (recommended; needs a Bitwarden item for the key + coder env wiring) [29]?
5. Preferred token-custody model if Coder-premium blocks full OAuth: Option **E** (Coder user-secrets per-user PATs, Beta) or keep Bitwarden shared PAT for the non-OAuth host?
6. Boot posture: OK with "first boot before approval prints an approval URL into workspace log and the clone fails until clicked"? (This is the only human-free-preserving design once PAT floor is removed for that host.)

## Reliability notes (STORM self-review)

- **High (9/10)**: Forgejo no-device-flow / no-scopes / 1h+30d / PKCE — triple-confirmed (live probe + v15.0.9 source + v15.0 docs) [12,16,17,27,28]. Coder gitea-type + askpass + access-token CLI at v2.35.2 — raw source+version-tagged docs [2,4,7,24,25]. Multi-provider cap — doc heading + enforcement code [1,9].
- **Medium (7/10)**: "Forgejo works as Coder gitea-type out-of-the-box" — endpoint shapes + userinfo 401-contract verified live, but the *authenticated* userinfo payload and empty-secret public-client handling were not exercised (need one live experiment). Consent-click count per approval (login→303 evidence only).
- **Lower (5/10)**: first-boot failure UX (inferred from askpass source paths, not run); VS Code/code-server askpass inheritance on current code-server (2024-era fix reports [5,25], version not probed); refresh-token reuse policy on rotation [17] (spec-level silence).
- **Perspective weighting**: coder-platform and forgejo lenses dominate (the questions are mostly theirs); governance and devex inputs are real but thinner — their clashes (F2, F4) are the load-bearing tensions. A 6th angle that could change conclusions: **Keycloak-side** (e.g. launching an OAuth flow with Keycloak session-policy/timeout edges, or shortening the whole chain by having Coder mint Forgejo PATs via API) — not run; PAT-via-API remains unexplored and could beat B on scope-preservation if the user rejects F2 (worth a quick spike before committing).

## Sources

| # | URL | Title / what it proved |
|---|---|---|
| 1 | https://coder.com/docs/admin/external-auth | External Auth for Git Providers (current docs; callback URL; GIT_ASKPASS internals; "Multiple External Providers (Premium)") |
| 2 | https://raw.githubusercontent.com/coder/coder/v2.35.2/docs/admin/external-auth/index.md | v2.35.2-tagged same doc (env config, gitea section, self-managed providers, REGEX rule) |
| 3 | https://raw.githubusercontent.com/coder/coder/v2.35.2/docs/reference/cli/external-auth.md | v2.35.2 CLI: only `access-token` subcommand |
| 4 | https://raw.githubusercontent.com/coder/coder/v2.35.2/docs/reference/cli/external-auth_access-token.md | access-token exit0 token / exit1 auth-URL contract + startup-script example |
| 5 | https://github.com/coder/coder/discussions/10451 | Gitea self-managed precedent; IDE askpass override; maintainer "env tokens expire, askpass the way" |
| 6 | https://raw.githubusercontent.com/coder/coder/v2.35.2/codersdk/externalauth.go | gitea ∈ Git() provider set; ExternalAuthLink fields; unlink/revoke semantics |
| 7 | https://raw.githubusercontent.com/coder/coder/v2.35.2/coderd/externalauth/externalauth.go | giteaDefaults (PKCE S256, regex/token/userinfo derivation); promoauth S256-only; provider build path |
| 8 | https://raw.githubusercontent.com/coder/coder/v2.35.2/coderd/externalauth.go | device endpoints exist but gated by per-provider DeviceAuth (gitea: none) |
| 9 | https://raw.githubusercontent.com/coder/coder/v2.35.2/enterprise/coderd/license/license.go | ExternalAuthCount>1 → FeatureMultipleExternalAuth entitlement ERROR |
| 10 | https://coder.com/pricing | Community vs Premium tier framing |
| 11 | https://github.com/coder/envbuilder/blob/main/docs/git-auth.md | CODER_GITAUTH = build-time repo auth (distinct feature; not the workspace path) |
| 12 | https://forgejo.org/docs/v15.0/user/authentication/oauth2-provider/ | grants=authcode+PKCE+OIDC; endpoints incl. openid-configuration; confidential+public clients; loopback any-port; **scopes unimplemented; full account rights; prefer scoped tokens**; git-credential-oauth recipe w/ constant client id; per-user app registration |
| 13 | https://forgejo.org/docs/v15.0/admin/advanced/oauth2-provider/ | pre-registered GCM + git-credential-oauth apps; DEFAULT_APPLICATIONS |
| 14 | https://forgejo.org/docs/v15.0/user/authentication/token-scope/ | PAT route-scoping (PAT-only feature) |
| 15 | https://forgejo.org/docs/v15.0/admin/config-cheat-sheet/ | oauth2_client section (auto-registration semantics) |
| 16 | https://codeberg.org/forgejo/forgejo/src/tag/v15.0.9/routers/web/auth/oauth.go | access=+AccessTokenExpirationTime seconds; refresh=+RefreshTokenExpirationTime hours |
| 17 | https://codeberg.org/forgejo/forgejo/src/tag/v15.0.9/modules/setting/oauth2.go | defaults 3600s/730h, InvalidateRefreshTokens=true, DefaultApplications incl. tea, EnableAdditionalGrantScopes=false |
| 18 | https://codeberg.org/forgejo/forgejo/src/tag/v15.0.9/routers/web/user/setting/oauth2.go | RevokeOAuth2Grant user-side handler |
| 19 | https://codeberg.org/forgejo/forgejo/issues/4830 | Device Authorization Grant — OPEN issue (headless gap) |
| 20 | https://github.com/hickford/git-credential-oauth/blob/main/README.md | forgejo: OAuth ✔ device ✗; browserless needs device flow; storage-helper design |
| 21 | https://github.com/hickford/git-credential-oauth/blob/main/main.go | refresh-via-stored-oauth_refresh_token mechanism (headless after seeding) |
| 22 | https://forgejo.org/docs/latest/user/api/authorized-integrations/ | ("Authorized Integrations" = Actions JWT feature, NOT OAuth revocation — disambiguation) |
| 23 | https://forgejo.org/releases/ | v17 latest / v15 LTS line context |
| 24 | https://raw.githubusercontent.com/coder/coder/v2.35.2/cli/gitaskpass.go | agent askpass: prints approval URL headless→stderr; 404→default git behavior; Match:host token fetch |
| 25 | https://raw.githubusercontent.com/coder/coder/v2.35.2/docs/admin/templates/extending-templates/external-auth.md | prompt→store→refresh UX; askpass = preferred; data-source tokens don't refresh; VSCode settings |
| 26 | https://login.spencerslab.com/realms/SpencersLab/.well-known/openid-configuration | (live) Keycloak realm issuer + device endpoint present (KC-only) |
| 27 | https://git.scifi.farm/.well-known/openid-configuration | (live) Forgejo OIDC discovery: grants authcode+refresh, PKCE plain/S256, no device endpoint, userinfo/introspect status codes (same on git.spencerslab.com) |
| 28 | https://git.scifi.farm/login/oauth/... | (live) authorize→303 login; token POST grant-type error; /login/oauth/revoke + device 404; api/v1/version 15.0.9 |
| 29 | https://raw.githubusercontent.com/coder/coder/v2.35.2/docs/admin/security/database-encryption.md | tokens plaintext-by-default; AES-256-GCM keys cover external_auth_links + user_secrets |
| 30 | https://raw.githubusercontent.com/coder/coder/v2.35.2/docs/user-guides/user-secrets.md | User Secrets Beta: per-user env/file injection, DB storage, workspace-readable warning |
| 31 | repo AGENTS.md + skills/helm-chart-creation | SpencersLab secrets rules (ExternalSecret+Bitwarden; item-per-concern; sentinel flow) |
| 32 | repo plan/DECISIONS/STATE of this ticket | shipped C01–C03 posture; OVERRIDE_NEEDED slot; scope-flip evidence |
| 33 | https://codeberg.org/forgejo-contrib/forgejo-cli/src/tag/v0.7.0/src/auth.rs | fj v0.7.0 `auth login`: PKCE public client, redirect http://127.0.0.1:26218/, browser-open-or-abort, ssh alias setup |
| 34 | https://codeberg.org/forgejo-contrib/forgejo-cli/src/tag/v0.7.0/src/keys.rs | LoginInfo::OAuth{token,refresh_token,expires_at}; early auto-refresh w/ rotation persisted; keys.json paths |
| 35 | https://codeberg.org/forgejo-contrib/forgejo-cli/src/branch/main/src/auth.rs | client_ids config file (~/.config/forgejo-cli/client_ids, /etc/fj/client_ids) + built-in allowlist (no lab hosts) |
| 36 | https://codeberg.org/api/v1/repos/forgejo-contrib/forgejo-cli/releases/tags/v0.7.0 | v0.7.0 published 2026-10-16 (image pin has auth login) |
| 37 | https://codeberg.org/forgejo-contrib/forgejo-cli/raw/branch/main/README.md | fj purpose/scope (API client, works alongside git) |
| 38 | https://git-scm.com/docs/gitcredentials | credential helper chain answers before askpass; OAuth access token as basic-auth password |
| 39 | https://docs.openchamber.dev/integrations | OpenChamber Forgejo card = URL+PAT (write:repository/write:issue/read:user), stored server-side (also plan-cited) |
| 40 | repo containers/coder-workspace/workspace-startup.sh | shipped guards/helpers/fj seeding; per-host loop; use-time env expansion; boot contract |
| 41 | (live) readonly-dev-kubernetes + readonly-infra-kubernetes | coder v2.35.2 deployment; forgejo 15.0.9-rootless ×2; keycloak 26.7.2; workspace image `coder-workspace:main` running |
