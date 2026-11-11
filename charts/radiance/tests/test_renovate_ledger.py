# cf-143 C02 — the image pin + digest ledger (chunks/C02.md Tests bullet 6;
# AC5; DECISIONS D2). Posture: upstream public image `docker.io/stilldeadcode/
# radiance:1.17.0` with a datasource=docker renovate pin comment, pullPolicy
# IfNotPresent, and BOTH digests as labeled LEDGER COMMENTS — the amd64 image
# manifest sha256:6fb0e99b… (the valid digest-pin form, RESEARCH RQ0/S4/S11)
# and the tag's index sha256:c2acbaa3… — "which is which" spelled out, plus
# the tag-rebuild caution (the unified-vulkan-262 precedent: tags CAN be
# rebuilt in place) and why there is no digest FIELD (repo has no
# image.digest precedent — tags + ledger only).
#
# Red state at handoff (designed): every leg red until C02 lands. Pure file
# reads — no helm, no skip.

from __future__ import annotations

import re

import yaml

import radiance_testlib as R


def _image_block_values() -> dict:
    vals = R.chart_values()
    nodes = []

    def walk(node):
        if isinstance(node, dict):
            if "repository" in node and "tag" in node:
                nodes.append(node)
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(vals)
    serve = [n for n in nodes if n.get("repository") == R.IMAGE_REPO]
    assert serve, f"C02 AC5: no image spec on {R.IMAGE_REPO} in charts/radiance/values.yaml (nodes: {nodes})"
    return serve[0]


def test_renovate_pin_comment_parses():
    """The regex the repo's docker-pin idiom demands: '# renovate:
    datasource=docker depName=docker.io/stilldeadcode/radiance' directly
    above the tag line (the llama-swap precedent shape)."""
    lines = R.CHART_DIR.joinpath("values.yaml").read_text().splitlines()
    tag_idx = [i for i, ln in enumerate(lines)
               if re.match(r"^\s*tag:\s*[\"']?1\.17\.0[\"']?\s*(#.*)?$", ln)]
    assert tag_idx, "C02 AC5: no image tag line `tag: 1.17.0` in charts/radiance/values.yaml"
    window = " ".join(lines[max(0, i - 6):i + 1] for i in tag_idx)
    assert re.search(
        r"#\s*renovate:\s*datasource=docker\s+depName=docker\.io/stilldeadcode/radiance", window
    ), (
        f"C02 AC5: the tag lacks its `# renovate: datasource=docker depName=docker.io/"
        f"stilldeadcode/radiance` pin comment (window: {window[:200]!r}) — renovate tracking "
        "for the radiance docker pin is a plan Commands deliverable"
    )


def test_image_spec_shape():
    img = _image_block_values()
    assert str(img.get("tag")) == R.IMAGE_TAG
    assert img.get("pullPolicy") == "IfNotPresent", (
        f"C02 AC5: pullPolicy {img.get('pullPolicy')!r} — the digest-pinned upstream public "
        "image ships IfNotPresent (the :main+Always law is for OWNYOURIO re-exports only, gotcha 15)"
    )
    assert "digest" not in img, (
        "C02/D2: an image.digest FIELD exists — the repo posture is tag + digest-in-comment "
        "ledger; no chart here uses a digest field (gotcha 15)"
    )


def test_both_digests_ledgered_and_labeled():
    """AC5: BOTH radiance digests present, each labeled with WHICH identity
    it is (amd64 image-manifest vs index) — the RQ0 pin-shape nuance; an
    unlabeled digest pair is the ambiguity the guide's own pin hides."""
    text = R.CHART_DIR.joinpath("values.yaml").read_text()
    digests = set(re.findall(r"sha256:[0-9a-f]{64}", text))
    assert R.AMD64_IMAGE_MANIFEST in digests, (
        "C02 AC5: the amd64 image-manifest digest sha256:6fb0e99b… is not ledgered in full "
        "64-hex form (RESEARCH S4: exactly the guide's pin, valid for 1.17.0@<digest>)"
    )
    assert R.INDEX_DIGEST in digests, (
        "C02 AC5: the tag's index digest sha256:c2acbaa3… is not ledgered — both spellings "
        "ride the comment, each named (RQ0: 'pin shape matters')"
    )
    flat = " ".join(text.split())
    assert re.search(r"(?i)(amd64|image[- ]?manifest)", flat) and re.search(r"(?i)index", flat), (
        "C02 AC5: the digest ledger never says which is which (amd64 image manifest vs index)"
    )
    assert re.search(r"(?i)rebuild", flat), (
        "C02/D2: the tag-rebuild caution is unrecorded (the unified-vulkan-262 in-place "
        "rebuild precedent — why the digest ledger exists beside a tag pin)"
    )


def test_pack_ledger_comment():
    """The model-path comment carries the pack ledger (C02 task): HF repo,
    exact bytes, lfs sha, ungated — RESEARCH RQ0's pack table, the staging
    init's verification authority."""
    text = R.CHART_DIR.joinpath("values.yaml").read_text()
    flat = " ".join(text.split())
    assert R.PACK_REPO in text, f"C02: the pack ledger omits the HF repo {R.PACK_REPO}"
    assert re.search(r"121[,_]?969[,_]?901[,_]?568", flat), (
        f"C02: the pack byte count {R.PACK_BYTES:,} is not in the ledger"
    )
    assert R.PACK_LFS_SHA in text, "C02: the pack lfs sha 0af5e962… is not ledgered in full"
    assert re.search(r"(?i)ungated", flat), "C02/RQ0: 'ungated' (gated:False verified) is not stated"
