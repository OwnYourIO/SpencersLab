#!/usr/bin/env bash
# Board-provisioning engine + skill + command contract
# (2026/2026-10-cf-90-feat-board-coord-improvements, C01).
#
# Pins chunks/C01.md "## Tests" + AC1-AC8: the offline stdlib-only engine
# (snapshot in, ordered action list out — idempotent by diffing the built-in
# spec against the snapshot), the hand-written skills/wekan-board-provision
# procedure text, the generated /wekan-board-provision command, and the Inbox
# contract (ensured in Backlog, never mirrored into Planning, never Bucket-
# labeled or ruled). AC trace: t1[determinism] t2[AC1 exact action set +
# ids-resolve-at-apply] t3[AC2 idempotence] t4[AC4 offline/credential-free]
# t5[AC5 skill text pins] t6[command trio generated+parses, AGENTS discover-
# ability] t7[swimlaneName:Planning cross-fire guard — RESEARCH F1]
# t8[AC3 Inbox contract both variants] t9[cf-106 C02 AC1/AC3 — the hand-managed
# provision skill's three Model(s) default-check citations move to the current
# vocabulary generation (Qwen Dense), the retired label stays out of this
# current-state surface, and the Model(s) four-item closure holds — with a
# Dense-free-copy and a fifth-item-copy control].
#
# ENGINE JSON CONTRACT (dev implements to this — fixed here because the
# assertions below are the interface): stdout is a JSON array of objects,
#   {"action":"create_list","title":<str>,"swimlane":<swimlane-name>}
#   {"action":"create_label","name":<str>,"color":<str>}
#   {"action":"create_rule","title":"Bucket: <list> — <activityType>",
#    "trigger":{"activityType":<createCard|moveCard>,"listName":<str>,
#               "swimlaneName":"Planning"},"label":"Bucket: <list>"}
# in that shape, in any order (t2 compares order-normalized; t1 pins that a
# given snapshot always renders byte-identical). --format text renders one
# human-readable line per action; content shape is dev's, determinism is not.
#
# Fixtures are data (t2 asserts titles/names only — the engine keys on titles;
# the live snapshot embeds the planning-prefetch In-Process ids and synthetic
# others). Dev MUST re-probe and regenerate ai-dev-live-2026-10-31.json for
# realism (C01 Files-in-scope note); if the regenerated live state drifts from
# AC1's recorded action set (2 create_list / 8 bucket labels / 16 rules /
# 2 provider labels + 1 Research: Parallel ensure since the cf-96 C08 spec grew), the EXPECTED SET below re-pins via the test owner —
# never by relaxing a count here.
#
# Red posture: everything here is designed-red until C01 dev lands
# scripts/provision-board.py + the skill + the command; every red names the
# missing surface, never a harness fault. Self-contained: the cf-90 C01 gate
# is `bash tests/wekan-board-provision/surface.sh` (all ids); no check in this
# file invokes any suite carrying the known pre-existing reds (gate t17 /
# coord-inwork i4 / session-origin s4 / kickoff-branch m4 / wekan-mcp
# create-list t2) — those predate cf-90 (warm-location permissions drift and
# the merged cf-68 base, tracked outside this ticket) and stay out of cf-90
# gates per this ticket's DECISIONS/FRICTION baseline note.
#
# No live board is touched (C01 AC8): engine reads fixtures only; no network,
# no credentials, anywhere in this suite either.
#
# Usage:
#   bash tests/wekan-board-provision/surface.sh           # t1..t9
#   bash tests/wekan-board-provision/surface.sh t2 t8     # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

ENGINE="scripts/provision-board.py"
SKILL="skills/wekan-board-provision/SKILL.md"
CMD_SRC=".rulesync/commands/wekan-board-provision.md"
CMD_GEN=".opencode/commands/wekan-board-provision.md"
RULES_SRC=".rulesync/rules/overview.md"
FXDIR="tests/wekan-board-provision/fixtures"
LIVE_FX="$FXDIR/ai-dev-live-2026-10-31.json"
FULL_FX="$FXDIR/ai-dev-full-provisioned.json"
NOINBOX_FX="$FXDIR/ai-dev-no-inbox.json"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

TMP=$(mktemp -d /tmp/opencode/board-provision-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7 8 9; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-9]$ ]] || fail "unknown check id '$a' (expected t1..t9)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# Fixtures are this suite's own data: validate them before blaming dev.
for fx in "$LIVE_FX" "$FULL_FX" "$NOINBOX_FX"; do
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$fx" \
    || fail "harness: $fx is not valid JSON — the test data itself is broken (report, do not blame dev)"
done

cat >"$TMP/win.py" <<'PY'
# Co-location window (sibling-suite convention): needles must read as ONE
# passage of the skill text; --ci folds case so prose pins survive register.
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

engine_guard() {
  [ -f "$ENGINE" ] \
    || fail "$1[C01]: $ENGINE does not exist yet — the offline engine is C01's first task (designed red before C01 dev, not a harness fault)"
}

run_engine() { # run_engine <out-name> <fixture> <extra args...>
  local name="$1" fx="$2"; shift 2
  python3 "$ENGINE" --fixture "$fx" "$@" >"$TMP/$name.json" 2>"$TMP/$name.err"
}

# --- t1: determinism — same fixture, byte-identical output --------------------
if want t1; then
  engine_guard "t1"
  run_engine a "$LIVE_FX" --format json || { cat "$TMP/a.err" >&2; fail "t1[C01 AC-1'']: engine exited nonzero on the live fixture"; }
  run_engine b "$LIVE_FX" --format json || fail "t1: engine exited nonzero on the second live-fixture run"
  cmp -s "$TMP/a.json" "$TMP/b.json" \
    || fail "t1[C01 determinism]: two --format json runs on the SAME fixture differ — the action list must be deterministic (the zero-action verify loop depends on stable diffs)"
  run_engine ta "$LIVE_FX" --format text || fail "t1: engine exited nonzero in text format"
  run_engine tb "$LIVE_FX" --format text || fail "t1: second text run nonzero"
  cmp -s "$TMP/ta.json" "$TMP/tb.json" \
    || fail "t1[C01 determinism]: two --format text runs on the SAME fixture are not byte-identical"
  ok "t1: engine is deterministic — byte-identical repeats in both json and text formats"
fi

# --- t2: the live fixture emits EXACTLY the AC1 action set --------------------
if want t2; then
  engine_guard "t2"
  # --dry-run is a documented no-op shape: the deterministic engine IS the dry
  # run (plan Commands + skill step 2), so both invocations must agree.
  run_engine plain "$LIVE_FX" --format json || { cat "$TMP/plain.err" >&2; fail "t2: engine nonzero"; }
  run_engine dry  "$LIVE_FX" --dry-run --format json || { cat "$TMP/dry.err" >&2; fail "t2[plan Commands]: `python3 scripts/provision-board.py --fixture <live> --dry-run` shape nonzero — the exact invocation the plan's Commands line runs"; }
  cmp -s "$TMP/plain.json" "$TMP/dry.json" \
    || fail "t2[C01 skill step 2]: --dry-run output differs from the plain run — the engine always emits the plan; the flag must not change it"
  if ! python3 - "$TMP/dry.json" "$LIVE_FX" <<'PY'
import json, sys
got = json.load(open(sys.argv[1]))
assert isinstance(got, list), f"engine JSON must be a top-level array of actions, got {type(got).__name__}"
fx = json.load(open(sys.argv[2]))
planning_after = ["Context", "CICD", "Home Assistant", "Dev Env", "Research", "Features", "Outside Process", "Wekan"]
exp = []
for t in ("Outside Process", "Wekan"):
    exp.append({"action": "create_list", "title": t, "swimlane": "Planning"})
for t in planning_after:
    exp.append({"action": "create_label", "name": f"Bucket: {t}", "color": "darkgreen"})
for t in planning_after:
    for at in ("createCard", "moveCard"):
        exp.append({"action": "create_rule", "title": f"Bucket: {t} — {at}",
                    "trigger": {"activityType": at, "listName": t, "swimlaneName": "Planning"},
                    "label": f"Bucket: {t}"})
exp.append({"action": "create_label", "name": "Provider: API", "color": None})
exp.append({"action": "create_label", "name": "Provider: Local", "color": None})
exp.append({"action": "create_label", "name": "Research: Parallel", "color": None})
key = lambda a: json.dumps(a, sort_keys=True)
norm = sorted(map(key, got))
# provider-label colors are NOT pinned (the spec fixes only the bucket color):
# mask them, and reject empty/non-string colors while doing so.
for want_mask in ("Provider: API", "Provider: Local", "Research: Parallel"):
    for i, s in enumerate(norm):
        a = json.loads(s)
        if a.get("action") == "create_label" and a.get("name") == want_mask:
            c = a.get("color")
            assert isinstance(c, str) and c, f"{want_mask}: create_label needs a non-empty string color, got {c!r}"
            a["color"] = None
            norm[i] = key(a)
norm.sort()  # masking rewrites the sort key; the pre-mask order is stale
expn = sorted(map(key, exp))
if norm != expn:
    extra = [json.loads(s) for s in norm if s not in expn]
    missing = [a for a in (json.loads(s) for s in expn) if key(a) not in norm]
    print(f"action-set drift on the live fixture. got {len(got)} actions, want {len(exp)}.")
    print(f"unexpected: {json.dumps(extra, ensure_ascii=False)}")
    print(f"missing:    {json.dumps(missing, ensure_ascii=False)}")
    sys.exit(1)
lists = [a for a in got if a["action"] == "create_list"]
labels = [a for a in got if a["action"] == "create_label"]
rules = [a for a in got if a["action"] == "create_rule"]
assert (len(lists), len(labels), len(rules)) == (2, 11, 16), \
    f"AC1 shape: want 2 create_list + 8 bucket + 2 provider + 1 Research: Parallel create_label + 16 create_rule, got {len(lists)}+{len(labels)}+{len(rules)}"
for a in labels:
    assert a["name"].startswith(("Provider:", "Research: Parallel")) or a["color"] == "darkgreen", \
        f"bucket label {a['name']!r} carries color {a['color']!r}, want the Bucket Color swatch 'darkgreen'"
print("exact")
PY
  then fail "t2[C01 AC1]: live-fixture action set differs from the AC1 contract above (got 29 actions: 2 create_list + 8 Bucket + 2 Provider labels + 1 Research: Parallel ensure + 16 rules)"; fi
  ok "t2[C01 AC1]: live fixture -> EXACTLY 2 create_list(Planning) + 8 Bucket(darkgreen) + 2 Provider labels + 1 Research: Parallel ensure + 16 rule records, nothing else"
fi

# --- t2b control (runs with t2): titles-only — ids are for realism alone -------
if want t2; then
  python3 - "$LIVE_FX" "$TMP/scrambled.json" <<'PY'
import json, sys
fx = json.load(open(sys.argv[1]))
n = 0
def fake(_):
    global n
    n += 1
    return f"scrambledId{n:04d}"
fx["board"]["id"] = fake(None)
mapping = {}
for name, sid in list(fx["swimlanes"].items()):
    new = fake(sid)
    mapping[sid] = new
    fx["swimlanes"][name] = new
fx["lists"] = {mapping[k]: v for k, v in fx["lists"].items()}
for r in fx["rules"]:
    for k in list(r):
        pass  # normalized rule records are title/trigger/action only — no ids
json.dump(fx, open(sys.argv[2], "w"), ensure_ascii=False, indent=2)
PY
  run_engine scr "$TMP/scrambled.json" --format json \
    || { cat "$TMP/scr.err" >&2; fail "t2[ids-at-apply]: engine nonzero on the id-scrambled fixture — the engine must read the snapshot without depending on ids"; }
  run_engine ref "$LIVE_FX" --format json || fail "t2[ids-at-apply]: reference run nonzero"
  cmp -s "$TMP/scr.json" "$TMP/ref.json" \
    || fail "t2[C01 Tests note]: swapping every swimlane/board id changed the emitted plan — the engine keys on TITLES and names; ids resolve at apply time (test's words, C01 '## Tests')"
  ok "t2[ids-at-apply]: plan is id-independent — scrambling snapshot ids changes nothing"
fi

# --- t3: fully-provisioned fixture -> ZERO actions (AC2) -----------------------
if want t3; then
  engine_guard "t3"
  run_engine full "$FULL_FX" --format json || { cat "$TMP/full.err" >&2; fail "t3[C01 AC2]: engine nonzero on the full-provisioned fixture"; }
  if ! python3 - "$TMP/full.json" <<'PY'
import json, sys
got = json.load(open(sys.argv[1]))
if got:
    print(json.dumps(got, ensure_ascii=False, indent=1))
    sys.exit(1)
PY
  then fail "t3[C01 AC2]: the fully-provisioned fixture produced actions above — the update path must be idempotent (read-then-create only)"; fi
  run_engine fulltxt "$FULL_FX" --dry-run || fail "t3[C01 AC2]: plan-Commands dry-run shape nonzero on the full fixture"
  ok "t3[C01 AC2]: full-provisioned fixture -> zero actions (idempotent update path)"
fi

# --- t4: offline engine — no network imports, no credential surface (AC4) -----
if want t4; then
  engine_guard "t4"
  if ! python3 - "$ENGINE" <<'PY'
import ast, re, sys
path = sys.argv[1]
src = open(path).read()
tree = ast.parse(src)
mods = set()
for n in ast.walk(tree):
    if isinstance(n, ast.Import):
        mods.update(a.name.split(".")[0] for a in n.names)
    elif isinstance(n, ast.ImportFrom) and n.module:
        mods.add(n.module.split(".")[0])
banned = {"socket", "ssl", "urllib", "http", "httpx", "requests", "urllib3",
          "aiohttp", "ftplib", "smtplib", "telnetlib", "websocket"}
hit = sorted(mods & banned)
if hit:
    print(f"network-capable imports: {hit} — the engine diffs a snapshot offline; applying is the skill's job (C01 AC4)")
    sys.exit(1)
envs = []
for n in ast.walk(tree):
    if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) \
       and n.value.id == "os" and n.attr in ("environ", "getenv", "env"):
        envs.append(f"os.{n.attr} at line {n.lineno}")
    if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) \
       and isinstance(n.func.value, ast.Name) and n.func.value.id == "os" \
       and n.func.attr == "getenv":
        envs.append(f"os.getenv() at line {n.lineno}")
if envs:
    print(f"credential env reads present: {envs} — the engine is credential-free (AC4)")
    sys.exit(1)
cred = re.compile(r"^--?[a-z-]*(token|password|secret|credential|api.?key|auth)", re.I)
opts = [c for c in ast.walk(tree) if isinstance(c, ast.Constant)
        if isinstance(c.value, str) and cred.match(c.value)]
if opts:
    print(f"credential-shaped CLI arguments: {[o.value for o in opts]} — apply is never the engine's (AC4)")
    sys.exit(1)
print("offline")
PY
  then fail "t4[C01 AC4]: the engine is not credential-free/offline — reasons above"; fi
  ok "t4[C01 AC4]: stdlib offline engine — no network imports, no env credential reads, no credential arguments"
fi

# --- t5: skill text pins (AC5) --------------------------------------------------
if want t5; then
  [ -f "$SKILL" ] \
    || fail "t5[C01]: $SKILL does not exist yet — the operational procedure is C01's second task (designed red before C01 dev)"
  if ! python3 - "$SKILL" <<'PY'
import re, sys, yaml
m = re.match(r"^---\n(.*?)\n---\n", open(sys.argv[1]).read(), re.S)
assert m, "skill has no YAML frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
assert fm.get("name") == "wekan-board-provision", f"name is {fm.get('name')!r}"
assert (fm.get("description") or "").strip(), "description empty"
PY
  then fail "t5[C01]: the skill frontmatter is not a parseable wekan-board-provision contract (reason above)"; fi
  grep -qiE 'dry.?run' "$SKILL" \
    || fail "t5[C01 AC5]: the skill never names the dry run — the printed action plan + human confirmation comes before any apply (dry-run-first)"
  python3 "$TMP/win.py" --ci "$SKILL" 900 'action plan' 'confirm' \
    || fail "t5[C01 AC5]: dry-run-first is not stated as: engine output IS the action plan, printed and human-confirmed before apply"
  python3 "$TMP/win.py" --ci "$SKILL" 600 'never delete' 'backlog' \
    || fail "t5[C01 AC5]: the additive-only invariant is missing — a Planning list absent from Backlog is NEVER deleted"
  python3 "$TMP/win.py" --ci "$SKILL" 700 'case-insensitiv' 'rename' \
    || fail "t5[C01 AC5]: case-insensitive title matching with never-rename is not stated (the Farm 'Outside Proccess' typo must survive untouched)"
  python3 "$TMP/win.py" --ci "$SKILL" 900 'probe' 'catalog' \
    || fail "t5[C01 AC5]: the skill omits the tool-probe-before-apply step (the deployed dev-boards lacks create_list/create_label — FRICTION 2026-10-31)"
  python3 "$TMP/win.py" --ci "$SKILL" 700 'create_rule' 'dev-boards' \
    || fail "t5[C01]: the skill does not route create_rule through dev-boards (present in the deployed surface)"
  grep -qE 'POST /api/boards/[^ ]*lists' "$SKILL" \
    || fail "t5[C01 AC5]: the raw-REST list-creation fallback recipe (POST /api/boards/:id/lists) is absent — the fallback is load-bearing, not theoretical"
  grep -qE 'POST /api/boards/[^ ]*labels' "$SKILL" \
    || fail "t5[C01 AC5]: the raw-REST label-creation fallback recipe (POST /api/boards/:id/labels) is absent"
  grep -qF 'WEKAN_TOKEN' "$SKILL" && grep -qF 'WEKAN_BASE_URL' "$SKILL" \
    || fail "t5[C01 AC5]: the REST fallback does not point at the wekan-api skill's human-shell credential convention (WEKAN_BASE_URL + WEKAN_TOKEN)"
  python3 "$TMP/win.py" --ci "$SKILL" 700 're-run' 'zero' \
    || fail "t5[C01 AC5]: the verify step is missing — re-collect the snapshot and re-run the engine expecting ZERO actions"
  python3 "$TMP/win.py" --ci "$SKILL" 1600 'inbox' 'never' 'planning' \
    || fail "t5[C01 AC3/AC5]: the skill does not pin the Inbox contract — ensured in Backlog, NEVER copied into Planning"
  python3 "$TMP/win.py" --ci "$SKILL" 1600 'inbox' 'bucket' \
    || fail "t5[C01 AC3/AC5]: the skill does not state that Inbox never receives a Bucket: label or rule pair"
  ok "t5[C01 AC5]: skill text pins dry-run-first, additive-only, case-insensitive/never-rename, tool-probe, REST fallback + credential convention, zero-action verify, Inbox contract"
fi

# --- t6: the command trio lands (generated + parses + discoverable) ------------
if want t6; then
  [ -f "$CMD_SRC" ] || fail "t6[C01]: $CMD_SRC missing — the slash command source is a C01 task"
  [ -f "$CMD_GEN" ] \
    || fail "t6[C01 AC6]: $CMD_GEN missing — sources and generated mirrors land together (rulesync generate); a source without its mirror is not shipped"
  if ! python3 - "$CMD_GEN" <<'PY'
import re, sys, yaml
m = re.match(r"^---\n(.*?)\n---\n", open(sys.argv[1]).read(), re.S)
assert m, "generated command has no YAML frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
assert (fm.get("description") or "").strip(), "generated command frontmatter lacks a non-empty description"
assert "agent" not in fm or str(fm.get("agent") or "default") in ("", "default"), \
    f"the command names agent {fm.get('agent')!r} — C01 Tasks pin the DEFAULT agent (no agent: frontmatter)"
PY
  then fail "t6[C01]: the generated command does not parse to the default-agent contract (reason above)"; fi
  grep -qF '/wekan-board-provision' "$RULES_SRC" \
    || fail "t6[C01]: $RULES_SRC never names /wekan-board-provision — the commands-surface line makes the command discoverable; AGENTS.md regenerates from it"
  grep -qF '/wekan-board-provision' AGENTS.md \
    || fail "t6[C01 AC6]: AGENTS.md does not carry the command name — regenerate from the rules source (never hand-edit the mirror)"
  ok "t6[C01]: /wekan-board-provision source + generated command exist, parse (description present, default agent), and the rules source + AGENTS.md name it"
fi

# --- t7: every emitted rule carries swimlaneName: Planning (cross-fire guard) --
if want t7; then
  engine_guard "t7"
  run_engine t7 "$LIVE_FX" --format json || fail "t7: engine nonzero"
  if ! python3 - "$TMP/t7.json" <<'PY'
import json, sys
got = json.load(open(sys.argv[1]))
rules = [a for a in got if a.get("action") == "create_rule"]
assert rules, "no create_rule actions emitted — the AC1 set expects 16; run t2 for the set diff"
for a in rules:
    tr = a.get("trigger") or {}
    if tr.get("swimlaneName") != "Planning":
        print(f"{a.get('title')}: trigger swimlaneName is {tr.get('swimlaneName')!r} — same-named lists in other swimlanes would cross-fire (RESEARCH F1)")
        sys.exit(1)
    if a.get("label") != f"Bucket: {tr.get('listName')}":
        print(f"{a.get('title')}: rule action label {a.get('label')!r} does not match its listName — a mispaired Bucket rule mislabels cards")
        sys.exit(1)
print(len(rules))
PY
  then fail "t7[C01 AC1/RESEARCH F1]: emitted rule records fail the swimlaneName/listName guards above"; fi
  ok "t7: every emitted rule carries the swimlaneName: Planning matcher and its own Bucket: <list> label"
fi

# --- t8: Inbox contract, both variants (AC3) -----------------------------------
if want t8; then
  engine_guard "t8"
  run_engine i1 "$LIVE_FX" --format json || fail "t8: engine nonzero on the live fixture"
  if ! python3 - "$TMP/i1.json" <<'PY'
import json, sys
got = json.load(open(sys.argv[1]))
hits = [a for a in got if "inbox" in json.dumps(a, sort_keys=True).lower()]
if hits:
    print(f"with Inbox PRESENT in Backlog the engine still acts on it: {json.dumps(hits, ensure_ascii=False)}")
    sys.exit(1)
PY
  then fail "t8[C01 AC3]: Inbox-present variant must emit NO action for Inbox (no mirror, no Bucket label, no rule pair)"; fi
  run_engine i0 "$NOINBOX_FX" --format json || fail "t8: engine nonzero on the no-inbox variant"
  if ! python3 - "$TMP/i0.json" "$TMP/i1.json" <<'PY'
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
key = lambda x: json.dumps(x, sort_keys=True)
delta = sorted(set(map(key, a)) - set(map(key, b)))
want = json.dumps({"action": "create_list", "title": "Inbox", "swimlane": "Backlog"}, sort_keys=True)
if delta != [want]:
    print(f"no-inbox variant must differ from the live plan by EXACTLY create_list(Inbox, Backlog); got delta {delta}")
    sys.exit(1)
bad = [x for x in a if "inbox" in key(x).lower() and key(x) != want]
if bad:
    print(f"Inbox appears in non-ensure actions: {bad}")
    sys.exit(1)
PY
  then fail "t8[C01 AC3]: Inbox-absent variant must emit exactly one create_list(Inbox, Backlog) and still never mirror/label/rule Inbox (reason above)"; fi
  ok "t8[C01 AC3]: Inbox present -> silent; absent -> exactly one Backlog create, never mirrored/labeled/ruled"
fi

# --- t10: the hand-managed skill's Model(s) default-check citations follow the
#     vocabulary generation (cf-106 C02 AC1/AC3) ----------------------------------------
if want t9; then
  [ -f "$SKILL" ] || fail "t9[cf-106 C02]: $SKILL missing — the hand-managed provision skill is a landed surface (cf-90 C01)"
  cat >"$TMP/skillvocab.py" <<'PY'
# skills/wekan-board-provision/SKILL.md is hand-managed: it never regenerates, so
# a missed vocabulary place is a PERMANENT drift. Hence the pins are a count plus a
# closure check, not a presence grep.
import re, sys
text = open(sys.argv[1]).read()
dense = text.count("Qwen Dense")
if dense < 3:
    print(f"the skill names 'Qwen Dense' in {dense} places — three default-check citations "
          f"(frontmatter description, the checklist-spec paragraph, the artifact-shape "
          f"sentence) must all read the current vocabulary generation"); sys.exit(1)
if "Qwen 27b" in text:
    print("the retired label is still in the hand-managed provision skill — it is a current-state "
          "surface with no alias sentence, so the sweep must reach it"); sys.exit(1)
hits = [m.group(0) for m in re.finditer(r"Model\(s\)[^\n]{0,90}", text)]
if not hits:
    print("no Model(s) citation left in the provision skill"); sys.exit(1)
if any("Next" in h for h in hits):
    print(f"a Model(s) citation gained a 'Next' option: {hits}"); sys.exit(1)
if not re.search(r"Model\(s\)[^\n]{0,10}\(4", text):
    print(f"the Model(s) four-item count is gone — the Model(s) checklist stays four items: {hits}"); sys.exit(1)
print("ok")
PY
  # Controls first: a fabricated skill copy that drops the Dense label must FAIL,
  # and a fabricated fifth-item copy must FAIL — proving the dev-facing pin bites.
  python3 - "$SKILL" "$TMP/skill-flat.md" <<'PY'
import sys
open(sys.argv[2], "w", encoding="utf-8").write(open(sys.argv[1], encoding="utf-8").read().replace("Qwen Dense", "Qwen Something"))
PY
  python3 "$TMP/skillvocab.py" "$TMP/skill-flat.md" >/dev/null 2>&1 \
    && fail "t9 control: a skill copy with no 'Qwen Dense' anywhere passed the vocabulary pin — the pin is vacuous"
  python3 - "$SKILL" "$TMP/skill-fifth.md" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
open(sys.argv[2], "w", encoding="utf-8").write(t.replace("Model(s) (4,", "Model(s) (5,", 1))
PY
  python3 "$TMP/skillvocab.py" "$TMP/skill-fifth.md" >/dev/null 2>&1 \
    && fail "t9 control: a skill copy claiming a FIFTH Model(s) item passed the closure pin — AC3's four-option law is not enforced here"
  ok "t9[cf-106 C02 AC3 control]: the skill vocabulary pin fails a Dense-free copy and a fifth-item copy — the dev-facing pin is non-vacuous"
  if ! python3 "$TMP/skillvocab.py" "$SKILL" >/dev/null 2>&1; then
    python3 "$TMP/skillvocab.py" "$SKILL" || fail "t9[cf-106 C02 AC1]: the hand-managed provision skill's Model(s) default-check citations did not all move to the Dense generation (reason above; designed red until C02's three literal edits — this skill never regenerates)"
  fi
  ok "t9[cf-106 C02 AC1/AC3]: all three provision-skill default-check citations read Qwen Dense, the retired label is absent, and Model(s) stays four items"
fi

printf 'PASS: board-provisioning engine/skill/command contract checks (%d ok)\n' "$checks"
