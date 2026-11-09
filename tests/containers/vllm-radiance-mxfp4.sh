#!/usr/bin/env bash
# vllm-radiance-mxfp4 container contract (2026/2026-11-cf-131-feat-vllm-fp8-
# official, C01): the digest-pinned re-export of the 0.30 Radiance stack
# (magiccodingman/vllm-radiance:1.0.397 @ sha256:b73bf3e4...) plus the ONE
# sanctioned flash-attn pip layer (the D34 amendment — the port of vLLM's
# own official gfx1250 recipe, RESEARCH R5), plus the ledger README (tag→pin
# table, tag↔commit release-branch watch, manual-bump procedure, interface
# contract, FA-layer rider). The image is a self-contained terminal build
# (RESEARCH R3 L1.2) — the re-export adds EXACTLY that layer and nothing
# else, which is why the shape leg (t2) exists: a second RUN/ARG or any
# COPY/ENV/USER silently forks the pinned stack.
# Contract source: chunks/C01.md Tasks + AC1-AC3 + AC6 (the D34 amendment:
# the layer pins live in t7, the README rider legs in t4; the chart-side
# test_ac7 re-pin and the retirement scan live in
# charts/vllm/tests/test_contract.py).
#
# The pin is a MANUAL ledger by the D12-amended law: zero auto-update
# DIRECTIVES anywhere in the container dir — the upstream publishes are
# release-branch-only 1.0.<n>/sha-… pairs and the D34 flash-attn pin sits
# on a `_wip` branch head; neither may be auto-tracked. t5 scans for the
# directive FORM (`renovate:` / `datasource=`) the custom manager actually
# parses and requires ZERO: stating the law in prose is fine (C01's D34
# amendment words the rider that way), only a parseable directive breaks
# the ledger. (History: the retired overlay's suite recorded the
# bare-word trap that made the rider first phrase the law without naming
# the tool — the amendment supersedes that phrasing constraint.)
#
# docker build is CI-primary (no docker daemon in agent sessions): the suite
# never builds. t6 is network-gated — SKIP with warning on no egress; an HTTP
# error (e.g. 404 for the tag) or a live/ledger digest mismatch is a FAIL,
# naming both values (a digest drift = stop + flag, the C01 note). t7's AC6
# import probe is likewise gated: a not-yet-built image reads as the designed
# `no-daemon, CI-deferred` SKIP (cf-77), only contradicting published state
# FAILs.
#
# Run from the repo root:
#   bash tests/containers/vllm-radiance-mxfp4.sh          # t1..t7
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
# The D34 flash-attn layer pins (C01's dated amendment, verbatim per R5.2):
FA_REPO_URL="https://github.com/jpvillam-amd/flash-attention.git"
FA_REF="aa743c5933560d097d8aa5e833ca10153ed7f6bb"

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
  for i in $(seq 1 7); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-7]$ ]] || fail "unknown test id '$a' (expected t1..t7)"
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

# --- t2: the re-export law — FROM + the ONE sanctioned FA layer + EXPOSE ------
if want t2; then
  [ -f "$DF" ] || fail "t2: $DF missing (see t1)"
  if ! grep -Eq "^EXPOSE[[:space:]]+8000([[:space:]]|$)" "$DF"; then
    fail "t2: no EXPOSE 8000 record line (serve = health = metrics; the upstream declares no ports, the record is ours — C01 AC1)"
  fi
  # The D34 amendment grew the shape law from FROM+EXPOSE to FROM, the
  # flash-attn layer (two ARGs + one RUN — t7 pins their content), EXPOSE.
  # The sanctioned RUN spans continuation lines, so the counts walk LOGICAL
  # instructions, not physical ones.
  offenders=$(python3 - "$DF" <<'PY'
import sys
merged, buf = [], ""
for raw in open(sys.argv[1]).read().splitlines():
    ln = raw.strip()
    if not buf and (not ln or ln.startswith("#")):
        continue
    buf = f"{buf} {ln}".strip() if buf else ln
    if buf.endswith("\\"):
        buf = buf[:-1]
        continue
    merged.append(buf)
    buf = ""
if buf:
    merged.append(buf)
kw = [m.split(None, 1)[0].upper() for m in merged]
bad = []
if kw[:1] != ["FROM"]:
    bad.append(f"first instruction {kw[:1] or ['(none)']}, want FROM")
if kw[-1:] != ["EXPOSE"]:
    bad.append(f"last instruction {kw[-1:] or ['(none)']}, want EXPOSE")
for k, n in (("FROM", 1), ("ARG", 2), ("RUN", 1), ("EXPOSE", 1)):
    if kw.count(k) != n:
        bad.append(f"{k} x{kw.count(k)}, want x{n}")
extra = sorted({k for k in kw if k not in ("FROM", "ARG", "RUN", "EXPOSE")})
if extra:
    bad.append(f"unexpected instructions {extra}")
print("; ".join(bad))
PY
)
  if [ -n "$offenders" ]; then
    fail "t2: the D34 re-export law allows FROM + the flash-attn ARG-pair/RUN + EXPOSE only, got: $offenders — the 0.30 image is a self-contained terminal build (R3 L1.2), any instruction beyond the sanctioned layer forks the pinned stack (C01 AC1)"
  fi
  ok "t2: the Dockerfile is the sanctioned shape — FROM, the one ARG-pair + RUN layer, EXPOSE; no COPY/ENV/USER, no second RUN/ARG"
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
  # The D34 ledger rider (C01's amended README task): the re-export is no
  # longer a pure digest-copy — "copy + FA layer" — the FLASH_ATTN_REF
  # manual pin rides beside the base pin, and every base bump carries the
  # re-verify duty (layer builds, image imports flash_attn, marker logs).
  for token in 'FLASH_ATTN_REF' 'aa743c59' 'flash_attn'; do
    grep -qF "$token" "$README" \
      || fail "t4: the README lacks the flash-attn rider token '$token' (the manual pin recorded beside the base pin + the import named in the base-bump re-verify duty — C01 AC2/D34)"
  done
  grep -qiE 're-verif' "$README" \
    || fail "t4: the base-bump re-verify duty is not stated (the layer still builds, the image still imports flash_attn, the runbook step-3 marker line still logs — C01 AC2/D34)"
  ok "t4: the README carries the release-branch watch, the three-step manual bump, the interface contract (entrypoint / model-path args / mounts / root / AITER / no chat template), and the D34 flash-attn rider"
fi

# --- t5: zero auto-update directives — the manual-ledger law (D12-amended) ----
if want t5; then
  [ -d "$DIR" ] || fail "t5: $DIR missing — C01 is not implemented"
  mapfile -t hits < <(grep -rinE 'renovate:|datasource[[:space:]]*=' "$DIR" 2>/dev/null || true)
  if [ "${#hits[@]}" -ne 0 ]; then
    got=$(printf '%s; ' "${hits[@]}")
    fail "t5: auto-update directive lines in $DIR (${#hits[@]} hits), want ZERO — the base sha-pair publishes and the D34 FLASH_ATTN_REF pin are both manual ledgers (D12-amended; R5.2 bars a branch-head datasource); prose may name the tool, a parseable directive may not appear (got: ${got})"
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

# --- t7: the D34 flash-attn layer pins + the AC6 import corroboration ---------
if want t7; then
  [ -f "$DF" ] || fail "t7: $DF missing (see t1)"
  # C01's dated amendment records the layer lines VERBATIM per R5.2 (the
  # port of vLLM's own official gfx1250 recipe): the jpvillam branch source
  # at its commit pin, the Triton flag BUILD-TIME-INLINE (the runtime var
  # stays chart-owned — the restored 20-var law), the stack-atomicity flags
  # protecting the pinned torch/triton, and the provenance comment.
  grep -qxF "ARG FLASH_ATTN_REPO=${FA_REPO_URL}" "$DF" \
    || fail "t7: no FLASH_ATTN_REPO ARG pinning ${FA_REPO_URL} (the jpvillam-amd gfx1250_wip source the official vLLM base builds — C01 AC1/D34)"
  grep -qxF "ARG FLASH_ATTN_REF=${FA_REF}" "$DF" \
    || fail "t7: no FLASH_ATTN_REF ARG at the commit pin (manual-bump law — a drift here changes the installed source, not a bump — C01 AC1/D34)"
  grep -qF 'FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE python3 -m pip install' "$DF" \
    || fail "t7: the FA install does not carry the build-time-INLINE Triton flag (baked as ENV it forks the chart-owned runtime var; absent, the wheel compiles CK kernels — C01/D34)"
  grep -qF -- '--no-deps --no-build-isolation' "$DF" \
    || fail "t7: the FA install lacks the stack-atomicity flags (--no-deps --no-build-isolation protect the stack-pinned torch/triton — C01/D34)"
  grep -qF 'flash-attn @ git+${FLASH_ATTN_REPO}@${FLASH_ATTN_REF}' "$DF" \
    || fail "t7: the FA install does not consume the ARG pair through the git+repo@ref form (C01 AC1/D34)"
  grep -qF 'Dockerfile.rocm_base_gfx1250' "$DF" \
    || fail "t7: the layer comment block does not name the port provenance (vLLM's own docker/Dockerfile.rocm_base_gfx1250 @ v0.30.0 — the WHY of the source choice, C01/D34)"
  ok "t7: the flash-attn layer carries the D34 verbatim contract — jpvillam source + commit pin + inline-only Triton flag + stack-atomicity flags + ARG consumption + provenance comment"
  # AC6: the built image must import flash_attn. The suite never builds —
  # docker-build.yaml on the pushed branch is the build authority (cf-77).
  # When the published ghcr re-export is reachable, its config-blob layer
  # history corroborates the install at the pinned ref; unpublished,
  # private, or unreachable answers are the designed no-daemon,
  # CI-deferred SKIP — only a contradicting published history FAILs.
  out=$(python3 - "$FA_REF" <<'PY' || true
import json, re, sys, urllib.error, urllib.request

want_ref = sys.argv[1]
REPO = "ownyourio/vllm-radiance-mxfp4"
BASE = f"https://ghcr.io/v2/{REPO}"
ACCEPT = ("application/vnd.oci.image.index.v1+json,"
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
    tok = get(f"https://ghcr.io/token?service=ghcr.io&scope=repository:{REPO}:pull")["token"]
    m = get(f"{BASE}/manifests/main", ACCEPT, tok)
    if "manifests" in m:
        child = next((x for x in m["manifests"]
                      if x.get("platform", {}).get("architecture") == "amd64"
                      and x.get("platform", {}).get("os") == "linux"), None)
        if child is None:
            print("SKIP no amd64/linux child in the index"); sys.exit(0)
        m = get(f"{BASE}/manifests/{child['digest']}",
                "application/vnd.oci.image.manifest.v1+json,"
                "application/vnd.docker.distribution.manifest.v2+json", tok)
    cfg = get(f"{BASE}/blobs/{m['config']['digest']}", None, tok)
    history = cfg.get("history") or []
    if not history:
        print("SKIP the published image carries no build history (config shape)"); sys.exit(0)
    fa = [h for h in history if re.search(r"flash-attn(?!ion)", h.get("created_by", ""))]
    if not fa:
        print("SKIP the published :main predates the D34 layer — the CI rebuild on the pushed branch is the authority"); sys.exit(0)
    if not any(want_ref in h.get("created_by", "") for h in fa):
        print(f"MISMATCH the published flash-attn install does not name the pinned {want_ref} — the image and the Dockerfile diverged"); sys.exit(2)
    print("MATCH flash-attn install at the pinned ref in the published layer history")
except (urllib.error.URLError, OSError, KeyError, ValueError, json.JSONDecodeError) as ex:
    print(f"SKIP transport/parse: {ex}")
PY
)
  case "$out" in
    MATCH*) checks=$((checks + 1)); printf 'ok: t7 — the published ghcr re-export records the flash-attn install at the pinned ref (AC6 live corroboration)\n';;
    MISMATCH*) fail "t7: ${out#MISMATCH } — stop + flag, never ship a diverged import AC (C01 note)";;
    SKIP*) skip "t7 AC6: ${out#SKIP } — docker build => no-daemon, CI-deferred (the designed passing shape, cf-77)";;
    *) skip "t7 AC6: the probe produced no verdict ($out) — CI-deferred";;
  esac
fi

printf 'PASS: vllm-radiance-mxfp4 container contract checks (%d ok)\n' "$checks"
