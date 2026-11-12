# cf-143 C02 — the cross-chart GPU name identity (chunks/C02.md Tests bullet
# 5; AC4). The owner Q9 ruling in two needles: radiance claims
# amd.com/gpu-ai-pro-r9700 and llama-swap claims amd.com/gpu-8060s — the two
# pools are DISJOINT and each name equals what C07's vendored plugin ledger
# advertises for its device (7551/C0 -> gpu-ai-pro-r9700; 1586 -> gpu-8060s,
# RESEARCH §R6-Q1, computed against the plugin's baked amdgpu.ids). The
# ledger in charts/amd-gpu/values.yaml is the single authority BOTH charts'
# suites read — no second copy of the names.
#
# Red state at handoff (designed): red until C07 (the ledger + the flip) and
# C02 (the claim) land; C02's wave-2 dependency on C07 is exactly this
# needle's meaning (chunks/C02.md: "the dependency's sole executable
# meaning").
#
# Run per-directory: python3 -m pytest charts/radiance/tests -v

from __future__ import annotations

import pytest

import radiance_testlib as R

_ok, _reason = R.helm_ready()
helm_skip = pytest.mark.skipif(not _ok, reason=_reason)


@helm_skip
def test_radiance_claim_equals_the_ledger_r9700_pool():
    """AC4: the rendered claim string == the pool the vendored plugin
    advertises for the R9700 (7551/C0) per its ledgered expected-names
    comment."""
    ledger = R.amd_gpu_ledger_names()
    assert "7551" in ledger, (
        "C02 AC4: charts/amd-gpu/values.yaml ledger has no 7551 (R9700) row — the expected-"
        "names block is the cross-chart authority (C07 n4), the identity leg has nothing to read"
    )
    docs, _ = R.render(service=False)
    res = R.resources(R.serve_container(R.deployment(docs)))
    claims = {k for k in (res.get("requests") or {}) | (res.get("limits") or {}) if k.startswith("amd.com/")}
    assert claims == {R.GPU_CLAIM}, (
        f"C02 AC4: radiance GPU claims {claims}, want exactly {{{R.GPU_CLAIM!r}: 1}} (Q9 named pool)"
    )
    assert R.GPU_CLAIM == f"amd.com/{ledger['7551']}", (
        f"C02 AC4: the claimed name {R.GPU_CLAIM!r} != the plugin ledger's 7551 pool "
        f"'amd.com/{ledger['7551']}' — the name that must exist on the node post-C07 is one string"
    )


@helm_skip
def test_pools_are_disjoint_and_llama_swap_owns_the_apu_name():
    """The owner ask verified repo-side, per-cluster under B1/D21: the APU
    pool name != radiance's (ledger disjointness), and the gpu-AI
    overlay-MERGED llama-swap render's main container claims EXACTLY the
    ledger's 1586 pool — while the gpu-cluster render keeps the bare
    tree-global default (that cluster's plugin can advertise nothing else).

    C02 landing-round re-pin (the arm the C07 landing round missed): the
    round-1 form grepped charts/llama-swap/values.yaml for a live
    `amd.com/gpu-8060s: 1` line — a shape owner B1 explicitly forbids
    (the flip is overlay-only, D21) and which stood MUTUALLY exclusive
    against the C07 naming-flip suite's chart-stays-bare bar; passing this
    arm would have re-reddened those two. Re-read at the res= level through
    the llama-swap testlib's own render (same pattern as the C07 rewrite),
    so both suites now assert the SAME per-cluster truth."""
    ledger = R.amd_gpu_ledger_names()
    assert "1586" in ledger, "C02 AC4: ledger has no 1586 (APU) row (see C07 n4)"
    assert ledger.get("1586") != ledger.get("7551"), (
        "C02/Q9: the two devices share a pool name — per-device NAMING is the ruling "
        "(amd.com/gpu-ai-pro-r9700 vs amd.com/gpu-8060s)"
    )
    apu_name = f"amd.com/{ledger['1586']}"
    assert apu_name != R.GPU_CLAIM and apu_name == R.APU_CLAIM, (
        f"C02 AC4: the ledger's 1586 pool {apu_name!r} must equal this suite's APU constant "
        f"{R.APU_CLAIM!r} and differ from radiance's {R.GPU_CLAIM!r} (disjoint pools, one string each)"
    )
    # Render-level cross-chart read: the llama-swap testlib resolves its own
    # per-directory imports only when its dir is on sys.path (suites run
    # per-directory — the repo layout law; this arm is the sanctioned
    # cross-surface exception: the C02 cross-chart identity test is the
    # single needle joining the two charts' claims).
    import sys

    swap_tests = R.REPO_ROOT / "charts" / "llama-swap" / "tests"
    assert swap_tests.is_dir(), "C02 AC4: charts/llama-swap/tests missing — nothing to render against"
    if str(swap_tests) not in sys.path:
        sys.path.insert(0, str(swap_tests))
    import llama_swap_testlib as LS

    ls_ok, ls_reason = LS.helm_ready()
    if not ls_ok:
        pytest.skip(f"llama-swap render leg needs helm: {ls_reason}")

    def _main_limits(cluster: str) -> dict:
        docs = LS.render_docs(cluster)
        dep = next(d for d in docs
                   if d.get("kind") == "Deployment" and d.get("metadata", {}).get("name") == "llama-swap")
        main = next(c for c in dep["spec"]["template"]["spec"]["containers"] if c.get("name") == "main")
        return (main.get("resources") or {}).get("limits") or {}

    ai_limits = _main_limits("gpu-ai")
    assert ai_limits == {apu_name: 1}, (
        f"C02 AC4/D21: gpu-ai overlay-merged llama-swap limits are {ai_limits}, want exactly "
        f"{{{apu_name!r}: 1}} — the named-APU guarantee lives in the overlay, not the chart line"
    )
    gpu_limits = _main_limits("gpu")
    assert gpu_limits == {R.GPU_CLAIM_BARE: 1}, (
        f"C02/D21 shield: gpu-cluster llama-swap limits are {gpu_limits}, want exactly "
        f"{{{R.GPU_CLAIM_BARE!r}: 1}} — its external single-naming plugin can advertise only "
        "the bare name; a flip here is the B1 leak"
    )


@helm_skip
def test_bare_claim_absent_from_everything_this_chart_ships():
    """§R6-Q4-3: after the flip a stray bare amd.com/gpu claim anywhere
    becomes Pending-forever. Radiance ships none — and the string appears in
    this chart only inside comments explaining exactly that."""
    docs, raw = R.render(service=False)
    import yaml

    res_blob = yaml.safe_dump([R.resources(c) for c in
                               R.pod_spec(R.deployment(docs)).get("containers", [])
                               + R.pod_spec(R.deployment(docs)).get("initContainers", [])])
    assert f'"{R.GPU_CLAIM_BARE}":' not in res_blob and f"{R.GPU_CLAIM_BARE}:" not in res_blob, (
        "C02: a bare amd.com/gpu resource key rendered"
    )
    values_text = R.CHART_DIR.joinpath("values.yaml").read_text()
    bare_live = [ln for ln in values_text.splitlines()
                 if not ln.lstrip().startswith("#") and f"{R.GPU_CLAIM_BARE}:" in ln]
    assert not bare_live, (
        f"C02: live bare amd.com/gpu claim in charts/radiance/values.yaml: {bare_live}"
    )
    assert raw.count(R.GPU_CLAIM_BARE + ":") == 0, (
        "C02: rendered manifests carry a bare amd.com/gpu:"
    )
