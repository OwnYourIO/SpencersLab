"""2026-11-feat-radiance-multi-instance C05 — the two RESTING lanes.

The gpu-ai roster grows `radiance-flash-tp1` (the cf-143 TP1 array, second
release, one card) and `radiance-q27-tp2` (the q27 array plus the TP2 pair,
both cards). Both rest at `replicas: 0`: git resting state, flipped only by an
owner scale act.

Red state at handoff (designed): every roster/block/render/args leg is RED
against today's tree (neither block exists) and greens with C05-dev's wave.
The legs that stay GREEN now are the drift bars — the transcription sources
still resolve, the evidence files (test-session single sources) self-validate,
and the CI extraction idiom works before AND after the blocks land.

Run per-directory: python3 -m pytest charts/radiance/tests -v
"""

from __future__ import annotations

import collections
import re
import shutil
import subprocess

import pytest
import yaml

import radiance_testlib as R

_ok, _reason = R.helm_ready()
helm_skip = pytest.mark.skipif(not _ok, reason=_reason)

LANE_NAMES = R.NEW_LANE_NAMES


def _block(name):
    block = R.lane_block(name)
    assert isinstance(block, dict), (
        f"C05: services/gpu-ai/prod/values.yaml carries no top-level {name}: block — "
        "dev's roster entry has not landed; designed-red naming C05"
    )
    return block


def _container(name):
    return (
        _block(name).get("app-template", {}).get("controllers", {})
        .get("radiance", {}).get("containers", {}).get("radiance", {})
    )


def _args(name):
    args = _container(name).get("args")
    assert isinstance(args, list) and args, (
        f"C05: the {name} block carries no args array — the lane's whole-list replacement "
        "is the entire serving profile (D56/C03 shape); designed-red naming C05"
    )
    return [str(a) for a in args]


def _flag_map(args):
    """args as {flag: value}, repeating flags collected."""
    out = collections.defaultdict(list)
    i = 0
    while i < len(args):
        tok = args[i]
        if tok.startswith("--"):
            if "=" in tok:
                k, v = tok.split("=", 1)
                out[k].append(v)
                i += 1
                continue
            out[tok].append(args[i + 1] if i + 1 < len(args) else "")
            i += 2
            continue
        i += 1
    return out


def _pairs(docs, kind):
    return [d for d in docs if isinstance(d, dict) and d.get("kind") == kind]


# --- AC1: roster shape, resting replicas, the Guaranteed pair ------------------


@pytest.mark.parametrize("name", LANE_NAMES)
def test_c05_roster_entry_is_the_chart_override(name):
    """C05 AC1: the charts: map carries the lane entry EXACTLY — one chart dir,
    one release per roster key, the internal shape (no version/repository), and
    ServerSideApply "false" cloned from the existing radiance entries."""
    doc = yaml.safe_load(R.SERVICE_VALUES.read_text())
    entry = (doc.get("charts") or {}).get(name)
    assert isinstance(entry, dict), (
        f"C05: charts.{name} missing from the gpu-ai roster — the Application "
        f"gpu-ai-{name} that peers.{name} proxies to does not exist; designed-red naming C05"
    )
    assert entry == R.lane(name)["roster"], (
        f"C05: charts.{name} is {entry}, want EXACTLY {R.lane(name)['roster']} "
        "(chart-dir override is what lets one chart serve four releases)"
    )


@pytest.mark.parametrize("name", LANE_NAMES)
def test_c05_lane_rests_at_zero_replicas(name):
    """C05 AC1/AC5: nothing routes here by default, so nothing may run by default —
    the shipped replicas value is 0 (an owner scale act, never a git default)."""
    spec = R.lane(name)
    authored = _container(name).get("replicas", _block(name).get("replicas"))
    assert authored == 0, (
        f"C05: {name} ships replicas {authored!r}, want 0 — a resting lane that boots steals "
        f"the cards from the live lane and answers 200 where the tables say the lane is opt-in"
    )
    if _ok:
        docs, _raw = R.render_lane(name)
        deploys = _pairs(docs, "Deployment")
        assert deploys, f"C05: the {spec['release']} render has no Deployment"
        for dep in deploys:
            got = dep.get("spec", {}).get("replicas")
            assert got == 0, f"C05: rendered replicas {got!r}, want 0 for {spec['release']}"


@pytest.mark.parametrize("name", LANE_NAMES)
def test_c05_lane_pair_is_guaranteed_on_the_renamed_pool(name):
    """C05 AC1: memory request==limit (Guaranteed) at the specced figure, and the GPU
    claim pair on the RENAMED pool at the lane's card count, in the shipped QUOTED
    form — an unquoted pair is a different Helm type and a straggler on the retired
    pool is a pod that PENDINGs forever (C01 R-Q5)."""
    spec = R.lane(name)
    res = _container(name).get("resources", {})
    req, lim = res.get("requests"), res.get("limits")
    assert req and lim and req == lim, (
        f"C05: {name} resources are requests={req} limits={lim} — the pair must be EQUAL "
        "(Guaranteed QoS); a burstable lane OOM-kills the card it is holding"
    )
    assert req.get("memory") == spec["memory"], (
        f"C05: {name} memory {req.get('memory')!r}, want {spec['memory']!r} "
        "(110Gi is the fn working set this lane re-boots; 24Gi is q27's adjudicated print)"
    )
    claim = req.get(R.GPU_CLAIM)
    assert claim == spec["claim"], (
        f"C05: {name} requests[{R.GPU_CLAIM}] is {claim!r}, want {spec['claim']!r} — "
        "the claim count IS the card arithmetic (TP1 one card, TP2 both)"
    )
    assert lim.get(R.GPU_CLAIM) == spec["claim"], f"C05: {name} limits claim must mirror requests"
    text = R.lane_region_text(name)
    quoted = re.search(re.escape(R.GPU_CLAIM) + r":\s*[\"']" + re.escape(spec["claim"]) + r"[\"']", text)
    assert quoted, (
        f"C05: {name}'s claim is not authored in the shipped quoted form "
        f"({R.GPU_CLAIM}: \"{spec['claim']}\") — the needle is sharp on purpose: the bare-value "
        "shape is what made the old carrier sweep vacuous (C01 AC3)"
    )


# --- AC1 transcription proofs: the args come from a named source, not invention --


@pytest.mark.skipif(shutil.which("git") is None, reason="git binary unavailable — the transcription source cannot resolve")
def test_c05_flash_tp1_args_are_the_cf143_tp1_array_verbatim():
    """C05 AC1 (OQ-F): the flash-TP1 lane is the cf-143 TP1-era chart array with
    EXACTLY one value swapped — its own served id. Anything else means the lane was
    re-derived by hand, and the TP1 profile (pool 43000, --kv-resident 32768,
    expert_tiered, speculative 3) is exactly what a hand-copy gets wrong."""
    commit, path = R.FLASH_TP1_TRANSCRIPTION
    shown = subprocess.run(["git", "show", f"{commit}:{path}"], capture_output=True, text=True, timeout=120)
    assert shown.returncode == 0, (
        f"C05: the transcription source {commit}:{path} does not resolve — the proof has no "
        "authority, so the leg fails rather than passing vacuously (env note: needs git)"
    )
    source = (yaml.safe_load(shown.stdout).get("app-template") or {}).get("serveArgs")
    assert isinstance(source, list) and source, f"C05: no serveArgs at {commit}:{path}"
    want = [str(a) for a in source]
    want = [R.lane(R.FLASH_TP1_APP_NAME)["served_id"] if a == R.SERVED_ID else a for a in want]
    got = _args(R.FLASH_TP1_APP_NAME)
    assert got == want, (
        f"C05: the flash-TP1 args are not the {commit} TP1 array verbatim except the served id — "
        f"first difference at {next((i for i, (a, b) in enumerate(zip(got, want)) if a != b), min(len(got), len(want)))}"
        f"\n got  : {got}\n want : {want}"
    )


def test_c05_q27_tp2_args_are_the_q27_array_plus_the_tp_pair():
    """C05 AC1 (OQ-G): 27b-TP2 is the EXISTING q27 array plus `--tp 2 --tp-wire wht6`
    with its own served id — the source is the sibling block in the same file, so the
    proof is a set difference, not a copy."""
    base = _args(R.Q27_APP_NAME)
    want = [R.lane(R.Q27_TP2_APP_NAME)["served_id"] if a == R.Q27_SERVED_ID else a for a in base]
    want = want + list(R.Q27_TP2_EXTRA_FLAGS)
    got = _args(R.Q27_TP2_APP_NAME)
    flags = _flag_map(got)
    assert flags["--tp"] == ["2"], f"C05: 27b-TP2 --tp is {flags.get('--tp')}, want ['2']"
    assert flags["--tp-wire"] == ["wht6"], f"C05: 27b-TP2 --tp-wire is {flags.get('--tp-wire')}, want ['wht6']"
    extra = [a for a in got if a not in want]
    missing = [a for a in want if a not in got]
    assert not extra and not missing, (
        f"C05: 27b-TP2 args drift from (q27 array + --tp 2 --tp-wire wht6 + its own served id): "
        f"extra={extra} missing={missing}"
    )


@pytest.mark.parametrize("name", LANE_NAMES)
def test_c05_lane_serves_its_own_id_exactly_once(name):
    """Honest-id law: each lane advertises exactly one id, its own, and no two lanes
    collide — a duplicate --served-model-name makes the peer models list ambiguous
    and the solver's model routing non-deterministic."""
    spec = R.lane(name)
    flags = _flag_map(_args(name))
    assert flags["--served-model-name"] == [spec["served_id"]], (
        f"C05: {name} --served-model-name is {flags.get('--served-model-name')}, "
        f"want exactly [{spec['served_id']!r}]"
    )
    others = {n: R.lane(n)["served_id"] for n in R.LANES if n != name}
    others["radiance"] = R.SERVED_ID
    others[R.Q27_APP_NAME] = R.Q27_SERVED_ID
    assert spec["served_id"] not in others.values(), (
        f"C05: {name}'s id {spec['served_id']!r} collides with another lane: {others}"
    )


# --- AC3: internal-only shape, no secret, no sentinel --------------------------


@pytest.mark.parametrize("name", LANE_NAMES)
@helm_skip
def test_c05_lane_renders_no_ingress_no_secret_no_sentinel(name):
    """C05 AC3: the lanes are cluster-internal (peers talk Service DNS), so an ingress
    or a Secret in the render is a surface nobody asked for; the keyless lane must also
    carry no OVERRIDE_VIA_CUSTOM_VALUES placeholder (cf-143 D8 — no custom-values entry
    exists for these keys)."""
    docs, raw = R.render_lane(name)
    for kind in ("Ingress", "Secret"):
        assert not _pairs(docs, kind), f"C05: the {name} render emits a {kind} — the lane is internal-only and keyless"
    assert "OVERRIDE_VIA_CUSTOM_VALUES" not in raw, (
        f"C05: the {name} render carries a custom-values placeholder — the lanes are keyless (D8); "
        "a sentinel here has no custom-values/ entry and ships as a literal string"
    )
    assert R.keyless_env_token() not in raw, (
        f"C05: the {name} render names the keyless env var — keyless law (D8), assembled here so the ban stays real"
    )


@pytest.mark.parametrize("name", LANE_NAMES)
def test_c05_lane_pack_is_the_named_pack_with_the_skip_law(name):
    """C05: the pack scalars are the lane's model's pack — the flash lane re-uses the fn
    pack (one 500Gi PVC holds it once; the init marker-skip makes a co-boot cheap), the
    27b lane re-uses the q27 pack. The skip paragraph must exist in the block's comments:
    it is the reader's only warning that a scale-up does not re-download."""
    path, repo, size, sha = R.lane(name)["pack"]
    flags = _flag_map(_args(name))
    assert flags["--model"] == [path], f"C05: {name} --model is {flags.get('--model')}, want [{path!r}]"
    region = R.lane_region_text(name)
    for needle, what in (
        (repo, "the pack repo"),
        (str(size), "the pack byte count"),
        (sha, "the pack LFS sha"),
    ):
        assert needle in region, f"C05: the {name} block never states {what} ({needle}) — the init script's own verification authority is this ledger"
    assert re.search(r"(?i)marker|skip|already|same pack|one PVC|shared volume", region), (
        f"C05: the {name} block lacks the pack-skip paragraph (the marker file makes a co-boot with "
        "its sibling a no-download — without the sentence a reader assumes a second 120 GiB fetch)"
    )


@pytest.mark.parametrize("name", LANE_NAMES)
def test_c05_lane_region_carries_the_idle_and_scale_laws(name):
    """C05 AC5/AC7: two sentences must be readable where the owner edits — the 502-while-idle
    law (the hop is loud, never silent) and the scale-act discipline (0 is git resting state)."""
    region = R.lane_region_text(name)
    assert re.search(r"(?i)502", region) and re.search(r"(?i)idle|no endpoints|replicas 0|at 0\b", region), (
        f"C05: the {name} block never states the 502-while-idle law — a peer whose lane is at 0 answers "
        "the peer-proxy error and llama-swap neither health-checks nor hides it (the loud-by-design law)"
    )
    assert re.search(r"(?i)owner|scale|never a git default|human", region), (
        f"C05: the {name} block never says the 0 is a resting state an OWNER flips — without it the next "
        "editor treats replicas as a tunable and boots a lane the node cannot fit (AC7 arithmetic)"
    )


# --- AC2: the peers surface, evidence-first ------------------------------------


@pytest.mark.parametrize("name", LANE_NAMES)
def test_c05_lane_peers_entry_matches_its_evidence(name):
    """C05 AC2 (law order): the evidence YAML is the single source (test-authored);
    config.peers.<lane> must equal it — proxy host derived from the roster key, NO /v1,
    the lane's own models list, the lane's own priority floor, and no apiKey."""
    ev = R.lane_peers_evidence(name)
    doc = yaml.safe_load(R.SERVICE_VALUES.read_text())
    peers = ((doc.get("llama-swap") or {}).get("config") or {}).get("peers") or {}
    peer = peers.get(name)
    assert isinstance(peer, dict), (
        f"C05: config.peers.{name} missing — the solver has no hop for the lane; designed-red naming C05 "
        "(evidence exists, values must conform to it, never the reverse)"
    )
    assert peer.get("proxy") == ev["proxy"], (
        f"C05: peers.{name}.proxy is {peer.get('proxy')!r}, want {ev['proxy']!r} — the host must equal the "
        f"derived Application name gpu-ai-{name} and carry no /v1 (paths append verbatim)"
    )
    assert "/v1" not in str(peer.get("proxy")), f"C05: peers.{name}.proxy carries a /v1 suffix"
    assert peer.get("models") == ev["models_allowed"], (
        f"C05: peers.{name}.models is {peer.get('models')}, want {ev['models_allowed']} "
        f"(must be one of the sanctioned waves {ev['models_states']})"
    )
    assert "apiKey" not in peer and "apiKeyEnv" not in peer, f"C05: peers.{name} carries a key — keyless lanes (D8)"
    floor = ((peer.get("filters") or {}).get("setParams") or {}).get("priority?")
    want_floor = ((ev.get("filters") or {}).get("setParams") or {}).get("priority?")
    assert floor == want_floor, (
        f"C05: peers.{name} priority floor is {floor!r}, want {want_floor!r} — the floor is THIS lane's own "
        "default class (the cf-143 per-lane coherence law), never fn's 5"
    )


@pytest.mark.parametrize("name", LANE_NAMES)
def test_c05_new_ids_stay_out_of_the_outer_models_and_matrix(name):
    """C05 AC2: peers are invisible to the solver's own model list — the lane id appears
    ONLY in its peers entry and its catalog rows. A copy in the outer models list or the
    matrix makes a resting lane look routable, which is exactly the default-route bar C02 sets."""
    served = R.lane(name)["served_id"]
    doc = yaml.safe_load(R.SERVICE_VALUES.read_text())
    cfg = ((doc.get("llama-swap") or {}).get("app-template") or {}).get("config") or {}
    for key in ("models", "matrix"):
        blob = yaml.safe_dump(cfg.get(key) or "")
        assert served not in blob, (
            f"C05: {served!r} appears in llama-swap config.{key} — resting ids live in the catalog and their "
            "own peers entry only; the outer list is the solver's routable set"
        )


# --- AC7: the card arithmetic, and CI ------------------------------------------


def test_c05_card_arithmetic_is_claim_math():
    """C05 AC7: the steady-state table is arithmetic, not policy — with two cards in the
    pool, fn TP2 (2) plus anything else cannot co-boot, and the C04 lane counts too:
    strata(1) + flash-TP2(2) = 3 > 2. Encoded from the lane claims themselves so the
    statement cannot drift from the shipped numbers."""
    cards = 2
    tp2_claims = int(R.lane(R.Q27_TP2_APP_NAME)["claim"])
    tp1_claims = int(R.lane(R.FLASH_TP1_APP_NAME)["claim"])
    assert tp2_claims == cards, "the TP2 lanes claim the whole pool — that is what makes co-boot dead"
    assert tp1_claims + tp2_claims > cards, (
        "flash-TP1 + 27b-TP2 must NEVER co-boot (1+2 > 2 cards); if this flips, the pool grew and "
        "the plan's steady-state table needs re-deriving, not this leg"
    )
    assert 1 + tp2_claims > cards, "strata(1) + a TP2 lane = 3 > 2 — the parked-MoE law is claim math (D17)"


@pytest.mark.parametrize("name", LANE_NAMES)
def test_c05_ci_extracts_and_renders_each_new_lane(name):
    """C05 AC4: the workflow gains one extraction+render step per lane using the d.get
    idiom, which works BEFORE the block lands (yields {}) and after. PATHS stay
    byte-untouched (test_contract owns that pin)."""
    text = R.WORKFLOW.read_text()
    assert f"d.get('{name}') or {{}}" in text, (
        f"C05: .github/workflows/radiance-render-tests.yaml has no extraction step for {name} — "
        "the lane's render is untested in CI until the step exists"
    )
    assert f"helm template gpu-ai-{name} charts/radiance" in text, (
        f"C05: no render step for gpu-ai-{name}"
    )
