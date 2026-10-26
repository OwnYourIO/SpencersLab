#!/usr/bin/env bash
# C06 behavioral matrix (2026-10-feat-forgejo-auth-support): runs the REAL
# committed containers/coder-workspace/workspace-startup.sh under dash with a
# stubbed PATH (git, coder, fj, ssh-keygen, ssh-keyscan) and an isolated HOME
# scratch dir, then asserts what the script DOES, not what it greps like:
#   approved SSO  ⇒ no dev-host credential-helper SET, the stale helper is
#                  unset (git consults helpers before askpass — helpers would
#                  shadow the per-user token forever on the PVC), fj still
#                  gets the bot PAT, and the SSO token never lands on disk;
#   unapproved    ⇒ banner with the CLI's approval URL (exit-1 contract),
#                  PAT fallback wired, clones proceed;
#   neither       ⇒ gated skip (no raw credential failure) for the SSO host.
# Static greps cannot prove "helper NOT wired when approved" — DECISIONS
# 2026-10-24 mandates this behavioral coverage.
#
# FRICTION 2026-10-24 (review C02): the stub PATH MUST shadow `git` and HOME
# MUST be isolated before any git-touching fragment executes — a reviewer run
# without this wrote helper entries into the real ~/.gitconfig. `config` calls
# deliberately delegate to the REAL git (against the scratch HOME) so the
# on-disk credential state is the true observable; `clone` is intercepted
# (recording URL + transient-credential flags) because no real network auth
# can be proven here — coderd/askpass live verification is plan User action 5.
#
# Exit codes are captured WITHOUT pipes (FRICTION dev C01). A failed run keeps
# /tmp/opencode scratch for inspection; success cleans up.
#
# Run from the repo root (or anywhere in the worktree):
#   bash tests/coder-workspace/startup-sso-behavior.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

STARTUP="containers/coder-workspace/workspace-startup.sh"
[ -f "$STARTUP" ] || { printf 'FAIL: precondition: %s is missing\n' "$STARTUP" >&2; exit 1; }

REAL_GIT=$(command -v git) || { printf 'FAIL: precondition: no real git to delegate config to\n' >&2; exit 1; }
REAL_DASH=$(command -v dash) || { printf 'FAIL: precondition: dash not available (the script must run under it)\n' >&2; exit 1; }

DEV_HOST=git.scifi.farm
CAN_HOST=git.spencerslab.com
DEV_PAT=pat-dev-777
SSO_TOKEN_VALUE=sso-user-token-ZXCV99
SSO_URL="https://${DEV_HOST}/login/oauth/authorize?client_id=coder-stub&state=st8"
OAUTH_ID=forgejo

checks=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}
ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

WORK=$(mktemp -d /tmp/opencode/sso-behavior.XXXXXX)
BIN="$WORK/bin"
BIN_CODER="$WORK/bin-coder"
mkdir -p "$BIN" "$BIN_CODER"

# --- stubs ------------------------------------------------------------------
# The git wrapper logs every invocation, intercepts `clone` (a real https
# clone cannot authenticate against a live forge here; the decision WHAT to
# clone and WITH WHICH credential mechanism is the contract under test), and
# delegates everything else to the real git against the scenario HOME.
cat >"$BIN/git" <<EOF
#!/bin/sh
printf 'git %s\n' "\$*" >> "\$GIT_LOG"
found=0; url=""; dest=""
for a in "\$@"; do
  if [ "\$found" = 1 ]; then
    if [ -z "\$url" ]; then url=\$a; continue; fi
    case "\$a" in -*) continue ;; esac
    dest=\$a; break
  fi
  [ "\$a" = clone ] && found=1
done
if [ "\$found" = 1 ] && [ -n "\$url" ]; then
  [ -n "\$dest" ] || dest=\$(basename "\$url" .git)
  mkdir -p "\$dest/.git"
  # Transient-credential evidence, recorded WITHOUT the token value.
  tc="none"
  [ -n "\${GIT_CONFIG_VALUE_0:-}" ] && tc="env"
  case "\$*" in *-c*credential.helper*) tc="\${tc}-flag" ;; esac
  printf 'CLONE url=%s dest=%s transient=%s\n' "\$url" "\$dest" "\$tc" >> "\$GIT_LOG"
  exit 0
fi
exec "$REAL_GIT" "\$@"
EOF

cat >"$BIN/fj" <<'EOF'
#!/bin/sh
printf 'fj %s\n' "$*" >> "$FJ_LOG"
exit 0
EOF

# ssh-keygen: -F always "host unknown" (scan path taken), -y prints a stub
# public key, keygen creates the -f target so the chmod/cat below succeed.
cat >"$BIN/ssh-keygen" <<'EOF'
#!/bin/sh
case "$1" in
  -F) exit 1 ;;
  -y) printf 'ssh-rsa AAAAB3NACISTUBKEY coder@workspace\n'; exit 0 ;;
esac
target=""; prev=""
for a in "$@"; do
  [ "$prev" = "-f" ] && target=$a
  prev=$a
done
[ -n "$target" ] && : >"$target"
exit 0
EOF

cat >"$BIN/ssh-keyscan" <<'EOF'
#!/bin/sh
# Empty scan ⇒ the script's WARN path; keeps known_hosts handling offline and
# deterministic.
exit 0
EOF

# coder stub: exit 0 + validated token, or exit 1 + approval URL — the
# v2.35.2 `coder external-auth access-token` contract the gate is built on.
cat >"$BIN_CODER/coder" <<EOF
#!/bin/sh
printf 'coder %s\n' "\$*" >> "\$CODER_LOG"
case "\$SSO_STUB" in
  approved) printf '%s\n' "$SSO_TOKEN_VALUE"; exit 0 ;;
  url)     printf '%s\n' "$SSO_URL"; exit 1 ;;
esac
exit 127
EOF

chmod +x "$BIN/git" "$BIN/fj" "$BIN/ssh-keygen" "$BIN/ssh-keyscan" "$BIN_CODER/coder"

# --- scenario runner ---------------------------------------------------------
# run_scenario <name> <with-coder:yes|no> <stale-helper:yes|no> [KEY=VAL ...]
# Exports: OUT RC GIT_LOG CODER_LOG FJ_LOG HOME_DIR for the checks.
run_scenario() {
  local name=$1 with_coder=$2 stale=$3
  shift 3
  local home="$WORK/$name.home" logdir="$WORK/$name.logs"
  mkdir -p "$home" "$logdir"
  # .init_done short-circuits the /etc/skel seed (a different concern).
  : >"$home/.init_done"
  if [ "$stale" = yes ]; then
    # A PAT helper wired by an earlier pre-approval boot — on the real PVC it
    # outlives the pod, which is exactly why the approved path must unset it.
    cat >"$home/.gitconfig" <<EOF
[credential "https://${DEV_HOST}"]
	helper = !f() { echo username=token; echo password=\\\$FORGEJO_TOKEN; }; f
EOF
  fi
  local path="$BIN:/usr/bin:/bin"
  [ "$with_coder" = yes ] && path="$BIN_CODER:$path"
  GIT_LOG="$logdir/git.log" CODER_LOG="$logdir/coder.log" FJ_LOG="$logdir/fj.log"
  : >"$GIT_LOG"
  : >"$CODER_LOG"
  : >"$FJ_LOG"
  RC=0
  # `|| RC=$?` (not a bare call): under set -e a failing boot must reach the
  # rc assertions instead of silently aborting the harness.
  env -i \
    HOME="$home" PATH="$path" \
    GIT_LOG="$GIT_LOG" CODER_LOG="$CODER_LOG" FJ_LOG="$FJ_LOG" \
    SSO_STUB="${SSO_STUB:-none}" \
    CODER_USER=tester CODER_USER_EMAIL=tester@example.com \
    FORGEJO_HOST="$DEV_HOST" FORGEJO_TOKEN="$DEV_PAT" \
    FORGEJO_OAUTH_ID="$OAUTH_ID" \
    "$@" \
    "$REAL_DASH" "$STARTUP" >"$logdir/out" 2>"$logdir/err" || RC=$?
  OUT="$logdir/out" HOME_DIR="$home"
  export GIT_LOG CODER_LOG FJ_LOG
}

dev_set_calls()  { grep -E "config .*credential\.https://${DEV_HOST}\.helper" "$GIT_LOG" | grep -v -- '--unset' || true; }
dev_unset_calls(){ grep -E -- "--unset" "$GIT_LOG" | grep -E "credential\.https://${DEV_HOST}\.helper" || true; }

# ================= b-1: approved SSO + PAT pair ⇒ per-user wins ==============
SSO_STUB=approved run_scenario b1 yes no
[ "$RC" -eq 0 ] || fail "b-1: approved boot exited $RC (stderr: $(tail -n 3 "$WORK/b1.logs/err"))"
grep -qE "coder external-auth access-token ${OAUTH_ID}" "$CODER_LOG" ||
  fail "b-1: the probe never ran 'coder external-auth access-token ${OAUTH_ID}' — the SSO gate has no input"
ok "b-1: approved flow probes the coder CLI with the provider id"
[ -z "$(dev_set_calls)" ] ||
  fail "b-1: the dev-host PAT credential helper WAS wired while SSO is approved — the helper answers before askpass and shadows the per-user token ($(dev_set_calls))"
ok "b-1: approved ⇒ no dev-host credential.helper SET call"
[ -n "$(dev_unset_calls)" ] ||
  fail "b-1: approved ⇒ a stale dev-host credential.helper must be unset (PVC persists it across boots), none happened"
ok "b-1: approved ⇒ stale dev-host helper unset is issued"
if ! { grep -qF 'add-token' "$FJ_LOG" && grep -q "$DEV_PAT" "$FJ_LOG"; }; then
  fail "b-1: fj auth add-token never received the bot PAT — the fj floor must stay on the PAT even when git is per-user"
fi
ok "b-1: fj still gets the bot PAT while git goes per-user"
token_hits=$(grep -rlF "$SSO_TOKEN_VALUE" "$HOME_DIR" "$OUT" 2>/dev/null || true)
[ -z "$token_hits" ] || fail "b-1: the SSO token reached disk/log plaintext: $token_hits"
ok "b-1: the SSO token appears in no file under HOME and not in stdout"

# ================= b-2: approved clears a pre-seeded stale helper ============
SSO_STUB=approved run_scenario b2 yes yes
[ "$RC" -eq 0 ] || fail "b-2: approved-with-stale-helper boot exited $RC"
residual=$(HOME="$HOME_DIR" "$REAL_GIT" config --global --get "credential.https://${DEV_HOST}.helper" 2>/dev/null || true)
[ -z "$residual" ] ||
  fail "b-2: the stale helper survived approval (final config still answers '$residual') — askpass can never win while this line exists"
ok "b-2: final scratch gitconfig no longer carries the dev-host helper key"

# ================= b-3: unapproved + PAT ⇒ banner + fallback =================
SSO_STUB=url run_scenario b3 yes no \
  WORKSPACE_GIT_REPOS="https://${DEV_HOST}/org/lab.git"
[ "$RC" -eq 0 ] || fail "b-3: unapproved boot exited $RC (the gate must never die because of SSO)"
grep -qF "$SSO_URL" "$OUT" ||
  fail "b-3: the CLI's exit-1 approval URL was never printed — the user gets no 'approve here' path"
ok "b-3: unapproved ⇒ the approval URL from the CLI is printed"
grep -qiE 'approv' "$OUT" || fail "b-3: no approval prompt text in stdout"
grep -iE 'approv' "$OUT" | grep -qF "$DEV_HOST" ||
  fail "b-3: the approval banner never names the forge host it waits on"
ok "b-3: unapproved ⇒ host-naming approval banner printed"
[ -n "$(dev_set_calls)" ] || fail "b-3: unapproved with a PAT pair must wire the helper fallback (no SET call happened)"
ok "b-3: unapproved ⇒ PAT helper fallback is wired"
grep -q "CLONE url=https://${DEV_HOST}/org/lab.git" "$GIT_LOG" ||
  fail "b-3: the dev-forge repo was not cloned despite the working PAT fallback"
ok "b-3: dev-host repo still clones through the fallback (boot fully working)"

# ============ b-4: unapproved, NO dev PAT ⇒ gated skip, others run ==========
SSO_STUB=url run_scenario b4 yes no \
  FORGEJO_TOKEN="" WORKSPACE_GIT_REPOS="https://${DEV_HOST}/org/lab.git,https://${CAN_HOST}/org/other.git"
[ "$RC" -eq 0 ] || fail "b-4: gated boot exited $RC"
grep -qiE 'skip.*(pending|approv)|pending.*approval|not approved|awaiting' "$OUT" ||
  fail "b-4: the SSO-host clone without approval or PAT must log an explicit pending-approval skip, not fail raw"
ok "b-4: gated skip line printed instead of a raw credential failure"
if grep -q "CLONE url=https://${DEV_HOST}/org/lab.git" "$GIT_LOG"; then
  fail "b-4: the dev-forge repo was cloned with neither approval nor PAT"
fi
ok "b-4: unapproved+no-PAT dev-forge repo is skipped"
grep -q "CLONE url=https://${CAN_HOST}/org/other.git" "$GIT_LOG" ||
  fail "b-4: other-host repos must proceed while the SSO host is gated"
ok "b-4: the canonical-host repo cloned normally (gate is per-host)"

# ============ b-5: FORGEJO_OAUTH_ID absent ⇒ exactly C02 behavior ===========
SSO_STUB=approved run_scenario b5 yes no FORGEJO_OAUTH_ID=
[ "$RC" -eq 0 ] || fail "b-5: opt-out boot exited $RC"
[ ! -s "$CODER_LOG" ] || fail "b-5: without FORGEJO_OAUTH_ID the coder CLI must never be invoked, saw: $(head -n 2 "$CODER_LOG")"
ok "b-5: no SSO probe when FORGEJO_OAUTH_ID is unset (opt-out contract)"
[ -n "$(dev_set_calls)" ] || fail "b-5: the shipped helper wiring disappeared with the opt-out (PAT pair present)"
[ -z "$(dev_unset_calls)" ] || fail "b-5: unset fired without approval state — the opt-out must not touch the C02 contract"
! grep -qiE 'approv' "$OUT" || fail "b-5: an approval banner appeared without FORGEJO_OAUTH_ID"
ok "b-5: unset ⇒ helper wired, no probe/unset/banner — today's behavior byte-for-byte in effect"

# ============ b-6: coder CLI missing ⇒ warn/banner, boot survives ===========
SSO_STUB=none run_scenario b6 no no
[ "$RC" -eq 0 ] || fail "b-6: a missing coder CLI aborted the boot (exit $RC) — probe failure of any kind is the unapproved path"
[ -n "$(dev_set_calls)" ] || fail "b-6: CLI-missing must fall back to the PAT helper like the unapproved path"
grep -qiE 'approv|SSO|WARN' "$OUT" ||
  fail "b-6: CLI-missing printed no warn/banner line at all (banner-without-URL is the accepted shape)"
ok "b-6: missing coder CLI ⇒ warn/banner + PAT fallback, boot exit 0"

# ============ b-7: canonical PAT wiring is gone across ALL scenarios ========
# The canonical pair's PAT plumbing (forgejo-token-canonical) was removed
# unused 2026-10-26; the boot must never touch CAN_HOST credentials in any
# SSO state. CAN_HOST stays a clone-URL host only (SSH-key access and the
# gpu coder's external-auth provider still live there).
for s in b1 b2 b3 b4 b5 b6; do
  log="$WORK/$s.logs/git.log"
  [ -z "$(grep -E "credential\.https://${CAN_HOST}\.helper" "$log" || true)" ] ||
    fail "b-7: scenario $s — a CAN_HOST credential-helper call (set or unset) reappeared; the removed canonical PAT plumbing must not come back"
  ok "b-7: $s — no canonical-host credential calls (PAT plumbing removed)"
done

rm -rf "$WORK"
printf 'PASS: startup-sso-behavior checks (%d ok)\n' "$checks"
