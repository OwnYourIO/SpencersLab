# PLAN: Broad git write grant for the coord family, guarded by a pinned deny floor (Candidate B)

feature: 2026/2026-10-cf-72-chore-coord-git-read-globs (card #72, WeKan AI-Dev)
revision: 2026-10-29 R2 — batched round answered: Candidate B ORDERED by the owner ("if the coord is responsible for git, it needs broad write options"); the A reads-only recommendation is SUPERSEDED (DECISIONS D10-D16). Design verified on the live repo: the proposed floor closes 90/90 matrix cells under `tests/agent-perms/surface.sh`'s own matcher simulation (`family.py policy`, fnmatch last-match-wins), probed 2026-10-29 at `/tmp/opencode/cf72-probe/probe.py`.

## Goal

Replace the six coord sources' prefix-literal 13-row read block with a BROAD git grant — one `git *` allow (option-first, `-C` cross-worktree, writes, `git worktree *` included) — made safe by a trailing deny family that pins every publish and main-advance shape: all push forms, every force/`-P`/`--force-with-lease` spelling, the make-main-HEAD legs (checkout/switch/worktree-add on `main*`), ref plumbing (`update-ref`, `symbolic-ref`), branch ops targeting main (`-f/-d/-D/-m/-M/-c/-C`), `pull`, any `merge` except main-INTO-branch, and the `git config alias*` smuggling cap. Sources + generated mirrors + all six pin/splice suites + the agents-sync matrix row move in ONE commit, executed as ONE single-session pass (owner-confirmed), then one final review.

## Out of scope

- Bare-`ls`/compound `VAR=…` posture (stays denied — note: `GIT_PAGER=x git log` therefore denies; `git --no-pager log` allows).
- Any force push, including `--force-with-lease` on a rebased feature branch — the shipped `-pr` block already denies all four force spellings and `pipeline-push-pr` states never force; the rebase-requires-force flow stays a USER step (AGENTS.md: forced feature-branch update needs explicit user request + confirmation).
- Non-coord families (dev/test/review/plan/fuser/standalone) — their blocks do not move.
- Landing on `main` (user's PR decision).

## Design

### The block (exact order; row 1 opens, rows 2-52 floor, rows 53-68 re-allow, tails absolute last)

All six sources carry rows 1-68 identically (row 1 = the broad allow, rows 2-52 = the deny floor, rows 53-68 = exception re-allows); the alias/`-local` pair carries tail **T-2**, the `-pr` pair tail **T-7** — absolute last in the block. Totals: **70 rows** (alias/-local) / **75 rows** (-pr) per file; twins byte-identical save `name:`/`description:`. The full row list with order is the chunk's contract (chunks/C01.md, "The block").

Mechanics the floor depends on (all re-verified against the repo's shipped simulator, `tests/agent-perms/surface.sh:415-431`):

- **Last match wins**: one `git *` allow opens the block; every deny follows it; exception re-allows follow the floor (rows 53-68 re-permit `merge main*`, `merge --abort/--continue`, and `-b/-B/-c/-C` creates whose TARGET is not main but whose start-point may be). The tails (push) are absolute last so a variant flip changes only the tail.
- **Double-space trap**: `git * checkout main*` cannot match bare `git checkout main*` (pattern literals need their own spaces) — every in-command rule ships as a (prefix-form, `git *`-form) pair. The exception is the owner-pinned force family: `git * --force*` / `git * -f *` / `git * -P *` match only when the flag is a later token — which is where git flags always are.
- **`git *push*` substring form** (T-2 second row) is what actually closes "push at any position": the spaced `git * push*` misses quoted args (`git commit -am 'push posture'` slipped in simulation — probe finding F1). Consequence, pinned as friction: on `-local`/alias the literal token `push` anywhere in a command string denies — commit MESSAGES about push work must reword (or use a message file whose NAME avoids the token); reads mentioning push (`git log --grep push`) die, erring safe. On `-pr` the substring row is absent by design — its own work mentions push legitimately.
- Bare `git` (zero args) denies via the `* * deny` baseline (`git *` needs a space) — harmless.

### Safety: the main-advance completeness chain (recorded in the decision log)

Advancing `main` requires one of: **(1) making main HEAD somewhere** — floored for `checkout main*` / `switch main*` / flag-mid forms / `worktree add … main` (incl. every `-C` twin); creating or moving a NON-main ref at/from main is allowed (`-b feat main`, `-B feat main`, `merge main`, `rebase main` — none touch the main ref). **(2) direct ref plumbing** — `update-ref`/`symbolic-ref` fully denied (no legitimate coord use; the ONLY ref-movers outside (1)); `branch -f/-d/-D/-m/-M/-c/-C` with a main token target denied. **(3) merging INTO main** — needs main as HEAD (blocked by (1)); every other merge shape dies at `git merge *` except the sanctioned `… merge main*` (main INTO current branch — cannot be main by (1)). **(4) publishing** — `-local`/alias deny `git push*` + `git *push*`; `-pr` feature-push lives with main-token forms denied (`git push*main*`, `git * push *main*`, `git * push` for the zero-arg-`-C` footgun, `git -C <main> push` with no args) and ALL force spellings denied (shipped posture preserved). **(5) history rewrite** — the force family floor-wide; amend stays ALLOWED (owner ruling: own-branch pre-push amend is legit; the published case is blocked because its only publish path, force push, is dead). **(6) alias smuggling** — `git * config alias*` denied: the one grant-side way `git <word>` could run push (residual model note: command globs guard ACCIDENT shapes; deliberate evasion via `--exec-path`/external helpers is contract+review territory, same as it always was — the old 13-row allow-list never defended against a determined writer either).

**Accepted residual (DECISIONS D13):** `git -C <main-checkout> commit/rebase/cherry-pick` — write verbs against another worktree's CURRENT branch — cannot be glob-restricted (D27: globs cannot restrict directories). The main checkout's HEAD is main only when the owner left it there; drift would be LOCAL, unrecoverable-remote (chain (4) holds), and repairable in the owner's own checkout. This is the direct cost of the owner's broad-write ruling and is recorded as accepted.

### Frictions (owner: "enumerate") — pinned into the chunk's matrix

`checkout/switch main*` reserves every branch/ref NAME starting `main` (incl. `maintain-*`, `main.py` as a checkout TARGET — file restores use `git restore`); `git -f`-family blanket (`branch -f feat HEAD` dies — use `-M feat feat`; `checkout -f <br>`, `clean -f -d`, `fetch -f`, `grep -f`, `rebase -f <up>`, `worktree remove --force` die — combined/trailing spellings like `-fd` pass, inconsistent-by-glob, safe-by-overshoot); `--force*` kills messages/flags containing `--force`; `pull` dies outright (rebase-onto-main is the sanctioned pickup, already the repo rule); `merge --no-ff main` dies at `merge *` (plain `merge main` passes); `git log --grep push` / commit messages with `push`/`main`-token shapes may deny on `-local` (reword).

## Grounding (verified facts, file:line at a92649bd3)

1. **Inventory** — six sources' git blocks identical (twins byte-equal save name/description): :79-119 13 allow rows + `git push*` deny (:118); -pr :118 push ALLOW + deny rows :121-133. Mirrors 14/19 rows comment-free. `date *`/SHELL5/API anchors untouched. fuser's `git worktree list` pair (:75-79) — unchanged, out of scope.
2. **Pins that move** (the cf-76 wave touchpoints; B replaces the whole 13-row sequence so ALL move): `tests/agent-perms/surface.sh` GIT_READS :343-344 + COORD_SUFFIX :357-366 (A12 whole-sequence equality :410 — effect-aware), A9 slug loop :730, policy controls :809-830 (kept; extended with the AC6 matrices); DEV_SUFFIX :351-356 + :402 UNCHANGED. `tests/coord-inwork/surface.sh` atpos COMMON/TAILS :406-413 (COMMON becomes (resource, effect) pairs; tails = T-2 | T-7) + comments :365,:402; cfpins :265-315 unchanged (all rows `git `-prefixed). `tests/kickoff-branch/surface.sh` synth strip-set :264-270 (replace enumeration with a `resource.startswith("git ")` projection — pinning stays honest because atpos3 checks the whole sequence), splice3 GITBLOCK :358-372 + equality :447, atpos3 :508-512, comments :19,:61,:263,:504. `tests/session-origin/surface.sh` splice4 :311-325+379-381, atpos4 :435-439, synth :481-483, GB :544-548, comments :69,:403,:431,:476,:542. `tests/agent-board-coord/gate.sh` t17 COMMON/TAILS :343-351 + :340, t14 admits :710-738. `tests/agent-board-coord/rulesync-surface.sh` c8 admits (no row list — delegates per :284). `tests/agent-board-coord/agents-md.sh` c7 admits. Matrix `.rulesync/skills/agents-sync/references/permissions.md` coord :25 / coord-pr :27 / board-coord :28 cells + dated log entry :88+; mirror regen. `pipeline-role-coord/SKILL.md` :44/:54 prose ("git-only shell (reads plus commits)") stays literally true under B — unchanged (D8).
3. **Matcher semantics** — AC6 simulations run through `family.py policy` UNMODIFIED (the repo's shipped semantics: fnmatch on the raw command, last-match-wins, `*` crosses spaces, leading `* *` deny stays in play). Probe F1/F2/F3 corrections already baked into the block above (quoted-arg hole → substring push; `push :main` → `push *main*`; `branch -c/-C` → targeted). The probe itself is grounding, not a shipped surface — its 90 cells are re-embedded as the agent-perms verdict-matrix task.
4. **rulesync** — global v37.0.0; `generate --check` green; regen verified inside suites (s6/m6/S10/P6/c7). YAML trap for authors: quote every resource value containing `*` (`resource: '*'`) — bare `*` is a YAML alias and kills the parser (probe-verified).
5. **Baseline suite states (2026-10-29)** — agent-perms 15/15 PASS; coord-inwork 7/7; kickoff-branch 6/6; session-origin 7/7; standalone-agents 10/10; pipeline-push-pr 6/6; gate.sh FAIL t14, rulesync-surface FAIL c8, agents-md FAIL c7 (own plan folder unadmitted — design, cleared by the admit lines); pipeline-models FAIL M3 ONLY (pre-existing catalog era-red; m1 m2 m4 m5 PASS; untouched by this ticket); `rulesync generate --check` clean; `npx aislop ci --changes` green.

## Commands

- sources+regen: `rulesync generate && rulesync generate --check` → `rulesync generate` = no-op (`git status --porcelain -- .opencode/ AGENTS.md` empty post-commit)
- twins: `bash tests/agent-perms/surface.sh` (A12 parity on sources AND mirrors; A12 gitrows against the declared block)
- pins: `bash tests/coord-inwork/surface.sh` · `bash tests/kickoff-branch/surface.sh` · `bash tests/session-origin/surface.sh`
- board trio: `bash tests/agent-board-coord/gate.sh` · `bash tests/agent-board-coord/rulesync-surface.sh` · `bash tests/agent-board-coord/agents-md.sh` (incl. the cf-72 plan-folder admits)
- regression: `bash tests/standalone-agents/surface.sh` · `bash tests/pipeline-push-pr/surface.sh` · `bash tests/pipeline-models/surface.sh m1 m2 m4 m5` (full run must fail ONLY M3, exactly as baseline)
- verdict matrices (AC6): `python3 "$TMP/family.py" policy <file> '<command>'` per the chunk tables over all six sources + all six mirrors (dev embeds them in agent-perms; review runs the suite, not the /tmp probe)
- quality: `npx aislop ci --changes` · review: `git diff --stat main...HEAD` limited to Files in scope

## Chunks

| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C01 | Broad git write grant: 6 sources + regen + deny-floor pins + 90-cell verdict matrices + matrix rows + own-folder admits | L | 1 | [] | single chunk — sources and pins are mutually load-bearing (any split commits a red tree); L ⇒ one task per chunk by role rules |

## Wave order

1. C01 as **Single Session** (owner-confirmed): one dev pass lands sources→regen→pins→matrices→admits and runs the Commands; NO agent-test pre-round; ONE final whole-plan review follows. STATE `stages` re-set by coord on approval (plan+code+review).

## Risks / assumptions

- The floor IS the security boundary for a broad grant: any future git ref-mover that is neither make-HEAD nor plumbing MUST join the floor in the same commit (standing rule, decision log).
- Residual model: globs guard accident shapes, not determined evasion (old allow-list likewise); the push floor + contract + review remain the publish-line.
- The 13 old allow rows vanish — grep `tests/**`/`.rulesync/skills/**` for row-presence assumptions (e.g. `'git add \*'` literals) beyond the enumerated sequence-pins during dev.
- `-local` commit messages must avoid the `push`/`--force`/` main*` token shapes (substring denial) — including this ticket's own coordination commits after landing.
- cf-69 branch also touches tests/; later-landing rebases (STATE note).
- Generated mirrors are rulesync-owned; regen only.

## Open questions (batched round 2 — only NEW gaps from the B implementation; best guesses baked in)

1. **`git *push*` substring strictness on `-local`/alias** — the spaced-only approximation `git * push*` leaves quoted args through (PROVEN in simulation: `git commit -am 'push posture'` → allow). Strict substring denies any command TEXT containing `push` on the commit-only variants (reword messages / `git restore`-style workarounds exist); it is the faithful reading of "push at any position". Best guess: KEEP the substring form.
2. **Zero-arg `git push` on `-pr` stays ALLOWED** (own-branch upstream push, the pipeline-push-pr shape; the `-C` zero-arg footgun is separately denied via `git * push`) — confirm this matches the owner's -pr intent, since it means `-pr` push permission is now position-free for non-main refspecs. Best guess: ALLOW (contract-gated, shipped `pipeline-push-pr` skill unchanged).

(Answered and retired from round 1: design B ordered; `git worktree *` GRANTED under the floor; Single Session; type chore; slug; `git show` asymmetry → documented only.)
