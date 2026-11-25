#!/usr/bin/env python3
"""argocd-fanout — push-to-main fan-out driving real ArgoCD API syncs on
every cluster directly (cf-139 R7: repo-side fan-out home, invoked by the
main-sync sync-fanout job; targets DISCOVERED from ARGOCD_SYNC_<CAT>_URL
and _TOKEN Actions key pairs — org vars plus per-secret tokens; no blob
vault, no roster endpoint list).

The fleet keeps syncPolicy.automated off on every root app by owner ruling
(cf-139 OQ1), so this script calls each cluster's sync API itself. Semantics
port 1:1 from the shipped relay's main.py (root-first -> settle -> re-list
-> children sweep, byte repoURL + live targetRevision match, prune=false in
query AND body, 409 = success, per-target isolation); the HTTP/HMAC/event
layers drop, and the env-pair discovery plus the ThreadPool fan-out are new.

Exit posture (DECISIONS 2026-11-23, refined vs the relay's all-warn rule):
0 runtime-green (per-target failures audit honestly, next push self-heals),
1 config/setup RED (a typo'd category must not silently lose a cluster),
2 argparse usage. Token values arrive ONLY through the
ARGOCD_SYNC_<CAT>_TOKEN keys — never argv, never files, never echoed.
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

# R7 endpoint pairs: the broad shape catches every enumeration row the job
# can receive; SEG/CAT then decide legitimacy — single-underscore joins
# make the upper-snake -> hyphen category mapping injective, so a real
# category with an underscore is unrepresentable by design (runbook §8).
PAIR_KEY_RE = re.compile(r"^ARGOCD_SYNC_(.+)_(URL|TOKEN)$")
SEG_RE = re.compile(r"^[A-Z0-9](?:_?[A-Z0-9])*$")
CAT_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$")

# ArgoCD local-account tokens are JWTs: base64url segments joined by dots
# (RESEARCH [30][31]) — a failing value is a paste or typo, caught here,
# not a silent 401.
JWT_RE = re.compile(r"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_.-]+$")

# Kill-lane line, pinned byte-exact (micro-call a); column 0 because the
# runner's annotation grammar is line-anchored (review m1).
WARN_NOT_CONFIGURED = ("::warning::sync-fanout not configured (no "
                       "ARGOCD_SYNC_*_TOKEN keys with values) — fan-out "
                       "skipped, manual sync or the next push covers it")

# Discovery's designed skip-and-green when no TOKEN key carries a value:
# §7's kill lever — deleting/blanking the org TOKEN secrets suffices, URL
# residue may stay populated.
NOT_CONFIGURED = object()

ROSTER_KEYS = {"allowed_refs", "tracked_repo", "settle_seconds",
               "target_timeout_seconds", "parallel_workers"}


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
    # Extras go red too (review m3): symmetric with the per-target key
    # check, so leftovers (clusterHosts, tokenKey, reopen2's targets[])
    # cannot linger green — R7 deleted the endpoint list with no shim.
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

    return {"allowed_refs": refs, "tracked_repo": tracked,
            "settle": float(raw["settle_seconds"]),
            "timeout": float(raw["target_timeout_seconds"]),
            "workers": int(raw["parallel_workers"])}


def discover_targets(env):
    """R7: the environment IS the endpoint list.

    Broad-scan the pair keys, strict-validate segment and derived category
    (regex laws above): a malformed name carrying a value is RED naming
    the RAW KEY — an ignored typo'd enumeration row would re-open the
    silent-cluster-loss class this posture exists for; empty malformed
    residue is unattempted: ignored, unechoed; a double-empty fully-
    enumerated row in a CONFIGURED fleet is a ruling-(j) violation. Empty
    string == absent, since static enumeration passes unset org keys
    through empty. Lane order (DECISIONS 2026-11-25 a/b/c/i/j):
    malformed-with-value outranks even the all-absent kill lane (a typo'd
    TOKEN row must never warn-green a cluster away); the TOKEN side alone
    decides configured-vs-kill; the configured lane demands per category a
    non-empty URL (scheme, no @/query, slash normalized — relay port) and
    a non-empty JWT-shaped TOKEN, COLLECTING all violations into ONE
    category-sorted ConfigError (first-error-raise hides half a broken
    fleet). Returns {"targets" (root_app == category), "tokens"} or
    NOT_CONFIGURED; errors name keys and categories, never values.
    """
    malformed = []
    sides = {}
    for key, value in env.items():
        m = PAIR_KEY_RE.match(key)
        if not m:
            # Outside the pair shape — the dead ARGOCD_SYNC_TOKENS blob name
            # among them — matches nothing, by construction, and stays silent.
            continue
        seg, side = m.group(1), m.group(2)
        cat = seg.lower().replace("_", "-")
        if not (SEG_RE.match(seg) and CAT_RE.match(cat)):
            if value:
                malformed.append(key)
            continue
        sides.setdefault(cat, {})[side] = value
    if malformed:
        raise ConfigError("malformed ARGOCD_SYNC_* enumeration keys with values: %s — keys must be ARGOCD_SYNC_<CATEGORY>_<URL|TOKEN> with an upper-snake category" % ", ".join(sorted(malformed)))
    if not any(v for s in sides.values() for k, v in s.items() if k == "TOKEN"):
        return NOT_CONFIGURED
    targets, tokens, violations = [], {}, []
    for cat in sorted(sides):
        spec = sides[cat]
        url = spec.get("URL") or ""
        tok = spec.get("TOKEN") or ""
        if not url and not tok:
            # Ruling (j): a fully-enumerated both-empty row in a CONFIGURED
            # fleet is key-only-delete residue whose workflow row survived —
            # RED in the sorted aggregate, never unattempted-green (a row
            # without BOTH names present stays unattempted). The kill-lane
            # fleets returned above: paste-pending and the whole-fleet §7
            # lever stay byte-exact warn-green.
            if "URL" in spec and "TOKEN" in spec:
                violations.append('category "%s" enumerated but both values empty' % cat)
            continue
        if not tok:
            violations.append('category "%s" missing TOKEN value' % cat)
        elif not JWT_RE.match(tok):
            violations.append('category "%s" token is not JWT-shaped' % cat)
        if not url:
            violations.append('category "%s" missing URL value' % cat)
        elif not url.startswith(("http://", "https://")):
            violations.append('category "%s" URL must start with http(s)://' % cat)
        elif "@" in url or "?" in url:
            violations.append('category "%s" URL must not carry @ userinfo or a query' % cat)
        else:
            targets.append({"name": cat, "url": url.rstrip("/"), "root_app": cat})
            tokens[cat] = tok
    if violations:
        raise ConfigError("pair integrity: %s" % "; ".join(sorted(violations)))
    return {"targets": targets, "tokens": tokens}


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
    # Offline by contract: parse roster + discovered pairs fully, print the
    # table, open zero sockets (--dry-run is the dialing mode).
    print("argocd-fanout --check: OK")
    print("allowed_refs: %s" % ", ".join(cfg["allowed_refs"]))
    print("tunables: settle_seconds=%g target_timeout_seconds=%g parallel_workers=%d"
          % (cfg["settle"], cfg["timeout"], cfg["workers"]))
    print("targets:")
    print("  %-14s %s" % ("NAME", "URL"))
    for t in cfg["targets"]:
        print("  %-14s %s" % (t["name"], t["url"]))
    print("pairs: %d targets discovered (values never printed)" % len(cfg["targets"]))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="argocd-fanout",
        description="env-discovered ArgoCD sync fan-out (caller: the Forgejo main-sync sync-fanout job; endpoints and tokens come only from ARGOCD_SYNC_<CATEGORY>_URL/_TOKEN environment keys)")
    parser.add_argument("--config", default="scripts/argocd-fanout.json",
                        help="roster JSON path (checkout-borne; the five globals only)")
    parser.add_argument("--ref", default="refs/heads/main",
                        help="full git ref of the push (non-secret)")
    parser.add_argument("--check", action="store_true",
                        help="parse roster + env pairs fully, print the table, exit; zero network")
    parser.add_argument("--dry-run", action="store_true", dest="dry_run",
                        help="live GETs only: eligibility + would-sync per target, zero POSTs")
    args = parser.parse_args(argv)

    try:
        cfg = load_roster(args.config)
        discovered = discover_targets(os.environ)
    except ConfigError as e:
        # Setup errors name keys, categories and fields, never values (AC8):
        # the message goes to stderr, the job goes RED (ruled posture).
        print("argocd-fanout config: %s" % e, file=sys.stderr)
        return 1

    if discovered is NOT_CONFIGURED:
        # Before the ref gate and any output shape: an unconfigured fleet is
        # the designed green skip — exactly the one column-0 line, zero
        # sockets, no table, no summary (the kill lever's proof-of-off).
        print(WARN_NOT_CONFIGURED, flush=True)
        return 0

    cfg["targets"] = discovered["targets"]
    tokens = discovered["tokens"]

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
