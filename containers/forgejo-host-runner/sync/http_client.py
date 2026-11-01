"""Shared HTTP layer (chunks/C01.md "Shared HTTP layer"): stdlib urllib with
timeout, exactly one 5xx retry, and clean 4xx errors. `transport` is
injectable for pure fakes; the entry points run it unmodified against the
http.server-backed fakes on localhost."""

import json
import os
import time
import urllib.error
import urllib.request

DEFAULT_TIMEOUT = 30.0
RETRY_5XX = 1
RETRY_DELAY_SECONDS = 0.25
ERROR_BODY_SNIPPET = 200
CHUNK_SIZE = 65536


class HttpError(Exception):
    def __init__(self, status, url, detail=""):
        self.status = status
        self.url = url
        message = f"HTTP {status} for {url}"
        if detail:
            message += f": {detail}"
        super().__init__(message)


class Response:
    def __init__(self, status, fp):
        self.status = status
        self._fp = fp

    def read(self, size=-1):
        return self._fp.read(size)

    def close(self):
        # Idempotent: callers on the raise paths close in a finally after
        # request() may have already closed the same response.
        if self._fp is not None:
            self._fp.close()
            self._fp = None


def urllib_transport(method, url, headers, data, timeout):
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        fp = urllib.request.urlopen(request, timeout=timeout)
        return Response(fp.status, fp)
    except urllib.error.HTTPError as exc:
        # The error response carries a JSON body (Immich and Forgejo both
        # send one on 4xx/5xx), so it becomes a Response for the detail
        # snippet rather than propagating.
        return Response(exc.code, exc)


def request(method, url, *, headers=None, body=None, timeout=DEFAULT_TIMEOUT,
            transport=None, stream=False):
    """One API call with the contract's retry budget: 5xx retries once, 4xx
    fails on the first attempt (the retry budget belongs to 5xx only).
    Returns the body bytes, or (stream=True) the open Response."""
    data = json.dumps(body).encode() if body is not None else None
    out_headers = dict(headers or {})
    if data is not None:
        out_headers["Content-Type"] = "application/json"
    call = transport or urllib_transport

    response = None
    for attempt in range(RETRY_5XX + 1):
        try:
            response = call(method, url, out_headers, data, timeout)
        except (urllib.error.URLError, OSError) as exc:
            raise HttpError(0, url, str(exc)) from None
        if response.status < 500:
            break
        response.close()
        response = None
        if attempt < RETRY_5XX:
            time.sleep(RETRY_DELAY_SECONDS)
    if response is None:
        raise HttpError(500, url, "server failed after the single 5xx retry")

    if response.status >= 400:
        detail = response.read(ERROR_BODY_SNIPPET).decode("utf-8", "replace")
        response.close()
        raise HttpError(response.status, url, detail)
    if stream:
        return response
    try:
        return response.read()
    finally:
        response.close()


def json_request(method, url, **kw):
    payload = request(method, url, **kw)
    if not payload:
        return None
    return json.loads(payload)


def download(url, dest_path, *, headers=None, timeout=DEFAULT_TIMEOUT, transport=None):
    """Stream to a temp path then rename (chunks/C01.md §6): a killed run
    never leaves a half-written file at the derivative's final name."""
    response = request("GET", url, headers=headers, timeout=timeout,
                       transport=transport, stream=True)
    tmp = dest_path.parent / (dest_path.name + ".tmp")
    try:
        try:
            with open(tmp, "wb") as fh:
                while True:
                    chunk = response.read(CHUNK_SIZE)
                    if not chunk:
                        break
                    fh.write(chunk)
        except OSError:
            tmp.unlink(missing_ok=True)
            raise
    finally:
        response.close()
    try:
        os.replace(tmp, dest_path)
    except OSError:
        tmp.unlink(missing_ok=True)
        raise
