"""t4 (C06 Tests): secret hygiene grep sweep over every staged artifact —
C06 AC2 "secret REFERENCES by name only — no literals anywhere". The five
names may appear only as ${{ secrets.NAME }} references or as env keys
receiving such references."""

import re

from conftest import ALLOWLIST, read_text, staging_artifact_files, STAGING

TOKEN_SHAPED = (
    re.compile(r"\bghp_[A-Za-z0-9]{16,}"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{16,}"),
    re.compile(r"\bnfp_[A-Za-z0-9]{16,}"),
    re.compile(r"\beyJ[A-Za-z0-9_-]{16,}"),
    re.compile(r"\bAKIA[0-9A-Z]{12,}"),
    re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"),
    re.compile(r"\b[0-9a-f]{40,}\b|\b[0-9a-f]{64}\b"),
)


def staged_text_files():
    out = []
    for p in staging_artifact_files():
        try:
            text = p.read_text()
        except (UnicodeDecodeError, OSError):
            continue
        out.append((p, text))
    return out


def test_no_token_shaped_literals():
    offenders = []
    for p, text in staged_text_files():
        for rx in TOKEN_SHAPED:
            for m in rx.finditer(text):
                offenders.append(f"{p.relative_to(STAGING)}: {m.group(0)[:24]}…")
    assert not offenders, offenders


def test_secret_names_only_as_references():
    """NAME = literal (the red-flag shape) never appears; every mention of a
    seeded secret name is either inside ${{ secrets.NAME }}, an env key, or
    documentation prose about which item to seed."""
    names = ("IMMICH_API_KEY", "FORGEJO_SYNC_PAT", "NETLIFY_AUTH_TOKEN",
             "NETLIFY_SITE_ID", "NETLIFY_SITE_ID_FARM")
    offenders = []
    for p, text in staged_text_files():
        for name in names:
            for m in re.finditer(re.escape(name) + r"[^A-Z_]", text):
                tail = text[m.end():m.end() + 30]
                if tail.strip().startswith((":", "= ")) and "secrets." not in text[m.start():m.start() + 120]:
                    # NAME: <literal> directly — only allowed when the
                    # value on the same line is a secrets context.
                    line = text[m.start():text.find("\n", m.start())]
                    if "secrets." not in line:
                        offenders.append(f"{p.relative_to(STAGING)}: {line.strip()[:90]}")
    assert not offenders, offenders


def test_allowlist_holds_no_credentials():
    """The allowlist is pure mapping data (name/page/prefix) — nothing that
    looks like auth material can ride there."""
    text = read_text(ALLOWLIST, "t4")
    assert not re.search(r"(?i)(api.?key|token|secret|password)\s*:", text), \
        "credential-shaped key in sync-albums.yaml"
