# cf-86 C05 — the gpu-ai provider catalog contract (plan
# 2026/2026-10-cf-86-feat-more-strata-models, chunks/C05.md AC1-AC5).
#
# Two arms, deliberately asymmetric:
#   PRESENCE  — the sanctioned id list (cf-86 new + hygiene + the card's
#               already-served asks) must exist with the right shape. RED
#               pre-C05: the new ids and the ornith hygiene ladder are not in
#               the catalog yet.
#   NO-PHANTOM — every catalog key must be routable: a gpu-ai render model, a
#               render alias, or one of the two explicit allow-list families
#               (workload `:tags`/`:caption` aliases; peers-routed Strata
#               arenas, whose serving authority is the peers evidence file).
#               RED pre-C05 because the 13 ruled-out REMOVED_IDS are still
#               registered; stays RED if C05 pre-registers something that does
#               not serve.
#
# The conditional Q4-default flip is NOT asserted: no user approval is recorded
# in DECISIONS, so per TEST_SPEC §5.5 the flip is a non-asserted conditional and
# the executable part is the ABSENCE guard — the pipeline-models default-route
# strings must still be the pre-cf-86 ones. If the user rules the flip in, the
# red here names the missing surface.sh re-pin (test-session property), it is
# not a license for dev to edit either file.

from __future__ import annotations

import json

import pytest

import llama_swap_testlib as L
import strata_testlib as S

OPENCODE_JSONC = S.REPO_ROOT / ".opencode" / "opencode.jsonc"
PIPELINE_MODELS_SKILL = S.REPO_ROOT / ".rulesync" / "skills" / "pipeline-models" / "SKILL.md"

CTX = 262144

# Ids cf-86 puts in the catalog: C01/C02/C06 Strata arenas (frozen ids), the
# C03/C04 llama.cpp rungs, and C06's own appended entry. C05 must not register
# anything else that does not serve (the no-phantom arm is the guard).
CF86_NEW_CATALOG_IDS = [
    S.ABL_ID, S.ORCA_INNER_ID, S.Q4_ID,
    "qwen3.8-flash-next-heretic-q4", "qwen38-heretic",
]

# Trio law covers the Strata ids only (chunk C05 AC5, plan Commands trio grep).
# The two llama.cpp family ids have no service surface BY DESIGN: they ride the
# chart-side family — the gpu-ai overlay carries matrix letters (q38her), never
# the id — C05's plan forbids it touching services/**, and C04's AC1 arm bans a
# models-layer entry for qwen38-heretic there. Registration for all five ids is
# AC1's job (CF86_NEW_CATALOG_IDS); their live-serve side is pinned by the
# C03/C04 files' gpu-ai render arms.
CF86_TRIO_IDS = [S.ABL_ID, S.ORCA_INNER_ID, S.Q4_ID]

# The card's already-served asks (C05 AC3): verification greps, no edits.
CARD_ASK_IDS = ["qwen3.8-27b-q4", "qwen3.8-27b-q6", "qwen3.8-flash-next-q4"]

# Workload aliases Pictaria/Immich route by; they are catalog entries that are
# deliberately NOT model ids. Explicit so review counts them (chunk: "keep the
# allow-list explicit").
WORKLOAD_ALIAS_SUFFIXES = (":tags", ":caption")


def _strip_jsonc_comments(text: str) -> str:
    """Comment stripper that respects string literals (URLs carry //)."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            out.append(c)
            i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\":
                    out.append(text[i:i + 2])
                    i += 2
                    continue
                out.append(text[i])
                i += 1
            out.append('"')
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            i = n if end == -1 else end + 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


@pytest.fixture(scope="module")
def catalog() -> dict:
    raw = OPENCODE_JSONC.read_text()
    try:
        doc = json.loads(_strip_jsonc_comments(raw))
    except json.JSONDecodeError as exc:
        pytest.fail(f".opencode/opencode.jsonc does not parse (plan Commands parse check): {exc}")
    models = ((doc.get("providers") or {}).get("gpu-ai") or {}).get("models")
    assert isinstance(models, dict) and models, "providers.gpu-ai.models missing or empty"
    return models


def _render_surface() -> tuple[set, set]:
    cfg = L.rendered_config("gpu-ai")
    models = set(L.all_models_of(cfg))
    aliases = {a for m in L.all_models_of(cfg).values() for a in (m.get("aliases") or [])}
    return models, aliases


def _hygiene_ids() -> list:
    """The served-but-unroutable ids, read from the render (chunk: 'read the
    exact expansion ids from the rendered catalog') — the ornith 122B ladder as
    gpu-ai enables it today, plus the gated orca flash-next rung."""
    cfg = L.rendered_config("gpu-ai")
    models = L.all_models_of(cfg)
    ornith = sorted(m for m in models if m.startswith("ornith-1.5-122b-")
                    and not L.is_echo_cmd(models[m]["cmd"]))
    assert ornith, "no enabled ornith-1.5-122b rung in the gpu-ai render — render drift, re-pin this file"
    return ornith + ["qwen3.8-flash-next-orca-q6", "qwen3.6-35b-a3b-q6"]


# --- AC1: presence + shape ---------------------------------------------------


@pytest.mark.parametrize("model_id", CF86_NEW_CATALOG_IDS)
def test_c05_new_ids_registered(catalog, model_id):
    entry = catalog.get(model_id)
    assert entry is not None, (
        f"catalog has no {model_id} — C05 not landed (or the rung it names never served)"
    )
    assert entry.get("modelID") == model_id, f"{model_id}: modelID {entry.get('modelID')!r} != key"
    assert entry.get("name"), f"{model_id}: display name missing (model-picker surface)"
    assert (entry.get("limit") or {}).get("context") == CTX, (
        f"{model_id}: limit.context {(entry.get('limit') or {}).get('context')!r} != {CTX} (trained ceiling, no rope scaling)"
    )
    assert (entry.get("capabilities") or {}).get("tools") is True, f"{model_id}: tools not true"
    assert "output" not in (entry.get("limit") or {}), (
        f"{model_id}: limit.output invented — the key exists nowhere in the gpu-ai map (chunk Notes)"
    )


def test_c05_hygiene_ids_registered(catalog):
    """C05 registers the served-but-unroutable rungs (the routing half of U5).
    Read from the render, not a literal list, so the arm cannot go stale when
    the ladder changes shape."""
    missing, wrong = [], []
    for model_id in _hygiene_ids():
        entry = catalog.get(model_id)
        if entry is None:
            missing.append(model_id)
            continue
        if entry.get("modelID") != model_id or (entry.get("limit") or {}).get("context") != CTX:
            wrong.append(f"{model_id}: {entry.get('limit')!r}")
    assert not missing, f"hygiene ids served but unroutable — C05 registers them: {missing}"
    assert not wrong, f"hygiene entry shape wrong: {wrong}"


@pytest.mark.parametrize("model_id", CARD_ASK_IDS)
def test_c05_card_asks_already_served_and_routable(catalog, model_id):
    """AC3 verification greps: the card's 27B Q4/Q6 and the Q4 default subject
    are already registered at 262144 — no edit, just proof in commands_run."""
    entry = catalog.get(model_id)
    assert entry is not None, f"card ask {model_id} missing from the catalog"
    assert (entry.get("limit") or {}).get("context") == CTX, f"{model_id}: context != {CTX}"


# --- AC2: no-phantom drift arm -----------------------------------------------


def test_c05_no_phantom_catalog_entries(catalog):
    served, aliases = _render_surface()
    peers_routed = set(S.strata_peers_evidence()["models_allowed"])
    phantoms = []
    for key in sorted(catalog):
        if key in served or key in aliases or key in peers_routed:
            continue
        if key.endswith(WORKLOAD_ALIAS_SUFFIXES):
            continue
        if key in L.REMOVED_IDS:
            phantoms.append(f"{key} (ruled out in the 2026-10-24 replan — C05 deletes it)")
        else:
            phantoms.append(f"{key} (not served by the gpu-ai render)")
    assert not phantoms, (
        "catalog names ids nothing serves — C05 AC2 (no entry for a model that "
        "does not serve): " + "; ".join(phantoms)
    )


def test_c05_removed_ids_never_return(catalog):
    """Standing contract beyond C05: the ruled 13 stay out of the provider
    catalog even after the render drop (a catalog entry with no served model is
    exactly the phantom class AC2 forbids)."""
    back = sorted(set(catalog) & set(L.REMOVED_IDS))
    assert not back, f"ruled-out ids still registered: {back}"


# --- AC5: trio surfaces for the new ids -------------------------------------


@pytest.mark.parametrize("model_id", CF86_TRIO_IDS)
def test_c05_trio_grep_three_surfaces(model_id):
    """chart values + service peers entry + provider catalog = three surfaces
    (plan Commands trio grep)."""
    chart = (S.CHART_DIR / "values.yaml").read_text()
    svc = S.SERVICE_VALUES.read_text()
    assert model_id in chart, f"{model_id} absent from charts/llama-swap/values.yaml"
    assert model_id in svc, f"{model_id} absent from services/gpu-ai/prod/values.yaml"
    assert model_id in OPENCODE_JSONC.read_text(), f"{model_id} absent from .opencode/opencode.jsonc"


def test_c05_trio_scope_is_strata_ids_only():
    """Guard for the trio-scope fault class: an id whose service surface does
    not exist by design (llama.cpp family ids ride the chart-side family; the
    overlay carries letters, and C05's plan forbids services/**) must never be
    dragged into the trio law — doing so makes it unsatisfiable and forces a
    cross-chunk AC violation. Moving an id between these lists is a law
    amendment, not a test edit."""
    assert CF86_TRIO_IDS == [S.ABL_ID, S.ORCA_INNER_ID, S.Q4_ID], (
        f"trio scope moved: {CF86_TRIO_IDS} — Strata ids only, per chunk C05 AC5"
    )
    for mid in ("qwen3.8-flash-next-heretic-q4", "qwen38-heretic"):
        assert mid in CF86_NEW_CATALOG_IDS and mid not in CF86_TRIO_IDS, (
            f"{mid} is a llama.cpp family id: registered (AC1) and served via the family, "
            "never trio-grepped on the service surface"
        )


# --- provider surface preservation ------------------------------------------


def test_c05_provider_settings_and_default_agent_untouched(catalog):
    """C05 touches the models map ONLY: the cold-start timeouts that absorb a
    Strata pin, and the default agent, are byte-stable."""
    doc = json.loads(_strip_jsonc_comments(OPENCODE_JSONC.read_text()))
    prov = doc["providers"]["gpu-ai"]
    settings = prov["settings"]
    assert settings["baseURL"] == "https://llama.spencerslab.com/v1"
    assert settings["headerTimeout"] == 7200000 and settings["chunkTimeout"] == 7200000, (
        f"timeout surface changed: {settings}"
    )
    assert doc.get("default_agent") == "plan", (
        f"default_agent = {doc.get('default_agent')!r} — C05 edits the gpu-ai models map only"
    )


# --- conditional Q4-default arm: absence guard (not executed) ----------------


def test_c05_default_route_flip_not_applied_without_a_repin():
    """No user approval for the Q4-default flip is recorded, so the pipeline-
    models default route stays `gpu-ai/qwen3.8-flash-next-strata`. If the user
    rules it in, C05 re-routes AND re-pins tests/pipeline-models/surface.sh in
    the same commit — this arm is the guard that a route flip never lands
    without the test-session re-pin."""
    text = PIPELINE_MODELS_SKILL.read_text()
    assert "gpu-ai/qwen3.8-flash-next-strata" in text, (
        "pipeline-models default route changed without the approved flip + "
        "surface.sh re-pin (test-session property) — route this to coord"
    )
    rows = [ln for ln in text.splitlines() if ln.startswith("| `gpu-ai`")]
    assert rows and any("qwen3.8-flash-next-strata" in r for r in rows), (
        f"no gpu-ai favorites row routes to the Strata default: {rows}"
    )


def test_c05_ornith_strata_id_absent_everywhere():
    """C06 Shape-B record in executable form: no `ornith-1.5-122b-strata*` id
    may exist in any live surface while the llama.cpp ornith ladder and the
    C05 hygiene entries do."""
    hits = S.live_code_grep("ornith-1.5-122b-strata")
    assert not hits, f"Shape-B ornith Strata id appeared in live surfaces: {hits}"
    served, _aliases = _render_surface()
    assert any(m.startswith("ornith-1.5-122b-") for m in served), (
        "the llama.cpp ornith ladder disappeared from the gpu-ai render — the "
        "absence-arm's counterpart is what makes today's ornith path real"
    )
