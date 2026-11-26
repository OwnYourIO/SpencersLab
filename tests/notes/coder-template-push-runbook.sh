#!/usr/bin/env bash
# C03 runbook parity contract, re-pinned to the C04 fan-shape ruling
# (2026/2026-11-cf-56-feat-forgejo-coder-template-pipeline) for
# .agents/notes/2026-11-25-coder-template-push.md — the dated owner-leg
# runbook (the 2026-11-17-argocd-sync-fanout.md shape). Parity sources
# (the fanout-runbook convention): the LANDED workflow + both C02 scripts
# + main-sync.yaml (the fan-entry source, C04), overridable via env. AC
# trace (chunks/C03.md AC7; chunks/C04.md):
# r1[the runbook exists and carries all five owner legs UA1..UA5 — UA5
#    is the fan-shape migration leg: the first fan fire watch incl. our
#    called job green + the post-merge dev-side dispatch catch-up]
# r2[doc-vs-landed-files parity: every token the runbook quotes exists
#    byte-true in the file it quotes (incl. the fan-shape doc lines:
#    MARKER_SHA + the base= token in the detect script); the parity
#    sources exist; the workflow parity sources re-walk against the
#    called-run-shape files (the on: shape — no push arm + workflow_call
#    present + the dispatch input byte-frozen; NO advance-named job; the
#    resolver step's call-side gate + the ci/last-built name; the five
#    accessors byte-true); the main-sync.yaml fan entry byte-true (the
#    push-coder-templates job calling coder-template-push.yaml with no
#    inputs + the advance-marker needs list carrying it); the 5-line
#    re-fence (the runbook cites the post-rename names — the stale
#    pre-rename tokens are banned doc-wide); the host literals live in
#    the HUMAN-executed runbook and in NO pipeline file — the workflow +
#    both scripts are env-only / no-literal (the main-sync doctrine)]
# r3[banned-verb sweep: no kubectl, no helm install/upgrade/apply, no
#    `coder templates delete` outside the user-owned posture section —
#    token MINTS via `coder tokens create` are the only coder mint verbs]
# r4[human-executed marker per command block; the fenced blocks never
#    execute a coder template verb (push/edit/delete/archive/promote/
#    unarchive) — the push belongs to the pipeline, the human mints +
#    read-only-checks] r5[the UA3 label-pin leg cites the four-act-label
#    shape + the hand-bump law + the calendar-tag shape + the current pin
#    the new tag must outrank] r6[the ruled postures stated as answers:
#    warn-and-skip green, a 401 is red, the 168h TTL is NOT re-asserted,
#    template deletion/rename is user-owned, a Rollback section, zero
#    pending-question markers]
# r7[NEW — the FAN-STORY note pins (semantic, per-fact disjuncts +
#    same-line pairings — dev's wording is a prose call): the
#    no-own-marker-bootstrap text (the shared marker is fan-advanced —
#    the aggregate alone, once all three builders green; the plain
#    needs-gate named; a red fan leaves it put -> re-cover), the
#    single-repo state text (the marker lives on the prod-stage repo —
#    the dev instance carries no marker), the pre-state line (not yet
#    live — the first green fan creates it -> the announced tip-only
#    bootstrap), the no-full-fleet-legs line (the templates are already
#    live), the no-new-secret line (FORGE_PUSH_TOKEN may appear ONLY in
#    a negation line — the fan shape adds no new vault key), the
#    dev-side dispatch leg pins (HOW — the dev-instance workflow_dispatch
#    with the templates input; WHEN — post-merge + per template edit;
#    AND — a dispatch does not advance the shared marker per the fan
#    law)]
# r8[NEW — the NAMED-ASYMMETRY pins reworded to the r5 topology
#    (semantic, per-fact disjuncts): the re-run law shift (verify, not
#    re-mint; user-visible on the Coder servers; failure-class re-fires =
#    re-cover, the same full set re-pushed) and the stale-queued
#    over-push (churn, no correctness loss; vanishing under the
#    10-poller-pod x capacity-1 runner + FIFO + cancel-in-progress:
#    false by per-pod serialization; the marker never rewound — the
#    aggregate's non-FF refusal + classify law) + the re-cover coupling
#    (a red coder leg blocks the aggregate; a red sibling holds the
#    shared marker; the next fan re-covers all three domains — churn, no
#    correctness loss) stated as answers (the section-7 posture class —
#    zero pending-question markers, the r6 sweep still holds)].
#
# Designed-RED through C04 on r1 (UA5), r2 (the fan-shape re-walk + the
# re-fence) and the new r7/r8: the runbook is still the C03 push-trigger
# shape on the current tree; r3-r6 stay green (the banned-verb sweep, the
# human-executed markers, the label-pin leg, the ruled postures — the
# section-bound UA[1-4] regexes are safe with UA5 appended after UA4: the
# UA3 block stays bounded by the UA4 header and the UA5 content carries
# no banned verbs).
#
# Run from the repo root (or point the overrides at a synthetic tree for
# green-shape proofs):
#   bash tests/notes/coder-template-push-runbook.sh   # r1..r8
#   bash tests/notes/coder-template-push-runbook.sh r2 r5   # subset
# Env: CODER_RUNBOOK (doc path override), CODER_WF / CODER_DETECT /
#      CODER_PUSH / CODER_SYNC (parity sources), CODER_RUNBOOK_ROOT
#      (tree root).
set -euo pipefail

cd "${CODER_RUNBOOK_ROOT:-$(git rev-parse --show-toplevel)}"

RUNBOOK="${CODER_RUNBOOK:-.agents/notes/2026-11-25-coder-template-push.md}"
WF="${CODER_WF:-.forgejo/workflows/coder-template-push.yaml}"
DETECT="${CODER_DETECT:-scripts/coder-template-detect.sh}"
PUSH="${CODER_PUSH:-scripts/coder-template-push.sh}"
SYNC="${CODER_SYNC:-.forgejo/workflows/main-sync.yaml}"

# Joined-literal needles (the fanout-runbook technique): the suite file stays
# free of the joined forms so a repo-wide needle sweep never self-matches
# this test.
N1="coder templates"; N2=" delete"
H1="coder.dev."; H2="scifi.farm"
H3="coder.spencerslab"; H4=".com"
S1="CODER_"; S2="SESSION_TOKEN"
V1="CODER_"; V2="URL"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 8); do WANT["r$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^r[1-8]$ ]] || fail "unknown leg id '$a' (expected r1..r8)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

command -v python3 >/dev/null 2>&1 || fail "python3 is required for the runbook walk"

[ -f "$RUNBOOK" ] ||
  fail "r1: $RUNBOOK missing — C03 (the dated owner-leg runbook) is not implemented (designed-red carrier)"

# --- r1: all five owner legs present (C04 re-pin) --------------------------
if want r1; then
  for u in UA1 UA2 UA3 UA4 UA5; do
    grep -qE "\b$u\b" "$RUNBOOK" ||
      fail "r1: the $u owner leg is missing — the plan's Human-owned list is UA1..UA5 (dev mint, gpu mint, tag verify + label-pin bump, first-fire watch, the fan-shape migration leg: first fan fire watch incl. our called job green + the post-merge dev-side dispatch catch-up)"
  done
  ok "r1: the runbook exists with all five owner legs (UA1..UA5)"
fi

# --- r2: docs-parity against the landed sources (AC7, C04 re-pin) ---------
if want r2; then
  for f in "$WF" "$DETECT" "$PUSH" "$SYNC"; do
    [ -f "$f" ] ||
      fail "r2: parity source $f is absent — the runbook documents the LANDED shape; docs may not precede the code they pin (designed-red: the C04 fan-shape sources not yet landed)"
  done
  if ! python3 - "$RUNBOOK" "$WF" "$DETECT" "$PUSH" "$SYNC" <<'PY'
import os, re, sys
import yaml

runbook, wf, detect, push, sync = sys.argv[1:6]


def bad(msg):
    print("FAIL: r2: %s" % msg, file=sys.stderr)
    sys.exit(1)


try:
    doc = open(runbook).read()
except OSError:
    bad("%s unreadable (r1 covers absence; this is the read)" % runbook)

sources = {}
for label, path in (("workflow", wf), ("detect script", detect), ("push script", push), ("main-sync", sync)):
    try:
        sources[label] = open(path).read()
    except OSError:
        bad("parity source %s (%s) is absent — the runbook documents the LANDED shape" % (path, label))
wf_src, detect_src, push_src, sync_src = sources["workflow"], sources["detect script"], sources["push script"], sources["main-sync"]

# The vault keys are built from fragments so THIS file stays free of the
# joined forms (the fanout-runbook technique).
SECRET = "CODER_" + "SESSION_TOKEN"
URLV = "CODER_" + "URL"

# Every token the runbook quotes must exist byte-true in the file it quotes
# (the shipped parity technique: docs-vs-code drift is the bug class this
# leg kills). The C04 fan-shape doc lines join the list: the runbook cites
# the marker accessor + the base token, and they must be byte-true in the
# detect script.
PAIRS = [
    ("scripts/coder-template-detect.sh", wf_src, "the detect script the workflow's detect job invokes"),
    ("scripts/coder-template-push.sh", wf_src, "the push script the workflow's push job invokes"),
    (SECRET, wf_src, "the repo secret the workflow wires to env"),
    (URLV, wf_src, "the repo var the workflow wires to env"),
    (SECRET, push_src, "the env var the push script reads (env-only doctrine)"),
    (URLV, push_src, "the env var the push script reads (env-only doctrine)"),
    ("ignore-lockfile", push_src, "the pinned flag the push script passes (no lockfile shipped)"),
    ("vars.ROLE", wf_src, "the ROLE guard the runbook documents (the narrow-on-unset arithmetic)"),
    ("MARKER_SHA", detect_src, "the marker accessor the runbook's fan-shape doc lines document (the shared ci/last-built read)"),
    ("base=", detect_src, "the base token the runbook's fan-shape doc lines document (the echo names which arm won: marker|tip-only|before)"),
]
for tok, src, what in PAIRS:
    if tok not in doc:
        bad("the runbook never mentions %r (%s) — operators must be able to find every landed surface in the doc (AC7)" % (tok, what))
    if tok not in src:
        bad("the runbook quotes %r (%s) but its source file does not contain it (AC7 parity)" % (tok, what))

# The human-executed verbs: the mint + the two read-only checks. These live
# in the runbook (the human types them) and must NOT be wired into the
# workflow (the workflow never mints tokens or runs whoami).
DOC_ONLY = [
    ("tokens create", "the mint verb (human-executed, OQ6: server max lifetime)"),
    ("coder whoami", "the UA4 auth verification (human-executed, OQ4)"),
    ("coder templates versions", "the UA4 version check (human-executed)"),
]
for tok, what in DOC_ONLY:
    if tok not in doc:
        bad("the runbook never mentions %r (%s)" % (tok, what))
    if tok in wf_src:
        bad("the workflow carries %r — the mint/auth-check is a HUMAN leg, never wired into the workflow (the workflow only pushes)" % tok)

# The UA3 label-pin target must be a real repo file the runbook cites.
if "charts/forgejo-runner/values.yaml" not in doc:
    bad("the runbook never cites charts/forgejo-runner/values.yaml — the UA3 leg hand-bumps the label pin there")
if not os.path.exists("charts/forgejo-runner/values.yaml"):
    bad("charts/forgejo-runner/values.yaml does not exist in the tree (the UA3 target)")

# The C04 called-run shape re-walk: the parity sources must be the fan
# shape the runbook documents — the on: block (no push arm, workflow_call
# present, the dispatch input byte-frozen), no advance-named job, the
# resolver step (call-side gate + the shared ref name), the five
# byte-true accessors, and the main-sync fan entry (the called job + the
# aggregate needs list).
wfd = yaml.safe_load(wf_src) or {}
on = wfd.get("on", wfd.get(True))
if not isinstance(on, dict):
    bad("the workflow has no on: mapping to re-walk — the C04 called-run shape pins need it")
if "push" in on:
    bad("the workflow's on: block still carries a push arm — the C15 re-aim retired it (main-sync's prod-main fan calls the workflow; the runbook documents the fan shape, not the standalone trigger)")
if "workflow_call" not in on:
    bad("the workflow's on: block lacks workflow_call — the called-run trigger is the C15 contract the runbook documents")
t = ((on.get("workflow_dispatch") or {}).get("inputs") or {}).get("templates")
if not isinstance(t, dict) or set(t) != {"description", "required", "default", "type"}:
    bad("the workflow's templates dispatch input is not the byte-frozen four-key shape (the dev-side leg + the escape hatch the runbook documents)")
jobs = wfd.get("jobs") or {}
adv = [n for n in jobs if "advance" in str(n).lower()]
if adv:
    bad("the workflow carries advance-named job(s) %s — the advance job is RETIRED (main-sync's aggregate is the single marker writer; the runbook's fan story states it)" % adv)
det = None
for j in jobs.values():
    for s in (j or {}).get("steps", []):
        if isinstance(s, dict) and "coder-template-detect.sh detect" in str(s.get("run", "")):
            det = j
            break
    if det is not None:
        break
if det is None:
    bad("no detect job to re-walk (the C04 shape pins need it)")
steps = [s for s in (det or {}).get("steps", []) if isinstance(s, dict)]
mstep = next((s for s in steps if s.get("id") == "marker"), None)
if mstep is None or not str(mstep.get("run", "")):
    bad("the workflow carries no id: marker resolver step (with a run body) — the call-side-only resolver is the C04 shape the runbook documents")
mbody = str(mstep.get("run", ""))
if "ci/last-built" not in mbody:
    bad("the resolver step never names ci/last-built — it must read the SHARED ref (the OQ11 ruling: no own ref anywhere)")
if "workflow_call" not in mbody:
    bad("the resolver step carries no call-side gate (workflow_call) — the marker is CALL-SIDE only: a dispatch never reads the marker")
tstep = next((s for s in steps if "coder-template-detect.sh" in str(s.get("run", ""))), None)
env = (tstep or {}).get("env") or {}
ACC = {
    "EVENT_NAME": "${{ forgejo.event_name }}",
    "EVENT_BEFORE": "${{ forgejo.event.before }}",
    "SHA": "${{ forgejo.sha }}",
    "MANUAL_TEMPLATES": "${{ forgejo.event.inputs.templates }}",
    "MARKER_SHA": "${{ steps.marker.outputs.sha }}",
}
if set(env) != set(ACC):
    bad("the detect step's env keys are %s, expected exactly the five %s (the PR keys stay absent, the OQ2 ruling — the accessors the runbook documents)" % (sorted(env), sorted(ACC)))
for k, v in ACC.items():
    if str(env.get(k)) != v:
        bad("the detect step's %s accessor is %r, expected byte-exact %r (the five accessors the runbook documents)" % (k, env.get(k), v))
sjobs = (yaml.safe_load(sync_src) or {}).get("jobs") or {}
pc = sjobs.get("push-coder-templates")
if not isinstance(pc, dict):
    bad("main-sync.yaml carries no push-coder-templates job — the fan entry the runbook documents (the OQ10 fan member)")
if "coder-template-push.yaml" not in str(pc.get("uses", "")):
    bad("push-coder-templates.uses is %r, expected to call .forgejo/workflows/coder-template-push.yaml (the fan entry the runbook documents)" % pc.get("uses"))
if pc.get("with"):
    bad("push-coder-templates carries with: inputs — the called workflow needs none (its detection reads the event payload + the shared marker)")
advn = (sjobs.get("advance-marker") or {}).get("needs")
advn = [advn] if isinstance(advn, str) else (advn or [])
if "push-coder-templates" not in advn:
    bad("main-sync.yaml's advance-marker needs %s — the fan member must be in the aggregate's needs (a red coder leg holds the shared marker; the runbook states the coupling)" % advn)

# The 5-line re-fence (D24, the D50.3 pairing law): the runbook cites the
# post-rename names, and the stale pre-rename tokens are gone doc-wide.
# Tokens composed so this file never matches the ci-surface t8 sweep.
for stale in ("release" + ".yaml", "containers-build" + ".yaml"):
    if stale in doc:
        bad("the runbook still carries the stale token %r — the 5-line re-fence moves the citations to the post-rename names in the same commit set (the D50.3 pairing law)" % stale)
for newtok in ("build-charts" + ".yaml", "build-containers" + ".yaml"):
    if newtok not in doc:
        bad("the runbook never cites %r — the re-fenced citations (the guard fail-safe class, the merge fire, the sequencing legs) must name the post-rename chart" % newtok)

# The host literals: they live in the HUMAN-executed runbook (the human types
# the host at mint time — the fanout runbook's permitted shape) and in NO
# pipeline file (the workflow + both scripts are env-only / no-literal).
hosts = ["coder.dev." + "scifi.farm", "coder.spencerslab" + ".com"]
for host in hosts:
    if host not in doc:
        bad("the runbook never uses the host literal %r — the UA1/UA2 mint commands name the host the human types (the fanout runbook's permitted shape)" % host)
for label, src in (("workflow", wf_src), ("detect script", detect_src), ("push script", push_src)):
    for host in hosts:
        if host in src:
            bad("the %s carries the instance URL literal %r — no URL literal may enter a pipeline file (the main-sync doctrine: identical-safe to host; the endpoint comes from %s)" % (label, host, URLV))

# No token-shaped literal in any pipeline file: a pasted credential prefix, or
# a long opaque alphanumeric run (pure-hex runs are the digest-comment class,
# allowed).
for label, src in (("workflow", wf_src), ("detect script", detect_src), ("push script", push_src)):
    if re.search(r"ghp_|gho_|ghs_|ghr_|github_pat_|glpat-|\bgj_", src):
        bad("the %s carries a token prefix — no credential literal may be pasted in" % label)
    for i, ln in enumerate(src.splitlines(), 1):
        for m in re.finditer(r"[A-Za-z0-9]{24,}", ln):
            s = m.group(0)
            if re.fullmatch(r"[0-9a-f]+", s, re.I) is None:
                bad("the %s line %d carries a token-shaped literal (%s...)" % (label, i, s[:30]))
print("ok: r2")
PY
  then
    fail "r2: runbook-vs-landed-files parity is violated (reason printed above)"
  fi
  ok "r2: every quoted token (script paths, vault keys, flags, guard, hosts, MARKER_SHA, base=) exists byte-true in its source; the workflow re-walks the called-run shape (on: shape, no advance job, resolver gate + shared ref, five byte-true accessors); the main-sync fan entry is byte-true; the runbook cites the post-rename names with the stale tokens banned doc-wide; hosts live in the runbook and in NO pipeline file; no token-shaped literal in workflow/scripts"
fi

# --- r3: banned-verb sweep (AC7) --------------------------------------------
if want r3; then
  if ! python3 - "$RUNBOOK" <<'PY'
import re, sys

runbook = sys.argv[1]
lines = open(runbook).read().splitlines()
DELETE = "coder templates" + " delete"


def bad(msg):
    print("FAIL: r3: %s" % msg, file=sys.stderr)
    sys.exit(1)


# Doc-wide bans: this repo NEVER applies (AGENTS.md) and never helm-mutates.
for i, ln in enumerate(lines, 1):
    if re.search(r"\bkubectl\b", ln):
        bad("line %d carries kubectl — this repo NEVER applies (ArgoCD is the apply surface; AGENTS.md)" % i)
    if re.search(r"\bhelm (install|upgrade|apply)\b", ln):
        bad("line %d carries a helm install/upgrade/apply — charts reach the clusters via ArgoCD, never a helm apply" % i)

# Section bounds (the fanout technique), over numbered / UA-labeled section
# headers — the runbook's section form. A plain `# ...` comment line (e.g.
# "# human-executed") is markdown level 1 but is NOT a section: letting it
# bound a section would split the posture section and strand its lines.
heads = []
for i, ln in enumerate(lines):
    if re.match(r"^#{1,6}\s+(?:Section\s+)?(?:\d+[.:)]\s|UA[1-4]\b)", ln):
        heads.append((i, ln.strip()))

# Build (start, end, label) bounds over the header list.
bounds = []
for idx, (i, label) in enumerate(heads):
    j = heads[idx + 1][0] if idx + 1 < len(heads) else len(lines)
    bounds.append((i, j, label))


def is_posture(label):
    return bool(re.search(r"(?i)posture|user[- ]owned|limitation", label))


# The delete verb may be named ONLY in a user-owned-posture section.
for i, ln in enumerate(lines):
    if DELETE in ln:
        allowed = any(s <= i < e and is_posture(lab) for s, e, lab in bounds)
        if not allowed:
            bad("line %d names %r outside a user-owned-posture section — template deletion is user-owned (OQ9) and nameable only where the posture is stated" % (i + 1, DELETE))
print("ok: r3")
PY
  then
    fail "r3: a banned verb survives (reason printed above)"
  fi
  ok "r3: zero kubectl / helm install-upgrade-apply; 'coder templates delete' confined to the user-owned-posture section"
fi

# --- r4: human-executed markers + the fence command law (AC7) --------------
if want r4; then
  if ! python3 - "$RUNBOOK" <<'PY'
import re, sys

lines = open(sys.argv[1]).read().splitlines()


def bad(msg):
    print("FAIL: r4: %s" % msg, file=sys.stderr)
    sys.exit(1)


if not re.search(r"(?i)human[- \t]executed", "\n".join(lines)):
    bad("r4: no human-executed marker anywhere (this repo never applies; the whole runbook is human legs)")

MARK = re.compile(r"(?i)\bhuman\b|\bowner (runs|executes|pastes|mints|performs|deletes|checks)\b|\byou (run|paste|mint)\b")
in_fence = False
fence_start = 0
blocks = []
for i, ln in enumerate(lines):
    if re.match(r"^\s*```", ln):
        if not in_fence:
            in_fence, fence_start = True, i
        else:
            in_fence = False
            blocks.append((fence_start, i))
if in_fence:
    bad("r4: unterminated code fence at line %d" % (fence_start + 1))
if not blocks:
    bad("r4: the runbook has no fenced command blocks — the procedure must be copy-pasteable (human-executed, marked)")


def head_before(pos):
    h = ""
    for ln in lines[:pos]:
        if re.match(r"^#{1,6}\s", ln):
            h = ln
    return h


# The only coder verbs a human block may execute are the mint + the two
# read-only checks. The push belongs to the PIPELINE (the workflow), so a
# human block running coder templates push/edit/delete/... is the bug class.
BANNED_IN_FENCE = re.compile(r"\bcoder templates (push|edit|delete|archive|promote|unarchive)\b")
for a, b in blocks:
    body = lines[a + 1:b]
    if not any(l.strip() for l in body):
        continue  # diagram/table fences carry no commands
    context = "\n".join(lines[max(0, a - 12):a]) + "\n" + head_before(a)
    if not MARK.search(context):
        bad("r4: fenced block at line %d (`%s`...) has no human-executed marker in its heading or the 12 lines before it — every command here is human-owned by ruling" % (a + 1, body[0].strip()[:60]))
    for j, l in enumerate(body, start=a + 2):
        m = BANNED_IN_FENCE.search(l)
        if m:
            bad("r4: line %d is a human-executed 'coder templates %s' — the push/edit/delete belongs to the pipeline or is user-owned prose; a human block may only mint (coder tokens create) + read-only-check (coder whoami / coder templates versions)" % (j, m.group(1)))
print("ok: r4")
PY
  then
    fail "r4: the human-executed/command law is violated (reason printed above)"
  fi
  ok "r4: every command block is human-marked; no fenced block executes a coder template verb (mint + read-only checks only)"
fi

# --- r5: the UA3 label-pin leg (AC7) ----------------------------------------
if want r5; then
  if ! python3 - "$RUNBOOK" <<'PY'
import re, sys

lines = open(sys.argv[1]).read().splitlines()


def bad(msg):
    print("FAIL: r5: %s" % msg, file=sys.stderr)
    sys.exit(1)


# Locate the UA3 section header, then take its block to the next
# numbered/UA-labeled header at its level or shallower (a plain '# ...'
# comment line is not a section boundary — see r3's bound note).
i0 = None
for i, ln in enumerate(lines):
    if re.match(r"^#{1,6}\s+(?:Section\s+)?(?:\d+[.:)]\s+)?UA3\b", ln):
        i0 = i
        break
if i0 is None:
    bad("no UA3 section header found (the owner leg must be a headed section, the fanout shape)")
level = len(lines[i0]) - len(lines[i0].lstrip("#"))
j = len(lines)
for k in range(i0 + 1, len(lines)):
    ln = lines[k]
    m = re.match(r"^(#{1,6})\s+(?:Section\s+)?(?:\d+[.:)]\s|UA[1-4]\b)", ln)
    if m and len(m.group(1)) <= level:
        j = k
        break
block = "\n".join(lines[i0:j])


def need(pat, what):
    if not re.search(pat, block, re.I):
        bad("r5: the UA3 leg lacks %s" % what)


need(r"charts/forgejo-runner/values\.yaml", "the label-pin file (the pin's home)")
need(r"four.{0,40}act", "the four-act-label shape (the four act-24.04-family label lines are what the hand-bump touches)")
need(r"(?i)hand[- ]?bump|bump.{0,60}by hand", "the hand-bump law")
need(r"renovate", "the no-Renovate-lane law (AGENTS.md: no Renovate lane reads that pin — it is bumped by hand)")
need(r"yy\.mm\.N", "the calendar tag shape (the next tag past the current pin)")
need(r"26\.11", "the current pin the new tag must outrank")
need(r"ghcr", "the ghcr registry (the tag is published there AND the instance registry)")
need(r"registry", "the instance registry (the dual-publish the owner verifies before the bump)")
print("ok: r5")
PY
  then
    fail "r5: the UA3 label-pin leg is incomplete (reason printed above)"
  fi
  ok "r5: the UA3 leg cites charts/forgejo-runner/values.yaml + the four-act-label shape + the hand-bump law + the no-Renovate-lane law + the yy.mm.N tag shape past the current pin (ghcr + instance registry)"
fi

# --- r6: ruled postures stated as answers (AC7) ----------------------------
if want r6; then
  if ! python3 - "$RUNBOOK" <<'PY'
import re, sys

lines = open(sys.argv[1]).read().splitlines()
doc = "\n".join(lines)


def bad(msg):
    print("FAIL: r6: %s" % msg, file=sys.stderr)
    sys.exit(1)


def need(pat, what, flags=0):
    if not re.search(pat, doc, flags):
        bad("r6: %s lacks %r" % (what, pat))


need(r"(?i)warn[- ]?and[- ]?skip", "the warn-and-skip green posture (an unconfigured instance skips, never fails)")
# \bred\b (word-boundary): the bare substring 'red' false-positives on
# 'expired' — a 401 line describing token expiry is not the red-posture
# pairing. The 'fail' stem stands (failure/fails/failing are the intended
# pairings).
if not any(re.search(r"401", ln) and re.search(r"(?i)\bred\b|fail", ln) for ln in lines):
    bad("r6: no line pairs a 401 with a red/fail expectation — a configured auth failure must be RED (loud by design), not a silent skip")
if not any(re.search(r"168h", ln) and re.search(r"(?i)not re-assert|user[- ]owned|stays user", ln) for ln in lines):
    bad("r6: no line pairs the 168h default-TTL with the NOT-re-asserted / user-owned posture — OQ7: the pipeline does not re-assert the user's edit")
if not any(re.search(r"(?i)delet|rename", ln) and re.search(r"(?i)user[- ]owned", ln) for ln in lines):
    bad("r6: no line pairs template deletion/rename with the user-owned posture — OQ9")
if not any(re.match(r"^#{1,6}\s*.*rollback", ln, re.I) for ln in lines):
    bad("r6: no Rollback heading — the plan's rollback (unset the instance secret / flip the ROLE word) must be a stated section")
if re.search(r"(?i)pending owner|owner (decision|call) (pending|open)|to be (decided|ruled)", doc):
    bad("r6: an unresolved-question marker survives — the 2026-11-25 batched round ANSWERED every OQ; the runbook states rulings, not open questions")
print("ok: r6")
PY
  then
    fail "r6: a ruled posture row is missing (reason printed above)"
  fi
  ok "r6: warn-and-skip green, a 401 is red, the 168h TTL is NOT re-asserted, deletion/rename user-owned, a Rollback section, zero pending markers"
fi

# --- r7: the FAN-STORY note pins (C04, semantic — per-fact disjuncts +
# same-line pairings; dev's wording is a prose call, the pin is the fact) --
if want r7; then
  if ! python3 - "$RUNBOOK" <<'PY'
import re, sys

lines = open(sys.argv[1]).read().splitlines()
doc = "\n".join(lines)


def bad(msg):
    print("FAIL: r7: %s" % msg, file=sys.stderr)
    sys.exit(1)


# (a) the no-own-marker bootstrap: the shared marker is fan-advanced —
# the aggregate alone, once all three builders green; the plain
# needs-gate named; a red fan leaves it put -> re-cover.
if not any(re.search(r"marker", ln, re.I) and re.search(r"fan|aggregate", ln, re.I) for ln in lines):
    bad("r7: no line pairs marker + fan/aggregate — the no-own-marker bootstrap text (the shared marker is fan-advanced, the aggregate alone)")
if not any(re.search(r"aggregate", ln, re.I) and re.search(r"green", ln, re.I) for ln in lines):
    bad("r7: no line pairs aggregate + green — the advance fires only when all three builders are green (the plain needs-gate, named)")
if not any(re.search(r"red", ln, re.I) and re.search(r"marker", ln, re.I) and re.search(r"put|stays|hold|unmoved", ln, re.I) for ln in lines):
    bad("r7: no line pairs red + marker + a put/hold posture — a red fan leaves the shared marker put (the re-cover premise)")
if not re.search(r"re.cover|recovered|recovers", doc, re.I):
    bad("r7: no re-cover wording — a red fan leaves the marker put and the next fan re-covers (the coupling the runbook states)")

# (b) the single-repo state: the marker lives on the prod-stage repo —
# the dev instance carries no marker.
if not any(re.search(r"prod.stage", ln, re.I) and re.search(r"marker", ln, re.I) for ln in lines):
    bad("r7: no line pairs prod-stage + marker — the single-repo state (the shared marker lives on the prod-stage repo)")
if not any(re.search(r"\bdev\b", ln) and re.search(r"marker", ln, re.I) and re.search(r"\bno\b|\bnone\b|without|never|not\b|absent", ln, re.I) for ln in lines):
    bad("r7: no line states the dev instance carries no marker (the single-repo state half — the dev instance has no marker to read)")

# (c) the pre-state line: not yet live — the first green fan creates it
# -> the announced tip-only bootstrap.
if not any(re.search(r"marker", ln, re.I) and re.search(r"not yet|yet to|absent|creates?|first (green|fan)", ln, re.I) for ln in lines):
    bad("r7: no pre-state line — the ref is not yet live and the first green fan creates it")
if not any(re.search(r"tip.only", ln, re.I) and re.search(r"bootstrap|announce", ln, re.I) for ln in lines):
    bad("r7: no line pairs tip-only + bootstrap/announce — the bootstrap fire's announced narrowing (the runbook cites it)")

# (d) the no-full-fleet-legs line: the templates are already live.
if not any(re.search(r"template", ln, re.I) and re.search(r"live", ln, re.I) for ln in lines):
    bad("r7: no line pairs templates + already live — the no-full-fleet-legs line (the templates are already live; nothing fleet-side to mint)")

# (e) the no-new-secret line: FORGE_PUSH_TOKEN may appear ONLY in a
# negation line (the fan shape adds no new vault key — the push rides the
# checkout same-repo credential). A silent omission is the drift this pin
# kills: a negation line or a no-new-secret statement must exist.
forg_lines = [ln for ln in lines if "FORGE_PUSH_TOKEN" in ln]
for ln in forg_lines:
    if not re.search(r"\bno\b|\bnot\b|\bnever\b|\bwithout\b|\bnone\b", ln, re.I):
        bad("r7: a line names FORGE_PUSH_TOKEN without a negation — the no-new-secret line must state that no such token is added (a bare mention re-opens the retired credential)")
if not forg_lines and not any(re.search(r"no new", ln, re.I) and re.search(r"secret|token|key|vault", ln, re.I) for ln in lines):
    bad("r7: no no-new-secret statement — the fan-shape note must state the push rides the checkout credential (no new vault key; FORGE_PUSH_TOKEN may appear only in a negation line)")

# (f) the dev-side dispatch leg: HOW (the dev-instance workflow_dispatch
# with the templates input), WHEN (post-merge + per template edit), AND
# (a dispatch does not advance the shared marker per the fan law).
if not any(re.search(r"workflow_dispatch", ln) and re.search(r"templates", ln, re.I) for ln in lines):
    bad("r7: no line pairs workflow_dispatch + the templates input — the dev-side dispatch leg's HOW")
if not any(re.search(r"post.merge|after the merge|after merge", ln, re.I) and re.search(r"dispatch|catch", ln, re.I) for ln in lines):
    bad("r7: no line pairs post-merge + the dispatch catch-up — the dev-side leg's WHEN")
if not any(re.search(r"dispatch", ln, re.I) and re.search(r"marker", ln, re.I) and re.search(r"\bnot\b|\bno\b|\bnever\b|does not|without", ln, re.I) for ln in lines):
    bad("r7: no line states a dispatch does not advance the shared marker — the dev-side leg's AND (the fan law: a dispatch never advances the shared marker)")
print("ok: r7")
PY
  then
    fail "r7: a fan-story pin is missing (reason printed above)"
  fi
  ok "r7: the fan-story note pins — no-own-marker bootstrap (fan-advanced, aggregate alone, all-three-green; the needs-gate named; red fan leaves it put -> re-cover), single-repo state (prod-stage repo; the dev instance carries no marker), pre-state (not yet live; first green fan creates it -> announced tip-only bootstrap), no-full-fleet-legs (templates already live), no-new-secret (FORGE_PUSH_TOKEN only in a negation line), the dev-side dispatch leg (HOW/WHEN/AND)"
fi

# --- r8: the NAMED-ASYMMETRY pins, r5 topology (C04, semantic) -----------
if want r8; then
  if ! python3 - "$RUNBOOK" <<'PY'
import re, sys

lines = open(sys.argv[1]).read().splitlines()
doc = "\n".join(lines)


def bad(msg):
    print("FAIL: r8: %s" % msg, file=sys.stderr)
    sys.exit(1)


# (a) the re-run law shift: verify, not re-mint; user-visible on the
# Coder servers; failure-class re-fires = re-cover, the same full set
# re-pushed.
if not (any(re.search(r"re.mint", ln, re.I) and re.search(r"\bnot\b|\bno\b|\bnever\b|instead", ln, re.I) for ln in lines)
       or any(re.search(r"verify", ln, re.I) and re.search(r"re.mint", ln, re.I) for ln in lines)):
    bad("r8: no re-run law shift (verify, not re-mint) — a re-fired run verifies the last push; it does not re-mint anything")
if not any(re.search(r"visible", ln, re.I) and re.search(r"server", ln, re.I) for ln in lines):
    bad("r8: no line pairs visible + servers — the pushed versions are user-visible on the Coder servers (the re-run law's surface)")
if not any(re.search(r"re.fire|refire|re-fired|re-fire", ln, re.I) and re.search(r"re.cover|re-pushed|re.push|full set", ln, re.I) for ln in lines):
    bad("r8: no line pairs failure-class re-fires + re-cover / the full set re-pushed — a failure-class re-fire re-covers the same full set")

# (b) the stale-queued over-push: churn, no correctness loss; vanishing
# under the 10-poller-pod x capacity-1 runner + FIFO + cancel-in-progress
# false by per-pod serialization; the marker never rewound — the
# aggregate's non-FF refusal + classify law.
if not any(re.search(r"over.push|stale.{0,30}queued|stale queue", ln, re.I) and re.search(r"churn|correctness", ln, re.I) for ln in lines):
    bad("r8: no line pairs the stale-queued over-push + churn/correctness — the over-push is churn with no correctness loss")
if not any(re.search(r"capacity.{0,12}1|10.poller|poller.pod", ln, re.I) and re.search(r"serializ|FIFO|queue", ln, re.I) for ln in lines):
    bad("r8: no line pairs the runner topology (10-poller-pod x capacity-1, FIFO) + serialization — the over-push vanishing law (per-pod serialization with cancel-in-progress false)")
if not any(re.search(r"marker", ln, re.I) and re.search(r"rewind|non.FF|refus", ln, re.I) for ln in lines):
    bad("r8: no line states the marker is never rewound — the aggregate's non-FF refusal + classify law is the pin")

# (c) the re-cover coupling: a red coder leg blocks the aggregate; a red
# sibling holds the shared marker; the next fan re-covers all three
# domains — churn, no correctness loss.
if not (any(re.search(r"coder", ln, re.I) and re.search(r"aggregate|marker", ln, re.I) and re.search(r"red|block|hold", ln, re.I) for ln in lines)
       or any(re.search(r"sibling", ln, re.I) and re.search(r"marker", ln, re.I) and re.search(r"red|hold", ln, re.I) for ln in lines)):
    bad("r8: no line pairs a red coder leg / a red sibling + the aggregate or marker hold — the re-cover coupling")
if not any(re.search(r"three domains|all three|domains", ln, re.I) and re.search(r"re.cover", ln, re.I) for ln in lines):
    bad("r8: no line pairs the re-cover + all three domains — the next fan re-covers containers + charts + templates (churn, no correctness loss)")
print("ok: r8")
PY
  then
    fail "r8: a named-asymmetry pin is missing (reason printed above)"
  fi
  ok "r8: the named-asymmetry pins on the r5 topology — the re-run law shift (verify, not re-mint; user-visible on the Coder servers; failure-class re-fires re-cover the same full set), the stale-queued over-push (churn, no correctness loss; vanishing under the 10-poller-pod x capacity-1 runner + FIFO serialization; the marker never rewound — the non-FF refusal + classify law), the re-cover coupling (red coder leg blocks the aggregate; a red sibling holds the marker; the next fan re-covers all three domains)"
fi

printf 'PASS: coder template push runbook contract checks (%d ok)\n' "$checks"
