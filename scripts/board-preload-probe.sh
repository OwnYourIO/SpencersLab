#!/usr/bin/env bash
# board-preload-probe.sh — the AGENT-OWNED live-fire capability for the
# board-context prefetch (2026/2026-10-chore-board-tick-cleanup, C03 T2,
# OQ-N1 grant approved 2026-10-29). The coord runs it at T4 to collect the
# proof citation the enable gate requires; it is invoked ONLY argument-bearing
# (`all` or leg names) because the spaced grant literal
# `bash scripts/board-preload-probe.sh *` cannot match a zero-arg command line
# — a zero-arg call is refused with `PROBE: usage fail` and exit 2.
#
# Legs (the C03 runbook; LF3 has no live leg here — its proof is the shipped
# offline arms, and LF6 is pinned degraded, not run):
#   LF1  command-shape tick prompt on a worktree-rooted standalone instance:
#        the persisted first prompt must carry the injected Board context block
#        and the probe session must not have issued a structural dev-boards read.
#   LF2  the loop-body tick sentence (plus a zero-write probe wrapper) through
#        the same door: injection present. A skip while LF1 fired is the OQ-a
#        finding the runbook says to escalate, never a silent enable.
#   LF4  manual-shape writer leg on the background service: a session the
#        script creates and pre-seeds with an `openchamber.probeSentinel`
#        sibling, then prompts to execute only the boards skill's no-op-marker
#        recipe (the marker contract's homes stay the skill and the reader;
#        the prompt also carries the shell-matcher law and an ACK-on-record
#        precondition — FAIL-212124's non-compliance lesson). PASS = metadata.pipelineNoop well-formed AND the sentinel
#        still present (read-merge-write proven live).
#   LF5  derived from LF4's record: succeeded + scheduled-kind absent +
#        well-formed marker ⇒ the branch reader's conjunction must alert; the
#        push itself is confirmed by the user on the phone.
#   LF6  deterministic `degraded` verdict: the full scheduled-side silence leg
#        cannot be pre-merge proven from a worktree (OpenChamber stamps
#        kind:"scheduled" and the shared server loads main-checkout plugins
#        until merge) — the approved OQ-N2 ceiling: C02's unit matrix pins the
#        conjunction both directions, the first post-merge hourly fire is the
#        optional belt.
#   LF7  budget watch over the LF1/LF2 evidence of the same run: fail-loud if
#        a launched instance logged a FETCH_TIMEOUT_MS budget breach or a
#        degrade line, fail if the structural legs left no evidence to watch.
#   LF8  preload payload (cf-106 C06): the deployed preload_board answer carries
#        the checklist state (items with their finished flag) and the
#        swimlane/list titles — the claim-time per-card fan-out stays dead.
#   LF9  swimlane_titles (cf-106 C06): the filter bound is accepted and answers
#        exactly the named swimlane.
#        LF8/LF9 answer `degraded` when the deployed image predates the preload
#        surface (today's pin is wekan-mcp :v87, 26 tools); they are NOT part of
#        `all` — the board-context citation run must not go red on an image pin
#        the owner has not bumped yet.
#
# Launch topology (the location reality the chunk records): LF1/LF2/LF7 prove
# the BRANCH code through `opencode run --standalone` from this worktree, so
# the private instance loads this checkout's location plugins. LF4/LF5 run on
# the background service because the writer is the agent following the skill
# (grant `opencode api get/patch` reaching its own instance) and the runbook's
# readback channel is `opencode api get /api/session/<id>`; no branch location
# plugin is in that leg's path. Standalone sessions persist to the shared
# project storage and read back through the same API.
#
# Verdict contract: every leg answers exactly one machine-checkable line,
# `PROBE: <leg> pass|fail` (LF6 additionally has its sanctioned `degraded`
# token); anything unrecognizable resolves to fail, never a silent pass.
# Evidence lines (`evidence:`) and per-leg artifact files under
# /tmp/opencode/board-preload-probe/<stamp>/ carry what the citation quotes.
#
# Side effects: probe sessions are throwaway top-level `agent-board-coord`
# runs titled board-preload-probe-<leg>-* (zero claims, zero board writes —
# they never touch a real card; LF8/LF9 only ever call read tools). Every probe
# run that finishes successfully produces an "OpenCode: agent-board-coord
# finished" push from the question plugin of the instance that served it
# (manual shape keeps alerting — LF5's safe direction), so expect one per
# successful LF1/LF2/LF4/LF8/LF9 leg, with LF4's the pre-announced LF5 test push.

set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
cd "$ROOT_DIR"

SCRIPT_NAME="board-preload-probe.sh"
INJECT_HEADER="Board context (collected"
# The prefetch's structural surface (RESEARCH W1 F4): a board-coord first turn
# reading any of these consumed what the injection was supposed to spare.
STRUCTURAL_TOOLS="list_boards get_board list_lists list_swimlanes list_custom_fields"
# The cf-106 C06 payload legs (LF8/LF9) probe the deployed dev-boards answer,
# so the claim-time fan-out they are supposed to kill has a live-fire answer.
PRELOAD_TOOL="preload_board"
PROMPT_TIMEOUT=900
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RUN_DIR="/tmp/opencode/board-preload-probe/$STAMP"
mkdir -p "$RUN_DIR"

OVERALL=0

usage() {
  printf 'usage: bash scripts/%s all | bash scripts/%s <leg>...   (legs: lf1 lf2 lf3 lf4 lf5 lf6 lf7, plus lf8 lf9 which `all` excludes until the owner bumps the image pin)\n' \
    "$SCRIPT_NAME" "$SCRIPT_NAME"
}

verdict() { printf 'PROBE: %s %s\n' "$1" "$2"; }
ev() { printf 'evidence: %s\n' "$*"; }

fail_leg() { verdict "$1" fail; ev "$1: $2"; OVERALL=1; }

# The zero-arg refusal is the grant-shape law (DECISIONS 2026-10-29 coord
# adjudication 1), not a convenience: it must be deterministic and loud.
if [ "$#" -eq 0 ]; then
  usage >&2
  verdict usage fail
  ev "zero-arg call: the spaced allow literal never matches it; always pass 'all' or leg names"
  exit 2
fi

LEGS=()
for arg in "$@"; do
  lc=$(printf '%s' "$arg" | tr 'A-Z' 'a-z')
  case "$lc" in
    all) LEGS=(lf1 lf2 lf4 lf5 lf6 lf7) ;;
    lf1|lf2|lf3|lf4|lf5|lf6|lf7) LEGS+=("$lc") ;;
    # lf8/lf9 read the deployed payload, so they answer against the owner's
    # image pin; excluded from `all` (the board-context citation stays green
    # while the pin still predates the preload surface).
    lf8|lf9) LEGS+=("$lc") ;;
    *)
      usage >&2
      verdict usage fail
      ev "unknown argument '$arg'"
      exit 2
      ;;
  esac
done

new_sid() { printf 'ses_bpp%s%s%s\n' "$1" "$(date -u +%Y%m%d%H%M%S)" "$$"; }

# launch_standalone <leg> <prompt>: fresh worktree-rooted private instance,
# explicit session id so the readback target is known without parsing events.
# stdout is the sid channel only — diagnostics go to stderr or the captured
# lines would poison the command substitution.
launch_standalone() {
  local leg="$1" prompt="$2"
  local sid jsonf logsf
  sid=$(new_sid "$leg")
  jsonf="$RUN_DIR/$leg-run.json"
  logsf="$RUN_DIR/$leg-logs.txt"
  if ! timeout "$PROMPT_TIMEOUT" opencode run --standalone --print-logs --format json \
      --session "$sid" --agent agent-board-coord --title "board-preload-probe-$leg-$STAMP" \
      "$prompt" >"$jsonf" 2>"$logsf"; then
    printf 'evidence: %s: launched run exited nonzero (see %s)\n' "$leg" "$logsf" >&2
  fi
  printf '%s\n' "$sid"
}

# launch_background <leg> <sid> <prompt>: continue a pre-created background-
# service session (its location was stamped at creation), no private instance —
# the writer leg needs the agent's own `opencode api` rows to reach its instance.
launch_background() {
  local leg="$1" sid="$2" prompt="$3"
  local jsonf logsf
  jsonf="$RUN_DIR/$leg-run.json"
  logsf="$RUN_DIR/$leg-logs.txt"
  if ! timeout "$PROMPT_TIMEOUT" opencode run --session "$sid" \
      --agent agent-board-coord "$prompt" >"$jsonf" 2>"$logsf"; then
    ev "$leg: background run exited nonzero (see $logsf)"
    return 1
  fi
  return 0
}

fetch_context() {
  local sid="$1" out="$2"
  opencode api get "/api/session/$sid/context" >"$out" 2>"$out.err" || return 1
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$out" 2>/dev/null
}

fetch_record() {
  local sid="$1" out="$2"
  opencode api get "/api/session/$sid" >"$out" 2>"$out.err" || return 1
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$out" 2>/dev/null
}

ctx_injected() {
  python3 - "$1" "$INJECT_HEADER" <<'PY'
import json, sys
items = json.load(open(sys.argv[1])).get("data") or []
users = [i for i in items if i.get("type") == "user"]
sys.exit(0 if users and sys.argv[2] in (users[0].get("text") or "") else 1)
PY
}

ctx_structural() {
  python3 - "$1" "$STRUCTURAL_TOOLS" <<'PY'
import json, sys
items = json.load(open(sys.argv[1])).get("data") or []
want = set(sys.argv[2].split())
seen = []
for i in items:
    if i.get("type") != "assistant":
        continue
    for part in i.get("content") or []:
        if part.get("type") == "tool" and part.get("name") in want:
            seen.append(part["name"])
print(",".join(dict.fromkeys(seen)))
PY
}

# Full tool-call audit (name:status pairs) — the FAIL-212124 lesson: when a
# writer leg misses, the verdict must say whether the session was refused
# (permission wall mid-recipe) or never attempted, without a manual /context
# read afterwards.
ctx_tool_audit() {
  python3 - "$1" <<'PY'
import json, sys
items = json.load(open(sys.argv[1])).get("data") or []
seen = []
for i in items:
    if i.get("type") != "assistant":
        continue
    for part in i.get("content") or []:
        if part.get("type") == "tool":
            st = (part.get("state") or {}).get("status") or "?"
            seen.append(f"{part.get('name')}:{st}")
print(",".join(seen))
PY
}

# One line per call of <tool> in the session: status<TAB>input-JSON<TAB>answer
# text. The LF8/LF9 legs read what the deployed dev-boards server actually
# answered — the payload shape is the point, so the answer text is carried
# verbatim instead of being reduced to a status token.
ctx_tool_calls() {
  python3 - "$1" "$2" <<'PY'
import json, sys
items = json.load(open(sys.argv[1])).get("data") or []
name = sys.argv[2]
for i in items:
    if i.get("type") != "assistant":
        continue
    for part in i.get("content") or []:
        if part.get("type") != "tool" or part.get("name") != name:
            continue
        st = part.get("state") or {}
        texts = [c.get("text") or "" for c in (st.get("content") or [])
                 if isinstance(c, dict)]
        answer = "\n".join(texts)
        if st.get("error"):
            answer += "\n" + json.dumps(st["error"])
        print("\t".join([
            str(st.get("status") or "?"),
            json.dumps(st.get("input") or {}),
            answer.replace("\n", " "),
        ]))
PY
}

rec_shape() {
  # one line: outcome|kind|noopReason|noopAtType|sentinel. noopReason is the
  # RAW value only when it is a non-empty string; otherwise "" (absent),
  # "nonobj" (not an object) or "badtype" — the reader's well-formedness
  # vocabulary, so the verdict arms fail on any non-value token.
  python3 - "$1" <<'PY'
import json, sys
s = (json.load(open(sys.argv[1])).get("data") or {})
meta = s.get("metadata") or {}
oc = meta.get("openchamber") or {}
noop = meta.get("pipelineNoop")
if isinstance(noop, dict):
    reason = noop.get("reason")
    reason = reason if isinstance(reason, str) and reason else "badtype"
    attype = type(noop.get("at")).__name__
elif noop is None:
    reason, attype = "", ""
else:
    reason, attype = "nonobj", ""
print("|".join([
    str(s.get("outcome") or ""),
    str(oc.get("kind") or ""),
    reason,
    attype,
    "keepme" if oc.get("probeSentinel") == "keepme" else "",
]))
PY
}

# The marker token is well-formed iff rec_shape emitted a real reason string.
noop_ok() {
  case "$1" in
    "" | nonobj | badtype) return 1 ;;
    *) return 0 ;;
  esac
}

run_lf1() {
  local prompt sid ctxf
  prompt="Run the hourly scheduled AI-Dev board tick. PROBE WRAPPER (leg LF1, capability probe, not a real run): do not run the gate script, do not claim or move or read any board card, call no board or MCP tool, launch no subagent, rename or patch no session, edit no file — reply with exactly: PROBE-ACK"
  sid=$(launch_standalone lf1 "$prompt")
  ctxf="$RUN_DIR/lf1-context.json"
  if ! fetch_context "$sid" "$ctxf"; then
    fail_leg LF1 "session $sid first-prompt context unreadable — no admission evidence"
    LF1_EVID=0; return 0
  fi
  ev "LF1: session $sid, context saved to $ctxf, instance logs at $RUN_DIR/lf1-logs.txt"
  if ! ctx_injected "$ctxf"; then
    fail_leg LF1 "first prompt carries no '$INJECT_HEADER …' block — command-path admission door did not run the hook"
    LF1_EVID=0; return 0
  fi
  local structs
  structs=$(ctx_structural "$ctxf")
  if [ -n "$structs" ]; then
    fail_leg LF1 "injected, but the run still made structural dev-boards reads ($structs) — prefetch not effective"
    LF1_EVID=0; return 0
  fi
  verdict LF1 pass
  ev "LF1: injection present, zero structural reads, budget watch fed by $RUN_DIR/lf1-logs.txt"
  LF1_EVID=1
}

run_lf2() {
  local prompt sid ctxf
  prompt="Load the boards skill and run exactly one Parallel pipeline loops iteration. First call pipeline_status, then follow the skill. PROBE WRAPPER (leg LF2, loop-shape plain text, capability probe not a real tick): claim nothing, write nothing anywhere, launch no subagent — after the first turn reply with exactly: PROBE-ACK"
  sid=$(launch_standalone lf2 "$prompt")
  ctxf="$RUN_DIR/lf2-context.json"
  if ! fetch_context "$sid" "$ctxf"; then
    fail_leg LF2 "session $sid first-prompt context unreadable"
    LF2_EVID=0; return 0
  fi
  ev "LF2: session $sid (loop-body sentence + zero-write wrapper), context saved to $ctxf"
  if ! ctx_injected "$ctxf"; then
    fail_leg LF2 "loop-shape plain-text prompt did not receive the injection — OQ-a finding: escalate the loop-body swap decision, do not ship a command-path-only enable"
    LF2_EVID=0; return 0
  fi
  verdict LF2 pass
  ev "LF2: injection present through the plain-text loop door; tool audit at $RUN_DIR/lf2-logs.txt"
  LF2_EVID=1
}

run_lf3() {
  fail_leg LF3 "no live leg from the pipeline: the degrade proof needs breaking the dev-boards MCP config (ask-gated file, optional user-side leg only); the shipped offline arms are the primary proof and run under tests/opencode/board-context.test.ts"
}

run_lf4() {
  local sid prompt recf fields outcome kind reason attype sentinel
  LF4_REC=""
  LF4_RAN=1
  if ! opencode api post /api/session \
      -d "{\"title\":\"board-preload-probe-lf4-$STAMP\",\"location\":{\"directory\":\"$ROOT_DIR\"}}" \
      >"$RUN_DIR/lf4-create.json" 2>&1; then
    fail_leg LF4 "session creation on the background service failed (see $RUN_DIR/lf4-create.json)"
    return 0
  fi
  sid=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["data"]["id"])' \
        "$RUN_DIR/lf4-create.json" 2>/dev/null) || sid=""
  if [ -z "$sid" ]; then
    fail_leg LF4 "session-create answer carried no id (see $RUN_DIR/lf4-create.json)"
    return 0
  fi
  ev "LF4: created background session $sid at location $ROOT_DIR"
  # The sentinel sibling makes the read-merge-write proof non-vacuous: a
  # write-through that loses it did not merge the current full metadata.
  if ! opencode api patch "/api/session/$sid" \
      -d '{"metadata":{"openchamber":{"probeSentinel":"keepme"}}}' \
      >"$RUN_DIR/lf4-seed.json" 2>&1; then
    fail_leg LF4 "sentinel pre-seed failed (see $RUN_DIR/lf4-seed.json)"
    return 0
  fi
  # The pointer-only design (header) widens to the matcher's literal law on
  # evidence: FAIL-212124 wrapped 'cd … && opencode api … | head', the
  # whole-command allow refused it, and the run ACKed without ever patching
  # instead of retrying bare. The marker contract itself stays in the skill.
  prompt="PROBE (leg LF4, manual-shape writer, capability probe not a board run): zero pipeline_claim attempts, zero board reads, zero board writes, no worktree, no subagent, no file edits. Load the boards skill and execute exactly one step: its 'No-op marker (alert suppression)' recipe against your own session record, reason no-cards. Matcher law: the family's shell allows are whole-command patterns starting 'opencode api get /api/session' and 'opencode api patch /api/session/' — the '-d' payload is allowed, but no chain operator, pipe or redirect anywhere in the command (a 'cd … && opencode api … | head' wrapper matches nothing and is refused). Your first shell call is the recipe's bare get. If any shell call is refused, the very next call is that same command stripped to start at 'opencode api' — no Code Mode search, no MCP shim, nothing else in between. Reply PROBE-ACK only after a final bare get shows metadata.pipelineNoop with a non-empty reason and openchamber.probeSentinel still present; if the marker never lands, report that plainly instead — the leg's verdict reads the record, not your reply. This leg proves exactly that the coord family's own opencode api rows reach its session record."
  if ! launch_background lf4 "$sid" "$prompt"; then
    ev "LF4: continuing despite the nonzero run — the record readback is the verdict source"
  fi
  recf="$RUN_DIR/lf4-record.json"
  if ! fetch_record "$sid" "$recf"; then
    fail_leg LF4 "session $sid record unreadable after the writer run"
    return 0
  fi
  # Attempt-shape audit (evidence only — the record stays the verdict source):
  # a refused shell call reads as shell:error here, an unattempted recipe as an
  # empty audit line.
  local audit="unreadable"
  if fetch_context "$sid" "$RUN_DIR/lf4-context.json"; then
    audit=$(ctx_tool_audit "$RUN_DIR/lf4-context.json")
  fi
  ev "LF4: session $sid, record saved to $recf, tool audit = [$audit]"
  LF4_REC="$recf"
  fields=$(rec_shape "$recf")
  IFS='|' read -r outcome kind reason attype sentinel <<<"$fields"
  if ! noop_ok "$reason"; then
    fail_leg LF4 "metadata.pipelineNoop missing or malformed after the writer run (reason token '$reason')"
    return 0
  fi
  if [ "$sentinel" != "keepme" ]; then
    fail_leg LF4 "openchamber.probeSentinel lost — the marker write was not a read-merge-write of the full metadata"
    return 0
  fi
  verdict LF4 pass
  ev "LF4: marker reason '$reason' (at type $attype), sentinel sibling intact, kind='$kind'"
}

run_lf5() {
  local recf="${LF4_REC:-}" fields outcome kind reason attype sentinel
  if [ -z "$recf" ]; then
    # Standalone lf5 mints its own LF4 evidence — but only if lf4 never ran
    # in this invocation (a failed lf4 must not double-mint sessions/pushes).
    [ "${LF4_RAN:-0}" -eq 1 ] && { fail_leg LF5 "LF4 ran but left no readable record — see LF4 verdict"; return 0; }
    run_lf4
    recf="${LF4_REC:-}"
    [ -n "$recf" ] || { fail_leg LF5 "no LF4 evidence to derive the alert-direction proof from"; return 0; }
  fi
  fields=$(rec_shape "$recf")
  IFS='|' read -r outcome kind reason attype sentinel <<<"$fields"
  ev "LF5: from LF4 record — outcome=$outcome kind='$kind' noopReason='$reason' sentinel=$sentinel"
  if [ "$outcome" != "succeeded" ]; then
    fail_leg LF5 "LF4 session did not end succeeded (outcome='$outcome') — the finished-push condition never arose"
    return 0
  fi
  if [ "$kind" = "scheduled" ]; then
    fail_leg LF5 "LF4 record carries kind=scheduled — the manual-shape precondition broken, conjunction result meaningless"
    return 0
  fi
  if ! noop_ok "$reason" || [ "$sentinel" != "keepme" ]; then
    fail_leg LF5 "LF4 marker/sibling state not proven (see LF4 verdict)"
    return 0
  fi
  verdict LF5 pass
  ev "LF5: manual shape + well-formed marker ⇒ reader conjunction keeps alerting (C02 T10 pins the direction; the unit arms are the code-side proof)"
  ev "LF5: HUMAN leg — the user confirms exactly one 'OpenCode: agent-board-coord finished' push for the LF4 session arrived on the phone"
}

run_lf6() {
  verdict LF6 degraded
  ev "LF6: pre-merge ceiling (OQ-N2 approved 2026-10-29): kind:'scheduled' is stamped by OpenChamber's own scheduler and the shared server loads main-checkout plugins until merge, so the full scheduled-side silence leg is unit-pinned by C02's both-direction matrix (T9/T10) — the first post-merge real hourly fire is the optional user-side belt"
}

# The `degraded` token is only for a confirmed absent surface: the deployed
# wekan-mcp pin (v87 today) has no preload_board at all, so the enrichment
# cannot be judged from it. Anything else that is not the documented payload
# answers fail.
preload_absent() {
  grep -qiE 'not found|no such tool|invalid tool|died unexpectedly' "$1"
}

# LF8 verdict: `ok` when the answer carries checklist items with their finished
# flag plus the swimlane/list titles; `thin` when the payload is there but a
# part of the enrichment is missing (the claim would still fan out per card);
# `err` when the call itself failed.
lf8_shape() {
  python3 - "$1" <<'PY'
import json, sys
answer = open(sys.argv[1]).read().strip()
try:
    doc = json.loads(answer)
except ValueError:
    print("err|" + answer[:160])
    raise SystemExit(0)
if not isinstance(doc, dict) or "swimlanes" not in doc:
    print("err|" + answer[:160])
    raise SystemExit(0)
cards = [c for g in doc.get("swimlanes") or [] for l in g.get("lists") or []
         for c in l.get("cards") or []]
cl = [c["checklists"] for c in cards if c.get("checklists")]
items = [i for group in cl for i in group if i.get("items")]
flags = all(isinstance(i.get("finished"), bool)
            for group in cl for ch in group for i in ch.get("items") or [])
lanes = doc.get("swimlanes") or []
# The id-less tail group (unresolved parents) has no title by contract, so only
# rows with a real id are held to the title rule.
unnamed = [g.get("id") for g in lanes if g.get("id") and not g.get("title")]
unnamed += [l.get("id") for g in lanes for l in (g.get("lists") or [])
            if l.get("id") and not l.get("title")]
missing = []
if not cl:
    missing.append("no checklists section")
if not items:
    missing.append("no checklist items")
elif not flags:
    missing.append("items without a boolean finished flag")
if unnamed:
    missing.append(f"titled-group contract broken for {unnamed[:3]}")
if not cards:
    missing.append("no cards in the grouping")
if missing:
    print("thin|" + "; ".join(missing))
else:
    print(f"ok|{len(cards)} cards, {len(cl)} with checklists, "
          f"{len(lanes)} swimlanes")
PY
}

run_lf8() {
  local prompt sid ctxf callsf lastf shape token detail
  prompt="Load the boards skill. PROBE WRAPPER (leg LF8, payload capability probe, not a board run): claim nothing, move nothing, write nothing, launch no subagent, edit no file. Make exactly two dev-boards MCP calls: list_boards, then preload_board for the AI-Dev board id. Reply with exactly: PROBE-ACK"
  sid=$(launch_standalone lf8 "$prompt")
  ctxf="$RUN_DIR/lf8-context.json"
  if ! fetch_context "$sid" "$ctxf"; then
    fail_leg LF8 "session $sid context unreadable — no payload evidence"
    return 0
  fi
  callsf="$RUN_DIR/lf8-preload-calls.txt"
  ctx_tool_calls "$ctxf" "$PRELOAD_TOOL" >"$callsf"
  if [ ! -s "$callsf" ]; then
    fail_leg LF8 "session $sid never called preload_board — wrapper non-compliance, payload never fetched"
    return 0
  fi
  ev "LF8: session $sid, preload_board calls: $(cut -f1 "$callsf" | paste -sd, -), context saved to $ctxf"
  lastf="$RUN_DIR/lf8-last-answer.txt"
  tail -n1 "$callsf" | cut -f3 >"$lastf"
  if preload_absent "$lastf"; then
    verdict LF8 degraded
    ev "LF8: the deployed dev-boards answer is not a preload payload ($(head -c 160 "$lastf")) — image pin predates the preload surface; re-run after the owner's bump"
    return 0
  fi
  shape=$(lf8_shape "$lastf")
  token="${shape%%|*}"; detail="${shape#*|}"
  case "$token" in
    ok)
      verdict LF8 pass
      ev "LF8: payload carries the checklist state with finished flags and the swimlane/list titles — $detail (claim-time fan-out stays dead)"
      ;;
    thin) fail_leg LF8 "preload answer is missing enrichment: $detail" ;;
    *) fail_leg LF8 "preload answer unparseable: $detail" ;;
  esac
}

run_lf9() {
  local prompt sid ctxf callsf token detail
  prompt="Load the boards skill. PROBE WRAPPER (leg LF9, filter capability probe, not a board run): claim nothing, move nothing, write nothing, launch no subagent, edit no file. Make exactly three dev-boards MCP calls: list_boards; preload_board for the AI-Dev board id (read one swimlane title from its answer); preload_board again for the same board with swimlane_titles set to exactly that one title. Reply with exactly: PROBE-ACK"
  sid=$(launch_standalone lf9 "$prompt")
  ctxf="$RUN_DIR/lf9-context.json"
  if ! fetch_context "$sid" "$ctxf"; then
    fail_leg LF9 "session $sid context unreadable — no filter evidence"
    return 0
  fi
  callsf="$RUN_DIR/lf9-preload-calls.txt"
  ctx_tool_calls "$ctxf" "$PRELOAD_TOOL" >"$callsf"
  if [ ! -s "$callsf" ]; then
    fail_leg LF9 "session $sid never called preload_board — wrapper non-compliance"
    return 0
  fi
  if ! grep -q 'swimlane_titles' "$callsf"; then
    fail_leg LF9 "no preload_board call carried a swimlane_titles argument — the filter bound was never exercised"
    return 0
  fi
  ev "LF9: session $sid, filtered call inputs: $(grep -o 'swimlane_titles[^}]*' "$callsf" | head -3 | paste -sd' | ' -)"
  local filtered="$RUN_DIR/lf9-filtered-answer.txt"
  grep 'swimlane_titles' "$callsf" | tail -n1 | cut -f3 >"$filtered"
  if preload_absent "$filtered"; then
    verdict LF9 degraded
    ev "LF9: the deployed server never accepted the call ($(head -c 160 "$filtered")) — image pin predates the preload surface"
    return 0
  fi
  shape=$(python3 - "$callsf" "$filtered" <<'PY'
import json, sys
wanted, answer = None, open(sys.argv[2]).read()
for line in open(sys.argv[1]):
    parts = (line.rstrip("\n").split("\t") + ["", "", ""])[:3]
    try:
        args = json.loads(parts[1])
    except ValueError:
        continue
    if args.get("swimlane_titles"):
        wanted = args["swimlane_titles"]
if wanted is None:
    print("err|no call carried swimlane_titles")
    raise SystemExit(0)
try:
    doc = json.loads(answer)
except ValueError:
    print("err|" + answer[:160])
    raise SystemExit(0)
if not isinstance(doc, dict) or "swimlanes" not in doc:
    print("err|" + answer[:160])
    raise SystemExit(0)
got = [g.get("title") for g in doc.get("swimlanes") or []]
if not got:
    print(f"empty|{wanted}")
elif sorted(got) != sorted(wanted):
    print(f"widened|{got} vs {wanted}")
else:
    print(f"ok|{got}")
PY
)
  token="${shape%%|*}"; detail="${shape#*|}"
  case "$token" in
    ok)
      verdict LF9 pass
      ev "LF9: the swimlane_titles bound is accepted and answers exactly the named swimlane — $detail"
      ;;
    empty) fail_leg LF9 "the filtered call answered no swimlanes for $detail — an unmatched title is documented as swimlanes: [], so the probe's title did not exist or the filter over-narrowed" ;;
    widened) fail_leg LF9 "the filtered answer is not confined to the named swimlane: $detail" ;;
    *) fail_leg LF9 "filtered answer unparseable: $detail" ;;
  esac
}

run_lf7() {
  local hit=0 line
  local logs=(lf1 lf2)
  local l f
  for l in "${logs[@]}"; do
    f="$RUN_DIR/$l-logs.txt"
    [ -f "$f" ] || continue
    hit=1
    if grep -qE 'board fetch exceeded the|prompt left untouched|prompt hook degraded' "$f"; then
      line=$(grep -m1 -E 'board fetch exceeded the|prompt left untouched|prompt hook degraded' "$f")
      fail_leg LF7 "$l logs carry a budget/degrade line: $line"
      return 0
    fi
  done
  if [ "$hit" -eq 0 ]; then
    fail_leg LF7 "no LF1/LF2 evidence in this run ($RUN_DIR) — run lf7 together with lf1/lf2 (or all)"
    return 0
  fi
  if [ "${LF1_EVID:-0}" -ne 1 ] && [ "${LF2_EVID:-0}" -ne 1 ]; then
    fail_leg LF7 "neither structural leg passed, so its admission latency was never exercised — fix LF1/LF2 first"
    return 0
  fi
  verdict LF7 pass
  ev "LF7: no FETCH_TIMEOUT_MS (8000 ms) breach or degrade stderr in the launched-instance logs; run wall-times in $RUN_DIR/lf*-run.json timestamps"
}

printf 'board-preload-probe: run dir %s (evidence kept for the citation)\n' "$RUN_DIR"

for leg in "${LEGS[@]}"; do
  case "$leg" in
    lf1) run_lf1 ;;
    lf2) run_lf2 ;;
    lf3) run_lf3 ;;
    lf4) run_lf4 ;;
    # lf5 reuses LF4's record when the same invocation ran lf4 first (the
    # `all` order); standalone it triggers lf4 via the empty-rec fallback.
    lf5) run_lf5 ;;
    lf6) run_lf6 ;;
    lf7) run_lf7 ;;
    lf8) run_lf8 ;;
    lf9) run_lf9 ;;
  esac
done

if [ "$OVERALL" -ne 0 ]; then
  exit 1
fi
exit 0
