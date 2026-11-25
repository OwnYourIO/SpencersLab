#!/usr/bin/env bash
# C01-C05 contract (ticket 2026/2026-11-cf-133-feat-audio-ad-detection) for
# containers/audio-ad-detection (the headless .NET 10 worker that taps the
# home snapcast stream, fingerprints it with SoundFingerprinting 18.0.0, and
# publishes ad events to Home Assistant over MQTT), charts/audio-ad-detection
# (app-template 5.0.1, brand-new 1.0.0), and the services/home/prod wiring.
# Modeled on tests/containers/forgejo-runner.sh: no docker daemon exists in
# agent sessions, so the gate is a static contract + hadolint, and the build
# leg reports the designed-passing shape "docker build => no-daemon,
# CI-deferred" (ruled 2026-10-28, cf-77; AGENTS "Pipeline specifics in this
# repo") — the merge fire's own containers-build.yaml run is the authoritative
# build test. Every test here passes or fails on file content alone: no
# network, no docker build, no live broker.
#
# DEVIATION from the forgejo-runner shape: its fail() exits on the first
# failure; here a failed arm reports and the run continues, with the exit code
# carrying the aggregate. Reason: this script covers t1-t31 across six
# chunks, and dev/review need per-test commands_run evidence — an abort-on-
# first-fail run against the pre-dev tree would report only t1.
#
# Authored-RED posture: against the pre-dev tree (implementation absent) every
# content arm measures RED by design; t31 may already be green (it pins the
# script's own constants against the plan of record, both of which pre-date
# the dev chunks). GREEN only as dev lands C01..C05. A missing file is the
# chunk-not-yet-implemented state, not a skip; a missing TOOL (hadolint,
# helm) is an honest skip.
#
# AC trace (per-chunk "## Tests" lists):
# t1-t9   C01  Dockerfile pins (two pinned FROMs, renovate comment-above-ARG,
#             version-stable deb URL, apt shape, non-root + ENTRYPOINT/no CMD),
#             csproj pins (net10.0, NAudio.Core 3.3.0, SoundFingerprinting
#             18.0.0, MQTTnet 5.2.0.1603, M.E.Logging 10.x, no NAudio
#             meta-package), supervisor shape (foreground file-player argv,
#             stderr drain, 4-byte parity, watchdog 500ms/grace/Reconnecting/
#             SIGKILL/3-per-5-min escalation), HttpListener /healthz /readyz
#             /metrics + the two C01 metrics + env defaults, startup stream
#             assignment (GetStatus/SetStream gate), hadolint
# t10-t14 C02a  10,240-chunk constant singularity (no overlap stamping),
#             WdlResampler Sinc64 call shape + input-rate gate (no 3.3.0
#             provider wrapper), realtime config wired to env knobs with the
#             ruled defaults (120/5/120) + the 18.0.0 csproj pin,
#             InMemoryModelService directory ctor + Snapshot + non-fatal empty
#             startup, IStreamState members + IAdEventSink awaited callback
# t15-t19 C02b  capture state machine defaults (30/300/-45) + RMS consumption
#             + below-floor discard, ring buffer depth + WAV writer constants
#             + naming scheme, auto-promotion guardrails (2 sightings / 24 h
#             gap / 20 per day, no-single-sighting guard, proximity dedup,
#             auto_promoted flag, capped counter), manual promote lane
#             (--file/--dir, FFmpegAudioService, no auto_promoted flag,
#             non-zero exit), retention 14/200 + trigger sites + list/prune +
#             metrics
# t20-t24 C03  retained-leg inventory (one 'Retained = true' property site +
#             3+ explicit non-retained state publishes + the single retained
#             'online' + LWT builder spelling), LWT/online +
#             reconnect re-publish, discovery payload shape (R4), no
#             credentials material (verdict (a) anonymous default), shutdown
#             ordering (kill child before pipe close, Snapshot before exit 0)
# t25-t29 C04  render assertions (sentinel/ExternalSecret/credential-free,
#             Recreate/1-replica/probes with no RMS, D-8 pair on/off gate,
#             no Ingress + ClusterIP/10Gi RWO PVC + security context), the
#             services charts: entry shape + no ingress subdomain + no
#             custom-values entry (verdict (a)) + the TBD-owner placeholder,
#             Chart.yaml pins (apiVersion v2, version 1.0.0, app-template 5.0.1)
# t30-t31 C05  whole-plan validation re-entry (helm lint + t1..t29 re-run),
#             plan-of-record pin of the ruled defaults (drift reddens)
#
# Run from the repo root:
#   bash tests/containers/audio-ad-detection.sh          # t1..t31
#   bash tests/containers/audio-ad-detection.sh t3 t7    # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
export PATH="$HOME/.local/bin:$PATH"

CONTAINER_DIR="containers/audio-ad-detection"
DF="$CONTAINER_DIR/Dockerfile"
CSPROJ="$CONTAINER_DIR/src/AudioAdDetection.csproj"
SRC="$CONTAINER_DIR/src"
CHART_DIR="charts/audio-ad-detection"
CHART_YAML="$CHART_DIR/Chart.yaml"
CHART_VALUES="$CHART_DIR/values.yaml"
SERVICES_HOME="services/home/prod/values.yaml"
CUSTOM_VALUES="custom-values/home/prod-values.yaml"
PLAN_DIR=".agents/plans/2026/2026-11-cf-133-feat-audio-ad-detection"
C05="$PLAN_DIR/chunks/C05.md"

# Plan-of-record ruled defaults (C05 AC3). t12/t15/t17/t19 consume them; t31
# pins them back against C05.md so a drift in either direction reddens.
RT_OCA=120
RT_COV=5
RT_STALE=120
CAP_MIN=30
CAP_MAX=300
CAP_RMS=-45
CAP_RET=14
CAP_MAXFILES=200
AP_SIG=2
AP_GAP=24
AP_CAP=20

TMP="/tmp/opencode"
mkdir -p "$TMP"
RENDER="$TMP/aad-render-default.yaml"
RENDER_OFF="$TMP/aad-render-off.yaml"

ok_count=0
fail_count=0
skip_count=0

ok()   { ok_count=$((ok_count + 1));   printf 'ok: %s\n' "$1"; }
fail() { fail_count=$((fail_count + 1)); printf 'FAIL: %s\n' "$1" >&2; }
skip() { skip_count=$((skip_count + 1)); printf 'skip: %s\n' "$1" >&2; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 31); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t([1-9]|[12][0-9]|3[01])$ ]] || {
      printf "unknown test id '$a' (expected t1..t31)\n" >&2
      exit 2
    }
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# First src file containing $1 (empty when absent).
find_src() { grep -rlE "$1" "$SRC" 2>/dev/null | head -n 1 || true; }

# First line number of $2 in $1 (empty when absent).
line_of() { grep -nE "$2" "$1" 2>/dev/null | head -n 1 | cut -d: -f1 || true; }

# $1 file, $2 token, $3 number: the token line +-2 lines must contain the
# number as a standalone integer (a config default sits next to its knob).
near() {
  local ln win
  ln=$(grep -nE "$2" "$1" 2>/dev/null | head -n 1 | cut -d: -f1 || true)
  [ -n "$ln" ] || return 1
  win=$(sed -n "$((ln > 2 ? ln - 2 : 1)),$((ln + 2))p" "$1" || true)
  printf '%s\n' "$win" | grep -qE "(^|[^0-9])$3([^0-9]|$)"
}

# Print each k8s probe block (the probe key line through the last line more
# deeply indented) — t26's RMS-in-probes ban needs the block, not the whole
# render, because env names like CAPTURE_RMS_FLOOR_DB legitimately contain
# "rms" outside probe definitions.
extract_probe_blocks() {
  awk '
    function indent(s) { sub(/[^[:space:]].*$/, "", s); return length(s) }
    /^[[:space:]]*(startup|liveness|readiness)Probe:[[:space:]]*$/ {
      ind = indent($0); print; inb = 1; next
    }
    inb { if (indent($0) <= ind) { inb = 0 } else { print } }
  ' "$1"
}

helm_available() { command -v helm >/dev/null 2>&1; }

# $1 outfile, $2... helm --set args. No cache: one fresh render per arm.
get_render() {
  local out="$1"
  shift || true
  helm template "$CHART_DIR" "$@" > "$out" 2> "${out}.err"
}

FLAT=""
if [ -f "$DF" ]; then
  # Join backslash-wrapped lines so each logical RUN reads as one line
  # (forgejo-runner idiom) — the apt-cleanup-in-same-RUN arm needs it.
  FLAT=$(sed -e ':a' -e 'N' -e '$!ba' -e 's/\\\n[[:space:]]*/ /g' "$DF")
fi

# --- t1: exactly two FROM lines, the exact pinned bases, no :latest --------
if want t1; then
  A=$fail_count
  if [ -f "$DF" ]; then
    n_from=$(grep -cE '^FROM[[:space:]]' "$DF" || true)
    [ "$n_from" -eq 2 ] ||
      fail "t1: expected exactly two FROM lines (the sdk build stage + the runtime stage), found $n_from"
    from1=$(grep -E '^FROM[[:space:]]' "$DF" | sed -n 1p)
    from2=$(grep -E '^FROM[[:space:]]' "$DF" | sed -n 2p)
    case "$from1" in
      'FROM mcr.microsoft.com/dotnet/sdk:10.0'*) : ;;
      *) fail "t1: the first FROM line is '$from1', expected the mcr.microsoft.com/dotnet/sdk:10.0 build stage (10.0.15 noble amd64; R3)" ;;
    esac
    case "$from2" in
      'FROM mcr.microsoft.com/dotnet/runtime:10.0'*) : ;;
      *) fail "t1: the second FROM line is '$from2', expected the mcr.microsoft.com/dotnet/runtime:10.0 runtime stage (framework-dependent publish)" ;;
    esac
    if grep -qE ':latest' "$DF"; then
      fail "t1: ':latest' appears in $DF — mutable base tags are banned (the 10.0 pins are the ruled shape)"
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t1: two pinned FROM lines (sdk:10.0 -> runtime:10.0), no :latest anywhere"; fi
  else
    fail "t1: $DF does not exist (C01 not implemented)"
  fi
fi

# --- t2: renovate comment adjacency above the snapclient ARG pin -----------
if want t2; then
  A=$fail_count
  if [ -f "$DF" ]; then
    # The comment-above-ARG manager (renovate.json:112-169) binds the pin only
    # at direct adjacency; placement one line off is an inert pin that still
    # looks tracked (forgejo-runner t2's lesson).
    ln=$(line_of "$DF" '^ARG SNAPCAST_VERSION=')
    [ -n "$ln" ] || fail "t2: no ARG SNAPCAST_VERSION line in $DF"
    val=$(sed -n "${ln}p" "$DF" | sed -E 's/^ARG SNAPCAST_VERSION=//')
    [ "$val" = "0.35.0" ] ||
      fail "t2: ARG SNAPCAST_VERSION is '$val', expected the ruled pin 0.35.0 (the bookworm .deb from the GitHub release; R2 §4)"
    prev_line=$(sed -n "$((ln > 1 ? ln - 1 : 0))p" "$DF" 2>/dev/null | sed 's/[[:space:]]*$//' || true)
    [ "$prev_line" = "# renovate: datasource=github-releases depName=snapcast/snapcast" ] ||
      fail "t2: the line directly above ARG SNAPCAST_VERSION is '$prev_line', expected the github-releases renovate annotation (adjacency is what makes the pin tracked)"
    if [ "$fail_count" -eq "$A" ]; then ok "t2: ARG SNAPCAST_VERSION=0.35.0 under the directly-adjacent github-releases renovate annotation"; fi
  else
    fail "t2: $DF does not exist (C01 not implemented)"
  fi
fi

# --- t3: version-stable deb URL + apt install shape ------------------------
if want t3; then
  A=$fail_count
  if [ -f "$DF" ]; then
    printf '%s\n' "$FLAT" | grep -qF 'https://github.com/snapcast/snapcast/releases/download/v${SNAPCAST_VERSION}/snapclient_${SNAPCAST_VERSION}-1_amd64_bookworm.deb' ||
      fail "t3: the deb URL is not the version-stable shape (v\${SNAPCAST_VERSION} + snapclient_\${SNAPCAST_VERSION}-1_amd64_bookworm.deb) — a hardcoded version in the URL would bypass the ARG pin"
    printf '%s\n' "$FLAT" | grep -qE 'apt-get install -y --no-install-recommends.*\.deb' ||
      fail "t3: no 'apt-get install -y --no-install-recommends <deb>' line — the .deb install must carry the no-recommends flag"
    install_line=$(printf '%s\n' "$FLAT" | grep -E '^RUN.*apt-get install' | head -n 1 || true)
    [ -n "$install_line" ] || fail "t3: no RUN line installs the deb"
    printf '%s\n' "$install_line" | grep -qF 'rm -rf /var/lib/apt/lists' ||
      fail "t3: the deb install RUN carries no 'rm -rf /var/lib/apt/lists' — the cleanup must sit in the SAME RUN (a separate RUN leaves the package lists in the image)"
    if [ "$fail_count" -eq "$A" ]; then ok "t3: version-stable deb URL, --no-install-recommends install, apt cleanup in the same RUN"; fi
  else
    fail "t3: $DF does not exist (C01 not implemented)"
  fi
fi

# --- t4: non-root user, ENTRYPOINT present, no CMD, no USER root ----------
if want t4; then
  A=$fail_count
  if [ -f "$DF" ]; then
    printf '%s\n' "$FLAT" | grep -qE 'groupadd' ||
      fail "t4: no groupadd in $DF — the non-root law wants an explicit group + user (the bookworm username-collision lesson: pin the uid explicitly)"
    printf '%s\n' "$FLAT" | grep -qE 'useradd.*--uid[[:space:]]+65532' ||
      fail "t4: no useradd with '--uid 65532' — uid 65532 is the nonroot uid the chart's securityContext expects"
    if grep -qE '^USER[[:space:]]+root([[:space:]]|$)' "$DF"; then
      fail "t4: a 'USER root' line — the image must run as the non-root user"
    fi
    grep -qE '^USER[[:space:]]' "$DF" ||
      fail "t4: no USER line — the image must switch to the non-root user before ENTRYPOINT"
    grep -qE '^ENTRYPOINT' "$DF" ||
      fail "t4: no ENTRYPOINT line — service containers run the entrypoint so K8s args append, not replace"
    if grep -qE '^CMD[[:space:]]' "$DF"; then
      fail "t4: a CMD line — CMD would replace the ENTRYPOINT arg-append contract"
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t4: non-root uid 65532 (groupadd + useradd), USER line present and not root, ENTRYPOINT present, no CMD"; fi
  else
    fail "t4: $DF does not exist (C01 not implemented)"
  fi
fi

# --- t5: csproj target + the pinned PackageReference set -------------------
if want t5; then
  A=$fail_count
  if [ -f "$CSPROJ" ]; then
    grep -qE '<TargetFramework>net10\.0</TargetFramework>' "$CSPROJ" ||
      fail "t5: csproj does not target net10.0"
    grep -qE '<PackageReference Include="NAudio\.Core" Version="3\.3\.0"' "$CSPROJ" ||
      fail "t5: NAudio.Core 3.3.0 not pinned (the low-level WdlResampler needs 3.3.0; R3 §2)"
    grep -qE '<PackageReference Include="SoundFingerprinting" Version="18\.0\.0"' "$CSPROJ" ||
      fail "t5: SoundFingerprinting not pinned at 18.0.0 (Q4; the 17.4.x fallback is a recorded one-line swap, not the default)"
    grep -qE '<PackageReference Include="MQTTnet" Version="5\.2\.0\.1603"' "$CSPROJ" ||
      fail "t5: MQTTnet not pinned at 5.2.0.1603"
    grep -qE '<PackageReference Include="Microsoft\.Extensions\.Logging" Version="10\.' "$CSPROJ" ||
      fail "t5: Microsoft.Extensions.Logging not pinned at 10.x"
    if grep -qE '<PackageReference Include="NAudio"[[:space:]>]' "$CSPROJ"; then
      fail "t5: the NAudio meta-package is referenced — the meta-package drags the IIR-only provider surface; the contract is NAudio.Core only"
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t5: csproj targets net10.0 with the pinned set (NAudio.Core 3.3.0, SoundFingerprinting 18.0.0, MQTTnet 5.2.0.1603, M.E.Logging 10.x), no NAudio meta-package"; fi
  else
    fail "t5: $CSPROJ does not exist (C01 not implemented)"
  fi
fi
# --- t6: supervisor invariants in source ----------------------------------
if want t6; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    if [ -f "$SRC/SnapClientSupervisor.cs" ]; then
      SUP="$SRC/SnapClientSupervisor.cs"
    else
      SUP=$(find_src 'logsink')
    fi
    [ -n "$SUP" ] ||
      fail "t6: no supervisor file found (neither src/SnapClientSupervisor.cs nor a file with the 'logsink' token) — C01 not implemented"
    if [ -n "$SUP" ]; then
      grep -qF -- '--player file:filename=stdout' "$SUP" ||
        fail "t6: no '--player file:filename=stdout' argv shape (R2 implication 1 — the file player is a recorder: 50 ms ticks, silence-on-underrun; the read loop never treats a short read as EOF)"
      grep -qF -- '--logsink stderr' "$SUP" ||
        fail "t6: no '--logsink stderr' — the watchdog's outage tolerance reads 'Reconnecting' from the child's stderr, so the logs must land there"
      grep -qF -- '--hostID' "$SUP" ||
        fail "t6: no '--hostID' pin — pod MACs are random; the pinned hostID is what the startup Group.SetStream client lookup keys on"
      grep -qiE 'sampleformat' "$SUP" ||
        fail "t6: no '--sampleformat' in the argv builder (the 5512:16:* env-driven boundary; the CLI rejects numeric channels at startup — Q6)"
      grep -iE 'frame|parity' "$SUP" | grep -qE '[=:]?[[:space:]]4([[:space:]]|$)' ||
        fail "t6: no 4-byte frame constant tied to a frame/parity token (stereo s16 frame = 4 B) — the parity accumulator is the read loop's bookkeeping contract"
      grep -qiE 'standarderror|errordatareceived|beginerrorreadline' "$SUP" ||
        fail "t6: no stderr stream reference — stderr MUST be drained concurrently (a full stderr pipe deadlocks the child)"
      grep -qiE 'thread|task' "$SUP" ||
        fail "t6: no background thread/task for the stderr drain"
      if grep -rqF -- '--daemon' "$SRC"; then
        fail "t6: '--daemon' appears in $SRC — the child is a foreground supervised process, never a daemon"
      fi
      grep -qE '\b500\b' "$SUP" ||
        fail "t6: no 500 (the ms zero-byte kill threshold; R2 §2 #1563 posture — a hung process spins at 100% CPU)"
      gln=$(grep -niE 'grace' "$SUP" | head -n 1 | cut -d: -f1 || true)
      [ -n "$gln" ] ||
        fail "t6: no 'grace' token — the startup grace (10-30 s) is a ruled watchdog constant"
      gval=""
      for v in $(sed -n "${gln},$((gln + 2))p" "$SUP" | grep -oE '[0-9]+'); do
        if [ "$v" -ge 10 ] && [ "$v" -le 30 ]; then gval="$v"; break; fi
      done
      [ -n "$gval" ] ||
        fail "t6: no grace constant in 10..30 s near the grace token (window: $SUP line $gln..$((gln + 2)))"
      grep -q 'Reconnecting' "$SUP" ||
        fail "t6: no 'Reconnecting' keyword — the outage-tolerance window (extended to minutes while the server is down) keys on the child's stderr"
      grep -qE 'Kill\(|entireProcessTree|SIGKILL' "$SUP" ||
        fail "t6: no SIGKILL kill path (Process.Kill / entireProcessTree) — SIGTERM's io_context stop may never run on a #1563-hung process"
      eln=$(grep -niE 'escalat' "$SUP" | head -n 1 | cut -d: -f1 || true)
      [ -n "$eln" ] ||
        fail "t6: no 'escalat' token — the kill-escalation counter (>=3 kills in 5 min -> alert + respawn delay) is a ruled watchdog behavior"
      ewin=$(sed -n "$((eln > 1 ? eln - 1 : 1)),$((eln + 2))p" "$SUP")
      printf '%s\n' "$ewin" | grep -qE '\b3\b' ||
        fail "t6: no 3-kill escalation threshold near the escalation token"
      printf '%s\n' "$ewin" | grep -qE '\b5\b' || grep -qiE 'minutes\(5\)|[[:space:]]5[[:space:]]*\*[[:space:]]*60' "$SUP" ||
        fail "t6: no 5-minute escalation window (the ruled shape is >=3 kills in 5 min)"
      if [ "$fail_count" -eq "$A" ]; then ok "t6: supervisor contract — foreground file-player argv, stderr drain on a background thread, 4-byte parity, watchdog (500 ms / $gval s grace / Reconnecting tolerance / SIGKILL + respawn / 3-per-5-min escalation)"; fi
    fi
  else
    fail "t6: $SRC does not exist (C01 not implemented)"
  fi
fi

# --- t7: HttpListener endpoints + C01 metrics + env config surface --------
if want t7; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    HL=$(find_src 'HttpListener')
    [ -n "$HL" ] ||
      fail "t7: no HttpListener in $SRC — the runtime image carries no ASP.NET Core shared framework (R3 §1), so the HttpListener shape is the ruled one (no Kestrel)"
    if [ -n "$HL" ]; then
      for p in /healthz /readyz /metrics; do
        grep -qF "$p" "$HL" || fail "t7: '$p' not served in the HttpListener file ($HL)"
      done
    fi
    grep -rq 'HEALTH_PORT' "$SRC" ||
      fail "t7: HEALTH_PORT env name absent — the health/metrics port must come from the env surface (default 8080)"
    grep -rq 'SNAP_URL' "$SRC" ||
      fail "t7: SNAP_URL env name absent (default tcp://home-snapcast:1704)"
    grep -rqF 'tcp://home-snapcast:1704' "$SRC" ||
      fail "t7: the SNAP_URL default 'tcp://home-snapcast:1704' is not in the source"
    grep -rq 'SNAP_SAMPLE_FORMAT' "$SRC" ||
      fail "t7: SNAP_SAMPLE_FORMAT env name absent (default 5512:16:* — channels must be *, the CLI rejects numeric channels)"
    grep -rqF '5512:16:*' "$SRC" ||
      fail "t7: the '5512:16:*' default sample format is not in the source"
    grep -rq 'MQTT_BROKER_HOST' "$SRC" ||
      fail "t7: MQTT_BROKER_HOST env name absent (default home-mosquitto — verdict (a))"
    grep -rqF 'home-mosquitto' "$SRC" ||
      fail "t7: the 'home-mosquitto' broker default is not in the source"
    grep -rqE '\b1883\b' "$SRC" ||
      fail "t7: the '1883' broker port default is not in the source"
    grep -rq 'aad_audio_rms_db' "$SRC" ||
      fail "t7: the aad_audio_rms_db metric is absent from the source"
    grep -rq 'aad_snapclient_kills_total' "$SRC" ||
      fail "t7: the aad_snapclient_kills_total metric is absent from the source"
    if [ "$fail_count" -eq "$A" ]; then ok "t7: /healthz /readyz /metrics on the HttpListener at HEALTH_PORT; snap/mqtt defaults present (home-snapcast:1704, 5512:16:*, home-mosquitto:1883); the two C01 metrics present"; fi
  else
    fail "t7: $SRC does not exist (C01 not implemented)"
  fi
fi

# --- t8: startup stream assignment invariants ------------------------------
if want t8; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    grep -rq 'Server\.GetStatus' "$SRC" ||
      fail "t8: no Server.GetStatus RPC — the group lookup (the group whose clients[] contains the pinned hostID) keys on it"
    grep -rq 'Group\.SetStream' "$SRC" ||
      fail "t8: no Group.SetStream RPC — the one-shot startup tap re-point (R2 §5)"
    grep -rq 'SNAP_RPC_URL' "$SRC" ||
      fail "t8: SNAP_RPC_URL env name absent"
    grep -rqF 'http://home-snapcast-snapcast-http:1780/jsonrpc' "$SRC" ||
      fail "t8: the SNAP_RPC_URL default (the snapcast-http 1780 jsonrpc endpoint) is not in the source"
    grep -rq 'TBD-owner' "$SRC" ||
      fail "t8: 'TBD-owner' absent — the worker must treat the documented placeholder (and the empty value) as unassigned: config-order + logged marker, no RPC (Q2)"
    ASS=$(find_src 'Group\.SetStream')
    [ -n "$ASS" ] || fail "t8: no file with the Group.SetStream call site"
    if [ -n "$ASS" ]; then
      grep -qiE 'config.?order' "$ASS" ||
        fail "t8: no 'config-order' marker in the assignment path — the unassigned state must log its working-state marker (readiness is NOT blocked by the assignment)"
      grep -qE 'catch' "$ASS" ||
        fail "t8: no catch in the assignment path — the one-shot RPC is best-effort non-blocking: a failure is logged, not fatal (and it must stay out of the hot loop — a fresh CodecHeader is a #1563 exposure event)"
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t8: startup stream assignment — Server.GetStatus -> hostID group lookup -> Group.SetStream on SNAP_RPC_URL, gated on a real value (empty / TBD-owner -> config-order marker)"; fi
  else
    fail "t8: $SRC does not exist (C01 not implemented)"
  fi
fi

# --- t9: hadolint at the error threshold (honest skip if absent) ----------
if want t9; then
  A=$fail_count
  if [ ! -f "$DF" ]; then
    fail "t9: $DF does not exist (C01 not implemented)"
  elif ! command -v hadolint >/dev/null 2>&1; then
    skip "t9: hadolint not available here; the lint leg was not exercised (CI leg stands)"
  elif hadolint --failure-threshold error "$DF" >"$TMP/aad-hadolint.log" 2>&1; then
    # Error threshold, not warning (forgejo-runner t7's reasoning): the
    # dotnet base is a large distro image and warning-level findings are
    # inherited state no line of this Dockerfile can remove.
    if [ "$fail_count" -eq "$A" ]; then ok "t9: hadolint reports no errors on $DF"; fi
  else
    tail -n 40 "$TMP/aad-hadolint.log" >&2
    fail "t9: hadolint reported findings (log kept at $TMP/aad-hadolint.log)"
  fi
fi

# --- t10: the 10,240 chunk constant is singular; no overlap stamping ------
if want t10; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    n=$( { grep -roE '(^|[^0-9])10240([^0-9]|$)' "$SRC" 2>/dev/null || true; } | wc -l )
    [ "$n" -eq 1 ] ||
      fail "t10: found $n occurrences of 10240 in $SRC, expected exactly one — the chunk-size constant is the single chunking authority (exactly 10,240 resampled mono floats per AudioSamples @5512, 1.8578 s)"
    hit=$(grep -rnE '(^|[^0-9])10240([^0-9]|$)' "$SRC" | head -n 1 || true)
    printf '%s\n' "$hit" | grep -qE 'const|readonly|static|=' ||
      fail "t10: the single 10240 occurrence is not a constant declaration ($hit)"
    if grep -rqEi 'overlap' "$SRC"; then
      fail "t10: 'overlap' appears in $SRC — producer-side chunk overlap is banned: the library's internal prefix handles FFT continuity (R1 implication 1)"
    fi
    if grep -rqE 'TimeOffset[^;{]*[[:space:]]-[0-9]' "$SRC"; then
      fail "t10: a negative TimeOffset appears in $SRC — overlap-stamping is the banned shape"
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t10: the 10,240-sample chunk constant is singular; no overlap-stamp / negative-TimeOffset code"; fi
  else
    fail "t10: $SRC does not exist (C02a not implemented)"
  fi
fi

# --- t11: WdlResampler low-level call shape + input-rate gate --------------
if want t11; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    RS=$(find_src 'WdlResampler')
    [ -n "$RS" ] ||
      fail "t11: no WdlResampler usage in $SRC — the 48k->5512 conversion is worker-side (the library hard-checks SampleRate == 5512 and never resamples; R3 §2)"
    if [ -n "$RS" ]; then
      grep -qE 'SetRates[[:space:]]*\([[:space:]]*48000[[:space:]]*,[[:space:]]*5512[[:space:]]*\)' "$RS" ||
        fail "t11: no SetRates(48000, 5512) call — the input->output rate pair is the ruled shape"
      grep -qE 'SetFeedMode[[:space:]]*\([[:space:]]*true[[:space:]]*\)' "$RS" ||
        fail "t11: no SetFeedMode(true) — feed mode is the streaming Sinc64 shape"
      grep -qE 'SetMode[[:space:]]*\([[:space:]]*false[[:space:]]*,[[:space:]]*0[[:space:]]*,[[:space:]]*true[[:space:]]*,[[:space:]]*64[[:space:]]*\)' "$RS" ||
        fail "t11: no SetMode(false, 0, true, 64) — the Sinc64 kernel selector (the 3.3.0 WdlResamplingSampleProvider wrapper is IIR-only with no quality selector; R3 §2)"
      grep -qE '5512[[:space:]]*(!=|==)|(!=|==)[[:space:]]*5512' "$RS" ||
        fail "t11: no input-rate gate on 5512 — the resampler must be active only when the input rate != 5512 (the default 5512:16:* lane is a pass-through, no resampler in the hot path)"
    fi
    if grep -rq 'WdlResamplingSampleProvider' "$SRC"; then
      fail "t11: WdlResamplingSampleProvider referenced anywhere in $SRC — the 3.3.0 provider wrapper is IIR-only (R3 §2); the contract is the low-level WdlResampler"
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t11: WdlResampler Sinc64 call shape (SetRates(48000, 5512), SetFeedMode(true), SetMode(false, 0, true, 64)) gated on input rate != 5512; no provider wrapper"; fi
  else
    fail "t11: $SRC does not exist (C02a not implemented)"
  fi
fi
# --- t12: realtime query composition + env-wired ruled defaults ------------
if want t12; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    grep -rq 'BlockingRealtimeCollection' "$SRC" ||
      fail "t12: BlockingRealtimeCollection absent — the chunk feeder is the ruled realtime contract (10,240-sample AudioSamples chunks; R1 §1)"
    grep -rq 'IRealtimeQueryCommand' "$SRC" ||
      fail "t12: IRealtimeQueryCommand absent from the query composition"
    grep -rq 'NewOccurrenceAbove' "$SRC" ||
      fail "t12: NewOccurrenceAbove absent — the seam-jump policy is the documented ad-spot-in-program control (R1 §1)"
    grep -rq 'NEW_OCCURRENCE_ABOVE' "$SRC" ||
      fail "t12: the NEW_OCCURRENCE_ABOVE env knob is absent — the policy must stay configurable (keep it configurable, default $RT_OCA)"
    CONF=$(find_src 'NEW_OCCURRENCE_ABOVE')
    [ -n "$CONF" ] || fail "t12: no config surface file with NEW_OCCURRENCE_ABOVE"
    if [ -n "$CONF" ]; then
      near "$CONF" 'NEW_OCCURRENCE_ABOVE' "$RT_OCA" ||
        fail "t12: no default $RT_OCA near NEW_OCCURRENCE_ABOVE (the library's own broadcast-agent value; R1 §1)"
      grep -qE "\b$RT_COV\b" "$CONF" ||
        fail "t12: no coverage default $RT_COV in the config surface ($CONF) — COVERAGE_SECONDS is the TVEyes 40%-coverage emission bar (R1 §2)"
    fi
    grep -rq 'COVERAGE_SECONDS' "$SRC" ||
      fail "t12: the COVERAGE_SECONDS env knob is absent"
    grep -rq 'OngoingEntryStalenessCeiling' "$SRC" ||
      fail "t12: OngoingEntryStalenessCeiling absent — stale ongoing entries must close promptly (default $RT_STALE s)"
    [ -f "$CSPROJ" ] || fail "t12: $CSPROJ does not exist (C01 not implemented)"
    if [ -f "$CSPROJ" ]; then
      grep -qE '<PackageReference Include="SoundFingerprinting" Version="18\.0\.0"' "$CSPROJ" ||
        fail "t12: the csproj SoundFingerprinting pin is not 18.0.0 (Q4; the recorded 17.4.x fallback is a one-line swap, not a second code path)"
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t12: BlockingRealtimeCollection + IRealtimeQueryCommand composition; NewOccurrenceAbove/COVERAGE_SECONDS/staleness wired to env knobs with the ruled defaults ($RT_OCA / $RT_COV / $RT_STALE); csproj pinned at 18.0.0"; fi
  else
    fail "t12: $SRC does not exist (C02a not implemented)"
  fi
fi

# --- t13: InMemoryModelService load-from-dir + Snapshot + non-fatal empty --
if want t13; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    MS=$(find_src 'InMemoryModelService')
    [ -n "$MS" ] ||
      fail "t13: InMemoryModelService absent — the ruled storage lane (MIT, single container on the PVC; the 'intended for testing' caveat is carried consciously at O(100)-O(1,000) tracks; Emy CE is the documented upgrade path, not this ticket)"
    if [ -n "$MS" ]; then
      grep -q 'Snapshot(' "$MS" ||
        fail "t13: no Snapshot( call site in $MS — the snapshot is the directory form (source-verified at 17.4.0; 18.0.0 parity is the Post Research focus)"
      grep -qE 'Directory\.Exists|File\.Exists' "$MS" ||
        fail "t13: no existence check before load in $MS — an empty model dir is a WORKING state (auto-capture bootstrap: nothing matched yet); a fatal guard here breaks first boot"
    fi
    grep -rq 'MODEL_DIR' "$SRC" ||
      fail "t13: MODEL_DIR env name absent (default /models)"
    if [ "$fail_count" -eq "$A" ]; then ok "t13: InMemoryModelService directory ctor at startup + Snapshot( call site; empty startup non-fatal; MODEL_DIR present"; fi
  else
    fail "t13: $SRC does not exist (C02a not implemented)"
  fi
fi

# --- t14: IStreamState members + RMS metric + awaited IAdEventSink --------
if want t14; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    ST=$(find_src 'IStreamState')
    [ -n "$ST" ] ||
      fail "t14: IStreamState absent — C02b's capture state machine consumes its no-match span state (LastMatchAt / LastMatchMeta / CurrentRmsDb)"
    if [ -n "$ST" ]; then
      for m in LastMatchAt LastMatchMeta CurrentRmsDb; do
        grep -q "$m" "$ST" || fail "t14: IStreamState member $m missing ($ST)"
      done
    fi
    grep -rq 'aad_audio_rms_db' "$SRC" ||
      fail "t14: the aad_audio_rms_db gauge is missing — RMS is computed per 10,240-sample chunk and exported"
    grep -rq 'IAdEventSink' "$SRC" ||
      fail "t14: IAdEventSink absent — the event seam C03's MQTT sink implements (C01 logs, C03 publishes)"
    grep -rq 'SuccessCallback' "$SRC" ||
      fail "t14: SuccessCallback absent — the awaited callback is the backpressure point (the command awaits the callback's task before the next chunk; R1 implication 2)"
    CB=$(find_src 'SuccessCallback')
    [ -n "$CB" ] || fail "t14: no file with the SuccessCallback call site"
    if [ -n "$CB" ]; then
      grep -q 'await' "$CB" ||
        fail "t14: no await in $CB — the SuccessCallback must be AWAITED (fire-and-forget would drop the backpressure)"
      grep -qi 'sink' "$CB" ||
        fail "t14: no sink reference in $CB — the awaited SuccessCallback must invoke the IAdEventSink"
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t14: IStreamState exposes LastMatchAt/LastMatchMeta/CurrentRmsDb; aad_audio_rms_db exported; IAdEventSink invoked from the awaited SuccessCallback"; fi
  else
    fail "t14: $SRC does not exist (C02a not implemented)"
  fi
fi

# --- t15: capture state machine — ruled defaults + RMS gate + discard ------
if want t15; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    CF=$(find_src 'CAPTURE_MIN_SPAN_SECONDS')
    [ -n "$CF" ] ||
      fail "t15: no config surface with CAPTURE_MIN_SPAN_SECONDS — C02b not implemented"
    if [ -n "$CF" ]; then
      near "$CF" 'CAPTURE_MIN_SPAN_SECONDS' "$CAP_MIN" ||
        fail "t15: no default $CAP_MIN s near CAPTURE_MIN_SPAN_SECONDS (a non-match shorter than a standard 30 s spot is match jitter / gap noise; the 120 s NewOccurrenceAbove ceiling is a seam control, not a span threshold)"
      grep -q 'CAPTURE_MAX_SPAN_SECONDS' "$CF" ||
        fail "t15: CAPTURE_MAX_SPAN_SECONDS missing from the config surface"
      near "$CF" 'CAPTURE_MAX_SPAN_SECONDS' "$CAP_MAX" ||
        fail "t15: no default $CAP_MAX s near CAPTURE_MAX_SPAN_SECONDS (beyond 5 min is an off-air / program boundary, not a spot)"
      grep -q 'CAPTURE_RMS_FLOOR_DB' "$CF" ||
        fail "t15: CAPTURE_RMS_FLOOR_DB missing from the config surface"
      near "$CF" 'CAPTURE_RMS_FLOOR_DB' '45' ||
        fail "t15: no default 45 (dBFS) near CAPTURE_RMS_FLOOR_DB (TV-off / source-off silence sits far below the floor; it must not fill the candidate dir)"
    fi
    CS=$(find_src 'CAPTURE_RMS_FLOOR_DB')
    [ -n "$CS" ] || fail "t15: no capture state machine file found"
    if [ -n "$CS" ]; then
      grep -qE 'IStreamState|CurrentRmsDb' "$CS" ||
        fail "t15: the capture state machine does not consume C02a's IStreamState/CurrentRmsDb"
      grep -qiE 'discard' "$CS" ||
        fail "t15: no discard path — a span that dips below the RMS floor while open is discarded on close, not split"
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t15: capture state machine wired to env knobs with the ruled defaults ($CAP_MIN / $CAP_MAX / $CAP_RMS dBFS); RMS gate consumes IStreamState; below-floor discard present"; fi
  else
    fail "t15: $SRC does not exist (C02b not implemented)"
  fi
fi

# --- t16: ring buffer depth + WAV writer constants + naming scheme --------
if want t16; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    RB=$( { grep -rlEi 'ringbuffer|rollbuffer|\bring\b' "$SRC" 2>/dev/null || true; } | head -n 1 )
    [ -n "$RB" ] ||
      fail "t16: no ring buffer in $SRC — the 5 s pre/post roll cuts from it (the pre-roll covers the <1.5 s MatchedAt edge jitter; R1 §1)"
    if [ -n "$RB" ]; then
      grep -q '5512' "$RB" ||
        fail "t16: the ring buffer file ($RB) has no 5512 — the buffer holds resampled 5512 mono float"
      grep -qE '\b10\b' "$RB" ||
        fail "t16: no 10 s depth constant in the ring buffer file ($RB) — the ruled depth is 10 s (5 pre + 5 post) + margin, ~55,120 floats"
    fi
    WR=$( { grep -rlEi 'wav' "$SRC" 2>/dev/null || true; } | head -n 1 )
    [ -n "$WR" ] || fail "t16: no WAV writer in $SRC (the candidate writer is hand-rolled, no extra package)"
    if [ -n "$WR" ]; then
      grep -q '5512' "$WR" ||
        fail "t16: the WAV writer ($WR) does not pin 5512 Hz"
      grep -qE '\b44\b' "$WR" ||
        fail "t16: no 44-byte header constant in the WAV writer — the candidate WAV is a 44-byte-header, 5512 Hz mono s16le file"
      grep -qiE 's16|16.?bit' "$WR" ||
        fail "t16: no s16 bit-depth marker in the WAV writer"
      grep -qF 's.wav' "$WR" ||
        fail "t16: no 's.wav' suffix in the naming builder (<group>_<UTC-timestamp>_<duration>s.wav)"
      grep -q 'UtcNow' "$WR" ||
        fail "t16: no UtcNow in the naming builder — the timestamp leg is UTC"
      grep -q 'candidates' "$WR" || grep -q 'candidates' "$RB" ||
        fail "t16: no 'candidates' dir reference — candidates land under \$MODEL_DIR/candidates/"
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t16: ring buffer (5512 mono, 10 s + margin); WAV writer (44-byte header, 5512 Hz, mono s16); naming builder <group>_<UTC-timestamp>_<duration>s.wav under MODEL_DIR/candidates"; fi
  else
    fail "t16: $SRC does not exist (C02b not implemented)"
  fi
fi

# --- t17: auto-promotion guardrails (owner override 2026-11-24) -----------
if want t17; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    CF2=$(find_src 'AUTO_PROMOTE_MIN_SIGHTINGS')
    [ -n "$CF2" ] ||
      fail "t17: no config surface with the AUTO_PROMOTE_* guardrails — C02b not implemented (the owner override: auto-promote on recurrence, guardrails as env config)"
    if [ -n "$CF2" ]; then
      near "$CF2" 'AUTO_PROMOTE_MIN_SIGHTINGS' "$AP_SIG" ||
        fail "t17: no default $AP_SIG near AUTO_PROMOTE_MIN_SIGHTINGS (repetition across episodes/pods is the ad signal; a single sighting NEVER promotes)"
      near "$CF2" 'AUTO_PROMOTE_MIN_GAP_HOURS' "$AP_GAP" ||
        fail "t17: no default $AP_GAP h near AUTO_PROMOTE_MIN_GAP_HOURS (qualifying sightings must be >=24 h apart — cross-episode repetition, not back-to-back re-runs)"
      near "$CF2" 'AUTO_PROMOTE_MAX_PER_DAY' "$AP_CAP" ||
        fail "t17: no default $AP_CAP near AUTO_PROMOTE_MAX_PER_DAY (the per-day cap bounds drift-feeding)"
    fi
    AP=$( { grep -rlE 'AutoPromote' "$SRC" 2>/dev/null || true; } | head -n 1 )
    [ -n "$AP" ] || AP=$( { grep -rl 'aad_auto_promotions_capped_total' "$SRC" 2>/dev/null || true; } | head -n 1 )
    [ -n "$AP" ] || fail "t17: no auto-promotion logic file found"
    if [ -n "$AP" ]; then
      grep -qE '>=\s*2\b|>\s*1\b|MinSightings' "$AP" ||
        fail "t17: no no-single-sighting guard in $AP — the insert path must be unreachable with one sighting (the recurrence gate is the only door into the insert)"
      if ! grep -qiE 'dedup|deduplicate|proximit' "$AP"; then
        grep -rqEi 'dedup|deduplicate|proximit' "$SRC" ||
          fail "t17: no fingerprint-proximity dedup in the auto path or a shared helper — a known ad re-airing is not a new one (dedup vs the existing catalogue AND previously promoted candidates, before insert)"
      fi
      grep -q 'Snapshot(' "$AP" ||
        fail "t17: no Snapshot( after the auto-promote insert in $AP"
      grep -q 'auto_promoted' "$AP" ||
        fail "t17: no 'auto_promoted' meta flag on the auto path in $AP (the flag + list/prune is what keeps the human in the loop after the fact)"
      grep -qE '\bad\b' "$AP" ||
        fail "t17: no kind=ad marker on the auto insert in $AP"
    fi
    grep -rq 'aad_auto_promotions_capped_total' "$SRC" ||
      fail "t17: aad_auto_promotions_capped_total absent — a cap-hit skip must count (per-day cap $AP_CAP)"
    if [ "$fail_count" -eq "$A" ]; then ok "t17: auto-promotion guardrails wired to env ($AP_SIG sightings / $AP_GAP h gap / $AP_CAP per day); no-single-sighting guard; proximity dedup; auto_promoted flag + kind=ad + Snapshot after insert; capped counter present"; fi
  else
    fail "t17: $SRC does not exist (C02b not implemented)"
  fi
fi

# --- t18: manual promote lane (stays — single-shot / owner-dropped files) --
if want t18; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    PROM=$( { grep -rlF -- '--dir' "$SRC" 2>/dev/null || true; } | head -n 1 )
    [ -n "$PROM" ] ||
      fail "t18: no manual promote lane in $SRC (no '--dir' subcommand) — the manual lane STAYS (curated-dir capability survives as promote --dir)"
    if [ -n "$PROM" ]; then
      grep -qF -- '--file' "$PROM" ||
        fail "t18: no '--file' subcommand in the manual lane ($PROM)"
      grep -q 'FFmpegAudioService' "$PROM" ||
        fail "t18: no FFmpegAudioService — the --dir arbitrary-format path is the R1 §4 canonical insert shape (candidate WAVs decode directly; only --dir pulls FFmpeg)"
      grep -qE '\bad\b' "$PROM" ||
        fail "t18: no kind=ad meta on the manual insert in $PROM"
      if grep -q 'auto_promoted' "$PROM"; then
        fail "t18: 'auto_promoted' in the manual lane ($PROM) — manual origin must NOT carry the flag (the flag marks the auto path for audit)"
      fi
      grep -q 'Snapshot(' "$PROM" ||
        fail "t18: no final Snapshot( in the manual lane ($PROM)"
      if ! grep -qiE 'dedup|deduplicate|proximit' "$PROM"; then
        grep -rqEi 'dedup|deduplicate|proximit' "$SRC" ||
          fail "t18: no dedup guard in the manual lane (skip-if-already-known, before insert)"
      fi
      grep -qE 'ExitCode|return [1-9]' "$PROM" ||
        fail "t18: no non-zero exit path in $PROM — a per-file failure must exit non-zero"
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t18: manual lane — promote --file / --dir (FFmpegAudioService for --dir), kind=ad without auto_promoted, dedup guard, final Snapshot, non-zero exit on failure"; fi
  else
    fail "t18: $SRC does not exist (C02b not implemented)"
  fi
fi

# --- t19: retention 14/200 + trigger sites + list/prune + metrics ---------
if want t19; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    CF3=$(find_src 'CAPTURE_RETENTION_DAYS')
    [ -n "$CF3" ] ||
      fail "t19: no config surface with CAPTURE_RETENTION_DAYS — C02b not implemented"
    if [ -n "$CF3" ]; then
      near "$CF3" 'CAPTURE_RETENTION_DAYS' "$CAP_RET" ||
        fail "t19: no default $CAP_RET days near CAPTURE_RETENTION_DAYS"
      grep -qE "\b$CAP_MAXFILES\b" "$CF3" ||
        fail "t19: no max-$CAP_MAXFILES candidates constant in the config surface ($CF3) — retention is days-or-count, whichever trips first, oldest pruned"
    fi
    grep -rqEi 'timer|periodic|hourly' "$SRC" ||
      fail "t19: no periodic retention trigger — the ruled trigger sites are startup + periodic (e.g. hourly) + on-demand, on a low-priority path (never the hot chunk loop)"
    grep -rqE '"list"' "$SRC" ||
      fail "t19: no 'list' subcommand — the human audit surface (candidates with the auto_promoted flag + auto-promoted tracks)"
    grep -rqE '"prune"' "$SRC" ||
      fail "t19: no 'prune' subcommand — on-demand retention + promoted-track delete"
    grep -rqF -- '--track' "$SRC" ||
      fail "t19: no 'prune --track <name>' — the audit/prune of auto-promoted entries"
    grep -rq 'aad_capture_candidates_total' "$SRC" ||
      fail "t19: aad_capture_candidates_total absent — each candidate write increments it (a failed write is logged, never fatal to the query loop)"
    grep -rq 'aad_auto_promotions_total' "$SRC" ||
      fail "t19: aad_auto_promotions_total absent — each auto-promotion increments it"
    if [ "$fail_count" -eq "$A" ]; then ok "t19: retention $CAP_RET days / max $CAP_MAXFILES with startup + periodic + on-demand triggers; list + prune --track surfaces; capture/auto-promotion counters present"; fi
  else
    fail "t19: $SRC does not exist (C02b not implemented)"
  fi
fi
# --- t20: the retained-leg inventory (property site + non-retained + online + LWT) ---
if want t20; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    MQTT=$(find_src 'Mqtt')
    [ -n "$MQTT" ] ||
      fail "t20: no MQTT publisher file in $SRC — C03 not implemented"
    if [ -n "$MQTT" ]; then
      n_ret=$(grep -cE 'Retained[[:space:]]*=[[:space:]]*true' "$MQTT" || true)
      [ "$n_ret" -eq 1 ] ||
        fail "t20: found $n_ret 'Retained = true' property sites in $MQTT, expected exactly one — the discovery publish is the only retained publish via the property spelling (event/binary/sensor state must never be retained; R4 §3)"
      grep -qF 'homeassistant/device/audio-ad-detector/config' "$MQTT" ||
        fail "t20: the discovery topic is not in $MQTT — the single retain site must be the device-discovery publish"
      n_nonret=$(grep -cE 'retain[[:space:]]*:[[:space:]]*false|Retained[[:space:]]*=[[:space:]]*false|WithRetain\(false\)' "$MQTT" || true)
      [ "$n_nonret" -ge 3 ] ||
        fail "t20: found $n_nonret explicit non-retained publish sites in $MQTT, expected at least 3 — the event / binary / sensor state publishes must each be explicitly non-retained (a retained state message survives the worker's death and keeps serving stale state; R4 §3)"
      n_online=$(grep -cE 'retain[[:space:]]*:[[:space:]]*true' "$MQTT" || true)
      [ "$n_online" -eq 1 ] ||
        fail "t20: found $n_online 'retain: true' named-arg sites in $MQTT, expected exactly one — the only retained availability publish is the connect-time 'online'; any more is a second retained state path"
      grep -qF 'WithWillRetain(true)' "$MQTT" ||
        fail "t20: no WithWillRetain(true) — the LWT's retain is the builder spelling (it must not surface as a 'Retained = true' property site and inflate the single-site count; the LWT is retained + QoS 1 at connect, C03 AC3)"
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t20: retained-leg inventory — exactly one 'Retained = true' property site (the discovery const), 3+ explicit non-retained state publish sites, exactly one retained 'online' availability publish, LWT retain via the builder spelling — event/binary/sensor state publishes never retain (R4 §3)"; fi
  else
    fail "t20: $SRC does not exist (C03 not implemented)"
  fi
fi

# --- t21: LWT + online + reconnect re-publish ------------------------------
if want t21; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    MQTT=$(find_src 'Mqtt')
    [ -n "$MQTT" ] || fail "t21: no MQTT publisher file in $SRC — C03 not implemented"
    if [ -n "$MQTT" ]; then
      grep -q 'offline' "$MQTT" ||
        fail "t21: no 'offline' LWT payload — the LWT (retain, QoS 1) is set at connect on the lwt topic"
      grep -q 'online' "$MQTT" ||
        fail "t21: no 'online' availability publish on connect"
      grep -qiE 'will' "$MQTT" ||
        fail "t21: no LWT (LastWill/WillTopic) setup — entity liveness is LWT + expire_after, NEVER silence-based (R4 §3/§5)"
      grep -qi 'qos' "$MQTT" ||
        fail "t21: no QoS configuration — the LWT is QoS 1 and the event publishes are QoS 1"
      grep -qi 'reconnect' "$MQTT" ||
        fail "t21: no reconnect handling — the discovery payload must be re-published on every connect (a broker restart re-registers the entities)"
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t21: LWT 'offline' (retain, QoS 1) at connect + 'online' publish; discovery re-published on reconnect"; fi
  else
    fail "t21: $SRC does not exist (C03 not implemented)"
  fi
fi

# --- t22: discovery payload matches the R4 shape ---------------------------
if want t22; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    MQTT=$(find_src 'Mqtt')
    [ -n "$MQTT" ] || fail "t22: no MQTT publisher file in $SRC — C03 not implemented"
    for t in 'homeassistant/device/audio-ad-detector/config' 'dev_cla' 'sound' 'evt_typ' 'ad_detected' 'av_t' 'exp_aft' 'ad_playing' 'last_ad' 'ad_event' 'binary_sensor' 'cmps' 'origin' 'uniq_id'; do
      if ! grep -qF -- "$t" "$MQTT" && ! grep -rqF -- "$t" "$SRC"; then
        fail "t22: discovery payload token '$t' missing from the worker source — the R4 shape (2023.8+ event platform) requires it"
      fi
    done
    if [ -n "$MQTT" ] && ! grep -qw 'dev' "$MQTT" && ! grep -qw 'dev' "$SRC"; then
      fail "t22: the 'dev' block (ids/name/mf/mdl/sw) is missing from the discovery payload"
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t22: discovery payload matches the R4 shape — dev + origin + cmps: binary_sensor (dev_cla sound — no 'ad' class exists), sensor, event (evt_typ [ad_detected]); av_t + exp_aft on each component"; fi
  else
    fail "t22: $SRC does not exist (C03 not implemented)"
  fi
fi

# --- t23: no credentials material; optional path is env-var-only ----------
if want t23; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    if grep -rqE 'password[[:space:]]*=[[:space:]]*"[A-Za-z0-9!#$%^&*_-]{4,}"' "$SRC"; then
      fail "t23: a credential literal is assigned in $SRC — verdict (a) renders no credentials material anywhere in this run's tree"
    fi
    if grep -rqEi 'bitwarden|externalsecret|OVERRIDE_VIA|/var/run/secrets' "$SRC"; then
      fail "t23: a secret-plumbing reference (bitwarden / ExternalSecret / OVERRIDE_VIA / mounted secret path) in $SRC — the (c) variant is a recorded one-paragraph fallback, not plumbing built in this run"
    fi
    grep -rq 'MQTT_USERNAME' "$SRC" ||
      fail "t23: MQTT_USERNAME env name absent — the optional credentials code path must be retained (authenticate only when both are set; the recorded fallback (c) costs no code change)"
    grep -rq 'MQTT_PASSWORD' "$SRC" ||
      fail "t23: MQTT_PASSWORD env name absent"
    if [ "$fail_count" -eq "$A" ]; then ok "t23: no credentials material in the worker source; the default connect path is anonymous (verdict (a)), the optional path is env-var-only"; fi
  else
    fail "t23: $SRC does not exist (C03 not implemented)"
  fi
fi

# --- t24: graceful shutdown ordering ---------------------------------------
if want t24; then
  A=$fail_count
  if [ -d "$SRC" ]; then
    SH=$( { grep -rlE 'PosixSignal|SIGTERM' "$SRC" 2>/dev/null || true; } | head -n 1 )
    [ -n "$SH" ] || SH=$( { grep -rlEi 'shutdown' "$SRC" 2>/dev/null || true; } | head -n 1 )
    [ -n "$SH" ] || fail "t24: no shutdown path file in $SRC — C03 not implemented"
    if [ -n "$SH" ]; then
      grep -qE 'Cancel' "$SH" ||
        fail "t24: no query/reader cancellation in $SH — query cancel -> reader stop is the first leg"
      grep -q 'Kill' "$SH" ||
        fail "t24: no child kill in $SH"
      killln=$(line_of "$SH" 'Kill')
      if [ -n "$killln" ]; then
        closeln=$(sed -n "$((killln + 1)),\$p" "$SH" | grep -nE 'Close' | head -n 1 | cut -d: -f1 || true)
        [ -n "$closeln" ] ||
          fail "t24: no pipe/reader close AFTER the child kill in $SH — the child must die BEFORE the pipe read end closes (the SIGPIPE race; R3 implication 7)"
      fi
      grep -q 'Disconnect' "$SH" ||
        fail "t24: no MQTT graceful disconnect in $SH"
      grep -q 'Snapshot(' "$SH" ||
        fail "t24: no Snapshot( at shutdown in $SH — the snapshot-on-exit is the restart-load contract (next boot loads it, no re-fingerprint)"
      grep -qE 'Exit\(0\)|return 0' "$SH" ||
        fail "t24: no exit-0 in $SH — everything must land well inside the 30 s K8s grace"
      snapln=$(line_of "$SH" 'Snapshot\(')
      exitln=$(line_of "$SH" 'Exit\(0\)|return 0')
      if [ -n "$snapln" ] && [ -n "$exitln" ]; then
        [ "$snapln" -lt "$exitln" ] ||
          fail "t24: Snapshot( (line $snapln) must precede exit 0 (line $exitln)"
      fi
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t24: shutdown ordering — query cancel -> reader stop -> child TERM (5 s grace -> SIGKILL) before pipe close -> MQTT disconnect -> Snapshot -> exit 0"; fi
  else
    fail "t24: $SRC does not exist (C03 not implemented)"
  fi
fi

# --- t25: default render is sentinel/ExternalSecret/credential-free --------
if want t25; then
  A=$fail_count
  if ! helm_available; then
    skip "t25: helm not available here; the render arm was not exercised (CI leg stands)"
  elif [ ! -d "$CHART_DIR" ]; then
    fail "t25: $CHART_DIR does not exist (C04 not implemented)"
  elif ! get_render "$RENDER"; then
    tail -n 20 "${RENDER}.err" >&2
    fail "t25: helm template failed — the chart does not render yet (log at ${RENDER}.err)"
  else
    if grep -q 'OVERRIDE_' "$RENDER"; then
      fail "t25: an OVERRIDE_* sentinel in the default render — the chart carries no secrets (verdict (a): no custom-values entry in this run)"
    fi
    if grep -qE 'kind:[[:space:]]*ExternalSecret' "$RENDER"; then
      fail "t25: an ExternalSecret kind in the render — the (c) plumbing is a recorded one-paragraph fallback, not built in this run"
    fi
    if grep -qiE '(password|secret)[[:space:]]*:[[:space:]]*"?[A-Za-z0-9]{8,}' "$RENDER"; then
      fail "t25: credential material in the default render"
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t25: the default render is sentinel-free, ExternalSecret-free, credentials-free"; fi
  fi
fi

# --- t26: Recreate + 1 replica + the three probes, RMS-free ---------------
if want t26; then
  A=$fail_count
  if ! helm_available; then
    skip "t26: helm not available here; the render arm was not exercised (CI leg stands)"
  elif [ ! -d "$CHART_DIR" ]; then
    fail "t26: $CHART_DIR does not exist (C04 not implemented)"
  elif ! get_render "$RENDER"; then
    tail -n 20 "${RENDER}.err" >&2
    fail "t26: helm template failed (log at ${RENDER}.err)"
  else
    grep -q 'Recreate' "$RENDER" ||
      fail "t26: no Recreate strategy in the render (the values schema rejects invalid strategies; the ruled shape is the string Recreate)"
    grep -qE 'replicas:[[:space:]]*1' "$RENDER" ||
      fail "t26: replicas is not 1 in the render"
    for p in startupProbe livenessProbe readinessProbe; do
      grep -q "$p" "$RENDER" || fail "t26: no $p in the render (startup must be generous — model load + first connection)"
    done
    grep -q 'httpGet' "$RENDER" ||
      fail "t26: no httpGet probes in the render"
    grep -qF '/healthz' "$RENDER" ||
      fail "t26: no /healthz (the liveness endpoint — process health only) in the render"
    grep -qF '/readyz' "$RENDER" ||
      fail "t26: no /readyz (the readiness endpoint) in the render"
    probes=$(extract_probe_blocks "$RENDER")
    if printf '%s\n' "$probes" | grep -qi 'rms'; then
      fail "t26: RMS appears in a probe definition — liveness/readiness must never be on audio silence (the LWT + expire_after model owns liveness; R4 §3/§5)"
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t26: Recreate + replicas 1 + startup/liveness/readiness probes with httpGet /healthz + /readyz; no RMS in any probe block"; fi
  fi
fi

# --- t27: D-8 annotation pair — on by default, inert when gated off -------
if want t27; then
  A=$fail_count
  if ! helm_available; then
    skip "t27: helm not available here; the render arm was not exercised (CI leg stands)"
  elif [ ! -d "$CHART_DIR" ]; then
    fail "t27: $CHART_DIR does not exist (C04 not implemented)"
  elif ! get_render "$RENDER"; then
    tail -n 20 "${RENDER}.err" >&2
    fail "t27: helm template failed (log at ${RENDER}.err)"
  elif ! get_render "$RENDER_OFF" --set monitoring.annotations=false; then
    tail -n 20 "${RENDER_OFF}.err" >&2
    fail "t27: helm template --set monitoring.annotations=false failed (log at ${RENDER_OFF}.err)"
  else
    grep -qE 'k8s\.grafana\.com/scrape[[:space:]]*:[[:space:]]*"?true"?' "$RENDER" ||
      fail "t27: k8s.grafana.com/scrape does not render 'true' by default — the D-8 pair (the charts/vllm idiom) is on by default"
    grep -qE 'k8s\.grafana\.com/metrics\.portNumber[[:space:]]*:[[:space:]]*"?8080"?' "$RENDER" ||
      fail "t27: k8s.grafana.com/metrics.portNumber does not render 8080 by default (the health/metrics port)"
    grep -qE 'k8s\.grafana\.com/scrape[[:space:]]*:[[:space:]]*""' "$RENDER_OFF" ||
      fail "t27: gate-off render: k8s.grafana.com/scrape is not empty — the vllm D8 behavior keeps the keys with inert (empty) values when the gate is off; an empty value is what disables the scrape"
    grep -qE 'k8s\.grafana\.com/metrics\.portNumber[[:space:]]*:[[:space:]]*""' "$RENDER_OFF" ||
      fail "t27: gate-off render: metrics.portNumber is not empty"
    if [ "$fail_count" -eq "$A" ]; then ok "t27: D-8 pair renders scrape=true + portNumber=8080 by default; gate-off renders the inert empty-value shape"; fi
  fi
fi

# --- t28: no Ingress; ClusterIP service; pod security; PVC ----------------
if want t28; then
  A=$fail_count
  if ! helm_available; then
    skip "t28: helm not available here; the render arm was not exercised (CI leg stands)"
  elif [ ! -d "$CHART_DIR" ]; then
    fail "t28: $CHART_DIR does not exist (C04 not implemented)"
  elif ! get_render "$RENDER"; then
    tail -n 20 "${RENDER}.err" >&2
    fail "t28: helm template failed (log at ${RENDER}.err)"
  else
    if grep -qE 'kind:[[:space:]]*(Ingress|IngressRoute)' "$RENDER"; then
      fail "t28: an Ingress/IngressRoute object in the render — the proxy leg is N/A by design (the headless worker has no UI; the dev-mosquitto precedent: 'N/A by design, not an oversight')"
    fi
    grep -q 'kind: Service' "$RENDER" ||
      fail "t28: no Service object in the render"
    if grep -qE 'type:[[:space:]]*(LoadBalancer|NodePort)' "$RENDER"; then
      fail "t28: a LoadBalancer/NodePort service type in the render — the service is ClusterIP-only (headless)"
    fi
    grep -q 'ClusterIP' "$RENDER" ||
      fail "t28: no ClusterIP in the render"
    grep -qE 'port:[[:space:]]*8080' "$RENDER" ||
      fail "t28: no 8080 port in the render (the health/metrics port also serves /metrics)"
    grep -qE 'name:[[:space:]]*health([[:space:]]|$)' "$RENDER" ||
      fail "t28: no 'health' port name in the render"
    grep -qE 'runAsUser:[[:space:]]*65532' "$RENDER" ||
      fail "t28: no runAsUser: 65532 in the render (the nonroot uid the Dockerfile creates)"
    grep -qE 'runAsNonRoot:[[:space:]]*true' "$RENDER" ||
      fail "t28: no runAsNonRoot: true in the render"
    grep -qE 'allowPrivilegeEscalation:[[:space:]]*false' "$RENDER" ||
      fail "t28: no allowPrivilegeEscalation: false in the render"
    grep -qE 'readOnlyRootFilesystem:[[:space:]]*true' "$RENDER" ||
      fail "t28: no readOnlyRootFilesystem: true in the render (the writable set is mounted, not the root fs)"
    grep -q 'ALL' "$RENDER" ||
      fail "t28: no dropped 'ALL' capabilities in the render"
    grep -q 'emptyDir' "$RENDER" ||
      fail "t28: no emptyDir mounts in the render (the writable set: /tmp + the non-root \$HOME)"
    grep -q 'mountPath: /tmp' "$RENDER" ||
      fail "t28: no /tmp mount in the render"
    grep -q 'size: 10Gi' "$RENDER" ||
      fail "t28: no 10Gi PVC in the render (model snapshot + candidate budget: model + <=2 Gi candidates)"
    grep -q 'ReadWriteOnce' "$RENDER" ||
      fail "t28: no ReadWriteOnce access mode in the render"
    grep -q 'mountPath: /models' "$RENDER" ||
      fail "t28: no /models mount in the render (the model dir + candidate dir must survive pod recreation)"
    if [ "$fail_count" -eq "$A" ]; then ok "t28: no Ingress; ClusterIP service (health port 8080); pod security (65532, nonRoot, noPrivEsc, drop ALL, readOnlyRootFilesystem, emptyDir /tmp + \$HOME); 10Gi RWO PVC at /models"; fi
  fi
fi

# --- t29: services wiring + Chart.yaml pins + the TBD-owner placeholder ---
if want t29; then
  A=$fail_count
  [ -f "$SERVICES_HOME" ] || fail "t29: $SERVICES_HOME does not exist"
  if [ -f "$SERVICES_HOME" ]; then
    if ! grep -qE '^  audio-ad-detection:[[:space:]]*$' "$SERVICES_HOME"; then
      fail "t29: no 'audio-ad-detection:' charts: entry in $SERVICES_HOME (variant (a): key = chart name, no chart: field, no Chart.lock regen)"
    else
      block=$(awk '
        /^  audio-ad-detection:[[:space:]]*$/ { f = 1; next }
        f && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { exit }
        f && /^[^[:space:]#]/ { exit }
        f { print }
      ' "$SERVICES_HOME")
      [ -n "$block" ] || fail "t29: the audio-ad-detection charts: entry block is empty"
      for t in '#version:' '# renovate: datasource=helm' '#repository:' 'namespace: default' 'ServerSideApply: "true"'; do
        printf '%s\n' "$block" | grep -qF "$t" ||
          fail "t29: the charts: entry lacks '$t' (the existing entries' shape)"
      done
    fi
    ingress_block=$(awk '
      /^ingress:[[:space:]]*$/ { f = 1; next }
      f { if (/^[^[:space:]#]/) exit; print }
    ' "$SERVICES_HOME")
    if printf '%s\n' "$ingress_block" | grep -q 'audio-ad-detection'; then
      fail "t29: an ingress subdomains entry for audio-ad-detection — the proxy leg is N/A by design (no UI)"
    fi
    [ -f "$CUSTOM_VALUES" ] || fail "t29: $CUSTOM_VALUES does not exist"
    if [ -f "$CUSTOM_VALUES" ] && grep -q 'audio-ad-detection' "$CUSTOM_VALUES"; then
      fail "t29: a custom-values entry for audio-ad-detection — verdict (a) renders no entry in this run (the (c) variant is the recorded fallback, not plumbing)"
    fi
    [ -f "$CHART_YAML" ] || fail "t29: $CHART_YAML does not exist (C04 not implemented)"
    if [ -f "$CHART_YAML" ]; then
      grep -qE '^apiVersion:[[:space:]]*v2' "$CHART_YAML" ||
        fail "t29: Chart.yaml apiVersion is not v2"
      grep -qE '^name:[[:space:]]*audio-ad-detection' "$CHART_YAML" ||
        fail "t29: Chart.yaml name is not audio-ad-detection"
      grep -qE '^version:[[:space:]]*1\.0\.0' "$CHART_YAML" ||
        fail "t29: Chart.yaml version is not 1.0.0 (brand-new chart — the one-time 1.0.0; never hand-bump after)"
      grep -qE 'app-template' "$CHART_YAML" ||
        fail "t29: no app-template dependency in Chart.yaml"
      grep -qE '5\.0\.1' "$CHART_YAML" ||
        fail "t29: the app-template dependency is not 5.0.1 (repo standard, verified across all 55 charts)"
      grep -qF 'https://bjw-s-labs.github.io/helm-charts/' "$CHART_YAML" ||
        fail "t29: the app-template repository is not https://bjw-s-labs.github.io/helm-charts/"
    fi
    [ -f "$CHART_VALUES" ] || fail "t29: $CHART_VALUES does not exist (C04 not implemented)"
    if [ -f "$CHART_VALUES" ]; then
      grep -qF 'SNAP_STREAM_ID: "TBD-owner"' "$CHART_VALUES" ||
        fail "t29: the SNAP_STREAM_ID: \"TBD-owner\" documented placeholder is missing from the chart values (Q2: required value, family-TV group, name not yet supplied)"
      ln=$(line_of "$CHART_VALUES" 'SNAP_STREAM_ID')
      if [ -n "$ln" ]; then
        sed -n "$((ln > 3 ? ln - 3 : 1)),$ln p" "$CHART_VALUES" | grep -qi 'required' ||
          fail "t29: no required-value comment within 3 lines above SNAP_STREAM_ID — the documented placeholder must be documented"
      fi
    fi
    if [ "$fail_count" -eq "$A" ]; then ok "t29: charts: entry in the existing shape; no ingress subdomain; no custom-values entry (verdict (a)); Chart.yaml (v2, 1.0.0, app-template 5.0.1); TBD-owner placeholder with its required-value comment"; fi
  fi
fi

# --- t30: whole-plan validation re-entry (single command for final review) -
if want t30; then
  A=$fail_count
  if [ -n "${AAD_REENTER:-}" ]; then
    # The child re-entry run: this arm IS the child's t1..t29 report, so the
    # arm must not re-recurse (the AAD_REENTER guard breaks the cycle).
    skip "t30: child re-entry run — the whole-plan arm is the child's t1..t29 report"
  else
    rc=0
    if helm_available; then
      if [ -d "$CHART_DIR" ]; then
        if ! helm lint "$CHART_DIR" >"$TMP/aad-lint.log" 2>&1; then
          rc=1
          tail -n 15 "$TMP/aad-lint.log" >&2
        fi
      fi
    fi
    if ! AAD_REENTER=1 bash "$0" >"$TMP/aad-reenter.log" 2>&1; then
      rc=1
      tail -n 25 "$TMP/aad-reenter.log" >&2
    fi
    if [ "$rc" -eq 0 ]; then
      if [ "$fail_count" -eq "$A" ]; then ok "t30: the whole-plan validation arm is green (helm lint + the t1..t29 re-run)"; fi
    else
      fail "t30: the whole-plan validation arm is not green (helm lint or the t1..t29 re-run failed; log at $TMP/aad-reenter.log)"
    fi
  fi
fi

# --- t31: the ruled defaults are pinned in this script (drift reddens) ----
if want t31; then
  A=$fail_count
  [ -f "$C05" ] ||
    fail "t31: the plan of record ($C05) is missing — the pin has nothing to pin against"
  if [ -f "$C05" ]; then
    # Script-side pin: every constant this suite consumes must equal the
    # plan's ruled value. If a later edit moves a constant (to "fix" a red
    # arm, or because the plan changed), this test goes red first.
    [ "$RT_OCA" = "120" ] || fail "t31: the script-pinned NEW_OCCURRENCE_ABOVE default drifted to $RT_OCA (the plan rules 120)"
    [ "$RT_COV" = "5" ] || fail "t31: the script-pinned COVERAGE_SECONDS default drifted to $RT_COV (the plan rules 5)"
    [ "$RT_STALE" = "120" ] || fail "t31: the script-pinned staleness-ceiling default drifted to $RT_STALE (the plan rules 120)"
    [ "$CAP_MIN" = "30" ] || fail "t31: the script-pinned CAPTURE_MIN_SPAN_SECONDS default drifted to $CAP_MIN (the plan rules 30)"
    [ "$CAP_MAX" = "300" ] || fail "t31: the script-pinned CAPTURE_MAX_SPAN_SECONDS default drifted to $CAP_MAX (the plan rules 300)"
    [ "$CAP_RMS" = "-45" ] || fail "t31: the script-pinned CAPTURE_RMS_FLOOR_DB default drifted to $CAP_RMS (the plan rules -45)"
    [ "$CAP_RET" = "14" ] || fail "t31: the script-pinned CAPTURE_RETENTION_DAYS default drifted to $CAP_RET (the plan rules 14)"
    [ "$CAP_MAXFILES" = "200" ] || fail "t31: the script-pinned max-candidates default drifted to $CAP_MAXFILES (the plan rules 200)"
    [ "$AP_SIG" = "2" ] || fail "t31: the script-pinned AUTO_PROMOTE_MIN_SIGHTINGS default drifted to $AP_SIG (the plan rules 2)"
    [ "$AP_GAP" = "24" ] || fail "t31: the script-pinned AUTO_PROMOTE_MIN_GAP_HOURS default drifted to $AP_GAP (the plan rules 24)"
    [ "$AP_CAP" = "20" ] || fail "t31: the script-pinned AUTO_PROMOTE_MAX_PER_DAY default drifted to $AP_CAP (the plan rules 20)"
    # Plan-side pin: the plan of record must still carry the values it ruled.
    # The plan text writes the RMS floor with a U+2212 minus (match both) and
    # wraps long lines — "20 per day" straddles two of them — so grep the
    # line-flattened text, not the raw file.
    C05J=$(tr '\n' ' ' < "$C05" | tr -s ' ')
    printf '%s' "$C05J" | grep -qF "$RT_OCA / $RT_COV / $RT_STALE" ||
      fail "t31: C05.md no longer carries the realtime defaults '$RT_OCA / $RT_COV / $RT_STALE' (120 / 5 / 120)"
    printf '%s' "$C05J" | grep -qF "$CAP_MIN s / $CAP_MAX s" ||
      fail "t31: C05.md no longer carries the capture span pair '$CAP_MIN s / $CAP_MAX s' (30 s / 300 s)"
    printf '%s' "$C05J" | grep -qE '(-|−)45[[:space:]]*dBFS' ||
      fail "t31: C05.md no longer carries the RMS floor -45 dBFS"
    printf '%s' "$C05J" | grep -qF "$CAP_RET days" ||
      fail "t31: C05.md no longer carries the retention default '$CAP_RET days' (14 days)"
    printf '%s' "$C05J" | grep -qF "$CAP_MAXFILES candidates" ||
      fail "t31: C05.md no longer carries the max-candidates default '$CAP_MAXFILES candidates' (200 candidates)"
    printf '%s' "$C05J" | grep -qF "$AP_SIG sightings" ||
      fail "t31: C05.md no longer carries the min-sightings default '$AP_SIG sightings' (2 sightings)"
    printf '%s' "$C05J" | grep -qF "$AP_GAP h gap" ||
      fail "t31: C05.md no longer carries the gap default '$AP_GAP h gap' (24 h gap)"
    printf '%s' "$C05J" | grep -qF "$AP_CAP per day" ||
      fail "t31: C05.md no longer carries the per-day cap '$AP_CAP per day' (20 per day)"
    if [ "$fail_count" -eq "$A" ]; then ok "t31: the ruled defaults (120/5/120, 30/300/-45/14/200, 2/24h/20) are pinned in this script and still carried by the plan of record"; fi
  fi
fi

# --- summary ---------------------------------------------------------------
printf '\n'
if [ "$fail_count" -eq 0 ]; then
  printf 'PASS: audio-ad-detection contract checks (%d ok, %d skipped)\n' "$ok_count" "$skip_count"
  exit 0
else
  printf 'FAIL: audio-ad-detection contract checks (%d ok, %d failed, %d skipped)\n' "$ok_count" "$fail_count" "$skip_count"
  exit 1
fi
