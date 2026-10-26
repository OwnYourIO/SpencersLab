# PLAN: Kickoff mints the run's git branch
feature: 2026/2026-10-bug-kickoff-mints-run-branch

## Goal

`pipeline-kickoff` says "**Worktree + branch**: `opencode` tool `worktree_create`" (SKILL.md L32), but `worktree_create` produces a detached-HEAD worktree and never mints the named branch — every run rediscovers this and hand-creates the branch later (cf-50 test-writer, cf-52 dev; the worktree here still shows the detaching default: `bug-llama-swap-echo-proxy-port` sits on detached HEAD at f11bfcb85). Fix: kickoff explicitly mints the branch, executed by both coordinator variants through a validated repo script, and the contract text becomes honest about what the tool does.

Friction source (verbatim, cf-52 FRICTION.md line 12, dev(C01), status open; also STATE.json `deferred[3]`):
> 2026-10-26 · dev(C01) · the ticket worktree sat on detached HEAD and the STATE.json-named branch did not exist — worktree_create apparently detaches without minting the slug branch · resolution: committed detached then `git checkout -b cf-52-feat-coord-session-inwork` at the commit (local-only, base f11bfcb85 preserved); kickoff/worktree surface should actually create the named branch — follow-up candidate · open

## Severity — honestly

Observed data loss: **none** — both workarounds (`checkout -b` at/after the commit, cf-50 a42dc2896, cf-52 1a6517c81→branch@{2} reflog "Created from HEAD") preserved the base commit f11bfcb85 and all content. Detached commits stay reachable via the worktree HEAD + reflog (90-day GC horizon). The damage is **contract + flow** class: STATE.json `kickoff.branch` is fiction at kickoff time (cf-50 and cf-52 both named a branch that did not exist until a session improvised); resume/D11 re-claim, `agent-fuser` branch comparison, and the user-owned PR/push step all key on a branch name that may never exist; and the friction repeats every run, which is exactly what FRICTION.md exists to prevent. Medium urgency, low loss-potential.

## Verified facts (grounding)

- Tool surface (catalog re-verified 2026-10-26): `opencode` exposes only `worktree_create{name}→{directory}`, `worktree_list`, `worktree_remove`. No branch parameter, no variant, no config knob found in `.opencode/opencode.jsonc` or the machine-global config (grep `worktree` → 0 hits). `worktree_list` reports `strategy:"git"` for all entries.
- Reflog sampling (`bug-kubernetes-mcp-toml-*`, `chore-install-aislop-cli-*`, `dep-wekan-12.64-home-mongodb`, `feat-board-coord-intake`, `cf-52-*`): every ticket branch's oldest entry is `branch: Created from HEAD` — **no branch was ever minted by worktree_create**; in-session `git checkout -b` did, every time.
- De-facto invariant: branch name == worktree directory basename (all sampled branches, incl. run-tagged plain runs like `dep-wekan-12.64-home-mongodb` where slug+tag == dir == branch).
- Owner problem: neither coord variant has a git shell grant (`pipeline-role-coord` L46: the `opencode` grant "exists only to name the run"; shell = exactly the two `opencode api` work-mark allows). A raw `git -C * checkout -b *` grant cannot scope the target directory — the same resource string would match `-C /home/coder/SpencersLab ...`, flipping the scheduled runs' main checkout off `main`. Dev/test "first act mints it" relies on `shell: * ask`, which is a documented silent-drift class (cf-50 FRICTION: ask-gated actions ran "WITHOUT surfacing approval prompts").
- Precedent: `scripts/agent-board-coord-gate.sh` — deterministic kickoff-adjacent logic lives in `scripts/`, agents invoke it through a narrow grant, a behavior suite lives under `tests/`.
- Test-anchor landscape (collision map for the edit): `tests/coord-inwork/surface.sh` i1 (kickoff windows — all needles live inside the in-work bullet, a L32-region edit preserves them; negative pin bans literal strings `in-work:`/`done:` anywhere in skill trees), i4 (coord-pair frontmatter: exactly-two-allows splice, `+6/-0` line pin, literal add-lines — **must re-pin**), i5 (freeze set includes AGENTS.md/.rulesync/rules, commands dirs, gate script — untouched by this ticket as long as AGENTS.md stays un-edited), i6 (pair-carry/sync/generator — holds). `tests/agent-board-coord/rulesync-surface.sh` c2 (PORT_REF byte-pin with cf-52's two-allow OR arm — **must re-pin**), c8 (scope allow-list — **needs this ticket's FEATURE4**), c16/c12/c17/i2/i3 (windows/carry-sets preserved by the planned wording). agents-md.sh c7 (FEATURE4 scope widening only; no AGENTS.md delta → c8's "no other section" holds trivially).

## Out of scope

- The allow-list machinery fix ("derive union pattern from active-feature-folder glob", cf-50 FRICTION open line) — separate concern, stays its own follow-up.
- `agent-test`'s missing `tests/**` edit allow (cf-52 FRICTION line 9, open) — separate follow-up ticket.
- `hivetools-kubernetes-mcp-docs.sh` d4 per-ticket allow-set (cf-52 deferred 2).
- AGENTS.md `scripts/` bullet update (see OQ3 — best guess: skip to keep i5 freeze green).
- Upstream feature request for a branch-minting `worktree_create`; run-tag/branch-naming changes; research-only-card worktree semantics.

## Commands

- unit: `bash -n scripts/kickoff-mint-branch.sh`
- unit: `bash tests/kickoff-branch/script.sh` (scratch-repo behavior suite, red before C01)
- contract: `bash tests/kickoff-branch/surface.sh` (text pins, both trees, red before C02)
- regression: `bash tests/coord-inwork/surface.sh` (i4 re-pinned for the third grant; i1/i2/i3/i5/i6 must hold)
- regression: `bash tests/agent-board-coord/rulesync-surface.sh` (c2 sanctioned-delta arm + c8 FEATURE4; c1–c17 others hold)
- regression: `bash tests/agent-board-coord/agents-md.sh` (c7 FEATURE4; all content pins hold)
- regression: `bash tests/agent-board-coord/gate.sh` (must stay green untouched — gate is frozen)
- regen: `npx --no-install rulesync generate --check` clean + `generate` ×2 second-run no-op
- lint: `npx --no-install aislop ci --changes` (0 errors)
- grep-proof trio (each run against source AND generated mirror): `kickoff-mint-branch` present in `pipeline-kickoff/SKILL.md`, `pipeline-role-coord/SKILL.md`, `boards/SKILL.md` (pairs), and the resource string `bash scripts/kickoff-mint-branch.sh *` present in `agent-coord.md`/`agent-board-coord.md` source + generated (4 files).

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | `scripts/kickoff-mint-branch.sh` + behavior suite | S | 1 | [] | — |
| C02 | Kickoff/role-coord/boards text + coord-pair grant + regenerate mirrors + re-pin i4/c2 + FEATURE4 scopes + surface text-pins | M | 2 | [C01] | The text names the exact command string the script must accept, and the frontmatter resource literal must equal the landed script path; C02's surface pins grep for text that only exists after C01's script defines the contract shape |

## Wave order

1. C01 (adds a file + its own suite; zero existing pins affected)
2. C02 (one coupled subsystem: contract text + grants + mirrors + re-pins land together — partial landing turns cf-52's suites red)

## Risks / assumptions

- **cf-52 lands first.** C02 re-pins cf-52's `surface.sh` i4 and the OR-arm of `rulesync-surface.sh` c2 — both only exist on this base after the user lands cf-52. On an un-landed base C02 is blocked; coord re-checks, landing is user-owned.
- OpenCode may one day mint the branch natively. The script is idempotent (existing branch → `EXISTS`, exit 0), so a future upstream fix degrades this to a no-op, not a break.
- Shell-resource glob semantics: `bash scripts/kickoff-mint-branch.sh *` is prefix-literal + trailing glob, the same shape as the landed cf-52 allows; `;`-chaining inside a matched command string is a residual class cf-52 already accepted for the `opencode api` grants — the script's own argument validation is the effective guard (it never evals its args).
- `agent-test` writes the new `tests/kickoff-branch/*` suites — may hit cf-52 FRICTION line 9 (no `tests/**` allow in its frontmatter). The cf-52 test session worked around it via parent-passed grants; this ticket plans the same workaround path and leaves the permission fix out of scope.

## Open questions

(All answers consumed as best guesses; batched round for the user via coord.)

- **Q1 — Mechanism owner.** Best guess: repo script + one scoped shell grant `bash scripts/kickoff-mint-branch.sh *` added to both coord variants (gate.sh precedent; wildcard-safe via in-script validation). Alternatives rejected: raw `git -C * checkout -b *` grant (cannot restrict the target directory — main-checkout flip hazard); dev/test first-act mint (relies on `shell:* ask` silent-drift, wrong owner — naming is kickoff's job, and a run that never launches dev still needs its branch); commands `!`-block minting (impossible: the slug is minted mid-session, after expansion). Impact: shape of all of C01+C02.
- **Q2 — Branch-naming invariant.** Best guess: keep de-facto `branch == worktree-dir basename` (verified across tagged and card-driven branches); the script enforces it. Alt: branch == bare slug always — rejected silently renames run-tagged plain runs' de-facto branches; out of scope. Impact: script validation + kickoff text.
- **Q3 — AGENTS.md `scripts/` bullet.** Best guess: do NOT touch AGENTS.md (its generic "repo-machinery scripts launched by pipeline surfaces" sentence already covers a second script; editing it trips surface.sh i5's byte-freeze + forces a second re-pin). Alt: update it and relax i5 for this ticket's AGENTS.md delta. Impact: C02 file set + i5 pin status.
- **Q4 — permissions.md matrix row.** Best guess: update the coord/board-coord shell cells to list all three scoped allows (this ticket changes the row's truth; agents-sync mandates the matrix reflect permission-block changes; it incidentally closes cf-52 deferred 1's shell half). Alt: leave stale per "by design". Impact: 2 more files in C02 (source+generated reference).
- **Q5 — Landing order dependency.** Best guess: user lands cf-52 before C02 runs (C02 re-pins cf-52's suite). Alt: re-plan C02 onto whatever base is live. Impact: execution scheduling only.
- **Q6 — Resume-path re-check.** Best guess: yes — one clause in kickoff's mint bullet + role-coord step 0 ("on resume, if the worktree exists and the branch is absent, run the same idempotent mint"). The script's `EXISTS`/`MINTED` verdicts make this safe. Impact: text only, inside i2 windows that must hold.
- **Q7 — Scope of this ticket's folder naming.** Best guess: `bug` type, slug `kickoff-mints-run-branch` (contract-vs-reality defect, not new capability). Alt: `chore`. Impact: folder/branch/worktree names only.
