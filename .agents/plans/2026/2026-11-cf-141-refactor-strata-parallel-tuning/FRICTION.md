# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or
ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures,
stale docs/plans, forced repeats or workarounds — each with the resolution actually used.
Agents report via RESULT `friction:`; coord appends (its own items included).

- 2026-11-10 · plan(C01..C03) · the `pipeline-role-explore` role skill is absent from
  `.opencode/skills/` (roster carries coord/deploy/dev/fuser/plan/research/review/test — no
  explore twin), although the Exploration stage shipped EXPLORE.md · resolution: explore-role
  contract taken from the launch brief + the conventions in pipeline-conventions; EXPLORE.md's
  shape proves it worked — sync the role skill (agents-sync scope) · open.
- 2026-11-10 · plan(C01..C03) · glob/grep patterns under `.agents/**` silently return NO
  MATCHES — `.agents` is a symlink and the pattern tools do not follow it (`.agents/plans/…/*.md`
  patterns came back empty while `ls` shows the files; second occurrence, EXPLORE noted it too) ·
  resolution: use `read` on absolute paths or shell `ls`/`grep` for anything under `.agents/`
  or `.kilo` · fixed-for-plan (recipe here, stop rediscovering).
- 2026-11-10 · plan(C01..C03) · `dev-boards.get_card` on AD-141 returns the full 48.8k-char
  guide — a direct read floods context · resolution: Code-Mode composition — fetch once inside
  `execute`, regex-index the section headers, return only the slices needed (§1 ground rules,
  §10 procedure, §12 caveats); repeatable recipe, cost 2 small calls · fixed (documented).
- 2026-11-10 · plan(C01..C03) · fresh worktree renders ERROR in every helm-gated test: the
  app-template subchart is not vendored (gitignored `charts/`), first observed as
  "found in Chart.yaml, but missing in charts/" (TEST_SPEC §9.12 warned; the baseline numbers
  there are meaningless without this step) · resolution: `export PATH=$HOME/.local/bin:$PATH &&
  helm dependency update charts/llama-swap` ran clean (helm v3.16.4); the plan's Commands names
  it as step 1 · fixed (plan-level).
- 2026-11-10 · plan(C01..C03) · `charts/llama-swap/tests/TEST_SPEC.md` is ~2.9k lines of
  contract history; reading it fully to find the CURRENT baseline is a large token tax ·
  resolution: read the era-tail rounds (§9.24–§9.27, §10–§11) and MEASURED the posture instead
  (417 passed / 9 skipped / 0 failed, ~25 s full suite) — measuring beats archaeology · fixed
  (recipe here).
- 2026-11-11 · test(plan) · C02 chunk's env-law wording "every rung except q4 keeps env=={}"
  is falsified as written by live reality (strix's PROFILE-layer env carries the eight-set, an
  existing green law) · resolution: implemented as the exact per-rung env table resolved through
  the era chain (strix checked exactly against its eight-set, no rung exempted); the chunk's
  wording is the round-2-era simplification — later chunks' authors read the test, not the prose
  · open (chunk-wording vs live-law class; a plan touch could amend C02's wording, tests already
  authoritative).
- 2026-11-11 · test(plan) · aislop-gate's first scan of the session reported "0 changed file(s)"
  while files were still untracked at that moment · resolution: none needed — subsequent edits
  tracked correctly (9 changed files); recorded so no reader treats the first clean run as an
  un-scanned edit (untracked files stay out of `--changes` scope by design, same note cf-131
  round-1 already carries).
