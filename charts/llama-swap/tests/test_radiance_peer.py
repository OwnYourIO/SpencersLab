# cf-143 C04 — the radiance peer join contract (chunks/C04.md Tests,
# bullets 1-2; the Q5 coexistence rule made executable from the SPEC side).
#
# The gpu-ai outer llama-swap render must gain peers.radiance EXACTLY as
# charts/llama-swap/tests/evidence/radiance-peers-expected.yaml sanctions
# (test-session single source — dev conforms values to it, never the
# reverse, same authority pattern as strata's file per DECISIONS D13),
# while peers.strata stays PRESENT-AND-UNCHANGED (Q5 verbatim: "Strata
# shouldn't be disabled yet"). The golden legs mirror the cf-105 T4 capture
# pattern: re-capture is the dev's paired obligation; these legs are red
# until it lands and re-align automatically after.
#
# Red state at handoff (designed): every leg here is red until C04 lands
# (peers.radiance does not exist yet; the golden predates the join). The
# strata-unchanged legs are green now and MUST stay green — a red there
# names a chunk that touched the strata surface (review rejects outright).
#
# Run with the suite (per-directory): python3 -m pytest charts/llama-swap/tests -v

from __future__ import annotations

import pytest

import llama_swap_testlib as L
import strata_testlib as S

_ok, _ok_reason = L.helm_ready()
pytestmark = pytest.mark.skipif(not _ok, reason=_ok_reason)

SERVED_ID = "qwen3.8-flash-next-radiance"  # C02 --served-model-name, D7 (honest new id)


def _peers(cfg: dict) -> dict:
    return cfg.get("peers") or {}


# --- T1: peers.radiance renders exactly the evidence-sanctioned block ---------


def test_t1_peers_radiance_block_exact():
    """C04 AC2 / Tests bullet 2: proxy URL http://gpu-ai-radiance.default.
    svc.cluster.local:8000 with NO /v1 (request-path-appends law), single
    model id, timeouts responseHeader 1800 / connect 30 (the ~66 GiB-class
    cold-load knob, strata O2 precedent restated), filters.setParams
    "priority?" = 5 (Q2 floor — radiance's DEFAULT class under the flipped
    higher-wins polarity), no apiKey (D8 keyless)."""
    cfg = L.rendered_config("gpu-ai")
    peers = _peers(cfg)
    assert "radiance" in peers, (
        "cf-143 C04 T1: rendered gpu-ai config has no peers.radiance — the additive join "
        "is not landed (charts.radiance appset entry + peer block are one chunk)"
    )
    ev = L.radiance_peers_evidence()
    peer = peers["radiance"]
    assert peer == L.expected_radiance_peer(ev, peer.get("models")), (
        f"cf-143 C04 T1: peers.radiance is {peer} — must be EXACTLY the evidence block "
        "(evidence/radiance-peers-expected.yaml is the single source; dev conforms values)"
    )
    assert "/v1" not in peer.get("proxy", ""), (
        f"cf-143 C04 T1: peer proxy {peer.get('proxy')!r} carries a /v1 suffix — the request "
        "path is appended verbatim, a suffix would double-prefix every route"
    )
    assert peer.get("proxy") == "http://gpu-ai-radiance.default.svc.cluster.local:8000", (
        "cf-143 C04 T1: proxy is not the gpu-ai-radiance Service cluster DNS — the appset "
        "release name is gpu-ai + appName radiance (charts/base appset-charts template)"
    )
    assert peer.get("models") == [SERVED_ID], (
        f"cf-143 C04 T1: models {peer.get('models')!r} must be exactly [{SERVED_ID!r}] — "
        "explicit ids (peers is not a blanket URL proxy) and the id equals the chart's "
        "--served-model-name (C02 single id authority)"
    )
    assert peer.get("timeouts") == {"responseHeader": 1800, "connect": 30}, (
        f"cf-143 C04 T1: timeouts {peer.get('timeouts')!r}, want 1800/30 (cold-load first-byte knob)"
    )
    floor = ((peer.get("filters") or {}).get("setParams") or {}).get("priority?")
    assert floor == 5, (
        f"cf-143 C04 T1: filters.setParams 'priority?' floor is {floor!r}, want 5 — the "
        "set-if-undefined default class under radiance's higher-wins polarity (Q2)"
    )
    assert "apiKey" not in peer, "cf-143 C04 T1: a peer apiKey contradicts the keyless ruling D8"


# --- T2: peers.strata PRESENT-and-UNCHANGED (the Q5 guarantee) ----------------


def test_t2_peers_strata_present_unchanged():
    cfg = L.rendered_config("gpu-ai")
    peers = _peers(cfg)
    assert "strata" in peers, (
        "cf-143 C04 T2: peers.strata MISSING from the render — Q5 says strata lives; "
        "removing it here is the scope violation review rejects outright"
    )
    strata_ev = yaml_strata_evidence()
    s = peers["strata"]
    assert set(s) == {"proxy", "models", "timeouts"}, (
        f"cf-143 C04 T2: the strata peer keys are {sorted(set(s))}, want exactly "
        "{proxy, models, timeouts} — the block is byte-stable through the radiance join "
        "(its 505-519 law comments included)"
    )
    assert s["proxy"] == strata_ev["proxy"] and s["timeouts"] == strata_ev["timeouts"], (
        "cf-143 C04 T2: strata proxy/timeouts moved — the strata peer block must be "
        "identical to its evidence file before AND after C04 (Q5)"
    )
    served = set(S.inner_config(L.render_docs("gpu-ai"))["models"])
    assert s["models"] == S.expected_strata_peers(served), (
        "cf-143 C04 T2: strata models left the sanctioned wave — C04 does not touch "
        "strata's arena routing"
    )


def yaml_strata_evidence() -> dict:
    import yaml

    return yaml.safe_load((L.TESTS_DIR / "evidence" / "strata-peers-expected.yaml").read_text())["strata"]


# --- T3: the re-captured golden carries ALL FIVE peers, strata byte-identical ----


def test_t3_golden_three_peer_shape():
    """C04 AC2 (golden half) RE-PINNED by C15 T2, and again by the
    cf-radiance C05 landing round (D19): the peers subtree of the re-captured
    golden is strata (byte-identical to the sanctioned shape) + the FOUR
    radiance lanes — the FIVE-key set is the sanctioned C05 state. The name
    keeps the era label (three-peer) as history; the body is the current law.
    The re-capture itself moved to the test landing round per TEST_SPEC §9
    (never a dev edit), delta recorded in the §12 capture note."""
    golden = L.golden_config("gpu-ai")
    gp = _peers(golden)
    assert set(gp) == {"strata", "radiance", "radiance-q27", "radiance-flash-tp1", "radiance-q27-tp2"}, (
        f"cf-radiance C05: golden peers keys {sorted(gp)} — golden/gpu-ai.config.yaml is "
        "not yet the five-peer (C05/D19) capture; the test landing round owns the re-capture "
        "against C05's renders, per the §12 golden law"
    )
    cfg = L.rendered_config("gpu-ai")
    assert gp == _peers(cfg), (
        "cf-radiance C05 T3: the golden's peers subtree diverges from the fresh render — "
        "re-capture per TEST_SPEC §1 with the landing round (paired obligation)"
    )
    ev = L.radiance_peers_evidence()
    assert gp["radiance"] == L.expected_radiance_peer(ev, gp["radiance"].get("models")), (
        "cf-143 C04 T3: the golden's radiance block is not the evidence-sanctioned shape"
    )
    ev27 = L.radiance_q27_peers_evidence()
    assert gp["radiance-q27"] == L.expected_radiance_q27_peer(ev27, gp["radiance-q27"].get("models")), (
        "cf-143 C15 T3: the golden's radiance-q27 block is not ITS OWN evidence-sanctioned "
        "shape (D13 per-key; floor 4, no /v1, no apiKey)"
    )
    for lane in L.RESTING_RADIANCE_LANES:
        ev_lane = L.radiance_lane_peers_evidence(lane)
        assert gp[lane] == L.expected_radiance_lane_peer(ev_lane, gp[lane].get("models")), (
            f"C05/D19 T3: the golden's {lane} block is not ITS OWN evidence-sanctioned shape "
            "(D13 per-key; its own default-class floor, no /v1, no apiKey)"
        )


# --- T4: the gpu cluster is unaffected (HOLD) ---------------------------------


def test_t4_gpu_render_stays_radiance_free():
    cfg = L.rendered_config("gpu")
    assert _peers(cfg).get("radiance") is None, (
        "cf-143 C04 T4: peers.radiance leaked into the gpu cluster render — the join is "
        "gpu-ai-only (the radiance pod and its claim live on ai-gpu)"
    )


def test_t4_gpu_golden_stays_cf143_peer_free():
    path = L.GOLDEN_DIR / "gpu.config.yaml"
    text = path.read_text().lower()
    assert "radiance" not in text, (
        "cf-143 C04 T4: the gpu golden carries radiance text — gpu's golden is untouched "
        "by the cf-143 waves (plan 'Golden churn')"
    )
