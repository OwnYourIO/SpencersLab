# PLAN: Multi-repo pipeline — Repo: pickup filter, rulesync port to three HA/automation repos, HA + MQTT dev pods
feature: 2026/2026-10-cf-93-feat-multi-repo-pipeline
card: #93 (mxnEsiC2SwtLKZE9i) "Add repos: context and label support filtering." — slug `cf-93-feat-multi-repo-pipeline`, run_tag none (card-driven), models Qwen Flash both tiers, stages Plan+Test+Code+Review (legacy Research checklist → transition rule: full standard loop), HITL Plan+PR.

## Goal
Extend the board-driven pipeline to more repos: a `Repo:` label pickup filter (filter, not lock — locks are already per-repo via each root's `.pipeline/locks/`, RESEARCH A2), plus a full rulesync port of the agent machinery into `/home/coder/Home-Assistant-Label-based-Features`, `/home/coder/HomeAssistant` and `/home/coder/brother-ptouch-automation` with HA overlay agents. Second half: land the two dev-cluster pods (home-assistant + mosquitto) by filling `charts/home-assistant` on app-template 5.x and creating `charts/mosquitto`, wired through the dev trio.

## Out of scope
- Post-pod HA setup/onboarding/backup (separate card).
- Any change to `.opencode/plugin/pipeline-locks/` (RESEARCH A2: cross-repo exclusion is impossible-by-filesystem; the plugin ignores non-`Pipeline:` labels by construction — say so in every chunk note so no dev invents one).
- Commits, pushes or worktrees in the three target repos — all target-repo edits stay UNCOMMITTED on their `main` working trees, THIS CARD ONLY (OQ-B1 resolved 2026-10-31: the owner approved the port landing dirty and directed a follow-up card for a generic working-mode implementation — see Follow-up cards). The ported machinery itself keeps normal commit discipline for future runs; landing it permanently (commit + each repo's own PR flow) is the owner's post-accept step.
- Creating `Repo:` labels on the board (human-owned posture, like `Pipeline:`); OpenChamber scheduled-task enablement per target repo (human-owned scheduler hygiene — target loop files ship `enabled: false`).
- wekan-mcp label-assignment tooling (card #74's own scope — pickup filtering needs only label READ, proven live, RESEARCH A4).
- `agent-ha-config`, `agent-pt-*` python overlay, `agent-ha-review` variants — highlighted in C09 Notes, deferred to follow-up cards.

## Commands
All run from this worktree (SpencersLab side) or with `cd`/`-C` per target; `export PATH=$HOME/.local/bin:$PATH` first (helm lives there — FRICTION seeded).
- chart lint/render: `helm lint charts/<name>` ; `helm template charts/<name> --set domain=test.example.com --set bitwardenIds.home-assistant-pg=test-uuid` — no `OVERRIDE_*` string may appear in rendered output (except where a chunk documents gated-off sentinels)
- umbrella render: `helm lint services/dev/prod` ; `helm template services/dev/prod --set domain=test.example.com` — the `charts:` Applications and the `home-assistant` ingress host must appear
- trio grep: `grep -n "home-assistant\|mosquitto" services/dev/prod/values.yaml` (chart entry + proxy entry; mosquitto's proxy leg is documented N/A-in-cluster per the forgejo-runner-dev precedent)
- rulesync: `rulesync generate` (twice — second run no-op) and `rulesync generate --check` in THIS repo; the same inside each target repo (`/home/coder/<repo>`)
- target-repo safety pin: `git -C /home/coder/<repo> rev-parse HEAD` recorded at run start; MUST equal it at every review (nothing committed)
- contract suites: `bash tests/multi-repo/<suite>.sh` (agent-test writes; per-directory basename-dedup rule applies)
- quality gate: `npx aislop ci --changes` posture on touched files (manual `$aislop` before hand-back)
- deploy verification (post human-merge, user-owned): `readonly-dev-kubernetes` — HA + mosquitto releases in `default`, pods Running

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | boards skill: `Repo:` pickup filter + repo-identity rule + AGENTS.md identity line | M | 1 | [] | |
| C02 | hourly BOARD CHECK repo-filtered + gate-script posture note | S | 2 | [C01] | command text consumes C01's filter semantics + identity rule (interface) |
| C03 | `charts/home-assistant`: app-template 5.0.1 container fill-in + postgres/pvc gating flags | M | 1 | [] | |
| C04 | new `charts/mosquitto` on app-template 5.0.1 (`version: 1.0.0`) | M | 1 | [] | |
| C05 | dev trio wiring: `services/dev/prod/values.yaml` entries + ingress + render/greps | M | 2 | [C03,C04] | appset entries reference the two charts (file/data) |
| C06 | reference pipeline port → Home-Assistant-Label-based-Features (uncommitted) | L | 3 | [C01,C02] | ported boards skill + hourly command must carry the C01/C02 edits (content) |
| C07 | port → HomeAssistant (uncommitted; delta: keep cost-title plugin, HA-config services list) | M | 4 | [C06] | C06's port recipe is the interface it copies |
| C08 | port → brother-ptouch-automation (uncommitted; delta: pytest/ruff test law) | M | 4 | [C06] | same recipe; independent of C07 |
| C09 | HA overlay agents in LBF + HomeAssistant: `agent-ha-{dev,code,debug}` + `agent-ha-custom-component` + coord roster extension | M | 5 | [C06,C07] | overlay sources need the targets' generated surfaces + skill registry (files) |

## Wave order
1. C01, C03, C04 (independent; id order)
2. C02, C05 (independent; id order)
3. C06
4. C07, C08 (independent; id order)
5. C09

## Verified facts (plan session, 2026-10-31 — re-pin at run start, verify-after-apply posture)
- Target HEADs NOW (the no-commit pins for C06–C09): LBF `2ea63fdecf1b5cfe36f7ac2e1f56ce8d4bbd5e7e`, HomeAssistant `ddd20d587fc6a92186d0cbce6d0d50270d8f4950`, brother-ptouch-automation `381d72f75f7c169edb448dc3c04ea64743d6abf7` — all on `main`, none has `.rulesync/` yet.
- `rulesync` 37.0.0 on PATH at `~/.nvm/versions/node/v26.5.0/bin/rulesync`; `helm` at `~/.local/bin` (PATH export note applies).
- `charts/home-assistant`: Chart.yaml v1.0.16, dependency stub COMMENTED (4.3.0), values carry the `# TODO: add home-assistant container.` + 3 `bitwardenIds` sentinels; pg/pvc/secret templates exist, PVC fully commented ("Disabled until Home Assistant pod is added"); grow deploys it as appName `assistant` (`services/grow/prod/values.yaml` L25).
- `services/home/prod/values.yaml` L153–155: commented-out mosquitto ingress entry (home-cluster history; dev wiring is fresh).
- Image tags probed live 2026-10-31: `eclipse-mosquitto` newest numeric Docker Hub tag `2.0.22`; HA `2026.10.4` (= pajikos appVersion = live prod HA, RESEARCH C/14).
- dev-boards deployed catalog: 26 tools, no label tool; label READ (`get_board` labels + `get_card` label_ids) works — the filter needs reads only (RESEARCH A4).
- RESEARCH ROUND 2 (2026-10-31, /tmp render matrix + registry blobs, R2.1–R2.5): the proven C03 mechanism = Chart.yaml dep `condition: homeAssistant.enabled` + `createDefaultServiceAccount: false` + REMOVE the `nameOverride: "{{ .Release.Name }}"` string (landmine post-dep-activation) + qdrant-style `existingClaim` + UPPERCASE `TCP` probe types — default render proven byte-identical, dev-mode kinds `[Deployment, Service]`; mosquitto image User None ⇒ pod trio runAsUser/runAsGroup/fsGroup **1883** + runAsNonRoot (uid 100 was the Debian-package uid, not the image's); bare mosquitto stream ends at 2.0.22 (`latest = 2.1.2-alpine`); dev release/service naming PROVEN `dev-home-assistant`/`dev-mosquitto` (appset `<serviceName>-<appName>` + release-derived nameOverride); `helm lint services/dev/prod` baseline carries one PRE-EXISTING WARNING (coder-OVERRIDE_VIA_APPSET-ingress); all three targets run REVERSED `.opencode/agents|skills` symlinks — swap order mandatory before first generate (R2.4.1); brother-ptouch already has `.opencode/opencode.json` plugins to MERGE (RQ-2); plain ported dev-local must drop the unresolvable helm skill pins (R2.4.5); `rulesync import -t opencode -f rules` proven.

## Key decisions (full log in DECISIONS.md — all confirmed in the batched round 2026-10-31, OQ ids cited)
- `Repo:` = pickup filter only; never joins the claim set; `Pipeline:` keeps its lock meaning and coexists (OQ-A1 HUMAN CONFIRMED: coexist, no migration of the owner's `Pipeline: Home Assistant/Local/CICD/Context` tracks).
- Repo identity = canonical-root basename cross-checked against a per-repo AGENTS.md `Repo identity:` line; mismatch → RESULT flag, never guess; no plugin/config change (OQ-A2 CONFIRMED).
- Session gate (`agent-board-coord-gate.sh`) KEEPS cross-project counting — shared OpenCode server confirmed; one repo's live coord serializes the others (conservative single-writer); only the BOARD CHECK is repo-filtered (OQ-A3 CONFIRMED).
- HA pod = fill the existing in-repo `charts/home-assistant` (app-template 5.0.1, image pinned `2026.10.4`), pajikos kept cited as community fallback; CNPG/secret templates gain `postgres.enabled` default **true** so the grow release renders byte-identical; HA container + config PVC gated by `homeAssistant.enabled` default **false** (OQ-C1 CONFIRMED). Mechanism per round 2 (R2.2, PROVEN renders, no longer dev-discretion): dependency `condition:` gate + `createDefaultServiceAccount: false` + nameOverride-string removal + existingClaim persistence + uppercase TCP probes.
- MQTT = new app-template chart on `eclipse-mosquitto:2.0.22` (bare-stream rationale per R2.3: 2.1.x ships only as `-alpine`; `latest` = 2.1.2-alpine), ClusterIP-only in dev, anonymous listener ConfigMap, pod security runAsUser/runAsGroup/fsGroup **1883** + runAsNonRoot (image User None), no secrets ⇒ no custom-values entry, proxy leg documented N/A (OQ-C2 CONFIRMED).
- `/config` on local-path with ReclaimPolicy Delete: accepted, documented in the values (OQ-C3 CONFIRMED).
- HA overlay agents land in the TARGET repos' `.rulesync/subagents/` (repo-owned overlays per agents-sync "other repos may add overlays"; skill pins must resolve in the target registry), NOT this repo's sources (placement stands with the plan approval; see DECISIONS).
- Target repos: uncommitted-dirty-main working mode is THIS CARD ONLY (the port edits themselves); the ported machinery keeps normal commit discipline for future runs; coord files a follow-up card tracking a generic implementation (OQ-B1 ANSWERED WITH ADDITION — see Follow-up cards).
- `Repo:` label spellings = exact dir names, case-sensitive, incl. lowercase-b `Home-Assistant-Label-based-Features`; the four `Repo:` labels are created by the owner in WeKan (OQ-B2 CONFIRMED, human-owned).

## Open questions — RESOLVED in the batched round 2026-10-31 (answers folded into plan/DECISIONS/chunks)
- OQ-A1: ANSWERED **COEXIST** — `Repo:` is a pickup-only filter; `Pipeline:` labels keep their lock meaning untouched. No label migration. (C01 implements the coexistence wording; owner keeps their track labels.)
- OQ-A2: **CONFIRMED best guess** — canonical-root basename + per-repo AGENTS.md `Repo identity:` cross-check; mismatch → RESULT flag, never guess; no plugin/config change. (C01.)
- OQ-A3: **CONFIRMED** — shared OpenCode server; the session gate keeps cross-project session counting (conservative single-writer); only the hourly BOARD CHECK gets repo-filtered. (C02.)
- OQ-B1: **ANSWERED WITH AN ADDITION** (verbatim): "Ok, so you should do it for this card, and create another card to track implementing it generically." → uncommitted-dirty-main is THIS-card-only in the C06–C09 notes (the ported machinery keeps normal commit discipline for future runs), AND coord files a follow-up board card tracking the generic implementation (Review-list posture, per the boards skill's friction-override card pattern). Coord executes the card creation — not a chunk task. See Follow-up cards.
- OQ-B2: **CONFIRMED** — exact dir-name spellings, case-sensitive, incl. lowercase-b `Home-Assistant-Label-based-Features`; the owner creates the four `Repo:` labels in the WeKan UI (human-owned, like `Pipeline:`). (C01 filter table.)
- OQ-B3: **CONFIRMED** — keep the permission `ask` flow with mid-run human approvals (question-notify); no pre-widening chunk. The run-tempo risk note stands (Risks).
- OQ-C1: **CONFIRMED** — app-template fill-in of `charts/home-assistant`; the gating flags keep the grow release byte-identical. (C03.)
- OQ-C2: **CONFIRMED** — mosquitto ClusterIP-only in dev; proxy leg documented N/A. (C04/C05.)
- OQ-C3: **CONFIRMED** — `/config` on local-path with Delete policy accepted, documented in the chart values. (C03.)
- OQ-D1: **CONFIRMED** — per-repo Services-checklist sets as drafted in the C06–C08 notes.
- OQ-A4: **accepted as informational** — the "Provider" analogy is the Model(s)-checklist routing; no action, no `Provider:` label concept.

## Round-2 research questions (folded as mechanism notes — NOT a new user round)
- RQ-1 (C03 mechanism): RESOLVED by this fold — R2.2 items are now chunk Tasks requirements; `ha-chart.sh` already pins them (no test-vs-mechanism conflict found).
- RQ-2 (brother `.opencode/opencode.json` vs `.jsonc` precedence): OPEN MECHANISM, dev-probes once inside C08 and keeps ONE config file (best guess: merge plugins into the jsonc, remove the json) — reported in chunk RESULT, no user question.
- RQ-3 (plain ported dev/code pins per target): folded as C06/C07/C08 retarget task text per the best guesses (LBF/HA standalone → home-assistant-best-practices + home-assistant-yaml; brother → contract set only; plain pipeline dev-local → executing-plans + contract set everywhere).

## Follow-up cards (coord-side, not chunks)
- **Generic uncommitted-dirty-main mode** (from OQ-B1, owner verbatim: "…create another card to track implementing it generically"): ONE card created by coord into **Review** (never an in-session agent-plan ticket — boards skill friction-follow-up posture: `create_card` into Review; the createCard rule adds the five standard checklists; `toggle_checklist_item` the known answers: Services `agent context`, Type `chore`, Model(s) `Qwen Flash`), titled to state the fix and describing: the card-#93 port used a this-card-only uncommitted-dirty-main working mode in the three target repos; the generic mechanism (a per-repo "working mode" ruling in the ported kickoff/gates/dev-role contract text, how it interacts with worktree/branch minting and per-chunk commit discipline, and which repos adopt it) is the follow-up work. Quote this plan's OQ-B1 answer as its context. Human moves Review → Finished/Rework.
- The four `Repo:` board labels themselves remain owner hygiene after C01/C02 land (Out of scope note) — no card required unless the owner wants one tracked.

## Risks
- Permission `ask` mid-run (OQ-B3 CONFIRMED — keep the flow, human approves): a scheduled/unattended leg that cannot reach the human stalls at the first `.rulesync/subagents|commands` edit or `rulesync generate`; mitigations: approval landed before the chunk loop (this round), stale clock (2 h) noted, chunk order keeps read-mostly C01/C03/C04 first. The risk itself stands — recorded, accepted.
- Cross-repo edits ride on the machine-global `external_directory * allow` — not repo-verifiable; review re-proves by reading target files, never trusting a dev "done" claim (agents-sync: verify deploys landed).
- Growing a second worker repo makes the hourly gates interactive: a mis-tagged card (no `Repo:`) still counts for SpencersLab only by the default-picker rule; a typo'd label silently parks a card — claim-comment records the derived set (existing drift posture extends to Repo: skips, one sentence in C01).
- C03 touches the live grow release: byte-identical default render is an AC, and `helm template charts/home-assistant` before/after diff is in the test suite.
- Target repos are dirty ahead-of-remote working trees (RESEARCH B): the port must not touch their existing dirty files (`HomeAssistant/.opencode/plugin/cost-title.ts`, LBF worktrees dir, `brother-ptouch` 2 dirty files) — chunk scope lists are explicit allow-lists.
- Card-driven run: no run tag; all surfaces named from slug `cf-93-feat-multi-repo-pipeline`; PR landing on `main` + target-repo commits/label creation + scheduler enable are human-owned (HITL PR checked; Deploy stage absent → `-local` posture, report "ready — commits local").

## Skills per chunk area
- C01/C02: `/agents-sync` `/boards` `/pipeline-conventions` (+ `/writing-plans` review posture). C02 also reads `scripts/agent-board-coord-gate.sh` header.
- C03/C04/C05: dev pins `/helm-bjw-s-chart` `/helm-chart-creation` `/gitops-workflows` `/executing-plans` (+ `/kubernetes-skill` for the mosquitto security shape).
- C06/C07/C08: `/agents-sync` (+ `references/syncing-to-other-repos.md`, `references/permissions.md`), `/rulesync`, `/boards`.
- C09: `/agents-sync` `/ha-integration-dev` `/home-assistant-best-practices` `/labeled-features` (LBF) `/helm-chart-creation` not needed.
- MCP: none required for any chunk's validation (all local renders/greps); `readonly-dev-kubernetes` only in the post-merge user-owned deploy check; `dev-boards` stays coord-side.
