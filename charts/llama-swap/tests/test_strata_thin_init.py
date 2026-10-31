# cf-86 C07 chart-side residue — the model-fetch init converts from a ~330-line
# script body in values.yaml to a thin exec-form command against the baked
# entrypoint (chunks/C07.md "Chart-side residue (exact)").
#
# Two postures in one file:
# - the NEW-shape arms (exec form, empty args, script body gone, chart-side
#   mkdir gone) are DESIGNED RED until dev lands the conversion — the reds
#   name the un-converted surface;
# - the byte-unchanged arms (env scalars + hf-token secretKeyRef placement,
#   resources, securityContext, image + pullPolicy) are GREEN now and must
#   stay green through the lift — a red there is a C07 deviation, not a queue.
#
# The boot-guard law is the ordering adjudication made executable: exec form
# with no shell wrapper means a chart pointing at a not-yet-pushed image fails
# at container start with zero script executed and markers untouched — the
# self-heal inside the CI push window rests on that loudness, so the command
# may reference ONLY paths the Dockerfile build-verify step pins.

from __future__ import annotations

import re

import pytest

import strata_testlib as S

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)


def _init(docs) -> dict:
    inits = S.strata_pod(docs)["spec"].get("initContainers") or []
    hits = [c for c in inits if c.get("name") == "model-fetch"]
    assert hits, f"strata pod has no model-fetch init: {[c.get('name') for c in inits]}"
    return hits[0]


def _on_init():
    return _init(S.render_on()[0])


def _values_text() -> str:
    return S.read(S.CHART_DIR / "values.yaml", "the init conversion is a values.yaml edit")


# --- the conversion (designed red until dev lands) -----------------------------


@helm
def test_c07_init_command_is_the_exec_form_baked_entrypoint():
    """command: ["/opt/strata/bin/fetch_models.sh"], args empty — no /bin/sh -c
    wrapper. A shell wrapper would turn the boot guard into a silent no-op
    (sh starts fine, the missing file fails later, half the law's loudness is
    lost); exec form fails container START with exec: no such file."""
    ctr = _on_init()
    cmd = [str(x) for x in (ctr.get("command") or [])]
    assert cmd == [f"{S.BIN}/fetch_models.sh"], (
        f"init command {cmd!r} — C07 conversion not landed: exec form, exactly "
        f"one element, the baked entrypoint, no shell wrapper"
    )
    assert not (ctr.get("args") or []), f"init args must be empty post-lift: {ctr.get('args')!r}"


@helm
def test_c07_boot_guard_interface_freeze_init_paths_are_build_verified():
    """Interface-freeze pattern extended to the fetch entrypoint: every
    /opt/strata path the rendered init executes must be pinned by the image
    build (COPY or verify test -x). The thin chart may not reference a path
    nothing builds — that is the old-image boot the ordering adjudication
    accepts ONLY because the failure is loud, and loudness requires the path
    pair (chart reference, build pin) to stay one fact."""
    dockerfile = S.read(S.CONTAINER_DIR / "Dockerfile", "C07 adds COPY files/ + verify")
    cmd = [str(x) for x in (_on_init().get("command") or [])]
    refs = [t for t in cmd if t.startswith("/opt/strata/")]
    assert refs, f"init command references no baked path yet ({cmd}) — conversion not landed"
    unverified = [t for t in refs if t not in dockerfile]
    assert not unverified, f"init executes paths the image build never pins: {unverified}"


@helm
def test_c07_script_body_vanishes_from_values_yaml():
    """Zero script-body lines remain: no pack functions, no heredoc downloaders,
    no byte literals, no marker assignment. The pointer comments naming
    containers/strata/files/ are what remains (chunk: chart states intent +
    env contract only). Red today: each token still sits in values.yaml."""
    text = _values_text()
    for tok, why in (
        ("abl_pack()", "the SC117 pack body (lifts INTACT in C07, deleted only by C08)"),
        ("orca_pack()", "the orca pack body"),
        ("<<'PY'", "the heredoc downloaders"),
        ("47342144896", "the SC117 byte literal (byte_pins.env is its home now)"),
        ("44637691008", "the orca byte literal"),
        ('MARK="/models/strata/.setup-', "the marker assignment"),
        ('ln -sfn /models/strata /data/install', "the install-anchor dance"),
    ):
        assert tok not in text, f"values.yaml still carries {why}: {tok!r} still present"
    assert "fetch_models.sh" in text, (
        "the thin init lost its pointer to containers/strata/files/ — "
        "the why-comment is how a reader finds the moved logic"
    )


@helm
def test_c07_chart_side_sessions_mkdir_leaves_with_the_script():
    """Exactly-once law for the sessions mkdir: C06 put it chart-side because
    the overlay could not hold the script; the lift moves it into the driver
    (pinned in test_strata_image_fetch.py), so the chart copy must not survive
    as a second home."""
    assert "mkdir -p " + S.Q4_SLOT_SAVE_PATH not in _values_text(), (
        f"values.yaml still mkdir's {S.Q4_SLOT_SAVE_PATH} chart-side — two homes "
        "for one law is the staleness class the lift exists to kill"
    )


@helm
def test_c07_strix_packaged_engine_legs_move_to_the_re_pinned_build():
    """v0.2.8 fold-in, chart side: engineProfileStrix exe + lib_dirs carry the
    0.1.54 halo label; no 0.1.52 pin survives in the strix region outside
    bump-explaining comments. The claim-compiled primary path is version-free
    and untouched."""
    text = _values_text()
    region = S.values_region(text, "engineProfileStrix")
    assert "0.1.54-linux-x86_64-hip-halo" in region, (
        f"strix profile did not move to the 0.1.54 packaged root:\n{region[:300]}"
    )
    bare = [ln for ln in region.splitlines() if "0.1.52" in ln and not ln.lstrip().startswith("#")]
    assert not bare, f"stale 0.1.52 pin in executable strix lines: {bare}"
    primary = S.profile_json(S.render_on()[0], S.PROFILE_PRIMARY_FILE)
    assert primary["exe"] == "/models/strata/Strata/engine/strata", (
        "the claim-compiled primary exe path is version-free — the re-pin must not touch it"
    )


@helm
def test_c07_only_the_strix_exe_leg_moves_among_the_profiles():
    """C07 touches exactly one packaged exe: the re-pin's chart-side effect is
    the strix profile; primary/orca/q4 run the claim-compiled engine and their
    exe legs stay byte-equal today's captured literal. (C08's sweep removed the
    abliterated profile — its absence is pinned in test_strata_c08_rung_shifts.py.)"""
    docs = S.render_on()[0]
    claim_exe = "/models/strata/Strata/engine/strata"
    for file in (S.PROFILE_PRIMARY_FILE, S.PROFILE_ORCA_FILE, S.PROFILE_Q4_FILE):
        prof = S.profile_json(docs, file)
        assert prof.get("exe") == claim_exe, (
            f"{file} exe {prof.get('exe')!r} — only the STRIX profile runs a packaged engine root"
        )


# --- byte-unchanged posture (green today, must stay green) ---------------------


@helm
def test_c07_init_resources_are_the_compile_peak_pair_byte_unchanged():
    """2Gi/32Gi with the 200m request — the compile-peak ruling (1Gi cap OOM'd
    the ninja -j16 clang step 2026-10-29). Runtime shape, not logic: the lift
    must not resize it."""
    res = _on_init().get("resources", {})
    assert res.get("requests", {}).get("memory") == "2Gi", res
    assert res.get("requests", {}).get("cpu") in ("200m", 0.2), res
    assert res.get("limits", {}).get("memory") == "32Gi", res


@helm
def test_c07_init_privileged_device_shape_unchanged():
    sc = _on_init().get("securityContext") or {}
    assert sc.get("privileged") is True, (
        "the HIP probe needs the device view (setup.sh --backend hip); "
        "the download-only non-privileged shape is the pre-2026-10-27 ruling"
    )


@helm
def test_c07_init_image_stays_the_rolling_same_image_pair():
    """Same image as the main container, tag main + pullPolicy Always — the
    rolling-tag posture law (the self-heal window argument REQUIRES Always:
    the next attempt after CI's :main push re-pulls and re-enters). No :v<run>
    hand-pin (repo law), no tag flip."""
    for docs in (S.render_on()[0], S.render_service_overlay()[0]):
        img = _init(docs).get("image")
        assert img == "ghcr.io/ownyourio/strata:main", f"init image {img!r} — tag flips are not C07's to make"
        assert img == S.strata_container(docs).get("image"), (
            "the fetch init no longer rides the SAME image it just built the claim for — "
            "the boot guard's 'the image that lacks the file' argument dies with a separate image"
        )
        assert _init(docs).get("imagePullPolicy") == "Always", (
            f"init pullPolicy {_init(docs).get('imagePullPolicy')!r} — the self-heal rests on Always re-pull"
        )


@helm
def test_c07_env_scalar_law_survives_the_lift_on_both_renders():
    """Chart default keeps STRATA_QUANTS: "q3" as a scalar; the gpu-ai overlay
    carries the three-token set + the two STRATA_MODEL_* scalars + exactly one
    secretKeyRef (hf-token/token) on the init. The script reads
    HF_TOKEN from its process env — plumbing must not move or wrap (R-d
    download-only law). C08's sweep shrank the set from q3,abl,orca,q4 and
    deleted STRATA_MODEL_ABL (U9.3): the swept scalar's ABSENCE is part of the
    law, and the post-state trio is pinned in test_strata_c08_rung_shifts.py."""
    text = _values_text()
    assert re.search(r'STRATA_QUANTS:\s*"q3"\s*$', text, re.M), (
        "chart-side STRATA_QUANTS q3 default must survive the conversion"
    )
    docs = S.render_service_overlay()[0]
    env = {e.get("name"): e for e in (_init(docs).get("env") or []) if isinstance(e, dict)}
    assert (env.get("STRATA_QUANTS") or {}).get("value") == "q3,orca,q4", env.get("STRATA_QUANTS")
    assert "STRATA_MODEL_ABL" not in env, (
        "the swept abliterated scalar is back — C08 U9.3 deleted it; a revival "
        "without PROVENANCE is an un-sanctioned re-add"
    )
    for name, want in (("STRATA_MODEL_ORCA", "orca/IQ4_XS"),
                       ("STRATA_MODEL_Q4", "unsloth/UD-Q4_K_XL")):
        entry = env.get(name) or {}
        assert entry.get("value") == want, f"{name} = {entry!r}, want scalar {want!r}"
        assert "valueFrom" not in entry, f"{name} became a reference — scalars only"
    hf = env.get("HF_TOKEN") or {}
    ref = (hf.get("valueFrom") or {}).get("secretKeyRef") or {}
    assert (ref.get("name"), ref.get("key")) == ("hf-token", "token"), f"HF_TOKEN plumbing moved: {hf!r}"
    hits = S.serve_path_secret_hits(docs)
    assert not hits, f"secret material reached the serve path through the lift: {hits}"


@helm
def test_c07_init_container_mounts_and_order_unchanged():
    """advancedMounts/persistence and the single-init shape stay untouched —
    the lift converts command/args only. Pinning the volumeMount set keeps a
    'drive-by cleanup' from quietly removing the devices or the claim."""
    ctr = _on_init()
    paths = sorted(m["mountPath"] for m in ctr.get("volumeMounts") or [])
    assert paths == ["/dev/dri", "/dev/kfd", "/models"], f"init mounts moved: {paths}"
    inits = S.strata_pod(S.render_on()[0])["spec"].get("initContainers") or []
    assert [c.get("name") for c in inits] == ["model-fetch"], [c.get("name") for c in inits]
