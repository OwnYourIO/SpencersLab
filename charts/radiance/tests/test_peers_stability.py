# cf-143 C02 — the served-id single authority (chunks/C02.md Tests bullet 4).
# `--served-model-name qwen3.8-flash-next-radiance` is THE id: C04's peer
# models list, C05's catalog rows and C06's runbook all consume exactly this
# string (DECISIONS D7 — the honest new id; reusing …-strata-q4 is the
# three-way-collision confusion the naming law warns about). One pin here,
# every downstream surface conforms — the evidence/anchor pattern the repo
# already runs for modelPath.
#
# Red state at handoff (designed): red until C02; the peer-evidence leg reads
# the test-session fixture (exists) against the render (lands with C02/C04).
#
# Run per-directory: python3 -m pytest charts/radiance/tests -v

from __future__ import annotations

import pytest

import radiance_testlib as R

_ok, _reason = R.helm_ready()
helm_skip = pytest.mark.skipif(not _ok, reason=_reason)


@helm_skip
def test_served_model_name_is_the_pinned_id():
    docs, _ = R.render(service=False)
    args = [str(a) for a in (R.serve_container(R.deployment(docs)).get("args") or [])]
    pairs = R.flag_pairs(args)
    assert pairs.get("--served-model-name") == R.SERVED_ID, (
        f"C02: --served-model-name is {pairs.get('--served-model-name')!r}, want "
        f"{R.SERVED_ID!r} — the single id authority for C04/C05/C06 (D7)"
    )


@helm_skip
def test_served_id_matches_the_peer_evidence_single_source():
    """The radiance peer evidence (test-session single source, D13) names the
    same id the engine serves: if the chart flips --served-model-name without
    the evidence re-author, this reds BEFORE any render-time mismatch can
    reach the cluster."""
    ev = R.radiance_peers_evidence()
    assert ev["models_allowed"] == [R.SERVED_ID], (
        f"C04 evidence vs C02 id: evidence models_allowed {ev['models_allowed']} != [{R.SERVED_ID!r}]"
    )
    assert ev["proxy"] == R.PEER_URL, (
        f"C04 evidence proxy {ev['proxy']!r} != the chart NOTES/peer URL {R.PEER_URL!r}"
    )


def test_served_id_never_contains_strata():
    """The naming landmine made mechanical: a radiance-served id carrying
    "-strata" would collide the three-way record (engine-radiance vs
    vllm-radiance fork vs Strata) — the id must be exactly the honest new
    one, substring-clean of both retired names."""
    assert R.SERVED_ID == "qwen3.8-flash-next-radiance"
    for retired in ("strata", "vllm"):
        assert retired not in R.SERVED_ID, f"C02 D7: the served id embeds the {retired} era"
