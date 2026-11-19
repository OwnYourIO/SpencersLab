#!/usr/bin/env python3
"""argocd-hook — GitHub push-hook relay driving real ArgoCD API syncs.

The fleet keeps syncPolicy.automated off on every root app by owner ruling
(cf-139 OQ1) and ArgoCD webhooks only refresh, never sync — so this relay calls
each cluster's sync API itself after verifying the push HMAC. Stateless by
design: a restart mid-fan-out drops that push's tail; the fallback is manual sync.
"""

import argparse
import hashlib
import hmac
import json
import os
import re
import sys
import threading
import time
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib import error as urlerror
from urllib import parse as urlparse
from urllib import request as urlrequest

DEFAULT_ALLOWED_REFS = ["refs/heads/main"]
DEFAULT_PORT = 8080
DEFAULT_SETTLE_SECONDS = 10.0
DEFAULT_TARGET_TIMEOUT_SECONDS = 60.0
MAX_BODY_BYTES = 10 * 1024 * 1024
GITHUB_SECRET_FILE = "github-webhook"

# Target names land verbatim in the audit lines operators grep, so the roster
# is restricted to what that parser accepts: [A-Za-z0-9_.-]+
TARGET_NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+$")


class ConfigError(Exception):
    """Config/secret problem. Reasons name files and fields, never contents."""


class TargetError(Exception):
    """Per-target fan-out failure; isolated so one dead cluster never aborts the rest."""


@dataclass
class Target:
    name: str
    url: str
    root_app: str
    token_key: str
    repo: str
    local: bool = False
    token: bytes = b""


@dataclass
class RelayState:
    allowed_refs: list
    targets: list
    key: bytes
    settle: float
    timeout: float


def log(line):
    print("%s %s" % (time.strftime("%Y-%m-%dT%H:%M:%S"), line), flush=True)


def env_number(name, default, minimum):
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        value = float(raw)
    except ValueError:
        raise ConfigError("%s is not a number" % name)
    if value < minimum:
        raise ConfigError("%s must be >= %g" % (name, minimum))
    return value


def read_secret_file(path):
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError as e:
        raise ConfigError("%s: %s" % (path, e.strerror or e.__class__.__name__))
    # Secret-rendering tools commonly end files with a newline; GitHub webhook
    # secrets and ArgoCD API tokens never contain whitespace, so strip is safe.
    value = data.strip()
    if not value:
        raise ConfigError("%s is empty" % path)
    return value


def validate_config(raw):
    if not isinstance(raw, dict):
        raise ConfigError("targets.json top level must be an object")

    refs = raw.get("allowed_refs")
    if refs is None or refs == []:
        refs = list(DEFAULT_ALLOWED_REFS)
    if not isinstance(refs, list) or not all(isinstance(r, str) and r for r in refs):
        raise ConfigError('allowed_refs must be a list of full refs, e.g. ["refs/heads/main"]')
    for r in refs:
        if not r.startswith("refs/"):
            raise ConfigError("allowed_refs entry %r is not a full ref (must start with refs/)" % r)
        if r.startswith("refs/tags/"):
            raise ConfigError("allowed_refs must not list refs/tags/* — tag pushes never fire")

    targets = raw.get("targets")
    if not isinstance(targets, list) or not targets:
        raise ConfigError("targets must be a non-empty list")
    out = []
    seen = set()
    for i, t in enumerate(targets):
        if not isinstance(t, dict):
            raise ConfigError("targets[%d] must be an object" % i)
        entry = {}
        for k in ("name", "url", "rootApp", "tokenKey", "repo"):
            v = t.get(k)
            if not isinstance(v, str) or not v:
                raise ConfigError("targets[%d] needs a non-empty string %s" % (i, k))
            entry[k] = v
        local = t.get("local", False)
        if not isinstance(local, bool):
            raise ConfigError("targets[%d].local must be a boolean" % i)
        if not TARGET_NAME_RE.match(entry["name"]):
            raise ConfigError("targets[%d].name %r must match %s" % (i, entry["name"], TARGET_NAME_RE.pattern))
        if not entry["url"].startswith(("http://", "https://")):
            raise ConfigError("targets[%d].url must start with http:// or https://" % i)
        if entry["name"] in seen:
            raise ConfigError("duplicate target name %r" % entry["name"])
        seen.add(entry["name"])
        out.append(Target(
            name=entry["name"],
            url=entry["url"].rstrip("/"),
            root_app=entry["rootApp"],
            token_key=entry["tokenKey"],
            repo=entry["repo"],
            local=local,
        ))
    return refs, out


def build_state(args):
    try:
        with open(args.config) as f:
            raw = json.load(f)
    except OSError as e:
        raise ConfigError("%s: %s" % (args.config, e.strerror or e.__class__.__name__))
    except json.JSONDecodeError:
        raise ConfigError("%s is not valid JSON" % args.config)

    allowed_refs, targets = validate_config(raw)
    # Stable partition: remotes keep config order, the `local: true` hub entry
    # goes last — its root sync re-renders the hub and can restart this relay.
    targets = sorted(targets, key=lambda t: t.local)
    key = read_secret_file(os.path.join(args.secrets_dir, GITHUB_SECRET_FILE))
    for t in targets:
        t.token = read_secret_file(os.path.join(args.secrets_dir, t.token_key))

    sample = b"argocd-hook self-check"
    digest = "sha256=" + hmac.new(key, sample, hashlib.sha256).hexdigest()
    if not verify_signature(key, digest, sample):
        raise ConfigError("HMAC sign/verify round-trip failed")
    if verify_signature(key, "sha256=" + "0" * 64, sample):
        raise ConfigError("HMAC verification accepted a forged digest")

    return RelayState(
        allowed_refs=allowed_refs,
        targets=targets,
        key=key,
        settle=env_number("SETTLE_SECONDS", DEFAULT_SETTLE_SECONDS, 0.0),
        timeout=env_number("TARGET_TIMEOUT_SECONDS", DEFAULT_TARGET_TIMEOUT_SECONDS, 0.1),
    )


def verify_signature(key, header, body):
    if not header.startswith("sha256="):
        return False
    expected = hmac.new(key, body, hashlib.sha256).hexdigest().encode()
    return hmac.compare_digest(header[len("sha256="):].encode("ascii", "backslashreplace"), expected)


def ref_tail(ref):
    if ref.startswith("refs/heads/"):
        return ref[len("refs/heads/"):]
    if ref.startswith("refs/"):
        return ref[len("refs/"):]
    return ref


def app_name(app):
    if not isinstance(app, dict):
        return None
    name = (app.get("metadata") or {}).get("name")
    return name if isinstance(name, str) and name else None


def app_sources(app):
    # The fleet's root apps are multi-source (git + chart sources); older or
    # plain apps carry a single spec.source. The eligibility predicate must be
    # able to match either shape or a real spec hides in the unchecked form.
    spec = app.get("spec") or {}
    sources = [s for s in (spec.get("sources") or []) if isinstance(s, dict)]
    single = spec.get("source")
    if isinstance(single, dict):
        sources.append(single)
    return sources


def app_matches(app, repo, tail):
    return any(s.get("repoURL") == repo and s.get("targetRevision") == tail
               for s in app_sources(app))


def app_sync_status(app):
    # Unknown (not None): a fresh Missing app must still be synced, matching
    # the child filter "status != Synced".
    status = ((app.get("status") or {}).get("sync") or {}).get("status")
    return status if isinstance(status, str) and status else "Unknown"


def api_request(method, url, token, timeout, body=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {
        # errors=replace: a token with stray bytes must fail at ArgoCD's auth
        # check (visible as a sync failure), not crash mid-fan-out here.
        "Authorization": "Bearer " + token.decode("utf-8", "replace"),
        "Accept": "application/json",
    }
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urlrequest.Request(url, data=data, method=method, headers=headers)
    return urlrequest.urlopen(req, timeout=timeout)


def list_applications(target, timeout):
    url = target.url + "/api/v1/applications"
    try:
        with api_request("GET", url, target.token, timeout) as resp:
            payload = json.load(resp)
    except urlerror.HTTPError as e:
        raise TargetError("applications list HTTP %d" % e.code)
    except Exception as e:
        raise TargetError("applications list failed: %s" % _reason(e))
    items = payload.get("items") if isinstance(payload, dict) else None
    if not isinstance(items, list):
        raise TargetError("applications list had no items array")
    return items


def sync_application(target, name, timeout):
    url = "%s/api/v1/applications/%s/sync?prune=false" % (target.url, urlparse.quote(name, safe=""))
    # prune=false in BOTH query and body: the grpc-gateway maps query params
    # onto SyncRequest fields while CLI-shaped clients read the body — pinning
    # both leaves no path for a server-side default (OQ6: never prune, never force).
    try:
        with api_request("POST", url, target.token, timeout, {"prune": False}):
            return "synced"
    except urlerror.HTTPError as e:
        try:
            detail = e.read().decode("utf-8", "replace")
        except Exception:
            detail = ""
        # 409 / "another operation is already in progress" IS success: that
        # operation syncs the same git state with the same non-prune semantics.
        if e.code == 409 or "already in progress" in detail:
            return "in-progress"
        raise TargetError("sync HTTP %d" % e.code)
    except Exception as e:
        raise TargetError("sync failed: %s" % _reason(e))


def _reason(exc):
    return str(exc) or exc.__class__.__name__


def drive_target(state, target, tail):
    items = list_applications(target, state.timeout)
    eligible = {app_name(a) for a in items if app_matches(a, target.repo, tail)}
    if target.root_app not in eligible:
        # Skipping here is the OQ7 guarantee: a widened stage push can never
        # sync-fire a cluster whose root tracks a different revision.
        return "skipped", "root app %s does not track revision %s" % (target.root_app, tail)

    root_phase = sync_application(target, target.root_app, state.timeout)

    # Settle, then re-list: syncing the root regenerates the child
    # Applications from the new git, so the child pass is judged entirely on
    # this fresh listing, never the pre-sync snapshot.
    time.sleep(state.settle)
    items = list_applications(target, state.timeout)
    children = 0
    for a in items:
        name = app_name(a)
        if not name or name == target.root_app:
            continue
        if app_matches(a, target.repo, tail) and app_sync_status(a) != "Synced":
            sync_application(target, name, state.timeout)
            children += 1
    return "ok", "root %s, %d children synced" % (root_phase, children)


def fan_out(state, ref, delivery):
    tail = ref_tail(ref)
    log("push accepted ref=%s delivery=%s targets=%d" % (ref, delivery or "-", len(state.targets)))
    for target in state.targets:
        started = time.monotonic()
        try:
            result, detail = drive_target(state, target, tail)
        except TargetError as e:
            result, detail = "failed", str(e)
        except Exception as e:
            result, detail = "failed", "%s: %s" % (e.__class__.__name__, _reason(e))
        log("target=%s result=%s root=%s ref=%s elapsed=%.1fs detail=%s" % (
            target.name, result, target.root_app, ref, time.monotonic() - started, detail))


class Handler(BaseHTTPRequestHandler):
    state = None  # set on the class before serve_forever

    def _route(self):
        return self.path.split("?", 1)[0].rstrip("/") or "/"

    def _reply(self, code, text):
        payload = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self._route() == "/health":
            self._reply(200, "ok\n")
        else:
            self._reply(404, "not found\n")

    def do_POST(self):
        try:
            self._handle_post()
        except Exception as e:
            log("handler error: %s" % e.__class__.__name__)
            try:
                self._reply(500, "internal error\n")
            except Exception as reply_error:
                # The client is typically gone by now; the log line above is
                # the remaining audit trail.
                log("500 reply failed: %s" % reply_error.__class__.__name__)

    def _handle_post(self):
        if self._route() != "/":
            return self._reply(404, "not found\n")
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            return self._reply(400, "bad Content-Length\n")
        if length < 0 or length > MAX_BODY_BYTES:
            return self._reply(413, "payload too large\n")
        body = self.rfile.read(length)

        # Verify the raw bytes before trusting anything inside the payload.
        signature = self.headers.get("X-Hub-Signature-256") or ""
        if not verify_signature(self.state.key, signature, body):
            return self._reply(401, "invalid signature\n")

        event = self.headers.get("X-GitHub-Event") or ""
        if event != "push":
            # ping (and everything else) is an accepted no-op so GitHub's
            # "Test" button goes green without touching a cluster.
            return self._reply(200, "accepted\n")

        try:
            payload = json.loads(body)
        except ValueError:
            return self._reply(400, "push payload is not JSON\n")
        ref = payload.get("ref") if isinstance(payload, dict) else None
        if not isinstance(ref, str) or not ref:
            return self._reply(400, "push payload has no ref\n")

        # The tag-never-fire rule lives in validate_config (refs/tags is
        # rejected at load), so this membership test already no-ops every tag.
        if ref not in self.state.allowed_refs:
            return self._reply(200, "accepted\n")

        delivery = self.headers.get("X-GitHub-Delivery") or ""
        threading.Thread(target=fan_out, args=(self.state, ref, delivery), daemon=True).start()
        # GitHub's 10s delivery budget: the fan-out (settle delays included)
        # must never block this response.
        return self._reply(202, "accepted\n")


def cmd_check(args):
    try:
        state = build_state(args)
    except ConfigError as e:
        print("argocd-hook --check: FAILED — %s" % e, file=sys.stderr)
        return 1
    print("argocd-hook --check: OK")
    print("hmac round-trip: verified")
    print("allowed_refs: %s" % ", ".join(state.allowed_refs))
    print("tunables: SETTLE_SECONDS=%g TARGET_TIMEOUT_SECONDS=%g" % (state.settle, state.timeout))
    print("targets (fan-out order, remotes first):")
    print("  %-15s %-15s %-15s %-9s %s" % ("NAME", "ROOTAPP", "TOKENKEY", "LOCAL", "URL"))
    for t in state.targets:
        print("  %-15s %-15s %-15s %-9s %s" % (t.name, t.root_app, t.token_key, t.local, t.url))
    return 0


def cmd_serve(args):
    try:
        state = build_state(args)
    except ConfigError as e:
        log("config invalid — refusing to start: %s" % e)
        return 1
    Handler.state = state
    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    server.daemon_threads = True
    log("argocd-hook listening port=%d targets=%d allowed_refs=%s"
        % (args.port, len(state.targets), ",".join(state.allowed_refs)))
    server.serve_forever()
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(prog="argocd-hook",
                                     description="GitHub push-hook relay for ArgoCD sync fan-out")
    parser.add_argument("--config", required=True, help="path to targets.json")
    parser.add_argument("--secrets-dir", required=True, dest="secrets_dir",
                        help="directory with the github-webhook HMAC key and one file per tokenKey")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--check", action="store_true",
                        help="validate config, secrets and HMAC offline; print the roster; exit")
    args = parser.parse_args(argv)
    sys.exit(cmd_check(args) if args.check else cmd_serve(args))


if __name__ == "__main__":
    main()
