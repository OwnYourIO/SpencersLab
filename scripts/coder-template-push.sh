#!/usr/bin/env bash
# Per-template `coder templates push` driver for
# .forgejo/workflows/coder-template-push.yaml, run at the checked-out repo
# root. Matrix cells are fed by scripts/coder-template-detect.sh.
#
#   scripts/coder-template-push.sh <template-name>
#
# The env contract is exactly two keys (the OQ5-minimal vault): CODER_URL
# and CODER_SESSION_TOKEN. Either absent/empty = a ::warning:: line naming
# the key + exit 0 (the designed warn-and-skip green, the main-sync.yaml
# unset-vault posture); a configured 401 fails red (the CLI's non-zero
# exit propagates). No value env of any kind: the script passes no --var —
# template input values ride the auto-loaded terraform.tfvars + the main.tf
# defaults.

set -euo pipefail

die() {
  printf 'coder-template-push: %s\n' "$1" >&2
  exit 2
}

[ "$#" -eq 1 ] || die 'usage: scripts/coder-template-push.sh <template-name>'
name="$1"

# The matrix is fed by the detect gate: a name with no pushable dir
# (DNS-safe + carrying a main.tf, the gate's contract) could not have come
# from it, so this is a BUG, not an input — fail loudly before any coder
# call, even on an unconfigured instance (a swallowed bug would hide under
# the warn-and-skip green).
[ -f "charts/coder/coder-templates/$name/main.tf" ] ||
  die "unknown template '$name': no charts/coder/coder-templates/$name/main.tf (a matrix cell could not have come from the detect gate — a bug, not an input)"

# The warn-and-skip green is a designed outcome (exit 0), so the missing-
# key checks are explicit — never a ${VAR:?} trap under set -e.
if [ -z "${CODER_URL:-}" ] || [ -z "${CODER_SESSION_TOKEN:-}" ]; then
  [ -z "${CODER_URL:-}" ] &&
    printf '::warning::coder-template-push: CODER_URL is not set, skipping the push (unconfigured instance; a configured 401 fails red, this skip is the designed green)\n' >&2
  [ -z "${CODER_SESSION_TOKEN:-}" ] &&
    printf '::warning::coder-template-push: CODER_SESSION_TOKEN is not set, skipping the push (unconfigured instance; a configured 401 fails red, this skip is the designed green)\n' >&2
  exit 0
fi

# The dispatch escape hatch may carry no event ref: the message sha falls
# back to HEAD (the main-sync.yaml REF-chain shape). The version name is
# always the checked-out short HEAD sha.
event="${EVENT_NAME:-push}"
sha="${SHA:-}"
[ -n "$sha" ] || sha=$(git rev-parse HEAD)
short_sha=$(git rev-parse --short HEAD)

# The token reaches the coder CLI only as the CODER_SESSION_TOKEN
# environment variable — never argv, never a file (the argocd-fanout.py
# doctrine). --ignore-lockfile is pinned because neither template dir
# ships a .terraform.lock.hcl; a lockfile appearing later changes nothing
# (the flag is a no-op then), but dropping it would re-noise the log. The
# CLI's exit code is the script's: the workflow's fail-fast: false matrix
# isolates the siblings, a swallowed exit loses them.
coder templates push "$name" \
  --directory "charts/coder/coder-templates/$name" \
  -y \
  --ignore-lockfile \
  --name "$short_sha" \
  --message "forgejo $event $sha"
