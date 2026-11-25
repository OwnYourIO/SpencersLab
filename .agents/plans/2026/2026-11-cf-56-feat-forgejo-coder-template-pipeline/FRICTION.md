# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; coord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open
- 2026-11-25 · plan · stale commands in the 2026-10-feat-coder-workspace-rebuild plan: its packaging guard lacks `helm dependency build` (errors on the coder wrapper's unpinned dependency) and its `/tmp/opencode/tfbin` terraform path no longer exists · resolution: re-verified each command in-session 2026-11-25; corrected forms pinned in this plan's Commands (`helm dependency build` prefix; `~/.local/bin/terraform` v1.16.6) · open
- 2026-11-25 · coord(explore) · first agent-explore launch on `gpu-ai/qwen3.8-27b-radiance` died the documented parked-q27 peer-proxy 502 (connection refused, no endpoint) · resolution: owner ruled `gpu-ai/qwen3.8-27b-radiance-tp2` for every tier (DECISIONS.md); scout relaunched fresh on that route and completed · fixed
