#!/usr/bin/env bash
# cf-143 C12 AC2/AC4 — the radiance HOST-TUNING checklist contract.
#
# The doc under contract: .agents/notes/radiance-host-tuning.md (NEW in C12,
# designed-RED here until dev lands it — the accepted red-first shape). It is
# the OWNER-EXECUTED post-boot tuning loop for the 5.1-tok/s decode + 142-t/s
# prefill findings: fifteen stable-token families (AC2's order = owner-impact-
# first), each carrying the startup-report token, the read-only check, the
# healthy target, the fix and the WHY for this engine's hot path. Repo law:
# read-only commands or owner-executed prose ONLY — zero GitOps meaning, zero
# cluster mutation from the repo (the strata scale-down adjudication is the
# precedent for the marker shape).
#
# T1  structure/provenance + the CITATION-RESOLVER arm: every RESEARCH RQ<n>,
#     §D<m>(.k) (EXPLORE) and D-note (DECISIONS) citation must land on a real
#     heading/marker. The resolver ships with a three-state fixture-probe
#     (§12.5 law — re.S/`^## §?` robustness class, §12.7 lesson): a conforming
#     synthetic cite GREENS the machinery, a stale cite reddens it, the real
#     doc is then resolved through the proven-live code path — no latent-dead
#     arm may survive authoring.
# T2  completeness: the FIFTEEN family tokens in SECTION-HEADING or numbered-
#     family-list form (not incidental prose), IN AC2 ORDER, + the boot-param
#     paste strings (AC2.6: `amd_iommu=off …amdgpu.lockup_timeout=30000`) and
#     the printed-112.00-GiB pin-cap-as-authority rule, + §PROTOCOL's budget-
#     line check the suite can pin (report `pinned … GiB` vs limit ≥ pinned+4
#     — AC4's concretization of D28's class law).
# T3  read-only / owner-executed law: kubectl/helm/argocd mutation verbs and
#     host-side WRITES (systemctl mutations, cpupower sets, echo> /sys|/proc|
#     /etc, sysctl -w, swapoff -a, modprobe, grubby…) legal ONLY with the
#     owner-executed marker on the same or the immediately preceding line —
#     the runbook T1 mechanism, case-insensitive token. The marker/hash-bypass
#     mention class must be absent or explicitly human-owned / prohibited.
# T4  TWO-DOC GATE COHERENCE: the note and the acceptance runbook must not
#     contradict on the three shared gates AC2/AC3 fold together — the CORRECTED
#     IOMMU posture (amd_iommu=off is a working supported state; the C06
#     iommu=pt expectation was the wrong gate — the class that bit: runbook
#     expected pt while the live host ran off), the tens-of-minutes hash
#     envelope (§D4: 30–70 @200m / 8–23 @1000m — "minutes-class" is dead), and
#     the 110-era budget arithmetic (the 71.04-GiB
#     printed receipt + the owner-ruling 110 scalar, D29). Arms compare
#     token-for-token across the two docs.
#
# Run from the repo root:
#   bash tests/notes/radiance-host-tuning.sh          # T1..T4
#   bash tests/notes/radiance-host-tuning.sh T2       # subset
# Fixture probing (the suite author's three-state harness):
#   RAD_TUNING=/tmp/conforming.md bash tests/notes/radiance-host-tuning.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

TUNING="${RAD_TUNING:-.agents/notes/radiance-host-tuning.md}"
RUNBOOK="${RAD_RUNBOOK:-.agents/notes/radiance-on-target-acceptance.md}"
PLAN=".agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata"
RESEARCH="${RAD_RESEARCH:-$PLAN/RESEARCH.md}"
EXPLORE="${RAD_EXPLORE:-$PLAN/EXPLORE.md}"
DECISIONS="${RAD_DECISIONS:-$PLAN/DECISIONS.md}"

checks=0

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok()  { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for t in 1 2 3 4; do WANT["t$t"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-4]$ ]] || fail "unknown test id '$a' (expected T1..T4)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# ---------------------------------------------------------------------------
# T1: existence + posture + provenance + citation resolver (fixture-probed)
# ---------------------------------------------------------------------------
if want t1; then
  if [ ! -f "$TUNING" ]; then
    fail "T1: $TUNING missing — C12 AC2 (the host-tuning checklist) is not implemented (designed-RED until dev lands the note)"
  fi
  rc=0
  python3 - "$TUNING" "$RESEARCH" "$EXPLORE" "$DECISIONS" <<'PY' || rc=$?
import re, sys

doc = open(sys.argv[1]).read()
research = open(sys.argv[2]).read()
explore = open(sys.argv[3]).read()
decisions = open(sys.argv[4]).read()


def resolve(doc_text):
    """Return the list of unresolved citations in doc_text. One code path for
    the real doc and the fixture probe alike (a resolver only proven against
    the real doc can be latently dead — §12.5)."""
    rq = {int(m.group(1)) for m in re.finditer(r"(?m)^## RQ([0-9]) —", research)}
    sd = {int(m.group(1)) for m in re.finditer(r"(?m)^## §?D([0-9]+)", explore)}
    dn = set()
    for m in re.finditer(r"(?m)^[ \t]*(?:[-*] )?\d{4}-\d{2}-\d{2}[^\n]*?\bD(\d+)\b", decisions):
        dn.add(int(m.group(1)))
    errs = []
    cites = []
    for m in re.finditer(r"(?<![A-Za-z0-9])RQ\s*([0-9])", doc_text):
        cites.append(("RQ", int(m.group(1))))
    sd_spans = [m.span() for m in re.finditer(r"§\s*D([0-9]+)(?:[.\s]\d+)?", doc_text)]
    for m in re.finditer(r"§\s*D([0-9]+)", doc_text):
        cites.append(("S", int(m.group(1))))
    # Bare D-notes: skip spans already claimed by a §D citation (the §D<m>
    # form resolves through EXPLORE, not the decision ledger).
    for m in re.finditer(r"(?<![0-9A-Za-z.\-§])D(\d+)\b", doc_text):
        if any(a <= m.start() < b for a, b in sd_spans):
            continue
        if re.search(r"§\s*$", doc_text[max(0, m.start() - 2):m.start()]):
            continue
        cites.append(("D", int(m.group(1))))
    for kind, n in sorted(set(cites)):
        if kind == "RQ" and n not in rq:
            errs.append(f"RQ{n}: no '## RQ{n} —' heading in RESEARCH.md (stale pointer)")
        if kind == "S" and n not in sd:
            errs.append(f"§D{n}: no '## §D{n}' heading in EXPLORE.md (stale pointer)")
        if kind == "D" and n not in dn:
            errs.append(f"D{n}: no D{n} entry in DECISIONS.md (stale pointer)")
    return cites, errs


# --- fixture-probe (three states): conforming cite GREENS, stale cite REDS ---
good_cites, good_errs = resolve("Grounded per RESEARCH RQ1 and §D4 (scout round 6), decisions D17, D27 and D28; §D4.4 details.")
if good_errs:
    sys.exit(f"resolver machinery broken: the CONFORMING fixture cite failed to resolve: {good_errs}")
if {("RQ", 1), ("S", 4), ("D", 17), ("D", 27), ("D", 28)} - set(good_cites):
    sys.exit(f"resolver machinery broken: the conforming fixture cites were not even harvested: {sorted(set(good_cites))}")
_stale_cites, stale_errs = resolve("Per RESEARCH RQ9 and §D42 and D222, the envelope holds.")
if not stale_errs:
    sys.exit("resolver machinery broken: the STALE fixture cite resolved (teeth dead — a vacuous resolver would green any doc)")

# --- posture + provenance on the real doc (first ~40 lines) ---
head = "\n".join(doc.splitlines()[:40])
perrs = []
for pat, what in (
    (r"(?i)owner[- ]executed|no agent runs", "the owner-executed posture line"),
    (r"(?i)read[- ]only", "the read-only law"),
    (r"(?i)cf-143", "the cf-143 provenance"),
    (r"(?i)C12", "the C12 chunk provenance"),
    (r"(?i)(report 1|report 2|startup.report)", "the live startup-report receipt basis"),
    (r"(?i)(checklist|tuning loop|one variable at a time)", "the checklist/PROTOCOL posture"),
):
    if not re.search(pat, head):
        perrs.append(what)
if perrs:
    sys.exit("posture/provenance missing up top: " + "; ".join(perrs))

cites, errs = resolve(doc)
if not cites:
    errs.append("the note cites NO research/explore/decision heading — C12 AC2 grounds every family in the live receipts (RQ/§D/D-note forms are mandatory)")
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PY
  if [ "$rc" -ne 0 ]; then
    fail "T1: structure/provenance or the citation resolver rejected the note (C12 AC4/T1 — diagnostics above)"
  fi
  ok "T1: the tuning note exists with the owner-executed/read-only posture + cf-143 C12 provenance up top, every RQ/§D/D-note citation resolves (resolver proven live by the conforming-green + stale-red fixture probe), and the doc cites its receipts"
fi

# ---------------------------------------------------------------------------
# T2: the fifteen AC2 family tokens, heading form, in order + receipt strings
# ---------------------------------------------------------------------------
if want t2; then
  [ -f "$TUNING" ] || fail "T2: $TUNING missing (C12 AC2 — designed-RED until dev lands the note)"
  if ! python3 - "$TUNING" <<'PY'
import re, sys

doc = open(sys.argv[1]).read()
lines = doc.splitlines()

# AC4's token list is authority; AC2's order = owner-impact-first.
FAMILIES = ("LINK", "MEMLOCK", "DIO-NGRAM", "GOVERNOR", "SWAP-ZRAM", "HUGEPAGES-TTM",
            "RUNTIME-PM", "IOMMU", "PROVEN-DONE", "POWER-CLOCKS", "NUMA", "APU-VISIBLE",
            "KV-STREAM-MISS", "HEAT-ENGINE", "PROTOCOL")

def family_line(pat):
    """Section-HEADLINE form only (C12 AC4/T2: 'not incidental prose'): a
    markdown heading or a numbered family-list item line carrying the token
    at a word boundary (LimitMEMLOCK-style prose tokens can't match — the
    lookbehind rejects the leading alnum)."""
    for i, ln in enumerate(lines):
        if not re.match(r"^(?:#{1,6}\s|\d+\.\s+\*\*|\d+\.\s+)", ln):
            continue
        if re.search(rf"(?<![A-Za-z0-9]){pat}(?![A-Za-z0-9])", ln):
            return i
    return None

pos = {}
errs = []
for tok in FAMILIES:
    i = family_line(re.escape(tok))
    if i is None:
        errs.append(f"family token {tok} has no section-heading/numbered-item line (AC2 family missing in heading form)")
    else:
        pos[tok] = i
seq = [pos[t] for t in FAMILIES if t in pos]
if len(seq) == len(FAMILIES) and seq != sorted(seq):
    errs.append(f"the fifteen families are OUT of AC2 order (owner-impact-first): {[ (t, pos[t]) for t in FAMILIES ]}")

# AC2.6 mandated verbatim strings: the boot-param paste + the printed-cap rule.
if "amd_iommu=off" not in doc:
    errs.append("the boot-param paste string is missing the amd_iommu=off token (AC2 item 6: 'the note must restate the exact paste string')")
if not re.search(r"amdgpu\.lockup_timeout=30000", doc):
    errs.append("the boot-param paste is missing amdgpu.lockup_timeout=30000 (verbatim receipt strings are AC2's Tasks deliverable)")
if not re.search(r"ttm\.(page_pool_size|pages_limit)", doc):
    errs.append("the boot-param paste is missing the ttm.page*_limit/pool_size trio (assume-nothing-custom adjudication rides it)")
if not re.search(r"112\.00", doc):
    errs.append("the engine-printed 112.00 GiB pin cap is absent — the authority number AC2.6 rules over the stock 120.6 formula")
if not re.search(r"(?i)(authorit|stock|assume nothing|not stock)", doc):
    errs.append("the pin-cap AUTHORITY / assume-nothing-custom adjudication is not stated (112.00 printed > formula advisory)")

# (amendment 2026-11-13) §D6 TRUTH CORRECTIONS folded into the family arms —
# a suite that blesses a falsified remedy is §12.10's class seen from the
# other side (vocabulary pinned to a claim the live probes disproved). Each
# arm demands the CORRECTED truth at its family and bars the dead claim
# unless correction-framed.
def section(tok):
    i = family_line(tok)
    if i is None:
        return ""
    j = i + 1
    while j < len(lines) and not re.match(r"^(?:#{1,6}\s|\d+\.\s+\*\*)", lines[j]):
        j += 1
    return "\n".join(lines[i:j])

link = section("LINK")
if not re.search(r"TargetSpeed", link):
    errs.append("LINK lacks the §D6 discriminator (LnkCtl2 TargetSpeed: =8.0 ⇒ BIOS pin, =16-while-8 ⇒ electrical/cable — the ONLY read that closes retrain-vs-luck)")
if not re.search(r"(?i)reprinted|proven downgraded|downgrade[^.\n]{0,40}proven", link):
    errs.append("LINK still reads as open ('did not repeat' alone): §D6 PROVED the downgrade — the WARN REPRINTED at 49% busy on the 15:01Z fresh boot; report-2's silence was luck/state")
for m in re.finditer(r"(?i)indistinguishable|retrain[^.\n]{0,30}luck", link):
    w = link[max(0, m.start() - 160): m.end() + 160]
    if not re.search(r"(?i)closed|resolved|no longer|was luck|state —", w):
        errs.append(f"LINK re-states retrain-vs-luck as OPEN (§D6 closed it): {m.group(0)[:60]!r}")
gov = section("GOVERNOR")
if not re.search(r"(?i)cpupower\.service|systemctl enable|tmpfiles|udev|tuned|tlp|kernel param", gov):
    errs.append("GOVERNOR lacks a PERSISTENCE route — §D6 proved the runtime writes DID NOT PERSIST (fresh 15:01Z boot re-printed powersave); a bare runtime set is not the fix")
if not re.search(r"(?i)did not persist|doesn.?t persist|non-?persist|reverts? (on|at|across)|not mere snapshot", gov):
    errs.append("GOVERNOR does not carry the non-persistence truth (host reads performance NOW yet the fresh-boot report printed powersave — §D6)")
for m in re.finditer(r"frequency-set", gov):
    w = gov[max(0, m.start() - 200): m.end() + 200]
    if not re.search(r"(?i)revert|not the fix|alone|does not persist|never", w):
        errs.append("a runtime `cpupower frequency-set` appears as THE fix without the reverts-on-reboot disavowal (AC2-ii: persistence routes only)")
mem = section("MEMLOCK")
if not re.search(r"crictl", mem) or "/proc/" not in mem:
    errs.append("MEMLOCK lacks the CORRECTED read (crictl ps → inspect .info.pid → /proc/<pid>/limits — §D6.3: the earlier 16787369984 was the PAUSE SANDBOX, the engine's 8.00 MiB is the container truth)")
if not re.search(r"(?i)pause|sandbox", mem):
    errs.append("MEMLOCK does not record the sandbox-vs-container probe correction (the ×8 figure belongs to the pause sandbox)")
if not re.search(r"(?i)8\.00 MiB", mem):
    errs.append("MEMLOCK does not carry the container truth (the engine's reprinted 'RLIMIT_MEMLOCK is 8.00 MiB')")
if not re.search(r"(?i)no per-?pod|node lane|only route|k3s\.service|strata-host-prep", mem):
    errs.append("MEMLOCK does not state the NODE-LANE-only adjudication (no PodSpec rlimit, no containerd default_ulimits — repo precedent strata-host-prep-gpu-ai.md:115-118)")
for m in re.finditer(r"16787369984", mem):
    w = mem[max(0, m.start() - 160): m.end() + 160]
    if not re.search(r"(?i)pause|sandbox", w):
        errs.append("the 16787369984 figure attributed without the pause-sandbox correction context")
dio = section("DIO-NGRAM")
if not re.search(r"118\.72", dio):
    errs.append("DIO-NGRAM lacks the kill-sum (71.04 + 47.68 = 118.72 > 110 — the RAM tier is ARITHMETICALLY DEAD at BOTH candidate limits)")
if not re.search(r"(?i)dead|does not buy|not viable|unlocks nothing|moot", dio):
    errs.append("DIO-NGRAM does not state the verdict: unlocking MEMLOCK DOES NOT BUY the RAM tier (§D6, AC2-iv)")
if not re.search(r"(?i)xfs|ext4", dio):
    errs.append("DIO-NGRAM lacks the real option set (stay-on-disk 4 KiB spans vs move /models to XFS/ext4 — the storage-lane decision)")
if not re.search(r"3\.42", dio):
    errs.append("DIO-NGRAM does not record the measured direct read (3.42 GB/s — under the runbook's own ≥5 GB/s gate bar)")
for m in re.finditer(r"(?i)ngram-placement ram|ram=DIR", dio):
    w = dio[max(0, m.start() - 160): m.end() + 160]
    if not re.search(r"(?i)dead|118\.72|>|cannot|forfeit|moot", w):
        errs.append(f"the RAM-tier option is presented without its DEAD arithmetic context: {m.group(0)[:60]!r}")
iom = section("IOMMU")
if not re.search(r"(?i)wrong", iom):
    errs.append("IOMMU does not name the gate WRONG (AC2-v: the C06 iommu=pt expectation was the defect, not the host — §D6 confirmed)")
if not re.search(r"(?i)amdxdna|NPU", iom):
    errs.append("IOMMU omits the §D6 side effect (amdxdna 'Running without IOMMU not supported' — off kills the NPU: the owner's fact, their call, no radiance action)")

# AC4's budget-line concretization lives in the §PROTOCOL family: report
# `pinned … GiB` vs limit >= pinned+4 — the D28 class law made checkable.
proto = family_line("PROTOCOL")
if proto is not None:
    tail = "\n".join(lines[proto:])
    if not re.search(r"(?i)pinned[^.\n]{0,160}(≥|>=|\+ ?4|budget)|budget[^.\n]{0,80}(check|line|sum)|limit[^.\n]{0,80}pinned", tail):
        errs.append("§PROTOCOL lacks the budget-line check pin (compare the printed 'pinned … GiB' sum to the limit; limit ≥ pinned+4 — D28's class law, AC4 requires the suite-pinnable form)")
    # (amendment) the budget line NOW walks concrete shipped-value terms:
    # limit ≥ 110, pinned 71.04, slack 38.96 (AC2-PROTOCOL amended).
    if not (re.search(r"71\.04", tail) and re.search(r"110", tail) and re.search(r"38\.96", tail)):
        errs.append("§PROTOCOL's budget line does not carry the 110-era terms (pinned 71.04 / limit 110 / slack 38.96 — AC2 amendment)")

if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PY
  then
    fail "T2: the fifteen-family completeness / receipt-string / budget-line contract is violated (C12 AC4/T2 — diagnostics above)"
  fi
  ok "T2: all fifteen AC2 family tokens present in heading form and in owner-impact order, the boot-param paste + printed-112.00 authority rule are restated verbatim, and §PROTOCOL carries the pinnable budget-line check"
fi

# ---------------------------------------------------------------------------
# T3: read-only / owner-executed law (marker mechanism as the runbook's T1)
# ---------------------------------------------------------------------------
if want t3; then
  [ -f "$TUNING" ] || fail "T3: $TUNING missing (C12 AC2 — designed-RED until dev lands the note)"
  if ! python3 - "$TUNING" <<'PY'
import re, sys

lines = open(sys.argv[1]).read().splitlines()
OWNER = re.compile(r"(?i)owner[- ]executed|owner lane|human[- ]owned")
CLUSTER_MUT = re.compile(r"kubectl[ \t]+(apply|create|delete|scale|edit|patch|label|annotate|cordon|drain|taint|run|rollout)|helm[ \t]+(install|upgrade|uninstall|rollback)|argocd[ \t]+(app[ \t]+)?(sync|delete)")
EXEC = re.compile(r"kubectl[ \t]+exec")
HOST_WRITE = re.compile(r"systemctl[ \t]+(edit|restart|start|stop|enable|disable|daemon-reload|set-property)|cpupower[ \t]+(set|frequency-set)|echo[^\n>] *> *>? */(sys|proc|etc)/|tee[^\n]*/(sys|proc)/|sysctl[ \t]+-w|swapoff[ \t]+-a|modprobe[ \t]|grubby|(?:reboot|shutdown)(?: now|[ \t]+-|[ \t]*$)|setpci|pp_dpm_sclk[^\n]*echo")
errs = []
for i, ln in enumerate(lines):
    prev = lines[i - 1] if i else ""
    if re.match(r"^\s*#", ln):  # a comment naming the law it states is exempt (runbook idiom)
        continue
    marked = any(OWNER.search(x) for x in (ln, prev))
    if EXEC.search(ln):
        errs.append(f"{i+1}: kubectl EXEC is barred outright (no pod-exec tier — AGENTS MCP law; this is a host-commands note, not a cluster one): {ln.strip()[:90]}")
    if CLUSTER_MUT.search(ln) and not marked:
        errs.append(f"{i+1}: unmarked cluster-mutating command — the note is ZERO-GitOps; a mutation line is legal only owner-executed-marked (same or previous line): {ln.strip()[:90]}")
    if HOST_WRITE.search(ln) and not marked:
        errs.append(f"{i+1}: unmarked host WRITE — cpufreq/systemctl/echo-to-/sys fixes are OWNER-EXECUTED prose steps, never repo-runnable lines (AC2 repo law): {ln.strip()[:90]}")

# The marker/hash-bypass class (D27/§D4): touching the staging marker or
# skipping the hash is a HUMAN decision — if the note mentions it at all, the
# mention must be owner/human-framed or prohibitive.
doc = "\n".join(lines)
for m in re.finditer(r"(?i)(touch[^.\n]{0,30}MARKER|bypass[^.\n]{0,60}(hash|sha|checksum)|skip[^.\n]{0,40}(the )?(first )?(hash|sha256|checksum))", doc):
    window = doc[max(0, m.start() - 200): m.end() + 200]
    if not re.search(r"(?i)owner|human|never|do not|don.t|forbidden|only if", window):
        errs.append(f"marker/hash-bypass mention without an owner/human/prohibition frame: {m.group(0)[:80]!r}")

if errs:
    print("\n".join(errs[:8]), file=sys.stderr)
    sys.exit(1)
PY
  then
    fail "T3: the read-only/owner-executed law is violated (C12 AC4/T3 — unmarked mutation or an unframed bypass mention, diagnostics above)"
  fi
  ok "T3: zero unmarked cluster mutations and zero unmarked host writes (owner-executed marker law holds); every marker/hash-bypass mention is owner/human-framed or prohibitive (AC2 repo law)"
fi

# ---------------------------------------------------------------------------
# T4: two-doc gate coherence (tuning note × acceptance runbook)
# ---------------------------------------------------------------------------
if want t4; then
  [ -f "$TUNING" ] || fail "T4: $TUNING missing (C12 AC2 — designed-RED until dev lands the note)"
  [ -f "$RUNBOOK" ] || fail "T4: $RUNBOOK missing — the coherence arm reads BOTH docs of the gate pair"
  if ! python3 - "$TUNING" "$RUNBOOK" <<'PY'
import re, sys

note = open(sys.argv[1]).read()
rb = open(sys.argv[2]).read()
docs = {"tuning note": note, "runbook": rb}
errs = []

POSTURE = re.compile(r"(?i)amd_iommu=off|(off[^.\n]{0,140}(acceptable|supported|working|correct|proven))")
# AC2.7/AC3 corrected posture: "off" is a working supported state for THIS
# workload; the C06 iommu=pt expectation was the wrong gate. Both docs must
# carry the corrected posture; neither may RESTATE pt as the live requirement
# (a stale gate line = the contradiction class this arm exists to catch).
STALE_GATE = re.compile(r"(?i)(expect[a-z]*|required|require[sd]?|must (be|have|set)|gate wants)[^.\n]{0,60}iommu=pt|iommu=pt[^.\n]{0,40}(is required|expected)")
CORRECTION = re.compile(r"(?i)wrong|superseded|no longer|was the|old gate|instead|not the (host|gate)|re-verify|before any|correction|vs\b")
ENVELOPE = re.compile(r"(?i)tens[- ]of[- ]minutes|30\s*[–—-]\s*70 ?(min|minutes)|8\s*[–—-]\s*23 ?(min|minutes)")
RECEIPT = re.compile(r"71\.04")
# (amendment) the 110 era — SCOPE-AWARE like the runbook T2 needle: strata's
# OWN limit line ("its limits are 110Gi") may not satisfy it; require the
# guaranteedMemoryGi context or an unambiguous 110-era arithmetic figure.
SHIPPED_110 = re.compile(r"(?i)guaranteedMemoryGi[^\n]{0,20}\b110\b|115\.28|9\.80 ?GiB|118\.72[^.\n]{0,30}> ?110|110 ?\(?GiB\)? ?\(your figure\)|110[^\n]{0,40}(pair|ruling|slack)")

for name, text in docs.items():
    if not POSTURE.search(text):
        errs.append(f"{name}: no amd_iommu=off / off-is-a-working-posture token — both docs must carry the AC2.8 corrected IOMMU gate (the pt-vs-off contradiction is the class C12 closes)")
    for ln in text.splitlines():
        if "iommu=pt" in ln and STALE_GATE.search(ln) and not CORRECTION.search(ln):
            errs.append(f"{name}: a line RE-STATES iommu=pt as the live requirement without a correction word — two docs, two answers: {ln.strip()[:90]!r}")
    if not ENVELOPE.search(text):
        errs.append(f"{name}: no tens-of-minutes hash envelope (§D4: 30–70 min @200m / 8–23 min @1000m — the 'minutes-class' fold must reach BOTH docs)")
    if not RECEIPT.search(text):
        errs.append(f"{name}: the 71.04-GiB printed-budget receipt is absent — the budget-line class law (D28) anchors the 110 in BOTH docs")
    if not SHIPPED_110.search(text):
        errs.append(f"{name}: never states the 110-era guaranteedMemoryGi arithmetic (owner ruling, D29 — a two-doc law: runbook :189-class scalar + the note's 118.72-dead-tier math)")

if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PY
  then
    fail "T4: the two docs CONTRADICT (or fail to carry) the shared gates — iommu posture / hash envelope / 110 arithmetic (C12 AC4/T4 — diagnostics above)"
  fi
  ok "T4: note and runbook carry the SAME corrected gates token-for-token — amd_iommu=off posture with no uncorrected iommu=pt re-statement, the tens-of-minutes §D4 envelope, and the 71.04-receipt-anchored 110 arithmetic (owner ruling)"
fi

printf 'PASS: radiance host-tuning contract checks (%d ok)\n' "$checks"
