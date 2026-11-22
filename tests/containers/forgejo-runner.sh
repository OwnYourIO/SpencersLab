#!/usr/bin/env bash
# C05 contract (cf-55 fix round, ticket 2026/2026-11-cf-55-feat-helm-builds-to-
# forgejo) for containers/forgejo-runner/Dockerfile — the act job image the lab
# builds itself after the release pipeline's FIRST FIRE died on a read
# ECONNRESET downloading helm from get.helm.sh inside the runner's "Set up
# helm" step (D33: the toolchain bakes at IMAGE build time; workflow jobs
# install nothing). Modeled on tests/containers/forgejo-host-runner.sh: no
# docker daemon exists in agent sessions (Coder workspace), so the gate is a
# static contract + hadolint, and the build leg reports the designed-passing
# shape "docker build => no-daemon, CI-deferred" (ruled 2026-10-28, cf-77;
# AGENTS "Pipeline specifics in this repo") — the merge fire's own
# containers-build.yaml run is the authoritative build test, and detection is
# path-based (scripts/forgejo-container-detect.sh gates on the containers/**
# diff + a DNS-safe name + Dockerfile presence), so nothing registers this
# image anywhere (D36/§F3).
#
# AC trace (chunks/C05.md): t1[AC3 single FROM, digest-pinned act-24.04]
# t2[AC4 ARG pins, directly-above renovate annotations, the cr pin pair]
# t3[AC5 helm baked at build time, coder-workspace :142-149 recipe shape]
# t4[AC5 cr baked, sha256-pair verified, D37] t5[the C07/D43 call surface:
# both tools on the default PATH] t6[AC5+D36 base-preserving: no COPY/USER/
# ENTRYPOINT/CMD/ADD, no apt, the root-job-shell deviation comment] t7[AC2
# hadolint at the error threshold, honest skip] t8[AC2 designed CI-deferred
# build shape].
#
# Red-first: the image arrives with C05; a missing Dockerfile is the chunk-
# not-yet-implemented state, not a skip.
#
# Run from the repo root:
#   bash tests/containers/forgejo-runner.sh          # t1..t8
#   bash tests/containers/forgejo-runner.sh t3 t7    # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

CONTAINER_DIR="containers/forgejo-runner"
DF="$CONTAINER_DIR/Dockerfile"

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
  for i in $(seq 1 8); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-8]$ ]] || fail "unknown test id '$a' (expected t1..t8)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# t8 reports the designed no-daemon shape whether or not the Dockerfile
# exists yet (t10 precedent); every other leg has the file as its subject.
if want t1 || want t2 || want t3 || want t4 || want t5 || want t6 || want t7; then
  [ -f "$DF" ] || fail "$DF does not exist (the C05 image contract has nothing to check)"
fi

# --- t1: one FROM, digest-pinned act-24.04 base (AC3) ------------------------
if want t1; then
  n_from=$(grep -cE '^FROM ' "$DF" || true)
  [ "$n_from" -eq 1 ] ||
    fail "t1: expected exactly one FROM line, found $n_from — D36 ships a single-stage derivative whose output IS the job image"
  img=$(grep -E '^FROM ' "$DF" | awk '{print $2}')
  case "$img" in
    ghcr.io/catthehacker/ubuntu:act-24.04@sha256:*) : ;;
    *) fail "t1: FROM '$img' is not ghcr.io/catthehacker/ubuntu:act-24.04 carrying an @sha256: digest — the RESEARCH C1 inventory rides the current act-24.04 content (the no-regression law), and dev pins the digest the live head shows at dev time, not the plan-time one (C05)" ;;
  esac
  hex=${img##*@sha256:}
  printf '%s' "$hex" | grep -qE '^[0-9a-f]{64}$' ||
    fail "t1: FROM digest '$hex' is not 64 hex characters"
  ok "t1: single FROM, ghcr.io/catthehacker/ubuntu:act-24.04 with a 64-hex digest pin (tag kept for humans, digest the authority)"
fi

# --- t2: ARG pins + directly-adjacent renovate annotations (AC4) -------------
if want t2; then
  # renovate's Dockerfile ARG manager binds an annotation to the line
  # DIRECTLY below it (renovate.json:117) — placement one line off is an inert
  # pin that still LOOKS tracked (forgejo-host-runner t2's lesson).
  argln() { grep -nE "^ARG $1=" "$DF" | head -n 1 | cut -d: -f1 || true; }
  check_pin() { # $1 ARG name, $2 exact value, $3 annotation line, $4 label
    local ln val prev
    ln=$(argln "$1")
    [ -n "$ln" ] || fail "t2: no ARG $1 line"
    val=$(sed -n "${ln}p" "$DF" | cut -d= -f2-)
    [ "$val" = "$2" ] ||
      fail "t2: ARG $1 is '$val', expected the ruled pin $2 ($4)"
    prev=$((ln - 1))
    prev_line=$(sed -n "${prev}p" "$DF" | sed 's/[[:space:]]*$//')
    if [ "$prev_line" != "$3" ]; then
      fail "t2: the line directly above ARG $1 is not the annotation $3 (adjacency is what makes the pin renovate-tracked — the manager regex at renovate.json:112-121 binds the comment to the ARG on its next line; placement one line off is an inert pin)"
    fi
  }
  check_pin HELM_VERSION 'v3.22.1' '# renovate: datasource=github-releases depName=helm/helm' \
    'D38 adopts the v3.22.1 line (the coder-workspace baked pin + the GitHub-hosted preinstall equivalent), not the first-fire v3.16.4'
  check_pin CR_VERSION '1.10.1' '# renovate: datasource=github-releases depName=helm/chart-releaser' \
    'D37 migrates the workflow-verified cr version pin into the Dockerfile'
  ln=$(argln CR_SHA256); [ -n "$ln" ] || fail "t2: no ARG CR_SHA256 line — the verified archive digest must ride with the version pin"
  val=$(sed -n "${ln}p" "$DF" | cut -d= -f2-)
  [ "$val" = 'ce46baf9975d10193b7070b2b7406750c3f664181e36df3f3bbb4a00be40dc1b' ] ||
    fail "t2: ARG CR_SHA256 is '$val', expected the sha the C01 review verified against the chart-releaser 1.10.1 checksums.txt (D37)"
  window=$(sed -n "$((ln > 4 ? ln - 4 : 1)),$((ln - 1))p" "$DF")
  printf '%s' "$window" | grep -q '# manual-pin:' ||
    fail "t2: ARG CR_SHA256 carries no '# manual-pin:' why-comment above it — the digest rides OUTSIDE renovate deliberately (HUGO/GO/FJ precedent): it must bump with CR_VERSION by hand, and a stale digest has to fail the build loudly"
  printf '%s' "$window" | grep -qiE 'bump|version' ||
    fail "t2: the CR_SHA256 manual-pin comment must state the bump-with-version law"
  ok "t2: helm v3.22.1 + cr 1.10.1 pins with directly-adjacent renovate annotations; CR_SHA256 exact with its manual-pin why-comment"
fi

# --- t3: helm bakes at BUILD time via the coder-workspace recipe (AC5) -------
if want t3; then
  # RUN lines wrap with trailing backslashes in the pinned shape; join them so
  # each logical command reads as one line (t5 idiom, forgejo-host-runner).
  flat=$(sed -e ':a' -e 'N' -e '$!ba' -e 's/\\\n[[:space:]]*/ /g' "$DF")
  printf '%s' "$flat" | grep -qE 'https://get\.helm\.sh/helm-\$\{?HELM_VERSION\}?-linux-amd64\.tar\.gz' ||
    fail "t3: no get.helm.sh tarball URL expanding HELM_VERSION — the bake moves the download from every job to this one audited build lane (D33/D38)"
  printf '%s' "$flat" | grep -qE 'helm-\$\{?HELM_VERSION\}?-linux-amd64\.tar\.gz\.sha256sum' ||
    fail "t3: the .sha256sum sidecar is not fetched — coder-workspace:142-149 recipe shape (D38)"
  printf '%s' "$flat" | grep -qE 'sha256sum -c' ||
    fail "t3: the helm tarball is not sha256sum -c verified"
  printf '%s' "$flat" | grep -qE 'install -m 0755[^&|;]*/usr/local/bin/helm($|[^A-Za-z0-9_-])' ||
    fail "t3: no install -m 0755 of the extracted binary to /usr/local/bin/helm"
  printf '%s' "$flat" | grep -qE 'helm version[^;]*HELM_VERSION' ||
    fail "t3: no build-time helm version assert against HELM_VERSION — a mis-baked tool must fail the BUILD, not the next release fire"
  ok "t3: helm bakes at build time from get.helm.sh, sidecar-verified, asserted"
fi

# --- t4: cr bakes sha-verified from the release asset (AC5, D37) --------------
if want t4; then
  flat=$(sed -e ':a' -e 'N' -e '$!ba' -e 's/\\\n[[:space:]]*/ /g' "$DF")
  printf '%s' "$flat" | grep -qE 'https://github\.com/helm/chart-releaser/releases/download/v\$\{?CR_VERSION\}?/chart-releaser_\$\{?CR_VERSION\}?_linux_amd64\.tar\.gz' ||
    fail "t4: no chart-releaser release-asset URL expanding CR_VERSION — the release.yaml :294-308 install promotes to build time (D37)"
  printf '%s' "$flat" | grep -qE 'CR_SHA256[^;&]*sha256sum -c|sha256sum -c[^;&]*CR_SHA256' ||
    fail "t4: the cr archive is not sha256-verified against \${CR_SHA256} on its own install line — the bare fetch reopens the supply-chain question the pin closed"
  printf '%s' "$flat" | grep -qE 'tar [^&|;]*-C[[:space:]]+/usr/local/bin[[:space:]]+cr($|[^A-Za-z0-9_-])' ||
    fail "t4: no binary-only extract (tar -xzf ... -C /usr/local/bin cr)"
  printf '%s' "$flat" | grep -qE 'chmod 0755[[:space:]]+/usr/local/bin/cr($|[^A-Za-z0-9_-])' ||
    fail "t4: no chmod 0755 /usr/local/bin/cr"
  printf '%s' "$flat" | grep -qE 'cr --version' ||
    fail "t4: no build-time 'cr --version' assert"
  ok "t4: cr 1.10.1 bakes through the verified pin pair, binary-only, asserted"
fi

# --- t5: default-PATH binaries — the C07 call surface -------------------------
if want t5; then
  flat=$(sed -e ':a' -e 'N' -e '$!ba' -e 's/\\\n[[:space:]]*/ /g' "$DF")
  printf '%s' "$flat" | grep -qE '/usr/local/bin/helm($|[^A-Za-z0-9_-])' ||
    fail "t5: helm does not land at /usr/local/bin/helm"
  printf '%s' "$flat" | grep -qE '/usr/local/bin/cr($|[^A-Za-z0-9_-])' ||
    fail "t5: cr does not land at /usr/local/bin/cr"
  if printf '%s' "$flat" | grep -qE '\.cr-bin|GITHUB_PATH'; then
    fail "t5: a HOME-scoped install or a PATH-extension dance survives — the C07 baked posture deletes every 'Set up helm'/'Install cr' step, so the release workflows' PLAIN helm/cr invocations must resolve off the default PATH immediately (D43: the invocation IS the check)"
  fi
  ok "t5: both tools land at the default-PATH names plain workflow invocations resolve"
fi

# --- t6: base-preserving derivative (AC5, D36) --------------------------------
if want t6; then
  for instr in USER ENTRYPOINT CMD COPY ADD; do
    if grep -qE "^$instr[[:space:]]" "$DF"; then
      fail "t6: a $instr line enters the Dockerfile — the image is the act base plus two static binaries and NOTHING else (C05 AC5: no COPY/USER/ENTRYPOINT/CMD; D36 keeps the base's job shell)"
    fi
  done
  if grep -qE 'apt(-get)?[[:space:]]+(install|update)' "$DF"; then
    fail "t6: apt work in the Dockerfile — the RESEARCH C1 inventory (git/git-lfs/jq/python3/node/yq/docker CLI+buildx+compose) is inherited, not rebuilt; adding packages risks regressing it"
  fi
  if ! grep -E '^#' "$DF" | grep -qiE 'root' || ! grep -E '^#' "$DF" | grep -qiE 'job|USER'; then
    fail "t6: no deviation comment on the root job shell — the container-creation non-root law serves SERVICE containers; a job image deliberately keeps the base's root user because today's jobs apt-get and write system paths, and a USER line would regress them (D36). The Dockerfile records the why."
  fi
  ok "t6: pure base superset — no COPY/USER/ENTRYPOINT/CMD/ADD/apt lines, root-job-shell deviation documented"
fi

# --- t7: hadolint (AC2, error threshold per the repo bar) ---------------------
if want t7; then
  export PATH="$HOME/.local/bin:$PATH"
  if ! command -v hadolint >/dev/null 2>&1; then
    skip "t7: hadolint not available here; the lint leg was not exercised (CI leg stands)"
  elif hadolint --failure-threshold error "$DF" >/tmp/opencode/hadolint-forgejo-runner.log 2>&1; then
    # error threshold, not warning (forgejo-host-runner t9's reasoning): the
    # act base is a huge Ubuntu image and warning-level findings are inherited
    # state no line of this Dockerfile can remove.
    ok "t7: hadolint reports no errors on $DF"
  else
    tail -n 40 /tmp/opencode/hadolint-forgejo-runner.log >&2
    fail "t7: hadolint reported findings (log kept at /tmp/opencode/hadolint-forgejo-runner.log)"
  fi
fi

# --- t8: docker build (designed passing shape, cf-77) -------------------------
if want t8; then
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if docker build "$CONTAINER_DIR" -t forgejo-runner:contract >/tmp/opencode/forgejo-runner-build.log 2>&1; then
      ok "t8: docker build $CONTAINER_DIR succeeds"
    else
      tail -n 40 /tmp/opencode/forgejo-runner-build.log >&2
      fail "t8: docker build failed (log kept at /tmp/opencode/forgejo-runner-build.log)"
    fi
  else
    # Not a deviation: the containers-build.yaml run on the merged main IS the
    # build authority for containers (AGENTS 'Pipeline specifics'); the static
    # contract above is this session's share. This line is the DESIGNED
    # passing shape for the image legs (cf-77 ruling), not a failure.
    ok "t8: docker build => no-daemon, CI-deferred (designed passing shape)"
  fi
fi

printf 'PASS: forgejo-runner container checks (%d ok)\n' "$checks"
