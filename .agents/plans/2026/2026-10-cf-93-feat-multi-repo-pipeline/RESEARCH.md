# RESEARCH — cf-93 feat: Add repos — context and label support filtering (Pre-Planning round)

Written 2026-10-31 by the pre-planning `agent-research` round for card #93
("Add repos: context and label support filtering."). Card answers consumed as
given: Services dev + home-assistant + agent context; Type feat; Models Qwen
Flash; legacy Research checklist Before+After Planning; HITL Plan+PR.
Method: STORM-adapted — the four launch scopes (A–D) were each investigated
from its governing stakeholder lens (repo-law/GitOps keeper, board-flow
architect, maintenance-risk analyst, tool-surface auditor), every claim below
grounded in a live probe or a retrieved source (numbered, §Sources). No
5-persona interview fan-out was run: the scopes were pre-enumerated by the
launch, so retrieval-and-verify was the proportionate form of the method.
Deep-dive artifacts: the raw probes are reproducible from this file's claims
(MCP reads) and the citation list; no `storm-runs/` dir was scaffolded.

## TL;DR

1. `Repo:` is a **pickup filter, not a lock**: locks already live per-repo
   (each canonical root's own `.pipeline/locks/`), and the plugin ignores any
   non-`Pipeline:` label by construction — so the filter touches the boards
   skill, the pickup walk, and the hourly gate's board operand only.
2. Two gate surfaces **break as soon as a second repo runs the loop**: the
   hourly BOARD CHECK stops on any card in Executing (another repo's live run
   would block every hour), and the session gate counts all coord sessions on
   one OpenCode server regardless of project directory.
3. All three target repos have only the 5 standalone agents + shared
   aurora-smart-home skills and **zero pipeline machinery** — full rulesync
   port per the agents-sync "Syncing into another repo" reference, plus the
   card's own "leave work UNCOMMITTED on their main branches" overrides the
   repos' own commit/branch hard rules.
4. HA-in-K8s: community charts exist and pajikos/home-assistant-helm-chart is
   the healthiest (per-HA-release automation, v0.3.89 = HA 2026.10.4), but
   repo law ("all charts built on the bjw-s app-template library") and the
   in-repo `charts/home-assistant` with its `# TODO: add home-assistant
   container` point to **filling in that chart on app-template 5.x**;
   Bitnami's mosquitto chart is **gone from bitnami/charts (404)** post the
   2025 public-catalog shutdown — build the MQTT pod on app-template with the
   upstream `eclipse-mosquitto` image like `charts/zigbee2mqtt` does [4][5][6][12].
5. The dev cluster is nearly empty (5 namespaces, 18 d, everything in
   `default`, k3s single-node, local-path SC): the two pods land in
   `default` via the existing `dev-appset`/`dev-charts-appset` wiring, no
   MQTT or HA exists there yet [D-probe].

## A. Repo: label filter — ground truth and touchpoints

### A1. How `Pipeline:` works today (the pattern to copy)

- The boards skill (`/.rulesync/skills/boards/SKILL.md`, generated to
  `.opencode/skills/boards/`) owns the posture: labels are human-created in
  the WeKan UI, never agent-created or agent-mutated; a `Pipeline:<name>`
  label's TRIMMED remainder is one lock name, case-sensitive prefix match,
  one card may carry several, no such label ⇒ the single `default` pipeline
  (D17/D19) [1].
- Derivation is agent-side: `get_card` → `label_ids`, resolved through
  `get_board`'s label list (the by-list projection strips labels) — then
  passed to `pipeline_claim(cardId, pipelines)`; the plugin NEVER reads the
  board (`pipeline-locks/index.ts` header, `derivePipelineSet()` lines 186–196)
  [2].
- The claim is all-or-nothing over the derived set (O_EXCL files sorted,
  rollback on first contention) and the claim comment records the derived
  set so a typo'd label drifting to `default` stays visible [1][2].

### A2. Locks are already per-repo — `Repo:` is not a lock

- `resolveLockRoot` anchors the lock dir at the repo's **canonical root**
  (ctx.location.project.canonical → `.pipeline/locks/<key>.json`) [2]. Two
  different repos therefore keep two different lock directories; SpencersLab
  and HomeAssistant workers can lock `default` simultaneously without
  interacting. `Repo:` contributes nothing to the lock set and should not:
  cross-repo exclusion is impossible-by-filesystem already, and same-repo
  serialization is already the `Pipeline:` label's job.
- `sanitizePipelineKey` folds everything outside `[A-Za-z0-9._-]` to `-`, so
  even if a `Repo: …` name ever leaked into a claim it names a clean file —
  but by construction `derivePipelineSet` filters on the exact `Pipeline:`
  prefix only, so a `Repo:` label is invisible to the lock surface [2].
- Naming caution the plan must decide: the live board ALREADY carries
  `Pipeline: Home Assistant`, `Pipeline: Local`, `Pipeline: CICD`,
  `Pipeline: Context` (live `get_board` probe today) and card #93 itself is
  labelled `Pipeline: Home Assistant`, card #74 `Pipeline: Context` [3].
  The owner is using Pipeline: names as quasi-repo/area tracks; introducing
  `Repo:` either migrates those labels or defines coexistence rules (cards
  could carry both a track lock and a repo filter). OQ-A1.

### A3. What a `Repo:` filter touches

1. **boards skill** — new label posture paragraph (mirror `Pipeline:`'s
   human-owned/agent-read-only wording); pickup walk step gains a filter
   between `get_card` confirm and the lock-availability check: take a
   candidate only when its labels include `Repo:<this repo>` or no `Repo:`
   label at all AND this repo is the designated default picker (the card's
   rule: "the current repo's task handles `Repo: SpencersLab` and the
   no-label default" — generalized that way it becomes a per-repo rule, see
   A4). Also: the no-op marker reason set (`no-cards` | `no-claimable-cards`)
   — repo-mismatch skips are "no-claimable-cards" shaped; whether they should
   get a third reason is a plan call [1][2].
2. **Worker repo identity** — nothing today names which repo a board-coord
   run belongs to. Options found: (a) a `repo` constant in each repo's rules
   (AGENTS.md / a repo-side skill note; AGENTS.md loads into every session
   automatically — cheapest, no machinery change); (b) a `repo` key in
   `.pipeline/config.json` — the D8 config loader exists, but `.pipeline/` is
   plugin-owned and "agents never read it", so exposing it means widening
   `pipeline_status`; (c) basename of the canonical root (`resolveLockRoot`
   already proves it's resolvable) — no config drift but couples the identity
   to the checkout dir name (`SpencersLab`, `HomeAssistant`,
   `Home-Assistant-Label-based-Features`, `brother-ptouch-automation`) which
   is exactly the label-remainder form anyway. Plan must pick one; (a)+(c)
   cross-check is the safest shape. OQ-A2.
3. **Hourly gate surfaces** — `/pipeline-boards-hourly` (`.rulesync/commands/`)
   + `scripts/agent-board-coord-gate.sh` + `.agents/loops/pipeline-worker.md`:
   - **BOARD CHECK is broken for multi-repo**: "Executing ≥1 card → stop"
     presumes one worker repo. With N repos each moving its card into
     Executing, every other repo's hourly launch would short-stop. It must
     count only cards whose `Repo:` matches this run's repo (and the
     no-label card counts for the default picker only). The gate script itself
     never touches the board (the board operand is the agent's read-only
     turn), so this fix lives in the command text + boards skill. Verified
     in the command body [8].
   - **Session gate counts across projects**: the script deliberately rejects
     the directory/project scope so "a manual or worktree launch must stay
     visible to the main-checkout hourly run" — on ONE OpenCode server shared
     by several projects (this Coder workspace holds all three target repos
     as siblings under `/home/coder`), a live HomeAssistant coord makes
     SpencersLab's gate answer LIVE. Whether each repo gets its own OpenChamber/
     server instance or shares one is the deployment question; if shared, the
     gate needs a repo/directory predicate. OQ-A3.
   - Each target repo needs its own copy of loop file + `/pipeline*` commands
     + gate script (none has any — B below); the OpenChamber scheduled-task
     sync is per-project and human-owned per the cf-76 ruling.
4. **Lock naming interaction** — none by design (A2). The claim input stays
   "derived Pipeline: set"; a `Repo:`-only card claims `default`, same as today.
5. **Reaper/alert legs** — card moves (Timeout), HA alerts, lock records are
   card/pipeline-scoped, not repo-scoped; multiple repos reaping into one
   board can double-alert a card whose repo filter mis-matches — low risk,
   worth one plan sentence.

### A4. cf-87 friction and the label-tool card #74 — refined state

- The friction as recorded (card #74's own description, "ordered at card
  #87's batched round"): "wekan-mcp exposes no label read/apply surface, so
  agent label work must round-trip board automation rules or raw REST";
  cf-87's research note: "the boards vocabulary … is not machine-readable"
  — and a label tool "would make pickup filtering (Pipeline:* derivation)
  verifiable tool-side instead of comment-side" [7].
- **Refined by today's live probes** [3][14]: label READ is machine-readable
  today — `get_board` returns label definitions (name→id) and `get_card`
  returns `label_ids` (only the by-list projection strips both). What is
  still missing: (i) card-label ASSIGNMENT (no add/remove-label-to-card
  tool anywhere — wekan-api skill: "label-assignment workaround" via rules
  engine / REST `labelIds`) [9]; (ii) a `list_labels` convenience; (iii) the
  deployed dev-boards image still lags: live `tools/list` = 26 tools with no
  label tool, while this branch (cf-89 v102 IS an ancestor) defines
  `create_label` in `containers/wekan-mcp/wekan_mcp/server.py:1054` (31-tool
  parity commit cfb62f1b2) — the image swap to the v103/v102 build is
  human-owned deploy work [10].
- Consequence: a **pickup filter needs only reads, so `Repo:` is NOT blocked
  on #74**. What #74 unblocks is tool-side *verification* (asserting derived
  sets, later stage-label automation) and any agent-side label *writing*,
  which the human-owned posture excludes anyway. The Repo: labels themselves
  are created in the WeKan UI by the owner exactly like `Pipeline:` labels.

### A5. "Provider labels" — the card's analogy has no referent

The live board has no `Provider:` labels (full label set in [3]); "Provider"
exists only as the model-routing column in `pipeline-models` (gpu-ai vs
openrouter) and the Model(s) checklist. Either the owner means the Model(s)
checklist routing (most likely) or plans a Provider: label concept. OQ-A4 —
batched round.

## B. Target-repo inventory (read-only disk survey, 2026-10-31)

**Note: the card's first path is mis-cased.** `/home/coder/Home-Assistant-
Label-Based-Features/` does not exist; the real directory is
`/home/coder/Home-Assistant-Label-based-Features` (lowercase "based") [11].
Repo: label values must pin the exact names — the plan should propose the
label spelling set and flag the rename to the owner.

| | Home-Assistant-Label-based-Features | HomeAssistant | brother-ptouch-automation |
|---|---|---|---|
| What it is | HA **custom-component** repo: `custom_components/labeled_features` + hacs.json, tests (pytest.ini, ruff), README system docs | full **HA configuration dir**: configuration.yaml, packages/ (incl. `package_labeled_features_*`), automations/scripts/scenes yaml, blueprints, dashboards, dwains-dashboard, esphome, themes | Python **label-printer service**: `src/label_printer` (Brother PT-P750W/P710BT/E550W raster engine), `tests/` (18 pytest files), `containers/brother-ptouch-automation` (built in this lab — SpencersLab containers/ + services/home `brother-ptouch-automation` entry exist), docs/, research/ |
| GitHub origin | CuratedForest/Home-Assistant-Label-based-Features | TheHackmeister/HomeAssistant | CuratedForest/brother-ptouch-automation |
| agents | 5 standalone only: ask, code, debug, plan, review (`.agents/agents/`) | same 5 | same 5 (code.md, plan.md currently dirty-modified) |
| pipeline machinery | none — no `.rulesync/`, no pipeline agents/commands/skills, no plugins, no `.pipeline/`, no loops | none | none |
| self-written skills | `skills/labeled-features` (label grammar, component↔YAML parity law) | `skills/wekan-home-assistant` | `skills/label-printer` |
| third-party skills (`.agents/skills/`, locked in root `skills-lock.json`) | 9: agent-rules, api-catalog, aurora, esphome, ha-dashboard-design, ha-integration-dev, home-assistant-best-practices, home-assistant-yaml, node-red | same 9 | 7 (no agent-rules, no home-assistant-best-practices) |
| skill source | tonylofgren/aurora-smart-home (GitHub, hash-locked; the three locks drift slightly — e.g. ESPHome hash differs in HomeAssistant's lock) | | |
| working state | main ahead 1, dirty; worktrees dir exists | main ahead 1, dirty (cost-title plugin `/.opencode/plugin/cost-title.ts` + extensions/group-costs) | main clean-tracking, 2 files dirty |

Adaptation implications:

- The pipeline stack to port per repo: `.rulesync/` sources (subagents,
  commands, skills incl. `pipeline-*` contract set + `boards`), generated
  `.opencode/agents|commands|skills` + AGENTS.md rule sources, `.agents/plans/templates/`,
  the four hand-written plugins (pipeline-locks, question-notify,
  board-context, aislop-gate — the last is optional per repo), the gate
  script + loop, and the repo-side grounding (Services list differs per
  repo — the boards skill's 13-folder Services checklist is
  SpencersLab-specific and needs a per-repo variant or a generalized
  "work targets" answer set). The agents-sync skill's
  `references/syncing-to-other-repos.md` is the porting runbook [13].
- The card's "at least 3 new `agent-ha-(dev|code|debug)` agents" maps
  naturally onto the existing role/dev family with an HA overlay marker —
  agents-sync's overlay-name law ("lead with the overlay marker"; exact-match
  subagent permissions) applies [13]. Skills they should pin already exist:
  `ha-integration-dev` (tonylofgren/aurora-smart-home; custom_components,
  DataUpdateCoordinator, config_flow, HACS publishing),
  `home-assistant-best-practices` (homeassistant-ai/skills), the `ha-mcp-*`
  quintet (zorak1103/ha-mcp) — all already vendored + hash-locked in
  SpencersLab's own `skills-lock.json` today [12].
- Custom-agent highlights the card asked for: a **custom_component
  integration agent** is well-founded — the LBF repo is exactly that domain
  and the `ha-integration-dev` skill is a complete contract base; the LBF
  skill adds the docs-vs-YAML parity law any HA dev agent in these repos
  must obey. Also sensible per repo: an HA-config agent for HomeAssistant
  (packages/automations authoring — home-assistant-best-practices pins it),
  and a Python/service agent for brother-ptouch-automation (it has a REAL
  pytest suite — pipeline "Commands/tests" there mean `uv run pytest` /
  ruff, not helm renders; per-repo test-law text needed in its AGENTS.md).
- Hard-rule conflicts the plan must resolve: all three repos' AGENTS.md carry
  the same never-merge/push-to-main law and expect worktrees + local commits,
  while the card says **"Leave all work uncommitted in the main branch on
  those repos"** — that overrides the pipeline's per-chunk commit discipline
  (coord commits each chunk) and worktree/branch minting for those repos.
  The adaptation needs a per-repo "working mode" ruling (no worktree,
  dirty-main edits) — this changes kickoff, gates, and dev-role text.
  OQ-B1.

## C. HA-in-K8s chart landscape (web research, 2026-10-31)

- **Community HA Helm charts exist and are current**:
  - `pajikos/home-assistant-helm-chart` (Artifact Hub repo `helm-hass`) —
    v0.3.89/appVersion 2026.10.4 released 2026-10-24; per-HA-release
    auto-update CI; NOT archived (348★, 645 commits, pushed today);
    StatefulSet-or-Deployment controller, PVC persistence, ingress +
    Gateway-API HTTPRoute, trusted-proxies handling incl. the HA 2026.8+
    `.storage/http` migration, code-server addon, hostNetwork note for HA
    auto-discovery. Default image `ghcr.io/home-assistant/home-assistant`
    [4]. **This is the live successor of the ecosystem the card remembered
    as `nullin/home-assistant-helm-chart` — that repo is now a 404** (live
    probe; no redirect) [5].
  - `k8s-home-lab/k8s-home-lab-repo` `home-assistant` 16.3.1
    (appVersion 2026.3.1, last release 2026-04-24) — the k8s-at-home-lineage
    fork, slower cadence [6].
- **Against repo law**: AGENTS.md hard rule — "Helm charts (`charts/`), **all
  built on the bjw-s app-template library**"; external charts exist here only
  as wrapper precedents (erp-next wraps frappe). The in-repo
  `charts/home-assistant` ALREADY is the chosen shape: an app-template-style
  values block (`app-template:` …) whose container is stubbed with
  `# TODO: add home-assistant container.` — the chart today delivers the HA
  CNPG database, PVC and secrets on the grow cluster only [12]. The clean
  landing: fill in that TODO with the HA container (app-template 5.0.1, the
  version this repo already pins in charts/zigbee2mqtt) for the dev cluster
  entry, keeping the pajikos chart as the documented community fallback.
  For a *dev, initially empty* instance none of pajikos' extras (addons,
  ServiceMonitor, configuration templates) are required — app-template gives
  the repo-convention shape, and its chart version law (`version: 1.0.0` only
  for brand-new charts; release.yaml bumps) stays intact because
  charts/home-assistant already exists.
- **MQTT**: the bitnami path is DEAD — `bitnami/mosquitto` returns 404 in
  bitnami/charts today (live GitHub API probe; the repo itself is still
  active, pushed 2026-10-29) and Artifact Hub no longer lists a bitnami
  mosquitto package (empty API answer) [5][6]; Broadcom's public
  docker.io/bitnami catalog shutdown (Aug–Sep 2025, deletion deadline
  postponed to 2025-09-29 with brownouts before cutover) is the documented
  cause [15]. Remaining community options: MJD Systems' `mosquitto` chart
  0.1.0 (Eclipse 2.0.15, OCI `registry.mjdsystems.ca/charts/mosquitto`) —
  single-instance StatefulSet, old app version; SINTEF/mosquitto-helm-chart;
  HelmForge docs page. None matches this repo's conventions; **the app-template
  route on the upstream `eclipse-mosquitto` image is the repo-consistent
  answer** (chart precedent in-repo: zigbee2mqtt on app-template 5.0.1 with
  the koenkk image). Config shape: mosquitto needs a config + optional ACL/
  password file — a configmap/env from the bjw-s pattern, secrets via
  ExternalSecret+Bitwarden placeholder per repo law. Note also the lab's
  `containers/traefik-mqtt-allowlist` middleware exists for the home-cluster
  broker's exposure story — dev-cluster exposure (tcp 1883 via Traefik or the
  gateway-api tcproutes already enabled in services/dev values) is a plan
  decision; an empty dev HA does not need external MQTT reachability on day
  one [12][16].
- HA image reference: live production HA is 2026.10.4 (readonly ha-mcp probe),
  identical to the pajikos appVersion — pins "what current means" for the
  dev instance tag choice (`:stable` vs pinned `2026.10.4` — repo law prefers
  renovate-annotated pins) [14].

## D. Dev-cluster grounding (readonly-dev-kubernetes, 2026-10-31)

- Topology: single-node **k3s** (node `dev`, amd64, control-plane), Traefik
  in kube-system, **18 days old**, namespaces: default, kube-system,
  kube-node-lease, kube-public, system-upgrade only [17].
- Storage: one SC — `local-path` (rancher.io/local-path, default, RWO,
  WaitForFirstConsumer, ReclaimPolicy **Delete**) → HA `/config` persistence
  is a deliberate decision (empty instance tolerates it; the card says empty
  is fine, backup is a separate card) [17].
- Everything runs in namespace `default`, GitOps-applied by Argo CD v3.5.6
  (argo-cd-10.11.1 chart, `dev` instance) via two ApplicationSets: `dev-appset`
  and `dev-charts-appset` — the same pattern as every other cluster; existing
  workloads: argocd, coder, forgejo (+runner, runner currently
  CrashLoopBackOff — pre-existing, not our chunk), cert-manager, cloudnative-pg
  (+pg-coder, pg-forgejo clusters), external-secrets-bitwarden, bitwarden-cli,
  searxng, gpt-researcher, k8s-monitoring (alloy), reloader, toolhive-operator
  + mcp-{boards,kubernetes-readonly,kubernetes-admin,playwright,renovate,
  searxng} [17].
- **No MQTT broker and no HA anywhere in the cluster today** — the two pods
  are greenfield. Landing shape per repo law: entries under `charts:` in
  `services/dev/prod/values.yaml` (home-assistant + mosquitto), values blocks
  in the same file, the chart entry in `charts/home-assistant` (fill the
  container TODO) + a small new `charts/mosquitto` (app-template, brand-new
  ⇒ `version: 1.0.0` per the version law) — plus proxy/ingress entries: the
  dev ingress subdomain pattern (`services/dev/prod/values.yaml`
  `ingress.subdomains`) covers HA over HTTP (8123 container port);
  `mcp.dev.scifi.farm`-style host naming applies. The Service trio
  (chart entry + ApplicationSet values entry + proxy values entry) is the
  repo's own validation grep [12][17].
- Deployed wekan-mcp note (affects nothing in the pods but affects A4):
  `mcp-boards` runs the 26-tool image; the branch's source is v102+ with
  `create_label` — the image bump is human-owned deploy work [10].

## Contradictions & how to weigh them

- Card text says "research whether existing charts exist; if not use the
  app-template pattern." Existing charts DO exist and are healthy [4], which
  read literally permits adopting pajikos' chart. But AGENTS.md is unambiguous
  ("Helm charts, all built on the bjw-s app-template library") and the repo
  already holds a purpose-built `charts/home-assistant` awaiting exactly this
  container [12]. Weigh: repo law + in-repo chart win for the dev pod;
  pajikos stays cited as the alternative (and its README is the best
  operational reference for HA-in-k8s gotchas: 2026.8 http-settings
  migration, hostNetwork discovery, `/config` ownership) — surface as a
  plan question only if the owner wants the community chart.
- "Machine-readable labels" (cf-87) vs today's probes: READ works now [3],
  ASSIGN and deploy-side verification still don't [9][10]. The friction
  note overstated the read gap; the card #74 scope (read+apply tools) is
  still half-valid — its "list board labels / get card label_ids" items are
  already satisfied by get_board/get_card, leaving apply-by-name as the real
  ask. This RESEARCH's reading beats the older friction phrasing (both
  cited); plan should not re-scope #74 based on stale wording.
- The three repos' own AGENTS.md commit/worktree discipline vs the card's
  "leave work UNCOMMITTED on their main branches": the card is the owner's
  live instruction and wins for THIS port work, but the per-repo pipeline
  agents need an explicit adapted working-mode rule text or every chunk gate
  (commit-per-chunk, PR flow) will fight it. OQ-B1.

## Implications for the plan (what the planner should decide differently)

1. Scope the Repo: work as: boards-skill source edit (pickup filter +
   human-owned Repo: posture + default-picker rule) + per-repo identity
   constant + repo-aware BOARD CHECK in the hourly command + gate-script
   scoping decision + `.rulesync/commands`/loop porting per repo. No
   pipeline-locks plugin change needed (A2) — keep that in Scope explicitly
   to stop a dev inventing one.
2. Decide OQ-A1 (existing `Pipeline:` tracks vs new `Repo:` values) with the
   owner before writing the filter's matching table; propose `Repo:` values
   = exact dir names, with SpencersLab as default picker.
3. Two chart chunks: (a) `charts/home-assistant` container fill-in + dev
   values wiring; (b) new `charts/mosquitto` on app-template 5.0.1 + dev
   wiring — both validated by `helm lint`/`helm template` + trio greps
   (this repo's "test" shape), no docker builds. Post-pod HA setup/backup:
   out of scope per card (separate card).
4. The agents/skills port is the biggest chunk set: rulesync sources +
   generated surfaces + templates + plugins + gate/loop per repo, pinned
   skills carried via each repo's skills-lock (already hash-locked to the
   same sources), and new agent files: the plain pipeline roles plus an
   `agent-ha-dev`/`agent-ha-code`/`agent-ha-debug` overlay trio (name it per
   the overlay-marker law) and a highlighted custom_component candidate
   (ha-integration-dev base) + HA-config and python-service variants.
5. Uncommitted-main working mode (OQ-B1) gates every target-repo chunk's
   dev/coord contract — resolve in the batched round BEFORE chunk writing.

## Open questions (for the batched plan round)

- OQ-A1: Migrate the existing `Pipeline: Home Assistant/Local/CICD/Context`
  labels to `Repo:` semantics, or coexist? Best guess: coexist — `Pipeline:`
  keeps the lock meaning, `Repo:` is new and pickup-only; the owner's track
  labels stay.
- OQ-A2: Repo-identity source: per-repo rules constant, canonical-root
  basename, or config key? Best guess: canonical-root basename validated
  against a per-repo AGENTS.md constant (no plugin change).
- OQ-A3: Do the repos run separate OpenChamber/server instances (per-repo
  gates) or share one (gate script needs a directory predicate)? Best guess:
  shared workspace now → gate gains a per-project scope row for board-coord
  sessions only when a launch names a repo; hourly BOARD CHECK becomes
  repo-filtered regardless.
- OQ-A4: The card's "Provider" label analogy — Model(s) checklist routing or
  a planned `Provider:` label? Best guess: checklist routing; no Provider:
  label exists on the board today.
- OQ-B1: Uncommitted-main mode per target repo: adopt the dirty-main working
  mode for ALL future pipeline runs in those repos, or only for this port?
  Best guess: for this port work; target repos get full commit discipline
  after their pipeline landing is itself merged.
- OQ-B2: Repo: label spellings — `Repo: SpencersLab`, `Repo: HomeAssistant`,
  `Repo: Home-Assistant-Label-based-Features`,
  `Repo: brother-ptouch-automation`? (Card path mis-cased "Label-Based").
- OQ-C1: HA dev pod: fill-in `charts/home-assistant` on app-template (repo
  law, empty config) vs the maintained pajikos chart (richer, off-law)? Best
  guess: app-template fill-in.
- OQ-C2: Mosquitto exposure on dev (in-cluster ClusterIP only first; Traefik
  1883 / tcproutes later)? Best guess: ClusterIP-only initially.
- OQ-C3: HA `/config` persistence on local-path with ReclaimPolicy Delete —
  accept (empty instance) or provision differently? Best guess: accept.
- OQ-D1: Which Services-checklist answer set replaces the SpencersLab
  13-folder list in the ported repos' cards? Best guess: per-repo Services
  lists defined in each repo's boards-skill adaptation.

## Adjacent (short, not core)

- The hourly loop/gate landing on target repos depends on OpenChamber's
  per-project scheduled-task sync — same mechanism verified live for
  SpencersLab on 2026-10-29 (`pipeline-worker` task); scheduler hygiene stays
  human-owned per the OQ10 ruling carried in `.agents/loops/pipeline-worker.md`
  comment block [8][16].
- Pre-existing dev-cluster condition noticed during D: `dev-forgejo-runner-dev-0`
  is CrashLoopBackOff. Unrelated to card #93; noted so the plan's cluster
  validations don't blame it.

## Sources

Retrieved/probed 2026-10-31 unless dated otherwise. [n] keys cited above.

1. `/.rulesync/skills/boards/SKILL.md` (repo source; generated twin
   `.opencode/skills/boards/SKILL.md`) — label posture, pickup walk, Parallel
   pipeline loops D17, no-op marker, card lifecycle. Read in-session.
2. `/.opencode/plugin/pipeline-locks/index.ts` — LABEL_PREFIX (53),
   derivePipelineSet (186–196), sanitizePipelineKey (176), resolveLockRoot
   (286–308), claim/release/status/heartbeat/reap engine. Read in-session
   (lines 1–1165+).
3. Live `dev-boards` MCP probes (this session): `list_boards` → AI-Dev
   `TNQJ2BrXenZovngTS`; `get_board` labels = Research, Ready for Work,
   `Pipeline: Local`, `Pipeline: CICD`, `Pipeline: Context`, Bucket Color,
   `Pipeline: Home Assistant`; `list_swimlanes` = In Process, Backlog, Farm,
   Planning; card #93 (`mxnEsiC2SwtLKZE9i`, label_ids=[`urP8pR`]) and card #74
   (`MS8e8uoF27R2dk73e`, label_ids=[`G7mzkC`]); `tools/list`-equivalent
   catalog = 26 dev-boards tools, no label tool.
4. https://github.com/pajikos/home-assistant-helm-chart (README, fetched
   2026-10-31) — chart features, controller/persistence/HTTPRoute/2026.8
   notes; GitHub API: latest release `home-assistant-0.3.89`
   (2026-10-24T21:20:50Z), pushed 2026-10-31, not archived, 348★/87 forks.
5. https://github.com/nullin/home-assistant-helm-chart — HTTP 404 (live probe
   2026-10-31); https://github.com/bitnami/charts contents `bitnami/mosquitto`
   — 404 "Not Found" (live API probe 2026-10-31), repo itself active
   (pushed_at 2026-10-29).
6. Artifact Hub API reads (live 2026-10-31): `packages/helm/helm-hass/
   home-assistant` v0.3.89/app 2026.10.4 not-deprecated;
   `packages/helm/k8s-home-lab-repo/home-assistant` v16.3.1/app 2026.3.1
   (ts 2026-04-24); `packages/helm/mosquitto/mosquitto` v0.1.0/app 2.0.15
   (OCI registry.mjdsystems.ca); `packages/helm/bitnami/mosquitto` → empty
   (removed).
7. WeKan card #74 (number 74, "wekan-mcp: add a label tool to drop the
   rules-engine round-trip", Not Started) — description quotes card #87's
   batched round Q6 ruling and cf-87's research friction note (live get_card
   read, this session).
8. `/.rulesync/commands/pipeline-boards-hourly.md` + `/scripts/agent-board-coord-
   gate.sh` header/verdicts + `/.agents/loops/pipeline-worker.md` — gate shape,
   BOARD CHECK rule ("≥1 card → stop"), D11 no-directory-scope, loop cron body.
   Read in-session.
9. `/skills/wekan-mcp/SKILL.md` (failure-mode table incl. "deployed build lags
   the repo source"; board-context block schema) +
   `/skills/wekan-api/SKILL.md` ("card label assignment (no label tool;
   rules-engine round-trip)") + `/skills/wekan-api/references/rest-api-overview.md`
   (PUT /api/boards/:id/labels semantics, 25 colors, idempotency (name,color)) +
   `/skills/wekan-mcp/references/call-shapes.md` (create_label row,
   "source-only (v12.65 source-check 2026-10-30; live tools/list probe
   post-merge, user-owned)"). Read in-session.
10. `/home/coder/SpencersLab` main checkout: `containers/wekan-mcp/wekan_mcp/
    server.py:1054 def create_label(...)`; git log `cfb62f1b2 cf-89 C01:
    wekan-mcp v102 … (create_label/list_board_members) + 31-count parity`.
    Verified `cfb62f1b2` is an ancestor of this worktree's HEAD (live probes).
11. Live filesystem reads (2026-10-31): `/home/coder/` listing;
    `/home/coder/Home-Assistant-Label-based-Features` (+ `-Label-Based-…`
    404); each repo's `ls -a`, `.agents/agents`, `skills/`,
    `.agents/skills`, `skills-lock.json` (aurora-smart-home sources + hashes),
    `AGENTS.md`, git status/log/remote (CuratedForest/*, TheHackmeister/*),
    `HomeAssistant/.opencode/plugin/cost-title.ts`,
    `brother-ptouch-automation/tests/` (18 files).
12. This repo: `/AGENTS.md` (chart law, version law, secrets, service trio);
    `/charts/home-assistant/Chart.yaml` (v1.0.16) + `values.yaml`
    (`app-template:` block, `# TODO: add home-assistant container.`) +
    templates (pg/pvc/secrets only); `/charts/zigbee2mqtt/Chart.yaml`
    (app-template 5.0.1 dep) + values (koenkk image, no in-cluster broker
    env); `/services/grow/prod/values.yaml` (assistant→chart: home-assistant);
    `/services/home/prod/values.yaml` (commented-out mosquitto ingress entry
    lines 153–155, brother-ptouch entries); `/services/dev/prod/values.yaml`
    charts+subdomains blocks; `/skills-lock.json` (ha-integration-dev ←
    tonylofgren/aurora-smart-home, ha-mcp-* ← zorak1103/ha-mcp,
    home-assistant-best-practices ← homeassistant-ai/skills, storm ←
    kunjan-p/storm-skill); `/containers/traefik-mqtt-allowlist/`.
13. `/skill agents-sync` body + `references/syncing-to-other-repos.md` +
    `/skill pipeline-conventions` + `/skill pipeline-role-research` —
    porting runbook, overlay naming law, RESULT schema, RESEARCH.md format.
14. `readonly-global-homeassistant.get_system_info` — live HA 2026.10.4,
    RUNNING, home.spencerslab.com (this session).
15. https://github.com/bitnami/containers/issues/83267 — "Upcoming changes to
    the Bitnami catalog (effective August …)" + deletion postponed to
    September 29 2025, brownouts (searxng result, 2026-10-31); corroborating
    https://www.terasky.com/resources/bitnami-repository-shutdown/.
16. `.agents/plans/2026/2026-10-cf-89-feat-wekan-mcp-board-provisioning/` —
    RESEARCH §3 (label route facts), DECISIONS (Q3 create_label ruling, coord
    live-probe verdict), STATE.json plan_status=complete (read this session).
    `.agents/plans/2026/2026-10-chore-board-tick-cleanup/DECISIONS.md` —
    OpenChamber `pipeline-worker` task sync verification 2026-10-29.
17. `readonly-dev-kubernetes` live probes (this session): Namespaces (5),
    Nodes (single k3s `dev`), StorageClasses (local-path default,
    ReclaimPolicy Delete), Deployments/Pods/Services lists (all `default` ns:
    argocd v3.5.6/argo-cd-10.11.1, coder, forgejo+runner(CrashLoop),
    cert-manager, cloudnative-pg, external-secrets, searxng, gpt-researcher,
    k8s-monitoring, toolhive+mcp-*, mcp-boards), ApplicationSets
    (`dev-appset`, `dev-charts-appset`).

## Reliability notes

- Confidence 9/10 — A/B/D findings are direct reads of this repo's files and
  live MCP/FS/API probes (reproducible in-session).
- Confidence 8/10 — C chart-liveness facts rest on today's GitHub/Artifact
  Hub API reads; the k8s-at-home lineage attribution for k8s-home-lab is from
  its name/version numbering (16.x fork lineage), not an explicit statement —
  verify if the plan ever weighs that chart.
- Weakest claim: "deployed dev-boards lags main" — proven via the live tool
  catalog (26) vs in-branch source (create_label present), but the exact
  deployed image tag wasn't read; the swap being human-owned keeps this
  honest regardless.
- Blind spot none of the four scopes covered: whether WeKan's rules engine can
  *auto-apply* Repo: labels (the import-runbook angle) — deferred, labels are
  human-owned posture anyway.

---

## Round 2 — post-plan grounding (2026-10-31)

After-Planning round. Read: the approved plan (96 l), all 9 chunk files, DECISIONS.md,
FRICTION.md, STATE.json (plan_status approved, all chunks pending, current_wave 1, test
handoff recorded). Scope: the concrete surfaces the chunk loop hits that round 1 left as
design intent — exact text anchors, byte-level chart facts verified by RENDERING, image
shapes verified through the registries, and the port-recipe deltas. Method: live local
renders/probes (helm against a downloaded app-template 5.0.1 in /tmp — the repo's
`charts/**/charts` vendoring is gitignored so NO repo file was written), GitHub/Docker
Hub/GHCR registry APIs, searxng. No repo edits; no questions asked.

### R2.1 C01/C02 — exact edit anchors (verified line-level against the sources)

Boards source `.rulesync/skills/boards/SKILL.md` (anchors for the filter insert):
- L15: the Board-facts label bullet ("Board label **Research** … `Pipeline:` … human-created
  in the WeKan UI and never agent-created or agent-mutated — the same posture as Research
  (D17/D19)") — the `Repo:` posture sentence mirrors this wording and slots into this bullet.
- L18: Services bullet — the 13-folder list C06/C07/C08 re-target per repo (OQ-D1).
- L51 `## Config constants`; L64 `## Card pickup` (steps L66–L79: 1 given-id, 2 walk
  Rework→Not Started→Low Priority, 3 confirm-with-`get_card`, 4 nothing→`no-cards` marker);
  L94 `## Parallel pipeline loops`; L99 derivation bullet (the "Repo: NEVER contributes"
  sentence goes here); L101 claim bullet ("at most 3 claim attempts … `no-claimable-cards`");
  L107 `### No-op marker`. The filter step per C01 sits BETWEEN pickup step 3 and the
  lock-availability sentence that closes the walk description ("On parallel-pipeline runs
  the candidate is additionally filtered by lock-set availability per Parallel pipeline
  loops below", L~82) — that trailing sentence is the join point; the eligibility test
  inserts ahead of it (or step 3 gains a sub-step — same window; `repo-label-filter.sh` t1
  uses anchor+window matching, prose may re-wrap, semantics may not).
- Generated mirror `.opencode/skills/boards/SKILL.md`: diff vs source is FRONTMATTER ONLY
  (description re-folded to a block scalar, `targets:` dropped, one blank line) — body
  byte-equal, so every source anchor greps identically in the generated twin (which is
  what the t1/t2 suites read). Dev edits the source, `rulesync generate` mirrors.
- Hourly command source `.rulesync/commands/pipeline-boards-hourly.md`: L15 `Request` line,
  L22–24 the three GATE verdict bullets, **L26 the BOARD CHECK paragraph** (verbatim:
  "BOARD CHECK (LIVE branch only, read-only dev-boards calls): `list_boards` → the board
  **AI-Dev**; its lists under swimlane **In Process** → the list titled **Executing**;
  `list_cards_in_list` on it → count the cards.") followed by the 4 verdict bullets
  ("Executing empty → continue…", "≥1 card → stop… max 5…", fail-closed, reads allow-list),
  L37 `Notes:` — the OQ-A3 posture bullet joins that list. Generated
  `.opencode/commands/pipeline-boards-commit … pipeline-boards-hourly.md` again differs only
  in frontmatter (`targets`/`opencode.agent` flattened to `agent:`). Manual
  `/pipeline-boards` carries NO BOARD CHECK block today (C02's t3 regression pin confirmed
  green-at-base).
- Gate script `scripts/agent-board-coord-gate.sh`: header comment block L1–28 — the D11
  paragraph C02 extends is L17–21 ("The listing API also accepts a directory/project
  scope — smaller walks, but rejected: … (D11: interactive launches count)"). Variables:
  `THRESHOLD_MIN_DEFAULT=15`, `GRACE_MIN_DEFAULT=5`, `CLI_TIMEOUT=20`, `PAGE_LIMIT=500`,
  `MAX_PAGES=40`; verdict helpers `say_run` (exit 0) / `say_skip` (exit 1) at L104–105, LIVE
  print L255 + `exit 2` L273. **Trap for AC2 (comment-only diff):** a near-identical D11
  sentence also exists INSIDE the `usage()` heredoc ("No directory or project scoping —
  interactive and worktree launches are supposed to count (D11)." ~L92) — heredoc lines are
  not `#`-prefixed, so an edit landing there breaks `hourly-board-check.sh` t2's
  `^+#`-only proof. C02's wording ("header comment") points at L17–21 — correct target;
  dev must not touch the heredoc twin. [R2-probe: local reads + diffs]

### R2.2 C03 — the chart as it stands + the PROVEN gating mechanism

Current chart state (all verified live): `Chart.yaml` apiVersion v2, name home-assistant,
`version: 1.0.16`, `appVersion: 1.0.0`, dependency stub fully commented at 4.3.0.
`values.yaml` keys exactly: `bitwardenIds.{home-assistant-pg,mcp-pg-grow-assistant,
mcp-pg-grow-assistant-sensors}: OVERRIDE_VIA_CUSTOM_VALUES`, `domain: OVERRIDE_VIA_APPSET`,
and `app-template: { global: { nameOverride: "{{ .Release.Name }}" }, # TODO: add
home-assistant container. }`. Templates: 2 CNPG Clusters (pg-home-assistant,
pg-home-assistant-sensors), 4 ExternalSecrets (secret-home-assistant = app pg creds,
secret-pg-home-assistant, 2 mcp secrets), the PVC template fully commented ("# TODO:
Disabled until Home Assistant pod is added", 5Gi RWO). Default render today: 2 Cluster +
4 ExternalSecret — the golden snapshot `tests/multi-repo/snapshots/ha-chart-default.yaml`
matches (agent-test capture at 7e07a6273e; chart still byte-untouched at R2 time).
[charts/home-assistant reads, render]

**Empirically established render mechanics (the plan left these to "decide from the
reference charts" — the suites now pin the contract):**
1. `tests/multi-repo/ha-chart.sh` t2 renders with `--set homeAssistant.enabled=true
   --set postgres.enabled=false` and demands kinds EXACTLY `[Deployment, Service]` — a
   chart-level `homeAssistant.enabled` flag MUST therefore gate the app-template subchart
   itself. The mechanism that satisfies it (proved in /tmp): the dependency entry in
   `Chart.yaml` gains **`condition: homeAssistant.enabled`** — helm dependency condition
   gating. Default render (`homeAssistant.enabled: false` in values) renders the subchart
   NOWHERE → **byte-identical to the snapshot, proven**; `--set homeAssistant.enabled=true`
   activates the whole subchart. (`ha-chart.sh` t5 grow-slice render relies on the same:
   the extracted grow slice carries no `homeAssistant` key → condition false → no
   Deployment — the test's forbidden-kinds list.) [R2 render matrix]
2. **The existing `nameOverride: "{{ .Release.Name }}"` string is a landmine**: inert while
   no dependency is vendored, it becomes a raw non-templated string inside the subchart
   and BREAKS the render outright (`error converting YAML to JSON: invalid map key
   map[interface{}]…{".Release.Name":nil}`). It MUST be removed — app-template 5.0.1
   self-derives release-based naming (`app-template.hardcodedValues` in its common.yaml
   sets `global.nameOverride = .Release.Name` when unset). [R2 render, at 5.0.1 extracted
   templates/common.yaml]
3. **app-template 5.0.1 renders a default ServiceAccount even with zero controllers**
   (`global.createDefaultServiceAccount: true` default, common-library `_init.tpl` +
   `_serviceAccount.tpl`), which would break BOTH AC1 (default render gains a doc) and
   t2's exact-`[Deployment, Service]` kinds. The chart values must carry
   `app-template.global.createDefaultServiceAccount: false`. Verified: with the condition
   gate + the two fixes above, default render = snapshot byte-identical; dev-mode render
   (flip flags) = `ServiceAccount` suppressed, `Deployment`+`Service` (+parent PVC when
   `homeAssistant.persistence.enabled=true`), image
   `ghcr.io/home-assistant/home-assistant:2026.10.4` (GHCR manifest 200 + amd64 platform,
   re-probed), ports 8123, readiness/liveness/startup probes present, drop-ALL +
   allowPrivilegeEscalation:false container sc, `/config` mount via
   `persistence.config.existingClaim: "{{ .Release.Name }}"` + `globalMounts` — the
   qdrant/zigbee repo pattern (`existingClaim` renders NO PVC object — the parent's gated
   PVC template supplies the single PVC t2 counts). [R2 render matrix; qdrant/zigbee values]
4. Probe `type` must be UPPERCASE `TCP` — app-template 5.0.1 ships `values.schema.json`
   and a lowercase `tcp` fails render validation
   (`probes.startup.type … must be one of "TCP","HTTP","HTTPS","GRPC","AUTO"`). [R2 render]
5. Persistence schema: v5 PVC volumes want `size`/`storageClass` per volume, NOT the v4-era
   `accessMode`/`capacity` top keys (schema error `size is required`); with the
   `existingClaim` pattern neither is needed. Devs following zigbee/qdrant land on it.
6. `helm dependency update charts/home-assistant` needs network to
   `bjw-s-labs.github.io/helm-charts` — works from this workspace (downloaded 5.0.1 tgz
   today; zigbee2mqtt's Chart.lock digest `sha256:0ea7893a…` matches the registry's 5.0.1).
   `charts/**/charts` + `services/**/charts` are gitignored (root .gitignore L3–4) while
   `Chart.lock` IS committed — suites render from /tmp copies after `dependency update`,
   skipping loudly when the registry is unreachable. [repo reads, live download]
7. Grow invocation, byte-identical risk points: grow deploys `assistant:` under `charts:`
   with `chart: home-assistant` (`services/grow/prod/values.yaml` L21–26); the release
   VALUES come from top-level `assistant:` (none exists today) merged with
   `custom-values/grow/prod-values.yaml`'s `assistant:` block — which carries ONLY real
   `bitwardenIds` UUIDs (all three keys). So C03's new keys (`postgres.enabled`,
   `homeAssistant.*`, the reworked `app-template:` block) flow to grow as chart defaults;
   no custom-values change needed, and the grow render stays pg+secrets-only. Dev slice in
   C05 flips `homeAssistant.enabled: true`, `postgres.enabled: false`,
   `homeAssistant.persistence.enabled: true` — the single flag names `ha-chart.sh` pins.
   [grow values reads]

### R2.3 C04/C05 — image shape + dev wiring (registry-verified)

eclipse-mosquitto via Docker Hub registry API + official-images (2026-10-31):
- `2.0.22` EXISTS (amd64 manifest `sha256:8bf6e60e…`), but the tag-set reading is
  subtler than the plan's note: the official-images recipe now maps
  `2.0.22, 2.0.22-openssl, 2.0, 2-openssl, openssl` → directory `docker/2.0-openssl`, and
  `latest = 2.1.2-alpine` (`2.1` series is published ONLY with the `-alpine` suffix — no
  bare `2.1.2` tag exists). So "newest numeric tag 2.0.22" means newest of the bare
  release stream; the newest image at all is `2.1.2-alpine`. Pinning `2.0.22` stays
  coherent (bare stream, renovate-annotatable); flag as informational, not a change.
- Image config (registry blob, 2.0.22 amd64): `User: None`, `Cmd:
  ["/usr/sbin/mosquitto","-c","/mosquitto/config/mosquitto.conf"]`, `Volumes:
  {"/mosquitto/data","/mosquitto/log"}`, `ExposedPorts: 1883/tcp`.
- The image's own user is **uid/gid 1883** (`addgroup -S -g 1883 mosquitto` /
  `adduser -S -u 1883 … -G mosquitto`, Dockerfile at `docker/2.0-openssl`, official-images
  commit 5b74cce) — the C04 note's "mosquitto uid 100 — confirm" resolves to **1883**
  (100 is the Debian-PACKAGE uid; the image is not that). Entrypoint chowns /mosquitto to
  1883 ONLY when started as uid 0 (`docker-entrypoint.sh`: `if [ "$(id -u)" = '0' ]`).
  Pod shape that works: `podSecurityContext: runAsUser: 1883, runAsGroup: 1883,
  fsGroup: 1883, runAsNonRoot: true` + container drop-ALL/no-priv (t3 asserts exactly
  those two). CAUTION: `runAsNonRoot: true` WITHOUT `runAsUser` would be rejected at
  runtime (image User None ⇒ treated-as-root); and ConfigMap-mounted config arrives
  world-readable (0644) so uid 1883 can read the subPath item. `readOnlyRootFilesystem:
  false` stays (broker may touch /mosquitto paths; already planned).
- Minimal anonymous config: the image SHIPS `/mosquitto-no-auth.conf` = `listener 1883` +
  `allow_anonymous true` (fetched) — the C04 ConfigMap adds the bind (`0.0.0.0`) and
  `persistence false`; matches mosquitto-chart.sh t1's needle set (`listener 1883`,
  `allow_anonymous true`, `persistence false`). Note also 2.x default refuses remote
  listeners — the chunk's "ConfigMap is load-bearing" stands.

dev wiring (services/dev/prod): umbrella chart `name: dev`; `charts:` entries are 4-line
blocks (`namespace: default`, `ServerSideApply`, optional `chart:` — copy the
`searxng:`/`cloudnative-pg:` shape; C04 said copy qdrant's FILE set, C05 said copy the
`forgejo-runner-dev` N/A precedent — both confirmed present in the file). AppSet naming
law: base `appset-charts.yaml` template metadata.name = `{{ .serviceName }}-{{
.appName }}` → dev releases `dev-home-assistant` / `dev-mosquitto`; app-template (with the
hardcoded release-derived nameOverride) renders the Service NAMED `dev-home-assistant` —
matches the existing ingress comment (`searxng → dev-searxng`) and `dev-wiring.sh` t2/t3
pins (`service: dev-home-assistant`, port 8123, host `home-assistant.<domain>` via the
generic-ingress `ingress.subdomains` key rule: non-clusterBase key = `"<key>.<domain>"`).
Mosquitto gets NO subdomains entry (t2 asserts zero mosquitto hosts); N/A comment leg
confirmed by the forgejo-runner-dev/`runner:` slice precedent. Umbrella baseline TODAY:
`helm lint services/dev/prod` passes with one pre-existing WARNING (`coder-OVERRIDE_VIA_
APPSET-ingress` name) — tests must not treat it as new. [registry API + renders + reads]

### R2.4 C06–C09 — port-recipe deltas round 1 missed

1. **Symlink direction is REVERSED in all three targets.** Each has `.opencode/agents →
   ../.agents/agents` and `.opencode/skills → ../.agents/skills` (targets: real dirs in
   `.agents/`, symlinks in `.opencode/`), while SpencersLab runs the opposite (sources in
   `.rulesync/`, real generated `.opencode/`, `.agents/agents|commands → .opencode/…`).
   Consequence: `rulesync generate` run in a target TODAY would follow `.opencode/agents`
   INTO the tracked `.agents/agents/` dir and pour generated agents beside the 5 tracked
   files — and with `delete: true` (rulesync.jsonc default in SpencersLab) the orphan
   sweep operates through the same symlinks. The C06 inside-out sequence is therefore
   MANDATORY, concretely: author sources → delete the two `.opencode/agents`/`skills`
   symlinks (and the absent `commands` one is new anyway) → generate into real
   `.opencode/` dirs → point `.agents/agents → ../.opencode/agents` (the old tracked dir's
   5 files first folded, then `rm -r`) → keep `.agents/skills` REAL (aurora registry) and
   ADD `skills/` path coverage via the ported opencode config, generating the pipeline-*
   + boards skills as real `.opencode/skills/` content. AC6's "`.agents/skills`
   byte-unchanged" is exactly the guard against the reverse-symlink hazard. HomeAssistant
   `.opencode/` also holds real `extensions/` + `plugin/cost-title.ts` — the swap must not
   convert those to symlinks. [ls -la probes ×3]
2. **Worktrees interplay (LBF)**: `git worktree list` = 25 rows (main + 24 checkouts under
   `.agents/worktrees/`, gitignored at repo `.gitignore` L2 `.agents/worktrees/`;
   `.agents/.gitignore` hides `agent-manager.json`, node_modules, locks). The symlink swap
   in the MAIN checkout does not propagate into worktrees (each materializes its own
   tracked symlinks from ITS branch commit) — no port damage; the residual risk is only
   RULESYNC SWEEP traversal if dev ever runs generate from inside a worktree (C06/C07/C08
   must run it at the repo root). `port-lbf.sh` pins `LBF_WORKTREES_MIN=25` (live-verified)
   and the skills registry hashes (`SKILLS_LOCK_SHA 1442a292…`, `SKILLS_TREE_SHA e2eee38a…`
   — re-verified matching disk state at R2 time). [probes]
3. **Import path exists and works**: `rulesync import -t opencode -f rules` imports
   `AGENTS.md` → `.rulesync/rules/overview.md` (proved on a /tmp fixture — "Imported 1
   file(s) (1 rules)"). None of the targets has CLAUDE.md/.cursorrules/copilot rules/root
   opencode configs beyond the items below, so `-t opencode` is the right import verb;
   hand-place/section-split after import per plan. rulesync 37.0.0 at
   `~/.nvm/versions/node/v26.5.0/bin/rulesync` (re-verified). [fixture run]
4. **Per-repo config collisions the plan under-specifies**:
   - brother already carries `.opencode/opencode.json` (`plugins: [ocx,
     @mohac34/opencode-notifier, @plannotator/opencode@latest, plannotator/opencode@latest]`)
     + `.opencode/opencode.json.openchamber.backup`. The C06-recipe copy lands
     `.opencode/opencode.jsonc` — SAME directory, different extension: two project config
     files, precedence undefined. C08 dev must MERGE the `plugins` array into the ported
     `opencode.jsonc` and keep or remove `opencode.json` deliberately (the backup file is
     untracked noise — leave it). Also re-pin `uv.lock`, `.vscode/`, `docs/proposals/0002`
     as untracked leave-alone items (the plan's "2 dirty files" is about the two tracked-M
     agents; the untracked four exist and must survive too).
   - HomeAssistant: protected dirty set matches the plan (M Coder.code-workspace; ??
     cost-title.ts + extensions/ + one plan file) — all untracked/M, none revert-able.
     `.agents/package.json|node_modules` (kilocode plugin dep, gitignored by
     `.agents/.gitignore`) — leave.
   - The ported `.opencode/opencode.jsonc` skills paths (this repo's file lists
     `["/home/coder/CuratedForest.com/content/tech/home-assistant", "./.agents/skills",
     "skills/"]`) — the absolute CuratedForest.com entry is SpencersLab-specific; targets
     need `./.agents/skills` + `skills/` only (drop or adapt; harmless otherwise).
   - LBF/brother `.opencode/plugin/` exist but contain only `.gitkeep` → the three plugins
     drop in cleanly; HomeAssistant keeps cost-title.ts alongside (C07 task already right).
5. **Pinned-skill retargeting for the plain dev family (the real C06 trap)**: this repo's
   `agent-dev-local` pins `/helm-bjw-s-chart /gitops-workflows /helm-chart-creation
   /executing-plans` (+ the two pipeline skills). Targets have NONE of the first three
   (their registries: the 9 aurora skills — agent-rules/api-catalog/aurora/esphome/
   ha-dashboard-design/ha-integration-dev/home-assistant-best-practices/home-assistant-
   yaml/node-red — plus each repo's self-written skills; LBF/HA identical 9, brother has 7,
   missing agent-rules + home-assistant-best-practices). `port-lbf.sh` has no machine check
   for it (only t6 registry-hash guards), but `port-brother-ptouch.sh` DOES run the
   absent-skill guard over generated agent/skill sources — so an un-retargeted dev-local
   pin fails C08 at minimum. Decision the ports must make once (and replicate): re-pin
   target dev-local/code-family task skills to the target registry (e.g. LBF dev overlay
   gets ha-integration-dev-class pins via C09's ha agents; the PLAIN dev-local keeps only
   executing-plans + the pipeline-* contract skills, which the port provides). The C09
   per-agent pin table in `ha-overlay-agents.sh` (ha-dev/custom-component →
   ha-integration-dev + home-assistant-best-practices (+labeled-features LBF-only), ha-code
   → home-assistant-best-practices + home-assistant-yaml, head pins per repo = plan's) is
   live-consistent with all target registries — no action.
6. Coord roster extension shape for C09: this repo's `agent-coord-local.md` permission
   list carries `- action: subagent / resource: agent-<name> / effect: allow` rows (dev-
   local/review/research visible in source L338–345); the target coord sources gain rows
   for `agent-ha-dev` + `agent-ha-custom-component` in exactly that shape; the ha agents'
   own permission blocks copy `agent-dev-local`'s frontmatter shape verbatim (broad
   `edit *` allow first, tests/plans denies, `.rulesync/**` ask, question allow —
   last-match-wins order preserved). [source reads]

### R2.5 — per-chunk reality check (AC vs live state)

- C01: no contradictions; anchors exist where the chunk expects them (R2.1). The suite's
  anchor+window design survives bullet re-wrap — dev must keep the six semantic tokens
  (Repo: posture, eligibility rule, filter position, never-in-claim-set, identity
  mismatch→NEEDS_INFO, four spellings) rather than prose form.
- C02: consistent, plus the heredoc-trap note (R2.1) and the live fact that Executing
  currently holds 3 label-less cards — all default-picker (SpencersLab) cards today; the
  filtered count legitimately stops SpencersLab's hourly while any is there, and would
  legitimately let OTHER repos proceed once Repo:-tagged — matches intent.
- C03: three plan-gaps converted to decisions-by-evidence (R2.2): remove the nameOverride
  string; set `createDefaultServiceAccount: false`; use the Chart.yaml `condition:` gate
  (the only mechanism that satisfies t2's chart-level flag semantics). Startup-probe type
  uppercase TCP. None contradicts an AC; all ACs are achievable and were proven achievable
  in /tmp renders (default = snapshot byte-identical; dev-mode kinds set correct).
- C04: image fact corrections (uid 1883 not 100; `latest`/2.1.2-alpine nuance) —
  informational, the pinned `2.0.22` and the ConfigMap content stand. One runtime caution
  added: runAsNonRoot needs explicit runAsUser 1883 (image User None).
- C05: all pins verified against live renders/comments (release naming, ingress host
  rule, qdrant/zigbee precedents, umbrella baseline warning is pre-existing).
- C06: achievable as specified WITH the R2.4 reversals applied (symlink direction,
  dev-local skill-pin retarget, opencode.jsonc skills-paths trim). FRICTION's LBF
  clean-tree correction re-verified live (porcelain empty; 25 worktree rows; registry
  hashes match suite defaults).
- C07: protected-file claims re-verified (all untracked/M as listed). Cost-title plugin
  and extensions/ survive the generate only if the R2.4.1 swap order is honored.
- C08: "2 dirty files" is accurate but INCOMPLETE — 4 untracked paths also exist
  (uv.lock, .vscode/, docs/proposals/0002, .opencode/opencode.json.openchamber.backup);
  add the existing `.opencode/opencode.json` plugins-merge to the port recipe (R2.4.4).
  The dirty agents' sha pins (f07dac60…/aaba9e48…) match live.
- C09: pin table vs target registries — fully resolvable (checked per agent); overlay
  names + coord-roster shape grounded (R2.4.6). No contradiction.

### Round-2 open questions (batch later — do NOT re-ask research-side)

- RQ-1 (C03 mechanism fold-back): the `condition:` gate + `createDefaultServiceAccount:
  false` + nameOverride-line removal are now PROVEN requirements of the written tests,
  not just dev choices — coord should paste R2.2 items 1–4 into C03's dev launch brief
  (or the dev rediscovers them the hard way; acceptable but slower).
- RQ-2 (C08 config merge): keep `.opencode/opencode.json` after merging its plugins into
  the ported `opencode.jsonc`, or delete it? OpenCode's precedence between the two
  extensions is not documented in this repo's surfaces — dev probes once (both files
  present, check a plugin effect or config read), reports the observed winner, and the
  port keeps ONE file. Best guess: merge into jsonc, remove the .json.
- RQ-3 (plain dev-local retarget set): the exact task-skill pins for the ported PLAIN
  dev/code/debug in each target (beyond "drop the helm trio") — best guess: LBF/HA →
  home-assistant-best-practices (+home-assistant-yaml) for the standalone `code`,
  nothing extra for pipeline dev-local (the ha overlay trio carries the domain pins);
  brother → none beyond executing-plans + the contract set.

### Round-2 source addenda (continuing numbering)

[18] Live reads this round: the feature-folder plan/chunks/DECISIONS/FRICTION/STATE;
`.rulesync/skills/boards/SKILL.md` + generated mirror (diffs, anchor lines);
`.rulesync/commands/pipeline-boards-hourly.md` + mirror;
`scripts/agent-board-coord-gate.sh`; `charts/home-assistant/*` (all files);
`charts/zigbee2mqtt/{Chart.yaml,Chart.lock,values.yaml,templates}`; `charts/qdrant/*`;
`services/{dev,grow,home}/prod/values.yaml` slices + `services/dev/prod/templates/`
+ `charts/base/templates/appset-charts.yaml`; `.gitignore` L3–4; targets' `.gitignore`s,
`.agents/`+`.opencode/` layouts (ls -la), `agent-manager.json` (LBF), `opencode.json`
(brother), `.agents/.gitignore`×3; `rulesync.jsonc`; `rulesync --version` + `import
--help` + fixture import run; `.rulesync/subagents/agent-dev-local.md` +
`agent-coord-local.md`; `tests/multi-repo/*` (all nine suites' pins, anchors, snapshots);
`.agents/skills/rulesync/SKILL.md` excerpt; `skills-lock.json` re-reads.
[19] Live renders (this round, /tmp working copies only — repo untouched): pre-change
`helm template ha-test charts/home-assistant` (golden); variant matrix
before/after — dep-active-as-is (BREAKS: YAML-conversion error), dep-active-no-ATblock
(stray ServiceAccount), dep-active + `createDefaultServiceAccount:false`
(BYTE-IDENTICAL), + controller/service/persistence blocks `enabled: false`
(BYTE-IDENTICAL), + `condition: homeAssistant.enabled` gate (BYTE-IDENTICAL default;
`--set homeAssistant.enabled=true postgres.enabled=false` → Deployment+Service, pinned
image, probes, drop-ALL, /config mount via existingClaim, Service port 8123; schema
errors pinned for lowercase probe type and v4-style persistence keys). qdrant render
naming (Service=release-name, parent PVC=chart-name). `helm lint services/dev/prod`
baseline. `helm dependency update` fetch of app-template 5.0.1 (digest matches
zigbee2mqtt Chart.lock). app-template 5.0.1 internals read from the tgz
(templates/common.yaml hardcodedValues, charts/common `_enabled_controllers.tpl`
default-on semantics, `_init.tpl` default-ServiceAccount injection, values.schema.json).
[20] Docker Hub/GHCR/official-images (2026-10-31): registry API blob reads —
`library/eclipse-mosquitto` 2.0.22 (User None, Cmd /usr/sbin/mosquitto -c
/mosquitto/config/mosquitto.conf, Volumes data+log, ExposedPorts 1883) and 2.1.2-alpine
same shape; hub tags list (`latest`=2.1.2-alpine digest-equal, bare stream ends at
2.0.22, `-openssl` flavor notes); `docker-library/official-images/master/library/
eclipse-mosquitto` (GitCommit 5b74cce, tag→directory map); the repo's
`docker/2.0-openssl/Dockerfile` (addgroup/adduser **1883**, chown /mosquitto) +
`docker-entrypoint.sh` (uid-0-only chown) + `mosquitto-no-auth.conf`
(`listener 1883` + `allow_anonymous true`); GHCR token+manifest —
`home-assistant/home-assistant:2026.10.4` 200 OK with amd64 platform.

### Reliability notes — round 2

- Confidence 10/10 on R2.2/R2.3 items proved by direct renders (the /tmp matrix) and
  registry blobs. R2.1/R2.4 are direct file reads. R2.5 re-verifies round-1 volatile
  pins (HEADs, worktree rows, dirty sets) — all re-pinned TODAY; they can still drift
  before wave 3–5 runs (re-pin at chunk start, per the suite env knobs).
- Weakest claim: RQ-2 (opencode.json vs .jsonc precedence) — unprobed (needs an OpenCode
  runtime); dev probes once, it is testable from inside the chunk.
- Not re-checked this round: live board state (unchanged since round 1 except nothing —
  no board writes happened in round 1 either); the grow cluster (post-merge check stays
  user-owned).
