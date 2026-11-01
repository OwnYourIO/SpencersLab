# PLAN: Fix Renovate — restore clean dependency lookups
feature: 2026/2026-11-cf-95-bug-fix-renovate

**Goal:** Renovate runs on this repo with zero ERROR records and zero "Dependency Lookup Warnings" for the seven card-listed dependencies — by fixing three renovate.json config bugs (broken git-refs leg, `oci://` fed to the helm datasource, vendored-skill placeholder scanning), removing one provably dead Dockerfile annotation, and replacing three dead-upstream references (two images in `services/home/prod/values.yaml`, the deleted Grafana dashboard at the `speedtest-exporter-hub` pin in `services/monitoring/prod/values.yaml` → live successor 13665 rev 4) — all choices per the user's 2026-11-01 batched answers.

**Architecture:** Renovate (running against this repo's `renovate.json`) extracts deps via ten regex customManagers + built-in managers; the card's failures split into config bugs (fix in `renovate.json`; branch-aware + default git-refs legs), dead upstreams (repoint images + replace the dashboard pin with a live successor), and one placeholder-scan artifact (disable the path). Each fix is proven by an offline regex emulation against the real files plus a local `platform=local` dry-run whose ERROR/`failed to look up` lines are the acceptance gate.

**Tech Stack:** Renovate 44.181.5 (CLI via npx/nvm node 24.22.0), renovate.json JSON config (customManagers/packageRules), Helm chart + service values files, Docker registry HTTP APIs, bash test suites under `tests/renovate/`.

**Spec:** card #95 description (verbatim failure report in `STATE.json` sibling docs / this plan's Facts section); feature folder `2026/2026-11-cf-95-bug-fix-renovate`.

## Global Constraints

- Never bump chart versions by hand; `release.yaml` owns `Chart.yaml` `version` (AGENTS.md hard rule). This plan touches no `version:` fields.
- ArgoCD applies everything — no `kubectl apply` from this repo; C02 changes deployed image refs only via this PR's merge (user-owned).
- `.agents/skills/**` is third-party synced content with hashes in `skills-lock.json` — do NOT edit those files; the fix lives in Renovate config.
- Renovate annotations (`# renovate:` comments) in values files and Dockerfiles stay intact (AGENTS.md "Where things live" → renovate.json note) — the single exception is the provably dead coder-workspace base annotation C01 removes per DECISIONS D10 (annotation only; the FROM line is untouched).
- Git safety: work on branch `cf-95-bug-fix-renovate`; no merges/pushes to `main`; push of the feature branch only per the `-pr` variant flow (`local: false`, Human-in-the-Loop: PR).
- No docker daemon / no `buildx imagetools` in agent sessions; registry facts are verified via the registries' HTTP APIs (recipes in Commands).
- `PATH=$HOME/.local/bin:$PATH` before helm; node comes from nvm (v24.22.0 — renovate engines `^24.11.0`).

## Verified facts (planning-phase evidence, 2026-11-01)

Baseline reproduction (verbatim card error, exit 1):

```
export PATH=/home/coder/.nvm/versions/node/v24.22.0/bin:$PATH
cd <worktree> && LOG_LEVEL=info npx -y renovate@44.181.5 --platform=local --dry-run=lookup
# ERROR: Request Error: cannot parse url
#   "url":"index.yaml" "baseUrl":"oci://ghcr.io/mariadb-operator/charts/"
#   "resolvedUrl":"oci://ghcr.io/mariadb-operator/charts/index.yaml"
# exit=1 ("Renovate was run at log level info ... non-zero code due to logged errors")
# also WARN: rate-limit (no GITHUB_COM_TOKEN) + docker-token errors; ~2 min run
```

Per-failure classification:

| # | Card failure | File | Cause (verified) | Class |
|---|---|---|---|---|
| 1 | `ERROR: Request Error: cannot parse url` | `charts/mariadb-operator/Chart.yaml` | customManager "Override changelog/source URL" (renovate.json L108-117) captures `registryUrl: oci://ghcr.io/mariadb-operator/charts` with `datasourceTemplate: helm`; the helm datasource fetches `<registryUrl>/index.yaml` → ky cannot parse an `oci://` scheme. Reproduced verbatim above; Node emulation confirms the pattern matches exactly the mariadb block (and the two wekan https blocks). | (a) config |
| 2 | `helm mariadb-operator: no-result` | same | Same dep — manager 9's helm-datasource lookup failing on #1. The built-in `helmv3` manager tracks this OCI dep fine: GHCR token flow for `repository:mariadb-operator/charts/mariadb-operator:pull` → 200, tags `[...,26.10.1,26.10.2]` — pin is current. Upstream publishes OCI-only: `https://mariadb-operator.github.io/mariadb-operator/charts/index.yaml` → 404. | (a) config |
| 3 | `pypi my-hub-api / my-service-api: no-result` | `.agents/skills/ha-integration-dev/templates/*/manifest.json` | Renovate gained a built-in `homeassistant-manifest` manager (docs: fileMatch `/(^\|\/)manifest\.json$/`, datasources pypi+git-tags) — it scans the skill-template PLACEHOLDERS (`my-hub-api==1.0.0`, `my-service-api==1.0.0`); pypi → 404 verified. 10 `manifest.json` files live under `.agents/` (incl. `assets/templates/`); other templates pin REAL pypi packages → Renovate would open PRs editing hash-locked vendored files. | (a) config |
| 4 | `git-refs assafelovic/gpt-researcher: no-result` (both containers/ Dockerfiles) | `containers/gpt-researcher{,-frontend}/Dockerfile` | git-refs datasource requires a fully-qualified URL `packageName` (docs table + source: `GitDatasource._getRawRefs` → `git ls-remote <packageName>`; a bare `owner/repo` is treated as a local path → error caught → `null` → no-result — matches `getReleases` catch in `git-refs/index.ts`). Manager L96-105 supplies only `depName=owner/repo`, no `packageNameTemplate`. Repo is ALIVE: default branch `main`, HEAD `3582a684...` (2026-10-10) vs pin `5cdad9cb...`. | (a) config |
| 5 | `custom.grafana-dashboards 16541: no-result` | `services/monitoring/prod/values.yaml` (L428-430) | Dashboard 16541 ("Speedtest Exporter") is GONE upstream: `https://grafana.com/api/dashboards/16541` → 404 `Dashboard not found`; no Wayback snapshot of its revision download exists, so its JSON is unrecoverable. Live successor verified 2026-11-01: **13665 "Speedtest-Exporter Dashboard"** (API 200, revision 4, metric family `speedtest_up`/`…_bits_per_second`/`…_latency_milliseconds`/`speedtest_server_id` — the same miguelndecarvalho-exporter family the sibling `speedtest-exporter:` entry L603-609 already runs). 22651 rejected (different metric family, hub exporter unverified). | (b) dead upstream → REPLACE (user answer #3; DECISIONS D3) |
| 6 | `docker ghcr.io/paperless-ngx/tika: no-result` | `services/home/prod/values.yaml` (L731-734) | The paperless-ngx team **removed their tika fork** (upstream issue #11212: image "no longer publicly accessible", moved to official apache/tika in May 2024); GHCR anonymous pull token for the scope → 403 DENIED (control: `home-assistant/home-assistant` scope → 200). Upstream docs/compose now use `apache/tika:latest-full`; the complete probed `apache/tika` 2.9.* tag set ends at **`2.9.2.1-full`** (newest 2.9.x per user ruling #4) and serves port 9998 by default = `PAPERLESS_TIKA_ENDPOINT` (values L627). | (b) dead upstream → REPLACE with newest 2.9.x |
| 7 | `docker gcr.io/zenika-hub/alpine-chrome: no-result` | `services/home/prod/values.yaml` (L1022-1023) | GCR project `zenika-hub` returns 401 even on the anonymous token realm (GCR hides deleted projects behind 401). The maintained Docker Hub twin `zenika/alpine-chrome` serves tag `124`: manifest 200, multi-arch index (amd64+arm64), actively pushed (2026-09). Same project/entrypoint → the `chromium-browser` + 9222 command/args block (karakeep chrome sidecar, L963/L1016-1033) carries over unchanged. | (b) dead upstream → repoint |

Dead-config observation (was draft open question 1, now IN SCOPE per user answer #1 → C01 task + DECISIONS D10): `containers/coder-workspace/Dockerfile:29` carries `# renovate: datasource=docker depName=debian` above a `FROM` line — no customManager's datasource alternation includes `docker`, so the annotation matches nothing; it is being removed (base stays intentionally digest-pinned; repo convention leaves base images untracked).

## Out of scope

- No edits under `.agents/skills/**` (vendored, hash-locked) — the fix lives in Renovate config.
- No changes to any dashboard entry other than the dead `speedtest-exporter-hub` pin site; no Grafana-DB cleanup of the stale imported object (human note, C02 AC8).
- No version bumps beyond restoring living upstreams (Renovate's own PRs do future updates; C02's tika jump to newest 2.9.x is the user's explicit ruling, not a sweep).
- No GitHub-Actions/token/hostRules/renovate-runner infrastructure work — the card's failures are all config/dependency facts, reproduced locally without the runner.
- No chart `version:` bumps, no ArgoCD/kubectl actions.

## Commands

```bash
# every agent: node + helm paths
export PATH=/home/coder/.nvm/versions/node/v24.22.0/bin:$HOME/.local/bin:$PATH
cd "$(git rev-parse --show-toplevel)"

# 1) config schema validation (renovate ships its validator bin)
npx -y -p renovate@44.181.5 renovate-config-validator renovate.json

# 2) existing + extended regex-manager contracts (binds to the REAL renovate.json)
bash tests/renovate/dockerfile-pins.sh
bash tests/renovate/chart-yaml-legs.sh          # new suite added by agent-test (C01)
bash tests/services/home-dead-image-refs.sh     # new suite added by agent-test (C02)

# 3) local dry-run reproduction gate — ERROR lines + failed lookups are the signal
LOG_LEVEL=debug npx -y renovate@44.181.5 --platform=local --dry-run=lookup > /tmp/opencode/renovate-dry.log 2>&1
grep -E "ERROR|failed to look up" /tmp/opencode/renovate-dry.log   # post-fix: empty except documented rate-limit noise
# NOTE: platform=local takes NO positional repo arg; exit 1 == logged ERROR;
# no GITHUB_COM_TOKEN here => github-* datasource rate-limit WARNs are EXPECTED noise (not card deps);
# `--report-file-name` is not a CLI flag and reportFileName yields no file at dry-run=lookup — grep the log instead.

# 4) C02 image-ref gates
grep -cE "ghcr.io/paperless-ngx/tika|gcr.io/zenika-hub" services/home/prod/values.yaml   # want 0
grep -c "16541" services/monitoring/prod/values.yaml                                      # want 0
python3 -c "import yaml; yaml.safe_load(open('services/home/prod/values.yaml')); yaml.safe_load(open('services/monitoring/prod/values.yaml'))"
# apache/tika 2.9.2.1-full index digest probe (for the @sha256 pin) — Docker Hub token flow:
T=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:apache/tika:pull" | sed -E 's/.*"token":"([^"]+)".*/\1/')
curl -sI -H "Authorization: Bearer $T" -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
  "https://registry-1.docker.io/v2/apache/tika/manifests/2.9.2.1-full" | grep -i docker-content-digest

# 5) quality gate (AGENTS.md): comment-slop on the diff, then
npx aislop ci --changes

# 6) C02 grafana successor live probe (never trust the plan's values — re-run)
curl -s https://grafana.com/api/dashboards/13665 | head -c 400   # expect 200, "name":"Speedtest-Exporter Dashboard", "revision":4+
```

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | renovate.json config-leg fixes (branch-aware git-refs split, oci:// exclusion, `.agents/**` silence, dead Dockerfile annotation removal) | M | 1 | [] | — |
| C02 | replace three dead-upstream refs in services values (tika → apache/tika newest 2.9.x, chrome → zenika/alpine-chrome, dashboard 16541 → successor 13665) | M | 1 | [] | Independent subsystem (deployed service values vs renovate config); C01's dry-run gate allowlists C02's three not-yet-replaced lines and vice versa; final whole-plan review runs the one fully-clean dry-run. |

## Wave order

1. C01, C02 (independent; run in id order — C01 first so the post-C02 dry-run is interpretable against fixed managers).
2. Final whole-plan review: dry-run gate must show no ERROR and no `failed to look up` for any card dep (the two docker lines and the 16541 line only become clean once C02 lands).

## Risks / assumptions

- **Deploy impact:** C02 swaps image identities of running sidecars (paperless tika, karakeep chrome). Both old refs are unpullable on a fresh node, so the swap is strictly a repair; the PR stop point (Human-in-the-Loop `PR` checked) keeps it human-gated. Rollback = revert the values lines.
- **Renovate version skew:** local repro pins 44.181.5 (the MCP-bundled version). The live runner may differ; the card's symptoms reproduced exactly on 44.181.5, so the config semantics hold; `homeassistant-manifest` existence is version-dependent — if the live runner is older, the warnings on the card prove it is not.
- **Rate-limit noise:** local dry-runs without `GITHUB_COM_TOKEN` produce github-* lookup WARNs; the gate greps ERROR + card-dep failures only.
- **RE2 vs JS regex:** the local repro run logged `RE2 not usable, falling back to RegExp` — but a runner WITH RE2 silently rejects `(?!…)` lookaheads. Chosen fix therefore avoids lookaheads entirely: manager #9's registryUrl capture becomes `(?<registryUrl>https?://\S+)` (RE2-safe; mariadb's `oci://` line then has no match at all — DECISIONS D6). Dev keeps this property; the test suite's mutation check pins it.
- **Dashboard content swap (user-approved via answer #3):** the `speedtest-exporter-hub` provisioned dashboard's CONTENT changes (13665 rev4's 11 panels replace the frozen deleted import). If the hub's Prometheus scraped a different speedtest exporter than the miguelndecarvalho family, panels render empty — mitigation: the sibling consumer in the same file already runs 13665 against this stack; dev/review re-run the live probe (C02 AC6/AC7), and a stale old dashboard object may linger in Grafana's DB until human cleanup (C02 AC8, Deferred note).
- **tika 2.9.2.1-full compatibility:** same 2.9 series as the dead fork's 2.9.1 and the version line paperless docs recommend; digest re-probed at implement time; ArgoCD sync stays human-gated by the PR stop.

## Open questions (batched — answer round before approval)

**None — the 2026-11-01 batched round resolved all seven draft items; resolutions folded in (answer map: 1→C01 task + DECISIONS D10 fix-in-plan; 2→blanket `.agents/**` D2; 3→successor replacement D3; 4→newest 2.9.2.1-full D4; 5→branch= grammar D7; 6→rely on surviving leg's sourceUrl D6; 7→tag 124 stays D5).**

## RESULT handoff note

Plan reworked per the batched answers; `plan_status` stays `draft` for user approval (coord records it).
