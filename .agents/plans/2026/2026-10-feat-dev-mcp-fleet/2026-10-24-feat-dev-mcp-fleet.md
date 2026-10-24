# PLAN: dev-cluster utility MCP fleet (playwright, renovate, searxng, boards)
feature: 2026/2026-10-feat-dev-mcp-fleet

## Goal
Expose the lab's four utility MCP servers on the dev cluster's ToolHive platform
(`https://mcp.dev.scifi.farm/<name>/mcp`) by copying the gpu entries into
`services/dev/prod`, plus the backends they need (dev-local searxng, login-based
wekan auth). Register them in the repo's client config as tier-less `dev-*`
servers and grant pipeline agents access via a `dev*` MCP allow rule.

## Out of scope
- Ticket 2: agent-pipeline machinery changes (coord webfetch removal, comment
  policy, kickoff research-timing, permission audit).
- Deploying a wekan instance/chart on dev (does not exist; repo ships no wekan
  chart) — see open item OQ1.
- Machine-global client config sync (`~/.config/opencode/`, `~/.config/kilo/`)
  — user-owned.
- Any hand-bumped image tags or Chart.yaml versions (CI/release own those).

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | searxng backend on dev (chart entry + values slice) | S | 1 | [] | — |
| C02 | wekan-mcp container: username+password login + refresh-on-401 | M | 1 | [] | — (C03's boards entry consumes the `:main` image behavior) |
| C03 | dev hivetools `mcp` entries + umbrella secret templates + bitwardenIds/custom-values | M | 2 | [C01, C02] | C01: `SEARXNG_URL` targets the `dev-searxng` service C01 creates; C02: `boards` passes WEKAN_BASE_URL/USERNAME/PASSWORD to the image that only knows how to spend the credentials after C02 merges & CI rebuilds `:main` |
| C04 | client `dev-*` entries + `dev*` agent allow rules + rulesync regenerate + AGENTS.md table | M | 3 | [C03] | registering client URLs + agent access before the servers exist produces dead MCP connections; entry names (ingress paths) are fixed by C03 |

## Wave order
1. C01, C02 (independent; run in id order)
2. C03
3. C04

## Commands
Repo has no unit-test suite; "tests" = the validation invocations below plus
the contract scripts `agent-test` writes under `tests/` (bash, existing
house style: render from a `/tmp/opencode` copy after `helm dependency update`,
worktree never written; helm resolved from PATH → `~/.local/bin/helm` → download fallback — the recipe in `tests/services/dev-forgejo-runner.sh`).

- chart lint: `helm lint charts/searxng && helm lint charts/hivetools`
- searxng render: `helm template searxng charts/searxng --set domain=test.example.com --set bitwardenIds.searxng=test-uuid` (from the /tmp copy) → ExternalSecret `searxng`, service `searxng` on 8080, no `OVERRIDE_` strings
- dev hivetools render (extract the `hivetools:` block of `services/dev/prod/values.yaml` to a temp file first — worked example in `skills/helm-chart-creation/references/mcp-servers.md` Validation): `helm template hivetools charts/hivetools --set domain=test.example.com --set clusterName=dev --set subDomain=dev --set bitwardenIds.mcp-sso=test-uuid --set keycloak.realm=test -f <tmp-slice>` → `MCPServer mcp-playwright|mcp-renovate|mcp-searxng|mcp-boards` + ingress paths `/playwright`, `/renovate`, `/searxng`, `/boards` on host `mcp.dev.test.example.com`
- dev umbrella render: `helm template dev services/dev/prod --set domain=test.example.com --set clusterName=dev --set bitwardenIds.github-mcp=test-uuid --set bitwardenIds.wekan-mcp=test-uuid --set bitwardenIds.cert-manager-solver-token=test-uuid --set bitwardenIds.argocd-sso-secret=test-uuid --set bitwardenIds.github-pat=test-uuid --set bitwardenIds.forgejo-token=test-uuid` → ExternalSecrets `github-mcp`, `wekan-mcp` render with test UUIDs, no sentinels in output
- sentinel parity: grep `OVERRIDE_VIA_CUSTOM_VALUES` in `services/dev/prod/values.yaml` ↔ matching keys in `custom-values/dev/prod-values.yaml` (1:1)
- container: `bash tests/containers/wekan-mcp-login.sh` and `docker build containers/wekan-mcp -t wekan-mcp:contract`
- rulesync: `npx rulesync generate && npx rulesync generate --check` (v37 via npx; commit sources + generated output together)
- client config JSONC validity: python stdlib comment-strip → `json.loads` (asserted inside the contract script)
- post-sync cluster verification (USER-OWNED — ArgoCD applies, never `kubectl apply`; via user kubectl or readonly-dev-kubernetes): `MCPServer` CRDs `mcp-playwright/-renovate/-searxng/-boards` present in `default`; pods `mcp-<name>-0` + proxy Running (`kubectl get pods -l toolhive-name=mcp-<name>`); ingress `mcp-multi-server-ingress` gained the four paths; `tools/list` against each `https://mcp.dev.scifi.farm/<name>/mcp`; dev-searxng pod Running + LAN-reachable at `https://searxng.scifi.farm/search?q=x&format=json`; boards pod Running and logged-in against the item-URI instance (minted token validated on `/api/user`)

## Risks / assumptions
- **OQ1 RESOLVED (approval round)**: dev has no wekan instance; `boards` takes
  `WEKAN_BASE_URL` from the URI field of Bitwarden item d8e2b2ca via the
  `bitwarden-uri` store (no hardcoded host, `enabled: true`). Precondition
  shifts to the item content: user must record a reachable wekan base URL +
  valid password service account there (OQ2), else the boards pod fails fast
  (visible, not silent).
- Bitwarden items for `github-mcp` and dev searxng don't exist yet (OQ2): until
  the user creates them and pastes the UUIDs, those ExternalSecrets stay
  unready and renovate/searxng MCP pods cannot start — visible failure, the
  placeholders are the documented interim state (forgejo-runner precedent).
- dev searxng LAN host: `searxng.scifi.farm` ingress renders like the live
  `git`/`research` entries (direct dev traefik, `wildcard-cert`, no
  proxy-remote target — user decision 2026-10-24); DNS/wildcard assumed
  handled by the existing dev base stack.
- `boards` targets `wekan-mcp:main`; the login-capable image only exists after
  C02 merges to main and docker-build publishes. Pre-merge, a dev-boards pod
  would fail token validation. Ordering (C02 wave 1 → C03 wave 2) respects this;
  runtime verification happens post-sync (user-owned).
- renovate clones `github.com/OwnYourIO/SpencersLab` (origin; forgejo remotes are
  mirrors) — same as gpu. If the mirror lags, dev dry-runs see a stale repo.
- SEARXNG_BASE_URL renders empty on any cluster (known app-template gotcha,
  chart-owned; cosmetic, not touched here).
- `services.dev.customValuesUrls` cluster annotation verified by inference only
  (readonly MCP cannot read argocd-ns secrets) — same conclusion as the
  forgejo-infra ticket; dev's existing synced UUIDs prove the mechanism works.

## User action items
1. Populate/verify Bitwarden item `d8e2b2ca-792d-4e0a-86ae-b4ed0122c21a`:
   URI field = the wekan instance base URL dev-boards should target
   (`WITH_API=true`, password login), and its username+password are a valid
   service account there (OQ1 resolved: base URL is data-driven).
2. Create the remaining dev Bitwarden items + paste UUIDs (OQ2): fields item
   for the dev github token (`token` field), LOGIN item for the dev searxng
   secret key.
3. After merge+sync: run the post-sync verification (or let the agent run the
   readonly-dev-kubernetes checks).
4. Mirror the four `dev-*` server entries into the machine-global configs
   (`~/.config/opencode/opencode.json`, `~/.config/kilo/kilo.jsonc`).
5. PR/merge to main is the user's decision (never agent-side per AGENTS.md).
