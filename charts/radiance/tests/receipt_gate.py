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
  - EVERY lane: the pool-backs line's M figure parses and M >= the chart's
    FORM-fixed --max-num-seqs — the bar is READ from
    charts/radiance/values.yaml (D6: 8 today, parent-D46 FORM_FIXED), so a
    future FORM ruling moves the bar with it; a missing or ambiguous flag
    is a refusal, never a fallback to a hardcoded 8 (an unverified bar is
    the pass-on-absence class);
  - fn ONLY (D9(b) — the silent-mode risk was ruled on the live default
    route, risk accepted): the eight-admitted-sessions smoke, all 2xx —
    Radiance warns rather than refuses on an under-funded pool, so "serves
    fewer than 8" is a SILENT failure mode and the smoke is its loud check.
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

# The four ruled lanes, in ladder order — the block and the gate share this
# tuple (D8: a lane-count change lands in both).
LANES = (
    "radiance",           # fn-TP2 — D9 (informed; M >= 8 bar + eight-session smoke)
    "radiance-q27",       # 27b-TP1 — D1/D2
    "radiance-flash-tp1", # flash-TP1 — D5
    "radiance-q27-tp2",   # 27b-TP2 — D1 (fit MEASURED)
)

FN_LANE = "radiance"
# Expected served figure on ALL FOUR lanes post-C02 (PROVISIONAL until this
# gate closes it); the block hard-wires it, the gate checks the item's presence.
EXPECTED_SERVED = 262144
# The M bar is NOT a constant: it is read per run from the chart's compose
# FORM (D6: --max-num-seqs is FORM-fixed — 8 today — so a future FORM ruling
# moves the bar; hardcoding 8 would silently invalidate it). The fn-only
# smoke count stays a constant: the ruling named eight sessions (D9(b)).
SMOKE_SESSIONS = 8  # D9(b) — fn only

# The nine-item receipt set (RESEARCH implication (e)) + the fn smoke. Marker
# families: OK (pass), FAIL/MISMATCH (block-detected refusal), MISSING (block
# ran, the item did not surface). The gate refuses on the latter two and on
# a bare absence of the line alike — the three states are the anti-drift law.
ITEMS = (
    (1, "DIAG_OK", "DIAG_MISMATCH", "the /diagnostics config echo shows the served --max-model-len"),
    (2, "VRAM_OK", "VRAM_MISSING", "the VRAM-split lines (weights vs KV pool per card)"),
    (3, "POOL_OK", "POOL_MISSING", "the 'kv: the pool backs N% ... M full-length sessions' line — parsed per lane: M >= the FORM-fixed --max-num-seqs is the machine bar (all four lanes); N% is the owner's read (a warning when < 100, never a bar)"),
    (4, "PIN_OK", "PIN_FAIL PIN_MISSING", "the pinned line vs the held 24Gi/110Gi (the limit - printed-pinned >= 4 law)"),
    (5, "SLOTS_OK", "SLOTS_MISSING", "the checkpoint-slot count (log-scaled)"),
    (6, "WARN_OK", "WARN_MISSING", "the prefix-cache tier warning (the TP2 either/or)"),
    (7, "MEM_OK", "MEM_FAIL MEM_MISSING", "memory.peak + oom_kill=0"),
    (8, "PEER_HOP_OK", "PEER_HOP_FAIL", "the peer-hop smoke (a real request through the hop, the served id back)"),
    (9, "NEAR_FULL_OK", "NEAR_FULL_FAIL", "ONE near-262144 session accepted (a real request at ~262144 context, no refusal/400)"),
)

# The pre-authored command block (D8). The owner runs it ONCE at the scale
# act; it enumerates ALL FOUR lanes, captures the nine-item set per lane
# (items 1-9) plus the eight-admitted-sessions smoke for fn (D9(b)), and
# writes tests/radiance-receipt/<lane>.log. The marker lines are the gate's
# deterministic carriers; the embedded raw lines are the quoted receipts
# (C04 records each item quoted from the print, per lane).
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
# 262144 on ALL FOUR lanes post-C02 (the move is uniform: D1/D2/D5/D9).
for spec in \
  "radiance|110|qwen3.8-flash-next-radiance" \
  "radiance-q27|24|qwen3.8-27b-radiance" \
  "radiance-flash-tp1|110|qwen3.8-flash-next-radiance-tp1" \
  "radiance-q27-tp2|24|qwen3.8-27b-radiance-tp2"
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

  # fn ONLY: the eight-admitted-sessions smoke (D9(b) — the silent failure
  # mode's loud check; eight NEAR-FULL sessions at once, each admitted or not)
  if [ "$name" = "radiance" ]; then
    pids=""
    i=1
    while [ "$i" -le 8 ]; do
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

# The M bar's source of truth: the chart's compose FORM (one shared line,
# FORM-owned — D6). The gate reads it rather than hardcoding 8, so a future
# FORM ruling moves the bar; when it cannot be read, the gate refuses
# (an unverified bar is the D49 pass-on-absence class, not a fallback).
_SEQS_RE = re.compile(r"--max-num-seqs\s+(\d+)")


def chart_values_path() -> Path:
    """The gate's own chart (charts/radiance/values.yaml) — the compose FORM
    the block's pods run is the same bytes this file reads."""
    return Path(__file__).resolve().parent.parent / "values.yaml"


def read_configured_max_num_seqs(values_path: Path) -> tuple[int | None, str | None]:
    """The per-lane M bar, READ from the compose FORM (D6: FORM-fixed —
    8 today). Returns (bar, None) on success; (None, reason) when the bar
    cannot be established — a missing file, a missing flag, or two distinct
    values are all REFUSALS, never a fallback to a hardcoded 8 (D49)."""
    try:
        text = Path(values_path).read_text()
    except OSError as e:
        return None, (f"the configured --max-num-seqs cannot be read from {values_path} ({e.__class__.__name__}) — "
                     f"the M bar cannot be evaluated, so it cannot pass (absence is not a pass, D49)")
    found = _SEQS_RE.findall(text)
    if not found:
        return None, (f"no --max-num-seqs flag in {values_path} — the M bar cannot be evaluated, "
                     f"so it cannot pass (absence is not a pass, D49); this gate never falls back to a hardcoded 8")
    distinct = sorted(set(found))
    if len(distinct) > 1:
        return None, (f"ambiguous --max-num-seqs in {values_path}: {distinct} — the M bar cannot be "
                     f"decided, so it cannot pass (an unverified bar is not a bar, D49)")
    return int(distinct[0]), None


def _item_line(text: str, num: int) -> str | None:
    for ln in text.splitlines():
        if ln.startswith(f"ITEM{num}: "):
            return ln
    return None


def gate(logs_dir: Path, values_path: Path | None = None) -> tuple[list[str], list[str]]:
    """The D8 closing gate: the refusals list is EMPTY (pass) only if every
    item is present on every lane, the per-lane M bar holds, and the fn
    smoke is 8x2xx. Refuses — and NAMES the reason — on: a missing log
    file, a missing item line, a block-detected FAIL/MISMATCH marker, an
    M figure that is absent/unparseable or below the configured
    --max-num-seqs on ANY lane (D49: absence is not a pass), an unreadable
    or ambiguous bar, and an fn smoke with fewer than eight 2xx admissions
    (D9(b)). The warnings list is the owner's read: N% < 100 (or the N%
    figure absent) per lane — surfaced and attributable, never a refusal."""
    diags: list[str] = []
    warnings: list[str] = []
    bar, bar_err = read_configured_max_num_seqs(values_path if values_path is not None else chart_values_path())
    if bar is None:
        diags.append(bar_err)
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
        if bar is not None:
            d, w = _pool_diags(lane, text, bar)
            diags.extend(d)
            warnings.extend(w)
        if lane == FN_LANE:
            diags.extend(_fn_smoke_diags(text))
    return diags, warnings


def _pool_diags(lane: str, text: str, bar: int) -> tuple[list[str], list[str]]:
    """The per-lane fit adjudication — all four lanes (pre-fix the M check
    was fn-only, which let a non-fn lane's POOL_OK presence certify an
    under-funded pool). The machine decision: M parses and M >= bar. The
    owner's read: N% < 100 (or absent) — a warning, never a refusal."""
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
                diags.append(f"{lane}: the pool backs M={m.group(1)} full-length sessions, want M >= {bar} (the chart's FORM-fixed --max-num-seqs) — the lane is under-funded at the ruled window; Radiance SILENTLY serves fewer sessions (warns, does not refuse) — this is what the gate exists to catch")
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
        diags.append(f"{FN_LANE}: D9(b) — the eight-admitted-sessions smoke has {len(admitted)}/{SMOKE_SESSIONS} entries (missing: {missing or 'none — the count itself is wrong'}) — the silent failure mode's loud check did not fire")
    else:
        not_ok = {i: c for i, c in admitted.items() if not c.startswith("2")}
        if not_ok:
            diags.append(f"{FN_LANE}: D9(b) — sessions not admitted (non-2xx): {not_ok} — the pool is under-funded and Radiance is SILENT (warns, does not refuse); this is the loud check the ruling attached")
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
        print("PASS — the machine bar held on all four lanes (every item present, per-lane M >= the FORM-fixed --max-num-seqs, fn eight-session smoke all 2xx); any N% warning above is the owner's read, not a fit certification; PROVISIONAL may close by the C04 dated annotation")
        return 0
    print(f"unknown argument: {argv[0]}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
