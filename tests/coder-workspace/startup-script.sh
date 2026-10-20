#!/usr/bin/env bash
# C01 acceptance checks for containers/coder-workspace/workspace-startup.sh —
# the baked startup contract the Coder templates call. Covers criterion 1
# (POSIX sh, set -eu), the env contract, the pinned code-server install, and
# the forbidden strings. Each check prints one pass/fail line; any fail makes
# the script exit non-zero.
#
# This script is the single baked startup contract for the hardened template,
# so the checks assert exactly what the template and the image depend on: the
# env names the template will export, the verified code-server artifact, and
# the absence of machinery the rebuild deliberately drops.
#
# Usage: bash tests/coder-workspace/startup-script.sh

set -u

cd "$(git rev-parse --show-toplevel)" || { echo "fail: cannot resolve repo root via git"; exit 2; }

STARTUP="containers/coder-workspace/workspace-startup.sh"

# The code-server release publishes no checksum file, so the startup script
# must hardcode the sha256 (verified 2026-10-18, DECISIONS #22) — the same
# deliberate pattern as FJ_SHA256: a version bump fails startup until the
# hash is recomputed.
CODE_SERVER_SHA256='65bcd20b524d03eb1b5adb7f360244599ef0e5b74089a46a982d32c074b97a29'
CODE_SERVER_DEFAULT_VERSION='v4.141.0'

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'pass: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'fail: %s\n' "$1"; }

# Absence checks scan code lines only: an explanatory comment naming a removed
# tool is legitimate, and matching it would fail a correct implementation.
code_lines() {
  grep -vE '^[[:space:]]*#' "$1" | grep -vE '^[[:space:]]*$' || true
}

if [ ! -f "$STARTUP" ]; then
  fail "c1: $STARTUP is missing — the image has no baked startup contract yet"
  echo "=== startup-script: $PASS passed, $FAIL failed (file absent — remaining checks not run) ==="
  exit 1
fi

# --- criterion 1: POSIX sh, set -eu ---------------------------------------
# The chunk names bash -n as the gate; it proves the script parses. POSIX-ness
# is the shebang/contract the Coder template relies on (the script runs as the
# workspace bootstrap, not under a bash guarantee).
if bash -n "$STARTUP" 2>/dev/null; then
  pass "c1: bash -n passes (script parses; POSIX sh)"
else
  fail "c1: bash -n reports a syntax error in $STARTUP"
fi

if grep -qE '^set[[:space:]]+-eu([[:space:]]|$)' "$STARTUP"; then
  pass "c1: script runs under 'set -eu' (a failed step aborts startup)"
else
  fail "c1: no 'set -eu' at the start of the script"
fi

# --- env contract -----------------------------------------------------------
# These are the exact env names the hardened template will export; a rename on
# either side would silently break workspace startup.
for var in OPENCODE_SERVER_PASSWORD GITHUB_TOKEN FORGEJO_TOKEN FORGEJO_HOST CODE_SERVER_VERSION CODER_USER CODER_USER_EMAIL WORKSPACE_GIT_REPOS; do
  if grep -Eq "(^|[^A-Za-z0-9_])\\\$\\{?${var}" "$STARTUP"; then
    pass "env: \${${var}} is read by the startup script"
  else
    fail "env: \${${var}} is not read by the startup script"
  fi
done

# --- SSH + clone jobs -------------------------------------------------------
# The script provisions the workspace SSH key, pre-trusts the git hosts, and
# clones the repos the template selected (WORKSPACE_GIT_REPOS).
for needle in ssh-keygen known_hosts 'git clone'; do
  if grep -qF -- "$needle" "$STARTUP"; then
    pass "job: '$needle' is present in the startup script"
  else
    fail "job: '$needle' is missing from the startup script"
  fi
done

if grep -Fq "$CODE_SERVER_DEFAULT_VERSION" "$STARTUP"; then
  pass "env: code-server falls back to ${CODE_SERVER_DEFAULT_VERSION} when CODE_SERVER_VERSION is unset"
else
  fail "env: no ${CODE_SERVER_DEFAULT_VERSION} default for CODE_SERVER_VERSION"
fi

# --- pinned code-server install ---------------------------------------------
if grep -Fq "$CODE_SERVER_SHA256" "$STARTUP"; then
  pass "code-server: the verified sha256 ${CODE_SERVER_SHA256:0:16}… is hardcoded in the script"
else
  fail "code-server: the verified sha256 ${CODE_SERVER_SHA256} is not in the script"
fi

# The asset name is built from the (possibly env-supplied) version, e.g.
# code-server-${version#v}-linux-amd64.tar.gz; match the shape, not the
# variable name, so either a direct ${CODE_SERVER_VERSION...} expansion or a
# local alias satisfies the contract.
if grep -Eq "code-server-[A-Za-z0-9_\$.{}#\"'-]*-linux-amd64\.tar\.gz" "$STARTUP"; then
  pass "code-server: the official 'code-server-<version>-linux-amd64.tar.gz' asset pattern is used"
else
  fail "code-server: no 'code-server-<version>-linux-amd64.tar.gz' asset pattern found"
fi

# --- forbidden strings --------------------------------------------------------
# The rebuild drops sudo, nvm, Kilo and pbir; their return in code would
# re-introduce runtime installs or stripped features. SSH-key machinery is
# NOT forbidden: the script keeps the key + known_hosts + clone jobs.
for s in sudo nvm kilocode pbir; do
  hit=$(code_lines "$STARTUP" | grep -inF -- "$s" | head -n 1 || true)
  if [ -n "$hit" ]; then
    fail "forbidden: '$s' present in $STARTUP ($hit)"
  else
    pass "forbidden: no '$s' in $STARTUP code"
  fi
done

echo "=== startup-script: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
