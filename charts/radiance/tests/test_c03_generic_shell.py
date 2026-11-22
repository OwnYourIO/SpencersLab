"""2026-11-feat-radiance-multi-instance C03 — charts/radiance becomes mechanism.

C03 relocates; it decides nothing. The two existing lanes' DATA (serve args, GPU
claim pair, memory, pack ledger) moves from charts/radiance/values.yaml into the
lanes' service roster blocks, and the proof is that the rendered Deployment does
not change. So the strongest legs here are EQUIVALENCE legs against fixtures
captured pre-move (evidence/pre-move-render-*.yaml, re-derived by
capture_c03_fixtures.py) — green before the wave and after it, red if anything
but the relocation moves.

Red state at handoff (designed): the chart-stripped legs (no lane args, no claim,
no pack literals, no sourceDir trap), the q27 whole-script retirement, and the
NOTES.txt shell-law rewrite name C03.

Run per-directory: python3 -m pytest charts/radiance/tests -v
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest
import yaml

import radiance_testlib as R

_ok, _reason = R.helm_ready()
helm_skip = pytest.mark.skipif(not _ok, reason=_reason)

EVIDENCE = Path(__file__).resolve().parent / "evidence"

# The two lanes that exist today and whose renders must not move.
MOVING_LANES = {"radiance": "gpu-ai-radiance", R.Q27_APP_NAME: R.Q27_RELEASE}


def _fixture(key: str) -> dict:
    path = EVIDENCE / f"pre-move-render-{key}.yaml"
    assert path.is_file(), (
        f"C03: {path.name} missing — the pre-move equivalence fixture is the pre-move half of the "
        "proof; re-derive it with charts/radiance/tests/capture_c03_fixtures.py"
    )
    return yaml.safe_load(path.read_text())


def _fold(text: str) -> str:
    """Fold the pool name to the fixture token (see the fixture header): the rename
    is the one difference C03 may inherit, and a retired-pool spelling folds to
    `<POOL>-1`, which matches nothing."""
    return text.replace(R.GPU_CLAIM, "<POOL>")


def _rendered_deployment(key: str) -> dict:
    """The release's render at the shape production feeds it: the chart plus that
    roster key's block under the derived Application name."""
    if key == R.Q27_APP_NAME:
        docs, _raw = R.render_q27()
    else:
        docs, _raw = R.render(release=MOVING_LANES[key], service=True)
    deps = [d for d in docs if d.get("kind") == "Deployment"]
    assert len(deps) == 1, f"{MOVING_LANES[key]}: expected one Deployment, got {len(deps)}"
    return deps[0]


def _first_diff(a, b, path="$"):
    """(serialized a-side, serialized b-side) at the first structural difference."""
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a or k not in b:
                return (f"{path}.{k} = {a.get(k, '<ABSENT>')}", f"{path}.{k} = {b.get(k, '<ABSENT>')}")
            left, right = _first_diff(a[k], b[k], f"{path}.{k}")
            if left != right:
                return left, right
        return path, path
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return (f"{path} length {len(a)}", f"{path} length {len(b)}")
        for i, (x, y) in enumerate(zip(a, b)):
            left, right = _first_diff(x, y, f"{path}[{i}]")
            if left != right:
                return left, right
        return path, path
    return (f"{path} = {a}" if a != b else path, f"{path} = {b}" if a != b else path)


@pytest.mark.parametrize("key,release", sorted(MOVING_LANES.items()))
@helm_skip
def test_c03_move_is_render_byte_equivalent(key, release):
    """C03 AC1 (the chunk's core): post-move render == the captured pre-move Deployment,
    byte for byte after the pool-name fold. Args arrays, claim/memory pairs, the init
    script tokens, probes, grace and replicas are all inside this comparison — a
    "relocation" that changes one serving flag fails here rather than at boot."""
    fix = _fixture(key)
    want = fix["deployment"]
    got = json.loads(_fold(json.dumps(_rendered_deployment(key), sort_keys=True)))
    left, right = _first_diff(want, got)
    assert got == want, (
        f"C03 AC1: the {release} render moved across the relocation. "
        f"(fixture captured at {fix['captured_from_commit'][:9]}; re-derive it ONLY if the tree moved "
        f"for a reason C03 does not own)\n  want: {left}\n  got : {right}"
    )


# --- AC2: the chart is mechanism only ------------------------------------------


def test_c03_chart_ships_no_lane_data():
    """C03 AC2 (OQ-D): the chart keeps image/pin/probes/security/PVC/service/init MECHANISM and
    carries no lane DATA — no serve array, no GPU claim, no per-pack sha/URL/byte literals, no
    modelPath default. A second release of the same chart would otherwise inherit the fn lane's
    numbers, which is the exact failure the four-lane roster cannot work around."""
    text = R.chart_values_text()
    data = R.chart_values()
    at = data.get("app-template") or {}
    assert "serveArgs" not in at and "--model" not in text, (
        "C03 AC2: charts/radiance/values.yaml still carries a lane serve array — the lane args belong in the "
        "release block (OQ-D mechanism-only shell); designed-red naming C03"
    )
    live_claims = [
        ln for ln in text.splitlines()
        if re.match(r"^\s*" + re.escape(R.GPU_CLAIM) + r":\s*[\"']?[0-9]", ln) and not ln.lstrip().startswith("#")
    ]
    assert not live_claims, (
        f"C03 AC2: the chart still ships a live GPU claim line {live_claims} — every release of a generic shell "
        "would claim the fn lane's card count (the per-block claim pair is the carrier)"
    )
    for literal, what in (
        (R.PACK_LFS_SHA, "the fn pack LFS sha"),
        (R.Q27_PACK_LFS_SHA, "the q27 pack LFS sha"),
        (str(R.PACK_BYTES), "the fn pack byte count"),
        (str(R.Q27_PACK_BYTES), "the q27 pack byte count"),
    ):
        assert literal not in text, (
            f"C03 AC2: the chart still hard-codes {what} ({literal}) — a per-pack literal in a generic shell is "
            "a law the second release cannot obey; the init script takes it as a per-release scalar"
        )


def test_c03_source_dir_trap_stays_dead():
    """C03 (gotcha 11): the inert `radianceFetch.sourceDir` lever — a key a reader retargets and the
    script never reads — must not exist in the shell or in a lane block. BAR, not a red: the key is
    ALREADY absent at this ticket's base (the plan's gotcha names a site the cf-144 wave removed), and
    the leg exists so C03's parameterization cannot reintroduce it alongside the real scalars."""
    for path in (R.CHART_DIR / "values.yaml", R.SERVICE_VALUES):
        assert not re.search(r"(?m)^\s*sourceDir\s*:", path.read_text()), (
            f"C03: {path} declares sourceDir — an inert lever is worse after C03 than before it, because "
            "the lane blocks now carry the REAL pack scalars and a reader cannot tell which one the init "
            "script obeys"
        )


@pytest.mark.skipif(not _ok, reason="render env")
def test_c03_q27_drops_the_whole_script_for_scalars():
    """C03 (task 3): the q27 block stops replacing the init container's whole `command` and carries its
    four pack scalars instead, so the chart's template composes the script. The equivalence leg proves
    the rendered bytes stay the same; this leg proves the maintenance shape changed — a per-lane fork of
    the fetch script is the one thing the D27 BusyBox-grammar legs cannot protect, and EXPLORE gotcha 11
    names it as the reason the q27 overlay's own lever was already inert."""
    block = R.q27_service_block()
    assert isinstance(block, dict), "C03: no radiance-q27 block to inspect — designed-red naming C03"
    controllers = (block.get("app-template") or {}).get("controllers") or {}
    fetch = ((controllers.get("radiance") or {}).get("initContainers") or {}).get(R.INIT_NAME) or {}
    assert "command" not in fetch, (
        "C03: the radiance-q27 block still replaces the whole fetch script (initContainers.radiance-fetch.command) "
        "— designed-red naming C03: the lane passes PACK/LFS_SHA/URL/MARKER/MODEL_PATH as scalars and the chart "
        "template owns the BusyBox-portable gate"
    )
    blob = str(fetch)
    for needle, what in (
        (R.Q27_PACK_LFS_SHA, "the LFS sha"),
        (R.Q27_PACK_URL, "the pack URL"),
        (R.Q27_MODEL_PATH, "the pack path"),
    ):
        assert needle in blob, f"C03: the q27 block no longer states {what} ({needle}) — the scalars replace the script, not the facts"


@helm_skip
def test_c03_chart_bare_render_is_mechanism_only():
    """C03 AC2 (the render-side pair of the values-level bar): `helm template` on the bare chart must
    still be valid and must schedule nothing and serve nothing — zero GPU claim lines, zero lane serve
    args, zero pack literals, and no OVERRIDE sentinel. A shell that renders a half-lane is worse than a
    lane-specific chart: it looks deployable."""
    docs, raw = R.render(service=False)
    assert docs, "C03: the bare chart renders nothing"
    assert R.GPU_CLAIM not in raw, (
        f"C03 AC2: the bare chart render still claims {R.GPU_CLAIM} — the claim is lane data and belongs in "
        "the release block; designed-red naming C03"
    )
    assert "--model" not in raw, (
        "C03 AC2: the bare chart render still serves a model path — with four releases of one chart the "
        "bare render must carry the mechanism (probes, security, PVC, init template) and no lane args"
    )
    for literal, what in ((R.PACK_LFS_SHA, "fn LFS sha"), (R.Q27_PACK_LFS_SHA, "q27 LFS sha")):
        assert literal not in raw, f"C03 AC2: the bare render embeds {literal} ({what}) — a per-lane fact"
    assert "OVERRIDE_VIA_CUSTOM_VALUES" not in raw, "C03 AC3: an OVERRIDE sentinel entered the render (D8 keyless law)"


@pytest.mark.parametrize("key", sorted(MOVING_LANES))
@helm_skip
def test_c03_model_path_and_serve_headroom_agree_per_lane(key):
    """Dual-edit guard, per lane (the cf-143 D27 idiom relocated): the block's modelPath must equal the
    `--model` its args actually serve. Split edits are how a lane ends up serving the sibling's pack."""
    release = MOVING_LANES[key]
    cont = _rendered_deployment(key)["spec"]["template"]["spec"]["containers"][0]
    args = [str(a) for a in cont.get("args") or []]
    served = args[args.index("--model") + 1] if "--model" in args else None
    assert served, f"C03: {release} renders no --model — the lane serves nothing"
    block = yaml.safe_load(R.SERVICE_VALUES.read_text()).get(key) or {}
    declared = (block.get("app-template") or {}).get("modelPath")
    assert declared in (None, served), (
        f"C03: {key} declares modelPath {declared!r} but serves {served!r} — the dual-edit guard: the ledger "
        "path and the served path are one fact written twice"
    )


# --- AC1/AC2 carrier: NOTES.txt says shell law ---------------------------------


def test_c03_notes_state_the_four_lane_shell():
    """C03 (task 2): NOTES.txt becomes shell law — it enumerates the lanes, states the claim math per
    lane (any TP2 holds both cards; at most one TP2 up; at the transcribed memory the two TP1 lanes cannot
    co-boot), and repeats the 502-idle law. The fn-only text is what a q27 or resting-lane operator reads
    today, and it is wrong for them."""
    notes = (R.CHART_DIR / "templates" / "NOTES.txt").read_text()
    flat = " ".join(notes.split())
    for lane_name in ("radiance", R.Q27_APP_NAME, R.FLASH_TP1_APP_NAME, R.Q27_TP2_APP_NAME):
        assert lane_name in flat, (
            f"C03: NOTES.txt never names the {lane_name} lane — the chart is one shell with four releases and "
            "the notes still read as the fn lane's private page"
        )
    assert re.search(r"(?i)tp ?2[^.]{0,80}(both cards|both devices|claim ?2)", flat), (
        "C03: NOTES.txt never states that any TP2 lane holds BOTH cards — the claim math is the operator's only "
        "warning before a scale-up PENDINGs"
    )
    assert re.search(r"(?i)(at most one|only one)[^.]{0,60}tp ?2", flat), (
        "C03: the at-most-one-TP2-UP law is missing (2+2 > 2 cards)"
    )
    assert "125.08" in flat and re.search(r"(?i)110[^.]{0,40}24", flat), (
        "C03: the two-TP1 co-boot arithmetic (110 + 24 + ~5.3 > 125.08) is not stated — the pool fits them, "
        "the node's RAM does not, and only the second fact stops an operator"
    )
    assert "502" in flat, "C03: the 502-while-idle law is absent from the shell notes"
