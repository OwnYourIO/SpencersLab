"""
Internal WeKan client used by the MCP server.

Reads WEKAN_BASE_URL plus one credential form from the environment ONCE at
process start: WEKAN_TOKEN (a pre-obtained bearer), or WEKAN_USERNAME +
WEKAN_PASSWORD, which the client exchanges for a bearer via POST /users/login
at startup and re-mints once on a 401. These values live in the server process
— NOT in tool schemas, NOT in tool arguments, NOT in tool responses (unless a
tool explicitly returns them).

Design constraints imposed by WeKan:
    - Login body is JSON, not form data (form data is documented as broken).
    - Old tokens stay valid after re-login (issue #1437), so the 401 re-mint
      is resilience against a bad/expired token, not rotation.
    - Base URL must be the site root, not ending in /api.
    - Server must be started with WITH_API=true or every call returns 401.
    - Several endpoints return HTTP 200 with an embedded error body -
      the client detects and raises on those.
    - No pagination or documented rate limiting on list endpoints.
"""

from __future__ import annotations

import os
from typing import Any, Optional

import httpx


class WekanError(Exception):
    """Raised on WeKan API failures, including HTTP 200 with embedded error bodies."""

    def __init__(self, message: str, status: Optional[int] = None, body: Any = None):
        super().__init__(message)
        self.status = status
        self.body = body


def _sanitize_error(status: int, path: str, body: Any) -> str:
    """
    Build an error message the LLM will see. NEVER include the Authorization
    header, the token, or the raw request. Body is truncated.
    """
    body_repr = ""
    if isinstance(body, dict):
        # Only surface WeKan's own error/reason fields, never headers.
        reason = body.get("reason") or body.get("error") or ""
        body_repr = f": {reason}" if reason else ""
    return f"WeKan {status} on {path}{body_repr}"


class WekanClient:
    """
    Thin authenticated wrapper around the WeKan REST API.

    Constructed once at server startup; holds the token in this process's
    memory and never surfaces it in tool schemas or responses.
    """

    def __init__(
        self,
        base_url: Optional[str] = None,
        token: Optional[str] = None,
        username: Optional[str] = None,
        password: Optional[str] = None,
        timeout: float = 30.0,
    ):
        base_url = (base_url or os.environ.get("WEKAN_BASE_URL") or "").rstrip("/")
        if not base_url:
            raise WekanError("WEKAN_BASE_URL not set")
        if base_url.endswith("/api"):
            raise WekanError(
                "WEKAN_BASE_URL must be the site root (e.g. https://boards.example.com), "
                "not ending in /api"
            )
        token = token or os.environ.get("WEKAN_TOKEN")
        username = username or os.environ.get("WEKAN_USERNAME")
        password = password or os.environ.get("WEKAN_PASSWORD")
        # Stored even when a token wins: request() re-mints on a 401 only if
        # the pair is available.
        self._creds: Optional[tuple[str, str]] = (
            (username, password) if username and password else None
        )
        if not token and not self._creds:
            raise WekanError(
                "WEKAN_TOKEN not set, and no WEKAN_USERNAME/WEKAN_PASSWORD pair "
                "to mint one with. Inject a pre-obtained bearer as WEKAN_TOKEN, "
                "or a password-based service account as the pair."
            )

        self._base_url = base_url
        headers = {"Accept": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        self._client = httpx.Client(
            base_url=base_url,
            headers=headers,
            timeout=timeout,
        )
        self.user_id: Optional[str] = None
        if not token:
            self.login()

    def login(self) -> None:
        """
        Mint a bearer token from the stored username/password pair via
        POST /users/login and install it on the shared client's headers.

        Calls httpx directly rather than request() so that request()'s
        refresh-on-401 cannot recurse into login on a rejecting server; a
        failed login surfaces as an error, never as another login attempt.
        Neither the password nor a minted token may reach a message or log —
        only WeKan's own reason field is surfaced, via _sanitize_error.
        """
        if self._creds is None:
            raise WekanError("No WEKAN_USERNAME/WEKAN_PASSWORD pair to mint a token with")
        username, password = self._creds
        try:
            resp = self._client.post(
                "/users/login", json={"username": username, "password": password}
            )
        except httpx.HTTPError as e:
            raise WekanError(f"WeKan login network error: {type(e).__name__}") from None

        try:
            parsed = resp.json() if resp.content else None
        except ValueError:
            parsed = None

        if resp.status_code >= 400:
            raise WekanError(
                _sanitize_error(resp.status_code, "/users/login", parsed),
                status=resp.status_code,
                body=None,  # never retain the login body; it can reflect account data
            )
        minted = parsed.get("token") if isinstance(parsed, dict) else None
        if not minted:
            raise WekanError(
                "WeKan /users/login returned no token (embedded error or "
                "unexpected response shape)",
                status=resp.status_code,
                body=None,
            )
        self._client.headers["Authorization"] = f"Bearer {minted}"

    def validate(self) -> dict:
        """
        Confirms the token works and populates self.user_id. Called once at startup.
        Fails fast with a clear message if the token is bad or WITH_API is off.
        """
        me = self.request("GET", "/api/user")
        if isinstance(me, dict):
            self.user_id = me.get("_id")
        return me if isinstance(me, dict) else {}

    def close(self) -> None:
        self._client.close()

    def _send(
        self,
        method: str,
        path: str,
        json_body: Any,
        params: Optional[dict],
        headers: Optional[dict],
    ) -> httpx.Response:
        try:
            return self._client.request(
                method, path, json=json_body, params=params, headers=headers
            )
        except httpx.HTTPError as e:
            # Don't leak the URL structure or headers.
            raise WekanError(f"WeKan network error on {method} {path}: {type(e).__name__}") from None

    def request(
        self,
        method: str,
        path: str,
        json_body: Any = None,
        params: Optional[dict] = None,
    ) -> Any:
        if not path.startswith("/"):
            path = "/" + path
        headers = {}
        if json_body is not None:
            headers["Content-Type"] = "application/json"
        headers = headers or None
        resp = self._send(method, path, json_body, params, headers)
        # Refresh-on-401: exactly one re-mint and retry, and only when a
        # credential pair exists to re-mint from. The retry is not re-guarded,
        # so a second 401 falls through to the raise below.
        if resp.status_code == 401 and self._creds is not None:
            self.login()
            resp = self._send(method, path, json_body, params, headers)

        # Parse body first so error paths can include a sanitized snippet.
        try:
            parsed = resp.json() if resp.content else None
        except ValueError:
            parsed = None

        if resp.status_code == 401:
            raise WekanError(
                f"WeKan 401 on {path}. Token invalid/expired or WITH_API is off.",
                status=401,
                body=None,  # deliberately omit body — some servers reflect auth headers
            )
        if resp.status_code >= 400:
            raise WekanError(
                _sanitize_error(resp.status_code, path, parsed),
                status=resp.status_code,
                body=parsed,
            )

        # HTTP 200 with embedded error is a WeKan pattern.
        if isinstance(parsed, dict) and "error" in parsed and "reason" in parsed:
            raise WekanError(
                f"WeKan embedded error on {path}: {parsed.get('reason')}",
                status=resp.status_code,
                body=parsed,
            )

        return parsed

    def get(self, path: str, **kw): return self.request("GET", path, **kw)
    def post(self, path: str, json_body: Any = None, **kw): return self.request("POST", path, json_body=json_body, **kw)
    def put(self, path: str, json_body: Any = None, **kw): return self.request("PUT", path, json_body=json_body, **kw)
    def delete(self, path: str, **kw): return self.request("DELETE", path, **kw)
