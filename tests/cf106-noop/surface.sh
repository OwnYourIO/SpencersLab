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
# once over a fixture store] N2[AC3 read-only posture, machine-checked, with a
# fabricated write control] N3[AC4 no new shell grant anywhere] N4[AC1 baseline
# parity per named session id over a seeded fixture + the newer-session control]
# N5[HOLD — the marker contract's own legs keep passing untouched: this chunk
# changes no contract text] N6[cf-106 C03b HOLD/GREEN pair — a gate-stop session
# that marks reads marked-archived, which is how the fix is judged].
#
# Red posture: the script does not exist yet — N1, N2, N4 and N6 are designed red
# and each names the missing surface, never a harness fault. N3 and N5 are green
# now and must stay green (C03a adds no permission; C03b owns the contract text).
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


def session(cur, sid, *, agent="agent-board-coord", directory="/repo", metadata=None,
            archived_at=None, title="scheduled tick", model="gpu-ai/qwen3.8-27b-q4",
            slug="cf-42-feat-x", created=None, idle_outcome=None):
    cur.execute(
        "insert into session_v2 (id, project_id, slug, directory, title, agent, model,"
        " metadata, time_created, time_updated, time_archived, idle_outcome)"
        " values (?,?,?,?,?,?,?,?,?,?,?,?)",
        (sid, "proj", slug, directory, title, agent, model,
         json.dumps(metadata) if metadata is not None else None,
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
    # one session per verdict class, in the fixed vocabulary's order
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
if want n1; then
  [ -f "$AUDIT" ] \
    || fail "N1[C03a AC2]: $AUDIT does not exist — the audit script is C03a's first task (designed red before C03a dev, not a harness fault)"
  python3 "$TMP/mkstore.py" all "$TMP/store-all.db" || fail "harness: fixture builder failed (report, do not blame dev)"
  if ! run_audit "$TMP/store-all.db" n1; then
    fail "N1[C03a AC2]: the audit run over the fixture store failed (reason above) — the script must classify a fixture store through --db"
  fi
  if ! python3 - "$TMP/n1.json" <<'PY'
import json, sys
WANT = {
    "ses_marked_arch": "marked-archived",
    "ses_marked_unarch": "marked-unarchived",
    "ses_unmarked_arch": "unmarked-archived",
    "ses_gate_stop": "gate-stop",
    "ses_abnormal": "abnormal-end",
    "ses_mcp_absent": "mcp-surface-absent",
    "ses_did_work": "did-work",
}
try:
    rows = json.load(open(sys.argv[1]))
except Exception as exc:
    print(f"--json is not the pinned JSON array: {exc}"); sys.exit(1)
if not isinstance(rows, list):
    print(f"--json must print a JSON array, got {type(rows).__name__}"); sys.exit(1)
got = {r.get("id"): r for r in rows}
for sid, verdict in WANT.items():
    row = got.get(sid)
    if row is None:
        print(f"fixture session {sid} is missing from the output (every session in the window gets exactly one row)"); sys.exit(1)
    if row.get("verdict") != verdict:
        print(f"{sid}: verdict {row.get('verdict')!r}, want {verdict!r} — the fixed vocabulary is machine-derived, not a guess"); sys.exit(1)
    for key in ("verdict", "archived", "kind", "title", "excerpt"):
        if key not in row:
            print(f"{sid}: row lacks the pinned key {key!r}: {json.dumps(row)[:200]}"); sys.exit(1)
extra = sorted(set(got) - set(WANT))
if extra:
    print(f"the fixture emitted rows outside the seeded sessions: {extra}"); sys.exit(1)
classes = [r.get("verdict") for r in rows]
bad = [c for c in classes if c not in set(WANT.values())]
if bad:
    print(f"verdict(s) outside the fixed vocabulary: {bad}"); sys.exit(1)
print("ok")
PY
  then fail "N1[C03a AC2]: the classification leg failed (reason above)"; fi
  ok "N1[C03a AC2]: each fixture session lands in exactly one verdict class, all seven derived, every row carries the pinned keys"
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
    r"execute\(|subprocess\.(run|Popen)\(\s*[\"']opencode": "shelling out to the opencode CLI from a diagnostic",
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
  # Control: a fabricated copy that PATCHes a session must be caught.
  python3 - "$AUDIT" "$TMP/audit-write.sh" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
open(sys.argv[2], "w", encoding="utf-8").write(t + "\n# control\nopencode api patch --session \"$SID\" '{\"archived\": true}'\n")
PY
  python3 "$TMP/readonly.py" "$TMP/audit-write.sh" >/dev/null 2>&1 \
    && fail "N2 control: a copy of the audit that PATCHes a session passed the read-only posture check — the check is vacuous"
  ok "N2[C03a AC3]: the audit script opens the store read-only and carries no session, board, or lock write (fabricated-PATCH control proves the check bites)"
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
  python3 "$TMP/mkstore.py" late "$TMP/store-late.db" || fail "harness: late-session fixture build failed"
  if ! run_audit "$TMP/store-late.db" n4late; then
    fail "N4[C03a AC1]: audit run over the late-session fixture failed (reason above)"
  fi
  python3 - "$TMP/store-all.db" "$TMP/n1.json" "$TMP/n4late.json" <<'PY' || fail "N4[C03a AC1]: the newer-session control failed (reason above)"
import json, sys
base = {r["id"]: r["verdict"] for r in json.load(open(sys.argv[2]))}
late = {r["id"]: r for r in json.load(open(sys.argv[3]))}
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
