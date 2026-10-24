#!/usr/bin/env bash
# Acceptance checks for containers/coder-workspace/workspace-startup.sh —
# the baked startup contract the Coder templates call. Covers criterion 1
# (POSIX sh, set -eu), the env contract, the SSH + clone jobs, the dual-host
# Forgejo wiring (2026-10-feat-forgejo-auth-support C02), and the forbidden
# strings. Each check prints one pass/fail line; any fail makes the script
# exit non-zero.
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
for var in OPENCODE_SERVER_PASSWORD GITHUB_TOKEN FORGEJO_TOKEN FORGEJO_HOST \
  FORGEJO_TOKEN_CANONICAL FORGEJO_HOST_CANONICAL CODER_USER CODER_USER_EMAIL WORKSPACE_GIT_REPOS; do
  if grep -Eq "(^|[^A-Za-z0-9_])\\\$\\{?${var}" "$STARTUP"; then
    pass "env: \${${var}} is read by the startup script"
  else
    fail "env: \${${var}} is not read by the startup script"
  fi
done

# --- dual-host Forgejo wiring (2026-10-feat-forgejo-auth-support C02) -------
# One wire_forgejo function serves both Forgejo pairs, so the canonical pair
# inherits the dev pair's guard/order/failure semantics instead of a drifting
# inline copy. The token travels by env-var NAME: the helper must expand it at
# use time, because the home PVC outlives the Secret and a config-time value
# would persist the token on disk.
if code_lines "$STARTUP" | grep -qE '\[ -n "?\$\{?FORGEJO_TOKEN_CANONICAL'; then
  pass "wire: the canonical pair sits behind its own -n guard (no env, no action)"
else
  fail "wire: FORGEJO_TOKEN_CANONICAL is not read in a '-n' guard context — the optional-pair contract is unmet"
fi

if code_lines "$STARTUP" | grep -qE '^[[:space:]]*wire_forgejo[[:space:]]*\([[:space:]]*\)[[:space:]]*\{'; then
  pass "wire: wire_forgejo is defined (single wiring path for both hosts)"
else
  fail "wire: no wire_forgejo function definition — the dual-host block was not factored out"
fi

can_ref=$(code_lines "$STARTUP" \
  | grep -E 'wire_forgejo.*FORGEJO_TOKEN_CANONICAL|password=\\\$\{?FORGEJO_TOKEN_CANONICAL' \
  | head -n 1 || true)
if [ -n "$can_ref" ]; then
  pass "helper: the canonical token is referenced by name at the wiring site or in a helper body"
else
  fail "helper: nothing references \$FORGEJO_TOKEN_CANONICAL by name — the helper would expand some other (or no) token at use time"
fi

# Both hosts seed fj through the function: every 'add-token' call-site must live
# inside wire_forgejo's body, not next to it for one pair only.
wf_body=$(awk '
  /^[[:space:]]*wire_forgejo[[:space:]]*\(/ { f = 1 }
  f { print }
  f && /^[[:space:]]*\}[[:space:]]*$/ { exit }
' "$STARTUP")
at_all=$(code_lines "$STARTUP" | grep -cF 'add-token' || true)
at_wf=$(printf '%s\n' "$wf_body" | grep -cF 'add-token' || true)
if [ "${at_wf:-0}" -ge 1 ] && [ "${at_all:-0}" -eq "${at_wf:-0}" ]; then
  pass "fj: 'fj auth add-token' is invoked only from wire_forgejo (both hosts share it)"
else
  fail "fj: ${at_all:-0} add-token call-site(s), ${at_wf:-0} inside wire_forgejo — one pair bypasses the shared function"
fi

if code_lines "$STARTUP" | grep -qF 'password=\$'; then
  pass "helper: the credential helper echoes a \$-referenced password (use-time expansion)"
else
  fail "helper: no 'password=\$' indirection survives in the script"
fi

bad_exp=$(code_lines "$STARTUP" | grep -E 'password=.{0,3}\$\{?(FORGEJO|GITHUB)_[A-Z_]*' | head -n 1 || true)
if [ -z "$bad_exp" ]; then
  pass "helper: no token env var is expanded into the helper at config time"
else
  fail "helper: token expanded at config time ($bad_exp) — the value would persist in ~/.gitconfig on the PVC"
fi

disk_hit=$(code_lines "$STARTUP" | grep -E 'git-credentials|(git[[:space:]]+config.*\bstore\b)' | head -n 1 || true)
if [ -z "$disk_hit" ]; then
  pass "no-disk: no credential-store file or 'store' helper (a store on the home PVC would outlive the Secret)"
else
  fail "no-disk: credential-store machinery present ($disk_hit)"
fi

tok_write=$(code_lines "$STARTUP" | grep -E '>>' | grep -E '\$\{?(FORGEJO|GITHUB)_TOKEN' | head -n 1 || true)
if [ -z "$tok_write" ]; then
  pass "no-disk: no token env var is redirected to a file"
else
  fail "no-disk: token redirected to disk ($tok_write)"
fi

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

# --- forge SSH pre-trust (2026-10-feat-forgejo-auth-support C02) ------------
# The lab forges serve ssh://git@<host>:22222 (sibling forgejo-ssh decision:
# node sshd keeps :22), so pre-trust must scan port 22222 — a port-22 scan of a
# forge host pins the NODE's sshd key under the wrong name, useless for those
# URLs. github.com stays at its default port.
if code_lines "$STARTUP" | grep -qE 'ssh-keyscan.*-p[[:space:]]'; then
  pass "ssh: ssh-keyscan runs with an explicit -p port"
else
  fail "ssh: no ssh-keyscan -p — the forge endpoints on :22222 would never be trusted"
fi

if code_lines "$STARTUP" | grep -qF '22222'; then
  pass "ssh: the forgejo SSH node port 22222 is referenced"
else
  fail "ssh: '22222' absent — the forges' real SSH endpoint is not pre-trusted"
fi

for host in git.scifi.farm git.spencerslab.com; do
  if code_lines "$STARTUP" | grep -qF "$host"; then
    pass "ssh: $host appears in code (scan list and/or key-registration banner)"
  else
    fail "ssh: $host absent from code — neither its host key is trusted nor its key registration advertised"
  fi
done

bad_scan=$(code_lines "$STARTUP" | grep -E 'ssh-keyscan' | grep -E 'git\.(scifi\.farm|spencerslab\.com)' | grep -vF '22222' | head -n 1 || true)
if [ -z "$bad_scan" ]; then
  pass "ssh: no lab forge is keyscanned at the default port"
else
  fail "ssh: a default-port scan of a lab forge remains ($bad_scan)"
fi

if grep -qF 'git.spencerslab.com' "$STARTUP"; then
  pass "banner: git.spencerslab.com is named so users know where to register the workspace key"
else
  fail "banner: the canonical instance is never named in the script"
fi

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
