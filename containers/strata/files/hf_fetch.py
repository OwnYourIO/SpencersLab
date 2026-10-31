# The staged-fetch downloader for /opt/strata/bin/fetch_models.sh, lifted
# verbatim from the chart's model-fetch-init heredocs (C07, U9.4): bodies and
# their measured facts move with the logic, because build-verify covers a
# file, not a heredoc. One client consumes it today — the gated legs of the
# orcarouter pack (cf-86 C02, tier moved to IQ4_XS in C08). The public mode's
# only client, C01's SC117 pair, was swept in C08; the mode stays as a
# documented image surface, since deleting it re-opens the source shape the
# C02 token laws are written against for no gain (DECISIONS 2026-10-31).
#
# Call shape (the driver's leg functions are the only callers):
#
#   "$SRC/.venv/bin/python" /opt/strata/bin/hf_fetch.py <mode> <url> <part> <want-bytes>
#
# Still the CHECKOUT's venv interpreter rather than a system one: setup's own
# downloader is stdlib urllib, the venv is the interpreter the pack step
# already needs, and the image provably carries no curl (bake+verify law —
# never assume at boot a tool the build never checks).
#
# Modes:
#   anon    public bytes: Range-resume against the origin, no credential.
#   gated   gated bytes: Bearer at the token host ONLY, hops walked by hand.
#
# Why the gated walk is manual, measured 2026-10-30 (review-C02 law): the 401 +
# Bearer challenge sits at the huggingface.co ORIGIN (an invalid Bearer 401s
# before any redirect), the public chain 302s to a PRE-SIGNED
# us.aws.cdn.hf.co URL whose Signature/Expires query authorizes the CDN leg
# (Range crosses the hop: 206 Content-Range), and CPython's own
# HTTPRedirectHandler.redirect_request COPIES Authorization onto every
# cross-host hop — auto-following the chain would hand the token to the CDN.
# So the handler below returns None (the 302 surfaces as HTTPError) and each
# hop is re-opened under the platform allowlist, with the 4-hop cap.
#
# Both modes share one loop: .part staging, 4 attempts, Range resume, corrupt-
# leftover restart, and a completion check on the EXACT want-bytes (the driver
# passes a byte_pins.env literal). The caller renames .part only after this
# process exits 0, so nothing is ever marked complete on a partial.
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

if len(sys.argv) != 5 or sys.argv[1] not in ("anon", "gated"):
    sys.exit("usage: hf_fetch.py <anon|gated> <url> <part> <want-bytes>")
mode, url, part, want = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

TOKEN_HOST = "huggingface.co"
PLATFORM = (".hf.co", ".huggingface.co")


class NoAutoRedirect(urllib.request.HTTPRedirectHandler):
    # returning None surfaces the 302 as HTTPError instead of
    # urllib re-issuing the request (and its Authorization
    # header) at the next host
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


if mode == "gated":
    # R-d download-only law: the token enters this process through its own env
    # (the hf-token secretKeyRef already sits on the init container and must
    # not move or wrap) and stops here — never argv (visible in ps and in the
    # init's logs), never the pack, never the serve path.
    TOKEN = os.environ.get("HF_TOKEN")
    if not TOKEN:
        sys.exit("hf fetch (gated): HF_TOKEN is empty - the gated pack needs the hf-token secretKeyRef on this init (R-d download-only)")

opener = urllib.request.build_opener(NoAutoRedirect())


def open_anon(target, have):
    req = urllib.request.Request(target, headers={"Range": "bytes=%d-" % have} if have else {})
    return urllib.request.urlopen(req, timeout=120)


def open_gated(target, have, depth=0):
    host = urllib.parse.urlsplit(target).netloc
    headers = {"Authorization": "Bearer " + TOKEN} if host == TOKEN_HOST else {}
    if have:
        headers["Range"] = "bytes=%d-" % have
    try:
        return opener.open(urllib.request.Request(target, headers=headers), timeout=120)
    except urllib.error.HTTPError as err:
        if err.code not in (301, 302, 303, 307, 308) or depth >= 4:
            raise
        nxt = urllib.parse.urljoin(err.geturl(), err.headers.get("Location", ""))
        nh = urllib.parse.urlsplit(nxt).netloc
        if nh != TOKEN_HOST and not nh.endswith(PLATFORM):
            sys.exit("hf fetch (gated): refusing off-platform redirect %s -> %s (the token never leaves %s)" % (err.geturl(), nh, TOKEN_HOST))
        return open_gated(nxt, have, depth + 1)


open_target = open_gated if mode == "gated" else open_anon

for _ in range(4):
    have = os.path.getsize(part) if os.path.exists(part) else 0
    if have > want:
        os.remove(part); have = 0  # corrupt leftover: restart rather than wedge
    if have == want:
        break
    try:
        with open_target(url, have) as r:
            if have and r.status == 200:
                os.remove(part); have = 0  # Range ignored: restart cleanly
            with open(part, "ab" if have else "wb") as f:
                while True:
                    chunk = r.read(1048576)
                    if not chunk:
                        break
                    f.write(chunk)
    except (urllib.error.URLError, OSError) as err:
        sys.stderr.write("hf fetch (%s): attempt failed: %s (%s)\n" % (mode, err, part))
final = os.path.getsize(part) if os.path.exists(part) else 0
sys.exit(0 if final == want else "hf fetch (%s): %s ended at %d of %d bytes (partial kept for a resume)" % (mode, url, final, want))
