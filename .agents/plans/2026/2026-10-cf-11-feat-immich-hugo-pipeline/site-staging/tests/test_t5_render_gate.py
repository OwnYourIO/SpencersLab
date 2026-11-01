"""t5 (C06 Tests): the hugo render gate — C06 AC5's gallery-integration
PRE/POST states rendered by the REAL hugo (v0.151.0+extended, the site's
exact netlify.toml pin, at ~/.local/bin) on scratch copies under
/tmp/opencode. The live checkout at /home/coder/CuratedForest.com is
read-only; test_live_repo_untouched asserts the guard.

TIER A (gallery-contract render): a module-free shell site embedding the
LIVE layouts/_shortcodes/gallery.html byte-for-byte and the pinned fixture
sync states — this is the gate that runs offline in agent sessions today.

TIER B (full-repo render): rsync of the real repo (excluding .git/lfs and
worktrees, following the chunk's exclusions) with the staging applied and
the same fixture states hand-built into the real bundles. Hugo modules need
the go binary/network; where module loading cannot be satisfied OFFLINE the
leg reports SKIP-BLOCKED (the chunk's designed shape — never a fake pass).

Fixture states mirror what C01 writes (names per contract §4/§5, the block
byte-exact to the R12 pinned shape) — this gate validates the workflow
artifacts' render contract, it is not a C01 re-test (chunk t5)."""

import re
import shutil
import subprocess
from pathlib import Path

import pytest

from conftest import ALLOWLIST, DEPLOY, GALLERY_HTML, LIVE_SITE, require_artifact

TESTS = Path(__file__).resolve().parent
SHELL = TESTS / "fixtures" / "render-shell"
SEED_JPG = TESTS / "fixtures" / "derivative-seed.jpg"

CURRENT = "plants/aeroponics/current-grows"
ENVS = "plants/aeroponics/past-designs/grow-environments"
GLOBS = ("v6-*", "v5-*", "v4-*", "v3-*", "v2-*", "2017-pfc-*")

UNPREFIXED = ["20260314-092653_00010203_img_c0.jpg", "20260315-100000_01020304_img_c1.jpg"]
ALBUM = "Past Designs Archive"
SLUG = "past-designs-archive"
PREFIXED = [
    f"sync-{SLUG}-20260101-210500_02020202_img_g0.jpg",
    f"sync-{SLUG}-20260102-210501_03030303_img_g1.jpg",
]
MACHINE_BLOCK = (
    f'<!-- immich-sync:album="{ALBUM}" slug={SLUG} -->\n'
    f'{{{{< gallery match="sync-{SLUG}-*" sort="desc" >}}}}\n'
    f"<!-- immich-sync:end:{SLUG} -->\n"
)

CURRENT_FM = """---
title: Current Grow System
weight: 1
type: docs
---

What the current aeroponic systems look like.

{{< gallery sort="desc" >}}
"""

ENVS_FM = """---
title: Grow Environments
weight: 2
type: docs
---

""" + "\n\n".join(f"### {g[:-2]}\n\n" + "{{< " + f'gallery match="{g}" sort="asc"' + " >}}" for g in GLOBS) + "\n"


def _hugo_env():
    import os
    env = dict(os.environ)
    env["PATH"] = f"{Path.home()}/.local/bin:{env.get('PATH', '')}"
    return env


def run_hugo(site_dir, tag, expect_module_blocked=False):
    proc = subprocess.run(
        ["hugo", "-D", "--gc", "--destination", f"public-{tag}"],
        cwd=str(site_dir), env=_hugo_env(), capture_output=True, text=True, timeout=1500,
    )
    out = proc.stdout + proc.stderr
    module_blocked = re.search(r"failed to load modules|failed to download modules|binary .*go.* not found", out)
    if module_blocked:
        pytest.skip(
            "SKIP-BLOCKED: hugo module load needs the go binary/network (no fake pass — "
            f"C06 t5's designed report). Details: {module_blocked.group(0)}"
        )
    assert proc.returncode == 0, f"hugo build ({tag}) failed:\n{out[-3000:]}"
    return site_dir / f"public-{tag}"


def _build_shell(base):
    site = base / "shell-site"
    if site.exists():
        shutil.rmtree(site)
    shutil.copytree(SHELL, site)
    (site / "layouts" / "_shortcodes").mkdir(parents=True, exist_ok=True)
    shutil.copy(GALLERY_HTML, site / "layouts" / "_shortcodes" / "gallery.html")
    cur = site / "content" / CURRENT
    cur.mkdir(parents=True)
    (cur / "_index.md").write_text(CURRENT_FM)
    for i in range(3):
        shutil.copy(SEED_JPG, cur / f"2025122{i}-103000_100000000{i}_old-{i}.jpg")
    envs = site / "content" / ENVS
    envs.mkdir(parents=True)
    (envs / "index.md").write_text(ENVS_FM)
    for i, g in enumerate(GLOBS):
        shutil.copy(SEED_JPG, envs / f"{g[:-1]}-system-{i:03d}.jpg")
    return site


def _apply_post_state(site):
    cur = site / "content" / CURRENT
    for name in UNPREFIXED:
        shutil.copy(SEED_JPG, cur / name)
    envs = site / "content" / ENVS
    for name in PREFIXED:
        shutil.copy(SEED_JPG, envs / name)
    page = envs / "index.md"
    page.write_text(page.read_text() + MACHINE_BLOCK)


def _page_html(public, page, index_underscore=True):
    d = public / page
    f = d / "index.html"
    assert f.exists(), f"rendered page {page} missing under {public}"
    return f.read_text()


def _gallery_items(html):
    return re.findall(r'aria-label="View ([^"]+)"', html)


def live_porcelain():
    # --no-optional-locks keeps the read-only check from refreshing the
    # live index (a status without it can write .git).
    return subprocess.run(
        ["git", "--no-optional-locks", "-C", str(LIVE_SITE), "status", "--porcelain"],
        capture_output=True, text=True,
    ).stdout


@pytest.fixture(scope="module")
def live_baseline():
    """Read-only baseline for /home/coder/CuratedForest.com. The guard test
    runs after the tier-A legs (which could write to the live tree by bug);
    tier B is read-only by construction — rsync only reads its source."""
    if not LIVE_SITE.exists():
        pytest.skip("SKIP-BLOCKED: /home/coder/CuratedForest.com not present in this environment")
    return live_porcelain()


@pytest.fixture(scope="module")
def gallery_source(live_baseline):
    if not GALLERY_HTML.exists():
        pytest.skip(f"SKIP-BLOCKED: {GALLERY_HTML} missing — the shortcode under contract is unavailable")
    return GALLERY_HTML.read_bytes()


def test_machine_block_shape_is_the_pinned_bytes():
    """R12 pins the block; the fixture that C06 hands to hugo must be the
    byte-exact shape C01 writes (this is the two chunks' shared seam)."""
    lines = MACHINE_BLOCK.rstrip("\n").splitlines()
    assert lines == [
        f'<!-- immich-sync:album="{ALBUM}" slug={SLUG} -->',
        f'{{{{< gallery match="sync-{SLUG}-*" sort="desc" >}}}}',
        f"<!-- immich-sync:end:{SLUG} -->",
    ]


def test_pre_state_renders_without_new_images(tmp_path, gallery_source):
    site = _build_shell(tmp_path)
    public = run_hugo(site, "pre")
    cur_html = _page_html(public, CURRENT)
    envs_html = _page_html(public, ENVS)
    for name in UNPREFIXED + PREFIXED:
        assert name not in cur_html and name not in envs_html, name


def test_post_state_galleries_include_new_images(tmp_path, gallery_source):
    site = _build_shell(tmp_path)
    _apply_post_state(site)
    public = run_hugo(site, "post")

    cur_html = _page_html(public, CURRENT)
    items = _gallery_items(cur_html)
    # No-glob page: the new unprefixed files join the Name-sorted
    # firehose; sort=desc puts the newest derivative first.
    assert set(UNPREFIXED) <= set(items), items
    assert items[0] == max(UNPREFIXED), items[:4]

    envs_html = _page_html(public, ENVS)
    eitems = _gallery_items(envs_html)
    assert set(PREFIXED) <= set(eitems), eitems
    # Machine gallery is the block at file end -> its items render last,
    # newest-first inside (sort=desc on the sync- names).
    assert eitems[-2:] == sorted(PREFIXED, reverse=True), eitems[-4:]
    # Thumb + lightbox markup per image (shortcode contract): each name
    # carries a lightbox div too.
    for name in PREFIXED:
        assert envs_html.count(f'aria-label="{name}"') >= 1, name

    # PRE/POST delta proof against the same shell minus the images.
    site2 = tmp_path / "cmp"
    shutil.copytree(site, site2)
    for name in UNPREFIXED:
        (site2 / "content" / CURRENT / name).unlink()
    for name in PREFIXED:
        (site2 / "content" / ENVS / name).unlink()
    page = site2 / "content" / ENVS / "index.md"
    page.write_text(page.read_text().replace(MACHINE_BLOCK, ""))
    public2 = run_hugo(site2, "post")
    assert not any(n in _gallery_items(_page_html(public2, ENVS)) for n in PREFIXED)


def test_gallery_shortcode_untouched_vs_live(tmp_path, gallery_source):
    """C06 ships ZERO template changes — the staged suite may only ever
    consume layouts/_shortcodes/gallery.html, and it must be live-repo
    identical (AC5's last clause)."""
    shell_copy =_build_shell(tmp_path) / "layouts" / "_shortcodes" / "gallery.html"
    assert shell_copy.read_bytes() == gallery_source


def test_live_repo_untouched(live_baseline):
    """C06 AC6's in-suite guard: the render gate must have touched nothing
    in the live checkout (review verifies the repo-level status separately)."""
    assert live_porcelain() == live_baseline, \
        "the render gate modified the live repo — forbidden (AC6)"


def test_tier_b_full_repo_render(tmp_path, live_baseline):
    """The chunk's literal gate: rsync the real repo (excluding .git/lfs/
    and .agents/worktrees), apply the staging artifacts, hand-build the same
    fixture sync states into the real bundles, and hugo -D --gc."""
    if not shutil.which("rsync"):
        pytest.skip("SKIP-BLOCKED: rsync unavailable")
    copy = tmp_path / "cf-render-full"
    subprocess.run(
        ["rsync", "-a", "--exclude", ".git/lfs/", "--exclude", ".agents/worktrees/",
         f"{LIVE_SITE}/", str(copy)],
        check=True, timeout=600,
    )
    require_artifact(DEPLOY, "t5")
    shutil.copytree(DEPLOY.parent, copy / ".forgejo" / "workflows", dirs_exist_ok=True)
    shutil.copy(ALLOWLIST, copy / ALLOWLIST.name)

    def add(rel_bundle, names, block=False):
        b = copy / "content" / rel_bundle
        for n in names:
            shutil.copy(SEED_JPG, b / n)
        if block:
            page = b / "index.md"
            page.write_text(page.read_text() + MACHINE_BLOCK)

    add(CURRENT, UNPREFIXED)
    add(ENVS, PREFIXED, block=True)

    public = run_hugo(copy, "full")
    cur_html = _page_html(public, CURRENT)
    envs_html = _page_html(public, ENVS)
    for name in UNPREFIXED:
        assert name in cur_html
    for name in PREFIXED:
        assert name in envs_html
    assert (copy / "layouts" / "_shortcodes" / "gallery.html").read_bytes() == GALLERY_HTML.read_bytes()
