#!/usr/bin/env bash
# skills/wekan-api rest-api-overview.md v12.65-refresh contract
# (2026/2026-10-cf-89-feat-wekan-mcp-board-provisioning, C02): the upstream
# REST facts this ticket made load-bearing — PUT /api/boards/:id/title (body,
# gate, response; bare PUT :id is 405 upstream #5299), the label bare-string
# id + (name,color) idempotency + the 25-name color list incl. white, the
# swimlane POST sort semantics and the two GET projections, and the
# nine-boolean members[] shape with the site-admin username note.
#
# Contract source: chunks/C02.md "## Tests" + "## Acceptance criteria".
# AC trace: t1[AC1] t2[AC2] t3[AC3] t4[AC4] t5[AC5+AC6].
#
# Statics-only (same posture as the sibling suites): section-windowed greps,
# no network. Assertions cite endpoint paths and section headings, never line
# numbers. Every added fact must carry the v12.65 stamp (AC6) — checked per
# section window, because the whole point of the refresh is that facts come
# with their grounding (RESEARCH.md §7.6 lists what went stale unsourced).
#
# Red before C02 lands: t1-t4 — verified at the base 2026-10-30: no title-
# route section, a 24-name color list without white, no swimlane POST/sort
# facts, a four-flag members body. t5 runs the sibling suites (C02 must be
# inert to their pins); they carry the v102 count re-pin and go green with
# C01's code+docs, not with C02's prose — that red is C01's designed
# half-change, not a C02 harness fault.
#
# Usage:
#   bash tests/wekan-mcp/rest-overview-v102.sh          # t1..t5
#   bash tests/wekan-mcp/rest-overview-v102.sh t1 t2    # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

OVERVIEW="skills/wekan-api/references/rest-api-overview.md"
TOOLS_SUITE="tests/wekan-mcp/tools.sh"
SURFACE_SUITE="tests/wekan-mcp/skill-surface.sh"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-5]$ ]] || fail "unknown test id '$a' (expected t1..t5)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

[ -f "$OVERVIEW" ] || fail "harness: $OVERVIEW does not exist"

# Section window: from the heading containing NEEDLE to the next heading of
# the same or shallower level. Heading needles, not line numbers — the file
# reorders freely.
extract_section() {
  python3 - "$OVERVIEW" "$1" <<'PY'
import sys
lines = open(sys.argv[1]).read().splitlines()
needle = sys.argv[2]
start = None
for i, l in enumerate(lines):
    if l.startswith('#') and needle in l:
        start = i
        break
if start is None:
    sys.exit(1)
level = len(lines[start]) - len(lines[start].lstrip('#'))
end = len(lines)
for j in range(start + 1, len(lines)):
    if lines[j].startswith('#'):
        lvl = len(lines[j]) - len(lines[j].lstrip('#'))
        if lvl <= level:
            end = j
            break
print("\n".join(lines[start:end]))
PY
}

# --- t1: PUT /api/boards/:id/title documented; bare PUT :id is 405 (AC1) --------
if want t1; then
  sec=$(extract_section "PUT /api/boards/:id/title") \
    || fail "t1: rest-api-overview.md has no section heading for \`PUT /api/boards/:id/title\` — the sanctioned rename route must be documented (C02 AC1)"
  missing=$(python3 - "$sec" <<'PY'
import sys
sec = sys.argv[1]
need = ('"title"', 'checkBoardAdmin', '403', '405', '#5299', '_id', '12.65')
print(' '.join(t for t in need if t not in sec))
PY
)
  [ -z "$missing" ] \
    || fail "t1: the title-route section lacks: $missing — it must carry the {\"title\": …} body, the checkBoardAdmin gate (member=>403 title unchanged), the {_id, title} response, the bare-PUT-is-405 statement (#5299), and the v12.65 stamp (C02 AC1+AC6)"
  ok "t1: the PUT …/title section documents body + checkBoardAdmin gate + {_id, title} response + 403, and states bare PUT /api/boards/:id is 405 (#5299), v12.65-stamped (C02 AC1)"
fi

# --- t2: 25-color label set incl. white, bare-string id, idempotency (AC2) ------
if want t2; then
  python3 - "$OVERVIEW" <<'PY' || fail "t2: the labels documentation contract is violated (C02 AC2 — reason above)"
import re, sys
text = open(sys.argv[1]).read()
def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

# config/const.js ALLOWED_COLORS at v9.88 AND v12.65 (RESEARCH §3) — the docs
# carried only 24 (no white). Backtick-anchored so `blue` does not match
# `clearblue` (that is a BOARD color, a different set).
LABEL_COLORS = ('white', 'green', 'yellow', 'orange', 'red', 'purple', 'blue',
                'sky', 'lime', 'pink', 'black', 'silver', 'peachpuff',
                'crimson', 'plum', 'darkgreen', 'slateblue', 'magenta',
                'gold', 'navy', 'gray', 'saddlebrown', 'paleturquoise',
                'mistyrose', 'indigo')
missing = [c for c in LABEL_COLORS if re.search(r'`' + c + r'`', text) is None]
if missing:
    bad(f't2: label color names absent (backticked) from the docs: {missing} — the accepted set is the 25 config/const.js names including white')

def section(needle):
    lines = text.splitlines()
    start = None
    for i, l in enumerate(lines):
        if l.startswith('#') and needle in l:
            start = i
            break
    if start is None:
        return ''
    level = len(lines[start]) - len(lines[start].lstrip('#'))
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].startswith('#'):
            lvl = len(lines[j]) - len(lines[j].lstrip('#'))
            if lvl <= level:
                end = j
                break
    return '\n'.join(lines[start:end])

# The label facts belong to the label routes wherever the file puts them
# (today the PUT sits under Boards and ## Labels cross-references it).
facts = section('PUT /api/boards/:id/labels') + '\n' + section('## Labels')
if not facts.strip():
    bad('t2: no label-route section found (PUT …/labels heading and ## Labels section both missing)')
gaps = []
if not (re.search(r'bare', facts, re.I) and 'string' in facts):
    gaps.append('bare JSON string response')
if not re.search(r'idempot', facts, re.I):
    gaps.append('(name, color) idempotency')
if not re.search(r'second label', facts, re.I):
    gaps.append('same name + different color creates a SECOND label')
if '12.65' not in facts:
    gaps.append('v12.65 stamp')
if gaps:
    bad(f't2: the label sections lack: {gaps} — the PUT …/labels response is a bare JSON string label id (new or existing), the idempotency key is (name, color), and every added fact rides the v12.65 stamp (C02 AC2+AC6)')
print('ok')
PY
  ok "t2: all 25 label color names (incl. white) documented backticked; the label sections state the bare-string id response, (name,color) idempotency incl. the second-label rule, v12.65-stamped (C02 AC2)"
fi

# --- t3: swimlane POST body/sort + the two GET projections (AC3) -----------------
if want t3; then
  sec=$(extract_section "## Swimlanes") \
    || fail "t3: rest-api-overview.md lost its ## Swimlanes section (C02 AC3)"
  missing=$(python3 - "$sec" <<'PY'
import sys
sec = sys.argv[1]
need = ('sort', 'max', '+1', 'archived', 'single', 'full', '_id', '12.65')
print(' '.join(t for t in need if t not in sec))
PY
)
  [ -z "$missing" ] \
    || fail "t3: the Swimlanes section lacks tokens for: $missing — it must state the POST body {title, sort?} (explicit finite sort honored #3624, else max(live sort)+1 over archived:false siblings), the {_id}-only response, and the collection-vs-single GET projections (collection projects {_id, title} with no sort; single returns the full doc incl. sort), v12.65-stamped (C02 AC3+AC6)"
  ok "t3: Swimlanes section documents sort pass-through + max+1 default, the {_id}-only POST response, the collection-vs-single GET projections incl. the archived:false filter, v12.65-stamped (C02 AC3)"
fi

# --- t4: nine role booleans + site-admin username note; four-flag body gone (AC4)
if want t4; then
  sec=$(extract_section "## Board members and roles") \
    || fail "t4: rest-api-overview.md lost its ## Board members and roles section (C02 AC4)"
  missing=$(python3 - "$sec" <<'PY'
import re, sys
sec = sys.argv[1]
def bad(msg):
    print(msg); sys.exit(1)
flags = ('isAdmin', 'isActive', 'isNoComments', 'isCommentOnly', 'isWorker',
         'isNormalAssignedOnly', 'isCommentAssignedOnly', 'isReadOnly',
         'isReadAssignedOnly')
gaps = [f for f in flags if f not in sec]
for tok in ('userId', 'required', 'optional', '/api/users'):
    if tok not in sec:
        gaps.append(tok)
if not re.search(r'site[- ]admin', sec, re.I):
    gaps.append('site-admin username note')
if '12.65' not in sec:
    gaps.append('v12.65 stamp')
if gaps:
    bad(' '.join(gaps)); sys.exit(1)
# Stale-shape guard: the board doc's members[] are objects keyed by userId
# with role booleans — never bare ids. The card `members: ["<userId>"]` body
# (Cards section, out of this window) legitimately holds bare ids.
if re.search(r'members[^.\n]*\b(bare|only)\s+(user\s*)?ids?\b', sec, re.I):
    bad('members[] described as bare ids — the board document publishes userId + nine role booleans (RESEARCH §4, v12.65)'); sys.exit(1)
PY
) && [ -z "$missing" ] \
  || fail "t4: the members section violates the shape contract: ${missing:-see above} — it must list all nine role booleans (isAdmin/isActive required + the seven optional flags, replacing the stale four-flag body), the userId-keyed object shape, the no-usernames-at-board-privilege note (/api/users routes are site-admin-only), v12.65-stamped (C02 AC4+AC6)"
  ok "t4: Board members section lists the nine booleans (2 required + 7 optional) on the userId-keyed members[] objects, keeps no bare-ids claim, carries the site-admin username note, v12.65-stamped (C02 AC4)"
fi

# --- t5: header re-stamp + inertness to the sibling suites (AC5+AC6) -------------
if want t5; then
  head -n 25 "$OVERVIEW" | grep -qE '12\.65' \
    || fail "t5: the version-pinning header was not re-stamped to the v12.65 verification (C02 Tasks / AC6)"
  head -n 25 "$OVERVIEW" | grep -qF '2026-10-30' \
    || fail "t5: the header stamp lacks the 2026-10-30 verification date (AC6: every added fact sourced, and the file header is where the whole-file grounding lives)"

  log=/tmp/opencode/rest-overview.tools.log
  if bash "$TOOLS_SUITE" >"$log" 2>&1; then
    ok "t5a: bash $TOOLS_SUITE green — C02 is inert to the tool-surface pins (C02 AC5)"
  else
    tail -n 20 "$log" >&2
    fail "t5: $TOOLS_SUITE is not green — C02 edits no pinned region; this red belongs to C01's flipped count pins (or to a C02 edit outside scope) (log: $log)"
  fi
  log=/tmp/opencode/rest-overview.surface.log
  if bash "$SURFACE_SUITE" >"$log" 2>&1; then
    ok "t5b: bash $SURFACE_SUITE green — C02 is inert to the skill-surface pins (C02 AC5)"
  else
    tail -n 20 "$log" >&2
    fail "t5: $SURFACE_SUITE is not green — same ownership note as t5a (log: $log)"
  fi
fi

printf 'PASS: wekan-mcp rest-overview-v102 checks (%d ok)\n' "$checks"
