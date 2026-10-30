# PLAN: wekan-mcp v102: board-provisioning surface (update_board, create_swimlane, create_label, list_board_members)
feature: 2026/2026-10-cf-89-feat-wekan-mcp-board-provisioning
card: #89 "New WeKan MCP tools" (AI-Dev board, id phrhiExtY4B9TAZmg, slug cf-89-feat-wekan-mcp-board-provisioning)

## Goal
Extend `containers/wekan-mcp` from its v101 27-tool registry to a 31-tool v102 surface by adding four board-provisioning tools — `update_board` (title-only rename preserving board id AND the cardNumber sequence), `create_swimlane` (hydrated read-back incl. actual `sort`), `create_label` (name+color, 25 named colors, bare-id response), `list_board_members` (ids + role booleans with a username-resolution note) — behind the same `WEKAN_MCP_READ_ONLY` gate, with snake_case args and per-tool HTTP-200-with-error-body guards. All route behavior is grounded on upstream **v12.65** per `RESEARCH.md`, whose verdicts supersede the card prose (card's "9.88.0" premise is wrong; color/permission knobs do not exist over REST).

## Out of scope
- Any chart / ApplicationSet / deployment change: the `ghcr.io/ownyourio/wekan-mcp:v87` pins (`services/dev/prod/values.yaml`, `services/gpu/prod/values.yaml` ×2) bump post-merge via renovate (`:v<run>`); live `tools/list` acceptance at `mcp.dev.scifi.farm/boards` is user-owned.
- Entity deletes (`delete_board`/`delete_card`/`delete_list`/`remove_member`) — explicitly NOT requested; the two bounded destructive exceptions stay as-is.
- The optional nice-to-haves `update_swimlane`, `delete_swimlane`, `update_list`, move-position — deferred (route facts already captured in RESEARCH.md §6 for a future v103).
- `wekan_mcp/wekan.py` — byte-stable (tools.sh t8 pin); the 200-error guards live in server.py.
- Board `key` mutation (no REST route exists), username resolution (site-admin-only routes), board color/permission.

## Verified facts (source-checked 2026-10-30; details in RESEARCH.md)
- Repo pin: wekan chart **12.65.0** ×2 in `services/home/prod/Chart.yaml`+`Chart.lock` → upstream **v12.65** live server. v12.74 drift-checked: none on these routes.
- server.py registry today: 27 = 13 `@mcp.tool` reads + 14 `@_write_tool` writes. After v102: **31 = 14 reads + 17 writes**.
- Routes: rename `PUT /api/boards/:id/title` (gate `checkBoardAdmin` at 12.65; e2e-verified member→403); swimlane `POST /api/boards/:boardId/swimlanes` (`checkBoardWriteAccess`, explicit `sort` honored, default max+1, response `{_id}`, single-GET carries `sort`); label `PUT /api/boards/:id/labels` (inline board-admin-or-site-admin gate, clean 401/403/404/400, response bare JSON string id, (name,color)-idempotent); members via `GET /api/boards/:id` board doc (`checkBoardAccess`; members[] = userId + `isAdmin`/`isActive` required + 7 optional role flags; no usernames at bot privilege).
- Count-pin blast radius flipping 27→31 (all in C01): `tests/wekan-mcp/tools.sh` (t2 arithmetic + name sets, t5 `'27 typed tools'` README/wekan-api literals), `tests/wekan-mcp/skill-surface.sh` (t4 `len(names) != 27` + header prose), `tests/wekan-mcp/create-list.sh` (t3 README/`full, 27 tools`×2/`all 27 tools`/`27 typed tools`/27-row table pins + prose), `containers/wekan-mcp/README.md` L9 + Tools table (27→31 rows), `skills/wekan-mcp/SKILL.md` tier cells, `skills/wekan-mcp/references/call-shapes.md` header + one stamped row per new tool, `skills/wekan-api/SKILL.md` L40/L48 + Read/Write enumerations. `tests/wekan-mcp/board-context.sh` has no count pins (only a date matched).
- Rules routes are `checkBoardAdmin` at v12.65 (fetched from the tag today) → `create_rule`/`remove_rule` is the board-admin live probe with zero new surface.

## Commands
- test (new suite, agent-test writes pre-dev): `bash tests/wekan-mcp/board-provisioning.sh` (subset form `bash tests/wekan-mcp/board-provisioning.sh t1 t2`)
- regression: `bash tests/wekan-mcp/tools.sh && bash tests/wekan-mcp/skill-surface.sh && bash tests/wekan-mcp/create-list.sh && bash tests/wekan-mcp/board-context.sh && bash tests/containers/wekan-mcp-login.sh` (green with pins at 31; wekan.py byte-pin holds)
- lint: `python3 -m py_compile containers/wekan-mcp/wekan_mcp/server.py containers/wekan-mcp/wekan_mcp/wekan.py`
- docker build: `docker build => no-daemon, CI-deferred` — `docker-build.yaml` on the pushed branch is authoritative (AGENTS.md rule; the line itself is the designed passing shape). No new pip deps; Dockerfile/base untouched → no build-critical facts change.
- surface: `git diff --name-only $(git merge-base main HEAD)..HEAD` ⊆ the chunk's declared file lists (plan-folder artifacts exempt).
- live probe (early, agent-run in the TEST wave, NOT a scripted suite test): board-admin status of the dev-boards bot on AI-Dev via `dev-boards` MCP `create_rule` (never-fires trigger) → `remove_rule`; record the answer in DECISIONS.md + chunk notes. Exact recipe in chunks/C01.md.
- live probe (user-owned, post-merge post-image-bump): `tools/list` on `dev-boards` shows 31 tools incl. the four new signatures; `readonly-global-wekan` lists 14 reads, no new writes (recipe: `skills/wekan-api/references/wekan-mcp-ops.md`).

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | v102 tool surface: 4 tools + 200-guard + 27→31 count parity + board-admin live probe | M | 1 | [] | single shippable unit: server.py and the registry-count pins must land together (cf-68 precedent — docs/tests pin the registry, half the change is red) |
| C02 | wekan-api `rest-api-overview.md` docs refresh (routes this ticket made load-bearing) | S | 1 | [] | independent of C01 (documents upstream REST, not our code); content already sourced by RESEARCH.md; deferrable if the human declines (Open question 4) |

## Wave order
1. C01, C02 (independent; run in id order — C02 is pure docs and cannot break C01's suites).

## Risks / assumptions
- Deployed-build lag is the known failure mode: repo docs are claims until the live `tools/list` probe; that probe is post-merge and user-owned (wekan-mcp skill playbook).
- Bot board-admin status on AI-Dev is an assumption until the early probe answers it; the tools are correct either way (the gate is server-side), but a 403 result means the user must grant the bot board admin on AI-Dev for v102 ops to work there.
- The live probe mutates AI-Dev momentarily (rule create+delete). Never-fires trigger by construction; failed removal leaves a harmless rule + rule-history entry, reported for user cleanup.
- `sort` on swimlane create and the label (name,color) idempotency are server behaviors stamped at v12.65; a WeKan upgrade must re-verify (version-pinning discipline).
- `create_list`'s v101 response shape and `_slim_board`/`get_board` stay byte-stable (new tool echoes are built separately, not by widening shared helpers).

## Open questions
(RESOLVED in the 2026-10-30 batched round — answers in DECISIONS.md; the plan above already embodies them. Historical text kept as written.)
1. **Version grounding**: accept v12.65 (chart 12.65.0) as the authoritative grounding for all ACs, superseding the card's "9.88.0"? Best guess: **yes** (research verdict; repo pins verified today). Impact: docstring/row stamps and AC wording only — the code paths are identical at both bounds.
2. **Bot board-admin on AI-Dev**: unknown (title-rename + label-create 403 without it). Best guess: **probe it early** — C01's TEST-wave live probe (rules routes are the admin gate at 12.65) answers it empirically before dev; if 403, escalate to the user to grant board admin on AI-Dev. Impact: none on the code; changes the deployment follow-up the user owns.
3. **`create_label` arg ergonomics**: explicit `name` + `color` with tool-side default `color="green"`, sending the documented `{"label": {name, color}}` form (string-form passthrough NOT exposed). Best guess: that. Impact: one arg default; server's own green default makes behavior identical either way.
4. **Docs-refresh scope**: does `skills/wekan-api/references/rest-api-overview.md` (known-wrong per RESEARCH.md §7.6: missing `PUT …/title`, swimlane body/sort, 4-vs-9 role flags, bare label id, bulk-labels route) ride this ticket (C02) or get deferred? Best guess: **ride it** — cheap, sourced, prevents rediscovery. Impact: one docs file; drop C02 if declined.
5. **Slug confirmation**: minted slug vs the offered alternates, Type staying `feat` (the card answered it). **Answer: REPLACED** — the user chose `cf-89-feat-wekan-mcp-board-provisioning`; folder/plan file, branch, session and the card slug field carry it, the worktree DIRECTORY keeps its legacy basename (cosmetic — see DECISIONS 2026-10-30).
