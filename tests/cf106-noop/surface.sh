#!/usr/bin/env bash
# cf-106 C03a — the no-op audit instrument contract (scripts/session-noop-audit.sh)
#
# The instrument turns "did the scheduled ticks mark and archive?" from a memory
# into a measurement: a read-only pass over the OpenCode session store that
# classifies every board-coord session into one fixed verdict class. C03b's fix
# is judged by this output, and this suite is what keeps the instrument honest.
#
# SCRIPT CONTRACT (dev implements to THIS — the assertions below are the
# interface, the same posture as the sibling suites' ENGINE JSON CONTRACT):
#   * invocation: bash scripts/session-noop-audit.sh [--since ISO] [--until ISO]
#     [--repo <directory>] [--limit N] [--json] [--db <path>]
#     --db defaults to the HOST store ~/.local/share/opencode/opencode.db; the
#     suite points it at a fixture it builds, so the live store never enters a gate.
#   * store access: python3 stdlib sqlite3 opened as file:<path>?mode=ro — there is
#     no sqlite3 binary in the workspace. Reads only: no opencode api POST/PATCH,
#     no board call, no .pipeline/ write, no session write.
#   * schema it joins (verified against the live store 2026-11-04):
#       session_v2(id, slug, directory, title, agent, model, metadata,
#                  -- `model` is a JSON OBJECT in the live store ({"id":…,"provider":…});
#                  -- older rows and fixtures hold a bare string. Both shapes appear.
#                  time_created, time_archived, idle_outcome)
#       session_message(session_id, type, seq, time_created, data)  -- type in
#                  user|assistant|system|synthetic|idle|…, data is JSON:
#                  user {"time":{…},"text":…}; assistant {"time":{…},
#                  "content":[{"type":"text","text":…},…]}
#   * --json prints a JSON array, one object per session, with at least the keys:
#       {"id":…,"verdict":…,"marker":…,"archived":true|false,"kind":…,"model":…,
#        "title":…,"excerpt":…}
#     `verdict` is EXACTLY ONE of the fixed vocabulary
#       marked-archived | marked-unarchived | unmarked-archived | gate-stop |
#       abnormal-end | mcp-surface-absent | did-work
#     (marker classes win over stop-shape classes, so a marked-and-archived
#     gate-stop tick reads marked-archived — that precedence is what makes
#     C03b's fix visible in the table); `kind` is the record's OpenChamber launch
#     kind; `excerpt` is a SHORT last-text excerpt, never a whole transcript.
#   * `--limit`/window filters never change a verdict: per-id classification,
#     never a total-count equality (the live store keeps growing).
#
# AC trace (chunks/C03a.md): N1[AC2 classification — every class derived exactly
# once over a fixture store, INCLUDING the fall-through shapes the vocabulary must
# not reinterpret (no message rows, malformed message rows, malformed metadata →
# neutral; tool-call-only tail → abnormal-end via the cut-tail branch) and both
# model-column spellings (live JSON object and legacy bare string), with a fixture
# shape guard and four fabricated-output controls] N2[AC3 read-only posture, machine-checked (write TARGETS
#    only — the SQL entry point itself is legal since python 3.14 dropped
#    exec_driver_sql), with a
# fabricated write control] N3[AC4 no new shell grant anywhere] N4[AC1 baseline
# parity per named session id over a seeded fixture + the newer-session control]
# N5[HOLD — the marker contract's own legs keep passing untouched: this chunk
# changes no contract text] N6[cf-106 C03b HOLD/GREEN pair — a gate-stop session
# that marks and archives reads marked-archived: the instrument side of the pair,
# while the live judgement is the marker columns (see readback.md)].
#
# Posture since C03a dev landed the script: all six legs green. Nothing here is
# designed red — a red is a defect, either in the script (N1/N2/N4/N6) or in the
# fixture itself (N1's shape guard says so explicitly rather than blaming dev).
# N3 and N5 are HOLDs: C03a adds no permission, C03b owns the contract text.
#
# Usage:
#   bash tests/cf106-noop/surface.sh            # N1..N6
#   bash tests/cf106-noop/surface.sh N1 N6      # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

AUDIT="scripts/session-noop-audit.sh"
EVIDENCE=".agents/plans/2026/2026-11-cf-106-feat-coord-fixes/2026-11-03-cf-106-feat-coord-fixes-noop-evidence.md"
GATE_SCRIPT="scripts/agent-board-coord-gate.sh"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

TMP=$(mktemp -d /tmp/opencode/cf106-noop-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6; do WANT["n$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^n[1-6]$ ]] || fail "unknown check id '$a' (expected N1..N6)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# The fixture builder is the suite's own data: it builds a store with the pinned
# schema and one session per verdict class, so classification can be judged
# without touching the host store (536 MB of real transcripts has no place in a
# gate). Kept as a file so N1, N4 and N6 drive the SAME builder.
cat >"$TMP/mkstore.py" <<'PY'
"""Build a minimal OpenCode-shaped session store for the audit contract."""
import json, sqlite3, sys

T0 = 1_762_100_000_000  # 2026-11-03T00:00Z-ish, epoch ms

# The live store's model column is a JSON object; seeding that shape by default keeps
# the fixture honest about what the readback table actually reads.
# Key spelling taken from the live store: {"id":…,"providerID":…}, and the id carries
# no provider prefix there — the readback's model column is only as honest as the shape.
LIVE_MODEL = json.dumps({"id": "qwen3.8-27b-q4", "providerID": "gpu-ai"})


def session(cur, sid, *, agent="agent-board-coord", directory="/repo", metadata=None,
            raw_metadata=None,
            archived_at=None, title="scheduled tick", model=LIVE_MODEL,
            slug="cf-42-feat-x", created=None, idle_outcome=None):
    cur.execute(
        "insert into session_v2 (id, project_id, slug, directory, title, agent, model,"
        " metadata, time_created, time_updated, time_archived, idle_outcome)"
        " values (?,?,?,?,?,?,?,?,?,?,?,?)",
        (sid, "proj", slug, directory, title, agent, model,
         raw_metadata if raw_metadata is not None
         else (json.dumps(metadata) if metadata is not None else None),
         created or T0, created or T0, archived_at, idle_outcome),
    )


def msg(cur, sid, typ, text, seq):
    if typ == "assistant":
        data = {"time": {"created": T0 + seq * 1000}, "content": [{"type": "text", "text": text}]}
    else:
        data = {"time": {"created": T0 + seq * 1000}, "text": text}
    cur.execute("insert into session_message (id, session_id, type, seq, time_created, time_updated, data)"
                " values (?,?,?,?,?,?,?)", (f"msg_{sid}_{seq}", sid, typ, seq, T0 + seq * 1000,
                                            T0 + seq * 1000, json.dumps(data)))


def msg_raw(cur, sid, typ, data_text, seq):
    """A message row whose `data` is left exactly as given — malformed JSON or a
    content list with no text part, i.e. the unreadable shapes a store change can bring."""
    cur.execute("insert into session_message (id, session_id, type, seq, time_created, time_updated, data)"
                " values (?,?,?,?,?,?,?)", (f"msg_{sid}_{seq}", sid, typ, seq, T0 + seq * 1000,
                                            T0 + seq * 1000, data_text))


def turns(cur, sid, n=6):
    for i in range(1, n + 1):
        msg(cur, sid, "user", f"step {i}", i * 2 - 1)
        msg(cur, sid, "assistant", f"did step {i}", i * 2)


def build(path, rows):
    con = sqlite3.connect(path)
    con.execute("""create table session_v2 (
        id text primary key, project_id text, slug text, directory text, title text,
        agent text, model text, metadata text, time_created integer, time_updated integer,
        time_archived integer, idle_outcome integer)""")
    con.execute("""create table session_message (
        id text primary key, session_id text, type text, seq integer,
        time_created integer, time_updated integer, data text)""")
    cur = con.cursor()
    rows(cur)
    con.commit()
    con.close()


def marker(reason="no-cards", at=None):
    m = {"openchamber": {"kind": "scheduled"}, "pipelineNoop": {"reason": reason}}
    if at is not None:
        m["pipelineNoop"]["at"] = at
    return m


def all_classes(cur):
    # one session per verdict class, in the fixed vocabulary's order, then the
    # unreadable-transcript shapes and both model-column spellings
    session(cur, "ses_marked_arch", metadata=marker("no-cards", T0), archived_at=T0 + 9000)
    turns(cur, "ses_marked_arch", 4)
    session(cur, "ses_marked_unarch", metadata=marker("no-claimable-cards", T0))
    turns(cur, "ses_marked_unarch", 4)
    session(cur, "ses_unmarked_arch", metadata={"openchamber": {"kind": "scheduled"}},
            archived_at=T0 + 9000)
    turns(cur, "ses_unmarked_arch", 4)
    session(cur, "ses_gate_stop", metadata={"openchamber": {"kind": "scheduled"}})
    msg(cur, "ses_gate_stop", "user", "GATE: SKIP session detection failed (no live session resolvable)", 1)
    for i in range(1, 5):
        msg(cur, "ses_gate_stop", "assistant", f"gate verdict already printed; stopping turn {i}", i + 1)
    session(cur, "ses_abnormal", metadata={"openchamber": {"kind": "scheduled"}})
    msg(cur, "ses_abnormal", "user", "tick", 1)
    msg(cur, "ses_abnormal", "assistant", "I will now call <tool_call>pipeline_claim</tool_call>", 2)
    session(cur, "ses_mcp_absent", metadata={"openchamber": {"kind": "scheduled"}})
    turns(cur, "ses_mcp_absent", 4)
    msg(cur, "ses_mcp_absent", "assistant",
        "the dev-boards MCP tools are not present in this session's tool surface — cannot read the board", 9)
    session(cur, "ses_did_work", metadata={"openchamber": {"kind": "scheduled"}},
            idle_outcome=0)
    turns(cur, "ses_did_work", 8)
    # Unreadable-transcript shapes: none of these may land in abnormal-end. A session
    # with no message rows, or only unparseable ones, or malformed metadata says
    # nothing about how the run ended — only a store-shape change would read them as
    # "died before any exit".
    session(cur, "ses_no_messages", metadata={"openchamber": {"kind": "scheduled"}})
    session(cur, "ses_bad_messages", metadata={"openchamber": {"kind": "scheduled"}})
    for seq in (1, 2, 3):
        msg_raw(cur, "ses_bad_messages", "assistant", "{ truncated at the page boundary", seq)
    session(cur, "ses_bad_metadata", raw_metadata='{"openchamber": {"kind": "schedul')
    turns(cur, "ses_bad_metadata", 4)
    session(cur, "ses_toolcall_tail", metadata={"openchamber": {"kind": "scheduled"}})
    msg(cur, "ses_toolcall_tail", "user", "tick", 1)
    for seq in (2, 3, 4):
        msg_raw(cur, "ses_toolcall_tail", "assistant",
                json.dumps({"time": {"created": T0 + seq * 1000},
                            "content": [{"type": "tool-call", "toolName": "list_boards",
                                        "input": {"board": "AI-Dev"}}]}), seq)
    # model-column shapes, both seeded on purpose: the readback's model column and
    # C10's runner-model readback read it, and the store carries both spellings.
    session(cur, "ses_model_object", model=json.dumps({"id": "qwen3.8-27b-q4",
                                                       "providerID": "gpu-ai"}),
            metadata={"openchamber": {"kind": "scheduled"}})
    turns(cur, "ses_model_object", 6)
    session(cur, "ses_model_null", model=None,
            metadata={"openchamber": {"kind": "scheduled"}})
    turns(cur, "ses_model_null", 6)
    session(cur, "ses_model_string", model="gpu-ai/qwen3.8-flash-next-strata",
            metadata={"openchamber": {"kind": "scheduled"}})
    turns(cur, "ses_model_string", 6)


if __name__ == "__main__":
    mode, path = sys.argv[1], sys.argv[2]
    if mode == "all":
        build(path, all_classes)
    elif mode == "baseline":
        # the evidence artifact's named ids and recorded verdicts (C03a AC1)
        def baseline(cur):
            for i in range(32):
                session(cur, f"ses_base_marked_{i:02d}", metadata=marker("no-cards", T0), archived_at=T0 + 9000)
                turns(cur, f"ses_base_marked_{i:02d}", 4)
            for sid in ("ses_base_abn_a", "ses_base_abn_b"):
                session(cur, sid, metadata={"openchamber": {"kind": "scheduled"}})
                msg(cur, sid, "user", "tick", 1)
                msg(cur, sid, "assistant", "calling <function=pipeline_claim> inline", 2)
            for i in range(3):
                session(cur, f"ses_base_mid_{i}", metadata={"openchamber": {"kind": "scheduled"}})
                for k in range(1, 5):
                    msg(cur, f"ses_base_mid_{i}", "assistant", f"checked the lock set, mid-turn stop {k}", k)
            session(cur, "ses_base_mcp", metadata={"openchamber": {"kind": "scheduled"}})
            msg(cur, "ses_base_mcp", "user", "tick", 1)
            msg(cur, "ses_base_mcp", "assistant", "dev-boards tools absent from the MCP surface", 2)
            session(cur, "ses_probe_sentinel", title="probeSentinel",
                    metadata={"openchamber": {"kind": "manual"}}, archived_at=T0 + 9000)
            turns(cur, "ses_probe_sentinel", 4)
        build(path, baseline)
    elif mode == "late":
        # same store plus a newer session — no existing verdict may move
        def with_late(cur):
            all_classes(cur)
            session(cur, "ses_later_tick", created=T0 + 5_000_000,
                    metadata=marker("gate-skip", T0 + 5_000_000), archived_at=T0 + 5_000_000 + 9000)
            turns(cur, "ses_later_tick", 4)
        build(path, with_late)
    elif mode == "gatestop-fixed":
        # the C03b post-fix shape: the tick stop marks and archives
        def fixed(cur):
            session(cur, "ses_gate_stop_fixed", metadata=marker("gate-skip", T0), archived_at=T0 + 9000)
            msg(cur, "ses_gate_stop_fixed", "user", "GATE: SKIP session detection failed", 1)
            msg(cur, "ses_gate_stop_fixed", "assistant",
                "GATE: SKIP — marking the no-op, archiving, then stopping.", 2)
        build(path, fixed)
    else:
        raise SystemExit(f"harness: unknown fixture mode {mode}")
PY

run_audit() { # run_audit <fixture> <out-name> [extra args]
  local fx="$1" name="$2"; shift 2
  python3 - "$AUDIT" "$fx" "$TMP/$name.json" "$@" <<'PY'
import subprocess, sys
audit, fx, out = sys.argv[1], sys.argv[2], sys.argv[3]
extra = sys.argv[4:]
try:
    proc = subprocess.run(["bash", audit, "--db", fx, "--json"] + extra,
                          capture_output=True, text=True, timeout=120)
except FileNotFoundError:
    print(f"cannot run {audit}"); sys.exit(3)
open(out, "w", encoding="utf-8").write(proc.stdout)
sys.stderr.write(proc.stderr[:400])
sys.exit(proc.returncode)
PY
}

# --- N1: every verdict class derived exactly once (AC2) -------------------------
# The fall-through branches matter as much as the seven named classes: a session
# with no message rows, with unparseable message rows, or with malformed metadata
# carries NO evidence about how the run ended, so it must read neutral. Reading
# those as abnormal-end would convert store-schema drift into a wave of runs that
# "die before any exit" — the class the plan's risk register treats as a gap.
if want n1; then
  [ -f "$AUDIT" ] \
    || fail "N1[C03a AC2]: $AUDIT does not exist — the audit script is C03a's first task (designed red before C03a dev, not a harness fault)"
  python3 "$TMP/mkstore.py" all "$TMP/store-all.db" || fail "harness: fixture builder failed (report, do not blame dev)"
  # Fixture self-validation before blaming dev: an arm that pins a shape is only
  # honest while the seeded store still carries that shape.
  if ! python3 - "$TMP/store-all.db" <<'PFIX'
"""Every shape the classifier arms pin must really be in the seeded store."""
import json, sqlite3, sys
con = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
con.row_factory = sqlite3.Row


def parses(text):
    try:
        json.loads(text)
        return True
    except (TypeError, ValueError):
        return False


def msgs(sid):
    return list(con.execute("select type, data from session_message where session_id=?", (sid,)))


def col(sid, name):
    row = con.execute("select " + name + " from session_v2 where id=?", (sid,)).fetchone()
    return row[name] if row else None


bad = []
if msgs("ses_no_messages"):
    bad.append("ses_no_messages has message rows — the no-transcript shape is gone")
bm = msgs("ses_bad_messages")
if not bm or any(parses(r["data"]) for r in bm):
    bad.append("ses_bad_messages rows parse — the malformed-data shape is gone")
tt = msgs("ses_toolcall_tail")
if len([r for r in tt if r["type"] == "assistant"]) < 3:
    bad.append(f"ses_toolcall_tail has {len(tt)} rows — the cut-tail arm must sit above the turn floor")
if tt and any((c.get("text") or "") for r in tt for c in (json.loads(r["data"]).get("content") or [])
               if c.get("type") == "text"):
    bad.append("ses_toolcall_tail carries a text part — the tool-call-only tail shape is gone")
if parses(col("ses_bad_metadata", "metadata")):
    bad.append("ses_bad_metadata metadata parses — the malformed-metadata shape is gone")
mo = col("ses_model_object", "model")
if not (parses(mo) and isinstance(json.loads(mo), dict) and json.loads(mo).get("id")):
    bad.append("ses_model_object's model column is not a JSON object with an id — the live shape is gone")
if parses(col("ses_model_string", "model")):
    bad.append("ses_model_string's model column parses as JSON — the bare-string shape is gone")
if col("ses_model_null", "model") is not None:
    bad.append("ses_model_null's model column is not NULL — the absent-model shape is gone")
if not (parses(col("ses_marked_arch", "model")) and isinstance(json.loads(col("ses_marked_arch", "model")), dict)):
    bad.append("the fixture's default model column is not the live object shape — the fixture drifted off the store it mirrors")
print("; ".join(bad))
sys.exit(1 if bad else 0)
PFIX
  then fail "N1[C03a AC2]: FIXTURE FAULT (reason above) — the seeded store no longer carries a shape the classifier arms pin (harness, not dev)"; fi
  if ! run_audit "$TMP/store-all.db" n1; then
    fail "N1[C03a AC2]: the audit run over the fixture store failed (reason above) — the script must classify a fixture store through --db"
  fi
  cat >"$TMP/classes.py" <<'PY'
"""Verdict classes over the fixture store (AC2), plus the row shapes the readback reads.

`abnormal-end` is reserved for evidence of a death (too few turns, or a turn cut off
mid-stream). Unreadable transcripts — no rows, unparseable rows, malformed metadata —
decide neutral, or a store-schema change would manufacture "died before any exit".
"""
import json, sys

WANT = {
    "ses_marked_arch": "marked-archived",
    "ses_marked_unarch": "marked-unarchived",
    "ses_unmarked_arch": "unmarked-archived",
    "ses_gate_stop": "gate-stop",
    "ses_abnormal": "abnormal-end",
    "ses_mcp_absent": "mcp-surface-absent",
    "ses_did_work": "did-work",
    "ses_no_messages": "did-work",
    "ses_bad_messages": "did-work",
    "ses_bad_metadata": "did-work",
    "ses_toolcall_tail": "abnormal-end",
    "ses_model_object": "did-work",
    "ses_model_string": "did-work",
    "ses_model_null": "did-work",
}
# Per-id row shape, so an arm cannot pass by accident: turns/excerpt decide WHICH
# fall-through branch fired, model decides whether the column rendered usefully.
SHAPES = {
    "ses_no_messages": {"turns": 0, "excerpt": ""},
    "ses_bad_messages": {"turns": 0, "excerpt": ""},
    "ses_toolcall_tail": {"turns": 4, "excerpt": ""},
    "ses_bad_metadata": {"turns": 8},
    "ses_model_object": {"model": "qwen3.8-27b-q4"},
    "ses_model_string": {"model": "gpu-ai/qwen3.8-flash-next-strata"},
    "ses_model_null": {"model": None},
    "ses_marked_arch": {"model": "qwen3.8-27b-q4"},
}
KEYS = ("verdict", "archived", "kind", "title", "excerpt", "model", "turns")
VOCAB = set(WANT.values())
TURN_FLOOR = 3

try:
    rows = json.load(open(sys.argv[1]))
except Exception as exc:
    print(f"--json is not the pinned JSON array: {exc}"); sys.exit(1)
if not isinstance(rows, list):
    print(f"--json must print a JSON array, got {type(rows).__name__}"); sys.exit(1)
got = {r.get("id"): r for r in rows}
problems = []
for sid, verdict in WANT.items():
    row = got.get(sid)
    if row is None:
        problems.append(f"fixture session {sid} is missing from the output (every session in the window gets exactly one row)")
        continue
    if row.get("verdict") != verdict:
        problems.append(f"{sid}: verdict {row.get('verdict')!r}, want {verdict!r} — the fixed vocabulary is machine-derived, not a guess")
    for key in KEYS:
        if key not in row:
            problems.append(f"{sid}: row lacks the pinned key {key!r}: {json.dumps(row)[:200]}")
    for key, want in SHAPES.get(sid, {}).items():
        if row.get(key) != want:
            problems.append(f"{sid}: {key}={row.get(key)!r}, want {want!r}"
                            + (" — the model column must render as one id (object → its id, string → itself)" if key == "model" else ""))
tail = got.get("ses_toolcall_tail")
if tail is not None and tail.get("turns", 0) < TURN_FLOOR:
    problems.append("ses_toolcall_tail is below the turn floor — that arm would pin the low-turn branch, not the cut-tail branch")
extra = sorted(set(got) - set(WANT))
if extra:
    problems.append(f"the fixture emitted rows outside the seeded sessions: {extra}")
bad = [c for c in (r.get("verdict") for r in rows) if c not in VOCAB]
if bad:
    problems.append(f"verdict(s) outside the fixed vocabulary: {bad}")
for p in problems:
    print(p)
sys.exit(1 if problems else 0)
PY
  if ! python3 "$TMP/classes.py" "$TMP/n1.json"; then
    fail "N1[C03a AC2]: the classification leg failed (reason above)"; fi
  ok "N1[C03a AC2]: all fourteen fixture sessions land in their class — the seven named classes plus the unreadable trio (no rows, malformed rows, malformed metadata → neutral), the tool-call-only tail (→ abnormal-end on the cut-tail branch, not the turn floor), and both model shapes rendering as one id"
  # Controls: fabricated audit outputs, one per arm. Each must be rejected by the
  # same checker the dev-facing run uses, or that arm is inert.
  cat >"$TMP/corrupt.py" <<'PMUT'
import json, sys
rows, defect = json.load(open(sys.argv[1])), sys.argv[3]


def setv(sid, key, value):
    for r in rows:
        if r.get("id") == sid:
            r[key] = value
            return True
    return False


FIXED = {
    "unreadable_as_abnormal": lambda: setv("ses_no_messages", "verdict", "abnormal-end"),
    "tail_as_didwork": lambda: setv("ses_toolcall_tail", "verdict", "did-work"),
    "model_raw": lambda: setv("ses_model_object", "model",
                              json.dumps({"id": "qwen3.8-27b-q4", "providerID": "gpu-ai"})),
    "model_dropped": lambda: setv("ses_model_string", "model", None),
}[defect]()
if not FIXED:
    print("the fixture output has no row for the fabricated defect"); sys.exit(2)
json.dump(rows, open(sys.argv[2], "w"))
PMUT
  for defect in unreadable_as_abnormal tail_as_didwork model_raw model_dropped; do
    python3 "$TMP/corrupt.py" "$TMP/n1.json" "$TMP/classes-$defect.json" "$defect" \
      || fail "N1 control: could not fabricate the '$defect' output (harness fault)"
    python3 "$TMP/classes.py" "$TMP/classes-$defect.json" >/dev/null 2>&1 \
      && fail "N1 control: the fabricated '$defect' output still passed the classifier contract — that arm is inert"
  done
  ok "N1[C03a AC2 control]: four fabricated outputs are each rejected — unreadable read as abnormal-end, cut-tail read as did-work, model column left raw, model column dropped"
fi

# --- N2: read-only by construction (AC3) ----------------------------------------
if want n2; then
  [ -f "$AUDIT" ] || fail "N2[C03a AC3]: $AUDIT does not exist yet (designed red before C03a dev)"
  cat >"$TMP/readonly.py" <<'PY'
"""Static read-only posture of the audit script (AC3, machine-checked).

Every forbidden pattern is named with what it would mean, so a red line reads as
a defect report. uri='file:…?mode=ro' (or mode=ro in any spelling) is REQUIRED,
not just the absence of writes — a plain sqlite3.connect(path) opens for write.
"""
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
forbidden = {
    r"opencode api post": "a session/board POST from a diagnostic that must never write",
    r"opencode api patch": "a session PATCH — the audit reads the store, it never marks or archives",
    r"move_card|add_comment|toggle_checklist_item|set_card_custom_field": "a board write from a read-only instrument",
    r"pipeline_claim|pipeline_release|pipeline_heartbeat": "a lock-tool call from a diagnostic (it must not claim)",
    r"\.pipeline/": "a lock-file touch — the plugin owns .pipeline/, agents and scripts never do",
    # The SQL entry point is NOT the forbidden thing: python 3.14 removed
    # sqlite3's exec_driver_sql, so a store-reading script must call execute().
    # What is forbidden is a call whose TARGET mutates state — a subprocess spawn
    # (how a CLI write would arrive), an HTTP client or write verb, a session
    # mutation endpoint, or a DML statement against the store.
    r"subprocess\.(run|Popen|call|check_output|check_call|getoutput|open)\b": "a subprocess spawn — this diagnostic reads sqlite; a CLI write would arrive through here",
    r"\b(curl|wget)\b[^\n]*(opencode|/api/|/session/)": "an HTTP call out of a diagnostic that must only read the store",
    r"\b(curl|wget)\b[^\n]*(-X\s*(POST|PATCH|PUT|DELETE)|--request\s*(POST|PATCH|PUT|DELETE)|--data|--form|-d\s)": "an HTTP write verb via curl",
    r"\b(import|from)\s+(urllib|http\.client|requests|httpx|aiohttp)\b": "an HTTP client imported into a store-reading diagnostic — no session-API call is legitimate here, aliased or not",
    r"urllib\.request|http\.client\.|requests\.(get|post|patch|put|delete)|httpx\.|aiohttp\.": "an HTTP client call in a store-reading diagnostic",
    r"os\.(system|popen)\(|popen\(": "a shell-out vector in a diagnostic that only needs sqlite3",
    r"/session/[A-Za-z0-9_\"'{]+/(move|archive|update)": "a session mutation endpoint named in the audit",
    r"\bexecute(script)?\s*\(\s*[\"'](insert|update|delete|replace|create|drop|alter|pragma)\b": "a DML statement — the audit issues SELECTs only",
    r"mode=ro": None,  # required, inverted below
    r"sqlite3\.connect\(\s*['\"](?!file:)": "a sqlite connect without the file: URI — that opens for write",
}
problems = []
for pat, why in forbidden.items():
    hits = re.findall(pat, text)
    if why is None:
        if not hits:
            problems.append("no mode=ro connect anywhere — the store must be opened read-only")
        continue
    if hits:
        problems.append(f"{pat} → {why}")
if re.search(r"sqlite3\.connect\(", text) and not re.search(r"mode=ro", text):
    problems.append("sqlite connect present but never read-only")
for p in problems:
    print(p)
sys.exit(1 if problems else 0)
PY
  python3 "$TMP/readonly.py" "$AUDIT" \
    || fail "N2[C03a AC3]: the audit script's read-only posture failed (reason above) — AC3 is machine-checked on purpose"
  # Controls: fabricated write shapes, one per arm of the posture. Each is the real
  # script plus one injected line; every one must redden the same checker, or the
  # arm it covers is inert. (The old bare-execute needle reddened the real script
  # itself instead — an unimplementable pin, not a posture proof.)
  cat >"$TMP/inject.py" <<'PINJ'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
DEFECTS = {
    "api_patch": "\nopencode api patch --session \"$SID\" '{\"archived\": true}'\n",
    "cli_post": "\ncurl -X POST https://api.example/session/x\n",
    "http_client": "\nimport urllib.request as _u; _u.urlopen(_u.Request(url, method=\"PATCH\"))\n",
    "move_endpoint": "\npath = \"/session/ses_1/archive\"\n",
    "store_write": "\ncur.execute(\"update session_v2 set idle_outcome=? where id=?\", (1, sid))\n",
}
open(sys.argv[3], "w", encoding="utf-8").write(text + DEFECTS[sys.argv[2]])
PINJ
  for defect in api_patch cli_post http_client move_endpoint store_write; do
    python3 "$TMP/inject.py" "$AUDIT" "$defect" "$TMP/audit-$defect.sh" \
      || fail "N2 control: could not fabricate the '$defect' write shape (harness fault)"
    python3 "$TMP/readonly.py" "$TMP/audit-$defect.sh" >/dev/null 2>&1 \
      && fail "N2 control: a copy of the audit carrying the '$defect' write shape passed the read-only posture check — that arm is vacuous"
  done
  ok "N2[C03a AC3]: the audit script opens the store read-only and carries no session, board, lock or store write — five fabricated write shapes (session PATCH, curl PATCH, aliased urllib PATCH, archive endpoint path, sqlite DML) are each rejected"
fi

# --- N3: no new shell grant anywhere (AC4) ---------------------------------------
if want n3; then
  cat >"$TMP/agents.list" <<'LIST'
.rulesync/subagents/agent-coord.md
.rulesync/subagents/agent-coord-local.md
.rulesync/subagents/agent-coord-pr.md
.rulesync/subagents/agent-board-coord.md
.rulesync/subagents/agent-board-coord-local.md
.rulesync/subagents/agent-board-coord-pr.md
.rulesync/subagents/agent-dev-local.md
.rulesync/subagents/agent-dev-pr.md
.rulesync/subagents/agent-test.md
.rulesync/subagents/agent-review.md
.rulesync/subagents/agent-explore.md
.rulesync/subagents/agent-research.md
.rulesync/subagents/agent-plan.md
LIST
  [ -s "$TMP/agents.list" ] || fail "harness: the agent-source list is empty"
  missing=""
  while IFS= read -r f; do
    [ -f "$f" ] || missing="$missing $f"
  done <"$TMP/agents.list"
  [ -z "$missing" ] || fail "harness: agent sources missing from the expected list:$missing (the permission surface moved — re-pin this suite, do not blame dev)"
  hits=$(grep -l 'session-noop-audit' $(cat "$TMP/agents.list") 2>/dev/null || true)
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" >&2
    fail "N3[C03a AC4]: an agent definition grants session-noop-audit — the audit stays human/interactive-invoked (the owner's answer 11 keeps the toggle posture); no bash row is added for it in this ticket"
  fi
  # The scope-block admits are the ONLY place the script may be named outside
  # scripts/ and this suite: a scope line is not a shell grant.
  scoped=$(grep -rln 'session-noop-audit' .rulesync .opencode/agents .agents/agents 2>/dev/null || true)
  if [ -n "$scoped" ]; then
    printf '%s\n' "$scoped" >&2
    fail "N3[C03a AC4]: session-noop-audit named in an agent source or skill surface — the chunk adds no permission and no contract text for it"
  fi
  ok "N3[C03a AC4]: no agent definition or skill surface grants or names the audit script — the invocation posture stays human/interactive"
fi

# --- N4: baseline parity per named session id, never by count (AC1) --------------
if want n4; then
  [ -f "$AUDIT" ] || fail "N4[C03a AC1]: $AUDIT does not exist yet, so the baseline cannot be reproduced (designed red before C03a dev)"
  [ -f "$EVIDENCE" ] || fail "harness: the evidence artifact $EVIDENCE is missing — the baseline it records is the parity target (report, do not blame dev)"
  python3 "$TMP/mkstore.py" baseline "$TMP/store-base.db" || fail "harness: baseline fixture build failed"
  if ! run_audit "$TMP/store-base.db" n4; then
    fail "N4[C03a AC1]: audit run over the baseline fixture failed (reason above)"
  fi
  python3 - "$TMP/n4.json" "$EVIDENCE" <<'PY' || fail "N4[C03a AC1]: the baseline-parity leg failed (reason above)"
import json, sys
rows = json.load(open(sys.argv[1]))
by = {r.get("id"): r for r in rows}
verdicts = [r.get("verdict") for r in rows]
marked_arch = verdicts.count("marked-archived")
scheduled = [r for r in rows if r.get("kind") == "scheduled"]
unmarked = [r for r in scheduled if not (r.get("marker") and str(r.get("marker")) not in ("None", "null", ""))]
# The artifact's read (2026-11-03T22:45Z): 32 marked+archived scheduled rows, 6
# unmarked scheduled rows (2 abnormal-end on raw tool-call XML, 3 mid-turn deaths,
# 1 mcp-surface-absent), and 1 manual probeSentinel control row. Parity is per-id
# and per-class, never a total count.
if marked_arch != 32:
    print(f"baseline parity: {marked_arch} marked-archived rows, the artifact records 32"); sys.exit(1)
if len(unmarked) != 6:
    print(f"baseline parity: {len(unmarked)} unmarked scheduled rows, the artifact records 6"); sys.exit(1)
for sid, want in (("ses_base_abn_a", "abnormal-end"), ("ses_base_abn_b", "abnormal-end"),
                  ("ses_base_mcp", "mcp-surface-absent"),
                  ("ses_base_mid_0", None), ("ses_base_mid_1", None), ("ses_base_mid_2", None)):
    row = by.get(sid)
    if row is None:
        print(f"the artifact's named session {sid} has no row at all"); sys.exit(1)
    if want and row.get("verdict") != want:
        print(f"{sid}: verdict {row.get('verdict')!r}, the artifact records {want!r}"); sys.exit(1)
sent = by.get("ses_probe_sentinel")
if sent is None or sent.get("kind") != "manual":
    print(f"the manual probeSentinel control row must classify as a manual-kind session, got {sent}"); sys.exit(1)
print("ok")
PY
  ok "N4[C03a AC1]: the fixture store seeded with the artifact's named sessions reproduces the recorded classes (32 marked+archived, 6 unmarked, the manual control), per id"
  # Control: a NEWER session added to the store must not move any recorded verdict
  # (the arm that keeps the live-store read from going flaky).
  # Self-sufficient base: the control builds its own base store (the same fixture
  # mode N1 uses) instead of reusing N1's output, so N4 runs as an id-subset — a leg
  # that only passes after another leg is un diagnosable in a battery that aborts red.
  python3 "$TMP/mkstore.py" all "$TMP/store-n4base.db" || fail "harness: no-drift base fixture build failed"
  if ! run_audit "$TMP/store-n4base.db" n4base; then
    fail "N4[C03a AC1]: audit run over the no-drift base fixture failed (reason above)"
  fi
  python3 "$TMP/mkstore.py" late "$TMP/store-late.db" || fail "harness: late-session fixture build failed"
  if ! run_audit "$TMP/store-late.db" n4late; then
    fail "N4[C03a AC1]: audit run over the late-session fixture failed (reason above)"
  fi
  python3 - "$TMP/n4base.json" "$TMP/n4late.json" <<'PY' || fail "N4[C03a AC1]: the newer-session control failed (reason above)"
import json, sys
base = {r["id"]: r["verdict"] for r in json.load(open(sys.argv[1]))}
late = {r["id"]: r for r in json.load(open(sys.argv[2]))}
if not base:
    print("the base fixture produced no rows — the control compares nothing"); sys.exit(1)
drift = {sid: (v, late[sid]["verdict"]) for sid, v in base.items() if sid in late and late[sid]["verdict"] != v}
if drift:
    print(f"a newer session changed existing verdicts: {drift} — classification is per-id and window-independent (AC1's non-flaky-by-construction rule)"); sys.exit(1)
new = sorted(set(late) - set(base))
if "ses_later_tick" not in new:
    print(f"the newer control session is absent from the output: {new}"); sys.exit(1)
if late["ses_later_tick"]["verdict"] != "marked-archived":
    print(f"the newer marked+archived tick must classify marked-archived, got {late['ses_later_tick']['verdict']}"); sys.exit(1)
print("ok")
PY
  ok "N4[C03a AC1 control]: a newer session in the store changes no existing verdict and classifies on its own — the parity check cannot drift with the live store"
fi

# --- N5: HOLD — the marker contract's own legs stay green (C03a changes no text) ---
if want n5; then
  # N5 runs the marker suite's text legs that must survive untouched: the reader
  # conjunction and the RESULT-posture pair. The cf-106 C03b re-pinned legs
  # (N2/N6/N7 of that suite) are deliberately NOT run here — they carry designed
  # reds of their own.
  for leg in n1 n5; do
    if ! out=$(bash tests/noop-marker/surface.sh "$leg" 2>&1); then
      printf '%s\n' "$out" | tail -3 >&2
      fail "N5[HOLD]: tests/noop-marker/surface.sh $leg failed — C03a adds no contract text, so the marker contract's own legs must pass untouched (if this leg was re-pinned red by C03b, run the leg the re-pin owns instead of weakening this one)"
    fi
  done
  ok "N5[HOLD]: the marker contract's reader and RESULT-posture legs pass untouched while C03a lands — the instrument changes no contract text"
fi

# --- N6: C03b's regression guard — a marked tick stop reads marked-archived -------
if want n6; then
  [ -f "$AUDIT" ] || fail "N6[cf-106 C03b]: $AUDIT does not exist yet (designed red before C03a dev)"
  python3 "$TMP/mkstore.py" gatestop-fixed "$TMP/store-fixed.db" || fail "harness: gate-stop fixture build failed"
  if ! run_audit "$TMP/store-fixed.db" n6; then
    fail "N6[cf-106 C03b]: audit run over the post-fix gate-stop fixture failed (reason above)"
  fi
  python3 - "$TMP/n6.json" <<'PY' || fail "N6[cf-106 C03b]: the post-fix gate-stop parity leg failed (reason above)"
import json, sys
rows = json.load(open(sys.argv[1]))
row = next((r for r in rows if r.get("id") == "ses_gate_stop_fixed"), None)
if row is None:
    print("the post-fix gate-stop session has no row"); sys.exit(1)
if row.get("verdict") != "marked-archived":
    print(f"a scheduled tick that stopped on a gate verdict and DID mark+archive reads {row.get('verdict')!r}, "
          f"want 'marked-archived' — the marker classes must win over the stop shape, otherwise C03b's fix "
          f"is invisible in the table and AC8's readback cannot be judged"); sys.exit(1)
if not row.get("archived"):
    print(f"the row must report archived true, got {row.get('archived')!r}"); sys.exit(1)
print("ok")
PY
  ok "N6[cf-106 C03b]: a gate-stop session that marked and archived classifies marked-archived — the instrument is also the fix's regression guard"
fi

printf 'PASS: cf-106 no-op audit instrument checks (%d ok)\n' "$checks"
