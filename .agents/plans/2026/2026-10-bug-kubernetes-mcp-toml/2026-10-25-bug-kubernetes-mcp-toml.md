# PLAN: kubernetes-mcp-server TOML config migration (SEV-HIGH incident fix)
feature: 2026/2026-10-bug-kubernetes-mcp-toml

> **For agentic workers:** REQUIRED SUB-SKILLS: load `helm-chart-creation` +
> `helm-bjw-s-chart`; read `RESEARCH.md` and `DECISIONS.md` in this folder before
> touching any file. Steps use checkbox (`- [ ]`) syntax.

## Goal

`ghcr.io/containers/kubernetes-mcp-server` v0.0.68 removed every runtime CLI
flag; the Renovate bump to `v0.0.69` (PR #704) left both chart-default
`mcp.kubernetes-{readonly,admin}` entries passing dead flags, crash-looping the
`mcp-kubernetes-*` servers on 10 clusters and blinding every `*-kubernetes` MCP
client fleet-wide. Migrate both tiers forward to the TOML `--config` surface
without touching the image pin, and stop Renovate from proposing jumps across
the config-surface boundary again.

**Out of scope**
- Any image-tag change (pin stays `v0.0.69` — binding user decision; also keeps
  the no-hand-bump rule untouched).
- Rollback to v0.0.65, ToolHive version changes (operator stays 0.56.0),
  OIDC re-enable, `sessionAffinity` tuning, `/healthz` probes — each stays a
  separate future ticket if wanted.
- The machine-global config drift side finding (see DECISIONS D9) — later ticket.
- Cluster-side application: ArgoCD does it on merge to main; no `kubectl apply`
  from this repo, ever.

## Global Constraints (binding, from intake — not re-openable)

1. Fix forward on `v0.0.69`; no rollback, no tag change anywhere.
2. Renovate posture: keep semver tag bumps, ignore the known-breaking range via
   a config-surface floor; mechanism per repo convention (`packageRules`
   `allowedVersions`), validated with the renovate MCP tooling.
3. `charts/hivetools` ships from `main` by path (`charts/base/values.yaml`
   `charts.hivetools`, `charts/base/templates/appset-charts.yaml`,
   `targetRevision: main`, no `version:`) → **on merge, ArgoCD re-renders the
   chart on every cluster**; never hand-bump `Chart.yaml` version (release.yaml
   owns it, currently 1.0.72).
4. Chart renders identically on every cluster → nothing may require per-cluster
   values edits.
5. TOML bytes are contractual: `port = "8080"` is a **string**; unknown keys
   fail startup hard; no env-var alternative exists for the dropped flags.
6. RBAC (`templates/rbac-kubernetes-mcp.yaml`) stays the enforcement boundary —
   untouched except comments. `/mcp` path, ingress and proxy Service naming
   unchanged.

## Verified evidence base (planner re-checked all claims against files, 2026-10-25)

- Dead flags in chart defaults: `charts/hivetools/values.yaml` L108–114
  (`--port 8080 --stateless --read-only`, pin L100) and L149–152
  (`--port 8080 --stateless`, pin L141). Both pins already `v0.0.69`.
- Image appears **exactly twice** repo-wide (chart defaults only);
  `custom-values/**` clean; other `--port` hits belong to other binaries
  (dev playwright entry `services/dev/prod/values.yaml:222`, archon, okd,
  llama-swap — not this server).
- `generic-mcpserver.yaml` passes `args` (L37–40) and `podTemplateSpec`
  (L53–56) through verbatim → ConfigMap delivery needs **no change to that
  template**, only a new ConfigMap template + values edits.
- Renovate reaches the pin via the built-in `helm-values` manager (the repo's
  regex image manager covers `templates/` only, not `values.yaml`); PR #704
  commit title `Update ghcr.io/containers/kubernetes-mcp-server Docker tag to
  v0.0.69` confirms depName = the full image string.
- Proposed rule validated offline with `dev-renovate` MCP (2026-10-25, this
  session): `validate_config` strict => valid; `lint_config` => clean;
  `test_package_rules` => matches only
  `ghcr.io/containers/kubernetes-mcp-server` (exact names only — `-old` and
  `wekan-mcp` variants do NOT match).
- Client entries measured in `.opencode/opencode.jsonc`: **18**
  (`(readonly|admin)-<cluster>-kubernetes` × 9 clusters: ai-gpu, dev, gpu,
  grow, home, infra, media, monitoring, proxy-local). Briefing said 20 —
  treat the crash-loop cluster list (incl. "2 unlabeled streams") as
  user-verified cluster-side facts; the repo-side contract tests below bind
  to measured values.

## Commands (this repo has no unit suite; these ARE the tests — AGENTS.md "Pipeline specifics")

Environment facts (from sibling ticket 2026-10-feat-dev-mcp-fleet FRICTION —
do not rediscover): `helm` is NOT on PATH (only `~/.local/bin/helm`; use the
discovery recipe in `tests/services/dev-forgejo-runner.sh` header). Render from
a `/tmp/opencode` COPY after `helm dependency update` (never write into the
worktree; `charts/` vendored deps are gitignored). `--set` with `/`-containing
image names breaks — override via extracted `--values` files. Suites that exec
other scripts must run **sequentially**; never edit a script mid-suite-run.

- test (C01 contract): `bash tests/services/hivetools-kubernetes-mcp-toml.sh`
  (ids `t1..t7`; selection: `... .sh t2 t3`)
- test (C02 contract): `bash tests/renovate/kubernetes-mcp-version-floor.sh`
  (supports `RENOVATE_CONFIG=<abs path>` override per
  `tests/renovate/dockerfile-pins.sh`)
- test (C03 contract): `bash tests/services/hivetools-kubernetes-mcp-docs.sh`
  (ids `d1..d4`)
- regression (run AFTER C01 implementation, sequentially):
  `bash tests/services/dev-mcp-fleet.sh t6 t7 t8 t11`
- raw lint/render (what the contract scripts wrap): copy chart to
  `/tmp/opencode/<x>`, `(cd <x> && ~/.local/bin/helm dependency update)`,
  `~/.local/bin/helm lint <x>` and
  `~/.local/bin/helm template hivetools <x> --set domain=test.example.com --set clusterName=dev --set subDomain=dev --set bitwardenIds.mcp-sso=test-uuid --set keycloak.realm=test`
- renovate deep validation (agent action, MCP): `dev-renovate`
  `validate_config` + `lint_config` on the edited `renovate.json`, plus
  `test_package_rules` for target / non-target deps (commands recorded in
  `chunks/C02.md`).

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Chart migration: ConfigMap delivery + `--config` args (both tiers) | M | 1 | [] | — |
| C02 | Renovate config-surface floor rule | S | 1 | [] | independent file set (renovate.json + tests/renovate/) |
| C03 | Docs: mcp-servers.md config-file delivery; AGENTS.md check | S | 2 | [C01] | docs describe C01's final `configFile` values shape — interface dependency |

## Wave order

1. C01, C02 (independent files; run in id order)
2. C03

## Landing consequence (state to reviewers)

No chart-release bump is needed or allowed: the path-source `targetRevision:
main` means the merge itself rolls the fix fleet-wide — ArgoCD re-renders
hivetools on every cluster, MCPServer CRs update, operator rolls the two
StatefulSets. A transient second rolling update from selfHeal of operator
pod-template annotations is expected and harmless (known GitOps mechanic).

## Post-merge verification — USER-OWNED (k8s MCP servers are the broken thing; agents cannot check their own fix cluster-side; no pod exec via MCP in any tier)

Per cluster (ctx = dev, gpu, gpu-ai, grow, home, infra, media, monitoring,
proxy-local + the 2 unlabeled streams), after the sync lands:

```bash
kubectl --context <ctx> -n default get mcpserver mcp-kubernetes-readonly \
  -o jsonpath='{.spec.args}{"\n"}'   # expect: ["--config","/etc/kubernetes-mcp-server/config.toml"]
kubectl --context <ctx> -n default get configmap mcp-kubernetes-readonly-config \
  -o jsonpath='{.data.config\.toml}' # expect: the 3 TOML lines; admin CM: no read_only
kubectl --context <ctx> -n default get sts mcp-kubernetes-readonly \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="mcp")].volumeMounts}{"\n"}'
kubectl --context <ctx> -n default get pods -w -l 'toolhive-name in (mcp-kubernetes-readonly,mcp-kubernetes-admin)'
kubectl --context <ctx> -n default logs mcp-kubernetes-readonly-0 -c mcp --tail=20
```

Prometheus (via `readonly-global-grafana` once reachable, or Grafana Explore):

```promql
kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff", pod=~"mcp-kubernetes.*"}  # → empty
kube_statefulset_status_replicas_ready{statefulset=~"mcp-kubernetes.*"}                        # → replicas per cluster
```

Then: the 18 client entries return to agent MCP catalogs; one read call via
`readonly-<cluster>-kubernetes` succeeds; `tools/list` parity — readonly tier
shows NO write tools (TOML `read_only = true` preserves the old flag's hiding
behaviour) and admin shows them; `configuration_view` is absent from BOTH tiers
(expected v0.0.68+ HTTP-mode behavior delta — see DECISIONS D5).

## Risks / assumptions

- Crash fleet-wide count + the "2 unlabeled streams" are cluster-side facts
  from the forensics round, marked user-verified; repo-side evidence is all
  planner-verified above.
- Upstream could change the TOML schema again in another 0.0.x — pre-1.0 risk.
  Mitigations: renovate floor rule (C02), contract tests (C01 t2–t7), and
  sweep guard t7 binding future entries. A jump past a *future* boundary is a
  new incident class, not this one; the floor only pins today's proven one.
- ConfigMap projected as a directory mount (not subPath) so kubelet refreshes
  it on CM edits; `stateless` is restart-only in the server, so a refresh
  changing it needs a pod restart anyway (reloader ships on every cluster but
  MCPServer pods carry no reloader annotation — out of scope, note in docs).
- No new secrets → no `custom-values/` entry required (Hard rule trio: the two
  entries needing an override would be a chart/service values change, already
  in C01; proxy entry unchanged per verified ingress contract).
