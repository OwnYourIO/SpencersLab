# cf-141 C04 — the bump era (PR-2): Strata 0.2.9→0.2.13 / engine 0.1.55→
# 0.1.59 with the `"drafting": "mtp"` config obligation. Ledger law (plan
# law 6): every version literal moves in ONE commit; envelope literals and
# the claim-compiled exe paths do NOT. Authority: owner Q8 (un-defer), Q13(a)
# (pin-first, bump gated), Q16 (drafting + STRATA_MMQ_KQ stay present at
# 0.1.59 with EXPERIMENTAL-flag comments, never settled-intent wording),
# RESEARCH Round 2 OQ-R2b.5 item 1 / [79].
#
# Red posture: the version-reading legs (strix root, drafting keys, marker
# pair, experimental comments) are DESIGNED RED until C04 lands — each names
# C04 and the exact literal it waits for. The invariance legs (claim-compiled
# exe version-free, supervisor tag untouched, envelope literals, services
# clean) are GREEN now and become the tripwires if C04's single commit
# over-reaches. Landing-round moves by the test session (TEST_SPEC §9.28
# inventory): the pre-bump constants in test_dockerfile.py /
# test_strata_c09_ornith_carry.py / test_strata_thin_init.py re-pin at the
# same gate this wave's capture lands.

from __future__ import annotations

import re

import pytest

import strata_testlib as S

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)

DOCKERFILE = S.CONTAINER_DIR / "Dockerfile"
IMAGE_README = S.CONTAINER_DIR / "README.md"

# 0.2.9-era digests (containers README ledger today): the bump ledger must
# show FRESH digests, so "digest copied not re-read" == still these values.
PRE_BUMP_DIGESTS = (
    "sha256:a0536d4b9e734a1d06b9b630362b95d01108382a4a39785e6abdc1dfe8326c39",
    "sha256:2ac97575713efaa37299d914c628d3f1d40b68b893dd78430f7ea4bd18c5084a",
)


def _exec_lines(text: str) -> list[str]:
    return [ln.strip() for ln in text.splitlines() if ln.strip()
            and not ln.strip().startswith("#")]


def _flavor_tags(dockerfile: str) -> list[str]:
    return sorted({m.group(1) for m in re.finditer(
        re.escape("ghcr.io/niko1221/strata:") + r"(\S+?-rocm-gfx1\d{3})", dockerfile)})


# --- version legs: RED until C04 lands, naming C04 -----------------------------


@helm
def test_cf141_c04_strix_packaged_root_at_0159():
    """C04 AC2: the chart's only packaged-root literals — strix exe +
    lib_dirs — read the 0.1.59 halo root, and no retired-era label
    (0.1.52/0.1.54/0.1.55) survives in executable strix lines (comments may
    carry the bump history)."""
    text = S.read(S.CHART_DIR / "values.yaml", "C04 moves the strix exe/lib_dirs literals")
    region = S.values_region(text, "engineProfileStrix")
    assert S.CF141_ENGINE_HALO_LABEL in region, (
        f"strix region does not name {S.CF141_ENGINE_HALO_LABEL} — C04's bump not landed"
    )
    stale = [ln for ln in region.splitlines()
             if re.search(r"0\.1\.5[245]\b", ln) and not ln.lstrip().startswith("#")]
    assert not stale, f"retired engine labels in executable strix lines (C04 must clear 0.1.55): {stale}"


@helm
def test_cf141_c04_drafting_on_four_flash_next_absent_on_ornith():
    """C04 AC4: `"drafting": "mtp"` renders on EXACTLY the four flash-next
    profiles (0.2.13 shapes drafting unconditionally [79]; the pin makes the
    MTP resolution explicit and grep-verifiable), and stays ABSENT from
    ornith's q36 surface — its surface law is separate, the closed-world key
    check says a foreign key there is red."""
    docs = S.render_on()[0]
    profiles = {f: S.profile_json(docs, f) for f in S.INNER_PROFILE_FILES.values()}
    problems = S.drafting_violations(profiles)
    assert not problems, ("cf-141 C04 drafting obligation unmet:\n" + "\n".join(problems))


@helm
def test_cf141_c04_q16_experimental_comments_in_values_source():
    """C04 AC4 (source half — Q16: the render carries the key, the SOURCE
    carries the word): every values region that arms a drafting pin must
    mark it EXPERIMENTAL at the new engine, the q4 env region likewise keeps
    its Q16 posture, and settled-intent wording must not appear anywhere in
    the source."""
    text = S.read(S.CHART_DIR / "values.yaml", "C04's drafting pins live in the values comments")
    for key in ("engineProfile", "engineProfileStrix", "engineProfileOrca", "engineProfileStrataQ4"):
        region = S.values_region(text, key)
        if "drafting" not in region:
            pytest.fail(f"{key}: no drafting pin in the values region yet — C04 not landed "
                        "(the render arm names the same missing key)")
        assert re.search(r"experimental", region, re.I), (
            f"{key}: drafting pin without the Q16 experimental-flag comment"
        )
    q4_region = S.values_region(text, "engineProfileStrataQ4")
    assert re.search(r"STRATA_MMQ_KQ", q4_region), "C04 keeps the q4 STRATA_MMQ_KQ pin present (Q16)"
    assert re.search(r"experimental", q4_region, re.I), (
        "q4 env pin lost its Q16 experimental posture at the new engine"
    )
    for ln in text.splitlines():
        if re.search(r"settled intent", ln, re.I) and not re.search(r"\bnot\b|never", ln, re.I):
            pytest.fail(f"values carries settled-intent wording (Q16 forbids): {ln.strip()[:90]!r}")


def test_cf141_c04_checkout_marker_moves_to_the_0213_pair():
    """C04: `fetch_models.sh` L74-75 marker literals become
    `.checkout-0.2.13-carry1` / `0.2.13-carry-1` — content-compared, so the
    first boot on merged main re-fires the claim migration (the recompile
    lands the new engine at the SAME version-free path; the exe legs do not
    move). The version-free migration laws stay pinned by
    test_strata_c09_ornith_carry.py and must survive the string flip."""
    problems = S.marker_pair_violations(S.read(S.FETCH_SH, "C04 moves the marker literals"))
    assert not problems, ("cf-141 C04 marker pair not landed:\n" + "\n".join(problems))


def test_cf141_c04_ledger_pair_fresh_digests_and_engine_proof():
    """C04 AC2 offline shape (the digests themselves are live re-reads at the
    landing round — pin STRUCTURE, not the network): the containers README
    pairs BOTH 0.2.13 flavor tags with distinct 64-hex digests, records the
    re-read method + date, and names the `com.strata.engine` label with the
    0.1.59 proof; the 0.2.9 digest pair must not survive as the current
    rows (the copied-not-re-read class)."""
    readme = S.read(IMAGE_README, "C04's ledger-law move")
    for tag in S.CF141_FROM_TAGS:
        assert tag in readme, f"README never names the bumped flavor tag {tag} — C04 not landed"
        idx = readme.index(tag)
        window = readme[max(0, idx - 200): idx + 700]
        digests = set(re.findall(r"sha256:[0-9a-f]{64}", window))
        assert digests, f"{tag}: no 64-hex digest paired with it in the ledger window"
        assert not any(d in PRE_BUMP_DIGESTS for d in digests) or len(digests) > 1, (
            f"{tag}: the ledger still carries the 0.2.9 digest pair — a copied-not-re-read digest"
        )
    assert re.search(r"com\.strata\.engine[^\n]{0,200}" + re.escape(S.CF141_ENGINE_VERSION)
                     + r"|" + re.escape(S.CF141_ENGINE_VERSION) + r"[^\n]{0,200}com\.strata\.engine",
                     readme, re.S), "no com.strata.engine 0.1.59 label proof recorded"
    assert re.search(r"(anonymous token|manifest HEAD)[^\n]{0,200}\d{4}-\d{2}-\d{2}"
                     r"|\d{4}-\d{2}-\d{2}[^\n]{0,200}(re-read|re-read)", readme), \
        "the ledger records no dated re-read method for the new pair"


def test_cf141_c04_clone_and_dockerfile_labels_at_the_pair():
    """C04 ledger law inside the Dockerfile: BOTH FROM tags == 0.2.13 pair
    (a half-moved pair reddens — the two-stage image would carry two apps),
    the clone is v0.2.13, both engine label dirs are 0.1.59, and no :0.2.9
    reference survives in an executable line."""
    dockerfile = S.read(DOCKERFILE, "C04's FROM/clone/label literals")
    problems = S.flavor_pair_violations(_flavor_tags(dockerfile))
    clones = re.findall(r"git clone[^\n&;]*--branch\s+(\S+)", dockerfile)
    if not (clones and all(c == S.CF141_CLONE_TAG for c in clones)):
        problems.append(f"clone tags {clones}, want v0.2.13")
    if not (S.CF141_ENGINE_RX9070_LABEL in dockerfile and S.CF141_ENGINE_HALO_LABEL in dockerfile):
        problems.append("the engine COPY/verify label dirs are not both at 0.1.59")
    stale = [ln for ln in _exec_lines(dockerfile) if re.search(r"strata:0\.2\.9|0\.1\.55-linux", ln)]
    if stale:
        problems.append(f"pre-bump literals in executable lines: {stale[:3]}")
    assert not problems, ("cf-141 C04 Dockerfile literals not at the bump:\n" + "\n".join(problems))


def test_cf141_c04_q14_containers_readme_doc_truth():
    """C04's folded Q14 spots (owner round-3, same-PR files): the containers
    README builder-base row states alpine 3.24 (the Dockerfile truth), and
    the cgroup sentence states the shipped 110Gi, not the stale 72Gi."""
    readme = S.read(IMAGE_README, "C04 folds the two containers-README doc-truth fixes")
    assert "alpine:3.22" not in readme, "the stale alpine:3.22 claim survives — R2-E7 spot 1, C04"
    assert "alpine:3.24" in readme, "the builder-base row does not state the Dockerfile's 3.24 truth"
    assert "72Gi" not in readme, "the stale 'caps the container at 72Gi' claim survives — R2-E7 spot 2, C04"
    assert "110Gi" in readme, "the cgroup sentence must state the shipped 110Gi"


# --- invariance legs: green now, the C04 tripwires ------------------------------


@helm
def test_cf141_c04_claim_exe_paths_stay_version_free():
    """Plan law 6: the claim-compiled rungs' exe paths are version-free and
    do NOT move with the bump (marker-keyed migration recompiles in place).
    Green today; red if C04's commit reaches into these paths."""
    docs = S.render_on()[0]
    claim_exe = "/models/strata/Strata/engine/strata"
    for file in (S.PROFILE_PRIMARY_FILE, S.PROFILE_ORCA_FILE, S.PROFILE_Q4_FILE,
                 S.PROFILE_ORNITH_FILE):
        assert S.profile_json(docs, file).get("exe") == claim_exe, (
            f"{file}: exe moved off the version-free claim-compiled root — the bump does not "
            "rewrite chart exe paths (marker migration lands the new engine at this path)"
        )


@helm
def test_cf141_c04_envelope_literals_invariant_under_the_bump():
    """C04 AC4 (the "bump touches no envelope" leg, pre-capture form): the
    caps, the cgroup and `--kv*`/conv-slots literals this ticket must not
    move are pinned against the era-chain fixtures AND the shipped constants.
    After C03 lands these read the envelope state; C04's own step is the
    bump-era delta check in test_cf141_era_steps_are_one_delta_each."""
    docs = S.render_on()[0]
    primary = dict(S.arg_pairs(S.profile_json(docs, S.PROFILE_PRIMARY_FILE)))
    assert primary.get("--memory-limit-mib") == str(S.PRIMARY_MEMORY_LIMIT_MIB)
    q4 = dict(S.arg_pairs(S.profile_json(docs, S.PROFILE_Q4_FILE)))
    assert q4.get("--memory-limit-mib") == str(S.Q4_MEMORY_LIMIT_MIB)
    orca = dict(S.arg_pairs(S.profile_json(docs, S.PROFILE_ORCA_FILE)))
    assert orca.get("--memory-limit-mib") == "92160"
    for file in S.INNER_PROFILE_FILES.values():
        args = " ".join(S.arg_tokens(S.profile_json(docs, file)))
        assert "--kv-grow" not in args
    ctr = S.strata_container(docs)
    assert (ctr.get("resources") or {}).get("limits", {}).get("memory") == S.STRATA_CGROUP_LIMIT


def test_cf141_c04_supervisor_pin_untouched():
    """One branch, one concern: the supervisor `unified-vulkan-<N>` pin is
    not this bump's (C04 Files-not-touched). Green today; red if the ledger
    commit over-reaches."""
    dockerfile = S.read(DOCKERFILE, "the supervisor stage pin is outside C04")
    m = re.search(re.escape("ghcr.io/mostlygeek/llama-swap:") + r"([\w.-]+)", dockerfile)
    assert m and m.group(1) == S.CF141_SUPERVISOR_TAG, (
        f"supervisor tag {m.group(1) if m else None!r} moved — unified-vulkan stays out of cf-141"
    )


def test_cf141_c04_services_block_carries_no_version_literals():
    """EXPLORE R2-B [V]: no version literals live under services/ — the bump
    has no service-side leg to touch. If this ever reddens, the premise
    changed and the ledger law needs a new surface, not a silent edit."""
    text = S.SERVICE_VALUES.read_text()
    offenders = [ln.strip()[:80] for ln in text.splitlines()
                 if re.search(r"0\.2\.9|0\.2\.13|0\.1\.5[59]|v\.?0\.2\.\d", ln)
                 and not ln.strip().startswith("#")]
    assert not offenders, f"version literals in services/gpu-ai values: {offenders}"


# --- non-vacuity probes (pure validators over synthetic states) ------------------


def test_cf141_c04_half_bump_mutants_redden_by_name():
    """The chunk's non-vacuity list, executable offline through the SHARED
    validators (mutant and live check cannot drift apart): a half-moved FROM
    pair, drafting smuggled onto ornith, a drafting era riding a conv value,
    and the marker left at 0.2.9 must each fail the owning law."""
    half = ("FROM ghcr.io/niko1221/strata:0.2.13-rocm-gfx120x AS a\n"
            "FROM ghcr.io/niko1221/strata:0.2.9-rocm-gfx1151 AS b\n")
    assert S.flavor_pair_violations(_flavor_tags(half)), "half-moved pair must redden the pair law"
    assert not S.flavor_pair_violations(list(S.CF141_FROM_TAGS)), "the complete bumped pair must clear"
    good = {f: {"drafting": S.CF141_DRAFTING_VALUE} for f in S.FLASH_NEXT_PROFILES}
    good[S.PROFILE_ORNITH_FILE] = {"parallel": 1}
    assert not S.drafting_violations(good), "the four-profile state must satisfy the obligation law"
    leak = dict(good)
    leak[S.PROFILE_ORNITH_FILE] = {"parallel": 1, "drafting": "mtp"}
    assert any("q36" in v for v in S.drafting_violations(leak)), "drafting-on-ornith must redden by name"
    missing = dict(good)
    missing[S.PROFILE_Q4_FILE] = {}
    assert any("strata-q4" in v for v in S.drafting_violations(missing)), "a dropped pin must redden"
    bump_prev = {"parallel": 8, "env": {}, "args": ["--conv 16384"]}
    smuggled = {"parallel": 8, "env": {}, "args": ["--conv 32768"], "drafting": "mtp"}
    assert S.era_delta(bump_prev, smuggled) == {"args", "drafting"}, \
        "a drafting step riding a conv value must surface as a two-key delta (the era arm rejects it)"
    assert S.marker_pair_violations("CHECKOUT_MARKER=/models/strata/.checkout-0.2.9-carry1\n"
                                    "CHECKOUT_MARKER_ID=0.2.9-carry-1\n"), \
        "the marker-left-behind mutant must trip the pair check"
    assert not S.marker_pair_violations(
        "CHECKOUT_MARKER=" + S.CF141_CHECKOUT_MARKER + "\n"
        "CHECKOUT_MARKER_ID=" + S.CF141_CHECKOUT_MARKER_ID + "\n"), "the bumped pair must clear"
