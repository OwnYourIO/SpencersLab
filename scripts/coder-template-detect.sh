#!/usr/bin/env bash
# Changed-template detection for
# .forgejo/workflows/coder-template-push.yaml. Pure shell + coreutils: the
# workflow parses the stdout JSON textually.
#
#   detect    stdout a sorted JSON array of the
#             charts/coder/coder-templates/<name> dirs to push, run at the
#             checked-out repo root. A dir is a pushable template only
#             when it is DNS-safe and carries a main.tf. Inputs are
#             environment variables: EVENT_NAME (push|workflow_call|
#             workflow_dispatch — no PR arm, the workflow has no PR
#             trigger), EVENT_BEFORE and SHA (push-era range), MARKER_SHA
#             (the last-built marker: when set it replaces before as the
#             base, so a push a dead or cancelled run lost is re-covered by
#             the next run instead of staying skipped forever; on a
#             workflow_call run with no marker the range is tip-only and
#             announced — a called run carries no push payload, so an empty
#             before is expected there and the push arm still dies on it).
#             The coder-template-push workflow resolves and validates
#             MARKER_SHA; this script only reads it, and an empty value is
#             the bootstrap fallback. The base token echoed on stderr names
#             which arm won: marker|tip-only|before, so called runs read
#             distinctly from push-era ones. MANUAL_TEMPLATES (dispatch
#             list, comma/space separated).

set -eu

die() {
  printf 'coder-template-detect: %s\n' "$1" >&2
  exit 2
}

detect() {
  local event="${EVENT_NAME:-push}" names n

  if [ "$event" = workflow_dispatch ]; then
    # A dispatch names its push list outright: it fires on demand with no
    # commit range behind it, so an empty list pushes nothing.
    names=$(printf '%s' "${MANUAL_TEMPLATES:-}" | tr ', ' '\n\n')
  else
    local a b base_src=''
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
      # migrated the ref yet): tip-only and LOUD about it — the narrowing
      # announces itself exactly like the all-zero first push arm.
      printf '::warning::first called run (workflow_call, no marker): tip-only detection over HEAD^..HEAD\n' >&2
      a='HEAD^'
      b='HEAD'
      base_src='tip-only'
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
    # The endpoints actually diffed, named on stderr before the call: a red
    # detection must be diagnosable from the job log alone. stdout stays
    # exactly the JSON array — the step captures it into its output. The
    # non-dispatch arms name which base won, so a marker-fed run reads
    # differently from a bootstrap one; the dispatch arm echoes nothing —
    # its list is its own range, and the empty-set verdict is the detect
    # step's to read from this script's JSON, not a script warning.
    printf 'detect: range %s..%s (event %s%s)\n' "$a" "$b" "$event" \
      "${base_src:+, base=$base_src}" >&2
    # No `|| true` and no masking pipe on the git call itself: a range that
    # fails to resolve must fail the job, not be reported as "nothing
    # changed" and silently skip the pushes it covers.
    local changed
    changed=$(git diff --name-only "$a" "$b" -- charts/coder/coder-templates/)
    names=$(printf '%s\n' "$changed" | cut -d/ -f4)
  fi

  # Both gates apply to every source, dispatch lists included: a name in a
  # free-text input is not a promise that a pushable template exists for
  # it — the dir must exist and carry a main.tf.
  local result
  result=$(
    printf '%s\n' "$names" |
      grep -E '^[a-z0-9]+(-[a-z0-9]+)*$' |
      while IFS= read -r n; do
        [ -f "charts/coder/coder-templates/$n/main.tf" ] && printf '%s\n' "$n"
      done |
      sort -u |
      json_array
  )

  printf '%s\n' "$result"
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
  *) die 'usage: coder-template-detect.sh detect' ;;
esac
