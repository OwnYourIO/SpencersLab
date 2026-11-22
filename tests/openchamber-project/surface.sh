#!/usr/bin/env bash
# cf-126 C06 round-2 (D37 route b′) — validation for the committed
# .openchamber/project.json magic-prompt override + its canonical fixture.
#
# Home call: a NEW tests/openchamber-project/ suite (the amendment mandates
# the fixture live at tests/openchamber-project/default-summary-instructions.txt
# — the validation homes beside its fixture; the narratives suite keeps its
# 25-file roster purity).
#
# Law (D37 + the amendment): the file carries EXACTLY version(=1) +
# magicPrompts with the ONE dotted key "session.summary.instructions"; the
# value is the FULL builtin default (verbatim — whole-replacement resolution
# makes a short override silently LOSE the "Do NOT compact or mutate" safety
# clause) + a blank line + the sanctioned appended pointer paragraph (the
# /summary-leg law sentence; the compaction's obey-trigger stays the shipped
# D9 hook). One wrong entry voids the whole project scope (DOCUMENTATION
# invariant) — every needle below carries a biting synthetic fixture.
#
# AC trace: P1[AA1 exists+tracked+parses] P2[AA1 key shape incl. the dotted
# single-key] P3[AA3 safety substring] P4[AA1 pointer suffix verbatim]
# P5[AA1 {{topic_block}} literal] P6[AA1/AA2 fixture fidelity: value ==
# fixture + blank line + pointer] P7[AA4 opencode.jsonc stays knobs-only]
# P8[AA2 five fabricated-drift fixtures + clean satisfiability fixture —
# runnable standalone NOW as the bite evidence].
#
# Red posture: P1–P7 designed-RED until C06 dev lands the file + the fixture
# (dev creates BOTH; the clone byte-compare fidelity leg is dev's
# commands_run duty per the amendment). P8 is GREEN now: it drives the SAME
# shipped checkers over synthetic clean/dirty fixtures, proving every real
# needle non-vacuous before the surfaces exist.
#
# Usage:
#   bash tests/openchamber-project/surface.sh          # P1..P8
#   bash tests/openchamber-project/surface.sh P8       # controls only
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

PJ=".openchamber/project.json"
FIX="tests/openchamber-project/default-summary-instructions.txt"
CFG=".opencode/opencode.jsonc"
POINTER='When this request carries hook-injected compaction instructions, follow them as the law: produce exactly the pointer summary they specify. The non-destruction rule above always stands.'

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

TMP=$(mktemp -d /tmp/opencode/openchamber-project-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7 8; do WANT["p$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^p[1-8]$ ]] || fail "unknown check id '$a' (expected P1..P8)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

printf '%s\n' "$POINTER" > "$TMP/pointer.txt"

# The shipped checkers — the live arms and the P8 synthetic fixtures run the
# SAME code, so a control that reddens proves the live needle bites.
cat > "$TMP/aa.py" <<'PY'
import json, sys
mode = sys.argv[1]
KEY = "session.summary.instructions"
SAFETY = "Do NOT compact or mutate"
TOPIC = "{{topic_block}}"
def die(msg, code=1):
    print(msg); sys.exit(code)
if mode == "keys":                     # P1/P2: parse + shape; writes the value out
    try:
        obj = json.load(open(sys.argv[2], encoding="utf-8"))
    except Exception as e:
        die(f"malformed-JSON: {e}", 2)
    top = sorted(obj.keys())
    if top != ["magicPrompts", "version"]:
        die(f"unknown-key-set: top-level keys are {top}, want exactly ['magicPrompts','version'] (AA1 — one wrong entry voids the whole project scope)")
    if obj["version"] != 1:
        die(f"version is {obj['version']!r}, want 1")
    mp = obj.get("magicPrompts")
    if not isinstance(mp, dict) or sorted(mp.keys()) != [KEY]:
        die(f"magicPrompts must carry EXACTLY the one dotted key {KEY!r}, got {sorted(mp.keys()) if isinstance(mp, dict) else type(mp).__name__}")
    open(sys.argv[3], "w", encoding="utf-8").write(mp[KEY])
    print("ok")
    sys.exit(0)
if mode == "check":                    # P3–P6: value vs fixture + pointer law
    value = open(sys.argv[2], encoding="utf-8").read()
    try:
        fixture = open(sys.argv[3], encoding="utf-8").read()
    except OSError:
        die("missing-fixture: canonical default fixture absent (dev creates tests/openchamber-project/default-summary-instructions.txt)")
    pointer = open(sys.argv[4], encoding="utf-8").read().rstrip("\n")
    errs = []
    if SAFETY not in value:
        errs.append("dropped-safety: the value lost the builtin 'Do NOT compact or mutate' clause — whole-replacement resolution means a short override SILENTLY DELETES it (D37)")
    if TOPIC not in value:
        errs.append(f"missing-token: {{{{topic_block}}}} was stripped — placeholder removal silently breaks topic-focus rendering")
    if not value.rstrip("\n").endswith(pointer):
        errs.append("missing-pointer: the sanctioned appended paragraph is not the value's tail — the /summary-leg law sentence (D37 amendment, verbatim)")
    want = fixture.rstrip("\n") + "\n\n" + pointer
    if value.rstrip("\n") != want.rstrip("\n"):
        errs.append("template-drift: value != fixture-default + blank line + pointer — the default portion must equal the committed fixture byte-true (a reworded bullet silently forks the builtin)")
    if SAFETY not in fixture or TOPIC not in fixture:
        errs.append("fixture-hollow: the canonical fixture itself lost the safety clause or the topic token — the anchor must carry the full builtin")
    if errs:
        die("; ".join(errs))
    print("ok")
    sys.exit(0)
die(f"unknown mode {mode}", 3)
PY

# --- P1+P2: the file exists, is TRACKED, parses, and carries the exact shape ----
if want p1 || want p2; then
  [ -f "$PJ" ] || fail "P1[AA1]: $PJ missing — designed red until C06 dev creates the committed override (D37 route b′: the repo NOW owns this surface; the paste route is the recorded rejected alternative)"
  git ls-files --error-unmatch "$PJ" >/dev/null 2>&1 \
    || fail "P1[AA1]: $PJ exists but is UNTRACKED — the artifact is repo-committed by ruling; a working-tree-only file is not the landing"
  python3 "$TMP/aa.py" keys "$PJ" "$TMP/value.txt" \
    || fail "P2[AA1]: $PJ fails the key-shape law (reason above — version=1 + magicPrompts carrying ONLY the dotted session.summary.instructions)"
  ok "P1+P2[AA1]: the override file is tracked, parses, and carries exactly version=1 + the single dotted magic-prompt key"
fi

# --- P3–P6: the value law (safety, pointer verbatim, topic token, fidelity) -----
if want p3 || want p4 || want p5 || want p6; then
  [ -f "$TMP/value.txt" ] || fail "harness: value not extracted (P1/P2 run first — the keys order in the file list is the run order)"
  python3 "$TMP/aa.py" check "$TMP/value.txt" "$FIX" "$TMP/pointer.txt" \
    || fail "P3–P6[AA1/AA2/AA3]: the value violates the composition law (reason above)"
  ok "P3–P6[AA1-AA3]: safety clause present, pointer paragraph verbatim as the tail, {{topic_block}} intact, default portion byte-equal to the committed fixture"
fi

# --- P7: opencode.jsonc stays knobs-only (AA4) -----------------------------------
if want p7; then
  python3 - "$CFG" <<'PY' || fail "P7[AA4]: the repo config crossed into instruction TEXT — knobs only (auto/background/buffer/keep); the TEXT is never config-settable (D37 non-scope)"
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
comp = cfg.get("compaction", {})
allowed = {"auto", "background", "buffer", "keep"}
extra = sorted(set(comp) - allowed)
if extra:
    print(f"compaction carries non-knob keys {extra} — the knobs set is exactly auto/background/buffer/keep (D37: numbers are config-settable, the TEXT never is)"); sys.exit(1)
def leaves(o):
    if isinstance(o, dict):
        for v in o.values(): yield from leaves(v)
    else:
        yield o
long_text = [x for x in leaves(comp) if isinstance(x, str) and len(x) > 40]
if long_text:
    print(f"compaction knobs carry instruction-sized strings: {long_text}"); sys.exit(1)
print("ok")
PY
  ok "P7[AA4]: opencode.jsonc compaction stays knobs-only (no instruction text, no unknown keys)"
fi

# --- P8: fabricated-drift fixtures + clean satisfiability (green NOW) -------------
# The five amendment drifts, each through the SHIPPED checkers, each asserted to
# redden for its NAMED reason; plus the clean synthetic that must read green —
# the pair proves every live needle satisfiable and non-vacuous before the real
# surfaces exist.
if want p8; then
  DEF=$'Produce a non-destructive summary. Do NOT compact or mutate session history.\n\nBullets\n- keep {{topic_block}} rendering\nEnd.'
  printf '%s\n' "$DEF" > "$TMP/fix-clean.txt"
  CLEANVAL=$(printf '%s\n\n%s' "$DEF" "$(cat "$TMP/pointer.txt")")
  printf '%s' "$CLEANVAL" > "$TMP/val-clean.txt"
  if ! python3 "$TMP/aa.py" check "$TMP/val-clean.txt" "$TMP/fix-clean.txt" "$TMP/pointer.txt" >/dev/null 2>&1; then
    fail "P8 control: the CLEAN synthetic fixture failed the checker — the live arms would be unsatisfiable (harness fault)"
  fi
  # 1 dropped-safety
  NOSAFE=$(printf '%s\n\n%s' "${DEF/Do NOT compact or mutate session history./Summarize session history.}" "$(cat "$TMP/pointer.txt")")
  printf '%s' "$NOSAFE" > "$TMP/val-nosafe.txt"; printf '%s\n' "${DEF/Do NOT compact or mutate session history./Summarize session history.}" > "$TMP/fix-nosafe.txt"
  out=$(python3 "$TMP/aa.py" check "$TMP/val-nosafe.txt" "$TMP/fix-nosafe.txt" "$TMP/pointer.txt" 2>&1) \
    && fail "P8 control: the dropped-safety fixture passed — the safety needle is vacuous"
  case "$out" in *dropped-safety*) ;; *) fail "P8 control: dropped-safety reddened for the wrong reason ($out)";; esac
  # 2 unknown-key
  printf '%s' '{"version":1,"magicPrompts":{"session.summary.instructions":"x"},"plansDir":"/tmp"}' > "$TMP/pj-unknown.json"
  out=$(python3 "$TMP/aa.py" keys "$TMP/pj-unknown.json" "$TMP/v0.txt" 2>&1) \
    && fail "P8 control: the unknown-key fixture passed — the key-shape needle is vacuous"
  case "$out" in *unknown-key-set*) ;; *) fail "P8 control: unknown-key reddened for the wrong reason ($out)";; esac
  # 3 malformed-JSON
  printf '%s' '{"version": 1,' > "$TMP/pj-broken.json"
  out=$(python3 "$TMP/aa.py" keys "$TMP/pj-broken.json" "$TMP/v1.txt" 2>&1) \
    && fail "P8 control: the malformed-JSON fixture parsed — the parse needle is vacuous"
  case "$out" in *malformed-JSON*) ;; *) fail "P8 control: malformed-JSON reddened for the wrong reason ($out)";; esac
  # 4 missing-pointer
  printf '%s\n' "$DEF" > "$TMP/val-nopointer.txt"
  out=$(python3 "$TMP/aa.py" check "$TMP/val-nopointer.txt" "$TMP/fix-clean.txt" "$TMP/pointer.txt" 2>&1) \
    && fail "P8 control: the stripped-pointer fixture passed — the pointer needle is vacuous"
  case "$out" in *missing-pointer*) ;; *) fail "P8 control: missing-pointer reddened for the wrong reason ($out)";; esac
  # 5 template-drift (one reworded default bullet vs the fixture)
  DRIFTDEF=${DEF/Bullets/Bullet points}
  printf '%s\n\n%s' "$DRIFTDEF" "$(cat "$TMP/pointer.txt")" > "$TMP/val-drift.txt"
  out=$(python3 "$TMP/aa.py" check "$TMP/val-drift.txt" "$TMP/fix-clean.txt" "$TMP/pointer.txt" 2>&1) \
    && fail "P8 control: the template-drift fixture passed the fidelity check — the fixture anchor is decorative"
  case "$out" in *template-drift*) ;; *) fail "P8 control: template-drift reddened for the wrong reason ($out)";; esac
  ok "P8[AA2]: clean synthetic reads green and ALL FIVE drift fixtures redden for their named reasons (dropped-safety, unknown-key, malformed-JSON, missing-pointer, template-drift) through the shipped checkers"
fi

printf 'PASS: openchamber project-override checks (%d ok)\n' "$checks"
