# charts/amd-gpu provenance contract — C07 AC1/AC6 + DECISIONS D19, the
# VENDORED-CHART GOVERNANCE LINE made machine-checked: the header comment of
# the vendored chart records the fork point (upstream chart 0.22.0, tag
# amd-gpu-helm-0.22.0, index digest 791ada88…) and the exact delta (the
# ~10-line args hook), so a future refresh diff is against a RECORDED base,
# not archaeology. Chart.yaml identity: name PINNED to `amd-gpu` (the
# orphan-rename class), version 1.0.0 (brand-new chart entry — the repo's
# only sanctioned 1.0.0s are this one and charts/radiance; release.yaml owns
# every later bump), appVersion 1.31.0.12, NO app-template dependency
# (upstream shape — the repo library standard is for app charts; this is a
# third-party vendor).
#
# Red state at handoff (designed): every leg red until C07 lands (missing
# files). Pure file reads — no helm, no skip.
#
# cf-143 C07 landing-round re-pin (dev-routed, chunks/C07.md "Pending test-
# round scope" item 1): the renovate-window join flattens its per-tag line
# windows before joining (the round-1 form nested lists into str.join and
# TypeErrors); same facts, same window, no bar moved.

from __future__ import annotations

import re

import yaml

import amd_gpu_testlib as A

CHART_DIR = A.CHART_DIR


def _chart_text() -> str:
    assert (CHART_DIR / "Chart.yaml").is_file(), (
        "C07: charts/amd-gpu/Chart.yaml missing — the vendored chart is not implemented"
    )
    return (CHART_DIR / "Chart.yaml").read_text()


def _values_text() -> str:
    return A.chart_values_text()


# --- Chart.yaml identity (D19) --------------------------------------------------


def test_chart_yaml_pinned_identity():
    text = _chart_text()
    meta = yaml.safe_load(text)
    assert meta.get("name") == "amd-gpu", (
        f"C07/D19: Chart.yaml name is {meta.get('name')!r} — it MUST stay the upstream "
        "name `amd-gpu`: the vendored templates hardcode .Chart.Name into every object "
        "name, and the gpu-ai-amd-gpu Application source-flip orphans anything renamed"
    )
    assert str(meta.get("version")) == "1.0.0", (
        f"C07/D19: Chart.yaml version is {meta.get('version')!r}, want 1.0.0 — brand-new "
        "chart entry per the repo version law (release.yaml owns later bumps; no hand-tag)"
    )
    assert str(meta.get("appVersion")) == A.PLUGIN_TAG, (
        f"C07: appVersion {meta.get('appVersion')!r}, want {A.PLUGIN_TAG} — the first plugin "
        "release carrying the product naming strategy (§R6-Q1)"
    )
    assert not meta.get("dependencies"), (
        f"C07/D19: Chart.yaml declares dependencies {meta.get('dependencies')} — the vendored "
        "chart keeps the upstream shape (NO app-template dep; this is a third-party vendor, "
        "not a repo app chart)"
    )


# --- the governance header (fork point + delta) ---------------------------------


def test_header_records_fork_point_and_delta():
    """D19 refresh policy is only executable against a RECORDED base: the
    header comment (Chart.yaml or values.yaml) must name upstream chart
    0.22.0, the tag amd-gpu-helm-0.22.0, the plugin image tag, the index
    digest prefix, the args-hook delta and the refresh trigger."""
    blob = _chart_text() + "\n" + _values_text()
    flat = re.sub(r"\s+", " ", blob)
    for token, why in (
        (A.UPSTREAM_CHART_VERSION, "the fork-point chart version"),
        (A.UPSTREAM_CHART_TAG, "the fork-point tag"),
        (A.PLUGIN_TAG, "the plugin image tag the vendored chart pins"),
        (A.HELM_INDEX_DIGEST_PREFIX, "the 0.22.0 index digest prefix (D19)"),
    ):
        assert token in flat, (
            f"C07/D19 provenance: the vendored-chart header never names {token} — "
            f"{why}; without it a future re-copy has no recorded base to diff against"
        )
    flat_low = flat.lower()
    assert "vendored" in flat_low or "vendor" in flat_low, (
        "C07/D19: the header does not call out the chart as VENDORED (a self-owned "
        "liability logged in DECISIONS, not upstream-maintained)"
    )
    assert re.search(r"args|extraArgs", flat), (
        "C07/D19: the header does not record the delta (the ~10-line args/extraArgs hook "
        "the upstream release lacks — PR #122)"
    )
    assert re.search(r"(?i)refresh|0\.23|#122", flat), (
        "C07/D19: the refresh policy trigger is unrecorded (upstream chart >= 0.23 or "
        "PR #122 merge: re-copy, re-apply the delta by hand, fresh dated decision line)"
    )


# --- values: pin + renovate + digest ledger + expected-names ledger -------------


def test_image_tag_renovate_pin_parses():
    """C07 AC1/AC6: dp.image.tag = 1.31.0.12 with the datasource=docker
    renovate comment above it (the pin MIGRATED here from the service
    entry's datasource=helm comment — record the datasource move where the
    entry sits, tests/services/amd-gpu-naming.sh n1 greps the service side)."""
    lines = _values_text().splitlines()
    tag_idx = [i for i, ln in enumerate(lines) if re.match(r"^\s*tag:\s*[\"']?1\.31\.0\.12[\"']?\s*(#.*)?$", ln)]
    assert tag_idx, (
        f"C07: values.yaml carries no dp.image.tag: 1.31.0.12 line — the pin the naming "
        "strategy ships on (§R6-Q2: the tag IS values-reachable, the flag is not)"
    )
    window = " ".join(ln for i in tag_idx for ln in lines[max(0, i - 6):i + 1])
    assert re.search(
        r"#\s*renovate:\s*datasource=docker\s+depName=docker\.io/rocm/k8s-device-plugin", window
    ), (
        f"C07 AC6: no `# renovate: datasource=docker depName=docker.io/rocm/k8s-device-plugin` "
        f"comment above the tag (window: {window[:200]}!r) — the new docker pin must be "
        "renovate-visible (global-renovate dry-run confirms; the helm pin left services/)"
    )
    repo = A.chart_values().get("dp", {}).get("image", {}).get("repository")
    assert repo == A.PLUGIN_REPO, f"C07: dp.image.repository is {repo!r}, want {A.PLUGIN_REPO}"


def test_digest_ledger_present_and_labeled():
    """D2 posture: tag + digest-in-COMMENT (no digest field). The amd64 image
    manifest digest ledger (§R6-S13, 6437c74f…) sits as a 64-hex comment
    beside the image block, labeled with what it is."""
    text = _values_text()
    digests = re.findall(r"sha256:[0-9a-f]{64}", text)
    assert digests, (
        "C07/D19: values.yaml has no full 64-hex sha256 digest — the ledger comment must "
        "carry the COMPLETE digest (§R6-Q5 posture), not the research-truncated prefix"
    )
    assert any(d.startswith(A.PLUGIN_AMD64_DIGEST_PREFIX) for d in digests), (
        f"C07: no digest starting with {A.PLUGIN_AMD64_DIGEST_PREFIX} in values.yaml — "
        "the pin's amd64 manifest identity is unrecorded (tag-rebuild caution, the "
        "unified-vulkan-262 precedent)"
    )
    flat = re.sub(r"\s+", " ", text)
    assert re.search(r"(?i)(amd64|image[- ]?manifest)", flat), (
        "C07: the digest comment never names WHICH identity it is (amd64 image manifest — "
        "the ledger must say which is which, radiance's own ledger law)"
    )


def test_extra_args_default_is_the_product_strategy():
    vals = A.chart_values()
    assert vals.get("dp", {}).get("extraArgs") == [A.STRATEGY_FLAG], (
        f"C07: dp.extraArgs default is {vals.get('dp', {}).get('extraArgs')!r}, want "
        f"exactly [{A.STRATEGY_FLAG!r}] — product naming is the vendored chart's whole point"
    )


def test_expected_names_ledger_block():
    """The n4/C02 authority: a comment block in values.yaml records the
    ledgered expected names (7551/C0 -> gpu-ai-pro-r9700, 1586 -> gpu-8060s)
    computed by §R6-Q1's source-port against the plugin's baked amdgpu.ids.
    C02's cross-chart name-identity needle reads this SAME block — one
    authority, no second copy."""
    text = _values_text()
    flat = re.sub(r"\s+", " ", text)
    for device, revision, name in A.EXPECTED_NAME_LEDGER:
        if revision:
            assert re.search(rf"{device}\b[^A-Za-z0-9\n]{{0,60}}\b{revision}\b[^A-Za-z]{{0,60}}{name}",
                            text + " " + flat), (
                f"C07 §R6-Q1 ledger: values.yaml never maps ({device},{revision}) -> {name} "
                "within one comment window — the cross-chart identity needle has no authority to read"
            )
        else:
            assert device in flat and name in flat, (
                f"C07 §R6-Q1 ledger: {device} / {name} not both present — the APU row "
                "(revisions C1/C3/C6/D1) must be recorded beside the R9700 row"
            )
    assert "amd.com/gpu-ai-pro-r9700" in text and "amd.com/gpu-8060s" in text, (
        "C07 ledger: the full amd.com/-prefixed resource names must appear verbatim "
        "(radiance claims the first, llama-swap flips to the second — C02/C07 read them here)"
    )
    # The fallback trap is NAMED (its decision tree stays in the runbook, C06):
    assert re.search(r"(?i)fallback", text), (
        "C07 §R6 ledger: the fallback trap (unknown sysfs (device,revision) -> bare "
        "amd.com/gpu, C06 step-0 receipts close it) is not recorded where the names are"
    )
