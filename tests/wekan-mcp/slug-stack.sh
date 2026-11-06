#!/usr/bin/env bash
# cf-106 C01 — the `slug` custom field as an append-only STACK (ask 1).
# (2026/2026-11-cf-106-feat-coord-fixes, chunks/C01.md "## Tests" S1-S5.)
#
# The combined `[<slug>](<session link>)` value stops being one line that a
# later run clobbers and becomes a stack of lines, newest LAST, with ONE parse
# authority (`_slug_from_combined_value`) shared by the preload tool and the
# skill contract, and `set_card_custom_field` staying a verbatim upsert (the
# append lives consumer-side). AC trace:
#   S1[AC3]  parser cases over the REAL function body in server.py, the
#            one-walk/only-scanner law, and the ruled legacy + pairing shape
#   S2[AC1,AC2] boards source+mirror: append shape, idempotent same-slug branch,
#            never-drop/never-reorder, "last non-empty line" parse + tolerance
#   S3[AC4,AC5] call-shapes.md rows: verbatim upsert AND consumer-side append
#   S4[AC5] posture: the retired `session` field appears only in never-read /
#            never-written wording; no agent-side backfill
#   S5[AC6] roster wording (owner ruling OQ-15): slug the only ACTIVE
#            agent-facing field, other live fields outside the surface without
#            claiming they do not exist, Priority undeclared. (A15 in
#            tests/agent-perms/surface.sh re-pins the same fence on the source
#            bullet; this leg adds the mirror and the fabricated controls.)
#
# Red posture (designed red before the C01 dev edit, per the chunk):
#   S1 reddens on two cells — a two-line stack parses to the FIRST entry today
#   (the newest slug is lost, which is the ask) and `""` returns `""` instead of
#   None. The other cells (single combined, bare legacy value, None) HOLD green
#   across red->green: the parser must keep them.
#   S2/S4/S5 are red until the wording lands (they grep for the stack rule, the
#   "last non-empty line" phrasing and the agent-facing roster), each red naming
#   the exact sentence dev must write. S3 is red only for the append half of the
#   `set_card_custom_field` row (the verbatim-upsert half is a HOLD pin).
#   Fabricated controls (S3/S5) run against TMP copies with the suite's OWN
#   checker, so no arm here is vacuous.
#
# Offline-deterministic: the tree + an AST-extracted copy of the parser run in
# the harness's own python (no `mcp` package here, no board, no network).
#
# cf-106 C07 test round (2026-11-04, agent-test): S1 execs the parser in a
# namespace holding every module-level `_slug*` def, not one function per
# namespace — the isolated shape NameErrors on a helper that delegates to its
# sibling, so it forced C07's dev to write a second line-walk instead of sharing
# the authority (server.py's own get_card_details docstring cites this leg).
# With the coordinator's ruling landed (one walk, the scalar delegating, a legacy
# bare value reading as a one-entry stack of itself), the spelling-based copy
# guard is replaced by the behaviour-based single-walk check it always needed:
# exactly one module-level def may scan lines for the `](` pair (docstrings
# excluded — they quote the format) and every other `_slug*` def must delegate to
# it. The ruled legacy shape is pinned HERE, in S1, rather than only in
# card-details.sh t3, because it is a property of the parser: the stack carries a
# bare value as its single entry, a bare line inside a bracketed stack is not an
# entry, and `current_slug == slug_stack[-1]` for every value, so a card never
# reports an empty stack next to a non-empty current slug. Arms are named
# (structural / scalar / stack / pairing) so the five fabricated copies prove
# which arm bites instead of passing by accident.
#
# Usage:
#   bash tests/wekan-mcp/slug-stack.sh             # S1..S5
#   bash tests/wekan-mcp/slug-stack.sh S1 S3       # subset
#   WEKAN_SERVER=<path> bash tests/wekan-mcp/slug-stack.sh S1   # scratch-copy probe
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SERVER="${WEKAN_SERVER:-containers/wekan-mcp/wekan_mcp/server.py}"
BD_SRC=".rulesync/skills/boards/SKILL.md"
BD_GEN=".opencode/skills/boards/SKILL.md"
CALLS="skills/wekan-mcp/references/call-shapes.md"
SKILL="skills/wekan-mcp/SKILL.md"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s (artifacts kept at %s)\n' "$1" "$TMP" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/slug-stack-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5; do WANT["s$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^s[1-5]$ ]] || fail "unknown check id '$a' (expected S1..S5)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# Co-location window helper (agent-board-coord/* + wekan-mcp convention): the
# contract needles must read as ONE passage, not as scattered file-wide hits.
cat >"$TMP/win.py" <<'PY'
import sys
argv = sys.argv[1:]
ci = argv[0] == '--ci'
if ci:
    argv = argv[1:]
path, span = argv[0], int(argv[1])
needles = argv[2:]
text = open(path).read()
if ci:
    text = text.lower(); needles = [n.lower() for n in needles]
pts = []
for n in needles:
    start, found = 0, 0
    while True:
        i = text.find(n, start)
        if i < 0:
            break
        pts.append((i, n)); start = i + 1; found += 1
    if not found:
        print(f'missing needle: {n}'); sys.exit(1)
pts.sort()
need = len(set(needles))
cnt, have, best, left = {}, 0, None, 0
for right, (p, n) in enumerate(pts):
    cnt[n] = cnt.get(n, 0) + 1
    if cnt[n] == 1:
        have += 1
    while have == need:
        s = p - pts[left][0]
        if best is None or s < best:
            best = s
        cnt[pts[left][1]] -= 1
        if cnt[pts[left][1]] == 0:
            have -= 1
        left += 1
if best is None or best > span:
    print(f'no window of {span} chars covers all needles (min span {best})'); sys.exit(1)
PY

# --- S1: the parser — ONE walk, newest-LAST, ruled legacy shape (AC3) -----------
# Reusable checker so the fabricated controls exercise the SAME arms as the live
# file (the A10/A14 non-vacuity discipline). Arms are named so a control proves
# which arm bites: --arms takes a comma list.
#   structural — exactly one module-level def may scan lines for the "](" pair,
#                and every other _slug* def must call one (no second walk, not
#                even a behaviour-preserving private copy);
#   scalar     — the current-slug answers (AC3 cell table);
#   stack      — the stack shape, including the ruled legacy bare value
#                (one-entry stack of itself) and the stack+legacy-line mix;
#   pairing    — current_slug == slug_stack[-1] for every value, so a card can
#                never report an empty stack with a non-empty current slug.
# The legacy shape is pinned here (the ask's Q1 ruling) rather than only in
# card-details.sh t3, because it is a property of the parser, not of the read.
if want s1; then
  [ -f "$SERVER" ] || fail "S1[AC3]: $SERVER missing (harness fault)"
  cat >"$TMP/slugparse.py" <<'PY'
import ast, sys, typing

arms = "structural,scalar,stack,pairing"
args = sys.argv[1:]
for i, a in enumerate(args):
    if a == "--arms":
        arms = args[i + 1]
        del args[i:i + 2]
        break
path = args[0]
arms = [a.strip() for a in arms.split(",") if a.strip()]

src = open(path).read()
tree = ast.parse(src)
defs = [n for n in tree.body if isinstance(n, ast.FunctionDef)]
SCALAR = "_slug_from_combined_value"
if not any(n.name == SCALAR for n in defs):
    print(f"structural: {SCALAR} is gone from {path} — the boards skill and preload point at that name "
          "(rename is forbidden by chunks/C01.md Notes)"); sys.exit(1)

# --- arm: structural — one walk of the combined value, everyone else delegates.
# "Scans" is behavioural, not spelling-matched against one implementation: a
# module-level def scans when it holds a string constant with "](" OUTSIDE its
# docstring (docstrings legitimately quote the [<slug>](<session link>) format).
def scans_pair(fn):
    doc = set()
    if fn.body and isinstance(fn.body[0], ast.Expr) and isinstance(fn.body[0].value, ast.Constant) \
            and isinstance(fn.body[0].value.value, str):
        doc.add(id(fn.body[0].value))
    return any(isinstance(c, ast.Constant) and isinstance(c.value, str) and "](" in c.value
               and id(c) not in doc for c in ast.walk(fn))


scanners = [n.name for n in defs if scans_pair(n)]
if "structural" in arms:
    if len(scanners) != 1:
        print(f"structural: {len(scanners)} module-level defs scan lines for the ]( pair: {scanners} — "
              f"the combined slug value has exactly ONE walk (C07 single-authority ruling)"); sys.exit(1)
    for n in defs:
        if not n.name.startswith("_slug") or scans_pair(n):
            continue
        callees = {c.func.id for c in ast.walk(n) if isinstance(c, ast.Call) and isinstance(c.func, ast.Name)}
        if not any(c.startswith("_slug") and c != n.name for c in callees):
            print(f"structural: {n.name} scans nothing and calls no _slug* helper — every _slug* def besides "
                  f"the one scanner must delegate to it, never reimplement the walk"); sys.exit(1)

# The stack authority is the single scanner when there is exactly one (the ruled
# shape); with the structural arm switched off, fall back to its name so the
# behaviour arms stay meaningful on a mutated copy.
stack_name = scanners[0] if len(scanners) == 1 else "_slug_stack_from_combined_value"

# Run the REAL bodies, not re-implementations, in ONE shared namespace: the
# delegating scalar is undefined in an isolated one, and per-function exec would
# force the duplication this arm exists to forbid.
ns = {"Optional": typing.Optional}
for n in defs:
    if n.name.startswith("_slug"):
        exec(ast.get_source_segment(src, n), ns)
parse = ns[SCALAR]
stackfn = ns.get(stack_name)
if not callable(stackfn):
    print(f"stack: no one-argument stack parser ({stack_name}) in {path} (harness: the arm's assumption "
          f"about its name broke)"); sys.exit(1)

# AC3 cell table for the current slug: (input, expected). None is the literal None.
CASES = [
    ("[old](u1)\n[new](u2)", "new"),      # stack -> the LAST entry (the ask)
    ("[only](u)", "only"),                # single combined line (HOLD)
    ("cf-1-x", "cf-1-x"),                 # legacy bare value (HOLD, ruled: its own stack entry)
    (None, None),                          # unset (HOLD)
    ("", None),                            # empty value reads as unset (AC3)
    ("[a](u1)\n[b](u2)\n[c](u3)", "c"),    # three runs, newest last
    ("[a](u1)\n", "a"),                    # trailing newline keeps the one entry
    ("[a](u1)\nnotes without brackets", "a"),  # prose tail: bracket scan ignores it
    ("just prose, no brackets", "just prose, no brackets"),  # documented passthrough, never a crash
    ("[old](u1)\n[old](u2)", "old"),       # idempotent same-slug rewrite reads back the same slug
]
# The stack side, ruled by the coordinator for cf-106 C07: a value with no
# bracket pair at all is a ONE-entry stack of the stripped value (never []),
# because every card must satisfy current_slug == slug_stack[-1]; a bare line
# INSIDE a bracketed stack is not an entry; only a missing/blank value is [].
STACKS = [
    (None, []),                            # unset field -> no stack
    ("", []),                              # empty -> no stack
    ("   \n \n", []),                      # blank lines -> no stack, not a [""] entry
    ("cf-1-x", ["cf-1-x"]),                # the ruled legacy bare shape
    ("just prose, no brackets", ["just prose, no brackets"]),
    ("cf-1-x\n", ["cf-1-x"]),              # trailing newline keeps one entry
    ("[only](u)", ["only"]),
    ("[old](u1)\n[new](u2)", ["old", "new"]),      # oldest first
    ("[a](u1)\nnotes without brackets", ["a"]),     # bare tail line is NOT an entry
    ("[a](u1)\n[b](u2)\nlegacy-bare-line", ["a", "b"]),  # stack + legacy line: newest wins
    ("legacy-bare\n[a](u1)", ["a"]),       # legacy line below a stack entry: the entry wins
    ("[old](u1)\n[old](u2)", ["old", "old"]),
]

def check(table, fn, arm):
    errs = []
    for value, want in table:
        try:
            got = fn(value)
        except Exception as e:  # a crash is never an acceptable answer
            errs.append(f"{value!r} raised {type(e).__name__}: {e}")
            continue
        if got != want:
            errs.append(f"{value!r} -> {got!r}, want {want!r}")
    if errs:
        print(f"{arm}: " + "; ".join(errs)); sys.exit(1)

if "scalar" in arms:
    check(CASES, parse, "scalar")
if "stack" in arms:
    check(STACKS, stackfn, "stack")
if "pairing" in arms:
    # The ruling in invariant form: the scalar is always the stack's last entry,
    # and an empty stack never carries a non-empty current slug.
    errs = []
    for value in {v for v, _ in CASES} | {v for v, _ in STACKS}:
        st, cu = stackfn(value), parse(value)
        if cu != (st[-1] if st else None):
            errs.append(f"{value!r}: current_slug {cu!r} != slug_stack[-1] of {st!r}")
        if not st and cu is not None:
            errs.append(f"{value!r}: slug_stack [] with non-empty current_slug {cu!r}")
    if errs:
        print("pairing: " + "; ".join(errs)); sys.exit(1)
sys.exit(0)
PY
  python3 "$TMP/slugparse.py" "$SERVER" || fail "S1[AC3]: the single-walk slug parser no longer satisfies the stack contract (reason above)"

  # Controls: fabricated copies of the live module, each breaking ONE arm. Built
  # from the live source (not hand-written) so they track it; a mutation that can
  # no longer be applied is a harness fault (exit 2), never a silent pass.
  cat >"$TMP/mutants.py" <<'PY'
import re, sys

src = open(sys.argv[1]).read()
out = {}

def seg(name):
    m = re.search(rf"^def {name}\(.*?(?=\n\ndef |\n@|\Z)", src, re.S | re.M)
    if not m:
        print(f"control {name}: could not locate def {name} in the live source (harness fault)"); sys.exit(2)
    return m.group(0)

stack_src = seg("_slug_stack_from_combined_value").rstrip("\n")
scalar_src = seg("_slug_from_combined_value").rstrip("\n")

# 1) second scanner: a duplicate of the walk under another name (behaviours all
#    unchanged — only the structural arm can see it).
out["second-scanner"] = src + "\n\n" + stack_src.replace(
    "def _slug_stack_from_combined_value(", "def _slug_pair_scan_duplicate(", 1) + "\n"

# 2) behaviour-preserving private walk: the scalar recomputes the same answers
#    (marker built at runtime, so the "](" literal scan stays clean) instead of
#    delegating — again only the structural arm can see it.
private_scalar = '''def _slug_from_combined_value(value: Optional[str]) -> Optional[str]:
    pair = "]" + "("
    for raw in reversed((value or "").splitlines()):
        line = raw.strip()
        if line.startswith("[") and pair in line and line.endswith(")"):
            return line[1:line.index(pair)]
    return (value or "").strip() or None'''
out["no-delegate"] = src.replace(scalar_src, private_scalar, 1)

# 3) drift: the scalar delegates but reduces to the OLDEST entry (pre-C07
#    newest-first confusion) — the behaviour arms, not the structural one, bite.
out["drift-oldest"] = src.replace(scalar_src, '''def _slug_from_combined_value(value: Optional[str]) -> Optional[str]:
    stack = _slug_stack_from_combined_value(value)
    return stack[0] if stack else None''', 1)

# 4) legacy regression: the stack parser answers [] for a bare value again
#    (the pre-ruling shape).
ruled = """    if entries:
        return entries
    bare = value.strip()
    return [bare] if bare else []"""
if ruled not in stack_src:
    print("control legacy-empty: the ruled bare-value fallback is no longer spelled as expected (harness fault)"); sys.exit(2)
out["legacy-empty"] = src.replace(ruled, "    return entries", 1)

# 5) the whole pre-ruling shape back: a stack parser that answers [] for a bare
#    value AND a scalar with its own walk that passes the value through — i.e.
#    an empty stack next to a non-empty current slug (the ruling's violation).
out["pre-ruling"] = out["legacy-empty"].replace(scalar_src, private_scalar, 1)

for name, text in out.items():
    if text == src:
        print(f"control {name}: mutation was a no-op against the live source (harness fault)"); sys.exit(2)
    open(sys.argv[1 + list(out).index(name) + 1], "w").write(text)
print(" ".join(out))
PY
  python3 "$TMP/mutants.py" "$SERVER" "$TMP/m-second-scanner.py" "$TMP/m-no-delegate.py" \
    "$TMP/m-drift-oldest.py" "$TMP/m-legacy-empty.py" "$TMP/m-pre-ruling.py" >/dev/null \
    || fail "S1[AC3]: a control copy could not be built from $SERVER (harness fault)"
  # Each control reddens the named arm, and with the other arms switched off
  # nothing else can be credited for catching it (attribution, not incidental).
  ctl_red() {
    if python3 "$TMP/slugparse.py" --arms "$2" "$TMP/m-$1.py" >"$TMP/m-$1.out" 2>&1; then
      fail "S1[AC3]: control '$1' passes the '$2' arm — that arm no longer bites (non-vacuity)"
    fi
    msg=$(head -1 "$TMP/m-$1.out")
    case "$msg" in
      "$2:"*) ;;
      *) fail "S1[AC3]: control '$1' was caught by the wrong arm: $(printf '%.140s' "$msg")" ;;
    esac
  }
  ctl_red second-scanner structural   # a second walk, behaviours unchanged
  ctl_red no-delegate structural      # a private walk reproducing the answers
  ctl_red drift-oldest pairing        # the scalar reducing to the oldest entry
  ctl_red legacy-empty stack          # the bare value no longer its own entry
  ctl_red pre-ruling pairing          # empty stack next to a non-empty current
  ctl_red pre-ruling structural
  ok "S1[AC3]: one module-level def scans the ]( pair and every other _slug* def delegates to it; the current slug is the LAST bracketed entry (2-, 3-line stacks), the legacy bare value is a one-entry stack of itself, a bare line inside a bracketed stack is not an entry, stack+legacy resolves to the newest entry, None/empty/blank are [], and current_slug always equals slug_stack[-1] — plus five fabricated copies (second scanner, private non-delegating walk, oldest-entry drift, bare-value-returns-[], the whole pre-ruling shape) each reddening the intended arm"
fi

# --- S2: boards source + mirror carry the stack rule (AC1, AC2) -----------------
if want s2; then
  for f in "$BD_SRC" "$BD_GEN"; do
    [ -f "$f" ] || fail "S2[AC1]: $f missing (harness fault)"
    # 1. the literal append shape: existing value, newline, this run's line.
    python3 "$TMP/win.py" "$f" 900 '<slug>](<session link>)' 'existing' \
      || fail "S2[AC1]: $f has no write-back sentence pairing this run's [<slug>](<session link>) line with the value's EXISTING content — C01 AC1's literal shape is \`<existing value>\\n[<slug>](<session link>)\` (red before C01: the step is a blind upsert)"
    grep -qF '\n[<slug>](<session link>)' "$f" \
      || fail "S2[AC1]: $f never spells the append with the literal \\n separator between the existing value and this run's line (AC1 names the shape verbatim — write it, do not paraphrase it away)"
    # 2. the idempotent same-slug branch (link refresh, no duplicate line).
    python3 "$TMP/win.py" --ci "$f" 700 'same slug' 'in place' \
      || fail "S2[AC1]: $f lacks the idempotent branch — when the last line's bracketed text EQUALS this run's slug, rewrite that line in place (refresh the link half); never append a duplicate (red before C01)"
    # 3. never drop / never reorder an existing line.
    python3 "$TMP/win.py" --ci "$f" 500 'never drop' 'reorder' \
      || fail "S2[AC1]: $f lost the never-drop / never-reorder sentence — the stack is append-only (AC1, red before C01)"
    # 4. the D11 parse rule: newest = the LAST non-empty line.
    grep -qEi 'last non-empty line' "$f" \
      || fail "S2[AC2]: $f's Resume-vs-new-run rule does not name the LAST NON-EMPTY LINE as this run's slug — the multi-line stack parse (D11 as amended by C01; red before C01)"
    # 5. mixed-shape tolerance stated explicitly (split pre-flip values,
    #    duplicated combined values) so resume never dies on live data.
    python3 "$TMP/win.py" --ci "$f" 900 'toler' 'split' \
      || fail "S2[AC2]: $f never states the mixed-live-shape tolerance (split pre-flip slug/session values and duplicated combined values are TOLERATED on read, never rewritten) — C01 AC2/AC5 (red before C01)"
    # 6. the <slug>-N sequence rule survives the stack.
    python3 "$TMP/win.py" --ci "$f" 600 'complete' '<slug>-1' \
      || fail "S2[AC2]: $f lost the <slug>-1 sequence rule for a completed newest run (C01 keeps it — the stack does not retire the sequence)"
  done
  # source <-> generated mirror byte-parity of the amended sections (the
  # regeneration contract the alias-twin law rides on).
  python3 - "$BD_SRC" "$BD_GEN" <<'PY' || fail "S2[AC1]: boards source/generated mirror drift in the slug/write-back wording — regenerate, never hand-edit .opencode/"
import re, sys
def sections(p):
    text = open(p).read()
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    assert m, f"{p}: no parsable frontmatter"
    body = m.group(2)
    out = {}
    cur, buf = None, []
    for line in body.splitlines():
        if re.match(r"^#{2,3} ", line):
            if cur:
                out[cur] = "\n".join(buf).strip()
            cur, buf = line.strip(), []
        elif cur is not None:
            buf.append(line)
    if cur:
        out[cur] = "\n".join(buf).strip()
    return out
s, g = sections(sys.argv[1]), sections(sys.argv[2])
for head in ("## Post-plan card write-back",):
    if head not in s or head not in g:
        print(f"section {head!r} missing from one of the pair (source sections: {sorted(s)} / mirror: {sorted(g)})"); sys.exit(1)
    if s[head] != g[head]:
        print(f"section {head!r} differs between source and generated mirror — the append rule must be byte-identical on both"); sys.exit(1)
PY
  ok "S2[AC1,AC2]: boards source AND mirror carry the literal append shape with \\n, the idempotent same-slug rewrite, the never-drop/never-reorder law, the last-non-empty-line parse, the mixed-shape tolerance and the <slug>-1 sequence rule — and the write-back section is byte-identical across the pair"
fi

# --- S3: docs rows — verbatim upsert + consumer-side append (AC4, AC5) ---------
if want s3; then
  for f in "$CALLS" "$SKILL"; do
    [ -f "$f" ] || fail "S3[AC4]: $f missing (harness fault)"
  done
  # The set_card_custom_field row keeps the verbatim-upsert wording (HOLD) and
  # gains the consumer-side append sentence (red until C01).
  row=$(grep -m1 -E '^\|[[:space:]]*`set_card_custom_field`' "$CALLS" || true)
  [ -n "$row" ] || fail "S3[AC4]: $CALLS lost its \`set_card_custom_field\` row — the upsert semantics have a documented home (harness fault if the row was renamed)"
  echo "$row" | grep -qiF 'verbatim' \
    || fail "S3[AC4]: the set_card_custom_field row no longer says the value is stored VERBATIM — C01 keeps the server semantics unchanged (AC4); the append is a skill-contract rule"
  echo "$row" | grep -Eqi 'append' \
    || fail "S3[AC4]: the set_card_custom_field row never says the slug STACK append is CONSUMER-side read-modify-write (C01 docs parity; red before C01)"
  echo "$row" | grep -Eqi 'no server-side append|server does not append|no append (semantics|support) server-side' \
    || fail "S3[AC4]: the row does not NEGATE a server-side append primitive — the stack is built by the consumer, and the docs must say so out loud (red before C01)"
  # preload slug row follows the same authority (newest-last), without
  # restating the parse.
  preload_row=$(grep -m1 -E '^\|[[:space:]]*`preload_board`' "$CALLS" || true)
  [ -n "$preload_row" ] || fail "S3[AC4]: $CALLS lost its \`preload_board\` row (harness fault)"
  echo "$preload_row" | grep -Eqi 'last|newest' \
    || fail "S3[AC4]: the preload_board row still describes the slug as the parsed (first) bracketed value — C01 makes it the LAST/newest entry of the stack (red before C01)"
  # Negative control (the cf-85 re-pin posture kept): a fabricated row that
  # claims the TOOL appends must be rejected by this same checker.
  python3 - "$CALLS" "$TMP/calls-appends.md" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"(?m)^\|[ \t]*`set_card_custom_field`[^\n]*", text)
assert m, "fixture: no set_card_custom_field row"
open(sys.argv[2], "w").write(text[:m.start()] + "| `set_card_custom_field` | `board_id`, `card_id`, `custom_field_id`, `value` | — | `{card_id, custom_field_id, value, attached}` — appends the value to the field's stack server-side. | source-only |" + text[m.end():])
PY
  fab=$(grep -m1 -E '^\|[[:space:]]*`set_card_custom_field`' "$TMP/calls-appends.md")
  if echo "$fab" | grep -qiF 'verbatim'; then
    fail "S3[AC4]: NEGATIVE CONTROL FAILED — the fabricated row kept the 'verbatim' wording, so the HOLD half proves nothing"
  fi
  if echo "$fab" | grep -Eqi 'no server-side append|server does not append|no append (semantics|support) server-side'; then
    fail "S3[AC4]: NEGATIVE CONTROL FAILED — the fabricated server-side-append row passed the negation check"
  fi
  # Server side: the tool itself gains no append logic (AC4 machine check).
  python3 - "$SERVER" <<'PY' || fail "S3[AC4]: set_card_custom_field grew append/read-modify-write logic — the append lives in the skill contract only (AC4)"
import ast, sys
src = open(sys.argv[1]).read()
fn = next((n for n in ast.parse(src).body if isinstance(n, ast.FunctionDef) and n.name == "set_card_custom_field"), None)
if fn is None:
    print("no set_card_custom_field function in server.py"); sys.exit(1)
b = ast.get_source_segment(src, fn)
if "_slug_from_combined_value" in b:
    print("set_card_custom_field parses the combined value — a write tool touching the parse authority means the append moved server-side"); sys.exit(1)
low = b.lower()
for needle in ("existing value +", "value + \"\\n\"", "\\n["):
    if needle in low:
        print(f"set_card_custom_field contains an append expression ({needle!r}) — AC4 keeps the upsert verbatim"); sys.exit(1)
print("ok: S3 server-side upsert unchanged")
PY
  ok "S3[AC4,AC5]: the set_card_custom_field row still says verbatim upsert AND names consumer-side appending with an explicit no-server-side-append negation; the preload row reads slug as the newest stack entry; server.py's set_card_custom_field grew no append logic; a fabricated server-append row is rejected"
fi

# --- S4: the retired `session` field stays never-read/never-written (AC5) ------
if want s4; then
  for f in "$BD_SRC" "$BD_GEN"; do
    [ -f "$f" ] || fail "S4[AC5]: $f missing (harness fault)"
    # Every sentence that mentions the retired field must sit in never-read /
    # never-written wording (windowed, provider-loops t7 style).
    if ! python3 - "$f" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
bad = []
# Sentence-scoped: the retired field's name in backticks, then the sentence.
for m in re.finditer(r"`session`", text):
    start = max(text.rfind(". ", 0, m.start()), text.rfind("\n", 0, m.start()),
                text.rfind("; ", 0, m.start()))
    end = min(
        next((i for i in [text.find(". ", m.end())] if i >= 0), len(text)),
        next((i for i in [text.find("\n", m.end())] if i >= 0), len(text)),
    )
    sentence = text[start:end]
    if not re.search(r"(?i)never[ ,]+(read|written|reads|writes)|never read, never written|retired", sentence):
        bad.append(sentence.strip()[:160])
if bad:
    print("lines mentioning the retired `session` field WITHOUT never-read/never-written wording:")
    print("\n".join(bad))
    sys.exit(1)
print("clean")
PY
    then fail "S4[AC5]: $f mentions the retired session field outside its never-read/never-written posture — the field is retired, and the only sanctioned wording is the retirement clause"; fi
    # No backfill instruction anywhere on the pair (AC5: frozen history).
    grep -Eiq 'backfill.*(session|slug)|(session|slug).*backfill' "$f" \
      && fail "S4[AC5]: $f instructs backfilling the legacy slug/session values — C01 AC5 freezes existing card fields; the parse rule only tolerates them"
    # And the field must never appear as a write target in the flow steps.
    grep -Eq 'set_card_custom_field[^|]*`session`' "$f" \
      && fail "S4[AC5]: $f writes the retired session field through set_card_custom_field"
  done
  ok "S4[AC5]: the retired session field appears only inside never-read/never-written/retired wording on both boards surfaces, no backfill instruction exists, and it is never a write target"
fi

# --- S5: the custom-field roster, agent-facing not board-count (AC6) -----------
# Reusable checker so the fabricated controls exercise the SAME code (the
# A10/A14 non-vacuity discipline).
cat >"$TMP/roster.py" <<'PY'
# The cf-106 C01 roster contract (owner ruling OQ-15):
#   * the roster bullet names `slug` as the ONLY ACTIVE agent-facing field;
#   * it names the retired `session` field with never-read AND never-written;
#   * it does NOT claim the board holds exactly one custom field (live drift:
#     Priority + the retired session field exist), and the frontmatter
#     description may not claim it either;
#   * it does not declare the live Priority field (another ticket owns it).
import re, sys
path = sys.argv[1]
text = open(path).read()
m = re.search(r"(?m)^[-*][ \t]+Custom fields:[^\n]*", text)
if not m:
    print("no 'Custom fields:' roster bullet"); sys.exit(3)
bullet = m.group(0)
errs = []
if not re.search(r"`slug`", bullet):
    errs.append("bullet does not name `slug`")
if not re.search(r"(?i)only[^.]*active", bullet):
    errs.append("bullet does not name slug the ONLY ACTIVE field")
if not re.search(r"(?i)agent-facing|for the agent", bullet):
    errs.append("bullet does not scope the roster to the AGENT-FACING field set")
if not re.search(r"\[<slug>\]\(", bullet):
    errs.append("bullet does not state the combined [<slug>](<session link>) value")
if not re.search(r"`session`", bullet):
    errs.append("bullet does not name the retired `session` field")
if not re.search(r"(?i)never[ ,]*read", bullet):
    errs.append("bullet lost the never-read clause")
if not re.search(r"(?i)never[ ,]*written", bullet):
    errs.append("bullet lost the never-written clause")
if not re.search(r"(?i)third[\w \t-]{0,20}field", bullet):
    errs.append("bullet lost the third-field negation (the D19 fence)")
if "models" not in bullet:
    errs.append("bullet lost the D12 no-models-field negation")
if re.search(r"(?i)exactly[ ]+(one|1)[^\n]{0,40}(board-level|board level|text field|custom field)", bullet):
    errs.append("bullet claims the board has exactly ONE custom field (falsified by live drift — scope it to the agent-facing set)")
if re.search(r"(?i)exactly[ ]+(two|three)", bullet):
    errs.append("bullet counts fields into the agent roster")
if "Priority" in bullet:
    errs.append("bullet declares the live Priority field (undeclared by ruling OQ-15)")
for mm in re.finditer(r"(?i)single slug custom field|only custom field|one board-level text field", text):
    errs.append(f"current-state claim of a single board field (the frontmatter description counts too — reword it with the bullet): …{text[max(0, mm.start()-40):mm.end()+20]}…")
if errs:
    print("; ".join(errs)); sys.exit(1)
print("ok: S5 roster")
PY

if want s5; then
  for f in "$BD_SRC" "$BD_GEN"; do
    [ -f "$f" ] || fail "S5[AC6]: $f missing (harness fault)"
    python3 "$TMP/roster.py" "$f" \
      || fail "S5[AC6]: $f violates the cf-106 roster contract (reason above; red before C01's rewording lands)"
  done
  # Controls (the A10/A14 non-vacuity discipline): build ONE compliant file,
  # prove the checker accepts it (positive control), then fabricate each
  # violation ON TOP of that compliant base and require rejection — so a red
  # control means the intended violation, not an unrelated wording gap.
  python3 - "$BD_SRC" "$TMP/roster-compliant.md" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"(?m)^[-*][ \t]+Custom fields:[^\n]*", text)
assert m, "fixture: no Custom fields bullet"
repl = ("- Custom fields: `slug` is the only active agent-facing field, carrying the combined "
        "`[<slug>](<session link>)` link value; other live fields are outside the agent's read/write "
        "surface — the retired `session` field is never read, never written; no third agent-facing field "
        "and no `models` field.")
text = text[:m.start()] + repl + text[m.end():]
# The frontmatter description carries the same falsified claim ("the single
# slug custom field"); C01's rewording covers it too, so the compliant base
# moves both surfaces exactly as the contract asks.
text = text.replace("the single slug custom field", "the active slug custom field")
open(sys.argv[2], "w").write(text)
PY
  python3 "$TMP/roster.py" "$TMP/roster-compliant.md" >/dev/null 2>&1 \
    || fail "S5[AC6]: POSITIVE CONTROL FAILED — the checker rejects a roster wording that DOES satisfy the contract, so the arm is unsatisfiable and dev's correct text would go red; report rather than narrowing the contract"
  python3 - "$TMP/roster-compliant.md" "$TMP/roster-exactly-one.md" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"(?m)^[-*][ \t]+Custom fields:[^\n]*", text)
assert m, "fixture: no Custom fields bullet"
repl = ("- Custom fields: exactly ONE board-level text field — `slug`, carrying the combined "
        "`[<slug>](<session link>)` link value; the retired `session` field is never read, never written; "
        "no third field and no `models` field.")
open(sys.argv[2], "w").write(text[:m.start()] + repl + text[m.end():])
PY
  python3 "$TMP/roster.py" "$TMP/roster-exactly-one.md" >/dev/null 2>&1 \
    && fail "S5[AC6]: NEGATIVE CONTROL FAILED — the restored 'exactly ONE board-level text field' claim passed the roster checker"
  python3 - "$TMP/roster-compliant.md" "$TMP/roster-priority.md" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"(?m)^[-*][ \t]+Custom fields:[^\n]*", text)
assert m, "fixture: no Custom fields bullet"
repl = m.group(0).rstrip(".") + " — and the human-owned `Priority` number field, which the run reads and sets like `slug`."
open(sys.argv[2], "w").write(text[:m.start()] + repl + text[m.end():])
PY
  python3 "$TMP/roster.py" "$TMP/roster-priority.md" >/dev/null 2>&1 \
    && fail "S5[AC6]: NEGATIVE CONTROL FAILED — a fabricated Priority roster entry passed the roster checker (OQ-15 says Priority stays undeclared)"
  ok "S5[AC6]: the roster bullet on source AND mirror names slug the only active agent-facing field with never-read/never-written session wording, no board-count claim and no Priority declaration; the fabricated restoration and fabricated Priority row are both rejected, and a compliant wording passes"
fi

printf 'PASS: cf-106 slug-stack contract checks (%d ok)\n' "$checks"
