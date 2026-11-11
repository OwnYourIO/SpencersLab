# C03 blast-radius contract — everything outside the flash-next family is
# frozen against the pre-chunk baseline (ticket
# 2026/2026-10-debug-flash-next-vulkan-oom, chunks/C03.md AC2/AC3).
#
# Why a baseline fixture instead of the 2026-10-22 goldens: the goldens
# predate the flash-next/ornith catalog, so golden-era parity cannot pin the
# surface this ticket must preserve (e.g. the healthy ${moe} rungs added after
# capture). Baseline capture + provenance: tests/evidence/
# flashnext-pre-chunk-baseline/PROVENANCE.md; compared like everything here,
# on the PARSED render — helm toYaml re-wrapping is not behavior (plan Risks),
# but cmd/echo STRINGS are compared exactly, which is what "the echo path
# never resolves macros" needs.
#
# Divergence policy: FLASHNEXT_FAMILY_IDS may change (the regime fix); any
# change elsewhere is C03 stepping outside its scope. A red here on a C04-era
# legitimate change (e.g. the escalation-C1 rung, or post-C04 q4 containment)
# is routed through the test session — NOT patched away in dev/review
# (pipeline-role-test immutability).

from __future__ import annotations

import pytest

import llama_swap_testlib as L

FN = set(L.FLASHNEXT_FAMILY_IDS)
# cf-86 sanctioned roster/matrix growth (DECISIONS "cf-86 model/source
# decisions"): exactly these ids/letters may join, nothing else.
CF86_IDS = set(L.CF86_NEW_IDS)
CF86_VARS = dict(L.CF86_MATRIX_VARS)

_ok, _reason = L.helm_ready()


def _skip_without_helm() -> None:
    if not _ok:
        pytest.skip(_reason)


def _diff_entries(base: dict, cur: dict, prefix: str) -> list[str]:
    out = []
    for key in sorted(set(base) | set(cur)):
        b, c = base.get(key), cur.get(key)
        if b == c:
            continue
        if isinstance(b, dict) and isinstance(c, dict):
            out += _diff_entries(b, c, f"{prefix}{key}.")
        else:
            out.append(f"{prefix}{key}: {b!r} -> {c!r}")
    return out


# --- AC2: ${moe} is byte-frozen and no macro addition leaks onto healthy rungs


def test_c03_ac2_moe_macro_byte_frozen():
    _skip_without_helm()
    base = L.baseline_config("gpu-ai")["macros"]
    cur = L.rendered_config("gpu-ai")["macros"]
    removed = sorted(set(base) - set(cur))
    modified = sorted(k for k in set(base) & set(cur) if base[k] != cur[k])
    assert not removed and not modified, (
        f"macros changed outside C03's scope: removed={removed}, modified={modified}. "
        "The blast-radius rule (DECISIONS 2026-10-26): ${moe} and every existing "
        "macro stay untouched — they carry the q35/q36/ornith/vl rungs that load fine today."
    )
    # A NEW family-scoped macro is C03-sanctioned ("a new dedicated macro
    # referenced from the family") but must be referenced by flash-next cmds
    # only — otherwise it silently joins the shared composition surface.
    added = set(cur) - set(base)
    for name in sorted(added):
        users = [mid for mid, m in L.all_models_of(L.rendered_config("gpu-ai")).items()
                 if f"${{{name}}}" in m.get("cmd", "")]
        assert users and set(users) <= FN, (
            f"new macro ${{{name}}} referenced outside the flash-next family: {sorted(set(users) - FN)}"
        )


# --- AC2: the whole non-flash-next models map is identical


def test_c03_ac2_non_flashnext_models_identical_gpu_ai():
    _skip_without_helm()
    base_models = L.all_models_of(L.baseline_config("gpu-ai"))
    cur_models = L.all_models_of(L.rendered_config("gpu-ai"))
    added = sorted(set(cur_models) - set(base_models))
    # cf-86 (DECISIONS "cf-86 model/source decisions") grows the roster by
    # exactly the two heretic rungs; anything else added is scope creep.
    strays = sorted(set(added) - set(L.CF86_NEW_IDS))
    assert not strays, (
        f"gpu-ai render gained model ids {strays} — C03 scope is the existing flash-next "
        "family only (an escalation-C1 rung would be a DECISIONS-recorded, test-session-"
        "rebaselined change, not a silent add)"
    )
    for mid in sorted(set(added) & set(L.CF86_NEW_IDS)):
        assert not L.is_echo_cmd(cur_models[mid]["cmd"]), (
            f"gpu-ai/{mid}: the cf-86 rung is ENABLED on gpu-ai but rendered as an echo"
        )
    diffs = []
    for mid in sorted(set(base_models) & set(cur_models) - FN):
        diffs += _diff_entries(base_models[mid], cur_models[mid], f"{mid}.")
    assert not diffs, (
        "gpu-ai: non-flash-next model fields diverged from the pre-chunk baseline "
        "(AC2 'zero changes outside the flash-next family IDs' — ${moe} consumers "
        "qwen3.6-35b-a3b*/qwen36*/ornith-1.5-*/qwen3-vl-30b* must render identical):\n"
        + "\n".join(diffs[:20])
    )


# --- AC2: catalog-wide config surface other than models/macros is identical


# cf-77 peers carve-out (user ruling 2026-10-28; run cf-77-feat-strata-
# llama-swap, cross-ticket escalation routed through the test session). The
# Q4-mandated gpu-ai `peers:` entry IS a top-level delta this 2026-10-26
# baseline predates — sanctioned, so it gets an EXACT exception instead of a
# baseline re-capture (the fixture stays byte-intact; history keeps the delta
# visible). Tolerated shape, pinned to evidence/strata-peers-expected.yaml as
# the single source for the strata entry: peers absent from the base;
# strata == {proxy, models, timeouts} with the evidence's proxy/timeouts and
# models equal to one of the evidence's sanctioned states. cf-105 C03 (2026-
# 11-05) grew the sanctioned delta by the vllm peer; cf-143 C01+C04 (2026-
# 11-11) re-pinned it: the vllm peer is DISABLED (Q3 commented-out — the wave
# set retires {strata, vllm}) and the radiance peer joins ADDITIVE beside
# strata (Q5), pinned to its own sibling evidence file radiance-peers-
# expected.yaml (D13: the per-key authority pattern), read live and never
# hand-copied. Anything else — another top-level key, a third peer beyond the
# sanctioned {strata} / {strata, radiance} waves, an apiKey on either entry, a
# byte off strata proxy/timeouts, or a models list outside the sanctioned
# states — stays RED.
# The helper READS BOTH EVIDENCE FILES LIVE, so the run-2 re-author of the
# strata file (proxy URL flipping from gpu-ai-strata to the consolidated
# gpu-ai-llama-swap-strata name) re-aligns the sanctioned state automatically:
# between the re-author and r2-C03 flipping the service values, this test was
# RED BY DESIGN — the red named run-2's C03, never a license to touch the
# evidence or this guard. C05 grows the models list by appending the strix
# id: that flows through the evidence file's models_allowed state, and the
# evidence update is TEST-SESSION property — dev routes any peers-shape
# change via RESULT/coord, never edits the evidence itself.


_STRATA_PEERS_EVIDENCE = L.TESTS_DIR / "evidence" / "strata-peers-expected.yaml"


def _hooks_scoped(h: dict) -> dict:
    """hooks.on_startup.preload, off-scope for every BASELINE diff in this file.
    The value is pinned positively instead (llama_swap_testlib.C04_PRELOAD_PINNED,
    asserted by test_new_roster and both heretic arms), and the list has moved
    three times since this capture — 2026-10-20 dropped the MoE q8, 2026-10-29
    dropped the dense q8, 2026-11-02 dropped the embedding sidecar — so
    re-diffing it against a frozen baseline would make the baseline veto the very
    rulings recorded on its own header. The scope is the ONE key: a new hook
    type or an on_startup.profile stays strict here. Declared blind spot: a
    hooks block absent on one side versus a preload-only block on the other both
    normalize to {}, so that shape is invisible to this diff — it is covered by
    test_config_schema's hooks-is-a-dict arm and the C04 preload pins, not here.
    Scoping also keeps the peers carve-out earnable (see _cf77_peers_carved)."""
    out = {k: (dict(v) if isinstance(v, dict) else v) for k, v in (h or {}).items()}
    st = out.get("on_startup")
    if isinstance(st, dict):
        st = dict(st)
        st.pop("preload", None)
        out["on_startup"] = st
    return out


def _cf77_peers_carved(base: dict, cur: dict) -> bool:
    """True iff the ONLY top-level base→cur differences are the pinned peers
    delta (cf-77's strata evidence shape + the cf-143 sanctioned wave —
    {strata} after C01's vllm disable, {strata, radiance} once C04 lands,
    the radiance entry deep-equal to its own evidence file) plus (from cf-86
    on) matrix growth that is itself inside the sanctioned additive shape
    (then callers carve `peers` and stay strict on everything else).
    Exactness lives here: key sets and values compared against the evidence
    files, never against a copy of either's contents."""
    import yaml

    if "peers" in base or base.get("peers") is not None:
        return False
    if cur.get("peers") is None:
        return False
    # `hooks` is compared through _hooks_scoped: a sanctioned preload change must
    # not revoke the peers carve-out, because revoking it turns an authorised
    # preload edit into a bogus "unauthorised peers delta" red.
    b_cmp, c_cmp = dict(base), dict(cur)
    if "hooks" in b_cmp or "hooks" in c_cmp:
        b_cmp["hooks"], c_cmp["hooks"] = _hooks_scoped(b_cmp.get("hooks")), _hooks_scoped(c_cmp.get("hooks"))
    others = [k for k in (set(b_cmp) | set(c_cmp)) - {"models", "macros", "peers", "matrix"}
              if b_cmp.get(k) != c_cmp.get(k)]
    if others:
        return False
    # matrix joins the carve ONLY while the cf-86 guard below reports nothing:
    # the sanctioned vars/sets growth and the peers wave are the same change
    # (a new rung needs both a matrix letter and a peers route), and any matrix
    # edit outside the pinned additive shape still refuses the carve, so the
    # peers delta goes red together with it.
    if base.get("matrix") != cur.get("matrix") and _cf86_matrix_violations(base, cur):
        return False
    evidence = yaml.safe_load(_STRATA_PEERS_EVIDENCE.read_text())["strata"]
    peers = cur["peers"]
    # cf-143 C01+C04 wave law (test-session re-pin of the cf-105 vllm-era
    # check — the peers delta the carve sanctions is {strata} after C01's
    # vllm comment-out, {strata, radiance} once C04's additive join lands;
    # a live vllm key or any other third peer REFUSES the carve, so the
    # era violation goes red with the rest of the surface it guards).
    if not isinstance(peers, dict) or set(peers) not in ({"strata"}, {"strata", "radiance"}):
        return False
    entry = peers["strata"]
    if not isinstance(entry, dict) or set(entry) != {"proxy", "models", "timeouts"}:
        return False
    if entry["proxy"] != evidence["proxy"] or entry["timeouts"] != evidence["timeouts"]:
        return False
    # cf-86 wave table: the models list must equal one sanctioned intermediate
    # or final state exactly (ordered), not merely a subset of the final five.
    if entry["models"] not in evidence["models_states"]:
        return False
    # cf-143 C04: the radiance peer is pinned to ITS OWN evidence file
    # (DECISIONS D13 per-key authority), read live — never a copy, so a
    # test-session re-author re-aligns this carve automatically. The exact
    # sanctioned block includes the filters floor (keyless, no apiKey).
    if "radiance" in peers:
        ev = L.radiance_peers_evidence()
        if peers["radiance"] != L.expected_radiance_peer(ev, peers["radiance"].get("models")):
            return False
    return True


def _cf86_matrix_violations(base: dict, cur: dict) -> list[str]:
    """cf-86 sanctioned matrix growth (plan C03/C04): the two heretic rungs
    join vars and the enabled sets. Everything already in the baseline must
    survive — vars byte-equal, and every baseline DNF combo still present —
    and each NEW combo must actually pair a cf-86 rung (a re-pairing of
    existing rungs changes co-residency behavior for models this ticket
    doesn't own). Combo-level comparison via the strata testlib's DNF parser
    keeps this formatting-independent (helm/values re-wrap is not behavior)."""
    import strata_testlib as S

    out = []
    b_vars, c_vars = (base.get("matrix") or {}).get("vars") or {}, (cur.get("matrix") or {}).get("vars") or {}
    for name, val in sorted(b_vars.items()):
        if c_vars.get(name) != val:
            out.append(f"matrix.vars.{name}: {val!r} -> {c_vars.get(name)!r}")
    new_vars = sorted(set(c_vars) - set(b_vars))
    for name in new_vars:
        if name not in CF86_VARS:
            out.append(f"matrix.vars.{name} = {c_vars[name]!r}: not a cf-86 pinned letter")
        elif c_vars[name] != CF86_VARS[name]:
            out.append(f"matrix.vars.{name} = {c_vars[name]!r} != pinned {CF86_VARS[name]!r}")
    new_ids = set(CF86_IDS)
    base_exp, cur_exp = S.matrix_expansions(base), S.matrix_expansions(cur)
    for name in sorted(set(base_exp) | set(cur_exp)):
        b_combos, c_combos = base_exp.get(name, []), cur_exp.get(name, [])
        if any(b not in c_combos for b in b_combos):
            lost = sorted(", ".join(sorted(c)) for c in b_combos if c not in c_combos)
            out.append(f"matrix.sets.{name}: baseline combos lost: {lost}")
        for combo in c_combos:
            if combo in b_combos:
                continue
            if not (combo & new_ids):
                out.append(f"matrix.sets.{name}: new combo {sorted(combo)} pairs no cf-86 rung")
    return out


def test_c03_ac2_matrix_hooks_scalars_identical():
    _skip_without_helm()
    base = L.baseline_config("gpu-ai")
    cur = L.rendered_config("gpu-ai")
    carved = _cf77_peers_carved(base, cur)
    diffs = []
    for key in sorted((set(base) | set(cur)) - {"models", "macros", "matrix"} -
                      ({"peers"} if carved else set())):
        b, c = base.get(key), cur.get(key)
        if key == "hooks":
            b, c = _hooks_scoped(b), _hooks_scoped(c)
        if b != c:
            diffs.append(f"{key}: {b!r} -> {c!r}")
    diffs += _cf86_matrix_violations(base, cur)
    if not carved and cur.get("peers") != base.get("peers"):
        diffs.append("peers delta present but NOT the pinned shape (cf-77 strata "
                     "evidence + cf-143 sanctioned {strata}/{strata, radiance} waves — "
                     "see the carve-out comment; peers-shape changes route through the "
                     "test session)")
    assert not diffs, (
        "gpu-ai: non-models config surface diverged (matrix sets/vars guard the solo-"
        "matrix membership and no-preload rules C03 must keep; hooks.preload and the "
        "scalars are off-scope; cf-86 matrix growth allowed only in the pinned additive "
        "shape):\n" + "\n".join(diffs)
    )


# --- AC3: the gpu render is preserved; flash-next stays macro-free echo


def test_c03_ac3_gpu_render_preserved():
    """AC3 'byte-identical to pre-chunk', enforced structurally on the parsed
    config + exactly on every cmd STRING. Two documented allowances: the derived
    display fields (name/description) of the five gpu-echoed flash-next ids —
    removing the family draft/spec legitimately drops the ', MTP' name marker
    (same display-excision lineage as ratified amendment P, TEST_SPEC §7) — and
    matrix.vars gaining the cf-86 letters, which the shared chart catalog forces
    onto every cluster. The vars allowance is the confined one
    (llama_swap_testlib.cf86_matrix_growth_violations): pinned letters only, and
    no gpu combo changes. Everything else, echo cmds included, is strict."""
    _skip_without_helm()
    base = L.baseline_config("gpu")
    cur = L.rendered_config("gpu")
    display_exempt = {"name", "description"}
    diffs = []
    for key in sorted((set(base) | set(cur)) - {"models", "matrix"}):
        if base.get(key) != cur.get(key):
            diffs.append(f"{key}: {base.get(key)!r} -> {cur.get(key)!r}")
    diffs += L.cf86_matrix_growth_violations(base, cur)
    base_models = L.all_models_of(base)
    cur_models = L.all_models_of(cur)
    gained = sorted(set(cur_models) - set(base_models))
    lost = sorted(set(base_models) - set(cur_models))
    # cf-86: the two heretic rungs are gpu-ai-only, so on gpu they must arrive
    # as fail-fast echoes (P5 superset law) — nothing else may join or leave.
    if set(gained) - set(CF86_IDS) or lost:
        diffs.append(f"gpu roster changed: gained {gained}, lost {lost}")
    for mid in set(gained) & set(CF86_IDS):
        if not L.is_echo_cmd(cur_models[mid]["cmd"]):
            diffs.append(f"gpu/{mid}: cf-86 rung must be a fail-fast echo on gpu: "
                         f"{cur_models[mid]['cmd']!r}")
    for mid in sorted(base_models):
        b, c = base_models[mid], cur_models[mid]
        if mid in FN:
            b = {k: v for k, v in b.items() if k not in display_exempt}
            c = {k: v for k, v in c.items() if k not in display_exempt}
        if b != c:
            diffs.append(mid)
    assert not diffs, (
        "gpu render diverged from the pre-chunk baseline outside the exempted "
        "flash-next display fields (flash-next echoes there — a gpu change means "
        "the regime edit leaked off-cluster):\n" + "\n".join(diffs[:20])
    )


def test_c03_ac3_gpu_flashnext_echoes_stay_macro_free():
    """The echo path must keep never resolving macros: each flash-next entry
    on gpu stays an exact-string echo with no ${...} reference and no
    llama.cpp flag tokens — the specific regression AC3's parenthetical names."""
    _skip_without_helm()
    base_models = L.all_models_of(L.baseline_config("gpu"))
    cur_models = L.all_models_of(L.rendered_config("gpu"))
    for mid in sorted(FN):
        cmd = cur_models[mid]["cmd"]
        assert L.is_echo_cmd(cmd), f"gpu/{mid}: echo shape lost: {cmd!r}"
        assert cmd == base_models[mid]["cmd"], f"gpu/{mid}: echo string mutated: {cmd!r}"
        assert "${" not in cmd and "--load-mode" not in cmd and "--fit" not in cmd, (
            f"gpu/{mid}: echo resolved flag or macro content — use:/flags: legs "
            "must not become resolvable on the gpu cluster (AC3)"
        )
