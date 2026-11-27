#!/usr/bin/env bash
# Fan-out engine behavior contract (2026/2026-11-cf-139-feat-argocd-webhook-sync):
# scripts/argocd-fanout.py + scripts/argocd-fanout.json — the vault-direct
# fan-out logic home (ruling R6), stdlib-only, ported 1:1 from the shipped
# relay's main.py semantics (root-first -> settle -> children sweep, live
# targetRevision + byte repoURL match, prune=false in query AND body,
# 409-as-success, per-target isolation, M2 redirect containment).
#
# Re-pin at reopen4 (R8, plan "Fan-out INPUT contract" v3, waves 13–14): the
# script gains the ARGOCD_PAIRS_FILE channel — load_pairs_file feeds the
# EXISTING discover_targets UNCHANGED (the file is just another dict in the
# same ARGOCD_SYNC_* namespace, DECISIONS 2026-11-26 (b)), precedence is
# file-wins-entirely (set-and-non-empty skips the env scan; unset/empty keeps
# it byte-identical), file errors are config RED naming the PATH only, and an
# empty {} file is the all-absent discovery result — the SAME pinned
# WARN_NOT_CONFIGURED green lane. OQ-A is RULED pure discovery (option b):
# NO categories list, NO oracle, NO membership concept in any channel — the
# delivered vault map IS fleet membership. Ruled drift envelope (t9, asserted
# AS CONTRACT): half-delete RED / both-gone QUIET fleet N−1 (the summary
# count is the only signal, by design) / stray-complete pair QUIET JOIN /
# blanked-both (j) RED. The roster stays the five globals byte-unchanged
# (zero schema churn); the main-sync t13 roster leg is parse-only permanently
# — the schema pin lives HERE, in t2.
#
# Contract source: chunks/C14.md "## Tests" re-pin map + plan "Fan-out INPUT
# contract" + DECISIONS OQ-A block. AC trace: t1[AC1] t2[AC1 guard] t3–t5[AC7
# env-channel preservation] t6[AC3] t7[AC4] t8[AC5] t9[AC5] t10–t13[AC5
# core + channel-independence twins] t14[CLI contract] t15[AC6/AC8].
# Ruling (j) survives for BLANKED pairs only (names present, values empty in
# the map); a DELETED pair leaves discovery silently — t9 pins both classes
# per ruling, never one against the other.
#
# RED POSTURE (authoring-era, pre-C14 — historical; today the whole suite is
# green on the landed tree): t6–t9 red (they name the missing
# channel — then the file is ignored and the empty env fall-through answers
# the kill lane), plus the two file-channel twin sublegs inside t10/t13;
# everything else was green on the pre-C14 script and stayed green through C13
# (C13 touches only the workflow — the script keeps env-scanning, and the
# mid-wave CI run warn-greens inert, never wrong). After C14 the whole suite
# must be green — PROVEN: the C14 landing (subject 'feat(fanout): C13+C14
# fleet-blind pipeline') turns the
# designed-red set green on the tracked script; any /tmp oracle used to
# pre-prove the shape is a scratch artifact, not a suite dependency.
#
# ALLOWED SURFACE (t15 doctrine): C14 may edit ONLY the module docstring,
# add load_pairs_file, and rewire main's source selection. discover_targets,
# cmd_check, load_roster, both error classes, every regex/kill-lane constant
# and all 13 core functions are byte-locked (t15 compares them against the
# recorded tips). If implementation pressure says "touch discover_targets",
# STOP — one validator body serving both sources IS the design's testability
# guarantee (DECISIONS 2026-11-26 (a)).
#
# TRANSITIONAL-ERA SHIM (why run_core exists): the core-semantics legs must
# stay green ON THE SHIPPED script today (C09's red map kept them out of the
# designed-red set) and green on the C14 script after landing. No single
# invocation shape satisfies the pre-C09 and post-C09 eras (shipped requires
# roster targets[]; C09 forbids it), so run_core() tries the C09 form first
# (pairs env + five-globals roster) and re-runs the legacy form (blob env +
# targets roster) ONLY when the fingerprint is the shipped-era roster-schema
# ConfigError. Any other red stands as a real failure — an input-layer
# regression can never fall back silently.
#
# The suite's invocations are SOURCED-ENV ONLY: pair values flow through the
# subprocess environment (or, from C14, a pairs JSON file whose PATH is the
# only byte that travels) — never KEY=value argv — and t14 sweeps the argv
# ledger to prove it (no '=' byte, no ARGOCD_SYNC name, no token material
# anywhere).
#
# Offline-deterministic: the fake ArgoCD API is threaded loopback
# http.server stubs (the relay-suite stub pattern, re-armed for the
# script's REST-client side); scratch under /tmp/opencode per the repo's
# script.sh precedent. Every fixture token is JWT-shaped and carries the
# SENT23 stem so t15's zero-echo sweep is one grep over every captured leg
# log + the argv ledger — including the file-channel legs, where the token
# lives inside a pairs.json the script must never print.
#
# HARNESS-PINNED SURFACE (authored before the implementation): 1. --dry-run
# prints one per-target line carrying `target=<name>`. 2. Config-error lines
# land on stderr (the `argocd-fanout config:` prefix is contract-pinned).
# 3. The ref-gate line names the rejected ref. 4. The kill-lane stdout is
# EXACTLY the pinned column-0 warning line (AC6: no other stdout) — and the
# {}-file lane reaches it through the file channel identically.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

FANOUT="${FANOUT_SCRIPT:-scripts/argocd-fanout.py}"
ROSTER="${FANOUT_ROSTER:-scripts/argocd-fanout.json}"
# BASELINE CONTENT-LOCKS (the cf-56-round durable convention): every raw
# hash this chain has ever mapped — 6ed762140, de3bccf43, 0d1ba90eb — has
# dangled within one rebase, because rebases and cherry-picks rewrite
# hashes while PRESERVING commit subjects. So baselines resolve by subject:
#   git log -F --grep='<subject>' --format=%H --reverse | head -1
# An empty resolution FAILS loudly naming the subject (a legitimate subject
# reword needs a suite-side remap, never a silent pass); the raw-hash env
# overrides (CHUNK_BASE / INPUT_BASE) remain for review pinning to one
# exact commit. Subject 'fix(fanout): C12 ruling (j)' covers BOTH locks:
# every core function AND the whole pre-C14 input layer is byte-identical
# there (the reopen3-close chore carries the same script bytes; C14's
# allowed surface is docstring + load_pairs_file + main only).
resolve_subject() {
  local subj="$1" out
  out=$(git log -F --grep="$subj" --format=%H --reverse | head -1)
  if [ -z "$out" ]; then
    printf 'FAIL: baseline subject "%s" resolves to NO commit in this history — the content-lock convention names commits by subject (survives rebase/cherry-pick); a subject reword is a plan-side event: remap this suite, or pass the raw-hash env override for one run\n' "$subj" >&2
    exit 1
  fi
  printf '%s\n' "$out"
}
CORE_BASE="${CHUNK_BASE:-$(resolve_subject 'fix(fanout): C12 ruling (j)')}"
INPUT_BASE="${INPUT_BASE:-$(resolve_subject 'fix(fanout): C12 ruling (j)')}"

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
  for i in $(seq 1 15); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t([1-9]|1[0-5])$ ]] || fail "unknown test id '$a' (expected t1..t15)"
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
export BEH_FANOUT="$FANOUT" BEH_ROSTER="$ROSTER" BEH_OUT="$OUT" BEH_CORE_BASE="$CORE_BASE" BEH_INPUT_BASE="$INPUT_BASE"

# --- t1: files, exact import set, five-globals roster (AC1) ----------------------
if want t1; then
  [ -f "$FANOUT" ] ||
    fail "t1: $FANOUT does not exist — the fan-out engine is not implemented (red posture: this fail-fast names the absent script)"
  [ -f "$ROSTER" ] ||
    fail "t1: $ROSTER does not exist — the roster globals ship beside the script"
  python3 -m py_compile "$FANOUT" || fail "t1: py_compile failed on $FANOUT"
  if ! python3 - "$FANOUT" <<'PY'
import json, os, re, subprocess, sys

src = open(sys.argv[1]).read()
# C09 AC1 pins the import set UNCHANGED from the shipped script: no module
# may be ADDED (the job image guarantees only this budget), pyyaml/requests
# stay banned, and a pure REST client spawns nothing. C14's load_pairs_file
# rides json/os — already in the budget.
EXPECTED = {'argparse', 'concurrent', 'json', 'os', 're', 'sys', 'time', 'urllib'}
mods = set()
for m in re.finditer(r'(?m)^(?:import|from)\s+([A-Za-z_][A-Za-z0-9_]*)', src):
    mods.add(m.group(1))
if mods != EXPECTED:
    extra = sorted(mods - EXPECTED)
    missing = sorted(EXPECTED - mods)
    print('FAIL: t1: import set changed: added %s, removed %s (C09 AC1: unchanged from the shipped stdlib budget)'
          % (extra or '[]', missing or '[]'), file=sys.stderr)
    sys.exit(1)
for banned in ('yaml', 'requests'):
    if re.search(r'(?m)^(?:import|from)\s+%s\b' % banned, src):
        print('FAIL: t1: imports %s — the job image does not guarantee it (stdlib-only)' % banned, file=sys.stderr)
        sys.exit(1)
for word in ('subprocess', 'docker'):
    if word in src:
        print('FAIL: t1: %r appears in the script — the fan-out spawns nothing (docker-free by ruling; the runner already carries python3)' % word, file=sys.stderr)
        sys.exit(1)

# Roster: EXACTLY the five globals (targets[] dies with R7; no compat shim).
roster = json.load(open(os.environ["BEH_ROSTER"]))
if set(roster) != {"allowed_refs", "tracked_repo", "settle_seconds",
                   "target_timeout_seconds", "parallel_workers"}:
    print('FAIL: t1: roster keys are %s, expected exactly the five globals (R7 consequence 3: targets[] DELETES — the delivered vault map is the endpoint list)'
          % sorted(roster), file=sys.stderr)
    sys.exit(1)

# Legacy roster carrying `targets` must be RED via the unknown-keys rule (C09
# task: no back-compat). Written scratch, run through --check with any env.
import os
legacy = dict(roster)
legacy["targets"] = [{"name": "dev", "url": "https://cluster.example", "root_app": "dev"}]
path = os.path.join(os.environ["BEH_OUT"], "..", "t1-legacy-roster.json")
with open(path, "w") as f:
    json.dump(legacy, f)
env = {k: v for k, v in os.environ.items() if not k.startswith("ARGOCD_SYNC")}
env["ARGOCD_SYNC_DEV_URL"] = "https://cluster.example"
env["ARGOCD_SYNC_DEV_TOKEN"] = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJtY3AtYm90In0.devSENT23xKq"
r = subprocess.run([sys.executable, "-u", sys.argv[1], "--check", "--config", path],
                   capture_output=True, text=True, env=env, timeout=30)
if r.returncode != 1 or "targets" not in (r.stderr or ""):
    print('FAIL: t1: a roster still carrying targets exited %s (expected 1, unknown-keys message naming targets) — R7 forbids a compat shim:\n%s'
          % (r.returncode, (r.stdout + r.stderr)[:400]), file=sys.stderr)
    sys.exit(1)
print('ok: t1')
PY
  then
    fail "t1: the script/roster shape contract is violated (reason printed above)"
  fi
  ok "t1: script+roster exist; py_compile clean; import set EXACTLY the shipped stdlib budget; roster is the five globals and a legacy targets-bearing roster goes RED naming the key (AC1, R7 no-back-compat)"
fi

# --- shared harness for t3..t15 --------------------------------------------------
if want t3 || want t4 || want t5 || want t6 || want t7 || want t8 \
   || want t9 || want t10 || want t11 || want t12 || want t13 || want t14 || want t15; then
  cat > "$WORK/harness.py" <<'HARNESS'
"""Stub ArgoCD API + fan-out subprocess driver for the cf-139 R7/R8 contract.

One records list per stub with seq + wall-clock stamps: per-target request
ORDER (root sync before the post-settle list before child syncs) is the
threading guarantee under ThreadPoolExecutor(4) — global audit-line order is
deliberately NOT asserted (results print as workers finish).

Input plumbing (R7 base + R8 channel): pairs flow as ARGOCD_SYNC_<CAT>_URL /
_TOKEN keys in the subprocess env (run_core's era-shim aside) or, from C14,
in a flat {NAME: value} JSON file whose path travels as ARGOCD_PAIRS_FILE.
clean_env strips BOTH surfaces on every leg, so an env arm can never see a
leftover file pointer and vice versa (suite guard: the env-channel legs
t3–t5 run with PAIRS_FILE unset by construction).
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

# Pinned column-0 kill-lane warning (plan Fan-out INPUT contract / DECISIONS
# micro-call a). Exact bytes: the runbook greps it and operators read it.
# R8 ruling (e): the {}-file lane reaches the SAME string unchanged.
WARN_KILL = ("::warning::sync-fanout not configured (no ARGOCD_SYNC_*_TOKEN keys "
             "with values) — fan-out skipped, manual sync or the next push covers it")


def token_for(cat):
    # JWT-shaped per the pinned regex, per-category distinctive so an echo
    # can be attributed; every token carries STEM for the sweep grep.
    slug = cat.replace("-", "")
    return "%s.%s.%s%sxKq" % (SEG1, SEG2, slug, STEM)


def url_key(cat):
    return "ARGOCD_SYNC_" + cat.upper().replace("-", "_") + "_URL"


def token_key(cat):
    return "ARGOCD_SYNC_" + cat.upper().replace("-", "_") + "_TOKEN"


def vault(cats):
    """DEAD-GRAMMAR blob (reopen2 era): only run_core's legacy fallback and
    the blob-ignored arms construct one — never an R7/R8 input path."""
    return "\n".join("%s:%s" % (c, token_for(c)) for c in cats)


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
                 egress off the discovered origin is observable, not inferred.
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
                        elif outer.get_code != 200:
                            self._send(outer.get_code, {"error": {"message": "mock list failure"}})
                        else:
                            self._send(200, {"items": list(outer.apps)})
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
CORE_BASE = os.environ.get("BEH_CORE_BASE", "HEAD")
INPUT_BASE = os.environ.get("BEH_INPUT_BASE", "HEAD")

GLOBALS = {"allowed_refs": ["refs/heads/main"],
           "tracked_repo": REPO,
           "settle_seconds": 0.2,
           "target_timeout_seconds": 5.0,
           "parallel_workers": 4}


def make_globals(dirpath, **overrides):
    """R7 roster: the five globals ONLY (targets[] is gone — the delivered
    pair map is the endpoint list)."""
    os.makedirs(dirpath, exist_ok=True)
    cfg = dict(GLOBALS)
    cfg.update(overrides)
    path = os.path.join(dirpath, "roster.json")
    with open(path, "w") as f:
        json.dump(cfg, f)
    return path


def make_legacy(dirpath, cats_urls, **overrides):
    """Pre-C09 roster shape (globals + targets[]) for run_core's transitional
    fallback ONLY. cats_urls: list of {name,url} — root_app mirrors name."""
    os.makedirs(dirpath, exist_ok=True)
    cfg = dict(GLOBALS)
    cfg["targets"] = [{"name": t["name"], "url": t["url"], "root_app": t["name"]}
                      for t in cats_urls]
    cfg.update(overrides)
    path = os.path.join(dirpath, "roster-legacy.json")
    with open(path, "w") as f:
        json.dump(cfg, f)
    return path


def clean_env():
    env = dict(os.environ)
    for k in list(env):
        if k.startswith("ARGOCD_SYNC") or k == "ARGOCD_PAIRS_FILE":
            del env[k]
    return env


def pair_env(env, pairs):
    """pairs: {cat: {"url": str|None, "token": str|None}} — None means the
    key is ABSENT, "" means the empty-string residue the blob delivers."""
    for cat, spec in (pairs or {}).items():
        if spec is None:
            continue
        if spec.get("url") is not None:
            env[url_key(cat)] = spec["url"]
        if spec.get("token") is not None:
            env[token_key(cat)] = spec["token"]
    return env


def file_pairs(pairs):
    """The {cat: {url, token}} spec shape rendered into the flat
    {NAME: value} map of DECISIONS (b): None drops the key from the file
    (a deleted org key), "" keeps it present-and-blank."""
    doc = {}
    for cat, spec in (pairs or {}).items():
        if spec is None:
            continue
        doc[url_key(cat)] = spec.get("url")
        doc[token_key(cat)] = spec.get("token")
    return {k: v for k, v in doc.items() if v is not None}


def write_pairs(name, mapping, dirpath=None, raw=None):
    """Emit a pairs file OUTSIDE the swept $OUT dir (its content legitimately
    carries token material — the sweep scans OUTPUT, never fixtures)."""
    home = dirpath or os.path.join(OUT, "..", "pairs")
    os.makedirs(home, exist_ok=True)
    path = os.path.join(home, "%s.json" % name)
    if raw is not None:
        with open(path, "w") as f:
            f.write(raw)
    else:
        with open(path, "w") as f:
            json.dump(mapping, f, sort_keys=True)
    return path


def run(name, *args, pairs=None, blob=None, raw_env=None, config=None,
        pairs_file=None, timeout=40):
    """Invoke the real script as a subprocess; capture combined output to
    $OUT/<name>.log and the argv to $OUT/argv.log (t15 sweeps both).
    Values flow through the environment (env channel) or a FILE whose PATH
    is the only byte that travels — never KEY=value argv, never the file's
    content in argv (t14's ledger pin)."""
    cmd = [sys.executable, "-u", FANOUT]
    if config is not None:
        cmd += ["--config", config]
    cmd += list(args)
    env = clean_env()
    pair_env(env, pairs)
    if blob is not None:
        env["ARGOCD_SYNC_TOKENS"] = blob
    env.update(raw_env or {})
    if pairs_file is not None:
        env["ARGOCD_PAIRS_FILE"] = str(pairs_file)
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


def run_file(name, *args, pairs=None, mapping=None, raw_file=None, dirpath=None,
             config=None, timeout=40):
    """File-channel runner: the C14 pairs file is the ONLY input source —
    no ARGOCD_SYNC_* env keys exist alongside it (the precedence arms that
    mix both channels call run() with raw_env directly)."""
    doc = mapping if mapping is not None else file_pairs(pairs)
    path = write_pairs(name, doc, dirpath=dirpath, raw=raw_file)
    return run(name, *args, config=config, pairs_file=path, timeout=timeout)


# Shipped-era fingerprint: load_roster demanding the deleted targets key.
_SHIPPED_ROSTER_ERR = re.compile(r"roster missing required fields:.*targets")


def run_core(name, *args, urls=None, config=None, timeout=60):
    """Core-semantics runner across the input redesign (see behavior.sh
    header). urls: {cat: url}; tokens are always the fixture JWTs. C09 form
    first; legacy form ONLY on the shipped-era roster-schema fingerprint."""
    cats = sorted(urls)
    pairs = {c: {"url": urls[c], "token": token_for(c)} for c in cats}
    rc, out, err = run("%s-r7" % name, *args, pairs=pairs, config=config, timeout=timeout)
    if rc == 1 and _SHIPPED_ROSTER_ERR.search(out + err):
        # Shipped-era code: rerun the same invocation with the pre-R7 input
        # (globals+targets roster, newline blob env) so the CORE assertions
        # below test the same fan-out shape across both eras.
        base = json.load(open(config)) if config else dict(GLOBALS)
        base.pop("targets", None)
        lc = make_legacy(os.path.join(OUT, "..", "legacy-%s" % name),
                         [{"name": c, "url": urls[c]} for c in cats], **base)
        rc, out, err = run("%s-legacy" % name, *args, blob=vault(cats),
                           config=lc, timeout=timeout)
    return rc, out, err


# run_file_core: the C14-era twin of run_core for the channel-independence
# twins — same urls fixture, delivered as a pairs file instead of env.
def run_file_core(name, *args, urls=None, config=None, timeout=60):
    cats = sorted(urls)
    pairs = {c: {"url": urls[c], "token": token_for(c)} for c in cats}
    return run_file("%s-file" % name, *args, pairs=pairs, config=config, timeout=timeout)


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

# --- t2: roster globals byte-pins + pure-discovery guard (R7 c3, OQ-A b) ----------
# The reopen2 eleven-host pin leg is DELETED here: instance-side keys are the
# endpoint list now, so the route-truth doctrine relocates to the runbook §6
# table + the --check pair listing + the dispatch smoke (DECISIONS 2026-11-25
# micro-call f — "correct against live, never guess" transfers with them).
# What STAYS repo-pinned: the five globals, byte-exact — this is the ONE
# schema home (the main-sync t13 leg is parse-only permanently).
# The C14 guard sub-leg pins the OQ-A answer (pure discovery, 2026-11-26):
# no membership oracle anywhere. It sweeps the ROSTER for the banned tokens
# (the JSON has no prose, a raw sweep is sound) and the SCRIPT's executable
# code via AST — docstrings and comments may name what the ruling REJECTS
# (discover_targets' own pinned docstring says "categories"); an oracle may
# not be REACHABLE as a key lookup, a roster field, a dict key, a comparison
# operand, or a function argument.
if want t2; then
  [ -f "$ROSTER" ] || fail "t2: $ROSTER missing — the roster globals cannot be pinned"
  if ! python3 - "$ROSTER" "$FANOUT" <<'PY'
import ast, json, re, sys

roster_path, script_path = sys.argv[1], sys.argv[2]
roster = json.load(open(roster_path))


def bad(msg):
    print("FAIL: t2: %s" % msg, file=sys.stderr)
    sys.exit(1)


if set(roster) != {"allowed_refs", "tracked_repo", "settle_seconds",
                   "target_timeout_seconds", "parallel_workers"}:
    bad("top-level keys are %s, expected exactly the FIVE globals (R7: targets[] deleted — the delivered vault map is the endpoint list)" % sorted(roster))
if roster["allowed_refs"] != ["refs/heads/main"]:
    bad("allowed_refs is %r, expected exactly [\"refs/heads/main\"]" % roster["allowed_refs"])
# R1(c): the fleet's live app sources read GitHub; flip ONLY in lockstep
# with the cluster annotations ([P §3] — the skipped-x11 trap). The ONE
# global URL the design still pins repo-side.
if roster["tracked_repo"] != "https://github.com/OwnYourIO/SpencersLab.git":
    bad("tracked_repo is %r, expected the GitHub byte-exact string" % roster["tracked_repo"])
if roster["settle_seconds"] != 10.0 or roster["target_timeout_seconds"] != 60.0:
    bad("tunables settle=%r timeout=%r, expected 10.0 / 60.0 (shipped values; the 20s tightening was rejected)" % (roster["settle_seconds"], roster["target_timeout_seconds"]))
if roster["parallel_workers"] != 4:
    bad("parallel_workers is %r, expected 4 (RESEARCH Implications 6)" % roster["parallel_workers"])

# --- pure-discovery guard (C14 AC1, OQ-A answered b) ----------------------------
raw_roster = open(roster_path).read()
for word in ('categories', 'oracle'):
    if re.search(r'(?i)%s' % word, raw_roster):
        bad('roster carries the banned %r token — no membership concept lives in the five globals (pure discovery is RULED; the declined oracle must not creep back through the JSON)' % word)
src = open(script_path).read()
tree = ast.parse(src)
BANNED = re.compile(r'(?i)categories|oracle')
names, mech = set(), set()
for node in ast.walk(tree):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
        names.add(node.name)
        if isinstance(node, ast.FunctionDef):
            a = node.args
            for arg in list(a.posonlyargs) + list(a.args) + list(a.kwonlyargs):
                names.add(arg.arg)
            if a.vararg:
                names.add(a.vararg.arg)
            if a.kwarg:
                names.add(a.kwarg.arg)
    if isinstance(node, ast.Name):
        names.add(node.id)
    if isinstance(node, ast.Attribute):
        names.add(node.attr)
    if isinstance(node, ast.keyword) and node.arg:
        names.add(node.arg)
    if isinstance(node, ast.Subscript):
        sl = node.slice
        if isinstance(sl, ast.Index):  # py<3.9 shape
            sl = sl.value
        if isinstance(sl, ast.Constant) and isinstance(sl.value, str):
            mech.add(sl.value)
    if isinstance(node, ast.Compare):
        for comp in node.comparators:
            if isinstance(comp, ast.Constant) and isinstance(comp.value, str):
                mech.add(comp.value)
    if isinstance(node, ast.Call):
        f = node.func
        fname = f.attr if isinstance(f, ast.Attribute) else (f.id if isinstance(f, ast.Name) else '')
        if fname in ('get', 'pop', 'setdefault', 'update', 'discard', 'remove', 'add', 'keys'):
            for arg in list(node.args) + [kw.value for kw in node.keywords]:
                if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                    mech.add(arg.value)
    if isinstance(node, ast.Dict):
        for k in node.keys:
            if isinstance(k, ast.Constant) and isinstance(k.value, str):
                mech.add(k.value)
hits = sorted(n for n in names if BANNED.search(n)) + sorted(c for c in mech if BANNED.search(c))
if hits:
    bad('the declined membership oracle is reachable in executable code: %s (pure discovery — identifiers and mechanism strings carry no categories/oracle concept; prose may)' % hits)

# ROSTER_KEYS is the five globals, exactly (the oracle's other possible home).
rk = None
for node in tree.body:
    if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'ROSTER_KEYS' for t in node.targets):
        rk = {e.value for e in node.value.elts}
if rk != {"allowed_refs", "tracked_repo", "settle_seconds", "target_timeout_seconds", "parallel_workers"}:
    bad('ROSTER_KEYS is %s, expected exactly the five globals (C14: roster schema churn ZERO — the six-vs-five question died with the OQ-A answer)' % sorted(rk or []))

# discover_targets serves BOTH channels with one body: one positional
# parameter, no defaults, no kwargs (the drafted `expected=categories`
# oracle hook must stay undelivered).
for node in tree.body:
    if isinstance(node, ast.FunctionDef) and node.name == 'discover_targets':
        a = node.args
        if len(a.args) != 1 or a.defaults or a.kwonlyargs or a.vararg or a.kwarg:
            bad('discover_targets signature changed (%d args, defaults %s) — C14 pins ZERO signature change: the dict-shaped source IS the design' % (len(a.args), a.defaults))
print("ok: t2")
PY
  then
    fail "t2: the roster globals or the pure-discovery guard is violated (reason printed above)"
  fi
  ok "t2: roster is exactly the five globals — refs/allowed_refs + GitHub tracked_repo + shipped tunables; host pins relocated per micro-call f; the OQ-A pure-discovery guard holds (no categories/oracle in the roster or in executable code, ROSTER_KEYS five, discover_targets arity unchanged)"
fi

# --- t3: env discovery, category law, broad-catch (AC5, AC8) ----------------------
if want t3; then
  if ! python3 - "$WORK" <<'PY'
import os, re, sys

sys.path.insert(0, sys.argv[1])
import harness as h

recs = []
stub = h.StubArgo("all", recs)
stub2 = h.StubArgo("ai", recs, apps=[h.app("gpu-ai", h.REPO, "main", "OutOfSync")])
stub.start(); stub2.start()
try:
    roster = h.make_globals(os.path.join(sys.argv[1], "t3"))

    # (a) happy discovery incl. the underscore→hyphen law (GPU_AI -> gpu-ai,
    # PROXY_REMOTE -> proxy-remote): --check prints the derived table.
    pairs = {"dev": {"url": stub.url, "token": h.token_for("dev")},
             "gpu-ai": {"url": stub2.url, "token": h.token_for("gpu-ai")},
             "proxy-remote": {"url": stub.url, "token": h.token_for("proxy-remote")}}
    rc, out, err = h.run("t3a", "--check", pairs=pairs, config=roster)
    blob = out + err
    if rc != 0:
        h.bad("t3: happy discovery --check exited %s (env pairs must BE the input now):\n%s" % (rc, blob[:600]))
    if "argocd-fanout --check: OK" not in blob:
        h.bad("t3: no OK line:\n%s" % blob[:400])
    for cat in ("dev", "gpu-ai", "proxy-remote"):
        if cat not in blob:
            h.bad("t3: table has no row for category %r — upper-snake env names must derive hyphen categories (GPU_AI→gpu-ai): %s" % (cat, blob[:500]))
    if "gpu_ai" in blob:
        h.bad("t3: an underscore category leaked into the table — the category law maps _ to - (audit grammar and org keys must agree)")
    if stub.url not in blob or stub2.url not in blob:
        h.bad("t3: --check table does not print the DISCOVERED env URLs (the pairs are the endpoint list now)")
    if not re.search(r"(?m)^pairs: 3 targets discovered \(values never printed\)", blob):
        h.bad("t3: the pinned single-line `pairs: N targets discovered (values never printed)` phrase is missing (plan --check contract):\n%s" % blob[:500])
    if recs:
        h.bad("t3: --check opened sockets — %d requests landed (zero-network law survives R7)" % len(recs))
    if h.STEM in blob:
        h.bad("t3: --check echoes token material (AC8)")

    # (b) BROAD-CATCH: a typo'd enumeration row with a NON-EMPTY value must
    # go RED naming the RAW KEY — silently ignoring it re-opens the
    # silent-cluster-loss class the config-red posture exists for.
    for tag, key in (("lower", "ARGOCD_SYNC_gpu2_URL"),
                     ("dot", "ARGOCD_SYNC_A.B_TOKEN"),
                     ("double-underscore", "ARGOCD_SYNC_GPU__URL"),
                     ("leading-underscore", "ARGOCD_SYNC__DEV_TOKEN")):
        rc, out, err = h.run("t3b-%s" % tag, "--check",
                             pairs={"dev": {"url": stub.url, "token": h.token_for("dev")}},
                             raw_env={key: stub.url}, config=roster)
        blob = out + err
        if rc != 1:
            h.bad("t3[%s]: malformed env key %r with a value exited %s, expected 1 (broad-catch strict-validate, DECISIONS (c))" % (tag, key, rc))
        if key not in blob:
            h.bad("t3[%s]: the RED does not name the raw key %r — operators cannot find the typo'd row otherwise:\n%s" % (tag, key, blob[:400]))
        if h.STEM in blob:
            h.bad("t3[%s]: token material echoed (AC8)" % tag)

    # (c) malformed-but-EMPTY residue is ignored (an unattempted row).
    rc, out, err = h.run("t3c", "--check",
                         pairs={"dev": {"url": stub.url, "token": h.token_for("dev")}},
                         raw_env={"ARGOCD_SYNC_gpu2_URL": "", "ARGOCD_SYNC_A.B_TOKEN": ""},
                         config=roster)
    blob = out + err
    if rc != 0 or "argocd-fanout --check: OK" not in blob:
        h.bad("t3: empty malformed residue must be IGNORED (rc %s):\n%s" % (rc, blob[:400]))
    if "pairs: 1 targets discovered" not in blob:
        h.bad("t3: empty malformed residue changed the discovered count:\n%s" % blob[:400])
    if "gpu2" in blob or "A.B" in blob:
        h.bad("t3: ignored empty keys were echoed anyway:\n%s" % blob[:400])

    # (d) the dead blob name is ignored BY CONSTRUCTION and never echoed.
    rc, out, err = h.run("t3d", "--check",
                         pairs={"dev": {"url": stub.url, "token": h.token_for("dev")}},
                         blob="dev:%s\nZQ:%s" % (h.token_for("dev"), h.token_for("gpu")),
                         config=roster)
    blob = out + err
    if rc != 0 or "pairs: 1 targets discovered" not in blob:
        h.bad("t3: ARGOCD_SYNC_TOKENS must match nothing and change nothing (rc %s):\n%s" % (rc, blob[:400]))
    if "ARGOCD_SYNC_TOKENS" in blob:
        h.bad("t3: the dead blob KEY NAME was echoed — ignored names stay silent (AC5)")
    if h.STEM in blob:
        h.bad("t3: blob junk echoed (AC8)")

    # (e) URL trailing-slash normalization: the discovered URL is dialed
    # byte-clean (rstrip('/') ported to the env path).
    live = h.make_globals(os.path.join(sys.argv[1], "t3e"))
    rc, out, err = h.run("t3e", "--ref", "refs/heads/main",
                         pairs={"dev": {"url": stub.url + "/", "token": h.token_for("dev")}},
                         config=live)
    if rc != 0:
        h.bad("t3: trailing-slash run exited %s\n%s" % (rc, (out + err)[:400]))
    paths = [r["path"] for r in recs if r["stub"] == "all"]
    if any("//" in p for p in paths):
        h.bad("t3: a double-slash path landed (%s) — the rstrip('/') normalization must apply to ENV URLs (stub URL was built without a trailing slash, so the slash came from the pair)" % paths)
finally:
    stub.stop(); stub2.stop()

print("ok: t3 — GPU_AI/PROXY_REMOTE pairs discover to hyphen categories with the pinned pairs-line check output and zero sockets; four malformed-key shapes with values go RED naming the raw key; empty malformed residue and the dead blob name are ignored and unechoed; env URLs normalize the trailing slash (AC5, AC8)")
PY
  then
    fail "t3: the discovery contract is violated (reason printed above)"
  fi
  ok "t3: discovery + category law + broad-catch matrix hold (AC5/AC8)"
fi

# --- t4: pair-integrity aggregation + preserved roster guards (AC4, AC11) --------
if want t4; then
  if ! python3 - "$WORK" <<'PY'
import json, os, re, sys

sys.path.insert(0, sys.argv[1])
import harness as h

recs = []
stub = h.StubArgo("probe", recs, apps=[h.app("dev", h.REPO, "main", "OutOfSync")])
stub.start()
try:
    roster = h.make_globals(os.path.join(sys.argv[1], "t4"))
    HEALTHY = {"dev": {"url": stub.url, "token": h.token_for("dev")}}

    def grow(spec):
        p = dict(HEALTHY)
        p["grow"] = spec
        return p

    def check(tag, rc, out, err, pat, no_echo=()):
        blob = out + err
        if rc != 1:
            h.bad("t4[%s]: exit %s, expected 1 — pair-integrity/config errors are the ruled RED lane (token-side configured predicate; a residue beside a live fleet must never warn-green a half-sync)" % (tag, rc))
        if not any(re.search(pat, ln) for ln in err.splitlines()):
            h.bad("t4[%s]: stderr lacks the pinned shape (%r):\n%s" % (tag, pat, err[:400]))
        if h.STEM in blob:
            h.bad("t4[%s]: output echoes vault token material (AC8: messages name categories and fields, never values)" % tag)
        for v in no_echo:
            if v in blob:
                h.bad("t4[%s]: output echoes the offending value %r (AC8: never values)" % (tag, v))

    # Per-violation pinned phrases, one arm each (DECISIONS (b): collected,
    # one aggregated line; these arms have the healthy dev pair so the lane
    # is CONFIGURED and integrity RED fires, not the kill lane).
    arms = [
        ("url-without-token", grow({"url": stub.url}),
         r'argocd-fanout config:.*category "grow" missing TOKEN value'),
        ("token-without-url", grow({"token": h.token_for("grow")}),
         r'argocd-fanout config:.*category "grow" missing URL value'),
        ("empty-token-residue", grow({"url": stub.url, "token": ""}),
         r'argocd-fanout config:.*category "grow" missing TOKEN value'),
        ("empty-url-residue", grow({"url": "", "token": h.token_for("grow")}),
         r'argocd-fanout config:.*category "grow" missing URL value'),
        ("non-jwt-token", grow({"url": stub.url, "token": "plain-secret-not-a-jwt"}),
         r'argocd-fanout config:.*category "grow" token is not JWT-shaped',
         ("plain-secret-not-a-jwt",)),
        ("bad-scheme-url", grow({"url": "cluster.grow.lan", "token": h.token_for("grow")}),
         r'argocd-fanout config:.*category "grow" URL must start with http\(s\)://'),
        ("userinfo-url", grow({"url": "https://user:pw@cluster.grow.lan", "token": h.token_for("grow")}),
         r'argocd-fanout config:.*category "grow"'),
        ("query-url", grow({"url": "https://cluster.grow.lan?redirect=1", "token": h.token_for("grow")}),
         r'argocd-fanout config:.*category "grow"'),
        # Ruling (j): a double-empty ENUMERATED row in a CONFIGURED fleet is
        # RED, not unattempted-green — a fleet that is configured must
        # account for every row (a key-only org delete whose workflow row
        # survives must not fan out silent). Landed C09 skips these rows,
        # so this arm is the designed-red carrier for C12.
        ("both-empty-row", grow({"url": "", "token": ""}),
         r'argocd-fanout config:.*category .grow. enumerated but both values empty'),
    ]
    for arm in arms:
        tag, pairs, pat = arm[0], arm[1], arm[2]
        no_echo = arm[3] if len(arm) > 3 else ()
        rc, out, err = h.run("t4-%s" % tag, "--ref", "refs/heads/main",
                             pairs=pairs, config=roster)
        check(tag, rc, out, err, pat, no_echo)

    # AGGREGATION (DECISIONS (b)): several broken categories at once ⇒ ONE
    # `argocd-fanout config:` line listing them SORTED (first-error-raise
    # would hide half a broken fleet behind one push's red).
    p = dict(HEALTHY)
    p["grow"] = {"token": h.token_for("grow")}                  # missing URL
    p["media"] = {"url": stub.url, "token": "not-jwt-ZQZQ"}    # non-JWT
    p["infra"] = {"url": "", "token": h.token_for("infra")}    # missing URL
    rc, out, err = h.run("t4-aggregate", "--ref", "refs/heads/main",
                         pairs=p, config=roster)
    cfg_lines = [ln for ln in err.splitlines() if ln.startswith("argocd-fanout config:")]
    if rc != 1:
        h.bad("t4[aggregate]: exit %s, expected 1" % rc)
    if len(cfg_lines) != 1:
        h.bad("t4[aggregate]: %d `argocd-fanout config:` lines, expected ONE aggregated line (DECISIONS (b)):\n%s" % (len(cfg_lines), err[:400]))
    line = cfg_lines[0] if cfg_lines else ""
    idx = [(cat, line.find('"%s"' % cat)) for cat in ("grow", "infra", "media")]
    if any(pos < 0 for _, pos in idx):
        h.bad("t4[aggregate]: the single line must name every broken category: %r" % line[:300])
    if [pos for _, pos in idx] != sorted(pos for _, pos in idx):
        h.bad("t4[aggregate]: categories must be listed SORTED (grow, infra, media), got %r" % line[:300])
    if h.STEM in line:
        h.bad("t4[aggregate]: the aggregated line echoes token material (AC8)")

    # Ruling (j) mixed aggregate: ONE both-empty row AND one one-sided row ⇒
    # the SAME single line names both, sorted (the both-empty phrase and the
    # one-sided phrase coexist in one aggregated RED).
    p = dict(HEALTHY)
    p["grow"] = {"url": "", "token": ""}                 # both-empty row
    p["infra"] = {"token": h.token_for("infra")}         # one-sided residue
    rc, out, err = h.run("t4-j-mixed", "--ref", "refs/heads/main",
                         pairs=p, config=roster)
    cfg_lines = [ln for ln in err.splitlines() if ln.startswith("argocd-fanout config:")]
    if rc != 1 or len(cfg_lines) != 1:
        h.bad("t4[j-mixed]: exit %s / %d config lines, expected 1/1 — (j) folds the both-empty row into the existing ONE-line aggregation" % (rc, len(cfg_lines)))
    line = cfg_lines[0] if cfg_lines else ""
    mg = re.search(r'category .grow. enumerated but both values empty', line)
    mi = re.search(r'category .infra. missing URL value', line)
    if not (mg and mi):
        h.bad("t4[j-mixed]: the single line must carry BOTH the (j) phrase for grow and the one-sided phrase for infra: %r" % line[:300])
    if mg and mi and mg.start() >= mi.start():
        h.bad("t4[j-mixed]: categories must sort (grow before infra): %r" % line[:300])
    if h.STEM in line:
        h.bad("t4[j-mixed]: aggregated line echoes token material (AC8)")

    # §7 partial-kill scenario per (j): the whole-fleet lever (all tokens
    # blank ⇒ kill-lane green, t5) is different from KILLING FEWER THAN ALL:
    # one survivor configures the fleet and every blanked/deleted row —
    # one-sided OR both-empty — aggregates into ONE sorted RED naming them.
    p = {"dev": {"url": stub.url, "token": h.token_for("dev")}}   # the survivor
    p["media"] = {"url": stub.url}                                  # token deleted
    p["grow"] = {"url": "", "token": ""}                            # pair deleted, row survives
    p["proxy-backup"] = {"url": "", "token": h.token_for("proxy-backup")}  # url deleted, token kept
    rc, out, err = h.run("t4-j-levermix", "--ref", "refs/heads/main",
                         pairs=p, config=roster)
    cfg_lines = [ln for ln in err.splitlines() if ln.startswith("argocd-fanout config:")]
    if rc != 1 or len(cfg_lines) != 1:
        h.bad("t4[j-levermix]: partial §7 kill must be ONE aggregated RED (exit %s, %d lines):\n%s" % (rc, len(cfg_lines), (out + err)[:400]))
    line = cfg_lines[0] if cfg_lines else ""
    pos = {}
    for cat, rx in (("media", r'media. missing TOKEN value'),
                    ("grow", r'grow. enumerated but both values empty'),
                    ("proxy-backup", r'proxy-backup. missing URL value')):
        m = re.search(rx, line)
        if not m:
            h.bad("t4[j-levermix]: line must carry the %s phrase for %s (ruling (j) mixes one-sided and both-empty classes): %r" % (rx, cat, line[:300]))
        pos[cat] = m.start()
    if not (pos["grow"] < pos["media"] < pos["proxy-backup"]):
        h.bad("t4[j-levermix]: aggregate must sort (grow, media, proxy-backup): %r" % pos)
    if h.STEM in line:
        h.bad("t4[j-levermix]: token material echoed (AC8)")

    # The --check mode enforces the SAME integrity matrix (AC7 tail).
    rc, out, err = h.run("t4-check-integrity", "--check",
                         pairs=grow({"url": stub.url}), config=roster)
    check("check/integrity", rc, out, err,
          r'argocd-fanout config:.*category "grow" missing TOKEN value')
    # (j) must hold in --check too (it validates the fleet fully).
    rc, out, err = h.run("t4-check-bothempty", "--check",
                         pairs=grow({"url": "", "token": ""}), config=roster)
    check("check/both-empty", rc, out, err,
          r'argocd-fanout config:.*category .grow. enumerated but both values empty')

    # AC11: the preserved roster guards (the reopen2 review-round family —
    # allowed_refs/tunables/roster-shape semantics survive R7 UNCHANGED).
    def roster_copy(mutate, tag):
        cfg = json.load(open(roster))
        mutate(cfg)
        path = os.path.join(sys.argv[1], "t4-%s.json" % tag)
        with open(path, "w") as f:
            json.dump(cfg, f)
        return path

    guards = [
        ("empty-refs", lambda c: c.update(allowed_refs=[]), r'argocd-fanout config:.*allowed_refs'),
        ("tags-ref", lambda c: c.update(allowed_refs=["refs/heads/main", "refs/tags/v1"]), r'argocd-fanout config:'),
        ("short-ref", lambda c: c.update(allowed_refs=["main"]), r'argocd-fanout config:'),
        ("extra-keys", lambda c: c.update(clusterHosts={"dev": "x"}), r'argocd-fanout config:.*clusterHosts'),
        ("inf-settle", lambda c: c.update(settle_seconds=float("inf")), r'argocd-fanout config:.*settle_seconds'),
        ("nan-timeout", lambda c: c.update(target_timeout_seconds=float("nan")), r'argocd-fanout config:.*target_timeout_seconds'),
        ("frac-workers", lambda c: c.update(parallel_workers=4.5), r'argocd-fanout config:.*parallel_workers'),
    ]
    for tag, mutate, pat in guards:
        cfg = roster_copy(mutate, tag)
        rc, out, err = h.run("t4-%s" % tag, "--ref", "refs/heads/main",
                             pairs=HEALTHY, config=cfg)
        check(tag, rc, out, err, pat)

    # Malformed roster files.
    bad_json = os.path.join(sys.argv[1], "t4-bad.json")
    open(bad_json, "w").write("{ not valid json ]")
    rc, out, err = h.run("t4-bad-json", "--ref", "refs/heads/main",
                         pairs=HEALTHY, config=bad_json)
    check("bad-json", rc, out, err, r'argocd-fanout config:')
    rc, out, err = h.run("t4-unreadable", "--ref", "refs/heads/main",
                         pairs=HEALTHY, config=os.path.join(sys.argv[1], "t4-absent.json"))
    check("unreadable-file", rc, out, err, r'argocd-fanout config:')

    if recs:
        h.bad("t4: %d stub requests landed despite every arm being a config error — validation must fail closed BEFORE the network (a dialed-anyway arm can half-sync)" % len(recs))
finally:
    stub.stop()

print("ok: t4 — every pair-integrity violation (eight one-sided/scheme shapes + the ruling-(j) both-empty class) exits 1 naming its category with the pinned phrases (values never echoed); both-empty+one-sided and the §7 partial-kill mix aggregate into ONE sorted line; --check enforces the same matrix, and the preserved roster guards (refs/tunables/schema) stay red (AC4, AC11, ruling (j))")
PY
  then
    fail "t4: the pair-integrity/guards contract is violated (reason printed above)"
  fi
  ok "t4: aggregated pair-integrity RED incl. the ruling-(j) both-empty class + preserved roster guards + zero-dial/zero-echo (AC4/AC11/(j))"
fi

# --- t5: kill lane (3 arms) + happy fan-out ordering + ref gate (AC6, AC9) --------
if want t5; then
  if ! python3 - "$WORK" <<'PY'
import os, sys

sys.path.insert(0, sys.argv[1])
import harness as h

recs = []
stub = h.StubArgo("all", recs)
stub.start()
try:
    roster = h.make_globals(os.path.join(sys.argv[1], "t5"))

    # Kill-lane arms (AC6): the TOKEN-side predicate decides; URLs populated
    # or not, keys absent, or all-empty strings — three arms — ⇒ pinned
    # column-0 warning, exit 0, ZERO sockets, no table, no summary.
    # Kill-lane arms (AC6 + the ruling-(j) boundary proofs): the TOKEN-side
    # predicate decides; (j) fires ONLY when OTHER clusters are configured,
    # so both-empty rows in an all-empty fleet must STILL warn-green —
    # the paste-pending state and the whole-fleet §7 lever survive.
    kill_arms = [
        ("keys-absent", {}),
        ("urls-populated", {"dev": {"url": stub.url}, "gpu": {"url": stub.url}}),
        ("all-empty", {"dev": {"url": stub.url, "token": ""}, "gpu": {"token": ""}}),
        ("empty-malformed-residue", {"dev": {"url": stub.url, "token": ""}}),
        ("all-rows-both-empty", {"dev": {"url": "", "token": ""}, "gpu": {"url": "", "token": ""}}),
        ("zero-tokens-one-bothempty", {"dev": {"url": "", "token": ""}, "gpu": {"url": stub.url}}),
    ]
    for tag, pairs in kill_arms:
        rc, out, err = h.run("t5-kill-%s" % tag, "--ref", "refs/heads/main",
                             pairs=pairs, config=roster)
        if rc != 0:
            h.bad("t5[kill/%s]: an unconfigured fleet is a designed GREEN skip, got exit %s\n%s" % (tag, rc, (out + err)[:400]))
        if recs:
            h.bad("t5[kill/%s]: %d stub requests landed on the kill lane (zero-socket law)" % (tag, len(recs)))
        if h.WARN_KILL not in out:
            h.bad("t5[kill/%s]: the pinned column-0 warning is absent (DECISIONS micro-call a, byte-exact):\n%s" % (tag, (out + err)[:400]))
        wl = [ln for ln in out.splitlines() if "::warning::" in ln]
        if len(wl) != 1 or not wl[0].startswith("::warning::sync-fanout not configured"):
            h.bad("t5[kill/%s]: the warning must be EXACTLY one column-0 line (m1 lesson applies to this new lane too): %r" % (tag, wl))
        if out.count(h.WARN_KILL) != 1:
            h.bad("t5[kill/%s]: the pinned warning appears %d times, expected once" % (tag, out.count(h.WARN_KILL)))
        # "no other stdout" (AC6): the kill lane prints ONLY the warning.
        extra = [ln for ln in out.splitlines() if ln.strip() and ln.strip() != h.WARN_KILL]
        if extra:
            h.bad("t5[kill/%s]: kill-lane stdout carries %r beyond the warning (AC6: no table, no summary, no ref-gate line)" % (tag, extra[:3]))
        if "fan-out summary" in out + err or "target=" in out + err:
            h.bad("t5[kill/%s]: a summary/audit line on the kill lane — the skip returns BEFORE any fan-out shape" % tag)
        if "not in allowed_refs" in out + err:
            h.bad("t5[kill/%s]: the unconfigured fleet also printed the REF-GATE line — the kill signal returns before the gate (C09 main task)" % tag)
finally:
    stub.stop()

# ---- happy fan-out + ref gate: the CORE legs, run_core across eras ----
recs2 = []
dev = h.StubArgo("dev", recs2, apps=[
    h.app("dev", h.REPO, "main", "OutOfSync", multi=True),  # roots are multi-source
    h.app("dev-app1", h.REPO, "main", "OutOfSync"),         # -> sync
    h.app("dev-synced", h.REPO, "main", "Synced"),          # -> leave
    h.app("dev-wrongrev", h.REPO, "stage", "OutOfSync"),    # -> leave (live targetRevision)
    h.app("dev-wrongrepo", h.OTHER_REPO, "main", "OutOfSync"),  # -> leave (byte repoURL)
    h.app("dev-multi", h.REPO, "main", "Unknown", multi=True),  # sources-shape child -> sync
])
media = h.StubArgo("media", recs2, apps=[h.app("media", h.REPO, "main", "OutOfSync")])
grow = h.StubArgo("grow", recs2, apps=[h.app("grow-child", h.REPO, "main", "OutOfSync")])  # root absent -> skipped
for s in (dev, media, grow):
    s.start()
try:
    roster2 = h.make_globals(os.path.join(sys.argv[1], "t5core"), settle_seconds=0.3)
    urls = {"dev": dev.url, "media": media.url, "grow": grow.url}
    rc, out, err = h.run_core("t5-happy", "--ref", "refs/heads/main", urls=urls, config=roster2)
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

    d_first, d_last = min(r["ts"] for r in dev.calls()), max(r["ts"] for r in dev.calls())
    m_first, m_last = min(r["ts"] for r in media.calls()), max(r["ts"] for r in media.calls())
    if not (d_first < m_last and m_first < d_last):
        h.bad("t5: dev and media request windows do not overlap (%.3f..%.3f vs %.3f..%.3f) — the fan-out must run targets concurrently, plan contract parallel_workers 4" % (d_first, d_last, m_first, m_last))

    # Ref gate (C09 map folds it into t5; assertions ported unchanged):
    pre_gate = len(recs2)
    rc, out, err = h.run_core("t5-refgate", "--ref", "refs/heads/other",
                              urls={"dev": dev.url}, config=roster2)
    blob = out + err
    if rc != 0:
        h.bad("t5: a non-allowed ref is a designed no-op, not an error — exit %s\n%s" % (rc, blob[:400]))
    if len(recs2) != pre_gate:
        h.bad("t5: %d stub requests landed for a ref outside allowed_refs (AC9: ZERO API calls — the gate is the OQ7 widening guarantee)" % (len(recs2) - pre_gate))
    if "refs/heads/other" not in blob:
        h.bad("t5: the skip is silent — the one log line must name the ref (AC9: gate line unchanged)")
    if h.summary(blob):
        h.bad("t5: the ref gate emitted a fan-out summary — no fan-out ran; the ref-gate path is the one line + exit 0")
    if len(h.audits(blob)) != 0:
        h.bad("t5: the ref gate emitted per-target audit lines (one log line, not audits)")
finally:
    for s in (dev, media, grow):
        s.stop()

print("ok: t5: six kill-lane arms (incl. the ruling-(j) boundary: all-rows-both-empty and zero-tokens-with-one-bothempty stay WARN-GREEN — (j) only fires when OTHER clusters are configured) print ONLY the pinned column-0 warning, exit 0, dial zero sockets and skip the ref-gate line; the core fan-out keeps root->settle->re-list->children order, ThreadPool overlap, the child filters, pinned details and summary math; the ref gate stays a one-line green no-op (AC6, AC9, ruling (j))")
PY
  then
    fail "t5: the kill-lane / happy-shape / ref-gate contract is violated (reason printed above)"
  fi
  ok "t5: kill lane (6 arms incl. the ruling-(j) boundaries) + core ordering + ref gate hold (AC6/AC9/(j))"
fi

# --- t6: channel precedence (C14 AC3/AC7 — designed-red until the channel lands) --
# The pinned rule (DECISIONS 2026-11-26 (d)): set-and-non-empty PAIRS_FILE
# wins OVER THE ENV SCAN ENTIRELY — a broken or partial file never falls
# back to env; unset or empty-string PAIRS_FILE keeps the env scan
# BYTE-IDENTICAL (the local/manual posture, every existing arm).
if want t6; then
  if ! python3 - "$WORK" <<'PY'
import os, sys

sys.path.insert(0, sys.argv[1])
import harness as h

recs = []
dev = h.StubArgo("dev", recs, apps=[h.app("dev", h.REPO, "main", "OutOfSync")])
ai = h.StubArgo("ai", recs, apps=[h.app("gpu-ai", h.REPO, "main", "OutOfSync")])
for s in (dev, ai):
    s.start()
try:
    roster = h.make_globals(os.path.join(sys.argv[1], "t6"))

    # (a) FILE WINS: env carries the canonical dev pair PLUS a 12th
    # complete zeta pair; the file carries dev only. Discovery must be the
    # file's fleet — zeta NEVER appears (no merge, no env leak).
    env_pairs = {"dev": {"url": dev.url, "token": h.token_for("dev")},
                 "zeta": {"url": dev.url, "token": h.token_for("zeta")}}
    mapping = h.file_pairs({"dev": {"url": dev.url, "token": h.token_for("dev")}})
    path = h.write_pairs("t6a", mapping)
    rc, out, err = h.run("t6a", "--check", pairs=env_pairs, config=roster, pairs_file=path)
    blob = out + err
    if rc != 0:
        h.bad("t6[a]: the file-channel run exited %s\n%s" % (rc, blob[:400]))
    if "zeta" in blob:
        h.bad("t6[a]: the env-channel 12th pair leaked into a file-channel run — set-and-non-empty PAIRS_FILE skips the env scan ENTIRELY (C14 AC3): %s" % blob[:400])
    if "pairs: 1 targets discovered" not in blob:
        h.bad("t6[a]: discovered count is not the FILE's fleet (expected pairs: 1):\n%s" % blob[:400])

    # (b) file {} beats a fully-configured env: the file wins, the {} IS
    # the all-absent result ⇒ kill lane, not an env fallback.
    path_b = h.write_pairs("t6b", {})
    rc, out, err = h.run("t6b", "--check", pairs=env_pairs, config=roster, pairs_file=path_b)
    blob = out + err
    if rc != 0 or h.WARN_KILL not in blob:
        h.bad("t6[b]: {} file beside a configured env must warn-green (file wins, all-absent), rc %s:\n%s" % (rc, blob[:400]))
    if "--check: OK" in blob:
        h.bad("t6[b]: the {}-file run printed the env fleet's table — precedence inverted (file must skip the env scan):\n%s" % blob[:400])
    if recs:
        h.bad("t6[b]: %d sockets on a kill-lane run" % len(recs))

    # (c) UNSET ⇒ env scan byte-identical (preservation leg, green today):
    # no PAIRS_FILE anywhere; the canonical env arms behave as t3/t5 pin.
    rc, out, err = h.run("t6c", "--check",
                         pairs={"dev": {"url": dev.url, "token": h.token_for("dev")},
                                "gpu-ai": {"url": ai.url, "token": h.token_for("gpu-ai")}},
                         config=roster)
    blob = out + err
    if rc != 0 or "pairs: 2 targets discovered" not in blob:
        h.bad("t6[c]: PAIRS_FILE unset must leave the env scan exactly as landed, rc %s:\n%s" % (rc, blob[:400]))

    # (d) EMPTY STRING ⇒ treated unset (micro-call: ARGOCD_PAIRS_FILE="" is
    # the unset posture, not a path). Preservation leg, green today.
    rc, out, err = h.run("t6d", "--check",
                         pairs={"dev": {"url": dev.url, "token": h.token_for("dev")}},
                         raw_env={"ARGOCD_PAIRS_FILE": ""}, config=roster)
    blob = out + err
    if rc != 0 or "pairs: 1 targets discovered" not in blob or "config:" in blob:
        h.bad("t6[d]: PAIRS_FILE=\"\" must scan the env exactly as landed (never RED on an empty path), rc %s:\n%s" % (rc, blob[:400]))
finally:
    for s in (dev, ai):
        s.stop()

print("ok: t6: file wins ENTIRELY (12th env pair never appears; {} file warn-greens a configured env); PAIRS_FILE unset/empty-string keeps the env scan byte-identical (C14 AC3/AC7)")
PY
  then
    fail "t6: the channel-precedence contract is violated (reason printed above)"
  fi
  ok "t6: precedence pinned — file-wins-entirely + env-scan preservation (AC3/AC7; red until C14 lands)"
fi

# --- t7: file error lane (C14 AC4 — path-named REDs, never values) -----------------
# load_pairs_file failures are config RED naming the PATH (+ reason) with
# ZERO values in the line; the {} file is NOT an error — it is the all-absent
# discovery result ⇒ the pinned WARN_NOT_CONFIGURED green lane, unchanged
# string (DECISIONS (e)). The env scan must NOT rescue a broken file (each
# red arm carries a valid env pair beside it — the file wins even broken).
if want t7; then
  if ! python3 - "$WORK" <<'PY'
import json, os, sys

sys.path.insert(0, sys.argv[1])
import harness as h

recs = []
dev = h.StubArgo("dev", recs, apps=[h.app("dev", h.REPO, "main", "OutOfSync")])
dev.start()
try:
    roster = h.make_globals(os.path.join(sys.argv[1], "t7"))
    env_valid = {"dev": {"url": dev.url, "token": h.token_for("dev")}}

    def err_arm(tag, path):
        rc, out, err = h.run("t7-%s" % tag, "--ref", "refs/heads/main",
                             pairs=env_valid, config=roster, pairs_file=path)
        blob = out + err
        if rc != 1:
            h.bad("t7[%s]: exit %s, expected 1 — a set-and-non-empty PAIRS_FILE that cannot load is config RED, never an env fallback or a silent kill-lane (C14 AC4):\n%s" % (tag, rc, blob[:400]))
        cfg = [ln for ln in err.splitlines() if ln.startswith("argocd-fanout config:")]
        if not cfg:
            h.bad("t7[%s]: no `argocd-fanout config:` line on stderr:\n%s" % (tag, blob[:400]))
        if os.path.basename(path) not in blob:
            h.bad("t7[%s]: the RED must name the pairs-file PATH (%r) — operators find the bad producer by path:\n%s" % (tag, os.path.basename(path), blob[:400]))
        if h.STEM in blob:
            h.bad("t7[%s]: the RED echoes token material (AC8: path + reason only)" % tag)
        if recs:
            h.bad("t7[%s]: %d sockets — file errors fail closed BEFORE the fan-out" % (tag, len(recs)))
        return blob

    d = os.path.join(sys.argv[1], "t7")
    os.makedirs(d, exist_ok=True)

    err_arm("missing", os.path.join(d, "absent-pairs.json"))
    err_arm("unreadable", d)  # a directory: OSError under every uid (chmod 000 would not bite as root)
    err_arm("bad-json", h.write_pairs("t7-badjson", None, dirpath=d, raw="{ not valid json ]"))
    err_arm("non-dict", h.write_pairs("t7-nondict", None, dirpath=d, raw="[1, 2]"))
    blob = err_arm("non-string", h.write_pairs("t7-nonstring", {"ARGOCD_SYNC_DEV_URL": 42}, dirpath=d))
    if "42" in blob:
        h.bad("t7[non-string]: the offending non-string VALUE was echoed — messages name the path and the reason, never values (AC4): %r" % blob[:300])

    # (f) {} file: the ALL-ABSENT discovery result — pinned warn-green,
    # exit 0, zero sockets, no table, no summary (the unchanged string is
    # WARN_KILL; ruling (e) verified still-true in the blob world).
    path_empty = h.write_pairs("t7-empty", {}, dirpath=d)
    rc, out, err = h.run("t7-empty-object", "--ref", "refs/heads/main", config=roster, pairs_file=path_empty)
    blob = out + err
    if rc != 0:
        h.bad("t7[{}]: the empty-object file must be the GREEN kill lane, got exit %s (mislabeled RED? — C14 AC4 pins {} as all-absent, not an error):\n%s" % (rc, blob[:400]))
    if h.WARN_KILL not in out:
        h.bad("t7[{}]: the {}-file lane must print the EXACT pinned warning, unchanged:\n%s" % (blob[:400],))
    if "argocd-fanout config:" in blob or "--check: OK" in blob:
        h.bad("t7[{}]: the {}-file lane printed an error or a table — {} means zero delivered keys:\n%s" % (blob[:400],))
    if recs:
        h.bad("t7[{}]: %d sockets on the all-absent lane" % len(recs))
finally:
    dev.stop()

print("ok: t7: missing/unreadable/invalid-JSON/non-dict/non-string-values each exit 1 naming the path with zero values echoed and zero sockets; the {} file is the unchanged WARN_NOT_CONFIGURED green lane (C14 AC4)")
PY
  then
    fail "t7: the file error lane is violated (reason printed above)"
  fi
  ok "t7: path-named error arms + {}-is-all-absent green lane hold (AC4; red until C14 lands)"
fi

# --- t8: discovery parity through the file channel (C14 AC5) -----------------------
# The same validator body serves both sources (DECISIONS (a)): for identical
# NAME->value content the file channel must reproduce the env channel
# bit-for-bit — rc and full output. The matrix replays t3/t4's classes
# through pairs files: half-pair RED, blanked-both (j) RED, JWT checks,
# malformed-with-value preemption, aggregation sorted, all-blank lever,
# the dead blob name ignored — and no value ever printed from file content.
if want t8; then
  if ! python3 - "$WORK" <<'PY'
import os, re, sys

sys.path.insert(0, sys.argv[1])
import harness as h

recs = []
stub = h.StubArgo("parity", recs, apps=[h.app("dev", h.REPO, "main", "OutOfSync")])
stub.start()
try:
    roster = h.make_globals(os.path.join(sys.argv[1], "t8"))
    T = h.token_for

    def mapping(spec):
        """{cat: (url, token)} with None/"" semantics in the flat NAME map."""
        doc = {}
        for cat, (u, tk) in spec.items():
            if u is not None:
                doc[h.url_key(cat)] = u
            if tk is not None:
                doc[h.token_key(cat)] = tk
        return doc

    # Extra raw NAME->value entries (malformed shapes, the dead blob name)
    # join the flat map verbatim — the file namespace IS the env namespace.
    def with_raw(spec, raw):
        doc = mapping(spec)
        doc.update(raw)
        return doc

    DEV = {"dev": (stub.url, T("dev"))}
    ARMS = [
        ("happy", mapping({"dev": (stub.url, T("dev")),
                           "gpu-ai": (stub.url, T("gpu-ai"))}),
         0, r"pairs: 2 targets discovered", None),
        ("half-missing-token", mapping({"dev": (stub.url, T("dev")),
                                        "grow": (stub.url, None)}),
         1, r'argocd-fanout config:.*category "grow" missing TOKEN value', None),
        ("half-missing-url", mapping({"dev": (stub.url, T("dev")),
                                      "grow": (None, T("grow"))}),
         1, r'argocd-fanout config:.*category "grow" missing URL value', None),
        ("blanked-both-j", mapping({"dev": (stub.url, T("dev")),
                                    "grow": ("", "")}),
         1, r'argocd-fanout config:.*category .grow. enumerated but both values empty', None),
        ("non-jwt", mapping({"dev": (stub.url, T("dev")),
                             "grow": (stub.url, "plain-secret-not-a-jwt")}),
         1, r'token is not JWT-shaped', ("plain-secret-not-a-jwt",)),
        ("bad-scheme", mapping({"dev": (stub.url, T("dev")),
                                "grow": ("cluster.grow.lan", T("grow"))}),
         1, r'URL must start with http\(s\)://', None),
        ("userinfo-url", mapping({"dev": (stub.url, T("dev")),
                                  "grow": ("https://user:pw@cluster.grow.lan", T("grow"))}),
         1, r'category "grow"', None),
        ("aggregate-sorted", mapping({"dev": (stub.url, T("dev")),
                                      "grow": (None, T("grow")),
                                      "media": (stub.url, "not-jwt-ZQZQ"),
                                      "infra": ("", "")}),
         1, r'argocd-fanout config:', None, "SORTED"),
        ("malformed-with-value", with_raw(DEV, {"ARGOCD_SYNC_GPU__URL": stub.url}),
         1, r'malformed ARGOCD_SYNC_\* enumeration keys with values: ARGOCD_SYNC_GPU__URL', None),
        ("malformed-empty-ignored", with_raw(DEV, {"ARGOCD_SYNC_gpu2_URL": ""}),
         0, r"pairs: 1 targets discovered", None),
        ("unshapeable-ignored", with_raw(DEV, {"ARGOCD_SYNC_NOTAPAIR": stub.url}),
         0, r"pairs: 1 targets discovered", None),
        ("dead-blob-ignored", with_raw(DEV, {"ARGOCD_SYNC_TOKENS": "dev:%s" % T("dev")}),
         0, r"pairs: 1 targets discovered", None),
        ("all-blank-lever", mapping({"dev": ("", ""), "grow": (None, "")}),
         0, "WARN_KILL", None),
        ("underscore-law", mapping({"gpu-ai": (stub.url, T("gpu-ai")),
                                    "proxy-remote": (stub.url, T("proxy-remote"))}),
         0, r"pairs: 2 targets discovered", ("gpu_ai", "proxy_remote")),
    ]

    for arm in ARMS:
        tag, doc, want_rc, pat = arm[0], arm[1], arm[2], arm[3]
        no_echo = arm[4] if len(arm) > 4 else None
        # PARITY: identical mapping bytes through both channels, same flags.
        rc_e, out_e, err_e = h.run("t8-%s-env" % tag, "--check",
                                   raw_env=dict(doc), config=roster)
        rc_f, out_f, err_f = h.run_file("t8-%s-file" % tag, "--check",
                                        mapping=doc, config=roster)
        if (rc_e, out_e, err_e) != (rc_f, out_f, err_f):
            h.bad("t8[%s]: channels diverge for identical content — env (rc %s) vs file (rc %s):\nENV: %s\nFILE: %s"
                  % (tag, rc_e, rc_f, (out_e + err_e)[:250], (out_f + err_f)[:250]))
        blob = out_f + err_f
        if rc_f != want_rc:
            h.bad("t8[%s]: exit %s, expected %s:\n%s" % (tag, rc_f, want_rc, blob[:400]))
        if pat == "WARN_KILL":
            if h.WARN_KILL not in blob:
                h.bad("t8[%s]: the pinned kill-lane warning is absent through the file channel (unchanged string, DECISIONS (e)):\n%s" % (tag, blob[:400]))
        elif pat:
            if not re.search(pat if not pat.startswith("pairs:") else r"(?m)^" + pat, blob) and pat not in blob:
                h.bad("t8[%s]: output lacks the pinned shape %r:\n%s" % (tag, pat, blob[:400]))
        if no_echo == "SORTED":
            line = next((ln for ln in err_f.splitlines() if ln.startswith("argocd-fanout config:")), "")
            pos = [(c, line.find('"%s"' % c)) for c in ("grow", "infra", "media")]
            if any(p < 0 for _, p in pos) or [p for _, p in pos] != sorted(p for _, p in pos):
                h.bad("t8[%s]: the file channel must aggregate the SAME single sorted line: %r" % (tag, line[:300]))
        elif no_echo:
            for v in no_echo:
                if v in blob:
                    h.bad("t8[%s]: %r leaked into output (file content and offending values are never printed)" % (tag, v))
        if h.STEM in blob:
            h.bad("t8[%s]: token material from the pairs file echoed into output (AC8 — the file is an input, never an echo surface)" % tag)
        if "gpu_ai" in blob or "proxy_remote" in blob:
            h.bad("t8[%s]: the underscore→hyphen category law did not apply through the file channel" % tag)

    if recs:
        h.bad("t8: %d stub sockets across --check arms — file channel shares the zero-network law" % len(recs))
finally:
    stub.stop()

print("ok: t8: every discovery matrix class reproduces BIT-IDENTICALLY through pairs files (half-pair, (j)-blanked, JWT, scheme/@/query URL, malformed preemption + empty-residue/dead-name ignore, sorted aggregation, all-blank lever, underscore law) — one validator body, two channels (C14 AC5)")
PY
  then
    fail "t8: the channel-parity battery is violated (reason printed above)"
  fi
  ok "t8: env/file discovery parity across the full matrix (AC5; red until C14 lands)"
fi

# --- t9: the ruled drift envelope (OQ-A pure discovery, asserted AS CONTRACT) ------
# Four classes, pinned verbatim from the DECISIONS 2026-11-26 OQ-A block:
# (1) half-delete ⇒ RED naming the category (existing class, unchanged);
# (2) BOTH keys deleted ⇒ CLEAN INTENTIONAL DECOMMISSION — the category
#     vanishes, fleet N−1, GREEN, and the summary targets=N is the ONLY
#     signal (designed-quiet: pin the absence of any error line — this is
#     the ruling, not a defect; making it loud demands a repo edit per
#     decommission and the owner declined it);
# (3) blanked-but-present pair ⇒ still (j) RED while the fleet is configured;
# (4) a stray COMPLETE valid pair JOINS silently — mirror image of (2).
# No membership error class exists: none of these arms may emit one.
if want t9; then
  if ! python3 - "$WORK" <<'PY'
import os, re, sys

sys.path.insert(0, sys.argv[1])
import harness as h

recs = []
stubs = {}
for c in ("dev", "grow", "media", "zeta"):
    stubs[c] = h.StubArgo(c, recs, apps=[h.app(c, h.REPO, "main", "OutOfSync")])
for s in stubs.values():
    s.start()
try:
    roster = h.make_globals(os.path.join(sys.argv[1], "t9"), settle_seconds=0.0)
    FULL = {"dev": (stubs["dev"].url, h.token_for("dev")),
            "grow": (stubs["grow"].url, h.token_for("grow")),
            "media": (stubs["media"].url, h.token_for("media"))}

    def mp(spec):
        doc = {}
        for cat, (u, tk) in spec.items():
            if u is not None:
                doc[h.url_key(cat)] = u
            if tk is not None:
                doc[h.token_key(cat)] = tk
        return doc

    def quiet(tag, rc, out, err, where):
        blob = out + err
        if "config:" in blob:
            h.bad("t9[%s]: %s is RULED QUIET — a membership/config error line contradicts the pure-discovery ruling (count is the only signal):\n%s" % (tag, where, blob[:400]))
        if "::warning::" in blob:
            h.bad("t9[%s]: %s must not warn (a clean vault change is by design; the runbook §5 count line is the audit):\n%s" % (tag, where, blob[:400]))
        if "zeta" in tag and "unknown" in blob.lower():
            h.bad("t9[%s]: an unknown-category error class exists — there is NO membership oracle:\n%s" % (tag, blob[:400]))

    # (2) BOTH-key delete ⇒ invisible category, GREEN fleet N−1=2. The
    # summary line is the ONLY signal: pin targets=2, the absence of the
    # category name in any error/warning line, and zero dials to media.
    doc = mp({c: v for c, v in FULL.items() if c != "media"})
    rc, out, err = h.run_file("t9-both-gone", "--ref", "refs/heads/main", mapping=doc, config=roster)
    blob = out + err
    if rc != 0:
        h.bad("t9[both-gone]: a clean decommission must fan out GREEN over the survivors, exit %s:\n%s" % (rc, blob[:400]))
    if h.summary(blob) != ("2", "2", "0", "0"):
        h.bad("t9[both-gone]: summary %r, expected targets=2 ok=2 — the COUNT is the designed signal of the shrink (OQ-A (2))" % (h.summary(blob),))
    quiet("both-gone", rc, out, err, "a both-key delete")
    if any(r["stub"] == "media" for r in recs):
        h.bad("t9[both-gone]: the deleted category was still DIALED — it left discovery entirely")
    names = {x["name"] for x in h.audits(blob)}
    if names != {"dev", "grow"}:
        h.bad("t9[both-gone]: audit set %s, expected exactly the fleet-1 survivors" % sorted(names))

    # (4) stray COMPLETE valid pair ⇒ JOINS silently at N+1=3 (dev+grow +
    # zeta). Same contract posture, mirrored.
    doc = mp({"dev": FULL["dev"], "grow": FULL["grow"],
              "zeta": (stubs["zeta"].url, h.token_for("zeta"))})
    rc, out, err = h.run_file("t9-stray", "--ref", "refs/heads/main", mapping=doc, config=roster)
    blob = out + err
    if rc != 0 or h.summary(blob) != ("3", "3", "0", "0"):
        h.bad("t9[stray]: a complete stray pair joins the fleet GREEN at targets=3, got rc %s summary %r:\n%s" % (rc, h.summary(blob), blob[:400]))
    quiet("stray", rc, out, err, "a stray complete pair")
    if not any(r["stub"] == "zeta" for r in recs):
        h.bad("t9[stray]: the stray pair did not actually dial (join must be REAL, not count-only)")

    # (1) half-delete (TOKEN gone, URL survives) ⇒ RED naming the category.
    doc = mp({"dev": FULL["dev"], "grow": FULL["grow"],
              "media": (stubs["media"].url, None)})
    rc, out, err = h.run_file("t9-half", "--ref", "refs/heads/main", mapping=doc, config=roster)
    blob = out + err
    if rc != 1 or 'category "media" missing TOKEN value' not in blob:
        h.bad("t9[half]: one-sided delete stays RED naming the category (existing class, OQ-A (1)), rc %s:\n%s" % (rc, blob[:400]))
    if h.STEM in blob:
        h.bad("t9[half]: token material echoed")

    # (3) blanked-but-present pair ⇒ (j) RED while the fleet is configured.
    doc = mp({"dev": FULL["dev"], "grow": FULL["grow"], "media": ("", "")})
    rc, out, err = h.run_file("t9-blanked", "--ref", "refs/heads/main", mapping=doc, config=roster)
    blob = out + err
    if rc != 1 or not re.search(r'category .media. enumerated but both values empty', blob):
        h.bad("t9[blanked]: a blanked pair (both names present, both \"\") stays (j) RED (OQ-A (3) — the §7 partial-blank shape is LOUD; only clean deletes are quiet), rc %s:\n%s" % (rc, blob[:400]))
    if h.STEM in blob:
        h.bad("t9[blanked]: token material echoed")
finally:
    for s in stubs.values():
        s.stop()

print("ok: t9: the ruled pure-discovery envelope as CONTRACT — both-gone QUIET fleet N−1 (summary count the only signal), stray-pair QUIET JOIN N+1, half-delete RED naming the category, blanked-pair (j) RED; no membership error class exists (C14 AC5; red until C14 lands)")
PY
  then
    fail "t9: the ruled drift envelope is violated (reason printed above)"
  fi
  ok "t9: drift envelope pinned per ruling (quiet classes asserted; loud classes unchanged) (AC5)"
fi

# --- t10: prune=false in query AND body, never force; discovered-count summary ----
# (C09-era t6/t9, folded; AC9 byte-stable.) The fan-out core is
# channel-agnostic — the twin arm delivers the same urls through a pairs
# file (C14 "two of them ALSO exercised through the file channel").
if want t10; then
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
    roster = h.make_globals(os.path.join(sys.argv[1], "t10"), settle_seconds=0.0)
    rc, out, err = h.run_core("t10-prune", "--ref", "refs/heads/main",
                              urls={"gpu": stub.url}, config=roster)
    if rc != 0:
        h.bad("t10: run exited %s\n%s" % (rc, (out + err)[:400]))
    syncs = stub.syncs()
    if len(syncs) != 2:
        h.bad("t10: %d sync POSTs, expected 2 (root + child)" % len(syncs))
    for r in syncs:
        q = r["path"].split("?", 1)
        if len(q) != 2 or "prune=false" not in q[1]:
            h.bad("t10: POST path %r lacks ?prune=false in the QUERY (OQ6 pins both places: the grpc-gateway maps query params onto SyncRequest fields)" % r["path"])
        if r["body"] != {"prune": False}:
            h.bad("t10: POST body %r, expected exactly {\"prune\": false} (the CLI-shaped client reads the BODY; pinning both leaves no server-side default path)" % r["body"])
        if "force" in q[1] or (isinstance(r["body"], dict) and "force" in r["body"]):
            h.bad("t10: a `force` key appears (OQ6: never force — a forced sync overwrites operator drift by hand)")
finally:
    stub.stop()

recs2 = []
dev = h.StubArgo("dev", recs2, apps=[h.app("dev", h.REPO, "main", "OutOfSync")])
gpu_ai = h.StubArgo("gpu-ai", recs2, apps=[h.app("gpu-ai", h.REPO, "main", "OutOfSync")])
grow = h.StubArgo("grow", recs2, apps=[h.app("grow", h.REPO, "main", "Synced")])
for s in (dev, gpu_ai, grow):
    s.start()
try:
    roster = h.make_globals(os.path.join(sys.argv[1], "t10sum"), settle_seconds=0.0)
    # Two discovered pairs (incl. the GPU_AI category) ⇒ summary targets=2 —
    # the count is the DISCOVERED fleet, the roster carries no number.
    rc, out, err = h.run_core("t10-sum2", "--ref", "refs/heads/main",
                              urls={"dev": dev.url, "gpu-ai": gpu_ai.url}, config=roster)
    blob = out + err
    if rc != 0:
        h.bad("t10: exited %s\n%s" % (rc, blob[:400]))
    if h.summary(blob) != ("2", "2", "0", "0"):
        h.bad("t10: summary %r, expected targets=2 ok=2 skipped=0 failed=0 — targets= must carry the DISCOVERED count (R7: no roster count exists any more)" % (h.summary(blob),))
    names = {x["name"] for x in h.audits(blob)}
    if names != {"dev", "gpu-ai"}:
        h.bad("t10: audit set %s, expected the discovered categories incl. the hyphen-mapped gpu-ai" % sorted(names))
    # Third pair added ⇒ targets=3 (a fleet grows by instance keys and
    # nothing else — the summary follows). The grow root is Synced but
    # still ELIGIBLE: an eligible root audits ok (skipped is reserved for
    # non-tracking roots).
    rc, out, err = h.run_core("t10-sum3", "--ref", "refs/heads/main",
                              urls={"dev": dev.url, "gpu-ai": gpu_ai.url, "grow": grow.url},
                              config=roster)
    blob = out + err
    if h.summary(blob) != ("3", "3", "0", "0"):
        h.bad("t10: three-pair summary %r, expected targets=3 ok=3 skipped=0 failed=0 (the discovered count tracks the PAIRS, not any repo-side list)" % (h.summary(blob),))

    # FILE-channel twin (C14 channel-independence of the core): the same
    # three pairs delivered as a pairs file ⇒ identical fan-out arithmetic
    # and the same audit set (designed-red subleg until C14 lands).
    rc, out, err = h.run_file_core("t10-file", "--ref", "refs/heads/main",
                                   urls={"dev": dev.url, "gpu-ai": gpu_ai.url, "grow": grow.url},
                                   config=roster)
    blob = out + err
    if rc != 0:
        h.bad("t10[file]: the file-channel happy fan-out exited %s (C14 red until the channel lands):\n%s" % (rc, blob[:500]))
    if h.summary(blob) != ("3", "3", "0", "0"):
        h.bad("t10[file]: file-channel summary %r, expected the same 3/3/0/0 arithmetic (core independence)" % (h.summary(blob),))
    names = {x["name"] for x in h.audits(blob)}
    if names != {"dev", "gpu-ai", "grow"}:
        h.bad("t10[file]: file-channel audit set %s != the env-channel fleet" % sorted(names))
finally:
    for s in (dev, gpu_ai, grow):
        s.stop()

print("ok: t10: every sync POST carries prune=false in query AND body with no force anywhere; the summary's targets= equals the DISCOVERED pair count (2 then 3), gpu-ai audits under its derived name; the file-channel twin reproduces the full happy fan-out (AC9/OQ6, C14 AC5)")
PY
  then
    fail "t10: the prune/counting/channel-independence contract is violated (reason printed above)"
  fi
  ok "t10: prune=false both places + discovered-count summary + file-channel happy twin (AC9, AC5)"
fi

# --- t11: 409 is success AND the sweep continues (AC9) -----------------------------
if want t11; then
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
    roster = h.make_globals(os.path.join(sys.argv[1], "t11"), settle_seconds=0.0)
    rc, out, err = h.run_core("t11", "--ref", "refs/heads/main",
                              urls={"media": stub.url}, config=roster)
    blob = out + err
    a = h.audits(blob)
    if rc != 0:
        h.bad("t11: a 409-root run must exit 0, got %s\n%s" % (rc, blob[:400]))
    if len(a) != 1 or a[0]["result"] != "ok" or a[0]["detail"] != "root in-progress, 1 children synced":
        h.bad("t11: audit %r, expected result=ok detail='root in-progress, 1 children synced' (409 = the same state is already syncing under the same non-prune semantics; and the child sweep must CONTINUE past the in-progress root — shipped drive_target behavior)")
    names = [r["app"] for r in stub.syncs()]
    if names != ["media", "media-child"]:
        h.bad("t11: POST order %s — the child sync must still fire after the 409 root" % names)
finally:
    stub.stop()

print("ok: t11: 409 audits as root=in-progress success and the sweep continues to children (AC9, byte-stable)")
PY
  then
    fail "t11: the 409-as-success posture is violated (reason printed above)"
  fi
  ok "t11: 409-as-success with continued sweep (AC9, byte-stable)"
fi

# --- t12: per-target isolation incl. the RULED OQ9 posture + M2 3xx (AC9) ---------
if want t12; then
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
    roster = h.make_globals(os.path.join(sys.argv[1], "t12"), settle_seconds=0.0,
                            target_timeout_seconds=0.5)
    urls = {"dev": dev.url, "gpu": gpu.url, "grow": grow.url, "media": media.url,
            "proxy-backup": "http://127.0.0.1:%d" % dead_port}
    rc, out, err = h.run_core("t12", "--ref", "refs/heads/main", urls=urls, config=roster)
    blob = out + err
    if rc != 0:
        h.bad("t12: dead/401/garbage/timeout/refused targets must NOT flip the exit code (R1 self-heal: the next push covers them) — got %s\n%s" % (rc, blob[:500]))
    a = {x["name"]: x for x in h.audits(blob)}
    if set(a) != {"dev", "gpu", "grow", "media", "proxy-backup"}:
        h.bad("t12: audit set %s != the 5 targets — every target, healthy or not, gets its line (isolation must not swallow lines)" % sorted(a))
    if a["dev"]["result"] != "ok":
        h.bad("t12: healthy target dev got %r while neighbors failed (per-target isolation)" % a["dev"]["result"])
    for t, why in (("gpu", "401"), ("grow", "garbage JSON"), ("media", "timeout"),
                   ("proxy-backup", "connection refused — the RULED OQ9 warn-and-skip posture: a listed but unreachable cluster is an honest failed audit line, never a silent drop")):
        if a[t]["result"] != "failed":
            h.bad("t12: %s target must audit failed (%s), got %r" % (t, why, a[t]))
        if not a[t]["detail"].strip():
            h.bad("t12: failed audit for %s carries no reason (operators grep detail)" % t)
    if "401" not in a["gpu"]["detail"]:
        h.bad("t12: 401 detail %r should name the HTTP code (shipped `applications list HTTP %d` vocabulary)" % a["gpu"]["detail"])
    if "tim" not in a["media"]["detail"] or "out" not in a["media"]["detail"]:
        h.bad("t12: timeout detail %r does not name the timeout (the 0.5s per-request budget must be enforced on the list leg)" % a["media"]["detail"])
    if h.summary(blob) != ("5", "1", "0", "4"):
        h.bad("t12: summary %r, expected targets=5 ok=1 skipped=0 failed=4 (the math must reconcile with the audit lines)" % (h.summary(blob),))
    child = [r for r in dev.syncs() if r["app"] == "dev-app1"]
    if len(child) != 1:
        h.bad("t12: the healthy target's child sweep was disturbed by its neighbors (dev-app1 POSTs: %d)" % len(child))

    # ---- M2 phase: 3xx containment, both legs, against a separate-origin
    # redirect target whose access log is the token-egress witness. The live
    # trigger is real: cluster.proxy-local answers 307 to the SSO edge even
    # with a bearer present (review round 1). The pinned posture: a door 3xx
    # surfaces in the FAILED audit lane with the shipped HTTP-code wording,
    # the bearer never leaves the discovered origin, and a 3xx-turned-GET
    # can never earn result=ok.
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
        urls2 = {"gpu": front_list.url, "media": front_sync.url}
        rc2, out2, err2 = h.run_core("t12-3xx", "--ref", "refs/heads/main",
                                     urls=urls2, config=roster)
        blob2 = out2 + err2
        if rc2 != 0:
            h.bad("t12-3xx: a redirecting cluster is a RUNTIME failure — soft lane, exit 0 (got %s)\n%s" % (rc2, blob2[:400]))
        a2 = {x["name"]: x for x in h.audits(blob2)}
        if set(a2) != {"gpu", "media"}:
            h.bad("t12-3xx: audits %s, expected both redirect targets" % sorted(a2))
        if a2.get("gpu", {}).get("result") != "failed" or "applications list HTTP 302" not in a2.get("gpu", {}).get("detail", ""):
            h.bad("t12-3xx: the 302 list door must audit failed with the shipped `applications list HTTP 302` wording (no silent follow), got %r" % a2.get("gpu"))
        if a2.get("media", {}).get("result") != "failed" or "sync HTTP 301" not in a2.get("media", {}).get("detail", ""):
            h.bad("t12-3xx: the 301 sync door must audit failed with `sync HTTP 301` — and MUST NOT audit ok: the default opener turns POST into GET, lands an HTML page, and would fake a green sweep (review M2 false-green)")
        if "result=ok" in blob2:
            h.bad("t12-3xx: result=ok appeared with zero real syncs performed — the operator-grepped success channel was earned by a redirect page (M2)")
        for label, xlog in (("cross1", x1), ("cross2", x2)):
            if xlog:
                leaks = [r for r in xlog if r.get("auth")]
                h.bad("t12-3xx: %d request(s) landed on the redirect TARGET %s (%d carrying Authorization!) — the bearer left the discovered origin; api_request must refuse redirects" % (len(xlog), label, len(leaks)))
        gl = [r for r in recs if r["stub"] == "front-list"]
        gs = [r for r in recs if r["stub"] == "front-sync"]
        if not any(r["method"] == "GET" for r in gl) or not any(r["method"] == "GET" for r in gs):
            h.bad("t12-3xx: the redirecting targets were not dialed (doors must be PROVEN unreachable, not bypassed)")
        if not any(r["method"] == "POST" for r in gs):
            h.bad("t12-3xx: front-sync never received the POST attempt — eligibility said sync, so the sync leg must fire into the door")
        if h.summary(blob2) != ("2", "0", "0", "2"):
            h.bad("t12-3xx: summary %r, expected targets=2 ok=0 skipped=0 failed=2" % (h.summary(blob2),))
        if h.STEM in blob2:
            h.bad("t12-3xx: token material echoed in the 3xx legs' output (AC8)")
        for r in gl + gs:
            if r["auth"] and not r["auth"].startswith("Bearer " + h.SEG1):
                h.bad("t12-3xx: door request carried an unexpected Authorization shape: %r" % r["auth"][:30])
    finally:
        for s in (cross1, cross2, front_list, front_sync):
            s.stop()
finally:
    for s in (dev, gpu, grow, media):
        s.stop()

print("ok: t12: 401/garbage/timeout/refused neighbors fail in isolation — each audits a reason, the healthy target completes, the summary reconciles, exit stays 0; the closed-port arm is the OQ9 honest-failed posture; the 3xx phase proves redirect containment on BOTH legs (M2): door 3xx audits `applications list HTTP 302` / `sync HTTP 301`, no result=ok, zero requests on the redirect target and its bearer (AC9)")
PY
  then
    fail "t12: the isolation posture is violated (reason printed above)"
  fi
  ok "t12: per-target isolation + OQ9 honest failed lines + M2 3xx containment + soft exit (AC9, byte-stable)"
fi

# --- t13: --check from pairs + zero sockets, --dry-run GET-only (AC7, AC9) ---------
# The C09-era t10, plus the FILE twin of the --check table: cmd_check derives
# from whichever channel fed discovery — output lines unchanged (C14).
if want t13; then
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
    roster = h.make_globals(os.path.join(sys.argv[1], "t13"))
    pairs = {"dev": {"url": dev.url, "token": h.token_for("dev")},
             "grow": {"url": grow.url, "token": h.token_for("grow")}}

    # (a) --check (AC7): table from DISCOVERED pairs, pinned pairs-line, zero
    # sockets — the C09 replacement for the reopen2 vault-table leg.
    rc, out, err = h.run("t13-check", "--check", pairs=pairs, config=roster)
    blob = out + err
    if rc != 0:
        h.bad("t13: --check exited %s\n%s" % (rc, blob[:400]))
    if "argocd-fanout --check: OK" not in blob:
        h.bad("t13: no OK line")
    if "pairs: 2 targets discovered" not in blob:
        h.bad("t13: --check table is not derived from the discovered pairs (missing the pairs: 2 line):\n%s" % blob[:500])
    for cat, url in (("dev", dev.url), ("grow", grow.url)):
        if cat not in blob or url not in blob:
            h.bad("t13: --check NAME/URL table lacks the pair %r→%r (the discovered endpoints must be visible for the owner's verification legs)" % (cat, url))
    if "refs/heads/main" not in blob:
        h.bad("t13: --check never echoes allowed_refs")
    if recs:
        h.bad("t13: --check opened sockets — %d requests landed (zero-network law)" % len(recs))
    if h.STEM in blob:
        h.bad("t13: --check echoes token material (AC8)")

    # --check must also RED on the integrity matrix (AC7 tail) and stay
    # GREEN-only-on-warning in the kill lane (kill returns before tables).
    broken = {"dev": {"url": dev.url, "token": h.token_for("dev")},
              "grow": {"url": grow.url}}
    rc, out, err = h.run("t13-check-broken", "--check", pairs=broken, config=roster)
    if rc != 1 or 'category "grow" missing TOKEN value' not in (err or ""):
        h.bad("t13: --check on a broken fleet must exit 1 with the pinned integrity line (got rc=%s):\n%s" % (rc, (out + err)[:400]))
    rc, out, err = h.run("t13-check-kill", "--check",
                         pairs={"dev": {"url": dev.url}}, config=roster)
    if rc != 0 or h.WARN_KILL not in (out + err) or "--check: OK" in (out + err):
        h.bad("t13: --check on an unconfigured fleet is the kill lane: exit 0, ONLY the warning, NO table (rc %s):\n%s" % (rc, (out + err)[:400]))

    # (a2) FILE twin (C14 channel-independence): the identical pairs as a
    # pairs file ⇒ the SAME --check table lines — cmd_check's output is
    # channel-blind, derived from discovery (designed-red subleg until C14).
    rc, out, err = h.run_file("t13-check-file", "--check", pairs=pairs, config=roster)
    blob = out + err
    if rc != 0 or "argocd-fanout --check: OK" not in blob or "pairs: 2 targets discovered" not in blob:
        h.bad("t13[file]: --check through the pairs file must print the same derived table, rc %s:\n%s" % (rc, blob[:400]))
    for cat, url in (("dev", dev.url), ("grow", grow.url)):
        if cat not in blob or url not in blob:
            h.bad("t13[file]: file-channel --check table lacks %r→<url>: the pairing is channel-blind" % cat)
    if h.STEM in blob:
        h.bad("t13[file]: --check through the file echoed token material (the FILE contents are never printed)")
    if recs:
        h.bad("t13[file]: %d sockets — the file channel shares the zero-network law" % len(recs))

    # (b) --dry-run (AC9, the shipped smoke mode, byte-stable): live GETs
    # only, ZERO POSTs, per-target eligibility, exit 0.
    rc, out, err = h.run_core("t13-dry", "--dry-run", "--ref", "refs/heads/main",
                              urls={"dev": dev.url, "grow": grow.url}, config=roster)
    blob = out + err
    if rc != 0:
        h.bad("t13: --dry-run exited %s\n%s" % (rc, blob[:400]))
    posts = [r for r in recs if r["method"] == "POST"]
    if posts:
        h.bad("t13: --dry-run POSTed %d times — dry-run is the runbook smoke/preflight mode; it must never change cluster state (plan Modes: live GETs only, zero POSTs)" % len(posts))
    if not dev.lists() or not grow.lists():
        h.bad("t13: --dry-run skipped a target's list call — it is the REACHABILITY proof (the proxy-backup preflight row), every target must be dialed")
    for t in ("dev", "grow"):
        if ("target=%s" % t) not in blob:
            h.bad("t13: no per-target eligibility line for %r in --dry-run output (AC9):\n%s" % (t, blob[:500]))
finally:
    dev.stop(); grow.stop()

print("ok: t13: --check prints the pairs-derived table + pinned pairs line with ZERO sockets, reds on the integrity matrix, kill-lanes on an unconfigured fleet; the file-channel twin prints the SAME table; --dry-run dials GETs only, never POSTs, per-target eligibility, exit 0 (AC7, AC9)")
PY
  then
    fail "t13: the check/dry-run contract is violated (reason printed above)"
  fi
  ok "t13: --check-from-pairs (+file twin) and dry-run GET-only hold (AC7/AC9)"
fi

# --- t14: all-skipped warns and stays green; CLI/usage posture (AC9 + CLI) ----------
# (C09-era t11 + the non-sweep half of the C09-era t12; the zero-echo sweep
# itself runs last — t15 — so it can cover every leg in the suite.)
if want t14; then
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
    # Two targets: the m1 "exactly once" pin cannot bite on a one-target run.
    roster = h.make_globals(os.path.join(sys.argv[1], "t14"),
                            tracked_repo="https://github.com/OwnYourIO/NeverDeployed.git")
    rc, out, err = h.run_core("t14", "--ref", "refs/heads/main",
                              urls={"dev": stub.url, "grow": stub.url}, config=roster)
    blob = out + err
    a = h.audits(blob)
    if rc != 0:
        h.bad("t14: all-skipped exits %s, expected 0 (a runtime-shape miss stays soft; only SETUP errors go red)" % rc)
    if not a or any(x["result"] != "skipped" for x in a) or len(a) != 2:
        h.bad("t14: audits %r, expected both targets skipped" % [dict(x) for x in a])
    if "::warning::" not in blob:
        h.bad("t14: all-skipped run lacks the pinned `::warning::` line (plan: the trackedRepo-mismatch trap [P §3] must announce)")
    wlines = [ln for ln in blob.splitlines() if "::warning::" in ln]
    if len(wlines) != 1:
        h.bad("t14: %d lines carry ::warning:: — the trap annotation appears EXACTLY once per run" % len(wlines))
    if any(not ln.startswith("::warning::") for ln in wlines):
        h.bad("t14: the all-skipped ::warning:: is not at column 0 (m1: mid-line the runner grammar ignores it — print the annotation directly, not through log())")
    if h.summary(blob) != ("2", "0", "2", "0"):
        h.bad("t14: summary %r, expected targets=2 ok=0 skipped=2 failed=0" % (h.summary(blob),))
finally:
    stub.stop()

# CLI contract (argparse surface FROZEN by C14 — no --pairs flag: the
# channel is the ARGOCD_PAIRS_FILE ENV var, DECISIONS (c)).
rc, out, err = h.run("t14-help", "--help")
blob = out + err
if rc != 0:
    h.bad("t14: --help exited %s\n%s" % (rc, blob[:300]))
for flag in ("--config", "--ref", "--check", "--dry-run"):
    if flag not in blob:
        h.bad("t14: --help does not advertise %s (the CLI contract is exactly these four flags + --help — UNCHANGED by R7 AND R8)" % flag)
for flag in ("--token", "--secret", "--vault", "--pairs"):
    if flag in blob:
        h.bad("t14: --help advertises %s — values come ONLY from the environment/pairs file, never argv, and the R8 channel is the ARGOCD_PAIRS_FILE env var, NOT a CLI flag (argparse surface frozen)" % flag)
if "ARGOCD_SYNC_TOKENS" in blob:
    h.bad("t14: --help still advertises the DEAD blob name — the wording must point at the ARGOCD_SYNC_<CAT>_* pairs")

rc, out, err = h.run("t14-positional", "refs/heads/main",
                     pairs={"dev": {"url": "http://127.0.0.1:1", "token": h.token_for("dev")}})
if rc != 2:
    h.bad("t14: a positional ref exited %s, expected argparse 2 — 'No positional args' is the pinned CLI contract" % rc)
# A decoy value (not a fixture token) keeps the argv ledger honest: the
# probe proves no token channel exists without poisoning the ledger with one.
rc, out, err = h.run("t14-token-flag", "--token", "DECOY42-not-a-real-token",
                     pairs={"dev": {"url": "http://127.0.0.1:1", "token": h.token_for("dev")}})
if rc != 2:
    h.bad("t14: a --token flag exited %s, expected argparse 2 — a token-receiving flag must not exist" % rc)
# The KEY=value argv shape (a non-sourced invocation) must be rejected too:
# the runbook pins the source-then-run recipe precisely so values never
# reach a command line.
rc, out, err = h.run("t14-kv-argv", "ARGOCD_SYNC_DEV_TOKEN=DECOY42-zzz")
if rc != 2:
    h.bad("t14: a KEY=value argv shape exited %s, expected argparse 2 — no positional channel exists for env-shaped args" % rc)
# The PAIRS_FILE PATH is not a secret (it may ride argv) but the FILE's
# CONTENTS must never be inlined into any invocation: the ledger proves no
# leg ever passes pair VALUES as arguments (t15 sweeps the ledger file-wide).
rc, out, err = h.run("t14-pairs-flag", "--pairs-file", "/tmp/opencode/nope.json")
if rc != 2:
    h.bad("t14: a --pairs-file flag exited %s, expected argparse 2 — the channel is the env var (DECISIONS (c)), a new flag is surface churn" % rc)

print("ok: t14: all-skipped audits skipped, warns ONE column-0 ::warning::, summarizes, exits 0; --help shows only the four pinned flags (no --pairs*, no blob wording); positional, --token, --pairs-file and KEY=value argv all exit 2 (AC9, CLI contract frozen by C14)")
PY
  then
    fail "t14: the all-skipped/CLI contract is violated (reason printed above)"
  fi
  ok "t14: all-skipped posture + frozen CLI surface (AC9 + plan (c))"
fi

# --- t15: byte-lock + zero-echo across BOTH channels (C14 AC6/AC8) ------------------
# C09's guarantee (13 CORE names byte-identical to $CHUNK_BASE — resolved by
# SUBJECT 'fix(fanout): C12 ruling (j)', the durable content-lock) is KEPT
# UNCHANGED; the C14 extension adds the INPUT layer locked to the same
# subject-resolved commit: the R8 channel is docstring +
# load_pairs_file + main's source selection ONLY. discover_targets,
# cmd_check, load_roster, the error classes and every regex/lane constant
# show ZERO hunks — one validator body serving both sources is the design,
# not a convenience. (C12 precedent: the (j) repair moved discover_targets
# with a recorded baseline bump; if C14 lands an intentional move, review
# repoints INPUT_BASE — the leg never weakens.) Finally the sweep: no
# fixture token, JWT segment, assignment byte or ARGOCD_SYNC name ever
# reached output or argv across EVERY leg of both channels — file contents
# included (a pairs file is an input, never an echo surface).
if want t15; then
  if ! python3 - "$FANOUT" "$CORE_BASE" "$INPUT_BASE" <<'PY'
import ast, os, subprocess, sys

fanout, base, input_base = sys.argv[1:4]


def bad(msg):
    print("FAIL: t15: %s" % msg, file=sys.stderr)
    sys.exit(1)


def show(ref):
    try:
        shown = subprocess.run(["git", "show", "%s:scripts/argocd-fanout.py" % ref],
                               capture_output=True, text=True)
    except OSError as e:
        bad("git unavailable for the byte-lock leg: %s" % e)
    if shown.returncode != 0:
        bad("cannot read the baseline (`git show %s:scripts/argocd-fanout.py`): %s — repoint CHUNK_BASE/INPUT_BASE to the pre-C14 commits" % (ref, shown.stderr.strip()[:120]))
    return shown.stdout


def segments(src, label):
    try:
        tree = ast.parse(src)
    except SyntaxError as e:
        bad("%s does not parse (%s)" % (label, e))
    out = {}
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            seg = ast.get_source_segment(src, node)
            if seg is not None:
                out[node.name] = seg
        elif isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            seg = ast.get_source_segment(src, node)
            if seg is not None:
                out[node.targets[0].id] = seg
    return out


# --- the unchanged CORE leg (13 names @ the subject-resolved base) ----------
CORE = ["log", "ref_tail", "app_name", "app_sources", "app_matches",
        "app_sync_status", "_NoRedirect", "api_request", "list_applications",
        "sync_application", "_reason", "drive_target", "fan_out"]
base_src = show(base)
old = segments(base_src, "shipped %s" % base)
new = segments(open(fanout).read(), "working %s" % fanout)
missing = [n for n in CORE if n not in new]
if missing:
    bad("core names vanished from the working file: %s (AC10 — the core survives intact)" % missing)
changed = [n for n in CORE if old.get(n) != new[n]]
if changed:
    import difflib
    for n in changed:
        a = (old.get(n) or "").splitlines()
        b = new[n].splitlines()
        diff = "\n".join(list(difflib.unified_diff(a, b, lineterm="", n=1))[:14])
        print("  %s hunk:\n%s" % (n, diff), file=sys.stderr)
    bad("core function bodies gained hunks: %s — R7 pinned the fan-out core byte-UNTOUCHED (C09 AC10); input changes belong to load_pairs_file/main" % changed)

# --- the C14 extension: input layer @ INPUT_BASE (reopen3 close) --------------
INPUT = ["discover_targets", "load_roster", "cmd_check", "ConfigError", "TargetError",
         "PAIR_KEY_RE", "SEG_RE", "CAT_RE", "JWT_RE", "WARN_NOT_CONFIGURED",
         "NOT_CONFIGURED", "ROSTER_KEYS"]
try:
    iprev = segments(show(input_base), "input baseline %s" % input_base)
except SystemExit:
    raise
except Exception as e:  # ref unreadable — same fail path as show()
    bad("input baseline unavailable: %s" % e)
ifind = [n for n in INPUT if n not in iprev]
if ifind:
    bad("input-layer names missing from the baseline %s: %s (the leg's baseline is the wrong commit)" % (input_base, ifind))
ichanged = [n for n in INPUT if iprev.get(n) != new.get(n)]
if ichanged:
    import difflib
    for n in ichanged:
        a = (iprev.get(n) or "").splitlines()
        b = (new.get(n) or "").splitlines()
        diff = "\n".join(list(difflib.unified_diff(a, b, lineterm="", n=1))[:14])
        print("  %s hunk:\n%s" % (n, diff), file=sys.stderr)
    bad("the C14 allowed surface was exceeded: %s gained hunks — R8 permits ONLY the module docstring, a NEW load_pairs_file, and main's source-selection branch (chunk C14 AC6)" % ichanged)
if "discover_targets" in new and "discover_targets" not in iprev:
    bad("discover_targets vanished at the input baseline — impossible, but the leg would green-light a rename")

print("ok: t15 byte-lock")
PY
  then
    fail "t15: the byte-lock proof failed (reason printed above)"
  fi
  if ! python3 - "$WORK" <<'PY'
import os, sys

sys.path.insert(0, sys.argv[1])
import harness as h

# Standalone-run safety: when t15 runs without its sibling legs, seed one
# canonical invocation so the sweep has bytes to scan (a vacuous green on an
# empty dir would make the leg meaningless in isolation).
if not os.path.exists(os.path.join(h.OUT, "argv.log")):
    roster = h.make_globals(os.path.join(sys.argv[1], "t15"))
    h.run("t15-sanity", "--check",
          pairs={"dev": {"url": "http://127.0.0.1:1", "token": h.token_for("dev")}},
          config=roster)

# The sweep: every leg captured so far — combined output of ALL runs, both
# channels — must not contain a single fixture token (SENT23 stem); the argv
# ledger must carry no JWT-shaped value, no '=' assignment byte, and no
# ARGOCD_SYNC key name (the sourced-recipe/pairs-file-only law: the PATH may
# travel, the CONTENTS never do).
hits = []
for fn in sorted(os.listdir(h.OUT)):
    path = os.path.join(h.OUT, fn)
    with open(path, errors="replace") as f:
        if h.STEM in f.read():
            hits.append(fn)
if hits:
    h.bad("t15: token material echoed in %s — the zero-token-echo guarantee (AC8) failed on at least one leg; logs kept at %s" % (hits, h.OUT))
argv_lines = open(os.path.join(h.OUT, "argv.log"), errors="replace").read().splitlines()
argv_hits = [ln.split("\t")[0] for ln in argv_lines if h.SEG1 in ln]
if argv_hits:
    h.bad("t15: fixture token reached the argv of leg(s) %s — values come ONLY from the environment or the pairs file (plan CLI contract)" % argv_hits)
# t14-kv-argv is the intentional decoy probe (it PUTS a KEY=value in argv to
# prove argparse rejects it with exit 2); its own ledger line is excluded
# from the assignment-byte scan so the suite does not flag its own fixture.
kv_hits = [ln.split("\t")[0] for ln in argv_lines
           if ln.split("\t")[0] != "t14-kv-argv" and ("=" in ln or "ARGOCD_SYNC" in ln)]
if kv_hits:
    h.bad("t15: argv of leg(s) %s carries an assignment byte or an ARGOCD_SYNC name — the sourced-env recipe and the PAIRS_FILE path are the PINNED invocation shapes, never KEY=value argv" % kv_hits)
for c in h.CATS:
    if c.replace("-", "") + h.STEM in " ".join(open(os.path.join(h.OUT, fn), errors="replace").read()
                                               for fn in os.listdir(h.OUT)):
        h.bad("t15: per-category token for %r echoed (attribution-level sweep)" % c)
# The pairs files themselves must never be cat-ed into output by the script:
# covered above — every leg's captured log is scanned for SENT23, and the
# file-channel legs (t6–t10, t13) put token material in their fixtures.
print("ok: t15 sweep")
PY
  then
    fail "t15: the zero-echo sweep failed (reason printed above)"
  fi
  ok "t15: 13 core names byte-locked at $CORE_BASE + input layer (discover_targets body, cmd_check, load_roster, regexes, lane strings, constants) byte-locked at $INPUT_BASE — C14's allowed surface is docstring + load_pairs_file + main only; zero token/assignment/argv leaks across both channels (AC6/AC8)"
fi

rm -rf "$WORK"
printf 'PASS: argocd-fanout behavior checks (%d ok)\n' "$checks"