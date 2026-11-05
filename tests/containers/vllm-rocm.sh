#!/usr/bin/env bash
# vllm-rocm container contract (2026/2026-11-cf-105-feat-implement-vllm, C01):
# the thin overlay over the upstream vllm/vllm-openai-rocm:v0.33.0-rocm100
# base that adds the OOT vllm-gguf-plugin (the only 32 GiB weight path that
# fits the D4 envelope) pinned to a GIT REF, plus the R1 recipe env pins.
# Contract source: chunks/C01.md "## Tests" (t1-t6).
#
# The image pin is a MANUAL ledger (tag in the Dockerfile FROM, full digest
# in a Dockerfile comment and the README table) with ZERO renovate
# directives — the ONE sanctioned directive is the plugin ARG's git-refs
# comment — so t4 counts case-insensitive "renovate" lines over the whole
# container dir and requires EXACTLY ONE. Two README phrasing traps follow
# from that bar: the zero-directives note must not use the literal word
# "renovate" (say "auto-update directives"), and the "why no release
# exists" note must not quote the pin syntax "vllm-gguf-plugin==" (name
# the version, not the pin) — either one fails t4/t5.
#
# docker build is CI-primary (no docker daemon in agent sessions): the
# suite never builds. t3 is network-gated — SKIP with warning on no
# egress; an HTTP error (e.g. 404 for the tag) or a live/ledger digest
# mismatch is a FAIL, naming both values, never silent.
#
# Run from the repo root:
#   bash tests/containers/vllm-rocm.sh          # t1..t6
#   bash tests/containers/vllm-rocm.sh t1 t6    # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

DIR="containers/vllm-rocm"
DF="$DIR/Dockerfile"
README="$DIR/README.md"
BASE_IMAGE="vllm/vllm-openai-rocm"
BASE_TAG="v0.33.0-rocm100"
# Dots escaped for ERE: the FROM pin must be the exact tag, not a near-match.
BASE_TAG_RE='v0\.33\.0-rocm100'
HUB_URL="https://hub.docker.com/v2/repositories/${BASE_IMAGE}/tags/${BASE_TAG}"

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

WORK=$(mktemp -d /tmp/opencode/vllm-rocm.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

# Full sha256 digests recorded in the Dockerfile (ledger comment) and in the
# README (ledger table); t2 pairs the two, t3 checks the live registry
# against the ledger.
df_digests() {
  [ -f "$DF" ] && grep -oE 'sha256:[0-9a-f]{64}' "$DF" | sort -u || true
}
rd_digests() {
  [ -f "$README" ] && grep -oE 'sha256:[0-9a-f]{64}' "$README" | sort -u || true
}

# The Docker Hub tags API carries the digest in a "digest" field; any other
# shape (error page, unexpected JSON) must surface as a named FAIL below,
# not a raw python traceback.
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

# --- t1: the base is FROM-pinned to the exact R1-verified tag ----------------
if want t1; then
  if [ ! -f "$DF" ]; then
    fail "t1: $DF missing — C01 (the vllm-rocm overlay image) is not implemented"
  fi
  if ! grep -E "^FROM[[:space:]]+${BASE_IMAGE}:${BASE_TAG_RE}([[:space:]]|$)" "$DF" >/dev/null; then
    fail "t1: no FROM line pinning ${BASE_IMAGE}:${BASE_TAG} exactly (C01 AC2 — the R1-verified image class)"
  fi
  ok "t1: the Dockerfile FROM-pins ${BASE_IMAGE}:${BASE_TAG}"
fi

# --- t2: the ledger digest is full, and paired consistently ------------------
if want t2; then
  [ -f "$DF" ] || fail "t2: $DF missing (see t1)"
  [ -f "$README" ] || fail "t2: $README missing — the tag→digest ledger (C01 task 2) is not implemented"
  df_digests > "$WORK/df.dg"
  rd_digests > "$WORK/rd.dg"
  if [ ! -s "$WORK/rd.dg" ]; then
    fail "t2: the README ledger carries no full sha256:<64-hex> digest (C01 AC2 — the digest-pinned base)"
  fi
  if [ ! -s "$WORK/df.dg" ]; then
    fail "t2: the Dockerfile carries no full sha256 digest in its ledger comment (C01 task 1: tag + full digest in a ledger comment)"
  fi
  if ! grep -qF "${BASE_TAG}" "$README"; then
    fail "t2: the README ledger does not name the base tag ${BASE_TAG} — the tag↔digest pairing is incomplete"
  fi
  if ! comm -12 "$WORK/df.dg" "$WORK/rd.dg" | grep -q .; then
    fail "t2: no full digest is shared between the Dockerfile comment and the README ledger — the tag↔digest pairing is inconsistent (Dockerfile: $(tr '\n' ' ' < "$WORK/df.dg") / README: $(tr '\n' ' ' < "$WORK/rd.dg"))"
  fi
  ok "t2: the ledger carries a full sha256 digest, names the base tag, and the Dockerfile comment matches the ledger digest"
fi

# --- t3 (network-gated): the live registry digest equals the ledger digest ---
if want t3; then
  [ -f "$README" ] || fail "t3: $README missing — the ledger to verify against is not implemented (see t2)"
  rd_digests > "$WORK/rd.dg"
  if [ ! -s "$WORK/rd.dg" ]; then
    fail "t3: no ledger digest to verify against (see t2)"
  fi
  if curl -fsS --max-time 30 "$HUB_URL" -o "$WORK/hub-tag.json" 2> "$WORK/hub-err"; then
    live=$(hub_digest "$WORK/hub-tag.json" 2>/dev/null) || live="UNPARSEABLE"
    if [ "$live" = "UNPARSEABLE" ]; then
      head -c 200 "$WORK/hub-tag.json" >&2 || true
      fail "t3: the Docker Hub tags API answered for ${BASE_TAG} but the response carries no usable digest (body above) — the ledger pins $(tr '\n' ' ' < "$WORK/rd.dg") (C01 AC2)"
    fi
    if ! grep -qxF "$live" "$WORK/rd.dg"; then
      fail "t3: digest mismatch — the ledger pins $(tr '\n' ' ' < "$WORK/rd.dg") but ${BASE_IMAGE}:${BASE_TAG} now resolves to ${live} (re-verify and re-record the ledger; never ship a drifted pin — C01 AC2)"
    fi
    ok "t3: the live Docker Hub digest for ${BASE_TAG} equals the ledger digest (${live})"
  elif grep -qiE 'HTTP error|404|not found' "$WORK/hub-err"; then
    fail "t3: the Docker Hub tags API answered an HTTP error for ${BASE_TAG} — the pinned base tag must exist ($(head -1 "$WORK/hub-err"))"
  else
    skip "t3: no egress to hub.docker.com ($(head -1 "$WORK/hub-err" 2>/dev/null || echo 'network unreachable')) — the live digest re-verification was not run (the CI build is the authority)"
  fi
fi

# --- t4: exactly one renovate directive — the sanctioned plugin git-refs -----
if want t4; then
  [ -d "$DIR" ] || fail "t4: $DIR missing — C01 is not implemented"
  mapfile -t hits < <(grep -rin 'renovate' "$DIR" 2>/dev/null || true)
  if [ "${#hits[@]}" -ne 1 ]; then
    got=""
    if [ "${#hits[@]}" -gt 0 ]; then got=$(printf '%s; ' "${hits[@]}"); fi
    fail "t4: 'grep -ri renovate $DIR/' returns ${#hits[@]} hits, want EXACTLY ONE — the sanctioned git-refs comment on the plugin ARG (the manual-ledger contract covers the image pins; C01 AC5)${got:+ (got: ${got})}"
  fi
  if ! printf '%s' "${hits[0]}" | grep -q 'datasource=git-refs'; then
    fail "t4: the sole renovate hit is not the git-refs one (got: ${hits[0]})"
  fi
  if ! printf '%s' "${hits[0]}" | grep -q 'depName=vllm-project/vllm-gguf-plugin'; then
    fail "t4: the sole renovate hit does not name vllm-project/vllm-gguf-plugin (got: ${hits[0]})"
  fi
  ok "t4: exactly one renovate directive in the container dir — the sanctioned git-refs comment for the plugin pin"
fi

# --- t5: the plugin pin is a git ref (not PyPI, not a branch); patch applied --
if want t5; then
  [ -f "$DF" ] || fail "t5: $DF missing (see t1)"
  if ! python3 - "$DIR" <<'PY'
import re, sys
from pathlib import Path
d = Path(sys.argv[1])
df_lines = (d / "Dockerfile").read_text().splitlines()
# Instructions commonly span physical lines (backslash continuations); the
# install/apply assertions run on logical lines, the comment/ARG adjacency
# on physical ones (a comment cannot sit inside a continuation).
logical, buf = [], ""
for ln in df_lines:
    if ln.rstrip().endswith("\\"):
        buf += ln.rstrip()[:-1] + " "
        continue
    logical.append((buf + ln).strip())
    buf = ""
if buf:
    logical.append(buf.strip())

# The sanctioned comment sits DIRECTLY above an ARG <NAME>=<40-hex-sha> line
# (the in-repo git-pin shape, containers/gpt-researcher precedent).
arg_name = None
for i, ln in enumerate(df_lines):
    m = re.match(r"^ARG\s+([A-Za-z_][A-Za-z0-9_]*)=([a-f0-9]{40})\s*$", ln)
    if not m:
        continue
    prev = df_lines[i - 1].strip() if i else ""
    if re.match(r"^#\s*renovate:\s*datasource=git-refs\s+depName=vllm-project/vllm-gguf-plugin\s*$", prev):
        arg_name = m.group(1)
        break
assert arg_name, (
    "no '# renovate: datasource=git-refs depName=vllm-project/vllm-gguf-plugin' comment directly above "
    "an 'ARG <NAME>=<40-hex-sha>' line (the in-repo git-pin shape, containers/gpt-researcher precedent)"
)

# The install line: pip install ... git+https://github.com/.../vllm-gguf-plugin@${ARG}
inst = [ln for ln in logical
        if re.search(r"\bpip[3]?\s+install\b", ln)
        and re.search(r"git\+https://github\.com/vllm-project/vllm-gguf-plugin@\$\{" + re.escape(arg_name) + r"\}", ln)]
assert inst, f"no 'pip install ... git+https://github.com/vllm-project/vllm-gguf-plugin@${{{arg_name}}}' line (C01 task 1)"

# NOT a PyPI release, NOT a bare branch: no 'vllm-gguf-plugin==' pin anywhere
# in the container dir (C01 AC3 — the Qwen3.5 adapter is main-only).
blob = "\n".join(p.read_text(errors="replace") for p in d.rglob("*") if p.is_file())
assert not re.search(r"vllm-gguf-plugin\s*==", blob), (
    "a PyPI release pin (vllm-gguf-plugin==) exists — the pin must be a git ref (C01 AC3)"
)

# The carry import-compat patch exists (strata carry-patch shape: a .patch
# file under carry/) and the Dockerfile APPLIES it — an apply/patch command
# at a command position on a line referencing the carry file; a bare COPY of
# the patch file is not an application.
carry = sorted(p.name for p in (d / "carry").glob("*.patch")) if (d / "carry").is_dir() else []
assert carry, "no *.patch file under containers/vllm-rocm/carry/ (the vendored import-compat patch, strata carry precedent)"
APPLY = re.compile(r"(?:^|[\s;&|])(?:git\s+apply(?!\s+--check)|patch)\b")
apply = [ln for ln in logical
         if not ln.lstrip().startswith("#") and "carry/" in ln and APPLY.search(ln)]
assert apply, "the Dockerfile does not apply the carry/ patch (strata carry-patch shape — git apply / patch, not just a COPY)"

# A Dockerfile comment documents what the patch fixes (the qwen3_5 import
# layout vLLM #60623 changed) (C01 AC3).
doc = [ln for ln in df_lines if ln.lstrip().startswith("#") and "qwen3_5" in ln]
assert doc, "no Dockerfile comment documenting the import patch (what it fixes: the qwen3_5 import, C01 AC3)"
print(f"t5 ok: git-ref pin via ARG {arg_name} + pip git+ install + no PyPI pin + carry patch applied and documented")
PY
  then
    fail "t5: the vllm-gguf-plugin pin contract is not met (diagnostics above)"
  fi
  ok "t5: the plugin is pinned to a git ref (ARG 40-hex + git-refs comment, pip git+ install, no PyPI pin) and the carry import patch is applied + documented"
fi

# --- t6: the R1 recipe env pins are baked -------------------------------------
if want t6; then
  [ -f "$DF" ] || fail "t6: $DF missing (see t1)"
  for kv in \
    'PYTORCH_ALLOC_CONF=expandable_segments:True' \
    'TRITON_CACHE_DIR=/data/triton' \
    'HUGGINGFACE_HUB_CACHE=/data/hf' \
    'VLLM_ROCM_USE_AITER=0'; do
    if ! grep -qF "$kv" "$DF"; then
      fail "t6: env pin '$kv' missing from the Dockerfile (C01 task 1: the R1 recipe env pins; AITER prebuilds are CDNA-only and must stay OFF on gfx12x)"
    fi
  done
  ok "t6: all four env pins are present (PYTORCH_ALLOC_CONF / TRITON_CACHE_DIR / HUGGINGFACE_HUB_CACHE / VLLM_ROCM_USE_AITER=0)"
fi

printf 'PASS: vllm-rocm container contract checks (%d ok)\n' "$checks"
