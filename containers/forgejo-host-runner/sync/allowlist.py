"""`sync-albums.yaml` allowlist schema — chunks/C01.md contract §1 + owner
answer N3 (DECISIONS R13). stdlib-only parsing of exactly the shape C06
ships: `albums:` holding `- name:/page:/prefix:` mappings, bare or quoted."""

import re

_PREFIX_SAFE_RE = re.compile(r"^[A-Za-z0-9._-]*$")


class AllowlistError(Exception):
    """Schema error: loud, names the entry, raised before any network call
    or write (N3: page: REQUIRED, no fallback posture)."""


def _unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def _add_field(current, stripped):
    if ":" not in stripped:
        raise AllowlistError(f"allowlist: expected 'key: value', got {stripped!r}")
    key, value = stripped.split(":", 1)
    current[key.strip()] = _unquote(value)


def parse(text):
    entries = []
    current = None
    seen_albums_key = False
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if not seen_albums_key:
            if raw.strip() == "albums: []":
                return []
            if raw.strip() == "albums:":
                seen_albums_key = True
                continue
            raise AllowlistError(f"allowlist: expected top-level 'albums:' key, got {raw.strip()!r}")
        stripped = raw.strip()
        if stripped.startswith("- "):
            current = {}
            entries.append(current)
            remainder = stripped[2:].strip()
            if remainder:
                _add_field(current, remainder)
            continue
        if current is None or not raw[:1].isspace():
            raise AllowlistError(f"allowlist: not an album entry: {raw.strip()!r}")
        _add_field(current, stripped)
    if not seen_albums_key:
        raise AllowlistError("allowlist: missing the top-level 'albums:' key")
    return entries


def _entry_identifier(entry, index):
    if entry.get("name"):
        return f'entry #{index} (name: "{entry["name"]}")'
    if entry.get("page"):
        return f"entry #{index} (page: {entry['page']})"
    return f"entry #{index}"


def validate(entries):
    validated = []
    names = set()
    for index, entry in enumerate(entries, start=1):
        ident = _entry_identifier(entry, index)
        name = entry.get("name")
        if not name:
            raise AllowlistError(f"allowlist {ident} is missing the required 'name:'")
        page = entry.get("page")
        if not page:
            raise AllowlistError(f"allowlist {ident} is missing the required 'page:' "
                                 "(owner answer N3: page: is required on every entry)")
        prefix = entry.get("prefix") or ""
        if not _PREFIX_SAFE_RE.match(prefix):
            # A prefix is concatenated straight into file names; a "/" here
            # would smuggle a path outside the bundle past the §3 target guard.
            raise AllowlistError(f"allowlist {ident} has an unsafe prefix: {prefix!r}")
        if name in names:
            raise AllowlistError(f"allowlist: duplicate album name {name!r}")
        names.add(name)
        validated.append({"name": name, "page": page, "prefix": prefix})
    return validated


def select(validated, albums_override):
    """ALBUMS is a dispatch narrowing of the curated set — an override name
    absent from the allowlist is an error, never an implicit add (§env)."""
    if not albums_override:
        return list(validated)
    wanted = [part.strip() for part in albums_override.split(",") if part.strip()]
    by_name = {entry["name"]: entry for entry in validated}
    missing = [name for name in wanted if name not in by_name]
    if missing:
        raise AllowlistError(
            "ALBUMS override names are not in the allowlist (the override "
            f"narrows, it never widens): {', '.join(repr(m) for m in missing)}"
        )
    return [by_name[name] for name in wanted]
