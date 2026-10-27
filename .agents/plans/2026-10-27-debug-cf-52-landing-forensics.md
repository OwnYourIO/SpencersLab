# 2026-10-27 debug: forensics — how cf-52-feat-coord-session-inwork landed in main

**Type:** debug · **Status:** FINDINGS (read-only investigation, no changes made)
**Request:** user — "why is cf-52's work landing in main? A link somewhere was
missed; track it down so it gets created in the future."

## Verdict (one paragraph)

Nothing automated landed the branch. Every main-moving operation was a
**user-initiated OpenChamber GitView action** (integrate / merge / sync / push —
every audited record carries `initiator: "user"`, executed by
`openchamber-server-git`), run against a branch whose coord session was still
marked `openchamber.work.state: "open"` (in work) the entire time. It *could*
land because **no link exists between "in work" and "do not land"**: per cf-52's
own ratified design (DECISIONS D8/D12, user answer 4: "We should not be hanging
anything off in-work. It's a purely UI feature"), zero consumers read the
in-work state — not the pipeline gates, and not OpenChamber's integrate/merge/
push flows. The one mechanical link that *was* missing and is documented:
**the worktree→branch link at kickoff** — cf-52's worktree was created DETACHED,
the slug branch never minted (dev-1 friction). The fix for that
(`scripts/kickoff-mint-branch.sh` + mint contract, ticket
bug-kickoff-mints-run-branch) was itself riding on the cf-52 branch and landed
with it.

## Evidence timeline (all times UTC, Oct 26 → Oct 27 2026)

| Time | Event | Evidence |
|---|---|---|
| 15:17–16:07 | cf-52 pipeline runs (test/dev/review subagents) in worktree `5e680f/cf-52-feat-coord-session-inwork`; dev-1 records friction: **worktree DETACHED, named branch absent**; creates branch manually via `git checkout -b` | opencode.db sessions ses_e8735fa11/ses_e871f45b2/ses_e870ebe56; STATE.json dev-1 RESULT |
| 17:32:48 | cf-52 coord closes its run cleanly: "card #52 → Review ✅ … Your landing items: **PR to main**" then idle | session message 17:32:48 |
| **17:41:58** | **OpenChamber integration started: cf-52 → main.** GitView integrate flow creates temp worktree `oc-integrate-Ozu2FO` on `main` (`git worktree add --force`), cherry-pick of `1a6517c81` conflicts; OpenChamber injects 3 messages (Code-Mode catalog, conflict JSON, user-role prompt "Resolve cherry-pick conflicts… onto branch main") **into the cf-52 coord session** | session messages msgtype=synthetic/user 17:41:58; `createIntegrateTempWorktree` in @openchamber/web service.js |
| 17:46–18:01 | Coord can't reach the temp worktree (permissions); user: "Try again or pass to dev agaent" → coord launches agent-dev subagent with the resolution recipe | messages 17:46:06, 18:01:02 |
| **18:06:57** | Subagent `cherry-pick --continue` → `ffa9a75db` on main — **contaminated**: the temp worktree's index carried pre-staged unrelated content; commit includes forgejo/coder/custom-values files it shouldn't | main reflog 18:06:57; subagent reasoning 18:09–18:10 |
| 18:16–18:22 | User instruction ("make it make sense") → subagent clean-room remediation: `reset --hard 916044893`, contaminated commit preserved as **`backup/cf52-contaminated`** (that's what that branch is), fresh re-pick `9a48c916d`, test re-pin commit, 3 doc cherry-picks → 5 commits on local main | main reflog 18:19–18:20; subagent messages 18:19:16/18:20:37/18:22:10 |
| **19:28:45** | Audit record: `sync` succeeded (initiator=user) — OpenChamber sync = fetch + rebase local-only commits onto origin tip + **push** → cf-52's work reaches `origin/main` (release-charts follows) | source-control-audit.json; main reflog "rebase (start): checkout 081b57889" 19:28:47 |
| 19:44–19:51 | Branch rebased onto new main tip (`a5fbf4440`, "re-applied after temp-worktree loss"), then **ff-merge cf-52 → main** (UI action; no agent session ran it) | branch history; main reflog 19:51:10 |
| 21:23–23:22 | Follow-up friction tickets (tests-edit-perms, kickoff-mints, session-origin) execute **stacked on the cf-52 branch** ("landed-stack"); their commits keep landing in main via ff-merge (22:06) and another integrate cherry-pick run (23:22) | first-parent main log 22:06/23:22; branch history |
| 23:30–23:49 | Direct commit on main (dev-boards fix), reset+cherry-pick of llama-swap C04 chain (23:46, another integrate run), sync push, release-charts `8922894cb` 23:49 | main reflog 23:30–23:46; audit sync 23:30 |
| 02:51–02:55 | Cherry-pick of 2 session-origin doc commits onto local main; no-op merge attempt of cf-52 ("updating HEAD") | main reflog 02:51:36/02:55:44 |
| 12:11:03 | Audit: **push failed** (TRANSPORT_FAILED) → direct commit on main (cf-58 docs) → `pull --rebase` onto `8922894cb` (re-picks the 2 doc commits → duplicate shas `e9ce592d0`/`a0b70c4ff`) | git-network-operations.json record; HEAD reflog 12:11 |
| **12:35:28** | `merge cf-52-feat-coord-session-inwork` (ort strategy) → `e27b83825` — brings the entire remaining branch in: session-origin + kickoff-mints feature commits, re-pins, friction docs | main reflog 12:35:28; merge parents e25919a2a + 44ae924c4 |
| after 12:35 | `origin/main` now == `e27b83825` (FETCH_HEAD last touched 12:17 ⇒ updated by a push, not a fetch). No agent session ran `git push` in this window — push came from OpenChamber/user | `git rev-parse origin/main main`; opencode.db shell-command search |

## What the agents did and did not do

- **Did:** resolve the integration conflicts when OpenChamber routed them to
  the cf-52 coord session (17:41 handoff), under explicit user instructions;
  the clean-room re-pick remediation at user direction. All of it on the
  integration temp worktree / local main — and it was user-prompted each step.
- **Did not:** no agent session ran `git merge`/`cherry-pick`/`push` into main
  on its own initiative. The ff-merges (19:51, 22:06), the merge (12:35) and
  all pushes trace to OpenChamber user actions (audit `initiator:"user"` for
  every recorded git operation; agent shell logs contain none of them).
- cf-52's own contract was honored by the agents: "landing stays user-owned
  (PR merge)" (plan Landing note 1, dev-1 RESULT "no push, no merge").

## The missed links (what "gets created in the future")

1. **Worktree→branch link at kickoff (the documented one).** `worktree_create`
   left cf-52's worktree DETACHED without minting
   `cf-52-feat-coord-session-inwork` (dev-1 friction, later re-statused
   `fixed`): **bug-kickoff-mints-run-branch landed
   `scripts/kickoff-mint-branch.sh` + the kickoff mint contract
   (create → mint → rename → mark → move)**. That fix landed *with* cf-52's
   merge — so future kickoffs mint the named branch. Verify on the next
   board run that the worktree actually sits on its slug branch.
2. **In-work→landing-guard link (the architectural one — does not exist
   anywhere).** `metadata.openchamber.work.state` was `"open"` the whole time
   (live-checked: coord session metadata carries `work {state:"open",
   openedBy:"auto"}`, never done), yet integrate/merge/sync/push faced zero
   friction: this was deliberate design (D8/D12: "purely UI", "zero
   consumers"). If in-work should *protect* a branch, a consumer must be
   added — options, cheapest first:
   - OpenChamber-side: in the integrate/merge dialog, warn (or require
     confirm) when the source branch is the checked-out branch of a session
     whose `openchamber.work.state == "open"`. (OpenChamber already has both
     facts — the session→directory map and the work state.)
   - Repo-side gate (fits the pipeline posture better, cf-50 D4's fail-open
     concern): a pre-push/CI check that flags pushes to `main` containing
     commits from a branch whose ticket card is not in Finished / whose
     STATE.json is not `complete`.
   Note: this reverses user answer 4 from cf-52 — it is a decision, not a
   bug fix.
3. **Integration-conflict routing link (worked as designed, worth knowing).**
   When an integrate cherry-pick conflicts, OpenChamber hands the conflict to
   the session tied to the source work — with a user-role prompt. Agents will
   therefore resolve integration conflicts when asked. If that's not wanted,
   the routing/acceptance of that synthetic handoff is the knob.

## Residue still on the board (not touched — branch is in work)

- Worktree `5e680f/cf-52-feat-coord-session-inwork` is DETACHED at the old
  main tip `e25919a2` with an unresolved merge state (`UU` in
  `tests/agent-board-coord/gate.sh`, `rulesync-surface.sh`,
  `tests/coord-inwork/surface.sh`; `DU tests/kickoff-branch/surface.sh`;
  staged `scripts/session-origin.sh` + `tests/session-origin/*`) — leftover of
  the integration machinery / stacked follow-ups. Its branch tip `44ae924c4`
  is now fully merged via `e27b83825`; the worktree needs reattach-or-retire,
  but only once the user confirms no session is driving it (it was touched
  12:12 today).
- `backup/cf52-contaminated` = the contaminated first cherry-pick
  `ffa9a75db`; keep as evidence until the user says otherwise.
- The 12:11 pull-rebase created **duplicate copies** of two session-origin doc
  commits (`3a7b2dba7`/`ffdd27a75` local picks vs `e9ce592d0`/`a0b70c4ff`
  re-picks) — harmless doc duplication, now part of main's history.
- The 10 `oc-integrate-*` temp worktrees from these runs were removed
  2026-10-27 ~12:36 (user-approved, see 2026-10-27-chore-worktree-branch-cleanup.md
  Phase 1) — after the 12:35 merge completed; no in-flight integration was
  orphaned.

## How this was verified

- `git reflog show main` / `git reflog` (every cherry-pick, merge, reset, pull
  with timestamps); `git log --first-parent`; ancestry checks
  (`merge-base --is-ancestor`); `git branch -r --contains`.
- OpenChamber state: `source-control-audit.json` (176 records, all
  `initiator:"user"`, executor `openchamber-server-git`),
  `git-network-operations.json` (the 12:11 failed push record),
  `sessions-directories.json`, `~/.config/openchamber/tmp` mtimes.
- OpenChamber source: `@openchamber/web/server/lib/git/service.js`
  (`integrateWorktreeCommits`, `createIntegrateTempWorktree`,
  `computeIntegratePlan`, `syncCleanIntegrateTargetWorktrees`) +
  `routes.js` (`POST /api/git/integrate/{action}`, `runAsUserAction`).
- opencode.db (`session_v2`, `session_message`, `worktree`): session
  identities, directories, metadata (`work.state`), and the full message
  trail of the integration handoff, subagent launches, and user instructions;
  shell-command searches across all sessions in every merge/push window.