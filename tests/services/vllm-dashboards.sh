#!/usr/bin/env bash
# vLLM Grafana dashboard pins (2026/2026-11-cf-105-feat-implement-vllm, C05):
# the two official vLLM dashboards land in the central Grafana via the repo's
# proven grafana.dashboards url: convention, pinned to the vllm repo TAG
# v0.33.0 — the same tag as the cf-105 GGUF-overlay base image — with a
# tag-coupling comment on each entry (auto-update cannot track raw-URL pins,
# so the two pins bump together by hand).
# Contract source: chunks/C05.md "## Tests" (t1-t4).
#
# cf-131 C01 re-pin (the D-T2 disposition): t4's LEDGER follows the ledger
# home to containers/vllm-radiance-mxfp4/README.md. RECORDED FOLLOW-UP, not
# a re-pin of anything else here: the dashboards values' v0.33.0 base-image
# pin is STALE BY DESIGN — the engine the dashboards observe is now the 0.30
# Radiance stack, and the dashboards RE-IMPORT is owner/central-stack
# territory (C05 step 7.3 records the need; it is not a repo edit in this
# ticket). The same follow-up FLAGS services/monitoring/prod/values.yaml
# ~L661 — the entry comment naming the RETIRED GGUF overlay's base image
# (named by position, not by string: this file must stay clear of the
# retirement grep's scan set, C01 AC1 extended) — flagged for the owner's
# follow-up, not re-pinned. t4 keeps passing on this ground only because
# the new ledger records the v0.33.0 base as its PREDECESSOR row
# (vllm/vllm-openai-rocm:v0.33.0-rocm100) — a version-prefix match, until a
# re-import retires this coupling entirely.
#
# t3 is network-gated (SKIP with warning on no egress); a real HTTP error
# (e.g. 404 on the tag URL) is a FAIL — a tag-layout 404 at review time is
# BLOCKED-with-evidence, never a silent repin to main (C05 notes).
#
# t4 was designed-red until C01 lands: it couples the dashboard tag to a
# tag row in the C01 ledger (since cf-131: the predecessor row named
# above). The ledger match is a version-prefix, not the full image:tag
# composite — the C01 ledger is a tag→digest table and its own pairing test
# only guarantees the bare tag string in the README, which a table layout
# may keep off the image name's line.
#
# Run from the repo root:
#   bash tests/services/vllm-dashboards.sh          # t1..t4
#   bash tests/services/vllm-dashboards.sh t1 t2    # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

VALS="services/monitoring/prod/values.yaml"
LEDGER="containers/vllm-radiance-mxfp4/README.md"
# The vllm repo tag the pin couples to — the cf-105 base image's tag; since
# cf-131 it matches the C01 ledger's PREDECESSOR row, not the live base tag
# (see the recorded-follow-up note at the header). t4 guards the pairing
# because the bump is manual.
TAG="v0.33.0"
URL_PERF="https://raw.githubusercontent.com/vllm-project/vllm/${TAG}/examples/observability/dashboards/grafana/performance_statistics.json"
URL_QUERY="https://raw.githubusercontent.com/vllm-project/vllm/${TAG}/examples/observability/dashboards/grafana/query_statistics.json"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

skip() {
  printf 'skip: %s\n' "$1" >&2
}

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-4]$ ]] || fail "unknown test id '$a' (expected t1..t4)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

WORK=$(mktemp -d /tmp/opencode/vllm-dashboards.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

[ -f "$VALS" ] || fail "precondition: $VALS missing"

# --- t1: both entries under grafana.dashboards.default, datasource Prometheus --
if want t1; then
  rc=0
  python3 - "$VALS" <<'PY' || rc=$?
import sys, yaml
vals = sys.argv[1]
try:
    d = yaml.safe_load(open(vals))
except yaml.YAMLError as ex:
    print(f"{vals} does not parse as YAML: {ex}", file=sys.stderr)
    sys.exit(2)
if not isinstance(d, dict):
    print(f"{vals} top level is not a mapping ({type(d).__name__})", file=sys.stderr)
    sys.exit(2)
default = (d.get("grafana") or {}).get("dashboards", {}).get("default") or {}
errs = []
for name in ("vllm-performance-statistics", "vllm-query-statistics"):
    e = default.get(name)
    if e is None:
        errs.append(f"{name}: missing under grafana.dashboards.default (C05 not landed)")
        continue
    if not isinstance(e, dict):
        errs.append(f"{name}: entry is not a mapping ({e!r})")
        continue
    if e.get("url") is None:
        errs.append(f"{name}: no url: (the repo url: convention, cf. the cert-manager/emqx entries)")
    if e.get("datasource") != "Prometheus":
        errs.append(f"{name}: datasource is {e.get('datasource')!r}, want 'Prometheus' (C05 AC3)")
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PY
  if [ "$rc" -eq 2 ]; then
    fail "t1: $VALS does not parse as YAML (C05 AC1 — the file must stay valid YAML)"
  elif [ "$rc" -ne 0 ]; then
    fail "t1: the vLLM dashboard entries are not in $VALS as required (C05 AC1/AC3 — the two entries are absent or malformed; diagnostics above)"
  fi
  ok "t1: $VALS parses; both entries exist under grafana.dashboards.default with url: + datasource: Prometheus"
fi

# --- t2: the exact tag-pinned urls + the tag-coupling comment on each entry ----
if want t2; then
  rc=0
  python3 - "$VALS" "$URL_PERF" "$URL_QUERY" <<'PY' || rc=$?
import re, sys, yaml
vals, want_perf, want_query = sys.argv[1:4]
d = yaml.safe_load(open(vals))
default = (d.get("grafana") or {}).get("dashboards", {}).get("default") or {}
errs = []
expected = {
    "vllm-performance-statistics": want_perf,
    "vllm-query-statistics": want_query,
}
for name, want in expected.items():
    if name not in default:
        errs.append(f"{name}: entry missing under grafana.dashboards.default (C05 not landed)")
        continue
    url = (default[name] or {}).get("url") or ""
    if url != want:
        errs.append(f"{name}: url is {url!r}, want exactly the tag pin {want!r} (the /vllm-project/vllm/v0.33.0/ segment — never main/master; C05 AC2)")
text = open(vals).read()
def entry_block(name):
    # Comments do not survive yaml.safe_load, so the entry body is located
    # by indent in the raw text: the lines below the key line indented
    # deeper than the key.
    out, started, indent = [], False, 0
    for ln in text.splitlines():
        if not started:
            if re.match(r"^\s+" + re.escape(name) + r":\s*(#.*)?$", ln):
                started = True
                indent = len(ln) - len(ln.lstrip())
            continue
        if not ln.strip():
            out.append(ln)
            continue
        ind = len(ln) - len(ln.lstrip())
        if ind <= indent:
            break
        out.append(ln)
    return out
for name in expected:
    if name not in default:
        continue  # the url pass above already reported the missing entry
    comments = [ln for ln in entry_block(name) if ln.lstrip().startswith("#")]
    if not comments:
        errs.append(f"{name}: no comment on the entry — the tag-coupling pin note is missing (renovate can't track raw URLs: bump this WITH the image pin)")
    elif not any(re.search(r"v\d+\.\d+\.\d+|tag[- ]coupling|image pin", c, re.I) for c in comments):
        errs.append(f"{name}: the entry comment carries no tag-coupling pin note")
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PY
  [ "$rc" -eq 0 ] || fail "t2: the dashboard url pins / tag-coupling comments are not met (C05 AC2 — diagnostics above)"
  ok "t2: both urls are exactly the ${TAG}-pinned ones (no main/master) and each entry carries the tag-coupling comment"
fi

# --- t3 (network-gated): the pinned urls are live dashboards -------------------
if want t3; then
  if ! urls=$(python3 - "$VALS" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
default = (d.get("grafana") or {}).get("dashboards", {}).get("default") or {}
for name in ("vllm-performance-statistics", "vllm-query-statistics"):
    url = (default.get(name) or {}).get("url")
    if url:
        print(url)
PY
  ); then
    fail "t3: cannot read the dashboard urls from $VALS (C05 AC1 parse precondition — see t1)"
  fi
  if [ -z "$urls" ]; then
    fail "t3: no vLLM dashboard urls to probe — the C05 entries are not landed (see t1)"
  fi
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    if code=$(curl -sS -o "$WORK/dash.json" -w '%{http_code}' --max-time 30 "$url" 2> "$WORK/curl-err"); then
      if [ "$code" != "200" ]; then
        fail "t3: $url answered HTTP $code — the tag pin must be live (C05 notes: a 404 at review time is BLOCKED-with-evidence, never a repin to main)"
      fi
      if ! python3 - "$WORK/dash.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
panels = d.get("panels")
assert isinstance(panels, list) and panels, "no non-empty panels array"
PY
      then
        fail "t3: $url is not a Grafana dashboard JSON (no non-empty panels array)"
      fi
      ok "t3: $url is live (HTTP 200, dashboard JSON with panels)"
    else
      skip "t3: no egress to the dashboard URL ($(head -1 "$WORK/curl-err" 2>/dev/null || echo 'network unreachable')) — the live check was not run"
    fi
  done <<< "$urls"
fi

# --- t4: pin-coupling drift guard against the C01 ledger ----------------------
if want t4; then
  if ! ver=$(python3 - "$VALS" <<'PY'
import re, sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
default = (d.get("grafana") or {}).get("dashboards", {}).get("default") or {}
tags = set()
for name in ("vllm-performance-statistics", "vllm-query-statistics"):
    m = re.search(r"vllm-project/vllm/(v\d+\.\d+\.\d+)/", (default.get(name) or {}).get("url") or "")
    if m:
        tags.add(m.group(1))
if not tags:
    print("no vllm tag in either dashboard url — the C05 entries are not landed (see t1/t2)", file=sys.stderr)
    sys.exit(1)
if len(tags) > 1:
    print(f"the two dashboard urls disagree on the vllm tag: {sorted(tags)}", file=sys.stderr)
    sys.exit(1)
print(tags.pop())
PY
  ); then
    fail "t4: cannot derive the dashboard tag from $VALS (diagnostics above — see t1/t2)"
  fi
  if [ ! -f "$LEDGER" ]; then
    fail "t4: $LEDGER missing — the C01 ledger the dashboard pin couples to is not landed (C01 is wave 1, so the ledger must exist by C05 dev — see tests/containers/vllm-radiance-mxfp4.sh t3)"
  fi
  # Dots escaped for ERE: a near-match (v0x33x0) must not pass, and the
  # boundary class keeps v10.33.0 / av0.33.0 out.
  ver_re=${ver//./\\.}
  if ! hit=$(grep -E "(^|[^A-Za-z0-9.])${ver_re}([.-]|$)" "$LEDGER" | head -1); then
    fail "t4: pin drift — the dashboards pin ${ver} but the C01 ledger (${LEDGER}) names no tag row starting with ${ver} (since cf-131 the match is the recorded predecessor row; the tag-coupling comment says bump the two TOGETHER — until the owner's re-import retires the pairing)"
  fi
  ok "t4: the dashboard pin (${ver}) couples to a tag row in the C01 ledger ($(printf '%s' "$hit" | sed 's/^[[:space:]]*//'))"
fi

printf 'PASS: vllm dashboard contract checks (%d ok)\n' "$checks"
