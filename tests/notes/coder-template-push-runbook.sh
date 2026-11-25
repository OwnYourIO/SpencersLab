#!/usr/bin/env bash
# C03 runbook parity contract (2026/2026-11-cf-56-feat-forgejo-coder-template-
# pipeline) for .agents/notes/2026-11-25-coder-template-push.md — the dated
# owner-leg runbook (the 2026-11-17-argocd-sync-fanout.md shape). Parity
# sources (the fanout-runbook convention): the LANDED workflow + both C02
# scripts, overridable via env. AC trace (chunks/C03.md AC7):
# r1[the runbook exists and carries all four owner legs UA1..UA4]
# r2[doc-vs-landed-files parity: every token the runbook quotes exists
#    byte-true in the file it quotes; the parity sources exist; the host
#    literals live in the HUMAN-executed runbook and in NO pipeline file —
#    the workflow + both scripts are env-only / no-literal (the main-sync
#    doctrine)] r3[banned-verb sweep: no kubectl, no helm
#    install/upgrade/apply, no `coder templates delete` outside the
#    user-owned posture section — token MINTS via `coder tokens create` are
#    the only coder mint verbs] r4[human-executed marker per command block;
#    the fenced blocks never execute a coder template verb (push/edit/
#    delete/archive/promote/unarchive) — the push belongs to the pipeline,
#    the human mints + read-only-checks] r5[the UA3 label-pin leg cites the
#    four-act-label shape + the hand-bump law + the calendar-tag shape +
#    the current pin the new tag must outrank] r6[the ruled postures stated
#    as answers: warn-and-skip green, a 401 is red, the 168h TTL is NOT
#    re-asserted, template deletion/rename is user-owned, a Rollback
#    section, zero pending-question markers].
#
# Designed-RED until C03 lands the runbook (and the workflow + scripts it
# pins): a missing runbook or a missing parity source is the
# not-yet-implemented state, not a skip.
#
# Run from the repo root (or point the overrides at a synthetic tree for
# green-shape proofs):
#   bash tests/notes/coder-template-push-runbook.sh   # r1..r6
#   bash tests/notes/coder-template-push-runbook.sh r2 r5   # subset
# Env: CODER_RUNBOOK (doc path override), CODER_WF / CODER_DETECT /
#      CODER_PUSH (parity sources), CODER_RUNBOOK_ROOT (tree root).
set -euo pipefail

cd "${CODER_RUNBOOK_ROOT:-$(git rev-parse --show-toplevel)}"

RUNBOOK="${CODER_RUNBOOK:-.agents/notes/2026-11-25-coder-template-push.md}"
WF="${CODER_WF:-.forgejo/workflows/coder-template-push.yaml}"
DETECT="${CODER_DETECT:-scripts/coder-template-detect.sh}"
PUSH="${CODER_PUSH:-scripts/coder-template-push.sh}"

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
  for i in $(seq 1 6); do WANT["r$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^r[1-6]$ ]] || fail "unknown leg id '$a' (expected r1..r6)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

command -v python3 >/dev/null 2>&1 || fail "python3 is required for the runbook walk"

[ -f "$RUNBOOK" ] ||
  fail "r1: $RUNBOOK missing — C03 (the dated owner-leg runbook) is not implemented (designed-red carrier)"

# --- r1: all four owner legs present ----------------------------------------
if want r1; then
  for u in UA1 UA2 UA3 UA4; do
    grep -qE "\b$u\b" "$RUNBOOK" ||
      fail "r1: the $u owner leg is missing — the plan's Human-owned list is UA1..UA4 (dev mint, gpu mint, tag verify + label-pin bump, first-fire watch)"
  done
  ok "r1: the runbook exists with all four owner legs (UA1..UA4)"
fi

# --- r2: docs-parity against the landed sources (AC7) -----------------------
if want r2; then
  for f in "$WF" "$DETECT" "$PUSH"; do
    [ -f "$f" ] ||
      fail "r2: parity source $f is absent — the runbook documents the LANDED C02/C03 shape; docs may not precede the code they pin (designed-red: C02/C03 not yet landed)"
  done
  if ! python3 - "$RUNBOOK" "$WF" "$DETECT" "$PUSH" <<'PY'
import os, re, sys

runbook, wf, detect, push = sys.argv[1:5]


def bad(msg):
    print("FAIL: r2: %s" % msg, file=sys.stderr)
    sys.exit(1)


try:
    doc = open(runbook).read()
except OSError:
    bad("%s unreadable (r1 covers absence; this is the read)" % runbook)

sources = {}
for label, path in (("workflow", wf), ("detect script", detect), ("push script", push)):
    try:
        sources[label] = open(path).read()
    except OSError:
        bad("parity source %s (%s) is absent — the runbook documents the LANDED shape" % (path, label))
wf_src, detect_src, push_src = sources["workflow"], sources["detect script"], sources["push script"]

# The vault keys are built from fragments so THIS file stays free of the
# joined forms (the fanout-runbook technique).
SECRET = "CODER_" + "SESSION_TOKEN"
URLV = "CODER_" + "URL"

# Every token the runbook quotes must exist byte-true in the file it quotes
# (the shipped parity technique: docs-vs-code drift is the bug class this
# leg kills).
PAIRS = [
    ("scripts/coder-template-detect.sh", wf_src, "the detect script the workflow's detect job invokes"),
    ("scripts/coder-template-push.sh", wf_src, "the push script the workflow's push job invokes"),
    (SECRET, wf_src, "the repo secret the workflow wires to env"),
    (URLV, wf_src, "the repo var the workflow wires to env"),
    (SECRET, push_src, "the env var the push script reads (env-only doctrine)"),
    (URLV, push_src, "the env var the push script reads (env-only doctrine)"),
    ("ignore-lockfile", push_src, "the pinned flag the push script passes (no lockfile shipped)"),
    ("vars.ROLE", wf_src, "the ROLE guard the runbook documents (the narrow-on-unset arithmetic)"),
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
  ok "r2: every quoted token (script paths, vault keys, flags, guard, hosts) exists byte-true in its source; hosts live in the runbook and in NO pipeline file; no token-shaped literal in workflow/scripts"
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

printf 'PASS: coder template push runbook contract checks (%d ok)\n' "$checks"
