# PLAN: question-notify consume-once claim — collapse the location-plugin fan-out to one push per event

branch: `bug/question-notify-fanout-dedup` · date: 2026-11-07 · type: bug
role: `code` (user-handed standalone debug → implement) · worktree: `.agents/worktrees/bug-question-notify-fanout-dedup`

## Symptom (user-reported, 2026-11-07)

The Home Assistant alerting plugin pushes duplicate phone notifications. Measured live in this
session (user-counted on the Pixel 6):

- **5 × "OpenCode: … finished"** from one session (this debug session, agent `code`) across its turn-ends.
- **2 × "needs approval"** from ONE on-screen approval prompt (user confirmed).
- **4 × "OpenCode: code finished"** for a single `session.execution.succeeded` event (the decisive measurement).
- **0** pushes for questions from a `code` session (agent-prefix filter works — not a bug, kept).

## Root cause (proven, not hypothesized)

question-notify is a **location plugin**: OpenCode loads one instance per active checkout per
server, and every instance subscribes to the server-wide public event stream — the v2 plugin docs
state `ctx.location` is "the plugin instance's location, not the location of every session it can
access or event it receives". Both live servers share one durable store
(`~/.local/share/opencode/opencode.db`), so the same event reaches every instance on every server:

- managed service (PID 9017, run `845cd46d`, started 15:05): loaded question-notify from
  **2 locations** (`/home/coder/SpencersLab`, worktree `cf-123-bug-tweak-init`)
- OpenChamber server (PID 837, port 4096, run `09cdee9e`, started 14:58): loaded it from **4 locations**
  (main + `fix-vllm-common-loader` + `cf-104` + `cf-123`)
- every per-location copy is byte-identical to main's (`diff -q` → 0) — this is NOT a version-skew bug
- the 15 s cooldown map is built inside `setup()` → per-instance memory; nothing dedupes across instances

One event → N pushes, N = loaded instances. v2.2.5 did not change the design; the restart +
multi-worktree board activity just raised N from "occasionally 2" to a visible storm.

**The fix mechanism, grounded:** the storage backend is the `kv` table, key namespace
`plugin:<plugin-id>:<key>` (verified by inspecting `local.pipeline-locks`' rows: `child/ses_*`,
`claim/ses_*` written from instances in main AND worktree locations). The namespace is keyed by
plugin id alone — no location, no server component — so a consume-once claim on
`ctx.storage` is shared by every instance in the fleet.

## Decisions (human rulings this session, 2026-11-07)

- D1: implement the `ctx.storage` consume-once dedup now, keys on event identity (question tool-call
  `id`, approval `requestID`, lifecycle event `id`), storage failure ⇒ push anyway (fail-loud kept).
- D2: lifecycle scope unchanged — every top-level finish/crash keeps alerting, 1× each after dedup.
  Rejected: agent-* only, scheduled only.
- D3: single approval prompt ⇒ 2 pushes confirmed as the dedup sample on that leg; no design change
  to the pending-15 s behavior.

## Changes (dependency order: tests red → plugin green)

1. `tests/opencode/question-notify.test.ts` — append T11–T13; extend `fakeDeps` with `opts.storage`
   (+ `opts.claimSwept` capture), `fakeCtx` with `storage: opts.storage` and a handler-capturing
   `tool.hook`, add `liveStorage()` helper + exported-seam name list grows `handleQuestion`/`claimOnce`/
   `sweepExpiredClaims`.
2. `tests/opencode/permission-ask-notify.test.ts` — `fakePermissionDeps` gains `opts.storage`; new
   cross-instance arms (same requestID, two shared-storage instances ⇒ one push; ask→reply consumes no
   claim; distinct ids ⇒ both push).
3. `.opencode/plugin/question-notify/index.ts` (hand-managed; never rulesync):
   - `CLAIM_TTL_MS` (15 min) + `claimOnce(storage, key)` / `sweepExpiredClaims(storage)` exported seams.
   - `handleQuestion(deps, event)` extracted from the `setup()` hook (same filter/agent/cooldown order;
     setup registers a thin wrapper that keeps the one-shot debug line and the fire-and-forget shape).
   - claim gates: FINISHED/CRASH keyed `lifecycle:<type>:<sessionID>:<event.id>` (only when the event
     carries an id — identity-gated fail-loud), approval keyed `approval:<requestID>` at fire time after
     the cooldown, question keyed `question:<tool-call id>`.
   - setup passes `ctx.storage` into deps and sweeps expired claims once per load (best-effort).
   - header comment: fan-out design fact, mechanism, improvement bound (get→set is not atomic across
     processes ⇒ rare double-push still possible, never systematic ×N), mixed-fleet caveat.

## Out of scope

- The per-turn "finished" push volume (D2 — user keeps it), HA-side notify history forensics,
  AGENTS.md blurb (stays accurate; it describes triggers, not dedup), any pipeline-locks/board-context
  change, the stale `plugin:probe:key` kv leftover (note for the user, not this branch's diff).

## Facts for later agents (all tool-verified this session)

- [EVID-1] 4× fan-out for one event — user count, session `ses_e4976ba77…` (agent `code`), ~15:07Z.
- [EVID-2] plugin stderr never reaches `opencode.log` on v2.2.5 (`grep -cF "[question-notify]"` → 1 hit, a
  shell command string, zero real lines) — log-based verification of this plugin is dead; phone-count and
  storage-rows are the live instruments.
- [EVID-3] `notify.mobile_app_pixel_6` exists and one direct `call_service` arrives exactly once — the
  transport leg was proven healthy before touching the plugin.
- [EVID-4] two live servers (`opencode serve` PID 837 @4096 + managed-service PID 9017) on one shared
  `opencode.db`; `/api/session` on one lists the other's worktree sessions.

## Risks / rollout notes

- **Mixed fleet**: a location whose checkout lacks the fix never consults claims ⇒ it keeps pushing
  blindly. Full silence arrives when every active checkout runs the new code (main via the user's PR;
  worktrees as their owners rebase; CuratedForest's twin copy carries the same plugin id so its claims
  interoperate the moment it lands there too).
- Race window: two instances can both claim within the same ms (no CAS primitive). Bounded improvement,
  not exactly-once; documented in the header.
- TTL window cost: a crash→fix→re-crash inside 15 min pushes once, not twice (accepted, tiny).

## Commands (validation)

Run from the worktree root. `node --test` per-file from the repo ROOT (FRICTION 2026-11-04 rerun law).

1. `node --test tests/opencode/question-notify.test.ts` ⇒ all pass (48 shipped arms unchanged + T11–T13);
   expected ~61/61. Red first (seams absent) is the designed TDD shape.
2. `node --test tests/opencode/permission-ask-notify.test.ts` ⇒ all pass (~41 + 4 new).
3. `node --test "tests/opencode/"*.test.ts` (quoted-glob explicit-file form) ⇒ baseline measured at branch
   start, then green at the same count + the new arms, 0 fail.
4. `bash tests/noop-marker/surface.sh` ⇒ exit 0 (pins reader literals in `$QN` incl. the N7
   crash-never-suppressed 900-char window — the edit must not scatter it).
5. `npx --no-install aislop ci --changes` ⇒ 0 errors (the file-too-large warning grows; pre-existing,
   accepted-by-design single-file convention).
6. helm lint/template: N/A (no chart touched).
7. Post-merge live check (user-side, the only end-to-end proof): one top-level turn-end ⇒ exactly 1 push;
   if still ×N, the envelope lacks `event.id` (claim stays identity-gated) — escalate, don't guess keys.

## Landing (user-owned)

Commit stays on `bug/question-notify-fanout-dedup`; PR/merge to main is the user's decision (hard rules).
