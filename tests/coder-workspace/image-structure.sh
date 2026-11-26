#!/usr/bin/env bash
# C01 structural acceptance checks (2026-10-feat-coder-workspace-rebuild),
# criteria 2-6, run by grep/awk against containers/coder-workspace/, plus the
# C02 criterion-7 node-layer teeth (cf-6-debug-detect-rerun): static pins for
# the v-prefixed nodejs.org URL/filename/assertion shapes and executed
# scratch-fixture legs for the checksum leg's non-vacuity.
#
# This repo has no unit-test suite (AGENTS.md "Pipeline specifics"); these
# structural checks are the local gate because there is no docker daemon here
# and the build proof is PR CI. Each check prints one pass/fail line; any fail
# makes the script exit non-zero.
#
# Criterion 7 is the class-of-failure lesson of EXPLORE §Bucket-C: the node
# layer ran 0-green/15-red since 3713c83d1 (2026-10-20) with every leg above
# green, because those pin shapes — "a checksum line is present", "an
# assertion is live" — while the bug (bare semver interpolated into nodejs.org
# paths that only exist v-prefixed, plus an unmatched grep piped straight
# into `sha256sum -c -`, which exits 0 silently on empty input) kept every
# shape literally true and semantically empty. Static shape-pins catch the
# interpolation class; the executed fixtures catch the vacuity class — the
# daemon-free detection this container never had.
#
# Posture: 52 pass / 1 fail expected once the fix lands — the 1 is the
# PRE-EXISTING c2 debian-annotation red (cf-95 removed the dead comment;
# owner ledger, not criterion 7's to fix). Against the unfixed layer the six
# c7 legs are authored-red by design and the c7g historical-form control is
# green by design.
#
# Tests are the dev agent's contract: every pinned value below is taken from
# chunks/C01.md + chunks/C02.md "Acceptance criteria" and DECISIONS.md.
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
layer_block() { # $1 = ARG name, $2 = Dockerfile path (default: the repo's)
  local f="${2:-$DOCKERFILE}"
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
  ' "$f"
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

# --- criterion 7 (C02): node-layer v-prefix + checksum non-vacuity ---------
# EXPLORE §Bucket-C grounds this block: the legs above stayed green through
# a 0-green/15-red node layer because they pin shapes ("a checksum line is
# present", "an assertion is live") while bare-semver interpolation into
# v-only nodejs.org paths and an empty grep piped into `sha256sum -c -` kept
# every shape literally true. Here the shapes are pinned directly and the
# verify step is EXECUTED against a vendor-shaped scratch fixture — static
# legs catch the interpolation class, executed legs catch the vacuity class,
# neither needs a docker daemon.

# Fixture version reads the file's own ARG so the executed legs track future
# renovate bumps; PIN[NODE_VERSION] (c3) owns the value, and the
# datasource=node-version contract keeps the ARG bare — the v is the
# interpolation's job.
node_ver=$(code_lines "$DOCKERFILE" | grep -E '^ARG NODE_VERSION=' | head -n 1 | sed -E 's/^ARG NODE_VERSION=//; s/[[:space:]]*(#.*)?$//' || true)
node_ver=${node_ver:-${PIN[NODE_VERSION]}}
node_xz="node-v${node_ver}-linux-x64.tar.xz"

# c7a — the two dist URLs (tarball fetch, SHASUMS fetch) must interpolate
# the v-prefixed version, restated from the AC1 grep fingerprint.
dist_v=$(code_lines "$DOCKERFILE" | grep -oF 'nodejs.org/dist/v${NODE_VERSION}' | wc -l)
dist_bare=$(code_lines "$DOCKERFILE" | grep -oF 'nodejs.org/dist/${NODE_VERSION}' | wc -l)
if [ "$dist_v" -eq 2 ] && [ "$dist_bare" -eq 0 ]; then
  pass "c7a: both nodejs.org dist URLs use 'dist/v\${NODE_VERSION}' and no bare interpolation survives"
else
  fail "c7a: nodejs.org dist URLs: want 2 'dist/v\${NODE_VERSION}' sites and 0 bare, got ${dist_v} v-prefixed and ${dist_bare} bare"
fi

# c7b — the tarball filename at its five use sites (curl -o, dist URL tail,
# grep pattern, tar, rm): occurrence-count, not line-count, because curl's
# -o and URL share a physical line.
xz_v=$(code_lines "$DOCKERFILE" | grep -oF 'node-v${NODE_VERSION}-linux-x64.tar.xz' | wc -l)
xz_bare=$(code_lines "$DOCKERFILE" | grep -oF 'node-${NODE_VERSION}-linux-x64.tar.xz' | wc -l)
if [ "$xz_v" -eq 5 ] && [ "$xz_bare" -eq 0 ]; then
  pass "c7b: 'node-v\${NODE_VERSION}-linux-x64.tar.xz' at all 5 use sites and bare form gone"
else
  fail "c7b: 'node-v\${NODE_VERSION}-linux-x64.tar.xz': want 5 occurrences and 0 bare, got ${xz_v} v-prefixed and ${xz_bare} bare"
fi

# c7c — node prints the v; an assertion comparing "$(node --version)" to the
# bare ARG could never pass, and never did.
if code_lines "$DOCKERFILE" | grep -qF 'test "$(node --version)" = "v${NODE_VERSION}"' \
  && ! code_lines "$DOCKERFILE" | grep -qF 'test "$(node --version)" = "${NODE_VERSION}"'; then
  pass "c7c: the node version assertion compares against \"v\${NODE_VERSION}\" exactly"
else
  fail "c7c: no exact 'test \"\$(node --version)\" = \"v\${NODE_VERSION}\"' (v-form missing or bare form survives)"
fi

# c7d — checksum-leg shape: the grep result must be captured and proven
# non-empty before `sha256sum -c -` sees it. A grep piped directly into
# sha256sum is the historical bug shape: a miss forwards empty input to the
# checker, and whether that passes silently is a property of the checker's
# version, never of the layer (see the stub note in the executed section).
# Sanctioned spellings capture the grep result and guard it, so the scope is
# pinned while the spelling stays dev's choice.
node_block=$(layer_block NODE_VERSION)
pipe_bug=$(printf '%s\n' "$node_block" | grep -E 'grep[^()&|;]*\|[[:space:]]*sha256sum' || true)
capture=$(printf '%s\n' "$node_block" | grep -E '\$\([^)]*grep|grep[^|]*[[:space:]]>' || true)
guard=$(printf '%s\n' "$node_block" | grep -E '(\[+|test)[[:space:]]+!?[[:space:]]*-[nsz][[:space:]]' || true)
if [ -z "$pipe_bug" ] && [ -n "$capture" ] && [ -n "$guard" ]; then
  pass "c7d: checksum leg captures the grep result and guards emptiness before sha256sum -c"
else
  fail "c7d: checksum leg not capture-and-guard shaped (want no direct grep->sha256sum pipe, a captured grep result, and an emptiness test)"
fi

# The executed legs run the layer's own verify step: extracted from the
# SHASUMS grep line through the sha256sum line, continuations joined into
# one '&&' chain, and the layer's /tmp rewritten to the fixture dir — so a
# single-line, subshell-wrapped, or multi-line capture-and-guard spelling
# all execute identically.
extract_verify() { # $1 = Dockerfile path; prints the verify chain, or nothing
  layer_block NODE_VERSION "$1" | awk '
    {
      line = $0
      sub(/\\[[:space:]]*$/, "", line)
      sub(/^[[:space:]]*(&&[[:space:]]*)+/, "", line)
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+&&$/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (started) {
        seg = seg " && " line
      } else if (line ~ /grep/ && (line ~ /SHASUMS/ || line ~ /linux-x64/)) {
        started = 1
        seg = line
      } else {
        next
      }
      if (line ~ /sha256sum/) { print seg; exit }
    }
  '
}

scratch=$(mktemp -d "${TMPDIR:-/tmp}/cf6-c02-XXXXXX" 2>/dev/null || true)
if [ -z "$scratch" ]; then
  fail "c7e: scratch fixture dir could not be created"
  fail "c7f: scratch fixture dir could not be created"
  fail "c7g: scratch fixture dir could not be created"
else
  trap 'rm -rf "$scratch"' EXIT
  mkdir -p "$scratch/pos" "$scratch/neg" "$scratch/bin"
  printf 'cf-6 C02 fixture payload — never a real node artifact\n' > "$scratch/pos/$node_xz"
  cp "$scratch/pos/$node_xz" "$scratch/neg/$node_xz"
  real_sha=$(command -v sha256sum)
  real_hex=$("$real_sha" "$scratch/pos/$node_xz" | cut -d' ' -f1)
  fake_hex=$(printf 'f%.0s' {1..64})

  # The executed legs run behind a lenient-checker stand-in: coreutils >=8.31
  # refuses empty stdin to sha256sum -c with exit 1 ("no properly formatted
  # checksum lines"), so on THIS host's tool the historical pipe dies by a
  # version accident rather than by design — and any pre-8.31 behaviour, a
  # re-implemented coreutils on the runner, or a checksum step fed a
  # non-matching-but-well-formed line is the silent exit 0 the doctrine is
  # written against. The stub emulates exactly the vacuous semantics (empty
  # input => exit 0, no output; real input => delegate unchanged), so the
  # legs ask "can this layer pass verification while checking nothing?" —
  # a structural question — instead of "what does today's coreutils do?".
  cat > "$scratch/bin/sha256sum" <<EOF
#!/bin/sh
f=\$(mktemp)
cat > "\$f"
if [ ! -s "\$f" ]; then rm -f "\$f"; exit 0; fi
"$real_sha" "\$@" < "\$f"
rc=\$?
rm -f "\$f"
exit \$rc
EOF
  chmod +x "$scratch/bin/sha256sum"

  # Vendor SHASUMS256.txt form: "<hex><space><space><name>", one line per
  # release artifact; the two-space gap is what the layer's single-leading-
  # space grep pattern anchors on. Neighbour artifacts sit on either side so
  # the anchored match must pick OUR line, not any line.
  {
    printf '%s  node-v%s-headers.tar.gz\n' "$fake_hex" "$node_ver"
    printf '%s  %s\n' "$real_hex" "$node_xz"
    printf '%s  node-v%s-linux-arm64.tar.xz\n' "$fake_hex" "$node_ver"
  } > "$scratch/pos/SHASUMS256.txt"

  # A vendor file that names nothing matching our artifact: the tarball is on
  # disk with its true hex known, so any green must come from a real match.
  # "Nothing matched" must be data, never green (the family's AD-133 class).
  {
    printf '%s  node-v9.9.9-linux-x64.tar.xz\n' "$real_hex"
    printf '%s  node-v%s-linux-arm64.tar.xz\n' "$real_hex" "$node_ver"
    printf '%s  node-v%s-linux-x64.tar.gz\n' "$real_hex" "$node_ver"
  } > "$scratch/neg/SHASUMS256.txt"

  run_verify() { # $1 = verify command (Dockerfile text), $2 = fixture dir;
                 # sets RUN_RC and RUN_OUT (stdout only, like the layer sees).
                 # No pipefail: the chain's emptiness guard, not grep's own
                 # exit status, is what must refuse here.
    local cmd="${1//\/tmp/$2}"
    RUN_OUT=$(cd "$2" && env PATH="$scratch/bin:$PATH" NODE_VERSION="$node_ver" bash -c "$cmd" 2>/dev/null)
    RUN_RC=$?
  }

  seg=$(extract_verify "$DOCKERFILE")
  if [ -z "$seg" ]; then
    fail "c7e: no verify step extractable from the node layer (nothing from the SHASUMS grep through sha256sum)"
    fail "c7f: no verify step extractable from the node layer (nothing from the SHASUMS grep through sha256sum)"
  else
    run_verify "$seg" "$scratch/pos"
    if [ "$RUN_RC" -eq 0 ] && printf '%s\n' "$RUN_OUT" | grep -Fq "$node_xz: OK"; then
      pass "c7e: extracted verify line exits 0 on the matching vendor line and claims '${node_xz}: OK'"
    else
      fail "c7e: extracted verify line exited ${RUN_RC} with '${RUN_OUT:-<no output>}'; want exit 0 plus the '${node_xz}: OK' claim — the OK line is the only stdout proof that a checksum was actually checked, and the old pipe never printed one"
    fi

    run_verify "$seg" "$scratch/neg"
    if [ "$RUN_RC" -ne 0 ]; then
      pass "c7f: extracted verify line refuses a SHASUMS256.txt with no matching entry (exit ${RUN_RC})"
    else
      fail "c7f: extracted verify line exited 0 with '${RUN_OUT:-<no output>}' though no listed checksum matches the fetched file — the empty-grep-green is still structurally possible"
    fi
  fi

  # c7g — negative control, GREEN at authoring and green by design after the
  # fix: the historical verify line embedded VERBATIM here (not read from the
  # Dockerfile — dev will remove it there) run against c7f's mismatched
  # fixture under the lenient stand-in checker. It exits 0 with empty stdout:
  # the exact vacuous pass, pinned as the mutation column proving c7f's
  # non-zero exit is decided by the layer's guard, not by fixture luck or
  # coreutils behaviour.
  run_verify '(cd /tmp && grep " node-${NODE_VERSION}-linux-x64.tar.xz$" SHASUMS256.txt | sha256sum -c -)' "$scratch/neg"
  if [ "$RUN_RC" -eq 0 ] && [ -z "$RUN_OUT" ]; then
    pass "c7g: the historical empty-grep pipe passes silently when the checker accepts empty input (documents the vacuity c7f must now refuse)"
  else
    fail "c7g: historical verify line exited ${RUN_RC} with '${RUN_OUT:-<empty>}' — expected the documented vacuous exit 0 with no output"
  fi
fi

echo "=== image-structure: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
