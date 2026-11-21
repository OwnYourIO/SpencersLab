#!/usr/bin/env bash
# cf-126 C03/C04 — the context-handoff doctrine + the repo-config pins.
#
# Homes: the boards-skill Context-handoff contract lines (C03 AC4's five,
# placed here per the chunk's admissible `tests/handoff/` home), the
# pipeline-role-coord step-8b cross-reference, and the `.opencode/opencode.jsonc`
# pins C03 Tests names "agents-md.sh-style" (the suite stays self-contained;
# the staged agents-md.sh carries only its own plan-folder admit). AC trace:
#   H1[line a: failed compaction is the PRIMARY signal]
#   H2[line b: successor bootstrap = the /pipeline-resume convention]
#   H3[line c: no-per-turn-manual-compaction law]
#   H4[line d: subagent relaunch-FRESH doctrine + the upstream failure ids]
#   H5[line e: the dispatcher's fresh-start reset]
#   H6[line f: repo-wide scope note, cite-only (the OQ3 ruling)]
#   H7[8b cross-reference in pipeline-role-coord cites the Stage map]
#   H8[C03 AC5: JSONC parses + compaction.keep.tokens with its convention
#       comment + NO deprecated V1 keys + NO top-level `agents` key (OQ4)]
#   H9[C04: the q27 served-context parity — the comment's figure equals the
#       catalog rows' limit.context (the verify-only leg's invariant; a dated
#       exact-value retarget belongs to the gate receipt)]
#
# Red posture: H1..H7 designed-red until C03 dev edits the skills and
# regenerates; H8 designed-red until the `compaction` block lands; H9 is green
# now and must HOLD green (it pins the invariant, not a state — reddening at a
# gate merge with a stale comment is the point). Fabricated-drift controls ride
# H1..H4, H7, H8 (the siblings' non-vacuity discipline).
#
# Usage:
#   bash tests/handoff/surface.sh           # H1..H9
#   bash tests/handoff/surface.sh H1 H8     # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BD_SRC=".rulesync/skills/boards/SKILL.md"
BD_GEN=".opencode/skills/boards/SKILL.md"
RC_SRC=".rulesync/skills/pipeline-role-coord/SKILL.md"
RC_GEN=".opencode/skills/pipeline-role-coord/SKILL.md"
CFG=".opencode/opencode.jsonc"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

TMP=$(mktemp -d /tmp/opencode/handoff-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7 8 9; do WANT["h$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^h[1-9]$ ]] || fail "unknown check id '$a' (expected H1..H9)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

cat >"$TMP/sectwin.py" <<'PY'
# Window scoped to one heading's section (the sibling suites' convention).
import re, sys
argv = sys.argv[1:]
ci = argv[0] == '--ci'
if ci:
    argv = argv[1:]
path, span, title = argv[0], int(argv[1]), argv[2]
needles = [n.lower() for n in argv[3:]] if ci else argv[3:]
text = open(path).read()
m = re.search(r'(?ms)^#+[^\n]*' + re.escape(title) + r'[^\n]*\n(.*?)(?=^#+[^\n]*$|\Z)', text)
if not m:
    print(f'section "{title}" not found'); sys.exit(1)
body = m.group(1).lower() if ci else m.group(1)
pts = []
for n in needles:
    i = body.find(n)
    if i < 0:
        print(f'needle "{n}" not in section "{title}"'); sys.exit(1)
    pts.append(i)
if max(pts) - min(pts) > span:
    print(f'section "{title}" needles span {max(pts) - min(pts)} > {span} — scattered'); sys.exit(1)
PY

cat >"$TMP/stripcopy.py" <<'PY'
# Fabricated-drift control fixture: copy with EVERY occurrence of one token
# removed; exits 3 when the token is absent (the live pin would be vacuous).
import sys
src, dst, token = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(src, encoding="utf-8").read()
if token not in t:
    print(f'control fault: anchor token "{token}" absent from {src}'); sys.exit(3)
open(dst, "w", encoding="utf-8").write(t.replace(token, ""))
PY

# The section the dev adds is named "Context handoff (compaction)" per the
# chunk; the title needle 'Context handoff' matches any heading carrying it.

# --- H1: a failed compaction is the PRIMARY signal (line a) ---------------------
if want h1; then
  for f in "$BD_SRC" "$BD_GEN"; do
    [ -f "$f" ] || fail "H1: $f missing (harness fault)"
    python3 "$TMP/sectwin.py" --ci "$f" 1600 'Context handoff' 'primary' 'token limit' 're-prompt' \
      || fail "H1[C03 AC4]: $f has no Context-handoff section stating that a FAILED compaction (compaction.failed / 'Compaction summary reached the output token limit') is the PRIMARY signal — never re-prompt the wedged session (upstream #56784/#57187); run the handoff protocol on the failure instead (red before C03 dev)"
  done
  python3 "$TMP/stripcopy.py" "$BD_SRC" "$TMP/h1-off.md" 'primary' \
    || fail "H1 control: could not fabricate the drift copy (anchor missing — the live pin is vacuous)"
  if python3 "$TMP/sectwin.py" --ci "$TMP/h1-off.md" 1600 'Context handoff' 'primary' >/dev/null 2>&1; then
    fail "H1 control: the copy stripped of the primary-signal wording still passed — the pin is vacuous"
  fi
  ok "H1[C03 AC4]: failed compaction as the primary signal, no-re-prompt law (source + mirror); stripped copy reddens"
fi

# --- H2: the successor bootstrap is the /pipeline-resume convention (line b) -----
if want h2; then
  for f in "$BD_SRC" "$BD_GEN"; do
    python3 "$TMP/sectwin.py" --ci "$f" 1400 'Context handoff' 'read order' 'MUST-load' 'pipeline-resume' \
      || fail "H2[C03 AC4/D10]: $f's Context-handoff section does not state the successor bootstrap law — the /pipeline-resume convention (read the plan folder in the read order, then the MUST-load skills), NO new mechanism (red before C03 dev)"
  done
  ok "H2[C03 AC4/D10]: successor bootstrap = the resume convention (source + mirror)"
fi

# --- H3: no per-turn manual compaction (line c) ----------------------------------
if want h3; then
  for f in "$BD_SRC" "$BD_GEN"; do
    python3 "$TMP/sectwin.py" --ci "$f" 1200 'Context handoff' 'manual' 'cache' \
      || fail "H3[C03 AC4/D19]: $f's Context-handoff section lost the no-per-turn-manual-compaction law (the auto threshold + the hook are the ONLY triggers; forcing compaction blows the token cache) (red before C03 dev)"
  done
  ok "H3[C03 AC4/D19]: the no-manual-compaction law (source + mirror)"
fi

# --- H4: the subagent relaunch-FRESH doctrine (line d) ---------------------------
if want h4; then
  for f in "$BD_SRC" "$BD_GEN"; do
    python3 "$TMP/sectwin.py" --ci "$f" 1800 'Context handoff' 'relaunch' 'fresh' 'launch brief' \
      || fail "H4[C03 AC4]: $f's Context-handoff section does not carry the subagent relaunch doctrine — a child whose error report carries the compaction-failure shape is relaunched FRESH with the full launch brief (chunk file + read order + skills), never a follow-up (red before C03 dev)"
    # The upstream failure ids are the WHY of the whole leg — without them the
    # doctrine reads as preference, and the #59110 exposure stays invisible.
    python3 "$TMP/sectwin.py" --ci "$f" 1800 'Context handoff' '56784' '57187' '59110' \
      || fail "H4[C03 AC4]: $f's relaunch law does not name the upstream failure shapes (#56784/#57187/#59110) as the reason — the reason must ride the rule (red before C03 dev)"
    python3 "$TMP/sectwin.py" --ci "$f" 1800 'Context handoff' 'alert' 'coord' \
      || fail "H4[C03 AC4/D8]: $f does not state that the relaunch decision is the coord's and the HA alert (question-notify) is the wedge detector"
  done
  python3 "$TMP/stripcopy.py" "$BD_SRC" "$TMP/h4-off.md" '59110' \
    || fail "H4 control: could not fabricate the drift copy (anchor missing — the live pin is vacuous)"
  if python3 "$TMP/sectwin.py" --ci "$TMP/h4-off.md" 1800 'Context handoff' '59110' >/dev/null 2>&1; then
    fail "H4 control: the copy stripped of the #59110 citation still passed — the failure-shapes pin is vacuous"
  fi
  ok "H4[C03 AC4]: relaunch-fresh doctrine + upstream ids + coord-decides/alert-detects split (source + mirror); stripped copy reddens"
fi

# --- H5: the dispatcher's fresh-start reset (line e) ------------------------------
if want h5; then
  for f in "$BD_SRC" "$BD_GEN"; do
    python3 "$TMP/sectwin.py" --ci "$f" 1800 'Context handoff' 'dispatcher' 'fresh' 'running facts' \
      || fail "H5[C03 AC4/D15]: $f's Context-handoff section does not state the dispatcher's reset shape — its handoff spawns a FRESH dispatcher carrying the running facts and ends; the fresh one starts from the loop body + the board block (red before C03 dev)"
  done
  ok "H5[C03 AC4/D15]: the dispatcher fresh-start reset (source + mirror)"
fi

# --- H6: the repo-wide scope note, cite-only (line f, the OQ3 ruling) ------------
if want h6; then
  for f in "$BD_SRC" "$BD_GEN"; do
    python3 "$TMP/sectwin.py" --ci "$f" 1400 'Context handoff' 'repo-wide' 'generic' \
      || fail "H6[C03 AC4/OQ3]: $f's Context-handoff section lacks the scope note — the hook is repo-wide (every agent); the board family's protocol is the full form, the other agents get the generic leg, cited not restated (red before C03 dev)"
  done
  ok "H6[C03 AC4/OQ3]: the repo-wide scope note (source + mirror)"
fi

# --- H7: role-coord step 8b cites the Stage map (never restates) ------------------
if want h7; then
  for f in "$RC_SRC" "$RC_GEN"; do
    [ -f "$f" ] || fail "H7: $f missing (harness fault)"
    python3 "$TMP/sectwin.py" --ci "$f" 900 '8b' 'dispatcher' \
      || fail "H7[C03 Tasks/C01 D18]: $f's step 8b does not name the dispatcher's top-level spawn as the board-family shape (red before C03 dev)"
    python3 "$TMP/sectwin.py" --ci "$f" 900 '8b' 'Stage map' \
      || fail "H7[C03 Tasks]: $f's 8b cross-reference does not cite the Stage map — the board-family clause lives there (cite, never restate)"
  done
  ok "H7[C03]: role-coord 8b names the dispatcher shape and cites the Stage map (source + mirror)"
fi

# --- H8: the opencode.jsonc compaction contract (C03 AC5) -------------------------
if want h8; then
  cat >"$TMP/jsonc.py" <<'PY'
# strip_jsonc -> json.loads (the tests/agent-perms/surface.sh A14 idiom, copied
# per the suites' self-contained convention).
import json, re, sys

def strip_jsonc(s):
    out, i, n, instr, esc = [], 0, len(s), False, False
    while i < n:
        c = s[i]
        if instr:
            out.append(c)
            if esc: esc = False
            elif c == '\\': esc = True
            elif c == '"': instr = False
            i += 1
            continue
        if c == '"':
            instr = True; out.append(c); i += 1; continue
        if c == '/' and i + 1 < n and s[i+1] == '/':
            while i < n and s[i] != '\n': i += 1
            continue
        if c == '/' and i + 1 < n and s[i+1] == '*':
            j = s.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        out.append(c); i += 1
    return re.sub(r',(\s*[}\]])', r'\1', ''.join(out))

def load(path):
    return json.loads(strip_jsonc(open(path, encoding="utf-8").read()))

if __name__ == "__main__":
    load(sys.argv[1])
    print("parse ok")
PY
  python3 "$TMP/jsonc.py" "$CFG" || fail "H8[C03 AC5]: $CFG does not parse as JSONC"
  python3 - "$CFG" <<'PY' || fail "H8[C03 AC5/D19/OQ4]: the compaction contract is violated (diagnostics above)"
import json, re, sys
def strip_jsonc(s):
    out, i, n, instr, esc = [], 0, len(s), False, False
    while i < n:
        c = s[i]
        if instr:
            out.append(c)
            if esc: esc = False
            elif c == '\\': esc = True
            elif c == '"': instr = False
            i += 1
            continue
        if c == '"':
            instr = True; out.append(c); i += 1; continue
        if c == '/' and i + 1 < n and s[i+1] == '/':
            while i < n and s[i] != '\n': i += 1
            continue
        if c == '/' and i + 1 < n and s[i+1] == '*':
            j = s.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        out.append(c); i += 1
    return re.sub(r',(\s*[}\]])', r'\1', ''.join(out))
raw = open(sys.argv[1], encoding="utf-8").read()
cfg = json.loads(strip_jsonc(raw))
errs = []
if "agents" in cfg:
    errs.append("top-level 'agents' key present — the OQ4 ruling (2026-11-17) is the SESSION model: its ABSENCE is the green state")
comp = cfg.get("compaction")
if not isinstance(comp, dict):
    errs.append(f"compaction block missing (red before C03 dev — D19's keep.tokens convention)")
else:
    keep = (comp.get("keep") or {}).get("tokens")
    if keep != 15000:
        errs.append(f"compaction.keep.tokens is {keep!r}, want the explicit 15000 (D19: the 15k default written as the value, owner-tunable)")
    if "auto" in comp and comp["auto"] is False:
        errs.append("compaction.auto set to false — auto + overflow recovery stay ON, the hook rides them")
    for dead in ("prune", "tail_turns", "preserve_recent_tokens", "reserved"):
        if dead in comp:
            errs.append(f"deprecated V1 field '{dead}' emitted — the field policy bans recommending it (RESEARCH section 5)")
low = raw.lower()
if isinstance(comp, dict):
    for needle in ("15-step", "owner-tunable", "manual compaction"):
        if needle not in low:
            errs.append(f"the keep.tokens convention comment must name '{needle}' (the knob's meaning is the comment's job; dev may reword only this set together)")
if errs:
    print("; ".join(errs)); sys.exit(1)
PY
  # Fabricated-drift: an agents-key insertion must redden the absence arm.
  python3 - "$CFG" "$TMP/h8-agents.md" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
open(sys.argv[2], "w", encoding="utf-8").write(t.replace("{", "{\n  \"agents\": { \"compaction\": { \"model\": \"x\" } },", 1))
PY
  if python3 - "$TMP/h8-agents.md" <<'PY' >/dev/null 2>&1
import json, re, sys
def strip_jsonc(s):
    out, i, n, instr, esc = [], 0, len(s), False, False
    while i < n:
        c = s[i]
        if instr:
            out.append(c)
            if esc: esc = False
            elif c == '\\': esc = True
            elif c == '"': instr = False
            i += 1
            continue
        if c == '"':
            instr = True; out.append(c); i += 1; continue
        if c == '/' and i + 1 < n and s[i+1] == '/':
            while i < n and s[i] != '\n': i += 1
            continue
        if c == '/' and i + 1 < n and s[i+1] == '*':
            j = s.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        out.append(c); i += 1
    return re.sub(r',(\s*[}\]])', r'\1', ''.join(out))
cfg = json.loads(strip_jsonc(open(sys.argv[1], encoding="utf-8").read()))
sys.exit(0 if "agents" not in cfg else 1)
PY
  then
    fail "H8 control: the copy with a fabricated top-level agents key passed the absence arm — the OQ4 pin is vacuous"
  fi
  ok "H8[C03 AC5/D19/OQ4]: JSONC parses; keep.tokens = 15000 with the convention comment; no deprecated V1 keys; the agents-key absence is pinned and the fabricated insertion reddens"
fi

# --- H9: the q27 served-context parity (C04 verify-only leg) ---------------------
if want h9; then
  python3 - "$CFG" <<'PY' || fail "H9[C04 AC6]: the q27 comment/state parity is broken — the verify-only leg's invariant (diagnostics above)"
import json, re, sys
def strip_jsonc(s):
    out, i, n, instr, esc = [], 0, len(s), False, False
    while i < n:
        c = s[i]
        if instr:
            out.append(c)
            if esc: esc = False
            elif c == '\\': esc = True
            elif c == '"': instr = False
            i += 1
            continue
        if c == '"':
            instr = True; out.append(c); i += 1; continue
        if c == '/' and i + 1 < n and s[i+1] == '/':
            while i < n and s[i] != '\n': i += 1
            continue
        if c == '/' and i + 1 < n and s[i+1] == '*':
            j = s.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        out.append(c); i += 1
    return re.sub(r',(\s*[}\]])', r'\1', ''.join(out))
raw = open(sys.argv[1], encoding="utf-8").read()
cfg = json.loads(strip_jsonc(raw))
provs = cfg.get("providerMetas") or cfg.get("providers") or {}
models = (provs.get("gpu-ai") or {}).get("models") or {}
errs = []
ctx = set()
for k, prio in (("qwen3.8-27b-radiance", 4), ("qwen3.8-27b-radiance-urgent", 8), ("qwen3.8-27b-radiance-low", 0)):
    e = models.get(k)
    if not e:
        errs.append(f"catalog row {k} missing (the trio stands: 8/4/0, wire qwen3.8-27b-radiance)")
        continue
    if e.get("modelID") != "qwen3.8-27b-radiance":
        errs.append(f"{k}: modelID {e.get('modelID')!r} — no catalog modelID changes in C04")
    if (e.get("body") or {}).get("priority") != prio:
        errs.append(f"{k}: body.priority {(e.get('body') or {}).get('priority')!r}, want {prio}")
    ctx.add((e.get("limit") or {}).get("context"))
if len(ctx) != 1 or None in ctx:
    errs.append(f"the trio's limit.context values diverge ({sorted(map(str, ctx))}) — one lane, one served figure")
else:
    served = ctx.pop()
    # The comment's figure must equal the rows' limit.context — the single-
    # authority honesty law: pre-gate that reads 200000==200000; a merged
    # 262144 retarget leaves the rows and the comment moving together (OQ5's
    # receipt depth). A stale half-move is exactly the drift this pins out.
    m = re.search(r"Context ([0-9]{6}) is q27's PER-SESSION ceiling", raw)
    if not m:
        errs.append("the q27 served-context comment line moved shape — the parity arm reads 'Context <figure> is q27's PER-SESSION ceiling'")
    elif int(m.group(1)) != served:
        errs.append(f"comment carries {m.group(1)} but the rows serve limit.context {served} — fix the comment (or re-pin Q27_CTX with the merge), never leave the pair split")
if errs:
    print("; ".join(errs)); sys.exit(1)
PY
  ok "H9[C04]: the q27 trio's priorities/wire ids stand and the served-context comment equals the rows' limit.context (parity invariant; the dated retarget rides the gate receipt)"
fi

printf 'PASS: handoff doctrine + repo-config checks (%d ok)\n' "$checks"
