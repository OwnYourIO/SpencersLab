#!/usr/bin/env bash
# cf-143 C16 — the q27 boot note contract (chunks/C16.md Tests T1-T5;
# cf-144 C02 adds T6 — the TP2 pool=2 / claim-math / parked-window-sync
# annotation arms, designed-red until the dated boot-note annotation lands).
# The doc under contract: .agents/notes/radiance-q27-boot.md — the OWNER-
# CONSOLE document for the pod-swap lane: resting state, staging math, THE
# SWITCH (fn DOWN first, then q27 UP), the load-bearing first-boot receipt
# read, the honest envelope, the smoke, the attribution table, the swap-back.
#
# DESIGN-RED at handoff (names C16): the note does not exist yet — dev D1
# writes it after this round, exactly the C06 runbook shape (§12 "the test
# session authors it against the step names before dev writes the doc").
# Its T2 equality ALSO names C15: the args law compares the note's one
# fenced block against the LANDED radiance-q27 overlay subtree — the C16
# dependency on C15 is real, not cosmetic (chunk "Why its own chunk").
#
# LAW CARRIED FROM THE fn SUITES (not re-argued): one-block law (§D54-F —
# the fn runbook pins EXACTLY ONE fn args block; q27 gets its OWN note so
# that witness stays untouched), OWNER-EXECUTED marker on the same or the
# immediately preceding line (C13 r1: repair by PROSE RE-ARRANGEMENT, never
# by loosening the arm), citations resolve against this folder's RESEARCH.md
# (§R19 round: §R19 / R19-Q<n> / R19-S<n> / R19-A..F forms EXTEND the
# resolver — the AC4-C14 precedent: never dodge a citation by dropping it),
# every speed figure carries its attribution (§R19-Q4, D54(4): 122 = model
# card TP1 SINGLE-stream mixed mean with the prose leg 77; 280 = the card's
# 4-stream TOTAL; 116 = Wilde, third-party, n=4 at 64K on a Gen4 board; a
# bare 122 must RED), and NO Flash-Next TP1 radiance speed exists to publish.
#
# The attribution and order arms PROVE THEMSELVES GREEN-BOTH-WAYS at every
# run (§12.14: "an arm that cannot red the lie AND green the truth is half
# a tripwire"): T4/T5 first run the validators against embedded fixtures —
# the truthful attributed row must pass, the bare-122 / reversed-order
# fixtures must fail — before touching the real note.
#
# Run from the repo root:
#   bash tests/notes/radiance-q27-boot.sh          # T1..T5
#   bash tests/notes/radiance-q27-boot.sh T4 T5    # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

NOTE="${RAD_Q27_NOTE:-.agents/notes/radiance-q27-boot.md}"
RESEARCH="${RAD_Q27_RESEARCH:-.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/RESEARCH.md}"
VALS="${RAD_Q27_VALS:-services/gpu-ai/prod/values.yaml}"

# The keyless env token the DROPPED rider carried is banned from any runnable
# line; assembled here because the AC4 repo-wide grep scopes tests/.
# The pool name follows the canonical constants block
# (charts/amd-gpu/tests/amd_gpu_testlib.py); SPLIT so this file stays a clean
# subject of the C01 zero-stale sweep.
R9700_CLAIM="amd.com/gpu-r9700"
RETIRED_R9700_CLAIM="amd.com/gpu-r9700"-"1"
KEYLESS_ENV_TOKEN="RADIANCE""_API_KEY"

checks=0

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok()  { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for t in 1 2 3 4 5 6; do WANT["t$t"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-6]$ ]] || fail "unknown test id '$a' (expected T1..T6)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- T1: note exists, step shape 0-7, posture, command law, §R19 resolver -------
if want t1; then
  if [ ! -f "$NOTE" ]; then
    fail "T1: $NOTE missing — C16 (the owner's first-boot console note) is not implemented (designed-red naming C16)"
  fi
  lines=$(wc -l < "$NOTE")
  if [ "$lines" -lt 100 ]; then
    fail "T1: the boot note is only $lines lines — the eight steps with the receipts, the envelope and the attribution table cannot fit (want >= 100)"
  fi
  if ! python3 - "$NOTE" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
first = {}
for i, ln in enumerate(text.splitlines()):
    if not ln.startswith("#"):
        continue
    for n in range(8):
        if n in first:
            continue
        if re.match(rf"^#{{1,6}}\s*(Step\s+)?{n}(?=[.: \t—–-]|$)", ln):
            first[n] = i
missing = [n for n in range(8) if n not in first]
if missing:
    sys.exit(f"missing step-group headers for steps: {missing} (the D1 shape is steps 0-7)")
seq = [first[n] for n in sorted(first)]
if seq != sorted(seq):
    sys.exit(f"step-group headers out of order: {first}")
PY
  then
    fail "T1: the boot note does not carry the step groups 0-7 in order (chunks/C16.md D1 step shape)"
  fi
  if ! python3 - "$NOTE" <<'PY'
import re, sys
head = "\n".join(open(sys.argv[1]).read().splitlines()[:40]).lower()
errs = []
for pat, what in (
    (r"(resting|idle by design)", "the resting-state posture (fn 1 / q27 0 — idle BY DESIGN, steps 0/2)"),
    (r"(nothing routes|never a default|no default route|opt[- ]in)", "the nothing-routes-by-default law (D54(4): measurement-conditional candidate only)"),
    (r"runner[- ]model[^\n]{0,80}(not move|does not move|unchanged)", "the runner-model literal does NOT move"),
    (r"receipt", "the receipt-decides law ('the receipt decides, never the rate' — §R8/D28(6) class)"),
    (r"owner[- ]executed", "the OWNER-EXECUTED posture"),
):
    if not re.search(pat, head):
        errs.append(what)
if errs:
    sys.exit("posture line(s) missing from the first 40 lines: " + "; ".join(errs))
PY
  then
    fail "T1: the AC3/D1-step-0 posture (resting state, nothing routes by default, runner literal unmoved, receipt decides, owner-executed) is not stated up top"
  fi
  # Command law (the runbook's shape, inherited): mutations only OWNER-marked;
  # kubectl exec barred outright (no pod-exec tier); argocd app sync barred.
  if ! python3 - "$NOTE" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()
MUT = re.compile(r"kubectl[ \t]+(apply|create|delete|scale|edit|patch|label|annotate|cordon|drain|taint|run|rollout)")
EX = re.compile(r"kubectl[ \t]+exec")
SYNC = re.compile(r"argocd[ \t]+app[ \t]+sync")
OWNER = re.compile(r"(?i)owner[- ](?:executed|lane)")
errs = []
for i, ln in enumerate(lines):
    if re.match(r"^\s*#", ln):          # comment lines may NAME the law (vllm exemption)
        continue
    if EX.search(ln) and not any(OWNER.search(x) for x in (ln, lines[i - 1] if i else "")):
        errs.append(f"{i+1}: a kubectl EXEC instruction — pod-exec is barred even owner-side: {ln.strip()[:90]}")
    if SYNC.search(ln) and not any(OWNER.search(x) for x in (ln, lines[i - 1] if i else "")):
        errs.append(f"{i+1}: an argocd app sync instruction — sync is ArgoCD's own reconciliation: {ln.strip()[:90]}")
    if MUT.search(ln) and not any(OWNER.search(x) for x in (ln, lines[i - 1] if i else "")):
        errs.append(f"{i+1}: unmarked cluster-mutating command (needs OWNER-EXECUTED on this or the previous line): {ln.strip()[:90]}")
if errs:
    print("\n".join(errs[:8]), file=sys.stderr); sys.exit(1)
PY
  then
    fail "T1: the command law is violated — the scale/sync/df lines must sit under the OWNER-EXECUTED marker (same or previous line; C13 r1: repair by prose re-arrangement, never by loosening this arm)"
  fi
  # §R19 citation resolver — the fn T4 family EXTENDED with the R<n> rounds
  # (never deleted; the bracketed [S<n>] ids stay inert by the standing design).
  if ! RAD_RESEARCH="$RESEARCH" python3 - "$NOTE" <<'PY'
import os, re, sys
doc = open(sys.argv[1]).read()
research = open(os.environ["RAD_RESEARCH"]).read()

rq = {int(m.group(1)) for m in re.finditer(r"(?m)^## RQ([0-5]) —", research)}
m_r6 = re.search(r"(?m)^## R6 —", research)
r6_part = research[m_r6.start():] if m_r6 else ""
r6q = {int(m.group(1)) for m in re.finditer(r"(?m)^### R6-Q([1-5]) —", r6_part)}
def numbered_items(t):
    return len(re.findall(r"(?m)^\d+\.\s", t))
m_oq = re.search(r"(?m)^## Open questions .*$", research)
oq_block = ""
if m_oq:
    rest = research[m_oq.end():]
    stop = re.search(r"(?m)^(## |RESULT)", rest)
    oq_block = rest[: stop.start() if stop else len(rest)]
main_oq = numbered_items(oq_block)

# Generic §R<n> section map (C14 idiom: resolve, never dodge): every round
# heading is `## §?R<n>`, Q sub-headings `### R<n>-Q<m>`, source rows
# `| R<n>-S<m> |`, receipt rows `| R<n>-A..F |`.
sections = {}
for m in re.finditer(r"(?m)^## §?(R[0-9]+)\b", research):
    sections[m.group(1).lstrip("R")] = m.start()

cites = []
for m in re.finditer(r"(?<![A-Za-z0-9])RQ\s*([0-5])", doc):
    cites.append(("RQ", int(m.group(1)), None))
for m in re.finditer(r"(?<![A-Za-z0-9])R6\s*[-–]\s*Q\s*([1-5])(?:\s*[-–]\s*(\d+))?", doc):
    cites.append(("R6Q", int(m.group(1)), None))
for m in re.finditer(r"(?<![A-Za-z0-9])R(\d+)\s*[-–]\s*Q\s*(\d+)", doc):
    cites.append(("RQn", (int(m.group(1)), int(m.group(2))), None))
for m in re.finditer(r"(?<![A-Za-z0-9])R(\d+)\s*[-–]\s*S\s*(\d+)", doc):
    cites.append(("RSn", (int(m.group(1)), int(m.group(2))), None))
for m in re.finditer(r"(?<![A-Za-z0-9])R(\d+)\s*[-–]\s*([A-F])(?![A-Za-z0-9])", doc):
    cites.append(("RXn", (int(m.group(1)), m.group(2)), None))
for m in re.finditer(r"§\s*R(\d+)(?![\w-])", doc):
    cites.append(("S", int(m.group(1)), None))
for m in re.finditer(r"(?<![A-Za-z0-9-])OQ\s*(\d+)", doc, re.I):
    if not re.search(r"R6\s*[-–]?\s*$", doc[max(0, m.start() - 6):m.start()], re.I):
        cites.append(("OQ", None, int(m.group(1))))

if not any(kind == "S" and n == 19 for kind, n, _ in cites):
    sys.exit("the boot note cites NO §R19 heading — every q27 number must trace to the research round (AC1/C16 T1; the resolver is EXTENDED, never dodged — AC4-C14)")

errs = []
for kind, n, extra in sorted({c for c in cites}, key=lambda c: (str(c[0]), str(c[1]), str(c[2]))):
    if kind == "RQ":
        if n not in rq:
            errs.append(f"RQ{n}: no '## RQ{n} —' heading in RESEARCH.md")
    elif kind == "R6Q":
        if n not in r6q:
            errs.append(f"R6-Q{n}: no '### R6-Q{n} —' heading in the §R6 block")
    elif kind == "RQn":
        sec, q = n
        if str(sec) not in sections:
            errs.append(f"§R{sec}: no '## §R{sec}' section in RESEARCH.md")
        elif not re.search(r"(?m)^### R%s-Q%s\b" % (sec, q), research[sections[str(sec)]:]):
            errs.append(f"R{sec}-Q{q}: no '### R{sec}-Q{q}' heading in the §R{sec} block")
    elif kind == "RSn":
        sec, s = n
        if str(sec) not in sections:
            errs.append(f"§R{sec}: no '## §R{sec}' section in RESEARCH.md")
        elif not re.search(r"(?m)^\| R%s-S%s \|" % (sec, s), research[sections[str(sec)]:]):
            errs.append(f"R{sec}-S{s}: no source row '| R{sec}-S{s} |' in the §R{sec} Sources table")
    elif kind == "RXn":
        sec, x = n
        if str(sec) not in sections:
            errs.append(f"§R{sec}: no '## §R{sec}' section in RESEARCH.md")
        elif not re.search(r"(?m)^\| R%s-%s \|" % (sec, x), research[sections[str(sec)]:]):
            errs.append(f"R{sec}-{x}: no receipt row '| R{sec}-{x} |' in the §R{sec} table")
    elif kind == "S":
        if str(n) not in sections:
            errs.append(f"§R{n}: RESEARCH.md has no '## §R{n}' section")
    elif kind == "OQ":
        if extra > main_oq:
            errs.append(f"OQ{extra}: the main open-questions list has only {main_oq} numbered items")

if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PY
  then
    fail "T1: a citation in the boot note does not resolve (C16 T1 — §R19/R19-Q<n>/R19-S<n>/R19-A..F must land on real RESEARCH.md headings, diagnostics above)"
  fi
  ok "T1: the boot note exists ($lines lines), carries steps 0-7 in order, states the D1 posture up top, obeys the OWNER-EXECUTED command law, and every §R19/R19-Q/R19-S/receipt citation resolves"
fi

# --- T2: the ONE fenced args block == the landed q27 subtree ---------------------
if want t2; then
  for f in "$NOTE" "$VALS"; do
    [ -f "$f" ] || fail "T2: $f missing — the args equality needs the C16 note AND the landed C15 subtree (the real dependency, chunks/C16.md)"
  done
  rc=0
  python3 - "$NOTE" "$VALS" <<'PY' || rc=$?
import re, sys, yaml, collections
note_path, vals_path = sys.argv[1:3]
note = open(note_path).read()
svc = yaml.safe_load(open(vals_path))
sub = (svc.get("radiance-q27") or {})
try:
    landed = [str(a) for a in sub["app-template"]["controllers"]["radiance"]["containers"]["radiance"]["args"]]
except (KeyError, TypeError):
    sys.exit("cf-143 C15/C16: the radiance-q27 overlay subtree carries no controllers.radiance.containers.radiance.args list — dev D2 has not landed it (the note's equality compares against the LANDED subtree, never a re-typed copy)")

def flag_multiset(tokens):
    out, i = collections.Counter(), 0
    while i < len(tokens):
        tok = tokens[i]
        if not isinstance(tok, str) or not tok.startswith("--"):
            i += 1; continue
        if "=" in tok:
            f, v = tok.split("=", 1); out[(f, v)] += 1; i += 1
        elif i + 1 < len(tokens) and not str(tokens[i + 1]).startswith("--"):
            out[(tok, str(tokens[i + 1]))] += 1; i += 2
        else:
            out[(tok, None)] += 1; i += 1
    return out

landed_ms = flag_multiset(landed)
blocks = re.findall(r"```[^\n]*\n(.*?)```", note, re.S)
args_blocks = [b for b in blocks if "--model" in b and "--port" in b]
shipped = [b for b in args_blocks if "--served-model-name qwen3.8-27b-radiance" in b]
errs = []
if len(shipped) != 1:
    errs.append(f"expected EXACTLY ONE fenced q27 args block (the boot expectation), found {len(shipped)} — a SECOND args block anywhere in the note is the §D54-F drift class")
elif len(args_blocks) != 1:
    extras = [b[:60] for b in args_blocks if b not in shipped]
    errs.append(f"additional fenced args block(s) found besides the shipped one: {extras} — the note documents ONE serving profile")
else:
    toks = shipped[0].replace("\\\n", " ").split()
    note_ms = flag_multiset(toks)
    if note_ms != landed_ms:
        only_note = {f"{k[0]} {k[1]}": v for k, v in (note_ms - landed_ms).items()}
        only_landed = {f"{k[0]} {k[1]}": v for k, v in (landed_ms - note_ms).items()}
        errs.append(f"note args block != the landed radiance-q27 subtree: note-side {only_note}, subtree-side {only_landed}")
if errs:
    print("; ".join(errs), file=sys.stderr); sys.exit(1)
PY
  if [ "$rc" -ne 0 ]; then
    fail "T2: the one-block law or the subtree equality is violated (C16 T2 / C06 idiom — diagnostics above)"
  fi
  ok "T2: exactly one fenced q27 args block, and its flag/value multiset EQUALS the landed radiance-q27 overlay subtree"
fi

# --- T3: OWNER-EXECUTED marker law on scale/sync/df + the DOWN-first order --------
if want t3; then
  [ -f "$NOTE" ] || fail "T3: $NOTE missing (see T1)"
  if ! python3 - "$NOTE" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()
errs = []
OWNER = re.compile(r"(?i)owner[- ](?:executed|lane)")
CMD = re.compile(r"(^\s*(?:\$\s*)?kubectl\s+scale\b|^\s*(?:\$\s*)?df\b[^\n]*-|`df -|[`\s]df\s+-[a-zA-Z])")
for i, ln in enumerate(lines):
    if re.match(r"^\s*#", ln):
        continue
    if CMD.search(ln) and not any(OWNER.search(x) for x in (ln, lines[i - 1] if i else "")):
        errs.append(f"{i+1}: unmarked scale/sync/df command line (OWNER-EXECUTED on this or the previous line — the C13 r1 adjacency law): {ln.strip()[:90]}")
# Order runs on the RAW text: joined lines would let the [^\n] windows leak
# across line boundaries and the DOWN/UP positions would mis-compare.
raw = "\n".join(lines)
down = re.search(r"kubectl[^\n]{0,120}scale[^\n]{0,60}gpu-ai-radiance(?![\w-])[^\n]{0,60}(--replicas=?0|replicas 0)", raw)
up = re.search(r"kubectl[^\n]{0,120}scale[^\n]{0,60}gpu-ai-radiance-q27[^\n]{0,60}(--replicas=?1|replicas 1)", raw)
if not down:
    errs.append("the note does not record the fn scale-DOWN command (the D1 step-2 switch: kubectl scale deployment gpu-ai-radiance --replicas=0)")
if not up:
    errs.append("the note does not record the q27 scale-UP command (the D1 step-2 switch: kubectl scale deployment gpu-ai-radiance-q27 --replicas=1)")
if down and up and down.start() >= up.start():
    errs.append("the q27 scale-UP appears BEFORE the fn scale-DOWN — the order IS the discipline (one device, non-subtractable claims, 9.80 GiB headroom: both-up lands Pending, C16 T3/T5)")
if errs:
    print("; ".join(errs[:8]), file=sys.stderr); sys.exit(1)
PY
  then
    fail "T3: the OWNER-EXECUTED marker law or the DOWN-first scale order is violated (C16 T3 — repair prose, never the arm)"
  fi
  ok "T3: scale/sync/df lines carry the OWNER-EXECUTED marker (same or previous line) and the switch order is fn DOWN first, THEN q27 UP"
fi

# --- T4: attribution arms, synthesis-proven green-both-ways ----------------------
if want t4; then
  [ -f "$NOTE" ] || fail "T4: $NOTE missing (see T1)"
  rc=0
  python3 - "$NOTE" <<'PY' || rc=$?
import re, sys
note_path = sys.argv[1]

def problems(text):
    """Speed-figure attribution law (§R19-Q4 / D54(4) — the ticket has been
    charged TWICE for unconditioned figures). Returns the violation list;
    empty means clean."""
    errs = []
    flat = " ".join(text.split())
    rules = {
        "122": (r"(?i)(model card|creator)", r"(?i)(tp ?1|single[ -]stream|one stream|1 stream)", r"(?i)(77|prose|mixed)"),
        "116": (r"(?i)(wilde|third[ -]party)", r"(?i)(n ?= ?4|64 ?k|gen ?4)"),
        "280": (r"(?i)(4[ -]stream|four stream|@4|total)",),
    }
    for fig, pats in rules.items():
        for m in re.finditer(r"(?<![\d.])" + fig + r"(\.\d+)?(?![\w])", flat):
            window = flat[max(0, m.start() - 240): m.end() + 240]
            if not re.search(r"(?i)(tok|speed|decode|throughput)", window):
                continue                     # a figure in a non-speed context stays inert
            missing = [p for p in pats if not re.search(p, window)]
            if missing:
                errs.append(f"bare {fig} tok/s claim without its attribution (needed: {len(pats)} condition tokens, missing {len(missing)}): …{window[max(0, m.start()-max(0,m.start()-240)):][:160]}…")
    for i, ln in enumerate(text.splitlines()):
        if re.search(r"(?i)flash[ -]?next", ln) and re.search(r"(?i)tok\s*/\s*s|t/s", ln) \
           and re.search(r"(?i)radiance", ln) and re.search(r"\d{2,4}", ln) \
           and not re.search(r"(?i)(no|not|never|none|unpublish|without|zero|does not exist|absent)", ln):
            errs.append(f"line {i+1}: a Flash-Next TP1 radiance tok/s FIGURE is published — none exists (§R19-Q4 re-survives: 'Flash-Next on a single R9700 in Radiance has no published speed'): {ln.strip()[:100]}")
    return errs

# GREEN-BOTH-WAYS self-proof FIRST (§12.14): the truthful attributed rows
# must pass, the bare-122 + fn-figure fixtures must fail. A validator that
# cannot do both exits 2 — a broken arm is LOUDER than a missing note.
green = ("122 / prose 77 / code 164 / 280@4-streams = model card TP1 (creator); "
         "116 = Thomas Wilde third-party n=4 at 64K on a Gen4 board; "
         "Flash-Next on a single R9700 in Radiance has no published speed (§R19-Q4).")
red = "q27 reaches 122 tok/s on one card; the Flash-Next radiance pod does 140 tok/s decode."
if problems(green):
    print("T4 validator self-DEFECT: the truthful attributed fixture FAILED: " + "; ".join(problems(green)), file=sys.stderr)
    sys.exit(2)
if not problems(red):
    print("T4 validator self-DEFECT: the bare-122 / fn-figure fixture PASSED — the arm is half a tripwire", file=sys.stderr)
    sys.exit(2)

errs = problems(open(note_path).read())
if errs:
    print("; ".join(errs[:8]), file=sys.stderr); sys.exit(1)
PY
  case "$rc" in
    0) ok "T4: attribution arms hold (122 = model card TP1 single-stream with the prose-77 co-window; 116 = Wilde/third-party n=4 64K Gen4; 280 = 4-stream total; no Flash-Next radiance figure ships — §R19-Q4), green-both-ways self-proven on the embedded fixtures" ;;
    2) fail "T4: the attribution validator FAILED ITS OWN fixture probe (a half tripwire cannot bless the note) — diagnostics above; the TEST lane owns this repair" ;;
    *) fail "T4: an unattributed speed figure or a published fn-TP1 radiance figure is in the boot note (C16 T4 — bare 122 goes RED, diagnostics above)" ;;
  esac
fi

# --- T5: the ban legs (keyless, /v1, don't-sync, the 502 idle law) + order synthesis ----------
if want t5; then
  [ -f "$NOTE" ] || fail "T5: $NOTE missing (see T1)"
  rc=0
  RAD_KEYLESS_TOKEN="$KEYLESS_ENV_TOKEN" python3 - "$NOTE" <<'PY' || rc=$?
import os, re, sys
note_path = sys.argv[1]
TOKEN = os.environ["RAD_KEYLESS_TOKEN"]

def problems(text):
    errs = []
    blocks = re.findall(r"```[^\n]*\n(.*?)```", text, re.S)
    for b in blocks:
        if "--api-key" in b:
            errs.append(f"the DROPPED --api-key rider appears in a FENCED command — the note must never print a runnable keyed boot (D54(2)): {b.strip()[:90]}")
    lines = text.splitlines()
    for i, ln in enumerate(lines):
        if TOKEN in ln:
            inside = any(ln in b for b in blocks)
            neigh = " ".join(lines[max(0, i - 1):i + 2])
            if inside or not re.search(r"(?i)(dropp|no key|keyless|rider)", neigh):
                errs.append(f"line {i+1}: the keyless env token appears outside a dropped-rider prose mark (AC6: every such line sits in prose NAMED dropped): {ln.strip()[:90]}")
    for i, ln in enumerate(lines):
        if "svc.cluster.local" in ln and "/v1" in ln:
            errs.append(f"line {i+1}: a proxy URL printed with a /v1 suffix — request paths append verbatim: {ln.strip()[:90]}")
    # Whitespace-collapsed: markdown prose wraps, and the interlock tokens
    # must match across line breaks exactly as the pytest validator does.
    flat = " ".join(text.split())
    sync_windows = [flat[m.start():m.start() + 400] for m in re.finditer(r"(?i)(do ?n[o']t|never)\s+\w*\s*sync\b", flat)]
    if not any("gpu-ai-radiance-q27" in w and "gpu-ai-llama-swap" in w for w in sync_windows):
        errs.append("the don't-sync law does not name BOTH gpu-ai-radiance-q27 and gpu-ai-llama-swap (AC7: the q27 lane AND the strata-window app, the D31/D32 unchanged law)")
    # Idle law (C15-r2 re-pin): the note carries the SOURCED interlock — the
    # 503 the first wave armed was a coord parenthetical treated as evidence
    # (D54(4) class); llama-swap's ErrorHandler over a no-endpoints dial is
    # a 502 peer proxy error. Dev writes the canonical sentence verbatim.
    if re.search(r"(?<![0-9])503(?![0-9])", flat):
        errs.append("the note still claims the 503 idle code — unsourced and wrong; the sourced "
                    "shape is the 502 peer-proxy-error sentence (C15-r2 interlock)")
    for pat, tok in ((r"(?<![0-9])502(?![0-9])", "502"), (r"(?i)peer proxy error", "peer proxy error"),
                     (r"(?i)\bno endpoints\b", "no endpoints"), (r"(?i)\bloud\b", "loud"),
                     (r"(?i)never silent", "never silent")):
        if not re.search(pat, flat):
            errs.append(f"idle-law interlock token missing: {tok!r} (the canonical sentence: 502 peer proxy error / no endpoints / loud / never silent)")
    # Order runs on the RAW text (joined lines would let [^\n] windows leak
    # across the fence and mis-compare DOWN/UP positions — self-test caught
    # it at authoring, §12.14's fixture-probe habit applied to OUR arms).
    raw = "\n".join(lines)
    down = re.search(r"kubectl[^\n]{0,120}scale[^\n]{0,60}gpu-ai-radiance(?![\w-])[^\n]{0,60}(--replicas=?0|replicas 0)", raw)
    up = re.search(r"kubectl[^\n]{0,120}scale[^\n]{0,60}gpu-ai-radiance-q27[^\n]{0,60}(--replicas=?1|replicas 1)", raw)
    if down and up and down.start() >= up.start():
        errs.append("scale order inverted in the note body — DOWN first, THEN UP (the three independent blockers make both-up Pending, §R19/§D54-H)")
    return errs

# The order fixture PROVES the arm bites (§12.14 green-both-ways): the
# reversed line must FAIL the validator, the correct order must pass.
correct = ("OWNER-EXECUTED: kubectl scale deployment gpu-ai-radiance --replicas=0\n"
           "OWNER-EXECUTED: kubectl scale deployment gpu-ai-radiance-q27 --replicas=1\n"
           "do not sync gpu-ai-radiance-q27 while using it, and do not sync gpu-ai-llama-swap during any strata dance; "
           "while q27 rests at replicas 0, the peers.radiance-q27 hop fails with a 502 peer proxy error "
           "(the Service has no endpoints; llama-swap neither health-checks nor hides peers) — loud, never silent.")
reversed_fixture = ("OWNER-EXECUTED: kubectl scale deployment gpu-ai-radiance-q27 --replicas=1\n"
                    "OWNER-EXECUTED: kubectl scale deployment gpu-ai-radiance --replicas=0\n"
                    "do not sync gpu-ai-radiance-q27 while using it, and do not sync gpu-ai-llama-swap; "
                    "while q27 rests at replicas 0, the peers.radiance-q27 hop fails with a 502 peer proxy error "
                    "(the Service has no endpoints; llama-swap neither health-checks nor hides peers) — loud, never silent.")
if problems(correct):
    print("T5 validator self-DEFECT: the correct-order fixture FAILED: " + "; ".join(problems(correct)), file=sys.stderr)
    sys.exit(2)
if not problems(reversed_fixture):
    print("T5 validator self-DEFECT: the REVERSED-ORDER fixture PASSED — the order arm is half a tripwire", file=sys.stderr)
    sys.exit(2)

errs = problems(open(note_path).read())
if errs:
    print("; ".join(errs[:8]), file=sys.stderr); sys.exit(1)
PY
  case "$rc" in
    0) ok "T5: bans hold (no --api-key in any fenced command; the dropped rider appears only as prose marked dropped; no /v1 on printed proxy URLs; don't-sync names BOTH apps; the 502 idle-law interlock holds — 502 / peer proxy error / no endpoints / loud / never silent, 503 purged; the DOWN-first order holds) — order+idle arms synthesis-proven both ways" ;;
    2) fail "T5: the ban validator FAILED ITS OWN fixture probe (a half tripwire cannot bless the note) — the TEST lane owns this repair" ;;
    *) fail "T5: a ban leg fired (C16 T5 — keyed line in a fence, /v1 on a proxy URL, don't-sync missing an app name, a broken 502 idle-law interlock, or inverted order; diagnostics above)" ;;
  esac
fi

# --- T6: cf-144 C02 — the TP2 annotation arms (claim-math, pool=2, parked-window sync) ----
if want t6; then
  [ -f "$NOTE" ] || fail "T6: $NOTE missing (see T1)"
  rc=0
  RAD_R9700="$R9700_CLAIM" python3 - "$NOTE" <<'PY' || rc=$?
import os, re, sys
POOL = os.environ["RAD_R9700"]
text = open(sys.argv[1]).read()
flat = " ".join(text.split())
errs = []
# The dated annotation exists (cf-144 carried into the boot note):
if "cf-144" not in flat:
    errs.append("no cf-144 annotation in the boot note — C02's dated marker is missing (annotate-never-rewrite: the historical text stays)")
# pool is 2 + fn TP2 claim-2 (git truth the owner reads on the next swap):
if not re.search(r"(?i)pool is (now )?2\b|" + POOL + r"(?![0-9-])[^\n]{0,8}[:=][^\n]{0,4}\D{0,3}2\b", flat):
    errs.append(f"the note never states the TP2 pool truth: pool is 2 / {POOL}: 2 on the LIVE pool name (git post-C01)")
if not (re.search(r"(?i)fn[^.]{0,120}(TP2|tensor[ -]parallel 2)[^.]{0,120}claim[^.]{0,40}2|claim[ -]2[^.]{0,120}(TP2|fn)", flat)
        or re.search(r"(?i)(both cards|2 of 2)", flat)):
    errs.append("the note never states fn TP2 claim-2 in git (one pod holding BOTH cards)")
# THE claim-math sentence (P05/OQ-A: the swap discipline is now claim-math,
# not pool-capacity-1; the fn-DOWN-first order law survives unchanged —
# T3/T5 keep policing it):
if not re.search(r"(?i)claim[ -]?math", flat):
    errs.append("the claim-math re-framing is missing: the swap discipline under fn-TP2 is CLAIM-MATH (fn UP holds both cards ⇒ q27 can only schedule with fn DOWN), annotate-never-rewrite")
if not re.search(r"(?i)(fn (is )?UP[^.]{0,160}(both|2)|holds both cards)[^.]{0,240}(q27[^.]{0,80}(DOWN|only|schedule)|schedule[^.]{0,80}DOWN)", flat):
    errs.append("the claim-math arithmetic sentence is missing (fn UP holds both cards ⇒ q27 schedules only with fn DOWN)")
# Parked-window sync truth from the plan's Landing shape (loud, designed):
if not re.search(r"(?is)(first|next)[^.]{0,60}TP2 sync[^.]{0,320}Pending[^.]{0,320}(until q27|q27 (DOWN|down|must be)|scale q27|loud|designed|by design)|TP2 sync[^.]{0,320}(q27 UP|UP with)[^.]{0,200}Pending", flat):
    errs.append("the parked-window sync truth is missing: the FIRST TP2 sync while q27 is UP lands fn Pending until q27 goes DOWN — loud, designed (plan Landing shape; nothing here pre-edits it in GitOps)")
# Zero-softening bars: the TP2 annotation must not reintroduce the dead
# capacity-1 phrasing as if it were the ONLY truth, nor move the resting
# pair. (The 502 interlock, /v1, keyed-line and DOWN-first order pins are
# byte-stable in T3/T5 and run regardless of this section.)
if not re.search(r"(?i)capacity-1[^.]{0,240}(was|historical|then|pre[ -]TP2)|(was|were) capacity-1", flat):
    if re.search(r"(?i)pool is capacity-1|capacity-1 pool", flat):
        errs.append("the capacity-1 blocker reads as PRESENT-TENSE truth — under cf-144 it is the historical shape (the pool is 2; the blocker moved to claim-math): annotate, never leave the sentence unmarked")
if not re.search(r"(?i)fn 1 / q27 0|resting", flat):
    errs.append("the git resting pair (fn 1 / q27 0) lost its statement — TP2 decides NEW git resting state VALUES, not live scale; the pair stays fn 1 / q27 0")
if errs:
    print("; ".join(errs[:8]), file=sys.stderr); sys.exit(1)
PY
  case "$rc" in
    0) ok "T6: the cf-144 C02 annotations hold (dated cf-144 marker; pool=2 + fn TP2 claim-2 in git; the claim-math re-framing with its arithmetic; the parked-window first-TP2-sync Pending truth; the capacity-1 blocker stays annotated-as-history and the fn 1 / q27 0 resting pair is stated)" ;;
    *) fail "T6: a cf-144 C02 boot-note arm fired (diagnostics above) — repair the prose in ONE commit with its needle re-pin (annotate-never-rewrite)" ;;
  esac
fi

printf 'PASS: radiance q27 boot-note contract checks (%d ok)\n' "$checks"
