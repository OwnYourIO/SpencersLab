# tests/seaweedfs-debug — surface suite notes

`surface.sh` is the single statics-only suite for the whole plan
(DECISIONS.md: arms-style, `tests/wekan-mcp/skill-surface.sh` precedent;
t1..t5 ↔ C01..C05; no t6 — C06 human-declined at approval 2026-11-11).

Run: `bash tests/seaweedfs-debug/surface.sh [t3 ...]` — exit 0 pass, fail-fast
exit 1 with the chunk+AC id in every FAIL/ok line. No CI job runs `tests/**`
(EXPLORE §2.3): these suites are invoked from each chunk's `## Commands` by
dev and re-run by review as its first step.

Pre-implementation state (verified 2026-11-11 at `a6e493b78`): every arm exits
1 — t1 on the stale `-collection=default` instructional line, t2/t3/t4 on the
absent skill files, t5 on the missing registration. Baseline-green pieces that
must HOLD as regressions: t1.7 preservation greps, t2.1's byte-identical path
scan (all repo spellings currently canonical), t4.7/t5.3 negatives, t5.2's
`rulesync generate --check` (exit 0 at base; run via PATH/npx cache, never
`npx --yes` — fetch is a network call and suites are statics-only), t5.4
(vacuous until C05 commits).

How the arms were validated both ways (re-runnable):
- Achievability: a compliant final state was mocked in a scratch repo
  (`/tmp/opencode/sw-armtest`, throwaway) — t1–t4 all green against it.
- Rigor: nine adversarial mutations (extra frontmatter key, folded
  description, unindexed file, broken heredoc restored, check.disk -apply
  without `-resurrectMissingNeedles`, `reference/` path variant, `-XPOST`
  added to the probe, skill leaked into `skills-lock.json`, out-of-scope
  `overview.md` line) — each is caught by its arm.

What the suite deliberately does NOT pin (review judgment, not harness):
- error-signatures.md per-row meaning/probe/pointer structure (t3.2 pins the
  13-token floor mechanically).
- Prose quality / §R1.7 contradiction-freedom (t1 AC7's semantic half).
- t5.4's allow-list admits any changed line naming one of the six existing
  skills — the wrapped bullet's removed side carries no anchor; tightening it
  further would false-fail the legitimate diff shape.

Gotchas inherited while writing (fixed in-suite): ERE alternation — `|` inside
heredoc patterns must be `\|` or the token degenerates to `tee` matching
anything; `-XPOST` hides from `\bPOST\b` (word-internal), so the probe guard
matches the `-X` form explicitly.
