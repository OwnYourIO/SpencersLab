#!/usr/bin/env bash
# cf-143 C03 — the second-GPU (TP2) expansion doc contract
# (chunks/C03.md Tests T1-T3): .agents/notes/radiance-second-gpu-tp2.md is
# the ONLY content source for the run-end Inbox follow-up card ("Radiance
# second-GPU (TP2) expansion", Q6 ruling), so the doc is pinned to exist,
# structured, RESEARCH-cited (never the card guide's stale numbers), and
# needle-complete on the rulings it carries (TP2 recipe corrections, the
# enumeration law, the APU-hide interdependency, the coexistence-relief
# reading under C07's product naming, the DRA alternative lane).
#
# Designed-RED at test-write: the doc does not exist yet (T1 names C03).
#
# T2 is the vllm-runbook T4 resolver idiom pointed at THIS folder's
# RESEARCH.md (incl. the §R6 block): every RQ<n> / R6-Q<n>(-<row>) / §R6 /
# OQ<m> / R6 OQ<m> citation must land on a real heading, and the doc must
# cite RESEARCH at least once (cited-number honesty law, DECISIONS
# 'Profile numbers come from RESEARCH').
#
# Run from the repo root:
#   bash tests/notes/radiance-tp2.sh            # T1..T3
#   bash tests/notes/radiance-tp2.sh T2         # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

DOC="${RAD_TP2_DOC:-.agents/notes/radiance-second-gpu-tp2.md}"
RESEARCH="${RAD_TP2_RESEARCH:-.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/RESEARCH.md}"
CARD_TITLE="Radiance second-GPU (TP2) expansion"

# ---------------------------------------------------------------------------
# GPU RESOURCE-NAME CONSTANTS — C08 D24 lane ruling landed (marked bash twin
# of charts/amd-gpu/tests/amd_gpu_testlib.py; future lane moves edit both).
R9700_CLAIM="amd.com/gpu-r9700-1"
APU_CLAIM="amd.com/gpu-8060s"
R9700_POOL="${R9700_CLAIM#amd.com/}"

checks=0

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok()  { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for t in 1 2 3; do WANT["t$t"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-3]$ ]] || fail "unknown test id '$a' (expected T1..T3)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- T1: doc exists, ≥12 structured sections, provenance + card title -----------
if want t1; then
  [ -f "$DOC" ] || fail "T1: $DOC missing — C03 (the TP2 expansion doc) is not implemented"
  lines=$(wc -l < "$DOC")
  if [ "$lines" -lt 100 ]; then
    fail "T1: the doc is only $lines lines — hardware path + enumeration law + TP2 recipe + envelope + second-lane + adoption steps cannot fit (want >= 100)"
  fi
  sections=$(grep -cE '^#{2,6} ' "$DOC" || true)
  if [ "$sections" -lt 12 ]; then
    fail "T1: only $sections section headings (want >= 12 numbered/structured sections — chunks/C03.md Tests T1)"
  fi
  head40=$(head -40 "$DOC")
  printf '%s' "$head40" | grep -q "cf-143" \
    || fail "T1: the header carries no cf-143 provenance line (plan folder / ruling round)"
  printf '%s' "$head40" | grep -qiF "$CARD_TITLE" \
    || fail "T1: the header does not name the follow-up card title it feeds ('$CARD_TITLE') — AC3: doc and coord's Inbox card cannot drift apart"
  printf '%s' "$head40" | grep -qiE 'feeds|follow-up card' \
    || fail "T1: no 'feeds follow-up card' line in the header (AC3)"
  ok "T1: the doc exists ($lines lines, $sections sections) with cf-143 provenance and the follow-up-card title '$CARD_TITLE'"
fi

# --- T2: citation resolver into RESEARCH.md --------------------------------------
if want t2; then
  [ -f "$DOC" ] || fail "T2: $DOC missing (see T1)"
  [ -f "$RESEARCH" ] || fail "T2: $RESEARCH missing (this folder's research record)"
  if ! python3 - "$DOC" "$RESEARCH" <<'PY'
import os, re, sys
doc = open(sys.argv[1]).read()
research = open(sys.argv[2]).read()

rq = {int(m.group(1)) for m in re.finditer(r"(?m)^## RQ([0-5]) —", research)}
m_r6 = re.search(r"(?m)^## R6 —", research)
r6_part = research[m_r6.start():] if m_r6 else ""
r6q = {int(m.group(1)) for m in re.finditer(r"(?m)^### R6-Q([1-5]) —", r6_part)}
m_r7 = re.search(r"(?m)^## §?R7", research)  # heading carries the § literally (## §R7 —)
r7_part = research[m_r7.start():] if m_r7 else ""
r7q = {int(m.group(1)) for m in re.finditer(r"(?m)^### R7-Q([0-9]+) —", r7_part)}

# cf-143 C16 re-pin (AC4-C14 precedent: EXTEND the resolver, never dodge by
# dropping citations): the §9/§11 SHIPPED annotations cite the later rounds —
# every §R<n> section, R<n>-Q<m> sub-heading and R<n>-S<m> source row
# resolves generically (§R19 included).
sections = {}
for m in re.finditer(r"(?m)^## §?(R[0-9]+)\b", research):
    sections[m.group(1).lstrip("R")] = m.start()

def numbered_items(section_text):
    return len(re.findall(r"(?m)^\d+\.\s", section_text))

m_oq = re.search(r"(?m)^## Open questions .*$", research)
oq_block = ""
if m_oq:
    rest = research[m_oq.end():]
    stop = re.search(r"(?m)^(## |RESULT)", rest)
    oq_block = rest[: stop.start() if stop else len(rest)]
main_oq = numbered_items(oq_block)
m_r6oq = re.search(r"(?m)^### R6 — Open questions.*$", r6_part)
r6_oq = 0
if m_r6oq:
    rest = r6_part[m_r6oq.end():]
    stop = re.search(r"(?m)^(### |RESULT)", rest)
    r6_oq = numbered_items(rest[: stop.start() if stop else len(rest)])

def r6q_rows(q):
    m = re.search(r"(?m)^### R6-Q%s —.*?(?=^### |\Z)" % q, r6_part, re.S)
    if not m:
        return set()
    return {int(mm.group(1)) for mm in re.finditer(r"(?m)^\|\s*(\d+)\s*\|", m.group(0))}

cites = []
for m in re.finditer(r"(?<![A-Za-z0-9])RQ\s*([0-5])", doc):
    cites.append(("RQ", int(m.group(1)), None))
for m in re.finditer(r"(?<![A-Za-z0-9])R6\s*[-–]\s*Q\s*([1-5])(?:\s*[-–]\s*(\d+))?", doc):
    cites.append(("R6Q", int(m.group(1)), int(m.group(2)) if m.group(2) else None))
for m in re.finditer(r"§\s*R6(?![\w-])", doc):
    cites.append(("S6", None, None))
for m in re.finditer(r"(?<![A-Za-z0-9])R7\s*[-–]\s*Q\s*([0-9]+)", doc):
    cites.append(("R7Q", int(m.group(1)), None))
for m in re.finditer(r"§\s*R7(?![\w-])", doc):
    cites.append(("S7", None, None))
# C16 generic-round extracts (run AFTER the R6/R7 special forms so the row
# shape of those legs stays byte-verbatim; duplicates are set-collapsed):
for m in re.finditer(r"(?<![A-Za-z0-9])R(\d+)\s*[-–]\s*Q\s*(\d+)", doc):
    cites.append(("RQn", (int(m.group(1)), int(m.group(2))), None))
for m in re.finditer(r"(?<![A-Za-z0-9])R(\d+)\s*[-–]\s*S\s*(\d+)", doc):
    cites.append(("RSn", (int(m.group(1)), int(m.group(2))), None))
for m in re.finditer(r"§\s*R(\d+)(?![\w-])", doc):
    cites.append(("S", int(m.group(1)), None))
for m in re.finditer(r"(?<![A-Za-z0-9])R6\s+OQ\s*(\d+)", doc, re.I):
    cites.append(("R6OQ", None, int(m.group(1))))
for m in re.finditer(r"(?<![A-Za-z0-9-])OQ\s*(\d+)", doc, re.I):
    if not re.search(r"R6\s*[-–]?\s*$", doc[max(0, m.start() - 6):m.start()], re.I):
        cites.append(("OQ", None, int(m.group(1))))

if not cites:
    sys.exit("the doc cites NO research heading — C03 AC1: every numeric claim resolves to a "
             "RESEARCH.md heading (RQ<n> / R6-Q<n>(-<row>) / §R6 / OQ<m> forms, T4-style)")

errs = []
for kind, n, extra in sorted(set(cites), key=lambda c: (c[0], str(c[1]), c[2] or 0)):
    if kind == "RQ":
        if n not in rq:
            errs.append(f"RQ{n}: no '## RQ{n} —' heading in RESEARCH.md")
    elif kind == "R6Q":
        if n not in r6q:
            errs.append(f"R6-Q{n}: no '### R6-Q{n} —' heading in the §R6 block")
        elif extra is not None and extra not in r6q_rows(n):
            errs.append(f"R6-Q{n}-{extra}: no table row {extra} inside '### R6-Q{n}'")
    elif kind == "S6":
        if not m_r6:
            errs.append("§R6: RESEARCH.md has no R6 section")
    elif kind == "R7Q":
        if n not in r7q:
            errs.append(f"R7-Q{n}: no '### R7-Q{n}' heading in the §R7 block")
    elif kind == "S7":
        if not m_r7:
            errs.append("§R7: RESEARCH.md has no R7 section")
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
    elif kind == "S":
        if str(n) not in sections:
            errs.append(f"§R{n}: RESEARCH.md has no '## §R{n}' section")
    elif kind == "R6OQ":
        if extra > r6_oq:
            errs.append(f"R6 OQ{extra}: the R6 open-questions list has only {r6_oq} numbered items")
    elif kind == "OQ":
        if extra > main_oq:
            errs.append(f"OQ{extra}: the main open-questions list has only {main_oq} numbered items")

if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
print(f"{len(set(cites))} citation forms resolve", file=sys.stderr)
PY
  then
    fail "T2: a RESEARCH citation in the doc does not resolve (C03 AC1 — stale pointer, diagnostics above)"
  fi
  ok "T2: citation resolver — every RQ<n>/R6-Q<n>(-row)/§R6/§R<n>/R<n>-Q<n>/R<n>-S<n>/OQ<m> reference in the doc lands on a real heading of this folder's RESEARCH.md (incl. the §R6 block and the C16-extension generic rounds — the SHIPPED annotations' §R19 cites resolve, never dodge)"
fi

# --- T3: the needle set + the two absence bars -----------------------------------
if want t3; then
  [ -f "$DOC" ] || fail "T3: $DOC missing (see T1)"
  rc=0
  RAD_R9700="$R9700_POOL" python3 - "$DOC" <<'PY' || rc=$?
import os, re, sys
doc = open(sys.argv[1]).read()
flat = " ".join(doc.split())
low = doc.lower()
errs = []

def need(needle, where, flags=0):
    if not re.search(needle, doc, flags):
        errs.append(f"needle missing in {where}: {needle!r}")

# TP2 compose recipe (corrected, RESEARCH Serving envelope + RQ4): wht6 wire,
# per-rank pool 12288, and the either/or law the TP2 shape turns ON.
need(r"wht6", "the TP2 compose recipe (wire quant, corrected recipe)")
need(r"12288", "the TP2 per-rank host pool")
need(r"(?is)(prefix.cache|kv.resident)[^\n]{0,240}(mutually|either|instead|exclusive)|(exclusive|either)[^\n]{0,240}(prefix.cache|kv.resident)",
     "the prefix-vs-kv-resident either/or (TP2 frees VRAM to choose the prefix tier AGAIN; the one-card build is forced onto --kv-resident)")
need(r"(?i)no RCCL", "the three-way naming disambiguation: radiance uses no RCCL — the crash-class note belongs to the vLLM lineage only")
need(r"120 ?W", "the Strix OCuLink ~120 W power caveat")

# Enumeration law + the re-enumeration checklist heading exists (C03 Tests T1/T3).
if not re.search(r"(?m)^#{1,6}.*re-?enumeration", doc, re.I):
    errs.append("no re-enumeration CHECKLIST heading (the third GPU shifts EVERY rocrVisibleDevices index)")
need(r"rocrVisibleDevices", "the enumeration law")

# APU-hide interdependency: vfio-pci hiding kills the outer llama-swap APU lane.
need(r"(?i)vfio-pci", "the APU-hide interdependency")
need(r"1002:1640|1640", "the audio-function id in the vfio pair")
need(r"(?is)vfio[^\n]{0,400}(kill|breaks|loses|unusable)|(kill|breaks|loses|unusable)[^\n]{0,400}vfio|8060[sS][^\n]{0,400}(vfio)|(vfio)[^\n]{0,400}8060[sS]",
     "the interdependency statement (hiding the APU kills the outer 8060S GGUF lane — not a drive-by)")
need(r"amd\.com/gpu", "the amd.com/gpu naming surface the hide would have changed")

# Absence bars: the stale guide flag inside a 'stale, do not use' mention only,
# and the guide's GB/s figures never presented as verified fact.
for m in re.finditer(r"--expert-vs-cache-ratio", doc):
    window = doc[max(0, m.start() - 200): m.end() + 200].lower()
    if "stale" not in window and "do not use" not in window:
        errs.append("--expert-vs-cache-ratio appears OUTSIDE a stale/do-not-use mention "
                    f"near offset {m.start()} (AC1: the absence-needle exception is explicit only)")
for figure in ("28.07", "54.7"):
    for m in re.finditer(re.escape(figure), doc):
        window = doc[max(0, m.start() - 200): m.end() + 200].lower()
        if not any(w in window for w in ("unverifiable", "direction-only", "direction only", "recorded as direction")):
            errs.append(f"the guide's {figure} GB/s figure appears WITHOUT the direction-only/"
                        f"unverifiable framing near offset {m.start()} (C03: UNVERIFIABLE, direction only)")
if re.search(r"radiance\s+serve\b", doc, re.I):
    errs.append("a 'radiance serve' VERB token — the engine has no serve verb (RESEARCH RQ0); TP2 compose flags are args on the engine command")

# Product-naming world (post-C07 reading of TP2): the pool-count-2 mechanic +
# the revision receipt carrying to the new card + the DRA alternative lane.
need(re.escape(os.environ["RAD_R9700"]), "the D24-renamed pool name (same-revision second card joins the same pool, count 2 — the pool-count mechanics are name-agnostic, the STRING is the ruling)")
# C08 T-E (amendment): the TP2 RE-VERIFICATION LAW — a second/third card is absent from the
# MINIMAL patched table by construction; its (device,revision) row must carry or be ADDED
# before TP2 scheduling is trusted (bare-fallback trap).
need(r"(?i)(re-?verif|carries?\b|added?\b)[^.\n]{0,160}(before|beforehand|first)[^.\n]{0,80}(tp2|schedul|trusting)|(tp2|second|third)[^.\n]{0,120}(re-?verif|verify|before trusting)", "the TP2 re-verification law (§6 bullet, minimal-table era)")
need(r"(?i)minimal|patched[ -]table|amdgpu\.ids", "the minimal patched-table provenance (the law\u2019s mechanism)")
need(r"(?i)dra|resourceclaim", "the R6 ranked-2 DRA alternative lane (recorded as the alternative, not the plan)")

# cf-143 C16 re-pin — the §9/§11 annotated strings (§D54-F: "a q27 doc that
# edits TP2 §9/§11 strings re-pins this suite same-wave"). TWO shapes:
# (1) UNCONDITIONAL survival: the §9 capacity ruling sentence and the §11
# sketch key radiance-tp2 stay present — D2 ANNOTATES, it does not rewrite
# (the sketch is the historical deferred shape; the shipped names ride the
# dated note). Green on today's doc, red on a rewrite-in-place.
# (2) ONE-WAY annotation arms (§12.14 green-both-ways law): silent until the
# "SHIPPED (cf-143 C15" token appears — C15's wave has its own bar demanding
# tp2.sh 3 ok BEFORE dev D2 lands, so an unconditional demand here would
# false-red the pre-annotation tree — then fully armed: the note must name
# the RESOLVED plumbing and the still-locked co-residency shape, never a
# truncated copy. A half-written annotation REDS.
need(r"two peer pods on one GPU is NOT feasible",
     "the §9 single-card capacity ruling (C16 D2 adds a POINTER — the ruling sentence itself must survive)")
if "radiance-tp2" not in doc:
    errs.append("§11's sketch key radiance-tp2 vanished — D2 annotates the sketch with a dated SHIPPED note BESIDE it ('the key names radiance-tp2 in the sketch became radiance-q27'); rewriting the sketch in place deletes the historical deferral the annotation exists to record")

m11 = re.search(r"(?ms)^## 11\..*?(?=^## |\Z)", doc)
if m11 and "SHIPPED (cf-143 C15" in m11.group(0):
    f11 = " ".join(m11.group(0).split())
    for pat, what in (
        (r"(?i)radiance-q27", "the shipped subtree/peer name radiance-q27 (the sketch's radiance-tp2 resolved)"),
        (r"(?i)chart:\s*['\"]?radiance|roster[^.]{0,60}chart", "the RESOLVED plumbing: roster `chart:` override on charts/radiance (D56)"),
        (r"(?i)evidence", "the per-key evidence file resolution (D13 chain)"),
        (r"(?i)pod-?swap[^\n]{0,120}replicas[: ]{1,2}0|replicas[: ]{1,2}0[^\n]{0,120}pod-?swap", "the SHAPE statement: pod-swap at replicas 0 on ONE card"),
        (r"(?i)(ad-?144|second card)[^.]{0,160}re-?verif|re-?verif[^.]{0,160}(ad-?144|second card)|unlock[^.]{0,160}(card 2|second card)", "the honest limit: beside-fn co-residency STILL unlocks only with card 2 (AD-144) + the pool RE-VERIFICATION law"),
    ):
        if not re.search(pat, f11):
            errs.append(f"§11 SHIPPED annotation lacks {what}")
if m11 and re.search(r"(?i)honored", m11.group(0)):
    errs.append("the HONORED pointer was written into §11 — it belongs to §9 (the ruling §9 made); keep each section's annotation where its ruling lives")

m9 = re.search(r"(?ms)^## 9\..*?(?=^## |\Z)", doc)
if m9 and re.search(r"(?i)honored", m9.group(0)):
    if not (re.search(r"(?i)not bypassed", m9.group(0)) and re.search(r"§R19|R19-Q", m9.group(0))):
        errs.append("§9's HONORED pointer must read as D2 instructs: the ruling was HONORED, NOT BYPASSED — the pod-swap lane is exactly what the single-card arithmetic allows, cited to §R19")

# --- cf-144 C02: the TP2-SHIPPED annotation arms (designed-RED until C02
# lands; annotate-never-rewrite law, cf-143 §9/§11 marker idiom). These pin
# the OWNERSHIP facts the shipped half must record: shape A, the P11 HOLD-110
# truth, the pool-2 live witness, the §12 CONDITIONAL re-open, and the C03
# rocminfo gate TODAY. The marker shape is the cf-143 idiom extended:
# "SHIPPED (cf-144 ..." — dev copies that dated-marker shape verbatim.
f144 = " ".join(doc.split())
def need_c144(pattern, where):
    if not re.search(pattern, f144, re.I):
        errs.append(f"cf-144 C02 annotation missing in {where}: {pattern!r}")
need_c144(r"SHIPPED \(cf-144", "the dated TP2-SHIPPED marker (the §11.5 marker idiom, cf-143 C15's shape carried to cf-144)")
# Status header: the re-derivation + repo-half-shipped line (doc :11-13 area):
head144 = " ".join(" ".join(doc.splitlines()[:45]).split())
if not (re.search(r"cf-144", head144) and re.search(r"(?i)re[ -]deriv", head144)
        and re.search(r"(?i)shipped", head144)):
    errs.append("the status header (first 45 lines) lacks the dated cf-144 note that the TP2 ticket re-derived the plan and SHIPPED the repo half (append-only; the 'expansion instructions, not shipped config' line stays readable as history)")
# §4: the sweep row applies TODAY (card 2 landed 2026-11-21, rocminfo-gated):
m4 = re.search(r"(?ms)^## 4\..*?(?=^## |\Z)", doc)
f4 = " ".join(m4.group(0).split()) if m4 else ""
if not (re.search(r"(?i)card 2 landed[^.]{0,200}2026-11-21", f4)
        and re.search(r"(?i)(applies TODAY|today)", f4) and re.search(r"rocminfo", f4)):
    errs.append("§4's annotation is missing/incomplete: 'card 2 landed 2026-11-21 — the sweep row applies TODAY', rocminfo-gated (the original wording stays under the marker)")
# §6: the pool-2 live witness (EXPLORE §0):
m6 = re.search(r"(?ms)^## 6\..*?(?=^## |\Z)", doc)
f6 = " ".join(m6.group(0).split()) if m6 else ""
if not (re.search(r"(?i)c7:00\.0", f6) and re.search(r"(?i)reporting 2 devices", f6)
        and re.search(r"(?i)(row already carr|no table edit)", f6)
        and re.search(r"(?i)rocminfo", f6) and re.search(r"(?i)sysfs", f6)):
    errs.append("§6's annotation lacks the pool-2 live witness (c7:00.0 + 'Reporting 2 devices as gpu-r9700-1' + the no-table-edit finding) with the formal owner gates kept (per-BDF sysfs + rocminfo receipts)")
# §11: shape A + the HOLD-110 truth:
m11b = re.search(r"(?ms)^## 11\..*?(?=^## |\Z)", doc)
f11b = " ".join(m11b.group(0).split()) if m11b else ""
if not (re.search(r"(?i)shape A\b", f11b) and re.search(r"(?i)one pod", f11b)
        and re.search(r"(?i)(claim|gpu-r9700-1)[^.]{0,60}\b2\b", f11b)):
    errs.append("§11 step 5's SHIPPED annotation lacks the shape-A truth: fn TP2 one pod, claim 2 (OQ-A ruling)")
if not (re.search(r"(?i)(held at 110|hold 110|110 HELD|HELD[^.]{0,40}110)", f11b)
        and re.search(r"(?i)print", f11b)
        and re.search(r"(?i)(post-TP2-boot|first-boot|owner-receipt)", f11b)):
    errs.append("§11 step 5's annotation lacks the P11 HOLD-110 truth: memory ships HELD at 110, the DOWN re-pin to the printed class is a POST-TP2-BOOT OWNER-RECEIPT leg — 'the first-boot print is the budget authority' (the one §11.5 scalar NOT moved this wave)")
# §12: CONDITIONAL re-open only, at the 118.3 class, riding CUTOVER:
m12 = re.search(r"(?ms)^## 12\..*?(?=^## |\Z)", doc)
f12 = " ".join(m12.group(0).split()) if m12 else ""
if "118.3" not in f12:
    errs.append("§12's shipped-110 restatement lacks the ≈118.3 class (48+64+6.3 — the re-open number IF/when the post-boot DOWN re-pin lands; P11 records it CONDITIONAL)")
if not re.search(r"(?i)if/when|conditional|awaits|only if", f12):
    errs.append("§12's annotation must state the re-open as CONDITIONAL (if/when the DOWN re-pin lands) — at the held 110 it stays CLOSED (110+64+6.3 = 180.3 > 125.08 remains the shipped truth)")
if not re.search(r"(?i)CUTOVER", f12):
    errs.append("§12's annotation loses the CUTOVER-ticket pointer (the co-existence decision does not live on this ticket)")
# Absence bar: no sentence may claim the co-exist decision WAS TAKEN here
# (the conditional stays a pointer — plan 'Out of scope' + DECISIONS P11).
# Sentence-scoped with a NEGATION EXEMPT, self-proven green-both-ways every
# run (§12.14: the explicit "was NOT decided here" must pass, the bare
# assertion must red — an arm that reddened its own negation would push dev
# into silence, the class P11 forbids):
def _coexist_claim_violations(text):
    out = []
    for sent in re.split(r"(?<=[.;])\s+", text):
        if re.search(r"(?i)co-?exist|co-?resid", sent) and \
           re.search(r"(?i)(decided|decision (was )?(taken|made|closed|shipped)|resolved (here|in cf-144)|taken (here|on this))", sent) and \
           not re.search(r"(?i)\bnot\b|never|nothing|\bno\b|awaits|conditional|if/when|rides|only if", sent):
            out.append(sent.strip()[:120])
    return out

_truth = "at the held 110 nothing was decided here — no co-existence outcome was decided, the decision still rides the CUTOVER ticket"
_lie = "the co-existence decision was taken here in cf-144 and the re-open is closed"
if _coexist_claim_violations(_truth):
    errs.append("co-exist bar self-DEFECT: it reddens the truthful denial — half tripwire, the TEST lane owns this repair")
if not _coexist_claim_violations(_lie):
    errs.append("co-exist bar self-DEFECT: it PASSED the assertion lie — half tripwire, the TEST lane owns this repair")
for _s in _coexist_claim_violations(f12):
    errs.append(f"a §12 sentence claims the co-existence decision was TAKEN in cf-144 (no exemption word in sight) — it rides the CUTOVER ticket (P11/OQ-B: recorded, not actioned): {_s!r}")

if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PY
  if [ "$rc" -ne 0 ]; then
    fail "T3: the needle set is incomplete or an absence bar fired (C03 Tests T3 — diagnostics above)"
  fi
  ok "T3: needles present (wht6, 12288, 'no RCCL', 120 W, re-enumeration checklist + rocrVisibleDevices, the vfio-pci/1640/8060S interdependency + amd.com/gpu surface, prefix-vs-kv-resident either/or, the shipped pool name + DRA alternative lane; cf-144 C02: the SHIPPED (cf-144 marker + header re-derivation + §4 today-sweep + §6 pool-2 witness + §11 shape-A/HOLD-110 + §12 conditional 118.3 with the co-exist-decision absence bar); absences hold (no stale-flag use outside its stale mention, no guide GB/s figure without direction-only framing, no serve-verb misuse)"
fi

printf 'PASS: radiance TP2 expansion-doc contract checks (%d ok)\n' "$checks"
