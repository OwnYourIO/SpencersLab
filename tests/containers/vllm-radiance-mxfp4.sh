#!/usr/bin/env bash
# vllm-radiance-mxfp4 container contract (2026/2026-11-cf-131-feat-vllm-fp8-
# official, C01): the THIN digest-pinned re-export of the 0.30 Radiance stack
# (magiccodingman/vllm-radiance:1.0.397 @ sha256:b73bf3e4...) under the repo's
# docker-build.yaml first-build law, plus the ledger README (tag→pin table,
# tag↔commit release-branch watch, manual-bump procedure, interface contract).
# The image is a self-contained terminal build (RESEARCH R3 L1.2) — the
# re-export adds NOTHING (no COPY/RUN/ENV/USER), which is why the thinness
# leg (t2) exists: a future COPY would silently fork the pinned stack.
# Contract source: chunks/C01.md Tasks + AC1-AC3 (the chart-side test_ac7
# re-pin and the retirement scan live in charts/vllm/tests/test_contract.py).
#
# The pin is a MANUAL ledger by the D12-amended law: zero auto-update
# directives anywhere in the container dir — the upstream publishes are
# release-branch-only 1.0.<n>/sha-… pairs, which no datasource tracks; t5
# counts case-insensitive "renovate" lines and requires ZERO, so the README
# note must phrase the law WITHOUT the literal word (say "auto-update
# directives" — same trap the retired overlay's suite recorded).
#
# docker build is CI-primary (no docker daemon in agent sessions): the suite
# never builds. t6 is network-gated — SKIP with warning on no egress; an HTTP
# error (e.g. 404 for the tag) or a live/ledger digest mismatch is a FAIL,
# naming both values (a digest drift = stop + flag, the C01 note).
#
# Run from the repo root:
#   bash tests/containers/vllm-radiance-mxfp4.sh          # t1..t6
#   bash tests/containers/vllm-radiance-mxfp4.sh t1 t2    # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

DIR="containers/vllm-radiance-mxfp4"
DF="$DIR/Dockerfile"
README="$DIR/README.md"
IMAGE="magiccodingman/vllm-radiance"
TAG="1.0.397"
DIGEST="sha256:b73bf3e41bc0a1cf7aaa5935bebe31123f549639e69b61a3ffa81acd5f7313e0"
SRC_COMMIT="5b99d66c844fd0a54e4a7eb93b40a1ece009a53d"
HUB_URL="https://hub.docker.com/v2/repositories/${IMAGE}/tags/${TAG}"

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
  for i in $(seq 1 6); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-6]$ ]] || fail "unknown test id '$a' (expected t1..t6)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

WORK=$(mktemp -d /tmp/opencode/vllm-radiance-mxfp4.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

# Full sha256 digests recorded in the Dockerfile (FROM pin or ledger comment)
# and in the README (ledger table); t3 pairs the two, t6 checks the live
# registry against the ledger.
df_digests() {
  [ -f "$DF" ] && grep -oE 'sha256:[0-9a-f]{64}' "$DF" | sort -u || true
}
rd_digests() {
  [ -f "$README" ] && grep -oE 'sha256:[0-9a-f]{64}' "$README" | sort -u || true
}

hub_digest() {
  python3 - "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1])).get("digest")
except (ValueError, OSError):
    d = None
print(d or "UNPARSEABLE")
PY
}

# --- t1: the FROM pin is the exact tag + full digest --------------------------
if want t1; then
  if [ ! -f "$DF" ]; then
    fail "t1: $DF missing — C01 (the thin radiance re-export overlay) is not implemented"
  fi
  if ! grep -Eq "^FROM[[:space:]]+docker\.io/${IMAGE}:${TAG}@${DIGEST}([[:space:]]|$)" "$DF"; then
    fail "t1: no FROM line pinning docker.io/${IMAGE}:${TAG}@${DIGEST} exactly (C01 AC1 — the tag+digest form IS the pin law, D23)"
  fi
  ok "t1: the Dockerfile FROM-pins ${IMAGE}:${TAG}@${DIGEST:0:19}…"
fi

# --- t2: the re-export law — only FROM + EXPOSE, port 8000 recorded -----------
if want t2; then
  [ -f "$DF" ] || fail "t2: $DF missing (see t1)"
  if ! grep -Eq "^EXPOSE[[:space:]]+8000([[:space:]]|$)" "$DF"; then
    fail "t2: no EXPOSE 8000 record line (serve = health = metrics; the upstream declares no ports, the record is ours — C01 AC1)"
  fi
  offenders=$(grep -vE '^[[:space:]]*(#|$)' "$DF" | grep -vE '^(FROM|EXPOSE)([[:space:]]|$)' || true)
  if [ -n "$offenders" ]; then
    fail "t2: the re-export law allows only FROM + EXPOSE instructions, got: $(printf '%s' "$offenders" | tr '\n' ';') — the 0.30 image is a self-contained terminal build (R3 L1.2), any COPY/RUN/ENV/USER forks the pinned stack"
  fi
  ok "t2: the Dockerfile is thin — FROM + EXPOSE only, no COPY/RUN/ENV/USER"
fi

# --- t3: the ledger is full and paired, both surfaces carry the record --------
if want t3; then
  [ -f "$DF" ] || fail "t3: $DF missing (see t1)"
  [ -f "$README" ] || fail "t3: $README missing — the tag→digest ledger (C01 task 2) is not implemented"
  df_digests > "$WORK/df.dg"
  rd_digests > "$WORK/rd.dg"
  [ -s "$WORK/rd.dg" ] || fail "t3: the README ledger carries no full sha256:<64-hex> digest (C01 AC2)"
  [ -s "$WORK/df.dg" ] || fail "t3: the Dockerfile carries no full sha256 digest (the FROM pin itself qualifies)"
  comm -12 "$WORK/df.dg" "$WORK/rd.dg" | grep -q . \
    || fail "t3: no full digest is shared between the Dockerfile and the README ledger — the tag↔digest pairing is inconsistent"
  # The identities the ledger comment + table must name (C01 AC2): source
  # commit, engine tag-commit, the sha-sibling tag, size and push date.
  for token in "${SRC_COMMIT}" "ced6857a" "4,079,863,554" "2026-10-18" "0.30.0"; do
    grep -qF "$token" "$DF" || fail "t3: the Dockerfile ledger comment lacks the identity token '$token' (C01 AC2)"
  done
  for token in "$TAG" "sha-5b99d66c844f" "5b99d66c" "ced6857a" "0.30.0"; do
    grep -qF "$token" "$README" || fail "t3: the README ledger lacks the pin token '$token' (C01 AC2 — the tag→pin table)"
  done
  ok "t3: the ledger digests pair across the two surfaces and both name the source commit / engine identity"
fi

# --- t4: the README carries the law + the interface contract -------------------
if want t4; then
  [ -f "$README" ] || fail "t4: $README missing (see t3)"
  grep -qiE 'release[- ]branch' "$README" \
    || fail "t4: no release-branch watch line — publishes are release-branch-only, the next 1.0.<n>/sha pair is the bump trigger, NOT main movement (R3 conflict #4, C01 AC2)"
  grep -qiE 'bump' "$README" \
    || fail "t4: the watch line never names the bump trigger (C01 AC2)"
  grep -qF 'hub.docker.com' "$README" && grep -qiE 'manifest' "$README" && grep -qiE 're-?bench' "$README" \
    || fail "t4: the manual-bump procedure (Hub tags API curl + registry manifest probe + on-target re-bench) is incomplete (C01 AC2)"
  grep -qF 'org.opencontainers.image.revision' "$README" \
    || fail "t4: the bump procedure must name the config-blob OCI revision label read (the fourth corroboration, R3 L1.1)"
  grep -qF '/opt/radiance_entrypoint.sh' "$README" \
    || fail "t4: the interface contract does not name the entrypoint (C01 AC3)"
  tr '\n' ' ' < "$README" | grep -qiE 'exec[[:space:]]+vllm[[:space:]]+serve' \
    || fail "t4: the interface contract omits the exec-vllm-serve entrypoint form — the pod args START WITH THE MODEL PATH only if this record exists (R3 L1.3, C01 AC3)"
  tr '\n' ' ' < "$README" | grep -qiE 'args[[:space:]]+start[[:space:]]+with[[:space:]]+the[[:space:]]+model[[:space:]]+path' \
    || fail "t4: the args-start-with-the-model-path law is not stated (C01 AC3)"
  for token in '/models' '/cache' 'AITER' 'RADIANCE_'; do
    grep -qF "$token" "$README" || fail "t4: the interface contract is missing '$token' (C01 AC3)"
  done
  grep -qiE 'chat[- ]template' "$README" \
    || fail "t4: the chat-template absence (checkpoint-native default at 0.30) is not recorded (C01 AC3)"
  grep -qiE 'root' "$README" \
    || fail "t4: the root posture is not recorded (C01 AC3)"
  ok "t4: the README carries the release-branch watch, the three-step manual bump, and the interface contract (entrypoint / model-path args / mounts / root / AITER / no chat template)"
fi

# --- t5: zero auto-update directives — the manual-ledger law (D12-amended) ----
if want t5; then
  [ -d "$DIR" ] || fail "t5: $DIR missing — C01 is not implemented"
  mapfile -t hits < <(grep -rin 'renovate' "$DIR" 2>/dev/null || true)
  if [ "${#hits[@]}" -ne 0 ]; then
    got=$(printf '%s; ' "${hits[@]}")
    fail "t5: 'grep -ri renovate $DIR/' returns ${#hits[@]} hits, want ZERO — the release-branch sha-pair publishes are a manual ledger (D12-amended); the README note must say 'auto-update directives' without the literal word (got: ${got})"
  fi
  ok "t5: no auto-update directive lines in the container dir — the manual-ledger contract holds"
fi

# --- t6 (network-gated): the live registry equals the ledger -------------------
if want t6; then
  [ -f "$README" ] || fail "t6: $README missing — the ledger to verify against is not implemented (see t3)"
  rd_digests > "$WORK/rd.dg"
  [ -s "$WORK/rd.dg" ] || fail "t6: no ledger digest to verify against (see t3)"
  if curl -fsS --max-time 30 "$HUB_URL" -o "$WORK/hub-tag.json" 2> "$WORK/hub-err"; then
    live=$(hub_digest "$WORK/hub-tag.json" 2>/dev/null) || live="UNPARSEABLE"
    if [ "$live" = "UNPARSEABLE" ]; then
      head -c 200 "$WORK/hub-tag.json" >&2 || true
      fail "t6: the Docker Hub tags API answered for ${TAG} but the response carries no usable digest (body above) — the ledger pins $(tr '\n' ' ' < "$WORK/rd.dg")"
    fi
    grep -qxF "$live" "$WORK/rd.dg" \
      || fail "t6: digest mismatch — the ledger pins $(tr '\n' ' ' < "$WORK/rd.dg") but ${IMAGE}:${TAG} now resolves to ${live} (re-verify and re-record the ledger; never ship a drifted pin — C01 note)"
    ok "t6: the live Docker Hub digest for ${TAG} equals the ledger digest (${live})"
  elif grep -qiE 'HTTP error|404|not found' "$WORK/hub-err"; then
    fail "t6: the Docker Hub tags API answered an HTTP error for ${TAG} — the pinned tag must exist ($(head -1 "$WORK/hub-err"))"
  else
    skip "t6: no egress to hub.docker.com ($(head -1 "$WORK/hub-err" 2>/dev/null || echo 'network unreachable')) — the live digest re-verification was not run (the CI build is the authority)"
  fi
  # The OCI revision-label corroboration (R3 L1.1): anonymous pull token →
  # manifest (index child for amd64/linux) → config blob → label. A
  # transport/shape failure SKIPS with warning; a resolvable label that
  # disagrees with the ledger FAILs (the pin's fourth source drifted).
  out=$(python3 - "$SRC_COMMIT" "$TAG" <<'PY' || true
import json, sys, urllib.error, urllib.request

want_rev, tag = sys.argv[1], sys.argv[2]
BASE = "https://registry-1.docker.io/v2/magiccodingman/vllm-radiance"
MANIFEST_ACCEPT = ("application/vnd.oci.image.index.v1+json,"
                   "application/vnd.docker.distribution.manifest.list.v2+json,"
                   "application/vnd.oci.image.manifest.v1+json,"
                   "application/vnd.docker.distribution.manifest.v2+json")

def get(url, accept=None, token=None):
    headers = {}
    if accept:
        headers["Accept"] = accept
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    return json.load(urllib.request.urlopen(req, timeout=30))

try:
    tok = get("https://auth.docker.io/token?service=registry.docker.io"
              "&scope=repository:magiccodingman/vllm-radiance:pull")["token"]
    m = get(f"{BASE}/manifests/{tag}", MANIFEST_ACCEPT, tok)
    if "manifests" in m:
        child = next((x for x in m["manifests"]
                      if x.get("platform", {}).get("architecture") == "amd64"
                      and x.get("platform", {}).get("os") == "linux"), None)
        if child is None:
            print("SKIP no amd64/linux child in the index"); sys.exit(0)
        m = get(f"{BASE}/manifests/{child['digest']}",
                "application/vnd.oci.image.manifest.v1+json,"
                "application/vnd.docker.distribution.manifest.v2+json", tok)
    cfg = m["config"]["digest"]
    c = get(f"{BASE}/blobs/{cfg}", None, tok)
    labels = (c.get("config") or {}).get("Labels") or c.get("labels") or {}
    rev = labels.get("org.opencontainers.image.revision", "")
    if not rev:
        print("SKIP config blob carries no OCI revision label (shape drift)"); sys.exit(0)
    if rev != want_rev:
        print(f"MISMATCH label is {rev}, ledger records {want_rev}"); sys.exit(2)
    print(f"MATCH {rev}")
except (urllib.error.URLError, OSError, KeyError, ValueError, json.JSONDecodeError) as ex:
    print(f"SKIP transport/parse: {ex}")
PY
  )
  case "$out" in
    MATCH*) checks=$((checks + 1)); printf 'ok: t6 — the config-blob OCI revision label equals the ledger source commit (%s)\n' "${out#MATCH }";;
    MISMATCH*) fail "t6: ${out#MISMATCH } — the four-source pin corroboration disagrees (stop + flag, C01 note)";;
    SKIP*) skip "t6-label: ${out#SKIP } — the OCI revision cross-check was not run";;
    *) skip "t6-label: the probe produced no verdict ($out) — the OCI revision cross-check was not run";;
  esac
fi

printf 'PASS: vllm-radiance-mxfp4 container contract checks (%d ok)\n' "$checks"
