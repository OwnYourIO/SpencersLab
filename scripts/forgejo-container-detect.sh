#!/usr/bin/env bash
# Changed-container detection and registry tag math for
# .forgejo/workflows/build-containers.yaml. Pure shell + coreutils: the
# workflow parses the tags/list JSON textually because the runner image
# ships no jq or python.
#
#   detect    stdout a sorted JSON array of the containers/<name> dirs to
#             rebuild, run at the checked-out repo root. Inputs are
#             environment variables: EVENT_NAME (push|pull_request|
#             workflow_call|workflow_dispatch), EVENT_BEFORE and SHA (push-era
#             range), MARKER_SHA
#             (the last-built marker: when set it replaces before as the base,
#             so a build a dead or cancelled run lost is re-covered by the
#             next run instead of staying skipped forever; on a workflow_call
#             run with no marker the range is the FULL SET — the empty tree —
#             and announced: a tip-only range would skip-and-seal, the
#             directories introduced below a burst tip stay invisible, the
#             marker seals at the tip on this run's green, and they never
#             build. A called run carries no push payload, so an empty before
#             is expected there and the push arm still dies on it). The
#             build-containers workflow resolves and validates MARKER_SHA; this
#             script only reads it, and an empty value is the bootstrap
#             fallback. The base token echoed on stderr names which arm won:
#             marker|full-set|tip-only|before, so called runs read distinctly
#             from push-era ones. BASE_SHA and HEAD_SHA (pull-request
#             range), MANUAL_CONTAINERS (dispatch list, comma/space separated).
#   next-n    stdin a tags/list JSON body (either registry), env YYMM=yy.mm;
#             stdout the month's next calendar release number, max(yy.mm.N)+1 or 1.
#   sanitize  argv branch name; stdout a Docker-tag-safe rolling/PR component.

set -eu

die() {
  printf 'forgejo-container-detect: %s\n' "$1" >&2
  exit 2
}

detect() {
  local event="${EVENT_NAME:-push}" names n

  if [ "$event" = workflow_dispatch ]; then
    # A dispatch names its rebuild list outright: it fires on demand with no
    # commit range behind it, so an empty list builds nothing.
    names=$(printf '%s' "${MANUAL_CONTAINERS:-}" | tr ', ' '\n\n')
  else
    local a b base_src=''
    if [ "$event" = pull_request ]; then
      a="${BASE_SHA:-}"
      b="${HEAD_SHA:-}"
      # Detection anchors on the merge base of the two payload shas, not
      # the base tip: a base that moved after the head branched must not
      # contribute base-side changes to a PR build, and the trigger filter
      # that dispatched this run already diffs merge-base..head. The raw
      # endpoints go to stderr BEFORE the call: git merge-base exits 1 on
      # an unrelated pair writing nothing, so a red run would otherwise
      # name no endpoint at all.
      printf 'detect: merge-base of %s and %s (event %s)\n' "$a" "$b" "$event" >&2
      a=$(git merge-base "$a" "$b")
    else
      local before="${EVENT_BEFORE:-}"
      # Marker first (C15 call-aware): the payload before can name a range
      # a dead or cancelled run already lost, and re-diffing it is the heal
      # this base exists for. Under workflow_call an empty before is
      # EXPECTED (called runs carry no push payload), so the marker check —
      # then the call bootstrap arm — precede the payload die; the die
      # stays scoped to real pushes.
      if [ -n "${MARKER_SHA:-}" ]; then
        a="$MARKER_SHA"
        b="${SHA:-HEAD}"
        base_src='marker'
      elif [ "$event" = workflow_call ]; then
        # First called run with no marker (bootstrap, or the owner has not
        # migrated the ref yet): the FULL SET and LOUD about it — a
        # tip-only range would skip-and-seal: directories introduced below
        # a burst tip stay invisible, the marker seals at the tip on this
        # run's green, and they never build. The one-time full build is
        # bounded: after this run's green the marker exists and every later
        # fire diffs marker..sha.
        # Why not the rejected alternative — refusing to advance the marker
        # on a multi-commit push: it does not resolve the skip (the next
        # no-marker called run is still tip-only; deferral is not coverage),
        # it defeats the marker's re-cover property (C14/D53), and it
        # cascades into the main-sync D54 single-writer job and its test —
        # cf-55 territory.
        printf '::warning::first called run (workflow_call, no marker): full-set detection over the empty tree — a tip-only range would skip-and-seal: directories introduced below a burst tip stay invisible, the marker seals at the tip and they never build\n' >&2
        EMPTY_TREE=$(git mktree < /dev/null)
        a="$EMPTY_TREE"
        b='HEAD'
        base_src='full-set'
      else
        if [ -z "$before" ]; then
          # A v15.0.10 push payload always carries before: a real oid, or the
          # all-zero sentinel on branch creation. An empty one therefore means
          # a wrong accessor or an unexpected event routed into the push arm,
          # and reading it as a first push would silently narrow a multi-commit
          # push to the tip commit.
          die 'push arm: EVENT_BEFORE is empty, which no push payload sends'
        fi
        if [ -z "${before//[0]/}" ]; then
          # The first push to a branch carries an all-zero before and
          # HEAD^..HEAD is the pushed commit — a tip-only range: older
          # commits of that push stay invisible, and the log line is where
          # the narrowing announces itself.
          printf '::warning::first push (all-zero before): tip-only detection over HEAD^..HEAD\n' >&2
          a='HEAD^'
          b='HEAD'
          base_src='tip-only'
        else
          a="$before"
          b="${SHA:-HEAD}"
          base_src='before'
        fi
      fi
    fi
    # The endpoints actually diffed, named on stderr before the call: a red
    # detection must be diagnosable from the job log alone. stdout stays
    # exactly the JSON array — the step captures it into its output. The
    # push arm also names which base won, so a marker-fed run reads
    # differently from a bootstrap one; the pull_request arm echoes no base
    # token, its output being byte-frozen against the PR re-run law.
    printf 'detect: range %s..%s (event %s%s)\n' "$a" "$b" "$event" \
      "${base_src:+, base=$base_src}" >&2
    # No `|| true` and no masking pipe on the git call itself: a range that
    # fails to resolve must fail the job, not be reported as "nothing
    # changed" and silently skip the builds it covers.
    local changed
    changed=$(git diff --name-only "$a" "$b" -- containers/)
    names=$(printf '%s\n' "$changed" | cut -d/ -f2)
  fi

  # Both gates apply to every source, dispatch lists included: a name in a
  # free-text or deleted-since input is not a promise that a buildable
  # directory exists for it.
  printf '%s\n' "$names" |
    grep -E '^[a-z0-9]+(-[a-z0-9]+)*$' |
    while IFS= read -r n; do
      [ -f "containers/$n/Dockerfile" ] && printf '%s\n' "$n"
    done |
    sort -u |
    json_array
}

next_n() {
  local yymm esc tag micro max
  yymm=${YYMM:?next-n reads the month from YYMM (e.g. 26.11)}
  esc=${yymm//./\\.}
  max=0
  # GHCR answers tags/list as one compact JSON line; keep only the tags
  # array, then only this month's bare yy.mm.<digits> entries, so legacy
  # v<run>, rolling and foreign-month tags never feed the comparison.
  while IFS= read -r tag; do
    micro=${tag##*.}
    # The filter above admits digits only, so the compare is numeric and
    # 26.11.10 outranks 26.11.9.
    if [ "$micro" -gt "$max" ]; then
      max=$micro
    fi
  done < <(
    tr -d '\n\r' |
      sed -n 's/.*"tags"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' |
      tr ',' '\n' |
      sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*/\1/p' |
      grep -E "^${esc}\.[0-9]+$" || true
  )
  printf '%s\n' "$((max + 1))"
}

sanitize() {
  [ "$#" -ge 1 ] || die 'sanitize takes a branch name'
  printf '%s' "$1" |
    tr 'A-Z' 'a-z' |
    tr '/' '-' |
    sed -e 's/[^a-z0-9._-]/-/g' -e 's/--*/-/g' |
    cut -c1-128
}

json_array() {
  local out='' name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    out="${out:+$out,}\"$name\""
  done
  printf '[%s]\n' "$out"
}

case "${1:-}" in
  detect) detect ;;
  next-n) next_n ;;
  sanitize)
    shift
    sanitize "$@"
    ;;
  *) die 'usage: forgejo-container-detect.sh detect | next-n | sanitize <branch>' ;;
esac
