#!/usr/bin/env python3
"""argocd-fanout — push-to-main fan-out driving real ArgoCD API syncs on
every cluster directly, from the Forgejo Actions vault (cf-139 reopen2,
ruling R6: this repo-side script is the fan-out logic home, invoked by the
main-sync sync-fanout job from the checkout; no relay, no in-cluster part).

The fleet keeps syncPolicy.automated off on every root app by owner ruling
(cf-139 OQ1), so this script calls each cluster's sync API itself. Semantics
port 1:1 from the shipped relay's main.py (root-first -> settle -> re-list
-> children sweep, byte repoURL + live targetRevision match, prune=false in
query AND body, 409 = success, per-target isolation); the HTTP/HMAC/event
layers drop, the vault parsing and the ThreadPool fan-out are new.

Exit posture (DECISIONS 2026-11-23, refined vs the relay's all-warn rule):
0 runtime-green (per-target failures audit honestly, next push self-heals),
1 config/setup RED (a typo'd category must not silently lose a cluster),
2 argparse usage. Tokens arrive ONLY as the ARGOCD_SYNC_TOKENS environment
variable — never argv, never files — and are never echoed by any output.
"""

import argparse
import concurrent.futures
import json
import os
import re
import sys
import time
from urllib import error as urlerror
from urllib import parse as urlparse
from urllib import request as urlrequest

# Target names land verbatim in the audit lines operators grep, so the roster
# is restricted to what that parser accepts: [A-Za-z0-9_.-]+
TARGET_NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+$")

# ArgoCD local-account tokens are JWTs: base64url segments joined by dots,
# no whitespace/commas in practice (RESEARCH [30][31]) — a record failing
# this shape is a paste or typo, caught at parse time, not a silent 401.
JWT_RE = re.compile(r"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_.-]+$")

TOKENS_ENV = "ARGOCD_SYNC_TOKENS"
ROSTER_KEYS = {"allowed_refs", "tracked_repo", "settle_seconds",
               "target_timeout_seconds", "parallel_workers", "targets"}


class ConfigError(Exception):
    """Config/secret problem. Reasons name files, categories and fields,
    never contents."""


class TargetError(Exception):
    """Per-target fan-out failure; isolated so one dead cluster never
    aborts the rest."""


def log(line):
    print("%s %s" % (time.strftime("%Y-%m-%dT%H:%M:%S"), line), flush=True)


def load_roster(path):
    try:
        with open(path) as f:
            raw = json.load(f)
    except OSError as e:
        raise ConfigError("%s: %s" % (path, e.strerror or e.__class__.__name__))
    except json.JSONDecodeError:
        raise ConfigError("%s is not valid JSON" % path)
    if not isinstance(raw, dict):
        raise ConfigError("roster top level must be an object")
    missing = ROSTER_KEYS - set(raw)
    if missing:
        raise ConfigError("roster missing required fields: %s" % ", ".join(sorted(missing)))
    # Extras go red too (review m3): symmetric with the per-target key check,
    # so a relay-era leftover (clusterHosts, tokenKey...) cannot linger
    # green through the disposal wave.
    extra = set(raw) - ROSTER_KEYS
    if extra:
        raise ConfigError("roster has unknown top-level keys: %s" % ", ".join(sorted(extra)))

    refs = raw["allowed_refs"]
    if not isinstance(refs, list) or not all(isinstance(r, str) and r for r in refs):
        raise ConfigError('allowed_refs must be a list of full refs, e.g. ["refs/heads/main"]')
    if not refs:
        # Red, not a silent green-off (review m2): an empty list would gate
        # every push to zero dials forever — the exact class the config-red
        # posture exists for.
        raise ConfigError("allowed_refs must list at least one full ref")
    for r in refs:
        if not r.startswith("refs/"):
            raise ConfigError("allowed_refs entry %r is not a full ref (must start with refs/)" % r)
        if r.startswith("refs/tags/"):
            raise ConfigError("allowed_refs must not list refs/tags/* — tag pushes never fire")

    for key, lo in (("settle_seconds", 0.0), ("target_timeout_seconds", 0.1),
                    ("parallel_workers", 1)):
        v = raw[key]
        # v != v rejects NaN and the upper bound rejects Infinity without
        # importing math (outside the pinned import budget); the bound also
        # keeps a typo from parking a worker for hours under the 30-min job
        # ceiling.
        if not isinstance(v, (int, float)) or isinstance(v, bool) or v < lo or v != v or v >= 3600:
            raise ConfigError("roster %s must be a finite number in [%g, 3600)" % (key, lo))
        if key == "parallel_workers" and v != int(v):
            raise ConfigError("roster parallel_workers must be a whole number, not %r" % v)

    tracked = raw["tracked_repo"]
    if not isinstance(tracked, str) or not tracked:
        raise ConfigError("tracked_repo must be a non-empty string")

    targets = raw["targets"]
    if not isinstance(targets, list) or not targets:
        raise ConfigError("targets must be a non-empty list")
    out = []
    seen = set()
    for i, t in enumerate(targets):
        if not isinstance(t, dict) or set(t) != {"name", "url", "root_app"}:
            raise ConfigError("targets[%d] must be an object with exactly name/url/root_app" % i)
        for k in ("name", "url", "root_app"):
            v = t[k]
            if not isinstance(v, str) or not v:
                raise ConfigError("targets[%d] needs a non-empty string %s" % (i, k))
        if not TARGET_NAME_RE.match(t["name"]):
            raise ConfigError("targets[%d].name %r must match %s" % (i, t["name"], TARGET_NAME_RE.pattern))
        if not t["url"].startswith(("http://", "https://")):
            raise ConfigError("targets[%d].url must start with http:// or https://" % i)
        if t["name"] in seen:
            raise ConfigError("duplicate target name %r" % t["name"])
        seen.add(t["name"])
        # rstrip("/") ported from the relay: URL and path concatenation
        # would otherwise double-slash on the first operator-added trailing
        # slash (and the stub-based suite pins byte paths).
        out.append({"name": t["name"], "url": t["url"].rstrip("/"), "root_app": t["root_app"]})

    return {"allowed_refs": refs, "tracked_repo": tracked,
            "settle": float(raw["settle_seconds"]),
            "timeout": float(raw["target_timeout_seconds"]),
            "workers": int(raw["parallel_workers"]),
            "targets": out}


def parse_vault(roster_names):
    raw = os.environ.get(TOKENS_ENV)
    if raw is None or not raw.strip():
        raise ConfigError("%s is empty or unset: expected newline cat:token records" % TOKENS_ENV)
    tokens = {}
    # OQ8 ruled newline cat:token records (per-line masking, RESEARCH [26]);
    # the [,\s]+ split is paste-accident defense, not an advertised style.
    # Tearing a value is impossible: JWTs contain no whitespace/commas and
    # categories contain none either, so delimiters can only sit BETWEEN
    # records. The first ":" splits category from token.
    for rec in re.split(r"[,\s]+", raw.strip()):
        if not rec:
            continue
        if ":" not in rec:
            raise ConfigError('vault record without a ":" separator (expected cat:token per line)')
        cat, _, tok = rec.partition(":")
        if cat not in roster_names:
            # A reversed "token:cat" paste lands the JWT in the category
            # slot; echoing it would print the whole token to stderr —
            # unmasked in CI, since [26] registers secret LINES and this
            # value is the line minus its tail. Real typos stay informative;
            # the echo is bounded because an unbounded field is a log-spam
            # surface too.
            if JWT_RE.match(cat):
                raise ConfigError("vault record looks reversed (token before category) — expected cat:token")
            raise ConfigError('record for unknown category "%s"' % cat[:64])
        if cat in tokens:
            raise ConfigError('duplicate vault record for category "%s"' % cat)
        if not JWT_RE.match(tok):
            raise ConfigError('token for "%s" is not JWT-shaped' % cat)
        tokens[cat] = tok
    # Set equality BOTH directions, loud: RESEARCH Implications 4 names the
    # typo'd-category class (a vault record that silently matches no roster
    # target) as the fan-out's one new silent failure — losing a cluster
    # every push forever. It goes RED here, never warn-and-green.
    for cat in sorted(roster_names - set(tokens)):
        raise ConfigError('roster target "%s" has no token' % cat)
    return tokens


def ref_tail(ref):
    # Audit lines keep the FULL ref; eligibility compares the tail (shipped
    # relay asymmetry kept on purpose — operators read full refs, clusters
    # store branch names).
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
    # Byte-compare against the CONFIG tracked_repo, never against anything a
    # payload carries: a widened stage push can never sync-fire prod clusters.
    return any(s.get("repoURL") == repo and s.get("targetRevision") == tail
               for s in app_sources(app))


def app_sync_status(app):
    # Unknown (not None): a fresh Missing app must still be synced, matching
    # the child filter "status != Synced".
    status = ((app.get("status") or {}).get("sync") or {}).get("status")
    return status if isinstance(status, str) and status else "Unknown"


class _NoRedirect(urlrequest.HTTPRedirectHandler):
    # Review M2, coord-ruled deviation from the 1:1 port: the default opener
    # follows 3xx, copying Authorization to the redirect target, and a POST
    # turned into a GET by 301/302/303 would audit the landed HTML page as
    # sync success. The relay dialed mesh hosts; the fan-out dials
    # SSO-fronted routes whose live shape IS a 307 to login. Bearer
    # containment and an unearnable result=ok outrank fidelity, so 3xx
    # raises into the existing failed lanes.
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_NO_REDIRECT_OPENER = urlrequest.build_opener(_NoRedirect)


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
    return _NO_REDIRECT_OPENER.open(req, timeout=timeout)


def list_applications(target, token, timeout):
    url = target["url"] + "/api/v1/applications"
    try:
        with api_request("GET", url, token.encode(), timeout) as resp:
            payload = json.load(resp)
    except urlerror.HTTPError as e:
        raise TargetError("applications list HTTP %d" % e.code)
    except Exception as e:
        raise TargetError("applications list failed: %s" % _reason(e))
    items = payload.get("items") if isinstance(payload, dict) else None
    if not isinstance(items, list):
        raise TargetError("applications list had no items array")
    return items


def sync_application(target, token, timeout, name):
    url = "%s/api/v1/applications/%s/sync?prune=false" % (target["url"], urlparse.quote(name, safe=""))
    # prune=false in BOTH query and body: the grpc-gateway maps query params
    # onto SyncRequest fields while CLI-shaped clients read the body —
    # pinning both leaves no path for a server-side default (OQ6: never
    # prune, never force).
    try:
        with api_request("POST", url, token.encode(), timeout, {"prune": False}):
            return "synced"
    except urlerror.HTTPError as e:
        try:
            detail = e.read().decode("utf-8", "replace")
        except Exception:
            detail = ""
        # 409 / "another operation is already in progress" IS success: that
        # operation syncs the same git state with the same non-prune
        # semantics.
        if e.code == 409 or "already in progress" in detail:
            return "in-progress"
        raise TargetError("sync HTTP %d" % e.code)
    except Exception as e:
        raise TargetError("sync failed: %s" % _reason(e))


def _reason(exc):
    return str(exc) or exc.__class__.__name__


def drive_target(cfg, target, token, tail, dry=False):
    """(result, detail) tuple return ported from the relay: "ok" / "skipped"
    / "dry", with the detail strings pinned by the operator-grepped audit
    grammar. Runtime failures raise TargetError and are caught in fan_out —
    the relay's drive/fan split, kept."""
    items = list_applications(target, token, cfg["timeout"])
    root = target["root_app"]
    eligible = {app_name(a) for a in items if app_matches(a, cfg["tracked_repo"], tail)}

    if dry:
        # Reachability + eligibility report only (the runbook smoke and the
        # proxy-backup preflight row): GETs, zero POSTs, no settle, no sweep.
        would = sum(1 for a in items
                    if app_name(a) and app_name(a) != root
                    and app_matches(a, cfg["tracked_repo"], tail)
                    and app_sync_status(a) != "Synced")
        state = "eligible" if root in eligible else "not-eligible"
        return "dry", "root %s, would-sync %d children" % (state, would)

    if root not in eligible:
        # Skipping here is the OQ7 guarantee: a widened stage push can never
        # sync-fire a cluster whose root tracks a different revision.
        return "skipped", "root app %s does not track revision %s" % (root, tail)

    root_phase = sync_application(target, token, cfg["timeout"], root)

    # Settle, then re-list: syncing the root regenerates the child
    # Applications from the new git, so the child pass is judged entirely on
    # this fresh listing, never the pre-sync snapshot.
    time.sleep(cfg["settle"])
    items = list_applications(target, token, cfg["timeout"])
    children = 0
    for a in items:
        name = app_name(a)
        if not name or name == root:
            continue
        if app_matches(a, cfg["tracked_repo"], tail) and app_sync_status(a) != "Synced":
            sync_application(target, token, cfg["timeout"], name)
            children += 1
    return "ok", "root %s, %d children synced" % (root_phase, children)


def fan_out(cfg, tokens, ref, dry=False):
    tail = ref_tail(ref)
    counts = {"ok": 0, "skipped": 0, "failed": 0}

    def one(target):
        # Each worker owns its target's full root->settle->children sequence;
        # the pool parallelizes BETWEEN targets only. The relay's dual catch
        # keeps one dead cluster (e.g. the ruled warn-and-skip proxy-backup,
        # OQ9) to an honest failed line, and elapsed measures real worker
        # time on those lanes — timeout included, never 0.
        token = tokens[target["name"]]
        started = time.monotonic()
        try:
            result, detail = drive_target(cfg, target, token, tail, dry=dry)
        except TargetError as e:
            result, detail = "failed", str(e)
        except Exception as e:
            result, detail = "failed", "%s: %s" % (e.__class__.__name__, _reason(e))
        return target, result, detail, time.monotonic() - started

    with concurrent.futures.ThreadPoolExecutor(max_workers=cfg["workers"]) as ex:
        # as_completed prints each target's line the moment its worker
        # finishes: global audit-line order is deliberately not pinned
        # (per-target request order is what the suite asserts server-side).
        for future in concurrent.futures.as_completed(ex.submit(one, t) for t in cfg["targets"]):
            target, result, detail, elapsed = future.result()
            if dry:
                log("target=%s dry-run root=%s ref=%s elapsed=%.1fs detail=%s"
                    % (target["name"], target["root_app"], ref, elapsed, detail))
                continue
            log("target=%s result=%s root=%s ref=%s elapsed=%.1fs detail=%s"
                % (target["name"], result, target["root_app"], ref, elapsed, detail))
            counts[result] += 1

    if dry:
        return counts
    log("fan-out summary: targets=%d ok=%d skipped=%d failed=%d"
        % (len(cfg["targets"]), counts["ok"], counts["skipped"], counts["failed"]))
    if counts["skipped"] == len(cfg["targets"]):
        # The trackedRepo-mismatch trap ([P §3]): matching nothing anywhere is
        # almost certainly a drifted tracked_repo, not an empty fleet — stay
        # green (the push landed) but announce. Printed at column 0, not via
        # log(): the runner's annotation grammar is line-anchored (review m1).
        print("::warning::all %d targets skipped — nothing matched tracked_repo+ref; check the roster against the clusters' live app sources"
              % len(cfg["targets"]), flush=True)
    return counts


def cmd_check(cfg, tokens):
    # Offline by contract: parse roster + vault fully, print the table,
    # open zero sockets (--dry-run is the dialing mode).
    print("argocd-fanout --check: OK")
    print("allowed_refs: %s" % ", ".join(cfg["allowed_refs"]))
    print("tunables: settle_seconds=%g target_timeout_seconds=%g parallel_workers=%d"
          % (cfg["settle"], cfg["timeout"], cfg["workers"]))
    print("targets:")
    print("  %-14s %s" % ("NAME", "URL"))
    for t in cfg["targets"]:
        print("  %-14s %s" % (t["name"], t["url"]))
    print("vault: %d records matched to the roster (values never printed)" % len(tokens))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="argocd-fanout",
        description="vault-direct ArgoCD sync fan-out (caller: the Forgejo main-sync sync-fanout job; "
                    "token values come only from the ARGOCD_SYNC_TOKENS environment variable)")
    parser.add_argument("--config", default="scripts/argocd-fanout.json",
                        help="roster JSON path (checkout-borne)")
    parser.add_argument("--ref", default="refs/heads/main",
                        help="full git ref of the push (non-secret)")
    parser.add_argument("--check", action="store_true",
                        help="parse roster + vault fully, print the table, exit; zero network")
    parser.add_argument("--dry-run", action="store_true", dest="dry_run",
                        help="live GETs only: eligibility + would-sync per target, zero POSTs")
    args = parser.parse_args(argv)

    try:
        cfg = load_roster(args.config)
        tokens = parse_vault({t["name"] for t in cfg["targets"]})
    except ConfigError as e:
        # Setup errors name categories and fields, never values (AC8): the
        # message goes to stderr, the job goes RED (ruled posture).
        print("argocd-fanout config: %s" % e, file=sys.stderr)
        return 1

    if args.check:
        return cmd_check(cfg, tokens)

    if args.ref not in cfg["allowed_refs"]:
        # The gate is the OQ7 widening guarantee and a designed no-op, not an
        # error: one line naming the rejected ref, zero API calls, green.
        log("ref %s is not in allowed_refs — fan-out skipped (no API calls)" % args.ref)
        return 0

    fan_out(cfg, tokens, args.ref, dry=args.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main())
