# Raise agent step limits across Kilo config

**Date:** 2026-09-08
**Type:** chore (Kilo configuration, no cluster/GitOps impact)
**Status:** complete

## Goal

Agents kept hitting their `steps` limit (max agentic iterations, after which
Kilo forces a text-only response and the turn ends). Raise the limits so
agents can run to completion.

## Findings

- `steps` is per-agent; the JSON schema (`https://app.kilo.ai/config.json`)
  documents it as "Maximum number of agentic iterations before forcing
  text-only response" with no practical maximum.
- Two sources define the custom agents:
  - Project files `.agents/agents/*.md` (loaded via the `.kilo -> .agents`
    symlink), `steps:` in YAML frontmatter — git-tracked.
  - Global `~/.config/kilo/kilo.jsonc` `agent` section — defines the same
    numbered pipeline agents plus legacy aliases (`write-code`, `tdd`,
    `review`, `planning`, `pipeline`, `feature-generation`, `docs-user`,
    `docs-dev`, `dependency-mapper`).
- Where both define the same agent, values matched before this change; both
  were updated to stay consistent.

## Changes

Project files (`.agents/agents/<name>.md`, old -> new):

| Agent | Old | New |
|---|---|---|
| 0-pipeline | 60 | 300 |
| 1-feature-generation | 40 | 200 |
| 2-dependency-map | 100 | 300 |
| 3-plan | 60 | 300 |
| 4-tdd | 100 | 300 |
| 5-write-code | 120 | 400 |
| 6-review | 80 | 300 |
| 7a-docs-user | 40 | 200 |
| 7b-docs-dev | 60 | 300 |
| code | 60 | 300 |
| plan | 30 | 150 |

Global `~/.config/kilo/kilo.jsonc` — same numbered agents updated to the same
values, plus legacy aliases: write-code 60->300, tdd 40->200, review 30->150,
planning 30->150, pipeline 40->200, feature-generation 40->200,
docs-user 20->100, docs-dev 30->150, dependency-mapper 40->200.

Backup of the original global config: `~/.config/kilo/kilo.jsonc.bak-steps`.

## Validation

- Global config still parses as JSONC after the edit (verified with a JSON
  parse after stripping `//` comment lines).
- `diff` against the backup shows only the 18 `"steps"` lines changed.
- `grep '^steps:' .agents/agents/*.md` confirms all 11 project files.

## Notes

- New sessions pick up the values automatically; already-running sessions
  keep the limits they started with.
- The project agent files are git-tracked; changes were left uncommitted for
  the user to review and land.
- Built-in agents (`general`, `explore`, etc.) were not touched; they can be
  tuned the same way via the `agent` section of kilo.json if needed.
