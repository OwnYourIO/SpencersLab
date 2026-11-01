"""Scratch-site replica builder — hand-built SMALL per chunks/C01.md "Notes
for dev": md files mirror the real gallery-call contracts from
RESEARCH-curatedforest-repo.md (no-glob sort=desc, six semantic-prefix globs,
case-insensitive jpg glob) without copying the live repo's bytes or tree.

Every page carries the current-grows-style review front matter (todo /
author_reviewed / editor_reviewed) because t9 (N1 policy) must prove those
keys survive byte-identical.
"""

import hashlib
from pathlib import Path

from conftest import MANUAL_DERIVATIVES, SEED_JPG

DEFAULT_FM = "\n".join(
    [
        "---",
        "title: {title}",
        "weight: 1",
        "type: docs",
        'todo: "- keep the narrative current"',
        "author_reviewed: false",
        "editor_reviewed: false",
        "---",
    ]
)

GROW_ENV_GLOBS = ("v6-*", "v5-*", "v4-*", "v3-*", "v2-*", "2017-pfc-*")


class Site:
    def __init__(self, root):
        self.root = Path(root)
        (self.root / "content").mkdir(parents=True)
        self._seed = SEED_JPG.read_bytes()

    def write(self, rel, text):
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        return p

    def image(self, rel, tag=b"x"):
        """Page resource with distinct bytes (hash-able for never-overwrite
        assertions); a fake .jpg is enough for these tests — nothing renders
        here (t13 is hugo-independent by contract)."""
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(self._seed[:4096] + hashlib.sha256(tag).hexdigest().encode())
        return p

    def bundle_page(self, page, *, title, galleries, body=None, index="_index.md", images=()):
        """galleries: list of shortcode arg strings ('sort="desc"' etc.)."""
        lines = [DEFAULT_FM.format(title=title), ""]
        lines.append(body or f"Prose for {title}.")
        for args in galleries:
            lines += ["", f'{{{{< gallery {args} >}}}}']
        self.write(f"content/{page}/{index}", "\n".join(lines) + "\n")
        for name, tag in images:
            self.image(f"content/{page}/{name}", tag)

    def no_glob_page(self, page="plants/aeroponics/current-grows", with_manual=True):
        """current-grows mirror: {{< gallery sort="desc" >}} with no match →
        .ByType image takes everything the page owns. Authored extras carry
        the repo's real date-first export names — hugo sorts by Name, where
        IMG_* would outrank every derivative name (digits < letters)."""
        images = [(name, f"manual:{name}".encode()) for name in MANUAL_DERIVATIVES] if with_manual else []
        images += [(f"2025122{i}-103000_100000000{i}_old-{i}.jpg", f"orig:{i}".encode()) for i in range(3)]
        self.bundle_page(
            page,
            title="Current Grow System",
            galleries=['sort="desc"'],
            body="What the current aeroponic systems look like.",
            index="_index.md",
            images=images,
        )
        return page

    def six_glob_page(self, page="plants/aeroponics/past-designs/grow-environments"):
        """grow-environments mirror: six authored semantic-prefix galleries
        — no sync-<slug>- name can fit any of them, the pinned no-fit case."""
        galleries = [f'match="{g}" sort="asc"' for g in GROW_ENV_GLOBS]
        images = [(f"{g[:-1]}-system-{i:03d}.jpg", f"{g}:{i}".encode()) for i, g in enumerate(GROW_ENV_GLOBS)]
        self.bundle_page(
            page,
            title="Grow Environments",
            galleries=galleries,
            body="Past grow environments, grouped by the hand-renamed prefixes.",
            index="index.md",
            images=images,
        )
        return page

    def jpg_glob_page(self, page="plants/aeroponics/past-designs"):
        """past-designs mirror: case-insensitive jpg glob — a plain
        date-named derivative fits it without any prefix."""
        self.bundle_page(
            page,
            title="Past Designs",
            galleries=['match="*.[jJ][pP]*" sort="asc"'],
            index="_index.md",
            images=[("old-design-001.JPG", b"oldjpg")],
        )
        return page

    def v7_glob_page(self, page="plants/aeroponics/past-designs/v7-designs"):
        """Single v7-* authored gallery — the allowlist-prefix fit case from
        the C06 example (prefix v7-web joins it with zero page edits)."""
        self.bundle_page(
            page,
            title="V7 Designs",
            galleries=['match="v7-*" sort="asc"'],
            index="index.md",
            images=[("v7-web-old-001.jpg", b"v7old")],
        )
        return page

    def site_chrome(self):
        """The files the HARD GUARDS forbid sync from editing, plus content
        that no allowlist entry targets — tree-digest fixtures."""
        self.write("hugo.yaml", "baseURL: https://curatedforest.example/\ntitle: Curated Forest\n")
        self.write("netlify.toml", '[build]\n  publish = "public"\n')
        self.write(".gitattributes", "*.jpg filter=lfs diff=lfs merge=lfs -text\n")
        self.write("layouts/_shortcodes/gallery.html", "{{/* bespoke gallery shortcode */}}\n")
        self.write(".forgejo/workflows/deploy.yml", "name: deploy\n")
        self.write("content/_index.md", DEFAULT_FM.format(title="Home") + "\n")
        self.bundle_page(
            "plants/aeroponics/untargeted",
            title="Untargeted",
            galleries=['sort="asc"'],
            images=[("keepme-001.jpg", b"keep")],
        )

    def page_text(self, page, index=None):
        for cand in ("_index.md", "index.md"):
            p = self.root / "content" / page / (index or cand)
            if p.exists():
                return p.read_text()
        raise AssertionError(f"no page under content/{page}")

    def page_bytes(self, page, index=None):
        for cand in ("_index.md", "index.md"):
            p = self.root / "content" / page / (index or cand)
            if p.exists():
                return p.read_bytes()
        raise AssertionError(f"no page under content/{page}")

    def bundle_files(self, page):
        d = self.root / "content" / page
        return sorted(p.name for p in d.iterdir() if p.is_file()) if d.exists() else []

    def body_of(self, page_text):
        """Markdown after the closing front-matter fence."""
        parts = page_text.split("---\n", 2)
        return parts[2] if len(parts) == 3 else page_text

    def fm_of(self, page_text):
        parts = page_text.split("---\n", 2)
        return parts[1] if len(parts) == 3 else ""
