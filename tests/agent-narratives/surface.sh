#!/usr/bin/env bash
# cf-126 C06 — the agent-definition narrative arms (round-3 direction, D35/D36).
#
# Homes the per-body narrative law: every in-scope .rulesync/subagents source
# (16 pipeline family + 9 standalone family) ends with ONE appended
# `## Compaction & fresh-start` section; role shape per the C06 scope
# decisions; frontmatter + existing bytes immovable (append-only law); the
# doctrine HOMES stay the skills (the single-authority needle forbids restated
# mechanics); the 9 standalone sections carry the generic wording only (no
# pipeline vocabulary, no bare /name lines, no /pipeline line — S7's law by
# construction); the OUT roster stays byte-frozen; THE ARTIFACT line is pinned
# verbatim in the plan's Round-3 section (drift there needs a re-ruling, the
# settled-constant law).
#
# AC trace: N1[C06 AC1 presence, 50 files] N2[AC1 template legs]
# N3[AC1 role differentiation] N4[AC2 single-authority restatement ban]
# N5[AC1/AC5 generic vocabulary absence + bare-line extractor guard]
# N6[AC3 frontmatter immobility + append-only prefix + twin discipline + the C07 named-line exception]
# N7[AC5 OUT-roster freeze] N8[the artifact-line record pin].
#
# Red posture (C07 re-pin wave): N3's coord-six + dispatcher role windows are
# DESIGNED-RED until C07 dev rewords the windows (the re-ground vocabulary in,
# the retired close-protocol phrases pinned absent); N6's prefix freeze gains
# the ONE C07 named-line exception (the dispatcher's pre-window bullet —
# single-line, keyed to its exact settled-base text, with the
# other-lines-must-not-move controls) — the settled base $BASE stays.
# N1/N2/N4/N5/N7/N8 HOLD at the ledger values (rc=0 bare). Fabricated-drift
# controls (strip, restate, template-swap, bare-line, moving-base,
# single-line-allow mutants) run against mutants and prove every pin
# non-vacuous. The round-2 app surface (.openchamber/project.json + its
# fixture) is validated in tests/openchamber-project/, not here.
#
# Usage:
#   bash tests/agent-narratives/surface.sh            # N1..N8
#   bash tests/agent-narratives/surface.sh N1 N8      # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# cf-126 C06 round-2 (D37 AA3, adopted from the polish round's deviation 2):
# SETTLED chunk-base, not a floating HEAD. The tree against which the narrative
# appends + the round-2 fold-ins are legitimate is the C06 test-wave commit —
# c372d0276 (verified: 25 bodies carry no section there; the dev append 5dfb8736b
# and polish fold-ins 010aa3ca6 are pure appends/inside-section edits above it;
# the OUT roster is byte-identical vs it). HEAD-as-default reddens every future
# SANCTIONED fold-in the moment the base moves (a fold-in edits bytes a moved
# base still carries) — the prefix-freeze law is "immovable vs the CHUNK base".
# Per-recorded-hash pinning follows the settled-constants precedent (C02 review's
# promotion item); the CHUNK_BASE override env stays honored.
BASE="${CHUNK_BASE:-c372d02760adc67e80f8ed66e5030af43307e163}"
PLAN=".agents/plans/2026/2026-11-cf-126-feat-compaction-pipeline-sessions/2026-11-17-feat-compaction-pipeline-sessions.md"

PIPE16=(agent-coord agent-coord-local agent-coord-pr agent-board-coord agent-board-coord-local
        agent-board-coord-pr agent-board-dispatch agent-plan agent-test agent-explore agent-research
        agent-dev-local agent-dev-pr agent-review agent-dev-deploy agent-dev-deploy-pr)
STAND9=(code code-pr dev dev-local dev-pr debug planner ask review)
OUTSRC=(agent-board agent-fuser)
SDLC=(0-pipeline 1-feature-generation 2-dependency-map 3-plan 4-tdd 5-write-code 6-review 7a-docs-user 7b-docs-dev)

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

TMP=$(mktemp -d /tmp/opencode/agent-narratives-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7 8; do WANT["n$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^n[1-8]$ ]] || fail "unknown check id '$a' (expected N1..N8)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

HDR='## Compaction & fresh-start'

cat >"$TMP/extract.py" <<'PY'
# Pull the sanctioned section out of a body file: from its header to EOF.
# Fails (named) when the header is absent, duplicated, or NOT the final
# heading — the shape law is ONE appended section at each body's end.
import re, sys
path, hdr, dst = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(path, encoding="utf-8").read()
hits = [m.start() for m in re.finditer(re.escape(hdr), t)]
if not hits:
    print(f"{path}: no '{hdr}' section (designed red until C06 dev appends it)"); sys.exit(1)
if len(hits) > 1:
    print(f"{path}: '{hdr}' appears {len(hits)} times — exactly ONE section"); sys.exit(1)
sec = t[hits[0]:]
after = sec[len(hdr):]
if re.search(r'^#{1,6} ', after, re.M):
    print(f"{path}: the sanctioned section is not the final heading — append-only means AT THE END"); sys.exit(1)
open(dst, "w", encoding="utf-8").write(sec)
print("ok")
PY

cat >"$TMP/win.py" <<'PY'
# Co-location window over the EXTRACTED section (the sibling suites' win.py,
# section-scoped by construction because the input is the section file).
import sys
argv = sys.argv[1:]
ci = argv[0] == '--ci'
if ci:
    argv = argv[1:]
path, span = argv[0], int(argv[1])
needles = argv[2:]
text = open(path, encoding="utf-8").read()
if ci:
    text = text.lower(); needles = [n.lower() for n in needles]
pts = []
for n in needles:
    i = text.find(n)
    if i < 0:
        print(f'missing needle: {n}'); sys.exit(1)
    pts.append(i)
if max(pts) - min(pts) > span:
    print(f'needles span {max(pts) - min(pts)} > {span} — scattered'); sys.exit(1)
PY

cat >"$TMP/ban.py" <<'PY'
# Banned-token scan over the extracted section (single-authority restatement
# ban, generic-vocabulary absence, bare /name lines). Prints hits; exit 1.
import re, sys
path = sys.argv[1]
mode = sys.argv[2]
args = sys.argv[3:]
text = open(path, encoding="utf-8").read()
if mode == "tokens":
    hits = [t for t in args if t in text]
elif mode == "bare":
    hits = [l for l in text.splitlines() if re.match(r"^\s*/[a-z0-9-]+\s*$", l)]
else:
    print(f"unknown mode {mode}"); sys.exit(2)
print("; ".join(str(h) for h in hits))
sys.exit(1 if hits else 0)
PY

# --- N1: presence, all 25 sources + 25 mirrors (AC1) ----------------------------
if want n1; then
  for n in "${PIPE16[@]}" "${STAND9[@]}"; do
    for f in ".rulesync/subagents/$n.md" ".opencode/agents/$n.md"; do
      [ -f "$f" ] || fail "N1[C06 AC1]: $f missing (harness fault)"
      python3 "$TMP/extract.py" "$f" "$HDR" "$TMP/sec.md" >/dev/null \
        || fail "N1[C06 AC1]: $f lacks the single final '$HDR' section (designed red; source legs flip with the dev append, mirror legs flip with the rulesync regen — the regen is C06 task 3)"
    done
  done
  ok "N1[C06 AC1]: all fifty in-scope surfaces (25 sources + 25 mirrors) carry exactly one '$HDR' section as the final heading; OUT roster + SDLC excluded by roster, frozen in N7"
fi

# --- N2: common template legs every section must name (AC1) ----------------------
if want n2; then
  for n in "${PIPE16[@]}" "${STAND9[@]}"; do
    for f in ".rulesync/subagents/$n.md" ".opencode/agents/$n.md"; do
      python3 "$TMP/extract.py" "$f" "$HDR" "$TMP/sec.md" >/dev/null \
        || fail "N2[C06 AC1]: $f has no section to read the template legs from (N1's stop names it; red by design pre-C06)"
      python3 "$TMP/win.py" --ci "$TMP/sec.md" 1600 'hook' 'pointer' 'read order' 'MUST-load' 'derive' \
        || fail "N2[C06 AC1]: $f's section misses a MUST leg — trigger (the pipeline-locks hook, pointer-shaped summary), fresh-start law (read order + MUST-load skills), or the comply-cite close (never re-derive); the window is the section itself"
    done
  done
  ok "N2[C06 AC1]: every section names the trigger, the fresh-start law and the comply-cite close in one passage"
fi

# --- N3: role differentiation (AC1, the D35 roster) --------------------------------
if want n3; then
  for n in agent-coord agent-coord-local agent-coord-pr agent-board-coord agent-board-coord-local agent-board-coord-pr; do
    f=".rulesync/subagents/$n.md"
    python3 "$TMP/extract.py" "$f" "$HDR" "$TMP/sec.md" >/dev/null \
      || fail "N3[C06 AC1]: $f unreadable for the coord role needle set (designed red pre-C06)"
    python3 "$TMP/win.py" --ci "$TMP/sec.md" 1600 're-ground' 'Context handoff' \
      || fail "N3[C06 AC1 + C07 re-pin]: $f's section omits the coord role story (C07: the next step re-grounds IN THIS session — state current, re-read in read order, MUST-load skills, step boundary; the card and lock stay put) or its Context-handoff cite"
    hits=$(python3 "$TMP/ban.py" "$TMP/sec.md" tokens 'handoff protocol' 'spawn the successor' 'and end' || true)
    [ -z "$hits" ] || fail "N3[cf-126 C07 AC4]: $f's section still carries the retired close-protocol wording ($hits) — the spawn-successor/handoff-close/end protocol is out (designed red pre-landing)"
  done
  for f in .rulesync/subagents/agent-board-dispatch.md; do
    python3 "$TMP/extract.py" "$f" "$HDR" "$TMP/sec.md" >/dev/null \
      || fail "N3[C06 AC1]: $f unreadable (designed red pre-C06)"
    python3 "$TMP/win.py" --ci "$TMP/sec.md" 1600 're-ground' 'marker' 'Dispatcher' \
      || fail "N3[C06 AC1 + C07 re-pin]: the dispatcher narrative omits the in-place re-grounding (loop body + marker + board reads re-consumed at the boundary; the proxy behavior and the card-spawn job stand) or the Dispatcher-section cite"
    hits=$(python3 "$TMP/ban.py" "$TMP/sec.md" tokens 'reset-per-marker' 'spawn a FRESH dispatcher' 'running facts' 'successor' || true)
    [ -z "$hits" ] || fail "N3[cf-126 C07 AC4]: the dispatcher section still carries the retired reset-per-marker spawn-end wording ($hits) — C07 re-grounds in place (designed red pre-landing)"
  done
  for n in agent-plan agent-test agent-explore agent-research; do
    f=".rulesync/subagents/$n.md"
    python3 "$TMP/extract.py" "$f" "$HDR" "$TMP/sec.md" >/dev/null || fail "N3[C06 AC1]: $f unreadable (designed red pre-C06)"
    python3 "$TMP/win.py" --ci "$TMP/sec.md" 1600 'bus' 'fresh' \
      || fail "N3[C06 AC1]: $f omits the relaunch-FRESH posture (launcher decides; files are the bus)"
  done
  for n in agent-dev-local agent-dev-pr; do
    f=".rulesync/subagents/$n.md"
    python3 "$TMP/extract.py" "$f" "$HDR" "$TMP/sec.md" >/dev/null || fail "N3[C06 AC1]: $f unreadable (designed red pre-C06)"
    python3 "$TMP/win.py" --ci "$TMP/sec.md" 1200 'chunk' 'brief' \
      || fail "N3[C06 AC1]: $f omits the chunk-brief bootstrap (chunk file + read order + skills; never re-ask what the brief carries)"
  done
  f=.rulesync/subagents/agent-review.md
  python3 "$TMP/extract.py" "$f" "$HDR" "$TMP/sec.md" >/dev/null || fail "N3[C06 AC1]: $f unreadable (designed red pre-C06)"
  python3 "$TMP/win.py" --ci "$TMP/sec.md" 1200 'chunk' 'test' \
    || fail "N3[C06 AC1]: agent-review omits the re-run-the-chunk-tests-first step cited to the plan contract"
  for n in agent-dev-deploy agent-dev-deploy-pr; do
    f=".rulesync/subagents/$n.md"
    python3 "$TMP/extract.py" "$f" "$HDR" "$TMP/sec.md" >/dev/null || fail "N3[C06 AC1]: $f unreadable (designed red pre-C06)"
    python3 "$TMP/win.py" --ci "$TMP/sec.md" 1200 'card comment' 'notify' \
      || fail "N3[C06 AC1/D18]: $f omits the hand-back story (done or out of context → notify the dispatcher or let the user, leave a card comment — cited, not restated)"
  done
  ok "N3[C06 AC1 + C07 re-pin]: role-by-role narratives land — coord six (re-ground + Context-handoff cite; retired close-protocol wording absent), dispatcher (re-ground + marker + Dispatcher cite; retired spawn-end wording absent), the four relaunch-fresh, the dev pair chunk-brief, review re-run-tests, the deploy pair hand-back"
fi

# --- N4: single-authority — restated mechanics reddens (AC2) -----------------------
if want n4; then
  for n in "${PIPE16[@]}" "${STAND9[@]}"; do
    for f in ".rulesync/subagents/$n.md" ".opencode/agents/$n.md"; do
      python3 "$TMP/extract.py" "$f" "$HDR" "$TMP/sec.md" >/dev/null \
        || fail "N4[C06 AC2]: $f unreadable for the restatement ban (designed red pre-C06)"
      hits=$(python3 "$TMP/ban.py" "$TMP/sec.md" tokens "entry.put" "instructions.entry" "ctx.session" "mutable" "system array" "FRICTION.md" "RESEARCH.md" "EXPLORE.md" || true)
      [ -z "$hits" ] || fail "N4[C06 AC2]: $f's section RESTATES mechanics ($hits) — the doctrine homes (boards Context-handoff, the pipeline-role-* skills, pipeline-conventions) own them; the narrative states consequences and cites, never re-derives (D35's rejected alternative)"
      hits=$(python3 "$TMP/ban.py" "$TMP/sec.md" bare || true)
      [ -z "$hits" ] || fail "N4[C06 AC2]: $f's section carries a bare /name line ($hits) — the MUST-load extractor pattern would ingest it; cite skills INLINE in backticks"
    done
  done
  # Fabricated-drift: a restated-mechanics section and a bare-line section both
  # must redden the SAME shipped scanners (non-vacuity).
  printf '%s\n' "$HDR" "The hook lands instructions.entry.put into the mutable system array; read order: STATE.json, DECISIONS.md, FRICTION.md." '/pipeline-conventions' >"$TMP/restated.md"
  if python3 "$TMP/ban.py" "$TMP/restated.md" tokens "entry.put" "instructions.entry" "ctx.session" "mutable" "system array" "FRICTION.md" "RESEARCH.md" "EXPLORE.md" >/dev/null 2>&1; then
    fail "N4 control: the restated-mechanics mutant passed the ban — the single-authority needle is vacuous"
  fi
  if python3 "$TMP/ban.py" "$TMP/restated.md" bare >/dev/null 2>&1; then
    fail "N4 control: the bare /name line mutant passed the extractor guard — the guard is vacuous"
  fi
  ok "N4[C06 AC2]: no section restates hook/read-order mechanics and none carries a bare /name line; both fabricated mutants redden the shipped scanners"
fi

# --- N5: generic-wording absence for the standalone nine (AC1/AC5) -----------------
if want n5; then
  for n in "${STAND9[@]}"; do
    for f in ".rulesync/subagents/$n.md" ".opencode/agents/$n.md"; do
      python3 "$TMP/extract.py" "$f" "$HDR" "$TMP/sec.md" >/dev/null \
        || fail "N5[C06 AC1]: $f unreadable for the generic-vocabulary scan (designed red pre-C06)"
      hits=$(python3 "$TMP/ban.py" "$TMP/sec.md" tokens "handoff" "pipeline_claim" "Lifecycle" "/pipeline" || true)
      [ -z "$hits" ] || fail "N5[C06 AC1/AC5]: $f's generic section carries pipeline vocabulary ($hits) — the standalone family runs WITHOUT pipeline context; a full-template copy is exactly the drift this rejects (S7's law by construction)"
    done
  done
  # Fabricated drift: the full template copied into code.md's section reddens.
  printf '%s\n' "$HDR" "Release with outcome handoff under the Lifecycle gates; pipeline_claim stays held; /pipeline-resume bootstraps the successor." >"$TMP/full-in-code.md"
  if python3 "$TMP/ban.py" "$TMP/full-in-code.md" tokens "handoff" "pipeline_claim" "Lifecycle" "/pipeline" >/dev/null 2>&1; then
    fail "N5 control: the full-template-copy mutant passed the generic absence — the vocabulary scan is vacuous"
  fi
  ok "N5[C06 AC1/AC5]: the nine standalone sections (sources + mirrors) stay generic — no handoff/pipeline_claim/Lifecycle vocabulary and no /pipeline string anywhere in them; the template-swap mutant reddens"
fi

# --- N6: append-only prefix + twin discipline (AC3; HOLD guard arms; the one C07 named-line exception) ----------------
if want n6; then
  python3 - "$BASE" "$TMP/extract.py" "$HDR" "${PIPE16[@]}" "${STAND9[@]}" <<'PY' || fail "N6[C06 AC3]: the append-only/frontmatter guard reddens (see reason above)"
import subprocess, sys
base, extract, hdr = sys.argv[1], sys.argv[2], sys.argv[3]
names = sys.argv[4:]
def sec_via_extractor(path):
    r = subprocess.run(["python3", extract, path, hdr, "/dev/null"], capture_output=True, text=True)
    return r.returncode == 0
# cf-126 C07: the one designed named-line exception — the dispatcher's
# pre-window bullet (its EXACT settled-base text, whose successor clause C07
# rewords in place; leaving it stale would teach the retired doctrine). Any
# OTHER prefix line moving stays red — the exception is single-line, keyed to
# the bullet's exact base text.
BULLET = "- Your own context stays survivable per the same compaction-pointer contract every pipeline session gets (the successor bootstraps from the plan folders and the board, like any resumed run)."
def check_prefix(old, new, allow_bullet):
    if new.startswith(old):
        return True, ""
    if not allow_bullet:
        return False, "bytes BEFORE the appended section moved"
    ol, nl = old.split("\n"), new.split("\n")
    if len(ol) != len(nl):
        return False, "line count moved — the C07 exception is a same-line reword only"
    diff = [i for i in range(len(ol)) if ol[i] != nl[i]]
    if len(diff) == 1 and ol[diff[0]] == BULLET:
        return True, ""
    return False, f"a prefix line other than the C07-named bullet moved ({len(diff)} lines differ)"
for n in names:
    for rel in (f".rulesync/subagents/{n}.md", f".opencode/agents/{n}.md"):
        old = subprocess.run(["git", "show", f"{base}:{rel}"], capture_output=True, text=True)
        if old.returncode != 0:
            print(f"{rel}: missing at base {base} (harness fault)"); sys.exit(1)
        new = open(rel, encoding="utf-8").read()
        okp, why = check_prefix(old.stdout, new, "agent-board-dispatch" in rel)
        if not okp:
            print(f"{rel}: {why} vs {base} — frontmatter and every existing line are byte-frozen except the C07-named dispatcher bullet (single-line, keyed to its exact base text); only the sanctioned '{hdr}' section may extend the body"); sys.exit(1)
        tail = new[len(old.stdout):].lstrip("\n") if new.startswith(old.stdout) else ""
        if tail and not tail.startswith(hdr):
            print(f"{rel}: the tail appended after base is not the sanctioned section ({tail[:60]!r})"); sys.exit(1)
# self-proof of bite: a mid-edit copy must fail the same prefix logic
if check_prefix("a\nb\n", "a\nX\n", False)[0]:
    print("prefix self-test broken (harness fault)"); sys.exit(1)
# C07 named-line exception control: the SAME shipped checker must admit the
# bullet reword and reject every other prefix movement — both directions, plus
# the non-dispatcher byte-freeze. A one-sided or absent fixture would prove
# the allow vacuous.
doc = "line1\n" + BULLET + "\nline3\n"
reworded = "line1\n" + BULLET.replace("successor bootstraps", "session re-grounds in place") + "\nline3\n"
if not check_prefix(doc, reworded, True)[0]:
    print("C07 exception control broken: the bullet-only reword was rejected (harness fault)"); sys.exit(1)
if check_prefix(doc, "line1-moved\n" + BULLET + "\nline3\n", True)[0]:
    print("C07 exception control broken: the other-line-moved mutant passed — the single-line allow is vacuous"); sys.exit(1)
if check_prefix(doc, "line1-moved\n" + reworded[len("line1\n"):], True)[0]:
    print("C07 exception control broken: the two-lines-moved mutant passed — the single-line allow is vacuous"); sys.exit(1)
if check_prefix(doc, reworded, False)[0]:
    print("C07 exception control broken: a non-dispatcher file took the bullet reword — the byte-freeze is vacuous"); sys.exit(1)
# cf-126 C06 round-2 (D37 AA3) MOVING-BASE drift proof: with BASE floated to
# HEAD, the commit that landed the sections becomes the base, and the NEXT
# sanctioned fold-in (an inside-section edit — legitimate against the settled
# chunk-base) reddens for the prefix reason. Both directions must hold; this is
# the fixture the amendment demands — the drift is caught by THIS arm, for the
# recorded reason, and the settled hash above is what keeps it green.
base_moved = "body\n\n## Compaction & fresh-start\nline1\nline2\n"
fold_in = "body\n\n## Compaction & fresh-start\nline1 folded\nline2\n"
if fold_in.startswith(base_moved):
    print("moving-base self-test broken (harness fault)"); sys.exit(1)
if not (fold_in.startswith("body\n") and fold_in[len("body\n"):].lstrip("\n").startswith("## Compaction & fresh-start")):
    print("settled-base self-test broken (harness fault)"); sys.exit(1)
print("ok")
PY
  # Twin discipline: byte-identical sections for the alias pairs (post-append;
  # inert while neither carries a section — N1 names the designed red).
  for pair in "agent-coord agent-coord-local" "agent-board-coord agent-board-coord-local" "dev dev-local"; do
    set -- $pair
    a=".rulesync/subagents/$1.md"; b=".rulesync/subagents/$2.md"
    ra=$(python3 "$TMP/extract.py" "$a" "$HDR" "$TMP/twinA.md" >/dev/null 2>&1; echo $?)
    rb=$(python3 "$TMP/extract.py" "$b" "$HDR" "$TMP/twinB.md" >/dev/null 2>&1; echo $?)
    [ "$ra" = "$rb" ] || fail "N6[C06 AC3]: twin pair ($1,$2) — one carries the section and the twin does not; twins append in the same commit"
    [ "$ra" = "0" ] || continue
    cmp -s "$TMP/twinA.md" "$TMP/twinB.md" \
      || fail "N6[C06 AC3]: twin pair ($1,$2) sections differ — alias twins receive BYTE-IDENTICAL sections (the parity law's prose face)"
  done
  ok "N6[C06 AC3 + C07 named-line exception]: every body's pre-append bytes are immovable vs $BASE and only the sanctioned section extends them — the dispatcher's pre-window bullet may reword in place (single-line, keyed to its exact base text; the other-line-moved and two-lines-moved mutants redden, the non-dispatcher freeze holds); alias twin sections are byte-identical once present"
fi

# --- N7: the OUT roster stays byte-frozen (AC5) -------------------------------------
if want n7; then
  for n in "${OUTSRC[@]}" "${SDLC[@]}"; do
    for f in ".rulesync/subagents/$n.md"; do
      [ -f "$f" ] || fail "N7[C06 AC5]: $f missing (harness fault)"
      git diff --quiet "$BASE" -- "$f" \
        || fail "N7[C06 AC5/D35]: $f changed vs $BASE — the OUT roster (agent-board: D2's narrow-surface law; agent-fuser; the 0-pipeline SDLC family) is byte-untouched by C06"
      grep -qF "$HDR" "$f" \
        && fail "N7[C06 AC5]: $f gained the sanctioned narrative section — OUT of the approved roster; the repo-wide hook covers it without file prose"
    done
  done
  ok "N7[C06 AC5]: agent-board, agent-fuser and the 0-pipeline SDLC bodies are byte-frozen vs $BASE and carry no narrative section"
fi

# --- N8: THE ARTIFACT line, pinned verbatim in the plan's Round-3 section ----------
# A plan/ticket-record fact: the wording the owner pastes into the
# machine-local OpenChamber setting (human-owned; the repo never sets it).
# Drift on the pinned string requires a re-ruling — the settled-constant law.
if want n8; then
  python3 - "$PLAN" <<'PY' || fail "N8[C06 artifact pin]: the artifact line is not verbatim inside the plan's Round-3 section (reason above)"
import re, sys
path = sys.argv[1]
t = open(path, encoding="utf-8").read()
m = re.search(r"(?ms)^## Round-3 direction.*?(?=^## |\Z)", t)
if not m:
    print("no Round-3 section in the plan of record"); sys.exit(1)
sec = m.group(0)
ARTIFACT = "Follow your agent's compaction instructions — the hook-injected note is the law; produce exactly the pointer summary they specify."
if ARTIFACT not in sec:
    print("the drafted OpenChamber compaction-prompt line is absent or altered in the Round-3 section"); sys.exit(1)
print("ok")
PY
  ok "N8[C06 artifact pin]: the drafted compaction-prompt line stands verbatim in the plan's Round-3 section (owner-paste wording; drift = re-ruling)"
fi

printf 'PASS: agent-narratives contract checks (%d ok)\n' "$checks"
