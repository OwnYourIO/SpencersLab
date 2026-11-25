#!/usr/bin/env bash
# C02 behavioral contract (2026/2026-11-cf-56-feat-forgejo-coder-template-
# pipeline) for scripts/coder-template-push.sh — the per-template
# `coder templates push` driver the workflow's push job runs — plus the
# OQ5-ruling repo-side value supply (the terraform.tfvars legs). AC trace
# (chunks/C02.md AC3/AC4):
# p1[AC3a CODER_SESSION_TOKEN unset -> exit 0 + a ::warning:: line naming
#    it, no coder invocation recorded] p2[AC3b CODER_URL unset, token set
#    -> the same warn-and-skip posture] p3[AC3c configured: the recorded
#    argv is exactly the contract line — name positional, --directory path,
#    -y, --ignore-lockfile, --name <short-sha>, --message shape, NO --var
#    of any kind (the ruling: values ride the auto-loaded tfvars) — and the
#    token value appears NOWHERE in the recorded argv (env-only doctrine);
#    a dispatch without an event ref falls back to HEAD for the message
#    sha] p4[AC3d an unknown template name exits non-zero] p5[AC3e the
#    fake coder exiting non-zero -> the script exits non-zero
#    (propagation; the workflow's fail-fast: false matrix isolates the
#    siblings)] p6[AC4 the kubernetes tfvars carries exactly the three
#    version pins with unchanged values + namespace = "default"] p7[AC4 the
#    kubernetes-hardened tfvars exists, carries namespace = "default", and
#    keeps the kubernetes header style (the auto-load / resolved-values
#    comment)].
#
# The legs run the real script at the repo root against a FAKE `coder`
# executable on PATH — a bash stub that records its argv one line per
# argument; the exit code is caller-controlled. Offline: no network, no
# live Coder, every assert on the recorded argv. The invocation env is
# hermetic (env -i): the four contract vars (CODER_URL,
# CODER_SESSION_TOKEN, EVENT_NAME, SHA) are set per leg, so a "missing"
# leg truly is missing.
#
# AC4's chart packaging guard (helm package, the tfvars-stay-out-of-the-
# tgz count) and the terraform-validate smoke are plan Commands — both
# need egress (helm.coder.com / registry.terraform.io) and stay out of
# these offline suites by the plan's own "test suites are offline (house
# shape)" note; dev runs them per the plan Commands. These legs carry the
# static tfvars content those guards' value side depends on.
#
# Designed-RED until C02 lands the script + the tfvars legs.
#
# Run from the repo root:
#   bash tests/coder/coder-template-push-script.sh   # p1..p7
#   bash tests/coder/coder-template-push-script.sh p3   # subset
# Env: CODER_FAKE (point at a directory pre-populated with a `coder` stub
# honoring CODER_ARGV_LOG/CODER_FAKE_EXIT — the fanout-runbook FANOUT_ROOT
# green-shape convention; the default generates the stub under /tmp/opencode).
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/coder-template-push.sh"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 7); do WANT["p$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^p[1-7]$ ]] || fail "unknown leg id '$a' (expected p1..p7)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

[ -f "$SCRIPT" ] ||
  fail "$SCRIPT does not exist (designed-red: C02's push script is not implemented)"

OWN_FAKE=1
if [ -n "${CODER_FAKE:-}" ]; then
  FAKE_DIR="$CODER_FAKE"
  OWN_FAKE=0
else
  FAKE_DIR="$(mktemp -d /tmp/opencode/coder-template-push-fake.XXXXXX)"
fi
WORK="$(mktemp -d /tmp/opencode/coder-template-push-work.XXXXXX)"
cleanup() {
  if [ "$OWN_FAKE" = 1 ]; then rm -rf "$FAKE_DIR"; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

if [ "$OWN_FAKE" = 1 ]; then
  cat > "$FAKE_DIR/coder" <<'EOF'
#!/usr/bin/env bash
# test double: record argv one line per argument, then exit with the
# caller-controlled code (CODER_FAKE_EXIT, default 0).
if [ -n "${CODER_ARGV_LOG:-}" ]; then
  printf '%s\n' "$@" >> "$CODER_ARGV_LOG"
fi
exit "${CODER_FAKE_EXIT:-0}"
EOF
  chmod +x "$FAKE_DIR/coder"
fi

RC=0
# run_push <template-name> <fake-exit> [env VAR=val ...]
run_push() {
  local name="$1" code="$2"
  shift 2
  LOG="$WORK/argv.$(date +%s%N)"
  # Hermetic env: only PATH (with the fake dir first), HOME (for git),
  # the fake's recording vars, and the contract vars this leg sets.
  if ( cd "$ROOT" && env -i PATH="$FAKE_DIR:$PATH" HOME="$HOME" \
        CODER_ARGV_LOG="$LOG" CODER_FAKE_EXIT="$code" \
        "$@" bash "$SCRIPT" "$name" ) >"$WORK/.out" 2>"$WORK/.err"; then
    RC=0
  else
    RC=$?
  fi
  OUT="$(cat "$WORK/.out")"
  ERR="$(cat "$WORK/.err")"
}

# A missing key's warning may land on either stream; the model's die/warn
# shape writes stderr, but the contract only pins the line's content.
combined() { printf '%s\n%s' "$OUT" "$ERR"; }

# --- p1: CODER_SESSION_TOKEN unset -> warn-and-skip green (AC3a) ----------
if want p1; then
  run_push kubernetes 0 CODER_URL='https://coder.example.test' EVENT_NAME=push SHA=0123456789abcdef
  [ "$RC" -eq 0 ] ||
    fail "p1: a missing CODER_SESSION_TOKEN exited $RC — the designed outcome is exit 0 (the warn-and-skip green, the main-sync.yaml unset-vault posture): an unconfigured instance must skip, not fail"
  combined | grep -q '::warning::' ||
    fail "p1: no ::warning:: line — the skip must be marked so an unconfigured instance reads differently from a working one"
  combined | grep -qF 'CODER_SESSION_TOKEN' ||
    fail "p1: the warning does not name the missing key (CODER_SESSION_TOKEN)"
  if [ -s "$LOG" ]; then
    fail "p1: the coder binary was invoked despite the missing token — the skip must happen BEFORE any coder call, with no partial push"
  fi
  ok "p1: CODER_SESSION_TOKEN unset -> exit 0 + a ::warning:: naming it, no coder invocation"
fi

# --- p2: CODER_URL unset -> the same posture (AC3b) ------------------------
if want p2; then
  run_push kubernetes 0 CODER_SESSION_TOKEN='test-token-0123456789abcdef' EVENT_NAME=push SHA=0123456789abcdef
  [ "$RC" -eq 0 ] ||
    fail "p2: a missing CODER_URL exited $RC — the designed outcome is exit 0 (the warn-and-skip green)"
  combined | grep -q '::warning::' ||
    fail "p2: no ::warning:: line for the missing CODER_URL"
  combined | grep -qF 'CODER_URL' ||
    fail "p2: the warning does not name the missing key (CODER_URL)"
  if [ -s "$LOG" ]; then
    fail "p2: the coder binary was invoked despite the missing CODER_URL"
  fi
  ok "p2: CODER_URL unset (token set) -> exit 0 + a ::warning:: naming it, no coder invocation"
fi

# --- p3: configured -> exactly the contract argv, env-only token (AC3c) ----
if want p3; then
  token='test-token-0123456789abcdef'
  sha_val='0123456789abcdef0123456789abcdef01234567'
  short_sha="$(git -C "$ROOT" rev-parse --short HEAD)"
  run_push kubernetes 0 CODER_URL='https://coder.example.test' \
    CODER_SESSION_TOKEN="$token" EVENT_NAME=push SHA="$sha_val"
  [ "$RC" -eq 0 ] ||
    fail "p3: the configured push exited $RC — a working invocation must exit 0 (the fake coder exits 0)"
  expected="$(printf '%s\n' templates push kubernetes \
    --directory charts/coder/coder-templates/kubernetes \
    -y --ignore-lockfile \
    --name "$short_sha" \
    --message "forgejo push $sha_val")"
  if [ "$(cat "$LOG")" != "$expected" ]; then
    fail "p3: the recorded argv is not exactly the contract line.
expected:
$expected
recorded:
$(cat "$LOG")
 — name positional, --directory path, -y, --ignore-lockfile, --name <short-sha>, --message 'forgejo <event> <sha>' (event/sha from the EVENT_NAME/SHA env); every extra flag is a contract violation"
  fi
  if grep -qE '^--var($|[ |=])' "$LOG"; then
    fail "p3: a --var argument was passed — the OQ5-minimal ruling: NO value vars of any kind; template input values come from the auto-loaded terraform.tfvars + main.tf defaults (the repo)"
  fi
  if grep -qF "$token" "$LOG"; then
    fail "p3: the token value appears in the recorded argv — the token must never reach argv (the argocd-fanout.py doctrine: env-only, never argv, never files)"
  fi
  # The dispatch escape-hatch leg: a dispatch may carry no event ref — the
  # message sha falls back to HEAD. The plan pins "fall back to HEAD"
  # without a length, so the assert accepts the full or the short form
  # (both are HEAD-derived; the 7-char prefix distinguishes them from any
  # other value).
  run_push kubernetes 0 CODER_URL='https://coder.example.test' \
    CODER_SESSION_TOKEN="$token" EVENT_NAME=workflow_dispatch
  [ "$RC" -eq 0 ] || fail "p3: the dispatch-shaped invocation (no SHA env) exited $RC"
  head_sha="$(git -C "$ROOT" rev-parse HEAD)"
  grep -qF "forgejo workflow_dispatch ${head_sha:0:7}" "$LOG" ||
    fail "p3: a dispatch without an event ref did not fall back to HEAD — the --message sha is neither the full nor the short HEAD sha (recorded: $(grep -F 'forgejo' "$LOG" || true))"
  ok "p3: the configured argv is exactly the contract line (no --var, token env-only); a dispatch without an event ref falls back to HEAD for the message sha"
fi

# --- p4: an unknown template name exits non-zero (AC3d) ---------------------
if want p4; then
  run_push no-such-template 0 CODER_URL='https://coder.example.test' \
    CODER_SESSION_TOKEN='test-token-0123456789abcdef' EVENT_NAME=push SHA=0123456789abcdef
  [ "$RC" -ne 0 ] ||
    fail "p4: an unknown template name exited 0 — a matrix cell could not have come from the detect gate, so a name with no directory is a BUG, not an input: it must fail loudly"
  ok "p4: an unknown template name exits non-zero"
fi

# --- p5: the coder CLI's non-zero exit propagates (AC3e) -------------------
if want p5; then
  run_push kubernetes 3 CODER_URL='https://coder.example.test' \
    CODER_SESSION_TOKEN='test-token-0123456789abcdef' EVENT_NAME=push SHA=0123456789abcdef
  [ "$RC" -ne 0 ] ||
    fail "p5: the coder CLI's non-zero exit (the fake's 3) did not propagate — a failed push must fail the matrix cell; the workflow's fail-fast: false is what isolates the siblings, a swallowed exit is what loses them"
  ok "p5: the coder CLI's non-zero exit propagates to the script's exit"
fi

# --- p6: the kubernetes tfvars (AC4, static) -------------------------------
if want p6; then
  tf="$ROOT/charts/coder/coder-templates/kubernetes/terraform.tfvars"
  [ -f "$tf" ] || fail "p6: $tf does not exist"
  grep -qE '^opencode_version[[:space:]]*=[[:space:]]*"2\.0\.22"[[:space:]]*$' "$tf" ||
    fail "p6: opencode_version must stay 2.0.22 (AC4: the C02 tfvars edit adds a value, it never changes the existing pins)"
  grep -qE '^openchamber_version[[:space:]]*=[[:space:]]*"2\.1\.0"[[:space:]]*$' "$tf" ||
    fail "p6: openchamber_version must stay 2.1.0 (AC4)"
  grep -qE '^kilo_cli_version[[:space:]]*=[[:space:]]*"7\.7\.7"[[:space:]]*$' "$tf" ||
    fail "p6: kilo_cli_version must stay 7.7.7 (AC4)"
  n_pins=$(grep -cE '^[a-z_]+_version[[:space:]]*=' "$tf")
  [ "$n_pins" -eq 3 ] ||
    fail "p6: exactly three *_version pins expected, found $n_pins — the kubernetes tfvars carries the three version pins and NOTHING else of that kind"
  grep -qE '^namespace[[:space:]]*=[[:space:]]*"default"[[:space:]]*$' "$tf" ||
    fail "p6: namespace = \"default\" missing — the OQ5 ruling: the one value the repo must supply (namespace is the only required variable with no default in either template; default is verified on BOTH instances)"
  ok "p6: the kubernetes tfvars carries exactly the three unchanged pins (2.0.22 / 2.1.0 / 7.7.7) + namespace = \"default\""
fi

# --- p7: the kubernetes-hardened tfvars (AC4, static) ----------------------
if want p7; then
  tfh="$ROOT/charts/coder/coder-templates/kubernetes-hardened/terraform.tfvars"
  [ -f "$tfh" ] ||
    fail "p7: $tfh does not exist — C02 creates it (the hardened template had no tfvars pre-C02)"
  grep -qE '^namespace[[:space:]]*=[[:space:]]*"default"[[:space:]]*$' "$tfh" ||
    fail "p7: namespace = \"default\" missing — the hardened template's own header requires the namespace holding the dev git-auth secrets (github-pat, forgejo-token), verified default on the dev cluster"
  if ! grep -qiE 'auto.?loads? ' "$tfh" || ! grep -qF 'coder templates push' "$tfh"; then
    fail "p7: the header does not keep the kubernetes file's style (the auto-load / resolved-values comment naming the command that auto-loads terraform.tfvars on 'coder templates push') — C02 creates it WITH the same header style, not a bare value file"
  fi
  ok "p7: the kubernetes-hardened tfvars exists, carries namespace = \"default\", and keeps the kubernetes header style"
fi

printf 'PASS: coder template push-script checks (%d ok)\n' "$checks"
