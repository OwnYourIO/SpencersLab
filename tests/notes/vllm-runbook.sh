#!/usr/bin/env bash
# vLLM on-target acceptance runbook contract (2026/2026-11-cf-105-feat-
# implement-vllm, C06; re-pinned by 2026/2026-11-cf-131-feat-vllm-fp8-official
# C05): the operator-run acceptance document (in-repo precedent:
# .agents/notes/strata-host-prep-gpu-ai.md) — eleven numbered step groups
# (0-10), read+curl+git only (no cluster mutation commands), envelope and
# recipe constants that match the shipped values, research citations that
# resolve, and the step content the chunk names (the 0.30 first-engine
# marker set, the day-one re-measure gate, the int4 qualification gate, the
# tool smoke, the one-engine-per-card law, the honest envelope).
# Contract source: chunks/C05.md "## Tests" (T3/T5 re-pin) + T1/T2/T4 carried
# byte-untouched from the cf-105 C06 contract.
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
# cf-105-vllm-followup C03 re-pin (2026-11-06): the four-class priority
# amendment supersedes cf-105 D6/HR2 — T3's class-value sweep goes
# ("1", "10") -> ("1", "5", "9") and its floor leg 10 -> 5 (the floor
# follows the default class, D2); T5 gains the qwen3.8-27b-vllm-low
# names-block needle. T1/T2/T4 stayed byte-untouched then, and again under
# the cf-131 re-pin below (the runbook edits are text-only).
# cf-131 note: the resolver chases ONLY these forms into the cf-105 research
# file — the cf-131 record cites (RESEARCH R2/R3 'L<n>.<m>' section refs and
# bracketed source ids) are plain text, T4-inert by the standing design; the
# runbook keeps ≥1 live cf-105 citation where the fact still lives (the R4
# preemption-semantics reference is the four-class victim order's authority,
# engine-version-agnostic — the named pick, C05 AC).
#
# cf-131 C05 re-pin (2026-11-08, rounds 1+2+3). T3: LEDGER repoints to the
# C01 re-export README (containers/vllm-radiance-mxfp4/README.md); the d4
# dict becomes the 12-flag 0.30 shipped-shape set (round-2 Q2 Shape-B
# seqs/chunk + the round-3 Q11 engine-cap 262144 on the max-model-len leg);
# a new ABSENCE leg pins that the chart ships NO --kv-cache-memory-bytes
# (the re-measure gate owns the pool, D24); the base-tag leg checks
# magiccodingman/vllm-radiance + 1.0.397 in the runbook AND the chart values
# (the values-side ledger mirror) plus the full digest in the chart values
# and the ledger pairing across surfaces; the phrase needles re-pin to the
# true-axis set (262144 == engine cap == catalog, D31) alongside the
# recorded 220000-class reference row. T5: the FP8/GGUF/sleep-wake-era legs
# are swapped for the 0.30 marker set, the two staging shas + the marker,
# the day-one gates (re-measure / int4 two-edit / tool-smoke keypress), the
# re-export image at step 1.4, the one-engine-per-card law + the
# kv-offloading escape hatch, and the 8.49/137.7/416.3 recorded numbers.
# T1/T2/T4: no structural edits (the recorded-alternatives + public-host
# tail are non-numbered sections, T1-inert; the day-one gates ride as
# sub-steps of groups 3/5/6; the 3.6-FAIL fp8+R4D return is a GIT-vals
# step and the DRY_RUN capture a `kubectl get` read — both T2-sanctioned
# shapes).
# D36 amendment re-pin (2026-11-09, the q4 KV package — the owner's R6-Q1
# ruling "A — q4 default, boot at 262144"): T3's shipped-shape dict is the
# 13-flag q4 set (kv-cache-dtype int4_per_token_head, attention-backend
# TRITON_ATTN, gpu-memory-utilization 0.98, the new --mamba-ssm-cache-dtype
# bfloat16 pair); the T3/T5 needles follow — 0.90 → 0.98, the R4D
# target-backend leg → TRITON_ATTN, the int4 gate reads as boot-config
# qualification (the fp8+R4D pair survives in the runbook as the recorded
# ALTERNATIVE's signature, not barred). The 20-var env law, the mm JSON and
# the 262144 pins are untouched by D36; T1/T2/T4 unaffected.
# D38 amendment re-pin (2026-11-09, the vision-drop + f2 package on the
# R8/R8b ground — the owner's R8-Q1 "C — drop vision" + R8b-Q1 "C + f2",
# DECISIONS D38): T3's shipped-shape dict drops the --limit-mm-per-prompt
# entry (the d13 form becomes the d12 form, recounted at the shipped list;
# the ssm leg stays) and gains the --language-model-only token-presence leg
# plus the mm-flag ABSENCE leg; the T5 3.4/multimodal/data-URL needle trio
# retires with the smoke — the runbook marks 3.4 RETIRED BY D38 and that
# marker is the new leg — and the step-3 marker legs invert: the registry
# text-only INFO line is the positive marker, the Flash-(Triton)-on-RDNA
# and MMEncoderAttention literals the recorded ABSENCE pair (verbatim for
# the 48 GB-RDNA3 re-enable rider). T1/T2/T4 unaffected; the env law moves
# 20 -> 21 vars (the f2 var) — that leg lives in charts/vllm/tests, not
# here.
# D39 amendment re-pin (2026-11-09, the per-drafter KV-dtype key, route A′
# on the R9/R10 ground — the owner's R10-Q1 "A′ now + C on watch", DECISIONS
# D39): crash #6 (the by-design non-causal drafter inheriting the global
# int4 into the causal-only assert) closes with ONE key inside the existing
# spec-JSON token — serveArgs stay 44, the d12 dict stays 12 keys — so the
# T3 --speculative-config VALUE re-pins to the shipped 7-key literal
# (verbatim copy, independent of the chart testlib constant) and T5 gains
# the 3.6 assert-marker-pair needle riding the dev's new row (the runbook
# records both readings: ABSENCE = the fix line, PRESENCE = the key lost).
# T1/T2/T4 unaffected.
# D40 amendment re-pin (2026-11-09, the skip-layers fix on the R11 ground
# — the owner's R11-Q1 "skip-layers in, A′ out", DECISIONS D40): crash #7
# falsified A′ on-target — the spec key made the drafter's bf16 page the
# model MAX page and the pages do not integer-divide, so page unification
# strided-pads the WHOLE pool (demand ×3.7647, the 19.05-vs-5.69 sizing
# ValueError). The T3 shipped-shape dict therefore re-pins the
# --speculative-config VALUE back to the reverted pre-D39 literal and
# GAINS the --kv-cache-dtype-skip-layers sliding_window entry — the pair
# forces exactly the 5 drafter SWA layers to auto/bf16 per-layer and
# Phase-3 aligns their pages onto the int4 page, no padding anywhere.
# d12 becomes d13, recounted at the shipped list; serveArgs move 44 -> 46
# (the render-verbatim pin lives in charts/vllm/tests). The T5 assert
# needle STAYS as the crash-#6 literal, its drift sense re-reads:
# PRESENCE now means the skip-layers pair was lost (never re-add the D39
# key). T1/T2/T4 unaffected.
#
# Designed-RED window: T3/T5 name artifacts the cf-131 waves land in order —
# the ledger (C01), the chart constants (C02/C03), the runbook text (C05).
# C05's bar is the full pass; earlier chunks do not run this suite.
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
LEDGER="${VLLM_LEDGER:-containers/vllm-radiance-mxfp4/README.md}"

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
    [ -f "$f" ] || fail "T3: $f missing — the cross-reference needs the cf-131 C01-C05 artifacts (this suite's bar is the final chunk)"
  done
  rc=0
  python3 - "$RUNBOOK" "$VALS" "$CHART_VALUES" "$LEDGER" <<'PY' || rc=$?
import re, sys, yaml
runbook, vals, chart_values, ledger = sys.argv[1:5]
rb = open(runbook).read()
led = open(ledger).read()
cv_raw = open(chart_values).read()
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

args = ((cv or {}).get("app-template") or {}).get("serveArgs") or []

# The shipped-shape flags the chart must carry (cf-131 C05 re-pin,
# D36-amended, D38-recounted, D40-grown): the round-2 Q2 Shape-B seqs/chunk constants,
# the round-3 Q11 engine-cap 262144 on the max-model-len leg (and the dflash
# JSON's matched draft context — the same 262144, the drafter's native
# ceiling), the D36 q4 package (int4_per_token_head + the TRITON_ATTN target
# + the ssm-bf16 pair, util at the 0.98 ceiling), the two Q7 carries, the
# D38 shipped-shape swap, and the D40 skip-layers pair entry
# (--kv-cache-dtype-skip-layers sliding_window) beside the D40-reverted
# --speculative-config value: the pair forces the 5 drafter SWA layers to
# auto/bf16 per-layer and Phase-3 aligns their pages onto the int4 page,
# the per-drafter spec key D39 shipped is OUT (its bf16 MAX page
# strided-padded the whole pool — crash #7). The mm pair LEFT the dict with
# D38's vision
# drop (its json.loads record now rides the values re-enable rider verbatim)
# and the D38 legs below take its place: the single-token
# --language-model-only presence + the mm-flag absence. The tool trio and
# the sampling surface are pinned by the pytest render-verbatim suite
# (charts/vllm/tests); this dict is the envelope + spec + carry cross-check
# between the runbook prose and the chart values.
# str()-normalize: an unquoted 262144 / 3 / 2560 parses as a number — it
# must still compare equal to the rendered arg string; quote survival on
# the util value is the pytest verbatim suite's law, not this leg's.
d13 = {
    "--served-model-name": "qwen3.8-27b-vllm",
    "--tensor-parallel-size": "1",
    "--max-num-seqs": "3",
    "--max-model-len": "262144",
    "--max-num-batched-tokens": "2560",
    "--gpu-memory-utilization": "0.98",
    "--kv-cache-dtype": "int4_per_token_head",
    "--kv-cache-dtype-skip-layers": "sliding_window",
    "--attention-backend": "TRITON_ATTN",
    "--mamba-ssm-cache-dtype": "bfloat16",
    "--scheduling-policy": "priority",
    "--watermark": "0.05",
    "--speculative-config": '{"method":"dflash","model":"/models/Qwen3.8-27B-DFlash2-FP8","num_speculative_tokens":7,"max_model_len":262144,"attention_backend":"TRITON_ATTN","disable_padded_drafter_batch":true}',
}
for flag, want in d13.items():
    got = serve_flag(args, flag)
    if got is None:
        errs.append(f"charts/vllm serveArgs lacks {flag} (C02 D24 recipe, D36/D38/D40 shape)")
    elif str(got) != want:
        errs.append(f"charts/vllm serveArgs {flag} is {str(got)!r}, want {want!r} (C02 D24, D36)")

# The re-measure-gate law (D24): the chart ships NO KV-pool pin — the day-one
# gate derives the pool at the shipped shape; a --kv-cache-memory-bytes line
# here would silently pre-empt the gate's measurement.
if "--kv-cache-memory-bytes" in args:
    errs.append("charts/vllm serveArgs carries --kv-cache-memory-bytes — the re-measure gate owns the pool (D24); the chart ships no pin")

# The D38 vision swap (the owner's R8-Q1 + R8b-Q1 rulings): the bool token
# ships in the carries tail as a single arg — no JSON value, so it takes a
# presence leg, not a dict entry — and the removed mm pair must stay OUT of
# the shipped shape; it returns only with the 48 GB-RDNA3 re-enable
# copy-back recorded in the values serveArgs comment. The flag choice is
# load-bearing: without it the image-0 trap (video defaults to 999) keeps
# the encoder rehearsal alive at the same peak [R8b 227].
if "--language-model-only" not in args:
    errs.append("charts/vllm serveArgs lacks --language-model-only — the D38 text-only token; its absence re-arms the multimodal warmup rehearsal the vision drop paid away")
if "--limit-mm-per-prompt" in args:
    errs.append("charts/vllm serveArgs carries --limit-mm-per-prompt — D38 dropped the mm pair; it may return only with the 48 GB-RDNA3 re-enable rider (values comment + catalog input leg + runbook rows copy back together)")

# Served name also on the peer route (the FE hop lists it explicitly — peers
# is not a blanket URL proxy) and in the runbook.
peer = ((((sv or {}).get("llama-swap") or {}).get("config") or {}).get("peers") or {}).get("vllm") or {}
if peer.get("models") != ["qwen3.8-27b-vllm"]:
    errs.append(f"services peers.vllm.models is {peer.get('models')!r}, want exactly ['qwen3.8-27b-vllm'] (C03)")
if "qwen3.8-27b-vllm" not in rb:
    errs.append("the runbook never names the served model qwen3.8-27b-vllm (C06 AC5)")

# The runbook names the shipped-shape constants it documents (C05 re-pin).
# 262144 is the TRUE AXIS — catalog == engine cap == the dflash draft
# context (round-2 Q3 keep + round-3 Q11 engine-cap ruling, D31); 220000
# survives as the recorded reference row's class (the 8.49 GiB pin's
# 0.9.3-stack provenance + the superseded Shape-B maxlen leg). Both numbers
# in the runbook, each with its role — that division is the ruling's
# documentation half, so both legs bind.
if "262144" not in rb:
    errs.append("the runbook never names the 262144 shipped context cap (the true axis — names block + envelope + step 3.2, D31; C05 AC)")
if "220000" not in rb:
    errs.append("the runbook never names 220000 — the recorded reference row's provenance class (the 8.49 GiB pin's 220000-class 0.9.3 origin; C05 names-block + envelope spec)")
if not re.search(r"max-num-seqs.{0,12}\b3\b", rb):
    errs.append("the runbook never states max-num-seqs 3 (the Shape-B constant, round-2 Q2; C05 AC)")
if "0.98" not in rb:
    errs.append("the runbook never names the 0.98 gpu-memory-utilization start (the D36 ceiling — 0.99 startup-dead on this card; C05 AC)")
if "fp8" not in rb:
    errs.append("the runbook never names fp8 — the documented KV toggle + the recorded fp8+R4D ALTERNATIVE under D36 (C05 AC)")
if "int4_per_token_head" not in rb:
    errs.append("the runbook never names int4_per_token_head — the D36 ship default, whose 3.6 gate is boot-config qualification binding the ship path")
if "TRITON_ATTN" not in rb:
    errs.append("the runbook never names the TRITON_ATTN target attention backend (the shipped --attention-backend value, D36 — R4D survives as the recorded alternative's wording; C05 step-3 marker set)")
if "spec_decode" not in rb or "diffusion" not in rb:
    errs.append("the runbook's spec-decode counter family is not the either-family law (spec_decode_* EXPECTED at 0.30 with the diffusion_* recorded fallback, R3 L2.3 — the on-target capture closes it; C05 step-3 spec)")
if "re-measure" not in rb.lower():
    errs.append("the runbook never states the re-measure gate — the SOLE envelope path at 0.30 (R3 L2.4, D29)")
if "HSA_TOOLS_DISABLE_REGISTER" not in rb:
    errs.append("the runbook never names the HSA idle-spin workaround var (issue #6/#12 mitigation, R3 L1.4 / R3-Q5; the #6/#12/#42 watch lives at step 10)")
if "one-engine-per-card" not in rb.lower():
    errs.append("the runbook never states the one-engine-per-card law (step 8/9 re-shape, the Q7 sleep-mode drop's consequence)")

# The true-axis phrasing itself: the names block pairs the catalog field
# with the cap, and the ruling's own phrase (D31) states its accuracy.
if not re.search(r"limit\.context[^\n]{0,80}262144", rb):
    errs.append("the runbook never pairs limit.context with 262144 (the true-axis note's catalog half, D31; C05 names-block spec)")
if not re.search(r"(?i)true at the engine", rb):
    errs.append("the runbook never states the advertisement is 'true at the engine' (the round-3 Q11 ruling's wording, D31)")

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

# Priority class values: the runbook names urgent=1, default=5, low=9 (the
# four-class amendment, cf-105-vllm-followup C03); the peer floor in the
# values is the set-if-undefined default-class value 5. The class constants
# are the byte-stable law the card protects — carried UNCHANGED by cf-131.
def prio_named(value):
    return any(re.search(rf"priority[^\n]{{0,40}}\b{value}\b", ln, re.I)
               for ln in rb.splitlines())
for v in ("1", "5", "9"):
    if not prio_named(v):
        errs.append(f"the runbook never names the vLLM priority value {v} (the urgent/default/low class constants, C06 AC5 — cf-105-vllm-followup C03 re-pin)")
floor = (((peer.get("filters") or {}).get("setParams")) or {}).get("priority?")
if floor != 5:
    errs.append(f"services peers.vllm.filters.setParams['priority?'] is {floor!r}, want 5 (the default-class floor — the floor follows the default class, cf-105-vllm-followup D2)")

# The single ledger pin (D23): the runbook names the upstream base, the
# chart values mirror it (the values-side ledger comment), and the ledger +
# chart share the full digest — the re-export's upstream identity must be
# ONE record read from three surfaces.
for where, hay in (("the runbook", rb), ("the chart values", cv_raw)):
    if "magiccodingman/vllm-radiance" not in hay:
        errs.append(f"{where} never names the upstream base image magiccodingman/vllm-radiance (C05 names block / C02 ledger comment, D23)")
    if "1.0.397" not in hay:
        errs.append(f"{where} never names the base tag 1.0.397 (the single ledger pin, D23)")
DIGEST = "sha256:b73bf3e41bc0a1cf7aaa5935bebe31123f549639e69b61a3ffa81acd5f7313e0"
if DIGEST not in cv_raw:
    errs.append("the chart values do not carry the full upstream digest sha256:b73bf3e4...7313e0 — the values-side mirror of the re-export's identity (C02 task, D23)")
if DIGEST not in led:
    errs.append(f"the C01 ledger does not carry the full digest {DIGEST[:19]}... — the tag→pin table must be the pairing authority (see tests/containers/vllm-radiance-mxfp4.sh t3)")

if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PY
  if [ "$rc" -eq 2 ]; then
    fail "T3: a cross-reference values file does not parse as YAML (C06 AC5 — diagnostics above)"
  elif [ "$rc" -ne 0 ]; then
    fail "T3: runbook constants do not match the shipped values (C05 AC3 — diagnostics above)"
  fi
  ok "T3: runbook constants match the shipped values (served name, the 13-flag shipped-shape dict recounted at the D40 list incl. the skip-layers pair and the reverted spec JSON, the --kv-cache-memory-bytes ABSENCE leg, the D38 --language-model-only presence + mm-flag absence legs, the true-axis + recorded-row phrase needles, scrapeInterval absence, priority 1/5/9 + floor 5, the 0.30 base tag across runbook/chart/ledger + the digest pairing)"
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
# cf-131 C05 named commands/constants: the 0.30 first-engine marker set +
# the DRY_RUN-analog capture surface, the staging facts (raw release +
# revision-pinned drafter + the both-sha marker), the day-one gates
# (re-measure / int4 boot-config qualification / tool smoke), the
# one-engine-per-card coexistence law, the recorded anchor classes and the
# honest envelope (pool-governed at the 262144 engine cap). Each assertion
# below is an exact string the C05 chunk's step list names the runbook must
# ship.
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

# Steps 0-2: the host gates carry; step 1.4's image-side enumeration one-shot
# now names the re-export (the swap C05 records); the chip-targeting pair is
# the D25 law (ROCR + the HIP twin pinning the 8060S out); step 2's staging
# facts are the init container's trees + marker + the two revision pins, and
# the Q8 contingency's first rung.
need("gfx1201", "step 0/1 (the chip the R9700 enumerates as)")
need("--entrypoint rocminfo", "step 1.4 (the image-side ROCr enumeration gate proving the R9700 index)")
need("ghcr.io/ownyourio/vllm-radiance-mxfp4", "step 1.4 (the one-shot runs the C01 re-export, not the retired overlay or the upstream)")
need("ROCR_VISIBLE_DEVICES", "step 1.3 (the chip-targeting env)")
need("HIP_VISIBLE_DEVICES", "step 1.3 (the 8060S-exclusion twin, D25)")
need("ls /models/Qwen3.8-27B-Quark-AWQ-MXFP4", "step 2.1 (the raw-release tree listing — the path authority, replacing the GGUF-era find)")
need(".staged-mxfp4", "step 2.1 (the both-sha marker file — the staging provenance in one glance)")
need("93245f7c", "step 2 (the raw-release source revision pin)")
need("ee0cb26a", "step 2 (the qualified drafter revision pin)")
need("RADIANCE_QUARK_BF16_MTP", "step 2.3 (the Q8 contingency ladder's first rung — the mtp-profile bf16-head load path)")

# Step 3: the FIRST-ENGINE GATE is the 0.30 marker set. The wrong-engine
# absence markers (no gguf plugin import, no stock-FP8 default-kernel line)
# are runbook prose asserted as ABSENT in the log, not as needles in the
# document — the present marker lines below are the pins (C05 T5 spec).
# The D38 amendment (vision drop, the owner's R8-Q1/R8b-Q1 rulings) INVERTS
# the ViT legs: at text-only serving the ViT never runs, so the runbook
# records the Flash-(Triton)-on-RDNA literal (rocm.py L771-773 @ ced6857a
# [139]) and the per-layer MMEncoderAttention confirm as an ABSENCE PAIR —
# their PRESENCE would mean the --language-model-only token was lost — and
# the literals stay recorded verbatim for the 48 GB-RDNA3 re-enable rider
# [R8b.4e]. The NEW positive marker is the registry's text-only INFO line
# (registry.py L146-149 @ ced6857a, R8b 226; the R8.1c compute_mm_encoder_budget
# WARNING correction rides the same runbook row). The bare CDNA-form Flash
# line stays the arch-view drift signal the runbook records BARRED (R5.3),
# that reading standing whenever the ViT runs.
need_re(r"first[ \t-]+engine[ \t-]+gate", "step 3 (the gate is the first on-RDNA 0.30-stack proof)", re.I)
need("Application startup complete", "step 3 (the vLLM-standard startup-complete marker)")
need("PIECEWISE", "step 3 (the dflash lane's compilation mode — the entrypoint-appended --compilation-config value)")
need("TRITON_ATTN", "step 3 (the target-attention engagement marker — the D36 q4 package: int4 is served only by TRITON_ATTN; the R4D+fp8kv kernel pair survives in the runbook as the recorded ALTERNATIVE's signature, not a barred string)")
need("All limits of multimodal modalities supported by the model are set to 0, running in text-only mode.", "step 3 (the D38 positive text-only marker — the registry INFO-once line the boot day greps)")
need("Using Flash Attention (Triton backend) for ViT model on RDNA.", "step 3 (the D38 ABSENCE pair, first literal — recorded in the runbook's absence-expected row, verbatim for the re-enable rider; PRESENCE of this line in the pod log = the text-only token was lost)")
need("Using AttentionBackendEnum.FLASH_ATTN for MMEncoderAttention.", "step 3 (the D38 absence pair's per-layer confirm — same absent-by-design reading at text-only serving)")
need("mxfp4 staging:", "step 2 (the init container's log-line authority — the pod log IS the staging record)")
need("DRY_RUN", "step 3 (the analog capture: the rendered args + startup-log resolution lines diffed against the plan recipe — the R3 medium-confidence close)")

# Steps 3.2-3.3: served-surface checks. The 3.4 leg became the retirement
# MARKER — the D38 ruling killed the multimodal smoke (its former
# 3.4/multimodal/data-URL needle trio retired with it) and an operator
# walking the step list must find the death entry, not hunt for a procedure;
# the data-URL payload text survives only inside the re-enable rider.
need("/v1/models", "step 3.2 (the in-cluster served-name + max_model_len check)")
need("1-token", "step 3.3 (the serve + first-token proof completion)", case=False)
need("RETIRED BY D38", "step 3.4 (the retirement marker — the multimodal smoke must read dead, with the 3.3 serve gate alive beside it)")

# The day-one gates (the round-2 Q5/Q6 rulings + the Q2 standing condition,
# D36-amended): re-measure heading, the int4 gate as BOOT-CONFIG
# QUALIFICATION (dtype + TRITON_ATTN stated together — the shipped pairing
# that binds the ship path), the tool smoke's keypress-fixture class.
need_re(r"(?i)re-measure gate", "the day-one gate heading (the SOLE envelope path, D29)")
need_re(r"(?is)int4_per_token_head.{0,400}TRITON_ATTN|TRITON_ATTN.{0,400}int4_per_token_head", "the int4 gate (the two 0.30 edits as the shipped boot config, D36)")
need_re(r"(?i)boot-config qualification", "the 3.6 gate's D36 promotion — the gate binds the ship path, no longer a day-one flip experiment")
need("AssertionError: INT4_PER_TOKEN_HEAD only supports causal attention", "step 3.6 leg 1 (the D39-era assert marker pair, D40-reworded — the runbook's row records both readings of the shipped skip-layers pair: ABSENCE is the D40 skip-layers line, PRESENCE means the pair was lost and the drafter re-inherited the global int4; the operator greps it verbatim)")
need("keypress", "the tool smoke (the keypress_auto/keypress_parallel fixture cases — the synthetic wire gate, never-executes-tools)")
need_re(r"(?i)tool[ \-]?smoke", "the tool smoke step (the round-2 Q6 marker's closing gate, D29)")

# FE chain + the vLLM class rows (the four-class contract's carrier rows;
# the hop is byte-stable, port 8000 preserved).
need("llama.spencerslab.com/v1", "step 4 (the FE chain the runbook smokes)")
need("qwen3.8-27b-vllm-urgent", "step 4 (the urgent OpenCode row whose body merge is live)")
need("qwen3.8-27b-vllm-low", "the names block (the low class row the 4-class contract adds)")

# Priority proof (step 5): the policy flag the engine must run (the D24
# carried flag, unmeasured-under-this-stack risk rides with it), the explicit
# body value, the preemption metric, and the Shape-B saturation drive.
need("--scheduling-policy priority", "step 5 (the policy that makes a non-zero priority legal)")
need("priority: 5", "step 5a (the explicit non-zero body value)")
need("vllm:num_preemptions_total", "step 5c (the preemption proof metric)")

# Benchmark + monitoring (steps 6-7) named signals.
need("vllm:kv_cache_usage_perc", "step 6 (the KV-pool exhaustion signal)")
need("up{job=\"vllm\"}", "step 7 (the Prometheus job-label fallback check)")
need("finished_reason", "step 7 (the enum values that feed the alert follow-up card)")

# Steps 8/9: the one-engine-per-card re-shape (the sleep/wake sequence is
# GONE — the --enable-sleep-mode drop's consequence; the escape hatch
# re-grounds to the 0.30 --kv-offloading-size seam, default off). The law
# word is matched case-insensitively because the section heading ships it
# uppercased in the C05 spec.
need("one-engine-per-card", "step 8/9 (the static coexistence law)", case=False)
need("kv-offloading", "step 8 (the 0.30 escape-hatch seam replacing the 0.9.3 KVCACHE=ram tier record, R3 L2.2)")

# The honest envelope (the Q11-re-bound block): the 0.9.3-stack 8.49 GiB pin
# survives as the RECORDED REFERENCE ROW (provenance, never the target —
# the gate derives the pool at the shipped shape); the anchor class carries
# the same-card-signature numbers; the 32 GiB card + pool-governed
# impossibility + intended-preemption phrasing stays (a single 262144-class
# session is a pool question, not a cap question, D31).
need("8.49", "envelope (the carried-and-unverified 0.9.3-stack KV pin — the recorded reference row)")
need("137.7", "envelope/step 6 (the 0.9.3 TP1 ANCHOR-CLASS single-stream figure, R3 L3.3)")
need("416.3", "envelope/step 6 (the 0.9.3 TP1 anchor-class c=8 aggregate)")
need_re(r"impossible|infeasible", "envelope (a full-context 262144-class pool on the 32 GiB card is stated impossible)", re.I)
need_re(r"32\s*(GiB|GB)", "envelope (the single 32 GiB card the impossibility is against)", re.I)
need_re(r"preempt", "envelope (priority-preemption on pool exhaustion is intended behavior)", re.I)

if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PY
  if [ "$rc" -ne 0 ]; then
    fail "T5: the runbook step content is incomplete (C05 AC4/AC5 — the named commands, the 0.30 marker set, the day-one gates, the one-engine-per-card law, or the honest envelope are missing; diagnostics above)"
  fi
  ok "T5: the step content is present (0.30 on-target facts + re-export enumeration, staging trees/marker/shas + the Q8 contingency rung, the 0.30 first-engine marker set incl. the D38 text-only marker + ViT ABSENCE pair + the 3.4 retirement marker + the DRY_RUN-analog capture, the day-one re-measure/int4/tool-smoke gates + the D40-reworded 3.6 assert marker pair, the priority proof, the one-engine-per-card law + kv-offloading hatch, the recorded anchor classes + the pool-governed envelope)"
fi

printf 'PASS: vllm runbook contract checks (%d ok)\n' "$checks"
