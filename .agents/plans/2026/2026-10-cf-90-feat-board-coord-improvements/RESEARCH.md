# RESEARCH — cf-90 agent-board-coord improvements

Round: Before-Planning (card #90 legacy Research checklist: Before Planning + After Planning both checked).
Date: 2026-10-31. Method: storm — local repo grounding first (the card is about in-repo machinery), then
web-grounded platform facts (WeKan main source, OpenChamber 2.5.2 server source on this machine, GitHub
Actions docs, Coder docs, kopia docs, playwright-mcp docs, helm docs). Every load-bearing claim cites a
source; `[L…]` = local repo/live-probe, `[W…]` = web source (all fetched 2026-10-31 unless noted).

## TL;DR

1. Every one of the card's 12 asks is feasible with machinery that mostly exists already; the two genuinely
   new build items are (a) an idempotent board-provision command (lists+labels+rules via existing wekan-mcp
   tools) and (b) a label-on-card capability in wekan-mcp for parent-label inheritance.
2. WeKan rules CANNOT derive a label name from the destination list (`addLabel` takes a fixed `labelId`, no
   substitution) — "Bucket: <list>" needs one label + two rules (createCard + moveCard) PER list, scoped by
   `swimlaneName` because list titles repeat across swimlanes. Fully automatable via create_label/create_rule.
3. Session archive-on-no-cards is a one-liner: OpenCode v2 has native archive — `PATCH /api/session/<id>
   {"archived": true}` (live-verified on this host; OpenChamber's own archive uses exactly this route).
4. Provider: API / Provider: Local filtering is coord-side pickup-walk text (OpenChamber has no label filter);
   the Local task is a second loop file with a gpu-ai model; Always-Allow is the OpenChamber task's
   `permissionAutoAccept` flag, settable in the UI, and it SURVIVES loop-file re-sync.
5. Kopia has never been in this repo (grep + full git history) — the backup/restore integration-test mechanics
   are genuinely follow-up-card territory, as the card itself directs.

## Key findings

### F1 — WeKan rules engine: no dynamic label names, per-list rules required (card ask: "Bucket: <list name>")

- Trigger vocabulary: `{activityType: createCard | moveCard | editCard | scheduledTrigger | button}` with
  optional matchers `listName, oldListName, swimlaneName, cardTitle, userId` (omitted = `'*'`). The create
  endpoint validates only key presence — the vocabulary is what `rulesHelper.js` implements [L3, source-checked
  v9.99; re-verified unchanged on main, W1].
- `addLabel` on current main is `await card.addLabel(action.labelId)` — a FIXED board label id; `substituteVars`
  is NOT applied to it [W1 L926-930]. WeKan main DOES have rule variable substitution — `{cardname}`,
  `{listname}`, `{boardname}`, `{cardnumber}`, `{swimlanename}`, `{customfield:Name}`, `{membername}`, date
  tokens — but only for TEXT fields: created checklist/card/list/swimlane names and email subject/body
  [W2]. Label selection is not among them, and there is no "create label" rule action [W1].
- Consequence: a single generic "add Bucket: {listname}" rule is impossible. The design is one rule pair per
  list: `createCard(listName=X, swimlaneName=Planning) → addLabel(Bucket:X)` AND `moveCard(listName=X,
  swimlaneName=Planning) → addLabel(Bucket:X)` (card creation emits `createCard`, not `moveCard`). The
  `swimlaneName` matcher is load-bearing: list titles repeat across swimlanes — live board has Context,
  Features, Research, Dev Env, Home Assistant each in Backlog + Farm + Planning as SEPARATE list documents
  [L16].
- Execution caveats: rules fire async ~1-2 s after the activity, are never retroactive (existing cards need a
  round-trip or backfill), and rule ORDER is unspecified on the lab's versions [L3]. Multi-action rules became
  deterministic only in WeKan v12.10+ (#4294; maintainer decision 2026-09-29 per W2 header comment) — Bucket
  rules are single-action, so ordering is not a factor.
- The known-broken `checkItem`/`uncheckItem` rule actions (field typo `checkListId` vs `checklistId`,
  v12.64 → current main; fix = 3-token rename) do NOT affect this ask — Bucket labels need no checklist
  actions. The board's createCard rule keeps its checkItem extras dormant until upstream fixes it [L5 L316-364].

### F2 — Board provisioning is fully reachable through the existing wekan-mcp surface (card asks: init/update process)

- cf-89 landed exactly the needed tools [L1, L2]: `create_list(board_id, title, swimlane_id?, position?)`
  (appends; non-atomic reposition), `create_label(board_id, name, color)` — idempotent on (name, color), 25
  named colors, hex rejected client-side; gate board-admin-or-site-admin, `create_swimlane`, `update_board`,
  plus `create_rule/update_rule/remove_rule` and `list_rules` for idempotency checks.
- Idempotency shapes the command: create_label is idempotent; create_list and create_rule are NOT — the
  init/update flow must read-then-create (list_lists/list_rules/get_board first, create only the missing
  pieces). Single-writer, so the documented read-modify-write races are acceptable.
- LIVE board state (probed read-only via dev-boards 2026-10-31) [L16]:
  - Swimlanes: In Process, Backlog, Farm, Planning (Planning already exists).
  - Backlog lists (8): Context, Features, Research, Outside Process, Dev Env, Home Assistant, CICD, Wekan.
  - Planning lists (6): Context, CICD, Home Assistant, Dev Env, Research, Features — MISSING vs Backlog:
    "Outside Process" and "Wekan". So the first real run of the init process creates exactly those two.
  - Board labels: Research, Ready for Work, Pipeline: Local, Pipeline: CICD, Pipeline: Context, and
    **"Bucket Color" = darkgreen** — the swatch the user put on the card; bucket labels should be `darkgreen`.
  - Provider: API / Provider: Local labels do NOT exist yet → provisioning creates them too.
- Lists belong to one swimlane (each list document carries its swimlane_id [L16, L2]); labels are board-wide.
  The wekan.fi docs sentence "Lists are board-wide" [W11] conflicts with live data + the repo's own v12.64/65
  source-checks of create_list [L2] — live API behavior wins (see Contradictions).

### F3 — OpenChamber loop tasks: duplication, model, and Always-Allow (card asks: Provider tasks, Permissions)

Source = OpenChamber 2.5.2 server code installed on THIS machine [L19] + live project config [L18].

- Loop files (`.agents/loops/*.md`, user scope `~/.agents/loops/` too) sync to scheduledTasks. Recognized
  frontmatter: `name` (required), `schedule` (cron, required), `enabled` (default false), `model`
  (`provider/model` → providerID+modelID), `agent`, `timezone`. The WHOLE file body (comments included)
  becomes the prompt. Any other frontmatter key is ignored [L19 loops.js].
- Duplicating the worker for Provider: Local = a second loop file (own name/cron/model/agent + prompt text
  naming the provider filter). The first sync needs a one-time human approval: loopApprovals pins the sha256
  of {name, schedule, execution} [L18, L19 loops.js loopFingerprint].
- "Permissions: Always Allow" = `execution.permissionAutoAccept: true` on the task: the scheduler enrolls the
  session (`setSessionAutoAccept(sessionID, true)`) BEFORE the first prompt goes out; subagents inherit the
  nearest ancestor's mode (ask/safety/auto) [L19 runtime.js, permission-auto-accept/DOCUMENTATION.md]. The
  loop frontmatter cannot express it — but reconcileLoopTasks explicitly PRESERVES "UI-only fields the file
  format does not define" (`execution: { ...task.execution, ...loop.definition.execution }`), so a one-time
  human toggle in the OpenChamber task UI sticks across loop re-syncs [L19 project-config.js]. Live config
  today: pipeline-worker has NO permissionAutoAccept (matches the card's complaint); the "Check cluster
  statuses" task has it [L18]. Alternative (blunter): Settings → Sessions `permissionDefaultMode=auto`.
- Provider-based card filtering has NO OpenChamber-side support — it is coord-side: the pickup walk already
  reads labels (get_card/get_board) for the Pipeline: lock derivation, so the Provider: filter is a skill-text
  addition to the walk (skip candidates lacking the task's provider label; unlabeled cards → best-guess in
  open questions). The "label map" the card mentions is the board-context block's `labels:` section, which
  carries new labels automatically with no code change [L15 F5].

### F4 — No-cards exit: archive the session, don't ask (card ask #2)

- OpenCode v2 has NATIVE session archive: `PATCH /api/session/{sessionID}` body `{"archived": true|false}` —
  "Archive the session with true or restore it with false. Repeating the current state is a no-op." Verified
  live on this host's `opencode api get /openapi.json` [L17]. The session list endpoint takes an
  `archived=true|false` filter; archive emits `session.archived`/`session.unarchived` events [L19
  @opencode/schema session.d.ts/event-manifest.d.ts].
- OpenChamber's archive feature is a wrapper over exactly this route ("OpenCode 2.1 archives sessions itself
  (PATCH /api/session/{id} with archived), and session-archive.js sends every archive there"), plus its own
  archivedAt store; archived sessions move to the Archive view [L19 openchamber-sessions/archive-store.js].
- The pieces already exist on the agent side: coord variants' shell permissions allow `opencode api patch
  /api/session/*`, and the no-op exit already resolves its own sessionID via `session_rename` for the no-op
  marker [L7, L8 boards skill recipe]. Change = boards skill no-op exit: after the marker write, PATCH
  archived:true and NEVER ask ("should I close out?" observed once — the skill must state explicitly that a
  no-cards end archives and stops; question-notify's scheduled-no-op suppression already keeps the phone
  quiet [L8]). Archive is a metadata flag — safe to set while the session's final turn finishes.

### F5 — Follow-up cards with parent labels (card ask #6) and create_card's current surface

- `create_card` today: title/description/swimlane + `default_checked` (checklist title → item titles arriving
  CHECKED, via bounded polling of the rules-created checklists) — NO labels parameter [L1 create_card, L2].
- No MCP tool puts a label on a card (deliberate surface omission; the proven workaround is a moveCard→addLabel
  rule + round-trip, which reverses list order and needs a pre-existing rule — unsuitable for ad-hoc cards) [L3].
- Raw REST supports it two ways: card PUT carrying `labelIds`, and the bulk route
  `POST /api/boards/:boardId/cards/labels` with `{"cardIds": [...], "addLabelIds": [...]}` — present at v9.88
  AND v12.65 (source-checked 2026-10-30 in cf-89); an unknown label id answers 400 [L4 §Labels].
- Agents have no generic HTTP surface on dev-boards, so parent-label inheritance means a wekan-mcp addition:
  either a `label_ids` optional param on create_card or a small `add_card_labels` tool (bulk route). Same
  ship flow as cf-89: containers/wekan-mcp change → docker-build CI → image pin bump in services/dev values
  (wekan-mcp currently `:v87` there [L13]). Inheritance policy (which parent labels carry over — all, or all
  except Research?) is a plan decision (open question OQ5).

### F6 — Coder → OpenCode agent env vars for the shared test account (card ask, -pr testing context)

- Local template facts [L12]: `coder_agent.main` carries an `env` map (today OPENCODE_BINARY/USERNAME/
  PASSWORD) inherited by every process the agent launches (opencode server, OpenChamber, bash); a
  `startup_script` runs at agent start; the workspace pod's container env is CODER_AGENT_TOKEN only. The repo
  denies agents reading `.env` files (coord variants) / asks (global config) — a deliberate guardrail.
- Coder's documented mechanisms [W6, W7]: the `coder_env` Terraform resource injects per-agent env vars
  (merge strategies replace/append/prepend/error; the `coder_agent` env block wins conflicts);
  `coder_parameter` for user-supplied values; startup scripts for fetch-at-boot patterns.
- Practical options for the single test username/password:
  (a) RECOMMENDED — template change: a Kubernetes Secret in the coder namespace + `coder_env`/container env
      sourced from it (secret stays out of the Terraform file; value lands in workspace state only as a
      reference). Agents consume via `$VAR` in bash (printenv/cat allowed); the playwright MCP session types
      the creds, so the agent must see them — env→context read is unavoidable by design; hygiene = a
      dedicated non-prod test account.
  (b) startup_script pulls from a secret store at boot — Bitwarden CLI (`bw`) is NOT installed in the
      workspace image today; wekan-mcp's server-side login-mint pattern is not reachable from agent sessions.
  (c) `.env` in $HOME — conflicts with the repo's read-deny posture and puts the secret in model context on
      any cat; not recommended.
- Mechanics of "how the agent uses it": bash tool env inherits the agent env (verified pattern:
  OPENCODE_SERVER_PASSWORD flows the same way to code-server/OpenChamber [L12 L235-248]); MCP SERVERS get
  their env server-side (dev-playwright pod env [L13]) — the browser itself needs no creds, the agent logs in
  through the page.

### F7 — Playwright MCP against authenticated apps + ingress enumeration (card ask, -pr testing context)

- Lab deployment [L13]: `mcr.microsoft.com/playwright/mcp:v0.0.83` on the dev cluster via
  `hivetools.mcp.playwright` (streamable-http, `--headless --isolated --allowed-hosts "*" --output-dir
  /home/node/.cache/`), reachable as `dev-playwright`. Running IN-cluster means ingress hosts resolve.
- Official semantics [W9]: three profile modes — Persistent (default, keeps logins), **Isolated** (fresh every
  session; can preload with `--storage-state <file>`), Extension. Storage tools save/restore cookies/
  localStorage/full state to files. Idle-timeout closes the headless browser after 1 h without tool calls —
  with `--isolated`, in-memory cookies die with it.
- Consequence: with today's `--isolated` args there is NO login persistence; every test run logs in fresh
  (navigate → fill → submit with env-provided creds from F6). Alternative: mount/produce a storage-state file
  and drop `--isolated` (chart change; the file is session-secret material — lifecycle needs a decision).
- Ingress/gateway enumeration: the lab's edge is Traefik — IngressRoute CRDs via the `kubernetescrd` provider
  (entrypoint `kube-system-crowdsec@kubernetescrd`); NO ingress-nginx and NO Gateway API objects in the repo
  [L14, grep]. Agents enumerate through the readonly-*-kubernetes MCP surfaces (per-cluster).
- skip-testing precedent: nothing in-repo today (grep). Upstream precedent = annotation-gated test resources:
  helm chart tests use `"helm.sh/hook": test` on Pods/Jobs that `helm test` runs [W10]; ArgoCD has
  `argocd.argoproj.io/hook: Skip`. Suggested shape for the plan: a chart values flag rendering a
  `spencerslab.io/skip-testing: "true"` annotation on the ingress/IngressRoute, honored by the walker — the
  exact key is a follow-up-card decision per the card's own scoping.

### F8 — GitHub Actions draft→ready as unit/integration gates (card ask, -pr testing context)

- Official event facts [W3]: `pull_request` default activity types = opened/synchronize/reopened;
  `ready_for_review` and `converted_to_draft` are opt-in types. Draft PRs do NOT run `pull_request`-triggered
  workflows at all [W4, W5]; pushes to the PR's head branch still fire `on: push` workflows. Workflows also
  skip when the PR has a merge conflict [W3 note].
- Mapping to the card's model:
  - "Draft covers unit tests": to get ANY CI while the PR is draft, unit jobs must ride `on: push` (branch)
    triggers — a pure `on: pull_request` unit workflow will not run until ready_for_review. The repo's render
    test suites (gpt-researcher, llama-swap [L11]) already pair push+pull_request triggers and are the ready
    template.
  - "Ready covers integration tests": a second workflow with `on: pull_request: types: [ready_for_review,
    synchronize]` guarded by `if: github.event.pull_request.draft == false` — the synchronize type keeps it
    re-running on new commits after ready [W3, W5].
  - Pitfalls [W4]: skipped checks report as passed/stale — if such a check is REQUIRED, a draft→ready PR can
    carry a stale pass; prefer types+draft-guard over bare `if:` skips, and keep required-check lists aligned
    with the ready-stage workflow.
- Repo CI today [L11]: aislop.yaml gates every PR-touched file; docker-build.yaml builds (never pushes) on
  PRs and pushes v<run>+branch tags only on main/dev merge — the "PR = build validation, merge = publish"
  split the card wants to extend already exists.

### F9 — Kopia restore into a test namespace (card ask, integration-test context)

- Kopia is absent from this repo: zero matches in grep across all files AND in full git history
  (`git log --all` for kopia: nothing) [L-grep]. The backups stack in-repo = seaweedfs + gitea +
  `backups-appset` (external chart, ownyourio.github.io/SpencersLab); `volsync` appears only in
  services/monitoring values (PVC replication; restic/rclone-family, not kopia).
- Where the lab's kopia actually runs (and its repository password handling) is NOT discoverable from this
  repo → open question OQ2. The card already directs the mechanics into follow-up cards ("we'll need a follow
  up card for the mechanics of both the backup and restore"), so this finding changes nothing in THIS card's
  scope — it only confirms the follow-up cards must start by locating the kopia deployment.
- Restore CLI mechanics when that card lands [W8]: `kopia restore <snapshot-id|path> <target>` restores a
  snapshot tree into a target path (`--snapshot-time` defaults to latest; overwrite flags; `--shallow` for
  placeholder trees); requires `kopia repository connect` with repo credentials first. Seeding a test
  namespace = restore-to-dir → PVC import (or object-store round-trip for DB dumps) — design space for the
  follow-up card.

### F10 — The remaining card bullets with local answers

- **ls/pwd on all coord variants: ALREADY DONE.** All six variants (agent-coord, -local, -pr,
  agent-board-coord, -local, -pr) carry explicit `ls`/`ls *`/`pwd`/`pwd *` allows (cf-88 ruling, 2026-10-30)
  and the generated `.opencode/agents` copies are in sync [L7]. The planner should verify-and-close this
  bullet (and decide whether dev/test/review subagents want the same — they are the ones probing surfaces).
- **Slug auto-accept**: pipeline-kickoff Q1 still mints 2-3 slug suggestions and asks [L6]; board-driven runs
  already derive `cf-<cardNumber>-<type>-<desc>` from card content — change: card-derived slugs skip the
  batched round entirely (the card's exact ask); keep the question for cardless agent-coord runs.
- **Drop the run tag**: boards runs already omit it (STATE kickoff carries card+slug+session_origin, no
  run_tag); pipeline-kickoff still mints `<slug>-<run tag>` worktrees/branches for agent-coord [L6]. Dropping
  the concept outright = kickoff + STATE schema + any skill citing run tags (plan decides scope: card says
  drop it, use slug consistently).
- **Follow-up-card timing** ("after post research, before tests/code"): mechanical — coord creates them at
  that stage using create_card with default_checked; parent-label inheritance depends on F5.
- **Work-complete cleanup** ("move to main/dev worktree, close old branch+worktree"): the pieces exist —
  `session_move` (opencode tool), `worktree_remove`, and local branch deletion (`git branch -d/-D` is allowed
  under the variants' broad `git *` allow; only main-advancing verbs are denied [L7]). Ordering matters:
  move the session OUT of the worktree first, then remove the worktree. Unmerged-branch deletion policy is
  OQ4.
- **-deploy variant + -pr description updates**: no external blockers found. The subagent machinery (launch,
  RESULT handoff, question-tool escalation on cancel) is the existing coord pattern [L20, pipeline-conventions
  skill]; "90% context" handoff = a convention the new role skill states; the card's flow (deploy agent fixes
  → re-review → user-cancel → coord question) composes from existing parts. The heavy lifting it depends on
  (CI draft/ready split, test env restore, playwright login, test creds) is F6-F9 and the card's own
  follow-up cards.

## Contradictions and how to weigh them

1. **"Lists are board-wide" (wekan.fi docs, W11) vs per-swimlane list documents (live probe [L16] + cf-68/89
   source-checks [L2]).** Weigh live API + source: list documents carry one swimlane_id; titles legitimately
   repeat across swimlanes (Context ×3 on AI-Dev). The docs sentence is a legacy-UI simplification (all
   columns visible per swimlane row). Impact: init must always pass `swimlane_id`, and Bucket rules must
   match `swimlaneName` or they cross-fire between same-named lists.
2. **"Draft PRs run unit CI" (card's model) vs GitHub reality (draft PRs trigger nothing on pull_request
   [W4]).** Resolve toward the platform: the unit tier needs `on: push` triggers (or it first runs at
   ready_for_review). The plan should state which reading it ships.
3. **"The repo already runs kopia" (card premise) vs zero kopia in repo or git history.** Weigh repo
   evidence: kopia runs outside this GitOps repo. Does not block this card (mechanics are follow-up cards by
   the card's own direction), but the follow-up cards must start with "locate the kopia deployment".
4. **Rule substitution exists ({listname}, W2) but not for labels (W1).** Tempting read "rules can do
   dynamic labels" is false — substitution covers created-object NAMES and email text only; addLabel is
   id-bound. Per-list rule pairs remain the design.

## Implications for the plan

- **Board provisioning command** (skill or `.agents/commands` entry, idempotent read-then-create): sync
  Planning lists from Backlog titles (missing today: Outside Process, Wekan), then for the target swimlane's
  lists ensure `Bucket: <title>` labels (color `darkgreen` — the board's "Bucket Color" swatch) + the two
  rules each, and ensure Provider: API / Provider: Local labels. Verify with get_board/list_rules. Include a
  "re-run after Backlog grows" mode — that is the update path the card asks for. Do NOT delete lists absent
  from Backlog (card says so explicitly).
- **Two loop tasks**: pipeline-worker gains a Provider: API filter sentence (and stays the API-provider
  model); a new `.agents/loops/` file for Provider: Local with `model: gpu-ai/<code-tier-model>` (OQ3).
  Pickup-walk label filter is skill text; cards with no Provider label need a default policy (OQ7).
- **Always-Allow**: human toggles permissionAutoAccept on both tasks once (documented in the runbook; it
  survives loop re-sync); follow-up card records the goal of dropping the need (card ask #1).
- **No-cards exit**: boards skill no-op path = marker write → `opencode api patch /api/session/<id>
  {"archived": true}` → stop, never ask. No plugin change needed (question-notify suppression is independent).
- **wekan-mcp work**: label-on-card capability (create_card `label_ids` and/or `add_card_labels` via the bulk
  route) + version bump + dev values pin — prerequisite for parent-label inheritance on follow-up cards.
- **Coord skill edits**: slug auto-accept for card-derived slugs; run-tag removal; follow-up-card creation
  point (post-research/pre-test); work-complete session_move + worktree_remove + branch cleanup; `-deploy`
  role skill + `-pr` description updates per F10.
- **CI split** belongs to the follow-up testing cards, but THIS card's -pr description updates should cite
  the F8 trigger shapes (push=draft-era unit; ready_for_review+synchronize+!draft=integration).
- **Env vars** for the shared test account: charts/coder template change (k8s Secret → coder_env) +
  workspace rebuild; the follow-up testing cards consume `$LAB_TEST_USER/$LAB_TEST_PASSWORD`.

## Open questions (best guess + impact)

- **OQ1** Does the dev-boards service user have board-admin on AI-Dev (create_label/create_rule gate)?
  Best guess: yes (cf-68/89 shipped admin-gated tools for this surface, and board structure reads work);
  verify with one probe call during planning. Impact: if no, provisioning runs via admin-global-wekan or a
  one-time human grant.
- **OQ2** Where does the lab's kopia run, and how do CI/test namespaces get repo credentials? Best guess:
  outside this repo (NAS or a second cluster); user answers in the Plan gate. Impact: follow-up cards only.
- **OQ3** Initial model for the Provider: Local loop task? Best guess: `gpu-ai/qwen3.8-flash-next-strata`
  (today's code-tier equivalent of openrouter/qwen3.8-flash; catalog churns — confirm at plan time). Impact:
  one frontmatter line.
- **OQ4** Work-complete cleanup of an UNMERGED ticket branch? Best guess: remove the worktree immediately,
  delete the branch only after the PR merged (until then it is the only copy of the work). Impact: exit-step
  wording in the coord skill.
- **OQ5** Which parent labels do follow-up cards inherit? Best guess: ALL parent labels (card says "include
  the parent's labels", unqualified) — including Pipeline:/Provider:/Bucket:; Research label inclusion would
  change flow shape, so likely exclude Research; user confirms at Plan gate. Impact: filter list in the
  create-with-labels call.
- **OQ6** Bucket rule scope: Planning only (card text) vs all swimlanes eventually? Best guess: Planning
  only for now; the provisioning command takes the target swimlane as a parameter so it extends later.
- **OQ7** Cards carrying NO Provider label: which task takes them? Best guess: the API task (OpenRouter)
  keeps today's behavior (unlabeled = default), the Local task only takes explicitly-labeled cards —
  preserves backward compatibility. Impact: one pickup-walk condition per task.
- **OQ8** The one run that "asked if it should close out": which surface asked is unknown (no logs); best
  guess: empty-pickup path flowing into kickoff wording. Fix is the same either way (explicit never-ask +
  archive), so this does not block.

## Adjacent

- OpenChamber scheduled tasks also support `targetSessionId` (run the prompt into an existing session) and
  goal/token-budget fields [L19 existing-session.js, runtime.js] — a future hook if loop runs should resume a
  session instead of minting one; not needed for this card.
- The Farm swimlane mirrors Backlog and carries a typo list "Outside Proccess" [L16] — the provisioning
  matcher should compare case-insensitively and never auto-rename human lists.
- Pipeline: Local/CICD/Context labels already exist on AI-Dev [L16] — the parallel-pipeline lock surface is
  already label-populated; Provider: labels are additive and orthogonal (routing, not locking).
- wekan-mcp in services/dev is pinned `:v87` while cf-89 built v102 [L13] — the label-tool chunk should ride
  the next image bump and update the pin deliberately.

## Sources

Local (repo/live): L1 containers/wekan-mcp/wekan_mcp/server.py · L2 skills/wekan-mcp/references/call-shapes.md ·
L3 skills/wekan-api/references/wekan-mcp-ops.md · L4 skills/wekan-api/references/rest-api-overview.md ·
L5 .agents/plans/2026/2026-10-dep-wekan-v12-upgrade/ (checkItem root cause L316-364) ·
L6 .rulesync/skills/pipeline-kickoff/SKILL.md · L7 .rulesync/subagents/agent-*coord*.md (perm blocks) ·
L8 .opencode/plugin/question-notify/index.ts · L9 .agents/loops/pipeline-worker.md ·
L10 scripts/agent-board-coord-gate.sh · L11 .github/workflows/{aislop,docker-build,gpt-researcher-render-tests,llama-swap-tools-tests}.yaml ·
L12 charts/coder/coder-templates/kubernetes/main.tf · L13 services/dev/prod/values.yaml ·
L14 services/proxy-local/prod/values.yaml · L15 .agents/plans/2026/2026-10-chore-board-tick-cleanup/RESEARCH.md ·
L16 live dev-boards probe 2026-10-31 (board/swimlanes/lists/labels) · L17 live `opencode api get /openapi.json`
(this host; PATCH /api/session/{id} archived) · L18 /home/coder/.config/openchamber/projects/*.json ·
L19 OpenChamber 2.5.2 server source (/home/coder/.nvm/versions/node/v26.5.0/lib/node_modules/@openchamber/web/server:
scheduled-tasks/{loops,runtime,service}.js, projects/project-config.js, permission-auto-accept/*,
openchamber-sessions/archive-store.js, @opencode/schema) · L20 .rulesync/skills/pipeline-push-pr/SKILL.md
Web (fetched 2026-10-31): W1 github.com/wekan/wekan main server/rulesHelper.js (raw) · W2 same repo
models/lib/ruleVarsSubstitute.js (raw) · W3 docs.github.com events-that-trigger-workflows (pull_request types) ·
W4 github.com/orgs/community/discussions/25722 · W5 stackoverflow.com/questions/73948443 ·
W6 coder.com/docs/admin/templates/extending-templates/environment-variables ·
W7 registry.terraform.io coder provider: coder_agent/coder_env (search-verified) ·
W8 kopia.io/docs/reference/command-line/common/restore/ · W9 playwright.dev/docs/getting-started-mcp ·
W10 helm.sh/docs/topics/chart_tests/ · W11 wekan.fi/docs (board-wide lists sentence)
