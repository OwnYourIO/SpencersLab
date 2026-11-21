#!/usr/bin/env bash
# argocd-hook relay container contract (2026/2026-11-cf-139-feat-argocd-webhook-sync, C01-fix):
# dual-dialect HMAC-verified push hook -> allowed_refs config-list filter ->
# 202-async fan-out of real ArgoCD API syncs (root first, then OutOfSync
# repo-sourced children matching the fired ref; prune=false, never force,
# 409 tolerated, remote clusters first / local last, per-target timeout +
# isolation).
#
# C01-fix (rulings R3/R4) re-pin: the canonical caller is now the Forgejo
# main-sync hook-relay job, so deliveries are signed in BOTH dialects —
# X-Hub-Signature-256 with the sha256= prefix (the R2 GitHub-shaped door,
# behavior byte-preserved from C01) and X-Forgejo-Signature PLAIN hex (the
# job's dialect) — with first-present-header selection, hub header present
# => hub dialect ONLY, no cross-dialect fallback, absent both => 401. The
# HMAC key file renames github-<n>webhook -> hook-secret (semantics moved
# off GitHub); t3 gains the forge-delivery e2e leg byte-mirroring C04's
# payload/header recipe. Event/ref/filter/fan-out semantics are UNCHANGED —
# every C01 leg is kept and re-signed, not rewritten.
#
# Contract source: chunks/C01-fix.md "## Tests". AC trace:
# t1[AC1] t2[AC2+AC6+dual-check] t3[AC1+AC2 dialect matrix, AC3 semantics]
# t4[AC4] t5[AC5] t6[AC7] t7[AC4+AC6 README/rename contract]
# (AC8 is review-verified from the dev RESULT commands_run line, not scripted —
# and `docker build` has no daemon here: `.forgejo/workflows/containers-build.yaml`
# on the pushed branch is authoritative, per the plan's Commands section.)
#
# HARNESS-PINNED SURFACE (authored before the implementation, so dev must satisfy
# these in addition to the chunk's CLI list — all mechanical, no behavior change
# for the shipped image):
#   1. `main.py --config C --secrets-dir S [--port N] [--check]` — the chunk pins
#      --config/--secrets-dir/--check and EXPOSE 8080 but gives no listen-port
#      knob; the harness runs several relay instances on loopback, so --port
#      (default 8080) is the minimal CLI addition. The chart never passes it;
#      the deployed listener stays 8080.
#   2. Per-target audit line: exactly one line per target per push, on stdout or
#      stderr, containing the literal tokens `target=<name>` and
#      `result=ok|failed|skipped`. This is the chunk's "structured log line per
#      target (name, root, children count, ok/failed + reason)" with its two
#      harness-grepped tokens pinned; it is the only observation channel for
#      409-tolerance and skip classification (AC4/AC5).
#   3. Sync request shape pinned to the chunk's literal API call: POST
#      <url>/api/v1/applications[/<namespace>]/<name>/sync?prune=false — the
#      harness greps the QUERY for prune=false (a body-prune implementation
#      fails t4 on purpose), and bars any force flag in query or body.
#   4. Secret files are byte-exact: `hook-secret` holds the raw HMAC key
#      (R4 rename; the harness writes it without a trailing newline, so
#      strip or no-strip implementations both pass) and one file per
#      tokenKey, flat in --secrets-dir — the C02 token ES shape ("flat
#      filenames win", and the rendered ES secretKey must equal this exact
#      filename byte-for-byte; tests/services/argocd-hook-wiring.sh t2 pins
#      the chart side of that pair).
#   5. Signature dialects are harness constants: signed() produces the two
#      shapes (prefixed for the hub header, plain for the forgejo header);
#      the selection rule is first-present-of (X-Hub-Signature-256,
#      X-Forgejo-Signature) with the hub value REQUIRED to carry the prefix
#      and the forgejo value REQUIRED bare — a malformed present header 401s
#      even when the other header would verify (no cross-dialect fallback).
#      The old key filename appears nowhere in this harness, on purpose
#      (grep gate inside t7).
#
# t2-t5 exercise the REAL handler over loopback HTTP against a stdlib stub
# ArgoCD API (in-process mock-server pattern of tests/containers/
# wekan-mcp-login.sh; stdlib-only python, no interpreter ladder).
#
# Run from the repo root:
#   bash tests/containers/argocd-hook-relay.sh          # t1..t7
#   bash tests/containers/argocd-hook-relay.sh t1 t3    # subset
# Env: CHUNK_BASE=<ref> points the t6 scope diff at the pre-chunk commit
#      (review passes it; default HEAD = the working tree).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

RELAY_DIR="${HOOK_RELAY_DIR:-containers/argocd-hook}"
MAIN="$RELAY_DIR/main.py"
DOCKERFILE="$RELAY_DIR/Dockerfile"
README="$RELAY_DIR/README.md"
BASE="${CHUNK_BASE:-HEAD}"

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
  for i in $(seq 1 7); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-7]$ ]] || fail "unknown test id '$a' (expected t1..t7)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

command -v python3 >/dev/null 2>&1 || fail "python3 missing — the relay is stdlib-only by design and the harness needs it"

WORK=$(mktemp -d /tmp/opencode/argocd-hook-relay.XXXXXX)
# py_compile writes __pycache__ next to the source; redirect it out of the repo
# so this suite never mutates tracked state (t6's untracked scan would also
# report it as a scope violation).
export PYTHONPYCACHEPREFIX="$WORK/pycache"

# --- t1: files + Dockerfile tokens (AC1) --------------------------------------
if want t1; then
  for f in "$MAIN" "$DOCKERFILE" "$README"; do
    [ -f "$f" ] || fail "t1: $f missing (C01 AC1: main.py, Dockerfile and README.md all ship)"
  done
  grep -q 'python:3.11-slim-bookworm' "$DOCKERFILE" ||
    fail "t1: Dockerfile does not pin FROM python:3.11-slim-bookworm (C01 Dockerfile task — the renovate-managed base)"
  grep -q '65532' "$DOCKERFILE" ||
    fail "t1: Dockerfile has no uid/gid 65532 non-root block (C01 AC1)"
  grep -Eq '^[[:space:]]*ENTRYPOINT' "$DOCKERFILE" ||
    fail "t1: Dockerfile has no ENTRYPOINT (C01 AC1: ENTRYPOINT, not CMD)"
  grep -Eq '^[[:space:]]*EXPOSE 8080' "$DOCKERFILE" ||
    fail "t1: Dockerfile has no EXPOSE 8080 (C01 AC1)"
  if grep -Eq 'pip[[:space:]]+install' "$DOCKERFILE"; then
    fail "t1: Dockerfile runs pip install — the relay is stdlib-only, no pip deps (C01 AC1)"
  fi
  if [ -e "$RELAY_DIR/requirements.txt" ]; then
    fail "t1: $RELAY_DIR/requirements.txt exists — stdlib-only means no requirements file (C01 Dockerfile task)"
  fi
  if grep -Eiq 'COPY[^[:space:]].*(secret|token|webhook|targets\.json)' "$DOCKERFILE"; then
    fail "t1: Dockerfile COPYes a secret/target path — config and secrets arrive via chart-mounted volumes, never the image (C01 AC1)"
  fi
  ok "t1: main.py+Dockerfile+README present; Dockerfile pins the base, uid 65532, ENTRYPOINT, EXPOSE 8080; no pip deps, no secret COPY (AC1)"
fi

# --- shared harness (t2..t5) ---------------------------------------------------
if want t2 || want t3 || want t4 || want t5; then
  [ -f "$MAIN" ] || fail "harness: $MAIN does not exist — nothing for t2-t5 to exercise (C01 not implemented)"
  cat > "$WORK/harness.py" <<'HARNESS'
"""Stub ArgoCD API + relay-subprocess driver for the argocd-hook C01 contract.

One shared records list across stubs makes cross-target fan-out ordering
assertable (remote-first / local-last). The relay runs as a real subprocess on
an ephemeral loopback port — webhook-handler behavior (401/400/200/202, HMAC,
ref filter) is proven over the wire, not against mock request objects.
"""
import hashlib
import hmac
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib import error as urlerror
from urllib import request as urlrequest

REPO = "https://github.com/OwnYourIO/SpencersLab.git"
OTHER_REPO = "https://github.com/OwnYourIO/OtherThings.git"
GH_SECRET = b"gh-hook-secret-SENTINEL-c1f9"

REC_LOCK = threading.Lock()


def record(records, rec):
    # The seq counter is the ordering authority: two identical list calls are
    # equal dicts, so records.index() would resolve the second one to the
    # first's position and cross-target ordering asserts would lie.
    with REC_LOCK:
        stamped = dict(rec, seq=len(records))
        records.append(stamped)


def token_for(name):
    return ("tok-%s-SENTINEL-7a3d" % name).encode()


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def sign(secret, body):
    return "sha256=" + hmac.new(secret, body, hashlib.sha256).hexdigest()


def sign_plain(secret, body):
    # R3 forge dialect: bare lowercase hex, no prefix — what openssl
    # `dgst -sha256 -hmac ... | awk '{print $NF}'` produces in C04's job.
    return hmac.new(secret, body, hashlib.sha256).hexdigest()


def forge_push_body(ref, before, after, full_name):
    """Byte-mirror of the main-sync hook-relay payload (C04 contract):
    json.dumps from env with exactly ref/before/after/repository.full_name;
    tests/services/forgejo-main-sync.sh t11 pins the same key set."""
    return json.dumps({
        "ref": ref,
        "before": before,
        "after": after,
        "repository": {"full_name": full_name},
    }).encode()


def push_body(ref):
    return json.dumps({
        "ref": ref,
        "before": "0" * 40,
        "after": "1" * 40,
        "repository": {"name": "SpencersLab", "full_name": "OwnYourIO/SpencersLab",
                       "html_url": "https://github.com/OwnYourIO/SpencersLab"},
        "pusher": {"name": "harness"},
    }).encode()


def ping_body():
    return json.dumps({
        "zen": "Keep it simple.",
        "hook_id": 1,
        "repository": {"name": "SpencersLab", "full_name": "OwnYourIO/SpencersLab"},
    }).encode()


def app(name, repo, revision, status):
    return {
        "metadata": {"name": name, "namespace": "default"},
        "spec": {"source": {"repoURL": repo, "targetRevision": revision,
                            "path": "services/%s/prod" % name}},
        "status": {"sync": {"status": status}},
    }


class StubArgo:
    """Stand-in for one cluster's ArgoCD API server.

    apps      — list payload for GET /api/v1/applications (re-read per call)
    sync_codes— per-app POST sync status override (default 200; 409 = the
                "operation already running" tolerance case; 503/500 = failure)
    get_code  — non-200 makes the whole list call fail (dead-cluster case)
    get_delay — seconds to stall the list call (async-order + timeout cases)
    """

    def __init__(self, name, records, apps=None, sync_codes=None,
                 get_code=200, get_delay=0.0):
        self.name = name
        self.records = records
        self.apps = apps or []
        self.sync_codes = sync_codes or {}
        self.get_code = get_code
        self.get_delay = get_delay
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def _send(self, code, obj):
                payload = json.dumps(obj).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def do_GET(self):
                path = self.path.split("?", 1)[0].rstrip("/")
                rec = {"stub": outer.name, "method": "GET", "path": self.path,
                       "auth": self.headers.get("Authorization")}
                if path.endswith("/api/v1/applications"):
                    if outer.get_delay:
                        time.sleep(outer.get_delay)
                    record(outer.records, dict(rec, kind="list"))
                    if outer.get_code != 200:
                        self._send(outer.get_code, {"error": {"message": "mock list failure"}})
                    else:
                        self._send(200, {"items": list(outer.apps)})
                else:
                    record(outer.records, dict(rec, kind="other"))
                    self._send(404, {"error": {"message": "not found"}})

            def do_POST(self):
                length = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(length) if length else b""
                try:
                    parsed = json.loads(raw) if raw else None
                except ValueError:
                    parsed = raw.decode(errors="replace")
                path = self.path.split("?", 1)[0].rstrip("/")
                rec = {"stub": outer.name, "method": "POST", "path": self.path,
                       "auth": self.headers.get("Authorization"), "body": parsed}
                if path.endswith("/sync"):
                    name = path.split("/")[-2]
                    record(outer.records, dict(rec, kind="sync", app=name))
                    code = outer.sync_codes.get(name, 200)
                    if code == 200:
                        self._send(200, {"status": {"operationState": {"phase": "Succeeded"}}})
                    else:
                        self._send(code, {"error": {"message": "another operation is already in progress"}})
                else:
                    record(outer.records, dict(rec, kind="other"))
                    self._send(404, {"error": {"message": "not found"}})

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.httpd.daemon_threads = True
        self.url = "http://127.0.0.1:%d" % self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)

    def start(self):
        self.thread.start()

    def stop(self):
        self.httpd.shutdown()
        self.httpd.server_close()

    def calls(self, records):
        return [r for r in records if r["stub"] == self.name]

    def lists(self, records):
        return [r for r in self.calls(records) if r["kind"] == "list"]

    def syncs(self, records):
        return [r for r in self.calls(records) if r["kind"] == "sync"]


def make_fixtures(dirpath, targets, allowed_refs="UNSET"):
    """Write config + flat secrets dir; returns (config_path, secrets_dir).

    allowed_refs="UNSET" omits the key entirely — the absent-key default is a
    tested behavior (OQ7: default ["refs/heads/main"]).
    """
    cfg_dir = os.path.join(dirpath, "config")
    sec_dir = os.path.join(dirpath, "secrets")
    os.makedirs(cfg_dir, exist_ok=True)
    os.makedirs(sec_dir, exist_ok=True)
    # R4 rename: the shared HMAC key file is hook-secret (semantics moved
    # off GitHub; the caller is the main-sync hook-relay job). The rendered
    # chart ExternalSecret secretKey must equal this filename byte-for-byte.
    with open(os.path.join(sec_dir, "hook-secret"), "wb") as f:
        f.write(GH_SECRET)
    roster = []
    for t in targets:
        name = t["name"]
        token_key = t.get("tokenKey", name)
        with open(os.path.join(sec_dir, token_key), "wb") as f:
            f.write(token_for(name))
        entry = {"name": name, "url": t["url"], "rootApp": t.get("rootApp", name),
                 "tokenKey": token_key, "repo": t.get("repo", REPO)}
        if t.get("local"):
            entry["local"] = True
        roster.append(entry)
    cfg = {"targets": roster}
    if allowed_refs != "UNSET":
        cfg["allowed_refs"] = allowed_refs
    cfg_path = os.path.join(cfg_dir, "targets.json")
    with open(cfg_path, "w") as f:
        json.dump(cfg, f)
    return cfg_path, sec_dir


class Relay:
    """Real relay subprocess + log/result scanner."""

    def __init__(self, main_py, config_path, secrets_dir, log_path, env=None):
        self.main_py = main_py
        self.config_path = config_path
        self.secrets_dir = secrets_dir
        self.log_path = log_path
        self.extra_env = env or {}
        self.proc = None
        self.logf = None
        self.port = None

    def start(self):
        self.port = free_port()
        env = dict(os.environ)
        env.update(self.extra_env)
        self.logf = open(self.log_path, "w")
        self.proc = subprocess.Popen(
            [sys.executable, "-u", self.main_py,
             "--config", self.config_path, "--secrets-dir", self.secrets_dir,
             "--port", str(self.port)],
            stdout=self.logf, stderr=subprocess.STDOUT, env=env)
        deadline = time.time() + 10
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError("relay exited at startup (rc=%s); log:\n%s"
                                   % (self.proc.returncode, self.log()))
            try:
                with urlrequest.urlopen("http://127.0.0.1:%d/health" % self.port, timeout=1) as r:
                    if r.status == 200:
                        return
            except Exception:
                time.sleep(0.1)
        raise RuntimeError("relay /health never answered 200 within 10s; log:\n%s" % self.log())

    def log(self):
        try:
            with open(self.log_path, errors="replace") as f:
                return f.read()
        except OSError:
            return ""

    def result_lines(self):
        out = []
        for line in self.log().splitlines():
            mt = re.search(r"(?<![A-Za-z0-9_-])target=([A-Za-z0-9_.-]+)", line)
            mr = re.search(r"(?<![A-Za-z0-9_-])result=(ok|failed|skipped)(?![A-Za-z0-9_-])", line)
            if mt and mr:
                out.append((mt.group(1), mr.group(1)))
        return out

    def wait_results(self, names, timeout):
        deadline = time.time() + timeout
        while time.time() < deadline:
            seen = {}
            for n, r in self.result_lines():
                seen[n] = r
            if all(n in seen for n in names):
                return seen
            time.sleep(0.1)
        seen = {}
        for n, r in self.result_lines():
            seen[n] = r
        return seen

    def post(self, event, body, sig="good", timeout=8.0, headers_extra=None):
        headers = {"Content-Type": "application/json"}
        if event is not None:
            headers["X-GitHub-Event"] = event
        # R3 dialect matrix: good/bad are the hub (prefixed) shape kept
        # byte-identical from C01; forgejo* are the plain-hex shape the
        # main-sync job sends; the mixed/bare/prefixed-cross shapes pin the
        # first-present-header selection rule with NO cross-dialect fallback.
        if sig == "good":
            headers["X-Hub-Signature-256"] = sign(GH_SECRET, body)
        elif sig == "bad":
            headers["X-Hub-Signature-256"] = sign(b"definitely-wrong-secret", body)
        elif sig == "forgejo":
            headers["X-Forgejo-Signature"] = sign_plain(GH_SECRET, body)
        elif sig == "forgejo-bad":
            headers["X-Forgejo-Signature"] = sign_plain(b"definitely-wrong-secret", body)
        elif sig == "hub-bare":
            headers["X-Hub-Signature-256"] = sign_plain(GH_SECRET, body)
        elif sig == "forgejo-prefixed":
            headers["X-Forgejo-Signature"] = sign(GH_SECRET, body)
        elif sig == "mixed":
            headers["X-Hub-Signature-256"] = sign(b"definitely-wrong-secret", body)
            headers["X-Forgejo-Signature"] = sign_plain(GH_SECRET, body)
        elif sig == "mixed-good":
            headers["X-Hub-Signature-256"] = sign(GH_SECRET, body)
            headers["X-Forgejo-Signature"] = sign_plain(b"definitely-wrong-secret", body)
        if headers_extra:
            headers.update(headers_extra)
        req = urlrequest.Request("http://127.0.0.1:%d/" % self.port,
                                 data=body, headers=headers, method="POST")
        t0 = time.monotonic()
        try:
            with urlrequest.urlopen(req, timeout=timeout) as r:
                return r.status, time.monotonic() - t0
        except urlerror.HTTPError as e:
            e.read()
            return e.code, time.monotonic() - t0

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
        if self.logf:
            self.logf.close()
HARNESS
fi

# --- t2: py_compile + --check contract (AC2 + AC6) -----------------------------
if want t2; then
  if python3 - "$MAIN" "$WORK" <<'PY'
import json, os, subprocess, sys

main_py, work = sys.argv[1:3]
sys.path.insert(0, work)
import harness as h


def bad(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)


rc = subprocess.run([sys.executable, "-m", "py_compile", main_py],
                    capture_output=True, text=True)
if rc.returncode != 0:
    bad("t2: python3 -m py_compile failed: %s" % rc.stderr[:400])

records = []
stub = h.StubArgo("dev", records)
stub.start()
try:
    # All three roster entries share the one stub URL so any --check network
    # attempt — however it forms the request — lands in `records` and is seen.
    cfg, secrets = h.make_fixtures(
        os.path.join(work, "t2"),
        [{"name": "dev", "url": stub.url},
         {"name": "grow", "url": stub.url},
         {"name": "proxy-local", "url": stub.url, "local": True}],
        allowed_refs=["refs/heads/main"])

    def run_check(config, secrets_dir):
        return subprocess.run([sys.executable, "-u", main_py, "--check",
                               "--config", config, "--secrets-dir", secrets_dir],
                              capture_output=True, text=True, timeout=30)

    r = run_check(cfg, secrets)
    out = r.stdout + r.stderr
    if r.returncode != 0:
        bad("t2: --check on the valid fixture exited %s\n%s" % (r.returncode, out[:600]))
    for name in ("dev", "grow", "proxy-local"):
        if name not in out:
            bad("t2: --check printed no roster row for %r (AC6: it prints the target table); output:\n%s" % (name, out[:600]))
    if records:
        bad("t2: --check dialed the network — %d stub requests landed (C01 notes: --check must never dial)" % len(records))

    for needle in ("SENTINEL", "gh-hook-secret", "tok-"):
        if needle in out:
            bad("t2: --check success output echoes secret material (%r) (AC6)" % needle)

    broken = os.path.join(work, "t2-broken.json")
    with open(broken, "w") as f:
        f.write("{ not valid json ]")
    r = run_check(broken, secrets)
    if r.returncode == 0:
        bad("t2: --check accepted a malformed targets.json (AC6 requires non-zero)")
    out = r.stdout + r.stderr
    for needle in ("SENTINEL", "gh-hook-secret", "tok-"):
        if needle in out:
            bad("t2: the malformed-JSON failure output echoes secret material (%r) (AC6: no secret echo in any error message)" % needle)

    cfg_no_tokens, secrets_no_tokens = h.make_fixtures(
        os.path.join(work, "t2-notoken"),
        [{"name": "grow", "url": stub.url}],
        allowed_refs=["refs/heads/main"])
    os.remove(os.path.join(secrets_no_tokens, "grow"))
    r = run_check(cfg_no_tokens, secrets_no_tokens)
    if r.returncode == 0:
        bad("t2: --check passed with the referenced token file missing (AC6: unreadable secret file -> non-zero)")
    out = r.stdout + r.stderr
    for needle in ("SENTINEL", "gh-hook-secret", "tok-"):
        if needle in out:
            bad("t2: the missing-secret failure output echoes secret material (%r) (AC6)" % needle)

    with open(cfg) as f:
        blob = json.load(f)
    blob["allowed_refs"] = "refs/heads/main"
    cfg_badrefs = os.path.join(work, "t2-badrefs.json")
    with open(cfg_badrefs, "w") as f:
        json.dump(blob, f)
    r = run_check(cfg_badrefs, secrets)
    if r.returncode == 0:
        bad("t2: --check accepted a non-list allowed_refs (C01: --check validates the allowed_refs shape)")

    blob = json.load(open(cfg))
    del blob["targets"][0]["rootApp"]
    cfg_badroster = os.path.join(work, "t2-badroster.json")
    with open(cfg_badroster, "w") as f:
        json.dump(blob, f)
    r = run_check(cfg_badroster, secrets)
    if r.returncode == 0:
        bad("t2: --check accepted a roster entry without rootApp (C01: --check validates the roster shape)")

    # C01-fix/R4: --check must resolve the key at the NEW flat filename —
    # deleting hook-secret must fail the self-test even though every other
    # file is intact. This leg (and the valid-fixture exit 0 above, whose
    # fixture now ships only hook-secret) reddens until the constant is
    # renamed.
    os.remove(os.path.join(secrets, "hook-secret"))
    r = run_check(cfg, secrets)
    if r.returncode == 0:
        bad("t2: --check passed with hook-secret missing (R4: the HMAC key must be read under the new filename — anything still reading the C01 name is rejected)")

    # C01-fix/R3: the --check round trip now runs BOTH dialects (plus both
    # forgery rejects) and its success output names them — pinned loosely
    # (header families, not exact sentences) so the contract is the naming,
    # not the prose.
    cfg2, secrets2 = h.make_fixtures(os.path.join(work, "t2-restored"),
                                     [{"name": "dev", "url": stub.url}],
                                     allowed_refs=["refs/heads/main"])
    r = run_check(cfg2, secrets2)
    if r.returncode != 0:
        bad("t2: --check on the restored hook-secret fixture exited %s (dual-dialect round trip must stay green; C01-fix --check task)\n%s" % (r.returncode, (r.stdout + r.stderr)[:600]))
    out = (r.stdout + r.stderr).lower()
    for dialect in ("hub", "forgejo"):
        if dialect not in out:
            bad("t2: --check success output never names the %s dialect — R3 pins the dual round-trip lines (C01-fix: 'success line names both')" % dialect)
finally:
    stub.stop()

print("ok: t2 — py_compile clean; --check exits 0 with the roster table and zero network, names BOTH dialects on success, fails on malformed JSON, unreadable secrets (incl. the hook-secret rename), bad allowed_refs and bad roster shapes, and never echoes secret bytes (AC2+AC6/C01-fix)")
PY
  then
    ok "t2 passed (AC2+AC6)"
  else
    fail "t2: the py_compile/--check contract is not satisfied (reason printed above)"
  fi
fi

# --- t3: handler behavior matrix (AC3) ------------------------------------------
if want t3; then
  if python3 - "$MAIN" "$WORK" <<'PY'
import os, sys, time

main_py, work = sys.argv[1:3]
sys.path.insert(0, work)
import harness as h


def bad(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)


WIDENED = ["refs/heads/main", "refs/heads/stage"]

# relay1: never fires fan-out — reject/no-op matrix + health
records1 = []
stub1 = h.StubArgo("dev", records1, apps=[h.app("dev", h.REPO, "main", "OutOfSync")])
relay1 = None
try:
    stub1.start()
    cfg, secrets = h.make_fixtures(os.path.join(work, "t3-fast"),
                                   [{"name": "dev", "url": stub1.url}],
                                   allowed_refs=WIDENED)
    relay1 = h.Relay(main_py, cfg, secrets, os.path.join(work, "t3-fast.log"))
    relay1.start()

    status, _ = relay1.post("push", h.push_body("refs/heads/main"), sig="bad")
    if status != 401:
        bad("t3: bad HMAC returned %s, expected 401" % status)
    status, _ = relay1.post("push", h.push_body("refs/heads/main"), sig="none")
    if status != 401:
        bad("t3: missing X-Hub-Signature-256 returned %s, expected 401" % status)

    # C01-fix/R3 selection matrix — wrong-secret, shape-violating and
    # cross-dialect deliveries all 401 BEFORE fan-out and before payload
    # parsing (stub1 must stay silent; checked once after the block):
    for sigv, why in (
        ("forgejo-bad", "wrong secret in X-Forgejo-Signature"),
        ("hub-bare", "bare hex in the hub header (prefix REQUIRED there)"),
        ("forgejo-prefixed", "sha256= in the forgejo header (must be bare there)"),
        ("mixed", "forged hub header + valid forgejo header (first-present = hub decides; NO cross-dialect fallback)"),
    ):
        status, _ = relay1.post("push", h.push_body("refs/heads/main"), sig=sigv)
        if status != 401:
            bad("t3: %s returned %s, expected 401 (R3 per-header verification over the raw body)" % (why, status))
    if records1:
        bad("t3: a rejected-signature delivery still reached fan-out (stub saw %r) — every R3 401 must short-circuit before any cluster call" % records1[:2])

    status, _ = relay1.post("ping", h.ping_body())
    if status != 200:
        bad("t3: signed ping returned %s, expected 200 no-op (GitHub Test button sanity)" % status)
    time.sleep(0.5)
    if records1:
        bad("t3: ping fired fan-out — stub saw %r (expected 200 no-op)" % records1)

    status, _ = relay1.post("push", h.push_body("refs/heads/feature-x"))
    if status != 200:
        bad("t3: push of refs/heads/feature-x (not in the allowed_refs list) returned %s, expected 200 no-op" % status)
    time.sleep(0.5)
    if records1:
        bad("t3: foreign-branch push fired fan-out — stub saw %r (OQ7: the config list decides whether the relay fires)" % records1)

    status, _ = relay1.post("push", h.push_body("refs/tags/base-1.0.203"))
    if status != 200:
        bad("t3: tag push returned %s, expected 200 no-op" % status)
    time.sleep(0.5)
    if records1:
        bad("t3: refs/tags/* fired fan-out — stub saw %r (C01: tags never fire)" % records1)

    status, _ = relay1.post("push", b'{"ref": "refs/heads/main", oops')
    if status != 400:
        bad("t3: valid-HMAC malformed JSON returned %s, expected 400 (C01 handler task)" % status)
    time.sleep(0.5)
    if records1:
        bad("t3: the 400 path fired fan-out — stub saw %r" % records1)
finally:
    if relay1:
        relay1.stop()
    stub1.stop()


def slow_relay(tag, allowed_refs):
    """Relay + list-stalling stub (3s) — proves 202 precedes fan-out completion."""
    records = []
    stub = h.StubArgo("dev", records, apps=[h.app("dev", h.REPO, "main", "OutOfSync")],
                      get_delay=3.0)
    stub.start()
    cfg, secrets = h.make_fixtures(os.path.join(work, "t3-" + tag),
                                   [{"name": "dev", "url": stub.url}],
                                   allowed_refs=allowed_refs)
    relay = h.Relay(main_py, cfg, secrets, os.path.join(work, "t3-%s.log" % tag))
    relay.start()
    return records, stub, relay


# widened list: refs/heads/main fires
records2, stub2, relay2 = slow_relay("main", WIDENED)
try:
    status, elapsed = relay2.post("push", h.push_body("refs/heads/main"))
    if status != 202:
        bad("t3: allowed push refs/heads/main returned %s, expected 202" % status)
    if elapsed >= 2.0:
        bad("t3: the 202 took %.2fs with the stub list stalling 3s — the handler awaited fan-out; GitHub's 10s budget requires answering 202 IMMEDIATELY" % elapsed)
    deadline = time.time() + 10
    while time.time() < deadline and not records2:
        time.sleep(0.1)
    if not records2:
        bad("t3: allowed push never fired fan-out — stub saw no API calls")
finally:
    relay2.stop()
    stub2.stop()

# widened list: the stage entry fires too (config-driven, not hardcoded main)
records3, stub3, relay3 = slow_relay("stage", WIDENED)
try:
    status, elapsed = relay3.post("push", h.push_body("refs/heads/stage"))
    if status != 202:
        bad("t3: allowed push refs/heads/stage returned %s, expected 202 — the widened fixture list proves the filter is config-driven (AC3/OQ7)" % status)
    if elapsed >= 2.0:
        bad("t3: the stage-push 202 took %.2fs — fan-out was awaited, not async" % elapsed)
    deadline = time.time() + 10
    while time.time() < deadline and not records3:
        time.sleep(0.1)
    if not records3:
        bad("t3: refs/heads/stage push fired no fan-out despite being in allowed_refs")
finally:
    relay3.stop()
    stub3.stop()


def default_relay(tag):
    records = []
    stub = h.StubArgo("dev", records, apps=[h.app("dev", h.REPO, "main", "OutOfSync")])
    stub.start()
    cfg, secrets = h.make_fixtures(os.path.join(work, "t3-" + tag),
                                   [{"name": "dev", "url": stub.url}],
                                   allowed_refs="UNSET")  # absent key -> default list
    relay = h.Relay(main_py, cfg, secrets, os.path.join(work, "t3-%s.log" % tag))
    relay.start()
    return records, stub, relay


# absent allowed_refs: stage must NOT fire
records4, stub4, relay4 = default_relay("nofile-stage")
try:
    status, _ = relay4.post("push", h.push_body("refs/heads/stage"))
    if status != 200:
        bad("t3: with allowed_refs absent, refs/heads/stage returned %s, expected 200 no-op (default is exactly [refs/heads/main])" % status)
    time.sleep(0.7)
    if records4:
        bad("t3: stage push fired fan-out under the default allowed_refs (stub saw %r) — default set must be [refs/heads/main]" % records4)
finally:
    relay4.stop()
    stub4.stop()

# absent allowed_refs: main must fire identically to the explicit list
records5, stub5, relay5 = default_relay("nofile-main")
try:
    status, _ = relay5.post("push", h.push_body("refs/heads/main"))
    if status != 202:
        bad("t3: with allowed_refs absent, refs/heads/main returned %s, expected 202 (default behaves identically, AC3)" % status)
    deadline = time.time() + 10
    while time.time() < deadline and not records5:
        time.sleep(0.1)
    if not records5:
        bad("t3: default-list main push fired no fan-out")
finally:
    relay5.stop()
    stub5.stop()


def fan_relay(tag, allowed_refs=None):
    """Relay + live-apps stub: for the R3 POSITIVE legs (a wrong-shape or
    wrong-dialect delivery must not just 401 here — an accept must fire)."""
    records = []
    stub = h.StubArgo("dev", records, apps=[h.app("dev", h.REPO, "main", "OutOfSync")])
    stub.start()
    cfg, secrets = h.make_fixtures(os.path.join(work, "t3-" + tag),
                                   [{"name": "dev", "url": stub.url}],
                                   allowed_refs=allowed_refs or WIDENED)
    relay = h.Relay(main_py, cfg, secrets, os.path.join(work, "t3-%s.log" % tag))
    relay.start()
    return records, stub, relay


# R3 positive: valid plain-hex forgejo delivery 202s and fans out — the
# shipped single-dialect relay 401s this, so the leg is designed-red until
# C01-fix lands (the rename reddens it too; the dialect is the point).
records6, stub6, relay6 = fan_relay("forgejo-accept")
try:
    status, _ = relay6.post("push", h.push_body("refs/heads/main"), sig="forgejo")
    if status != 202:
        bad("t3: valid X-Forgejo-Signature plain-hex delivery returned %s, expected 202 (R3: the main-sync job's dialect must verify)" % status)
    deadline = time.time() + 10
    while time.time() < deadline and not records6:
        time.sleep(0.1)
    if not records6:
        bad("t3: the accepted forgejo delivery fired no fan-out")
    res = relay6.wait_results(["dev"], timeout=15)
    if res.get("dev") != "ok":
        bad("t3: forgejo-dialect fan-out classified dev=%r, expected ok (AC1: 202 + real fan-out, not just the accept)" % (res,))
finally:
    relay6.stop()
    stub6.stop()

# R3 selection rule, positive side: valid hub header + forged forgejo
# header — first-present (hub) decides and the hub value verifies, so the
# delivery is ACCEPTED despite the bogus companion header.
records7, stub7, relay7 = fan_relay("mixed-good")
try:
    status, _ = relay7.post("push", h.push_body("refs/heads/main"), sig="mixed-good")
    if status != 202:
        bad("t3: valid hub + forged forgejo headers returned %s, expected 202 (first-present header wins: the hub dialect decides, a bad companion header is irrelevant)" % status)
finally:
    relay7.stop()
    stub7.stop()

# C04 contract end-to-end: the byte-for-byte delivery the main-sync
# hook-relay job sends (payload key set + header family pinned by
# tests/services/forgejo-main-sync.sh t11/t12) must be accepted and fan
# out. Offline proof that caller and relay agree BEFORE either is live.
records8, stub8, relay8 = fan_relay("forge-e2e")
try:
    run_tag = "91234-2"
    body = h.forge_push_body("refs/heads/main", "0" * 40, "1" * 40,
                             "OwnYourIO/SpencersLab")
    status, _ = relay8.post("push", body, sig="forgejo", headers_extra={
        "X-Forgejo-Event": "push",
        "X-Forgejo-Delivery": run_tag,
        "X-GitHub-Delivery": run_tag,
    })
    if status != 202:
        bad("t3: the C04 forge-delivery (exact key set + header family, plain-hex signature) returned %s, expected 202 — caller/relay contract drift would ship as every push silently 401-ing" % status)
    res = relay8.wait_results(["dev"], timeout=15)
    if res.get("dev") != "ok":
        bad("t3: the accepted C04 delivery classified dev=%r, expected ok (audit line required, not just the 202)" % (res,))
    if "push accepted" not in relay8.log():
        bad("t3: no `push accepted` audit line for the C04 delivery (the runbook §5 smoke greps exactly this token)")
finally:
    relay8.stop()
    stub8.stop()

print("ok: t3 — dual-dialect matrix (hub+forgejo valid 202-fires, forged/bare-in-hub/prefixed-in-forgejo/forged-hub-first 401s, none 401), C04 forge-delivery e2e 202+fanout+audit, ping 200, foreign-branch 200, tag 200, malformed JSON 400 (zero fan-out each), widened-list stage 202, absent-allowed_refs defaults to exactly [refs/heads/main] (AC1+AC2+AC3/OQ7)")
PY
  then
    ok "t3 passed (AC3)"
  else
    fail "t3: the handler behavior matrix is not satisfied (reason printed above)"
  fi
fi

# --- t4: fan-out ordering + tolerance matrix (AC4) ------------------------------
if want t4; then
  if python3 - "$MAIN" "$WORK" <<'PY'
import os, sys
from urllib import parse as urlparse

main_py, work = sys.argv[1:3]
sys.path.insert(0, work)
import harness as h


def bad(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)


# dev: 409 on the root sync; grow/gpu normal; gpu's LIST call 500s (dead target);
# proxy-local is local:true AND FIRST in the config list — the code must reorder.
records = []
stub_dev = h.StubArgo("dev", records,
                      apps=[h.app("dev", h.REPO, "main", "OutOfSync"),
                            h.app("dev-cache", h.REPO, "main", "OutOfSync")],
                      sync_codes={"dev": 409})
stub_gpu = h.StubArgo("gpu", records, apps=[h.app("gpu", h.REPO, "main", "OutOfSync")],
                      get_code=500)
stub_grow = h.StubArgo("grow", records, apps=[h.app("grow", h.REPO, "main", "OutOfSync")])
stub_pl = h.StubArgo("proxy-local", records,
                     apps=[h.app("proxy-local", h.REPO, "main", "OutOfSync")])
relays = []
try:
    for s in (stub_dev, stub_gpu, stub_grow, stub_pl):
        s.start()
    cfg, secrets = h.make_fixtures(
        os.path.join(work, "t4"),
        [{"name": "proxy-local", "url": stub_pl.url, "local": True},
         {"name": "dev", "url": stub_dev.url},
         {"name": "gpu", "url": stub_gpu.url},
         {"name": "grow", "url": stub_grow.url}],
        allowed_refs=["refs/heads/main"])
    relay = h.Relay(main_py, cfg, secrets, os.path.join(work, "t4.log"),
                    env={"SETTLE_SECONDS": "0"})
    relays.append(relay)
    relay.start()
    status, _ = relay.post("push", h.push_body("refs/heads/main"))
    if status != 202:
        bad("t4: allowed push returned %s, expected 202" % status)

    res = relay.wait_results(["dev", "gpu", "grow", "proxy-local"], timeout=30)
    expected = {"dev": "ok", "gpu": "failed", "grow": "ok", "proxy-local": "ok"}
    missing = [n for n in expected if n not in res]
    if missing:
        bad("t4: audit lines never landed for %s (seen: %s)\nlog:\n%s" % (missing, res, relay.log()[:800]))
    if res != expected:
        bad("t4: per-target classification %s != expected %s (409 must count ok, the 500-list target failed)" % (res, expected))

    if not relay.alive():
        bad("t4: relay died during fan-out — one target's failure must not take the process down")

    pl_first = min(r["seq"] for r in stub_pl.calls(records))
    remotes_last = max(r["seq"] for s in (stub_dev, stub_gpu, stub_grow) for r in s.calls(records))
    if pl_first < remotes_last:
        bad("t4: local:true target was attempted before remote fan-out finished (proxy-local call seq %d < last remote seq %d) — self-sync can restart the relay, so the hub entry goes LAST" % (pl_first, remotes_last))

    dev_syncs = stub_dev.syncs(records)
    root_sync = [r for r in dev_syncs if r["app"] == "dev"]
    child_sync = [r for r in dev_syncs if r["app"] == "dev-cache"]
    if not root_sync or not child_sync:
        bad("t4: root-409 aborted the target or the child pass never ran (dev syncs: %s) — 409 is success and fan-out continues to children" % [r["app"] for r in dev_syncs])
    if root_sync[0]["seq"] > child_sync[0]["seq"]:
        bad("t4: dev-cache synced before the dev root — root-first-per-cluster is required")
    if not stub_grow.syncs(records) or not stub_pl.syncs(records):
        bad("t4: the gpu list failure aborted the rest of the fan-out (grow/proxy-local syncs missing) — per-target try/except is required")

    all_syncs = stub_dev.syncs(records) + stub_grow.syncs(records) + stub_pl.syncs(records)
    for rec in all_syncs:
        q = urlparse.parse_qs(urlparse.urlparse(rec["path"]).query)
        if q.get("prune") != ["false"]:
            bad("t4: sync %s carries query %s — the chunk's literal contract is POST .../sync?prune=false (query form)" % (rec["app"], dict(q)))
        if "force" in q:
            bad("t4: sync %s carries a force query flag (OQ6 ruling: NEVER force)" % rec["app"])
        if isinstance(rec["body"], dict) and (rec["body"].get("force") or (rec["body"].get("syncOptions") or {}).get("force")):
            bad("t4: sync %s body requests a force (OQ6 ruling: NEVER force)" % rec["app"])
    for stub in (stub_dev, stub_gpu, stub_grow, stub_pl):
        for rec in stub.calls(records):
            want_auth = "Bearer " + h.token_for(stub.name).decode()
            if rec["auth"] != want_auth:
                bad("t4: %s %s carried auth %r, expected the per-target mcp-bot bearer from --secrets-dir/<tokenKey>" % (stub.name, rec["path"], rec["auth"]))
finally:
    for r in relays:
        r.stop()
    for s in (stub_dev, stub_gpu, stub_grow, stub_pl):
        s.stop()

# timeout leg: dev's list stalls 20s; TARGET_TIMEOUT_SECONDS=1 must release the
# run — grow's audit line inside 8s and dev classified failed prove the knob is
# honored; an implementation without a timeout would land dev's line at ~20s.
records2 = []
stub_slow = h.StubArgo("dev", records2, apps=[h.app("dev", h.REPO, "main", "OutOfSync")],
                       get_delay=20.0)
stub_ok = h.StubArgo("grow", records2, apps=[h.app("grow", h.REPO, "main", "OutOfSync")])
try:
    stub_slow.start()
    stub_ok.start()
    cfg2, secrets2 = h.make_fixtures(
        os.path.join(work, "t4-timeout"),
        [{"name": "dev", "url": stub_slow.url},
         {"name": "grow", "url": stub_ok.url}],
        allowed_refs=["refs/heads/main"])
    relay2 = h.Relay(main_py, cfg2, secrets2, os.path.join(work, "t4-timeout.log"),
                     env={"SETTLE_SECONDS": "0", "TARGET_TIMEOUT_SECONDS": "1"})
    relay2.start()
    try:
        relay2.post("push", h.push_body("refs/heads/main"))
        res2 = relay2.wait_results(["dev", "grow"], timeout=8)
        if res2.get("grow") is None or res2.get("dev") is None:
            bad("t4: with TARGET_TIMEOUT_SECONDS=1 the fan-out had not classified both targets within 8s (seen %r) — a stalled 20s list call means the per-target timeout knob is not honored" % (res2,))
        if res2["dev"] != "failed":
            bad("t4: the timed-out dev target was classified %r, expected failed" % res2["dev"])
        if not stub_ok.syncs(records2):
            bad("t4: the healthy grow target never synced while dev timed out — timeout must isolate, not abort the run")
    finally:
        relay2.stop()
finally:
    stub_slow.stop()
    stub_ok.stop()

print("ok: t4 — root-first + local-last ordering, 409-tolerance (target continues to children, classified ok), dead-target isolation, query prune=false with no force anywhere, per-target bearer auth, TARGET_TIMEOUT_SECONDS honored (AC4/OQ6)")
PY
  then
    ok "t4 passed (AC4)"
  else
    fail "t4: the fan-out ordering/tolerance matrix is not satisfied (reason printed above)"
  fi
fi

# --- t5: spec-match filter on the fired ref (AC5) --------------------------------
if want t5; then
  if python3 - "$MAIN" "$WORK" <<'PY'
import os, sys

main_py, work = sys.argv[1:3]
sys.path.insert(0, work)
import harness as h


def bad(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)


def run(tag, ref):
    records = []
    apps_infra = [
        h.app("infra", h.REPO, "main", "OutOfSync"),          # eligible root for main
        h.app("infra-stage", h.REPO, "stage", "OutOfSync"),   # matches only a stage fire
        h.app("infra-synced", h.REPO, "main", "Synced"),      # matches but never syncs
        h.app("infra-other", h.OTHER_REPO, "main", "OutOfSync"),  # wrong repo
        h.app("infra-semver", h.REPO, "1.0.198", "OutOfSync"),    # helm-version revision
    ]
    apps_gpu = [
        h.app("gpu", h.REPO, "stage", "OutOfSync"),           # root tracks stage only
        h.app("gpu-child", h.REPO, "main", "OutOfSync"),      # eligible child, no eligible root
    ]
    stub_infra = h.StubArgo("infra", records, apps=apps_infra)
    stub_gpu = h.StubArgo("gpu", records, apps=apps_gpu)
    stub_infra.start()
    stub_gpu.start()
    cfg, secrets = h.make_fixtures(
        os.path.join(work, "t5-" + tag),
        [{"name": "infra", "url": stub_infra.url},
         {"name": "gpu", "url": stub_gpu.url}],
        allowed_refs=["refs/heads/main", "refs/heads/stage"])
    relay = h.Relay(main_py, cfg, secrets, os.path.join(work, "t5-%s.log" % tag),
                    env={"SETTLE_SECONDS": "0"})
    relay.start()
    try:
        status, _ = relay.post("push", h.push_body(ref))
        if status != 202:
            bad("t5[%s]: push %s returned %s, expected 202" % (tag, ref, status))
        res = relay.wait_results(["infra", "gpu"], timeout=30)
        return records, res, relay
    finally:
        relay.stop()
        stub_infra.stop()
        stub_gpu.stop()


# fired refs/heads/main: ONLY the eligible OutOfSync root of infra syncs; the gpu
# target has no eligible root (its root tracks stage) -> skipped, others proceed
records_a, res_a, _ = run("main", "refs/heads/main")
if res_a != {"infra": "ok", "gpu": "skipped"}:
    bad("t5[main]: classifications %r, expected {'infra': 'ok', 'gpu': 'skipped'} (ineligible root skips its target with a log line; the other target still fans out)" % (res_a,))

synced_a = sorted({(r["stub"], r["app"]) for r in records_a if r["kind"] == "sync"})
if synced_a != [("infra", "infra")]:
    bad("t5[main]: sync set %r, expected exactly [('infra', 'infra')] — stage-revision, Synced, other-repo and semver-revision apps must stay untouched (targetRevision == fired-ref-tail ∧ repoURL == target.repo)" % (synced_a,))

infra_lists_a = [r for r in records_a if r["stub"] == "infra" and r["kind"] == "list"]
if len(infra_lists_a) < 2:
    bad("t5[main]: infra was listed %d times, expected >=2 (eligibility pre-list + the post-settle re-GET the fan-out spec mandates)" % len(infra_lists_a))
root_sync_a = next(r for r in records_a if r["kind"] == "sync")
if infra_lists_a[1]["seq"] < root_sync_a["seq"]:
    bad("t5[main]: the second infra list predates the root sync — children sync off the post-settle re-GET, not the pre-sync snapshot")

gpu_calls_a = [r for r in records_a if r["stub"] == "gpu"]
gpu_syncs_a = [r for r in gpu_calls_a if r["kind"] == "sync"]
if gpu_syncs_a:
    bad("t5[main]: the ineligible-root gpu target was still synced (%s) — no eligible root means NO syncs for that target" % gpu_syncs_a)
if not [r for r in gpu_calls_a if r["kind"] == "list"]:
    bad("t5[main]: gpu was never listed — eligibility is answered by the list call itself")

# fired refs/heads/stage (the OQ7 widening, end to end): ONLY the stage-tracking
# root syncs; the prod-tracking infra target is skipped — a widened stage ref can
# never sync-fire prod clusters
records_b, res_b, _ = run("stage", "refs/heads/stage")
if res_b != {"infra": "skipped", "gpu": "ok"}:
    bad("t5[stage]: classifications %r, expected {'infra': 'skipped', 'gpu': 'ok'}" % (res_b,))
synced_b = sorted({(r["stub"], r["app"]) for r in records_b if r["kind"] == "sync"})
if synced_b != [("gpu", "gpu")]:
    bad("t5[stage]: sync set %r, expected exactly [('gpu', 'gpu')]" % (synced_b,))

print("ok: t5 — per fired ref only repoURL==target.repo ∧ targetRevision==ref-tail ∧ OutOfSync apps sync, root-before-children on the post-settle re-GET, ineligible-root target skipped with its log line while others fan out, stage widening never fires prod roots (AC5/OQ7)")
PY
  then
    ok "t5 passed (AC5)"
  else
    fail "t5: the spec-match fan-out filter is not satisfied (reason printed above)"
  fi
fi

# --- t6: diff scope (AC7) ---------------------------------------------------------
if want t6; then
  git rev-parse --verify --quiet "$BASE" >/dev/null ||
    fail "t6: CHUNK_BASE '$BASE' does not resolve (review passes the pre-chunk commit; default HEAD)"
  { git diff --name-only "$BASE" 2>/dev/null || true; git ls-files --others --exclude-standard; } |
    sort -u > "$WORK/changed.txt"
  # Allow-list: the three C01-fix files, this ticket's own test surface
  # (authored by the test stage — coord may or may not have committed it
  # yet; that includes the C04 harness extension, which is test work that
  # coexists in the working set from this wave), C04's committed workflow
  # file (a sibling chunk landing ahead of a relay re-run must not read as
  # a scope violation — same admission argocd-hook-wiring.sh t5 already
  # carries), and plan/pipeline machinery. Everything else in the working
  # set is an AC7 violation.
  if grep -Ev '^(containers/argocd-hook/|tests/[^/]+/argocd-hook-|tests/services/forgejo-main-sync\.sh$|\.forgejo/workflows/main-sync\.yaml$|\.agents/|\.pipeline/)' "$WORK/changed.txt" | grep -q .; then
    offenders=$(grep -Ev '^(containers/argocd-hook/|tests/[^/]+/argocd-hook-|tests/services/forgejo-main-sync\.sh$|\.forgejo/workflows/main-sync\.yaml$|\.agents/|\.pipeline/)' "$WORK/changed.txt" | head -20)
    fail "t6: files outside the C01-fix scope changed (AC7 — chart work belongs to C02-fix, workflow work to C04): $offenders"
  fi
  if git diff "$BASE" 2>/dev/null | grep -qE '^diff --git a/(charts/base/|services/[^/]+/templates/appset\.yaml)'; then
    fail "t6: the diff carries hunks under charts/base/ or a services appset template (AC7 — the kill-switch/gate files are off-limits, OQ1 ruling)"
  fi
  ok "t6: working set stays inside the C01 file scope; no charts/base or appset-template hunks (AC7)"
fi

# --- t7: README/R3/R4 contract parity ------------------------------------------------
if want t7; then
  [ -f "$README" ] || fail "t7: $README missing — the chart (C02) and the runbook (C03) reference it as the shipped contract"
  # The C01 key filename, built so this harness itself never carries the
  # old literal (t7's own grep gate below proves that).
  old_fn='github-''webhook'
  for tok in 'targets.json' 'allowed_refs' '--secrets-dir' '--check' '/health'; do
    grep -qF -- "$tok" "$README" ||
      fail "t7: README does not document the interface token '$tok' (C01: the README is the config contract downstream consumers pin)"
  done
  # R3: both dialect headers named; R4: hook-secret is the only flat key
  # filename; the caller framing names main-sync and the no-webhook door.
  for tok in 'X-Hub-Signature-256' 'X-Forgejo-Signature' 'hook-secret' 'main-sync'; do
    grep -qF -- "$tok" "$README" ||
      fail "t7: README lacks '$tok' (C01-fix README task: dual dialect line, hook-secret, caller = main-sync hook-relay job)"
  done
  grep -qF 'no webhook created' "$README" ||
    fail "t7: README must state the GitHub-shaped edge is a door with no webhook created (R2 framing; the runbook parity sweep greps the same sentence)"
  if grep -qF "$old_fn" "$README"; then
    fail "t7: README still references the retired '$old_fn' key filename (R4 rename ripple)"
  fi
  # main.py + --help must follow the rename (the constant AND its help text;
  # --check already proves behavior in t2):
  grep -qF 'hook-secret' "$MAIN" ||
    fail "t7: main.py does not read the key under hook-secret (C01-fix constant rename)"
  if grep -qF "$old_fn" "$MAIN"; then
    fail "t7: main.py still carries the '$old_fn' filename string (C01-fix AC4: zero hits in containers/)"
  fi
  help_text=$(python3 "$MAIN" --help 2>&1 || true)
  printf '%s' "$help_text" | grep -qF 'hook-secret' ||
    fail "t7: --help does not document the hook-secret HMAC key file (C01-fix: '--secrets-dir help text follows')"
  # containers/ tree-wide: AC4's grep-0, and BOTH header tokens in main.py
  # (the dialect switch must be readable in the code, not only the docs).
  if grep -rqF "$old_fn" "$RELAY_DIR"; then
    fail "t7: '$old_fn' survives somewhere under $RELAY_DIR (C01-fix AC4: 0 hits in containers/ after the rename)"
  fi
  for tok in 'X-Hub-Signature-256' 'X-Forgejo-Signature'; do
    grep -qF -- "$tok" "$MAIN" ||
      fail "t7: main.py never names the '$tok' header (R3: both dialect headers are the handler's selection rule, greppable in code)"
  done
  # Harness self-gate: no residual old filename anywhere in this file.
  if grep -qF "$old_fn" "tests/containers/argocd-hook-relay.sh"; then
    fail "t7: the harness itself still carries the '$old_fn' filename (C01-fix secret-hygiene leg: renamed, not merely re-pointed)"
  fi
  ok "t7: README carries the config contract + both dialect headers + hook-secret + main-sync door framing; main.py/--help renamed with zero '$old_fn' hits in $RELAY_DIR and in this harness (C01-fix AC4+AC6)"
fi

rm -rf "$WORK"
printf 'PASS: argocd-hook-relay contract checks (%d ok)\n' "$checks"
