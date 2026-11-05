#!/usr/bin/env bash
# vLLM on-target acceptance runbook contract (2026/2026-11-cf-105-feat-
# implement-vllm, C06): the operator-run acceptance document (in-repo
# precedent: .agents/notes/strata-host-prep-gpu-ai.md) — eleven numbered step
# groups (0-10), read+curl+git only (no cluster mutation commands), D4
# envelope constants that match the shipped values, research citations that
# resolve, and the step content the chunk names (the probe gates, the
# sleep/wake sequence, the honest envelope).
# Contract source: chunks/C06.md "## Tests" (T1-T4) + the C06 step-content
# contract (T5).
#
# T4 is a regex cross-check: every R<n> OQ<m> / R<n> §<m> / R<n> Q<m> /
# Post-Research V<m> citation in the runbook must land on a real heading in
# RESEARCH.md — it catches stale research pointers, the class of rot a
# hand-maintained runbook develops. It also fails if the runbook cites NO
# research gap at all (C06 AC2: the gap-closing checks must cite their gap).
# The §<m> and Q<m> forms both resolve to the '### Q<m>' heading inside the
# R<n> part (RESEARCH.md has no numbered '### <n>.' section headings, so the
# Q section is the only home for a section reference); the OQ form resolves to
# the m-th numbered item of the '### Open questions (R<n>)' list.
#
# Designed-RED until C06 lands: the runbook file is absent, so T1/T2/T4/T5
# fail naming the file and T3 fails on the absent C01/C02/C06 artifacts.
#
# Path overrides (fixture probe): each artifact path honours an env var so a
# conforming fixture set in a scratch dir can be verified without touching
# the tree. The defaults are the real repo paths.
#
# Run from the repo root:
#   bash tests/notes/vllm-runbook.sh            # T1..T5
#   bash tests/notes/vllm-runbook.sh T1 T2      # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

RUNBOOK="${VLLM_RUNBOOK:-.agents/notes/vllm-on-target-acceptance.md}"
RESEARCH=".agents/plans/2026/2026-11-cf-105-feat-implement-vllm/RESEARCH.md"
VALS="${VLLM_VALS:-services/gpu-ai/prod/values.yaml}"
CHART_VALUES="${VLLM_CHART_VALUES:-charts/vllm/values.yaml}"
LEDGER="${VLLM_LEDGER:-containers/vllm-rocm/README.md}"

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
  for t in 1 2 3 4 5; do WANT["t$t"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-5]$ ]] || fail "unknown test id '$a' (expected T1..T5)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- T1: exists, non-trivial, eleven step groups in order ---------------------
if want t1; then
  if [ ! -f "$RUNBOOK" ]; then
    fail "T1: $RUNBOOK missing — C06 (the on-target acceptance runbook) is not implemented"
  fi
  lines=$(wc -l < "$RUNBOOK")
  if [ "$lines" -lt 200 ]; then
    fail "T1: the runbook is only $lines lines — eleven step groups, each with command + expected result + failure meaning, cannot fit (want >= 200)"
  fi
  if ! python3 - "$RUNBOOK" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
# A step-group header: a markdown heading whose text starts with the step
# number, optionally "Step"-prefixed, followed by a separator. Sub-section
# headings (### 1.1) also start with the parent number, but the parent
# '## <n>.' heading always precedes its children, so the first hit per number
# is the group header.
first = {}
for i, ln in enumerate(text.splitlines()):
    if not ln.startswith("#"):
        continue
    for n in range(11):
        if n in first:
            continue
        if re.match(rf"^#{{1,6}}\s*(Step\s+)?{n}(?=[.: \t—–-]|$)", ln):
            first[n] = i
missing = [n for n in range(11) if n not in first]
if missing:
    sys.exit(f"missing step-group headers for steps: {missing}")
seq = [first[n] for n in sorted(first)]
if seq != sorted(seq):
    sys.exit(f"step-group headers out of order: {first}")
PY
  then
    fail "T1: the runbook does not carry all eleven step-group headers (0-10) in order (C06 AC1)"
  fi
  ok "T1: the runbook exists, is >= 200 lines, and carries all eleven step-group headers (0-10) in order"
fi

# --- T2: mutation-command guard (read + curl + git only) ----------------------
if want t2; then
  [ -f "$RUNBOOK" ] || fail "T2: $RUNBOOK missing (see T1)"
  # Whole-line comments are exempt: the ground-rules prose may name the law it
  # states (the strata runbook precedent). Instruction lines — including fenced
  # code blocks — stay scanned.
  if grep -nE 'kubectl[[:space:]]+(apply|create|exec|delete|scale)([[:space:]]|$)' "$RUNBOOK" \
      | grep -vE '^[0-9]+:[[:space:]]*#' | grep -q .; then
    fail "T2: a kubectl apply/create/exec/delete/scale instruction appears in the runbook — the repo is ArgoCD-only (no kubectl mutations, no pod-exec tier; node-side one-shot container runs are docker/podman run, not kubectl exec; C06 AC3)"
  fi
  if grep -nE 'argocd[[:space:]]+app[[:space:]]+sync' "$RUNBOOK" \
      | grep -vE '^[0-9]+:[[:space:]]*#' | grep -q .; then
    fail "T2: an 'argocd app sync' instruction appears in the runbook — sync is ArgoCD's own reconciliation, never a runbook step (C06 AC3)"
  fi
  ok "T2: no kubectl mutation / kubectl exec / argocd app sync instructions (read + curl + git only)"
fi

# --- T3: cross-reference consistency with the shipped values ------------------
if want t3; then
  for f in "$RUNBOOK" "$VALS" "$CHART_VALUES" "$LEDGER"; do
    [ -f "$f" ] || fail "T3: $f missing — the cross-reference needs the C01/C02/C06 artifacts (C06 runs after C01-C05)"
  done
  rc=0
  python3 - "$RUNBOOK" "$VALS" "$CHART_VALUES" "$LEDGER" <<'PY' || rc=$?
import re, sys, yaml
runbook, vals, chart_values, ledger = sys.argv[1:5]
rb = open(runbook).read()
led = open(ledger).read()
errs = []

def serve_flag(args, flag):
    for i, a in enumerate(args):
        if a == flag and i + 1 < len(args):
            return args[i + 1]
    return None

def load(path):
    with open(path) as f:
        return yaml.safe_load(f)

try:
    cv = load(chart_values)
    sv = load(vals)
except yaml.YAMLError as ex:
    print(f"a values file does not parse as YAML: {ex}", file=sys.stderr)
    sys.exit(2)

args = (cv or {}).get("serveArgs") or []

# The D4 envelope flags the chart must ship (locked decision D4; --model is
# spliced from the service modelPath at render time, so its values-level
# placeholder is not asserted here). str()-normalize: an unquoted 262144 / 4 /
# 0.95 parses as a number; the contract is the rendered arg string.
d4 = {
    "--served-model-name": "qwen3.8-27b-vllm",
    "--scheduling-policy": "priority",
    "--max-model-len": "262144",
    "--max-num-seqs": "4",
    "--kv-cache-dtype": "fp8",
    "--gpu-memory-utilization": "0.95",
}
for flag, want in d4.items():
    got = serve_flag(args, flag)
    if got is None:
        errs.append(f"charts/vllm serveArgs lacks {flag} (C02 D4 recipe)")
    elif str(got) != want:
        errs.append(f"charts/vllm serveArgs {flag} is {str(got)!r}, want {want!r} (C02 D4)")

# Served name also on the peer route (the FE hop lists it explicitly — peers
# is not a blanket URL proxy) and in the runbook.
peer = ((((sv or {}).get("llama-swap") or {}).get("config") or {}).get("peers") or {}).get("vllm") or {}
if peer.get("models") != ["qwen3.8-27b-vllm"]:
    errs.append(f"services peers.vllm.models is {peer.get('models')!r}, want exactly ['qwen3.8-27b-vllm'] (C03)")
if "qwen3.8-27b-vllm" not in rb:
    errs.append("the runbook never names the served model qwen3.8-27b-vllm (C06 AC5)")

# The runbook names the D4 envelope constants it documents. max-num-seqs is
# matched as a phrase (a bare '4' digit is present in any 200-line document).
if "262144" not in rb:
    errs.append("the runbook never names the 262144 context envelope (C06 AC5)")
if not re.search(r"max-num-seqs.{0,12}\b4\b", rb):
    errs.append("the runbook never states max-num-seqs 4 (C06 AC5)")
if "fp8" not in rb:
    errs.append("the runbook never names the fp8 KV-cache dtype (C06 AC5)")
if "0.95" not in rb:
    errs.append("the runbook never names the 0.95 gpu-memory-utilization (C06 AC5)")

# The 60 s scrape is the v4 feature default: the runbook asserts the ABSENCE
# of the metrics.scrapeInterval annotation, and the chart carries no such key.
# The chart check walks the parsed YAML keys (not the raw text) so a comment
# explaining the absence cannot trip it.
if "metrics.scrapeInterval" not in rb:
    errs.append("the runbook never asserts the ABSENCE of the metrics.scrapeInterval annotation (C06 AC5: the 60 s v4 feature default governs — the runbook must pin the absence)")
def scrape_keys(node, path=""):
    out = []
    if isinstance(node, dict):
        for k, v in node.items():
            if "scrapeinterval" in str(k).lower():
                out.append(path + str(k))
            out += scrape_keys(v, path + str(k) + ".")
    elif isinstance(node, list):
        for i, v in enumerate(node):
            out += scrape_keys(v, path + f"[{i}].")
    return out
for p in scrape_keys(cv):
    errs.append(f"charts/vllm/values.yaml carries a scrapeInterval key at {p} — the Q5 ruling forbids it (C02)")

# Priority class values: the runbook names urgent=1 and default=10; the peer
# floor in the values is the set-if-undefined default-class value 10.
def prio_named(value):
    return any(re.search(rf"priority[^\n]{{0,40}}\b{value}\b", ln, re.I)
               for ln in rb.splitlines())
for v in ("1", "10"):
    if not prio_named(v):
        errs.append(f"the runbook never names the vLLM priority value {v} (the urgent/default class constants, C06 AC5)")
floor = (((peer.get("filters") or {}).get("setParams")) or {}).get("priority?")
if floor != 10:
    errs.append(f"services peers.vllm.filters.setParams['priority?'] is {floor!r}, want 10 (the C03 D6 default-class floor)")

# Base tag: the runbook and the C01 ledger both name the bare base tag. The
# ledger is a tag->digest table, so the bare tag (not the full image:tag
# composite) is the cross-reference — matching C01 test t2.
if "v0.33.0-rocm100" not in rb:
    errs.append("the runbook never names the base tag v0.33.0-rocm100 (C06 AC5)")
if "v0.33.0-rocm100" not in led:
    errs.append("the C01 ledger does not name the base tag v0.33.0-rocm100 (see C01 test t2)")

if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PY
  if [ "$rc" -eq 2 ]; then
    fail "T3: a cross-reference values file does not parse as YAML (C06 AC5 — diagnostics above)"
  elif [ "$rc" -ne 0 ]; then
    fail "T3: runbook constants do not match the shipped values (C06 AC5 — diagnostics above)"
  fi
  ok "T3: runbook constants match the shipped values (served name, D4 envelope, scrapeInterval absence, priority 1/10 + floor, base tag)"
fi

# --- T4: research citations resolve into RESEARCH.md ---------------------------
if want t4; then
  [ -f "$RUNBOOK" ] || fail "T4: $RUNBOOK missing (see T1)"
  [ -f "$RESEARCH" ] || fail "T4: $RESEARCH missing (the plan-folder research record)"
  if ! python3 - "$RUNBOOK" "$RESEARCH" <<'PY'
import re, sys
rb = open(sys.argv[1]).read()
research = open(sys.argv[2]).read()

# Split RESEARCH.md into its R1-R5 parts (from "## R<n> —" to the next
# "## R<n+1> —" or "## Post Research") and keep the Post Research tail.
marks = [(m.start(), int(m.group(1))) for m in re.finditer(r"(?m)^## R([1-5]) —", research)]
post = re.search(r"(?m)^## Post Research", research)
parts = {}
for i, (start, n) in enumerate(marks):
    end = marks[i + 1][0] if i + 1 < len(marks) else (post.start() if post else len(research))
    parts[n] = research[start:end]
post_part = research[post.start():] if post else ""

def oq_items(n):
    m = re.search(r"(?m)^### Open questions \(R" + str(n) + r"\).*?(?=^### |\Z)", parts.get(n, ""), re.S)
    if not m:
        return 0
    return len(re.findall(r"(?m)^\d+\.\s", m.group(0)))

def has_q_heading(n, q):
    return re.search(rf"(?m)^###\s+Q{q}\s", parts.get(n, "")) is not None

def has_v_heading(v):
    return re.search(rf"(?m)^###\s+V{v}\s", post_part) is not None

cites = []  # (kind, n_or_None, number)
for m in re.finditer(r"(?<![A-Za-z0-9])R([1-5])\s*-?\s*OQ\s*(\d+)", rb, re.I):
    cites.append(("OQ", int(m.group(1)), int(m.group(2))))
for m in re.finditer(r"(?<![A-Za-z0-9])R([1-5])\s*-?\s*§\s*Q?(\d+)", rb):
    cites.append(("Q", int(m.group(1)), int(m.group(2))))
for m in re.finditer(r"(?<![A-Za-z0-9])R([1-5])\s+Q\s*(\d+)", rb):
    cites.append(("Q", int(m.group(1)), int(m.group(2))))
for m in re.finditer(r"(?<![A-Za-z0-9])Post\s*Research\s+V\s*(\d+)", rb, re.I):
    cites.append(("V", None, int(m.group(1))))

if not cites:
    sys.exit("the runbook cites NO research gap — C06 AC2: the gap-closing on-target checks must cite the gap they close (R<n> OQ<m> / R<n> §<m> / Post Research V<m>)")

errs = []
for kind, n, num in sorted(set(cites), key=lambda c: (str(c[0]), c[1] or 0, c[2])):
    if kind == "OQ":
        if not oq_items(n):
            errs.append(f"R{n} OQ{num}: RESEARCH.md has no 'Open questions (R{n})' section")
        elif num > oq_items(n):
            errs.append(f"R{n} OQ{num}: the R{n} open-questions list has only {oq_items(n)} numbered items (stale pointer)")
    elif kind == "Q":
        if not has_q_heading(n, num):
            errs.append(f"R{n} §{num}: no '### Q{num}' heading inside the R{n} part of RESEARCH.md (stale pointer)")
    else:  # V
        if not has_v_heading(num):
            errs.append(f"Post Research V{num}: no '### V{num}' heading in the Post Research part of RESEARCH.md (stale pointer)")

if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PY
  then
    fail "T4: a research citation in the runbook does not resolve (C06 AC2 — stale pointer, diagnostics above)"
  fi
  ok "T4: every R<n> OQ/§/Q and Post Research V<n> citation resolves to a real heading/section in RESEARCH.md"
fi

# --- T5: the step content the chunk names -------------------------------------
# T1 proves the eleven group headers exist; T5 proves the groups carry the
# named commands/constants, the sleep/wake sequence in order with its 2x-peak
# caveat, and the honest envelope (C06 AC1 + AC4). Each assertion below is an
# exact string the C06 chunk's step list names.
if want t5; then
  [ -f "$RUNBOOK" ] || fail "T5: $RUNBOOK missing (see T1)"
  rc=0
  python3 - "$RUNBOOK" <<'PY' || rc=$?
import re, sys
rb = open(sys.argv[1]).read()
low = rb.lower()
errs = []

# Technical tokens (flags, env vars, commands, metric/model/filename/URL) are
# matched verbatim (case=True): the operator copies them, so a case drift is a
# real bug. Prose concepts are matched case-insensitively.
def need(needle, where, case=True):
    hay = rb if case else low
    n = needle if case else needle.lower()
    if n not in hay:
        errs.append(f"step content missing in {where}: {needle!r}")

def need_re(pattern, where, flags=0):
    if not re.search(pattern, rb, flags):
        errs.append(f"step content missing in {where}: pattern {pattern!r}")

# The four on-target facts the runbook resolves (no exec tier in agent
# sessions), each with its named command.
need("--entrypoint rocminfo", "step 1 (the image-side ROCr enumeration gate that proves the R9700 index)")
need("gfx1201", "step 0/1 (the chip the R9700 enumerates as)")
need("ROCR_VISIBLE_DEVICES", "step 1 (the chip-targeting env whose spelling is confirmed on target)")
need("find /models", "step 2 (the weight-presence find)")
need("Qwen3.8-27B-UD-Q4_K_XL.gguf", "step 2 (the exact q4 GGUF filename — the --model value authority)")
need("import vllm_gguf_plugin", "step 3a (the patched-plugin import probe — the FIRST engine gate)")
need("/v1/models", "step 3b (the in-cluster served-name check)")
need("1-token", "step 3c (the GGUF serve + first-token proof completion)", case=False)

# The first engine gate is labelled as such (no public RDNA run exists —
# RESEARCH Post Research V1 — so the runbook must mark this gate).
need_re(r"first[ \t-]+engine[ \t-]+gate", "step 3 (the gate is the first on-RDNA engine proof)", re.I)

# FE chain + the urgent model row (the D6 class rows the priority work ships).
need("llama.spencerslab.com/v1", "step 4 (the FE chain the runbook smokes)")
need("qwen3.8-27b-vllm-urgent", "step 4 (the urgent OpenCode row whose body merge is live)")

# Priority proof (step 5): the policy flag the engine must run, the explicit
# body value, and the preemption metric.
need("--scheduling-policy priority", "step 5 (the policy that makes a non-zero priority legal)")
need("priority: 5", "step 5a (the explicit non-zero body value)")
need("vllm:num_preemptions_total", "step 5c (the preemption proof metric)")

# Benchmark + monitoring (steps 6-7) named signals.
need("vllm:kv_cache_usage_perc", "step 6f (the KV-pool exhaustion signal)")
need("up{job=\"vllm\"}", "step 7 (the Prometheus job-label fallback check)")
need("finished_reason", "step 7 (the enum values that feed the alert follow-up card)")

# The sleep-mode sequence (step 8) — the documented sequence, not a bare
# sleep/wake pair. Order: sleep -> verify VRAM reclamation -> wake -> Strata
# re-pin. The 2x-peak OOM caveat must be stated (the wake allocation can
# coexist with the not-yet-reclaimed one and OOM in cuMemCreate at 0.95).
i_sleep = rb.find("POST /sleep")
i_wake = rb.find("POST /wake_up")
if i_sleep < 0:
    errs.append("step 8 missing: 'POST /sleep' (level 1)")
if i_wake < 0:
    errs.append("step 8 missing: 'POST /wake_up'")
if 0 <= i_sleep < i_wake:
    need("vllm:engine_sleep_state", "step 8 (the VRAM-reclamation verify between sleep and wake)")
    need("rocm-smi", "step 8 (the R9700 free-VRAM node reading before waking)")
    need_re(r"do\s+not\s+wake|don'?t\s+wake|without\s+waking", "step 8 (the gate-failure branch: record and stop, do not wake)", re.I)
    i_repind = low.find("re-pin")
    if i_repind < 0 or i_repind < i_wake:
        errs.append("step 8 missing: the Strata re-pin AFTER the wake (Strata stays evicted for the whole window)")
else:
    errs.append("step 8: 'POST /sleep' must precede 'POST /wake_up' (the documented sequence, not a bare pair)")
need("cuMemCreate", "step 8 (the OOM site the 2x-peak caveat names)")
need_re(r"2\s*[×x]|twice", "step 8 (the ~2x peak factor of the caveat)", re.I)
need("gpu_memory_utilization", "step 8 (the high utilization that makes the 2x peak OOM)")
need("VLLM_SERVER_DEV_MODE", "step 8 (the C02 env that makes /sleep + /wake_up exist)")

# The honest envelope in the runbook header (D4, Q3 override): 1x256k fits,
# 4x100k at the pool edge, 256k x3-4 impossible, preemption is intended.
need("7.8", "envelope (one full 256k session ~7.8 GiB KV fits)")
need("13.4", "envelope (the ~13.4 GiB fp8-KV pool)")
need("12.2", "envelope (4x100k ~12.2 GiB at the edge)")
need_re(r"4\s*[×x]\s*100k", "envelope (the 4x100k concurrent point)", re.I)
need_re(r"256k", "envelope (the per-session room)", re.I)
need_re(r"impossible|infeasible", "envelope (256k x3-4 simultaneously is stated impossible)", re.I)
need_re(r"32\s*(GiB|GB)", "envelope (the single 32 GiB card the impossibility is against)", re.I)
need_re(r"preempt", "envelope (priority-preemption on pool exhaustion is intended behavior)", re.I)

if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PY
  if [ "$rc" -ne 0 ]; then
    fail "T5: the runbook step content is incomplete (C06 AC1/AC4 — the named commands, the sleep/wake sequence, or the honest envelope are missing; diagnostics above)"
  fi
  ok "T5: the step content is present (on-target facts, first engine gate, priority proof, sleep/wake sequence + 2x-peak caveat, honest envelope)"
fi

printf 'PASS: vllm runbook contract checks (%d ok)\n' "$checks"
