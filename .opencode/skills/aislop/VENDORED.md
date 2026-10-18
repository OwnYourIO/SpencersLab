source: scanaislop/skills/skills/aislop
commit: e9017219841e5515913cf8c055becd6c12865c64
vendored: 2026-10-18
deviations (re-apply when re-vendoring):
  - SKILL.md frontmatter: added disable-model-invocation and
    metadata.opencode/autoinvoke "false" so the skill runs only via explicit
    $aislop, never auto-selected.
  - Claude/Anthropic references removed (this lab does not use Claude):
    skill.json drops the claude-code/anthropic keywords and compatibility
    entries, the "fix with claude" trigger, and examples/05-agent-handoff.md
    (deleted — it demonstrated a Claude Code hand-off); SKILL.md rewrites the
    fix/hook docs to the in-session flow (aislop fix -p, aislop-gate plugin).
