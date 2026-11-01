#!/usr/bin/env bash
# coder workspace TZ + the timestamp pass — OQ4 everything-displayed-local,
# instants preserved; OQ5 America/Denver shipped for real
# (2026/2026-10-cf-96-feat-dep-tracking-card-pickup, C09).
#
# Pins chunks/C09.md "## Tests": t1 the TZ line in BOTH coder templates'
# coder_agent env blocks, t2 the single offset-aware formatter behind all
# five stamp sites + the board-context collection stamp + the D25-comment
# restatement, t3 the instants-stay-instants list (gate.sh byte-untouched,
# epoch fields untouched), t4 the stamps-vs-instants rule sentences in the
# boards + conventions prose (+ the collector-command wording sync), t5 the
# reaper comparison-side NO-DIFF proof (parse lines + the 2 h window pinned
# byte-equal, plus a Date.parse offset/Z equivalence property check).
#
# WHY statics here and legs there: the runtime stamp-shape coverage lives in
# the four tests/opencode/pipeline-locks-*.test.ts re-pins (instant-
# preservation equality + TZ-set/TZ-unset shape) — those are C09's dev
# commit per its T5 (same-commit law: a red node suite would poison every
# other chunk's gate, since `node --test tests/opencode/*.test.ts` is in
# the plan-Commands regression line). THIS file therefore stays source-
# static + one dependency-free node property check. Baseline recorded by
# agent-test 2026-11-01: `node --test tests/opencode/*.test.ts` = 233 pass,
# 0 fail (all pipeline-locks suites green); tests/templates/{coder-hardened,
# coder-move}.sh red at base from the missing terraform binary (environment
# precondition, not cf-96); those pre-existing reds are excluded from this
# chunk's gate exactly as cf-90 excluded its warm-location family.
#
# AC trace: t1[C09 AC1] t2[AC3 — formatter + five sites + D25 comment]
# t3[AC4 — instant list pinned UNCHANGED + gate.sh byte-pin] t4[AC4 — prose
# rule sentences] t5[AC2 — comparison-side no-diff + parse equivalence].
#
# Red posture: t1, t2, t4 DESIGNED RED (verified 2026-11-01: no TZ in either
# tf env block; no localIso formatter in the plugins — toISOString is used
# bare at five sites; the old D25 sentence and the un-told rule sentence are
# the reds' twin). t3 and t5 are GREEN-now HOLD pins: they turn red the
# moment dev touches what must stay byte-equal (the no-hand-edit / no-
# comparison-side-diff contracts).
#
# Usage:
#   bash tests/cf96-tz/surface.sh            # t1..t5
#   bash tests/cf96-tz/surface.sh t5         # the reaper-consequence proof
#   CF96_TZ_BASE=<ref> bash tests/cf96-tz/surface.sh t3
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

TF_A="charts/coder/coder-templates/kubernetes/main.tf"
TF_B="charts/coder/coder-templates/kubernetes-hardened/main.tf"
LOCKS=".opencode/plugin/pipeline-locks/index.ts"
CTX=".opencode/plugin/board-context/index.ts"
GATE="scripts/agent-board-coord-gate.sh"
BOARDS_SRC=".rulesync/skills/boards/SKILL.md"
BOARDS_GEN=".opencode/skills/boards/SKILL.md"
CONV_SRC=".rulesync/skills/pipeline-conventions/SKILL.md"
CONV_GEN=".opencode/skills/pipeline-conventions/SKILL.md"
CMD_SRC=".rulesync/commands/wekan-board-context.md"
BASE_REF="${CF96_TZ_BASE:-$(git merge-base main HEAD)}"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-5]$ ]] || fail "unknown check id '$a' (expected t1..t5)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

TMP=$(mktemp -d /tmp/opencode/cf96-tz-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

# --- t1: TZ = America/Denver in both coder_agent env blocks (C09 T1 / AC1) ------------
if want t1; then
  for tf in "$TF_A" "$TF_B"; do
    [ -f "$tf" ] || fail "harness: $tf missing"
    python3 - "$tf" <<'PY' || fail "t1[C09 AC1]: $tf coder_agent env block lacks the pinned TZ line (reason above)"
import re, sys
path = sys.argv[1]
t = open(path).read()
# the coder_agent env block — the OPENCODE_BINARY block (RESEARCH S37);
# brace-matched so a TZ elsewhere in the tf (pod env) cannot satisfy it.
m = re.search(r"env\s*=\s*\{[^{}]*OPENCODE_BINARY[^{}]*\}", t, re.S)
if not m:
    print("t1: could not locate the coder_agent env block containing OPENCODE_BINARY"); sys.exit(1)
block = m.group(0)
if not re.search(r'^\s*TZ\s*=\s*"America/Denver"', block, re.M):
    print("t1: no 'TZ = \"America/Denver\"' inside the coder_agent env block — OQ5 shipped for REAL (no HOLD marker); until the owner reprovisions, $TZ stays unset and emitters keep the UTC fallback (the fallback is t2's duty, not a comment-out of this line)")
    sys.exit(1)
print("ok")
PY
  done
  # line-shape equality between the twins (AC1: hardened matches base shape)
  a=$(grep -E '^\s*TZ\s*=' "$TF_A" || true); b=$(grep -E '^\s*TZ\s*=' "$TF_B" || true)
  [ -n "$a" ] && [ "$a" = "$b" ] \
    || fail "t1[C09 AC1]: the two templates' TZ lines differ ('$a' vs '$b') — hardened twin must match the base template's line shape"
  ok "t1[C09 AC1]: TZ = America/Denver present in both coder_agent env blocks, identical line shape"
fi

# --- t2: one formatter, five sites, D25 restated (C09 T2 / AC3) -------------------------
if want t2; then
  defs=$( { grep -rc 'function localIso' .opencode/plugin --include='*.ts' || true; } | awk -F: '{s+=$2} END {print s+0}')
  [ "$defs" -eq 1 ] \
    || fail "t2[C09 AC3]: $defs definitions of 'function localIso' under .opencode/plugin — the formatter must live ONCE (one helper, five call sites; stamp shape is a contract, two implementations WILL drift — C09 Notes; designed red before C09 dev)"
  # every prior bare-stamp site now routes through it: at the five sites the
  # segment contains localIso(, and pipeline-locks keeps toISOString ONLY
  # inside the helper (its UTC-Z fallback).
  python3 - "$LOCKS" "$CTX" <<'PY' || fail "t2[C09 AC3]: the formatter/site pins failed (reason above)"
import re, sys

locks, ctx = open(sys.argv[1]).read(), open(sys.argv[2]).read()
def seg(src, name):
    m = re.search(rf"(?ms)^export (async )?function {name}\(.*?^\}}", src) or re.search(rf"(?ms)^(async )?function {name}\(.*?^\}}", src)
    return m.group(0) if m else None

for fn, why in [("newLockRecord", "claimedAt/heartbeatAt (lock records)"),
                ("heartbeatSet", "heartbeatAt beats"),
                ("appendEvent", "audit-JSONL at"),
                ("queueTimeoutRow", "timeouts.jsonl row at")]:
    s = seg(locks, fn)
    if s is None:
        print(f"t2: {fn} vanished from the plugin (harness-visible refactor?)"); sys.exit(1)
    if "localIso(" not in s:
        print(f"t2: {fn} does not call localIso() — the {why} stamp must ride the single formatter (OQ4: displayed stamps, workspace-local with offset, UTC-Z fallback)"); sys.exit(1)

# the fallback: toISOString survives ONLY inside the helper definition
hm = re.search(r"(?ms)(export )?function localIso\(.*?^\}", locks)
if hm is None:
    print("t2: the localIso definition is not in pipeline-locks/index.ts — the single formatter must live where the four lock stamp sites are (defs==1 counted a definition elsewhere: five sites cannot all import cleanly if the helper lives outside this file's reach)"); sys.exit(1)
helper = hm.group(0)
outside = re.sub(r"function localIso\(.*?^\}", "", locks, flags=re.S)
if outside.count("toISOString") != 0:
    print(f"t2: {outside.count('toISOString')} toISOString call(s) remain in pipeline-locks outside localIso — the five-site rewrite is incomplete (the fallback belongs in the helper only)"); sys.exit(1)
if "toISOString" not in helper:
    print("t2: the localIso helper lost its UTC-Z fallback ($TZ unresolvable ⇒ toISOString() — today's behavior, fail-safe per OQ4 encoding)"); sys.exit(1)
if not re.search(r"process\.env\.TZ|Intl|timeZone|getTimezoneOffset", helper):
    print("t2: localIso is not offset-aware (no TZ/Intl/offset machinery inside) — offset-bearing ISO-8601 like 2026-11-01T02:00:00-07:00 is the contract"); sys.exit(1)
if not re.search(r"localIso|from ['\"].*pipeline-locks", ctx):
    print("t2: board-context's collectedAt does not reference the single formatter — same rule, one implementation across the plugins (C09 T2)"); sys.exit(1)
if re.search(r"collectedAt: new Date\(\)\.toISOString\(\)", ctx):
    print("t2: board-context still stamps collectedAt with the bare UTC toISOString() — the collection stamp joins the local-with-offset rule"); sys.exit(1)
print("ok")
PY
  grep -qF 'Every timestamp is an ISO-8601 UTC string' "$LOCKS" \
    && fail "t2[C09 AC3]: the D25 comment still pins 'Every timestamp is an ISO-8601 UTC string' — C09 T2 rewrites it to the new contract (offset-bearing ISO-8601, instant-preserving, UTC fallback)"
  python3 - "$LOCKS" <<'PY' || fail "t2[C09 AC3]: the restated D25 comment is missing its contract words (reason above)"
import re, sys
src = open(sys.argv[1]).read()
i = src.find("newLockRecord")
window = src[max(0, i - 1500):i + 500]
if not re.search(r"offset", window, re.I) or not re.search(r"fallback", window, re.I):
    print("t2: near newLockRecord there is no comment stating offset-bearing + UTC fallback as the new timestamp contract"); sys.exit(1)
if not re.search(r"epoch-ms.{0,120}violation", window, re.I | re.S):
    print("t2: the restated comment must KEEP 'epoch-ms in lock files is a contract violation' (instants belong to epoch fields, not stamp fields)"); sys.exit(1)
print("ok")
PY
  ok "t2[C09 AC3]: localIso lives once, all five stamp sites route through it, UTC-Z fallback intact, D25 comment restated"
fi

# --- t3: instants stay instants — the OQ4 encoding boundary (C09 T3 / AC4) --------------
if want t3; then
  git rev-parse --verify "$BASE_REF" >/dev/null 2>&1 || fail "harness: base ref $BASE_REF unresolved (CF96_TZ_BASE=<ref>)"
  git diff --quiet "$BASE_REF" -- "$GATE" \
    || fail "t3[C09 AC2/AC4]: $GATE changed since $BASE_REF — the gate is epoch-only by construction and needs ZERO change (OQ4 ruling; the byte-pin is the proof)"
  grep -qF 'date +%s%3N' "$GATE" \
    || fail "t3[C09 AC4]: the gate's epoch-ms stamp expression vanished — instants are VALUES, not stamps; they are never reformatted"
  grep -qF '$(date +%s%3N)' "$BOARDS_SRC" \
    || fail "t3[C09 AC4]: the boards no-op-marker recipe must keep the epoch-ms inline (`$(date +%s%3N)`) — pipelineNoop.at stays epoch-ms by definition"
  grep -qF 'Date.now()' "$LOCKS" \
    || fail "t3[C09 AC4]: Date.now() pass-throughs must survive the stamp pass (instants)"
  grep -qF 'mtimeMs' "$LOCKS" \
    || fail "t3[C09 AC4]: mtimes stay mtimes — the reaper's disk arm depends on them"
  ok "t3[C09 AC4]: gate.sh byte-untouched vs $BASE_REF; epoch fields + mtime usage pinned unchanged (instants preserved)"
fi

# --- t4: the prose rule sentences — boards, conventions, collector (C09 T3/T4) ----------
if want t4; then
  python3 - "$BOARDS_SRC" "$BOARDS_GEN" <<'PY' || fail "t4[C09 AC4]: the boards stamps-vs-instants rule sentence pin failed (reason above)"
import re, sys
for path in sys.argv[1:]:
    t = open(path).read()
    flat = re.sub(r"\s+", " ", t)
    m = re.search(r"[Dd]isplayed stamps[^.]{0,400}", flat)
    if not m or "$TZ" not in m.group(0) or "offset" not in m.group(0).lower():
        print(f"t4: {path}: no 'displayed stamps follow workspace $TZ with offset' rule sentence (C09 T3 adds it to the boards prose)"); sys.exit(1)
    if not re.search(r"[Ii]nstant[^.]{0,300}never reformat", flat):
        print(f"t4: {path}: the second half of the rule — instant values (epoch-ms fields, mtimes, WeKan stored dates) are NEVER reformatted — is absent"); sys.exit(1)
    for tok in ("updated_at", "collected", "no-op"):
        if tok not in flat:
            print(f"t4: {path}: the stamp-rule sentence should name the {tok} surface (claim/summary comment stamps + STATE.json updated_at + no-op title)"); sys.exit(1)
print("ok")
PY
  python3 - "$CONV_SRC" "$CONV_GEN" <<'PY' || fail "t4[C09 T4]: the pipeline-conventions updated_at rule pin failed (reason above)"
import re, sys
for path in sys.argv[1:]:
    t = open(path).read()
    m = re.search(r"`updated_at`[^.]{0,300}", t)
    if not m or not re.search(r"offset|workspace-local", m.group(0), re.I):
        print(f"t4: {path}: STATE.json updated_at must be declared to follow the stamp rule (workspace-local ISO-8601 WITH offset — OQ4); current sentence: {m.group(0)[:120] if m else 'NONE'}"); sys.exit(1)
print("ok")
PY
  python3 - "$CMD_SRC" <<'PY' || fail "t4[C09 T2]: the collector command's stamp wording did not sync (reason above)"
import re, sys
t = open(sys.argv[1]).read()
if not re.search(r"offset|UTC fallback|Z\b.{0,80}offset|workspace-local", t, re.I):
    print("t4: .rulesync/commands/wekan-board-context.md still emits the plain-UTC collection stamp wording — C09 T2 syncs it to the same rule (an offset stamp IS ISO-8601, so the schema's 'collected <ISO-8601>' sentence stays true)"); sys.exit(1)
print("ok")
PY
  ok "t4[C09 AC4/T2-T4]: boards + conventions carry the stamps-vs-instants rule; collector wording synced"
fi

# --- t5: reaper comparison-side NO-DIFF + parse equivalence (C09 AC2) -------------------
if want t5; then
  while IFS= read -r line; do
    grep -qF "$line" "$LOCKS" \
      || fail "t5[C09 AC2]: comparison-side line not present byte-equal: '$line' — the staleness consumers must be UNTOUCHED (writer-side-only is the whole OQ4 encoding; a diff HERE means dev reached into the wrong side)"
  done <<'LINES'
const stamp = Date.parse(String(rec.heartbeatAt ?? rec.claimedAt ?? ""));
const hbMs = rec ? Date.parse(String(rec.heartbeatAt ?? "")) : Number.NaN;
const lastMs = Math.max(Number.isFinite(hbMs) ? hbMs : Number.NEGATIVE_INFINITY, mtimeMs);
const DEFAULT_STALE_MS = 7200000;
const GUARD_STALE_MS = 300000;
LINES
  node - <<'EOF' || fail "t5[C09 AC2]: the Date.parse offset↔Z equivalence property failed (reason above)"
const a = Date.parse("2026-11-01T02:00:00-07:00");
const z = Date.parse("2026-11-01T09:00:00Z");
if (!Number.isFinite(a) || a !== z) {
  console.error(`FAIL-REASON: t5: ECMAScript Date.parse must read an offset-bearing stamp as the SAME instant as its UTC twin (${a} vs ${z}) — the 2 h window proof depends on it`);
  process.exit(1);
}
const now = Date.parse("2026-11-01T10:00:00Z");
if (now - a >= 7200000 || now - z >= 7200000) {
  console.error("FAIL-REASON: t5: the mixed-era coexistence check failed — a fresh offset stamp must age exactly like its Z twin inside the 2 h window");
  process.exit(1);
}
console.log("ok: offset stamps parse to the same instants as their UTC twins; the 2h window ages identically");
EOF
  ok "t5[C09 AC2]: reaper/pipeline_status comparison lines byte-equal, 2h constants intact, offset↔Z parse equivalence proven"
fi

printf 'PASS: cf-96 TZ/timestamp-pass checks (%d ok)\n' "$checks"
