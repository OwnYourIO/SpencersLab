"""2026-11-feat-radiance-multi-instance C03 — charts/radiance becomes mechanism.

C03 relocates; it decides nothing about lane DATA (serve args, GPU claim pair,
memory, pack ledgers are transcribed, tp counts held, replicas held). Its proof
changed shape with the owner ruling D35: the CHART owns the generic init-script
FORM (a configMap carrier — app-template 5.0.1 renders command/args via plain
toYaml, no tpl, so a chart-side script cannot ride values) and the lane blocks
supply PACK/LFS_SHA/URL/MARKER as DATA. The live pod spec therefore MOVES, and
AC1 became an INTENTIONAL-DELTA proof: compared against the pre-move fixtures
(evidence/pre-move-render-*.yaml at the pinned base revision, re-derived by
capture_c03_fixtures.py), the render may differ on EXACTLY the four ruled paths
and on NOTHING ELSE. "The script is in the chart" is not the gate — the bounded
diff is, and the budget leg carries planted-drift teeth of its own.

Red state at handoff (designed, C03 round 2 turns them green): the two
delta-budget legs (the ruled carrier has not landed — today's per-block script
literals are the INTERIM shape D35 rules out), the chart-ships-the-form leg,
and the two block-drops-the-command legs. The teeth legs and the lane-local
pack-identity legs are green NOW (they gate the comparison engine and the
cross-lane drift law, not the not-yet-landed shape).

Run per-directory: python3 -m pytest charts/radiance/tests -v
"""

from __future__ import annotations

import copy
import json
import re
from pathlib import Path

import pytest
import yaml

import radiance_testlib as R

_ok, _reason = R.helm_ready()
helm_skip = pytest.mark.skipif(not _ok, reason=_reason)

EVIDENCE = Path(__file__).resolve().parent / "evidence"

# The two lanes that exist today and whose renders the budget governs.
MOVING_LANES = {"radiance": "gpu-ai-radiance", R.Q27_APP_NAME: R.Q27_RELEASE}

# D35's four-path budget, in this suite's path grammar (the ruling spells the
# annotation metadata.annotations."checksum/configMaps"; app-template renders
# it on the POD TEMPLATE — lib/pod/metadata/_annotations.tpl, witnessed in
# classes/_deployment.tpl — and keys with separators join bracketed). The
# list law (_diff_paths) keeps every budget path nameable: length-changed and
# scalar lists report their own path; same-length dict lists descend, so an
# init-IMAGE swap beside the ruled volumeMounts/command stays visible drift.
DELTA_BUDGET = frozenset({
    '$.spec.template.metadata.annotations["checksum/configMaps"]',
    "$.spec.volumes",
    "$.spec.template.spec.initContainers[0].volumeMounts",
    "$.spec.template.spec.initContainers[0].command",
})


def _fixture(key: str) -> dict:
    path = EVIDENCE / f"pre-move-render-{key}.yaml"
    assert path.is_file(), (
        f"C03: {path.name} missing — the pre-move fixture is the baseline side of the "
        "intentional-delta proof; re-derive it with charts/radiance/tests/capture_c03_fixtures.py"
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


def _join(path: str, key: str) -> str:
    return f"{path}.{key}" if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", str(key)) \
        else f'{path}["{key}"]'


def _leaf_paths(node, path: str) -> set:
    """Every leaf path under a one-sided subtree (dicts recurse; lists and
    scalars are opaque — a key present on ONE side contributes exactly its
    leaf paths, so an added annotation is charged per annotation, not per
    parent map)."""
    if isinstance(node, dict) and node:
        out = set()
        for k, v in node.items():
            out |= _leaf_paths(v, _join(path, k))
        return out
    return {path}


def _diff_paths(a, b, path: str = "$") -> set:
    """Sorted-ready set of normalized paths where the two documents differ.
    List law: a length change or any scalar-valued pair is OPAQUE, reported at
    its own path (k8s replaces lists wholesale — which is exactly why D35's
    budget names whole paths like the init command); a same-length pair of
    dict elements descends by index, so a swap INSIDE a ruled carrier entry —
    the init IMAGE beside its mounted volumes — stays visible as drift."""
    if isinstance(a, dict) and isinstance(b, dict):
        out = set()
        for k in sorted(set(a) | set(b)):
            p = _join(path, k)
            if k not in a:
                out |= _leaf_paths(b[k], p)
            elif k not in b:
                out |= _leaf_paths(a[k], p)
            else:
                out |= _diff_paths(a[k], b[k], p)
        return out
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return {path}
        if a and all(isinstance(x, dict) for x in a) and all(isinstance(y, dict) for y in b):
            out = set()
            for i, (x, y) in enumerate(zip(a, b)):
                out |= _diff_paths(x, y, f"{path}[{i}]")
            return out
        return {path} if a != b else set()
    return {path} if a != b else set()


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


# --- AC1 (D35): the intentional-delta proof --------------------------------------


@pytest.mark.parametrize("key,release", sorted(MOVING_LANES.items()))
@helm_skip
def test_c03_render_moves_only_on_the_four_ruled_paths(key, release):
    """C03 AC1 as RULED BY D35 (replaces whole-render byte-equality — replaced,
    never deleted: the diff budget IS the new gate). The block-fed render may
    differ from the pre-move fixture on EXACTLY the four ruled paths — the
    pod-template checksum/configMaps annotation, spec.volumes, the init's
    volumeMounts, its command — and on NOTHING ELSE: serve args, the claim
    pair, memory, cpu, replicas, probes, Recreate/grace, securityContext and
    the image@digest all stay byte-equal inside this comparison (a relocation
    that changes one serving flag fails here rather than at boot). BOTH sides
    of the budget bind: nothing unauthorized may move, AND each ruled path
    must actually move — the D35 carrier present IS the delta, so a tree still
    running the interim per-block script is red until round 2 lands the
    configMap carrier.
    THE FN LANE ROLLS because of this (D35(2), recorded so nobody "fixes" the
    delta back to equality to quiet a sync): restartPolicy Recreate plus the
    changed template means the owner's sync of gpu-ai-radiance restarts the
    lane that D16 made the default route for every tier — grace 180 s plus a
    model-load-class 502 window — so C03's rework lands as its OWN watched
    sync set, never bundled with the rename or the fleet wave, with the cf-143
    D28(6) first-boot print as the receipt."""
    fix = _fixture(key)
    want = fix["deployment"]
    got = json.loads(_fold(json.dumps(_rendered_deployment(key), sort_keys=True)))
    delta = _diff_paths(want, got)
    unauthorized = sorted(delta - DELTA_BUDGET)
    assert not unauthorized, (
        f"C03 AC1/D35: the {release} render moved off the ruled paths: {unauthorized}. "
        f"(fixture at {fix['captured_from_commit'][:9]}; only the four budget paths may differ — "
        f"first move: want {(_first_diff(want, got))[0]!r} / got {(_first_diff(want, got))[1]!r})"
    )
    missing = sorted(DELTA_BUDGET - delta)
    assert not missing, (
        f"C03 AC1/D35: {release} render does NOT carry the ruled delta on {missing} — "
        "the chart-owned configMap carrier has not landed (designed-red naming C03 round 2: "
        "the interim per-block script keeps the render equal, which D35 ruled away; "
        "re-derive the fixture ONLY from the pinned base revision via capture_c03_fixtures.py)"
    )


@pytest.mark.parametrize("key,release", sorted(MOVING_LANES.items()))
@helm_skip
def test_c03_delta_budget_catches_planted_drift(key, release):
    """Teeth of the budget leg (D35's own requirement — the vacuity class this
    ticket has already caught three times): plant TWO unauthorized moves in a
    synthetic copy of the release render — a serve-arg flip and both halves of
    the claim pair flipped — and the same comparison must flag exactly those
    paths as unauthorized. Green now and after round 2: this leg proves the
    gate is live, it is not itself the gate."""
    want = _fixture(key)["deployment"]
    # deepcopy: the render helpers are lru_cached and return SHARED objects —
    # planting on the cached dict would leak the plant into every later leg
    # (the contamination this suite's mutation guards exist to prevent).
    planted = copy.deepcopy(_rendered_deployment(key))
    spec = planted["spec"]["template"]["spec"]
    ci = next(i for i, c in enumerate(spec["containers"]) if c.get("name") == R.SERVE_NAME)
    serve = spec["containers"][ci]
    args = [str(a) for a in serve.get("args") or []]
    assert "--max-model-len" in args, f"{release}: no --max-model-len to plant on — the args carrier moved"
    args[args.index("--max-model-len") + 1] = "199999"
    serve["args"] = args
    for m in ("requests", "limits"):
        claims = serve.setdefault("resources", {}).setdefault(m, {})
        assert R.GPU_CLAIM in claims, f"{release}: no live claim in {m} to plant on"
        claims[R.GPU_CLAIM] = "7"
    got = json.loads(_fold(json.dumps(planted, sort_keys=True)))
    flagged = _diff_paths(want, got) - DELTA_BUDGET
    expected = {
        f"$.spec.template.spec.containers[{ci}].args",
        f'$.spec.template.spec.containers[{ci}].resources.requests["<POOL>"]',
        f'$.spec.template.spec.containers[{ci}].resources.limits["<POOL>"]',
    }
    assert expected <= flagged, (
        f"C03/D35 teeth: planted serve-arg + claim drift NOT flagged on {release} — "
        f"flagged {sorted(flagged)}, want {sorted(expected)} inside; the budget leg would be "
        "passing vacuously on real drift (half-tripwire class)"
    )


# --- AC1/AC2 mechanism: the chart owns the script FORM ----------------------------


def test_c03_chart_ships_the_script_form():
    """C03 (D35(3)): the generic fetch-script FORM is chart-owned bytes — it
    lives in the chart's values stanza or templates (the configMap carrier),
    carrying the C11/D27 portable-equality shape and NO lane literals (the
    literals bar is the sibling leg). Designed-red naming C03 round 2: today
    the script FORM sits in the two lane blocks' command literals — the interim
    shape D35 rules out — and no chart file carries the gate."""
    text = R.chart_carrier_text()
    for toks, what in (
        (R.EQ_GATE_TOKENS, "the portable compute line (actual=$(sha256sum … | cut -f1))"),
        (R.MISMATCH_ECHO_TOKENS, "the MISMATCH echo naming expected= and actual="),
    ):
        missing = [t for t in toks if t not in text]
        assert not missing, (
            f"C03/D35: the chart-owned files never carry {what} — missing {missing}. The shell must ship "
            "the ONE generic script FORM (designed-red naming C03 round 2: today the FORM lives in the "
            "lane blocks' command literals, which D35 rules out)"
        )
    assert 'touch "$MARKER"' in text, (
        "C03/D35: the chart-owned script FORM lacks the success-marker touch — the marker law "
        "(vllm/fn idiom, C06 receipts) rides the FORM, not the scalars"
    )


def test_c03_chart_ships_no_lane_data():
    """C03 AC2 (OQ-D + D35): the chart keeps image/pin/probes/security/PVC/service
    MECHANISM and the generic script FORM, and carries no lane DATA anywhere in
    chart-owned bytes — no serve array, no GPU claim, no per-pack sha/URL/byte
    literals (template files included now that a template may carry the FORM),
    no modelPath default. A second release of the same chart would otherwise
    inherit the fn lane's numbers, which is the exact failure the four-lane
    roster cannot work around."""
    text = R.chart_carrier_text()
    data = R.chart_values()
    at = data.get("app-template") or {}
    assert "serveArgs" not in at and "--model" not in text, (
        "C03 AC2: chart-owned bytes still carry a lane serve array — the lane args belong in the "
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
        (R.PACK_URL, "the fn pack URL"),
        (R.Q27_PACK_URL, "the q27 pack URL"),
        (R.MODEL_PATH, "the fn pack path"),
        (R.Q27_MODEL_PATH, "the q27 pack path"),
    ):
        assert literal not in text, (
            f"C03 AC2/D35: chart-owned bytes hard-code {what} ({literal}) — a per-pack literal in a generic "
            "shell (values OR the script-FORM template) is a law the second release cannot obey; the FORM "
            "takes it as a per-release scalar"
        )


def test_c03_source_dir_trap_stays_dead():
    """C03 (gotcha 11): the inert `radianceFetch.sourceDir` lever — a key a reader retargets and the
    script never reads — must not exist in the shell, its templates, or a lane block. BAR, not a red: the
    key is ALREADY absent at this ticket's base (the plan's gotcha names a site the cf-144 wave removed),
    and the leg exists so C03's parameterization cannot reintroduce it alongside the real scalars."""
    for path in (R.CHART_DIR / "values.yaml", R.SERVICE_VALUES, *sorted((R.CHART_DIR / "templates").glob("*"))):
        assert not re.search(r"(?m)^\s*sourceDir\s*:", path.read_text()), (
            f"C03: {path} declares sourceDir — an inert lever is worse after C03 than before it, because "
            "the lane blocks now carry the REAL pack scalars and a reader cannot tell which one the init "
            "script obeys"
        )


# --- the block side: scalars as DATA, never a script fork -------------------------


def _assert_block_shape(key: str, lane_literals: tuple, sib_literals: tuple):
    """Shared shape of the two scalar-block legs: no whole-command replacement,
    this lane's scalars authored as data inside the block, and the sibling's
    pack identity nowhere in the block. Each lane runs against ITS OWN
    constants — the sets are never cross-validated (D35's drift law)."""
    block = R.lane_block(key) if key != "radiance" else R.service_block()
    assert isinstance(block, dict), f"C03: no {key}: block to inspect — designed-red naming C03"
    controllers = (block.get("app-template") or {}).get("controllers") or {}
    fetch = ((controllers.get("radiance") or {}).get("initContainers") or {}).get(R.INIT_NAME) or {}
    assert "command" not in fetch, (
        f"C03: the {key} block still replaces the whole fetch script (initContainers.{R.INIT_NAME}.command) "
        "— designed-red naming C03 round 2: D35 rules the CHART owns the script FORM (configMap carrier); "
        "the lane passes its pack scalars as data only"
    )
    blob = str(block)
    sha, pack_path, url = lane_literals
    assert sha in blob, f"C03: the {key} block no longer authors its LFS sha ({sha[:12]}…) — the scalars replace the script, not the facts"
    assert pack_path in blob, f"C03: the {key} block no longer authors its pack path ({pack_path})"
    assert url in blob, f"C03: the {key} block no longer authors its pack URL ({url})"
    assert re.search(r"\.staged-(\$LFS_SHA|" + re.escape(sha) + ")", blob), (
        f"C03: the {key} block authors no .staged-<lfs-sha> marker (interpolated or expanded) — "
        "the vllm/fn marker law carries onto the scalar shape"
    )
    for lit in sib_literals:
        assert lit not in blob, (
            f"C03 drift guard: the {key} block carries the SIBLING lane's pack identity ({lit}) — "
            "scalar sets are per-lane facts; a copy-paste here is how a lane re-points at the other's pack"
        )


@pytest.mark.skipif(not _ok, reason="render env")
def test_c03_q27_drops_the_whole_script_for_scalars():
    """C03 (task 3, made SATISFIABLE by D35): the q27 block stops replacing the
    init container's whole `command` and carries its four pack scalars as DATA,
    so the chart's generic FORM composes the script. The maintenance law this
    leg always named — a per-lane fork of the fetch script is the one thing the
    D27 BusyBox-grammar legs cannot protect (gotcha 11) — is now enforced by
    shape: the FORM ships once, chart-side (see the two chart-FORM legs). The
    composed-script arms live in the q27 lane suite (grammar + substituted
    scalars read the rendered configMap)."""
    _assert_block_shape(R.Q27_APP_NAME, R.lane_pack_literals(R.Q27_APP_NAME),
                        R.lane_pack_literals("radiance"), "/models/radiance")


@pytest.mark.skipif(not _ok, reason="render env")
def test_c03_fn_block_drops_the_whole_script_for_scalars():
    """C03/D35 twin leg: the fn block follows the same law — D35's carrier rules
    BOTH live lanes, and asserting only q27 would let the fn lane keep the
    interim script fork (the class the whole chunk closes)."""
    _assert_block_shape("radiance", R.lane_pack_literals("radiance"),
                        R.lane_pack_literals(R.Q27_APP_NAME), "/models/radiance")


@pytest.mark.parametrize("key", sorted(MOVING_LANES))
@helm_skip
def test_c03_pack_identity_is_lane_local(key):
    """C03/D35 cross-lane drift guard, asserted INDEPENDENTLY per live lane:
    the release render carries THIS lane's pack identity (sha, pack path, URL)
    and NONE of the sibling's — wherever dev places the scalars (substituted
    into the configMap FORM, or the interim block script). A chart-side script
    edit that re-points one lane at the other's pack reddens this leg, because
    the render, not the authoring file, is what the pod runs."""
    own = R.lane_pack_literals(key)
    sib = R.lane_pack_literals(R.Q27_APP_NAME if key != R.Q27_APP_NAME else "radiance")
    _docs, raw = (R.render_q27() if key == R.Q27_APP_NAME
                  else R.render(release=MOVING_LANES[key], service=True))
    for lit, what in zip(own, ("lfs sha", "pack path", "pack URL")):
        assert lit in raw, (
            f"C03 drift guard [{key}]: the {key} render no longer carries its own {what} ({lit}) — "
            "the composed init would verify nothing (or the wrong pack)"
        )
    for lit in sib:
        assert lit not in raw, (
            f"C03 drift guard [{key}]: the {key} render carries the SIBLING lane's pack identity ({lit}) — "
            "one lane is pointing at the other's pack (exactly the re-pointing D35's independent "
            "scalar sets guard)"
        )


# --- AC2: the chart is mechanism only ------------------------------------------


@helm_skip
def test_c03_chart_bare_render_is_mechanism_only():
    """C03 AC2 (the render-side pair of the values-level bar) + the D35
    extension: `helm template` on the bare chart must still be valid and must
    schedule nothing and serve nothing — zero GPU claim lines, zero lane serve
    args, no OVERRIDE sentinel — AND the init configMap (mechanism form, if the
    bare render carries one) must hold ZERO lane pack identity: the FORM is
    generic data with per-release scalars, never a baked lane pack."""
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
    for literal, what in ((R.PACK_LFS_SHA, "fn LFS sha"), (R.Q27_PACK_LFS_SHA, "q27 LFS sha"),
                          (R.PACK_URL, "fn pack URL"), (R.Q27_PACK_URL, "q27 pack URL"),
                          (str(R.PACK_BYTES), "fn pack bytes"), (str(R.Q27_PACK_BYTES), "q27 pack bytes")):
        assert literal not in raw, f"C03 AC2: the bare render embeds {literal} ({what}) — a per-lane fact"
    for cm in R.configmap_docs(docs):
        blob = json.dumps(cm.get("data") or {})
        for lit in (*R.lane_pack_literals("radiance"), *R.lane_pack_literals(R.Q27_APP_NAME)):
            assert lit not in blob, (
                f"C03 AC2/D35: the BARE-render configMap {cm['metadata']['name']} embeds a lane pack "
                f"literal ({lit}) — chart-bare means mechanism form only, no per-release data"
            )
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
