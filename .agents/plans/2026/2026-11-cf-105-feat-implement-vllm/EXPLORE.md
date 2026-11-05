# EXPLORE — cf-105 "Implement vLLM"

Grounded by `agent-explore` 2026-11-04, read-only (repo reads + read-only MCP probes
on `dev-boards`, `readonly-ai-gpu-kubernetes`, `readonly-gpu-kubernetes`). Worktree
`cf-105-feat-implement-vllm` off main @ `ceb9a8ed6`.

The request (WeKan card cf-105, id `R4EjaHtDeHMjAkDpf`): add vLLM for
`qwen3.8-27b` on the "32GB video card" (3-4 parallel sessions, 100-256k ctx),
evaluate vLLM for the flash model vs Strata (~50 tok/s bar), research a UI,
wire the card-level `Priority` custom field into agent context, and research
Prometheus/Loki/Alloy monitoring for vLLM. All four research threads are
open — this file grounds the repo/cluster facts they plan against.

---

## 1. The llama-swap / llama.cpp / Strata deployment as it stands

**Clusters.** Two GPU clusters, both **AMD** (no NVIDIA anywhere in the repo or
either cluster):

| Cluster | Node (live) | CPU | RAM | GPU resource | Card(s) |
|---|---|---|---|---|---|
| `gpu` (services `services/gpu/`) | `gpu`, k3s v1.36.5+k3s1, containerd 2.3.4, openSUSE TW | 13 | ~30 GiB (`29994252Ki`) | `amd.com/gpu: 1` | 8 GiB Radeon 780M iGPU (`services/gpu/prod/values.yaml:258-265` comment) |
| `gpu-ai` (services `services/gpu-ai/`) | `ai-gpu`, k3s v1.36.5+k3s1 | 32 | ~128 GiB (`131151316Ki`) | `amd.com/gpu: 2` | **8060S** (gfx1151, PCI `1002:1586`, RDNA 3.5, up to 32 GB of shared LPDDR5X) + **R9700** (gfx1201) on OCuLink — `.agents/notes/strata-host-prep-gpu-ai.md` step 0.3; enumeration `0=R9700, 1=8060S` (`charts/llama-swap/values.yaml` `rocrVisibleDevicesByModel` comment) |

Node capacities verified live via `readonly-*-kubernetes.resources_get`
(`status.capacity/allocatable`) 2026-11-04. **The user's "32GB video card" is
the 8060S iGPU** — the card the dense llama.cpp 27B models run on ("llama.cpp
runs on the unified-memory 8060S, so every warm model is plain system RAM",
`services/gpu-ai/prod/values.yaml:474-476`). The R9700 is the card Strata's
pinned arenas run on (`rocrVisibleDevices: "0"`, `services/gpu-ai/prod/values.yaml:196-198`).

**Chart.** `charts/llama-swap/` — `Chart.yaml`: name `llama-swap`,
`version: 1.0.40`, `appVersion: unified-vulkan-266`, dependency
`app-template` 5.0.1 (bjw-s). Deployed from BOTH service values files:
`services/gpu/prod/values.yaml:100-102` and `services/gpu-ai/prod/values.yaml:22-24`
(`namespace: default`, `ServerSideApply: "false"`). Releases render as
`gpu-llama-swap` / `gpu-ai-llama-swap`.

**Image.** `ghcr.io/mostlygeek/llama-swap:unified-vulkan-266`
(`charts/llama-swap/values.yaml:1005-1007`) — the **Vulkan** unified build
(AMD). Pinning is renovate-managed but scoped: a dedicated packageRule in
`renovate.json:285-292` limits updates to the `unified-vulkan-<N>` tag family
(`versioning: regex:^unified-vulkan-(?<major>\d+)$`) because the built-in docker
versioning can't parse the tag. Digest of record:
`sha256:0cc42f1024b54be3de100ae7a7a2730047ca5c27cf7a354f8a9f63142f00c045`
(values comment, re-verified 2026-10-25).

**Main pod shape** (`charts/llama-swap/values.yaml:964-1050`):
- probes liveness+readiness `httpGet /health:8080` (the supervisor's own port —
  safe mid-swap)
- `resources.limits: {amd.com/gpu: 1}` (requests cpu 1000m / mem 4Gi)
- env: `LLAMA_CACHE=/models`, `LLAMA_SWAP_CONFIG=/app/config/config.yaml`,
  `LLAMA_SWAP_WATCH_CONFIG: "true"` (hot reload via directory mount)
- `tools` sidecar (LoRA conversion, `python:3.15.1-slim-bookworm`,
  `sleep infinity`), default-OFF, enabled on gpu-ai
- `reloader.stakater.com/auto: "true"` controller annotation

**Config content — where it lives.** The llama-swap config is a chart
`config:` values block (`charts/llama-swap/values.yaml:13+`), rendered by
`templates/_helpers-llama-swap.tpl` (`llama-swap.declaredConfig`) into
`templates/configmap-llama-swap.yaml` → ConfigMap `llama-swap-config`,
directory-mounted at `/app/config` (`values.yaml:1344-1366`; subPath mounts
never receive ConfigMap updates — the 2026-10-17 hot-reload incident). The
block layers: `config.macros`, `config.families` (the CA2 catalog — family ×
rung expansion; every rung ships `enabled: false` and the two service values
files flip enablement), `config.models` (per-ID override / raw-cmd escape
hatch), `config.matrix` (vars + sets), `config.peers`, `config.hooks`.
Service-level overrides: `services/gpu-ai/prod/values.yaml:87-560` (the
Qwen3.8-27B roster: `qwen3.8-27b-q4/q6/q8/bf16` with ggml-org MTP drafts,
`-c 262144`, cache-persistence tuning; `qwen38-rana` raw cmd; the
`peers.strata` route; gpu-ai-only `main`/`solo` matrix sets) and
`services/gpu/prod/values.yaml:257-418` (8 GiB-box tuned rungs +
`disabled:` fail-fast echoes).

**Peers → Strata route** (`services/gpu-ai/prod/values.yaml:493-521`):
`peers.strata.proxy: http://gpu-ai-llama-swap-strata.default.svc.cluster.local:8080`
(NO `/v1` suffix — path appends verbatim), `models:` lists the five inner IDs
explicitly, `timeouts.responseHeader: 1800` (cold arena pin). Peer models are
**invisible to the outer matrix solver** — coexistence is operator discipline.

**Strata = a second controller of the SAME Application** (cf-77 run-2
consolidation; `services/gpu-ai/prod/values.yaml:15-19` comment +
`charts/llama-swap/README.md`). Chart-default-OFF; flipped ON by SEVEN scalars
that must move together (`app-template.controllers.strata.enabled` +
`service.strata.enabled` + five `persistence.strata-*` entries —
`services/gpu-ai/prod/values.yaml:127-189`): controller + Service
`gpu-ai-llama-swap-strata` (ClusterIP, no ingress by the Q4 ruling) +
`strata-config`/`strata-profile` ConfigMaps, hostPath `/dev/kfd` + `/dev/dri`,
2 GiB shm emptyDir. Pod: `privileged: true` + hostPath devices (documented
deviation from the drop-ALL standard, `values.yaml:1313-1323` — the amd-gpu
plugin "advertises by count and cannot name gfx1201 vs the 8060S"),
`strategy: Recreate` (a RollingUpdate overlap double-pins the arena),
`terminationGracePeriodSeconds: 420` > `unloadTimeout 180` + 30 s drain,
`limits.memory: 116Gi` (paired with the engine's `--memory-limit-mib`).
Image `ghcr.io/ownyourio/strata:main` + `pullPolicy: Always` (brand-new
container rule — PIN-ME comment, `values.yaml:1209-1214`). Inner roster: 5
models (`qwen3.8-flash-next-strata`, `-strix`, `-orca`, `-q4`,
`ornith-1.5-122b-strata-q4`), inner matrix `(p | s | o | q | n)` — all
alternatives, one arena at a time.

**Storage.** PVC `llama-swap` (RWO, local-path): chart default
`modelsPvcSize: 300Gi` (gpu), gpu-ai overrides `500Gi`
(`services/gpu-ai/prod/values.yaml:88`). Live: **Bound 500Gi** on ai-gpu
(`resources_list` PVC probe 2026-11-04). Strata stages weights under
`/models/strata/` on the SAME claim (Q3 ruling — no second PVC,
`values.yaml:1381-1389`).

**Ingress / public surface (gpu-ai)** (`services/gpu-ai/prod/values.yaml:43-75`):
- `ai-llama-swap` → service `gpu-ai-llama-swap:8080`
- `llama` (clusterBase → internal `llama.gpu-ai.<domain>` + serviceName →
  public `llama.<domain>`) → same service
- every subdomain Ingress gets
  `traefik.ingress.kubernetes.io/service.serverstransport:
  default-llama-timeouts@kubernetescrd` (`services/gpu-ai/prod/templates/generic-ingress.yaml:17`);
  `servicestransport-llama.yaml` sets `forwardingTimeouts.responseHeaderTimeout: 0`
  + `idleConnTimeout: 3600s` (model loads / long prefills)
- public chain: `services/proxy-local/prod/values.yaml:286-292` — `llama:
  target: gpu-ai` with Keycloak SSO redirect; gpu's `llama-moe` → gpu cluster
  (lines 306-313). `ai-llama-swap` is served directly by gpu-ai's traefik,
  hub route disabled (comment 234-240).
- Preload hook: `hooks.on_startup.preload: []` — the pod boots with NOTHING
  resident (owner ruling 2026-11-02, `services/gpu-ai/prod/values.yaml:480-492`).

**Live state (readonly probe 2026-11-04, ai-gpu `default` ns):**
`gpu-ai-llama-swap-*` 2/2 Running (main+tools); `gpu-ai-llama-swap-strata-*`
1/1 Running; `amd-gpu-device-plugin-daemonset` Running; alloy pods
(`gpu-ai-k8s-monitoring-alloy-{metrics-0,logs,singleton}`) Running; gpu
cluster: `gpu-llama-swap-*` 1/1 Running, device plugin Running.

## 2. gpu-ai provider wiring (agent context)

- **Repo config** `.opencode/opencode.jsonc:75-92`: `providers.gpu-ai` —
  `package: aisdk:@ai-sdk/openai-compatible`, `baseURL:
  https://llama.spencerslab.com/v1`, `headerTimeout`/`chunkTimeout` both
  `7200000` (2 h; deep-prefill 499 rationale in the comment). Model catalog
  (lines 92-796): ~70 entries whose `modelID` **is** the llama-swap model ID
  verbatim (`qwen3.8-27b-q4`, `qwen3.8-flash-next-strata`, …), with
  `capabilities` and `limit.context` (262144 for the 27B/flash rungs,
  1010000 for `qwen3.8-27b-q8-1m`, 8192 for the 3B entries). So **model ids
  map 1:1 to llama-swap model ids** — the provider is a thin OpenAI-compatible
  facade over `llama.<domain>`.
- **Machine-global config** `~/.config/opencode/opencode.json` (NOT in the
  repo): the `gpu-moe` provider (line 735+), `baseURL:
  https://llama-moe.spencerslab.com/v1` (the gpu cluster's 8 GiB box), same
  2 h timeout shape. AGENTS.md records machine-global changes in the repo's
  table — a new vLLM provider/base-URL would follow the same split.
- **Routing rules**: `.opencode/skills/pipeline-models/SKILL.md` (source:
  `.rulesync/skills/pipeline-models/SKILL.md`) — the role→model table
  (planning tier `openrouter/qwen/qwen3.8-2.4t-a95b`, code tier
  `openrouter/qwen/qwen3.8-27b`), the kickoff picker mapping (`Qwen Large` /
  `Qwen 27b` / `Qwen Flash` / `Local (gpu-ai)`; `Local` → `gpu-ai/qwen3.8-27b-q4`
  default; Flash+Local → `gpu-ai/qwen3.8-flash-next-strata`), and the
  "Favorited models in this lab" table where a new vLLM-served model row would
  land. `.rulesync/skills/pipeline-kickoff/SKILL.md` — the live kickoff
  questions (slug, models) and where the answers land in `STATE.json`
  (`kickoff.models {plan, code}` + `local` flag).
- **Board family**: `.rulesync/skills/boards/SKILL.md` — card-driven intake
  (five checklists + slug CF answer kickoff), the Model(s) checklist drives
  routing (see §6).

## 3. Monitoring stack as it exists

- **Central** (monitoring cluster, `services/monitoring/prod/values.yaml`):
  kube-prometheus-stack Prometheus at `prometheus.spencerslab.com`, Loki at
  `loki.spencerslab.com` (S3-backed, `charts/loki/values.yaml` — tsdb schema
  v13, 30-day retention, `s3.spencerslab.com`), Grafana + dashboards
  (subdomains at `services/monitoring/prod/values.yaml:48-57`).
- **Per-cluster**: the `k8s-monitoring` wrapper chart
  (`charts/k8s-monitoring/`, no templates of its own — it wraps
  grafana/k8s-monitoring **v4**) is deployed on gpu-ai
  (`services/gpu-ai/prod/values.yaml:30-34`), gpu, monitoring, etc.
  `charts/k8s-monitoring/values.yaml` (read in full):
  - `destinations`: prometheus → `https://prometheus.spencerslab.com/api/v1/write`
    (remote write), loki → `https://loki.spencerslab.com/loki/api/v1/push`
  - `collectors`: `alloy-metrics` (statefulset), `alloy-singleton` (singleton),
    `alloy-logs` (daemonset + filesystem-log-reader) + `telemetryServices`
    node-exporter & kube-state-metrics (deploy: true)
  - **`prometheusOperatorObjects.enabled: true`** → PodMonitor/ServiceMonitor
    CRs are discovered and scraped (the wrapper installs the CRDs itself,
    values comment lines 137-143)
  - **`annotationAutodiscovery.enabled: true`** → `prometheus.io/*`
    annotation discovery
  - **`podLogsViaLoki.enabled: true`** → pod logs → Loki. This is the existing
    inference-log path: the chart's `logToStdout: "proxy,http"` comment says
    the request lines "still reach Loki via pod logs"
    (`charts/llama-swap/values.yaml:27-29`)
  - kepler/opencost (energy/GPU-cost metrics) explicitly disabled
- **Nothing scrapes llama-swap today**: no PodMonitor/ServiceMonitor template
  in `charts/llama-swap/`, no `prometheus.io` annotations anywhere in the
  chart (grep-verified). llama-swap does expose `/metrics` and a
  `performance` config block (CPU/RAM/GPU stats polling); the chart sets
  `performance: {enable: true, every: 5s}` — note `enable` is a legacy key the
  pinned v266 schema does NOT accept (schema has `performance.{disabled,every}`
  with `additionalProperties: false`); the test suite strips it via
  `strip_legacy_performance_keys` (`charts/llama-swap/tests/strata_testlib.py:725`,
  carve documented in `tests/test_strata_wiring.py:249`).
- The only PodMonitor/ServiceMonitor CR template in the repo is
  `services/monitoring/prod/templates/self-monitor.yaml` (ServiceMonitor for
  prometheus self-scrape); CNPG `pg-*` templates carry `enablePodMonitor`.
  So a vLLM scrape target = new PodMonitor/ServiceMonitor (or annotations) in
  its chart — the alloy side already does the rest. **No GPU exporter exists
  anywhere in the stack** (no rocm/dcgm exporter chart).

## 4. New gpu-ai service: the trio + validation commands

**Trio** (helm-chart-creation skill; verified in-repo):
1. **ApplicationSet entry** — `charts: <name>: {namespace: default,
   ServerSideApply: "false"}` in `services/gpu-ai/prod/values.yaml`. Rendered
   by `services/gpu-ai/prod/templates/appset.yaml` (ApplicationSet
   `gpu-ai-appset`, `baseChartVersion: 1.0.198`, valueFiles =
   `services/gpu-ai/prod/values.yaml`) which pulls
   `charts/base/templates/appset-charts.yaml` → one Application per
   `charts:` entry; the app's values come from the same file's `<appName>:`
   block (`index $.Values $appName`).
2. **Proxy values entry** — `ingress.subdomains.<name>: {service:
   gpu-ai-<appName>, port: N}` in the same file (generic-ingress renders the
   Ingress; add `clusterBase`/`serviceName` for the public host; a public
   host also needs the `services/proxy-local/prod/values.yaml` `target:
   gpu-ai` leg, the `llama:` shape being the precedent).
3. **custom-values entry — only with Bitwarden secrets**:
   `custom-values/gpu-ai/prod-values.yaml` currently holds cert-manager
   solver, argocd SSO, hivetools mcp-sso, and `llama-swap.bitwardenIds.hf-token`
   (whole file is 22 lines). A vLLM service without secrets gets NO entry.

**Commands a chunk runs** (AGENTS.md "Pipeline specifics in this repo" +
`charts/llama-swap/tests/TEST_SPEC.md`):
- `export PATH=$HOME/.local/bin:$PATH` FIRST — helm v3.16.4 lives at
  `~/.local/bin/helm`, not on the default PATH (verified: `which helm` fails
  without it; without it pytest silently mass-skips helm-guarded tests).
  `python3 -m pytest` is available (pytest 9.1.1).
- `helm lint charts/<name>` and `helm template charts/<name> --debug`
- render with `--set domain=… --set clusterName=gpu-ai --set
  bitwardenIds.<x>=test-uuid` and confirm no `OVERRIDE_*` sentinels in output
- trio grep: `grep -r "<name>" services/*/prod/values.yaml`
- pytest **per-directory** (test basenames duplicate across chart suites),
  e.g. `python3 -m pytest charts/<name>/tests -v`. CI precedent for this
  chart: `.github/workflows/llama-swap-tools-tests.yaml` (ubuntu-24.04, helm +
  python3.12 + network, `helm dependency update` then pytest; TEST_SPEC §4).
- The llama-swap suite is a good template for a config-render harness:
  `charts/llama-swap/tests/` — goldens captured by extracting the rendered
  ConfigMap data (TEST_SPEC §1 command block), schema pinned at
  `tests/schema/config-schema.v266.json` (sha256 in `tests/schema/PROVENANCE.json`),
  ~30 test files (parity/schema/roster/strata-*/render/boot_safety).

**Version rules that bite**: new chart starts `version: 1.0.0` ONLY (chart
releaser `release.yaml` bumps the patch on every merge to main; tags
`<chart>-<version>` — never hand-bump). Containers push
`:v<run_number>` (immutable) + `:<branch>` (rolling) automatically — see §5.

## 5. Container surface

- `containers/` today: 12 dirs; **the only GPU container is
  `containers/strata`** (AMD/ROCm): `Dockerfile` multi-stage over
  `ghcr.io/niko1221/strata:0.2.9-rocm-gfx120x` + `:0.2.9-rocm-gfx1151` engine
  images, the llama-swap supervisor binary harvested from
  `unified-vulkan-266`, and an alpine source-checkout stage (v0.2.9 + vendored
  `carry/ornith-q36.patch`). Pinning is **manual, no renovate directives by
  contract** — the tag→digest ledger lives in `containers/strata/README.md`
  (line 74+), each bump re-verifies digests + re-benches.
- **No CUDA/NVIDIA container exists in the repo** (no `nvidia` hit in
  charts/ or services/). A vLLM image would be either an upstream ROCm image
  (`vllm/vllm-openai:rocm*`-class, pinned tag per repo pinning rules) or a new
  `containers/<name>` if a fork is needed (the gfx120x/gfx1151 flavor pattern
  of strata is the closest in-repo precedent for arch-specific GPU images).
- **`docker-build.yaml` facts**: triggers on push/PR to main/dev touching
  `containers/**` (lines 8-19); per changed dir builds with buildx + GHA
  cache; on CI push pushes `:v<run_number>` + `:<branch>`; **PR builds build
  only, never push**. There is **no docker daemon in agent sessions** —
  `docker build` acceptance is CI-primary; locally, build-critical facts are
  verified from GHCR layer tar-listings / manifest digests, and a
  `docker build => no-daemon, CI-deferred` line is the designed gate shape
  (AGENTS.md + container-creation skill checklist).

## 6. Board / agent-context surface for the `Priority` custom field

**Live board facts** (dev-boards read-only probes 2026-11-04, AI-Dev board
`TNQJ2BrXenZovngTS`):
- `list_custom_fields` → exactly three fields:
  `slug` (text, `RaNeqvh9YoT4bnkZ8`), `session` (text, `zZw4PwMoLeodJy3eT` —
  legacy, retired), and **`Priority` (NUMBER, `fp5vnD5YrA7oAxPiK`)**
- `get_custom_field(Priority)` → `settings: {}` (empty — no min/max/range),
  `show_on_card: true`, `automatically_on_card: true`, `always_on_card: true`
- cf-105 card (`R4EjaHtDeHMjAkDpf`): `card_number: 105`, labels
  `f3sKNX` + `ezGduq`, `custom_fields` all currently `null` (incl. Priority)
- `get_card` is the only source of `custom_fields` as `[{id, value}]`
  (wekan-mcp skill `references/call-shapes.md` row `get_card`);
  `list_cards_in_list` strips them; **`preload_board` per-card dict is EXACTLY
  `{id, card_number, label_ids, slug, archived, sort, parent_id}`** — i.e. it
  carries the parsed `slug` and NOTHING else, so a Priority value is NOT in
  the claim-time preload payload; the claimed card's single `get_card` read
  (boards skill, preload-consumer paragraph) is where it would be read.

**Repo files that pin the current field roster / routing** (sources in
`.rulesync/skills/`, generated into `.opencode/skills/` — edit sources, then
`rulesync generate`; never hand-edit generated surfaces):
- `.rulesync/skills/boards/SKILL.md:32` — "Custom fields: **exactly ONE
  board-level text field — `slug`** … There is no `models` custom field (D12)
  — model routing rides the Model(s) checklist, never a field. Nor a
  `pipeline` field — … (D19)…" — this sentence (and the D12/D19 rulings it
  cites) is the constraint a Priority field breaks; the intake block
  (line ~402: "the CHECKED items, plus the card's `slug` custom-field value …
  and its `cardNumber`") and the slug write-back (lines 350-351) are the
  sibling spots.
- `.rulesync/skills/pipeline-models/SKILL.md` — the routing map a priority
  value would modify (role table + kickoff picker + favorited-models table).
- `.rulesync/skills/pipeline-kickoff/SKILL.md` — live kickoff questions +
  `STATE.json` `kickoff.models`/`local` recording (board cards skip the live
  round; the batched-round consumer is the boards skill).
- wekan-mcp write surface: `set_card_custom_field` is an upsert and "number/
  checkbox coercion is not expressible through this typed schema (raw REST
  via /wekan-api)" (call-shapes row) — writing numeric CFs through MCP is
  verbatim-string; `create_custom_field` shows the `dropdownItems` settings
  shape if the field is ever re-shaped.
- Board structure itself (adding the field) is **human-owned and already done**
  (the user added it); the repo change is agent-context skills only, per the
  card: "will likely just need agent context changes".

**Routing-relevant upstream fact (grounded, not researched)**: the pinned
llama-swap v266 config schema ALREADY carries a priority mechanism —
`routing.scheduler.use: "fifo"` with `routing.scheduler.settings.fifo.priority`
("Per-model priority. Keys are model IDs, values are integers (default 0).
Higher values are serviced first.") plus `routing.router.use: group|matrix`,
and a `selectors` block (virtual model IDs, strategies `warm`/`pin`/
`spillover`) — see `charts/llama-swap/tests/schema/config-schema.v266.json`.
The deployed chart config uses the legacy top-level `matrix` (the schema says
routing/matrix-styles must not be mixed), so adopting `routing` is a config
migration. Whether vLLM itself exposes request-level priority is the research
thread.

## 7. MCP server ids + verified cluster facts

- **`readonly-gpu-kubernetes`** / **`readonly-ai-gpu-kubernetes`** — 13 tools
  each: `events_list, namespaces_list, nodes_log, nodes_stats_summary,
  nodes_top, pods_get, pods_list, pods_list_in_namespace, pods_log, pods_top,
  projects_list, resources_get, resources_list`. No `nvidia*` servers exist;
  both GPU clusters are AMD (`amd.com/gpu`).
- **`readonly-global-wekan`** (13 tools, read-only tier), **`dev-boards`**
  (38 tools, write-capable — this scout used only its read tools:
  `list_boards`, `list_custom_fields`, `get_custom_field`, `get_card`).
- Verified: node capacities/allocatables (§1 table), PVC `llama-swap` Bound
  500Gi on ai-gpu, pod states (§1 live state), AMD device plugin present and
  Running on both clusters, alloy collectors Running on ai-gpu (so
  remote-write + log-push into the central stack is live).
- **No tier grants pod exec** — on-node commands (`rocminfo`, `dmesg`,
  `free -g`, `lspci`) are operator-run; a plan needs on-target verification
  steps phrased as such (the strata runbook at
  `.agents/notes/strata-host-prep-gpu-ai.md` is the in-repo precedent).

## 8. Gotchas

1. **No NVIDIA in the stack.** The "32GB video card" is the gfx1151 8060S
   (shared LPDDR5X, Strix Halo class, 128 GiB node RAM). CUDA-flavored vLLM
   images won't run here; ROCm support for gfx1151 is THE open research
   question. The R9700 (gfx1201) is the other GPU and is occupied by Strata's
   pinned arenas.
2. **Image pinning law**: no hand-bumps. llama-swap is renovate-managed via
   the scoped `unified-vulkan-<N>` packageRule (`renovate.json:285-292`);
   strata's image is manual-ledger with ZERO renovate directives (C01
   contract); a brand-new in-repo container starts `:main` + `pullPolicy:
   Always` until its first `:v<run>` (strata's PIN-ME pattern).
3. **Chart versions auto-bump** (chart-releaser on merge); a new chart starts
   `1.0.0` only. Service name == chart name; releases render
   `<category>-<appName>` (`gpu-ai-llama-swap`).
4. **ArgoCD applies everything** — no `kubectl apply` from the repo; no agent
   pod-exec tier either.
5. **Config-schema test gate**: rendered llama-swap config must validate
   against the pinned v266 schema (plus the documented `performance.enable`
   legacy carve). New top-level config keys (`routing`, `selectors`,
   `globalConcurrencyLimit` — all present in the v266 schema) are legal;
   `routing` cannot coexist with the legacy top-level `matrix` style.
6. **RAM coexistence law on the ai-gpu node**: ~125 GiB usable shared by
   strata's page-locked arenas (116 Gi cgroup), the llama.cpp trio's warm RAM,
   and the OS (~7.3 GiB floor measured). Any vLLM pod on this node competes
   for the same RAM (the 8060S "VRAM" is system RAM); sizing must be done
   inside that budget, and llama-swap "cannot evict across instances" (peers
   doc, cited in `services/gpu-ai/prod/values.yaml:484`).
7. **Device access pattern**: the amd-gpu plugin can't name the two chips
   (count-only `amd.com/gpu: 2`); chip targeting today is via
   `rocrVisibleDevices`-class env (strata) or privileged `/dev/kfd`+`/dev/dri`
   hostPaths (the accepted deviation, `values.yaml:1313-1323`; documented
   fallback = `amd.com/gpu` + IPC_LOCK/SYS_RESOURCE non-privileged once a
   naming-capable plugin exists).
8. **Long-header plumbing**: any public vLLM surface needs the
   `llama-timeouts` ServersTransport pattern (`responseHeaderTimeout: 0`,
   `generic-ingress.yaml:17` injects it per subdomain) AND provider-side
   2 h `headerTimeout`/`chunkTimeout` in `.opencode/opencode.jsonc` if agents
   route to it (deep-prefill 499s are the recorded reason).
9. **Peers semantics** if vLLM rides behind llama-swap: peer `proxy` carries
   NO `/v1` suffix (path appends verbatim), peer `models:` must list IDs
   explicitly, and peer models are invisible to the outer matrix solver
   (coexistence stays operator discipline).
10. **app-template gotcha**: subchart templates can't see top-level
    `domain`/`clusterName` (appset injects them top-level); domain-dependent
    env belongs in parent-context templates.
11. **helm PATH** (`~/.local/bin`) before any helm/pytest run; pytest runs
    per-directory; no docker daemon (CI-primary builds).
12. **`services/gpu` also runs llama-swap** (8 GiB box, its own tuned roster +
    fail-fast echoes) — chart-wide changes to `charts/llama-swap` affect BOTH
    clusters; the golden/parity suite pins both renders.

## Open questions (for coord → research/plan)

- [R1 — Needs research: yes] vLLM for `qwen3.8-27b` on the 32 GB gfx1151
  (8060S) ROCm card: vLLM ROCm support status for RDNA 3.5/gfx1151, which
  27B quant fits 32 GB (BF16 ≈ 54 GB won't), KV-cache budget at 100-256k ctx
  × 3-4 parallel sessions, expected tok/s vs today's ~50.
- [R2 — Needs research: yes] vLLM for the flash model (the 180B-class
  `qwen3.8-flash-next` family — weights alone ~104 GB at Q4) on the same card
  vs Strata's ~50 tok/s: feasibility at all, MoE-offload paths, the 50+
  tok/s go/no-go the user set.
- [R3 — Needs research: yes] vLLM UI: what ships with vLLM, community UIs, and
  the "reuse llama-swap as the FE" option (llama-swap has a built-in `/ui`
  incl. an Activity page keyed on `X-Session-ID`/`X-Litellm-Session-Id`
  headers — `ui.activity.session_id` in the v266 schema — and `peers` can
  proxy any OpenAI-compatible provider, which is the shape of that reuse).
- [R4 — Needs research: yes, repo side grounded] vLLM priority settings:
  grounded facts in §6 (llama-swap v266 `routing`/fifo per-model priority +
  `selectors`; card CF live and readable via `get_card`; `preload_board`
  does NOT carry it; the D12 "no custom field for routing" roster line in the
  boards skill is what a Priority change amends). What vLLM itself supports
  (preemption, per-request priority) is the research half.
- [R5 — Needs research: yes] vLLM monitoring: its `/metrics` surface (KV
  usage, per-request latency, queueing) and how to scrape it here (PodMonitor
  pattern, §3); note there is NO GPU exporter in the stack and kepler is
  disabled — GPU-side (VRAM/occupancy on ROCm) observability is a gap.
- [OQ1 — plan-owned] Deployment shape: second controller of the existing
  llama-swap Application (the strata consolidation pattern, same Application,
  seven-flag enable) vs a standalone `charts/vllm` + its own service trio on
  gpu-ai. The strata pattern is the in-repo precedent for a co-located
  inference engine; a standalone chart is cleaner for a separately-served
  engine.
- [OQ2 — plan/operator-owned] Which physical GPU the vLLM pod targets (8060S
  vs R9700) — the device plugin can't name chips; depends on R1/R2 findings
  and on Strata's arena residency (they time-share the R9700 via ttl 3600).
- [OQ3 — plan-owned] Public host or cluster-internal-only (the strata Q4
  ruling precedent is internal-only, reached via the llama-swap peers hop;
  a public `vllm.<domain>` would add the proxy-local + SSO leg).
- [OQ4 — plan-owned] Priority semantics mapping (card `Priority` number →
  what: model-tier choice at kickoff, llama-swap fifo priority per model,
  vLLM scheduling) — the card says "identify what needs to change", which
  §6 does for the agent-context side; the design choice is the plan's.
