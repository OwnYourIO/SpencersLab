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
for m in re.finditer(r"(?<![A-Za-z0-9])R6\s+OQ\s*(\d+)", doc, re.I):
    cites.append(("R6OQ", None, int(m.group(1))))
for m in re.finditer(r"(?<![A-Za-z0-9-])OQ\s*(\d+)", doc, re.I):
    if not re.search(r"R6\s*[-–]?\s*$", doc[max(0, m.start() - 6):m.start()], re.I):
        cites.append(("OQ", None, int(m.group(1))))

if not cites:
    sys.exit("the doc cites NO research heading — C03 AC1: every numeric claim resolves to a "
             "RESEARCH.md heading (RQ<n> / R6-Q<n>(-<row>) / §R6 / OQ<m> forms, T4-style)")

errs = []
for kind, n, extra in sorted(set(cites), key=lambda c: (c[0], c[1] or 0, c[2] or 0)):
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
  ok "T2: citation resolver — every RQ<n>/R6-Q<n>(-row)/§R6/OQ<m> reference in the doc lands on a real heading of this folder's RESEARCH.md (incl. the §R6 block)"
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

if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PY
  if [ "$rc" -ne 0 ]; then
    fail "T3: the needle set is incomplete or an absence bar fired (C03 Tests T3 — diagnostics above)"
  fi
  ok "T3: needles present (wht6, 12288, 'no RCCL', 120 W, re-enumeration checklist + rocrVisibleDevices, the vfio-pci/1640/8060S interdependency + amd.com/gpu surface, prefix-vs-kv-resident either/or, the shipped pool name + DRA alternative lane); absences hold (no stale-flag use outside its stale mention, no guide GB/s figure without direction-only framing, no serve-verb misuse)"
fi

printf 'PASS: radiance TP2 expansion-doc contract checks (%d ok)\n' "$checks"
