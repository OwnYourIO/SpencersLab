#!/usr/bin/env bash
# C02 contract (ticket 2026-10-cf-11-feat-immich-hugo-pipeline) for
# containers/forgejo-host-runner/Dockerfile — the ONE image the host-backend
# runner pod runs. No docker daemon exists in agent sessions (Coder
# workspace), so the gate is static-contract + hadolint, and the build leg
# reports the designed-passing shape "docker build => no-daemon, CI-deferred"
# (ruled 2026-10-28, cf-77; AGENTS "Pipeline specifics in this repo").
#
# AC trace (chunks/C02.md): t1[AC3 FROM pins] t2[AC3 renovate annotations]
# t3[AC5 USER/HOME] t4[AC3+image contract hugo extended 0.151.0] t5[AC5
# binary paths — the C03 chart command contract] t6[AC2 no secrets, no COPY
# . .] t7[.dockerignore excludes tests] t8[C01 regression guard] t9[AC1
# hadolint] t10[designed docker-build shape].
#
# Structure follows tests/containers/wekan-mcp-login.sh (fail/ok/skip +
# per-leg subset args) and the tests/services render-from-copy convention.
#
# Run from the repo root:
#   bash tests/containers/forgejo-host-runner.sh          # t1..t10
#   bash tests/containers/forgejo-host-runner.sh t4 t9    # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

CONTAINER_DIR="containers/forgejo-host-runner"
DF="$CONTAINER_DIR/Dockerfile"
DI="$CONTAINER_DIR/.dockerignore"

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
  for i in $(seq 1 10); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t([1-9]|10)$ ]] || fail "unknown test id '$a' (expected t1..t10)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# The Dockerfile is the contract subject — its absence is the chunk
# not-yet-implemented state (red-first), not a skip.
if want t1 || want t2 || want t3 || want t4 || want t5 || want t6; then
  [ -f "$DF" ] || fail "$DF does not exist (the C02 image contract has nothing to check)"
fi

# --- t1: FROM pins (AC3) ------------------------------------------------------
if want t1; then
  froms=$(grep -E '^FROM ' "$DF" || true)
  n_from=$(printf '%s\n' "$froms" | grep -cE '^FROM ' || true)
  [ "$n_from" -ge 2 ] ||
    fail "t1: expected a multi-stage build with >=2 FROM lines, found $n_from"
  while IFS= read -r f; do
    img=$(printf '%s' "$f" | awk '{print $2}')
    case "$img" in
      scratch) continue ;;
      *:*) : ;;
      *) fail "t1: FROM '$img' floats without a tag or digest" ;;
    esac
    case "$img" in
      *:latest) fail "t1: FROM '$img' floats on :latest" ;;
    esac
  done <<<"$froms"
  runner_from=$(printf '%s\n' "$froms" | grep 'data.forgejo.org/forgejo/runner:' || true)
  [ -n "$runner_from" ] ||
    fail "t1: no donor FROM line for data.forgejo.org/forgejo/runner:<tag> (image contract /bin/forgejo-runner)"
  runner_tag=$(printf '%s' "$runner_from" | sed -E 's#.*forgejo/runner:([0-9][0-9a-zA-Z._-]*).*#\1#')
  awk -v t="$runner_tag" 'BEGIN { split(t, p, "."); exit !(p[1] >= 13 && (p[1] > 13 || p[2] >= 2)) }' ||
    fail "t1: runner donor tag $runner_tag is below the 13.2 floor (C02 shape pins 13.2.1)"
  printf '%s\n' "$froms" | grep -qE 'node:22[-a-z]*' ||
    fail "t1: no node:22 base (netlify-cli needs Node >=18.14; the shape pins 22-bookworm-slim)"
  ok "t1: $n_from FROM lines all carry concrete pins; runner donor $runner_tag >= 13.2; node 22 base"
fi

# --- t2: renovate annotations on every ARG version pin (AC3) ------------------
if want t2; then
  n_ann=$(grep -cE '^# renovate:' "$DF" || true)
  [ "$n_ann" -ge 1 ] || fail "t2: the Dockerfile carries no renovate annotation lines"
  # Every annotation well-formed (datasource + depName; registryUrl optional).
  bad=$(grep -E '^# renovate:' "$DF" | grep -vE '^# renovate: datasource=[A-Za-z0-9_-]+ depName=[^ ]+( registryUrl=https://[^ ]+)?$' || true)
  [ -z "$bad" ] || fail "t2: malformed renovate annotation(s): $bad"
  grep -qE '^# renovate: datasource=docker depName=forgejo/runner registryUrl=https://data.forgejo.org' "$DF" ||
    fail "t2: the data.forgejo.org runner donor FROM has no docker-datasource annotation (that registry is not renovate's default lookup — the annotation makes the pin trackable)"
  grep -qE '^# renovate: datasource=github-releases depName=gohugoio/hugo' "$DF" ||
    fail "t2: no github-releases hugo annotation"
  grep -qE '^# renovate: datasource=npm depName=netlify-cli' "$DF" ||
    fail "t2: no npm netlify-cli annotation"
  # Each versioned ARG carries an annotation (or the documented manual-pin
  # fallback — C02 notes) within the 3 lines above it. Placement is above,
  # not the inline-sketch ordering of the chunk shape: renovate's
  # dockerfile-args manager binds an annotation to the line DIRECTLY BELOW
  # it — an annotation written after its ARG is inert.
  while IFS= read -r argline; do
    ln=$(printf '%s' "$argline" | cut -d: -f1)
    window=$(sed -n "$((ln > 3 ? ln - 3 : 1)),${ln}p" "$DF")
    printf '%s' "$window" | grep -qE '# renovate:|# manual-pin:' ||
      fail "t2: ARG pin at line $ln has no renovate (or manual-pin) annotation above it: $(printf '%s' "$argline" | cut -d: -f2-)"
  done < <(grep -nE '^ARG [A-Z_]+=[0-9][0-9a-zA-Z._-]*' "$DF" || true)
  ok "t2: $n_ann well-formed annotations cover the docker, hugo and netlify-cli pins and every ARG version line"
fi

# --- t3: non-root uid + HOME on the PVC (AC5) ----------------------------------
if want t3; then
  grep -qE '^USER node' "$DF" ||
    fail "t3: no USER node — uid 1000 is the chart fsGroup/cache contract; root would break the PVC mounts"
  grep -qE '^ENV HOME=/data' "$DF" ||
    fail "t3: no ENV HOME=/data — act cache + dotfiles must land on the PVC (chart comment contract)"
  ok "t3: USER node + ENV HOME=/data (image contract for C03)"
fi

# --- t4: hugo EXTENDED at the site pin -----------------------------------------
if want t4; then
  grep -qE '^ARG HUGO_VERSION=0\.151\.0$' "$DF" ||
    fail "t4: ARG HUGO_VERSION is not pinned to 0.151.0 (netlify.toml's exact pin — the render must reproduce Netlify's output)"
  grep -qE 'hugo_extended' "$DF" ||
    fail "t4: the hugo download does not name the EXTENDED edition — .Resize/SCSS work needs extended, not the base binary"
  grep -qE '\$\{?HUGO_VERSION\}?[^ ]*linux-amd64|linux-amd64[^ ]*hugo_extended' "$DF" ||
    fail "t4: the hugo asset URL is not the linux-amd64 release asset shape"
  ok "t4: hugo extended 0.151.0 linux-amd64"
fi

# --- t5: image contract paths C03's chart command assumes ----------------------
if want t5; then
  # RUN lines wrap with trailing backslashes in the pinned shape; join them
  # so package-list and COPY greps see one logical line.
  flat=$(sed -e ':a' -e 'N' -e '$!ba' -e 's/\\\n[[:space:]]*/ /g' "$DF")
  apt_line=$(printf '%s\n' "$flat" | grep -oE 'apt(-get)? install[^&|;]*' | head -n 1 || true)
  [ -n "$apt_line" ] || fail "t5: no apt-get install line found"
  grep -qE 'COPY --from=[a-z-]+ [^ ]*/bin/forgejo-runner /bin/forgejo-runner' "$DF" ||
    fail "t5: no COPY of the forgejo-runner binary to /bin/forgejo-runner (the chart command path)"
  printf '%s' "$apt_line" | grep -q 'dumb-init' ||
    fail "t5: dumb-init is not apt-installed (the chart commands /usr/bin/dumb-init explicitly)"
  { grep -qE '/usr/local/bin/hugo' "$DF" ||
    printf '%s\n' "$flat" | grep -E 'tar[^|;]*-C +/usr/local/bin' | grep -q 'hugo'; } ||
    fail "t5: hugo is not placed at /usr/local/bin/hugo (direct path or tar -C /usr/local/bin)"
  printf '%s\n' "$flat" | grep -qE 'npm (install|i)( -g|--global) netlify-cli' ||
    fail "t5: netlify-cli is not npm-installed global (the /usr/local/bin/netlify contract)"
  printf '%s\n' "$flat" | grep -qE 'COPY +sync/ /opt/immich-hugo-sync/' ||
    fail "t5: C01's sync/ package is not COPYed to /opt/immich-hugo-sync/ (no code duplication — AC4)"
  printf '%s\n' "$flat" | grep -q '/usr/local/bin/immich-hugo-sync' ||
    fail "t5: the immich-hugo-sync entry point is not created under /usr/local/bin"
  printf '%s\n' "$flat" | grep -q '/usr/local/bin/immich-hugo-publish' ||
    fail "t5: the immich-hugo-publish entry point is not created under /usr/local/bin"
  for tool in git git-lfs curl jq zstd python3 ca-certificates; do
    printf '%s' "$apt_line" | grep -qE "(^|[[:space:]])$tool($|[[:space:]])" ||
      fail "t5: apt install list lacks $tool (job-surface contract)"
  done
  ok "t5: every image-contract path is built by the Dockerfile"
fi

# --- t6: secret hygiene + build-context discipline ----------------------------
if want t6; then
  if grep -nEi '(ghp_[A-Za-z0-9]{10,}|github_pat_[A-Za-z0-9_]{10,}|nfp_[A-Za-z0-9]{10,}|AKIA[0-9A-Z]{8,}|xox[abposr]-|eyJ[A-Za-z0-9_-]{10,})' "$DF"; then
    fail "t6: a token-shaped literal appears in the Dockerfile"
  fi
  creds=$(grep -nEi '[[:space:]](token|password|secret|api[-_]?key)[a-z_]*[[:space:]]*=[[:space:]]*["'"'"']?[A-Za-z0-9+/=._-]{16,}' "$DF" |
    grep -vE '\$\{|version' || true)
  [ -z "$creds" ] || fail "t6: credential-shaped literal assignment(s): $creds (no secrets in any layer)"
  grep -qE '^COPY \. \.' "$DF" &&
    fail "t6: COPY . . from the repo root — the build context is the container dir by workflow convention"
  ok "t6: no secret literals, no root-context COPY"
fi

# --- t7: .dockerignore ---------------------------------------------------------
if want t7; then
  [ -f "$DI" ] || fail "t7: $DI is missing"
  grep -qE '^tests/?\*?$' "$DI" || fail "t7: .dockerignore does not exclude tests/"
  ok "t7: .dockerignore excludes tests/"
fi

# --- t8: C01 regression guard ---------------------------------------------------
if want t8; then
  [ -d "$CONTAINER_DIR/sync" ] ||
    fail "t8: $CONTAINER_DIR/sync does not exist (C01 modules are the COPY source)"
  if python3 -m compileall -q "$CONTAINER_DIR/sync"; then
    ok "t8: python3 -m compileall $CONTAINER_DIR/sync is green"
  else
    fail "t8: python3 -m compileall failed for $CONTAINER_DIR/sync"
  fi
fi

# --- t9: hadolint (AC1) ---------------------------------------------------------
if want t9; then
  export PATH="$HOME/.local/bin:$PATH"
  if ! command -v hadolint >/dev/null 2>&1; then
    skip "t9: hadolint not available here; AC1 was not exercised (CI leg stands)"
  elif hadolint --failure-threshold error "$DF" >/tmp/opencode/hadolint-forgejo-host-runner.log 2>&1; then
    # error threshold = the AC1 wording ("no errors"); the fleet itself
    # carries warning-level DL3008 findings (containers/strata), so failing
    # on warnings here would hold this image above the repo's own bar.
    ok "t9: hadolint reports no errors on $DF"
  else
    tail -n 40 /tmp/opencode/hadolint-forgejo-host-runner.log >&2
    fail "t9: hadolint reported findings (log kept at /tmp/opencode/hadolint-forgejo-host-runner.log)"
  fi
fi

# --- t10: docker build (designed shape) -----------------------------------------
if want t10; then
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if docker build "$CONTAINER_DIR" -t forgejo-host-runner:contract >/tmp/opencode/forgejo-host-runner-build.log 2>&1; then
      ok "t10: docker build $CONTAINER_DIR succeeds"
    else
      tail -n 40 /tmp/opencode/forgejo-host-runner-build.log >&2
      fail "t10: docker build failed (log kept at /tmp/opencode/forgejo-host-runner-build.log)"
    fi
  else
    # Not a deviation: docker-build.yaml on the merged main IS the build
    # authority for containers (AGENTS 'Pipeline specifics'); the static
    # contract above is this session's share of AC2.
    ok "t10: docker build => no-daemon, CI-deferred (designed passing shape)"
  fi
fi

printf 'PASS: forgejo-host-runner container checks (%d ok)\n' "$checks"
