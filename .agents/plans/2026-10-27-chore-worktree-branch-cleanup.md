# 2026-10-27 chore: worktree & branch cleanup

**Type:** chore · **Status:** Phase 1 EXECUTED 2026-10-27; Phases 2–3 deferred by user
**Requested by:** user ("open main branches slowing down my UI — scan and propose cleanup")

## Context & goal

The UI (OpenCode/OpenChamber worktree listing) is slow because this repo has
**79 git worktrees** (1 main checkout + 78 linked) spread over three
locations, plus 78 local branches. Many are finished work that already
reached `main`, including **10 stray checkouts of `main` itself** — the
"open main branches" from the request.

Reclaim the UI surface area (and ~1.4 GB disk) by removing finished/stale
workspaces and branches, keeping everything with unmerged commits, and
fixing a handful of anomalous worktree↔branch pairings. No work may be lost:
anything unique and unmerged gets an explicit rescue-or-discard decision.

## Verified facts (evidence-bearing, 2026-10-27)

- `git worktree list`: 79 entries. `git worktree prune --dry-run`: clean
  (no stale registrations).
- `main` == `origin/main` (`rev-list --count` 0/0). `git fetch prod` fails
  from this environment (no access) — remote-branch deletions in Phase 5 are
  user-executed anyway.
- Disk: `~/.config/openchamber/tmp` 195 MB, `~/.local/share/opencode/worktree`
  972 MB, `.agents/worktrees` 216 MB.
- Worktree metadata mtimes: `cf-58-feat-standalone-agent-merge` 12:17 and
  `cf-52-feat-coord-session-inwork` 12:12 **today, during this scan** — a
  session appears to be live in those trees. `oc-integrate-pNfYQw` last
  touched 02:51 today.
- Merge status per branch computed with `git merge-base --is-ancestor <br> origin/main`
  and `rev-list --left-right --count origin/main...<br>`.
- Dirty-content verdicts: for each dirty path, `git diff main --quiet -- <paths>`
  in the worktree (NOISE = working tree now identical to `main`, UNIQUE = differs).
- Cross-check on UNIQUE content: `charts/coder/coder-templates/kubernetes-hardened/`,
  hivetools pg-airman config, and the ilias/okd/immich-analyze/erp-next/mariadb-operator
  charts **all already exist on `main`** — the uncommitted edits in those
  old worktrees are superseded leftovers, not missing work.

## Classification

### A. The "open main branches" — 10 OpenChamber tmp checkouts of `main` (REMOVE)

`~/.config/openchamber/tmp/oc-integrate-{2Iq42r,36C9ph,470XhU,4nJVLr,7lucar,J8WVH1,Ozu2FO,SFyNk7,UmghZS,pNfYQw}`

All 10 have `refs/heads/main` checked out at exactly `main`'s HEAD, all are
dirty in the index (20–407 staged files each: mass `D` entries for files that
exist on `main`, `A`/`M` entries, one has an unresolved `UU` conflict in
`tests/agent-board-coord/gate.sh`). This is the signature of interrupted
merge-integration attempts, not work products. mtimes: Oct 24 → Oct 27 02:51.

**Gate:** confirm no OpenChamber integration job is currently running, then
remove with `git worktree remove --force` + `rm -rf` (force is required
because indices are dirty; user sign-off on the force is mandatory).

### B. Merged branches + clean worktrees — safe batch (REMOVE worktree + branch)

Branch fully in `origin/main` (ahead=0), worktree `dirty=0`:

| Worktree | Branch |
|---|---|
| `.agents/worktrees/add-mariadb-operator` | add-mariadb-operator |
| `.agents/worktrees/add-music-to-media` | add-music-to-media |
| `.agents/worktrees/add-named-weights-for-models` | add-named-weights-for-models |
| `.agents/worktrees/add-pictaria-with-skills` | add-pictaria-with-skills |
| `5e680f/bug-kubernetes-mcp-toml-openrouter-qwen3-8-flash` | bug-kubernetes-mcp-toml-openrouter-qwen3-8-flash |
| `5e680f/cf-50-feat-prevent-multiple-agent-board-coords` | cf-50-feat-prevent-multiple-agent-board-coords |
| `5e680f/feat-board-coord-intake` | feat-board-coord-intake |
| `.agents/worktrees/opencode-mcp-global-hardlink` | feat/opencode-mcp-global-hardlink |
| `ae3f6…/alright-so-i-d-like-to-revisit-the-containers-code-fusion-mvekqccb` | alright-so-i-d-like-to-revisit-the-containers-code/fusion-mvekqccb |
| `ae3f6…/alright-so-we-recently-implemented-forgejo-in-the-openrouter-qwen-qwen3-8-2-4t-a{,-calm-circuit,-proud-falcon}` | alright-so-we-recently-implemented-forgejo-in-the-/openrouter-qwen-qwen3-8-2-4t-a95b/{1,2,3} (3 identical branches, same tip) |
| `ae3f6…/can-you-take-this-guide-and-implement-it-for-this-openrouter-qwen-qwen3-8-{2-4t-a,flash}` | can-you-take-this-guide-and-implement-it-for-this-/{openrouter-qwen-qwen3-8-2-4t-a95b,openrouter-qwen-qwen3-8-flash} |
| `ae3f6…/lucid-dolphin` | lucid-dolphin |
| `ae3f6…/we-need-to-move-the-postgres-mcp-server-to-this-{fusion-mve80ksk,gpu-moe-kat-coder-q6}` | we-need-to-move-the-postgres-mcp-server-to-this/{fusion-mve80ksk,gpu-moe-kat-coder-q6} |

Merged branches with **no worktree** (branch delete only):
`chore-helm-default-path-openrouter-qwen-qwen3-8-27b`, `feat-forgejo-ssh-ssh`,
`fix-mcp-servers/openrouter-qwen-qwen3-8-2-4t-a95b/1`.

**Mechanism:** `git worktree remove <path>` (plain, no force — they are
clean) then `git branch -d <branch>` (`-d` refuses if not merged — built-in
safety).

### C. Merged branches + dirty worktrees (RESCUE decision, then REMOVE)

Branch is fully in `main`; the dirt is uncommitted leftovers.

**C1 — NOISE (working tree already equals `main` for every dirty path): remove freely**

- `.agents/worktrees/add-erp-next-to-grow-service` (1 file)
- `.agents/worktrees/add-mayan-edms-to-grow` (1 file; note: branch itself is
  unmerged ahead=5 — check the 5 commits before deleting the branch; the
  worktree removal is still safe)

**C2 — UNIQUE leftovers, but the underlying work verifiably landed on `main` via other branches. Recommend: archive untracked plan docs, discard the rest.**

| Worktree (branch) | Dirty content | Landed-on-main evidence |
|---|---|---|
| `.agents/worktrees/add-ilias-to-grow` | 6 chart/services edits + untracked plan doc | `charts/ilias` in main |
| `.agents/worktrees/add-immich-analyze` | 3 values edits + untracked plan doc | `charts/immich-analyze` in main |
| `.agents/worktrees/add-immich-analyze-with-skills` | 2 chart edits + untracked plan doc | `charts/immich-analyze` in main |
| `.agents/worktrees/add-mediamanager-lazylibrarian-and-audiobookrequ` | 1 `charts/minuspod/values.yaml` edit | minuspod history in main |
| `.agents/worktrees/add-okd-to-grow` | plan doc + 2 services edits | `charts/okd` in main |
| `ae3f6…/g1-alright-so-i-d-like-to-revisit…` | staged coder-template renames, untracked `kubernetes-hardened/` + `workspace-startup.sh` + `tests/` | `kubernetes-hardened` + `kubernetes` dirs both in main |
| `ae3f6…/we-need-to-move-the-postgres-mcp-server-to-this-openrouter-qwen-{qwen3-6-35b-a3b,qwen3-8-2-4t-a95,qwen3-8-27b}` | hivetools chart/values edits + plan doc | pg-airman config in main |
| `ae3f6…/can-you-load-the-rulesync-skill-as-well-as-buildin-{gpu-ai-qwen3-8-27b-q8,openrouter-deepseek-deepseek…,openrouter-qwen-qwen3-6-35b-a3b,openrouter-qwen-qwen3-8-2-4t,openrouter-qwen-qwen3-8-flash}` | 23–62 modified `.opencode/agents/*.md` (generated surfaces, stale regen from old bases) | `.opencode/agents` current on main; branches are parallel runs of one task |
| `.agents/worktrees/feat-gpu-ai-proxy-backup-services` | `.opencode/opencode.json`, `agent-config.jsonc`, proxy values | branch merged; branch pushed to origin (remote branch deletion is Phase 5/user) |

**Rescue step per worktree before removal:** copy untracked `.agents/plans/*.md`
docs into the main checkout (or discard on user say-so); optionally stash
interesting diffs with `git -C <wt> diff > /tmp/opencode/rescue/<name>.patch`
as cheap insurance.

### D. Unmerged branches — KEEP (user's PR queue / in-flight work)

Recent, active-looking (last commits Oct 25–27): `cf-49-bug-friction-followup-cards`
(ahead 33), `cf-52-feat-coord-session-inwork` (ahead 18), `cf-58-feat-agent-context-merge`
(ahead 5), `cf-58-feat-standalone-agent-merge` (ahead 9), `fix-paperless-startup-probe`,
`fix/seaweedfs-{admin,csi-fsgroup-policy,filer-http}`, `fix/k8s-monitoring-v4`,
`feat/ha-lifecycle-notify` (ahead 1), `dep-wekan-12.64-home-mongodb` (ahead 2),
`debug-flash-next-vulkan-oom` (ahead 13), `chore-install-aislop-cli` (ahead 7).

Older unmerged (Oct 17–25) — candidates for the user's PR review, not deletion:
`feat-agent-board-coord…` (ahead 25), `feat-dev-mcp-fleet…` (ahead 14),
`feat-forgejo-infra-and-{dev-runner-3,runner-gpu-ai…,runner-openrouter…}`,
`feat-seaweedfs-mcp-{qwen38-flash,xhigh}`, `refactor-forgejo-runner-per-instance-apps`,
`forgejo-auth-support`, `context-fine-tuning`, `feat/coder-workspace-debian-rebuild`,
`we-need-to-move-the-postgres-mcp-server-to-this/fusion-mvekra9w` (ahead 1),
`g2/g3/g4-alright-so…`, `can-you-load…/fusion-mvcs8r5s`, `add-dev-server` (ahead 4),
`add-pictaria-to-home-services` (ahead 6), `add-mayan-edms-to-grow` (ahead 5),
`bug-llama-swap-echo-proxy-port` (ahead 9), one-commit doc/dep branches
(`dep-wekan-mcp-v60-pin`, `docs-wekan-mcp-ops-learnings`, `feat-board-checklist-sets`,
`feat-wekan-mcp-add-checklist-item`, `fix-boards-review-list`, `gpu-dns`,
`please-implement-agents-plans-2026-09-27-bug-keycl/…`, `sim-c04`,
`llama-swap-config-generation`, `backup/cf52-contaminated`).

### E. Anomalies (fix during cleanup)

1. **Worktree/branch name mismatch:** `5e680f/feat-forgejo-ssh-ssh` worktree
   has `dep-basechartversion-1.0.199` checked out (ahead 11, behind 524,
   upstream oddly set to `origin/main`). The actual `feat-forgejo-ssh-ssh`
   branch is merged and deletable (B). The 11 commits of
   `dep-basechartversion-1.0.199` are likely a duplicated baseChartVersion
   bump — verify with `git log origin/main..dep-basechartversion-1.0.199`
   before discarding.
2. **Detached worktrees diverged from their branches:**
   - `5e680f/bug-llama-swap-echo-proxy-port` detached at an old commit with
     1 dirty file while branch tip is ahead 9 — reattach HEAD to the branch
     or fold the dirty file in before removal.
   - `5e680f/cf-52-feat-coord-session-inwork` detached at `main` tip, 7 dirty
     files, branch ahead 18 — **live (mtime 12:12 today), do not touch now**.
   - `5e680f/cf-58-feat-standalone-agent-merge` detached at `main` tip, 11
     dirty, branch ahead 9 — **live (mtime 12:17 today), do not touch now**.
3. **`recovery` branch:** last commit 2025-09-27, ahead 3507 / behind 6817 —
   a year-old rescue snapshot. User decision: delete or keep as archive tag.
4. **Stashes:** 2 OpenChamber stashes (`stash@{0}` on add-music-to-media
   2026-10-25, `stash@{1}` on main 2026-10-18). Inspect before Phase 2
   removes add-music-to-media.
5. **Upstream misconfig:** `fix-paperless-startup-probe`,
   `fix/seaweedfs-csi-fsgroup-policy`, `dep-basechartversion-1.0.199` track
   `origin/main` directly. Harmless, but worth unsetting when those branches
   get pushed for real.

## Execution plan (phased, each phase needs its sign-off)

### Phase 0 — Pre-flight (no mutations)
- [ ] User confirms no OpenChamber integration jobs are running.
- [ ] User confirms no editor/agent sessions are open in worktrees slated for
      removal (especially anything under `~/.config/openchamber/tmp`).
- [ ] Inspect both stashes (`git stash show -p stash@{0}` / `stash@{1}`);
      decide keep/drop.

### Phase 1 — Remove the 10 oc-integrate tmp worktrees (A)
For each of the 10 paths:
```bash
git worktree remove --force /home/coder/.config/openchamber/tmp/oc-integrate-XXXX
```
(`--force` justified: dirty indices contain only merge-conflict residue on
`main`@HEAD — verified above; user explicitly approves the force.)
Then `git worktree prune -v`, and confirm `git worktree list` dropped to 69.
**Unblocks the UI immediately — `main` is checked out in 1 place again.**

### Phase 2 — Batch-remove merged clean worktrees + branches (B)
```bash
git worktree remove <path> && git branch -d <branch>   # per row of B
git worktree prune -v
```
`-d` (not `-D`) is the safety: any branch that is somehow not merged aborts.
17 worktrees + 3 branch-only deletes → 35 branches gone.

### Phase 3 — Rescue-then-remove merged dirty worktrees (C)
Per worktree:
```bash
mkdir -p /tmp/opencode/rescue/$(basename <path>)
# copy untracked plan docs
git -C <path> status --porcelain | awk '$1=="??"{print $2}' | \
  xargs -I{} cp --parents {} /tmp/opencode/rescue/$(basename <path>)/ 2>/dev/null
# insurance patch of the uncommitted diff
git -C <path> diff > /tmp/opencode/rescue/$(basename <path>)/uncommitted.patch
git worktree remove --force <path>
git branch -d <branch>
```
C1 (NOISE) skips the rescue copy. 16 worktrees. Decide beforehand whether the
rescued plan docs get committed to `main` (a small follow-up commit/PR) or dropped.
`add-mayan-edms-to-grow`: worktree removal OK, but **keep the branch** until
its 5 unmerged commits are reviewed (it's really a D item).

### Phase 4 — Anomalies (E)
- Delete branch `feat-forgejo-ssh-ssh` (merged). Decide the fate of
  `dep-basechartversion-1.0.199` + its mismatched worktree after inspecting
  its 11 commits.
- Reattach or fold the `bug-llama-swap-echo-proxy-port` detached worktree.
- Revisit the two live cf-52/cf-58 detached worktrees once their sessions end.
- `recovery` branch: user decides delete vs. convert to tag.
- Unset bogus upstreams where branches will live on.

### Phase 5 — Remote hygiene (user-executed only)
Pushed branches that got deleted locally and are fully merged:
```bash
git push origin --delete <branch>   # for each, user runs
```
Known pushed + merged: `feat/gpu-ai-proxy-backup-services` (after Phase 3).
`add-dev-server` and `can-you-load…/fusion-mvcs8r5s` are pushed but UNMERGED —
leave. Never push/delete anything touching `main`; the agent does not push.

### Phase 6 — Prevention (optional follow-up work)
- On ticket close (`agent-coord` final review / plan-complete), delete that
  ticket's worktree as part of the closeout — record as a FRICTION item or a
  pipeline-conventions note.
- A small scheduled gate (like the existing hourly boards gate) that lists
  worktrees on merged branches and nudges the user.
- OpenChamber: tmp integration dirs should be removed when the job finishes;
  file an upstream issue / add a startup sweep.

## Expected outcome

| | Before | After phases 1–3 |
|---|---|---|
| Worktrees | 79 | 42 (main + unmerged/anomalous) |
| Local branches | 78 | 42 |
| `main` checkouts | 11 | 1 |
| Disk in worktree dirs | ~1.4 GB | ~0.5 GB |

## Execution log

**2026-10-27 Phase 1 — DONE** (user-approved): all 10 `oc-integrate-*` tmp
worktrees removed with `git worktree remove --force`; `git worktree prune`
clean; `~/.config/openchamber/tmp` now empty (freed 195 MB). Worktrees
79 → 69; `main` checked out in exactly one place again. No impact on
branches, stashes, or the main checkout.

**Note:** while executing, `main` advanced `e25919a2 → e27b83825`
("Merge branch 'cf-52-feat-coord-session-inwork'") — a live integration
completed normally (no orphaned job in the removed tmp dirs). Consequences
for later phases:
- `cf-52-feat-coord-session-inwork` is now fully merged → it joins the
  Phase 2/3 candidate list (branch deletable). Its worktree
  `5e680f/cf-52-feat-coord-session-inwork` is still detached at the OLD main
  tip with 7 dirty files and was touched at 12:12 — confirm its session has
  ended before touching it. Full landing forensics (how/why the branch landed
  in main): `2026-10-27-debug-cf-52-landing-forensics.md`.
- Re-ran the full merged-ancestry check after the move: the only newly
  merged branch is cf-52 itself. Phases 2/3 classifications above remain
  valid, but re-verify merge status at execution time (main moves often).

**Phases 2–3 — DEFERRED by user** (2026-10-27). Plan of record stays here;
resume with the phase gates above.

**2026-10-27 Phase H — user-highlighted families CLEANED (executed).**
The user boxed families in the OpenChamber sidebar and directed cleanup of
their workspaces, branches and sessions. Removed (worktree + branch + session
records), after re-verifying each at execution time:

- `alright-so-i-d-like-to-revisit-the-containers-code/fusion-mvekqccb`
- `alright-so-we-recently-implemented-forgejo-in-the-/openrouter-qwen-qwen3-8-2-4t-a95b/{1,2,3}`
- `can-you-load-the-rulesync-skill-as-well-as-buildin/{gpu-ai-qwen3-8-27b-q8, openrouter-deepseek-deepseek-v4-1-flash-1017, openrouter-qwen-qwen3-6-35b-a3b, openrouter-qwen-qwen3-8-2-4t-a95b, openrouter-qwen-qwen3-8-flash}` (dirty leftovers rescued to `/tmp/opencode/rescue/<slug>/` first; content verified superseded by main)
- `can-you-take-this-guide-and-implement-it-for-this-/{openrouter-qwen-qwen3-8-2-4t-a95b, openrouter-qwen-qwen3-8-flash}`
- `feat/coder-workspace-debian-rebuild` (git cherry vs origin/main: all six commits patch-equivalent `-`; origin copy retains the branch)
- `fix-paperless-startup-probe` — **content NOT on main** (paperless startupProbe failureThreshold 120 + rationale comment; main still 30). Preserved as `backup/2026-10-27-fix-paperless-startup-probe` @ 7ec953a1b before `-D`. Revive or PR it when wanted.
- `g1/g2/g3-alright-so-i-d-like-to-revisit-the-containers-code/openrouter-qwen-qwen3-8-2-4t-a95b` — fusion-discarded parallel attempts; the adopted lineage is the debian-rebuild branch above (all-`-` cherry). `g4/…` deliberately KEPT (not highlighted; preserves an attempt lineage on disk). g2's dirty entries rescued.
- `we-need-to-move-the-postgres-mcp-server-to-this/{fusion-mve80ksk, gpu-moe-kat-coder-q6, openrouter-qwen-qwen3-8-2-4t-a95b, openrouter-qwen-qwen3-8-27b}` (pg-airman config verified on main)

Already gone before the script ran (user cleaned from the UI mid-session):
`we-need-to-move-…/fusion-mvekra9w` and `…/openrouter-qwen-qwen3-6-35b-a3b`
(refs + worktrees); their branches' absence was verified, not assumed.

Sessions: 17 top-level session records deleted via
`opencode api delete /api/session/<id>`; OpenCode cascade-removed their 90
child sessions (verified: 0 session rows remain for any cleaned worktree
directory). KEPT: `can-you-load-…/fusion-mvcs8r5s` (unmerged, live session,
not highlighted) and everything outside the boxed families.

Result: worktrees 69 → 47, branches 78 → 61, worktree disk 972 MB → 641 MB.
Main checkout untouched (only the two untracked plan docs). The cf-52
worktree rebase (stopped at 6cd624702, 4 unmerged paths) was NOT touched —
its resolution proposal stands awaiting a decision.

## Hard rules respected

- No merge/push to `main`; remote deletions are user-executed (Phase 5).
- `git branch -d` (never `-D`) for batch deletes; `--force` worktree removal
  only on explicitly user-approved rows.
- Live worktrees (cf-52, cf-58-standalone) are hands-off until sessions end.
- Nothing deleted that has unmerged commits without a user decision.