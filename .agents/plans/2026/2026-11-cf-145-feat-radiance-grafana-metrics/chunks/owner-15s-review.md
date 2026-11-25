# owner-15s-review — uncommitted delta (gpu-ai scrape cadence 60s -> 15s, gpu-ai-only)

Verdict: **APPROVED** (1 minor, 1 nit — none blocking). Dev session: ses_defbd4285ffe8HHm6jtxCo1B7H (DONE).

## Evidence (fresh, this session — all commands direct RC)

- Item 1 values block: `python3 /tmp/opencode/rev15s-parse.py` RC=0 — YAML
  parses, single doc, 11 unique top-level keys, `k8s-monitoring` occurs once at
  column 0 (line 1747, outside `charts:` whose entry stays
  `{namespace: default, ServerSideApply: "true"}` byte-untouched), subtree ==
  `{"k8s-monitoring":{"global":{"scrapeInterval":"15s"}}}`.
  Merge path proven at BOTH levels:
  (1) `helm template gpu-ai services/gpu-ai/prod` RC=0 — generator `values:`
  JSON (rendered appset :155) carries exactly
  `"k8s-monitoring":{"k8s-monitoring":{"global":{"scrapeInterval":"15s"}}}`;
  diff vs HEAD render = 2 lines only (the injection).
  (2) base-chart leg: temp copy of charts/base (deps-stripped, /tmp only, repo
  untouched) + `-f services/gpu-ai/prod/values.yaml` RC=0 — the
  `appName: k8s-monitoring` element's `values` ==
  `{"k8s-monitoring":{"global":{"scrapeInterval":"15s"}},"shared-storage":null}`;
  at HEAD values the alias key is absent. Outer level consumed by
  appset-charts.yaml `index $.Values $appName`; inner level is the wrapper
  dependency alias (charts/k8s-monitoring/Chart.yaml dep name
  k8s-monitoring; alias block confirmed at values.yaml:6). Double key =
  correct merge path, not typo.
- Item 2 render truth: `helm template charts/k8s-monitoring -f <subtree>`
  RC=0, 79641 lines; control (no overlay) RC=0. ctl→overlay diff = 24 lines =
  exactly 12 pairs: 2x `replacement = "15s"` (enclosing blocks confirmed
  `discovery.relabel "annotation_autodiscovery_pods"` :634 /
  `..._services"` :755, fallback rule shape `__scrape_interval__` empty ->
  replacement), 3x `default_scrape_interval = "15s"`
  (prometheus.operator.podmonitors/probes/servicemonitors), 7x feature
  `scrape_interval = "15s"` (kubelet :872, kubelet_resources :922, cadvisor
  :967, apiserver :1108, kube_state_metrics :1165, node_exporter :1319,
  kubernetes_monitoring_telemetry :1451 = selfReporting — upstream
  _feature_self_reporting.tpl:99 `selfReporting.scrapeInterval | default
  global.scrapeInterval` confirms the inheritance). Zero interval-literal 60s
  left; residual 3x `60s` = `kubectl wait --for=delete ... --timeout=60s` in
  the Alloy pre-delete hook (non-interval, known). Control = 12 interval 60s
  (15 total with the 3 hook lines). `scrape_timeout = "10s"` x9 +
  `default_scrape_timeout = "10s"` x3 invariant; 10s < 15s holds.
- Item 3 runbook: only note hunk @@ -827,7 +827,9 @@ — inside the Step 9
  window (:792–:881). New phrase names the 15s gpu-ai override + owner
  directive 2026-11-25 + keeps "4.5.5's global default is 60 s" — all three
  independently true (upstream 4.5.5 values.yaml `scrapeInterval: 60s`, wrapper
  sets none, renders prove 15s). No stale 60s-interval sentence left in the
  note (other `60s` hits are `gpu-8060s` resource names).
  `pytest charts/radiance/tests/test_runbook_note.py -q` => 10 passed RC=0;
  `git diff HEAD --stat -- charts/radiance/tests/ tests/notes/` => EMPTY
  (unmodified); `bash tests/notes/radiance-runbook.sh` RC=0 (5 ok);
  `bash tests/notes/radiance-roster.sh` RC=0 (4 ok — its T2 re-derives rows
  from the EDITED values file and stays green).
- Item 4 suite: `python3 -m pytest charts/radiance/tests -q` =>
  **193 passed / 1 skipped / 0 failed**, RC=0 — matches claim. No test asserts
  a rendered interval value: `scrapeInterval` in tests appears only as a
  BANNED-KEY name (key-presence assertion, unaffected by the umbrella-level
  override) plus two prose sites (see minor).
- Item 5 scope honesty: tree-wide `grep -rn scrapeInterval services/
  custom-values/` => exactly 1 hit (gpu-ai:1750). external-hosts alloy
  configmap = services/monitoring/prod/templates/configmap-alloy-external-config.yaml
  (:32 own `scrape_interval = "60s"`) — monitoring cluster, byte-untouched.
  Old `gpu` umbrella: no k8s-monitoring subtree at all (stays upstream 60s).
  Log/event routes carry no scrape-interval concept — proven from render:
  nodeLogs `loki.source.journal "worker"` (:92), podLogs
  `loki.source.file "pod_logs"` (:390), clusterEvents
  `loki.source.kubernetes_events "cluster_events"` (:1529) — none has a
  scrape_interval argument.
- Item 6 gate: `npx --yes aislop scan --changes` RC=0, 118 files, 0 issues,
  100/100 — with the recorded quirk: "Scope 0 changed file(s)" for uncommitted
  work (same class as last round) and YAML/Markdown are outside aislop's
  analyzed languages, so neither delta file is scoreable-by-design; CI
  `aislop ci --changes` gates at PR. `git status --short` => exactly the two
  intended files, no strays (the 2026-11-19 "WIP on main" stash predates the
  directive — pre-existing repo state, not this delta's artifact).

## Findings

- minor — charts/radiance/tests/test_scrape_annotations.py:47 ("metrics.scrapeInterval
  -> the feature's global 60 s default") and :180 (failure message
  "(job `radiance`, 60 s, /metrics)"): true as UPSTREAM 4.5.5 default
  statements (verified), but both read as the EFFECTIVE gpu-ai cadence and are
  now false on this very branch — the guard's red text will tell the next
  person their interval is 60 s when gpu-ai ships 15 s. Not a weakening (the
  assertion bans per-pod annotation KEYS only; behavior correct, suite green).
  Fix (follow-up, comment/message-only): "(… global scrapeInterval — upstream
  default 60 s; gpu-ai overridden to 15 s, owner directive 2026-11-25)".
- nit — services/gpu-ai/prod/values.yaml:1741 pins the alias explanation to
  "charts/k8s-monitoring/values.yaml:6" — a positional anchor that drifts on
  any wrapper-values edit; the keyed reference alone survives. Same class as
  the prior round's deferred line-number nit.

## Conventions check

- Comment law: the values.yaml block comment passes the three-clause test —
  it carries the merge-path rationale a reader cannot see from the block
  (the double key looks like a typo), the invariant (per-cluster isolation),
  and dated provenance; deleting it invites a "simplify"-break. Kept.
- No version/tag bumps (Chart.yaml files untouched — release.yaml owns
  bumps). No secrets touched. No generated surfaces edited. Rulesync N/A
  (no .rulesync input in the diff). git: uncommitted per brief — commit is
  coord's leg.
- Governance gap (coord leg, not a code finding): the 2026-11-25 owner
  directive is NOT yet in DECISIONS.md nor in STATE.json `owner_followups`
  (grep: no '2026-11-25'/'15s' hits). Precedent: the 2026-11-22
  renovate-tracking entry. DECISIONS/STATE are coord-owned.

## Deferred

- Live-side effects of 4x cadence (Alloy CPU/series volume on gpu-ai,
  Prometheus retention pressure) are runtime/owner legs — nothing in-repo
  gates them; out of this review's scope per the gpu-ai-only directive
  framing.
