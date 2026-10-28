#!/usr/bin/env bash
# C01 structural acceptance checks (2026-10-feat-coder-workspace-rebuild),
# criteria 2-6, run by grep/awk against containers/coder-workspace/.
#
# This repo has no unit-test suite (AGENTS.md "Pipeline specifics"); these
# structural checks are the local gate because there is no docker daemon here
# and the build proof is PR CI. Each check prints one pass/fail line; any fail
# makes the script exit non-zero.
#
# Tests are the dev agent's contract: every pinned value below is taken from
# chunks/C01.md "Acceptance criteria" and DECISIONS.md.
#
# Usage: bash tests/coder-workspace/image-structure.sh

set -u

cd "$(git rev-parse --show-toplevel)" || { echo "fail: cannot resolve repo root via git"; exit 2; }

CONTAINER_DIR="containers/coder-workspace"
DOCKERFILE="$CONTAINER_DIR/Dockerfile"
STARTUP="$CONTAINER_DIR/workspace-startup.sh"

# Pinned values (DECISIONS #1/#3; C01 acceptance criteria 2/3/5).
BASE_IMAGE='debian:13-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad'
FJ_SHA256='6803c12eed17bfadb40ba95da2a6ab58f9b4a7dc10eabfe3512fce7e2fe6216f'

declare -A PIN=(
  [NODE_VERSION]='26.12.1'
  [GO_VERSION]='1.27.3'
  [HELM_VERSION]='v3.22.1'
  [KUBECTL_VERSION]='v1.36.5'
  [UV_VERSION]='0.13.5'
  [FJ_VERSION]='v0.7.0'
  [OPENCODE_VERSION]='2.1.4'
  [OPENCHAMBER_VERSION]='2.5.1'
)

# The exact renovate comment each tool ARG must carry on the line immediately
# above it. The attribute order is part of the contract: C02's custom managers
# extract (datasource, registryUrl, depName) positionally from comment+ARG
# pairs, so a reordered or extended comment silently breaks extraction.
declare -A COMMENT_RE=(
  [NODE_VERSION]='^#[[:space:]]*renovate:[[:space:]]+datasource=node-version[[:space:]]+depName=node[[:space:]]*$'
  [GO_VERSION]='^#[[:space:]]*renovate:[[:space:]]+datasource=golang-version[[:space:]]+depName=golang[[:space:]]*$'
  [HELM_VERSION]='^#[[:space:]]*renovate:[[:space:]]+datasource=github-releases[[:space:]]+depName=helm/helm[[:space:]]*$'
  [KUBECTL_VERSION]='^#[[:space:]]*renovate:[[:space:]]+datasource=github-releases[[:space:]]+depName=kubernetes/kubernetes[[:space:]]*$'
  [UV_VERSION]='^#[[:space:]]*renovate:[[:space:]]+datasource=github-releases[[:space:]]+depName=astral-sh/uv[[:space:]]*$'
  [FJ_VERSION]='^#[[:space:]]*renovate:[[:space:]]+datasource=forgejo-releases[[:space:]]+registryUrl=https://codeberg\.org[[:space:]]+depName=forgejo-contrib/forgejo-cli[[:space:]]*$'
  [OPENCODE_VERSION]='^#[[:space:]]*renovate:[[:space:]]+datasource=npm[[:space:]]+depName=@opencode/cli[[:space:]]*$'
  [OPENCHAMBER_VERSION]='^#[[:space:]]*renovate:[[:space:]]+datasource=npm[[:space:]]+depName=@openchamber/web[[:space:]]*$'
)

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'pass: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'fail: %s\n' "$1"; }

# Comments are stripped before every absence/presence scan below. C01 mandates
# explanatory comments naming what was removed (why no sudo/nvm/ppa), so
# matching prose would fail a correct implementation.
code_lines() {
  grep -vE '^[[:space:]]*#' "$1" | grep -vE '^[[:space:]]*$' || true
}

[ -f "$DOCKERFILE" ] || { fail "precondition: $DOCKERFILE is missing"; echo "=== image-structure: $PASS passed, $((FAIL + 1)) failed ==="; exit 1; }

# --- criterion 2: digest-pinned base image -------------------------------
if grep -qxF "FROM ${BASE_IMAGE}" "$DOCKERFILE"; then
  pass "c2: FROM is exactly '${BASE_IMAGE}'"
else
  fail "c2: FROM is not exactly '${BASE_IMAGE}' (got: $(grep -E '^[[:space:]]*FROM[[:space:]]' "$DOCKERFILE" | head -n 1 || echo '<no FROM line>'))"
fi

from_line=$(grep -nE '^[[:space:]]*FROM[[:space:]]' "$DOCKERFILE" | head -n 1 | cut -d: -f1 || true)
if [ -n "$from_line" ] && [ "$from_line" -gt 1 ] && \
  sed -n "$((from_line - 1))p" "$DOCKERFILE" | \
    grep -qE '^#[[:space:]]*renovate:[[:space:]]*datasource=docker[[:space:]]+depName=debian[[:space:]]*$'; then
  pass "c2: '# renovate: datasource=docker depName=debian' sits immediately above FROM"
else
  fail "c2: no '# renovate: datasource=docker depName=debian' comment on the line immediately above FROM"
fi

# --- criterion 3: every tool version ARG pinned and comment-annotated -----
# FJ_SHA256 is deliberately not in the loop: it is a checksum, not a version
# pin, and C02 criterion 3 requires it to stay out of renovate extraction —
# the custom manager pairs a renovate comment with the ARG directly below it,
# so a comment above FJ_SHA256 would register a duplicate forgejo-cli dep.
# It is asserted under criterion 5 instead.
TOOL_ARGS='NODE_VERSION GO_VERSION HELM_VERSION KUBECTL_VERSION UV_VERSION FJ_VERSION OPENCODE_VERSION OPENCHAMBER_VERSION'

report=$(awk -v want="$TOOL_ARGS" '
  BEGIN { n = split(want, w, " "); for (i = 1; i <= n; i++) need[w[i]] = 1 }
  /^[[:space:]]*$/ { next }
  {
    if ($0 ~ /^[[:space:]]*ARG[[:space:]]+[A-Z][A-Z0-9_]*=/) {
      name = $0
      sub(/^[[:space:]]*ARG[[:space:]]+/, "", name)
      sub(/=.*/, "", name)
      if (name in need)
        print name "|" (prev ~ /^#[[:space:]]*renovate:/ ? prev : "<not a renovate comment>")
    }
    prev = $0
  }
' "$DOCKERFILE")

for arg in $TOOL_ARGS; do
  row=$(printf '%s\n' "$report" | awk -F'|' -v a="$arg" '$1 == a { print; exit }')
  if [ -z "$row" ]; then
    fail "c3: ARG ${arg} is not declared in the Dockerfile"
    continue
  fi
  prevline=$(printf '%s\n' "$row" | cut -d'|' -f2-)
  got=$(code_lines "$DOCKERFILE" | grep -E "^ARG ${arg}=" | head -n 1 | sed -E 's/^ARG [A-Z0-9_]+=//; s/[[:space:]]*(#.*)?$//' || true)
  if [ "$got" = "${PIN[$arg]}" ]; then
    pass "c3: ARG ${arg} is pinned to ${PIN[$arg]}"
  else
    fail "c3: ARG ${arg} is pinned to '${got}', expected '${PIN[$arg]}'"
  fi

  if [ "$prevline" = "<not a renovate comment>" ]; then
    fail "c3: the line immediately above ARG ${arg} is not a '# renovate:' comment (got: '$prevline')"
  elif printf '%s\n' "$prevline" | grep -qE "${COMMENT_RE[$arg]}"; then
    pass "c3: the line immediately above ARG ${arg} is the pinned renovate comment"
  else
    fail "c3: the line immediately above ARG ${arg} does not match the pinned renovate comment (got: '$prevline')"
  fi
done

# --- criterion 4: removals must not reappear ------------------------------
# One check per forbidden string, over the code (comments stripped) of both
# files in the container directory.
forbidden() {
  local s="$1" hit f
  for f in "$DOCKERFILE" "$STARTUP"; do
    [ -f "$f" ] || continue
    hit=$(code_lines "$f" | grep -inF -- "$s" | head -n 1 || true)
    if [ -n "$hit" ]; then
      fail "c4: '$s' still present in $f ($hit)"
      return
    fi
  done
  pass "c4: no '$s' in $CONTAINER_DIR code"
}
forbidden 'pbir'
forbidden 'software-properties-common'
forbidden 'add-apt-repository'
forbidden 'nvm'
forbidden 'kilocode'
forbidden 'kilo '
forbidden 'ubuntu:'
forbidden 'ENTRYPOINT'
forbidden 'CMD '

# --- criterion 5: checksums and version assertions -------------------------
if grep -qE "^ARG FJ_SHA256=${FJ_SHA256}[[:space:]]*$" "$DOCKERFILE"; then
  pass "c5: ARG FJ_SHA256 carries the pinned forgejo-cli hash"
else
  fail "c5: ARG FJ_SHA256 is not set to the pinned forgejo-cli hash ${FJ_SHA256}"
fi

# The @sha256: line is the base-image digest pin, not a checksum; everything
# else that is a 64-hex value is a hardcoded vendor checksum, and there must
# be exactly one of them (fj, whose release publishes no checksum file).
hexes=$(code_lines "$DOCKERFILE" | grep -vE '@sha256:' | grep -oE '[0-9a-fA-F]{64}' | sort -u || true)
hexcount=$(printf '%s\n' "$hexes" | grep -c . || true)
if [ "$hexcount" = "1" ] && [ "$hexes" = "$FJ_SHA256" ]; then
  pass "c5: exactly one hardcoded sha256 in the image (FJ_SHA256); node/go/helm/kubectl/uv verify vendor-published checksums"
else
  fail "c5: expected exactly one hardcoded sha256 (FJ_SHA256), found $hexcount distinct value(s): $(printf '%s' "$hexes" | tr '\n' ' ')"
fi

# The first RUN block referencing a tool's version ARG is that tool's install
# layer; the block ends at the first physical line without a backslash
# (whole-line comments inside a continuation are skipped by Docker, so they
# do not end the block).
layer_block() { # $1 = ARG name
  awk -v ref="\${$1}" '
    function emit(   i) { for (i = 1; i <= n; i++) print b[i]; found = 1; exit }
    !inrun && /^[[:space:]]*RUN[[:space:]]/ { inrun = 1; n = 0; hit = 0 }
    inrun {
      n++; b[n] = $0
      if (index($0, ref) > 0) hit = 1
      if ($0 ~ /\\[[:space:]]*$/) next
      if ($0 ~ /^[[:space:]]*#/) next
      inrun = 0
      if (hit) emit()
    }
  ' "$DOCKERFILE"
}

# A version assertion is a test/grep line that names the tool, references the
# pinned ARG, and is not neutralised by '|| true' — a neutered assertion cannot
# fail the build on drift.
assert_line() { # $1 block text, $2 tool-name ERE, $3 ARG name
  printf '%s\n' "$1" \
    | grep -E '(^|[[:space:]])(test[[:space:]]|grep[[:space:]]+-q)' \
    | grep -F -- "\${$3}" \
    | grep -Ev '\|\|[[:space:]]*true' \
    | grep -Eq "$2"
}

declare -A TOOL_ERE=(
  [NODE]='(^|[^a-zA-Z0-9_-])node([[:space:]]|$)'
  [GO]='(^|[^a-zA-Z0-9_-])go([[:space:]]|$)'
  [HELM]='(^|[^a-zA-Z0-9_-])helm([[:space:]]|$)'
  [KUBECTL]='(^|[^a-zA-Z0-9_-])kubectl([[:space:]]|$)'
  [UV]='(^|[^a-zA-Z0-9_-])uvx?([[:space:]]|$)'
)

for tool in NODE GO HELM KUBECTL UV; do
  arg="${tool}_VERSION"
  block=$(layer_block "$arg")
  if [ -z "$block" ]; then
    fail "c5: no RUN layer installs ${tool} (no RUN block references \${${arg}})"
    continue
  fi
  if printf '%s\n' "$block" | grep -Eq 'sha256sum[[:space:]]+-c'; then
    pass "c5: ${tool} layer verifies a vendor-published checksum (sha256sum -c)"
  else
    fail "c5: ${tool} layer does not verify a vendor-published checksum (no sha256sum -c)"
  fi
  if assert_line "$block" "${TOOL_ERE[$tool]}" "$arg"; then
    pass "c5: ${tool} layer asserts the installed version against \${${arg}}"
  else
    fail "c5: ${tool} layer has no live version assertion of \${${arg}} (test/grep, not '|| true')"
  fi
done

fjblock=$(layer_block FJ_VERSION)
if [ -n "$fjblock" ] && printf '%s\n' "$fjblock" | grep -F -- '${FJ_SHA256}' | grep -Eq 'sha256sum[[:space:]]+-c'; then
  pass "c5: fj layer verifies the tarball against \${FJ_SHA256}"
else
  fail "c5: fj layer does not verify the tarball against \${FJ_SHA256}"
fi

# --- criterion 6: runtime shape -------------------------------------------
last_user=$(code_lines "$DOCKERFILE" | grep -E '^[[:space:]]*USER[[:space:]]' | tail -n 1 | sed -E 's/[[:space:]]+$//')
if [ "$last_user" = "USER 1000:1000" ]; then
  pass "c6: the final USER is 1000:1000"
else
  fail "c6: the final USER is not 'USER 1000:1000' (got: '${last_user:-<none>}')"
fi

last_workdir=$(code_lines "$DOCKERFILE" | grep -E '^[[:space:]]*WORKDIR[[:space:]]' | tail -n 1 | sed -E 's/[[:space:]]+$//')
if [ "$last_workdir" = "WORKDIR /home/coder" ]; then
  pass "c6: the final WORKDIR is /home/coder"
else
  fail "c6: the final WORKDIR is not /home/coder (got: '${last_workdir:-<none>}')"
fi

if grep -qxF 'COPY --chmod=0755 workspace-startup.sh /usr/local/bin/workspace-startup.sh' "$DOCKERFILE"; then
  pass "c6: COPY --chmod=0755 workspace-startup.sh /usr/local/bin/workspace-startup.sh is present"
else
  fail "c6: the COPY --chmod=0755 of workspace-startup.sh into /usr/local/bin is missing"
fi

# Apt must be one consolidated RUN (one update, one cleanup) so no layer below
# can outlive a stale package index and so the image grows by one cache, not
# one per install.
apt_runs=$(awk '
  !inrun && /^[[:space:]]*RUN[[:space:]]/ { inrun = 1; apt = 0; clean = 0 }
  inrun {
    if ($0 ~ /(^|[[:space:]])apt(-get)?[[:space:]]+(update|install)/) apt = 1
    if ($0 ~ /rm[[:space:]]+-rf[[:space:]]+\/var\/lib\/apt\/lists/) clean = 1
    if ($0 ~ /\\[[:space:]]*$/) next
    if ($0 ~ /^[[:space:]]*#/) next
    inrun = 0
    if (apt) print clean ? "clean" : "no-cleanup"
  }
' "$DOCKERFILE")
apt_count=$(printf '%s\n' "$apt_runs" | grep -c . || true)
if [ "$apt_count" = "1" ] && [ "$apt_runs" = "clean" ]; then
  pass "c6: apt is a single consolidated RUN with 'rm -rf /var/lib/apt/lists/*'"
else
  fail "c6: apt is not a single consolidated RUN with cleanup (apt RUNs found: ${apt_count:-0}; $(printf '%s' "$apt_runs" | tr '\n' ' '))"
fi

# The marker removal must be the loud form (bare rm, no -f): trixie's
# python3.13 always ships the marker, so a missing path means the base moved
# to a new python minor and the build must fail rather than silently ship
# with PEP 668 re-enabled.
if code_lines "$DOCKERFILE" | grep -Eq '(^|[[:space:]])rm[[:space:]]+/usr/lib/python3\.13/EXTERNALLY-MANAGED'; then
  pass "c6: 'rm /usr/lib/python3.13/EXTERNALLY-MANAGED' is present (loud form, no -f)"
else
  fail "c6: the PEP 668 marker /usr/lib/python3.13/EXTERNALLY-MANAGED is not removed with the loud bare-rm form"
fi

# --- criterion 3 (mechanical): no dangling '&&' / broken continuation ------
# Inside a RUN, every physical line must either continue with a backslash or
# be the last command; a line ending in '&&' has no right-hand side, which
# makes docker parse the rest of the layer as a different (broken) command
# list — a syntax error that only surfaces at image build time.
dangling=$(awk '
  {
    line = $0
    if (!inrun && line ~ /^[[:space:]]*RUN[[:space:]]/) inrun = 1
    if (inrun) {
      if (line ~ /\\[[:space:]]*$/) next
      if (line !~ /^[[:space:]]*#/) {
        if (line ~ /&&[[:space:]]*$/) print "line " NR ": " line
        inrun = 0
      }
    }
  }
' "$DOCKERFILE")
if [ -z "$dangling" ]; then
  pass "c3: no RUN line ends with a dangling '&&' or broken continuation"
else
  fail "c3: dangling '&&'/continuation error(s): $(printf '%s' "$dangling" | tr '\n' '; ')"
fi

echo "=== image-structure: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
