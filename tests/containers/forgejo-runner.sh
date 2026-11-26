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
# build-containers.yaml run is the authoritative build test, and detection is
# path-based (scripts/forgejo-container-detect.sh gates on the containers/**
# diff + a DNS-safe name + Dockerfile presence), so nothing registers this
# image anywhere (D36/§F3).
#
# AC trace (run -4 chunks/C01.md; the C05 single-stage AC numbering is
# superseded by the source change): t1[AC1 exactly three FROM lines —
# helmtool + crtool stages with their full digests, act-24.04 final]
# t2[AC2/AC3 HELM_VERSION/CR_VERSION annotation adjacency kept verbatim, the
# HELM_BIN_SHA256/CR_BIN_SHA256 manual-pin pair, CR_SHA256 banned] t3[AC1/
# AC3/AC4 helm stage FROM, COPY --from transport, binary anchor, version
# assert, no get.helm.sh RUN operand] t4[AC4 cr stage FROM, COPY --from
# transport, binary anchor, 'cr version' assert with the --version ban, no
# releases/download RUN operand] t5[the C07/D43 call surface: both tools on
# the default PATH] t6[AC4/AC5+D36 base-preserving: the COPY ban carves out
# COPY --from, bare COPY/ADD/USER/ENTRYPOINT/CMD/apt bans stand, the root-
# job-shell deviation comment] t7[AC2 hadolint at the error threshold,
# honest skip] t8[AC2 designed CI-deferred build shape].
#
# Retirement note (the run -3 retry pins, 2026-11-23): t3/t4 pinned a
# deterministic curl retry budget on the three bake fetches after lane
# dispatch #215 died of the D33 egress class (curl TLS exit 35 mid-
# handshake; --retry-all-errors is what makes curl retry that class).
# Three dispatches on the budgeted path died identically while ghcr pulls,
# the Forgejo API and the GitHub API worked from the same egress: upstream
# policy filtering of get.helm.sh against this address, not a path fault.
# Run -4 therefore changed the source, not the path — helm and cr arrive by
# COPY --from from digest-pinned tool images — and the fetch-shape pin
# texts retire here. The pair law for the moved literals: every pin and the
# Dockerfile shape it describes land in the same commit.
#
# Authored-RED (run -4 posture, inverted vs run -3, plan F1/F6): t1, the t2
# BIN arms, t3, t4 and t6 pin the family-A multi-stage form and measure RED
# against BASE bc4b2a3fa (the curl-form Dockerfile) by design; GREEN only
# against the Dockerfile DEV lands in the same commit. t5/t7/t8 are green
# against both forms — t5's destination-path pins match the COPY targets and
# its .cr-bin/GITHUB_PATH ban stays clean because the stages are named
# helmtool/crtool. A missing Dockerfile is still the chunk-not-yet-
# implemented state, not a skip.
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

# --- t1: exactly three FROM lines — two tool stages + the act base (AC1) --
if want t1; then
  n_from=$(grep -cE '^FROM ' "$DF" || true)
  [ "$n_from" -eq 3 ] ||
    fail "t1: expected exactly three FROM lines (helm stage, cr stage, act-24.04 base), found $n_from — since run -4 the bake is multi-stage: the digest-pinned tool images replaced the get.helm.sh/github.com fetches, and on every stage line the digest is the authority while the tag is the human label"
  from1=$(grep -E '^FROM ' "$DF" | sed -n 1p)
  from2=$(grep -E '^FROM ' "$DF" | sed -n 2p)
  from3=$(grep -E '^FROM ' "$DF" | sed -n 3p)
  printf '%s\n' "$from1" | grep -qE '^FROM docker\.io/alpine/helm:3\.22\.1@sha256:8191701ad1f82ee3695c87211fcbfe6d7b1bb7df92ac1c8de9ccdb0995a6a2c1 AS helmtool$' ||
    fail "t1: the first FROM line is '$from1', expected the helm tool stage — alpine/helm:3.22.1 carrying the multi-arch INDEX digest that tag serves (plan F2; the amd64 manifest 83dd7afc... would be the wrong anchor class), named AS helmtool. The digest, not the rolling tag, is the authority"
  printf '%s\n' "$from2" | grep -qE '^FROM ghcr\.io/helm/chart-releaser:v1\.10\.1-amd64@sha256:f04f886affa5ba55b004788591b56f35bfd79abca9f85f0cb2f61c2f90bbe84c AS crtool$' ||
    fail "t1: the second FROM line is '$from2', expected the official cr image stage — ghcr.io/helm/chart-releaser:v1.10.1-amd64 carrying the MANIFEST digest that per-arch tag serves (plan F3: pin what the tag serves — the v1.10.1 index 51758f90... would be the wrong anchor class), named AS crtool"
  case "$from3" in
    'FROM ghcr.io/catthehacker/ubuntu:act-24.04@sha256:'*) : ;;
    *) fail "t1: the third FROM line is '$from3', not an @sha256-pinned act-24.04 base — the final stage is the job image: D36's inherited-toolchain inventory rides the current act-24.04 content (the no-regression law), dev pins the digest the live head shows at dev time rather than the plan-time one, and the digest stays the authority over the rolling tag" ;;
  esac
  hex=${from3##*@sha256:}
  printf '%s' "$hex" | grep -qE '^[0-9a-f]{64}$' ||
    fail "t1: the act-24.04 FROM digest '$hex' is not 64 hex characters"
  ok "t1: three FROM lines in order — helmtool + crtool stages with their full measured digests, act-24.04 final with a 64-hex digest pin"
fi

# --- t2: ARG pins kept verbatim, binary anchors added, CR_SHA256 retired ---
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
  # The binary anchors (AC3) replace the CR_SHA256 archive arm: a tarball
  # hash is never the hash of the binary inside it (gzip+tar wrapper), and
  # the build now verifies the COPIED binaries — plan F4 measured both byte-
  # identical to the official release chain's extracted binaries.
  bin_pin() { # $1 ARG name, $2 measured anchor value, $3 provenance label
    local ln val prev prev_line window
    ln=$(argln "$1")
    [ -n "$ln" ] || fail "t2: no ARG $1 line — $3"
    val=$(sed -n "${ln}p" "$DF" | cut -d= -f2-)
    [ "$val" = "$2" ] ||
      fail "t2: ARG $1 is '$val', expected the measured binary anchor $2 ($3)"
    prev=$((ln - 1))
    prev_line=$(sed -n "${prev}p" "$DF" | sed 's/[[:space:]]*$//')
    case "$prev_line" in
      '# renovate:'*)
        fail "t2: ARG $1 sits directly under a renovate annotation ('$prev_line') — the binary anchors are manual by design (AC3): an annotation-tracked hash would auto-bump past the human re-anchor that makes the build's sha256sum -c the supply-chain gate" ;;
    esac
    window=$(sed -n "$((ln > 4 ? ln - 4 : 1)),$((ln - 1))p" "$DF")
    printf '%s' "$window" | grep -q '# manual-pin:' ||
      fail "t2: ARG $1 carries no '# manual-pin:' why-comment within 4 lines above it — the anchor rides OUTSIDE renovate deliberately (the retired CR_SHA256 precedent): it must bump with the version by hand, and a stale anchor has to fail the build loudly"
    printf '%s' "$window" | grep -qiE 'bump|version' ||
      fail "t2: the $1 manual-pin comment must state the bump-with-version law"
  }
  bin_pin HELM_BIN_SHA256 '46aeab5e043f62d01f7c168823b392cabc1cea3807b67906296290483791be43' \
    'sha256 of the extracted linux-amd64 helm binary of the official v3.22.1 release, measured byte-identical to alpine/helm:3.22.1 (plan F4)'
  bin_pin CR_BIN_SHA256 'ca45e76c0aa7a159425cd5b4b63269b8cb5ee481a2667c9f8ffcf092a33402fc' \
    'sha256 of the extracted linux_amd64 cr binary of the official v1.10.1 release, measured byte-identical to the official ghcr image (plan F4)'
  if grep -qE '^ARG CR_SHA256=' "$DF"; then
    fail "t2: ARG CR_SHA256 still present — the archive digest anchored the fetch shape run -4 removed, and it can never equal the extracted binary hash (plan F4); the BIN anchors above replace it, the archive values surviving only as provenance in Dockerfile comments"
  fi
  ok "t2: helm v3.22.1 + cr 1.10.1 pins with directly-adjacent renovate annotations; both binary anchors exact under their manual-pin why-comments; CR_SHA256 retired"
fi

# --- t3: helm arrives by stage transport, anchored and asserted ----------
if want t3; then
  # RUN lines wrap with trailing backslashes in the pinned shape; join them so
  # each logical command reads as one line (t5 idiom, forgejo-host-runner).
  flat=$(sed -e ':a' -e 'N' -e '$!ba' -e 's/\\\n[[:space:]]*/ /g' "$DF")
  runs=$(printf '%s\n' "$flat" | grep -E '^RUN' || true)
  grep -qE '^FROM docker\.io/alpine/helm:3\.22\.1@sha256:8191701ad1f82ee3695c87211fcbfe6d7b1bb7df92ac1c8de9ccdb0995a6a2c1 AS helmtool$' "$DF" ||
    fail "t3: the helm tool stage (alpine/helm:3.22.1 at its served index digest, plan F2, named AS helmtool) is not in the file — it is the bake's helm source now; t1 pins the same line as part of the three-FROM order law"
  grep -qE '^COPY --from=helmtool /usr/bin/helm /usr/local/bin/helm$' "$DF" ||
    fail "t3: no COPY --from=helmtool transport of the stage's own /usr/bin/helm (the path alpine/helm ships, plan F2) to /usr/local/bin/helm — the default-PATH name plain workflow invocations resolve (t5)"
  printf '%s' "$flat" | grep -qE 'HELM_BIN_SHA256[^;]*sha256sum -c' ||
    fail "t3: the copied helm binary is not sha256sum -c verified against HELM_BIN_SHA256 — the binary anchor is the supply-chain gate that replaced the get.helm.sh sidecar: a stage digest serving bytes off the official release chain must die THIS build (plan F4)"
  printf '%s' "$flat" | grep -qE 'helm version[^;]*HELM_VERSION' ||
    fail "t3: no build-time helm version assert against HELM_VERSION — a mis-baked tool must fail the BUILD, not the next release fire; the coder-workspace assert shape survives the transport change"
  if printf '%s' "$runs" | grep -qE 'get\.helm\.sh'; then
    fail "t3: a RUN line still names get.helm.sh — three lane dispatches died on that fetch class (curl TLS 35, STATE intake) and run -4 removed the source instead of hardening the path; only comments may name get.helm.sh as history"
  fi
  ok "t3: helm arrives by COPY --from from the digest-pinned stage, binary-anchored and version-asserted; no get.helm.sh RUN operand"
fi

# --- t4: cr arrives by stage transport, anchored and asserted (AC4) --------
if want t4; then
  flat=$(sed -e ':a' -e 'N' -e '$!ba' -e 's/\\\n[[:space:]]*/ /g' "$DF")
  runs=$(printf '%s\n' "$flat" | grep -E '^RUN' || true)
  grep -qE '^FROM ghcr\.io/helm/chart-releaser:v1\.10\.1-amd64@sha256:f04f886affa5ba55b004788591b56f35bfd79abca9f85f0cb2f61c2f90bbe84c AS crtool$' "$DF" ||
    fail "t4: the cr tool stage (ghcr.io/helm/chart-releaser:v1.10.1-amd64 at its served manifest digest, plan F3, named AS crtool) is not in the file — the official helm-org image is the bake's cr source now; t1 pins the same line as part of the three-FROM order law"
  grep -qE '^COPY --from=crtool /usr/local/bin/cr /usr/local/bin/cr$' "$DF" ||
    fail "t4: no COPY --from=crtool transport of the stage's own /usr/local/bin/cr (the path the official image ships, plan F3) to /usr/local/bin/cr — the default-PATH name plain workflow invocations resolve (t5)"
  printf '%s' "$flat" | grep -qE 'CR_BIN_SHA256[^;]*sha256sum -c' ||
    fail "t4: the copied cr binary is not sha256sum -c verified against CR_BIN_SHA256 — a bare COPY would reopen the supply-chain question the old archive pin closed; the anchor ties the bytes to the official checksum chain (plan F4)"
  # The FLAG form is a measured build-killer: plan F5 ran the exact binary —
  # cr 1.10.1 answers --version with 'unknown flag' and a non-zero exit, so
  # an image built on it dies at this RUN. It never surfaced only because
  # the fetch in front of it always died first; a first green build must not
  # inherit it by habit.
  if printf '%s' "$runs" | grep -qE 'cr --version'; then
    fail "t4: a RUN line asserts with 'cr --version' — chart-releaser 1.10.1 rejects the flag (measured: unknown flag, non-zero rc; plan F5), the working shape is the version SUBCOMMAND ('cr version' answers GitVersion: v1.10.1, rc 0) asserted below. Keeping the flag form re-plants that latent build-killer on the first build whose transport works"
  fi
  printf '%s' "$flat" | grep -qE 'cr version[^;]*CR_VERSION' ||
    fail "t4: no build-time 'cr version | grep' assert against CR_VERSION — the subcommand form is the measured-working shape (plan F5); the --version flag form is banned by the leg above"
  if printf '%s' "$runs" | grep -qE 'releases/download'; then
    fail "t4: a RUN line still fetches a github.com release asset — the cr tarball fetch moved to the official-image transport with the source change (run -4); dispatch #215 never even executed that arm and it gets no revival, only comments may name the history"
  fi
  ok "t4: cr arrives by COPY --from from the official digest-pinned stage, binary-anchored and 'cr version'-asserted; no releases/download RUN operand"
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

# --- t6: base superset, COPY ban carving out the stage transports ----------
if want t6; then
  for instr in USER ENTRYPOINT CMD ADD; do
    if grep -qE "^$instr[[:space:]]" "$DF"; then
      fail "t6: a $instr line enters the Dockerfile — the image is the act base plus two static binaries and NOTHING else (D36 keeps the base's job shell and the inherited tool inventory; run -4 adds exactly one new instruction class, COPY --from)"
    fi
  done
  # The COPY law inverts with the source change: context copies stay banned,
  # the two stage transports are now REQUIRED — pinning their count keeps
  # this ban from passing vacuously on a file that dropped the transports.
  bare=$(grep -E '^COPY' "$DF" | grep -vE '^COPY --from=' || true)
  [ -z "$bare" ] ||
    fail "t6: a context COPY line ('$bare') enters the image — the carve-out covers stage transports only (COPY --from=helmtool / COPY --from=crtool, pinned exactly by t3/t4); build-context files have never belonged in this image and still do not"
  n_copy=$(grep -cE '^COPY --from=' "$DF" || true)
  [ "$n_copy" -eq 2 ] ||
    fail "t6: found $n_copy COPY --from= lines, expected exactly 2 — the plan bar greps the same count as a change fingerprint: since run -4 the stage transport IS the shape, so the carve-out must bind on real COPY lines"
  if grep -qE 'apt(-get)?[[:space:]]+(install|update)' "$DF"; then
    fail "t6: apt work in the Dockerfile — the RESEARCH C1 inventory (git/git-lfs/jq/python3/node/yq/docker CLI+buildx+compose) is inherited, not rebuilt; adding packages risks regressing it"
  fi
  if ! grep -E '^#' "$DF" | grep -qiE 'root' || ! grep -E '^#' "$DF" | grep -qiE 'job|USER'; then
    fail "t6: no deviation comment on the root job shell — the container-creation non-root law serves SERVICE containers; a job image deliberately keeps the base's root user because today's jobs apt-get and write system paths, and a USER line would regress them (D36). The Dockerfile records the why."
  fi
  ok "t6: pure base superset — exactly the two stage COPY --from transports, no context COPY, no USER/ENTRYPOINT/CMD/ADD/apt lines, root-job-shell deviation documented"
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
    # Not a deviation: the build-containers.yaml run on the merged main IS the
    # build authority for containers (AGENTS 'Pipeline specifics'); the static
    # contract above is this session's share. This line is the DESIGNED
    # passing shape for the image legs (cf-77 ruling), not a failure.
    ok "t8: docker build => no-daemon, CI-deferred (designed passing shape)"
  fi
fi

printf 'PASS: forgejo-runner container checks (%d ok)\n' "$checks"
