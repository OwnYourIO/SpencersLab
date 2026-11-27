#!/usr/bin/env bash
# Helm repository registration for .forgejo/workflows/build-charts.yaml:
# the "Add repositories" step shared by the test-build, release and
# forgejo-publish jobs — the triple-duplicated loop the C04 extraction
# retired (the cf-77/D45 fix had to be applied at three sites; the
# extraction kills the drift class). Run at the checked-out repo root.
# Pure shell + coreutils: the runner image ships the toolchain (the D33
# bake), so this script adds nothing but the helm repo calls themselves.
#
# For every charts/<name>/ dir, scan `helm dependency list` for each row's
# first URL-shaped field and register it with `helm repo add` — except
# oci:// rows, which the shell guard keeps out (a registry reference is
# pulled by its reference, not registered as a repo). The scan is
# field-wise on purpose (cf-77 r2 finding — repro: declared subchart with
# an empty repository:): an empty REPOSITORY column shifts the STATUS word
# into the slot a naive field-3 read would take, and the awk `next`
# terminator registers every row — an `exit` would register only the first.

set -eu

die() {
  printf 'forgejo-helm-repo-add: %s\n' "$1" >&2
  exit 2
}

# A missing charts/ is a wrong cwd, not an empty registration: the die
# names it instead of `ls` dying with an unreadable message under -e.
[ -d charts ] || die 'charts/ is missing — run at the checked-out repo root'

for dir in $(ls -d charts/*/); do
  # NAME + first URL-shaped field: a dependency with an empty
  # REPOSITORY column shifts "unpacked" into $3, and
  # `helm repo add <name> unpacked` breaks this step under bash -e
  # (cf-77 r2 finding — repro: declared subchart with repository: "")
  helm dependency list $dir 2> /dev/null | tail +2 | head -n -1 | awk '{ for (i = 2; i <= NF; i++) if ($i ~ /^(https?|oci|file):\/\//) { print $1, $i; next } }' | while read name url; do
    if [[ ! "$url" =~ ^oci:// ]]; then
      helm repo add "$name" "$url"
    fi
  done
done
