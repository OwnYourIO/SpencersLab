# 2026-10-25 refactor: OpenCode MCP fleet — global hardlink + dev/regular split

Type: refactor (agent-tool config layout; no cluster workloads touched)
Branch: `feat/opencode-mcp-global-hardlink` (worktree `.agents/worktrees/opencode-mcp-global-hardlink`)

## Goal

Change how MCP servers are seen: version-control the machine-global OpenCode
config inside `.opencode/` via a hard link, split the MCP fleet into a
"regular" part (global, every project) and a "dev" part (project-local, this
repo only), and stop duplicating the fleet between project and global configs.

## Current state (verified 2026-10-25)

- `.opencode/opencode.jsonc` (project config, loaded for this repo): all 45
  fleet servers + permissions + skills + default agent.
- `~/.config/opencode/opencode.json` (global): NO `mcp` section (removed
  2026-10-13, see `opencode.json.pre-mcp-removal.bak`); carries providers
  (`gpu-ai`/`gpu-moe`), agents, permissions, skills. ~230KB, no secrets
  (no apikeys/tokens/passwords; local endpoints only).
- `~/.config/kilo/kilo.jsonc`: its own 43-server fleet copy (missing the 2
  `ai-gpu` servers). **Left untouched** (user decision).
- OpenCode merge semantics (V2 docs): global → project deep-merge, "settings
  that do not conflict are preserved"; per-key project entries win. A project
  file cannot remove servers defined globally.

## User-confirmed decisions (2026-10-25)

1. **Split**: the 6 dev-cluster servers (`readonly-dev-kubernetes`,
   `admin-dev-kubernetes`, `dev-playwright`, `dev-renovate`, `dev-searxng`,
   `dev-boards` — everything on `mcp.dev.scifi.farm`) stay project-local;
   the other 39 "regular" servers move to the global config. This repo still
   sees all 45 via merge; other projects see only the 39.
2. **Hardlink the WHOLE global config** into the repo at
   `.opencode/opencode-global.jsonc` → same inode as
   `~/.config/opencode/opencode.json`. The entire global config (providers,
   agents, permissions + restored fleet) becomes version-controlled here.
3. **Kilo untouched.**

## Changes

1. **New `.opencode/opencode-global.jsonc`** — current global config content
   plus `mcp.servers` with the 39 regular servers (definitions moved verbatim
   from the project config, `disabled` flags preserved); `mcp` inserted
   alphabetically between `disabled_providers` and `permissions`. Header
   comment rewritten (the old one still claims the file is symlinked and that
   kilo follows it — both false since 2026-10-13). Name deliberately NOT
   `opencode.json(c)` so OpenCode never auto-loads it as a second project
   config.
2. **`.opencode/opencode.jsonc` (dev version)** — `mcp.servers` trimmed to
   the 6 dev-cluster servers ("extra" = the 39 now served by the global);
   header comment rewritten to describe the split + hard link. Permissions,
   `disabled_providers`, `default_agent`, `skills` unchanged.
3. **`.rulesync/rules/overview.md`** (source of AGENTS.md):
   - "Where things live": `.opencode/` bullet gains `opencode-global.jsonc`;
     the `.opencode/opencode.jsonc` bullet rewritten (no more "globals are
     real files, keep in sync by hand" — the hard link IS the sync).
   - "MCP servers" section: first paragraph rewritten for the two-file model.
4. **`.rulesync/subagents/{agent-dev,agent-test}.md`**: add
   `.opencode/opencode-global.jsonc` next to the existing
   `.opencode/opencode.jsonc` `edit → ask` rule (fleet config, explicit
   user approval).
5. **`.rulesync/skills/agents-sync/references/permissions.md`**: the `ask`
   row and the MCP-audit step now cover both config files.
6. **`rulesync.jsonc`** comment: fleet description updated (was stale: "41
   lab servers" in one file).
7. **Regenerate**: `rulesync generate` (AGENTS.md + `.opencode/agents/`),
   `rulesync generate --check` green, sources + generated committed together.
8. **Hard link** (environment step, after content is final):
   `cp -p ~/.config/opencode/opencode.json ~/.config/opencode/opencode.json.bak-20261025`
   then `ln -f <worktree>/.opencode/opencode-global.jsonc ~/.config/opencode/opencode.json`.

## Commands (validation)

```sh
# both configs parse (JSONC: strip //-comments, then jq)
sed -E 's|^\s*//.*$||' .opencode/opencode-global.jsonc | jq -e '.mcp.servers | length == 39'
sed -E 's|^\s*//.*$||' .opencode/opencode.jsonc | jq -e '.mcp.servers | length == 6'
# no server name appears in both files; union == 45
# hard link intact: same inode, link count 2
stat -c '%i %h' .opencode/opencode-global.jsonc ~/.config/opencode/opencode.json
rulesync generate --check
```

## Known caveats (documented in AGENTS.md)

- A hard link survives in-place writes; an editor/tool that saves via
  rename-and-replace (many do) silently breaks it. After any such break, or
  after the PR merges and the main checkout gets its own inode, re-link:
  `ln -f /home/coder/SpencersLab/.opencode/opencode-global.jsonc ~/.config/opencode/opencode.json`.
- While the PR is unmerged, the live link points at the WORKTREE copy; the
  main checkout's post-merge copy needs the re-link above.

## User-owned steps

- Review + merge the PR (agent never merges/pushes to main).
- After merge: re-run the `ln -f` command from the main checkout (see caveats).

## Result (executed 2026-10-25)

All changes landed on `feat/opencode-mcp-global-hardlink` as planned, plus one
extra fix found en route: `skills/helm-chart-creation/SKILL.md` carried a
stale copy of the old config-layout text (and a backwards claim about the
`.agents/agents` symlink direction) — rewritten to match the new layout.

Validation evidence:

- Both files parse as JSONC; 39 regular servers in `opencode-global.jsonc`,
  6 dev-cluster servers in `opencode.jsonc`, zero overlap, union == 45, all
  definitions byte-verbatim from the old project config; non-mcp content of
  both files byte-identical to their sources.
- Hard link live: `~/.config/opencode/opencode.json` and the worktree's
  `.opencode/opencode-global.jsonc` share inode 699768233, link count 2;
  pre-link backup at `~/.config/opencode/opencode.json.bak-20261025`.
- `rulesync generate --check` green.
- End-to-end: after OpenCode reloaded the changed configs, `opencode mcp list`
  reports exactly 45 servers; live probes answered from both halves
  (`dev-searxng` from the dev version; `readonly-global-wekan` and
  `readonly-gpu-kubernetes` from the global-only regular fleet). Note: a
  transient "No MCP servers configured" from `opencode mcp list` during the
  config-change restart was a race with the service restart, not a breakage.
- Kilo config untouched (mtime/size unchanged).
- `aislop ci --changes` (same gate as PR CI): 0 errors, 0 warnings.