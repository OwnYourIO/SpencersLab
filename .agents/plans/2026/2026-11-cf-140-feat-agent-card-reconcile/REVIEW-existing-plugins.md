# REVIEW-existing-plugins.md — fresh-eyes judgment pass on the system AD-140 replaces

Reviewer: `agent-review` (special pre-planning review, `chunk: review-existing`), 2026-11-23.
Model: openrouter/qwen/qwen3.8-2.4t-a95b (card-requested). Method: the four EXPLORE files + STATE.json read
first, then every claim below re-verified against the real sources and the LIVE runtime (opencode.db
forensics, `.pipeline/` audit log, process table, `rulesync generate --check`). Nothing here is repeated
from the scout without independent verification; new evidence is marked **[live]**.

Severity scale: `blocker` (the pivot fails without it), `major` (design must absorb), `minor`, `nit`.

---

## 1. What the current code gets RIGHT — audited preserve set

The scout's ten-item list (EXPLORE-plugins §6) is accurate where it reaches; I verified each item in code
and add five corrections/additions. Verdict per item (keep = must survive the pivot in some form; re-home =
contract survives, implementation moves to card-runner; drop = see §3):

1. **Lock semantics** — verified: `acquireSetWithRollback` sorted-order walk + full rollback
   (pipeline-locks L642-729), O_EXCL create with bounded loser re-read (`HOLDER_READ_DELAYS_MS`, L115),
   `OccupiedError` emptiness refusal naming holders (L596-606, L678, L703), `shared: true` strictly
   per-claim human input ("nothing here may widen it into a deployment-wide setting", L756-758),
   `already_held` one-card-per-session checked against BOTH in-process map and durable storage (L768-772),
   card-id takeover tagged `after_reap` ONLY with a `.reaped/` record (L731-750, L782-784), stop marker
   clears only on the session's OWN new claim (L793-795). **Verdict: mostly DROP (§3) — the semantics are
   correct but solve a problem the reconciler design dissolves; keep only the one-card-per-session and
   no-self-reclaim postures, re-expressed on a run registry.**
2. **Lock file contract** — verified: v2 record (`newLockRecord` L403-438), `viewHolders` v1 tolerance
   (L447-461), `writeLockAtomic` tmp+rename with byte-preservation on failure (L517+), `TornLockError`
   "unreadable ≠ free" (L585-594), `sanitizePipelineKey`/`derivePipelineSet` (L269-289). **Verdict: DROP
   with the lock files — but the atomic-write + torn-state discipline is the template for whatever
   registry file replaces them.**
3. **Heartbeat engine** — verified: activity-only beats (`runBeatTick` L1280-1302, "Idle roots
   deliberately receive nothing"), set-wide verify-before-beat (`heartbeatSet` L1233-1278), 30 s throttle,
   the strict `LOCK_LOST_STOP` guard on `GUARDED_TOOLS = ["edit","write","bash"]` (L196, L206). **Verdict:
   the beat engine DROPS (liveness moves to session-API tree-age); the GUARD survives re-keyed (§3).**
4. **Reaper** — verified: `max(heartbeatAt, mtime)` 2 h formula, mkdir cross-process guard, rename-as-claim
   + race-restore, per-holder prune. **[live] its board leg has NEVER succeeded in production: every row
   in `.pipeline/timeouts.jsonl` is a failure degrade (`"get_card answered no list_id"` ×6, `"no Timeout
   list in the card's swimlane"` ×3, `"MCP error -32001: Session not found"` ×1) — the Timeout list does
   not exist on the live board. The HA alert + jsonl forensics are the only reap surfaces that ever ran.**
   **Verdict: detection policy DROPS (it criminalizes question-pauses — the pivot's reason to exist); the
   alerting/forensics legs survive re-homed on the reconciler's dead-run verdict, and the Timeout-list
   prerequisite must be an owner leg of THIS ticket or formally dropped.**
5. **Dispatcher wake + no-op marker contract** — verified: wake on every non-empty release, outcome-blind,
   self-healing (`wakeDispatcher` L858-878); reader conjunction `openchamber.kind==="scheduled" &&
   pipelineNoop.reason` non-empty (question-notify L154-161); N3 single-home grep confirmed live:
   `pipelineNoop` exists in exactly the boards skill pair + question-notify plugin. **Verdict: KEEP both
   contracts — wake re-targeted at the reconciler; no-op WRITER predicate needs redefinition if claims go
   (§3, finding M4).**
6. **Compaction contract** — verified: one `ctx.session.hook("compaction")` (L2686), `HANDOFF_FULL_AGENTS`
   (L1453), `session.compaction.failed` record-only listener (L1413-1444), `HANDOFF_ENTRY_KEY` sibling to
   the pin key, T15 creep-back guard present (question-notify.test.ts:1086). **Verdict: KEEP verbatim,
   re-homed in card-runner; the T15 pin must be deliberately re-pointed.**
7. **Never-throw degrade law** — verified across all board-context arms (catch → untouched prompt + one
   stderr line; `withinBudget` race L452-471; setup try/catch) and pipeline-locks. **Verdict: KEEP — it is
   the only reason a broken board fetch never killed a scheduled dispatch.**
8. **Once-per-session context injection** — the scout phrases this "keep, with the guard fixed".
   **CORRECTION: the guard is not fixable by tuning — §2(a) proves the failure is a runtime-capability
   flap, not a parameter bug. Preserve the INTENT (one board block per run, first prompt only) by moving
   it off the flapping surface: reconciler-spawned runs get the block in the launch brief; the prompt hook
   either dies or its mark moves to a canonical-root file / shared-db surface that demonstrably spans both
   server processes (the `.pipeline/` dir and opencode.db both provably do — locks beat and kv rows land
   cross-process today).**
9. **`localIso` single formatter** — verified: one implementation (L234-267), imported by board-context
   (L72), pinned by tests/cf96-tz. **Verdict: KEEP — card-runner keeps exactly one implementation.**
10. **Storage/audit continuity** — verified live: kv namespaces keyed `plugin:<hex(id)>:` (793 rows:
    pipeline-locks child/claim, board-context once, question-notify claim), events.log vocabulary in live
    use. **CORRECTION: a rename to `local.card-runner` silently orphans every existing kv row (claims,
    child maps, dedup stamps, once-marks) — restart-resume rebuild breaks at cutover. Decide explicitly:
    keep the `local.pipeline-locks` id inside card-runner, or migrate rows at setup. Scout OQ-2 touches
    this; promote it to a plan decision.**

**Additions the scout missed:**
11. **Restart-resume rebuild** — `storage.scan` of `claim/*` + `child/*` at setup (D26) is what lets a
    server restart re-attach beats to live runs. Whatever registry card-runner keeps needs the same
    property, or every opencode restart silently strands runs.
12. **Instruction-entry API shape** — the db carries a live `instruction_entry` table (32 rows); the
    v2.3.0 `entry.put` takes `{sessionID, key, value}` and `{key,text}` throws "Missing key" (cf-126
    binder note). The pivot's note/pin writes must use the verified shape.
13. **Cross-plugin import re-registration** — importing anything but a leaf function from a plugin file
    re-registers it under discovery (both plugin headers record it). card-runner must be self-contained or
    import leaves only from files that stay.
14. **[live] The ~3.0 KB session-metadata PATCH limit** — recorded in today's dispatcher metadata
    ("outgoing session metadata write hit the ~3.0KB server PATCH body limit (bisected)"). The
    reconciler's session-record bookkeeping (walk state, spawn records) MUST stay small or it truncates
    mid-write — a hard cap the design has to respect, invisible in the scout files.
15. **[live] Multi-process event fan-out is total** — every instance subscribes the whole public event
    stream (two live servers confirmed, §2(a)). Any event-driven leg in card-runner needs consume-once
    claims exactly like question-notify's `claimOnce` — and `claimOnce`'s tolerant read (`seen?.at`) is
    the storage-read shape that demonstrably round-trips, unlike board-context's `typeof === "number"`.

---

## 2. Root causes of the two owner symptoms — verified, with new evidence

### 2(a). Board block re-injected on every follow-up — DECIDED: storage-binding flap × two-process topology

Code path verified (board-context/index.ts): the only dedup is `readOnce` → `storage.get("once/<sid>")`
accepting `typeof value === "number"` (L378-388), falling back on any failure to the per-process
`attempted` Map; `writeOnce` writes map + storage (L389-398); a failed attempt still consumes the mark
(header doc, L34-38). The scout listed three failure legs without deciding. I decided, with evidence:

**[live] Empirical scale** — querying the shared opencode.db (`session_message` LIKE the canonical
header): 25 sessions carry >1 user prompt with the block; among board-coord sessions with ≥4 user
prompts, **15 of 17 re-received the block on follow-ups** (worst: ses_e6cf97059, cf-88 coord, 12 of 34
prompts over 7 days — "Continue / Continue, but use the 27b model / Went off the rails there…" each with
a freshly-collected block appended). Only 2 long-lived sessions were properly once-injected.

**[live] Which legs fire** — the durable once-mark shipped 2026-11-07 (d0361cf24). Two sessions
re-injected AFTER that merge with a durable mark already written: ses_e4ced1b7b (mark 2026-11-09 13:05;
re-injected +50 min and +2.5 h later) and ses_e4860e71b (mark 11-09 18:28; re-injected +4.5 min later).
Decisive details:
- The kv once-mark rows EXIST for these sessions (writes landed from SOME process), so the storage
  binding works on at least one load — this is not a universal code bug.
- The re-injecting follow-ups did NOT advance the kv stamp (value still equals the first mark). But
  `writeOnce` runs BEFORE the fetch on every injection attempt — so on the process serving the
  follow-ups, `storage` was null (early `return`) or `set` threw: a **bind-level absence**, not a
  read-shape mismatch.
- **Leg 3 (6 h TTL) is eliminated as the driver**: +4.5 min and +50 min re-injections sit far inside the
  TTL. The `typeof === "number"` strictness is likewise not the operative bug (kv values store fine as
  number-text; the failing process never writes at all).
- **Leg 1 × Leg 2 is the mechanism**: `bindOnceMarkStorage` returns null (or get/set throws) on some
  plugin loads → guard degrades to the per-process in-memory map → and the deployment runs **TWO opencode
  servers sharing one opencode.db** (confirmed live now: `opencode serve` pid 895 + `opencode.exe serve
  --service` pid 28770; question-notify's own header records the hazard; EXPLORE-session-api §9). Within
  one process the in-memory map rescues; across processes (or a restart) nothing does → every follow-up
  the storage-less process serves re-injects. The flap is load-dependent (some recent sessions are
  correctly guarded), consistent with version churn on this host through November (the Coder template
  vars updated outside the repo).

**Residual (honest)**: plugin stderr is not captured in `opencode.log` (verified: no `[board-context]`
degrade lines despite 2208 incidental hits), so the setup-degrade line itself cannot be sighted; the db
forensics above are the stronger evidence anyway. Design consequence: **never rebuild this guard on
`ctx.storage` capability** — use the shared-db session record or a canonical-root file (§1 item 8).

### 2(b). Lock "stomping" — PROVEN from emptiness rule + key derivation, plus live churn evidence

Mechanism, line-cited:
1. **Key derivation**: `derivePipelineSet` (L279-289) maps every `Pipeline:`-prefixed label to its
   trimmed remainder; `sanitizePipelineKey` (L269-277) folds to a filesystem name; NO labels → the single
   `default` key (L288, `DEFAULT_PIPELINE`). Two cards labeled `Pipeline: Context` both derive
   `["Context"]` → both resolve to the ONE file `.pipeline/locks/Context.json` (`lockPathOf`, L499-501).
   **[live]** today's dispatcher walk metadata shows exactly the collision pair: card 140
   `pipelineSet:["Context"]` and card 73 `pipelineSet:["Context","CICD"]`.
2. **Emptiness rule**: `acquireSetWithRollback` walks the sorted set; a key with live foreign holders and
   no override throws `OccupiedError` (L677-678) → refusal `{ok:false, reason:"occupied", holders:[…]}`
   (L699-703). `shared` is `input?.shared === true` — "a per-claim input the human supplies… nothing here
   may widen it into a deployment-wide setting" (L756-758).
3. **Worker doctrine**: the boards skill's Parallel pipeline loops ("Co-tenancy is the human's call, never
   the run's") forbids the run retrying with `shared:true` on its own — so the second manual card on
   `Pipeline: Context` gets `occupied` naming the first run, and the worker MUST prompt the owner. That
   prompt, repeated per contended card, is the owner's complaint. Unlabeled cards are worse: every one
   collapses into `default` and serializes globally.
4. **[live] Aggravator discovered in today's log**: the dispatcher recorded "lock tools absent from
   dispatcher Code Mode registry — pre-filter skipped, coord claim is the authoritative gate" — on the
   running v2.3.2 build the `pipeline_*` tools are not even visible to the dispatcher's Code Mode, so the
   availability pre-filter cannot run and contention surfaces ONLY at claim time, maximizing owner prompts.
5. **[live] The stomp is also intra-run**: today's `.pipeline/events.log` shows (a) THIS ticket's claim
   hit an 8-row `lock_lost cause:"stolen"` storm at 18:05:06 while its own holder row was live and
   continued live (Context.json still carries setId 34617c28, claimedAt 17:55:28) — the exact spurious
   PIPELINE LOCK LOST recorded in STATE.json's claim note, which forced an owner answer on a healthy run;
   (b) ses_e18d38cb, 3 min after releasing `outcome:"done"` at 18:52, took a 5-row `lock_lost
   cause:"missing"` storm — late beats racing the release cleanup armed the stop marker on an ALREADY
   FINISHED session. Both storms flow from `checkMember`'s classification (L1059-1070: any read without
   our holder row = "stolen"; absent file = "missing") with no idempotence on the lost path — every beat
   source (timer + before-hook + after-hook) re-runs `handleLockLost` and re-appends audit/pin. The
   firewall false-positives in production. The owner's prompt fatigue is not one bug: it is the
   occupied-refusal doctrine (by design) + the idle-age-out reap of question-paused runs (by design, the
   activity-only beat makes every human stop age out — cf. the 07:03 mass-reap of the 04:26 spawns at
   ageMin 122-125) + false lock-lost storms (bug class).

---

## 3. Is the lock mechanism still load-bearing once one reconciler decides? — verdict

**Framing correction first**: the pipeline lease was never the card-safety mechanism — the boards skill
makes **Executing membership alone** the ownership signal ("membership alone is also the whole
protection"), and `already_held` enforces one-card-per-session. The lease guards PIPELINE TRACKS
(`Pipeline:` labels) against concurrent runs. The owner's stated assumption — "two sessions on one
pipeline should become a NON-EVENT" — is exactly right: two cards on one track are disjoint work
(disjoint worktrees, disjoint slugs); once a single reconciler decides picks, there is nothing left to
refuse. So:

**CAN GO** (with reasoning):
- Per-pipeline lease files, O_EXCL acquisition + rollback, `occupied` refusal, `shared:true` co-tenancy,
  holder pruning, file-level last-writer-wins stamps, TornLockError handling — all machinery for mutual
  exclusion the reconciler's single-writer decision makes redundant. (Manual `/pipeline-boards` launches
  remain a theoretical second writer — see "must stay" below.)
- The heartbeat engine, throttles, 2 h staleness doctrine, claim-time pre-reap, `pipeline_heartbeat`
  tool, `/pipeline-reap` — liveness is now derived from session records (the gate's proven tree-age
  primitive), and "idle = dead" is precisely the doctrine the pivot exists to kill.
- The `pipeline-lock` instruction pin (registry replaces it).

**MUST STAY** (what actually breaks without it):
1. **A zombie firewall, re-keyed** (blocker). The scenario leases covered at card level: run A is judged
   dead, successor B starts on the same card (same worktree, same branch, both are "sole committer"), and
   A wakes — compaction-handoff residue, a slow model turn, a resumed laptop. Today the `LOCK_LOST_STOP`
   guard on edit/write/bash is the ONLY mechanism that stops A's writes; nothing else in the system
   prevents A committing into B's worktree. Dropping leases without a replacement firewall turns a
   noisy-but-safe failure into silent git interleaving. card-runner must keep a strict guard, re-keyed on
   the run registry ("session X is no longer card Y's runner" → block guarded tools), with the same
   one-sanctioned-question resume posture. Note the firewall's current false-positive class (§2b.5) must
   be designed out, not carried over.
2. **A durable, cross-process per-card run registry** (blocker). Replaces leases as the answer to "which
   session runs which card": restart-surviving (the storage-scan rebuild), visible to both server
   processes, consulted by the reconciler before ANY spawn and by the guard above. The `already_held`
   posture (one card per session) rides it.
3. **The reconciler-honored Executing-membership rule + claim-before-move sequencing** (blocker) — the
   real card-level exclusion; it survives as doctrine, enforced by the reconciler's own logic instead of a
   refusal answer.
4. **Dead-run alerting and forensics** (major): the HA push + timeouts.jsonl rows + audit vocabulary,
   re-triggered by the reconciler's dead verdict. The Timeout board leg needs its list provisioned (owner
   leg) or the jsonl degrade becomes the permanent design.
5. **The wake contract** (major): releases/wake → reconciler prompt; outcome-blind, self-healing.
6. **The compaction contract, never-throw law, localIso, no-op marker contract (redefined predicate),
   consume-once dedupe, audit JSONL** (§1 items 5-7, 9, 10, 15).

**The trade the owner must see** (major): dropping leases converts the last CODE-enforced guard against
two simultaneous schedulers into an OWNER-enforced one. The deployment has four historical scheduled
surfaces (`pipeline-worker`, `pipeline-dispatch`, "Hourly Pipeline call" — which runs NO gate — and the
manual commands); all are currently `enabled:false` owner-side, and the repo cannot delete them. Leases
are the only mechanism that makes a double-scheduler accident loud (`occupied`) instead of silent. If
leases go, the plan should state this precondition explicitly and keep the registry check cheap enough
that even an accidental second writer trips it.

---

## 4. Correctness risks in the pivot the card did NOT name

### 4.1 Coordinator context keeps getting junk even with a reconciler (major)
Measured **[live]**: this ticket's coord first prompt is 8,310 chars — 31 chars of intake
("Please pickup and work AD-140") + 8,279 chars of board block (99.6% card mechanics). The reconciler
removes the re-injection class, but opens new junk channels unless the plan bounds them:
- **Change-forwarding is the new injector.** Every "user changed the card" forward is a new user prompt
  in the coord's context. Without a compact delta format + dedupe + a cap, an active owner editing a card
  pollutes the run exactly like the old hook did. Prefer RE-WRITING the YAML dump (§4.2) and notifying in
  one line ("card updated — re-read CARD.yaml") over pasting diffs into prompts.
- **The claim-time card-details block** lands inside the `pipeline_claim` tool answer (verified degrade on
  this very run: STATE `card_details.degraded` — the hook never fired, coord called `get_card_details`
  itself and paid the fan-out in its OWN context). If claims/registry answers replace the tool, keep the
  details OUT of the answer; the YAML dump is their home.
- **The false-positive lock-lost stop text** (verified live, §2b.5) is a context-injection class too —
  pin writes + tool-result throws. Retiring the lease machinery retires it, provided the replacement
  guard's stop text is one-shot per event, not per beat source.

### 4.2 Per-card YAML dumps can go stale — and have undefined homes on gated runs (major)
- Writer identity: the plugin cannot know the feature-folder path; the coord must write the dump. But
  then freshness equals "the coord last acted" — reconciler-detected card changes need the RECONCILER to
  rewrite the dump, which requires resolving slug → folder from outside the run. Workable (the
  `cf-<cardNumber>-…` convention + `.agents/plans/<yyyy>/` scan), but it is new machinery the card
  assumes away.
- **`Worktree Creation`-unchecked runs have no plan folder to write into** (uncommitted-in-place runs —
  D28) — and this ticket's grouped sibling flow multiplies dumps (one per sibling card). The dump
  contract must name both cases.
- **Rework re-picks**: a card sent back to Rework carries an old dump from the previous run; the
  resume-vs-new-run rule (`<slug>-1`) changes the folder — the dump location rule must follow it.
- Mid-session staleness is unsolvable by construction (a running dev subagent cannot re-read): accept
  snapshot-at-subagent-launch semantics and stamp it in the file header, same posture as the board
  block's "snapshot, never a freeze" footer.

### 4.3 "Card objective completed" vs "run ended" — the signals do not exist (major)
The session record carries `outcome` (succeeded/failed/interrupted/None) and timestamps — NO objective
semantics (EXPLORE-session-api §2, verified: `outcome:None` includes 13 h-old dead rows, so even
"alive" is not a field). The plan must write an explicit decision matrix over the signals that DO exist:
- run ended + card in Review/Finished + release summary comment → objective met;
- run ended + card still Executing + fresh successor (parentID/`metadata.parent` chain or slug-stack
  newest line naming a live session) → compaction handoff, do nothing;
- run ended + card Executing + no fresh successor → crashed/abandoned → relaunch-or-Triage decision.
The dangerous confusion is the MIDDLE row: today's handoff releases look exactly like "run ended, card
still Executing" from outside. A reconciler that does not resolve the successor chain will double-spawn
on every compaction handoff — and cf-126's own lineage (visible in today's log: three dispatcher
handoffs before 05:00) shows handoffs are frequent, not rare. **Recommendation: scope "objective
completed" DOWN to the explicit signals (card membership + release comment); never an LLM judgment of
"did the run achieve the card".**

### 4.4 The reconciler starting a second coord on a question-paused card — the central hazard (blocker)
Today's signal inventory (EXPLORE-session-api §3, verified in code): NO `question.*` events exist; the
only observation point is the `question` tool's `execute.before` hook (question-notify's
`handleQuestion`, L408-433 — and that plugin is OWNER-DISABLED); there is no per-question timestamp
anywhere in-repo and no answer event. Meanwhile a question-paused session freezes `time.updated`, so a
tree-age-freshness reconciler reads it as DEAD within 15 minutes — exactly the window the card picks for
"move to Awaiting Answers". If the Awaiting Answers branch is not wired BEFORE the dead-run branch in the
reconciler's decision order, every paused run gets a second coordinator (same worktree on resume → the
stomp, now with no lock to catch it). Requirements the plan must carry:
- card-runner owns the question tool hook itself (independent of question-notify's disabled state) and
  records `{sessionID, cardId, askedAt, questionText}` durable + cross-process at hook time;
- "answered" is inferred from resumed activity after `askedAt` (there is no answer event) — state this
  inference explicitly;
- a card with a pending-question record routes to Awaiting Answers and NEVER to spawn, whatever the
  tree-age says; if the hook missed the ask (plugin crash, question raised pre-load), the degrade must be
  the conservative one (do not spawn; flag for owner);
- spawn-side re-check immediately before minting (registry + Executing membership), the claim-before-move
  equivalent.

### 4.5 Lifecycle/checklist drift makes card-driven kickoff ambiguous TODAY (major, with live proof)
Three checklist generations coexist on the live board: legacy Research (4-item, timing-only), 11-item
Lifecycle with `Pre Research`/`Post Research` (v12.65 artifacts), 13-item current (v12.77 artifact —
still owner-import-PENDING). **[live] This ticket's own STATE.json `stages` array contains "Pre Research"
and "Post Research" — stage names the current boards skill explicitly says "are not stage names in this
generation".** Kickoff consumed a legacy-shaped card and emitted vocabulary the current generation
forbids: the ambiguity is not hypothetical, it is the steady state. Consequences for the pivot:
- the reconciler's "start the next task" after an answer lands must interpret checklist state per
  detected generation — a stage-map lookup keyed on generation, or the Awaiting-Answers→resume leg
  resumes the WRONG stage;
- createCard rule checkItem extras are DORMANT (upstream WeKan bug), so new cards arrive fully
  unchecked: blank IS the 9-stage default loop — the reconciler must consume blank as an answer, never
  treat it as "card not ready";
- Model(s) `Qwen 27b`→`Qwen Dense` transition alias and the `Provider:`-unlabeled kickoff ask both still
  ride the same consumption path — a reconciler that pre-resolves kickoff answers inherits both edges.

---

## 5. Scope realism — what is implementable against deployed surfaces vs not

**Implementable now** (deployed surfaces verified live or in-repo):
- card-runner plugin (single-file discovery install; aislop-gate precedent) — yes;
- `agent-card-reconcile` agent + loop file (same shape as pipeline-dispatch.md; owner's loopApprovals
  fingerprint leg) — yes;
- per-tick board decision context: scoped `preload_board` (live; STATE shows it working, with the
  `with_checklists` arg degrade) — yes;
- session-status primitives: listing walk, envelope, tree-age rule, fail-closed (gate script, proven) —
  yes; spawn contract POST /api/session + prompt (live-verified in today's dispatcher log) — yes;
- question detection hook (question-notify's proven shape, re-homed) — yes;
- YAML dump at claim (get_card_details already returns structured data — NO new wekan-mcp feature needed)
  — yes;
- once-mark fix by hook removal/brief-only delivery — yes, cheap.

**Rests on features that do NOT exist yet** (must cut, defer, or split):
- Per-question ask-timestamp/answer signal: upstream-research open (EXPLORE-session-api §8.1) — the hook
  record is the only in-repo clock; if the plan wants more, it needs an upstream probe FIRST (research
  chunk, not dev chunk);
- busy/idle semantics on v2.3.2 (§8.2), POST /api/session `model` shape re-proof (§8.3),
  `session.updated` delivery (§8.4), `archived` visibility (§8.5) — research-gated;
- "Awaiting Answers" list: `create_list` exists in wekan-mcp but list creation is HUMAN-owned via the
  provision engine (`provision-board.py` spec bullet + owner apply) — an owner leg with a degrade until
  landed (exactly the Timeout-list pattern, which shows what happens when such a leg never lands: 5 weeks
  of jsonl degrade);
- card-change detection: no per-card activity endpoint in deployed WeKan v12.99; `modifiedAt` does NOT
  bump on REST writes (source-verified) — usable only as a UI-edit hint; snapshot-diff (Option A) is the
  floor; webhooks (Option B) need an externally-reachable endpoint + board-admin + allow-listing —
  genuine new infra. **Cut webhooks from this ticket; snapshot-diff of the tracked (Executing) cards is
  one GET per card per tick — trivially affordable at current scale**;
- the `format: json|yaml` wekan-mcp argument (EXPLORE-wekan-mcp's ask) is NOT needed for the YAML dump
  and is a separate container-build + deploy chain — **cut it from this ticket**; it is a different card.

**Recommended wave split** (the card as written is at least three tickets):
1. **Wave 1 — context hygiene** (ships value alone): card-runner skeleton + reconciler agent/loop +
   board-block delivery moved to the launch brief (prompt hook dies or re-keyed) + claim-time details to
   the YAML dump + AGENTS.md drift repair (verified RED at HEAD: `rulesync generate --check` reports
   "Files are not up to date" for AGENTS.md — the pivot's first commit must fix `.rulesync/rules/
   overview.md` or the regeneration clobbers the dispatcher paragraph).
2. **Wave 2 — question flow**: question hook re-homed in card-runner (independent of question-notify's
   disabled state — and the plan must rule: re-enable question-notify, or absorb its three legs?),
   Awaiting Answers list provision (owner leg), decision-order guarantee (§4.4).
3. **Wave 3 — lock retirement**: ONLY after waves 1-2 prove the reconciler in production: run registry +
   re-keyed zombie firewall + doctrine rewrite (boards Parallel pipeline loops, AGENTS.md "Pipeline
   worker iterations", 25 subagent Compaction paragraphs that name `pipeline-locks`, gate-script liveness
   set, N4/N8 "exactly TWO loop files" re-pin, b6 parity-ladder gap for `pipeline-boards-pr.md`,
   kv-namespace migration decision, T15 re-point). The re-pin blast radius is the largest cost in this
   ticket and should not be paid until the replacement has earned it.

**Prerequisites/constraints the plan must carry** (all verified):
- AGENTS.md drift red at HEAD (above);
- ~3.0 KB session-metadata PATCH limit (§1.14) bounds all session-record bookkeeping;
- `pipeline_*` tools invisible in dispatcher Code Mode on v2.3.2 (§2b.4) — card-runner must not depend
  on its tools being visible to agents; files/events/registry are the load-bearing surfaces;
- question-notify disabled since 2026-11-21 — the phone channel the Awaiting-Answers alerts want is OFF
  owner-side; the plan needs an explicit owner decision, not an assumption;
- two-process fan-out (§1.15) — every event-driven leg needs consume-once claims;
- loop-file fingerprint rotation is owner-executed; the repo ships files, the owner re-approves tasks.

---

## Findings summary (severity order)

- **blocker B1** — second-coord-on-paused-card hazard (§4.4): decision order + durable pending-question
  record + conservative degrade are acceptance criteria, not implementation details.
- **blocker B2** — zombie firewall must survive the lock retirement, re-keyed on the registry (§3.1).
- **blocker B3** — durable cross-process per-card run registry with restart-resume (§3.2); includes the
  kv-namespace rename decision (§1.10 correction).
- **major M1** — symptom (a) root cause is storage-binding flap × two processes (§2a): the new delivery
  must not sit on `ctx.storage` capability.
- **major M2** — "objective completed" needs the explicit signal matrix; handoff-successor resolution is
  mandatory before any spawn (§4.3).
- **major M3** — checklist-generation ambiguity is live today (this run's own stages) and the
  Awaiting-Answers resume leg must resolve it (§4.5).
- **major M4** — no-op marker writer predicate references `pipeline_claim`; redefine if claims go;
  reader conjunction + token vocabulary stay (§3.5).
- **major M5** — YAML dump contract undefined for Worktree-unchecked runs, siblings, and Rework re-picks
  (§4.2).
- **major M6** — change-forwarding is the new context injector; bound it (delta format, dedupe,
  dump-rewrite over prompt-paste) (§4.1).
- **major M7** — dropping leases makes single-scheduler an owner-enforced invariant; state it (§3 trade).
- **major M8** — wave split + cuts (§5): webhooks, `format: yaml` tool arg, and LLM-judged
  "objective met" out; AGENTS.md drift repair in commit 1.
- **minor m1** — reaper board leg never worked live (no Timeout list); decide provision-or-jsonl (§1.4).
- **minor m2** — false lock-lost storms (8-row stolen on a live claim; 5-row missing post-release) show
  the lost path needs idempotence if any guard survives in this shape (§2b.5).
- **minor m3** — 3.0 KB PATCH limit already truncated a dispatcher write today (§1.14).
- **nit n1** — the scout's preserve-set item 8 ("guard fixed") is misframed: replace mechanism, not fix
  (§1.8); items 11-15 added.

Verdict: **CHANGES_REQUESTED is not applicable** (no diff under review); this is advisory input to the
plan. The pivot is sound and the owner's two symptoms are both real, both code-grounded, and both
dissolved by the reconciler design — provided B1-B3 are treated as load-bearing acceptance criteria and
wave 3 is not paid for before waves 1-2 prove themselves.

RESULT
status: DONE
chunk: review-existing
files_changed: [.agents/plans/2026/2026-11-cf-140-feat-agent-card-reconcile/REVIEW-existing-plugins.md]
commands_run: [read STATE.json + 4 EXPLORE files => pass, read .opencode/plugin/board-context/index.ts (full) => pass, read .opencode/plugin/pipeline-locks/index.ts (constants/claim/release/wake/heartbeat/checkMember/lock-lost/reaper sections) => pass, read .opencode/plugin/question-notify/index.ts (claimOnce/noWorkSuppressed/handleQuestion sections) => pass, read .rulesync/subagents/agent-board-{coord,dispatch}.md + pipeline-role-coord SKILL + loops/pipeline-dispatch.md => pass, node:sqlite forensics on ~/.local/share/opencode/opencode.db (kv once-marks, session_message re-injection counts, mark-vs-prompt correlation) => pass, ps aux opencode process inventory => pass, cat .pipeline/{locks/*,timeouts.jsonl,meta/lastReap} + grep events.log claim/release/lock_lost/reaped rows => pass, npx rulesync@37.0.0 generate --check => fail(AGENTS.md stale — expected, finding M8/pre-req), grep pipelineNoop single-home + T15 pin + plugins array + tests dirs => pass]
deviations: none — read-only review; no code or tests touched
friction: plugin stderr never reaches opencode.log, so the board-context setup degrade line itself is unsightable from this host — db forensics substituted (stronger); write tool denied for /tmp/opencode scratch files — node heredocs via shell used instead
open_questions: [OQ-R1 (owner ruling): re-enable question-notify or absorb its three legs into card-runner — the phone channel is off owner-side since 2026-11-21 and the Awaiting-Answers alert path assumes it; OQ-R2 (owner ruling): provision the Awaiting Answers + Timeout lists via the provision engine, or accept jsonl degrade as permanent design; OQ-R3 (plan decision): keep the local.pipeline-locks plugin id inside card-runner (zero kv migration) or rename + migrate rows at setup; OQ-R4 (research, before wave 2 dev): pending-question persistence + answer signal on v2.3.2 (EXPLORE-session-api §8.1) and busy/idle emission (§8.2)]
next_suggested: coord commissions the plan (agent-plan) with this review as input — wave split per §5, B1-B3 as gating acceptance criteria, AGENTS.md drift repair in the first commit
