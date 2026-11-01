"""Page-side integration logic — chunks/C01.md §3/§5/§8 (owner answers N1/N2,
DECISIONS R11/R12). Everything here enforces the permitted-edits enumeration:
sync's own machine-marked gallery blocks and its own append-only front-matter
marker key are the ONLY edits an existing page may receive."""

import re

MACHINE_START_FMT = '<!-- immich-sync:album="{name}" slug={slug} -->'
MACHINE_GLOB_FMT = '{{{{< gallery match="sync-{slug}-*" sort="desc" >}}}}'
MACHINE_END_FMT = "<!-- immich-sync:end:{slug} -->"

_MACH_START_RE = re.compile(r'<!-- immich-sync:album="(?P<name>[^"]*)" slug=(?P<slug>[A-Za-z0-9._-]+) -->')
_MACH_END_RE = re.compile(r"<!-- immich-sync:end:(?P<slug>[A-Za-z0-9._-]+) -->")
# Best-effort single-line gallery-call parse (C01 "Notes for dev"): a call
# this regex cannot consume makes the page read as no-fit, so the safe
# outcome is the machine block — never a rewrite of authored syntax.
_GALLERY_OPENER_RE = re.compile(r"\{\{<\s*gallery\b")
_GALLERY_CALL_RE = re.compile(r"\{\{<\s*gallery\b(.*?)>\}\}", re.S)
_MATCH_ARG_RE = re.compile(r"""\bmatch\s*=\s*(?:"([^"]*)"|'([^']*)')""")
_MATCH_PRESENT_RE = re.compile(r"\bmatch\b\s*=")


def page_file_in_bundle(bundle_dir):
    for name in ("_index.md", "index.md"):
        candidate = bundle_dir / name
        if candidate.is_file():
            return candidate
    return None


def pinned_block_lines(name, slug):
    # The byte shape is DECISIONS R12-authoritative; C06's render-gate
    # fixture asserts the same block, so it is generated, never hand-edited.
    return [
        MACHINE_START_FMT.format(name=name, slug=slug),
        MACHINE_GLOB_FMT.format(slug=slug),
        MACHINE_END_FMT.format(slug=slug),
    ]


def machine_spans(lines):
    spans = []
    pending = {}
    for index, line in enumerate(lines):
        start = _MACH_START_RE.fullmatch(line.strip())
        if start:
            pending.setdefault(start["slug"], index)
            continue
        end = _MACH_END_RE.fullmatch(line.strip())
        if end and end["slug"] in pending:
            spans.append((pending.pop(end["slug"]), index, end["slug"]))
    return spans


def authored_gallery_globs(lines):
    """Returns (all_inclusive, globs, unparseable) over AUTHORED calls only —
    machine spans are masked, else our own `sync-<slug>-*` glob would
    self-certify the prefixed files and oscillate the mode every run.
    all_inclusive models a call without `match` (`.ByType "image"` takes
    everything the page owns)."""
    spans = machine_spans(lines)
    text = "\n".join(line for index, line in enumerate(lines)
                     if not any(start <= index <= end for start, end, _ in spans))
    calls = _GALLERY_CALL_RE.findall(text)
    if len(_GALLERY_OPENER_RE.findall(text)) != len(calls):
        return False, [], True
    globs = []
    for args in calls:
        match = _MATCH_ARG_RE.search(args)
        if match is None:
            if _MATCH_PRESENT_RE.search(args):
                return False, [], True  # exotic quoting on a match arg — no-fit
            return True, [], False
        globs.extend(p for p in re.split(r"[,\s]+", match[1] or match[2] or "") if p)
    return False, globs, False


def apply_machine_block(text, name, slug, want_machine):
    """§5 block lifecycle: recognized by markers, updated in place, appended
    after the file's last line only when absent — re-runs never stack, and
    an identical replacement leaves the text byte-identical."""
    lines = text.splitlines()
    span = next((found for found in machine_spans(lines) if found[2] == slug), None)
    if want_machine:
        block = pinned_block_lines(name, slug)
        updated = lines[: span[0]] + block + lines[span[1] + 1:] if span else lines + block
    else:
        if span is None:
            return text
        updated = lines[: span[0]] + lines[span[1] + 1:]
    return "\n".join(updated) + "\n"


def apply_fm_marker(text, album_name, today):
    """§8 (N1): the only front-matter edit is the immich_synced marker key;
    pre-existing key lines keep their exact bytes and order. Re-runs with
    the same albums on the same date must reproduce byte-identical text, so
    the albums list is the sorted union of marker + this run and the block
    is rewritten only when its text actually differs. draft /
    author_reviewed / editor_reviewed are never set or flipped — a
    draft:true would un-publish the page (destructive)."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return text  # a page without front matter is not ours to create one on
    close = next((index for index in range(1, len(lines)) if lines[index].strip() == "---"), None)
    if close is None:
        return text
    marker_start = next((index for index in range(1, close) if lines[index].strip() == "immich_synced:"), None)
    albums = {album_name}
    marker_end = marker_start
    if marker_start is not None:
        marker_end = marker_start + 1
        while marker_end < close and lines[marker_end].startswith(" "):
            if "albums:" in lines[marker_end]:
                albums.update(re.findall(r'"([^"]*)"', lines[marker_end]))
            marker_end += 1
    block = [
        "immich_synced:",
        "  albums: [" + ", ".join(f'"{name}"' for name in sorted(albums)) + "]",
        f"  at: {today}",
    ]
    if lines[marker_start:marker_end] == block:
        return text
    head = lines[1:marker_start] if marker_start is not None else lines[1:close]
    tail = lines[marker_end:close] if marker_start is not None else []
    return "\n".join([lines[0]] + head + block + tail + lines[close:]) + "\n"
