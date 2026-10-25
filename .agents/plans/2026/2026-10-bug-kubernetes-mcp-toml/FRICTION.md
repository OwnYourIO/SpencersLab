# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open

## Collected friction (coord ledger, appended from agent handoffs at plan close)
- **Cluster-side verification is unavailable to agents during this incident**: the broken servers ARE the tool agents use to check deploys (`readonly-*-kubernetes`, 18 entries). Post-merge verification is therefore user-owned (PromQL + kubectl in the plan file); agents must not claim a landing is verified they cannot see.
- `helm` is not on PATH (only `~/.local/bin`); renders must run from `/tmp` copies after `helm dependency update` (vendored deps are gitignored, and the worktree must not be written into) — a merge-base copy alongside the head copy is what makes byte-level "nothing else changed" proofs possible.
- `aislop` is not installed locally; the pinned fallback is `npx -y aislop@0.18.1`. On that version `scan --changes` reports "0 changed file(s)" for JSON/YAML/markdown — those languages are outside its analyzed set, so the gate is complete-by-scope, not evidence. Prose/JSON contracts need marker tests + a manual comment-slop pass.
- `dev-renovate` runs remotely behind the ingress: `configPath`/`repoPath` cannot see worktree files (check_setup reports "no git remote / no renovate config"). Pass the committed content via `configContent`, and state that fidelity is closed by a byte-compare against the file.
- `test_package_rules` returns `matchFileNames` matchers as "not evaluatable offline" for preset-side rules; harmless for package-name rules, but don't read it as a failure.
- **Sibling gate hazard**: `dev-mcp-fleet.sh` t7 is red on a stale `playwright/mcp:v0.0.78` literal (main moved to v0.0.83). Its fail-fast hides every later assertion in t7 and aborts a default-all run before t8–t14 — so fleet gates must run ids in split batches until it is re-pinned. Urgent follow-up ticket.
- `renovate.json` hygiene: 4 pre-existing `automerge-without-automerge-type` warnings, plus `chart/base` / `service/proxy` `matchFileNames` paths that don't exist in this layout. Deferred to its own ticket (one branch, one concern).
- D9 (open): AGENTS.md claims the machine-global configs mirror the fleet MCP list; `~/.config/opencode/opencode.json` has zero `kubernetes` entries. Own ticket.
- Process miss (mine): agents reported friction across five handoffs while I left `FRICTION.md` as the empty template and put the recipes in the plan's Commands section instead. Coord appends friction at every hand-back, not at plan close.
- `storm-runs/` exists twice now (committed under the ticket folder, plus an untracked copy at the worktree root) — the root duplicate should be removed by the user; nothing references it.
