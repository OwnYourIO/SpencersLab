# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open
- 2026-10-26 · plan · No `helm` binary in this worktree environment — validation commands can't run here · resolution: plan's Commands section documents it; C02/C03 surfaces must install helm or run checks in a helm-equipped checkout · open
- 2026-10-26 · plan · Pod exec is not available via MCP (repo rule) — on-node Vulkan/amdgpu topology probes can't be run by agents · resolution: C01 carries the exact user-run commands (e.g. `kubectl exec -n <ns> <pod> -- <cmd>`) for the user to execute · open
- 2026-10-26 · coord · Worktree created by `worktree_create` arrived detached at main's tip with no feature branch · resolution: planner created local branch `debug-flash-next-vulkan-oom-openrouter-qwen3-8-flash` · fixed (branch now exists; expect the same on future worktree launches)
- 2026-10-26 · research · webfetch egress proxy intermittently 403/404s on GitHub URLs incl. valid ones (raw paths, discussion HTML) · resolution: use execute-mode fetch against api.github.com instead; correct llama-swap repo is mostlygeek/llama-swap · fixed
- 2026-10-26 · research · llama.cpp 'fused top-k mask' PR origin not directly sourceable · resolution: answered from runtime logs + RFC threads, flagged low-confidence (source [32] in RESEARCH.md) · ignored (accepted, low impact — warning judged benign)
