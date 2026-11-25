#!/usr/bin/env bash
# Changed-template detection for
# .forgejo/workflows/coder-template-push.yaml. Pure shell + coreutils: the
# workflow parses the stdout JSON textually.
#
#   detect    stdout a sorted JSON array of the
#             charts/coder/coder-templates/<name> dirs to push, run at the
#             checked-out repo root. A dir is a pushable template only
#             when it is DNS-safe and carries a main.tf. Inputs are
#             environment variables: EVENT_NAME (push|workflow_dispatch —
#             no PR arm, the workflow has no PR trigger), EVENT_BEFORE and
#             SHA (push range), MANUAL_TEMPLATES (dispatch list,
#             comma/space separated).

set -eu

die() {
  printf 'coder-template-detect: %s\n' "$1" >&2
  exit 2
}

detect() {
  local event="${EVENT_NAME:-push}" names n
  # An empty result that is one of the two no-op semantics — a no-op ref
  # update (before == sha) or an empty dispatch list (it names nothing,
  # which is its own intent) — stays silent; every other empty set warns,
  # so a green run that pushed nothing reads differently from a range
  # that resolved to nothing.
  local exempt=0

  if [ "$event" = workflow_dispatch ]; then
    # A dispatch names its push list outright: it fires on demand with no
    # commit range behind it, so an empty list pushes nothing.
    names=$(printf '%s' "${MANUAL_TEMPLATES:-}" | tr ', ' '\n\n')
    [ -z "$(printf '%s' "$names" | tr -d '[:space:]')" ] && exempt=1
  else
    local before="${EVENT_BEFORE:-}"
    if [ -z "$before" ]; then
      # A push payload always carries before: a real oid, or the all-zero
      # sentinel on branch creation. An empty one therefore means a wrong
      # accessor or an unexpected event routed into the push arm, and
      # reading it as a first push would silently narrow a multi-commit
      # push to the tip commit.
      die 'push arm: EVENT_BEFORE is empty, which no push payload sends'
    fi
    local a b
    if [ -z "${before//[0]/}" ]; then
      # The first push to a branch carries an all-zero before and
      # HEAD^..HEAD is the pushed commit — a tip-only range: older
      # commits of that push stay invisible, and the log line is where
      # the narrowing announces itself.
      printf '::warning::first push (all-zero before): tip-only detection over HEAD^..HEAD\n' >&2
      a='HEAD^'
      b='HEAD'
    else
      a="$before"
      b="${SHA:-HEAD}"
      [ "$a" = "$b" ] && exempt=1
    fi
    # The endpoints actually diffed, named on stderr before the call: a red
    # detection must be diagnosable from the job log alone. stdout stays
    # exactly the JSON array — the step captures it into its output.
    printf 'detect: range %s..%s (event %s)\n' "$a" "$b" "$event" >&2
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

  if [ "$result" = '[]' ] && [ "$exempt" = 0 ]; then
    if [ "$event" = workflow_dispatch ]; then
      printf '::warning::no pushable template dirs resolved from the dispatch list: the run will push nothing\n' >&2
    else
      printf '::warning::no changed pushable template dirs in range %s..%s: the run will push nothing\n' "$a" "$b" >&2
    fi
  fi
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
