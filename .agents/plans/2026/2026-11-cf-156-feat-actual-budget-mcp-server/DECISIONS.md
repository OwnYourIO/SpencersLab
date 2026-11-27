# DECISIONS — cf-156 feat-actual-budget-mcp-server

Append-only. Owner answers are binding for this ticket; do not re-ask them at a later gate.

## 2026-11-23 — kickoff facts (board-driven intake, card AD-156)

- **Type** `feat`, **Services** `home` + `agent context` — from the card's checklists, consumed as the owner's answers.
- **Slug** `cf-156-feat-actual-budget-mcp-server`; folder `.agents/plans/2026/2026-11-cf-156-feat-actual-budget-mcp-server/`. The `slug` custom field read null at claim, so this is a FRESH run, not a resume — and this slug matches the two earlier runs on the card, so a later write-back appends rather than collides.
- **Stages the card checks** (`Lifecycle`): Exploration → Pre Research → Planning → Post Research → Test Writing → Chunk Development → Chunk Review → Final Review. Unchecked: Agent Decides Research, Deployment, Single Session.
- **Stop points** (`Human in the Loop`): after Pre Research, after Planning (the plan-approval pause), after Final Review. The `Deployment` stop is vacuous because that stage is unchecked.
- **Gated legs read as UNCHECKED because the card carries the pre-cutover 11-item Lifecycle shape**, which has no `Session Rename` and no `Worktree Creation` items. Consequences accepted as doctrine, not worked around: no rename and no sessionID captured (`kickoff.coord_session: null`), no in-work mark, the claim comment carries `unnamed`, this run's slug-stack line is the bare slug, and there is **no worktree/branch — the run works uncommitted in place on `main` in `/home/coder/SpencersLab` and the coordinator makes ZERO commits**. Landing onto a branch is the owner's call alone.
- **Shared claim, by owner word only.** The `Local` pipeline was occupied by a live run (`ses_df6dcd46bffeG0el3qCKVmGh2X`, claimed 16:07:16Z). A run never decides to share on its own, so the choice was put to the owner, who authorized co-tenancy for this one claim (`shared: true`, setId `5d58d120…`).

## 2026-11-23 — model routing (owner override)

- Card route from `Model(s)` = Qwen Dense + Local is `gpu-ai/qwen3.8-27b-radiance`; it answered a loud 502 peer-proxy error (the q27 pod is parked at `replicas 0`). First `agent-explore` died on it, wrote nothing.
- Interim: the documented hosted fallback for the same dense family, `openrouter/qwen/qwen3.8-27b` — said out loud, never a silent switch. That is the model the completed Exploration scout ran on.
- **Owner then instructed: "use gpu-ai radiance tp2 27b for the model the subagents use."** Both tiers now ride `gpu-ai/qwen3.8-27b-radiance-tp2` for every launch from Pre Research onward. Kickoff/owner choices override `pipeline-models` defaults.
- Recorded, not assumed: git renders `gpu-ai-radiance-q27-tp2` at `replicas 0` and llama-swap neither health-checks nor hides peers, so an unscaled lane answers the same loud 502; this session has no kubernetes surface to pre-probe it. The research launch on that lane served cleanly, which is evidence the scale act landed.
- Deviation kept in the open: the Exploration scout is NOT re-run on the new lane, because duplicating a live subagent's work is forbidden and both would race on `EXPLORE.md`. Strict parity is available on request.

## 2026-11-24 — lock reap and owner-authorized takeover

- The shared `Local` claim was reaped at `2026-11-24T01:19:58.999Z` while the run sat paused at its own checked `Pre Research` stop point — the 2h stale clock does not freeze at stops.
- Exactly ONE sanctioned question was asked ("may I continue anyway?") and the owner answered YES. The resume is a **fresh claim under the card-id key** (`pipelines:[itMHzqvEWzc6LAWvh]`, setId `fd1d1121-7591-4ef1-896e-be6b2e394096`), never a self-reclaim of the reaped label. Card stayed in **Executing**; the co-tenant's holder was left untouched; this run releases only its own.

## 2026-11-24 — owner answers from the batched plan-question round (BINDING)

1. **Server: `agigante80/actual-mcp-server`.** Chosen over s-stefanov (294★, single-budget), henfrydls (officially listed, single-budget, no public image), KazeFreeze and type0labs (thin), and over a custom in-repo container. It is the only mainstream server that spans multiple Actual servers in one deployment, ships the full write surface this ticket names (in-place splits that preserve `imported_id`/`cleared`, paired transfers, import-with-dedupe, budgets, rules, schedules, ActualQL reads), has a current GHCR image, and offers a read-only tier.
2. **"Reconcile the lists" = IMPORT-reconciliation** (dedupe by `imported_id`, `mergeTransactions`, `cleared` flag). **Statement-balance "lock" (`reconciled`) is NOT in scope.** Recorded consequence: no custom code chases an undocumented flag, and the archived guitarbeat `reconcile-account` tool stays a dead end by decision.
3. **Export semantics pinned:** the two lists are a **bank/statement export** (payments grouped) versus **Actual's own item-level, not-yet-bank-balanced transactions**. The agent reads the statement file, compares it against Actual, then splits/assigns inside Actual. On this answer upstream tools suffice — the custom-container branch is closed unless planning finds a gap.
4. **Auth: upgrade all three instances to 26.12+ for revocable, budget-scoped API keys.** The owner chose this over the interim session-token path. Constraints the plan must carry, not fight: (a) this puts a server-version change on the *existing* default + bri instances inside this ticket while the MCP surface stays wuulf-only; (b) the repo's hard rule forbids hand-bumping image tags — pins are Renovate's, so the upgrade lands as a Renovate-tracked pin move; (c) the 26.12.0 landing is an 8/10 **inference** from merge dates, not a release note, so if 26.12.0 is not published yet the API-key wiring is gated on it and the plan must say so instead of inventing a fallback.
5. **Scope: WUULF ONLY** — one budget, one deployment. (The owner declined the all-three registry, accepting that default/bri get MCP entries later.)

## 2026-11-24 — owner-owned external step (flagged, never executed by this run)

- A third host needs a **live Keycloak mutation**: client `actualbudget` in realm `SpencersLab` currently carries redirect URIs only for `budget.` and `bri-budget.spencerslab.com/*`; `https://wuulf-budget.spencerslab.com/*` must be added to redirect URIs **and** web origins. That is outside this repo, needs an `admin-*` surface the run does not self-authorize, and is therefore the owner's ops step. The plan must name it as a prerequisite, not a chunk task.

## Deferred / open at planning time

- Whether `reconciled` is settable via undocumented SDK/DB paths (B2) — moot by decision 2, do not spend a chunk on it.
- `ACTUAL_TOKEN_EXPIRATION` and whether 26.10.0 truly disables password login under OIDC enforce (B3) — only relevant if decision 4's upgrade leg slips; verify live rather than trusting an MCP author's README.
- Upstream image fit against the hivetools non-root/65532 podTemplateSpec (B6) — a dev-time check.
- Budget-switching cost inside one process (B5) — mostly moot under the wuulf-only scope.

## 2026-11-24 — plan approved at the pause; OQ answers (BINDING)

- **Plan approved AS WRITTEN** by the owner, accepting that the 26.12.x gate makes C02 **inert at first fire**: wuulf ships and goes live; the MCP server + credential plumbing lands with the ExternalSecret unready and the pod unable to start — a designed VISIBLE failure, no session-token fallback (binding #4 stands). `Post Research` verifies publication.
- **OQ1 answered AGAINST the plan's best guess — SPLIT the credentials into two Bitwarden items.** Proposed stems for the planner to adopt or name better, keeping the repo's one-item-per-convention rule: `actual-budget-mcp` (LOGIN, `password` = a random MCP-side Bearer token, mintable today, independent of 26.12.x) **and** a second item holding the wuulf budget-scoped API key (only mintable after the version leg). Consequences the rework must carry: TWO `OVERRIDE_VIA_CUSTOM_VALUES` sentinels in the home service values, TWO real-UUID mirrors in `custom-values/home/prod-values.yaml` (the 1:1 check counts both), and the ExternalSecret wiring split per item rather than one item with two target keys. The owner took the cleaner rotation story over the one-item shortcut.
- **OQ2 answered as the plan guessed:** the key is minted with FULL documented-workflow scope (reads + import/merge/split/transfer/assign + rules/budgets) and `MCP_READ_ONLY=true` is the server-side boundary. Two controls: the flag restricts today, the credential caps blast radius if the flag flips. No re-mint needed to enable the write tier later.
- Rework sequence, recorded so nobody skips it: Post Research → `agent-plan` folds the OQ1 split (+ any Post Research delta) into the plan file and `chunks/C02.md` → `plan_status: approved` → post-plan card write-back (the `slug` field gets the BARE slug, because this run is rename-skipped; the Priority stamp; every unchecked checklist item deleted) → Test Writing → C01 → C02 → Final Review.

## 2026-11-24 — POST RESEARCH INVALIDATES A PLAN PREMISE (needs owner ruling)

`agent-research` (TP2 lane) re-verified the planning-time facts and the re-verification did not hold. Recorded, with confidence scores, in `RESEARCH.md`'s "Post Research (2026-11-24)" section (sources `[27]`–`[55]`, appended to the existing numbering).

- **The blocker is the credential, not the version flag.** Current agigante80 (`0.35.2`) is **password-only**: no `sessionToken` and no API-key variable exists in its source, docs, history or tracker, and **no open issue requests one** (10/10). The plan's `BUDGET_<name>_SESSION_TOKEN` was invented. Because a fresh wuulf instance lands in the OIDC-only shape with no password line, **agigante80 cannot connect to wuulf at all** — and that is true independently of when 26.12.x ships. The `26.12+ API keys` ruling (binding #4) is therefore *necessary but not sufficient*: the chosen server has no door for the key to come through.
- **The transport fact that decides it:** budget-scoped API keys are documented as being **passed as `sessionToken`** (9/10) — per-budget `actual_[43]`, stateless per-request, no TTL, individually revocable, only opt-in is `bank-sync-global`, and the full documented-workflow scope IS mintable (so OQ2 is resolved with no conflict). So the question for any candidate server is narrow: **does it expose a sessionToken-shaped env var?** If yes, the 26.12 key rides it with no code change. agigante80 answers no.
- **`0.4.2` was a stale pin.** The planner's "newest stable versioned GHCR tag, queried 2026-11-24" was wrong: `0.4.2` published **2025-12-31** and bundles SDK **25.12.0**; `0.35.2` has been latest since **2026-11-22** and bundles **26.11.0** with an advisory-only, fail-open server guard (26.12.x sits inside the supported range, so it will not even warn). Whatever server is chosen, the pin must come from the registry's real latest, not a lexicographic guess.
- **B6 resolved by evidence:** the image starts as root by design; the hivetools non-root/65532 shape works **only** with `fsGroup: 65532` plus `MCP_BRIDGE_DATA_DIR` pointed at the PVC mount — and `fsGroup` is absent from the repo's standard block. 5Gi stays an assumption: no upstream size guidance exists.
- **26.12.0 is still unpublished** (10/10, four live sources agree). Earliest signal: the npm nightly `26.12.0-nightly.20261124` plus five `upcoming-release-notes/` API-key fragments. Recheck early December 2026.
- **Two live-cluster facts the run did not act on:** the `01-enable-openid` initContainer fails on **every** startup of `home-actualbudget` and `home-bri-budget` with `Missing script: enable-openid` (the SSO enable rides the auto-bootstrap path instead), and the `ACTUAL_OPENID_ENFORCE` "password login disabled" claim sourced from an MCP author's README is **disproven at the endpoint level by Actual's own source** (RESEARCH blind spot B3 closed). Neither is a chunk; both belong in the final summary for the owner.

`plan_status` is set to **needs-replan**. C01 (the wuulf instance) is untouched by any of this and stays approved; only C02's server/credential decision moves. Binding #1 (the server pick) is re-opened **only** because new evidence contradicts its premise, and the re-open belongs to the owner, not to this run.

## 2026-11-24 — planning-time verification that changes the auth story

- **26.12.0 is NOT published** (planner, 2026-11-24, live checks): GitHub releases for `actualbudget/actual` top out at `v26.11.0` published 2026-11-02; npm `@actual-app/api` `latest` = 26.11.0, `nightly` = 26.12.0-nightly.20261124. RESEARCH's 8/10 inference is confirmed as "not yet", so the API-key wiring is genuinely gated, not merely unimplemented.
- **MCP image pin chosen: `ghcr.io/agigante80/actual-mcp-server:0.4.2`** — newest stable versioned GHCR tag, queried live; `latest`/`main` rolling aliases deliberately not used; Renovate-tracked via the plain-image custom manager.
- The auth/version leg is **not a chunk**: its repo-side file work lives inside C02, and the version move itself is a Renovate PR the owner merges (hard rule: never hand-bump pins) plus owner mint acts. Carried consequence of binding #4: the shared pin move re-renders **all three** instances while the MCP surface stays wuulf-only.

## 2026-11-24 — replan rulings after the premise conflict (BINDING)

- **C02 server changed to `s-stefanov/actual-mcp`** (owner answer, after `agent-research` proved agigante80 is password-only with no `sessionToken` slot). Why it fits now: it already accepts a credential in the sessionToken slot, so binding #4 (26.12+ budget-scoped API keys) is satisfied the day the keys ship — by **dropping the key into the same variable, with no code change and no session-token stopgap**, which is exactly the auth ruling the owner made. It is active (294★, pushed 2026-11-23), e2e-tested against a real server, speaks stdio + streamable HTTP, carries Bearer auth on the MCP side, and exposes writes behind an opt-in flag. Its former downside (single budget) is moot under binding #5 (wuulf only). Standing caveats for dev: its Docker Hub image **lags the repo** (2026-10-20 vs 2026-11-23) so the pin must be taken from a live registry query, never from a lexicographic guess — the `0.4.2` mistake repeats if nobody checks; and the hivetools non-root/65532 fit is unverified (B6's `fsGroup` finding carries over as a check, not a conclusion).
- **agigante80 is dropped, not postponed.** Recorded so a later reader does not "restore" it: its multi-budget registry was the only reason it won, and the owner declined that scope. If a future ticket wants default/bri/wuulf in one server, the premise re-opens then.
- **C01 gains one scoped criterion: the `enable-openid` defect is fixed for WUULF ONLY.** The initContainer fails on every startup of both existing instances with `Missing script: enable-openid` (the SSO enable is actually carried by the auto-bootstrap path). The owner wants wuulf to come up without the broken step, and explicitly **not** a shared-chart change: the fix must land in wuulf's per-instance values, leaving `home-actualbudget` and `home-bri-budget` untouched. If the planner finds that no per-instance override exists and a shared-chart edit is the only way, that is a fresh question for the owner, not a licence to edit the shared chart.
- **OQ2 (API-key scope) and OQ1 (split credential items) are unchanged** by the server swap: full documented-workflow scope with the server-side read-only flag as the boundary, and two Bitwarden items (Bearer token / budget-scoped key). The variable names the plan references must be re-derived from the s-stefanov surface, not inherited from agigante80's (`MCP_BRIDGE_*`, `BUDGET_N_*` are the wrong project's names).
- Post Research remains authoritative on the gate: **26.12.0 is not published** (recheck early December 2026), API keys are minted per-budget and passed as `sessionToken`, and until then the MCP server cannot reach wuulf. The inert-until-the-key-lands framing survives the server swap; only its cause changes from "waiting on upstream to add a slot" to "waiting on Actual to ship 26.12.x so the slot has something revocable to hold".

> **Note on ordering:** the block headed **"planning decisions (agent-plan)"** further below is the planner's own log from BEFORE the replan rulings above it. Its agigante80 pin line and its "OQ1 one-item" naming are **superseded** by the replan rulings (server = s-stefanov, credentials = two split Bitwarden items). Kept verbatim as history, per the append-only rule.

## 2026-11-24 — C02 lands KNOWINGLY INCOMPLETE (owner ruling, deviates from the done-gate)

- **The blocker is data, not code.** C02's `custom-values/home/prod-values.yaml` leg needs two real Bitwarden **item UUIDs**, and the items do not exist yet. A UUID is issued by Bitwarden when an item is created, so it is the one value in this chunk that cannot be derived, looked up or deferred to a render — and a fabricated one would satisfy s6's *form* assertion while producing an ExternalSecret that points at nothing. The option was put to the owner (create both items and supply the IDs / implement incomplete / close on C01) and the owner ruled: **implement C02 now, leave it knowingly incomplete.**
- **What that means concretely, so nobody later reads it as a bug.** C02's entry, its two ExternalSecret templates and its PVC template land; the two UUID mirrors stay unwritten, so the repo's 1:1 sentinel↔custom-values convention is **deliberately violated on these two keys only** and the suite's s6 legs stay RED. The chunk therefore **cannot reach `done`**: it is recorded `dev_done_blocked`, and the Final Review covers it as a partial delivery by ruling, not as passing work.
- **The inert shape is unchanged and still visible.** Unresolved sentinels render the literal placeholder into the two NEW ExternalSecrets → both stay unready → the MCP pod cannot start. Verified scope limit: the two sentinels are new top-level keys, so they touch nothing on the existing instances; the acceptance bar for this chunk includes proving no pre-existing resource gains a sentinel or loses a mirror (the 8-sentinel baseline must still be 0 unmirrored, and `bri-budget`/`home-actualbudget` renders must be unchanged).
- **What closes it, in order:** (1) the owner mints the two LOGIN items and merges their UUIDs into `custom-values/home/prod-values.yaml` under `wuulf`-style nesting used by the existing entries — this is the remaining repo edit, one line per item; (2) the 26.12.x pin move lands via Renovate and the owner merges it; (3) the owner mints the wuulf budget-scoped API key into `actual-budget-mcp-key`'s password; (4) `--enable-write` is flipped when the read-only tier has proved itself. Steps 2–4 are owner ops; step 1 is the only thing that keeps this ticket's tests red.
- **Not an invitation to guess:** no session-token stopgap (binding #4), no invented Bearer token value in git, no shared-chart edit, no Keycloak or Bitwarden mutation by this run. If a dev or review step needs any of those to proceed, it stops and escalates instead.

## 2026-11-24 — planning decisions (agent-plan)

- **Chunk shape: two dev chunks (C01 the instance, C02 the MCP server); the auth/version leg is NOT a chunk.** Evidence: the auth leg's repo-side work (the credential plumbing — the ExternalSecret's second data entry, the per-budget credential env var) is the SAME file set as C02 (the `mcp` entry's env + the same ExternalSecret template); a split chunk would edit the same block under the uncommitted in-place posture, where the review surface is the working diff. The version leg is a Renovate-tracked pin move (never hand-bump) + the owner's mint acts — carried as plan Prerequisites 3–4, not a chunk task. C01 → C02 wave order: the BUDGET registry URL resolves against C01's in-cluster Service (data dependency) and sequential waves keep the working-diff review clean.
- **26.12.0 verified NOT published at planning time (2026-11-24):** GitHub releases top out at `v26.11.0` (published 2026-11-02); npm `@actual-app/api` `latest` = 26.11.0, `nightly` = 26.12.0-nightly.20261124. RESEARCH's 8/10 inference is confirmed as "not yet". The API-key wiring is gated on 26.12.x publication; verification handed to the Post Research round; no session-token fallback (owner rejected).
- **agigante80 pin `ghcr.io/agigante80/actual-mcp-server:0.4.2`** — the newest stable versioned tag in the GHCR registry (queried 2026-11-24; `latest`/`main` are rolling aliases, not used). Renovate-managed via the plain-image custom manager (semver-parseable).
- **Naming (conventional, OQ1):** the MCP server entry `hivetools.mcp.actual-budget` and the Bitwarden item `actual-budget-mcp` (LOGIN `password` = a random MCP-side Bearer token; custom field `api_key` = the budget-scoped key) — the `wekan-mcp` precedent. A rename is a two-line edit + the item name.

## 2026-11-24 — rework fold (agent-plan) — plan of record reworked in place

- **OQ1 stems adopted as proposed:** `actual-budget-mcp` (Bearer token, mintable today) + `actual-budget-mcp-key` (budget-scoped API key, mintable only after 26.12.x) — two LOGIN items, one ExternalSecret per item, two top-level sentinels, two UUID mirrors (the 1:1 check counts both). The owner's "adopt or name better" was answered by adopting.
- **R2 resolved WITHOUT a blocking owner question.** The replan ruling's fallback ("if no per-instance override exists and a shared-chart edit is the only way, that is a fresh question for the owner") never fires: `charts/actualbudget/values.yaml` defines **no** initContainers (verified 2026-11-24) — the broken `01-enable-openid` step (`npm run enable-openid --prefix /app || true`; fails `Missing script: enable-openid` on the 26.10.0 image) exists ONLY in the umbrella's instance-1 `actualbudget:` block (`services/home/prod/values.yaml:912-919`). The wuulf `chart:`-field copy inherits only the chart's values → comes up without the broken step **by construction**; SSO enablement rides the auto-bootstrap path (live-verified). `charts/actualbudget/values.yaml` untouched; `home-actualbudget` and `home-bri-budget` untouched. Recorded fallback if the criterion ever fails (a future chart change adds an initContainer; app-template has no negative container override): candidate A = a shared-chart gate (blast radius: every `chart:`-field actualbudget deployment re-renders — the owner explicitly rejected a shared-chart change), candidate B = accept the swallowed failing initContainer (`|| true`; the live instances already operate with the step failing). C01 Notes, not a blocking open question.
- **s-stefanov surface grounded at planning time (2026-11-24, README at master):** image `sstefanov/actual-mcp` (Docker Hub); `--sse` = streamable-http; `--enable-bearer` requires the `BEARER_TOKEN` env; `--enable-write` enables write-access tools (its ABSENCE is the first tier's boundary); `ACTUAL_SESSION_TOKEN` takes precedence over `ACTUAL_PASSWORD`; `ACTUAL_SERVER_URL`; `ACTUAL_DATA_DIR` (default `~/.actual`); `ACTUAL_BUDGET_SYNC_ID` (optional — deliberately NOT set; the key's per-budget-file grant selects wuulf); `ACTUAL_SYNC_TTL_MS` default 60000 (stays at default); the `--port <PORT>` flag exists but the default listen port is not stated as a default; `--test-resources` reports connection errors immediately at startup.
- **Dev-time verification items (C02 Notes, each with its check to run — never invent a value):** (1) the tag — a live Docker Hub registry query, newest published by the registry's own ordering/date (the image lags the repo: 2026-10-20 vs 2026-11-23; the `0.4.2` lexicographic trap); (2) the default HTTP port — read the repo source's port handling; pin `--port <verified>` if not 3000; (3) a read-only flag beyond the absence of `--enable-write` — grep the repo's argument parsing; (4) the image's entrypoint/user — `Dockerfile` + manifest `config.User`; derive the securityContext (the agigante80 `fsGroup: 65532` finding is NOT inherited); (5) the `BEARER_TOKEN` env wiring — confirm against the repo source.
- **B3 assumption stripped** (Post Research C-post-2, the "POST RESEARCH INVALIDATES" block): the `ACTUAL_OPENID_ENFORCE` "password login disabled" claim is disproven at the endpoint level; no plan text relies on it. The `enable-openid` defect fact stands and is C01's R2 criterion.
- **Inert reframed per the replan rulings' gate line:** the cause is now "waiting on Actual to ship 26.12.x so the slot has something revocable to hold" (26.12.0 unpublished — Post Research confirmed; earliest signals: the npm `nightly` stamp + five `upcoming-release-notes/` API-key fragments; re-check early December 2026). No session-token stopgap; the write-tier flip is a values change with no re-mint (the full-scope key covers it, OQ2).
- **Plan of record reworked in place** (the same dated file — never a second plan file): Goal / Out of scope / Verified / Prerequisites / Commands / Chunks / Open questions (resolved note) / Risks re-folded; `chunks/C01.md` gains the R2 criterion (AC2 + the s4 test + the Notes fallback); `chunks/C02.md` rewritten for the s-stefanov surface (all agigante80 names gone — `MCP_BRIDGE_*`, `BUDGET_N_*`, `MCP_READ_ONLY`, 3600, 0.4.2 as a pin); test numbering coherent across the one script (C01 s1–s4, C02 s5–s7). `plan_status` → draft (no blocking owner question); next = the plan-approval pause, then Test Writing → C01 → C02 → Final Review (the recorded rework sequence, the OQ-answer block of this same date).

## 2026-11-24 — C02 dev-time verification items (agent-dev, C02; verified, never invented)

All five C02 Notes dev-time items resolved with real checks (query
2026-11-24T21:24:50Z; source = s-stefanov/actual-mcp default branch `main`,
compared identical to `master` for the files fetched; Docker Hub tags API +
registry manifest — never memory or string sort):

- **1. Image tag: `v1.15.1`.** Docker Hub tags API for `sstefanov/actual-mcp`
  (22 tags total, all on page 1): newest *published* tag by the registry's own
  `tag_last_pushed` ordering = `v1.15.1` (pushed 2026-10-20T04:59:14Z; 3 s
  before the `latest` alias, i.e. the same build — the image-lags-repo fact
  holds: the repo default branch's `pushed_at` 2026-11-24T20:55:10Z is
  post-v1.15.1 unreleased work). Corroborated by the repo HEAD
  `package.json` `version` == `1.15.1`. No lexicographic trap (semver-newest
  too). **Carried fact (plan risk leg): the image bundles
  `@actual-app/api` exactly `26.10.0` — a pin, not a caret**, so it will not
  self-heal to 26.12.x when the version leg lands; the server-side key routes
  carry the key, but the image-side SDK pin stays a drift risk for the
  post-sync canary (`--test-resources` + `tools/list`).
- **2. Default listen port: 3000.** `src/index.ts`:
  `const resolvedPort = port ? parseInt(port, 10) : 3000;` +
  `app.listen(resolvedPort)`; the registry manifest's `ExposedPorts:
  3000/tcp` agrees. → `mcpPort: 3000`, and no `--port` arg (the Notes
  condition "pin `--port <verified>` if the default is not 3000" did not fire).
- **3. No dedicated read-only flag exists.** The full `parseArgs` flag set is
  exactly `--sse`, `--enable-write`, `--enable-bearer`, `--port`,
  `--test-resources`, `--test-custom` (booleans default false; `--port` a
  string); the write surface is `createServer({ enableWrite })` off
  `--enable-write`. The first tier's boundary (the owner ruling) is the
  absence of `--enable-write` — confirmed to be the ONLY write control.
- **4. Image user: root by default, no user-switching wrapper; chosen shape
  = repo-standard 65532 non-root block + pod-level `fsGroup: 65532`.**
  The Dockerfile has no `USER` line; the registry manifest (amd64,
  `v1.15.1`) has `config.User: null`, `Entrypoint: ["node", "build/index.js"]`
  (bare node — no su-exec/PUID logic, so the agigante80 entrypoint finding
  is NOT inherited), `WorkingDir: /app`, and `TMPDIR=` baked EMPTY (the
  Dockerfile's `mktemp -d` trick left nothing in the final image). The app's
  only filesystem write is `ACTUAL_DATA_DIR` (the app itself
  `fs.mkdirSync(dataDir, {recursive: true})` + the SDK budget cache; no
  temp-file usage anywhere in `src/`). Hence the pod-level `fsGroup: 65532`
  (group-writable PVC mount) is the SOLE write enabler needed, and the
  65532 non-root block (as in every other hivetools entry) + fsGroup is the
  chosen shape — re-derived from this image's real write surface, not
  inherited from agigante80 (whose root-by-design + su-exec entrypoint does
  not exist here). The pod-level `fsGroup` shape is established in-repo by
  the hivetools `renovate` entry.
- **5. Bearer wiring: environment, not an arg.** `src/index.ts`: the express
  middleware reads `process.env.BEARER_TOKEN` (401 absent/wrong token; 500
  unset) on `/sse`, `/`, `/mcp`, `/messages`, gated by `--enable-bearer`.
  `src/integrations/actual/connection.ts` reads
  `process.env.ACTUAL_SESSION_TOKEN` into the SDK init config (the
  sessionToken slot) and `ACTUAL_BUDGET_SYNC_ID` falls back to
  `budgets[0].cloudFileId` — with the single granted budget file the wuulf
  budget auto-selects, so that env stays deliberately absent (the plan's
  ruling).

## 2026-11-25 — C02 review outcome (APPROVED on the implemented surface, by ruling)

- **Verdict semantics, recorded so "APPROVED" is never over-read.** The reviewer approved *the implemented surface* and confirmed the suite's only two red checks are the two ruled-out `custom-values` mirrors. The chunk is **not** `done` and cannot become `done` while the owner-side UUIDs are outstanding; `STATE.json` carries it as `dev_done_blocked`, with `last_verdict` stating that scope in words.
- **The regression bound was confirmed independently, not inherited from the dev:** 10 top-level sentinels with the 8 pre-existing still 0-unmirrored, unmirrored bounded to precisely the two new keys, no sentinel VALUES anywhere in `custom-values`, `home-bri-budget` rendering unchanged, and `home-actualbudget` **still carrying the broken `01-enable-openid` step**. Nothing was repaired outside wuulf.
- **A plan-text error found and judged, not silently absorbed.** The plan's single hivetools render cannot contain the two new ExternalSecrets: service-specific ExternalSecret templates live in `services/<svc>/prod/templates/`, while `charts/hivetools/templates/` holds only chart-scoped ones (`mcp-sso`, `postgres-mcp-*`). The dev's substitute proof — the home-umbrella render plus the suite's file-presence/boilerplate asserts — was assessed as **fully covering AC1/AC2 without weakening them**, since those templates are unconditional and their only dynamic content is the UUID. The approved plan file stays as approved; the finding lives here rather than being edited into a signed artifact.
- **The SDK-pin consequence is now a standing close-out obligation attached to Prerequisite 3.** `v1.15.1` bundles `@actual-app/api` **exactly `26.10.0` — a pin, not a caret**, so the image will **not** self-heal when the 26.12.x server pin move lands. Whoever executes leg 3 must re-check for an s-stefanov release carrying a 26.12+ SDK (none exists at `v1.15.1`); until then the only runtime guard is the `--test-resources` + `tools/list` canary. The plan's Risks names the drift hazard but not this sharpness.
- **Deferred, not a change demand:** the new `mcp.actual-budget` entry omits the commented `# oidc:` "OIDC temporarily disabled (2026-09)" marker every pre-existing hivetools entry carries. Functionally the same opt-out (no `oidcConfigRef` in the render), but a future platform-wide OIDC re-enable grep will not surface this server. A later touch should add the marker for consistency.
- **All five dev-time values were spot-verified upstream at the tag itself** — tag by the registry's own `tag_last_pushed` plus repo `package.json` corroboration; port 3000 in source and manifest; the complete six-flag set proving `--enable-write`'s absence is the *only* write control; no `USER`, bare `node` entrypoint, empty baked `TMPDIR`; `BEARER_TOKEN` from `process.env`. The agigante80 root/su-exec conclusion was confirmed **not** inherited: the 65532 + `fsGroup` choice derives from this image's own write surface.

## 2026-11-26 — C03 replan: the owner's four instructions (binding) + the gate/naming decisions

### The owner's four instructions (2026-11-26, verbatim record, binding — folded as C03, not re-litigated)
1. Remove `wuulf-budget: enabled: true` from `services/proxy-remote/prod/values.yaml`
   (owner's words: "so I don't want anything on proxy-remote yet") — wuulf stays on
   proxy-local.
2. Use `actualbudget-mcp-key: 29e97ab5-db7f-4214-affd-b50e0032788d` and
   `actualbudget-mcp-bearer: 075f18ca-a137-415a-9296-b50e0033589c` — rename both
   `bitwardenIds` sentinels, both ExternalSecret templates/resources and their
   `remoteRef` item names to the owner's spelling; use these UUIDs.
3. Move the two ExternalSecret templates (and, if judged correct, the PVC — state and
   justify explicitly) from `services/home/prod/templates/` into
   `charts/actualbudget/templates/`.
4. Add both UUIDs to `custom-values/home/prod-values.yaml`.

### Decisions (recorded with the grounding that settled them)
- **Per-instance opt-in gate, chart default off.** `mcp: {enabled: false}` (new key,
  chart default) in `charts/actualbudget/values.yaml`; the `wuulf-budget:` per-instance
  block sets `mcp: {enabled: true}`; the moved templates gate on
  `{{- if index .Values "mcp" "enabled" }}` (nil-safe `index` access — the same access
  shape as the chart's own `pvc-data-default.yaml` name expression). Precedents: the
  `shared-storage` conditional-template pattern (`storage-and-secrets.md` §2 — chart
  declares the default map, the template uses `index` access); the `enabled` nil-safe
  gate vocabulary (`appset-charts.yaml:17-18` comment referencing the hivetools
  pattern). The hazard the gate exists for: `chart: actualbudget` is consumed by
  **two** Applications — `bri-budget` and `wuulf-budget` (the only two `chart:`
  consumers in `services/`, verified 2026-11-26); an unconditional move would render a
  second copy of the same-named ExternalSecret + PVC into the **bri** release — the
  documented two-Application sync-fight hazard. `home-actualbudget` cannot render the
  chart's templates by construction (the umbrella's `Chart.yaml` carries seven
  `app-template` dependencies, one aliased `actualbudget`, and **no** `actualbudget`
  chart dependency — verified 2026-11-26), so it renders NONE without any gate.
- **Release-prefixed, collision-safe names.** `{{ .Release.Name }}-mcp-key` /
  `-mcp-bearer` / `-mcp-data` (rendering `home-wuulf-budget-mcp-*` for the wuulf
  release; the appset release-name convention is `<category>-<appName>` — consistent
  with the entry's existing hardcoded `http://home-wuulf-budget.default.svc:5006`).
  Precedent: `charts/zigbee2mqtt` — a `chart:`-multi-instance chart (deployed three
  times: `zigbee2mqtt` / `zigbee2mqtt-coord` / `zigbee2mqtt-remote`) whose
  `secret-zigbee2mqtt.yaml` and `pvc-zigbee2mqtt-default.yaml` name their objects
  `{{ .Release.Name }}`-prefixed. Consequence proven in the C03 AC: a second instance
  enabling the gate renders `home-bri-budget-mcp-*` — **no object name shared** with
  the wuulf release, so the gate can never cause a sync-fight.
- **The PVC moves too (instruction 3's "if judged correct" — judged YES, justified).**
  The data PVC is part of the MCP-side resource set (the SDK budget-cache claim the
  mcp pod mounts at `/data`); gating it with the same key keeps all three MCP objects
  owned by the one Application that enables the gate, so no Application owns an object
  nobody uses. The bri release's **own** data PVC (the chart's pre-existing
  `pvc-data-default.yaml`, rendering `home-bri-budget-data`) is untouched and
  coexists with the gated template.
- **`deletionPolicy: Delete` on the two credential ExternalSecrets — a named part of
  the moved shape** (the mcp-servers.md Techniques recommendation; the repo-wide
  convention: `secret-argocd-mcp.yaml`, `secret-grafana-mcp-token.yaml`,
  `secret-grafana-mcp-admin-token.yaml`, `secret-postgres-mcp.yaml` all carry it,
  under `target:` beside `creationPolicy`).
- **Injection path after the move (stated, not re-derived in dev).** The sentinels
  move from the home service values' top-level `bitwardenIds` into a **new**
  `bitwardenIds:` map in `charts/actualbudget/values.yaml` (the lowest merge tier);
  the real UUIDs stay at the **top level** of
  `custom-values/home/prod-values.yaml`, where the appset merge
  (`appset-charts.yaml:101-123`: per-app custom > service-wide custom > service-level
  globals > base values) overrides the chart tier — the same injection that resolves
  `actualbudget-sso-secret` today. Per-app `custom-values` blocks
  (`wuulf-budget: bitwardenIds: …`) land as **nested** keys in chart values and never
  feed the chart's top-level map — so **no per-app MCP UUID blocks are added**; the
  two top-level UUIDs are the only mirror. The 1:1 check is re-pinned to count the
  chart sentinels (both files 1:1, GREEN with the owner's UUIDs).
- **Name→UUID mapping (OQ3, name-derived best guess, impact named).** The owner
  supplied names + UUIDs without restating roles; the plan wires by name semantics:
  `actualbudget-mcp-key` = the budget-scoped API key → `ACTUAL_SESSION_TOKEN` (the
  "key" naming is this plan's own across binding #4 / Prerequisite 4 / C02; the old
  `actual-budget-mcp-key` item is its direct dash-normalized successor);
  `actualbudget-mcp-bearer` = the MCP-side Bearer token → `BEARER_TOKEN`. If the
  roles were minted swapped, the fix is a two-line `secrets:`/`remoteRef` swap —
  **no re-mint, no item change** — and the failure mode is visible, not silent (the
  pod 401s at startup; `--test-resources` surfaces it).
- **C01's AC3 is recorded as a CHANGED requirement, not a re-opened chunk.**
  Instruction 1 removes the proxy-remote leg from C01's grep trio (C01 is `done`; the
  post-hoc revision is recorded in the plan's Open questions, the suite's s2 leg is
  re-pinned to an **absence** assertion by the Test Writing session, and the plan's
  `## Commands` trio is updated in place).

### Verified at replan time (2026-11-26, grounding the decisions above)
- **The C01/C02 surface is branch-only — nothing of it is live.** Targeted live gets
  (readonly-home-kubernetes): PVC `actual-budget-mcp-data`, PVC `wuulf-budget-data`,
  ExternalSecret `actual-budget-mcp`, ExternalSecret `actual-budget-mcp-key`,
  MCPServer `mcp-actual-budget` — **all five not found** (the branch is unmerged;
  ArgoCD tracks `main`). Consequence: the template move prunes **no live object** —
  the `values-and-appset.md` ownership-flip hazard (prune-before-adopt credential
  gaps, orphaned target Secrets) does not fire; every object is a pure creation at
  first post-merge sync. One residual, self-healing window: at first sync the mcp pod
  can start before `home-wuulf-budget-mcp-data` exists → Pending until the `wuulf-budget`
  Application syncs the PVC; the next ArgoCD loop recovers it. No action needed.
- **The standing-constraint comment goes with the old sentinels** (C02's deliberate-red
  record; C03 resolves the red it documented, so the comment is stale narration).

### The inert premise is over (consequence, recorded)
The 2026-11-24 "inert until the key lands" cause is gone: **Prerequisites 2 (the two
Bitwarden items) and 4 (the API-key mint) are SATISFIED** by the owner's rework —
`actualbudget-mcp-key` (the budget-scoped key, minted per OQ2's full documented-
workflow scope) and `actualbudget-mcp-bearer` (the random MCP-side Bearer) exist with
the supplied UUIDs. Therefore: the 1:1 sentinel check goes **GREEN** with C03; the
suite's designed 29/2 shape is **RETIRED** — the re-pinned suite's expected outcome
is passing in full (**0 failures**); and a live MCP pod **may now actually start and
connect** the moment C03 lands (the ExternalSecrets resolve the real UUIDs → the
target Secrets exist → the pod starts, connecting to wuulf through the budget-scoped
key in the `ACTUAL_SESSION_TOKEN` slot). The credential-is-the-gate mechanism stands
(Post Research Q2: the key has no read/write axis; a budget-file grant is full
read+write *within that budget only*); the first tier's boundary is unchanged — the
**absence of `--enable-write`**. Prerequisite 1 (Keycloak redirect URIs + web origins
for the wuulf host) and Prerequisite 3 (the 26.12.x pin move **+ the attached
`@actual-app/api` exactly-26.10.0 re-check** — `v1.15.1` bundles the SDK as a pin,
the image does not self-heal; canary `--test-resources` + `tools/list`) remain
owner-owned.

## 2026-11-26 — C03 reviewed APPROVED; C02 cleared to done; two record corrections

- **C03 is done.** The reviewer re-ran everything and it held: suite **48 pass / 0 fail** (the first fully green run in this ticket), three lints clean, the three-way render proof (wuulf gate-open with both real UUIDs resolved; **bri gate-closed rendering zero MCP objects**, confirmed also by the `--show-only` empty-render error; the umbrella rendering zero), the collision proof (`home-bri-budget-mcp-*` names with **zero** shared against the wuulf set), and live-pair byte-parity (bri chart render byte-identical pre/post, md5 `109d542ef8757a867e180f5721a8484f`; `home-actualbudget` Deployment doc sha256 identical, `01-enable-openid` still present).
- **It also checked the thing I would have wanted checked: whether a first-ever green run means the tests got soft.** It read the suite whole and confirmed s2 asserts absence with unreadable-file-fails, s5 checks the nil-safe `index` gate regex, release-prefixed names and gone-old-files, and s6 re-pins 1:1 to the chart sentinel source with the 8-sentinel regression pin — the re-pin is substance, not a widened no-op.
- **The architecture objection I raised is now resolved on evidence, not on assertion.** `charts/actualbudget` is **not** cluster-wide (absent from `charts/base`'s `charts:` list; exactly two `chart:` consumers), so the mcp-servers.md cross-cluster broken-sentinel concern cannot arise here. `deletionPolicy: Delete` is the repo convention on ExternalSecrets and the moved PVC carries none (an ES-only field); it is the SDK **cache**, so a prune self-heals, while the instances' own `pvc-data-default.yaml` stays unmodified and ungated. The relocation therefore overrides the documented services-templates rule **by owner instruction**, with the gate and naming as the documented counter to the sync-fight it would otherwise create.
- **C02 moves from `dev_done_blocked` to `done`** on the reviewer's recommendation, recorded in the same post-hoc changed-requirement form as C01's AC3: its blocker (the two UUID mirrors) landed via C03's top-level custom-values leg under the **owner's renamed items**, so instruction 2 supersedes the names C02 originally pinned, and its AC3 (template location) and AC6 (the 29/2 suite shape) are satisfied in C03's re-pinned form rather than their original wording. AC1/AC2/AC4/AC5 invariants were re-verified by the C03 renders. **No C02 criterion is unmet in substance.**
- **Correction to my own contract understanding, and a permission fact worth knowing:** `chunks/C03.md`'s Notes bullet contradicted itself — "dev commits C03 on the ticket branch" beside "the coordinator remains the sole committer". The C03 dev followed the contract and the coordinator committed. When I tried to fix the chunk line directly, **`edit` was denied on `chunks/*`**: chunk files belong to the planner, so the authoritative correction lives here and `agent-plan` applies the one-line text fix. My writable set in the folder is `STATE.json`, `DECISIONS.md`, `FRICTION.md` — which is exactly what `pipeline-role-coord` says and what I briefly forgot.
- **Nit recorded, not fixed:** the suite's s5 PVC pass message narrates `deletionPolicy Delete` boilerplate although a PVC has no such field and the checked extras are kind/namespace/RWO/5Gi. The checks are honest; only the label overstates. Left alone rather than churning a passing suite.
- **Consequence of the owner's UUIDs, now unavoidable:** C02 was delivered inert because the credentials could not exist. They exist, so on the next ArgoCD sync the ExternalSecrets resolve and the MCP server can actually start and connect to wuulf. The only thing keeping it read-only is the absence of `--enable-write`.
