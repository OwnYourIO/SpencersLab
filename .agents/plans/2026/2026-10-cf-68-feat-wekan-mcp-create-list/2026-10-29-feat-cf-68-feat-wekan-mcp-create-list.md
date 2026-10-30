# PLAN: wekan-mcp: add create_list tool (Timeout list for pipeline-locks reaper)
feature: 2026/2026-10-cf-68-feat-wekan-mcp-create-list

## Goal
Add a `create_list` write tool to `containers/wekan-mcp` (`board_id`, `title`,
optional `swimlane_id` + `position`) so deterministic board code can create board
lists through the MCP surface — the gap that forced cf-76's reaper into the
`.pipeline/timeouts.jsonl` degrade (card #68, parent #76 D22). Land the full
surface parity in the same change: container README, the `wekan-mcp` skill (SKILL.md
tier table + call-shapes table), the `wekan-api` skill tool enumeration, and the two
existing test suites that pin the 26-tool registry (`tools.sh`, `skill-surface.sh`).

## Out of scope
- Creating the "Timeout" list on the AI-Dev board — board structure is human-owned
  (card Notes); this ticket lands only the tool.
- Any change to the `pipeline-locks` reaper — wiring `create_list` into the reap path
  is NOT part of this card; the D22 interim degrade stays until the list exists.
- `create_label` (card: deliberately excluded, labels stay human-owned, #76 D19) and
  `delete_list` (entity-level destructive ops remain intentionally omitted).
- Deployment: the `wekan-mcp:v87` → new `:v<run>` image pin happens post-merge via
  renovate (container-creation pin-by-default flow); the live `tools/list` probe after
  that is user-owned acceptance.
- `wekan_mcp/wekan.py` client — the tool rides existing `_wekan.post/get` helpers.

## Verified facts (source-checked 2026-10-29)
- server.py registry: 26 tools = 13 `@mcp.tool` reads + 13 `@_write_tool` writes.
  The readonly tier needs no new gate code: `_write_tool` is a no-op decorator when
  `WEKAN_MCP_READ_ONLY` is set (write tools never registered — absent from
  `tools/list`, uncallable).
- Deployed WeKan is **v12.64** (`ghcr.io/wekan/wekan:v12.64` via official chart
  12.65.0, `services/home/prod/Chart.yaml`; the v9.99→v12.64 upgrade ran in
  2026-10 — stale v9.99 stamps in old docstrings predate it). New docstring facts are
  stamped v12.64.
- REST `POST /api/boards/:boardId/lists` (fetched from tag `v12.64`,
  `server/models/lists.js`): body `{title, swimlaneId?}`; server sets
  `sort = board.lists().length` (append — a **board-wide** count, so on multi-swimlane
  boards the new column may NOT land last within the chosen swimlane) and
  `swimlaneId = req.body.swimlaneId || defaultSwimlane._id` (board first swimlane when
  omitted). Response `{_id}`. Write access checked (`checkBoardWriteAccess`).
- Same-board `POST /api/boards/:boardId/lists/:listId/move` **exists on v12.64**
  (verified in the tag file): no `toBoardId` → pure reposition — optional
  `toSwimlaneId` rebind + `position` (0-based from left, among the board's live lists
  excluding self). It is the only REST-driven placement control for a new list.
- `GET /api/boards/:boardId/lists/:listId` returns the full list document (carries
  `swimlaneId` and `sort`) — the response-hydration source, same route
  `list_lists` already hydrates from.
- Count pins that break at 27 (blast radius, all must flip in C01):
  `tests/wekan-mcp/tools.sh` (t2 arithmetic `13 reads + 13 writes` + header prose +
  t5 literal `26 typed tools` in README/wekan-api SKILL + stale-wording tuples),
  `tests/wekan-mcp/skill-surface.sh` (t4 `len(names) != 26` + header prose),
  `containers/wekan-mcp/README.md` L9 "26 typed tools",
  `skills/wekan-mcp/SKILL.md` tier table (dev-boards + admin-global-wekan rows
  "full, 26 tools"),
  `skills/wekan-mcp/references/call-shapes.md` header "all 26 tools",
  `skills/wekan-api/SKILL.md` L48 "26 typed tools" + Write enumeration **and the
  pre-existing stale L40 "full 25-tool surface"** (fix to 27 in passing).

## Interface (pinned)
```python
@_write_tool
def create_list(board_id: str, title: str,
                swimlane_id: Optional[str] = None,
                position: Optional[int] = None) -> dict
```
- POST `/api/boards/{board_id}/lists` with `{"title": ...}` plus `swimlaneId` only
  when `swimlane_id` given.
- When `position` is not None: follow-up POST
  `/api/boards/{board_id}/lists/{id}/move` with `{"position": ...}` (+
  `toSwimlaneId` only when `swimlane_id` given). Failure of this leg NEVER fails the
  create — report `positioned: false` + `position_error` (precedent: `create_card`'s
  `default_checked` outcome reporting; no rollback).
- Hydrate the response from GET single-list:
  `{id, title, swimlane_id, sort, positioned}`; hydration failure degrades the echoed
  fields to null (precedent: `list_lists` hydrate warning) — a successful create must
  not surface as an error.
- Argument is `title` (not the card sketch's `list_title`): consistent with every
  other create tool (see DECISIONS D1). Docstring carries the v12.64 stamps, the
  append semantics, the board-wide sort quirk, and the default-swimlane behavior.

## Commands
- test: `bash tests/wekan-mcp/create-list.sh` (new suite — agent-test writes it before
  dev; per-directory runs, subset form `bash tests/wekan-mcp/create-list.sh t1 t2`)
- regression: `bash tests/wekan-mcp/tools.sh && bash tests/wekan-mcp/skill-surface.sh
  && bash tests/containers/wekan-mcp-login.sh` (green with the pins flipped to 27)
- lint: `python3 -m py_compile containers/wekan-mcp/wekan_mcp/server.py`
- docker build: `docker build => no-daemon, CI-deferred` — `docker-build.yaml` on the
  pushed branch is authoritative (AGENTS.md pipeline rule; the line itself is the
  designed passing shape). No new pip deps; base images untouched, so no
  build-critical facts change.
- surface: `git diff --name-only $(git merge-base main HEAD)..HEAD` ⊆ the chunk's
  declared file list.
- live probe (user-owned, post-merge after the image bump): MCP-over-HTTP
  `tools/list` on `dev-boards` shows `create_list` with the pinned signature;
  `readonly-global-wekan` does NOT list it (recipe:
  `skills/wekan-api/references/wekan-mcp-ops.md`).

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | create_list tool + doc/test surface parity | M | 1 | [] | single chunk: the server tool and the count flips must land together — docs/tests pin the registry, so half the change is red |

## Wave order
1. C01 (alone; a partial change breaks `tools.sh`/`skill-surface.sh`, so code and
   parity are one shippable unit).

## Risks / assumptions
- Deployed-build lag is the known failure mode (wekan-mcp skill playbook): docs are
  claims until the live `tools/list` probe; that probe is post-merge and user-owned.
- v12.64 route shapes were tag-fetched today; a WeKan upgrade must re-verify per the
  wekan-api version-pinning discipline (stamped, not assumed permanent).
- `position` is not atomic with create — a failed reposition leaves a live, appended
  list; visible in the response by design.
- Assumption: the `dev-boards` service user has board write access wherever it
  creates cards today (`create_card` already rides the same write-access gate).

## Open questions
(batched for the plan-approval round; best guesses already built into the plan)
1. **Arg name**: `title` (repo consistency — chosen) vs the card sketch's
   `list_title`? Best guess: `title`. Impact: ergonomics only — #76's plugin does not
   call the tool yet, so no consumer breaks either way; docs follow the choice.
2. **Include `position` at all?** The card asks "optional swimlane_id / sort
   placement"; best guess: include it via the verified same-board move/reposition leg
   (append-at-end stays the no-`position` behavior). Impact: one extra REST leg +
   failure-reporting arm in tool and tests; dropping it trims the surface.
3. **Hydrated response** `{id,title,swimlane_id,sort,positioned}` via the read-back
   GET vs minimal `{id,title}`? Best guess: hydrate — a caller (e.g. reaper target
   resolution) needs the resolved swimlane when it omitted the argument. Impact: one
   GET + a degrade arm.
4. **Test-pin strategy**: flip `tools.sh`/`skill-surface.sh` constants 26→27 in this
   change (best guess — the scripts' own message says "the test follows server.py",
   bumping the pin is the sanctioned mechanism) vs refactor them to derive the count
   live? Impact: test-file diff size only.
5. **Evidence stamp** for the new call-shapes row: `source-only` with an inline
   2026-10-29/v12.64 note (best guess — live probe can only happen post-merge) vs
   holding the row until probed live? Impact: one doc-cell wording; the stamp regex
   accepts the `source-only` form either way.
