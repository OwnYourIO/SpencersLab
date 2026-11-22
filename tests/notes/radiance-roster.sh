#!/usr/bin/env bash
# 2026-11-feat-radiance-multi-instance C06 — the roster note contract
# (chunks/C06.md Tests bullet 1): .agents/notes/radiance-multi-instance-roster.md
# is the ticket's single prose authority for the roster — the five claimants on
# the pool (four radiance releases + the PARKED strata lane), the steady-state
# claim table C04 points at, the routing wave's shipped defaults, the MoE
# bring-up order, and the convention reconciliation ask 4 needed.
#
# Its table rows are NEEDLES bound to the shipped values, not prose memory: T2
# re-derives every claim count and replicas value from
# services/gpu-ai/prod/values.yaml and requires the note to agree. A note that
# drifts from the tree is the failure class this suite exists for, so T4 plants a
# falsified row and proves the checker catches it.
#
# Designed-RED at test-write: the note does not exist yet (T1 names C06).
#
# Run from the repo root:
#   bash tests/notes/radiance-roster.sh          # T1..T4
#   bash tests/notes/radiance-roster.sh T2       # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

NOTE="${RAD_ROSTER_NOTE:-.agents/notes/radiance-multi-instance-roster.md}"
VALS="${RAD_ROSTER_VALS:-services/gpu-ai/prod/values.yaml}"

# ---------------------------------------------------------------------------
# GPU RESOURCE-NAME CONSTANTS — bash twin of the marked block in
# charts/amd-gpu/tests/amd_gpu_testlib.py (the one edit site). The RETIRED tier
# is SPLIT so this file stays a clean subject of the C01 zero-stale sweep.
R9700_CLAIM="amd.com/gpu-r9700"    # D21 (2026-11-22): ids-table product `r9700`
RETIRED_R9700_CLAIM="amd.com/gpu-r9700"-"1"
BARE_CLAIM="amd.com/gpu"
RUNNER_LITERAL="gpu-ai/qwen3.8-flash-next-radiance"
STRATA_CLAIMANT="strata"

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

# Subset runs (T2/T3/T4 alone, with the note still unwritten) must land on the
# C06 designed-red message rather than a cp/traceback/grep crash; T1 owns the
# canonical absence text in full-suite order. The red itself is unchanged —
# absent note still exits 1.
require_note() { [ -f "$NOTE" ] || fail "$1: $NOTE missing — C06 (the roster note) is not implemented"; }

# T2's checker, shared by the live leg and the teeth probe: every claimant row in
# the note must carry the claim count and replicas the tree actually ships.
check_rows() {  # $1 = note path; exits non-zero with diagnostics
  NOTE_PATH="$1" VALS_PATH="$VALS" POOL="$R9700_CLAIM" python3 - <<'PY'
import os, re, sys, yaml

note = open(os.environ["NOTE_PATH"]).read()
doc = yaml.safe_load(open(os.environ["VALS_PATH"]))
pool = os.environ["POOL"]

def lane(key):
    cont = ((doc.get(key) or {}).get("app-template") or {}).get("controllers", {}) \
             .get("radiance", {}).get("containers", {}).get("radiance", {})
    ctrl = ((doc.get(key) or {}).get("app-template") or {}).get("controllers", {}).get("radiance", {})
    res = cont.get("resources") or {}
    served = None
    args = [str(a) for a in (cont.get("args") or [])]
    if "--served-model-name" in args:
        served = args[args.index("--served-model-name") + 1]
    return {
        "claim": str(res.get("requests", {}).get(pool) or res.get("limits", {}).get(pool) or ""),
        "replicas": str(ctrl.get("replicas", cont.get("replicas", ""))),
        "served": served or "",
    }

rows = {}
for key in ("radiance", "radiance-q27", "radiance-flash-tp1", "radiance-q27-tp2"):
    rows[key] = lane(key)
strata = ((doc.get("llama-swap") or {}).get("app-template") or {}).get("controllers", {}) \
           .get("strata", {})
scont = (strata.get("containers") or {}).get("strata") or next(iter((strata.get("containers") or {}).values()), {})
sres = scont.get("resources") or {}
rows["strata"] = {
    "claim": str(sres.get("requests", {}).get(pool) or sres.get("limits", {}).get(pool) or ""),
    "replicas": str(strata.get("replicas", "")),
    "served": "",
}

errs = []
for key, want in rows.items():
    # One table row per claimant: the row is the line that names the key.
    row = next((ln for ln in note.splitlines()
                if ln.strip().startswith("|") and re.search(rf"(?<![a-z0-9-]){re.escape(key)}(?![a-z0-9-])", ln)), None)
    if row is None:
        errs.append(f"no roster table row names {key!r}")
        continue
    cells = [c.strip().strip("`") for c in row.strip().strip("|").split("|")]
    if want["claim"] and not re.search(rf"(?<![\d\"]){re.escape(want['claim'])}(?![\d\"])", " ".join(cells[1:])):
        errs.append(f"{key}: row {cells} does not carry the shipped claim count {want['claim']!r}")
    if want["replicas"] and not re.search(rf"(?<![\d\"]){re.escape(want['replicas'])}(?![\d\"])", " ".join(cells[1:])):
        errs.append(f"{key}: row {cells} does not carry the shipped replicas {want['replicas']!r}")
    if want["served"] and want["served"] not in row:
        errs.append(f"{key}: row does not name its served id {want['served']!r}")

if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PY
}

# --- T1: the note exists, is dated, and is AC4-clean ----------------------------
if want t1; then
  [ -f "$NOTE" ] || fail "T1: $NOTE missing — C06 (the roster note) is not implemented"
  if ! grep -qE '2026-11-2[0-9]|2026-1[12]-[0-9]{2}' "$NOTE"; then
    fail "T1: the roster note carries no date — annotate-never-rewrite only works if the annotation says when"
  fi
  if grep -qF -- "$RETIRED_R9700_CLAIM" "$NOTE"; then
    fail "T1: the roster note spells the RETIRED pool name — the C01 zero-stale sweep scans .agents/notes/ and the retired name is a capacity-0 trap for a reader (R-Q5)"
  fi
  if grep -qE 'amd\.com/r9700' "$NOTE"; then
    fail "T1: the roster note names an impossible claim string (amd.com/ + the bare product) — the plugin's code constants make it unreachable, so it can only mislead"
  fi
  for who in radiance radiance-q27 radiance-flash-tp1 radiance-q27-tp2 strata; do
    grep -qE "(^|[^a-z0-9-])${who}([^a-z0-9-]|$)" "$NOTE" \
      || fail "T1: the roster note never names the claimant '$who' — five things hold claims on this pool and the note is their single table"
  done
  if ! grep -qiE 'custom-values' "$NOTE" || ! grep -qiE 'secrets.only|secrets only' "$NOTE"; then
    fail "T1: the reconciliation sentence is missing — the note must say custom-values stays secrets-only and that the per-release service blocks are this chart's per-instance carrier (ask 4's convention law, cross-cited to DECISIONS)"
  fi
  ok "T1: roster note exists, dated, retired-pool-clean, names all five claimants, and carries the carrier-law sentence"
fi

# --- T2: the table matches the shipped tree -------------------------------------
if want t2; then
  require_note T2
  rc=0
  check_rows "$NOTE" || rc=$?
  case "$rc" in
    0) ok "T2: every roster row matches services/gpu-ai/prod/values.yaml (claim counts, replicas, served ids re-derived from the tree, not from prose memory)" ;;
    *) fail "T2: the roster table drifted from the shipped values (diagnostics above) — C06 AC2 counts against the tree" ;;
  esac
fi

# --- T3: the routing and discipline prose ---------------------------------------
if want t3; then
  require_note T3
  if ! grep -qF -- "$RUNNER_LITERAL" "$NOTE"; then
    fail "T3: the note never names the runner literal $RUNNER_LITERAL — the routing wave MOVED it (D16) and the note is where a reader learns which literal the loop actually runs"
  fi
  if ! grep -qE 'cf-106 OQ-14|cf-106 OQ14' "$NOTE" || ! grep -qE '2026-11-09' "$NOTE" || ! grep -qE '2026-11-22' "$NOTE"; then
    fail "T3: the runner literal appears without its ruling chain (cf-106 OQ-14 -> 2026-11-09 strata-q4 -> 2026-11-22 radiance) — an uncited runner pin invites the next editor to pick a model"
  fi
  if ! grep -qF -- 'qwen3.8-27b-radiance' "$NOTE" || ! grep -qEi 'Dense.*Local|Dense\+Local' "$NOTE"; then
    fail "T3: the Dense+Local route move (D20 -> qwen3.8-27b-radiance) is not recorded"
  fi
  if ! grep -qE '502' "$NOTE" || ! grep -qEi 'never a default|not a default|never routes' "$NOTE"; then
    fail "T3: the never-default / 502-while-idle law is missing — three cataloged lanes rest at 0 and a reader must know the hop answers the peer-proxy error rather than nothing"
  fi
  if ! grep -qEi 'fn[^.]{0,30}(→|->|to) ?0[^.]{0,80}strata[^.]{0,30}(→|->|to) ?1' "$NOTE"; then
    fail "T3: the MoE bring-up order (fn to 0, pod gone, then strata to 1) is missing — it is the only sequence that boots strata without a Pending pair"
  fi
  if ! grep -qEi 'steady.state|combination table' "$NOTE"; then
    fail "T3: the note does not hold the steady-state claim table — C04's strata block points HERE, and two copies of the table drift"
  fi
  ok "T3: routing chain, D20 route move, never-default/502 law, MoE bring-up order and the steady-state table are all present"
fi

# --- T4: teeth — the row checker must reject a falsified table ------------------
if want t4; then
  require_note T4
  probe=$(mktemp)
  cp "$NOTE" "$probe"
  # Falsify the flash-TP1 row: flip its claim count to something the tree does not ship.
  python3 - "$probe" <<'PY'
import re, sys
path = sys.argv[1]
lines = open(path).read().splitlines()
for i, ln in enumerate(lines):
    if ln.strip().startswith("|") and re.search(r"(?<![a-z0-9-])radiance-flash-tp1(?![a-z0-9-])", ln):
        lines[i] = re.sub(r'(?<![\d"])1(?![\d"])', "9", ln, count=1)
        break
else:
    raise SystemExit("probe: no radiance-flash-tp1 row to falsify")
open(path, "w").write("\n".join(lines) + "\n")
PY
  rc=0
  check_rows "$probe" || rc=$?
  rm -f "$probe"
  [ "$rc" -ne 0 ] || fail "T4: a roster row falsified to a claim count the tree does not ship passed the checker — T2 is an always-pass and cannot bless the table"
  ok "T4: the row checker reddens on a planted claim-count mismatch (T2 has teeth)"
fi

printf 'PASS: radiance roster-note contract checks (%s ok)\n' "$checks"
