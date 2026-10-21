#!/usr/bin/env bash
# Acceptance checks for containers/coder-workspace/workspace-startup.sh —
# the baked startup contract the Coder templates call. Covers criterion 1
# (POSIX sh, set -eu), the env contract, the SSH + clone jobs, and the
# forbidden strings. Each check prints one pass/fail line; any fail makes
# the script exit non-zero.
#
# This script is the single baked startup contract for the hardened template,
# so the checks assert exactly what the template and the image depend on: the
# env names the template will export, the jobs the script owns, and the
# absence of machinery the rebuild deliberately drops. code-server is NOT
# this script's job (the template's official Coder module owns it), and the
# checks pin that boundary too.
#
# Usage: bash tests/coder-workspace/startup-script.sh

set -u

cd "$(git rev-parse --show-toplevel)" || { echo "fail: cannot resolve repo root via git"; exit 2; }

STARTUP="containers/coder-workspace/workspace-startup.sh"

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
for var in OPENCODE_SERVER_PASSWORD GITHUB_TOKEN FORGEJO_TOKEN FORGEJO_HOST CODER_USER CODER_USER_EMAIL WORKSPACE_GIT_REPOS; do
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

# OpenChamber binds 0.0.0.0 only with an explicit unauthenticated-LAN waiver
# (user decision 2026-10-21); without it OpenChamber exits rather than serve.
if grep -qF 'OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN=true' "$STARTUP"; then
  pass "job: OpenChamber's non-loopback bind carries the ALLOW_UNAUTHENTICATED_LAN waiver"
else
  fail "job: OpenChamber would refuse its non-loopback bind (no ALLOW_UNAUTHENTICATED_LAN waiver)"
fi

# code-server is the template's official Coder module's job; a reinstall of
# it in the baked script would race the module and silently pin whatever the
# script fetched. Comments may name it; code must not.
cs_hit=$(code_lines "$STARTUP" | grep -in 'code-server' | head -n 1 || true)
if [ -z "$cs_hit" ]; then
  pass "job: no code-server install/start survives in the script (the module owns it)"
else
  fail "job: code-server machinery present in $STARTUP code ($cs_hit)"
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
