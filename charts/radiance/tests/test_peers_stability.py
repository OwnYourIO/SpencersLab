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
    """The id is byte-unchanged by the C03 move — and D43 (2026-11-22) moved
    its CARRIER a second time: the serve id reaches the engine through the
    lane's RADIANCE_SERVED_ID env and the chart-owned wrapper's composed
    vector, so the single authority is now proven at BOTH: the rendered env
    names it exactly, and executing the shipped wrapper yields it. Designed-red
    until dev round 3 lands the wrapper + lane env."""
    comp = R.lane_composition("radiance")
    assert comp["env"].get(R.ENV_SERVED_ID) == R.SERVED_ID, (
        f"C03/D43: rendered env {R.ENV_SERVED_ID} is {comp['env'].get(R.ENV_SERVED_ID)!r}, want "
        f"{R.SERVED_ID!r} — env is the lane's id channel"
    )
    argv = comp["facts"]["argv"]
    assert argv, "C03/D43: no composed vector to read the served id from"
    pairs = R.flag_pairs(argv)
    assert pairs.get("--served-model-name") == R.SERVED_ID, (
        f"C02: the COMPOSED --served-model-name is {pairs.get('--served-model-name')!r}, want "
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


# --- cf-143 C15: the q27 peer, the same per-peer law at the second release -------


@helm_skip
def test_q27_served_id_matches_the_q27_peer_evidence_single_source():
    """C15 T2 ("extend per-peer"): the q27 evidence file (D13 per-key
    sibling — its own models_states chain) names the served id the q27
    subtree's --served-model-name renders, and the proxy equals the
    appset-derived q27 cluster DNS (no /v1 — the request path appends
    verbatim, the peer law is release-independent). Designed-red until
    C15-dev lands the radiance-q27 subtree: the render raises naming C15."""
    ev = R.radiance_q27_peers_evidence()
    assert ev["models_allowed"] == [R.Q27_SERVED_ID], (
        f"cf-143 C15: q27 evidence models_allowed {ev['models_allowed']} != [{R.Q27_SERVED_ID!r}]"
    )
    assert ev["proxy"] == R.Q27_PEER_URL, (
        f"cf-143 C15: q27 evidence proxy {ev['proxy']!r} != {R.Q27_PEER_URL!r} "
        "(gpu-ai + appName radiance-q27, the peers hop's host)"
    )
    R.render_q27()  # fail fast (naming C15) if the subtree never landed
    comp = R.lane_composition(R.Q27_APP_NAME)
    env_id = comp["env"].get(R.ENV_SERVED_ID)
    assert env_id == ev["models_allowed"][0], (
        f"C15/D43: q27 rendered env {R.ENV_SERVED_ID}={env_id!r}, want the evidence id — env is "
        "the lane's id channel"
    )
    argv = comp["facts"]["argv"]
    assert argv, "C15/D43: no q27 composed vector"
    pairs = R.flag_pairs(argv)
    assert pairs.get("--served-model-name") == ev["models_allowed"][0], (
        f"cf-143 C15: q27 compose serves {pairs.get('--served-model-name')!r}, want the "
        "evidence id — the q27 lane gets ONE served-id authority (the fn D7 pattern)"
    )
    for retired in ("strata", "vllm"):
        assert retired not in R.Q27_SERVED_ID, f"cf-143 C15: the q27 id embeds the {retired} era"
