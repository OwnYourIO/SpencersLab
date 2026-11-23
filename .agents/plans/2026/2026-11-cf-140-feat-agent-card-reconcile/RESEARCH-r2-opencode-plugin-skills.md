# RESEARCH R2 — OpenCode plugin-writing skills + the V2 plugin API AD-140 must target

Ticket AD-140 (`cf-140-feat-agent-card-reconcile`) · research sibling R2 · 2026-11-23
Scope (from the card): (a) does a SKILL exist that teaches writing OpenCode plugins — installed
here or published upstream; (b) what is the authoritative current plugin-API shape a new plugin
must target (V2 docs, version-resolved); (c) failure modes. Deliberately NOT written to
`RESEARCH.md` (three siblings run concurrently; the coordinator merges).
Prior grounding honored: `EXPLORE-plugins.md`, `EXPLORE-session-api.md` (cited as [L1]/[L2]).
Every claim carries a bracketed source from the numbered list at the bottom; local probe evidence
is marked [P].

## TL;DR

1. **Skill exists — but as an index, not a guide.** The `/opencode` skill is official, bundled
   inside the `@opencode/cli` binary (v2.3.2 here); its Plugins section only points at three V2
   docs URLs. Nothing in this repo teaches plugin authoring beyond the four live plugins and the
   EXPLORE files. [1][2][P1]
2. **Upstream: several plugin-authoring skills exist, and all the mature ones teach the V1 API**
   (`@opencode-ai/plugin`, Hooks-object entrypoint) that "does not run in V2". Exactly **one**
   V2-targeted authoring skill was found (thin, pinned to 2.0.20). An honest near-negative. [3][13-16]
3. **The live docs target 2.4.x (released today); this repo runs 2.3.2 and pins facts to 2.1.4** —
   but the event vocabulary is near-identical across all three (only +5 events 2.1.4→2.3.2, 0
   removed), and the repo's capability-gated seams cover the real deltas (`instructions.entry`,
   per-tool `codemode` option, `ctx.experimental.automation`). [7][9][10][11][P2]
4. **Every failure mode the repo recorded has a matching upstream issue**, including the
   multi-instance `setup()` fan-out (#56290, open) and a brand-new open issue that plugin tool
   registrations may not reach the model catalog since 2.3.2 (#65842) — while this ticket's own
   claim worked on 2.3.2 today. [14-17]
5. **Recommendation: do NOT author a plugin-writing skill inside AD-140** — load `/opencode` +
   the cited V2 doc pages in plugin chunks; keep the repo-specific plugin law in the EXPLORE/plan
   homes; optionally propose a small vendored skill on a follow-up card.

## 1. Installed-here inventory — what already documents plugin authoring

**The `/opencode` skill (official, binary-bundled).** It is NOT a file in this repo: `.agents/skills/`
(third-party vendored, 70 skills), `.opencode/skills/` (rulesync-generated, pipeline contracts) and
`skills/` (repo-owned) contain nothing opencode-plugin related [P1]. The skill loads from
`skill://opencode` — its full SKILL.md text is embedded in the installed CLI binary
(`@opencode/cli` v2.3.2, `…/lib/node_modules/@opencode/cli/bin/opencode.exe`, string-probed) [P1].
Its **Version policy** mandates V2 docs only, with V1 consulted solely for explicit migration
questions. What its Plugins section points at — the whole of its plugin guidance:

- full plugins guide → `https://opencode.ai/docs/build/plugins` (hooks, transforms, tools, context
  capabilities, package entrypoints);
- TUI plugins → `https://opencode.ai/docs/build/plugins/cli`;
- shared methods/events → `https://opencode.ai/docs/build/plugins/rpc`;
- V1→V2 plugin migration → `https://opencode.ai/docs/migrate-v1` + the plugin migration guide;
- machine-readable index → `https://opencode.ai/docs/llms.txt`. [1][2]

**What it does NOT cover:** no inline API reference (it delegates every answer to a docs fetch), no
version-capability matrix (nothing about 2.1.4-vs-2.3.2 builds), nothing about multi-instance
plugin loading, storage-key scope, dedup law, degrade-never-throw style, the singular
`.opencode/plugin/` layout, or this repo's pin families. It is an index + version policy, not an
authoring skill. **No second bundled skill mentions plugins** (binary grep found no other
plugin-named skill content) [P1].

**Everything else in-repo:** AGENTS.md documents only the *placement* law (`.opencode/plugin/` is
hand-managed, never rulesync-generated) and the four plugins' behavior summaries; the pipeline
skills reference plugins only as permission boundaries ("never hand-edit"; the dev/test skills
name `.opencode/plugin/*` as scope) [P1]. The real local plugin-authoring knowledge is the
**four plugins themselves** (2767-line pipeline-locks, 856-line board-context, question-notify,
aislop-gate — their header comments are the de-facto reference) plus `EXPLORE-plugins.md`, which
already encodes the API-shape facts D26–D32 [L1 §0–6]. Net: this repo's plugin expertise is
operational and per-file, not skill-shaped.

## 2. Upstream — published plugin-authoring skills (verified, with API target)

| Source | Skill | API target | Verdict for this repo |
|---|---|---|---|
| `igorwarzocha/opencode-workflows` → `create-opencode-plugin` [13] | gated workflow + auto-generated hooks/events refs | **V1** (`@opencode-ai/plugin`, function→Hooks, `chat.params`, `auth` hook) | Stale entrypoint; the "regenerate refs from the installed SDK" gate is a pattern worth stealing |
| `fredcamaral/drawers` → `.claude/skills/opencode-plugin-dev` [14] | deep references (hooks.md, events.md, tui.md, gotchas) | **V1** (same Hooks model, `tool()` helper, `client.tui`) | Rich but would generate V1 code that V2 refuses to run |
| `sveltejs/ai-tools` → `.agents/skills/writing-opencode-plugins` (internal) [15] | types-are-truth, module shapes, review/testing checklists | **V1.18 object shape** (`{id, server}`, `@opencode-ai/plugin`) | Engineering rules (stable id, namespaced KV keys, bounded idempotent cleanup, never depend on load order) are API-agnostic and still correct for V2 |
| `different-ai/openwork` → `.opencode/skills/create-plugin` [16] | in-repo internal | V1-era | Not reusable |
| `hoshinoht/hoshi-opencode2` → `skills/opencode-plugin-dev` [16a] | operational: installs, pins, hot-reload, log/verification | **V2** (`@opencode/plugin`, OpenCode 2.x, written against 2.0.20) | The ONLY V2-targeted skill found; thin (~1 page); several claims version-stale (drifted `ctx.catalog` vs `ctx.model` naming was 2.0.x) |
| registries `skillsmp.com`, `skillsdirectory.com` [17] | mirrors of the above ("writing-opencode-plugins, Grade A", "opencode-plugin-dev") | mirror the V1 set | Discovery surface only; nothing V2 beyond hoshi |

**Ecosystem context:** `awesome-opencode/awesome-opencode` (~11k stars) curates *runtime* plugins
(not authoring skills) and hosts an "OpenCode V1 Bridge" discussion — evidence the ecosystem is
actively absorbing the V1→V2 plugin break [18]. Upstream states it plainly: V1 plugin
implementations do not run in V2; "Plugins made for OpenCode 1 need an update" (v1.19.6 release
note) [3][12]. Scaffolds on npm: `create-opencode-desktop-plugin` (GUI-only, official pattern),
`@involvex/create-opencode-plugin` (0.0.3, tiny community), `create-opencode-workspace` [19].
Community *tutorials* exist (e.g. "How to write an OpenCode plugin with the v2 API", daily.dev,
2026-10-16) but are not skills [20]. Official authoring prose: the V2 docs set [2-6] plus
`packages/plugin/src/README.md` in `anomalyco/opencode@dev` — the canonical in-repo V2 Promise-API
README [11a].

**Skill exists — explicit answer:**
- Installed here: **YES** — the bundled `/opencode` index skill (binary-embedded, official) [1][P1].
- Published, V1-era: **YES, several mature ones** [13-16].
- Published, V2-correct AND substantial: **NO** — one thin operational skill [16a]; the official
  docs are the only complete V2 authoring source [2-6][11a].

## 3. The V2 plugin API card-runner must target (version-resolved)

**Version baseline (resolved, not assumed):** live build **v2.3.2** (scout probe; `opencode
--version` re-confirmed on this host today) [P3]; npm `@opencode/plugin` `latest` is **2.4.1**,
published today, with 2.4.0 also today (2.1.4 = 2026-10-23, 2.2.0 = 2026-10-27, 2.3.0 = 2026-11-13,
2.3.2 = 2026-11-18) [10][P2]. The live docs therefore describe a **superset** of the 2.3.2 runtime —
capability-gating remains mandatory (house style already, [L1 §0]).

**Entrypoint + discovery.** V2 reads `id` and `setup(ctx)` from the default export; the docs'
canonical form is `Plugin.define({ id, async setup(ctx) })` from `@opencode/plugin`, but the plain
object the repo's four plugins ship is the same contract (`Plugin.define` adds typing, not runtime
magic — the dual V1/V2 export doc spells out that "V2 reads the default export's `id` and
`setup()`") [2][3]. **Discovery: V2 loads from BOTH `.opencode/plugin/` and `.opencode/plugins/`;
the docs explicitly recommend plural "for V2 files"** [5] — resolving the singular-vs-plural
question raised against the docs examples: the repo's placement is legal legacy-V1 layout; a new
`card-runner` may stay singular (zero re-pin) or move plural (docs-conformant) — decide once, see
OQ-R2-2. Config `plugins` array: entries load packages/dirs; `-<id>` disables by declared id (the
repo's `-local.question-notify` toggle, documented), `*` and `.*` wildcard removals supported;
configured local paths must be DIRECTORIES (a single-file path is skipped with a log warning);
changes under watched config dirs reload automatically [4][5]. Global plugins:
`~/.config/opencode/plugins/` [4].

**ctx surface.** "The plugin context is essentially an OpenCode server client" — there is no
separate `ctx.client` on server plugins (`ctx.client` exists only on TUI/GUI parts) [2][6]. Domains
(shipped in 2.3.2 unless noted): `app`, `location` (`directory`, `project{id,directory,canonical}`),
`options`, transforms for `provider/model/agent/command/integration/mcp/reference/skill/tool/vcs/
worktree/websearch`, reads for `session/storage/event/permission/plugin/credential/websearch/vcs`,
hooks on `session/permission/tool/shell`, `aisdk` hooks, `rpc` (register + typed self-call) [2][6][P2].
**There is no `ctx.prompt` or `ctx.summarize`** — the surfaces the ask asked about resolve to:
`ctx.session.prompt` (admits a user prompt — the repo's wake path), `ctx.session.compact` (requests
compaction), `ctx.session.generate` (transient generation in a session), and `ctx.experimental.generate.text`
(`ctx.generate.text` is deprecated in its favor) [2].
`ctx.session` full shape in 2.3.2 types: `list/create/get/remove/context/prompt/generate/command/
synthetic/compact/interrupt/update/move/switchAgent/switchModel` + experimental `wait` +
`instructions.entry.put/list/remove` (the keyed-note seam: **absent in 2.1.4 types, present in
2.3.2** — exactly the repo's capability-gated observation) [P2]. Session creation/prompting
server-side is fully documented: `ctx.session.create({title, …})` → `ctx.session.prompt(...)`;
the HTTP route (`POST /api/session`, `POST /api/session/<id>/prompt`) is the same surface the
dispatcher spawn contract already uses [L2 §1][2]. `ctx.session.update` accepts session writes
(including `metadata`/`archived` per the repo's proven note; docs list `update` with title/
permissions and it is the same typed client call) [2][L2].
New in **2.4.1 only**: `ctx.experimental.automation.{create,list,delete}` (plugins manage
automations — the first-class scheduling primitive; NOT reachable on the live 2.3.2) [11][12][P2].

**Hooks.** Session hooks: `fork`, `prompt` (pre-admission, mutable draft; "transforms input, no
typed rejection API; retry-safe law"), `context`, `compaction` (set `event.result = {summary}` to
record the summary yourself and skip the model call), `generate`, `title`,
`experimental.model.resolve`, `model.request`, `http.request/response`, experimental ws hooks,
`retry`; plus `permission.hook("evaluate")`, `shell.hook("create.before")`,
`tool.hook("execute.before"/"execute.after")` [2]. **Multiple plugins may register the same hook;
OpenCode runs them in registration (plugin) order** [2] — so the repo's "one process-wide
compaction hook" is a *design ruling* (blast-radius control), not an API limit; nothing upstream
would force a second registration to exist [2][L1 §1.8]. New in the official plugin README:
`session.hook("experimental.idle")` — fires just before a session goes idle (not after
interrupt/failure/control-only work; `event.background` lists running shells/subagents) — a
hook-shaped idle signal for the future, experimental and 2.4.x-docs-era [11a].

**Events — vocabulary AND emission, version-resolved.** Type vocabulary (authoritative source:
`@opencode/schema` per-version `event-manifest.d.ts`, downloaded and diffed) [P2][9]:
- 2.1.4: 121 event literals → 2.3.2: +5 (`artifact.updated`, `experimental.mcp.event`,
  `experimental.mcp.subscription.changed`, `persistent-pty.updated`, `session.step.first-token`),
  **0 removed** → 2.4.1: +1 (`experimental.job.updated`).
- **`session.updated` never existed in the V2 vocabulary** (checked all three versions) — the repo
  listener for it was speculative; the real events are `session.metadata.updated` (+`session.renamed`,
  `session.usage.updated`, `session.viewed`, `session.archived`…) [P2][9][L2].
- `session.idle` / `session.status` **exist in every version's vocabulary** but are classified
  **`durability: "ephemeral"`** (like `form.*` and `permission.*`), versus `durable` for
  `session.execution.*`, `session.created/deleted/archived`, `session.compaction.failed`,
  `session.tool.*`, `session.inbox.*`, `session.metadata.updated` [P2].
- No `question.*` events exist in any version — but `form.created/replied/cancelled` (all three
  versions) are the documented question-round-trip events (the `question` tool "pauses execution
  and presents … questions" [7]) — feed this to the question-detection sibling.
- **Contradiction to carry, not smooth:** the repo probe found `session.idle|status` never EMITTED
  (headless Coder host, v2.1.4) [L2]; the upstream #65834 reporter on desktop 2.2.5/2.0.32 observed
  5–7 duplicate `session.idle` deliveries [15]; the docs' own migration example teaches
  `session.idle` as the "session completed" signal [5]. Vocabulary membership ≠ emission; emission is
  host/version dependent. Settle on the live host (§OQ-R2-3).

**Tools + the Code-Mode question.** V2 registers tools via `ctx.tool.transform(editor => editor.add({
name, description, input(JSON Schema), options, execute }))` — the V1 `tool()` map/helper is the
migration source, not the API [3][2]. **Why `pipeline_*` are Code-Mode-only:** Code Mode (`execute`)
is the default reach path for catalog tools — the tools docs state that denying `execute` with `*`
"removes Code Mode" and the tools it would reach are then "listed as direct tools", and MCP servers
opt out with `codemode: false` [7]. On the type surface, **2.3.2 has no per-tool `codemode` option at
all** (the flag exists only on MCP server config and as a job `kind`) [P2]; the per-tool
`options.codemode` (bool, then the 2.4.0 object `{pinned?, description?, input?, output?}`) shipped
in the 2.4 line [11][12]. Conclusion: **D29 holds on the live build** — plugin tools are catalog/
Code-Mode-only on 2.3.2; a direct-tool path exists only after upgrading to ≥2.4 (and the docs'
"reachable ONLY through Code Mode" phrasing is the designed default, not a bug).
Call-identity change to design around: **since 2.3.1, each nested call inside a Code Mode program
gets its OWN call ID** in plugin hooks/traces (was: the outer `execute` call's id) — intended
change #64324 [12][16]. Any dedup/claim key that rides tool-call ids must tolerate both shapes.

**RPC.** `Rpc.define` (JSON Schema or any Standard-Schema) → `ctx.rpc.register(Acme, impl)` in
setup; callable over HTTP via `client.rpc(Acme)` and from other plugin parts; `events.on/subscribe`
with prefixed types (`rpc.<id>.<event>`), each carrying `location`. Two laws matter for the
reconciler's wake design: **"Event subscriptions are live only — disconnected subscribers miss
events"**, and external clients receive events from every location (check `event.location`) [6].
RPC is the documented path for scheduled/wake *methods* (an external scheduler calling the plugin);
today's wake mechanism (`ctx.session.prompt` on the tracked dispatcher session) remains the
documented prompt path [2][6][L1 §1.4].

## 4. Failure modes (docs + upstream issues + repo-recorded, cross-checked)

1. **Multi-instance loading / duplicated deliveries.** Upstream #56290 (OPEN since 2.0.30): in one
   long-lived server process `setup()` runs **once per loaded location/client connection**; every
   instance's `ctx.event.subscribe()` gets every event → N× side effects; docs "do not mention
   multi-instance semantics"; reported workarounds: a claim map on `globalThis`, or ignoring events
   whose `location` isn't the instance's own `ctx.location` [14]. #65834 (closed as duplicate of
   #56290): standalone `opencode run --standalone` = one setup; desktop/TUI long-lived hosts =
   6–15 setups [15]; #54140: instances pile up across config reloads [15]. This is the upstream
   face of the repo's recorded hazards (one-server-per-location D27, two-servers-one-db fan-out,
   the once-mark guard that fails across processes) [L1 §0/§2.1][L2 §9] — the consume-once-claim law
   stays load-bearing, and OpenChamber/desktop hosts make fan-out worse than headless probes show.
2. **Load/parse errors.** Docs: a configured single-file plugin path is skipped with a warning [5];
   unknown `event.subscribe` `types` names are ignored with a server-log warning [2]; a
   self-updating package that fails to load keeps running the previous version [4]. The plugin
   README: setup cleanup is awaited on unload/replacement; 2.3.0 fixed cleanup-failure blocking
   replacements [11a][12]. The hoshi V2 skill adds two operational traps: OpenCode does NOT install
   dependencies for local plugin *packages* (missing install → `Cannot find package
   '@opencode/plugin'` in the log, plugin state `failed` — visible via `GET /api/plugin`), and a
   running server **hot-reloads plugin files into live sessions** — editing plugin source is a live
   change [16a][8]. Repo-consistent: every `.ts` under `.opencode/` is treated as a plugin entry,
   which is why test files live outside `.opencode/` [L1 §9]; a plugin that throws in `setup`
   wedges an ephemeral location load (D31 — degrade-never-throw stays the house law; upstream has
   no doc contradicting it, and #65834's own repro plugin wraps everything defensively) [L1][15].
3. **Plugin tools not reaching the model (OPEN, current).** #65842 (filed today): on 2.3.2/2.4.0 a
   published plugin's registered tools are absent from every session's tool catalog (desktop +
   headless) while passive hooks keep working [17]. This repo's live counter-evidence: the AD-140
   coord claimed via `pipeline_claim` through Code Mode TODAY, successfully [P3][STATE.json] — so
   the issue's path (global package plugin, desktop) does not obviously match this host. Treat as
   a pre-ship verification duty for card-runner's tool legs (re-prove `tools.pipeline_*` on the
   exact build it ships), not a blocker.
4. **Tool-hook delivery around Code Mode.** #65742 (closed, cannot-reproduce): nested Code-Mode
   calls DO fire `tool.execute.*` hooks on 2.3.2 — but with their own call IDs since 2.3.1 [16].
   The repo's degraded card-details leg ("no block on the claim answer" today) is consistent with
   id-shape breakage or hook filtering, not hook absence — re-key the claim-time leg on the nested
   call id + sessionID, tolerate both spellings [16][STATE.json][L1 §2.2].
5. **Storage key shapes.** API: `get/set/remove/scan(prefix, limit, cursor)`; values are JSON;
   "Plugin storage is scoped by this ID" (the declared plugin id) [2][3][5] — and **project/location
   scoping is NOT specified in the docs**. The repo carries two conflicting readings: D26 "plugin-id
   + project-id scoped, shared across worktrees" (locks) vs "keyed by plugin id alone — visible
   fleet-wide" (question-notify) [L1 §0/§3.3]. Both agree the namespace is derived from the DECLARED
   id → a rename orphans all state (OQ-2 keep-vs-rename stays load-bearing). The disagreement needs
   a two-project live probe (OQ-R2-4). Key-shape round-trip law already proven in-repo:
   `board-context`'s once-mark reads ONLY `typeof value === "number"` — if the store returns a
   stringified/boxed value the guard silently fails; treat every read with a tolerant decode [L1 §2.1].
6. **The "one process-wide hook" constraint.** Upstream: multiple registrations are explicitly
   allowed and ordered [2] — the constraint is the repo's own blast-radius ruling (one compaction
   rewrite for every session in the location) plus the T15 creep-back pin that keeps exactly one
   file owning the compaction leg [L1 §1.8]. Nothing upstream forces or forbids it.
7. **Logging visibility.** The hoshi skill claims plugin `console.*` output is invisible in service
   mode and recommends plugin-owned log files [16a]; the repo's degrade-line convention greps
   `opencode.log` (`role=server`) [L1 §0][8]. Both can be true if only stderr/structured log lines
   are captured; settle with one grep on the host that serves live board runs (same probe as OQ-1).

## Contradictions and how to weigh them

| Clash | Weighing |
|---|---|
| Docs examples (`.opencode/plugins/`) vs repo's working `.opencode/plugin/` | Resolved: migrate guide states BOTH are discovered, plural recommended for V2 files [5]. Cosmetic; decide once for card-runner (keep singular = zero re-pin; plural = docs-conformant). |
| `session.idle`: never emitted (repo v2.1.4 probe) vs emitted ×5-7 (desktop #65834) vs taught as the idle signal (docs example) | All true in their hosts. Emission is host/version dependent; timestamps stay the primary liveness signal (repo doctrine), events as accelerators [9][15][L2]. |
| Docs feature set vs live 2.3.2 | Docs = 2.4.x superset (released today). Capability-gate everything newer; the repo's existing seams (`ctx.storage`, `entry.put`, optional `types`) are the proven pattern [P2][10][12]. |
| #65842 "plugin tools missing" vs this repo's working Code-Mode tools today | Trust the live counter-evidence for this host but verify on the shipping build; do not let the open issue veto the design [17][P3]. |
| Storage scope: docs "scoped by ID" vs repo D26 "+project-id" vs repo qn "fleet-wide" | Underdetermined upstream — genuine open probe item, not a doc question [3][L1]. |

## Implications for the plan (what C-chunks should say differently)

1. **Plugin chunks must load `/opencode` and fetch the V2 pages** — server guide, RPC guide,
   plugins-config page — as their API ground (cheapest correctness; the skill itself instructs
   fetching them) [1][2][6][4]. Add the two URLs to the plan's Commands/Skills notes.
2. **Placement decision** (singular vs plural dir) is now a documented free choice [5]; pin one in
   DECISIONS.md; also pin `card-runner`'s **id** permanently (state namespace rides the id) [3][L1].
3. **Dedup keys for tool-hook legs must not assume the outer-execute call id** (2.3.1 change); use
   `(sessionID, tool, nested-call-id)` tolerant of both shapes [12][16].
4. **Keep the consume-once claim pattern** for every event-driven leg — now justified upstream
   (#56290 open, docs silent) [14]; consider `globalThis`-map dedup *within* a process plus
   ctx.storage claims *across* processes; filter foreign-`location` events where the payload
   carries location [14][6].
5. **Version posture**: author against the 2.3.2 type surface (not the docs' 2.4.x), capability-gate
   `instructions.entry` (present), per-tool `codemode` (ABSENT → tools stay Code-Mode-only),
   `experimental.automation` (ABSENT). Re-stamp the capability matrix if the host moves to ≥2.4.
6. **Do not import from plugin files being replaced** (dual-registration stays the law) — docs never
   mention it; it's a repo-discovered loader behavior [L1 §0].

## Recommendation — should AD-140 author its own plugin-writing skill?

**No, not inside this ticket.** Reasons, honestly weighted:

- The generic API half is well-covered upstream (official V2 docs + bundled `/opencode` index +
  the in-repo plugin README) — writing-skills explicitly says don't create skills for standard
  practice well-documented elsewhere, and its Iron Law demands a failing-test-first baseline this
  ticket has not run. [1-6][11a][21]
- The repo-specific half (never-throw law, amend-field tolerance, dual-registration import rule,
  multi-instance dedup, id-permanence, storage ambiguity, version seams) is ALREADY written down in
  `EXPLORE-plugins.md` §0/§6 and FRICTION, which every AD-140 agent reads at run start — the bus
  already carries it. Duplicating it into a skill now creates a third normative home (exactly the
  drift the N3 single-home greps fight). [L1]
- The honest gap ("no mature V2 authoring skill exists upstream") is real but is an *upstream* gap;
  the lab's cheapest fix is a follow-up card (`Follow-up cards created` is unchecked on AD-140, so
  the protocol applies): propose a small vendored `opencode-plugin-v2` reference skill seeded from
  EXPLORE-plugins §0/§6 + this file, promoted only when a SECOND ticket touches plugin code —
  at which point writing-skills' TDD-for-skills can micro-test it against a real launch.
- One cheap adoption anyway: steal the community skills' best meta-pattern — **generate the API
  reference from the installed `@opencode/plugin` .d.ts** [13][14][16a] — as a plan note: card-runner
  chunks verify surfaces against `node_modules`-style dist types of the *installed* build, exactly
  as this research did [P2].

## Open questions (none block planning; all are live-probes, not web questions)

- **OQ-R2-2**: keep `.opencode/plugin/` (singular, zero re-pin) or move `card-runner` to plural
  (docs-preferred)? Both load [3]; one-line DECISIONS entry needed (coord-owned).
- **OQ-R2-3**: does the live OpenChamber-serving host emit `session.idle`/`session.status` on
  2.3.2 (ephemeral class; desktop hosts demonstrably emit idle)? Probe: a 24 h subscribed logger +
  the existing log grep; until answered, timestamp freshness stays the primary busy/finish signal.
- **OQ-R2-4**: ctx.storage scope — write key from project A, read from project B on one server
  (settles the D26-vs-qn contradiction [L1]).
- **OQ-R2-5**: applicability of #65842 (plugin tools missing since 2.3.2) to this deployment —
  already contradicted by today's working `pipeline_claim`, but re-prove every card-runner tool
  leg on the shipping build.
- **OQ-1 (carried from [L1])**: which board-context degrade leg fires on the live host — the
  console/stderr visibility question (§4.7) rides the same probe.

## Adjacent (not core R2)

- `form.created/replied/cancelled` events + the documented `question` tool are the right upstream
  leads for the unanswered-question sibling round (no `question.*` events exist) [7][9].
- `ctx.experimental.automation` (2.4.1) is the first-class scheduling door the hourly-tick design
  should keep an eye on after the host upgrades; `session.hook("experimental.idle")` is the
  hook-shaped idle signal to re-evaluate then [12][11a].
- The 2.4.0 async-plugin-loading note matters for wake timing: right after startup, plugin-supplied
  catalogs may be partial; long-lived clients refresh on `*.updated` events (e.g. `plugin.updated`,
  in the vocabulary since all probed versions) [12][9].

## Sources

Official docs (V2, fetched 2026-11-23 unless noted):
1. `/opencode` bundled skill (SKILL.md embedded in `@opencode/cli` v2.3.2 binary) — version policy + plugins index section.
2. https://opencode.ai/docs/build/plugins/server — full V2 server plugin API (ctx domains, session/tool/permission/shell hooks, events `types` filter, transforms).
3. https://opencode.ai/docs/build/plugins — building/parts/load/publish (entrypoint, `Plugin.define`, discovery).
4. https://opencode.ai/docs/plugins — plugin configuration/discovery/control/manage/reload (`-` disable, wildcards, auto-reload, package self-update).
5. https://opencode.ai/docs/build/plugins/migrate-v1 — V1→V2 plugin migration (V1 does not run in V2; both discovery dirs; storage scoped by id; hook table; `session.idle` example).
6. https://opencode.ai/docs/build/plugins/rpc — plugin RPC (define/register/call/events; live-only subscriptions; location on events).
7. https://opencode.ai/docs/tools — built-in tools incl. Execute/Code Mode default visibility, `question`, `subagent`.
8. https://opencode.ai/docs/troubleshooting — logs (`role=server`), service files, issue home `github.com/anomalyco/opencode`.
9. https://opencode.ai/docs/openapi.json — `V2EventEncoded` (101 variants; no `session.updated`/`session.error`; `form.*`, `session.idle/status` present).
Community skills / ecosystem:
13. https://raw.githubusercontent.com/igorwarzocha/opencode-workflows — `create-opencode-plugin` SKILL.md (V1).
14. https://github.com/fredcamaral/drawers — `.claude/skills/opencode-plugin-dev/SKILL.md` (V1, deep refs).
15. https://github.com/anomalyco/opencode/issues + https://raw.githubusercontent.com/sveltejs/ai-tools/main/.agents/skills/writing-opencode-plugins/SKILL.md (V1.18 object shape) — and issue #56290 (open, setup-per-location N× events; #54140 reload pile-ups).
16. https://github.com/anomalyco/opencode/issues/65742 (closed; nested-call ids since 2.3.1, #64324) + https://raw.githubusercontent.com/hoshinoht/hoshi-opencode2/HEAD/skills/opencode-plugin-dev/SKILL.md (the one V2 skill; 16a).
17. https://github.com/anomalyco/opencode/issues/65834 (closed-dup of #56290; desktop multi-setup) and issues/65842 (open; plugin tools missing since 2.3.2). Registry mirrors: skillsmp.com / skillsdirectory.com entries for the above.
18. https://github.com/awesome-opencode/awesome-opencode — runtime-plugin awesome list (~11k stars); V1-Bridge discussion.
19. npm registry search — `create-opencode-desktop-plugin`, `@involvex/create-opencode-plugin`, `create-opencode-workspace`; `@opencode/plugin` latest 2.4.1.
20. daily.dev "How to write an OpenCode plugin with the v2 API" (2026-10-16) — community tutorial (not a skill).
21. `/writing-skills` skill (installed, superpowers) — skill-creation criteria + Iron Law.
22. https://developers.cloudflare.com/agents/harnesses/opencode/ — third-party official docs using V2 `Plugin.define` + `ctx.skill.transform` skill registration.
Version/contract evidence (downloaded & diffed):
10. https://registry.npmjs.org/@opencode/plugin — dist-tags latest 2.4.1; publish dates 2.1.4/2.2.0/2.3.0/2.3.2.
11. `@opencode/schema` tarballs 2.1.4/2.3.2/2.4.1 — `event-manifest.d.ts` (durable vs ephemeral classification) + `@opencode/plugin` dist 2.1.4/2.3.2/2.4.1 (SessionDomain surface, `instructions`/`wait`, `codemode` placement).
11a. https://raw.githubusercontent.com/anomalyco/opencode/dev/packages/plugin/src/README.md — official V2 Promise plugin README (`experimental.idle` hook, codemode:false direct tool, reload list).
12. https://api.github.com/repos/anomalyco/opencode/releases — v2.3.0/2.3.1/2.3.2/2.4.0/2.4.1/v1.19.6 plugin lines (#64324, #63633, #64515, #64764, #63814, #65747).
Local: [L1] `EXPLORE-plugins.md` · [L2] `EXPLORE-session-api.md` · `STATE.json` (claim on 2.3.2 today) · AGENTS.md plugin placement law.
[P1] binary + skill-dir inventory probes (this run). [P2] npm tarball type diffs (this run). [P3] `opencode --version` → v2.3.2 on this host (today).

```
RESULT
status: DONE
chunk: R2
files_changed: [.agents/plans/2026/2026-11-cf-140-feat-agent-card-reconcile/RESEARCH-r2-opencode-plugin-skills.md]
commands_run: [binary skill-embed grep => pass, npm @opencode/plugin+schema tarball diff 2.1.4/2.3.2/2.4.1 => pass, docs fetch (plugins/server/rpc/migrate/tools/troubleshooting/openapi) => pass, upstream issue fetch 56290/65834/65742/65842 => pass, releases fetch => pass, V2 skill verification (igor/drawers/sveltejs/hoshi SKILL.md fetches) => pass]
deviations: wrote RESEARCH-r2-opencode-plugin-skills.md instead of RESEARCH.md per the launch instruction (three concurrent siblings; merge is coord-side); STORM run-dir scaffolding skipped — scope was four prescriptive questions, citation discipline kept
friction: skillsmp.com 403 on mirror pages (resolved via raw GitHub SKILL.md fetches); opencode api get /api/skill answered 0 skills without a location header (resolved via binary string probe); /api/skill header requirement is itself a small gotcha
open_questions: OQ-R2-2 singular-vs-plural placement (DECISIONS); OQ-R2-3 session.idle emission on the live host; OQ-R2-4 storage project-scope probe; OQ-R2-5 re-prove tool legs vs #65842 on the shipping build; OQ-1 (carried) live degrade/console visibility
next_suggested: merge the three RESEARCH-r* files into RESEARCH.md at the Planning gate; seed DECISIONS with the placement + id-permanence + codemode-absent rulings; plan plugin chunks to load /opencode + fetch docs/build/plugins/server and the RPC page as their API ground
```
