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

State update (D46, 2026-11-22): the two lane BLOCKS landed as C03 round-3
output and the args channel was retired by D43, so the block/render/composition
legs above are green; the standing designed reds are C05's own remaining scope
— the two charts: roster entries, the two peers entries, the two CI extraction
steps.

State update (2026-11-feat-radiance-fp8v4-lane D-16, 2026-11-24): a THIRD
resting lane joins this file's roster map — radiance-q27-fp8v4 (C03 lands its
block, so every NEW_LANE_NAMES-parameterized leg — roster/rest/peers/CI/render
— gains a designed-red param naming C03/C05 while the existing four lanes keep
their state; the seqs 5 move and the fp8_v4 dtype move live in the profile and
transcription legs below, not in the block shape). "the two RESTING lanes" in
the header is this file's parent-C05 provenance, kept as written.

Run per-directory: python3 -m pytest charts/radiance/tests -v
"""

from __future__ import annotations

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


def _controller(name):
    """The block's radiance controller map — the sanctioned home of controller-
    level keys (replicas rides here; app-template consumes the same key from no
    other place in the tree)."""
    return (
        _block(name).get("app-template", {}).get("controllers", {})
        .get("radiance", {}) or {}
    )


def _replicas_paths(node, path=""):
    """Every path where the block tree authors a `replicas` key. The resting
    law is that exactly ONE exists — the sanctioned lever: an inert second key
    (top-level or container-side) is the gotcha-11 decoy that satisfies a naive
    reader while the controller keeps scaling whatever it actually reads."""
    hits = []
    if isinstance(node, dict):
        for k, v in node.items():
            here = f"{path}.{k}" if path else str(k)
            if k == "replicas":
                hits.append(here)
            hits += _replicas_paths(v, here)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            hits += _replicas_paths(v, f"{path}[{i}]")
    return hits


# _args() RETIRED by owner ruling D43 (2026-11-22, replaced — never silently
# deleted): it read the lane block's serve args array, the carrier D43 rules
# out of existence (the argv moved into the chart-owned compose wrapper; the
# block's channel is env). The block-side reader below is its env twin; the
# RUNTIME proof of the vector lives in the harness (radiance_testlib) and the
# C03 composition legs.
def _block_env(name):
    """The lane block's authored env as {name: value} — the D43 block-side
    channel for profile values. The rendered-env twin (what the pod actually
    gets) is proven in the C03 suite; this reader is for authoring-shape
    needles that must bind before the render exists."""
    env = _container(name).get("env")
    assert isinstance(env, list) and env, (
        f"C05/D43: the {name} block carries no env list — env is the lane's whole serving-"
        "specifics channel since D43 (args are ruled out of the render); designed-red naming C05"
    )
    out = {}
    for e in env:
        assert e.get("name") not in out, (
            f"C05/D43: {name} authors env {e.get('name')!r} twice — one authority per value"
        )
        out[e["name"]] = e.get("value")
    return out


# _flag_map() retired 2026-11-22 (test-repair pass, replaced — never silently
# deleted): its consumers went with the D43 retirement of _args(); the live
# vector comparisons use R.flag_pairs in the harness, and a second args parser
# with no caller is exactly the drift the harness's single parser prevents.


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
        "(chart-dir override is what lets one chart serve five releases)"
    )


@pytest.mark.parametrize("name", LANE_NAMES)
def test_c05_lane_rests_at_zero_replicas(name):
    """C05 AC1/AC5: nothing routes here by default, so nothing may run by default.
    Three arms, one per truth: the SANCTIONED lever `controllers.radiance.replicas`
    is authored 0 (the fn/q27 precedent — the only place app-template consumes
    replicas from); NO other `replicas` key exists anywhere in the block (a second
    key is a decoy lever that buys this leg's green without moving the Deployment,
    the gotcha-11 class dev round 3 refused to feed); and the RENDERED
    spec.replicas is 0, what the cluster actually reconciles.

    Repaired 2026-11-22: the original read inspected the container and the block
    top level — two places app-template consumes NO replicas from, satisfiable
    only by an inert key."""
    block = _block(name)
    spec = R.lane(name)
    lever = "app-template.controllers.radiance.replicas"
    paths = _replicas_paths(block)
    assert paths == [lever], (
        f"C05: {name} authors replicas at {paths}, want EXACTLY [{lever!r}] — the controller "
        "scales from that one path; any other replicas key is inert decoration whose reader "
        "boots a resting lane while the real lever still says 0"
    )
    authored = _controller(name).get("replicas")
    assert authored == 0, (
        f"C05: {name} ships {lever} {authored!r}, want 0 — a resting lane that boots steals "
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


# --- AC1 transcription proofs: the profile comes from a named source -------------
#
# D43 (2026-11-22) split each era proof leg in two, keeping both halves of its
# duty: the TRANSCRIPTION proof is a pure git-constant law (provable today,
# render-independent — what the lane's RULED profile is), the CARRIAGE proof is
# the sandbox/env equality (designed-red until dev round 3 lands the wrapper
# and the lane envs — what the lane actually serves).

def test_c05_flash_tp1_profile_is_the_cf143_tp1_array_with_exactly_three_values_swapped():
    """C05 AC1 (OQ-F) transcription half, re-pinned BY RULING (2026-11-23
    bug-radiance-27b-context-window D5/D9 + this ticket's D-16/R2): the flash-
    TP1 ruled profile IS the cf-143 TP1-era chart array at the pinned commit,
    with EXACTLY THREE values swapped — its own served id, the context (262144,
    per D5/D9), and --max-num-seqs (5, per R2/D-16). The fidelity claim is
    bounded by ruling x3 — the source commit is immutable (it ships seqs 8),
    so this leg is never again described as verbatim or as a two-value swap.
    Anything else means the profile was re-derived by hand, and the TP1 recipe
    (pool 43000, --kv-resident 32768, expert_tiered, speculative 3) is exactly
    what a hand-copy gets wrong. The equality below is the 'NO FOURTH value
    may differ' arm — a drift of host-pool or batched-tokens away from the
    pinned array reddens it; the planted teeth prove the arm bites."""
    commit, path = R.FLASH_TP1_TRANSCRIPTION
    assert shutil.which("git"), "C05: git binary absent — the transcription source cannot resolve"
    shown = subprocess.run(["git", "show", f"{commit}:{path}"], capture_output=True, text=True,
                            timeout=120, cwd=str(R.REPO_ROOT))
    assert shown.returncode == 0, (
        f"C05: the transcription source {commit}:{path} does not resolve — the proof has no "
        "authority, so the leg fails rather than passing vacuously"
    )
    source = (yaml.safe_load(shown.stdout).get("app-template") or {}).get("serveArgs")
    assert isinstance(source, list) and source, f"C05: no serveArgs at {commit}:{path}"
    want = {str(source[i]): str(source[i + 1]) for i in range(0, len(source) - 1, 2)}
    assert want.get("--served-model-name") == R.SERVED_ID, (
        f"C05: the {commit} array does not serve the fn-era id — the transcription pin "
        "names the wrong revision or the array moved"
    )
    # the three sanctioned swaps: the lane's own id, the context ruling, the seqs ruling.
    want["--served-model-name"] = R.lane(R.FLASH_TP1_APP_NAME)["served_id"]
    want["--max-model-len"] = "262144"
    want["--max-num-seqs"] = "5"
    got = {f: str(v) for f, v in R.lane_profile(R.FLASH_TP1_APP_NAME).items()}
    assert got == want, (
        "C05: the flash-TP1 ruled profile is NOT the TP1 array with exactly the id, the "
        "context, and the seqs swapped (D5/D9 + D-16) — a fourth unplanned diff "
        "(host-pool, batched-tokens, ...) or a re-derived value: "
        f"{sorted(f for f in set(got) | set(want) if got.get(f) != want.get(f))}"
    )
    # Teeth: a FOURTH unplanned swap must be refused by the same equality — a
    # delta check that cannot refuse a re-derived flag is an inventory print,
    # not a proof. Plant one (host-pool away from the pinned 43000) and show
    # the comparison bites.
    planted = dict(want)
    planted["--host-pool-mib"] = "1"
    assert planted != got, (
        "C05 teeth: a planted fourth diff (host-pool 1 vs the pinned 43000) passed the "
        "three-swap equality — the transcription leg cannot refuse a re-derived profile"
    )


def test_c05_q27_tp2_profile_is_the_q27_array_plus_the_tp_pair():
    """C05 AC1 (OQ-G) transcription half: 27b-TP2's ruled profile is the
    EXISTING q27 profile plus the TP pair (`--tp` moved to 2, `--tp-wire
    wht6` added) with its own served id — derived from the sibling constant,
    so the proof is arithmetic on the map, never a copy.
    [2026-11-feat-radiance-fp8v4-lane D-16 — dated]: the seqs 5 reaches this
    lane by the same derivation (this leg reads R.Q27_PROFILE, which now
    carries 5), so the equality re-derives with no literal here — the whole
    point of the derived profile. q27_fp8v4_profile() then diverges back to
    8, and the next leg pins that re-override against this lane's 5."""
    want = dict(R.Q27_PROFILE)
    want["--tp"] = "2"
    want["--tp-wire"] = "wht6"
    want["--served-model-name"] = R.lane(R.Q27_TP2_APP_NAME)["served_id"]
    got = {f: str(v) for f, v in R.lane_profile(R.Q27_TP2_APP_NAME).items()}
    assert got == want, (
        "C05: the 27b-TP2 ruled profile drifted from (q27 array + tp pair + own id): "
        f"differing flags {sorted(f for f in set(got) | set(want) if got.get(f) != want.get(f))}"
    )
    assert list(R.Q27_TP2_EXTRA_FLAGS) == ["--tp", "2", "--tp-wire", "wht6"], (
        "C05: the EXTRA_FLAGS constant no longer matches the ruling — the OQ-G add is fixed text"
    )


def test_c05_fp8v4_profile_is_the_q27_tp2_profile_plus_dtype_and_seqs_override():
    """The fifth release is derived the same OQ-G way (clone shape + explicit
    override, never a fresh literal): the 27b-TP2 profile with the ruled dtype
    fp8_v4, this lane's served id, and — the trap this leg exists to pin — its
    OWN --max-num-seqs re-override back to 8. The ruling is 8 (R1/D-20); the
    parent 27b-TP2 profile now carries 5 (D-16), so a derived lane that does
    NOT re-override would silently serve 5 and erase the ruling. Assert both
    the derived equality AND the explicit 8-vs-5 parent/child split."""
    parent = R.q27_tp2_profile()
    want = dict(parent)
    want["--kv-cache-dtype"] = "fp8_v4"
    want["--served-model-name"] = R.lane(R.Q27_FP8V4_APP_NAME)["served_id"]
    want["--max-num-seqs"] = "8"
    got = {f: str(v) for f, v in R.lane_profile(R.Q27_FP8V4_APP_NAME).items()}
    assert got == want, (
        "C01: the fp8_v4 ruled profile is NOT (27b-TP2 profile + dtype + own id + "
        f"seqs re-override): differing flags {sorted(f for f in set(got) | set(want) if got.get(f) != want.get(f))}"
    )
    # the derivation trap, pinned: child carries 8, parent carries 5, and they differ.
    assert int(got["--max-num-seqs"]) == 8, "the fp8_v4 lane's seqs is its ruled 8"
    assert int(parent["--max-num-seqs"]) == 5, "its 27b-TP2 parent carries the existing-lane 5"
    assert got["--max-num-seqs"] != parent["--max-num-seqs"], (
        "the seqs re-override is gone — the child silently inherited the parent's 5, "
        "erasing the D-20 ruling (the trap this leg exists for)"
    )
    assert got["--kv-cache-dtype"] == "fp8_v4", "the ruled dtype reaches the profile"
    assert R.Q27_FP8V4_SEQS == "8", "the seqs constant the re-override reads is the ruled 8"


@pytest.mark.parametrize("name", R.NEW_LANE_NAMES)
@helm_skip
def test_c05_lane_composes_its_transcribed_profile(name):
    """The CARRIAGE half of the transcription proofs (D43): the lane's rendered
    env must equal its ruled profile's contract projection, and executing the
    shipped serve wrapper on that env must compose the profile EXACTLY.
    Designed-red twice over today: the lane blocks have not landed (C05) and
    the wrapper has not landed (dev round 3)."""
    comp = R.lane_composition(name)
    want_env = R.expected_env(R.lane_profile(name))
    got_env = comp["env"]
    missing = {k: v for k, v in want_env.items() if got_env.get(k) != v}
    extra = {k: v for k, v in got_env.items() if k not in want_env}
    assert not missing and not extra, (
        f"C05/D43 [{name}]: rendered RADIANCE_* env diverges from the ruled profile\n"
        f"  missing/incorrect: {missing}\n  extra: {extra}"
    )
    facts = comp["facts"]
    assert facts["rc"] == 0 and facts["argv"], (
        f"C05/D43 [{name}]: compose failed or composed nothing (rc {facts['rc']}, "
        f"stderr {facts['stderr'][:180]!r})"
    )
    pairs = R.flag_pairs(facts["argv"])
    want = {f: str(v) for f, v in R.lane_profile(name).items()}
    assert pairs == want, (
        f"C05 AC1/D43 [{name}]: composed vector diverges from the transcribed profile\n"
        f"  missing/incorrect: { {f: v for f, v in want.items() if pairs.get(f) != v} }\n"
        f"  extra: { {f: v for f, v in pairs.items() if f not in want} }"
    )


@pytest.mark.parametrize("name", LANE_NAMES)
def test_c05_lane_serves_its_own_id_exactly_once(name):
    """Honest-id law (D43-anchored 2026-11-22): each lane ADVERTISES exactly
    one id, its own — the id's block-side channel is now the authored
    RADIANCE_SERVED_ID env (args are ruled out of the render), and no two
    lanes collide: a duplicate served id makes the peer models list ambiguous
    and the solver's model routing non-deterministic. The composed-vector half
    of this law (the id appearing exactly once in the engine's argv) runs in
    the C03 profile-equality legs."""
    spec = R.lane(name)
    env = _block_env(name)
    assert env.get(R.ENV_SERVED_ID) == spec["served_id"], (
        f"C05/D43: {name} authors {R.ENV_SERVED_ID}={env.get(R.ENV_SERVED_ID)!r}, "
        f"want exactly {spec['served_id']!r}"
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
    assert _block_env(name).get(R.ENV_MODEL_PATH) == path, (
        f"C05/D43: {name} authors {R.ENV_MODEL_PATH}={_block_env(name).get(R.ENV_MODEL_PATH)!r}, "
        f"want [{path!r}] — the pack path reaches the engine through env now"
    )
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
