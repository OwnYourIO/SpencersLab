# owner-followup-review — uncommitted delta (sweep + guard + doctrine + stale-leg repair)

Verdict: **APPROVED** (2 minors, 2 nits — none blocking).

## Evidence (fresh, this session)

- Sweep purity: every swept file reconstructed from HEAD with trailing comments
  stripped ONLY on enabled `version:` lines is byte-identical to the worktree —
  exactly 9 deletions (6x enabled external-secrets-bitwarden + grafana +
  exporter-mikrotik + kube-prometheus-stack). Disabled `#version:` lines, the
  cf-105 dashboards annotations, and the cf-145 inference provider/dashboards
  surfaces are byte-untouched. No Dockerfile / renovate.json in the diff.
- Guard leg (`tests/renovate/chart-pin-extraction-guard.sh`): RC=0. Reads
  matchStrings from renovate.json at run time via description-keyed lookup
  (rot-proof, index-proof), g3 census = 13 files / 16 enabled pins extracted
  with correct triples. Anti-vacuity: glob-nonempty, managerFilePatterns
  coverage, trios==0 all fail loudly. Injection re-proven independently:
  grafana pin → g2 FAIL RC=1; sibling (es-bitwarden) pin → g3 FAIL RC=1;
  restored → md5sum -c OK, RC=0. Executable bit 755. `set -euo pipefail`,
  per-leg `if ! python3 …; then fail fi`, no pipe masking.
- Stale repair: k5 wekan literal 12.99.0 == services/home/prod/Chart.yaml +
  Chart.lock (both wekan deps) and the `# changelog:` sourceUrl. k10:
  containers/forgejo-host-runner/Dockerfile:14 is `# renovate: datasource=docker
  depName=forgejo/runner` directly above `FROM data.forgejo.org/forgejo/
  runner:13.2.1`; witnesses real and Renovate-authored (75e7f9083 bumps that
  exact FROM on its renovate branch; 966e8ac4f bumps coder-workspace FROM
  debian:13-slim digest); extends = config:recommended only. Leg logic
  untouched — the diff is the SUPPORTED array plus its header. Header law is
  consistent with built-in dockerfile-manager behavior; strata/Dockerfile:9-10
  independently corroborates the ARG-above-docker dead case.
- Doctrine: source hunk (.rulesync/rules/overview.md) and generated hunk
  (AGENTS.md) are the same text; `npx --yes rulesync@37.0.0 generate --check`
  => RC=0 "All files are up to date". Wording checked against the managers
  read at runtime: cm#8 `datasource=helm registryUrl=` inline syntax is
  appset-only (`/appset\.ya?ml$/`); cm#4/#5 `/values\.yaml$/` bare-pair
  adjacency broken by trailing comments (regex-verified); cf-105 dashboards
  annotations are consumed by cm#7 (`/\.ya?ml$/`, depName+gnetId+revision) —
  46 extractions from monitoring values — and the caveat scopes only "chart
  pins", so they are correctly excluded.
- Whole delta: pytest charts/radiance/tests -q => 96 passed, 0 failed,
  1 skipped, RC=0. Five executable tests/renovate legs RC=0 (guard,
  chart-yaml-legs 12/0, chart-lock-consistency 3/3, dockerfile-pins 37/0,
  forgejo-move-config 8/8). services-values-pins + system-upgrade-controller
  also RC=0. helm lint of all six swept umbrellas RC=0. aislop 0.20.0:
  `scan --changes` reports scope 0 files for the uncommitted delta; full-tree
  scan => 100/100, 0 issues (subsumes the delta files); CI
  `aislop ci --changes --base origin/main` will gate them at PR.

## Findings

- minor — tests/renovate/chart-pin-extraction-guard.sh header ("Why the pins
  need a net"): "7x external-secrets-bitwarden + grafana + exporter-mikrotik +
  kube-prometheus-stack" miscounts the swept class. The sweep deleted SIX
  enabled es-bitwarden pins (gpu/grow/home/infra/media/monitoring) — total 9,
  not 7+3=10. Fix: "6x external-secrets-bitwarden … (9 pins)". Comment-only
  correction; no leg behavior involved.
- minor — doctrine completeness (`.rulesync/rules/overview.md`): the
  keep-intact enumeration names appset baseChartVersion lines and Dockerfile
  pins but not the cf-105 grafana.com dashboards annotations
  (`# renovate: depName="…" + gnetId + revision`, consumed by cm#7 in values
  files). The caveat is correctly scoped to "chart pins" so the omission is
  not misleading today, but a reader auditing values.yaml annotations could
  over-apply the inert-or-harmful rule. Fix: add one clause, e.g. "the
  dashboards `# renovate: depName= … gnetId …` annotations are consumed by the
  grafana-dashboards manager and stay", then re-run rulesync generate.
- nit — k10 `SUPPORTED` allow-list is not position-aware: a
  `datasource=docker` annotation above an ARG line would now pass the D10
  gate. No such instance exists in the tree (the only datasource=docker
  annotation is the forgejo-host-runner FROM one) and the header names the
  tension honestly. Optional strengthening: require, for datasource=docker,
  that the next non-blank line starts with `FROM`.
- nit — guard header "runs the simulated final config before dev edits the
  file" is pipeline-history phrasing in a usage block; the override
  explanation works without the tense.

## Deferred

- tests/renovate/kubernetes-mcp-version-floor.sh (644, outside the five-leg
  set) fails RC=1: k2 pins packageRules count==8; the config carries 10
  (forgejo-move-config m5 confirms 10 is the current canon). Inputs are only
  renovate.json — untouched by this delta — so the red is byte-identical at
  HEAD: a pre-existing stale leg of exactly the class this delta repaired at
  k5/k10, last touched by cf-96's "pre-existing red family" re-pin. Owner/
  coord call whether to re-pin it in this delta or a follow-up; it does not
  bear on the shipped surfaces.

## Conventions check

No version/tag bumps (sweep is comment-only; k5 edits a test literal to match
shipped truth, not a pin). No secrets touched. STATE.json delta is the coord's
10-line owner_followups ledger (additions only). Generated-surface law
honored: source + AGENTS.md in one delta, check clean.
