#!/usr/bin/env bash
# C03 acceptance checks (2026-10-feat-coder-workspace-rebuild), criteria 1-4:
# charts/coder/coder-templates/{main.tf,terraform.tfvars} move into
# coder-templates/kubernetes/ as a pure file move with ZERO content change
# (DECISIONS: the server-side template name stays `kubernetes`).
#
# This repo has no unit-test suite (AGENTS.md "Pipeline specifics"); these
# checks are the local gate for C03. Each check prints one pass/fail line;
# any fail makes the script exit non-zero.
#
# Criterion 1 uses `git status --porcelain=v2` (not v1): only v2 reports the
# R100 similarity score and BOTH rename paths on one line, which is what
# proves "100% similarity, no content edit". Status is scoped to the
# coder-templates pathspec because the worktree legitimately carries other
# uncommitted C01/C02 changes (renovate.json, the Dockerfile, tests/).
#
# Criterion 2 runs PLAN.md's scratch-copy terraform recipe verbatim: init in
# a copy under /tmp/opencode, never inside the repo (.terraform/ must not be
# committed). The plugin cache makes re-init cheap; the binary must exist,
# a missing one is a fail line, not a crash.
#
# Usage: bash tests/templates/coder-move.sh
#   REPO_ROOT=<abs path> bash tests/templates/coder-move.sh
# REPO_ROOT defaults to the git toplevel of the current directory; the
# override exists to run the same contract against a scratch checkout with
# the move applied, without touching the real worktree.

set -u

if [ -n "${REPO_ROOT:-}" ]; then
  :
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "fail: cannot resolve repo root via git; set REPO_ROOT explicitly"; exit 2; }
fi
[ -d "$REPO_ROOT" ] || { echo "fail: REPO_ROOT '$REPO_ROOT' is not a directory"; exit 2; }
git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "fail: REPO_ROOT '$REPO_ROOT' is not a git worktree"; exit 2; }

HELM=/home/coder/.local/bin/helm
TF_BIN="${TF_BIN:-/tmp/opencode/tfbin/terraform}"
TF_PLUGIN_CACHE=/tmp/opencode/tfbin/plugin-cache
TPL=charts/coder/coder-templates

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'pass: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'fail: %s\n' "$1"; }

status_dump=$(git -C "$REPO_ROOT" status --porcelain=v2 -- "$TPL/" 2>&1)

# --- criterion 1: exactly two 100%-similarity renames, old paths gone ------
# A rename is one v2 line: "2 <XY> <sub> <m1> <m2> <mH> <X> <Y> <score> <path>\t<origPath>"
# — ten space-separated fields (the score is where R100 similarity is reported,
# the NEW path is last of them), then ONE tab, then the orig path.
#
# XY must be exactly "R." (staged rename, worktree clean against the index).
# The score compares INDEX vs HEAD, so an unstaged edit after `git mv` shows
# "RM ... R100" — index-still-identical, worktree-drifted — and must fail the
# zero-content-change contract.
rename_entry() { # $1 = expected new path, $2 = expected orig path
  printf '%s\n' "$status_dump" | awk -F'\t' -v want_new="$1" -v want_orig="$2" '
    NF == 2 {
      n = split($1, f, " ")
      if (n == 10 && f[1] == "2" && f[2] == "R." && f[9] == "R100" && f[10] == want_new && $2 == want_orig)
        found = 1
    }
    END { exit found ? 0 : 1 }
  '
}
status_tail=$(printf '%s' "$status_dump" | head -n 5 | tr '\n' '|')

if rename_entry "$TPL/kubernetes/main.tf" "$TPL/main.tf"; then
  pass "c1: main.tf is staged as an R100 rename to kubernetes/main.tf"
else
  fail "c1: no R100 rename entry $TPL/main.tf -> $TPL/kubernetes/main.tf (status under $TPL/ is: ${status_tail})"
fi
if rename_entry "$TPL/kubernetes/terraform.tfvars" "$TPL/terraform.tfvars"; then
  pass "c1: terraform.tfvars is staged as an R100 rename to kubernetes/terraform.tfvars"
else
  fail "c1: no R100 rename entry $TPL/terraform.tfvars -> $TPL/kubernetes/terraform.tfvars (status under $TPL/ is: ${status_tail})"
fi
# Count only type-2 (rename) lines, not all entries: C04's untracked
# kubernetes-hardened/ folder is a legitimate third entry under this
# pathspec (its file contract lives in tests/templates/coder-hardened.sh).
# A third rename still fails (count 3); a modification of either moved file
# still fails the per-file checks above, where worktree drift flips XY from
# "R." to "RM".
rename_count=$(printf '%s\n' "$status_dump" | awk '$1 == "2" { n++ } END { print n + 0 }')
if [ "$rename_count" -eq 2 ]; then
  pass "c1: exactly 2 rename entries under coder-templates/ (the two R100 renames only)"
else
  fail "c1: expected exactly 2 rename entries under coder-templates/, got $rename_count: $(printf '%s' "$status_dump" | tr '\n' '|')"
fi
if [ ! -e "$REPO_ROOT/$TPL/main.tf" ] && [ ! -e "$REPO_ROOT/$TPL/terraform.tfvars" ]; then
  pass "c1: old paths no longer exist on disk"
else
  fail "c1: old path(s) still exist on disk: main.tf=$([ -e "$REPO_ROOT/$TPL/main.tf" ] && echo yes || echo no) terraform.tfvars=$([ -e "$REPO_ROOT/$TPL/terraform.tfvars" ] && echo yes || echo no)"
fi
if [ -f "$REPO_ROOT/$TPL/kubernetes/main.tf" ] && [ -f "$REPO_ROOT/$TPL/kubernetes/terraform.tfvars" ]; then
  pass "c1: kubernetes/ contains both moved files on disk"
else
  fail "c1: kubernetes/ files missing on disk (main.tf: $([ -f "$REPO_ROOT/$TPL/kubernetes/main.tf" ] && echo present || echo absent), terraform.tfvars: $([ -f "$REPO_ROOT/$TPL/kubernetes/terraform.tfvars" ] && echo present || echo absent))"
fi

# --- criterion 2: scratch-copy terraform validate on kubernetes/main.tf ----
new_main="$REPO_ROOT/$TPL/kubernetes/main.tf"
if [ ! -f "$new_main" ]; then
  fail "c2: $TPL/kubernetes/main.tf is missing — the move has not landed yet, nothing to validate"
elif [ ! -x "$TF_BIN" ]; then
  fail "c2: terraform binary missing at $TF_BIN — re-provision per PLAN.md (terraform 1.9.8 into /tmp/opencode/tfbin) before re-running"
else
  scratch=/tmp/opencode/tf-validate-kubernetes
  rm -rf "$scratch" && mkdir -p "$scratch" && cp "$new_main" "$scratch/"
  if tf_out=$(cd "$scratch" && TF_PLUGIN_CACHE_DIR="$TF_PLUGIN_CACHE" "$TF_BIN" init -backend=false -input=false && "$TF_BIN" validate 2>&1); then
    pass "c2: scratch-copy terraform init -backend=false + validate passes on kubernetes/main.tf"
  else
    fail "c2: terraform init/validate failed in scratch copy; last lines: $(printf '%s' "$tf_out" | tail -n 3 | tr '\n' '|')"
  fi
fi

# --- criterion 3: packaged chart contains no coder-templates/ --------------
# helm dependency build is the documented fresh-worktree precondition
# (friction #16); it only writes the gitignored dep tarball and leaves
# Chart.lock untouched.
if (cd "$REPO_ROOT" && "$HELM" dependency build charts/coder >/dev/null 2>&1); then
  pass "precondition: helm dependency build charts/coder ok"
else
  fail "precondition: helm dependency build charts/coder failed (registry unreachable?) — helm checks below may be unreliable"
fi

if [ ! -x "$HELM" ]; then
  fail "c3: helm missing at $HELM"
  fail "c4: helm missing at $HELM"
else
  pkgdir=/tmp/opencode/helm-pkg
  rm -rf "$pkgdir"
  if (cd "$REPO_ROOT" && "$HELM" package charts/coder -d "$pkgdir" >/dev/null 2>&1); then
    tgz=$(ls "$pkgdir"/coder-*.tgz 2>/dev/null | head -n 1)
    if [ -z "$tgz" ]; then
      fail "c3: helm package produced no coder-*.tgz in $pkgdir"
    else
      # grep -c exits 1 on a zero count, which is the PASSING outcome here.
      count=$(tar -tzf "$tgz" | grep -c 'coder-templates/' || true)
      if [ "${count:-0}" -eq 0 ]; then
        pass "c3: packaged chart contains 0 coder-templates/ entries (.helmignore still covers the subfolder)"
      else
        fail "c3: packaged chart contains $count coder-templates/ entries (expected 0): $(tar -tzf "$tgz" | grep 'coder-templates/' | head -n 3 | tr '\n' '|')"
      fi
    fi
  else
    fail "c3: helm package charts/coder failed"
  fi

  # --- criterion 4: the chart itself is untouched --------------------------
  if (cd "$REPO_ROOT" && "$HELM" lint charts/coder >/dev/null 2>&1); then
    pass "c4: helm lint charts/coder passes"
  else
    fail "c4: helm lint charts/coder failed: $(cd "$REPO_ROOT" && "$HELM" lint charts/coder 2>&1 | grep -iE 'error|fail' | head -n 2 | tr '\n' '|')"
  fi
  if (cd "$REPO_ROOT" && "$HELM" template charts/coder >/dev/null 2>&1); then
    pass "c4: helm template charts/coder renders"
  else
    fail "c4: helm template charts/coder failed: $(cd "$REPO_ROOT" && "$HELM" template charts/coder 2>&1 | tail -n 2 | tr '\n' '|')"
  fi
fi

echo "=== coder-move: $PASS passed, $FAIL failed (REPO_ROOT=$REPO_ROOT) ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
