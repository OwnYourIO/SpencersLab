#!/usr/bin/env bash
# session-origin resolver behavior suite (2026/2026-10-bug-session-origin-no-line, C01).
#
# Pins the contract of scripts/session-origin.sh (DECISIONS D12/D13/D16, chunk
# C01.md tasks 1.1-1.3): the sanctioned resolution leg for a board launch whose
# command never expanded — one bounded derivation+probe of the command block's
# exact logic, emitting EXACTLY one `Session origin:` verdict line. Verdict is
# the LINE, never the exit code: exit 0 on resolved AND degraded (UNRESOLVED
# never blocks a run, D23-r2); exit 1 ONLY on caller misuse, and the mis-call
# still degrades to a verdict line instead of stalling the claim.
#
# D16: NO test seam in the script — an injectable probe answer is a forgery
# surface the command block never had. Determinism comes from the environment:
# real curl against loopback-listener fixtures (a python http.server on a
# kernel-assigned 127.0.0.1 port answers 200/4xx; a closed port answers ECONNREFUSED;
# a hung listener meets the real -m 5 timeout). The shipped code path is the
# tested code path, offline and DNS-free. Fixture hosts are clearly-fake or
# loopback — never a plausible real host is baked in (C01 Notes for dev).
#
# AC trace: b0[C01 AC1 bash -n] b1[AC2 row env-absent] b2[AC2 row shape]
# b3[AC2 rows answered-000 incl. timeout posture] b4[AC3 lowercase canonical +
# single bounded probe] b5[AC2 misuse exit 1] b6[AC3 five-surface fragment
# parity] negatives[AC5 no raw-env leakage + AC2 exactly-one-line].
#
# Red posture (test phase): the script does not exist yet — b0 fails
# file-not-found naming scripts/session-origin.sh, every b-check reads its
# output, and b6's script side reads its file; all name the absent C01 artifact,
# never a harness fault. Green after C01 dev lands the script.
#
# Usage:
#   bash tests/session-origin/script.sh            # b0..b6
#   bash tests/session-origin/script.sh b1 b6      # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SCRIPT="scripts/session-origin.sh"
CMD_FILES=(.rulesync/commands/pipeline-boards.md .opencode/commands/pipeline-boards.md
           .rulesync/commands/pipeline-boards-hourly.md .opencode/commands/pipeline-boards-hourly.md)

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s (artifacts kept at %s)\n' "$1" "$TMP" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/session-origin-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 0 1 2 3 4 5 6; do WANT["b$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^b[0-6]$ ]] || fail "unknown check id '$a' (expected b0..b6)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- loopback-listener fixtures (D16: real curl, no seam) -----------------------
# serve.py MODEs:
#   dir    — 200 on every path, counts requests to $TMP/hits (single-probe proof)
#   code:N — answers status N on every path (recognition-set gate: 403 in, 404 out)
#   hang   — accepts the connection and never answers (exercises the -m 5 timeout)
#   dead   — binds, prints the port, closes (connect-refused -> 000 without a server)
cat >"$TMP/serve.py" <<'PY'
import socket, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
mode = sys.argv[1]
hits_path = sys.argv[2]

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if mode == "dir":
            with open(hits_path, "a") as f:
                f.write(self.path + "\n")
            self.send_response(200); self.end_headers(); self.wfile.write(b"ok\n")
        else:
            code = int(mode.split(":")[1])
            self.send_response(code); self.end_headers(); self.wfile.write(b"no\n")
    def log_message(self, *a):
        pass

if mode == "hang":
    s = socket.socket(); s.bind(("127.0.0.1", 0))
    print(s.getsockname()[1], flush=True); s.listen(8)
    while True:
        c, _ = s.accept()
        threading.Thread(target=lambda: (time.sleep(30), c.close()), daemon=True).start()
elif mode == "dead":
    # pick a port that currently refuses: bind, release, then re-try a connect
    # and only accept the port when it is verifiably closed (closes the
    # kernel-reuse race that could otherwise flip 000 into a live listener)
    for _ in range(20):
        s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
        t = socket.socket(); t.settimeout(1)
        try:
            t.connect(("127.0.0.1", port)); t.close()
        except OSError:
            print(port, flush=True); sys.exit(0)
    sys.exit("no refused port found")
else:
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    print(srv.server_address[1], flush=True)
    srv.serve_forever()
PY

start_fixture() { # mode -> sets FX_PORT; supersedes the previous live fixture
  for p in ${FX_LIVE:-}; do kill "$p" 2>/dev/null || true; done
  FX_LIVE=""
  if [ "$1" = "dead" ]; then
    FX_PORT=$(python3 "$TMP/serve.py" dead "$TMP/hits")
    return  # the port is released again — that refusal is the fixture
  fi
  : >"$TMP/hits"; : >"$TMP/port"
  python3 "$TMP/serve.py" "$1" "$TMP/hits" >"$TMP/port" 2>/dev/null &
  FX_LIVE="$!"; FIXTURE_PIDS="$FIXTURE_PIDS $FX_LIVE"
  for _ in $(seq 1 100); do
    [ -s "$TMP/port" ] && break
    sleep 0.1
  done
  FX_PORT=$(head -1 "$TMP/port" 2>/dev/null || true)
  [ -n "${FX_PORT:-}" ] || fail "harness: loopback fixture ($1) did not report a port"
}
FIXTURE_PIDS=""
cleanup_fixtures() { for p in $FIXTURE_PIDS; do kill "$p" 2>/dev/null || true; done; }
trap cleanup_fixtures EXIT

# run_script <desc> <raw-env-or-UNSET> [args...] -> sets OUT/ERR/RC and enforces
# the shared verdict invariants: EXACTLY one stdout line, always starting
# 'Session origin: ', and the raw fixture env value absent from both streams
# (AC5 no-credentials posture; the raw string carries '{{port}}' and mixed case,
# so a legitimately-derived lowercased base can never false-positive it).
run_script() {
  local desc="$1" raw="$2"; shift 2
  RC=0
  if [ "$raw" = "UNSET" ]; then
    env -u VSCODE_PROXY_URI timeout 30 bash "$SCRIPT" >"$TMP/o" 2>"$TMP/e" || RC=$?
  else
    VSCODE_PROXY_URI="$raw" timeout 30 bash "$SCRIPT" "$@" >"$TMP/o" 2>"$TMP/e" || RC=$?
  fi
  NLINES=$(awk 'END{print NR}' "$TMP/o")
  [ "$NLINES" -eq 1 ] \
    || fail "$desc: stdout has $NLINES lines, want EXACTLY one (AC2: the verdict is one line)"
  head -1 "$TMP/o" | grep -qE '^Session origin: ' \
    || fail "$desc: line '$(head -1 "$TMP/o")' does not start 'Session origin: ' (AC2 vocabulary)"
  if [ "$raw" != "UNSET" ] && grep -qF "$raw" "$TMP/o" "$TMP/e"; then
    fail "$desc: raw VSCODE_PROXY_URI value echoed in output (AC5 no-credentials posture: only the derived canonical base or a reason token may be emitted)"
  fi
  OUT=$(head -1 "$TMP/o")
}

# --- b0: static gate (C01 AC1; shellcheck skip-with-warning, t1 convention) ------
if want b0; then
  [ -f "$SCRIPT" ] || fail "b0: $SCRIPT does not exist (red before C01 dev phase — the resolver script is the check target, cf-52's no-line gap has no sanctioned channel yet)"
  bash -n "$SCRIPT" || fail "b0: bash -n rejects $SCRIPT (C01 task 1.4 / AC1)"
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$SCRIPT" >"$TMP/sc.log" 2>&1 || { sed -n 1,20p "$TMP/sc.log" >&2; fail "b0: shellcheck findings (task 1.4's skip-with-warning is only for its ABSENCE)"; }
    ok "b0: script present, bash -n clean, shellcheck clean (when present — AC1)"
  else
    skip "b0: shellcheck not installed here — skipped with warning (task 1.4 convention)"
    ok "b0: script present and bash -n clean (shellcheck absent, skipped with warning)"
  fi
fi

# --- b1: env absent (C01 checklist b1) -------------------------------------------
if want b1; then
  [ -f "$SCRIPT" ] || fail "b1: $SCRIPT absent (red before C01 dev phase — env-absent verdict cannot be read from a missing script)"
  run_script "b1 env-absent" UNSET
  [ "$RC" -eq 0 ] || fail "b1: exit $RC, want 0 — UNRESOLVED never blocks the run (D12/D23-r2: verdict is the line, not the code)"
  [ "$OUT" = "Session origin: UNRESOLVED (no Coder app-origin env)" ] \
    || fail "b1: line '$OUT', want exactly 'Session origin: UNRESOLVED (no Coder app-origin env)' (block's verbatim reason)"
  ok "b1: unset VSCODE_PROXY_URI -> exact 'no Coder app-origin env' verdict, exit 0"
fi

# --- b2: template shape guard (C01 checklist b2) -----------------------------------
if want b2; then
  [ -f "$SCRIPT" ] || fail "b2: $SCRIPT absent (red before C01 dev phase — shape verdict cannot be read from a missing script)"
  run_script "b2 bad-shape" 'http://FIXTURE--EXAMPLE.INVALID:8443/plain-path'
  [ "$RC" -eq 0 ] || fail "b2: exit $RC, want 0 (degraded verdict still exits 0 — AC2)"
  [ "$OUT" = "Session origin: UNRESOLVED (unexpected VSCODE_PROXY_URI shape)" ] \
    || fail "b2: line '$OUT', want exactly 'Session origin: UNRESOLVED (unexpected VSCODE_PROXY_URI shape)' (no {{port}} -> shape branch, and NO probe was run: this fixture host must never be contacted)"
  ok "b2: shaped-guard env without {{port}} -> exact 'unexpected VSCODE_PROXY_URI shape' verdict, exit 0, no probe"
fi

# --- b3: shaped-but-unanswerable -> answered 000 (C01 checklist b3) ---------------
# Two real failure shapes of one branch: connect-refused on a closed port (b3a)
# and a hung listener meeting the real -m 5 timeout (b3b) — plus the single
# probe bound (no retry loop) proven on the served fixture in b4.
if want b3; then
  [ -f "$SCRIPT" ] || fail "b3: $SCRIPT absent (red before C01 dev phase — the answered-000 degrade branch has no script to run)"
  start_fixture dead
  run_script "b3a refused-port" "http://LOCALHOST:$FX_PORT/{{port}}"
  [ "$RC" -eq 0 ] || fail "b3a: exit $RC, want 0 (AC2: degraded verdict exits 0)"
  [ "$OUT" = "Session origin: UNRESOLVED (derived host answered 000)" ] \
    || fail "b3a: line '$OUT', want exactly 'Session origin: UNRESOLVED (derived host answered 000)' (D12: probe failure degrades to 000 on a dead loopback port, real curl, no seam)"

  start_fixture hang
  local_t0=$(date +%s)
  run_script "b3b hung-port" "http://LOCALHOST:$FX_PORT/{{port}}"
  local_t1=$(date +%s)
  [ "$RC" -eq 0 ] || fail "b3b: exit $RC, want 0"
  [ "$OUT" = "Session origin: UNRESOLVED (derived host answered 000)" ] \
    || fail "b3b: line '$OUT', want exactly 'Session origin: UNRESOLVED (derived host answered 000)' — a hung listener must hit the -m 5 timeout and degrade (D12 one bounded curl)"
  [ "$((local_t1 - local_t0))" -le 11 ] \
    || fail "b3b: run took $((local_t1 - local_t0))s against a hung listener — want <=11s (a single bounded -m 5 probe; a retry loop or unbounded connect breaks the probe posture)"
  ok "b3: dead port AND hung listener both degrade to exact 'answered 000' verdict, exit 0; timeout bounds the probe (no retry)"
fi

# --- b4: canonical transform on the RESOLVED path (C01 checklist b4) ---------------
# Mixed-case fixture env + {{port}} pointed at a loopback listener serving an
# `openchamber` path: proves sed+tr ran on the SUCCESS path (cf-50 AC7a's live
# shape) and that exactly ONE probe request was made (C01 1.2 no-retry bound).
if want b4; then
  [ -f "$SCRIPT" ] || fail "b4: $SCRIPT absent (red before C01 dev phase — the resolved branch has no script to run)"
  start_fixture dir
  RAW="http://LOCALHOST:$FX_PORT/{{port}}"
  WANT_LINE="Session origin: http://localhost:$FX_PORT/openchamber"
  run_script "b4 resolved-200" "$RAW"
  [ "$RC" -eq 0 ] || fail "b4: exit $RC, want 0 (resolved verdict exits 0 — AC2)"
  [ "$OUT" = "$WANT_LINE" ] \
    || fail "b4: line '$OUT', want exactly '$WANT_LINE' (D13: emitted base FULLY lowercased with {{port}} -> openchamber — the same transform the command block applies)"
  hits=$(wc -l <"$TMP/hits")
  [ "$hits" -eq 1 ] || fail "b4: listener saw $hits requests for one invocation, want exactly 1 (D12: one bounded curl per call, no retry)"

  # recognition-set positives beyond 200: 403 is recognized (resolved), while a
  # code outside {200,301,302,303,401,403} must degrade — the set gate is the
  # block's, so the script cannot "improve" it (b6 pins its bytes; this pins its effect).
  start_fixture code:403
  run_script "b4c resolved-403" "http://LOCALHOST:$FX_PORT/{{port}}"
  [ "$RC" -eq 0 ] || fail "b4c: exit $RC, want 0"
  [ "$OUT" = "Session origin: http://localhost:$FX_PORT/openchamber" ] \
    || fail "b4c: line '$OUT', want the resolved lowercased base — 403 is inside the recognition set"

  start_fixture code:404
  run_script "b4d degraded-404" "http://LOCALHOST:$FX_PORT/{{port}}"
  [ "$RC" -eq 0 ] || fail "b4d: exit $RC, want 0 (degraded verdict exits 0 — AC2)"
  [ "$OUT" = "Session origin: UNRESOLVED (derived host answered 404)" ] \
    || fail "b4d: line '$OUT', want exactly 'Session origin: UNRESOLVED (derived host answered 404)' — a code outside the recognition set degrades with the code in the reason"
  ok "b4: mixed-case env against a real listener -> fully-lowercased derived base (sed+tr on the success path), single probe, recognition set gates 403-in/404-out"
fi

# --- b5: caller misuse (C01 checklist b5) ------------------------------------------
if want b5; then
  [ -f "$SCRIPT" ] || fail "b5: $SCRIPT absent (red before C01 dev phase — the misuse branch has no script to run)"
  # the misuse call rides a LIVE listener fixture so hits==0 proves refusal
  # happens BEFORE any derivation/probe work (the grant blast-radius containment:
  # an argument-suffixed call must never spend the bounded curl the verdict needs)
  start_fixture dir
  RAW="http://LOCALHOST:$FX_PORT/{{port}}"
  for args in "foo" "--probe localhost" "a b"; do
    run_script "b5 misuse('$args')" "$RAW" $args
    [ "$RC" -eq 1 ] || fail "b5('$args'): exit $RC, want 1 — exit 1 ONLY on caller misuse (D12)"
    [ "$OUT" = "Session origin: UNRESOLVED (script misuse: unexpected arguments)" ] \
      || fail "b5('$args'): line '$OUT', want exactly 'Session origin: UNRESOLVED (script misuse: unexpected arguments)' — the mis-call degrades on the LINE (raw-id posture downstream) instead of stalling the claim"
  done
  [ ! -s "$TMP/hits" ] || fail "b5: misuse calls still probed the fixture host ($(wc -l <"$TMP/hits") requests seen) — the refusal must precede the derive+probe path (C01 1.1 branch order)"
  ok "b5: any argument(s) -> exact misuse verdict line + exit 1, raw env never echoed, refusal precedes any probe"
fi

# --- b6: five-surface fragment parity (C01 checklist b6, D12 drift guard) -----------
# The script is the 5th copy of the origin logic; the guard is that every shared
# fragment reads BYTE-IDENTICALLY across the script and the four command files
# (extends cf-50's md5-ladder class to five surfaces; commands stay READ-ONLY
# here — grepping them must never be allowed to fall through to a write).
if want b6; then
  [ -f "$SCRIPT" ] || fail "b6: $SCRIPT absent (red before C01 dev phase — the parity ladder has no 5th surface to compare)"
  fragments=(
    "sed 's/{{port}}/openchamber/' | tr 'A-Z' 'a-z'"
    "curl -s -o /dev/null -m 5 -w '%{http_code}'"
    "200|301|302|303|401|403"
    "no Coder app-origin env"
    "unexpected VSCODE_PROXY_URI shape"
    "derived host answered"
  )
  for frag in "${fragments[@]}"; do
    for f in "$SCRIPT" "${CMD_FILES[@]}"; do
      grep -qF -- "$frag" "$f" \
        || fail "b6: fragment '$frag' does not read identically in $f — the five surfaces (script + four command files) drift apart (D12; C02 must not touch commands or the script)"
    done
  done
  ok "b6: derivation segment, probe segment, recognition list and the three reason strings read byte-identically across the script and all four command files (five-surface ladder)"
fi

printf 'PASS: session-origin resolver behavior checks (%d ok)\n' "$checks"
