"""
Internal WeKan client used by the MCP server.

Reads WEKAN_BASE_URL and WEKAN_TOKEN from environment ONCE at process start.
These values live in the server process — NOT in tool schemas, NOT in tool
arguments, NOT in tool responses (unless a tool explicitly returns them).

Design constraints imposed by WeKan:
    - Login body is JSON, not form data (form data is documented as broken).
      We skip login entirely and reuse a pre-obtained bearer token.
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
        if not token:
            raise WekanError(
                "WEKAN_TOKEN not set. Obtain one by POSTing JSON to /users/login "
                "on the WeKan server, then inject it via the ToolHive secret."
            )

        self._base_url = base_url
        self._client = httpx.Client(
            base_url=base_url,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
            },
            timeout=timeout,
        )
        self.user_id: Optional[str] = None

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

    # ---- HTTP core ----

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
        try:
            resp = self._client.request(
                method, path, json=json_body, params=params, headers=headers or None
            )
        except httpx.HTTPError as e:
            # Don't leak the URL structure or headers.
            raise WekanError(f"WeKan network error on {method} {path}: {type(e).__name__}") from None

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

    # ---- convenience verbs ----

    def get(self, path: str, **kw): return self.request("GET", path, **kw)
    def post(self, path: str, json_body: Any = None, **kw): return self.request("POST", path, json_body=json_body, **kw)
    def put(self, path: str, json_body: Any = None, **kw): return self.request("PUT", path, json_body=json_body, **kw)
    def delete(self, path: str, **kw): return self.request("DELETE", path, **kw)
