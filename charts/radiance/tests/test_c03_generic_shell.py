"""2026-11-feat-radiance-multi-instance C03 — charts/radiance becomes mechanism.

C03 relocates; it decides nothing about lane DATA (serve profiles, GPU claim
pair, memory, pack ledgers are transcribed, tp counts held, replicas held).
Its proof changed shape twice by owner ruling:

D35 (round 2) ruled the FETCH side: the chart owns the generic init-script
FORM (a configMap carrier — app-template renders command/args via plain toYaml,
no tpl) and the lane blocks supply PACK/LFS_SHA/URL/MARKER as DATA.

D43 (round 3, 2026-11-22) extends the same carrier class to the SERVE side:
the chart owns the serve-argv COMPOSE wrapper (a second ConfigMap script,
proposed key serve.sh) and the lanes supply specifics as container ENV — env
rides tpl, args never did. AC1 therefore retired the four-path render-diff
BUDGET for a RUNTIME proof: execute the shipped wrapper bytes against each
lane's RENDERED env in a sandbox POSIX shell (busybox ash / dash — the image
rootfs has neither bash nor dash, only busybox ash, receipt at the pinned
digest) and require the vector the engine would receive to EQUAL the lane's
ruled profile. The wrapper startup echo of the composed argv is the D43(2)
boot receipt and is asserted once here.

RETIRED BY D43 (dated 2026-11-22, replaced — never silently deleted): the
four-path DELTA_BUDGET engine of rounds 1-2 (the whole-render path-diff of
test_c03_render_moves_only_on_the_four_ruled_paths, its planted-drift teeth,
and the _diff_paths/_leaf_paths/_first_diff machinery), plus the two-path
modelPath==args fence. The budget compared rendered args that no longer
exist; its invariance duty now runs as the per-property proof below (the
immutable pre-move fixtures stay the baseline), and its argv duty runs as the
composed-vector legs. The budget's teeth philosophy carries: the cheap-fake
ban, the both-direction teeth, and the loud guards below.

Run per-directory: python3 -m pytest charts/radiance/tests -v
"""

from __future__ import annotations

import collections
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

# The two lanes that exist today (the budget governed them; the invariance
# legs below inherit that duty) and the four the D43 composition proof spans.
MOVING_LANES = {"radiance": "gpu-ai-radiance", R.Q27_APP_NAME: R.Q27_RELEASE}


def _fixture(key: str) -> dict:
    path = EVIDENCE / f"pre-move-render-{key}.yaml"
    assert path.is_file(), (
        f"C03: {path.name} missing — the pre-move fixture is the baseline side of the "
        "invariance proof; re-derive it with charts/radiance/tests/capture_c03_fixtures.py"
    )
    return yaml.safe_load(path.read_text())


def _fold(text: str) -> str:
    """Fold the pool name to the fixture token (see the fixture header): the rename
    is the one difference C03 may inherit, and a retired-pool spelling folds to
    `<POOL>-1`, which matches nothing."""
    return text.replace(R.GPU_CLAIM, "<POOL>")


def _rendered_deployment(key: str) -> dict:
    """The release's render at the shape production feeds it, routed through the
    sanctioned per-lane renderer: fn/q27 via the service overlay, the resting
    lanes via their block renders — the same resolver COMPOSITION_LANES uses.
    The hand-mapped MOVING_LANES body reddened KeyError on the resting lanes as
    soon as the tp/claim leg went four-wide (2026-11-22 repair: the law spans
    four releases, a two-entry map cannot be its reader)."""
    deps = [d for d in R.lane_docs(key) if d.get("kind") == "Deployment"]
    assert len(deps) == 1, f"{key}: expected one Deployment, got {len(deps)}"
    return deps[0]


# _serve_ctr() retired 2026-11-22 (test-repair pass, replaced — never silently
# deleted): no leg called it after the D43 re-pin — the composition legs read
# the container through R.lane_composition/R.serve_container and the tp/claim
# leg through _rendered_deployment. A second container reader with no caller is
# the day someone uses it instead of the sanctioned one.


# --- AC1 (D43): the composed argv IS the ruled profile, per lane ------------------
#
# The proof runs the SHIPPED carrier bytes — a static read of the script or a
# profile constant copied twice proves nothing (that is the cheap fake the ban
# leg below forbids). Each leg takes the render's ConfigMap wrapper, the lane's
# rendered env, and the sandbox shell; the vector the engine stub receives is
# the only witness accepted.


@pytest.mark.parametrize("name", sorted(R.COMPOSITION_LANES))
@helm_skip
def test_c03_composed_argv_equals_the_ruled_profile(name):
    """C03 AC1 as ruled by D43: executing the shipped serve wrapper against the
    lane's rendered env yields EXACTLY the ruled profile — every flag once,
    every value pinned, no extra (an extra flag is as red as a missing one, the
    era's set-equality law carried onto the runtime shape). Designed-red until
    dev round 3 lands the wrapper and the lane envs; the two resting lanes are
    red twice over (their blocks have not landed — the message names C05)."""
    comp = R.lane_composition(name)
    facts = comp["facts"]
    assert facts["rc"] == 0, (
        f"C03/D43 [{name}]: the compose wrapper exited {facts['rc']} against this lane's rendered "
        f"env (stderr {facts['stderr'][:200]!r}) — it must boot the engine, not die on the recipe"
    )
    argv = facts["argv"]
    assert argv, (
        f"C03/D43 [{name}]: the engine stub never ran — the wrapper neither execs radiance by bare "
        "name nor passes a vector (probe rc {} token {!r})".format(
            facts["probe_rc"], facts["probe_token"])
    )
    pairs = R.flag_pairs(argv)
    want = {f: str(v) for f, v in R.lane_profile(name).items()}
    missing = {f: v for f, v in want.items() if pairs.get(f) != v}
    extra = {f: v for f, v in pairs.items() if f not in want}
    assert not missing and not extra, (
        f"C03 AC1/D43 [{name}]: the COMPOSED vector diverges from the ruled profile\n"
        f"  missing/incorrect: {missing}\n  extra: {extra}"
    )
    dupe = {f for f, c in collections.Counter(a for a in argv if a.startswith("--")).items() if c > 1}
    assert not dupe, f"C03 AC1/D43 [{name}]: composed vector repeats flags {dupe}"


@pytest.mark.parametrize("name", sorted(R.COMPOSITION_LANES))
@helm_skip
def test_c03_composition_reads_env_not_the_carrier(name):
    """D43 teeth direction ONE (env → vector): mutate one required env value on
    a copy of the lane's env — RADIANCE_TP to an out-of-contract 9 and the
    model path to a probe path — and EXACTLY the mapped flags may move in the
    composed vector; every other pair stays byte-equal. A carrier that restates
    values instead of composing them cannot pass this leg no matter what its
    text looks like: the mutation is in the env, not the bytes."""
    comp = R.lane_composition(name)
    base = comp["facts"]
    assert base["argv"], f"C03/D43 [{name}]: no baseline vector to mutate against (see the AC1 leg)"
    pairs_base = R.flag_pairs(base["argv"])
    for env_name, probe_value, flag in (
        (R.ENV_TP, "9", "--tp"),
        (R.ENV_MODEL_PATH, "/probe/other-model.rad", "--model"),
    ):
        assert env_name in comp["env"], f"C03/D43 [{name}]: rendered env lacks {env_name} to mutate"
        moved = dict(comp["env"])
        moved[env_name] = probe_value
        after = R.compose_serve_argv(comp["script"][2], moved)
        assert after["argv"] is not None, (
            f"C03/D43 [{name}]: mutating {env_name} killed the wrapper (rc {after['rc']}, "
            f"stderr {after['stderr'][:160]!r}) — it must serve the env it is given"
        )
        pairs_after = R.flag_pairs(after["argv"])
        assert pairs_after.get(flag) == probe_value, (
            f"C03/D43 [{name}]: env {env_name}={probe_value!r} did not reach {flag} "
            f"(composed {pairs_after.get(flag)!r}) — env is the ruled channel for it"
        )
        drift = {f for f in set(pairs_base) | set(pairs_after)
                 if f != flag and pairs_base.get(f) != pairs_after.get(f)}
        assert not drift, (
            f"C03/D43 [{name}]: {env_name}={probe_value!r} also moved {sorted(drift)} — one env, "
            "one flag; a flag reacting to the wrong env is the crossed-wires class"
        )


@pytest.mark.parametrize("flag", sorted(R.FORM_FIXED_FLAGS))
@helm_skip
def test_c03_form_flags_reach_every_lane_from_the_carrier(flag):
    """D43 teeth direction TWO (FORM → vector): rename the flag token INSIDE
    the carrier bytes (token-level, so the probe is blind to dev's composing
    style) and EVERY lane's composed vector must lose that flag. The rename
    must find the token (a FORM flag with no carrier byte is not carrier-
    sourced) — proving the fixed flags are the chart's, while the DATA flags
    above are the lanes'. Runs across all four lanes per flag: the FORM is one
    script and a per-lane drift here is the fork class."""
    docs = R.lane_docs("radiance")
    hit = R.serve_script_from_render(docs)
    assert hit is not None, (
        "C03/D43: no chart-owned serve wrapper in the render — the FORM teeth have nothing "
        "to bite; designed-red naming dev round 3"
    )
    renamed = hit[2].replace(flag, flag + "-x")
    assert renamed != hit[2], (
        f"C03/D43: the carrier bytes never name the FORM flag {flag!r} — every lane's profile "
        "requires it, so it must compose from the chart-owned FORM"
    )
    for name in sorted(R.COMPOSITION_LANES):
        comp = R.lane_composition(name)
        env = comp["env"]
        after = R.compose_serve_argv(renamed, env)
        assert after["argv"] is not None, (
            f"C03/D43 [{name}]: renaming {flag} broke the wrapper outright (rc {after['rc']}, "
            f"stderr {after['stderr'][:160]!r}) — the probe renames a token, not the script's spine"
        )
        pairs = R.flag_pairs(after["argv"])
        assert flag not in pairs, (
            f"C03/D43 [{name}]: {flag} still composed after the token rename — the value "
            "reaches argv from OUTSIDE the renamed carrier byte (a second argv source)"
        )
        assert f"{flag}-x" not in pairs or pairs.get(f"{flag}-x") == R.FORM_FIXED_FLAGS[flag], (
            f"C03/D43 [{name}]: the renamed flag carried a value other than the FORM's "
            f"{R.FORM_FIXED_FLAGS[flag]!r}: {pairs.get(f'{flag}-x')!r}"
        )


@pytest.mark.parametrize("name", sorted(R.COMPOSITION_LANES))
@helm_skip
def test_c03_startup_echo_is_the_composed_vector_once(name):
    """D43(2) boot receipt: the wrapper prints the composed argv once at
    startup (the operator's log line naming what the engine actually got) —
    exactly one line carrying the vector, naming both the --model and the
    --served-model-name pair, and the printed values are the lane's."""
    comp = R.lane_composition(name)
    facts = comp["facts"]
    assert facts["rc"] == 0 and facts["argv"], f"C03/D43 [{name}]: no successful boot to echo (see AC1 leg)"
    echo_lines = [ln for ln in facts["stdout"].splitlines()
                  if "--model" in ln and "--served-model-name" in ln]
    assert len(echo_lines) == 1, (
        f"C03/D43 [{name}]: startup echo lines naming the composed vector: {len(echo_lines)} — "
        "the D43(2) receipt is ONE startup line (zero leaves the pod blind at boot; two is "
        f"argv noise). stdout was: {facts['stdout'][:220]!r}"
    )
    assert str(R.lane_profile(name)["--model"]) in echo_lines[0], (
        f"C03/D43 [{name}]: the echo line does not name the lane's model path — the receipt "
        "must echo the vector, not a banner"
    )


@pytest.mark.parametrize("drop", sorted(R.ENV_REQUIRED))
@helm_skip
def test_c03_wrapper_fails_loud_on_missing_required_env(drop):
    """The loud-guard law (D43): a required env absent must kill the wrapper
    BEFORE exec with a message naming the variable — never serve a partial
    vector (a boot without --model is not a boot), never fall back to a baked
    default (that would re-smuggle lane data into the FORM). Run against the
    FULL env minus one key, and against the empty env."""
    docs = R.lane_docs("radiance")
    hit = R.serve_script_from_render(docs)
    assert hit is not None, "C03/D43: no serve wrapper to probe — designed-red naming dev round 3"
    full = R.expected_env(R.FULL_PROFILE)
    partial = {k: v for k, v in full.items() if k != drop}
    for env, what in ((partial, f"full env minus {drop}"), ({}, "empty env")):
        facts = R.compose_serve_argv(hit[2], env)
        assert facts["rc"] != 0, (
            f"C03/D43: wrapper exited 0 against the {what} — required env {drop} missing must "
            "fail loudly (a silent partial vector boots the engine on a stale default)"
        )
        assert facts["argv"] is None, (
            f"C03/D43: engine received argv even against the {what} — the guard must refuse "
            "BEFORE exec"
        )
    facts = R.compose_serve_argv(hit[2], partial)
    assert drop in facts["stderr"] + facts["stdout"], (
        f"C03/D43: the refusal against {drop} missing does not name the variable — an unnamed "
        "exit is undiagnosable from the pod log"
    )


@pytest.mark.parametrize("name", sorted(R.COMPOSITION_LANES))
@helm_skip
def test_c03_rendered_env_is_the_single_sizing_authority(name):
    """D43 single-source: the rendered RADIANCE_* env equals the lane profile's
    projection EXACTLY — no missing channel, no extra env (an extra is a second
    channel for some value, or an unmapped name the wrapper cannot obey), no
    name authored twice (charged in container_env), and the block-authored
    modelPath ledger equals the env value equals the composed --model (the
    re-anchored three-place fence that replaces the two-path budget fence)."""
    comp = R.lane_composition(name)
    want = R.expected_env(R.lane_profile(name))
    got = comp["env"]
    missing = {k: v for k, v in want.items() if got.get(k) != v}
    extra = {k: v for k, v in got.items() if k not in want}
    assert not missing and not extra, (
        f"C03/D43 [{name}]: rendered RADIANCE_* env diverges from the ruled contract\n"
        f"  missing/incorrect: {missing}\n  extra (second-channel or unmapped): {extra}"
    )
    unmapped = [k for k in got if k.startswith(R.ENV_PREFIX) and k not in R.ENV_TO_FLAG]
    assert not unmapped, (
        f"C03/D43 [{name}]: env names outside the ruled contract: {unmapped} — the FORM has no "
        "arm for them (a FORM-fixed flag attempted through env lands here too)"
    )
    facts = comp["facts"]
    if facts["argv"]:
        composed_model = R.flag_pairs(facts["argv"]).get("--model")
        assert composed_model == got.get(R.ENV_MODEL_PATH), (
            f"C03/D43 [{name}]: composed --model {composed_model!r} != env {R.ENV_MODEL_PATH} "
            f"{got.get(R.ENV_MODEL_PATH)!r} — the three-place fence (modelPath/env/--model) breaks here"
        )
    block = R.lane_block(name) if name != "radiance" else R.service_block()
    declared = ((block or {}).get("app-template") or {}).get("modelPath")
    assert declared in (None, got.get(R.ENV_MODEL_PATH)), (
        f"C03/D43 [{name}]: block modelPath {declared!r} != env value {got.get(R.ENV_MODEL_PATH)!r} "
        "— ledger and served pack are one fact written twice (the era's dual-edit law, env-anchored)"
    )


@pytest.mark.parametrize("name", sorted(R.COMPOSITION_LANES))
@helm_skip
def test_c03_tp_env_matches_the_gpu_claim(name):
    """D43 cross-channel law: the lane's RADIANCE_TP must equal its GPU claim
    count — the recipe's tp degree and the cards the pod pins are ONE fact
    about the same hardware; split edits (tp 2 beside claim 1) Pend forever or
    overcommit a card."""
    comp = R.lane_composition(name)
    env = comp["env"]
    assert R.ENV_TP in env, f"C03/D43 [{name}]: no RADIANCE_TP to compare (see the env-authority leg)"
    spec = _rendered_deployment(name)["spec"]["template"]["spec"]
    ctr = next(c for c in spec["containers"] if c.get("name") == R.SERVE_NAME)
    claim = (ctr.get("resources") or {}).get("requests", {}).get(R.GPU_CLAIM)
    assert str(env[R.ENV_TP]) == str(claim), (
        f"C03/D43 [{name}]: RADIANCE_TP={env[R.ENV_TP]!r} but the pod claims {claim!r} cards — "
        "tp pins one card per rank; a split here is a Pending forever or two ranks on one card"
    )


# --- the cheap-fake ban and the no-literal-argv render law ------------------------


@helm_skip
def test_c03_carrier_restates_no_lane_data():
    """The ban that makes the runtime proof load-bearing: the serve FORM's
    bytes must not contain ANY ruled DATA pair as a literal (`--flag value` or
    `--flag=value`), over the UNION of the four profiles (a carrier could fake
    one lane by restating another's), nor any lane identity string (model
    paths, served ids). Flag NAMES may live in the FORM; per-lane VALUES may
    not — a restated vector does not move when env moves, which is the exact
    staleness class D43 exists to kill."""
    docs = R.lane_docs("radiance")
    hit = R.serve_script_from_render(docs)
    assert hit is not None, "C03/D43: no serve wrapper to scan — designed-red naming dev round 3"
    script = hit[2]
    banned = [b for b in R.data_pair_bans(R.all_ruled_profiles()) if b in script]
    assert not banned, (
        f"C03/D43: the serve carrier ({hit[0]}/{hit[1]}) restates ruled DATA pairs as literals: "
        f"{banned} — that is a per-lane array re-copied into the chart, composing nothing"
    )
    ids = [lit for lit in R.LANE_IDENTITY_LITERALS if lit in script]
    assert not ids, (
        f"C03/D43: the serve carrier hard-codes lane identities {ids} — paths and served ids "
        "arrive only through env"
    )


@pytest.mark.parametrize("key", sorted(R.COMPOSITION_LANES))
@helm_skip
def test_c03_render_carries_no_literal_argv(key):
    """D43's render-side half: the serve container carries NO args key (the
    profile left the pod spec), its command is an INVOCATION of the mounted
    wrapper (mirroring the init precedent — ConfigMap files mount 0644, so the
    command is `sh` + the mounted path, never a script body and never a bare
    argv list), and the mounted data key is the one the locator found. The
    entrypoint law (§D1.5) survives INSIDE the wrapper: the probe in the AC1
    legs proves the engine is exec'd by bare name through PATH.

    Four-wide since the 2026-11-22 repair pass: D46 accepted the resting blocks
    as C03 output, so this chart law governs every render it produces — and the
    leg's old two-way dispatch was the same narrow-reader class as the tp/claim
    KeyError (a law spanning four releases read by code addressing two)."""
    docs = R.lane_docs(key)
    ctr = R.serve_container(R.deployment(docs))
    assert "args" not in ctr, (
        f"C03/D43 [{key}]: the serve container still renders an args key ({str(ctr.get('args'))[:160]}…) "
        "— D43 rules the argv out of the render into the wrapper + env"
    )
    command = ctr.get("command") or []
    assert command and all(isinstance(t, str) for t in command), (
        f"C03/D43 [{key}]: serve command renders {command!r} — the wrapper invocation must be "
        "a non-empty string list (loud fail at start, never a silent ENTRYPOINT boot)"
    )
    assert not any("\n" in t for t in command), (
        f"C03/D43 [{key}]: the serve command embeds a script body — the command invokes the "
        "mounted wrapper and carries no bytes of the FORM (the D35 init law, serve side)"
    )
    hit = R.serve_script_from_render(docs)
    assert hit is not None, (
        f"C03/D43 [{key}]: no serve-compose wrapper ConfigMap in the render — designed-red "
        "naming dev round 3"
    )
    _cm, key_name, _script = hit
    assert any(key_name in t for t in command), (
        f"C03/D43 [{key}]: serve command {[str(t) for t in command]} never references the wrapper "
        f"key {key_name!r} — the mounted ConfigMap would be decoration"
    )
    mount_paths = [str(m.get("mountPath", "")) for m in ctr.get("volumeMounts") or []]
    assert any(any(seg and seg in str(t) for seg in mount_paths) for t in command), (
        f"C03/D43 [{key}]: the serve command names no path under a volumeMount "
        f"({mount_paths}) — the wrapper must run from its mount, not a baked copy"
    )


# --- AC1 inheritance: the invariance proof against the immutable fixtures ---------


@pytest.mark.parametrize("key,release", sorted(MOVING_LANES.items()))
@helm_skip
def test_c03_render_holds_the_pinned_invariants(key, release):
    """D43 replaces the four-path diff BUDGET with the same duty in a narrower,
    argv-free shape: every property the budget kept byte-equal OUTSIDE its four
    paths — image@digest, probes, securityContext, the claim pair, memory, cpu,
    replicas, restartPolicy, grace — must equal the fixture EXACTLY (pool name
    folded). The D43 wave may move only env, command, args, volumes/mounts and
    the checksum annotation; anything else moving here is drift, and the
    planted-drift leg below proves this leg bites."""
    fix = _fixture(key)
    got = json.loads(_fold(json.dumps(_rendered_deployment(key), sort_keys=True)))
    want = fix["deployment"]
    wspec = want["spec"]["template"]["spec"]
    gspec = got["spec"]["template"]["spec"]
    wctr = next(c for c in wspec["containers"] if c.get("name") == R.SERVE_NAME)
    gctr = next(c for c in gspec["containers"] if c.get("name") == R.SERVE_NAME)
    for field in ("image", "imagePullPolicy", "securityContext",
                  "livenessProbe", "readinessProbe", "startupProbe"):
        assert wctr.get(field) == gctr.get(field), (
            f"C03 invariance [{release}]: serve container {field} moved off the fixture — "
            f"want {wctr.get(field)!r}, got {gctr.get(field)!r}; the D43 wave owns env/command/"
            "args/mounts and NOTHING else"
        )
    for m in ("requests", "limits"):
        assert wctr.get("resources", {}).get(m) == gctr.get("resources", {}).get(m), (
            f"C03 invariance [{release}]: resources.{m} moved — the claim pair and the Guaranteed "
            f"memory are transcribed facts (want {wctr.get('resources', {}).get(m)!r})"
        )
    assert want["spec"].get("replicas") == got["spec"].get("replicas"), (
        f"C03 invariance [{release}]: spec.replicas moved (want {want['spec'].get('replicas')!r}, "
        f"got {got['spec'].get('replicas')!r}) — rest states are owned facts (D54(1))"
    )
    assert wspec.get("terminationGracePeriodSeconds") == gspec.get("terminationGracePeriodSeconds"), (
        f"C03 invariance [{release}]: terminationGracePeriodSeconds moved — the 180 s drain "
        "envelope is not a wave variable"
    )
    assert wspec.get("restartPolicy") == gspec.get("restartPolicy"), (
        f"C03 invariance [{release}]: restartPolicy moved off {gspec.get('restartPolicy')!r} — "
        "Recreate is the pod-swap law"
    )
    for winit, ginit in zip(wspec.get("initContainers") or [], gspec.get("initContainers") or []):
        for field in ("image", "securityContext"):
            assert winit.get(field) == ginit.get(field), (
                f"C03 invariance [{release}]: init container {field} moved — the fetch FORM's "
                "carrier may change its command/volumeMounts, its identity may not"
            )


@pytest.mark.parametrize("key,release", sorted(MOVING_LANES.items()))
@helm_skip
def test_c03_invariance_catches_planted_drift(key, release):
    """Teeth of the invariance leg (the vacuity class this ticket has caught
    three times — the philosophy D43 inherits intact): plant an image swap,
    both halves of the claim pair, and a probe deletion into a deepcopy of the
    live render; each must redden its own arm of the comparison. Green always;
    this is the proof the gate is live, not itself the gate."""
    fix = _fixture(key)["deployment"]
    planted = copy.deepcopy(_rendered_deployment(key))  # deepcopy: lru_cached renders are SHARED
    spec = planted["spec"]["template"]["spec"]
    ctr = next(c for c in spec["containers"] if c.get("name") == R.SERVE_NAME)
    image = str(ctr.get("image", ""))
    assert ":" in image, f"{release}: serve image {image!r} carries no tag to plant on"
    ctr["image"] = image.rsplit(":", 1)[0] + ":planted-tag"
    for m in ("requests", "limits"):
        claims = ctr.setdefault("resources", {}).setdefault(m, {})
        assert R.GPU_CLAIM in claims, f"{release}: no live claim in {m} to plant on"
        claims[R.GPU_CLAIM] = "7"
    if "livenessProbe" in ctr:
        del ctr["livenessProbe"]
    gspec = planted["spec"]["template"]["spec"]
    wspec = fix["spec"]["template"]["spec"]
    gctr = next(c for c in gspec["containers"] if c.get("name") == R.SERVE_NAME)
    wctr = next(c for c in wspec["containers"] if c.get("name") == R.SERVE_NAME)
    assert wctr.get("image") != gctr.get("image"), "teeth: planted image NOT flagged"
    for m in ("requests", "limits"):
        assert wctr["resources"][m] != gctr["resources"][m], f"teeth: planted claim in {m} NOT flagged"
    if "livenessProbe" in wctr:
        assert wctr.get("livenessProbe") != gctr.get("livenessProbe"), "teeth: deleted probe NOT flagged"


# --- AC1/AC2 mechanism: the chart owns the script FORMs ----------------------------


def test_c03_chart_ships_the_fetch_form():
    """C03 (D35(3)): the generic fetch-script FORM is chart-owned bytes — it
    lives in the chart's values stanza or templates (the configMap carrier),
    carrying the C11/D27 portable-equality shape and NO lane literals (the
    literals bar is the sibling leg). Green since round 2; it guards the FETCH
    half of the carrier class while the D43 legs guard the serve half."""
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


def test_c03_chart_ships_the_serve_form():
    """C03/D43 serve-side twin of the fetch-FORM leg: the compose FORM is
    chart-owned bytes carrying the FORM-fixed flags, the loud guard on the
    required env, the startup echo, and the exec of the engine by BARE name
    (§D1.5 ENTRYPOINT law — the wrapper adds argv, it does not re-path the
    engine). Designed-red naming dev round 3 until the carrier lands."""
    text = R.chart_carrier_text()
    hit = [ln for ln in text.splitlines() if "--served-model-name" in ln]
    assert hit, (
        "C03/D43: no chart-owned byte composes --served-model-name — the serve FORM has not "
        "landed (the lanes still carry argv, or nothing); designed-red naming dev round 3"
    )
    for toks, what in (
        (("--port", "--host", "--max-num-seqs", "--kv-cache-dtype"), "the FORM-fixed flags"),
        (("radiance",), "the bare-name engine exec"),
    ):
        missing = [t for t in toks if t not in text]
        assert not missing, f"C03/D43: the chart-owned serve FORM never carries {what} — missing {missing}"
    guards = [ln for ln in text.splitlines() if "RADIANCE_MODEL_PATH" in ln]
    assert guards and any(re.search(r":\?|:?\"?[Mm]issing|is required|-e |set -eu", ln) for ln in guards), (
        "C03/D43: the serve FORM carries no loud guard on the required env — a missing "
        "RADIANCE_MODEL_PATH must kill the boot before exec, never fall back"
    )


def test_c03_chart_ships_no_lane_data():
    """C03 AC2 (OQ-D + D35 + D43): the chart keeps image/pin/probes/security/
    PVC/service MECHANISM and the generic script FORMs, and carries no lane
    DATA anywhere in chart-owned bytes — no serve array, no GPU claim, no
    per-pack sha/URL/byte literals, no modelPath default, and (D43) no ruled
    DATA pair or lane identity inside the serve FORM. The D43 re-anchor: the
    old `--model` token ban retired with the argv — flag NAMES are FORM
    bytes; the DATA pair ban above (same needle the carrier leg uses) is what
    bars the profile now."""
    text = R.chart_carrier_text()
    data = R.chart_values()
    at = data.get("app-template") or {}
    assert "serveArgs" not in at, (
        "C03 AC2: chart-owned bytes still carry a lane serve array (serveArgs) — the lane args "
        "belong in the release block's env (OQ-D mechanism-only shell, D43 channel); designed-red naming C03"
    )
    banned = [b for b in R.data_pair_bans(R.all_ruled_profiles()) if b in text]
    assert not banned, (
        f"C03 AC2/D43: chart-owned bytes restate ruled DATA pairs as literals: {banned} — a baked "
        "pair is lane data smuggled into the mechanism and the first thing the sandbox probe contradicts"
    )
    ids = [lit for lit in R.LANE_IDENTITY_LITERALS if lit in text]
    assert not ids, (
        f"C03 AC2/D43: chart-owned bytes hard-code lane identities {ids} — four releases of one "
        "shell inherit them, which is the exact failure the roster cannot work around"
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
    ):
        assert literal not in text, (
            f"C03 AC2/D35: chart-owned bytes hard-code {what} ({literal}) — a per-pack literal in a generic "
            "shell (values OR a script-FORM template) is a law the second release cannot obey; the FORM "
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
    this lane's scalars authored as data inside the block, the sibling's pack
    identity nowhere in the block, and (D43) no serve-args array on the serve
    container either — the serve specifics ride env. Each lane runs against ITS
    OWN constants — the sets are never cross-validated (D35's drift law)."""
    block = R.lane_block(key) if key != "radiance" else R.service_block()
    assert isinstance(block, dict), f"C03: no {key}: block to inspect — designed-red naming C03"
    controllers = (block.get("app-template") or {}).get("controllers") or {}
    fetch = ((controllers.get("radiance") or {}).get("initContainers") or {}).get(R.INIT_NAME) or {}
    assert "command" not in fetch, (
        f"C03: the {key} block still replaces the whole fetch script (initContainers.{R.INIT_NAME}.command) "
        "— designed-red naming C03 round 2: D35 rules the CHART owns the script FORM (configMap carrier); "
        "the lane passes its pack scalars as data only"
    )
    serve = ((controllers.get("radiance") or {}).get("containers") or {}).get(R.SERVE_NAME) or {}
    assert "args" not in serve, (
        f"C03/D43: the {key} block still authors a serve args array — the argv moved into the "
        "chart-owned compose wrapper; the block's channel for profile values is env "
        "(designed-red naming dev round 3)"
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
                        R.lane_pack_literals("radiance"))


@pytest.mark.skipif(not _ok, reason="render env")
def test_c03_fn_block_drops_the_whole_script_for_scalars():
    """C03/D35 twin leg: the fn block follows the same law — D35's carrier rules
    BOTH live lanes, and asserting only q27 would let the fn lane keep the
    interim script fork (the class the whole chunk closes)."""
    _assert_block_shape("radiance", R.lane_pack_literals("radiance"),
                        R.lane_pack_literals(R.Q27_APP_NAME))


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
    """C03 AC2 (the render-side pair of the values-level bar) + the D35/D43
    extensions: `helm template` on the bare chart must still be valid and must
    schedule nothing and serve nothing — zero GPU claim lines, zero lane DATA
    pairs, no OVERRIDE sentinel — and the configMaps (mechanism form, if the
    bare render carries them) must hold ZERO lane pack identity AND zero ruled
    DATA pairs: the FORMs are generic data with per-release scalars/env, never
    a baked lane pack or a baked vector. The D43 re-anchor retired the old
    `--model` token needle — flag names are FORM bytes now; the DATA-pair scan
    is what bars the profile here."""
    docs, raw = R.render(service=False)
    assert docs, "C03: the bare chart renders nothing"
    assert R.GPU_CLAIM not in raw, (
        f"C03 AC2: the bare chart render still claims {R.GPU_CLAIM} — the claim is lane data and belongs in "
        "the release block; designed-red naming C03"
    )
    for literal, what in ((R.PACK_LFS_SHA, "fn LFS sha"), (R.Q27_PACK_LFS_SHA, "q27 LFS sha"),
                          (R.PACK_URL, "fn pack URL"), (R.Q27_PACK_URL, "q27 pack URL"),
                          (str(R.PACK_BYTES), "fn pack bytes"), (str(R.Q27_PACK_BYTES), "q27 pack bytes"),
                          (R.MODEL_PATH, "fn model path"), (R.Q27_MODEL_PATH, "q27 model path")):
        assert literal not in raw, f"C03 AC2: the bare render embeds {literal} ({what}) — a per-lane fact"
    for cm in R.configmap_docs(docs):
        blob = json.dumps(cm.get("data") or {})
        for lit in (*R.lane_pack_literals("radiance"), *R.lane_pack_literals(R.Q27_APP_NAME)):
            assert lit not in blob, (
                f"C03 AC2/D35: the BARE-render configMap {cm['metadata']['name']} embeds a lane pack "
                f"literal ({lit}) — chart-bare means mechanism form only, no per-release data"
            )
        baked = [b for b in R.data_pair_bans(R.all_ruled_profiles()) if b in blob]
        assert not baked, (
            f"C03 AC2/D43: the bare-render configMap {cm['metadata']['name']} bakes DATA pairs {baked} "
            "— the compose FORM takes values through env; a bare render cannot know any lane's numbers"
        )
    assert "OVERRIDE_VIA_CUSTOM_VALUES" not in raw, "C03 AC3: an OVERRIDE sentinel entered the render (D8 keyless law)"


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
