#!/usr/bin/env bash
# seaweedfs-debug / health-probe.sh — read-only triage sweep of a SeaweedFS cluster.
#
# GETs the master + admin HTTP surfaces, prints a PASS/WARN line per probe, and
# exits non-zero only on an unreachable endpoint: WARNs are leads for the triage
# docs, not failures. Read-only is the whole contract — agent permission tiers
# reach HTTP and Loki but no cluster console, and every change belongs in a
# human-paste block (runbook: .agents/plans/2026-11-10-dep-seaweedfs-ec-removal.md).
# Interpreting each WARN: references/endpoints-and-probes.md; log-side
# confirmation: references/loki-recipes.md.
#
# Usage:
#   bash health-probe.sh                       # lab infra ingress defaults
#   SW_MASTER_URL=https://... SW_ADMIN_URL=https://... bash health-probe.sh
#
# Requires curl; jq optional — richer per-volume output with it, grep fallback
# without (operator machines vary; the sweep must run either way).
set -euo pipefail

SW_MASTER_URL="${SW_MASTER_URL:-https://seaweedfs-master.infra.spencerslab.com}"
SW_ADMIN_URL="${SW_ADMIN_URL:-https://seaweedfs-admin.infra.spencerslab.com}"
SW_PROBE_TIMEOUT="${SW_PROBE_TIMEOUT:-15}"

WORK=$(mktemp -d) || exit 2
trap 'rm -rf "$WORK"' EXIT

warnings=0
failures=0

note_ok()   { printf 'PASS  %s\n' "$1"; }
note_warn() { printf 'WARN  %s\n' "$1"; warnings=$((warnings + 1)); }
note_bad()  { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# fetch <url> <outfile> — plain GET; echoes the HTTP code, 000 when unreachable.
# Full body reads only: an early client disconnect makes the volume server log a
# write-error line (endpoints-and-probes.md, /status churn note).
fetch() {
  curl -sS --max-time "$SW_PROBE_TIMEOUT" -o "$2" -w '%{http_code}' "$1" 2>/dev/null || true
}

have_jq() { command -v jq >/dev/null 2>&1; }

# json_num <file> <key> — top-level integer field, jq when present, grep fallback.
json_num() {
  if have_jq; then
    jq -r --arg k "$2" '.[$k] // empty' "$1" 2>/dev/null || true
  else
    grep -o "\"$2\"[[:space:]]*:[[:space:]]*[0-9]*" "$1" | head -1 | grep -o '[0-9]*$' || true
  fi
}

echo "== seaweedfs health-probe (read-only) =="
echo "master: $SW_MASTER_URL"
echo "admin:  $SW_ADMIN_URL"
if ! have_jq; then
  echo "note:   jq absent — numeric fallback parsing only, per-volume ReadOnly ids unavailable"
fi

# --- liveness ---------------------------------------------------------------
for probe in "master:$SW_MASTER_URL/healthz" "admin:$SW_ADMIN_URL/health"; do
  name=${probe%%:*}; url=${probe#*:}
  code=$(fetch "$url" "$WORK/liveness")
  if [ "$code" = "200" ]; then note_ok "$name liveness ($url)"
  elif [ "$code" = "000" ]; then note_bad "$name unreachable at $url — no HTTP answer at all"
  else note_warn "$name liveness answered $code — reachable but not clean"; fi
done

# --- admin cluster totals ----------------------------------------------------
code=$(fetch "$SW_ADMIN_URL/api/admin" "$WORK/admin")
if [ "$code" = "000" ]; then
  note_bad "admin /api/admin unreachable at $SW_ADMIN_URL — totals, EC health and the retry-loop-fuel verdict are unavailable"
elif [ "$code" != "200" ]; then
  note_warn "admin /api/admin answered $code — reachable but not serving the summary (re-verify the route, endpoints-and-probes.md)"
else
  tv=$(json_num "$WORK/admin" total_volumes)
  tc=$(json_num "$WORK/admin" total_chunks)
  tev=$(json_num "$WORK/admin" total_ec_volumes)
  tes=$(json_num "$WORK/admin" total_ec_shards)
  echo "      totals: volumes=${tv:-?} chunks=${tc:-?} ec_volumes=${tev:-?} ec_shards=${tes:-?}"
  # EC groups present on a single-rack layout = the placement-impossible churn is
  # expected until the groups are gone (collections-and-ec.md, EC arithmetic).
  # An unparseable field is its own verdict — never let a miss read as "0 groups".
  if [ -z "$tev" ]; then
    note_warn "admin /api/admin carried no parseable total_ec_volumes — re-check the payload shape (endpoints-and-probes.md)"
  elif [ "$tev" -gt 0 ]; then
    note_warn "$tev EC volume group(s) present (${tes:-?} shards) — expect relaxed-placement / invalid-task-ID churn; decode+purge are human-shell work"
  else
    note_ok "no EC volume groups (total_ec_volumes = 0)"
  fi
fi

# --- master topology: per-node EC shard counts --------------------------------
code=$(fetch "$SW_MASTER_URL/dir/status" "$WORK/dir")
if [ "$code" = "200" ]; then
  ecs=$( (grep -o '"EcShards"[[:space:]]*:[[:space:]]*[0-9]*' "$WORK/dir" || true) \
        | grep -o '[0-9]*$' | awk '{s += $1} END {print s + 0}' || true)
  echo "      /dir/status: EcShards across nodes = ${ecs:-0}"
  if [ "${ecs:-0}" -gt 0 ]; then
    note_warn "master still announces $ecs EC shard(s) — the admin totals and the topology must both reach 0 for the EC removal to be done"
  else
    note_ok "no EC shards in the master topology"
  fi
elif [ "$code" = "000" ]; then
  note_bad "master /dir/status unreachable"
else
  note_warn "master /dir/status answered $code"
fi

# --- read-only sweep over the volume detail union -----------------------------
# /vol/status is the 1 MB union of every volume pod's detail (== volume.list);
# pulling it is the point of this probe — read-only marks and their ids are the
# headline incident artifact.
code=$(fetch "$SW_MASTER_URL/vol/status" "$WORK/vol")
if [ "$code" = "200" ]; then
  ro=$(grep -c '"ReadOnly"[[:space:]]*:[[:space:]]*true' "$WORK/vol" || true)
  echo "      /vol/status: read-only replica(s) = $ro"
  if [ "$ro" -gt 0 ]; then
    if have_jq; then
      ids=$(jq -r '[.Volumes // {} | to_entries[] as $e | $e.value[] | select(.ReadOnly == true)
                    | "\($e.key)#\(.Id)"] | join(" ")' "$WORK/vol" 2>/dev/null || true)
      [ -n "$ids" ] && echo "      nodes#volumes: $ids" || true
    fi
    note_warn "$ro read-only replica(s) marked — deletions behind them back up and s3 retry loops persist while any carrier entry stays live (loki-recipes.md: retry reading / max retry attempts); marks clear only via human volume.mark or weed fix (runbook Phase 3)"
  else
    note_ok "no read-only replicas in /vol/status"
  fi
elif [ "$code" = "000" ]; then
  note_bad "master /vol/status unreachable"
else
  note_warn "master /vol/status answered $code"
fi

# --- summary ------------------------------------------------------------------
echo "--"
if [ "$failures" -gt 0 ]; then
  echo "PROBE FAIL: $failures unreachable endpoint(s), $warnings warning(s) — check ingress + pod health first"
  exit 1
fi
if [ "$warnings" -gt 0 ]; then
  echo "PROBE OK (reachable): $warnings warning(s) — leads, not verdicts; triage via error-signatures.md, verify via loki-recipes.md fresh windows"
else
  echo "PROBE OK: all endpoints reachable, no read-only marks, no EC groups"
fi
