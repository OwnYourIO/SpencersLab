#!/usr/bin/env bash
# cf-143 C06 — the radiance on-target acceptance runbook contract
# (chunks/C06.md Tests: "The T1–T5 contract above is the test list; the test
# session authors it against the step names before dev writes the doc
# (designed-red until C06 dev lands — the accepted shape)").
#
# The doc under contract: .agents/notes/radiance-on-target-acceptance.md —
# operator-run, MANDATORY pre-deploy gates (step 0 a–e incl. the naming
# receipts), the owner-executed strata scale-down/restore protocol (Q10 —
# never a GitOps change), the FULL-profile 8-session gate + refusal ladder,
# the higher-wins polarity live-check (Q2 — fails loudly if the retired vLLM
# 1/5/9 was ever ported unflipped), the image smoke leg (Q8 retire-on-failure),
# the lockstep-revert rollback law (R6-Q4-4). Step groups 0–11 (twelve —
# two more than the vllm idiom's eleven).
#
# COMMAND LAW (T1/T2), the vllm shape + the owner-execution carve the chunk
# names: repo steps are read+curl+git ONLY — no kubectl apply/create/delete/
# scale/patch/exec/rollout/argocd-sync instruction lines. The strata scale-
# down IS documented as an OWNER-EXECUTED command (the exact kubectl scale
# recorded for convenience): a mutation line is legal ONLY where marked with
# the token `OWNER-EXECUTED` on the same line or the immediately preceding
# line. That marker is the contract — the checker distinguishes the two by
# nothing else.
#
# T2 shipped-flag equality: the runbook carries its DRY_RUN expectation as a
# fenced args block containing `--served-model-name qwen3.8-flash-next-
# radiance` — EXACTLY ONE such block; its flag/value multiset must equal the
# chart's serveArgs (read live from charts/radiance/values.yaml, C02), the
# four scalars needle-pinned on BOTH sides (43000 / 200000 / 8 / 64).
#
# T4 citation resolver: the vllm T4 regex shape extended to THIS folder's
# RESEARCH.md incl. the §R6 block (forms: RQ<n>, R6-Q<n>, R6-Q4-<row>,
# §R6, OQ<m>, R6 OQ<m>), and the runbook must cite research at least once
# (numbers trace to RESEARCH or the shipped values — none to the card guide).
#
# Run from the repo root:
#   bash tests/notes/radiance-runbook.sh            # T1..T5
#   bash tests/notes/radiance-runbook.sh T1 T2      # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

RUNBOOK="${RAD_RUNBOOK:-.agents/notes/radiance-on-target-acceptance.md}"
RESEARCH="${RAD_RESEARCH:-.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/RESEARCH.md}"
VALS="${RAD_VALS:-services/gpu-ai/prod/values.yaml}"
RAD_CHART="${RAD_CHART_VALUES:-charts/radiance/values.yaml}"
AMD_CHART="${RAD_AMD_CHART_VALUES:-charts/amd-gpu/values.yaml}"
CATALOG=".opencode/opencode.jsonc"

# ---------------------------------------------------------------------------
# GPU RESOURCE-NAME CONSTANTS — C08 D24 lane ruling landed (marked single edit
# site, bash twin of charts/amd-gpu/tests/amd_gpu_testlib.py's block; any
# future lane move edits here + that block, never needle archaeology). T3's
# name needles read these; the patched-table/watch sentences are pinned there
# too (T-E docs sweep).
R9700_CLAIM="amd.com/gpu-r9700-1"
APU_CLAIM="amd.com/gpu-8060s"

checks=0

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ok()  { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for t in 1 2 3 4 5; do WANT["t$t"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-5]$ ]] || fail "unknown test id '$a' (expected T1..T5)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- T1: existence, twelve step groups (0-11) in order, posture line, command law
if want t1; then
  if [ ! -f "$RUNBOOK" ]; then
    fail "T1: $RUNBOOK missing — C06 (the on-target acceptance runbook) is not implemented"
  fi
  lines=$(wc -l < "$RUNBOOK")
  if [ "$lines" -lt 250 ]; then
    fail "T1: the runbook is only $lines lines — twelve step groups with the five (a)-(e) gates, the receipts and the ladder cannot fit (want >= 250)"
  fi
  if ! python3 - "$RUNBOOK" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
first = {}
for i, ln in enumerate(text.splitlines()):
    if not ln.startswith("#"):
        continue
    for n in range(12):
        if n in first:
            continue
        if re.match(rf"^#{{1,6}}\s*(Step\s+)?{n}(?=[.: \t—–-]|$)", ln):
            first[n] = i
missing = [n for n in range(12) if n not in first]
if missing:
    sys.exit(f"missing step-group headers for steps: {missing}")
seq = [first[n] for n in sorted(first)]
if seq != sorted(seq):
    sys.exit(f"step-group headers out of order: {first}")
PY
  then
    fail "T1: the runbook does not carry all twelve step-group headers (0-11) in order (C06 Tasks step list)"
  fi
  # AC3 posture: the opening states operator-run, mandatory pre-deploy gates,
  # the owner-executed scale-down protocol, and no repo-side cluster mutation.
  if ! python3 - "$RUNBOOK" <<'PY'
import re, sys
head = "\n".join(open(sys.argv[1]).read().splitlines()[:40]).lower()
errs = []
for pat, what in (
    (r"operator", "operator-run posture"),
    (r"mandatory", "MANDATORY pre-deploy gates"),
    (r"(owner[- ]executed|owner runs|scale.?down protocol)", "the owner-executed scale-down protocol"),
    (r"(no|never|not)[^.\n]{0,60}(gitops|repo[- ]side|cluster mutation)", "the no-repo-side-mutation statement"),
):
    if not re.search(pat, head):
        errs.append(what)
if errs:
    sys.exit("posture line(s) missing from the first 40 lines: " + "; ".join(errs))
PY
  then
    fail "T1: AC3's first-line posture (operator-run, mandatory gates, owner scale-down, no repo mutation) is not stated up top"
  fi
  # Command law, vllm shape + the OWNER-EXECUTED carve (header contract):
  # repo lines may not instruct kubectl mutations or argocd syncs; kubectl
  # exec is barred outright (no pod-exec tier, AGENTS MCP law); mutation
  # verbs are tolerated ONLY owner-marked (same or previous line).
  if ! python3 - "$RUNBOOK" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()
MUT = re.compile(r"kubectl[ \t]+(apply|create|delete|scale|edit|patch|label|annotate|cordon|drain|taint|run|rollout)")
EX = re.compile(r"kubectl[ \t]+exec")
SYNC = re.compile(r"argocd[ \t]+app[ \t]+sync")
OWNER = re.compile(r"OWNER-EXECUTED")
errs = []
for i, ln in enumerate(lines):
    if re.match(r"^\s*#", ln):          # comment lines may NAME the law they state (vllm exemption)
        continue
    if EX.search(ln) and not any(OWNER.search(x) for x in (ln, lines[i - 1] if i else "")):
        errs.append(f"{i+1}: a kubectl EXEC instruction — pod-exec is not a sanctioned runbook shape even owner-side: {ln.strip()[:90]}")
    if SYNC.search(ln) and not any(OWNER.search(x) for x in (ln, lines[i - 1] if i else "")):
        errs.append(f"{i+1}: an argocd app sync instruction — sync is ArgoCD's own reconciliation: {ln.strip()[:90]}")
    if MUT.search(ln) and not any(OWNER.search(x) for x in (ln, lines[i - 1] if i else "")):
        errs.append(f"{i+1}: unmarked cluster-mutating command (needs the OWNER-EXECUTED marker on this or the previous line): {ln.strip()[:90]}")
if errs:
    print("\n".join(errs[:8]), file=sys.stderr); sys.exit(1)
PY
  then
    fail "T1: the read+curl+git command law is violated (unmarked mutation / argocd sync / kubectl exec) — the strata scale-down must appear as OWNER-EXECUTED-marked prose with the exact kubectl scale recorded for convenience (Q10: never GitOps-ized)"
  fi
  ok "T1: the runbook exists ($lines lines), carries the twelve step-group headers (0-11) in order, states the AC3 posture up top, and obeys the read+curl+git command law with the OWNER-EXECUTED carve for the documented scale-down"
fi

# --- T2: shipped-flag equality + both-side scalars + gate order ------------------
if want t2; then
  for f in "$RUNBOOK" "$RAD_CHART"; do
    [ -f "$f" ] || fail "T2: $f missing — flag equality needs the C02 chart (and C06's runbook) on this commit"
  done
  rc=0
  python3 - "$RUNBOOK" "$RAD_CHART" "$VALS" <<'PY' || rc=$?
import re, sys, yaml
runbook, chart, vals_path = sys.argv[1:4]
rb = open(runbook).read()
cv = yaml.safe_load(open(chart))

app = cv.get("app-template") or {}
serve = [str(a) for a in (app.get("serveArgs") or [])]
assert serve, "charts/radiance serveArgs missing in values (C02 not landed?)"

def flag_pairs(args):
    out, i = {}, 0
    seen = []
    while i < len(args):
        tok = args[i]
        if not tok.startswith("--"):
            i += 1; continue
        if "=" in tok:
            f, v = tok.split("=", 1); out[f] = v; seen.append(f); i += 1
        elif i + 1 < len(args) and not args[i + 1].startswith("--"):
            out[tok] = args[i + 1]; seen.append(tok); i += 2
        else:
            out[tok] = None; seen.append(tok); i += 1
    return out, seen

chart_flags, chart_seen = flag_pairs(serve)

# The runbook's shipped-args block: fenced blocks containing the served name.
blocks = re.findall(r"```[^\n]*\n(.*?)```", rb, re.S)
shipped = [b for b in blocks if "--served-model-name qwen3.8-flash-next-radiance" in b]
errs = []
if len(shipped) != 1:
    errs.append(f"expected EXACTLY ONE shipped-args fenced block (the step-5 DRY_RUN expectation), found {len(shipped)}")
else:
    toks = shipped[0].replace("\\\n", " ").split()
    rb_flags, rb_seen = flag_pairs(toks)
    if rb_flags != chart_flags:
        only_rb = {k: rb_flags[k] for k in rb_flags if k not in chart_flags or rb_flags[k] != chart_flags[k]}
        only_chart = {k: chart_flags[k] for k in chart_flags if k not in rb_flags}
        errs.append(f"runbook args block != chart serveArgs: runbook-side diff {only_rb}, chart-only {only_chart}")

# Scalars BOTH sides (chunk T2: 43000 / 200000 / 8 / 64).
for num in ("43000", "200000"):
    if num not in rb:
        errs.append(f"the runbook never names {num} (shipped scalar)")
    if num not in open(chart).read():
        errs.append(f"the chart values never name {num} (single-source scalar)")
if not re.search(r"max-num-seqs[ \t\"':=-]*8\b|8[ \t-]*sessions|8 concurrent", rb):
    errs.append("the runbook never states the 8-session scalar")
if not re.search(r"64 ?Gi|guaranteedMemoryGi[^\n]{0,20}\b64\b", rb):
    errs.append("the runbook never states the 64 (Gi-class guaranteedMemoryGi) scalar")

# Gate order: step-0 gates precede any boot text; scale-down precedes start.
m0 = re.search(r"(?m)^#{1,6}\s*(Step\s+)?0(?=[.: \t—–-]|$)", rb)
first_boot = re.search(r"(?i)\b(port-forward|application startup|first boot|engine boots)\b", rb)
if m0 and first_boot and first_boot.start() < m0.end():
    errs.append("boot text appears BEFORE the step-0 gates header (gate-order law)")
m3 = re.search(r"(?m)^#{1,6}\s*(Step\s+)?3(?=[.: \t—–-]|$).*?(?=^#{1,6}\s*(Step\s+)?4(?=[.: \t—–-]|$))", rb, re.S | re.M)
if not m3:
    errs.append("no step-3 section found for the scale-down-before-start ordering")
else:
    sec = m3.group(0)
    scale = re.search(r"kubectl[^\n]*scale[^\n]*", sec)
    start = re.search(r"(?i)(deploy|start|bring up|boot|schedul)[^\n]{0,60}radiance|radiance[^\n]{0,60}(deploy|start|bring up|boot|schedul)", sec)
    if not scale:
        errs.append("step 3 does not record the owner's kubectl scale-down command (Q10 protocol)")
    if scale and start and start.start() < scale.start():
        errs.append("step 3 mentions starting radiance BEFORE the strata scale-down — the order is the designed handshake")

if errs:
    print("; ".join(errs), file=sys.stderr); sys.exit(1)
PY
  if [ "$rc" -ne 0 ]; then
    fail "T2: shipped-flag equality / scalar pins / gate order violated (C06 T2 — diagnostics above)"
  fi
  ok "T2: the runbook's shipped-args block equals the chart serveArgs flag set (single DRY_RUN block), the 43000/200000/8/64 scalars are pinned BOTH sides, and the gate order holds (step-0 before boot text; scale-down before radiance start)"
fi

# --- T3: names block + triple-digest ledger + polarity + gates a-e ---------------
if want t3; then
  for f in "$RUNBOOK" "$VALS" "$RAD_CHART" "$AMD_CHART" "$CATALOG"; do
    [ -f "$f" ] || fail "T3: $f missing — the cross-reference needs the C02/C05/C07 artifacts (this suite's bar is the final chunk)"
  done
  rc=0
  RAD_R9700="$R9700_CLAIM" RAD_APU="$APU_CLAIM" \
  python3 - "$RUNBOOK" "$RAD_CHART" "$AMD_CHART" "$CATALOG" <<'PY' || rc=$?
import os, re, sys
runbook, rad_chart, amd_chart, catalog = sys.argv[1:5]
r9700_claim = os.environ["RAD_R9700"]   # constants-injected (C08 D24): no forked literals
apu_claim = os.environ["RAD_APU"]
rb = open(runbook).read()
rc_text = open(rad_chart).read()
ac_text = open(amd_chart).read()
cat_text = open(catalog).read()
errs = []

# Names block (step 1): served id, peer URL, both resource names, the scalars.
for needle, what in (
    ("qwen3.8-flash-next-radiance", "the served id"),
    ("gpu-ai-radiance.default.svc.cluster.local:8000", "the peer URL (no /v1)"),
    (r9700_claim, "the R9700 pool name (D24 renamed)"),
    (apu_claim, "the APU pool name"),
):
    if needle not in rb:
        errs.append(f"the names block never names {what}: {needle!r}")

# Triple digest ledger, PAIRED across surfaces (chunk T3):
MANIFEST = "sha256:6fb0e99bfb862e17cc15cb7b2f116c7dbdc831df59f82456a0691122e6cf5330"
INDEX = "sha256:c2acbaa373c89272ec47a22befa1cf04d2ddf1de51c2baf534f5273e517f7100"
for where, hay in (("the runbook", rb), ("the radiance chart", rc_text)):
    if MANIFEST not in hay:
        errs.append(f"{where} lacks the full amd64 image-manifest digest sha256:6fb0e99b…")
    if INDEX not in hay:
        errs.append(f"{where} lacks the full index digest sha256:c2acbaa3…")
if "sha256:6437c74f" not in rb:
    errs.append("the runbook lacks the plugin image digest 6437c74f… (the flip-wave pin ledger)")
if "sha256:6437c74f" not in ac_text:
    errs.append("the amd-gpu chart values lack the plugin digest ledger (the pairing authority)")
elif not re.search(r"sha256:6437c74f[0-9a-f]{56}", ac_text):
    errs.append("the amd-gpu chart digest is truncated (64-hex ledger form required, not the research prefix)")
for where, hay in (("radiance chart", rc_text), ("amd-gpu chart", ac_text)):
    if "renovate: datasource=docker" not in hay:
        errs.append(f"the {where} pin has no renovate docker comment (the pairing the runbook's ledger must mirror)")

# Polarity needles (Q2 higher-wins) in BOTH runbook and catalog:
if not re.search(r"(?i)(higher[^\n]{0,40}(wins|priority)|9/5/1)", rb):
    errs.append("the runbook never states radiance's higher-wins polarity (the flip of the retired vLLM 1/5/9 — Q2)")
for v in ("9", "5", "1"):
    if not re.search(rf"(?i)priority[^\n]{{0,40}}\b{v}\b", rb):
        errs.append(f"the runbook never names the radiance priority value {v} (urgent/default/low under higher-wins)")
cat_flat = re.sub(r"\s+", " ", cat_text)
for row, prio in (("qwen3.8-flash-next-radiance-urgent", 9), ("qwen3.8-flash-next-radiance-low", 1)):
    if row not in cat_flat:
        errs.append(f"the catalog has no {row} row (C05 must land before this suite's bar)")
    else:
        m = re.search(re.escape(row) + r".{0,260}?priority[^\n]{0,6}?(\d+)", cat_flat)
        if not m or int(m.group(1)) != prio:
            errs.append(f"catalog {row} body.priority is not {prio} (radiance rows 9/5/1, Q2 — a 1/5/9 port fails HERE)")

# The five step-0 gates (a)-(e) present BY NAME + the sysfs receipts + the
# fallback-trap tree (R6-Q4-5 a; the decision tree records both remedies).
m0 = re.search(r"(?m)^#{1,6}\s*(Step\s+)?0(?=[.: \t—–-]|$).*?(?=^#{1,6}\s*(Step\s+)?1(?=[.: \t—–-]|$))", rb, re.S | re.M)
if not m0:
    errs.append("no step-0 section to search for the (a)-(e) gates")
else:
    sec = m0.group(0)
    for letter in "abcde":
        if not re.search(rf"\({letter}\)", sec):
            errs.append(f"step-0 gate ({letter}) missing by name")
    if not (("/sys/module/amdgpu" in sec and "revision" in sec) or ("device" in sec and "revision" in sec and "sysfs" in sec)):
        errs.append("gate (a) lacks the sysfs device/revision receipt path")
    if not re.search(r"(?i)fallback", sec) or not re.search(r"(?i)decision tree", sec):
        errs.append("the fallback trap + decision tree are not in step-0 (unknown revision -> bare amd.com/gpu; remedies: pin the claim by the materialized name / fix the flip list)")
    if not re.search(r"(?i)request.?sum|allocatable", sec):
        errs.append("gate (b) lacks the request-sum arithmetic (64+64+4 > 125.08 — the Pending-by-design gate)")
# Belt-and-braces PCI assert survives (D18 — gate (e) in the R6-Q4-5 numbering):
if not re.search(r"(?i)belt.and.braces", rb) or "gfx1201" not in rb:
    errs.append("the belt-and-braces PCI/gfx1201 startup assert (R6-Q4-5 e) is not recorded")
# C08 T-B/T-E (amendment): the names' PROVENANCE moved to the patched table —
# the doc must say so (receipts + the mount-stops-applying watch).
if not re.search(r"(?i)patched[- \t]table|amdgpu\.ids", rb):
    errs.append("the runbook never names the patched-table/amdgpu.ids provenance (D24: the gate-(a) "
                "receipts now derive gpu-r9700-1 THROUGH the ConfigMap'd table)")
if not re.search(r"(?i)watch[\n]{0,160}(ids|mount|lookup|baked)|ids[\n]{0,80}(path|lookup)[\n]{0,120}(watch|baked|falls? back|stops? applying)", rb):
    errs.append("the mount-stops-applying WATCH sentence (image IDs-path move => baked name returns "
                "=> claim Pending; receipts catch it) is missing (C08 T-E)")

if errs:
    print("; ".join(errs), file=sys.stderr); sys.exit(1)
PY
  if [ "$rc" -ne 0 ]; then
    fail "T3: names/digests/polarity/gates contract violated (C06 T3 — diagnostics above)"
  fi
  ok "T3: names block complete (served id, peer URL, both pool names), the triple digest ledger pairs runbook<->charts<->renovate comments, higher-wins 9/5/1 in runbook AND catalog, the five step-0 gates (a)-(e) present by name with the sysfs receipts + fallback-trap decision tree + request-sum Pending gate, and the belt-and-braces gfx1201 assert"
fi

# --- T4: research citations resolve into this folder's RESEARCH.md ---------------
if want t4; then
  [ -f "$RUNBOOK" ] || fail "T4: $RUNBOOK missing (see T1)"
  [ -f "$RESEARCH" ] || fail "T4: $RESEARCH missing (the plan-folder research record)"
  if ! python3 - "$RUNBOOK" "$RESEARCH" <<'PY'
import re, sys
doc = open(sys.argv[1]).read()
research = open(sys.argv[2]).read()

rq = {int(m.group(1)) for m in re.finditer(r"(?m)^## RQ([0-5]) —", research)}
m_r6 = re.search(r"(?m)^## R6 —", research)
r6_part = research[m_r6.start():] if m_r6 else ""
r6q = {int(m.group(1)) for m in re.finditer(r"(?m)^### R6-Q([1-5]) —", r6_part)}
# C08 (§R7): the R7 part runs from its heading to EOF (it is the tail round).
m_r7 = re.search(r"(?m)^## §?R7", research)  # heading carries the § literally (## §R7 —)
r7_part = research[m_r7.start():] if m_r7 else ""
r7q = {int(m.group(1)) for m in re.finditer(r"(?m)^### R7-Q([0-9]+) —", r7_part)}

def numbered_items(t):
    return len(re.findall(r"(?m)^\d+\.\s", t))

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
for m in re.finditer(r"(?<![A-Za-z0-9])R7\s*[-–]\s*Q\s*([0-9]+)(?:\s*[-–]\s*(\d+|[A-Za-z]+))?", doc):
    cites.append(("R7Q", int(m.group(1)), None))
for m in re.finditer(r"§\s*R7(?![\w-])", doc):
    cites.append(("S7", None, None))
for m in re.finditer(r"§\s*R6(?![\w-])", doc):
    cites.append(("S6", None, None))
for m in re.finditer(r"(?<![A-Za-z0-9])R6\s+OQ\s*(\d+)", doc, re.I):
    cites.append(("R6OQ", None, int(m.group(1))))
for m in re.finditer(r"(?<![A-Za-z0-9-])OQ\s*(\d+)", doc, re.I):
    if not re.search(r"R6\s*[-–]?\s*$", doc[max(0, m.start() - 6):m.start()], re.I):
        cites.append(("OQ", None, int(m.group(1))))

if not cites:
    sys.exit("the runbook cites NO research heading — C06 AC2: every number traces to RESEARCH "
             "(incl. §R6 citations) or the shipped values, none to the card guide")

errs = []
for kind, n, extra in sorted(set(cites), key=lambda c: (c[0], c[1] or 0, c[2] or 0)):
    if kind == "RQ":
        if n not in rq:
            errs.append(f"RQ{n}: no '## RQ{n} —' heading in RESEARCH.md (stale pointer)")
    elif kind == "R6Q":
        if n not in r6q:
            errs.append(f"R6-Q{n}: no '### R6-Q{n} —' heading in the §R6 block")
        elif extra is not None and extra not in r6q_rows(n):
            errs.append(f"R6-Q{n}-{extra}: no table row {extra} inside '### R6-Q{n}'")
    elif kind == "R7Q":
        if n not in r7q:
            errs.append(f"R7-Q{n}: no '### R7-Q{n}' heading in the §R7 block")
    elif kind == "S7":
        if not m_r7:
            errs.append("§R7: RESEARCH.md has no R7 section")
    elif kind == "S6":
        if not m_r6:
            errs.append("§R6: RESEARCH.md has no R6 section")
    elif kind == "R6OQ":
        if extra > r6_oq:
            errs.append(f"R6 OQ{extra}: the R6 residual list has only {r6_oq} numbered items")
    elif kind == "OQ":
        if extra > main_oq:
            errs.append(f"OQ{extra}: the main open-questions list has only {main_oq} numbered items")

if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PY
  then
    fail "T4: a research citation in the runbook does not resolve (C06 AC2 — stale pointer, diagnostics above)"
  fi
  ok "T4: every RQ/R6-Q(-row)/§R6/OQ reference in the runbook lands on a real heading of this folder's RESEARCH.md incl. the §R6 block"
fi

# --- T5: the step content the chunk names ----------------------------------------
if want t5; then
  [ -f "$RUNBOOK" ] || fail "T5: $RUNBOOK missing (see T1)"
  rc=0
  python3 - "$RUNBOOK" <<'PY' || rc=$?
import re, sys
rb = open(sys.argv[1]).read()
errs = []

def need(pattern, where, flags=0):
    if not re.search(pattern, rb, flags):
        errs.append(f"step content missing in {where}: pattern {pattern!r}")

def need_lit(needle, where):
    if needle not in rb:
        errs.append(f"step content missing in {where}: {needle!r}")

# The 66 GiB-class first load (the peer-timeout rationale restated, C04):
need(r"66 GiB", "the cold-load marker (first request is minutes-class)")
# The x4 prefill band at the 55k class (RESEARCH Serving envelope receipts):
need(r"450\s*[–—-]\s*600", "the x4 prefill band 450-600 tok/s")
need(r"55k", "the @55k class the prefill band is quoted at")
# The pinned-RAM cap of this host:
need_lit("120.6", "the pinned cap (GiB) the host-prep arithmetic rides on")
# The refusal ladder at the SINGLE scalars (OQ3 closes here): pool steps, ctx
# steps, and the mutually-exclusive prefix tier ONLY as last resort with
# explicit owner sign-off (documented-option marks, never shipped-value).
need(r"40000", "the ladder DOWN pool rung (43000 -> 40000)")
need(r"36000", "the ladder DOWN pool rung (40000 -> 36000)")
need(r"128K|131072", "the ladder DOWN ctx rung (200K -> 128K)")
need(r"64K|65536", "the ladder DOWN ctx rung (128K -> 64K)")
need(r"(?i)last[ -]resort", "the prefix-cache tier marked LAST resort")
need(r"(?i)owner sign.?off", "the prefix-tier fallback requires explicit owner sign-off, recorded")
need(r"(?i)(ladder up|64 ?Gi[^.\n]{0,80}(72|80|96))", "the guaranteedMemoryGi ladder UP (64 -> 72/80/96 while strata is down)")
# /health startup probes, never a model endpoint (probe law, gotcha 10):
need(r"(?i)startup[^\n]{0,60}/health", "the /health startup probe")
if re.search(r"(?i)(probe|healthcheck)[^.]{0,80}/v1/models", rb):
    errs.append("a /v1/models PROBE appears — probe law: /health only (it triggers loads)")
# Absence bars (verbatim, no exception window in the runbook — unlike the TP2 doc):
if "--expert-vs-cache-ratio" in rb:
    errs.append("--expert-vs-cache-ratio (stale guide flag) shipped into the runbook at all")
if re.search(r"radiance\s+serve\b", rb, re.I):
    errs.append("a 'radiance serve' VERB token — the engine has no serve verb (RQ0)")
# The Pending-by-design handshake line (Q10/D17: 64+64+4 > 125.08 beside live
# strata is the designed state, radiance PENDING until the owner scales down):
need(r"(?is)pending[^\n]{0,200}(scale.?down|by design|handshake)|(scale.?down|by design|handshake)[^\n]{0,200}pending",
     "the Pending-by-design scale-down handshake")
# The 8-session gate at FULL sizing (RESEARCH OQ3 closes here):
need(r"(?i)(8.concurrent|8.session|eight.session)[^\n]{0,120}(gate|hold|start|concurrent)|(gate[^\n]{0,60}8 concurrent)",
     "the 8-session gate at full sizing")
need(r"(?i)kv.resident[^\n]{0,120}32768|32768", "the kv-resident 32768 lever the gate exercises")
# The polarity live-check (Q2) — metric names make it falsifiable:
need_lit("radiance:num_requests_preempted", "the preemption metric (higher-wins proof, step 8)")
need(r"(?i)429[^\n]{0,60}retry.?after|retry.?after[^\n]{0,60}429", "the 429 + Retry-After at --max-queued-requests depth")
# The image smoke leg (Q8) — retire-on-failure is the sanctioned rollback:
need(r"(?i)image[^\n]{0,80}(leg|smoke|request)|smoke[^\n]{0,60}image", "the IMAGE-request smoke leg (step 9)")
need(r"(?i)retire[^\n]{0,160}(input|image|catalog)|(input|image|catalog)[^\n]{0,160}retire",
     "the image-leg failure retires the catalog input:image claim (one-row edit, recorded)")
# ≥1 honest-envelope line (the x4 wall idle sessions re-pay):
need(r"(?i)honest[ -]envelope|re.?prefill[^\n]{0,120}(x4|wall)|(x4|wall)[^\n]{0,120}re.?prefill",
     "the honest-envelope line (kv-resident excludes the prefix tier; idle re-prefill pays the x4 wall)")
# Restore-back (step 10, Q10): strata scaled UP, runner route verified serving
# again — the loop literal survived the whole ticket (Q5/Q4):
need(r"(?i)restore", "the restore-back step")
need_lit("qwen3.8-flash-next-strata-q4", "the runner route string (re-verified after restore)")
# The lockstep-revert rollback law (R6-Q4-4, step 11): ONE git revert of the
# flip wave; the plugin revert and the llama-swap flip NEVER split:
need_lit("git revert", "the rollback recipe")
need(r"(?i)lockstep", "the lockstep-revert law")
need(r"(?i)never split|must revert in lockstep", "the never-split prohibition for the plugin+llama-swap pair")
# The owner protocol steps (Q10 verbatim, step 3): the exact kubectl scale
# recorded for convenience + the RSS/workingSet receipt for the owner's
# metrics window:
need(r"kubectl[^\n]*scale[^\n]*strata[^\n]*0|kubectl scale deployment[^\n]*--replicas=?[^\n]*0", "the owner-executed scale-down command (documented, never scripted by the repo)")
need(r"(?i)(rss|working.?set)[^\n]{0,120}(before|after|delta|record)", "the RSS/workingSet recording for the owner's metrics file")
# Staging readability trap (step 4): sha256sum vs ledger + the loud permission
# first-trap of the non-privileged class:
need_lit("sha256sum", "the landed-pack verification (step 4)")
need(r"(?i)0af5e962", "the pack lfs sha the receipt compares against")

if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PY
  if [ "$rc" -ne 0 ]; then
    fail "T5: the step content is incomplete (C06 T5 marker set — diagnostics above)"
  fi
  ok "T5: markers present (66 GiB-class first load, 450-600 @55k, 120.6 pin cap, the up/down ladder rungs marked documented-option with the prefix-tier last-resort owner-sign-off, /health startup with the /v1/models probe bar, no serve verb / no stale flag at all, Pending-by-design handshake, the 8-session gate, the preempted-metric + 429/Retry-After polarity proof, the image smoke leg with its retire-on-failure clause, an honest-envelope line, the restore-back step naming the runner route, the lockstep-revert rollback, the owner scale command + RSS receipts, the staging sha256 receipt)"
fi

printf 'PASS: radiance runbook contract checks (%d ok)\n' "$checks"
