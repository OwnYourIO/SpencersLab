"""D8 pre-authored receipt gate — bug-radiance-27b-context-window (2026-11-23).

ONE artifact, per D8: the owner-run command block + the item set + the closing
gate, so a lane-count change lands in both. The owner runs the block ONCE at
the scale act (post-C02 merge, the pods back up); C04 runs gate() against the
logs the block wrote and closes PROVISIONAL **only if every item is present on
every lane** — parent-D49: a gate which can pass on absence is not a gate.
Absence is never a pass: a missing log file, a missing item line, and a
block-detected FAIL/MISMATCH marker are all named in the diagnostic.

Shape law (plan OQ 1-5, PRINT-PENDING): the block's greps are best-effort
against the DOCUMENTED print shapes (the cf-143 boot print's "kv: the pool
backs N% of the worst case … M full-length sessions" line, the /diagnostics
echo); the MARKER lines it emits are the deterministic carriers and the embedded
raw lines are the quoted receipts. The gate is shape-independent: it passes on
an OK marker with embedded evidence, and nothing else — the first owner run
calibrates the greps, the anti-drift property does not depend on them.

Logs live in tests/radiance-receipt/ — deliberately NOT under
charts/radiance/tests/evidence/ (the C03 pin covers evidence/; a receipt log
there would break it).

Fit adjudication (the 2026-11-23 gate-fix round — the pre-fix gate certified
item 3 by the PRESENCE of the pool-backs line and parsed the M figure for
fn only, which let a non-fn lane's 4-session pool at 75% of the worst case
pass: an unguarded completeness gate on an unobserved value is the D49
class, in the artifact whose job is to catch it):
  MACHINE-DECIDED (a refusal keeps PROVISIONAL open):
  - every item present on every lane (absence is never a pass, D49);
  - a block-detected FAIL/MISMATCH marker;
  - EVERY lane: the pool-backs line's M figure parses and M >= that lane's
    configured --max-num-seqs. The bar is resolved PER LANE (2026-11-feat-
    radiance-fp8v4-lane D-16/owner R2: --max-num-seqs became per-lane data,
    5 on the four existing lanes and 8 on the fp8_v4 lane), reading the chart's
    FORM fallback overridden by that lane's RADIANCE_MAX_NUM_SEQS env from the
    service values — so a FORM ruling moves the fallback and a lane env moves
    that one lane's bar; an unreadable fallback, a missing flag, or a
    non-integer lane env is a REFUSAL for that lane, never a fallback to a
    hardcoded 8 (an unverified bar is the pass-on-absence class, D49). Two
    lanes carrying different bars is the DESIGNED state, not an ambiguity;
  - fn ONLY (D9(b), its count superseded to five by D-16): the five-admitted-
    sessions smoke, all 2xx — Radiance warns rather than refuses on an under-
    funded pool, so "serves fewer than the configured seqs" is a SILENT failure
    mode and the smoke is its loud check.
  OWNER-READ (a warning — surfaced and attributable, never a refusal):
  - EVERY lane: N% < 100 (or the N% figure absent). The funding margin is
    the owner's judgment; the gate records and surfaces it, it does not
    price it. A PASS certifies the machine bar and the presence — it is
    NOT a fit certification.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

# The five ruled lanes, in ladder order — the block and the gate share this
# tuple (D8: a lane-count change lands in both). The fifth (radiance-q27-fp8v4)
# joins this ticket's wave: a TP2 fp8_v4 lane at its OWN configured seqs.
LANES = (
    "radiance",            # fn-TP2 — seqs 5 authored (bar per lane); five-admitted smoke
    "radiance-q27",        # 27b-TP1 — seqs 5 authored
    "radiance-flash-tp1",  # flash-TP1 — seqs 5 authored
    "radiance-q27-tp2",    # 27b-TP2 — seqs 5 authored
    "radiance-q27-fp8v4",  # 27b-TP2 + fp8_v4 — seqs 8 (the ruled deficit, D-20)
)

FN_LANE = "radiance"
# Expected served figure on ALL FIVE lanes post-C02 (PROVISIONAL until this
# gate closes it); the block hard-wires it, the gate checks the item's presence.
EXPECTED_SERVED = 262144
# The M bar is NOT a constant and NOT a single whole-chart value: under
# 2026-11-feat-radiance-fp8v4-lane D-16 (owner R2) --max-num-seqs became
# PER-LANE data (existing four 5, the new lane 8), so the bar is resolved per
# lane = the chart's FORM fallback overridden by that lane's RADIANCE_MAX_NUM_SEQS
# env. A bar that cannot be established — an unreadable chart fallback, or a
# lane env that is not an integer — is a REFUSAL, never a fallback to a
# hardcoded 8 (D49: an unverified bar is the pass-on-absence class).
# The fn-only smoke count: D9(b)'s eight-admitted-sessions ruling is SUPERSEDED
# for fn by owner ruling R2 (2026-11-23, this ticket's DECISIONS D-16) — fn now
# configs seqs 5, so the loud check is five admitted, recorded not silent.
SMOKE_SESSIONS = 5  # D-16 — fn only (was D9(b)'s 8)

# The nine-item receipt set (RESEARCH implication (e)) + the fn smoke. Marker
# families: OK (pass), FAIL/MISMATCH (block-detected refusal), MISSING (block
# ran, the item did not surface). The gate refuses on the latter two and on
# a bare absence of the line alike — the three states are the anti-drift law.
ITEMS = (
    (1, "DIAG_OK", "DIAG_MISMATCH", "the /diagnostics config echo shows the served --max-model-len"),
    (2, "VRAM_OK", "VRAM_MISSING", "the VRAM-split lines (weights vs KV pool per card)"),
    (3, "POOL_OK", "POOL_MISSING", "the 'kv: the pool backs N% ... M full-length sessions' line — parsed per lane: M >= that lane's configured --max-num-seqs (the FORM fallback, the lane's RADIANCE_MAX_NUM_SEQS env override) is the machine bar — all five lanes; N% is the owner's read (a warning when < 100, never a bar)"),
    (4, "PIN_OK", "PIN_FAIL PIN_MISSING", "the pinned line vs the held 24Gi/110Gi (the limit - printed-pinned >= 4 law)"),
    (5, "SLOTS_OK", "SLOTS_MISSING", "the checkpoint-slot count (log-scaled)"),
    (6, "WARN_OK", "WARN_MISSING", "the prefix-cache tier warning (the TP2 either/or)"),
    (7, "MEM_OK", "MEM_FAIL MEM_MISSING", "memory.peak + oom_kill=0"),
    (8, "PEER_HOP_OK", "PEER_HOP_FAIL", "the peer-hop smoke (a real request through the hop, the served id back)"),
    (9, "NEAR_FULL_OK", "NEAR_FULL_FAIL", "ONE near-262144 session accepted (a real request at ~262144 context, no refusal/400)"),
)

# The pre-authored command block (D8). The owner runs it ONCE at the scale
# act; it enumerates ALL FIVE lanes, captures the nine-item set per lane
# (items 1-9) plus the five-admitted-sessions smoke for fn (D-16, superseding
# D9(b)'s eight), and writes tests/radiance-receipt/<lane>.log. The marker
# lines are the gate's deterministic carriers; the embedded raw lines are the
# quoted receipts (C04 records each item quoted from the print, per lane).
RECEIPT_COMMAND_BLOCK = r"""# Pre-authored receipt command block — bug-radiance-27b-context-window D8
# (2026-11-23; authored in the C01 test wave, ONE artifact with the gate).
# The owner runs this ONCE at the scale act (post-C02 merge, pods back up).
# Requires: kubectl (context = the gpu-ai cluster), curl, awk, git.
#
# It writes tests/radiance-receipt/<lane>.log — deliberately NOT under
# charts/radiance/tests/evidence/ (the C03 pin covers evidence/; a log there
# would break it). The marker lines (ITEM<n>: MARKER ...) are the gate's
# deterministic carriers; the raw lines embedded in them are the quoted
# receipts. A MISSING marker is a REFUSAL at the gate, not a pass — parent-D49.
set -eu
cd "$(git rev-parse --show-toplevel)"
mkdir -p tests/radiance-receipt

# Per-lane spec: <name>|<held GiB>|<served id>. The expected served figure is
# 262144 on ALL FIVE lanes post-C02 (the context move stays uniform: D1/D2/D5/
# D9); the seqs is NOT uniform — the gate reads each lane's own configured
# --max-num-seqs (D-16), so the four existing lanes are barred at 5 and the
# fp8_v4 lane at 8.
for spec in \
  "radiance|110|qwen3.8-flash-next-radiance" \
  "radiance-q27|24|qwen3.8-27b-radiance" \
  "radiance-flash-tp1|110|qwen3.8-flash-next-radiance-tp1" \
  "radiance-q27-tp2|24|qwen3.8-27b-radiance-tp2" \
  "radiance-q27-fp8v4|24|qwen3.8-27b-radiance-fp8v4"
do
  name=${spec%%|*}; rest=${spec#*|}; held=${rest%%|*}; id=${rest#*|}
  log=tests/radiance-receipt/$name.log
  : > "$log"
  echo "=== lane $name (held $held GiB, served $id) @ $(date -u +%Y-%m-%dT%H:%M:%SZ) ===" >> "$log"

  tmp=$(mktemp -d)
  kubectl -n default port-forward "svc/gpu-ai-$name" 18080:8000 > "$tmp/pf.log" 2>&1 &
  pf=$!
  sleep 4

  # raw captures (best-effort greps — the print is PRINT-PENDING, plan OQ 1-5;
  # the marker is the carrier, the embedded raw line is the quoted receipt)
  curl -s http://127.0.0.1:18080/diagnostics > "$tmp/diag.txt" || echo "DIAG_FETCH_FAIL" > "$tmp/diag.txt"
  kubectl -n default logs "deploy/gpu-ai-$name" --tail=5000 > "$tmp/boot.log" 2>&1 || true

  # item 1: the /diagnostics config echo shows the served figure
  dline=$(grep -Ei 'max[._-]model[._-]len' "$tmp/diag.txt" 2>/dev/null | head -1 || true)
  dfig=$(printf '%s\n' "$dline" | grep -Eo '[0-9]+' | tail -1 || true)
  if [ -n "$dline" ] && [ "$dfig" = "262144" ]; then
    echo "ITEM1: DIAG_OK $dline" >> "$log"
  else
    echo "ITEM1: DIAG_MISMATCH observed=${dfig:-<none>} want=262144 raw=${dline:-<no max-model-len line in the /diagnostics echo>}" >> "$log"
  fi

  # item 2: the VRAM-split lines (weights vs KV pool per card)
  vline=$(grep -i 'weights' "$tmp/boot.log" 2>/dev/null | grep -Ei 'kv|pool|drafter' | head -1 || true)
  if [ -n "$vline" ]; then
    echo "ITEM2: VRAM_OK $vline" >> "$log"
  else
    echo "ITEM2: VRAM_MISSING no weights/kv split line in the last 5000 boot lines (print shape pending — owner: append the line to this log, the gate re-reads)" >> "$log"
  fi

  # item 3: the pool-backs adjudicator line (documented shape: kv: the pool
  # backs N% of the worst case ... M full-length sessions)
  pline=$(grep -i 'pool backs' "$tmp/boot.log" 2>/dev/null | head -1 || true)
  if [ -n "$pline" ]; then
    echo "ITEM3: POOL_OK $pline" >> "$log"
  else
    echo "ITEM3: POOL_MISSING no 'pool backs' line in the boot log" >> "$log"
  fi

  # item 4: the pinned line vs the held (the limit - printed-pinned >= 4 law,
  # values.yaml :1388)
  kline=$(grep -i 'pinned' "$tmp/boot.log" 2>/dev/null | grep -E 'GiB' | head -1 || true)
  kfig=$(printf '%s\n' "$kline" | grep -Eo '[0-9]+(\.[0-9]+)?' | tail -1 || true)
  if [ -n "$kline" ] && [ -n "$kfig" ]; then
    ok=$(awk -v h="$held" -v p="$kfig" 'BEGIN { print (h - p >= 4) ? "y" : "n" }')
    if [ "$ok" = "y" ]; then
      echo "ITEM4: PIN_OK pinned=${kfig}GiB held=${held}GiB diff=$(awk -v h="$held" -v p="$kfig" 'BEGIN { print h - p }')" >> "$log"
    else
      echo "ITEM4: PIN_FAIL pinned=${kfig}GiB held=${held}GiB — the limit - printed-pinned >= 4 law is violated" >> "$log"
    fi
  else
    echo "ITEM4: PIN_MISSING no pinned line in the boot log" >> "$log"
  fi

  # item 5: the checkpoint-slot count (log-scaled)
  sline=$(grep -Ei 'checkpoint|slots' "$tmp/boot.log" 2>/dev/null | grep -E '[0-9]' | head -1 || true)
  if [ -n "$sline" ]; then
    echo "ITEM5: SLOTS_OK $sline" >> "$log"
  else
    echo "ITEM5: SLOTS_MISSING no checkpoint-slot line in the boot log" >> "$log"
  fi

  # item 6: the prefix-cache tier warning (EXPECTED at 262144 — the 4Gi tier
  # vs the 8.0/16.0 GiB full session)
  wline=$(grep -Ei 'prefix[ -]?cache' "$tmp/boot.log" 2>/dev/null | grep -Ei 'smaller|tier|warning|less' | head -1 || true)
  if [ -n "$wline" ]; then
    echo "ITEM6: WARN_OK $wline" >> "$log"
  else
    echo "ITEM6: WARN_MISSING no prefix-cache tier warning in the boot log (expected at 262144)" >> "$log"
  fi

  # item 7: memory.peak + oom_kill=0
  peak=$(grep -Ei 'peak' "$tmp/boot.log" 2>/dev/null | grep -E '[0-9]+(\.[0-9]+)? ?(gib|g|mb|mi)\b' | head -1 || true)
  oom=$(grep -Eo 'oom_kill=[0-9]+' "$tmp/boot.log" 2>/dev/null | tail -1 || true)
  if [ -n "$peak" ] && [ "$oom" = "oom_kill=0" ]; then
    echo "ITEM7: MEM_OK peak=$peak oom_kill=0" >> "$log"
  elif [ -n "$peak" ] || [ -n "$oom" ]; then
    echo "ITEM7: MEM_FAIL peak=${peak:-<none>} oom=${oom:-<none>}" >> "$log"
  else
    echo "ITEM7: MEM_MISSING no memory.peak / oom_kill line in the boot log" >> "$log"
  fi

  # item 8: the peer-hop smoke (a real request through the hop, the served
  # id back)
  code=$(curl -s -o "$tmp/r8.json" -w '%{http_code}' -X POST http://127.0.0.1:18080/v1/chat/completions -H 'Content-Type: application/json' -d "{\"model\":\"$id\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":1}" || echo FAIL)
  if [ "$code" = "200" ] && grep -qF "$id" "$tmp/r8.json" 2>/dev/null; then
    echo "ITEM8: PEER_HOP_OK $id" >> "$log"
  else
    echo "ITEM8: PEER_HOP_FAIL code=$code" >> "$log"
  fi

  # item 9: ONE near-262144 session accepted (a real request at ~262144
  # context — the engine must fund it before it starts)
  code=$(curl -s -o "$tmp/r9.json" -w '%{http_code}' -X POST http://127.0.0.1:18080/v1/chat/completions -H 'Content-Type: application/json' -d "{\"model\":\"$id\",\"messages\":[{\"role\":\"user\",\"content\":\"x\"}],\"max_tokens\":262143}" || echo FAIL)
  if [ "$code" = "200" ]; then
    echo "ITEM9: NEAR_FULL_OK 262143" >> "$log"
  else
    echo "ITEM9: NEAR_FULL_FAIL code=$code" >> "$log"
  fi

  # fn ONLY: the five-admitted-sessions smoke (D-16, superseding D9(b)'s eight —
  # the silent failure mode's loud check; five NEAR-FULL sessions at once, each
  # admitted or not, matching fn's configured seqs)
  if [ "$name" = "radiance" ]; then
    pids=""
    i=1
    while [ "$i" -le 5 ]; do
      ( code=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:18080/v1/chat/completions -H 'Content-Type: application/json' -d "{\"model\":\"$id\",\"messages\":[{\"role\":\"user\",\"content\":\"s$i\"}],\"max_tokens\":262143}" || echo FAIL); echo "SMOKE: ADMITTED $i $code" >> "$log" ) &
      pids="$pids $!"
      i=$((i + 1))
    done
    for p in $pids; do
      wait "$p" || true
    done
  fi

  kill "$pf" 2>/dev/null || true
  rm -rf "$tmp"
done

echo "receipt block done — logs in tests/radiance-receipt/"
echo "run the closing gate: python3 charts/radiance/tests/receipt_gate.py --gate"
"""

# The raw pool-backs line's M figure — documented shape: "kv: the pool backs
# N% of the worst case ... M full-length sessions" (the cf-143 print's form;
# print-pending tolerance: hyphen/space variants, case-insensitive).
_M_RE = re.compile(r"(\d+)\s*full[- ]length\s+sessions", re.IGNORECASE)
_N_RE = re.compile(r"pool\s+backs\s+(\d+(?:\.\d+)?)\s*%", re.IGNORECASE)
_ADMITTED_RE = re.compile(r"^SMOKE: ADMITTED (\d+) (\S+)\s*$")

# The M bar's source of truth is TWO-part now (2026-11-feat-radiance-fp8v4-lane
# D-16 / owner R2): the chart's compose FORM carries the FALLBACK inside the
# ${RADIANCE_MAX_NUM_SEQS:-N} expansion (its pre-C02 shape was the bare literal
# --max-num-seqs N — both forms read the same way, so the re-cut is byte-
# identical to today and invents no bar), and each lane's RADIANCE_MAX_NUM_SEQS
# env in its service block OVERRIDES that fallback. The gate reads both rather
# than hardcoding 8, so a FORM ruling moves every lane's baseline and a lane
# env moves just that lane; an unreadable fallback or a non-integer lane env is
# a per-lane REFUSAL (an unverified bar is the D49 pass-on-absence class). Two
# lanes carrying different bars is the DESIGNED state, not an ambiguity.
_SEQS_EXPANSION_RE = re.compile(r'--max-num-seqs\s+"?\$\{\s*RADIANCE_MAX_NUM_SEQS:-\s*(\d+)\s*\}"?')
_SEQS_LITERAL_RE = re.compile(r'--max-num-seqs\s+(\d+)')
_LANE_SEQS_ENV = "RADIANCE_MAX_NUM_SEQS"


def chart_values_path() -> Path:
    """The gate's own chart (charts/radiance/values.yaml) — the compose FORM
    the block's pods run is the same bytes this file reads."""
    return Path(__file__).resolve().parent.parent / "values.yaml"


def services_values_path() -> Path:
    """The gpu-ai service values — where each lane authors its per-lane seqs
    env override. The gate reads it to resolve a lane's bar; a lane with no
    block yet (C03 has not landed it) simply keeps the chart fallback, so a
    missing block never invents or refuses a bar."""
    return Path(__file__).resolve().parents[3] / "services" / "gpu-ai" / "prod" / "values.yaml"


def chart_seqs_fallback(chart_text: str) -> tuple[int | None, str | None]:
    """The whole-chart fallback digit: the ${RADIANCE_MAX_NUM_SEQS:-N} expansion
    or its pre-C02 literal. Exactly one distinct value, or REFUSAL (D49) — never
    a fallback to a hardcoded 8. The expansion carries the value the env-less
    lanes compose, so this is the default bar every lane falls back to."""
    digits = _SEQS_EXPANSION_RE.findall(chart_text) + _SEQS_LITERAL_RE.findall(chart_text)
    if not digits:
        return None, ("no --max-num-seqs fallback in the compose FORM (neither the "
                      "${RADIANCE_MAX_NUM_SEQS:-N} expansion nor a literal) — the M bar cannot be "
                      "evaluated, so it cannot pass (absence is not a pass, D49); this gate never "
                      "falls back to a hardcoded 8")
    distinct = sorted(set(digits))
    if len(distinct) > 1:
        return None, (f"ambiguous --max-num-seqs fallback in the compose FORM: {distinct} — the "
                      f"baseline bar cannot be decided, so it cannot pass (an unverified bar is "
                      f"not a bar, D49)")
    return int(distinct[0]), None


def read_configured_max_num_seqs(values_path: Path) -> tuple[int | None, str | None]:
    """The chart-fallback half of the bar, from a chart path (the FORM the
    block's pods run). Kept as the chart-only read; the per-lane override is
    lane_max_num_seqs below. A missing file is a named read failure."""
    try:
        text = Path(values_path).read_text()
    except OSError as e:
        return None, (f"the configured --max-num-seqs cannot be read from {values_path} ({e.__class__.__name__}) — "
                      f"the M bar cannot be evaluated, so it cannot pass (absence is not a pass, D49)")
    return chart_seqs_fallback(text)


def _lane_env_entries(node):
    """Every {name, value} env entry anywhere under a parsed block. The lane's
    seqs env rides app-template.controllers.<c>.containers.<c>.env, but this
    walks generically so a container rename never silently drops the override."""
    if isinstance(node, dict):
        for key, val in node.items():
            if key == "env" and isinstance(val, list):
                for entry in val:
                    if isinstance(entry, dict):
                        yield entry
            else:
                yield from _lane_env_entries(val)
    elif isinstance(node, list):
        for item in node:
            yield from _lane_env_entries(item)


def lane_max_num_seqs(lane: str, chart_text: str, services_doc) -> tuple[int | None, str | None]:
    """The per-lane M bar: the chart fallback, overridden by that lane's
    RADIANCE_MAX_NUM_SEQS env when its service block authors one. Absent lane
    env (or no block at all) ⇒ the fallback governs — a bar that never depends
    on the block existing. A non-integer lane env is a named refusal."""
    fallback, err = chart_seqs_fallback(chart_text)
    if err is not None:
        return None, f"{lane}: {err}"
    block = services_doc.get(lane) if isinstance(services_doc, dict) else None
    raw = next((e.get("value") for e in _lane_env_entries(block)
                if e.get("name") == _LANE_SEQS_ENV), None) if isinstance(block, dict) else None
    if raw is None:
        return fallback, None
    text = str(raw).strip()
    if not re.fullmatch(r"\d+", text):
        return None, (f"{lane}: its RADIANCE_MAX_NUM_SEQS env value {raw!r} is not a non-negative "
                      f"integer — the lane's M bar cannot be evaluated, so it cannot pass "
                      f"(absence is not a pass, D49)")
    return int(text), None


def _item_line(text: str, num: int) -> str | None:
    for ln in text.splitlines():
        if ln.startswith(f"ITEM{num}: "):
            return ln
    return None


def gate(logs_dir: Path, values_path: Path | None = None,
         services_path: Path | None = None) -> tuple[list[str], list[str]]:
    """The D8 closing gate: the refusals list is EMPTY (pass) only if every
    item is present on every lane, each lane's OWN M bar holds (the chart
    fallback overridden by that lane's RADIANCE_MAX_NUM_SEQS env — D-16), and
    the fn smoke is 5x2xx. Refuses — and NAMES the reason — on: a missing log
    file, a missing item line, a block-detected FAIL/MISMATCH marker, an
    M figure that is absent/unparseable or below that lane's configured
    --max-num-seqs on ANY lane (D49: absence is not a pass), an unreadable or
    ambiguous chart fallback, a non-integer lane env, and an fn smoke with
    fewer than five 2xx admissions (D-16, superseding D9(b)'s eight). The
    warnings list is the owner's read: N% < 100 (or the N% figure absent) per
    lane — surfaced and attributable, never a refusal."""
    diags: list[str] = []
    warnings: list[str] = []
    chart_text, chart_read_err = _read_chart_text(values_path if values_path is not None else chart_values_path())
    services_doc = _read_services_doc(services_path if services_path is not None else services_values_path())
    for lane in LANES:
        path = Path(logs_dir) / f"{lane}.log"
        if not path.is_file():
            diags.append(f"{lane}: no log file at {path} — the receipt block did not run this lane (absence is not a pass, D49)")
            continue
        text = path.read_text()
        for num, ok_marker, fail_markers, desc in ITEMS:
            line = _item_line(text, num)
            if line is None:
                diags.append(f"{lane}: item {num} ({desc}) — no ITEM{num} line in the log (absence is not a pass, D49)")
                continue
            if line.split(" ", 1)[1].split(" ", 1)[0] == ok_marker:
                continue
            fail_state = " ".join(m for m in line.split(" ", 1)[1].split()[:2])
            diags.append(f"{lane}: item {num} ({desc}) — {fail_state}: {line[len(f'ITEM{num}: '):]}")
        # The M bar resolves PER LANE now (D-16): a chart-level read failure
        # refuses every lane; otherwise the chart fallback with this lane's env
        # override. Two lanes with different bars is the designed state, never
        # an ambiguity — only an undecided FALLBACK (unreadable chart, absent
        # flag, two distinct fallbacks) or a malformed lane env refuses.
        if chart_read_err is not None:
            diags.append(f"{lane}: {chart_read_err}")
        else:
            bar, bar_err = lane_max_num_seqs(lane, chart_text, services_doc)
            if bar is None:
                diags.append(bar_err)
            else:
                d, w = _pool_diags(lane, text, bar)
                diags.extend(d)
                warnings.extend(w)
        if lane == FN_LANE:
            diags.extend(_fn_smoke_diags(text))
    return diags, warnings


def _read_chart_text(values_path: Path) -> tuple[str | None, str | None]:
    """(chart text, None) on success; (None, reason) when the compose FORM
    cannot be read — the absence-class refusal that applies to every lane."""
    try:
        return Path(values_path).read_text(), None
    except OSError as e:
        return None, (f"the configured --max-num-seqs cannot be read from {values_path} "
                      f"({e.__class__.__name__}) — the M bar cannot be evaluated, so it cannot "
                      f"pass (absence is not a pass, D49)")


def _read_services_doc(services_path: Path):
    """The parsed gpu-ai service values, or None when it is absent/unreadable —
    None just means no lane authors an override, so every bar falls to the chart
    fallback (a missing block is not a refusal; the bar comes from the FORM)."""
    try:
        return yaml.safe_load(Path(services_path).read_text())
    except (OSError, yaml.YAMLError):
        return None


def _pool_diags(lane: str, text: str, bar: int) -> tuple[list[str], list[str]]:
    """The per-lane fit adjudication — all five lanes (pre-fix the M check
    was fn-only, which let a non-fn lane's POOL_OK presence certify an
    under-funded pool). The machine decision: M parses and M >= the lane's OWN
    configured seqs (the bar argument). The owner's read: N% < 100 (or absent)
    — a warning, never a refusal."""
    diags: list[str] = []
    warnings: list[str] = []
    pool = _item_line(text, 3)
    if pool is not None and pool.split(" ", 1)[1].startswith("POOL_OK"):
        raw = pool[len("ITEM3: POOL_OK "):]
        m = _M_RE.search(raw)
        if m is None:
            if lane == FN_LANE:
                diags.append(f"{lane}: D9(a) — the pool-backs line carries no 'M full-length sessions' figure to parse: {raw!r} (the M >= {bar} bar cannot be evaluated, so it cannot pass)")
            else:
                diags.append(f"{lane}: item 3 — the POOL_OK line carries no 'M full-length sessions' figure to parse: {raw!r} — the M bar cannot be evaluated, so it cannot pass (absence is not a pass, D49)")
        elif int(m.group(1)) < bar:
            if lane == FN_LANE:
                diags.append(f"{lane}: D9(a) — the pool backs M={m.group(1)} full-length sessions, want M >= {bar} — a C03 trigger, not a close (D9(a))")
            else:
                diags.append(f"{lane}: the pool backs M={m.group(1)} full-length sessions, want M >= {bar} (this lane's configured --max-num-seqs: FORM fallback, lane env override) — the lane is under-funded at the ruled window; Radiance SILENTLY serves fewer sessions (warns, does not refuse) — this is what the gate exists to catch")
        n = _N_RE.search(raw)
        if n is None:
            warnings.append(f"{lane}: the pool-backs line carries no 'N%' figure — the owner's fit read is under-informed (the machine M bar is evaluated regardless)")
        elif float(n.group(1)) < 100:
            warnings.append(f"{lane}: the pool backs N={n.group(1)}% of the worst case — under 100%: surfaced for the owner's read, not a close bar (the machine bar is M >= {bar})")
    return diags, warnings


def _fn_smoke_diags(text: str) -> list[str]:
    diags: list[str] = []
    admitted = {}
    for ln in text.splitlines():
        am = _ADMITTED_RE.match(ln)
        if am:
            admitted[am.group(1)] = am.group(2)
    if len(admitted) != SMOKE_SESSIONS:
        got = sorted(admitted)
        want = [str(i) for i in range(1, SMOKE_SESSIONS + 1)]
        missing = [i for i in want if i not in admitted]
        diags.append(f"{FN_LANE}: D9(b)/D-16 — the five-admitted-sessions smoke has {len(admitted)}/{SMOKE_SESSIONS} entries (missing: {missing or 'none — the count itself is wrong'}) — the silent failure mode's loud check did not fire")
    else:
        not_ok = {i: c for i, c in admitted.items() if not c.startswith("2")}
        if not_ok:
            diags.append(f"{FN_LANE}: D9(b)/D-16 — sessions not admitted (non-2xx): {not_ok} — the pool is under-funded and Radiance is SILENT (warns, does not refuse); this is the loud check the ruling attached")
    return diags


def _default_logs_dir() -> Path:
    return Path(__file__).resolve().parents[3] / "tests" / "radiance-receipt"


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        print("usage: receipt_gate.py --commands | --gate [--logs-dir DIR]")
        return 2
    if argv[0] == "--commands":
        print(RECEIPT_COMMAND_BLOCK)
        return 0
    if argv[0] == "--gate":
        logs_dir = _default_logs_dir()
        i = 1
        while i < len(argv):
            if argv[i] == "--logs-dir":
                logs_dir = Path(argv[i + 1])
                i += 2
            else:
                print(f"unknown argument: {argv[i]}", file=sys.stderr)
                return 2
        diags, warnings = gate(logs_dir)
        if diags:
            print(f"REFUSED — PROVISIONAL stays open ({len(diags)} refusal(s); a gate that can pass on absence is not a gate, D49):")
            for d in diags:
                print(f"  - {d}")
        if warnings:
            print(f"owner-read warnings ({len(warnings)}) — N% < 100 or the N% figure absent: surfaced and attributable, never a close bar (the machine bar is the per-lane M figure):")
            for w in warnings:
                print(f"  ! {w}")
        if diags:
            return 1
        print("PASS — the machine bar held on all five lanes (every item present, per-lane M >= that lane's configured --max-num-seqs [FORM fallback / lane env override], fn five-session smoke all 2xx); any N% warning above is the owner's read, not a fit certification; PROVISIONAL may close by the C04 dated annotation")
        return 0
    print(f"unknown argument: {argv[0]}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
