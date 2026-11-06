# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; coord appends (its own items included).

- 2026-11-06 coord (open): launch-side — `gpu-ai/qwen3.8-27b-q4` answered HTTP 503 "no available server" on both `agent-plan` launches; run fell back to the hosted dense route `openrouter/qwen/qwen3.8-27b` per pipeline-models (recorded in DECISIONS + STATE.json `kickoff.model_note`). Local route availability worth watching during this run.
- 2026-11-06 test session (open): fresh worktrees need `helm dependency build charts/llama-swap` before the chart pytest suite — the app-template tgz is gitignored; without it 109 tests fail with "missing app-template" helm errors and 150 skip silently. Resolution: dev/review sessions run the dependency build first (test session did).
- 2026-11-06 test session (informational): `tests/notes/vllm-runbook.sh` T3's v='5' leg is already satisfied on the pre-C03 tree by the §5.1 curl body line (`priority: 5`), so T3's designed-red is precisely the v='9' leg + the floor leg. The implemented sweep is exactly per spec; C03's red-posture note is approximate on '5' only.
