#!/usr/bin/env bash
# Fan-out engine behavior contract (2026/2026-11-cf-139-feat-argocd-webhook-sync, C05):
# scripts/argocd-fanout.py + scripts/argocd-fanout.json — the vault-direct
# fan-out logic home (ruling R6), stdlib-only, ported 1:1 from the shipped
# relay's main.py semantics (root-first -> settle -> children sweep, live
# targetRevision + byte repoURL match, prune=false in query AND body,
# 409-as-success, per-target isolation) with the new vault-parsing +
# ThreadPoolExecutor(4) layer and the ruled exit posture (DECISIONS
# 2026-11-23): 0 runtime-green (failures audit, self-heal next push),
# 1 config/setup-red (the typo'd-category silent-no-op class must not ride
# the warn-and-green lane), 2 argparse usage.
#
# Contract source: chunks/C05.md "## Tests" + plan "Fan-out contract" (the
# pinned interface every later chunk consumes). AC trace:
# t1[AC1] t2[AC11] t3[AC3 + vault parser matrix incl. OQ8 newline form and
# the tolerant paste-accident defense] t4[AC4 + AC8 shared no-echo grep]
# t5[AC5 + ThreadPool(4) no-post-settle-race + OQ8 live comma rerun]
# t6[AC5 prune pinning] t7[AC5 409-as-success-continues] t8[AC6 isolation
# incl. the RULED OQ9 warn-and-skip honest-failed posture] t9[AC7 ref gate]
# t10[AC9 dry-run GET-only] t11[AC10 all-skipped warning] t12[AC8 secret
# hygiene sweep + no-positional/unknown-flag usage posture].
# Review round 1 (CHANGES_REQUESTED) arms, folded into those legs —
# t4: M1 reversed `token:cat` record (pinned reversed-message + LEAK grep:
# the token value must be ABSENT) and the cat[:64] echo bound; m2 empty
# allowed_refs; m3 unknown top-level roster keys named; nits finiteness
# (Infinity/NaN without importing math) and whole-number workers.
# t8: M2 redirect containment on BOTH legs (list 302 / sync 301) against a
# separate-origin target stub whose access log witnesses bearer egress, and
# a 3xx page that can never earn result=ok. t11: m1 column-0 anchored,
# exactly-one ::warning:: on a two-target all-skipped run.
#
# OQ8 ruled 2026-11-23: newline `cat:token` records are the vault form; the
# [,\s]+ split is paste-accident defense, so comma/space/mixed/CRLF inputs
# must still parse — this suite proves both halves.
#
# Offline-deterministic: the fake ArgoCD API is threaded loopback
# http.server stubs (the shipped relay-suite stub pattern, re-armed for
# the script's REST-client side); scratch under
# /tmp/opencode per the repo's script.sh precedent. Every fixture token is
# JWT-shaped and carries the SENT23 stem so t12's zero-echo sweep is one
# grep over every captured leg log + the argv ledger.
#
# Run from the repo root:
#   bash tests/argocd-fanout/behavior.sh            # t1..t12
#   bash tests/argocd-fanout/behavior.sh t4 t8      # subset
# Env: FANOUT_SCRIPT / FANOUT_ROSTER point the suite at script/roster
#      copies (green-shape proofs, mutation legs).
#
# Red posture (C05 "Red posture"): t1 fail-fasts naming the absent script
# until C05 lands; the roster pins (t2) are red until the JSON lands.
#
# HARNESS-PINNED SURFACE (authored before the implementation, same doctrine
# as the shipped relay suite — minimal observation contracts beyond the
# chunk's CLI list): 1. --dry-run prints one per-target line carrying
# `target=<name>` (the audit grammar extended to the dry mode — the only
# greppable channel for AC9's eligibility lines). 2. Config-error lines land
# on stderr (AC4 says "stderr line prefixed"). 3. The ref-gate line names the
# rejected ref (AC7's "one log line" must be attributable to the gate).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

FANOUT="${FANOUT_SCRIPT:-scripts/argocd-fanout.py}"
ROSTER="${FANOUT_ROSTER:-scripts/argocd-fanout.json}"

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
  for i in $(seq 1 12); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t([1-9]|1[0-2])$ ]] || fail "unknown test id '$a' (expected t1..t12)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

command -v python3 >/dev/null 2>&1 || fail "python3 missing — the fan-out is stdlib-only by design and the harness needs it"

WORK=$(mktemp -d /tmp/opencode/argocd-fanout-behavior.XXXXXX)
OUT="$WORK/out"
mkdir -p "$OUT"
# py_compile writes __pycache__ next to the source; keep it out of the repo
# so disposal sweeps never see test-session noise.
export PYTHONPYCACHEPREFIX="$WORK/pycache"
export BEH_FANOUT="$FANOUT" BEH_ROSTER="$ROSTER" BEH_OUT="$OUT"

# --- t1: files, stdlib-only import set, docker-free (AC1) ----------------------
if want t1; then
  [ -f "$FANOUT" ] ||
    fail "t1: $FANOUT does not exist — C05 (the fan-out engine) is not implemented (red posture: this fail-fast names the absent script)"
  [ -f "$ROSTER" ] ||
    fail "t1: $ROSTER does not exist — C05 ships the roster beside the script"
  python3 -m py_compile "$FANOUT" || fail "t1: py_compile failed on $FANOUT"
  if ! python3 - "$FANOUT" <<'PY'
import re, sys

src = open(sys.argv[1]).read()
# The C05 import budget is main.py's set minus the http/hmac server side
# (plan: json/urllib/re/threading/concurrent.futures; pyyaml is NOT
# guaranteed on the job image, requests would break stdlib-only).
ALLOWED = {'argparse', 'concurrent', 'dataclasses', 'json', 'os', 're', 'sys',
           'threading', 'time', 'urllib'}
mods = set()
for m in re.finditer(r'(?m)^(?:import|from)\s+([A-Za-z_][A-Za-z0-9_]*)', src):
    mods.add(m.group(1))
extra = sorted(mods - ALLOWED)
if extra:
    print('FAIL: t1: non-stdlib/outside-budget imports: %s (allowed: %s)'
          % (', '.join(extra), ', '.join(sorted(ALLOWED))), file=sys.stderr)
    sys.exit(1)
for banned in ('yaml', 'requests'):
    if re.search(r'(?m)^(?:import|from)\s+%s\b' % banned, src):
        print('FAIL: t1: imports %s — the job image does not guarantee it (plan Context: stdlib-only)' % banned, file=sys.stderr)
        sys.exit(1)
# A pure REST client: no child processes, no docker, no server side.
for word in ('subprocess', 'docker'):
    if word in src:
        print('FAIL: t1: %r appears in the script — the fan-out spawns nothing (docker-free by ruling; the runner already carries python3)' % word, file=sys.stderr)
        sys.exit(1)
print('ok: t1')
PY
  then
    fail "t1: the script shape contract is violated (reason printed above)"
  fi
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$ROSTER" \
    || fail "t1: $ROSTER is not valid JSON"
  ok "t1: script+roster exist; py_compile clean; import set stdlib-only and inside the C05 budget; no subprocess/docker server-side surface (AC1)"
fi

# --- shared harness for t3..t12 -------------------------------------------------
if want t3 || want t4 || want t5 || want t6 || want t7 || want t8 \
   || want t9 || want t10 || want t11 || want t12; then
  cat > "$WORK/harness.py" <<'HARNESS'
"""Stub ArgoCD API + fan-out subprocess driver for the cf-139 C05 contract.

One records list per stub with seq + wall-clock stamps: per-target request
ORDER (root sync before the post-settle list before child syncs) is the
threading guarantee under ThreadPoolExecutor(4) — global audit-line order is
deliberately NOT asserted (C05 notes: results print as they finish).
"""
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

REPO = "https://github.com/OwnYourIO/SpencersLab.git"
OTHER_REPO = "https://github.com/OwnYourIO/OtherThings.git"
CATS = ["dev", "gpu", "gpu-ai", "grow", "home", "infra", "media",
        "monitoring", "proxy-local", "proxy-backup", "proxy-remote"]
STEM = "SENT23"  # the one-needle token-echo marker
SEG1 = "eyJhbGciOiJIUzI1NiJ9"
SEG2 = "eyJzdWIiOiJtY3AtYm90In0"
REC_LOCK = threading.Lock()


def token_for(cat):
    # JWT-shaped per the pinned regex, per-category distinctive so an echo
    # can be attributed; every token carries STEM for the sweep grep.
    slug = cat.replace("-", "")
    return "%s.%s.%s%sxKq" % (SEG1, SEG2, slug, STEM)


def vault(cats, delim="\n"):
    return delim.join("%s:%s" % (c, token_for(c)) for c in cats)


def record(records, rec):
    with REC_LOCK:
        records.append(dict(rec, seq=len(records), ts=time.time()))


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def app(name, repo, rev, status, multi=False):
    if multi:
        spec = {"sources": [{"repoURL": repo, "targetRevision": rev, "path": "x"},
                            {"repoURL": "https://chart.example/repo", "targetRevision": rev, "path": "y"}]}
    else:
        spec = {"source": {"repoURL": repo, "targetRevision": rev, "path": "y"}}
    return {"metadata": {"name": name, "namespace": "default"},
            "spec": spec, "status": {"sync": {"status": status}}}


class StubArgo:
    """Stand-in for one cluster's ArgoCD API server.

    apps       — GET /api/v1/applications items (re-read per call)
    sync_codes — per-app POST sync code override (409 = in-progress arm)
    get_code   — non-200 kills the whole list call (401 dead-auth arm)
    get_delay  — stall the list call (timeout arm)
    get_raw    — respond 200 with non-JSON (garbage arm)
    get_redirect/post_redirect/redirect_to — 3xx door arms (review M2):
                 the redirect TARGET stub records separately, so bearer
                 egress off the rostered origin is observable, not inferred.
    """

    def __init__(self, name, records, apps=None, sync_codes=None,
                 get_code=200, get_delay=0.0, get_raw=None,
                 get_redirect=None, post_redirect=None, redirect_to=None):
        self.name = name
        self.records = records
        self.apps = apps or []
        self.sync_codes = sync_codes or {}
        self.get_code = get_code
        self.get_delay = get_delay
        self.get_raw = get_raw
        self.get_redirect = get_redirect
        self.post_redirect = post_redirect
        self.redirect_to = redirect_to
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def _send(self, code, body, ctype="application/json"):
                payload = body if isinstance(body, bytes) else json.dumps(body).encode()
                self.send_response(code)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def _redirect(self, code):
                body = b"moved"
                self.send_response(code)
                self.send_header("Location", outer.redirect_to or "/")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                path = self.path.split("?", 1)[0].rstrip("/")
                rec = {"stub": outer.name, "method": "GET", "path": self.path,
                       "auth": self.headers.get("Authorization")}
                if path.endswith("/api/v1/applications"):
                    record(outer.records, dict(rec, kind="list"))
                    if outer.get_redirect:
                        self._redirect(outer.get_redirect)
                    elif outer.get_delay:
                        time.sleep(outer.get_delay)
                        if outer.get_raw is not None:
                            self._send(200, outer.get_raw.encode(), "application/json")
                        else:
                            self._send(outer.get_code, {"items": list(outer.apps)}
                                       if outer.get_code == 200 else
                                       {"error": {"message": "mock list failure"}})
                    elif outer.get_raw is not None:
                        self._send(200, outer.get_raw.encode(), "application/json")
                    elif outer.get_code != 200:
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
                    parsed = {"_unparseable": raw.decode(errors="replace")}
                path = self.path.split("?", 1)[0].rstrip("/")
                rec = {"stub": outer.name, "method": "POST", "path": self.path,
                       "auth": self.headers.get("Authorization"), "body": parsed,
                       "raw_body": raw.decode(errors="replace")}
                if path.endswith("/sync"):
                    name = path.split("/")[-2]
                    record(outer.records, dict(rec, kind="sync", app=name))
                    if outer.post_redirect:
                        self._redirect(outer.post_redirect)
                        return
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

    def calls(self):
        return [r for r in self.records if r["stub"] == self.name]

    def lists(self):
        return [r for r in self.calls() if r["kind"] == "list"]

    def syncs(self):
        return [r for r in self.calls() if r["kind"] == "sync"]


FANOUT = os.environ["BEH_FANOUT"]
ROSTER = os.environ["BEH_ROSTER"]
OUT = os.environ["BEH_OUT"]


def make_roster(dirpath, targets, **overrides):
    """Fixture roster in the SHIPPED schema (name/url/root_app, no relay-era
    tokenKey/local/repo keys). targets: list of {name,url,root_app}."""
    os.makedirs(dirpath, exist_ok=True)
    cfg = {"allowed_refs": ["refs/heads/main"],
           "tracked_repo": REPO,
           "settle_seconds": 0.2,
           "target_timeout_seconds": 5.0,
           "parallel_workers": 4,
           "targets": [{"name": t["name"], "url": t["url"],
                        "root_app": t.get("root_app", t["name"])} for t in targets]}
    cfg.update(overrides)
    path = os.path.join(dirpath, "roster.json")
    with open(path, "w") as f:
        json.dump(cfg, f)
    return path


def run(name, *args, vault_value=None, unset=False, config=None, timeout=40):
    """Invoke the real script as a subprocess; capture combined output to
    $OUT/<name>.log and the argv to $OUT/argv.log (t12 sweeps both).
    unset=True runs with ARGOCD_SYNC_TOKENS removed from the environment;
    vault_value=None without unset simply means "no vault given"."""
    cmd = [sys.executable, "-u", FANOUT, "--config", config or "UNSET", *args]
    if config is None:
        cmd.remove("UNSET")
        cmd.remove("--config")
    env = dict(os.environ)
    if unset or vault_value is None:
        env.pop("ARGOCD_SYNC_TOKENS", None)
    else:
        env["ARGOCD_SYNC_TOKENS"] = vault_value
    argv_line = "%s\t%s" % (name, "\x1f".join(cmd))
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, env=env)
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate()
        stdout += "\n<HARNESS TIMEOUT after %ss>" % timeout
    with open(os.path.join(OUT, "%s.log" % name), "w") as f:
        f.write(stdout)
        f.write(stderr)
    with open(os.path.join(OUT, "argv.log"), "a") as f:
        f.write(argv_line + "\n")
    return proc.returncode, stdout, stderr


AUDIT_RE = re.compile(
    r"target=(?P<name>[A-Za-z0-9_.-]+) result=(?P<result>ok|skipped|failed) "
    r"root=(?P<root>\S+) ref=(?P<ref>\S+) elapsed=(?P<elapsed>\d+\.\d)s detail=(?P<detail>.*)$")


def audits(text):
    out = []
    for ln in text.splitlines():
        m = AUDIT_RE.search(ln)
        if m:
            out.append(m.groupdict())
    return out


def summary(text):
    m = re.search(r"fan-out summary: targets=(\d+) ok=(\d+) skipped=(\d+) failed=(\d+)", text)
    return m.groups() if m else None


def bad(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)
HARNESS
fi

# --- t2: roster byte-pins against [P2 §1] (AC11) --------------------------------
if want t2; then
  [ -f "$ROSTER" ] || fail "t2: $ROSTER missing — the roster pins (route-truth doctrine) cannot run until C05 lands the JSON"
  if ! python3 - "$ROSTER" <<'PY'
import json, re, sys

roster = json.load(open(sys.argv[1]))

# The [P2 RESEARCH §1] measured table, verbatim: 10 TLS-verified hosts + the
# two sanctioned exceptions (dev, home). The route-truth leg exists because
# the derived-form + exception indirection produced reopen1's two wrong
# hosts — a re-derived URL must redden HERE, not a live cluster.
P2 = {
    "dev": "https://cluster.dev.scifi.farm",
    "home": "https://cluster.home-lab.spencerslab.com",
    "gpu": "https://cluster.gpu.spencerslab.com",
    "gpu-ai": "https://cluster.gpu-ai.spencerslab.com",
    "grow": "https://cluster.grow.spencerslab.com",
    "infra": "https://cluster.infra.spencerslab.com",
    "media": "https://cluster.media.spencerslab.com",
    "monitoring": "https://cluster.monitoring.spencerslab.com",
    "proxy-local": "https://cluster.proxy-local.spencerslab.com",
    "proxy-backup": "https://cluster.proxy-backup.spencerslab.com",
    "proxy-remote": "https://cluster.proxy-remote.spencerslab.com",
}


def bad(msg):
    print("FAIL: t2: %s" % msg, file=sys.stderr)
    sys.exit(1)


if set(roster) != {"allowed_refs", "tracked_repo", "settle_seconds",
                   "target_timeout_seconds", "parallel_workers", "targets"}:
    bad("top-level keys are %s, expected exactly the six pinned by the plan roster schema" % sorted(roster))
if roster["allowed_refs"] != ["refs/heads/main"]:
    bad("allowed_refs is %r, expected exactly [\"refs/heads/main\"]" % roster["allowed_refs"])
# R1(c): the fleet's live app sources read GitHub; flip ONLY in lockstep
# with the cluster annotations ([P §3] — the skipped-x11 trap).
if roster["tracked_repo"] != "https://github.com/OwnYourIO/SpencersLab.git":
    bad("tracked_repo is %r, expected the GitHub byte-exact string" % roster["tracked_repo"])
if roster["settle_seconds"] != 10.0 or roster["target_timeout_seconds"] != 60.0:
    bad("tunables settle=%r timeout=%r, expected 10.0 / 60.0 (shipped values; the 20s tightening was rejected)")
if roster["parallel_workers"] != 4:
    bad("parallel_workers is %r, expected 4 (RESEARCH Implications 6)" % roster["parallel_workers"])

targets = roster["targets"]
if len(targets) != 11:
    bad("%d targets, expected the 11 roster categories (backups/personal have no root app and stay absent)" % len(targets))
names = [t.get("name") for t in targets]
if sorted(names) != sorted(P2):
    bad("target names %s != the 11 categories %s" % (sorted(names), sorted(P2)))
for t in targets:
    if set(t) != {"name", "url", "root_app"}:
        bad("target %r carries keys %s, expected exactly {name,url,root_app} (relay-era tokenKey/local/repo keys must not survive the port)" % (t.get("name"), sorted(t)))
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", str(t.get("name"))):
        bad("target name %r violates the audit-line charset [A-Za-z0-9_.-]+" % t.get("name"))
    if t.get("root_app") != t.get("name"):
        bad("target %r root_app is %r, expected the category name" % (t.get("name"), t.get("root_app")))
    if t.get("url") != P2[t["name"]]:
        bad("target %r url is %r, expected the [P2 §1] literal %r (route truth: measured, never guessed)" % (t["name"], t.get("url"), P2[t["name"]]))
print("ok: t2")
PY
  then
    fail "t2: the roster does not pin the [P2 §1] table / plan schema (reason printed above)"
  fi
  ok "t2: roster is exactly the 11 [P2]-byte-pinned targets + GitHub tracked_repo + shipped tunables, schema-clean (AC11)"
fi

# --- t3: --check offline contract + vault parser matrix (AC3 + OQ8) -------------
if want t3; then
  if ! python3 - "$WORK" <<'PY'
import os, re, sys

sys.path.insert(0, sys.argv[1])
import harness as h

# (a) 11-category fixture roster against a bound stub: --check must print the
# OK line, the category/URL table, the refs and tunables — and touch ZERO
# sockets (AC3: the server is bound but untouched).
recs = []
stub = h.StubArgo("all", recs)
stub.start()
try:
    roster = h.make_roster(os.path.join(sys.argv[1], "t3"),
                           [{"name": c, "url": stub.url} for c in h.CATS])
    rc, out, err = h.run("t3a", "--check", vault_value=h.vault(h.CATS), config=roster)
    blob = out + err
    if rc != 0:
        h.bad("t3: --check on the valid fixture exited %s\n%s" % (rc, blob[:600]))
    if "argocd-fanout --check: OK" not in blob:
        h.bad("t3: no `argocd-fanout --check: OK` line (AC3 pinned the exact success line):\n%s" % blob[:600])
    for c in h.CATS:
        if c not in blob:
            h.bad("t3: --check table has no row for category %r (AC3: 11-line category/URL table)" % c)
    if stub.url not in blob:
        h.bad("t3: --check table does not print the target URLs (AC3)")
    if "refs/heads/main" not in blob:
        h.bad("t3: --check never echoes allowed_refs (AC3)")
    if not (re.search(r"(?i)settle", blob) and re.search(r"(?i)timeout", blob) and "4" in blob):
        h.bad("t3: --check never echoes the tunables row (AC3: settle/timeout/workers are printed):\n%s" % blob[:600])
    if recs:
        h.bad("t3: --check opened sockets — %d stub requests landed (AC3: ZERO network; --check must never dial, --dry-run is the dialing mode)" % len(recs))
    if h.STEM in blob:
        h.bad("t3: --check output echoes vault token material (AC8)")

    # (b) the SHIPPED roster parses offline too (env FANOUT_ROSTER default),
    # proven against the same stub-free code path with a wall guard: a
    # --check that dials the 11 real hosts would hang or fail here.
    rc, out, err = h.run("t3b", "--check", vault_value=h.vault(h.CATS),
                         config=h.ROSTER, timeout=20)
    blob = out + err
    if rc != 0 or "argocd-fanout --check: OK" not in blob:
        h.bad("t3: --check on the shipped roster exited %s / no OK line (the shipped file must validate as-is):\n%s" % (rc, blob[:600]))
    for c in h.CATS:
        if c not in blob:
            h.bad("t3: shipped-roster --check table has no row for %r" % c)
    if not ("10" in blob and "60" in blob):
        h.bad("t3: shipped-roster --check does not print the shipped tunables 10/60 (AC3)")
    if h.STEM in blob:
        h.bad("t3: shipped-roster --check echoes token material (AC8)")

    # (c) parser matrix: OQ8 ruled newline records (the documented form,
    # per-line masking [26]); the [,\s]+ tolerance is paste-accident defense,
    # so comma / space / mixed+CRLF+edge-blank forms must ALL parse.
    for form, val in (
            ("comma", h.vault(h.CATS, delim=",")),
            ("space", h.vault(h.CATS, delim=" ")),
            ("mixed+CRLF+edges", "\r\n \r\n" + ",\t".join("%s:%s" % (c, h.token_for(c)) for c in h.CATS[:6])
             + "  \n  " + "\r\n".join("%s:%s" % (c, h.token_for(c)) for c in h.CATS[6:]) + "\n\n"),
            ("trailing-newline", h.vault(h.CATS) + "\n"),
    ):
        rc, out, err = h.run("t3c-%s" % form.replace("+", "_").replace(" ", ""),
                             "--check", vault_value=val, config=roster)
        blob = out + err
        if rc != 0 or "argocd-fanout --check: OK" not in blob:
            h.bad("t3: delimiter form %r must parse (paste-accident defense, plan vault parsing): rc=%s\n%s" % (form, rc, blob[:400]))
        if h.STEM in blob:
            h.bad("t3: %s-form --check echoes token material (AC8)" % form)
finally:
    stub.stop()

print("ok: t3 — --check exits 0 with the OK line, 11-row table, refs and tunables while the bound stub sees ZERO requests; the shipped roster validates offline within 20s; newline/comma/space/mixed-CRLF/edge-blank vault forms all parse; no token echo anywhere (AC3 + OQ8)")
PY
  then
    fail "t3: the --check offline contract is violated (reason printed above)"
  fi
  ok "t3: --check offline contract + vault parser matrix hold (AC3, OQ8)"
fi

# --- t4: config-error vocabulary, exit 1, loud, never echoing values (AC4/AC8) --
if want t4; then
  if ! python3 - "$WORK" <<'PY'
import json, os, re, sys

sys.path.insert(0, sys.argv[1])
import harness as h

recs = []
stub = h.StubArgo("probe", recs, apps=[h.app("dev", h.REPO, "main", "OutOfSync")])
stub.start()
try:
    good_roster = h.make_roster(os.path.join(sys.argv[1], "t4"), [
        {"name": "dev", "url": stub.url},
        {"name": "grow", "url": stub.url},
    ])
    good_vault = h.vault(["dev", "grow"])

    def load_roster(path):
        return json.load(open(path))

    def roster_copy(mutate, tag):
        cfg = load_roster(good_roster)
        mutate(cfg)
        path = os.path.join(sys.argv[1], "t4-%s.json" % tag)
        with open(path, "w") as f:
            json.dump(cfg, f)
        return path

    # (name, argv-extra, vault value or None+unset, expected stderr regex,
    # extra no-echo value). LIVE mode (no --check): the exact invocation the
    # C06 job runs — config errors must exit 1 there (the ruled red), and
    # they must be caught BEFORE any network (zero stub dials).
    # Review-round-1 arms added: M1 reversed `token:cat` paste (the first
    # field is JWT-shaped -> the reversed message, NEVER the value) and the
    # cat[:64] echo bound (probed separately below the loop); m2 empty
    # allowed_refs (a legal-but-silently-dead roster goes RED); m3 unknown
    # top-level keys (relay-era leftovers cannot linger green); the
    # nit-arms keep the finiteness/whole-number reds in the same family.
    arms = [
        ("unknown-category", good_vault + "\nnotacat:" + h.token_for("notacat"), None,
         r'argocd-fanout config: record for unknown category "notacat"'),
        ("reversed", h.token_for("dev") + ":dev", None,
         r'argocd-fanout config: vault record looks reversed \(token before category\)'),
        ("missing-token", h.vault(["dev"]), None,
         r'argocd-fanout config: roster target "grow" has no token'),
        ("non-jwt", "dev:%s\ngrow:plain-secret-not-a-jwt" % h.token_for("dev"), None,
         r'argocd-fanout config: token for "grow" is not JWT-shaped'),
        ("no-colon", good_vault + "\nbogusNOCOLONRECORD", None,
         r'argocd-fanout config:'),
        ("empty-env", "", None, r'argocd-fanout config:'),
        ("unset-env", None, True, r'argocd-fanout config:'),
        ("bad-json", good_vault, None, r'argocd-fanout config:'),          # config swapped below
        ("unreadable-file", good_vault, None, r'argocd-fanout config:'),   # config swapped below
        ("tags-ref", good_vault, None, r'argocd-fanout config:'),         # roster swapped
        ("short-ref", good_vault, None, r'argocd-fanout config:'),
        ("dup-name", good_vault, None, r'argocd-fanout config:'),
        ("bad-scheme", good_vault, None, r'argocd-fanout config:'),
        ("empty-refs", good_vault, None,
         r'argocd-fanout config:.*allowed_refs'),                          # m2: [] must go RED, not silently gate every push off
        ("extra-keys", good_vault, None,
         r'argocd-fanout config:.*clusterHosts'),                          # m3: unknown top-level key named in the message
        ("inf-settle", good_vault, None,
         r'argocd-fanout config:.*settle_seconds'),                        # nit: Infinity/NaN rejected without importing math
        ("nan-timeout", good_vault, None,
         r'argocd-fanout config:.*target_timeout_seconds'),
        ("frac-workers", good_vault, None,
         r'argocd-fanout config:.*parallel_workers'),                      # nit: 4.5 truncating silently is a config typo class
    ]

    def check(tag, rc, out, err, pat, no_echo=()):
        blob = out + err
        if rc != 1:
            h.bad("t4[%s]: exit %s, expected 1 — setup errors are the ruled RED lane (DECISIONS 2026-11-23; the job must fail, not warn-and-green a permanent silent no-op)" % (tag, rc))
        if not any(re.search(pat, ln) for ln in err.splitlines()):
            h.bad("t4[%s]: stderr lacks the pinned `argocd-fanout config:` shape (%r):\n%s" % (tag, pat, err[:400]))
        if h.STEM in blob:
            h.bad("t4[%s]: output echoes vault token material (AC8: messages name categories and fields, never values)" % tag)
        for v in no_echo:
            if v in blob:
                h.bad("t4[%s]: output echoes the offending value %r (AC8: never values)" % (tag, v))

    for tag, vval, unset, pat in arms:
        cfg = good_roster
        extra_no = ()
        if tag == "bad-json":
            cfg = os.path.join(sys.argv[1], "t4-bad.json")
            open(cfg, "w").write("{ not valid json ]")
        elif tag == "unreadable-file":
            cfg = os.path.join(sys.argv[1], "t4-absent.json")
        elif tag == "tags-ref":
            cfg = roster_copy(lambda c: c.update(allowed_refs=["refs/heads/main", "refs/tags/v1"]), "tags")
        elif tag == "short-ref":
            cfg = roster_copy(lambda c: c.update(allowed_refs=["main"]), "short")
        elif tag == "dup-name":
            cfg = roster_copy(lambda c: c["targets"].append({"name": "dev", "url": stub.url, "root_app": "dev"}), "dup")
        elif tag == "bad-scheme":
            cfg = roster_copy(lambda c: c["targets"][0].update(url="cluster.dev.lan"), "scheme")
        elif tag == "empty-refs":
            cfg = roster_copy(lambda c: c.update(allowed_refs=[]), "emptyrefs")
        elif tag == "extra-keys":
            cfg = roster_copy(lambda c: c.update(clusterHosts={"dev": "x"}, tokenKey="legacy"), "extrakeys")
        elif tag == "inf-settle":
            cfg = roster_copy(lambda c: c.update(settle_seconds=float("inf")), "infsettle")
        elif tag == "nan-timeout":
            cfg = roster_copy(lambda c: c.update(target_timeout_seconds=float("nan")), "nantimeout")
        elif tag == "frac-workers":
            cfg = roster_copy(lambda c: c.update(parallel_workers=4.5), "fracworkers")
        elif tag == "non-jwt":
            extra_no = ("plain-secret-not-a-jwt",)
        elif tag == "reversed":
            extra_no = (h.token_for("dev"),)
        rc, out, err = h.run("t4-%s" % tag, "--ref", "refs/heads/main",
                             vault_value=vval, unset=bool(unset), config=cfg)
        check(tag, rc, out, err, pat, extra_no)

    # M1's echo BOUND: a long non-JWT first field is an informative typo,
    # and its echo is allowed only up to 64 chars (review: cat[:64]) — an
    # unbounded field echoed into the job log is a log-spam surface even
    # when it is not a token. The bound is proven by the 65-char prefix
    # being ABSENT; whether fewer chars print is the implementation's call.
    longcat = "ZQ" * 150
    rc, out, err = h.run("t4-echo-bound", "--ref", "refs/heads/main",
                         vault_value=good_vault + "\n" + longcat + ":" + h.token_for("dev"),
                         config=good_roster)
    blob = out + err
    if rc != 1:
        h.bad("t4[echo-bound]: a 300-char unknown category exited %s, expected 1" % rc)
    if longcat[:65] in blob:
        h.bad("t4[echo-bound]: MORE than 64 chars of the offending field echoed (cat[:64] bound, review M1 optional half) — the leak-guard must also cap non-JWT field dumps")
    if h.STEM in blob:
        h.bad("t4[echo-bound]: the bound-arm record echoed token material (AC8)")

    if recs:
        h.bad("t4: %d stub requests landed despite every arm being a config error — validation must fail closed BEFORE the network (a dialed-anyway arm can half-sync)" % len(recs))

    # The --check mode must reject the SAME classes (it "parses roster +
    # vault fully", plan Modes).
    rc, out, err = h.run("t4-check-unknown", "--check",
                         vault_value=good_vault + "\nnotacat:" + h.token_for("notacat"),
                         config=good_roster)
    check("check/unknown-category", rc, out, err,
          r'argocd-fanout config: record for unknown category "notacat"')
finally:
    stub.stop()

print("ok: t4: every config-error class exits 1 with the pinned `argocd-fanout config:` stderr shape (the four byte-pinned messages plus the field-naming m1/m2/m3/nit arms), none echoes any token or offending value, the M1 echo stays within the cat[:64] bound, none dials the network, and --check enforces the same vocabulary (AC4, AC8, ruled red-posture, review-round arms M1/m2/m3/nits)")
PY
  then
    fail "t4: the config-error contract is violated (reason printed above)"
  fi
  ok "t4: config-error vocabulary + zero-dial + zero-echo hold in live and --check modes (AC4/AC8)"
fi

# --- t5: happy fan-out over stubbed clusters (AC5) ------------------------------
if want t5; then
  if ! python3 - "$WORK" <<'PY'
import os, sys

sys.path.insert(0, sys.argv[1])
import harness as h

recs = []
dev = h.StubArgo("dev", recs, apps=[
    h.app("dev", h.REPO, "main", "OutOfSync", multi=True),  # roots are multi-source
    h.app("dev-app1", h.REPO, "main", "OutOfSync"),         # -> sync
    h.app("dev-synced", h.REPO, "main", "Synced"),         # -> leave
    h.app("dev-wrongrev", h.REPO, "stage", "OutOfSync"),   # -> leave (live targetRevision)
    h.app("dev-wrongrepo", h.OTHER_REPO, "main", "OutOfSync"),  # -> leave (byte repoURL)
    h.app("dev-multi", h.REPO, "main", "Unknown", multi=True),  # sources-shape child, not Synced -> sync
])
media = h.StubArgo("media", recs, apps=[h.app("media", h.REPO, "main", "OutOfSync")])
grow = h.StubArgo("grow", recs, apps=[h.app("grow-child", h.REPO, "main", "OutOfSync")])  # root absent -> skipped
for s in (dev, media, grow):
    s.start()
try:
    roster = h.make_roster(os.path.join(sys.argv[1], "t5"), [
        {"name": "dev", "url": dev.url},
        {"name": "media", "url": media.url},
        {"name": "grow", "url": grow.url},
    ], settle_seconds=0.3)  # per-roster knob, not env (shipped relay read env; the script takes the roster)
    rc, out, err = h.run("t5", "--ref", "refs/heads/main",
                         vault_value=h.vault(["dev", "media", "grow"]), config=roster)
    blob = out + err
    if rc != 0:
        h.bad("t5: happy run exited %s (runtime must be green — per-target failures self-heal next push)\n%s" % (rc, blob[:600]))

    a = {x["name"]: x for x in h.audits(blob)}
    if set(a) != {"dev", "media", "grow"}:
        h.bad("t5: audit lines for %s, expected exactly the 3 targets (one line per target regardless of worker completion order)" % sorted(a))
    if a["dev"]["result"] != "ok" or a["dev"]["root"] != "dev" or a["dev"]["ref"] != "refs/heads/main":
        h.bad("t5: dev audit wrong: %r (pinned grammar target/result/root/ref/elapsed/detail)" % a["dev"])
    if a["dev"]["detail"] != "root synced, 2 children synced":
        h.bad("t5: dev detail %r, expected 'root synced, 2 children synced' (the Synced/wrongrev/wrongrepo children must NOT be synced — the OQ7 layer-2 filter)" % a["dev"]["detail"])
    if a["media"]["detail"] != "root synced, 0 children synced":
        h.bad("t5: media detail %r" % a["media"]["detail"])
    if a["grow"]["result"] != "skipped":
        h.bad("t5: missing-root target must be skipped, got %r" % a["grow"])
    if a["grow"]["detail"] != "root app grow does not track revision main":
        h.bad("t5: skip detail %r, expected the ported pinned text 'root app grow does not track revision main'" % a["grow"]["detail"])
    if h.summary(blob) != ("3", "2", "1", "0"):
        h.bad("t5: summary %r, expected targets=3 ok=2 skipped=1 failed=0" % (h.summary(blob),))

    seq = [r for r in dev.records if r["stub"] == "dev"]
    kinds = [(r["kind"], r.get("app")) for r in seq]
    want = [("list", None), ("sync", "dev"), ("list", None),
            ("sync", "dev-app1"), ("sync", "dev-multi")]
    if kinds != want:
        h.bad("t5: dev request sequence %s != pinned root-first -> settle -> re-list -> children (only matching, non-Synced children) %s" % (kinds, want))
    root_sync = next(r for r in seq if r["kind"] == "sync" and r["app"] == "dev")
    relist = [r for r in seq if r["kind"] == "list"][1]
    gap = relist["ts"] - root_sync["ts"]
    if gap < 0.25:
        h.bad("t5: only %.2fs between root sync and the re-list — settle_seconds=0.3 was not honored (the children pass must judge the FRESH post-root listing)" % gap)
    child_syncs = [r for r in seq if r["kind"] == "sync" and r["app"] != "dev"]
    if any(c["ts"] < relist["ts"] for c in child_syncs):
        h.bad("t5: a child POST landed before the post-settle re-list — the ThreadPool(4) workers must keep each target's root->settle->children order (no post-settle race)")
    gseq = [r["kind"] for r in grow.calls()]
    if gseq != ["list"]:
        h.bad("t5: skipped target dialed %s, expected exactly its eligibility list (a skip must not POST)" % gseq)

    # ThreadPool(4) witness: two settling targets must OVERLAP in wall time
    # (a serial port of the shipped loop would make them strictly ordered).
    d_first, d_last = min(r["ts"] for r in dev.calls()), max(r["ts"] for r in dev.calls())
    m_first, m_last = min(r["ts"] for r in media.calls()), max(r["ts"] for r in media.calls())
    if not (d_first < m_last and m_first < d_last):
        h.bad("t5: dev and media request windows do not overlap (%.3f..%.3f vs %.3f..%.3f) — the fan-out must run targets concurrently, plan contract parallel_workers 4" % (d_first, d_last, m_first, m_last))

    # OQ8 live rerun: the ruled form is newline, but a comma-paste must fan
    # out identically (paste-accident defense is code, not just parsing).
    rc2, out2, err2 = h.run("t5-comma", "--ref", "refs/heads/main",
                            vault_value=h.vault(["dev", "media", "grow"], delim=","),
                            config=roster)
    blob2 = out2 + err2
    a2 = {x["name"]: x for x in h.audits(blob2)}
    got2 = {k: v["result"] for k, v in a2.items()}
    if rc2 != 0 or got2 != {"dev": "ok", "media": "ok", "grow": "skipped"}:
        h.bad("t5: comma-form vault must parse and fan out with identical per-target results (the stub app state is static): rc=%s %r" % (rc2, got2))
finally:
    for s in (dev, media, grow):
        s.stop()

print("ok: t5: exact audit grammar, per-target root->settle->re-list->children order under ThreadPool(4) overlap, Synced/wrong-rev/wrong-repo children never POSTed, pinned skip detail, summary math, and the comma-paste live rerun all hold (AC5, OQ8)")
PY
  then
    fail "t5: the live fan-out shape is violated (reason printed above)"
  fi
  ok "t5: fan-out semantics + parallel-ordering guarantees hold against stubbed clusters (AC5)"
fi

# --- t6: prune=false in query AND body, never force (AC5/OQ6) -------------------
if want t6; then
  if ! python3 - "$WORK" <<'PY'
import os, sys

sys.path.insert(0, sys.argv[1])
import harness as h

recs = []
stub = h.StubArgo("gpu", recs, apps=[
    h.app("gpu", h.REPO, "main", "OutOfSync"),
    h.app("gpu-kube-system", h.REPO, "main", "OutOfSync"),
])
stub.start()
try:
    roster = h.make_roster(os.path.join(sys.argv[1], "t6"),
                           [{"name": "gpu", "url": stub.url}], settle_seconds=0.0)
    rc, out, err = h.run("t6", "--ref", "refs/heads/main",
                         vault_value=h.vault(["gpu"]), config=roster)
    if rc != 0:
        h.bad("t6: run exited %s\n%s" % (rc, (out + err)[:400]))
    syncs = stub.syncs()
    if len(syncs) != 2:
        h.bad("t6: %d sync POSTs, expected 2 (root + child)" % len(syncs))
    for r in syncs:
        q = r["path"].split("?", 1)
        if len(q) != 2 or "prune=false" not in q[1]:
            h.bad("t6: POST path %r lacks ?prune=false in the QUERY (OQ6 pins both places: the grpc-gateway maps query params onto SyncRequest fields)" % r["path"])
        if r["body"] != {"prune": False}:
            h.bad("t6: POST body %r, expected exactly {\"prune\": false} (the CLI-shaped client reads the BODY; pinning both leaves no server-side default path)" % r["body"])
        if "force" in q[1] or (isinstance(r["body"], dict) and "force" in r["body"]):
            h.bad("t6: a `force` key appears (OQ6: never force — a forced sync overwrites operator drift by hand)")
finally:
    stub.stop()

print("ok: t6: every sync POST carries prune=false in query AND body with no force anywhere (AC5/OQ6)")
PY
  then
    fail "t6: the prune/force pinning is violated (reason printed above)"
  fi
  ok "t6: prune=false in both places, never force (OQ6)"
fi

# --- t7: 409 is success AND the sweep continues (AC5) ---------------------------
if want t7; then
  if ! python3 - "$WORK" <<'PY'
import os, sys

sys.path.insert(0, sys.argv[1])
import harness as h

recs = []
stub = h.StubArgo("media", recs,
                  apps=[h.app("media", h.REPO, "main", "OutOfSync"),
                        h.app("media-child", h.REPO, "main", "OutOfSync")],
                  sync_codes={"media": 409})
stub.start()
try:
    roster = h.make_roster(os.path.join(sys.argv[1], "t7"),
                           [{"name": "media", "url": stub.url}], settle_seconds=0.0)
    rc, out, err = h.run("t7", "--ref", "refs/heads/main",
                         vault_value=h.vault(["media"]), config=roster)
    blob = out + err
    a = h.audits(blob)
    if rc != 0:
        h.bad("t7: a 409-root run must exit 0, got %s\n%s" % (rc, blob[:400]))
    if len(a) != 1 or a[0]["result"] != "ok" or a[0]["detail"] != "root in-progress, 1 children synced":
        h.bad("t7: audit %r, expected result=ok detail='root in-progress, 1 children synced' (409 = the same state is already syncing under the same non-prune semantics; and the child sweep must CONTINUE past the in-progress root — shipped drive_target behavior)")
    names = [r["app"] for r in stub.syncs()]
    if names != ["media", "media-child"]:
        h.bad("t7: POST order %s — the child sync must still fire after the 409 root" % names)
finally:
    stub.stop()

print("ok: t7: 409 audits as root=in-progress success and the sweep continues to children (AC5)")
PY
  then
    fail "t7: the 409-as-success posture is violated (reason printed above)"
  fi
  ok "t7: 409-as-success with continued sweep (AC5)"
fi

# --- t8: per-target isolation incl. the RULED OQ9 posture (AC6) -----------------
if want t8; then
  if ! python3 - "$WORK" <<'PY'
import os, sys

sys.path.insert(0, sys.argv[1])
import harness as h

recs = []
dead_port = h.free_port()  # closed socket: the proxy-backup analog (TCP filtered)
dev = h.StubArgo("dev", recs, apps=[h.app("dev", h.REPO, "main", "OutOfSync"),
                                    h.app("dev-app1", h.REPO, "main", "OutOfSync")])
gpu = h.StubArgo("gpu", recs, get_code=401)
grow = h.StubArgo("grow", recs, get_raw="this is not json {{{")
media = h.StubArgo("media", recs, apps=[h.app("media", h.REPO, "main", "OutOfSync")],
                   get_delay=3.0)
for s in (dev, gpu, grow, media):
    s.start()
try:
    roster = h.make_roster(os.path.join(sys.argv[1], "t8"), [
        {"name": "dev", "url": dev.url},
        {"name": "gpu", "url": gpu.url},
        {"name": "grow", "url": grow.url},
        {"name": "media", "url": media.url},
        {"name": "proxy-backup", "url": "http://127.0.0.1:%d" % dead_port},
    ], settle_seconds=0.0, target_timeout_seconds=0.5)
    rc, out, err = h.run("t8", "--ref", "refs/heads/main",
                         vault_value=h.vault(["dev", "gpu", "grow", "media", "proxy-backup"]),
                         config=roster)
    blob = out + err
    if rc != 0:
        h.bad("t8: dead/401/garbage/timeout/refused targets must NOT flip the exit code (R1 self-heal: the next push covers them) — got %s\n%s" % (rc, blob[:500]))
    a = {x["name"]: x for x in h.audits(blob)}
    if set(a) != {"dev", "gpu", "grow", "media", "proxy-backup"}:
        h.bad("t8: audit set %s != the 5 targets — every target, healthy or not, gets its line (isolation must not swallow lines)" % sorted(a))
    if a["dev"]["result"] != "ok":
        h.bad("t5-adjacent break: healthy target dev got %r while neighbors failed (per-target isolation)" % a["dev"]["result"])
    for t, why in (("gpu", "401"), ("grow", "garbage JSON"), ("media", "timeout"),
                   ("proxy-backup", "connection refused — the RULED OQ9 warn-and-skip posture: a listed but unreachable cluster is an honest failed audit line, never a silent drop")):
        if a[t]["result"] != "failed":
            h.bad("t8: %s target must audit failed (%s), got %r" % (t, why, a[t]))
        if not a[t]["detail"].strip():
            h.bad("t8: failed audit for %s carries no reason (operators grep detail)" % t)
    if "401" not in a["gpu"]["detail"]:
        h.bad("t8: 401 detail %r should name the HTTP code (shipped `applications list HTTP %d` vocabulary)" % a["gpu"]["detail"])
    if "tim" not in a["media"]["detail"] or "out" not in a["media"]["detail"]:
        h.bad("t8: timeout detail %r does not name the timeout (the 0.5s per-request budget must be enforced on the list leg)" % a["media"]["detail"])
    if h.summary(blob) != ("5", "1", "0", "4"):
        h.bad("t8: summary %r, expected targets=5 ok=1 skipped=0 failed=4 (the math must reconcile with the audit lines)" % (h.summary(blob),))
    child = [r for r in dev.syncs() if r["app"] == "dev-app1"]
    if len(child) != 1:
        h.bad("t8: the healthy target's child sweep was disturbed by its neighbors (dev-app1 POSTs: %d)" % len(child))

    # ---- M2 phase: 3xx containment, both legs, against a separate-origin
    # redirect target whose access log is the token-egress witness. The live
    # trigger is real: cluster.proxy-local answers 307 to the SSO edge even
    # with a bearer present (review round 1). The pinned posture: a door 3xx
    # surfaces in the FAILED audit lane with the shipped HTTP-code wording,
    # the bearer never leaves the rostered origin, and a 3xx-turned-GET can
    # never earn result=ok.
    x1, x2 = [], []
    cross1 = h.StubArgo("cross1", x1, apps=[h.app("gpu", h.REPO, "main", "OutOfSync")])
    cross2 = h.StubArgo("cross2", x2, apps=[h.app("media", h.REPO, "main", "OutOfSync")])
    front_list = h.StubArgo("front-list", recs, get_redirect=302,
                            redirect_to=cross1.url + "/login")
    front_sync = h.StubArgo("front-sync", recs,
                            apps=[h.app("media", h.REPO, "main", "OutOfSync")],
                            post_redirect=301, redirect_to=cross2.url + "/api/v1/applications")
    for s in (cross1, cross2, front_list, front_sync):
        s.start()
    try:
        roster2 = h.make_roster(os.path.join(sys.argv[1], "t8-3xx"), [
            {"name": "gpu", "url": front_list.url},
            {"name": "media", "url": front_sync.url},
        ], settle_seconds=0.0)
        rc2, out2, err2 = h.run("t8-3xx", "--ref", "refs/heads/main",
                                vault_value=h.vault(["gpu", "media"]), config=roster2)
        blob2 = out2 + err2
        if rc2 != 0:
            h.bad("t8-3xx: a redirecting cluster is a RUNTIME failure — soft lane, exit 0 (got %s)\n%s" % (rc2, blob2[:400]))
        a2 = {x["name"]: x for x in h.audits(blob2)}
        if set(a2) != {"gpu", "media"}:
            h.bad("t8-3xx: audits %s, expected both redirect targets" % sorted(a2))
        if a2.get("gpu", {}).get("result") != "failed" or "applications list HTTP 302" not in a2.get("gpu", {}).get("detail", ""):
            h.bad("t8-3xx: the 302 list door must audit failed with the shipped `applications list HTTP 302` wording (no silent follow), got %r" % a2.get("gpu"))
        if a2.get("media", {}).get("result") != "failed" or "sync HTTP 301" not in a2.get("media", {}).get("detail", ""):
            h.bad("t8-3xx: the 301 sync door must audit failed with `sync HTTP 301` — and MUST NOT audit ok: the default opener turns POST into GET, lands an HTML page, and would fake a green sweep (review M2 false-green)", )
        if "result=ok" in blob2:
            h.bad("t8-3xx: result=ok appeared with zero real syncs performed — the operator-grepped success channel was earned by a redirect page (M2)")
        for label, xlog in (("cross1", x1), ("cross2", x2)):
            if xlog:
                leaks = [r for r in xlog if r.get("auth")]
                h.bad("t8-3xx: %d request(s) landed on the redirect TARGET %s (%d carrying Authorization!) — the bearer left the rostered origin; api_request must refuse redirects" % (len(xlog), label, len(leaks)))
        # the rostered origins were dialed exactly once list-each (+ the
        # front-sync POST attempt): containment happens at the door, not by
        # skipping the target.
        gl = [r for r in recs if r["stub"] == "front-list"]
        gs = [r for r in recs if r["stub"] == "front-sync"]
        if not any(r["method"] == "GET" for r in gl) or not any(r["method"] == "GET" for r in gs):
            h.bad("t8-3xx: the redirecting targets were not dialed (doors must be PROVEN unreachable, not bypassed)")
        if not any(r["method"] == "POST" for r in gs):
            h.bad("t8-3xx: front-sync never received the POST attempt — eligibility said sync, so the sync leg must fire into the door")
        if h.summary(blob2) != ("2", "0", "0", "2"):
            h.bad("t8-3xx: summary %r, expected targets=2 ok=0 skipped=0 failed=2" % (h.summary(blob2),))
        # token stem never rides any line — cross logs stayed empty, and the
        # Bearer header that WAS sent went only to the rostered origin.
        if h.STEM in blob2:
            h.bad("t8-3xx: token material echoed in the 3xx legs' output (AC8)")
        # egress check on the wire itself: the front stubs saw the bearer
        # (their origin, correct); assert the auth headers on door requests
        # reference the dev/media tokens, not a stray target.
        for r in gl + gs:
            if r["auth"] and not r["auth"].startswith("Bearer " + h.SEG1):
                h.bad("t8-3xx: door request carried an unexpected Authorization shape: %r" % r["auth"][:30])
    finally:
        for s in (cross1, cross2, front_list, front_sync):
            s.stop()
finally:
    for s in (dev, gpu, grow, media):
        s.stop()

print("ok: t8: 401/garbage/timeout/refused neighbors fail in isolation — each audits a reason, the healthy target completes, the summary reconciles, exit stays 0; the closed-port arm is the OQ9 honest-failed posture; the 3xx phase proves redirect containment on BOTH legs (M2): door 3xx audits `applications list HTTP 302` / `sync HTTP 301`, no result=ok, zero requests on the redirect target and its bearer (AC6)")
PY
  then
    fail "t8: the isolation posture is violated (reason printed above)"
  fi
  ok "t8: per-target isolation + OQ9 honest failed lines + soft exit (AC6)"
fi

# --- t9: ref gate is zero-touch (AC7) -------------------------------------------
if want t9; then
  if ! python3 - "$WORK" <<'PY'
import os, sys

sys.path.insert(0, sys.argv[1])
import harness as h

recs = []
stub = h.StubArgo("dev", recs, apps=[h.app("dev", h.REPO, "main", "OutOfSync")])
stub.start()
try:
    roster = h.make_roster(os.path.join(sys.argv[1], "t9"),
                           [{"name": "dev", "url": stub.url}])
    rc, out, err = h.run("t9", "--ref", "refs/heads/other",
                         vault_value=h.vault(["dev"]), config=roster)
    blob = out + err
    if rc != 0:
        h.bad("t9: a non-allowed ref is a designed no-op, not an error — exit %s\n%s" % (rc, blob[:400]))
    if recs:
        h.bad("t9: %d stub requests landed for a ref outside allowed_refs (AC7: ZERO API calls — the gate is the OQ7 widening guarantee)" % len(recs))
    if "refs/heads/other" not in blob:
        h.bad("t9: the skip is silent — the one log line must name the ref (AC7: exactly one log line)")
    if h.summary(blob):
        h.bad("t9: the ref gate emitted a fan-out summary — no fan-out ran; the ref-gate path is the one line + exit 0 (a skipped-x-targets summary would be a different, unpinned shape)")
    if len(h.audits(blob)) != 0:
        h.bad("t9: the ref gate emitted per-target audit lines (AC7: one log line, not audits)")
finally:
    stub.stop()

print("ok: t9: --ref outside allowed_refs logs one line naming the ref, dials nothing, prints no audits/summary, exits 0 (AC7)")
PY
  then
    fail "t9: the ref gate is violated (reason printed above)"
  fi
  ok "t9: ref gate zero-touch posture (AC7)"
fi

# --- t10: --dry-run is live GETs only (AC9) -------------------------------------
if want t10; then
  if ! python3 - "$WORK" <<'PY'
import os, sys

sys.path.insert(0, sys.argv[1])
import harness as h

recs = []
dev = h.StubArgo("dev", recs, apps=[
    h.app("dev", h.REPO, "main", "OutOfSync"),
    h.app("dev-app1", h.REPO, "main", "OutOfSync"),
])
grow = h.StubArgo("grow", recs, apps=[h.app("grow", h.REPO, "main", "Synced")])
dev.start(); grow.start()
try:
    roster = h.make_roster(os.path.join(sys.argv[1], "t10"), [
        {"name": "dev", "url": dev.url},
        {"name": "grow", "url": grow.url},
    ])
    rc, out, err = h.run("t10", "--dry-run", "--ref", "refs/heads/main",
                         vault_value=h.vault(["dev", "grow"]), config=roster)
    blob = out + err
    if rc != 0:
        h.bad("t10: --dry-run exited %s\n%s" % (rc, blob[:400]))
    posts = [r for r in recs if r["method"] == "POST"]
    if posts:
        h.bad("t10: --dry-run POSTed %d times — dry-run is the runbook smoke/preflight mode; it must never change cluster state (plan Modes: live GETs only, zero POSTs)" % len(posts))
    if not dev.lists() or not grow.lists():
        h.bad("t10: --dry-run skipped a target's list call — it is the REACHABILITY proof (the proxy-backup preflight row), every target must be dialed")
    for t in ("dev", "grow"):
        if ("target=%s" % t) not in blob:
            h.bad("t10: no per-target eligibility line for %r in --dry-run output (AC9: eligibility + would-sync counts per target):\n%s" % (t, blob[:500]))
finally:
    dev.stop(); grow.stop()

print("ok: t10: --dry-run dials every target with GETs, records ZERO POSTs, prints per-target eligibility, exits 0 (AC9 — the smoke/preflight mode)")
PY
  then
    fail "t10: the dry-run contract is violated (reason printed above)"
  fi
  ok "t10: dry-run GET-only reachability posture (AC9)"
fi

# --- t11: all-skipped warns and stays green (AC10) ------------------------------
if want t11; then
  if ! python3 - "$WORK" <<'PY'
import os, sys

sys.path.insert(0, sys.argv[1])
import harness as h

recs = []
stub = h.StubArgo("dev", recs, apps=[h.app("dev", h.OTHER_REPO, "main", "OutOfSync")])
stub.start()
try:
    # The trackedRepo-mismatch trap [P §3]: a fan-out that skipped 100% of
    # targets is almost certainly a drifted tracked_repo, not an empty fleet.
    # Two targets: the m1 "exactly once" pin cannot bite on a one-target run
    # (per-target emission would still count 1).
    roster = h.make_roster(os.path.join(sys.argv[1], "t11"),
                           [{"name": "dev", "url": stub.url},
                            {"name": "grow", "url": stub.url}],
                           tracked_repo="https://github.com/OwnYourIO/NeverDeployed.git")
    rc, out, err = h.run("t11", "--ref", "refs/heads/main",
                         vault_value=h.vault(["dev", "grow"]), config=roster)
    blob = out + err
    a = h.audits(blob)
    if rc != 0:
        h.bad("t11: all-skipped exits %s, expected 0 (a runtime-shape miss stays soft; only SETUP errors go red)" % rc)
    if not a or any(x["result"] != "skipped" for x in a) or len(a) != 2:
        h.bad("t11: audits %r, expected both targets skipped" % [dict(x) for x in a])
    if "::warning::" not in blob:
        h.bad("t11: all-skipped run lacks the pinned `::warning::` line (plan: the trackedRepo-mismatch trap [P §3] must announce)")
    # Review m1: the annotation grammar is LINE-ANCHORED (act lineage
    # commandPatternGA ^::cmd::, runner issue #4692's framing) — a warning
    # behind log()'s timestamp is readable but never becomes an annotation,
    # and a per-target trap line would spam the job. Pin: exactly one, at
    # column 0.
    wlines = [ln for ln in blob.splitlines() if "::warning::" in ln]
    if len(wlines) != 1:
        h.bad("t11: %d lines carry ::warning:: — the trap annotation appears EXACTLY once per run" % len(wlines))
    if any(not ln.startswith("::warning::") for ln in wlines):
        h.bad("t11: the all-skipped ::warning:: is not at column 0 (m1: mid-line the runner grammar ignores it — print the annotation directly, not through log())")
    if h.summary(blob) != ("2", "0", "2", "0"):
        h.bad("t11: summary %r, expected targets=2 ok=0 skipped=2 failed=0" % (h.summary(blob),))
finally:
    stub.stop()

print("ok: t11: all-skipped audits skipped, warns ONE column-0 ::warning:: (m1), summarizes, exits 0 (AC10)")
PY
  then
    fail "t11: the all-skipped posture is violated (reason printed above)"
  fi
  ok "t11: all-skipped warning posture (AC10)"
fi

# --- t12: secret hygiene sweep + usage posture (AC8 + CLI contract) --------------
if want t12; then
  if ! python3 - "$WORK" <<'PY'
import os, sys

sys.path.insert(0, sys.argv[1])
import harness as h

# Extra invocations FIRST so their captures join the sweep:
rc, out, err = h.run("t12-help", "--help")
blob = out + err
if rc != 0:
    h.bad("t12: --help exited %s\n%s" % (rc, blob[:300]))
for flag in ("--config", "--ref", "--check", "--dry-run"):
    if flag not in blob:
        h.bad("t12: --help does not advertise %s (the CLI contract is exactly these four flags + --help)" % flag)
for flag in ("--token", "--secret", "--vault"):
    if flag in blob:
        h.bad("t12: --help advertises %s — tokens come ONLY from the ARGOCD_SYNC_TOKENS env var, never argv (plan CLI contract)" % flag)

rc, out, err = h.run("t12-positional", "refs/heads/main", vault_value=h.vault(["dev"]))
if rc != 2:
    h.bad("t12: a positional ref exited %s, expected argparse 2 — 'No positional args' is the pinned CLI contract" % rc)
# A decoy value (not a fixture token) keeps the argv ledger sweep honest: the
# probe proves no token channel exists without poisoning the ledger with one.
rc, out, err = h.run("t12-token-flag", "--token", "DECOY42-not-a-real-token",
                     vault_value=h.vault(["dev"]))
if rc != 2:
    h.bad("t12: a --token flag exited %s, expected argparse 2 — a token-receiving flag must not exist")

# The sweep: every leg captured so far — combined output of ALL runs — must
# not contain a single fixture token (SENT23 stem), and the argv ledger must
# carry no JWT-shaped value at all (the SEG1 header appears only inside real
# fixture tokens, which flow to the script via env, never argv).
hits = []
for fn in sorted(os.listdir(h.OUT)):
    path = os.path.join(h.OUT, fn)
    with open(path, errors="replace") as f:
        if h.STEM in f.read():
            hits.append(fn)
if hits:
    h.bad("t12: token material echoed in %s — the zero-token-echo guarantee (AC8) failed on at least one leg; logs kept at %s" % (hits, h.OUT))
argv_hits = [ln.split("\t")[0] for ln in open(os.path.join(h.OUT, "argv.log"), errors="replace")
             if h.SEG1 in ln or ":".join([h.SEG1, h.SEG2]) in ln]
if argv_hits:
    h.bad("t12: fixture token reached the argv of leg(s) %s — tokens come ONLY from the environment variable (plan CLI contract)" % argv_hits)
for c in h.CATS:
    if c.replace("-", "") + h.STEM in " ".join(open(os.path.join(h.OUT, fn), errors="replace").read()
                                               for fn in os.listdir(h.OUT)):
        h.bad("t12: per-category token for %r echoed (attribution-level sweep)" % c)

print("ok: t12: --help shows only the four pinned flags (no token channel); positional and --token invocations exit 2; SENT23 appears in ZERO bytes across every leg's captured stdout+stderr and the argv ledger (AC8)")
PY
  then
    fail "t12: the secret-hygiene/usage contract is violated (reason printed above)"
  fi
  ok "t12: zero token echo across all legs + usage posture (AC8)"
fi

rm -rf "$WORK"
printf 'PASS: argocd-fanout behavior checks (%d ok)\n' "$checks"
