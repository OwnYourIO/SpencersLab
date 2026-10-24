#!/usr/bin/env bash
# wekan-mcp container login contract (2026/2026-10-feat-dev-mcp-fleet, C02):
# username+password token minting against the WeKan POST /users/login endpoint,
# WEKAN_TOKEN precedence (gpu keeps injecting only the token — zero behavior
# change there), refresh-on-401 with a bounded retry, and the extended
# no-credentials error. dev-boards (C03) consumes exactly this image surface.
#
# Contract source: chunks/C02.md "## Tests" (t1-t6). AC trace:
# t1[C02 AC1] t2[mint] t3[precedence + AC4] t4[refresh-on-401]
# t5[no-creds, covers AC5 partially] t6[C02 AC3]
# t4's reject-all variant additionally proves the AC5 credential-hygiene rule
# on the failure path (the raised message must not echo the password).
#
# t2-t5 run against an in-process stdlib http.server mock (no fastmcp import —
# only wekan_mcp.wekan, which needs nothing beyond httpx + stdlib). httpx is
# resolved WEKAN_MCP_PY -> system python3 -> a persistent /tmp/opencode venv
# (created on demand; pip needs the network) — unresolvable => t2-t5 are
# skipped with a warning, the same fallback convention as the helm-download
# ladder in tests/services/dev-forgejo-runner.sh.
#
# Run from the repo root:
#   bash tests/containers/wekan-mcp-login.sh          # t1..t6
#   bash tests/containers/wekan-mcp-login.sh t1 t6    # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

CONTAINER_DIR="containers/wekan-mcp"
PKG_DIR="$CONTAINER_DIR/wekan_mcp"
VENV=/tmp/opencode/wekan-mcp-login-venv

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

skip() {
  printf 'skip: %s\n' "$1" >&2
}

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 6); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-6]$ ]] || fail "unknown test id '$a' (expected t1..t6)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

WORK=$(mktemp -d /tmp/opencode/wekan-mcp-login.XXXXXX)

[ -d "$PKG_DIR" ] || fail "container: $PKG_DIR does not exist — nothing to compile or exercise"

# --- t1: py_compile (C02 AC1) -------------------------------------------------
if want t1; then
  if python3 -m py_compile "$PKG_DIR"/*.py; then
    ok 't1: python3 -m py_compile passes for every wekan_mcp/*.py (C02 AC1)'
  else
    fail "t1: python3 -m py_compile failed for $PKG_DIR/*.py"
  fi
fi

# --- httpx interpreter ladder (t2-t5 dependency) ------------------------------
find_py() {
  if [ -n "${WEKAN_MCP_PY:-}" ] && "$WEKAN_MCP_PY" -c 'import httpx' 2>/dev/null; then
    printf '%s' "$WEKAN_MCP_PY"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import httpx' 2>/dev/null; then
    command -v python3
    return 0
  fi
  # Persistent venv survives runs; creation only happens when no interpreter
  # with httpx exists (the venv dir doubles as the cache).
  if [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c 'import httpx' 2>/dev/null; then
    printf '%s' "$VENV/bin/python"
    return 0
  fi
  python3 -m venv "$VENV" >/dev/null 2>&1 || return 1
  "$VENV/bin/pip" install --quiet --disable-pip-version-check httpx >/dev/null 2>&1 || return 1
  "$VENV/bin/python" -c 'import httpx' 2>/dev/null || return 1
  printf '%s' "$VENV/bin/python"
}

pybin=""
if want t2 || want t3 || want t4 || want t5; then
  pybin=$(find_py || true)
  if [ -z "$pybin" ]; then
    skip "t2: no python with httpx (system, WEKAN_MCP_PY, or a venv it could create here — pip needs the network); t2-t5 were not run"
  fi
fi

# The mock is written per run into WORK so every case imports one source of
# truth. Modes (chunk C02 t2-t5):
#   normal      — login mints, api accepts static + every minted token
#                 (WeKan old tokens stay valid after re-login, issue #1437)
#   expire-once — the first authenticated api call is 401'd once regardless of
#                 token, then normal (forces exactly one refresh-on-401 cycle)
#   reject-all  — 401 on everything including /users/login (bounded-retry +
#                 credential-hygiene case)
if [ -n "$pybin" ]; then
  cat >"$WORK/mock_wekan.py" <<'MOCK'
"""Stdlib WeKan stand-in for the wekan-mcp login contract (C02 tests)."""
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class MockWekan:
    def __init__(self, mode='normal', username='testuser', password='testpass',
                 static_token=None):
        self.mode = mode
        self.username = username
        self.password = password
        self.static_token = static_token
        self.records = []
        self._issued = set()
        self._login_count = 0
        self._reject_next_api = (mode == 'expire-once')
        outer = self

        class Handler(BaseHTTPRequestHandler):
            # Silence the default per-request stderr logging; the records list
            # is the only channel assertions read.
            def log_message(self, *args):
                pass

            def _send(self, status, obj, method=None, path=None,
                      content_type=None, body=None, authorization=None):
                payload = json.dumps(obj).encode()
                # Record BEFORE touching the socket: once the response starts
                # streaming the client may inspect records instantly, and an
                # append after wfile.write loses that race.
                outer.records.append({
                    'method': method or self.command,
                    'path': path or self.path,
                    'content_type': content_type,
                    'body': body,
                    'authorization': authorization,
                    'status': status,
                })
                self.send_response(status)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def do_POST(self):
                length = int(self.headers.get('Content-Length') or 0)
                raw = self.rfile.read(length) if length else b''
                try:
                    body = json.loads(raw) if raw else None
                except ValueError:
                    body = None
                ct = self.headers.get('Content-Type')
                auth = self.headers.get('Authorization')
                if self.path == '/users/login':
                    outer._login_count += 1
                    if outer.mode == 'reject-all':
                        self._send(401, {'error_code': 'error.accounts.Login_failed',
                                         'reason': 'Login failed (mock: reject-all)'},
                                   content_type=ct, body=body, authorization=auth)
                        return
                    if (ct or '').startswith('application/json') and \
                            isinstance(body, dict) and \
                            body.get('username') == outer.username and \
                            body.get('password') == outer.password:
                        tok = 'minted-%d' % outer._login_count
                        outer._issued.add(tok)
                        self._send(200, {'status': 'success', 'id': 'user-1',
                                         'token': tok,
                                         'tokenExpires': '2099-01-01T00:00:00.000Z'},
                                   content_type=ct, body=body, authorization=auth)
                    else:
                        # WeKan answers bad credentials with 401 + JSON.
                        self._send(401, {'error_code': 'error.accounts.Login_failed',
                                         'reason': 'Login failed'},
                                   content_type=ct, body=body, authorization=auth)
                    return
                self._send(404, {'error': 'not-found'},
                           content_type=ct, body=body, authorization=auth)

            def do_GET(self):
                auth = self.headers.get('Authorization')
                if self.path == '/api/user':
                    if outer.mode == 'reject-all':
                        self._send(401, {'error_code': '401',
                                         'reason': 'Unauthorized (mock: reject-all)'},
                                   authorization=auth)
                        return
                    if outer.mode == 'expire-once' and outer._reject_next_api:
                        outer._reject_next_api = False
                        self._send(401, {'error_code': '401',
                                         'reason': 'Token expired (mock: once)'},
                                   authorization=auth)
                        return
                    tok = auth[7:] if (auth or '').startswith('Bearer ') else None
                    if tok is not None and (tok in outer._issued or
                                            (outer.static_token and
                                             tok == outer.static_token)):
                        self._send(200, {'_id': 'user-1', 'username': outer.username},
                                   authorization=auth)
                    else:
                        self._send(401, {'error_code': '401',
                                         'reason': 'Unauthorized'},
                                   authorization=auth)
                    return
                self._send(404, {'error': 'not-found'}, authorization=auth)

        self.httpd = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.base_url = 'http://127.0.0.1:%d' % self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)

    def start(self):
        self.thread.start()

    def stop(self):
        self.httpd.shutdown()
        self.httpd.server_close()

    @property
    def login_hits(self):
        return sum(1 for r in self.records
                   if r['method'] == 'POST' and r['path'] == '/users/login')

    def api_calls(self, path='/api/user'):
        return [r for r in self.records if r['method'] == 'GET' and r['path'] == path]
MOCK
fi

# --- t2: username+password mints the bearer at startup (chunk "mint") ---------
if want t2 && [ -n "$pybin" ]; then
  if "$pybin" - "$CONTAINER_DIR" "$WORK" <<'PY'
import os, sys

pkg, work = sys.argv[1:3]
sys.path.insert(0, pkg)
sys.path.insert(0, work)

from mock_wekan import MockWekan
from wekan_mcp.wekan import WekanClient, WekanError  # the module under contract, no fastmcp

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

for k in list(os.environ):
    if k.startswith('WEKAN_'):
        del os.environ[k]

m = MockWekan(mode='normal')
m.start()
os.environ.update({'WEKAN_BASE_URL': m.base_url,
                   'WEKAN_USERNAME': 'testuser',
                   'WEKAN_PASSWORD': 'testpass'})
c = None
try:
    try:
        c = WekanClient()
    except WekanError as e:
        bad(f't2: WekanClient() raised {e!r} with only USERNAME/PASSWORD set — the startup mint path (chunk case 2) is the behavior C02 adds')
    me = c.validate()
    if not (isinstance(me, dict) and me.get('_id') == 'user-1'):
        bad(f't2: validate() returned {me!r}, expected the user dict with _id user-1')
    if c.user_id != 'user-1':
        bad(f't2: client.user_id is {c.user_id!r}, expected user-1 (validate must populate identity)')
    if m.login_hits != 1:
        bad(f't2: mock saw {m.login_hits} POST /users/login, expected exactly 1 (mint once at startup, not per request)')
    logins = [r for r in m.records if r['path'] == '/users/login']
    if not (logins[0]['content_type'] or '').startswith('application/json'):
        bad(f"t2: login POST content-type is {logins[0]['content_type']!r}, expected application/json — form data is documented-broken on WeKan /users/login")
    body = logins[0]['body']
    if not (isinstance(body, dict) and body.get('username') == 'testuser' and body.get('password') == 'testpass'):
        bad(f't2: login JSON body is {body!r}, expected the username/password pair')
    apis = m.api_calls()
    if not apis or apis[0]['authorization'] != 'Bearer minted-1':
        bad(f"t2: GET /api/user carried {((apis[0] if apis else {}).get('authorization'))!r}, expected the minted bearer 'Bearer minted-1'")
    if m.records.index(apis[0]) < m.records.index(logins[0]):
        bad('t2: /api/user was attempted before the login POST — the minted token must come first')
    print('ok: t2 — WEKAN_USERNAME/PASSWORD (no TOKEN) mint a bearer at startup; one JSON /users/login; validated GET /api/user carries it')
finally:
    m.stop()
    if c is not None:
        c.close()
PY
  then
    checks=$((checks + 1))
  else
    fail 't2: the mint-at-startup contract is not satisfied (reason printed above)'
  fi
fi

# --- t3: WEKAN_TOKEN precedence — gpu behavior verbatim (chunk "precedence") --
# C02 AC4: with a token present the code path must be behaviorally identical to
# today: the username/password pair is ignored and NO login POST happens
# (gpu injects only WEKAN_TOKEN; a login there would break a working fleet).
if want t3 && [ -n "$pybin" ]; then
  if "$pybin" - "$CONTAINER_DIR" "$WORK" <<'PY'
import os, sys

pkg, work = sys.argv[1:3]
sys.path.insert(0, pkg)
sys.path.insert(0, work)

from mock_wekan import MockWekan
from wekan_mcp.wekan import WekanClient

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

for k in list(os.environ):
    if k.startswith('WEKAN_'):
        del os.environ[k]

m = MockWekan(mode='normal', static_token='static-token-t3')
m.start()
os.environ.update({'WEKAN_BASE_URL': m.base_url,
                   'WEKAN_TOKEN': 'static-token-t3',
                   'WEKAN_USERNAME': 'testuser',
                   'WEKAN_PASSWORD': 'testpass'})
c = None
try:
    c = WekanClient()
    me = c.validate()
    if not (isinstance(me, dict) and me.get('_id') == 'user-1'):
        bad(f't3: validate() returned {me!r}, expected the user dict (token path must keep working)')
    if m.login_hits != 0:
        bad(f't3: mock saw {m.login_hits} POST /users/login, expected 0 — WEKAN_TOKEN must win outright (gpu backward compatibility, C02 AC4)')
    apis = m.api_calls()
    if not apis or apis[0]['authorization'] != 'Bearer static-token-t3':
        bad(f"t3: GET /api/user carried {((apis[0] if apis else {}).get('authorization'))!r}, expected 'Bearer static-token-t3'")
    print('ok: t3 — TOKEN set wins over USERNAME/PASSWORD: zero login calls, fixed bearer on the wire')
finally:
    m.stop()
    if c is not None:
        c.close()
PY
  then
    checks=$((checks + 1))
  else
    fail 't3: the WEKAN_TOKEN precedence contract is not satisfied (reason printed above)'
  fi
fi

# --- t4: refresh-on-401 (chunk "refresh-on-401") -------------------------------
# Positive: first authenticated call is rejected once -> exactly one re-login
# -> retry succeeds (login hits == 2). Negative (reject-all): every endpoint
# 401s -> WekanError raised, login hits bounded (<=2, the plan's single-retry
# guard), and the message carries neither the password nor any token (C02 AC5
# on the failure path).
if want t4 && [ -n "$pybin" ]; then
  if "$pybin" - "$CONTAINER_DIR" "$WORK" <<'PY'
import os, sys

pkg, work = sys.argv[1:3]
sys.path.insert(0, pkg)
sys.path.insert(0, work)

from mock_wekan import MockWekan
from wekan_mcp.wekan import WekanClient, WekanError

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

for k in list(os.environ):
    if k.startswith('WEKAN_'):
        del os.environ[k]

# positive
m = MockWekan(mode='expire-once')
m.start()
os.environ.update({'WEKAN_BASE_URL': m.base_url,
                   'WEKAN_USERNAME': 'testuser',
                   'WEKAN_PASSWORD': 'testpass'})
c = None
try:
    try:
        c = WekanClient()
    except WekanError as e:
        bad(f't4: WekanClient() raised {e!r} with only USERNAME/PASSWORD set — the startup mint path must exist before refresh-on-401 can be exercised')
    r = c.request('GET', '/api/user')
    if not (isinstance(r, dict) and r.get('_id') == 'user-1'):
        bad(f't4: the retried request returned {r!r}, expected the user dict')
    if m.login_hits != 2:
        bad(f't4: mock saw {m.login_hits} POST /users/login, expected exactly 2 (initial mint + one refresh; a second 401 must not loop)')
    apis = m.api_calls()
    if len(apis) != 2:
        bad(f't4: mock saw {len(apis)} GET /api/user calls, expected 2 (the 401 plus the retry)')
    if apis[-1]['authorization'] != 'Bearer minted-2':
        bad(f"t4: retry carried {apis[-1]['authorization']!r}, expected the re-minted 'Bearer minted-2'")
    print('ok: t4 — a 401 after credentials were used triggers exactly one re-login and one successful retry')
finally:
    m.stop()
    if c is not None:
        c.close()

# negative: 401 on everything, login included
for k in list(os.environ):
    if k.startswith('WEKAN_'):
        del os.environ[k]
m = MockWekan(mode='reject-all')
m.start()
os.environ.update({'WEKAN_BASE_URL': m.base_url,
                   'WEKAN_USERNAME': 'testuser',
                   'WEKAN_PASSWORD': 'testpass'})
c = None
try:
    try:
        c = WekanClient()
        c.request('GET', '/api/user')
        raised = None
    except WekanError as e:
        raised = e
    if raised is None:
        bad('t4: reject-all mock — no WekanError was raised; the client must fail closed on a dead login endpoint')
    if m.login_hits > 2:
        bad(f't4: reject-all mock — {m.login_hits} login attempts, expected <=2 (login must not auto-retry; infinite-retry guard, C02)')
    msg = str(raised)
    if 'testpass' in msg:
        bad(f't4: the WekanError message echoes the password (AC5): {msg!r}')
    if 'minted' in msg:
        bad(f't4: the WekanError message echoes a token: {msg!r}')
    print('ok: t4 — reject-all: WekanError raised, login attempts bounded (<=2), message free of credentials')
finally:
    m.stop()
    if c is not None:
        c.close()
PY
  then
    checks=$((checks + 2))
  else
    fail 't4: the refresh-on-401 contract is not satisfied (reason printed above)'
  fi
fi

# --- t5: no credentials at all (chunk "no-creds") ------------------------------
# The pre-C02 error named only WEKAN_TOKEN; the plan extends it to name both
# auth options, so all three env names must appear (the message is the
# operator's only diagnostic when the secret mapping is wrong).
if want t5 && [ -n "$pybin" ]; then
  if "$pybin" - "$CONTAINER_DIR" "$WORK" <<'PY'
import os, sys

pkg, work = sys.argv[1:3]
sys.path.insert(0, pkg)
sys.path.insert(0, work)

from wekan_mcp.wekan import WekanClient, WekanError

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

for k in list(os.environ):
    if k.startswith('WEKAN_'):
        del os.environ[k]
os.environ['WEKAN_BASE_URL'] = 'http://127.0.0.1:1'  # never connected to

try:
    WekanClient()
    bad('t5: no WekanError raised with no WEKAN_TOKEN and no USERNAME/PASSWORD pair')
except WekanError as e:
    msg = str(e)
    for name in ('WEKAN_TOKEN', 'WEKAN_USERNAME', 'WEKAN_PASSWORD'):
        if name not in msg:
            bad(f't5: the no-credentials error does not name {name} (message: {msg!r}) — the plan requires both auth options named')
    print('ok: t5 — no-credentials WekanError names WEKAN_TOKEN and the new WEKAN_USERNAME/WEKAN_PASSWORD alternative')
PY
  then
    checks=$((checks + 1))
  else
    fail 't5: the no-credentials error contract is not satisfied (reason printed above)'
  fi
fi

# --- t6: docker build (C02 AC3) ------------------------------------------------
# The pre-merge proof that the container actually builds (CI builds PRs
# without pushing; :main appears only after the user merges). Daemon/binary
# absence is a skip-with-warning (the helm-download-fallback convention); a
# build failure is only tolerated as a skip when the log shows a registry/
# network fault, never a code fault.
if want t6; then
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    skip "t6: docker binary or daemon not available here; the image build (C02 AC3) was not exercised"
  else
    build_log="$WORK/docker-build.log"
    if docker build "$CONTAINER_DIR" -t wekan-mcp:contract >"$build_log" 2>&1; then
      ok "t6: docker build $CONTAINER_DIR -t wekan-mcp:contract succeeds (C02 AC3)"
    elif grep -qiE 'dial tcp|no such host|TLS handshake|connection reset|context deadline|i/o timeout|toomanyrequests|rate limit|unauthorized' "$build_log"; then
      skip "t6: docker build failed on a registry/network condition here; re-run where ghcr.io/docker hub is reachable (log kept at $build_log)"
    else
      tail -n 40 "$build_log" >&2
      fail "t6: docker build failed for $CONTAINER_DIR (log kept at $build_log)"
    fi
  fi
fi

# A successful run is the only moment the /tmp workspace can go — a failed
# run keeps it so the docker-build "log kept at" pointer still resolves.
rm -rf "$WORK"

printf 'PASS: wekan-mcp-login checks (%d ok)\n' "$checks"
