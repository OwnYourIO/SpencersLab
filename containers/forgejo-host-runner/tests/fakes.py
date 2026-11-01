"""In-process test doubles (stdlib http.server only, AC2: no network).

FakeImmichServer is the contract-pinned fixture-E2E spine — it serves the v3
shapes RESEARCH.md R2.3 verified: paginated GET /albums?isOwned=true, POST
/search/metadata {albumIds, type:IMAGE} with a paginated assets envelope, and
GET /assets/{id}/thumbnail. It records every request so tests assert wire
facts the contract pins (x-api-key header, retry counts, page walking)
instead of reaching into module internals.

Path handling: the contract says the client composes calls under IMMICH_URL;
the real API base is {url}/api. Both mountings answer identically so the
fake pins the endpoint semantics, not a URL-prefix guess.
"""

import json
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

THUMB_BYTES = (Path(__file__).resolve().parent / "fixtures" / "derivative-seed.jpg").read_bytes()


class _Recording:
    def __init__(self, method, path, headers, body):
        self.method = method
        self.path = path
        self.headers = headers  # BaseHTTPRequestHandler.headers (case-insensitive Message)
        self.body = body

    def __repr__(self):
        return f"<{self.method} {self.path}>"


class _BaseServer:
    def __init__(self):
        self.requests = []

    def start(self):
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def stop(self):
        self.httpd.shutdown()
        self.httpd.server_close()

    def _record(self, handler, body=None):
        rec = _Recording(handler.command, handler.path, handler.headers, body)
        self.requests.append(rec)
        return rec

    def hits(self, method, needle):
        return [r for r in self.requests if r.method == method and needle in r.path]


class FakeImmichServer(_BaseServer):
    """albums: list of album DTOs, each carrying its assets under the
    private '_assets' key (search joins through it).

    Behavior hooks (t3/t4/t12):
      max_search_page_size — cap items per search page (pagination leg)
      thumbnail_5xx_once   — {asset_id}: first thumbnail GET returns 500
      thumbnail_404        — {asset_id}: every thumbnail GET returns 404
      last_modified        — {album_id: value}: live album-probe overrides
    """

    def __init__(self, albums, api_key, max_search_page_size=None):
        super().__init__()
        self.albums = albums
        self.api_key = api_key
        self.max_search_page_size = max_search_page_size
        self.thumbnail_5xx_once = set()
        self.thumbnail_404 = set()
        self._failed_once = set()
        self.last_modified = {}
        outer = self

        class Handler(BaseHTTPRequestHandler):
            # ThreadingHTTPServer races are impossible here: each test owns
            # one server and the append happens before the response starts.
            def log_message(self, *args):
                pass

            def _send(self, status, obj=None, raw=None, content_type="application/json"):
                payload = raw if raw is not None else json.dumps(obj).encode()
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def _authorized(self):
                # Contract pins the Immich header name; a Bearer-style client
                # would fall through to 401 and the run must fail loud.
                return self.headers.get("x-api-key") == outer.api_key

            def do_GET(self):
                path = re.sub(r"^/api", "", self.path.split("?")[0])
                query = self.path.split("?")[1] if "?" in self.path else ""
                rec = outer._record(self)
                if not self._authorized():
                    self._send(401, {"error": "unauthorized", "detail": "x-api-key required"})
                    return
                if path == "/albums":
                    self._send(200, outer.albums_payload(query))
                    return
                m = re.fullmatch(r"/assets/([^/]+)/thumbnail", path)
                if m:
                    aid = m.group(1)
                    if aid in outer.thumbnail_404:
                        self._send(404, {"error": "not-found"})
                        return
                    if aid in outer.thumbnail_5xx_once and aid not in outer._failed_once:
                        outer._failed_once.add(aid)
                        self._send(500, {"error": "boom-once"})
                        return
                    if aid not in outer.asset_ids():
                        self._send(404, {"error": "not-found"})
                        return
                    self._send(200, raw=THUMB_BYTES, content_type="image/jpeg")
                    return
                self._send(404, {"error": f"unmapped GET {path} ({query})"})

            def do_POST(self):
                path = re.sub(r"^/api", "", self.path)
                length = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(length) if length else b""
                try:
                    body = json.loads(raw) if raw else {}
                except ValueError:
                    body = {}
                outer._record(self, body=body)
                if not self._authorized():
                    self._send(401, {"error": "unauthorized"})
                    return
                if path == "/search/metadata":
                    self._send(200, outer.search_payload(body))
                    return
                self._send(404, {"error": f"unmapped POST {path}"})

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.base_url = "http://127.0.0.1:%d" % self.httpd.server_address[1]

    def asset_ids(self):
        return {a["id"] for al in self.albums for a in al["_assets"]}

    def albums_payload(self, query):
        page = int(_q(query, "page", 1))
        # One page holds every fixture album; nextPage null ends the walk.
        return {
            "albums": self.albums_view(),
            "count": len(self.albums),
            "nextPage": None,
            "hasPreviousPage": False,
            "hasNextPage": False,
        }

    def albums_view(self):
        out = []
        for al in self.albums:
            view = {k: v for k, v in al.items() if not k.startswith("_")}
            if al["id"] in self.last_modified:
                view["lastModifiedAssetTimestamp"] = self.last_modified[al["id"]]
            out.append(view)
        return out

    def search_payload(self, body):
        ids = set(body.get("albumIds") or ([body["albumId"]] if "albumId" in body else []))
        want_type = body.get("type")
        items = [
            a
            for al in self.albums
            if al["id"] in ids
            for a in al["_assets"]
            if want_type in (None, a["type"])
        ]
        page = int(body.get("page") or 1)
        size = int(body.get("size") or body.get("pageSize") or self.max_search_page_size or len(items) or 1)
        if self.max_search_page_size:
            size = min(size, self.max_search_page_size)
        start = (page - 1) * size
        window = items[start : start + size]
        more = start + size < len(items)
        return {
            "assets": {
                "items": window,
                "count": len(window),
                "total": len(items),
                # v3 SearchAssetResponseDto serializes ONLY nextPage (null
                # when done) — no hasNextPage on the wire, so a client that
                # reintroduces that dependency truncates here and t04 goes red.
                "nextPage": str(page + 1) if more else None,
                "hasPreviousPage": page > 1,
            },
            "albums": [],
        }


def _api_paths(path):
    """Strip the /api and /v1 mount prefixes so the fake's route table can
    speak resource paths only (clients may compose {base}/api/v1/...)."""
    return re.sub(r"^/api(?=/|$)(/v1(?=/|$))?", "", path)


class _ForgejoHandler(BaseHTTPRequestHandler):
    """PR-surface handler for FakeForgejoServer; state via server.state —
    module-level so the fake stays one reviewable piece per class."""

    def log_message(self, *args):
        pass

    def _send(self, status, obj):
        payload = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _authed(self):
        return self.headers.get("Authorization") == f"token {self.server.state.pat}"

    def _read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw) if raw else {}
        except ValueError:
            return raw.decode("utf-8", "replace")

    def do_GET(self):
        outer = self.server.state
        rec = outer._record(self)
        if not self._authed():
            self._send(401, {"error": "unauthorized"})
            return
        if re.fullmatch(r"/repos/[^/]+/[^/]+/pulls", _api_paths(self.path.split("?")[0])):
            self._send(200, outer.prs)
            return
        self._send(404, {"error": f"unmapped GET {rec.path}"})

    def do_POST(self):
        outer = self.server.state
        body = self._read_body()
        outer._record(self, body=body)
        if not self._authed():
            self._send(401, {"error": "unauthorized"})
            return
        path = _api_paths(self.path)
        if re.fullmatch(r"/repos/[^/]+/[^/]+/pulls", path):
            idx = len(outer.prs) + 1
            pr = {
                "index": idx,
                "number": idx,
                "title": body.get("title", ""),
                "body": body.get("body", ""),
                "state": "open",
                "head": {"name": body.get("head", ""), "ref": body.get("head", "")},
                "base": {"name": body.get("base", "main"), "ref": body.get("base", "main")},
                "html_url": f"http://forgejo.sentinel.invalid/CuratedForest/CuratedForest.com/pulls/{idx}",
            }
            outer.prs.append(pr)
            outer.created.append({"body": body, "pr": pr})
            self._send(201, pr)
            return
        self._send(404, {"error": f"unmapped POST {path}"})

    def do_PATCH(self):
        self._update("PATCH")

    def do_PUT(self):
        self._update("PUT")

    def _update(self, verb):
        outer = self.server.state
        body = self._read_body()
        outer._record(self, body=body)
        if not self._authed():
            self._send(401, {"error": "unauthorized"})
            return
        path = _api_paths(self.path)
        m = re.fullmatch(r"/repos/([^/]+)/([^/]+)/pulls/(\d+)", path)
        if not m:
            self._send(404, {"error": f"unmapped {verb} {path}"})
            return
        idx = int(m.group(3))
        pr = next((p for p in outer.prs if p["index"] == idx), None)
        if pr is None:
            self._send(404, {"error": f"no PR {idx}"})
            return
        if isinstance(body, dict) and "body" in body:
            pr["body"] = body["body"]
        outer.updated.append({"verb": verb, "index": idx, "body": body})
        self._send(200, pr)


class FakeForgejoServer(_BaseServer):
    """Forgejo PR surface: list (open), create (POST /pulls), update
    (PATCH|PUT /pulls/{index}). Authorization: token <pat> pinned by the
    contract's shared-HTTP section — anything else 401s.

    prs: pre-existing open PRs as dicts {branch, body}. html_url is served
    so publish can print the pinned PR_URL= line from the API response.
    """

    def __init__(self, prs, pat):
        super().__init__()
        self.pat = pat
        self.prs = [
            {
                "index": i + 1,
                "number": i + 1,
                "title": "immich sync",
                "body": p.get("body", ""),
                "state": "open",
                "head": {"name": p["branch"], "ref": p["branch"]},
                "base": {"name": "main", "ref": "main"},
                "html_url": f"http://forgejo.sentinel.invalid/CuratedForest/CuratedForest.com/pulls/{i + 1}",
            }
            for i, p in enumerate(prs)
        ]
        self.created = []
        self.updated = []
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), _ForgejoHandler)
        self.httpd.state = self
        self.base_url = "http://127.0.0.1:%d" % self.httpd.server_address[1]

    def pulls_hits(self):
        return [
            r
            for r in self.requests
            if re.search(r"/repos/[^/]+/[^/]+/pulls", r.path)
        ]


def _q(query, name, default):
    for part in query.split("&"):
        if part.startswith(name + "="):
            return part.split("=", 1)[1]
    return default
