# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- Ticket: SEV-HIGH incident `2026/2026-10-bug-kubernetes-mcp-toml`
  (run tag `openrouter-qwen3-8-flash`). Evidence: `RESEARCH.md` (24-source
  STORM trail in `storm-runs/kubernetes-mcp-server-flag-removal-toml-config-migration/`)
  + a read-only forensics round + the planner's own file-level re-verification
  (2026-10-25) recorded in the plan file's "Verified evidence base".
  Cluster-side facts (10 crash-looping clusters, catalog loss) are
  user-verified — the k8s MCP servers were the broken thing during planning.

## Decisions
- 2026-10-25 plan: **D1 root cause = the Renovate image bump, not the ToolHive
  upgrade.** v0.0.68 (upstream PR #1423 "Config rework") deleted every runtime
  CLI flag; v0.0.69 = same + container-publish fix. Repo timeline: pin bump
  commit 4922af75d merged 2026-10-25 15:14 UTC via PR #704; toolhive
  0.50→0.56 (PRs #787/#788) merged ~14:46 the same day merely recreated the
  pods and surfaced the crash. Exoneration evidence: the crash text is the
  server binary's own cobra usage, verbatim-matching v0.0.69 `root.go`; the
  operator has no arg-mutating change in 0.51–0.56 release notes; ghcr digests
  rule out a re-tagged v0.0.65. ToolHive stays at 0.56.0 — nothing to revert.
- 2026-10-25 plan(human intake): **D2 fix forward on v0.0.69; no rollback, no
  tag change.** Binding user decision. Rollback to the intact v0.0.65 tag
  would restore service but Renovate would re-propose the same jump (RESEARCH
  F6) and it leaves the fleet on a 3-month-old image; a tag change would also
  step on the "never hand-bump versions" Hard rule with no release-PR support.
  Consequence accepted: TOML config is mandatory for HTTP mode; delivery via
  ConfigMap is the only path on ToolHive (MCPServer `spec.volumes` is
  hostPath-only; no env-var alternative exists for the dropped flags).
- 2026-10-25 plan: **D3 renovate posture = semver floor at the config-surface
  boundary.** New packageRule (C02): `matchPackageNames:
  ["ghcr.io/containers/kubernetes-mcp-server"]`,
  `allowedVersions: ">= v0.0.68"`. Keeps semver tag bumps flowing on the TOML
  side; blocks proposals crossing the flag→TOML boundary in either direction.
  Mechanism verified offline with dev-renovate MCP (2026-10-25, planner):
  `validate_config` (strict) valid, `lint_config` clean, `test_package_rules`
  matches the exact target dep only — `ghcr.io/ownyourio/wekan-mcp` and the
  prefix variant `ghcr.io/containers/kubernetes-mcp-server-old` do NOT match
  (matchPackageNames is exact). Rejected: `ignoreDeps` (kills all bumps —
  violates the intake's "keep semver tag bumps"); `pin:ignore`
  (`pinIgnore` governs pin-type PRs only; this dep's PRs are patch-type
  tag bumps); excluding only v0.0.68 (leaves flag-era v0.0.66/67 proposable);
  line-level automerge holds (doesn't bound the version range); regex
  floor `/^v(0\.0\.(6[89]|[7-9]\d+)|[1-9]\d+)/` (fragile re: future tag
  formats). A floor is future-proof: a *schema-changing* TOML release would
  be a new incident class; the floor pins only today's proven boundary, and
  the C01 t7 sweep test binds any future entry to the contract.
- 2026-10-25 plan: **D4 config delivery = one ConfigMap per tier**, generated
  by a new generic `generic-mcpconfigmap.yaml` iterating `mcp.<name>.configFile`
  (name `mcp-<name>-config`, key `config.toml`). Rejected: one ConfigMap with
  two keys + subPath mounts — couples the tiers (a CM rename/delete hits both
  StatefulSets), subPath projections never refresh on CM edits, and the
  per-entry generic template falls out naturally instead of hand-templating a
  shared CM. Both options satisfy "renders identically on every cluster, no
  per-cluster values edits" (the content lives in chart-default values, deep-
  merged by the appset values layer); per-tier wins on blast-radius isolation
  and on the generic shape for any future flag→config server. Mount is a
  directory mount of the projected volume at `/etc/kubernetes-mcp-server`
  (refreshes; shadows the image-baked default the v0.0.69 Dockerfile ships —
  a zero-arg container would boot stateful with write tools visible,
  unacceptable for the readonly tier → explicit `--config` always).
- 2026-10-25 plan: **D5 tool-list parity preserved.** Old `--read-only` only
  hid write tools from `tools/list`; the TOML `read_only = true` has the same
  semantics (exposes `readOnlyHint=true` tools only) — verified against the
  tag-pinned upstream migration doc in RESEARCH F2. No `toolsets` key needed
  (default `["core","config"]` unchanged since v0.0.65); RBAC
  (`rbac-kubernetes-mcp.yaml`) is and stays the enforcement boundary, untouched.
  Behavior delta accepted: `configuration_view` disappears from HTTP-mode
  `tools/list` (disabled by default upstream since v0.0.68 — it exposed
  kubeconfig contents; acceptable/desirable). `stateless = true` restart-only
  reload semantics noted in the plan's risks.
- 2026-10-25 plan: **D6 validation = three contract scripts + regression rerun**
  (C01/C02/C03 "## Tests"), all following the `tests/services/dev-mcp-fleet.sh`
  house style (per-id selection, helm-discovery recipe, /tmp copies, lenient
  YAML loaders, skip-with-warning only where a registry is genuinely needed).
  "No other rendered MCPServer regressed vs today's output" is proven by
  re-running the sibling ticket's dev-mcp-fleet contract (its pinned literals
  are today's output) rather than a golden snapshot of the modified chart
  (self-referential once dev lands; main moving makes a git-show golden
  flaky). `--config`-presence + dead-flag-absence + exact TOML bytes + mount
  cross-check + image-pin equality + repo-wide sweep are t2/t3/t4/t5/t7
  respectively.
- 2026-10-25 plan: **D7 no AGENTS.md / `.rulesync/rules/` change.** Checked
  per the "keep these lists current" rule: no new skill or MCP server enters
  the change (dev-renovate/global-renovate already listed); version rules
  untouched; the hazard detail belongs in `mcp-servers.md` (C03), not in the
  high-level rules file. C03's d4 verifies generated surfaces show no diff
  instead. If review overrules, the edit goes to `.rulesync/rules/overview.md`
  + `rulesync generate` — never the output.
- 2026-10-25 plan: **D8 standing hazard recorded (pipeline-facing).** Because
  internal charts ship from `main` by path with **no chart version pin**
  (`charts/base/values.yaml` `charts.hivetools` → `appset-charts.yaml`
  `targetRevision: main`), a Renovate 0.0.x bump of any flag/config-sensitive
  third-party MCP image changes behavior on EVERY cluster at merge time,
  silently, with no chart-release PR and no canary. Fleet blast radius
  measured this incident: 10 clusters × 2 tiers crash-looped, and every
  `*-kubernetes` client entry vanished from agent catalogs (18 in
  `.opencode/opencode.jsonc` — the briefing's "20" did not reproduce from the
  file; counted by name pattern, 9 clusters × 2 tiers) — i.e. the tooling that
  would diagnose the outage is itself taken down by it. Mitigation standing
  for this ticket: the D3 renovate floor + the C01 t7 args/flag contract test
  (guards all future `mcp:` entries repo-wide). Broader sweep of OTHER MCP
  images for unpinned config surfaces is out of scope here (all were checked
  healthy for this incident: playwright 0.0.83, mcp-searxng 2.7.0, ha-mcp
  2026.10.2, mcp-grafana 2.1.1, renovate-mcp v31, wekan-mcp v60, pg-airman-mcp
  1.1.1 (flag surface differs — different binary, args still valid),
  argocd-mcp 1.8.0 env-only).
- 2026-10-25 plan: **D9 deferred side finding (later ticket, do NOT fix here):**
  AGENTS.md claims the machine-global configs
  (`~/.config/opencode/opencode.json`, `~/.config/kilo/kilo.jsonc`) mirror the
  fleet MCP list, but `~/.config/opencode/opencode.json` contains zero
  `kubernetes` entries (forensics round). Out of this ticket's blast radius.

## Deferred
- D9 → new ticket (opencode-config drift audit).
- `sessionAffinity: None` hardening for the two stateless servers (RESEARCH
  open item; optional, not needed for the fix).
- `/healthz` probes on the `mcp` containers via podTemplateSpec (RESEARCH open
  item — additive, future ticket).
- OIDC re-enable for the tiers (already parked in values comments since
  2026-09).
- Stakater-reloader annotation for MCPServer pods if config hot-reload is
  ever wanted (`stateless` is restart-only anyway).
