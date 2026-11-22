# EXPLORE.md — cf-145-feat-radiance-grafana-metrics (Exploration stage, scout round 1)

*Probes 2026-11-21 ~21:25–22:10Z. Sources: repo reads/greps on branch
`cf-145-feat-radiance-grafana-metrics` @ 7219bf588 (= origin/main tip, clean tree),
`readonly-ai-gpu-kubernetes` + `readonly-monitoring-kubernetes` +
`readonly-global-grafana` MCP reads, and one `webfetch` of the pinned upstream tag
(codeberg StillDeadcode/radiance @ v1.17.0). Read-only throughout; only this file written.*

Card asks three legs: (1) verify + wire the /metrics scrape, (2) import the shipped
radiance.json dashboard into the lab Grafana, (3) update the runbook step-9 note.
This file grounds all three. The two findings that most change the plan's shape:

- **F-α (scrape):** the /metrics endpoint is NOT the open question the card implies —
  parent RESEARCH §R15 carries a LIVE /metrics pair read off this very build
  (2026-11-15), and the engine's own dashboard at tag v1.17.0 queries it. What is
  actually missing is the **wiring**: nothing in the lab scrapes port 8000, so the
  central Prometheus holds zero radiance/vllm series (live-verified).
- **F-β (dashboard landing):** the repo's `grafana.dashboards` url-entry idiom is
  the right shape (the cf-105 vllm pair is verbatim precedent) **but is provably
  not self-executing**: those Nov-5 entries are on origin/main and still absent
  from the live Grafana, because the `monitoring-grafana` ArgoCD app is
  OutOfSync with **no automated sync policy**, and the url downloads happen only
  in the pod's `download-dashboards` init container at rollout time (running pod
  started 2026-10-25). Landing ANY dashboard entry therefore ends with a
  human-owned sync+rollout leg.

## 1. Facts — with evidence

| # | fact | evidence | confidence |
|---|---|---|---|
| 1 | C02 ships `docker.io/stilldeadcode/radiance` tag `"1.17.0"` (`pullPolicy: IfNotPresent`), with a digest ledger in comments: amd64 image manifest `sha256:6fb0e99b…`, tag index `sha256:c2acbaa3…` | `charts/radiance/values.yaml:224-242`; RESEARCH Sources S4 (hub API, digests) | high |
| 2 | Chart is app-template 5.0.1-based, `nameOverride: radiance`, `appVersion: "1.17.0"`, `version: 1.0.0`; only template file is NOTES.txt | `charts/radiance/Chart.yaml:6-16`; `ls charts/radiance/templates/` | high |
| 3 | The pod listens on **8000** (`serveArgs` `"--port","8000"`; containerPort 8000 named `http`; service `radiance` port 8000); probes all `/health:8000` | `charts/radiance/values.yaml:146,244-247,254-279,414-419` | high |
| 4 | **No scrape wiring ships at all**: grep -ri `monitor|scrape|prometheus|metrics` across `charts/radiance/**` (incl. tests) = ZERO hits. "C02 kept scrape annotations off" verified — and it went further than the vllm chart: there is not even a `monitoring:` gate/flag, and the absence is not test-pinned | grep output empty (this round); contrast `charts/vllm/values.yaml:103-107,257-264` | high |
| 5 | Two releases render from this chart: `gpu-ai-radiance` (fn) and `gpu-ai-radiance-q27` (C15 pod-swap lane, `chart: radiance`) — both ns `default`, both `ServerSideApply: "false"` | `services/gpu-ai/prod/values.yaml:68-101`; live Deployments `gpu-ai-radiance` + `gpu-ai-radiance-q27` (resources_list apps/v1) | high |
| 6 | **Live pod posture (2026-11-21): fn has ZERO pods** (Deployment exists, none scheduled — the scale-down protocol); **q27 runs 1/1** (`gpu-ai-radiance-q27-648bd6886-dndd6`, podIP 10.42.0.136, node ai-gpu, age 8h) | readonly-ai-gpu-kubernetes pods_list_in_namespace by instance label; resources_list Deployment | high |
| 7 | ClusterIP services live: `gpu-ai-radiance` 10.43.64.103:8000, `gpu-ai-radiance-q27` 10.43.162.16:8000; service selector `app.kubernetes.io/controller=radiance, app.kubernetes.io/instance=gpu-ai-<release>, app.kubernetes.io/name=radiance` | resources_get Service gpu-ai-radiance (full manifest); resources_list Service | high |
| 8 | **No ServiceMonitor/PodMonitor exists anywhere on ai-gpu** (list returns empty), while the `servicemonitors.monitoring.coreos.com` CRD is Established there | resources_list monitoring.coreos.com/v1 on ai-gpu → null; contrast SAME call on monitoring cluster → items (proves null=empty, not an error); resources_get CRD → Established=True | high |
| 9 | `/metrics` on THIS build is docs-VERIFIED and was even READ LIVE: RESEARCH 676 “`/metrics` confirmed Prometheus text, vllm-compat family [S2 §6.3][S3]”; §R15:3668 “the first REAL /metrics pair — `kv_stream_bytes_total{in}=410,673,152` over `generation_tokens_total=2385`” (owner capture 2026-11-15) | `RESEARCH.md:558-562, 675-676, 3516-3522, 3668-3675` | high (docs + witnessed live read); the agent-side unverified part is only “reachable again NOW from inside the pod” — see owner-leg §5 |
| 10 | The engine's dashboard file exists at the pinned tag and is fetchable by plain URL: `https://codeberg.org/StillDeadcode/radiance/raw/tag/v1.17.0/deploy/grafana/radiance.json` resolves to valid JSON (fetched this round): uid `radiance`, title `radiance`, tags `[radiance, llm]`, schemaVersion 39 | webfetch (this round, 200, ~3 KB of panels inspected in full output); RESEARCH:676 (“folder exists @v1.17.0”) | high. Caveat: “ships **in the image**” (card wording) ≠ proven — the verification witnesses the SOURCE tree at the tag; no agent-side image-layer check was done (Docker Hub, no daemon). Irrelevant if the plan lands the JSON by URL/Codeberg, which the precedent supports |
| 11 | Dashboard queries two families: `vllm:` compat (`vllm:prompt_tokens_total`, `vllm:generation_tokens_total`, `vllm:request_success_total`, `vllm:num_requests_running/waiting`, `vllm:kv_cache_usage_perc`, `vllm:request_{prompt,generation}_tokens_{sum,count}`, `vllm:gpu_prefix_cache_hit_rate`) and native `radiance:` (`engine_steps_total`, `engine_step_seconds_decode_total`, `engine_steps_decode_total`, `decode_tokens_total`, `prefill_tokens_total`, `attn_cached_tokens_total`, `linear_cached_tokens_total`, `draft_accepted_total`, `draft_tokens_total`, `draft_position_{accepted,reached}_total`, `draft_position_acceptance_ratio`, `prefix_cache_{,ckpt_}evictions_total`, `num_requests_preempted`, `http_queue_depth`, `http_admission_rejected_total`, `http_responses_total`, `linear_prefix_cache_hit_rate`); templating vars: `datasource` (type datasource→prometheus), `instance`, `model_name` | the fetched JSON itself (saved output `/home/coder/.local/share/opencode/tool-output/tool_200019d4a001SlzGGuLL3BgH64`) | high |
| 12 | Central Prometheus holds **no** radiance/vllm series: instant + 24 h range `{__name__=~"vllm:.*|radiance:.*|kv_stream_bytes_total"}` = empty; TSDB metric-name list contains no vllm:/radiance: family | readonly-global-grafana query_prometheus ×3 + list_prometheus_metric_names (datasourceUid `prometheus`) | high — and expected: nothing scrapes 8000; retention 7 d also aged out the pre-cutover vllm lane |
| 13 | **Scrape architecture (the repo way):** every cluster runs git-vendored `charts/k8s-monitoring` (grafana/k8s-monitoring v4 wrapper). gpu-ai runs it (`charts.k8s-monitoring` entry). Alloy collectors remote-write to `https://prometheus.spencerslab.com/api/v1/write`; `prometheusOperatorObjects` (ServiceMonitor/PodMonitor discovery) and `annotationAutodiscovery` are BOTH `enabled: true` → collector `alloy-metrics` → destination `prometheus` | `services/gpu-ai/prod/values.yaml:30-34`; `charts/k8s-monitoring/values.yaml:18-23, 137-143, 162-165` | high |
| 14 | **Live proof the path works cross-cluster:** gpu-ai alloy runs (`gpu-ai-k8s-monitoring-alloy-metrics` StatefulSet, alloy 1.14.3 / v1.21.2, + alloy-singleton/operator Deployments); Prometheus holds gpu-ai data labelled `cluster="gpu-ai"` (kube_pod_info{pod="gpu-ai-radiance-q27…"} live); and **PodMonitor objects demonstrably arrive via alloy remote-write** with job name `<ns>/<monitor-name>` — `count by (cluster,job)({__name__=~"cnpg_.*"})` returns e.g. `job="default/pg-coder"` from cluster dev/media/home (those clusters wire it via `enablePodMonitor: true` in their CloudNativePG CRs) | resources_list apps/v1 ai-gpu; query_prometheus ×3; `charts/coder/templates/pg-coder.yaml:24` etc. | high |
| 15 | Prometheus operator stack hosting the central TSDB: kube-prometheus-stack **chart 78.1.0** (prometheus-community), release `monitoring-kube-prometheus-prometheus` ns `default` on the **monitoring cluster** (svc = Grafana datasource URL; ingress subdomains `metrics`/`prometheus` → spencerslab.com; `enableRemoteWriteReceiver: true`); its selectors are wildcard (`serviceMonitorNamespaceSelector/podMonitorSelector` etc. = `{}` + `…NilUsesHelmValues: false`) — but it only watches ITS OWN cluster; gpu-ai objects are consumed by gpu-ai's alloy, not by this operator | `services/monitoring/prod/values.yaml:40-44, 52-55, 72-115` (note top-level `prometheus:` keys 72-77 are the chart's; the `kube-prometheus-stack:` block 80+ is the effective one); Application `monitoring-kube-prometheus-stack` lives on monitoring cluster ns default | high |
| 16 | Grafana: chart **grafana 10.1.0** (Grafana app v12.2.0), release `monitoring-grafana` ns `default` (monitoring cluster); datasource **Prometheus, uid `prometheus`**, url `http://monitoring-kube-prometheus-prometheus.default:9090`; `dashboards:` provisioning keyed provider-folder → entry, entries either `{gnetId, revision, datasource}` or `{url, datasource}`; sidecar also enabled (`grafana_dashboard` label, searchNamespace ALL) but ZERO in-repo ConfigMaps use it | `services/monitoring/prod/values.yaml:25-29, 267-290, 291+, 676-690`; grep `grafana_dashboard` → only the values line; live CMs `-dashboards-*` (all created 338 d ago) | high |
| 17 | **F-β mechanics verified live:** `monitoring-grafana` Application (monitoring cluster, ns `default`, child of `monitoring-charts-appset`): `status.sync = OutOfSync` vs main@7219bf588; last successful operation finished **2026-11-10T00:43Z**; `spec.syncPolicy` has syncOptions only — **no `automated` block** (manual sync fleet-wide, cf. parent EXPLORE’s 0/6 gpu-ai census); running pod `monitoring-grafana-7d6876595-mb896` started **2026-10-25T16:19Z**, init container `download-dashboards`; the ArgoCD-rendered desired valuesObject already contains the two vllm url entries (merged main 2026-11-05, `d0670e031`) yet Grafana API lists 71 dashboards with **no vllm dashboard** and `/api/dashboards/uid/radiance` = 404 | resources_get Application monitoring-grafana (full object); pods_get; grafana_api_request /api/search?limit=1000 + /api/dashboards/uid/radiance; `git log -1 -S vllm-performance-statistics … ; merge-base --is-ancestor … origin/main` => yes | high |
| 18 | Consequence: **the fetch/land path is the same as cf-105's** — a `grafana.dashboards.default.<name>: { url: …, datasource: Prometheus }` entry — but acceptance CANNOT be agent-side “dashboard appears in Grafana”; the honest AC stops at “entry merged to main (branch ready)”, with **sync + rollout + appearance** as owner legs (the label-based `k8s-sidecar`/ConfigMap alternative also needs a rollout, so it buys nothing) | #17; chart mechanics (init-container download at pod start) | high |
| 19 | Parent-run folder exists on this branch (main-derived): RESEARCH.md (5041 lines), EXPLORE.md (with scout rounds §D10+), STATE.json `plan_status: complete` (final review round 7 APPROVED 2026-11-15, HEAD adb0a304b), chunks C01–C16 | `ls .agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/`; STATE.json read | high |
| 20 | Parent rulings this card implements: Q6 = **two follow-up cards**, #2 = “Grafana dashboard re-import follow-up; `/metrics` is vllm-compat-family, the two existing dashboards are cheap candidates” (DECISIONS:1903-1904); vllm dashboards “untouched (owner re-import stays a recorded follow-up)” (D6, DECISIONS:54-55); C14 note: “the dashboard card stays dashboard-only” (DECISIONS:237) | `DECISIONS.md:50-55, 88-92, 234-240, 1900-1906` | high |
| 21 | Runbook step-9 anchor text (the note leg #3 must edit): lines 679-683 — “`/metrics` sanity only here: the vllm-compat family is live and the two existing vLLM-era dashboards are cheap re-import candidates — that is FOLLOW-UP CARD #2 (Grafana re-import, Q6). **Do NOT edit `services/monitoring/prod/values.yaml` in this run**; the dashboard question rides the second Inbox card, not this window.” The step-9 owner-exec block is lines 648-658 (port-forward + curl chain) | `.agents/notes/radiance-on-target-acceptance.md:648-683` verbatim | high |
| 22 | Metric-name witnesses for the fallback leg (if scrape ever turns out absent): §R14 — “`/metrics` carries `kv_resident_blocks`, `kv_stream_misses_total` and `kv_stream_bytes_total` … `/stats` carries step/budget planes (e.g. `steps_held`)”; the `/stats` alternative the card names is “step-time series, L1T-witnessed”. The exact `/stats` field table stays UNVERIFIED (§R14 open list) | RESEARCH 3516-3522, 3630-3637 | high for docs-claim; the “scrape absent” branch is itself refuted by #9/#11 — record the fallback but do NOT plan for it as the default |
| 23 | Label/`cluster` truth for queries: gpu-ai series carry `cluster="gpu-ai"` and `k8s_cluster_name="gpu-ai"` (NOT the release name, despite the `cluster.name: "{{ .Release.Name }}"` template in charts/k8s-monitoring — the appset render yields the short name) | query_prometheus kube_pod_info full label set | high |
| 24 | The radiance.json dashboard has **no `__inputs`/`__requires`** — its datasource arrives via a template variable — so a `url:` entry with `datasource: Prometheus` follows the vllm-entry shape but the mapping is cosmetic (no `${DS_*}` substitution applies); the instance variable will list scraped `instance` values = podIP:8000 (alloy scrapes pods directly; the label changes across pod restarts) | fetched JSON (templating list); job/instance shapes from cnpg + integrations/* series | high for shape; “instance=podIP” is the alloy-discovery pattern seen on kubelet/cadvisor jobs (instance=podIP:port) — MEDIUM on the exact radiance instance label |

## 2. Resolved ids / names (the wiring targets)

- **Cluster**: ai-gpu (node `ai-gpu`, k3s v1.36.5) via `readonly-ai-gpu-kubernetes`.
- **Namespace**: `default` (everything — releases, services, future monitors).
- **Scrape targets** (both release pods, one selector family):
  - svc `gpu-ai-radiance` (fn, ClusterIP 10.43.64.103:8000) — 0 pods today.
  - svc `gpu-ai-radiance-q27` (ClusterIP 10.43.162.16:8000) — 1/1 Running.
  - labels: `app.kubernetes.io/name=radiance`, `app.kubernetes.io/controller=radiance`,
    `app.kubernetes.io/instance=gpu-ai-radiance|-q27`, `app.kubernetes.io/service=gpu-ai-radiance|-q27`.
- **Collector**: gpu-ai Alloy `gpu-ai-k8s-monitoring-alloy-metrics` (StableSet, default ns).
- **Destination TSDB**: kube-prometheus-stack Prometheus `monitoring-kube-prometheus-prometheus`
  (monitoring cluster, ns `default`, ingress `prometheus.spencerslab.com`), retention 7 d,
  remote-write receiver ON.
- **Grafana**: release `monitoring-grafana` (monitoring cluster, ns `default`, app `monitoring-grafana`),
  datasource `Prometheus` uid `prometheus`; dashboards provider folders: default (""),
  its-alive, data, kubernetes, network, storage, system, logs. vllm pair sits under `default`.
- **Dashboard artifact URL (tag-pinned)**:
  `https://codeberg.org/StillDeadcode/radiance/raw/tag/v1.17.0/deploy/grafana/radiance.json`
  — bump WITH the image pin (the vllm comment law, values.yaml:660-663).

## 3. Verbatim shapes the planner will need

**(a) The two candidate scrape wirings, repo-precedent verbatim.**

Annotation idiom — what the vLLM lane (same chart family, same port 8000) actually shipped
(`charts/vllm/values.yaml:103-107` + `254-264`):

```yaml
  # D8: the two k8s.grafana.com/* pod annotations, gated. 60 s scrape
  # interval is the k8s-monitoring v4 annotationAutodiscovery feature
  # default — NO metrics.scrapeInterval annotation (Q5 ruling).
  monitoring:
    annotations: true
```
```yaml
  defaultPodOptions:
    # D8: exactly two k8s.grafana.com/* annotations (scrape + port). Values
    # are ternary-templated on the monitoring.annotations gate; the map is
    # tpl'd as a whole by app-template 5.0.1, so gate-OFF keeps the keys
    # with inert (empty) values instead of dropping them — an empty value
    # is what disables the scrape.
    annotations:
      k8s.grafana.com/scrape: '{{ .Values.monitoring.annotations | ternary "true" "" }}'
      k8s.grafana.com/metrics.portNumber: '{{ .Values.monitoring.annotations | ternary "8000" "" }}'
```
(The old-lane `prometheus.io/*` flavor at `charts/exporter-mikrotik/values.yaml:44-45` is
pre-v4 and has NO live consumer in k8s-monitoring v4’s annotationAutodiscovery — prefer the
`k8s.grafana.com/*` pair; mikrotik itself is served by a real ServiceMonitor, see (b).)

ServiceMonitor idiom — the only raw object in services/ templates
(`services/monitoring/prod/templates/self-monitor.yaml`, whole file):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: prometheus-self
  labels:
    app: kube-prometheus-stack-prometheus
spec:
  endpoints:
  - interval: 30s
    port: web
  selector:
    matchLabels:
      app: kube-prometheus-stack-prometheus
```
Plus the CNPG PodMonitor toggle used ~20× (`charts/coder/templates/pg-coder.yaml:24`
`enablePodMonitor: true`) whose live result is job `default/<pg-name>` — the proof that
operator objects on member clusters reach the central Prometheus. Note: the
`prometheus=system-monitoring-prometheus` label seen on live ServiceMonitors is a
monitoring-cluster-local artifact (kube-prometheus-stack legacy selector); for gpu-ai it is
**inert** — gpu-ai's alloy discovers operator objects with no label requirement
(`prometheusOperatorObjects` has no selector configured in `charts/k8s-monitoring/values.yaml`).

Placement choice the planner must make (both are precedented): a raw ServiceMonitor template
inside `charts/radiance/templates/` (per-release names land automatically: the chart renders
once per release; or one monitor matching `app.kubernetes.io/name=radiance` across both)
vs. the annotation pair in `charts/radiance/values.yaml` (zero new objects, auto-covers fn+q27,
exact vllm-chart precedent) vs. a services/gpu-ai/prod/templates/ file (self-monitor.yaml
precedent but that file is monitoring-cluster-local).

**(b) The dashboard entry, cf-105 shape verbatim**
(`services/monitoring/prod/values.yaml:659-668`):

```yaml
      vllm-performance-statistics:
        # Pinned to the vllm repo TAG v0.33.0 — the same tag as the
        # containers/vllm-rocm base image (C01 ledger + charts/vllm values).
        # renovate can't track a raw URL: bump this WITH the image pin.
        url: https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/examples/observability/dashboards/grafana/performance_statistics.json
        datasource: Prometheus
      vllm-query-statistics:
        # Same tag-coupling as above.
        url: https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/examples/observability/dashboards/grafana/query_statistics.json
        datasource: Prometheus
```
The radiance analogue drops into the same `default:` provider folder:
`radiance: { url: https://codeberg.org/StillDeadcode/radiance/raw/tag/v1.17.0/deploy/grafana/radiance.json, datasource: Prometheus }`
— tag-coupled to `charts/radiance` `1.17.0` (fact #1). No vendored-JSON or image-pull path
exists or is needed in this repo (fact #10, #18; grep confirms zero `grafana_dashboard`
ConfigMap precedents).

**(c) The chart's service block (wiring target)** —
`charts/radiance/values.yaml:414-419`:

```yaml
  service:
    radiance:
      controller: *chartName
      ports:
        http:
          port: 8000
```

## 4. Gotchas

- **G1 — never trust “entry on main == dashboard live”.** Proven broken today (fact #17):
  manual-sync fleet (no `automated` block, `RespectIgnoreDifferences=true`), and url/gnet
  JSONs are fetched by the `download-dashboards` init container only at pod rollout. The
  validation plan must stop at render-time checks (`helm lint`/`helm template` of the
  services chart, or a python/yaml grep leg per the repo “tests = validation” law) and
  explicitly defer sync+rollout+appearance to the owner.
- **G2 — the vllm pair is the cautionary tale, not a template to copy blindly:** its two
  URLs have sat unfetched for 16 days. The card’s “vllm lane's dashboards stay as C01 left
  them” is satisfied by simply not touching the entries (D6 verbatim: untouched). Do not
  “helpfully” verify or delete them; their absence live is pre-existing, and one manual
  sync of `monitoring-grafana` fixes radiance AND resurrects vllm in one shot (both fetch
  at the same rollout). Say so in the plan so nobody is surprised when vllm tiles appear
  with no data (the vllm lane serves nothing; empty panels ≠ incident).
- **G3 — fn scales to 0 by the owner's protocol** (D29/step-10: strata-restore-back is an
  either/or at 110 GiB). Wire the scrape to select BOTH releases and accept that
  `radiance:*`/`vllm:*` series exist only while a radiance engine runs; zero series while
  fn is down and q27 at 0 is the designed shape, not a failure. Do not pin ACs that
  require fn to be up.
- **G4 — the metrics path is `/metrics` on 8000 (serveArgs set no `--metrics-path`** —
  absent from the shipped arg list; the docs' endpoint table names `/metrics` directly,
  RESEARCH:558-562). Both annotationAuto-discovery (default path `/metrics`) and a
  ServiceMonitor endpoint (`path: /metrics` default) cover it; keyless D8 means no auth
  relabeling needed.
- **G5 — DNS-rebinding guard asymmetry**: `/metrics` sits on the machine-view class only
  for `/diagnostics`-style routes per RESEARCH:575-582 — `/metrics` was read fine
  loopback-forwarded (§R15 pair). Alloy scrapes pod-to-pod (not via Host: localhost),
  which is the same socket class as the runbook's port-forward; expected OK but it is the
  one live-behavior assumption the wiring change makes. The owner-exec leg (below) settles
  it honestly.
- **G6 — digest/renovate ledger coupling**: if the plan adds a dashboard URL entry, the
  tag-coupling comment style (bump WITH the image pin) is required, and renovate's
  `datasource=docker depName=docker.io/stilldeadcode/radiance` annotation
  (`charts/radiance/values.yaml:226`) stays the single pin source.
- **G7 — repo validation law**: there is no unit-test suite; per AGENTS.md the "tests" are
  `helm lint charts/radiance` + `helm template` + grep trios. A chart edit (annotations or
  a ServiceMonitor template) must extend `charts/radiance/tests/` — the suite is
  render-assert-based (`test_render.py`, `test_serve_args.py`, `test_contract.py` exist and
  run pytest per-directory with the `PATH=$HOME/.local/bin` helm gotcha, AGENTS.md).
  Current tests pin the ABSENCE of nothing metrics-related (fact #4) — so the suite is
  silently green today; new pins are the plan's call.
- **G8 — the MCP list shape**: `resources_list` returns flattened `Name/Age/Labels/…` string
  rows (not manifests) — same friction the parent scout logged; use `resources_get` for specs.

## 5. Owner-exec legs (barred from agents by design)

- Verify the endpoint live on the running engine (the card's step-9 successor). Exact,
  no pod exec for agents (AGENTS.md: no tier grants exec; present the command):
  `kubectl -n default port-forward svc/gpu-ai-radiance-q27 8000:8000 &` then
  `curl -s http://127.0.0.1:8000/metrics | grep -m5 -E "^vllm:|^radiance:"` (fn variant:
  `svc/gpu-ai-radiance`, requires scaling fn back up per step 2/10). On q27 today this
  should return `radiance:*`/`vllm:*` lines if the engine build behaves as §R15 witnessed.
- Sync `monitoring-grafana` (ArgoCD, monitoring cluster) after the entry merges, confirm
  the `download-dashboards` init ran, and visually accept the dashboard (folder “default”
  = unfiled, unless the plan picks a provider folder). Also the human half of G1: the
  branch-side AC can only be render/grep-level.
- (Historic, likely moot) the runbook's “owner's metrics file” series of manual /metrics
  pairs — §R15's pair already landed; a new scrape makes the file obsolete but retiring it
  is owner prose work, not this ticket's.

## 6. Open for planner

1. **Scrape mechanism choice** — annotation pair (vllm-chart precedent, zero new objects,
   auto-covers fn+q27, 60 s default interval) vs. per-release ServiceMonitor template in
   charts/radiance (typed object, explicit port name `http`, interval control, job names
   become `default/gpu-ai-radiance[-q27]`). Both provably reach the central TSDB (facts
   #13-14); annotationAutodiscovery is enabled-but-unproven-on-this-cluster (no live
   annotated pod anywhere since the vllm lane slept), ServiceMonitor/PodMonitor on member
   clusters is PROVEN (cnpg witnesses). Pick with that asymmetry in mind, or pick SM for
   the proof.
2. **Which provider folder / entry name** for the dashboard (default vs. a new
   `inference:` provider folder would touch `dashboardProviders` too — the vllm precedent
   says `default:`).
3. **AC boundary** — recommend: chart/services render + values grep as the automated legs;
   “dashboard visible” and “series flowing” become OWNER-EXECUTED checklist lines (G1/G-§5),
   possibly with a follow-up owner note that one `monitoring-grafana` sync also resurrects
   the two vllm dashboards (G2).
4. **Runbook edit wording** — step-9 lines 679-683 must be rewritten to point at the wired
   dashboard + the monitor wiring (and its “Do NOT edit services/monitoring/prod/values.yaml
   in this run” becomes historical; keep the sentence's intent but re-anchor it, this IS
   the follow-up card it deferred to).
5. **The /stats fallback branch** — do NOT plan for it as default: it exists for “scrape
   engine-side-absent”, which §R15's live pair refutes for this build (fact #9); leave it
   one honest line (fallback witness RESEARCH:3516-3522, 3630-3637) in case the owner-exec
   curl in §5 unexpectedly 404s.
6. **fn at zero pods**: whether any validation leg waits for an owner fn up-scale, or the
   plan validates against q27's live pod only (G3).
7. Whether to also record a DECISIONS line closing the parent's D6/Q6 follow-up #2 when
   this lands (parent DECISIONS:1903-1904 is this card's mandate).

RESULT
status: DONE
chunk: plan
files_changed: [.agents/plans/2026/2026-11-cf-145-feat-radiance-grafana-metrics/EXPLORE.md]
commands_run: [repo reads/greps (charts/radiance values+Chart.yaml full, charts/vllm monitoring blocks, charts/k8s-monitoring values, services/monitoring/prod values+templates, services/gpu-ai/prod values, runbook 628-702, cf-143 STATE/DECISIONS/RESEARCH/EXPLORE windows, cf-145 STATE.json) => pass; git (branch/log/show-current/status/merge-base ancestry of d0670e031) => pass; readonly-ai-gpu-kubernetes: pods_list_in_namespace ×3 label selectors, resources_list Service/Deployment/StatefulSet/ServiceMonitor/PodMonitor, resources_get Service+CRD => pass; readonly-monitoring-kubernetes: resources_list ConfigMap/Pod/Application, resources_get Application monitoring-grafana + Pods, configmap gets => pass; readonly-global-grafana: query_prometheus ×7 (vllm/radiance/kv regex, 24 h range, kube_pod_info, up by job, cnpg census), list_prometheus_metric_names, list_prometheus_label_values(cluster), search_dashboards ×5, grafana_api_request /api/search + /api/dashboards/uid/radiance => pass; webfetch codeberg raw deploy/grafana/radiance.json @v1.17.0 => pass (200, valid dashboard JSON)]
deviations: none — readonly tiers only, no admin, no pod exec, no board/cluster writes; wrote EXPLORE.md inside the ticket folder only; webfetch used once for the engine project's own pinned-tag artifact (allowed by the launch).
friction: readonly-ai-gpu-kubernetes resources_list emits flattened rows and returns null (not an empty items array) for absent custom-resource kinds — validated the null semantics with a positive control on the monitoring cluster; the grafana search_dashboards tool caps at 50 rows with hasMore — full enumeration needed grafana_api_request /api/search?limit=1000.
open_questions: [planner-decision: ServiceMonitor (proven cross-cluster path via alloy) vs k8s.grafana.com annotation autodiscovery (vllm-chart precedent, config-enabled but no live proof on gpu-ai since the vllm lane slept) — §6.1; planner-decision: dashboard provider folder + entry name (§6.2); owner-legs: the §5 port-forward /metrics curl, the manual monitoring-grafana sync+rollout (no automated policy fleet-wide; the same sync also resurrects the two vllm dashboards — pre-existing, do not treat as this ticket's regression); needs research: no — the /metrics docs-verification and the endpoint evidence are already settled by the parent RESEARCH (§R14/§R15) + this round's tag-URL fetch]
next_suggested: agent-plan reads this file + the vllm-entry block (values.yaml:659-668) and charts/vllm/values.yaml:103-107,254-264, then chunks: scrape wiring (pick §6.1 mechanism, extend charts/radiance tests) + grafana.dashboards radiance url entry (vllm shape) + runbook step-9 note rewrite; all ACs render/grep-level with the sync/rollout/curl legs marked OWNER-EXECUTED.
