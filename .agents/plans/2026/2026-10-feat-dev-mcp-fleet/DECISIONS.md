# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- MCP servers are hivetools `mcp:<name>` entries (ToolHive MCPServer CRDs), NOT
  standalone charts; ingress `mcp.<subDomain|clusterName>.<domain>/<name>` is
  chart-owned (`generic-mcp-ingress.yaml`) — no per-service ApplicationSet or
  `ingress.subdomains` entry for the MCP servers themselves. Recipe:
  `skills/helm-chart-creation/references/mcp-servers.md`.
- dev umbrella value flow (verified against `charts/base/templates/appset-charts.yaml:16-33`
  + `services/dev/prod/templates/appset.yaml:106-128`): `hivetools.mcp` and the
  per-app `searxng:` slice ride from `services/dev/prod/values.yaml` +
  `custom-values/dev/prod-values.yaml` (both loaded as base valueFiles) into the
  respective Applications; umbrella `templates/*.yaml` read the TOP-LEVEL
  `.Values.bitwardenIds`.
- Chart render validation uses the repo test-house recipe (copy under
  `/tmp/opencode` + `helm dependency update`, worktree never written, helm from
  PATH→~/.local/bin→download fallback) — see `tests/services/dev-forgejo-runner.sh`.

## Decisions
- 2026-10-24 human(intake, binding): deploy `charts/searxng` on dev too;
  dev-local `SEARXNG_URL`. Rejected: point dev MCP at gpu's backend. — user
  wants a self-contained dev cluster.
- 2026-10-24 human(intake, binding): `dev-boards` = admin-tier wekan MCP;
  server-side read-only deliberately NOT enforced (no `WEKAN_MCP_READ_ONLY`).
  Credentials = Bitwarden LOGIN item `d8e2b2ca-792d-4e0a-86ae-b4ed0122c21a`
  via new `wekan-mcp` ExternalSecret exposing WEKAN_USERNAME/WEKAN_PASSWORD.
- 2026-10-24 human(intake, binding): wekan-mcp container extended with
  username+password login (mint at startup, keep WEKAN_TOKEN support,
  refresh-on-401) rather than pre-minting a token item. Rejected: manual
  token mint + LOGIN-password item (gpu pattern) — dev creds are given as a
  username+password login item and the container change benefits every future
  login-style deployment.
- 2026-10-24 human(intake, binding): renovate on dev gets a NEW Bitwarden
  fields item for the dev github token; placeholder sentinel + TODO is an
  acceptable interim (UUID is not a secret).
- 2026-10-24 human(intake, binding): client entries added to
  `.opencode/opencode.jsonc` only; machine-global sync is a user follow-up.
  `dev-*` naming is tier-less by user choice.
- 2026-10-24 human(intake, binding): `dev*` MCP allow rule in the six
  `agent-{plan,research,test,dev,review,fuser}.md` sources is IN SCOPE (runtime
  OpenCode v2.1.4 honors these blocks; tier-less servers fall through to `ask`
  = blocked unattended).
- 2026-10-24 human(intake, binding): agent-pipeline machinery changes (coord
  webfetch, comment policy, kickoff research timing, permission audit) are a
  separate ticket — excluded.
- 2026-10-24 plan: dev cluster has NO wekan instance and the repo ships no
  wekan chart (live-verified via readonly-dev-kubernetes: zero
  wekan/boards Service/Ingress/MCPServer; and wekan tiers on gpu target the
  lab bot instance `https://wekan.spencerslab.com`). Boards base-URL is
  therefore OPEN ITEM OQ1 — do not guess-deploy. C03 ships
  `boards: enabled: false` unless the user resolves OQ1 first.
- 2026-10-24 plan: dev `searxng` gets NO public ingress (backend-only for the
  MCP server). Rejected: gpu-parity `ingress.subdomains.searxng` public host —
  nothing on dev consumes the UI/API publicly; precedent for deliberate
  no-proxy entries: forgejo-runner comment (`services/dev/prod/values.yaml:86-89`).
  User may override at approval.
- 2026-10-24 plan: `dev-searxng` service host is
  `http://dev-searxng.default.svc.cluster.local:8080` (release name pattern
  `<serviceName>-<appName>`; verified against gpu live: release `gpu-searxng`,
  ingress `service: gpu-searxng`, SEARXNG_URL `gpu-searxng`).
- 2026-10-24 plan: renovate dev clones `github.com/OwnYourIO/SpencersLab`
  (git `origin`; the forgejo remotes `git.scifi.farm`/`git.spencerslab.com` are
  mirrors — verified `git remote -v`). Verbatim gpu pattern incl. the PAT
  secret `github-mcp` (name historical per gpu template comment).
- 2026-10-24 plan: keep gpu's ExternalSecret templates verbatim WITHOUT
  `deletionPolicy: Delete` (parity > the mcp-servers.md recommendation; a
  repo-wide sweep is out of this ticket's scope).
- 2026-10-24 plan: `dev-boards` references `ghcr.io/ownyourio/wekan-mcp:main`
  + `imagePullPolicy: Always` per user decision; pinning to the first login-
  capable `:v<run>` is a post-merge follow-up (deferred list).
- 2026-10-24 plan: C04 edits only `.opencode/opencode.jsonc` directly; every
  other doc/agent surface goes through `.rulesync/` sources + `rulesync
  generate` (Hard rule). `rulesync gitignore` never run; mcp/permissions
  features stay OFF (rulesync.jsonc rationale).
- 2026-10-24 plan: no pyproject version bump in C02 (file itself documents the
  field as cosmetic; CI owns tags).
- 2026-10-24 human(approval round): **dev-boards base URL comes from the URI
  field of Bitwarden item `d8e2b2ca-…` (`bitwarden-uri` store), not from a
  values-pinned env** — supersedes the OQ1 default above; `boards` ships
  `enabled: true`, `WEKAN_BASE_URL` flows through the `wekan-mcp` Secret like
  `secret-homeassistant-mcp.yaml`'s HA_URL. User must fill/verify the item's
  URI + the service account on the target instance.
- 2026-10-24 human(approval round): **dev searxng DOES get a local ingress** —
  `searxng.scifi.farm` reachable from the LAN, explicitly NOT via proxy-remote;
  supersedes the backend-only plan decision. Mechanism: plain
  `ingress.subdomains.searxng: {service: dev-searxng, port: 8080}` (no
  clusterBase/serviceName) renders the key-derived top-level host on dev's own
  traefik with `wildcard-cert`, external-dns proxy-remote target commented out
  — same form as the live `git`/`research` entries.

- 2026-10-24, **user ruling (post-approval, OQ2 resolved)**: the dev GitHub token is
  NOT a new FIELDS item — it reuses the existing dev LOGIN item `github-pat`
  (`522b1cc4-2c74-4399-887d-b4e20014b2d2`, password = the PAT), so
  `secret-github-mcp.yaml` reads `bitwarden-login` / `property: password`.
  Re-rules C03's intake assumption ("new Bitwarden item… `token` field") and the
  immutable contract t9's store/property assertions, which encoded that
  assumption — routed to the `agent-test` session, then to dev for the template.
  Dev searxng secret_key LOGIN item: `f90806ff-8ee5-435d-b2e2-b4ed0176d701`
  (replaces the `OVERRIDE_NEEDED` placeholder; no contract change — t4/t10
  already accept a real UUID).

## Deferred
- OQ2 (partly resolved by the ruling above): populate/verify the `d8e2b2ca`
  item's URI field and that its username+password is a valid password-based
  service account on that URI's instance (`WITH_API=true`).
- Machine-global client config sync (`~/.config/opencode/`, `~/.config/kilo/`)
  — user-owned.
- Pin dev-boards `:main` → `:v<run>` once the login build lands (renovate).
- Post-sync cluster verification (MCPServer CRDs/pods/ingress/tools-list) —
  user-owned or readonly-MCP checks after ArgoCD syncs.
- searxng `SEARXNG_BASE_URL` renders empty (app-template gotcha, chart-owned) —
  cosmetic, untouched.

## Landing provenance (recorded by coord, 2026-10-24)
- The ticket reached `main` by **cherry-pick of every branch commit + push to
  origin/main** — an action taken outside this session (coord/dev/review agents
  committed only to the feature branch; landing is user-owned per repo hard
  rules). Consequences, verified from live git state:
  - `main` = base `ae9ecb053` + cherry-picked copies, INCLUDING the C03
    fix-round (`bitwarden-login`/`password`, both UUIDs pasted).
  - `main..HEAD` on this branch = 30 original-SHA commits (the branch was also
    rebased onto `ae9ec053`-era base, so SHAs differ from main's copies by
    design, not by content).
  - Content difference between `main` and the branch tip: exactly one file,
    `chunks/C03.md` (+103 lines of re-review notes, the two post-push doc
    commits). No source, test, values, or custom-values delta — `git diff
    --name-only main HEAD` lists that single doc file.
  - Therefore: do NOT merge this branch into main (duplicate-history merge);
    any remaining delta is doc-only and lands by cherry-pick at the user's call.
- 2026-10-25, **user ruling (post-sync boards failure)**: hivetools MCP servers consume
  MULTIPLE keys from one Secret via the mcp container's `podTemplateSpec.envFrom.secretRef`
  (gpu `homeassistant` precedent), never repeated `spec.secrets[]` entries — the toolhive
  MCPServer CRD keys `spec.secrets` as a list-map on `name`, so duplicates are rejected at
  apply time (`dev-hivetools` was OutOfSync/Failed and `mcp-boards` never existed).
  Re-rules the immutable t7 boards block (test session `d241475f5`), which had encoded the
  unimplementable three-entry shape; t7 now also asserts Secret-name uniqueness across every
  rendered MCPServer. Accepted sub-decisions from the test author: the "no top-level env"
  check stays targeted to WEKAN_BASE_URL (not a blanket spec.env ban), and a single-entry
  `secrets[]` remains legitimate alongside `envFrom`. Fix is repo-side in C03 scope;
  cluster convergence happens through ArgoCD after landing (no hand-mutation).
