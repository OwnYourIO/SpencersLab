# PLAN: Radiance Grafana dashboard + metrics scrape wiring
feature: 2026/2026-11-cf-145-feat-radiance-grafana-metrics

> Reworked 2026-11-21 after the owner's batched-round answers: OQ-1 OVERRIDDEN (annotations path), OQ-4 OVERRIDDEN (new `inference:` provider folder), OQ-8 OVERRIDDEN (OE-2 unconditional manual sync). OQ-2/3/5/6/7 kept, re-expressed per the answers. Nothing beyond these answers is folded in.

## Goal
Put the radiance engine's `/metrics` surface (live-verified on this build — RESEARCH §R15 owner pair read 2026-11-15) under the central Prometheus the OWNER-RULED way: the `k8s.grafana.com/*` pod-annotation pair in `charts/radiance` (the vllm-chart D8 precedent), consumed by gpu-ai's k8s-monitoring annotationAutodiscovery → alloy → remote-write chain. File the engine's own dashboard (`radiance.json` @ tag v1.17.0) into a NEW `inference:` Grafana provider folder (owner ruling), and rewrite runbook step-9 to point at the wired surfaces honestly.

## Out of scope
- The vllm lane's dashboard entries — untouched (parent D6); their live absence is pre-existing and the owner's sync resurrects them as a side effect (R2 — do NOT verify, fix, or delete them from any chunk).
- A raw ServiceMonitor/PodMonitor for radiance anywhere — the owner ruled the annotations path; C01's guard leg exists to keep the two paths from ever double-wiring. `services/gpu-ai/prod/templates/` and `services/gpu-ai/prod/values.yaml` stay untouched.
- `charts/radiance/**` OUTSIDE C01's scope: the zero-diff law is LIFTED for C01 only (gate + annotation region of values.yaml); the renovate annotation, image tag, digest ledger (values.yaml:224-242), serveArgs, probes and every other region stay byte-stable — the 46-green suite legs and ledger files become ACs to PRESERVE, not avoid.
- Live cluster state: no ArgoCD sync, no rollout, no pod exec, no admin-* MCP (barred; owner legs OE-1..3 below).
- Version/tag/`Chart.yaml` edits anywhere — release.yaml owns chart bumps; service-umbrella charts are static 1.0.0.
- Retiring the runbook's "owner's metrics file" prose (owner work, EXPLORE §5). The vllm:/radiance: series themselves. Vendoring the dashboard JSON.

## Commands
Re-verified 2026-11-21 (post-rework, this branch @7219bf5). Export PATH first — without `~/.local/bin/helm` pytest silently mass-skips its helm-guarded legs (AGENTS.md).

- env: `export PATH=$HOME/.local/bin:$PATH`
- deps (REQUIRED before chart renders; the app-template tgz is not vendored; CI does the same): `helm dependency update charts/radiance`
- suite baseline (green today): `pytest charts/radiance/tests -v` → 67 passed, 1 skipped; the single skip is LOUD and pre-existing (llama-swap cross-render leg needs `helm dependency update charts/llama-swap`) — not the silent mass-skip class
- chart: `helm lint charts/radiance` · `helm template radiance charts/radiance` (0 failed; renders OK)
- gpu-ai umbrella (C01 must not break it): `helm lint services/gpu-ai/prod` · `helm template gpu-ai services/gpu-ai/prod` (renders clean with no `--set`; the `llama-OVERRIDE_VIA_APPSET-ingress` lint WARNING is pre-existing)
- monitoring umbrella: `helm lint services/monitoring/prod` (0 failed, same warning class)
- grafana render leg (C02's provider-filing proof, VERIFIED THIS ROUND — RC=0, provisioning CM + download script render): extract the top-level `grafana:` subtree of `services/monitoring/prod/values.yaml` to a temp file (yaml-safe-dump, the mcp-servers-reference extract idiom), then `helm template monitoring-grafana <grafana-chart@version> -n default -f <subtree>` — chart version READ from `charts.grafana.version` in the same file (one authority; currently 10.1.0, repo `https://grafana.github.io/helm-charts/`); in tests via `helm pull grafana/grafana --version <v>` into a temp dir (radiance CI already has helm network use via dependency update)
- sentinel greps (per chunk): annotation-pair greps in `charts/radiance/values.yaml` + absence guards (no `k8s.grafana.com/job`, no `prometheus.io/`, no `kind: ServiceMonitor` under `services/gpu-ai/prod/templates/`) · the provider/entry greps in `services/monitoring/prod/values.yaml` · runbook phrase greps scoped to the Step-9 window (C03).

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | radiance scrape wiring — k8s.grafana.com annotation pair in charts/radiance (gates fn + q27 together) | M | 1 | [] | — |
| C02 | dashboard filing — NEW `inference:` provider folder + `radiance.json` url entry @tag v1.17.0 | M | 1 | [] | independent of C01: different umbrella, different file; a dashboard before scrape is the designed empty-panels state (G3/R4) |
| C03 | runbook step-9 note rewrite — point at the wired surfaces | S | 2 | [C01, C02] | the prose pins the landed artifacts by file paths, job name and provider folder; written early it would anchor wording to surfaces still movable under review |

## Wave order
1. C01, C02 (independent; id order)
2. C03

## Execution notes (this run)
Stages: Exploration done → Planning (this file, reworked per owner answers) → Test Writing (all three chunk test files, red-first) → C01 dev/review, C02 dev/review, C03 dev/review (alternating) → Final Review. HITL stops: plan-approval re-confirmation (pending, owner approved subject to THIS rework) + Final Review hand-off. Deployment stage OFF — commits stay local on branch `cf-145-feat-radiance-grafana-metrics`; landing on main is the owner's PR decision alone.

## Owner-executed legs (barred from agents by design — mark in ACs)
- **OE-1 endpoint confirmation** (not a gate — the build is verified): `kubectl -n default port-forward svc/gpu-ai-radiance-q27 8000:8000 &` then `curl -s http://127.0.0.1:8000/metrics | grep -m5 -E "^vllm:|^radiance:"` (fn variant needs an up-scale per step-2/10 protocol).
- **OE-2 scrape live (unconditional manual-sync step, owner ruling OQ-8)**: after merge, SYNC THE `gpu-ai` Application in ArgoCD (no automated policy assumed — drive the sync explicitly), then confirm on the central Prometheus: target group for job `radiance` (annotationAutodiscovery label-fallback job name — see R5b) active on the q27 pod at `podIP:8000`, and `{__name__=~"radiance:.*|vllm:.*",cluster="gpu-ai"}` non-empty. This leg is ALSO the live proof of the annotation path itself (R5a).
- **OE-3 dashboard live**: SYNC THE `monitoring-grafana` Application (manual-sync fleet) + confirm the `download-dashboards` init ran at the rollout → dashboard `radiance` (uid `radiance`) appears in the **Inference** folder. Same sync resurrects the two stale vllm dashboards (R2). Panels fill only with a radiance engine running (R4).

## Risks / assumptions
- **R1 (F-β law)**: "entry on main == dashboard in Grafana" is FALSE for this fleet — url JSONs are fetched by the init container only at pod rollout (proven: cf-105's Nov-5 entries still unfetched). Automated acceptance therefore stops at render/parse/grep; appearance is OE-3, by ruling, not by omission. Same law applies to the scrape: annotated pods are discovered only after the gpu-ai sync + an alloy reload cycle (OE-2).
- **R2**: the one manual sync that lands radiance also loads the two vllm dashboards — pre-existing gap, empty vllm panels (lane dormant) ≠ incident. State it in the Final Review hand-off so nobody is surprised.
- **R3**: `/metrics` treated as build-confirmed (docs + §R15 live pair). OE-1 is a confirmation leg, not a gate. If it unexpectedly 404s, C03's contingency sentence is the honest path: point at `/stats` step-time series (L1T-witnessed; witnesses RESEARCH §R14 ~3516-3522, exact field table UNVERIFIED per §R14) and retire the metrics claim — do NOT re-plan the scrape on a guess.
- **R4**: fn scales to 0 by owner protocol; zero series while no engine runs is the designed shape (G3). The annotation pair ships in the CHART, so both releases carry it automatically; no AC requires fn up.
- **R5a (mechanism honesty — owner ruling recorded)**: the CHOSEN path (annotation autodiscovery) is enabled on gpu-ai (`annotationAutodiscovery.enabled: true` → collector alloy-metrics → destination prometheus, charts/k8s-monitoring/values.yaml:162-165) but UNPROVEN LIVE on that cluster — the only annotated lane the repo ever shipped (charts/vllm) is dormant, so no annotated target has ever flowed through gpu-ai's alloy. The rejected alternative (operator-object ServiceMonitor) was the live-proven path (cnpg PodMonitor witnesses). **OE-2 is therefore the live proof leg for the mechanism itself, not just for this wiring** — if it fails, the honest report is "annotation path dead in practice on gpu-ai", a new DECISIONS round, not a silent fix.
- **R5b (job/label facts — grounded from the shipped k8s-monitoring 4.5.5 feature component, this round)**: with exactly the vllm-pair annotations (`scrape` + `metrics.portNumber`), autodiscovery yields: target address `podIP:8000` (portNumber rule), path `/metrics` (documented absent-annotation default), **job = `radiance`** (no `k8s.grafana.com/job` annotation → the relabel fallback chain fills job from the pod label `app.kubernetes.io/name` = `radiance`, identical for fn AND q27 — the owner's unified recognizable identity, pinned to the mechanism fact, not to the earlier hoped-for `default/radiance`), interval 60 s (the feature's `global.scrapeInterval: 60s` default; `k8s.grafana.com/metrics.scrapeInterval` is the override key and stays ABSENT per the D8/Q5 ruling — exactly two annotations). NOT `default/radiance` — that `<ns>/<monitor-name>` shape belongs to the operator-object path.
- **R6**: dashboard `instance` var will show podIP:8000 and churn across restarts (fact #24, MEDIUM confidence) — accepted; OE-2/OE-3 confirm live behavior.
- **R7**: the ScrapeConfig idiom (`exporter-mikrotik-scrape-config.yaml`) carries monitoring-cluster operator selector labels and is NOT part of either ruled path here — do NOT copy it anywhere.
- **R8 (new-provider mechanics, grounded from the grafana 10.1.0 chart source this round)**: `download_dashboards.sh` resolves each url dashboard's write path by matching the provider `name` in `dashboardproviders.yaml` against the `dashboards` map KEY — so the C02 edit MUST add BOTH the provider block (`name: inference`, `options.path: /var/lib/grafana/dashboards/inference`) AND the `inference:` dashboards key, name-coupled exactly, or the JSON downloads nowhere. `folder: Inference` follows the existing key→Title-case display convention (data→Data, kubernetes→Kubernetes). The `datasource: Prometheus` string triggers the chart's sed rewrite of every `"datasource":` field in the fetched JSON — same behavior the vllm pair relies on.

## Open questions
All eight original questions were ANSWERED by the owner's 2026-11-21 batched round and folded in above (OQ-1→annotations+R5a/R5b, OQ-2→job fact `radiance` pinned in R5b/AC, OQ-3→60s via feature default with the override key named, OQ-4→inference provider + R8 coupling law, OQ-5→boundary kept, OQ-6→contingency kept, OQ-7→closure recorded here only, OQ-8→OE-2 unconditional manual sync). No genuine new gap surfaced from the rework: the annotation pair verifiably covers both releases (one chart, two releases — gate+annotations live in the chart defaults the q27 overlay deep-merges over), the 46-green suite has no leg the pair can collide with (only the `reloader.stakater.com`-absence leg touches pod annotations; k8s.grafana.com keys are a different concern), and the grafana render leg proved end-to-end on the un-edited tree this round.

## Resolved-answer record (what changed from draft 1)
- Draft-1's ServiceMonitor object (name `radiance`, job `default/radiance`, services-umbrella file) is RETIRED; superseded by DECISIONS D-8.
- Draft-1's dashboard-under-`default:` filing is RETIRED; superseded by DECISIONS D-9 (inference provider) with R8 as the mechanical law.
- Draft-1's conditional OE-2 sync wording is superseded by DECISIONS D-10 (unconditional manual sync steps).
