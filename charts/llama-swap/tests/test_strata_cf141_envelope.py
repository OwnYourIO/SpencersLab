# cf-141 C03 — the owner-ruled envelope: `parallel: 8` on the four flash-next
# rungs (primary at the full row-H shape), ornith's 1 kept. Authority: owner
# Q9 ("8 slots everywhere. I know it won't fit… I'd rather crash it and scale
# back from there") + Q10 (row-H) + Q17(a) (ship at the pin), plan-approved
# 2026-11-10T23:17Z. Red posture: the per-rung table, the row-H shape trio
# and the era steps are DESIGNED RED until C03 lands (missing value / missing
# capture — the green/red map names them); the pre-envelope guard, the
# q4/orca overshoot derivations, the purity of the landed anchor dir and the
# ornith negative pin are green now and must stay green.
#
# Scale-back path (documented per the chunk's probe requirement): dropping
# ONE rung back to 4 is a re-pin of that rung's row in
# strata_testlib.CF141_PARALLEL_RULINGS — landed only with the era-step
# capture the §9.16 ritual owns — never a re-widening of the sibling loop
# (test_cf141_scaleback_is_a_table_repin_probe).

from __future__ import annotations

import json

import pytest

import strata_testlib as S

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)


def _docs():
    return S.render_on()[0]


def _profile(file: str) -> dict:
    return S.profile_json(_docs(), file)


# --- AC1: the per-rung table (RED naming C03 until the raise lands) ------------


@helm
def test_cf141_per_rung_parallel_table():
    """C03 AC1: rendered `parallel` per profile file == {8,8,8,8,1} EXACT,
    every entry sourced from the per-rung ruling-table constant (with its
    owner citation), never from the sibling loop."""
    rendered = S.render_parallel_map(_docs())
    problems = S.parallel_violations(rendered, S.CF141_PARALLEL_RULINGS)
    assert not problems, ("cf-141 C03 envelope not shipped (per-rung rulings, not a loop):\n"
                          + "\n".join(problems))


def test_cf141_rung_rulings_name_their_owner_words():
    """The table is only legal because every row carries its ruling: Q9 with
    the Q17(a) ship-at-the-pin posture, row-H = Q9+Q10 for the primary, the
    q36 surface law for ornith's kept 1. An anonymous number in the table is
    an un-attributed envelope change — this meta-arm is the audit."""
    problems = []
    for file, (value, citation) in S.CF141_PARALLEL_RULINGS.items():
        if not citation or citation.strip() == "":
            problems.append(f"{file}: ruling row has no citation")
        if not value or value < 1:
            problems.append(f"{file}: parallel {value!r} is not a positive slot count")
    if not any("Q9" in c for _v, c in S.CF141_PARALLEL_RULINGS.values()):
        problems.append("no row cites Q9 — the envelope opening has no owner word")
    assert not problems, "\n".join(problems)


@helm
def test_cf141_rowh_primary_shape():
    """C03 AC1 (row-H trio, Q10 verbatim): primary conv pair (32768,16) ->
    (16384,16) via arg_pairs pair form, env EXACTLY {"STRATA_PLE_AUTO_RAM":
    "0"} (JSON string — int form is the §9.12 keys-vs-values class), and the
    frozen others byte-unchanged; --ple-io explicit stays forbidden (hazard
    law survives row-H: the pin is env-form only)."""
    prof = _profile(S.PROFILE_PRIMARY_FILE)
    pairs = dict(S.arg_pairs(prof))
    assert pairs.get("--conversation-cache-mib") == "16384", (
        f"primary conv reads {pairs.get('--conversation-cache-mib')!r}, row-H says 16384 (Q10)"
    )
    assert pairs.get("--conversation-cache-slots") == "16", (
        "row-H halves the conv BUDGET, not the slots — 16 stays"
    )
    problems = S.env_pin_violations(prof.get("env"), S.CF141_PRIMARY_ENV_ARMED)
    assert not problems, "primary env != the row-H PLE-direct pin: " + "; ".join(problems)
    for flag, want in (("--memory-limit-mib", str(S.PRIMARY_MEMORY_LIMIT_MIB)),
                       ("--kv", "int8"), ("--kv-resident", "32768"),
                       ("--max-context", "262144"), ("--prefill", "auto:32768")):
        assert pairs.get(flag) == want, (
            f"row-H shipped alongside {flag} {want!r}; render reads {pairs.get(flag)!r} — "
            "C03's envelope half moves conv/env/parallel and NOTHING else (AC1/AC2)"
        )
    toks = set(S.arg_tokens(prof))
    assert "--ple-io" not in toks, "--ple-io explicit rode row-H (hazard law: env-form only)"


@helm
def test_cf141_non_target_values_untouched():
    """C03 AC1 tail / AC2: every profile file deep-equals its era-chain tip
    capture (whole-file — catches extra riders a key-pinned arm misses: a
    conv tweak smuggled into orca's era, q4 env drift beyond C02's state),
    and the pod-level literals that must stay byte-identical (cgroup 110Gi,
    requests 64Gi, grace 420). A red naming a MISSING capture means the
    values moved before its §9.16-era step dir landed."""
    docs = _docs()
    for file in (S.PROFILE_PRIMARY_FILE, S.PROFILE_STRIX_FILE,
                 S.PROFILE_ORCA_FILE, S.PROFILE_Q4_FILE):
        assert S.profile_fixture(file) == S.profile_json(docs, file), (
            f"{file} diverged from its era-chain tip — if C02/C03 dev just landed the values "
            "edit, run the capture ritual (verify the delta, double-capture, write the step dir)"
        )
    ornith = _profile(S.PROFILE_ORNITH_FILE)
    assert ornith.get("parallel") == 1, "ornith moved — Q9 read as flash-next rungs only (Q17)"
    ctr = S.strata_container(docs)
    res = ctr.get("resources") or {}
    assert (res.get("limits") or {}).get("memory") == S.STRATA_CGROUP_LIMIT, (
        "C03's envelope law: the 110Gi cgroup stays UNCHANGED (no ruling re-opens it)"
    )
    assert (res.get("requests") or {}).get("memory") == "64Gi", "requests must stay 64Gi"
    assert S.strata_pod(docs)["spec"].get("terminationGracePeriodSeconds") == 420


# --- AC3: the interlock narrowing (executed here; loop keeps its teeth) --------


@helm
def test_cf141_interlock_dropped_parallel_leg():
    """C03 law move 1: `parallel` LEFT the byte-identical cross-rung set by
    owner Q9. Membership guard — the sibling set is exactly
    {exe, cwd, lib_dirs, backend, gpu, host}; silently removing a second key
    (e.g. backend) reddens THIS arm, not the data arm. The q4 loop file must
    cite the Q9 ruling at the exclusion, and the loop must iterate the
    pinned constant."""
    assert set(S.CF141_SIBLING_KEYS) == {"exe", "cwd", "lib_dirs", "backend", "gpu", "host"}, (
        f"sibling set moved to {sorted(S.CF141_SIBLING_KEYS)} — every member is a per-node fact "
        "pinned by the owner rulings; parallel rejoining would re-forbid the pre-authorized "
        "scale-backs, any other leaving would silently widen what C03 already loosened"
    )
    src = (S.TESTS_DIR / "test_strata_q4_rung.py").read_text()
    assert "S.CF141_SIBLING_KEYS" in src, "the q4 equality loop no longer iterates the pinned set"
    assert "Q9" in src, "the loop's exclusion of `parallel` must name the owner ruling (Q9)"
    q4 = _profile(S.PROFILE_Q4_FILE)
    primary = _profile(S.PROFILE_PRIMARY_FILE)
    assert not S.sibling_divergences(q4, primary), (
        "engine siblings diverged — that is not what C03 loosened"
    )


# --- AC3: era steps — one owner-ruled delta per dir (RED naming each chunk) ----


@helm
def test_cf141_era_steps_are_one_delta_each():
    """C03 AC3: each rung's chain steps are machine-verified adjacent deltas
    — q4's two-step {env}->{parallel} chain on top of the era-0 anchor,
    primary/strix/orca's {parallel}/shape steps, ornith unmoved. An un-landed
    step dir is RED naming its chunk (the capture is part of the chunk's
    gate); a landed step with a rider is RED naming the keys that rode it.
    The single-flag history eras (t03/u14, c07/c09) are re-verified byte-true
    by the same-walk guards in test_strata_strix.py."""
    problems = []
    for file in (S.PROFILE_PRIMARY_FILE, S.PROFILE_STRIX_FILE,
                 S.PROFILE_ORCA_FILE, S.PROFILE_Q4_FILE):
        chain = S.CF141_ERA_CHAIN[file]
        landed_prefix = S.cf141_chain_present(file)
        for idx, (era_dir, chunk) in enumerate(chain):
            if era_dir not in landed_prefix:
                problems.append(f"{file}: era step {era_dir} missing — names {chunk} "
                                "(run the §9.16 capture after that chunk's values land)")
                break
            prev_dir = chain[idx - 1][0] if idx else None
            if prev_dir is None:
                continue
            prev = json.loads((S.EVIDENCE_DIR / prev_dir / file).read_text())
            nxt = json.loads((S.EVIDENCE_DIR / era_dir / file).read_text())
            moved = S.era_delta(prev, nxt)
            want = S.cf141_step_for(file, era_dir)
            if moved != want:
                problems.append(f"{file} {prev_dir}->{era_dir}: delta {sorted(moved)}, "
                                f"step law pins {sorted(want)} — nothing may ride a ruling")
        if file == S.PROFILE_Q4_FILE and landed_prefix == [S.CF141_PRE_ERA, S.CF141_ERA_L2]:
            l2 = json.loads((S.EVIDENCE_DIR / S.CF141_ERA_L2 / file).read_text())
            anchor = json.loads((S.EVIDENCE_DIR / S.CF141_PRE_ERA / file).read_text())
            assert S.era_delta(anchor, l2) == S.CF141_ERA_STEP[S.CF141_ERA_L2], (
                "q4 era 0 -> cf141-l2 must move exactly {env} (C02 AC2)"
            )
            assert l2.get("args") == anchor.get("args"), "C02's era must not touch q4 args"
    assert not problems, "cf-141 era chain incomplete or riders found:\n" + "\n".join(problems)


def test_cf141_era_dirs_purity_and_provenance():
    """Landed cf-141 step dirs carry EXACTLY the files their step moved (the
    no-primary-in-a-re-pin-era law generalized) and every capture is
    provenance-first: per-file sha re-verified against the stored bytes, a
    stated double-capture, a date and a commit ref. Checks the PRE anchor dir
    TODAY (green) and each future dir at landing."""
    problems = []
    for era_dir, files in S.CF141_ERA_FILES.items():
        d = S.EVIDENCE_DIR / era_dir
        if not d.is_dir():
            continue
        problems += S.provenance_violations(d, files)
    assert not problems, "era-dir purity/provenance violated:\n" + "\n".join(problems)


def test_cf141_era_delta_helper_rejects_riders():
    """Non-vacuity: the delta function used by every era arm must catch the
    smuggling classes named in the chunk — a drafting step riding a conv
    value, an env step riding parallel."""
    base = {"parallel": 4, "env": {}, "args": ["--x 1"]}
    assert S.era_delta(base, base | {"env": {"A": "1"}}) == {"env"}
    assert S.era_delta(base, base | {"env": {"A": "1"}, "parallel": 8}) == {"env", "parallel"}
    assert S.era_delta(base, base | {"args": ["--x 2"]}) == {"args"}, \
        "an args value move must register as the args key"
    assert S.era_delta(base, dict(base)) == frozenset(), "an unchanged era pair must be a zero delta"


# --- AC4: budget statements derived from the render ----------------------------


@helm
def test_cf141_c03_rowh_budget_fits_derivation():
    """C03 AC4: the primary's row-H arithmetic — 46.84 arena + 9 sessions x
    262144 x 13,728 B + conv 16 + ~6 ≈ 99.0 ≤ cap 110592 (=108) ≤ cgroup
    110Gi — computed FROM THE RENDER (primary total != 99.0 while conv/
    parallel read the pre-envelope state: that is this arm's designed red,
    naming C03). Proves the number, not the prose."""
    prof = _profile(S.PROFILE_PRIMARY_FILE)
    pairs = dict(S.arg_pairs(prof))
    total = S.cf141_host_total_gib("primary", prof["parallel"],
                                   int(pairs["--conversation-cache-mib"]))
    assert abs(total - 99.0) <= 0.5, (
        f"primary budget derives {total:.1f} GiB from the render, the runbook row H says ≈99.0 "
        "— row-H (parallel 8 + conv 16384, Q9/Q10) not shipped yet: this red names C03"
    )
    cap_gib = int(pairs["--memory-limit-mib"]) / 1024
    cgroup_gib = int(S.STRATA_CGROUP_LIMIT.removesuffix("Gi"))
    assert total <= cap_gib <= cgroup_gib, (
        f"row-H chain broken: {total:.1f} ≤ {cap_gib} ≤ {cgroup_gib} must all hold "
        "(the #1601 pairing: declared inside the cgroup)"
    )


@helm
def test_cf141_q4_orca_overshoot_derivations_stand():
    """C03 AC4 / plan risk, era-scoped: the authorized-overshoot rows (q4
    123.9 > the 110Gi cgroup, orca 101.9 > its 92160 declared cap) are
    8-SLOT arithmetic — they bind the envelope render, so this arm is a
    designed red naming C03 until every flash-next rung reads 8, then it
    re-derives both figures from the rendered terms (parallel + conv read
    from the render; the arena constants are the [M-node] measurements) and
    proves the ">" statements instead of echoing them. (At the shipped
    4-slot state the same law already puts q4's worst-case terms at the
    cgroup edge — the reason the runbook calls the 8-everywhere posture a
    crash-and-scale-back ruling, not a fit.)"""
    docs = _docs()
    for file, rung, named, against in (
        (S.PROFILE_Q4_FILE, "q4", 123.9, "cgroup"),
        (S.PROFILE_ORCA_FILE, "orca", 101.9, "cap"),
    ):
        prof = S.profile_json(docs, file)
        pairs = dict(S.arg_pairs(prof))
        if prof.get("parallel") != 8:
            pytest.fail(f"cf-141 C03 not landed: the {rung} {named} overshoot row is 8-slot "
                        "arithmetic and this rung still reads the pre-C03 state")
        total = S.cf141_host_total_gib(rung, prof["parallel"], int(pairs["--conversation-cache-mib"]))
        assert abs(total - named) <= 0.5, (
            f"{rung} at 8 slots derives {total:.1f} GiB from the render, the runbook row names "
            f"{named} — the KV law or an arena constant moved without the ledger"
        )
        if against == "cgroup":
            assert total > int(S.STRATA_CGROUP_LIMIT.removesuffix("Gi")), (
                f"q4 {total:.1f} GiB is NOT over the cgroup — the authorized-overshoot statement "
                "(degrade/cgroup-kill expected, Q9) lost its arithmetic basis"
            )
        else:
            assert total > int(pairs["--memory-limit-mib"]) / 1024, (
                f"orca {total:.1f} GiB is NOT over its declared cap — the park-refusal "
                "expectation the runbook states for orca lost its arithmetic basis"
            )


# --- preservation + the scale-back mechanism -----------------------------------


@helm
def test_cf141_ornith_negative_pin_untouched():
    """The chunk's negative pin: ornith keeps `parallel: 1` and an empty env
    through every cf-141 wave (C02's arm, C03's envelope, C04's drafting all
    stop at its surface law)."""
    prof = _profile(S.PROFILE_ORNITH_FILE)
    assert prof.get("parallel") == 1, "ornith's 1-slot negative pin moved (Q9 read = flash-next only)"
    assert (prof.get("env") or {}) == {}, f"ornith env grew: {prof.get('env')!r}"


def test_cf141_scaleback_is_a_table_repin_probe():
    """C03 probe requirement, executable here: ONE rung scale-backed to 4
    without a re-pin goes red naming that rung (the path the pre-authorized
    scale-back re-greens — a ruling-table row edit plus its era capture — is
    never the sibling loop). Synthetic state, the live repo is not touched."""
    shipped = {f: v for f, (v, _c) in S.CF141_PARALLEL_RULINGS.items()}
    scaled = dict(shipped)
    scaled[S.PROFILE_Q4_FILE] = 4
    problems = S.parallel_violations(scaled, S.CF141_PARALLEL_RULINGS)
    assert len(problems) == 1 and "strata-q4.json" in problems[0], (
        f"single-rung scale-back must redden exactly the q4 row, got {problems}"
    )
