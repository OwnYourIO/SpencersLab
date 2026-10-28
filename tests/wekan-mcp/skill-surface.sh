#!/usr/bin/env bash
# skills/wekan-mcp surface contract (2026/2026-10-cf-75-bug-wekan-mcp-skill,
# C01): the new generic MCP board skill — frontmatter, the three server ids,
# the ten call-shape rule tokens, the one normative Board context block schema
# (repo-wide single owner outside plan folders), the 26-tool call-shapes
# reference with per-entry evidence stamps anchored on server.py FUNCTION
# names, the wekan-api pointer without duplication, and the AGENTS.md
# self-written-skills line.
#
# Contract source: chunks/C01.md "## Tests". AC trace:
# t1[AC1] t2[AC1] t3[AC2] t4[AC3] t5[AC4] t6[AC5] t7[AC6] t8[AC7].
#
# Statics-only by design (D8 precedent: no network in suites — the live
# dev-boards smoke is C03's, dev+run side). Red before C01: t1-t4/t7 fail on
# the absent skill directory, t6 on the unlisted skill name — every red names
# the missing contract, never a harness fault. t5 and t8 are green at the
# base already and HOLD as regressions (t8 also guards the dev-never-touches-
# the-sibling-ticket rule while the plan folder still exists).
#
# t3 scope rule: the schema owner is Markdown prose only — the C04 formatter
# IMPLEMENTS the schema in TypeScript and is not a normative copy, and plan
# folders quote the schema as ticket context, so both are excluded from the
# one-owner scan.
#
# Usage:
#   bash tests/wekan-mcp/skill-surface.sh            # t1..t8
#   bash tests/wekan-mcp/skill-surface.sh t2 t4      # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SKILL="skills/wekan-mcp/SKILL.md"
CALLS="skills/wekan-mcp/references/call-shapes.md"
SERVER="containers/wekan-mcp/wekan_mcp/server.py"
TOOLS_SUITE="tests/wekan-mcp/tools.sh"
AGENTS="AGENTS.md"
RULES_SRC=".rulesync/rules/overview.md"
CHUNK=".agents/plans/2026/2026-10-cf-75-bug-wekan-mcp-skill/chunks/C01.md"
DECISIONS=".agents/plans/2026/2026-10-cf-75-bug-wekan-mcp-skill/DECISIONS.md"
SIBLING="2026-10-docs-wekan-mcp-arg-ergonomics"
HEADER='Board context (collected'

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/skill-surface-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7 8; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t([1-8])$ ]] || fail "unknown test id '$a' (expected t1..t8)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- t1: SKILL.md frontmatter + required section headers (C01 AC1) -------------
if want t1; then
  [ -f "$SKILL" ] || fail "t1: $SKILL does not exist (C01 Task 1: ship the skill)"
  python3 - "$SKILL" <<'PY' || fail "t1: SKILL.md frontmatter/section contract violated (reason above)"
import re, sys, yaml
text = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
assert m, "t1: no YAML frontmatter block"
fm = yaml.safe_load(m.group(1))
errs = []
if not fm.get("name"):
    errs.append("frontmatter has no name")
desc = str(fm.get("description") or "")
if not desc:
    errs.append("frontmatter has no description")
# The description is the trigger surface (agents-sync convention): it must
# carry the names an agent would type when it needs this skill.
for t in ("dev-boards", "wekan-mcp", "AI-Dev"):
    if t not in desc:
        errs.append(f"description lacks trigger phrase {t!r}")
heads = re.findall(r"^#{1,4}[^\n]*", text, re.M)
joined = "\n".join(heads).lower()
for label, pat in (
    ("servers/tier table", r"server|tier"),
    ("call-shape rules", r"call.?shape"),
    ("Board context block schema", r"board context"),
    ("failure playbook", r"failure"),
):
    if not re.search(pat, joined):
        errs.append(f"no section header matching {label} ({pat!r}); headers found: {heads}")
if errs:
    print("; ".join(errs)); sys.exit(1)
PY
  ok "t1: SKILL.md exists, frontmatter parses (name + dev-boards/wekan-mcp/AI-Dev triggers), and the four contract sections are headed (C01 AC1)"
fi

# --- t2: server ids + the ten call-shape rule tokens (C01 AC1) ------------------
if want t2; then
  [ -f "$SKILL" ] || fail "t2: $SKILL does not exist"
  for s in dev-boards admin-global-wekan readonly-global-wekan; do
    grep -qF "$s" "$SKILL" || fail "t2: SKILL.md never names server id '$s' (the three-server table is AC1)"
  done
  for tok in finished done to_swimlane_id card_number created_at from_list_id board_id _id top-down tools/list; do
    grep -qF "$tok" "$SKILL" || fail "t2: SKILL.md is missing call-shape rule token '$tok' (the ten rules of chunks/C01.md Task 1)"
  done
  ok "t2: the three server ids and all ten rule tokens grep out of SKILL.md (C01 AC1)"
fi

# --- t3: one normative Board context schema, owned by this skill (C01 AC2) -------
if want t3; then
  [ -f "$SKILL" ] || fail "t3: $SKILL does not exist"
  # find, not git-ls: the skill arrives untracked until dev commits it, and a
  # one-owner scan that misses untracked copies would guard nothing.
  grep -rlF --include='*.md' "$HEADER" . \
    --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=plans 2>/dev/null \
    | grep -v '^\./\.agents/plans/' >"$TMP/owners.txt" || true
  owners=$(cat "$TMP/owners.txt")
  [ "$owners" = "./$SKILL" ] \
    || fail "t3: '$HEADER' must occur in exactly one markdown file outside .agents/plans/, $SKILL — found: ${owners:-<none>}"
  n=$(grep -cF "$HEADER" "$SKILL")
  [ "$n" -eq 1 ] || fail "t3: SKILL.md must carry the canonical schema header exactly once, found $n (the schema has one normative home)"
  ok "t3: the Board context schema header is owned solely by $SKILL (C01 AC2)"
fi

# --- t4: call-shapes.md — 26 live-extracted tool rows, stamps, no line refs -----
if want t4; then
  [ -f "$CALLS" ] || fail "t4: $CALLS does not exist (C01 Task 2: the full tool->args->shape table)"
  python3 - "$SERVER" "$CALLS" <<'PY' || fail "t4: call-shapes.md violates the 26-row/stamp/no-line-numbers contract (reason above)"
import ast, re, sys

tree = ast.parse(open(sys.argv[1]).read())
names = []
for node in tree.body:
    if isinstance(node, ast.FunctionDef):
        for d in node.decorator_list:
            if isinstance(d, ast.Attribute) and d.attr == "tool" and isinstance(d.value, ast.Name) and d.value.id == "mcp":
                names.append(node.name)
            elif isinstance(d, ast.Name) and d.id == "_write_tool":
                names.append(node.name)
if len(names) != 26:
    print(f"server.py registers {len(names)} tools, expected 26 — re-read the registry, the test follows server.py"); sys.exit(1)

text = open(sys.argv[2]).read()
bad = []
for name in names:
    rows = [l for l in text.splitlines()
            if re.match(r"^\|\s*`?" + re.escape(name) + r"`?\s*\|", l)]
    if not rows:
        bad.append(f"no table row for {name}")
        continue
    if len(rows) > 1:
        bad.append(f"{name} has {len(rows)} rows, expected one")
    # Both stamp spellings of chunks/C01.md are accepted: the task-text prose
    # ("verified <date> ... live probe") and the AC token form.
    if "source-only" not in rows[0] and not ("live probe" in rows[0] and "2026-10-27" in rows[0]):
        bad.append(f"{name} row carries no evidence stamp (live probe 2026-10-27 / source-only)")
if bad:
    print("; ".join(bad)); sys.exit(1)
hits = re.findall(r"\bL\d+\b", text)
if hits:
    print(f"line-number refs present: {hits[:5]} — DECISIONS: cite server.py function names, never line numbers"); sys.exit(1)
PY
  ok "t4: call-shapes.md has exactly one stamped row per @mcp.tool function in server.py (26, names read live) and zero L<digits> refs (C01 AC3)"
fi

# --- t5: regression — the tools.sh suite still pins wekan-api (C01 AC4) ---------
if want t5; then
  log=/tmp/opencode/skill-surface.tools.log
  if bash "$TOOLS_SUITE" >"$log" 2>&1; then
    ok "t5: bash $TOOLS_SUITE stays green — the wekan-api pinned regions were not disturbed (C01 AC4)"
  else
    tail -n 20 "$log" >&2
    fail "t5: $TOOLS_SUITE broke (log: $log) — C01 edits outside the t5/t9 pinned regions or the test is faulty"
  fi
fi

# --- t6: AGENTS.md skills line + rulesync --check (C01 AC5) ----------------------
if want t6; then
  for f in "$AGENTS" "$RULES_SRC"; do
    python3 - "$f" <<'PY' || fail "t6: $f self-written-skills line does not list wekan-mcp + wekan-api"
import re, sys
lines = open(sys.argv[1]).read().splitlines()
anchor = [i for i, l in enumerate(lines) if "self-written skills" in l]
if not anchor:
    print("no 'self-written skills' anchor line"); sys.exit(1)
# Windowed, not same-line: rulesync re-wraps the generated AGENTS.md, so the
# added names may land on a continuation line of the same bullet.
for i in anchor:
    window = "\n".join(lines[i:i + 3])
    if "wekan-mcp" in window and "wekan-api" in window:
        break
else:
    print("'self-written skills' bullet does not name wekan-mcp and wekan-api within its first 3 lines"); sys.exit(1)
PY
  done
  RS=""
  if command -v rulesync >/dev/null 2>&1; then RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "t6: rulesync not resolvable here (PATH or npx cache) — the --check gate was not run (c7/t14 ladder precedent)"
  else
    timeout 180 $RS generate --check >"$TMP/rscheck.log" 2>&1 \
      || { tail -n 15 "$TMP/rscheck.log" >&2; fail "t6: rulesync generate --check is not clean — AGENTS.md is stale against .rulesync/rules"; }
    ok "t6: rulesync generate --check clean via $RS (source and generated AGENTS.md agree)"
  fi
fi

# --- t7: reference not duplicate — pointer in, rules-engine verbs out (C01 AC6) --
if want t7; then
  [ -f "$SKILL" ] || fail "t7: $SKILL does not exist"
  grep -qF 'wekan-mcp-ops.md' "$SKILL" \
    || fail "t7: SKILL.md never points at wekan-mcp-ops.md — the MCP-over-HTTP recipe and rules engine stay owned by wekan-api (AC6: reference, never copy)"
  # The rules-engine vocabulary is camelCase trigger/activityType values and
  # action verbs documented in wekan-mcp-ops.md; the snake_case MCP tool names
  # (create_rule etc.) may appear — these tokens may not.
  hits=$(grep -rnE 'addChecklistWithItems|activityType|addLabel|removeLabel|createCard|moveCard|editCard|scheduledTrigger' \
    skills/wekan-mcp/ 2>/dev/null || true)
  [ -z "$hits" ] || fail "t7: rules-engine vocabulary duplicated into skills/wekan-mcp (pointer rule broken): $hits"
  ok "t7: wekan-mcp points at the ops reference and carries no rules-engine vocabulary (C01 AC6 anti-duplication)"
fi

# --- t8: retirement is coord bookkeeping, never a dev file list (C01 AC7) --------
if want t8; then
  [ -f "$CHUNK" ] || fail "t8: $CHUNK missing — the chunk file is the AC7 host"
  grep -q '^## Coord bookkeeping' "$CHUNK" || fail "t8: chunks/C01.md lost its '## Coord bookkeeping' section"
  grep -qF "$SIBLING" "$CHUNK" || fail "t8: the Coord bookkeeping section must name the retired draft ticket $SIBLING"
  grep -qF "$SIBLING" "$DECISIONS" || fail "t8: DECISIONS.md does not record the retirement decision for $SIBLING"
  awk '/^## Files in scope/{f=1; next} /^## /{if (f) exit} f' "$CHUNK" >"$TMP/scope.txt"
  if grep -qF "$SIBLING" "$TMP/scope.txt"; then
    fail "t8: a '## Files in scope' line of chunks/C01.md resolves inside the sibling ticket folder — dev must never edit another ticket (retirement is coord bookkeeping)"
  fi
  ok "t8: Coord bookkeeping + DECISIONS name the $SIBLING retirement; no C01 scope line reaches into the sibling folder (C01 AC7)"
fi

printf 'PASS: wekan-mcp skill-surface checks (%d ok)\n' "$checks"
