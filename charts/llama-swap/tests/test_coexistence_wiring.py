# cf-143 C04 — the coexistence wiring contract (chunks/C04.md Tests, bullet 3;
# Q5 "Strata shouldn't be disabled yet" made executable end to end).
#
# Two halves, one file:
#  * STRATA AS TODAY — the strata render legs (controller Deployment,
#    Service, config/profile ConfigMaps) against a THREE-LAYER truth: the
#    pre-ticket baseline evidence/cf143-pre-ticket-strata/ (captured at the
#    cf-143 clean tip) stays FROZEN history and the divergence from it is
#    bounded by the C04 (D17+D26) four-leaf budget — claims, park, memory
#    mirror, nothing else; the post-C04 evidence
#    evidence/c04-post-ticket-strata/ byte-pins today's sanctioned shape so
#    any FUTURE strata move reddens at full sensitivity instead of riding
#    the budget; and the cf-144 P15/P16 strix-ROCR carve (see the helper)
#    normalizes its one receipted line on both sides of every comparison.
#    Plus the service-level parse pins:
#    the seven-flag strata enable-set still enabled:true, the matrix/preload
#    blocks un-disturbed.
#  * RADIANCE LANDS BESIDE IT — the charts.radiance appset entry renders
#    from the internal charts/ shape (name gpu-ai-radiance derived from the
#    base appset template — the template read is the evidence, same shape as
#    C07's amd-gpu n1 leg), the top-level radiance: service block carries
#    scalars ONLY, and neither engine disables the other (no radiance rung
#    joins the outer matrix; no strata flag flips).
#
# Red state at handoff (designed): the strata baseline + enable-set legs are
# GREEN NOW (they must STAY green — a red there names a chunk that touched
# strata, which review rejects); the radiance-entry legs went green with
# C04's landed values edit.
#
# Run with the suite (per-directory): python3 -m pytest charts/llama-swap/tests -v

from __future__ import annotations

import copy
import re
import sys

import pytest
import yaml

import llama_swap_testlib as L
import strata_testlib as S

# cross-chart import idiom test_c04_strata_claim.py / test_cf143_naming_flip.py use
_amd_tests = L.REPO_ROOT / "charts" / "amd-gpu" / "tests"
if str(_amd_tests) not in sys.path:
    sys.path.insert(0, str(_amd_tests))
import amd_gpu_testlib as A  # noqa: E402

_ok, _ok_reason = L.helm_ready()
helm_mark = pytest.mark.skipif(not _ok, reason=_ok_reason)

BASELINE = L.TESTS_DIR / "evidence" / "cf143-pre-ticket-strata" / "gpu-ai.strata-docs.yaml"
BASE_APPSET = L.REPO_ROOT / "charts" / "base" / "templates" / "appset-charts.yaml"
CUSTOM_VALUES = L.REPO_ROOT / "custom-values" / "gpu-ai" / "prod-values.yaml"


def _svc() -> dict:
    return yaml.safe_load(S.SERVICE_VALUES.read_text())


def _strata_docs(docs) -> list:
    wanted = {("Deployment", S.STRATA_OBJECT_NAME), ("Service", S.STRATA_OBJECT_NAME),
              ("ConfigMap", S.CM_CONFIG), ("ConfigMap", S.CM_PROFILE)}
    picked = [d for d in docs if (d.get("kind"), (d.get("metadata") or {}).get("name")) in wanted]
    found = {(d["kind"], (d.get("metadata") or {}).get("name")) for d in picked}
    assert found == wanted, f"strata render legs missing from the live render: {sorted(wanted - found)}"
    return sorted(picked, key=lambda d: (d["kind"], d["metadata"]["name"]))


# --- half 1: strata renders AS TODAY ------------------------------------------


_C144_ROCR_SENTINEL = "ROCR_VISIBLE_DEVICES=__CF144_C03_CARVED__"


def _c144_carve_strix_rocr(doc: dict, side: str) -> dict:
    """cf-144 C03 sanctioned-divergence normalizer (DECISIONS P15/P16).

    Replaces, inside the strata-config ConfigMap's config.yaml string, the
    SINGLE ``- ROCR_VISIBLE_DEVICES=<idx>`` env item of the STRIX model block
    (``qwen3.8-flash-next-strata-strix:``) with a sentinel, and returns the
    doc copy. Identification is model-key + ROCR-token scoped — a blanket
    env-line or whole-strix-model exclusion would let other drift through,
    which is why the helper FAILS LOUD instead of no-op'ing when the block or
    the line shape is not found exactly once on EITHER side: zero hits means
    the oracle/render layout moved under the carve's feet (re-pin the helper,
    don't widen it), >1 hits means a second ROCr line appeared inside strix —
    exactly the unauthorized class the carve must not swallow."""
    data = doc.get("data") or {}
    cfg = data.get("config.yaml")
    assert isinstance(cfg, str), f"cf-144 carve/{side}: strata-config carries no config.yaml string"
    lines = cfg.split("\n")
    starts = [i for i, ln in enumerate(lines)
              if re.match(r'^  "?' + re.escape(S.STRIX_ID) + r'"?:\s*$', ln)]
    assert len(starts) == 1, (
        f"cf-144 carve/{side}: strix model key found {len(starts)}× at 2-indent in the "
        "config.yaml string, want exactly 1 — the model-block layout moved; re-pin THIS "
        "helper against the render shape, never widen the carve"
    )
    start = starts[0]
    end = next((i for i in range(start + 1, len(lines)) if re.match(r"^(?:\S|  [^ \t-])", lines[i])),
               len(lines))
    hits = [i for i in range(start, end)
            if re.match(r"^\s+- ROCR_VISIBLE_DEVICES=\S+$", lines[i])]
    assert len(hits) == 1, (
        f"cf-144 carve/{side}: strix model block carries {len(hits)} ROCR_VISIBLE_DEVICES "
        "env lines, want exactly 1 — the sanctioned divergence is that single line; a "
        "missing/duplicated shape here is layout drift, not a license to blanket-exclude"
    )
    lines[hits[0]] = f"    - {_C144_ROCR_SENTINEL}"
    return {**doc, "data": {**data, "config.yaml": "\n".join(lines)}}


def test_baseline_fixture_present():
    assert BASELINE.is_file(), (
        f"cf-143 C04: pre-ticket strata baseline {BASELINE} missing — fixture breakage, "
        "not a code red (test-session property; cf-143 test session, TEST_SPEC §12)"
    )


# --- C04 bounded delta (D17 + D26): the one-time divergence from the frozen
# pre-ticket baseline, encoded the way C03's delta budget is (DECISIONS D35
# doctrine): enumerated ruled leaves + planted-drift teeth, never a blanket
# "ignore strata resources" carve. ----------------------------------------------------------------


C04_POST_EVIDENCE = L.TESTS_DIR / "evidence" / "c04-post-ticket-strata" / "gpu-ai.strata-docs.yaml"

# The four leaves C04 (D17 claim + D26 park) moves against the pre-ticket
# baseline, in this file's leaf grammar (D17's shorthand "the claim +1 in
# requests/limits" and the D26 park; the memory leaf is the requests side of
# the cgroup ceiling riding INTO requests — the number is pre-ticket chart
# truth, limits.memory 110Gi, see the verdict note on the leg).
C04_DEPLOY_BUDGET = frozenset({
    "$.spec.replicas",
    f'$.spec.template.spec.containers[0].resources.requests["{A.R9700_CLAIM}"]',
    f'$.spec.template.spec.containers[0].resources.limits["{A.R9700_CLAIM}"]',
    "$.spec.template.spec.containers[0].resources.requests.memory",
})

# Each ruled leaf must carry its RULED value, not merely "have moved" (the
# both-arms law from C03: an absent claim is as wrong as a second claim).
C04_RULED_VALUES = {
    "$.spec.replicas": "0",
    f'$.spec.template.spec.containers[0].resources.requests["{A.R9700_CLAIM}"]': "1",
    f'$.spec.template.spec.containers[0].resources.limits["{A.R9700_CLAIM}"]': "1",
    "$.spec.template.spec.containers[0].resources.requests.memory": S.STRATA_CGROUP_LIMIT,
}


def _join(path: str, key) -> str:
    return f"{path}.{key}" if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", str(key)) \
        else f'{path}["{key}"]'


def _leaf_paths(node, path: str) -> set:
    if isinstance(node, dict) and node:
        return {p for k, v in node.items() for p in _leaf_paths(v, _join(path, k))}
    return {path}


def _leaf_diff(a, b, path: str = "$") -> set:
    """Leaf paths where two docs differ. Same list law as the C03 delta engine
    (charts/radiance/tests/test_c03_generic_shell.py): length change or scalar
    elements are OPAQUE at the list path; equal-length dict lists descend by
    index, so a swap inside a listed container stays nameable drift."""
    if isinstance(a, dict) and isinstance(b, dict):
        out = set()
        for k in sorted(set(a) | set(b)):
            p = _join(path, k)
            if k not in a:
                out |= _leaf_paths(b[k], p)
            elif k not in b:
                out |= _leaf_paths(a[k], p)
            else:
                out |= _leaf_diff(a[k], b[k], p)
        return out
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return {path}
        if a and all(isinstance(x, dict) for x in a) and all(isinstance(y, dict) for y in b):
            return {p for i, (x, y) in enumerate(zip(a, b)) for p in _leaf_diff(x, y, f"{path}[{i}]")}
        return {path} if a != b else set()
    return {path} if a != b else set()


def _docs_by_id(docs) -> dict:
    return {(d["kind"], (d.get("metadata") or {}).get("name")): d for d in docs}


def _ruled_value_checks(dep: dict) -> dict:
    """path -> live str-value for each budget leaf (the missing/value arm: the
    ruled moves must have LANDED with the ruled values)."""
    ci = dep["spec"]["template"]["spec"]["containers"][0]
    res = ci.get("resources") or {}
    req, lim = res.get("requests") or {}, res.get("limits") or {}
    return {
        "$.spec.replicas": str(dep["spec"].get("replicas")),
        f'$.spec.template.spec.containers[0].resources.requests["{A.R9700_CLAIM}"]': str(req.get(A.R9700_CLAIM)),
        f'$.spec.template.spec.containers[0].resources.limits["{A.R9700_CLAIM}"]': str(lim.get(A.R9700_CLAIM)),
        "$.spec.template.spec.containers[0].resources.requests.memory": str(req.get("memory")),
    }


@helm_mark
def test_strata_render_moves_from_pre_ticket_baseline_only_on_the_ruled_leaves():
    """C04 AC1/AC4 vs the FROZEN pre-ticket baseline (re-pinned from cf-143's
    whole-render byte-equality by D17 + D26 — the strata surface legitimately
    diverges now, and the divergence is the enumerated FOUR-LEAF budget: the
    claim pair positive-ADDED at count 1 (D17), replicas 1→0 (D26 K1 park),
    and requests.memory 64Gi→110Gi (the cgroup ceiling, whose number is
    PRE-TICKET chart truth: the baseline's own limits.memory is 110Gi — C04
    mirrors requests TO the existing ceiling, it invents nothing; the
    consequence, strata+fn being RAM-unschedulable together (110+110 >
    125.08 node RAM), is the never-co-exist law enforced a second time below
    the GPU claim's 1+2 > 2, and the only lawful bring-up (fn→0 first, C06
    runbook) fits with room: strata 110Gi + the always-on main pod's 4.125Gi
    requests on the same node). BOTH arms bind (C03 doctrine): NOTHING
    outside the budget may differ on ANY of the four docs (the two ConfigMaps
    and the Service carry ZERO budget — the cf-144 strix-ROCR carve stays
    applied to both sides for the config ConfigMap), and each ruled leaf must
    carry its ruled VALUE, not merely have moved. Dev's proof
    /tmp/opencode/c04/byte-equal-delta-proof.txt measured exactly these four
    leaves at the same paths."""
    assert BASELINE.is_file(), f"cf-143 C04: baseline fixture {BASELINE} missing"
    baseline = yaml.safe_load(BASELINE.read_text())
    assert isinstance(baseline, list), f"cf-143 C04: baseline fixture is {type(baseline).__name__}, want a list of docs"
    docs, _raw = S.render_service_overlay("gpu-ai")
    live = _docs_by_id(_strata_docs(docs))
    base = _docs_by_id(baseline)
    assert set(live) == set(base), f"strata doc set changed: {sorted(set(live) ^ set(base))}"
    unauthorized = []
    for doc_id in sorted(base):
        b, c = base[doc_id], live[doc_id]
        if doc_id == ("ConfigMap", S.CM_CONFIG):
            b = _c144_carve_strix_rocr(b, "baseline-oracle")
            c = _c144_carve_strix_rocr(c, "live-render")
        budget = C04_DEPLOY_BUDGET if doc_id[0] == "Deployment" else frozenset()
        unauthorized += [f"{doc_id[1]}:{p}" for p in sorted(_leaf_diff(b, c) - budget)]
    assert not unauthorized, (
        f"C04/D17+D26: strata render moved OUTSIDE the four-leaf budget: {unauthorized}. "
        "The cf-143 waves are ADDITIVE and C04 rules exactly claims+park+memory-mirror; a "
        "fifth leaf here names an unauthorized strata change (review rejects outright). The "
        "cf-144 P15/P16 carve normalizes ONLY the strix ROCR_VISIBLE_DEVICES line inside "
        "strata-config (both sides sentinelled before this compare)"
    )
    dep = live[("Deployment", S.STRATA_OBJECT_NAME)]
    mismatches = {p: (C04_RULED_VALUES[p], got) for p, got in _ruled_value_checks(dep).items()
                  if got != C04_RULED_VALUES[p]}
    assert not mismatches, (
        f"C04/D17+D26: ruled leaves not landed at ruled values (want/ got): {mismatches} — "
        "the budget binds BOTH ways: the claim pair at 1, the park at 0, requests.memory at "
        f"the {S.STRATA_CGROUP_LIMIT} cgroup ceiling (designed-red naming C04 until it lands)"
    )


@helm_mark
def test_strata_render_byte_equal_to_post_c04_evidence():
    """The FORWARD byte-pin: the live strata docs equal the checked-in
    post-C04 evidence exactly (strix-ROCR carve applied to both sides). The
    budget absorbs ONE sanctioned divergence — the one C04 ruled — and this
    leg makes that absorption one-time: from C04 forward the strata surface
    is byte-pinned again (cf-143's Q5 doctrine continued against post-C04
    truth), so a future move reddens at full sensitivity instead of hiding
    inside the budget's arms. Re-pinning the evidence is a ruling-and-retest
    act, never a silent refresh."""
    assert C04_POST_EVIDENCE.is_file(), (
        f"C04: post-ticket strata evidence {C04_POST_EVIDENCE} missing — test-session "
        "artifact (chunks/C04.md Tests flip-list); re-capture per the provenance header in "
        "the evidence file itself, never hand-edit"
    )
    pinned = _docs_by_id(yaml.safe_load(C04_POST_EVIDENCE.read_text()))
    docs, _raw = S.render_service_overlay("gpu-ai")
    live = _docs_by_id(_strata_docs(docs))
    assert set(pinned) == set(live), f"strata doc set moved since C04: {sorted(set(pinned) ^ set(live))}"
    for doc_id in sorted(pinned):
        b, c = pinned[doc_id], live[doc_id]
        if doc_id == ("ConfigMap", S.CM_CONFIG):
            b = _c144_carve_strix_rocr(b, "evidence-side")
            c = _c144_carve_strix_rocr(c, "live-render")
        assert b == c, (
            f"strata {doc_id[0]}/{doc_id[1]} diverged from the post-C04 evidence — every strata "
            "surface move after C04 needs a ruling, a budget/legs update AND an evidence re-pin "
            "in the SAME test wave; a red here with no fresh ruling is unauthorized drift"
        )


@helm_mark
def test_c04_strata_budget_catches_planted_drift():
    """Teeth of the budget leg (the D31 half-tripwire class): plant FOUR
    drifts on synthetic copies of the live render — an image-tag swap INSIDE
    the listed container, a profile-ConfigMap value append, dropping the
    limits.memory key, and pulling the requests claim — and show the engine
    + arms catch each: the first three as unauthorized leaves, the fourth by
    the ruled-value arm (removal erases the diff, exactly the hole both arms
    close). Green always; this leg proves the gate is live."""
    docs, _raw = S.render_service_overlay("gpu-ai")
    base = _docs_by_id(yaml.safe_load(BASELINE.read_text()))
    clean = _docs_by_id(_strata_docs(docs))

    def delta_of(live: dict):
        bad = []
        for doc_id in base:
            b, c = base[doc_id], live[doc_id]
            if doc_id == ("ConfigMap", S.CM_CONFIG):
                b = _c144_carve_strix_rocr(b, "teeth-baseline")
                c = _c144_carve_strix_rocr(c, "teeth-live")
            budget = C04_DEPLOY_BUDGET if doc_id[0] == "Deployment" else frozenset()
            bad += _leaf_diff(b, c) - budget
        return bad

    dep_id = ("Deployment", S.STRATA_OBJECT_NAME)

    p = {k: copy.deepcopy(v) for k, v in clean.items()}
    dci = p[dep_id]["spec"]["template"]["spec"]["containers"][0]
    dci["image"] = str(dci.get("image", "")).rsplit(":", 1)[0] + ":planted"
    assert "$.spec.template.spec.containers[0].image" in delta_of(p), \
        "C04 teeth: planted image swap inside the ruled containers list passed as authorized"

    p = {k: copy.deepcopy(v) for k, v in clean.items()}
    cm_id = ("ConfigMap", S.CM_PROFILE)
    key = sorted(p[cm_id]["data"])[0]
    p[cm_id]["data"][key] += "\n# planted"
    assert _join("$.data", key) in delta_of(p), \
        "C04 teeth: planted profile-ConfigMap drift passed on the ZERO-budget side"

    p = {k: copy.deepcopy(v) for k, v in clean.items()}
    del p[dep_id]["spec"]["template"]["spec"]["containers"][0]["resources"]["limits"]["memory"]
    assert "$.spec.template.spec.containers[0].resources.limits.memory" in delta_of(p), \
        "C04 teeth: dropping the cgroup ceiling key erased its own diff — the one-sided leaf law is dead"

    p = {k: copy.deepcopy(v) for k, v in clean.items()}
    del p[dep_id]["spec"]["template"]["spec"]["containers"][0]["resources"]["requests"][A.R9700_CLAIM]
    bad = {p2: (C04_RULED_VALUES[p2], got) for p2, got in _ruled_value_checks(p[dep_id]).items()
           if got != C04_RULED_VALUES[p2]}
    assert f'$.spec.template.spec.containers[0].resources.requests["{A.R9700_CLAIM}"]' in bad, (
        "C04 teeth: a PULLED requests-claim left no diff against the claim-less baseline and "
        "the ruled-value arm did not catch it — the both-arms law is half-wired"
    )


def test_strata_enable_set_unchanged_seven_flags():
    """The seven default-OFF flags stay enabled:true in the service values —
    parse-compare against the checked expectation (the FLAG_PATHS table from
    strata's own consolidation law), no render needed."""
    block = _svc()["llama-swap"]

    def dig(doc, path: str):
        cur = doc
        for part in path.split("."):
            if not isinstance(cur, dict) or part not in cur:
                return None
            cur = cur[part]
        return cur

    flipped = []
    for fp in S.FLAG_PATHS:
        # FLAG_PATHS spell the chart-root key path (app-template.-prefixed) —
        # the service block nests the same tree under llama-swap:, so the
        # dig starts at llama-swap and keeps the full path.
        if dig(block, fp) is not True:
            flipped.append(fp)
    assert not flipped, (
        f"cf-143 C04/Q5: strata enable flags no longer true in the service values: {flipped} — "
        "the enable-set (121-197) is byte-stable through the radiance join"
    )


# --- half 2: radiance lands beside it ------------------------------------------


def test_radiance_charts_entry_internal_shape():
    """C04 AC4 trio leg 1: charts.radiance = {namespace: default,
    ServerSideApply: "false"} (gotcha 6: SSA "false" for the llama-swap
    family), no version/repository keys (internal chart)."""
    entry = (_svc().get("charts") or {}).get("radiance")
    assert entry is not None, (
        "cf-143 C04: charts.radiance entry missing from services/gpu-ai/prod/values.yaml — "
        "the appset leg of the trio is not wired"
    )
    assert entry == {"namespace": "default", "ServerSideApply": "false"}, (
        f"cf-143 C04: charts.radiance is {entry}, want exactly "
        '{namespace: default, ServerSideApply: "false"} (internal-chart shape, gotcha 6)'
    )


def test_application_name_derivation_is_gpu_ai_radiance():
    """C04 AC4 (name evidence): the base appset template derives the
    Application name as {{serviceName}}-{{appName}} (radiance -> gpu-ai-
    radiance, the peer URL's host) and renders internal entries (no
    version/repository) as a git path source — the same read C07's n1
    needle pins for amd-gpu."""
    text = BASE_APPSET.read_text()
    assert 'name: "{{ `{{ .serviceName }}` }}-{{ `{{ .appName }}` }}"' in text, (
        "cf-143 C04: the base appset Application-name derivation changed — re-read "
        "charts/base/templates/appset-charts.yaml and re-pin the peer-URL reasoning"
    )
    assert re.search(r"- repoURL: '.*hasKey \. \"repository\".*services\.repo.*'", text), (
        "cf-143 C04: the appset repoURL branch (repository ? external : git repo) changed "
        "shape — internal entries (charts.radiance) resolve to services.repo + path"
    )


def test_service_radiance_block_scalars_only_and_dual_edit():
    """C04 task 2 + AC5, C03 carrier re-aim: top-level radiance: block —
    the deep-merge REPLACE law (gotcha 3) in its POST-C03 form. The block is
    no longer scalars-only (the lane's mechanism now lives here: args + the
    staging command), so the law moved from "no lists" to "no list path the
    chart shell also defines" — a block list colliding with a chart mechanism
    list would silently REPLACE it. The modelPath anchor moved into the block
    with the lane, so the dual-edit equality is block-internal: the anchor and
    the serve --model are equal bytes. NO rocrVisibleDevices key (no env on
    the named-pool path) — unchanged."""
    block = _svc().get("radiance")
    assert isinstance(block, dict), (
        "cf-143 C04: no top-level radiance: values block — the service half of the "
        "chart-into-appset wiring is missing"
    )

    def walk(node, path=""):
        if isinstance(node, dict):
            for k, v in node.items():
                yield from walk(v, f"{path}.{k}")
        elif isinstance(node, list):
            yield path, "list"

    sub = block.get("app-template") or {}
    list_paths = sorted(p for p, kind in walk(sub) if kind == "list")
    chart_values = L.REPO_ROOT / "charts" / "radiance" / "values.yaml"
    assert chart_values.is_file(), (
        "cf-143 C04: charts/radiance/values.yaml missing — C02 must land first (wave 2 dep); "
        "the merge-collision check has no chart side to compare against"
    )
    chart_at = yaml.safe_load(chart_values.read_text()).get("app-template") or {}
    chart_list_paths = {p for p, kind in walk(chart_at) if kind == "list"}
    collisions = sorted(set(list_paths) & chart_list_paths)
    assert not collisions, (
        f"cf-143 C04/C03: block list paths {collisions} also exist chart-side — helm deep-merge "
        "REPLACES lists wholesale, so a collision silently drops the chart's mechanism list "
        "(the block may carry lists only at paths the mechanism-only shell does not define)"
    )
    assert "rocrVisibleDevices" not in sub, (
        "cf-143 C04: radiance service block re-pins rocrVisibleDevices — the named-pool "
        "path sets no ROCr/HIP env (C02 absence law)"
    )
    ctrl = (sub.get("controllers") or {}).get("radiance") or {}
    args = [str(a) for a in ((ctrl.get("containers") or {}).get("radiance") or {}).get("args") or []]
    model = args[args.index("--model") + 1] if "--model" in args else None
    assert sub.get("modelPath") == model, (
        f"cf-143 C04 AC5: block modelPath {sub.get('modelPath')!r} != block serve --model "
        f"{model!r} — the anchor and the serve path are a DUAL edit (per C03 they live in the "
        "same block, so the equality is block-internal now)"
    )


def test_no_radiance_ingress_host_and_two_skip_comments():
    """C04 AC4 trio leg 3 (the documented skip): NO radiance key under
    ingress.subdomains, and the subdomains block now carries TWO internal-
    only skip comments (strata's Q4 stays as-is + radiance's mirror)."""
    svc = _svc()
    subs = (svc.get("ingress") or {}).get("subdomains") or {}
    offenders = [k for k in subs if "radiance" in k]
    assert not offenders, f"cf-143 C04: ingress.subdomains carries {offenders} — radiance is internal-only (Q4 mirror)"
    text = S.SERVICE_VALUES.read_text()
    m = re.search(r"^\s*subdomains:\s*$", text, re.M)
    assert m, "cf-143 C04: no ingress.subdomains block to search for the skip comments"
    rest = text[m.end():]
    stop = re.search(r"^[a-z]", rest, re.M)
    region = rest[: stop.start() if stop else len(rest)]
    comment_lines = [ln for ln in region.splitlines() if ln.lstrip().startswith("#")]
    radiance_skips = [ln for ln in comment_lines if "radiance" in ln.lower()]
    strata_skips = [ln for ln in comment_lines if "strata" in ln.lower()]
    assert radiance_skips, (
        "cf-143 C04: no radiance internal-only skip comment in the subdomains block "
        "(the D7/Q4 precedent text mirrored — trio law's documented skip)"
    )
    assert strata_skips, "cf-143 C04: the strata Q4 skip comment vanished — that block is byte-stable (Q5)"


def test_custom_values_gains_no_radiance_key():
    """D8: keyless + ungated packs = no secret surface = no custom-values leg
    (the trio law's secrets-condition documented in the chunk). C15 NOTE: the
    "radiance" SUBSTRING check already covers any radiance-q27 key — the
    fourth D8 leg stays UNMOVED and is deliberately NOT widened to name
    q27 specifically (we ship no secret, so no q27 key may appear at all)."""
    text = CUSTOM_VALUES.read_text()
    assert "radiance" not in text.lower(), (
        "cf-143 C04/D8: custom-values/gpu-ai/prod-values.yaml gained a radiance key — "
        "the lane ships no secrets; a bitwardenId here contradicts D8"
    )


# --- cf-143 C15: the q27 siblings of the coexistence laws -------------------------


def test_c15_no_radiance_q27_ingress_host_and_q27_skip_comment():
    """C15 D4/T2 (the third-peer wave's coexistence half): NO radiance-q27
    key under ingress.subdomains (the proxy leg STAYS skipped — D56(8),
    internal-only like fn), AND the subdomains region carries the q27 skip
    sentence beside the radiance/vllm/strata mirrors. The skip-comment arm
    is DESIGNED-RED until dev D4 lands the comment; the no-host arm is green
    now and must STAY green (a proxy entry invented for q27 is the drift).
    The scalars-only leg above stays SCOPED to the fn radiance subtree: the
    q27 overlay REPLACES LISTS (args + init command) BY DESIGN — the
    anchor-trap law makes scalars useless there (D56(1); TEST_SPEC §12.15)."""
    svc = _svc()
    subs = (svc.get("ingress") or {}).get("subdomains") or {}
    offenders = [k for k in subs if "radiance-q27" in k]
    assert not offenders, f"cf-143 C15: ingress.subdomains carries {offenders} — q27 is internal-only too (D56(8))"
    text = S.SERVICE_VALUES.read_text()
    m = re.search(r"^\s*subdomains:\s*$", text, re.M)
    assert m, "cf-143 C15: no ingress.subdomains block to search for the q27 skip comment"
    rest = text[m.end():]
    stop = re.search(r"^[a-z]", rest, re.M)
    region = rest[: stop.start() if stop else len(rest)]
    comment_lines = [ln for ln in region.splitlines() if ln.lstrip().startswith("#")]
    q27_skips = [ln for ln in comment_lines if "radiance-q27" in ln.lower() or ("q27" in ln.lower() and "radiance" in ln.lower())]
    assert q27_skips, (
        "cf-143 C15: no radiance-q27 internal-only skip comment in the subdomains block — "
        "dev D4 lands the mirror sentence ('deliberately NO radiance-q27 host either'); "
        "designed-red naming C15 until it does"
    )


@helm_mark
def test_radiance_id_stays_out_of_the_outer_matrix_and_models():
    """Peer law (RESEARCH 'Catalog/matrix anchors'): peer models stay OUT of
    the outer matrix; the outer config gains no radiance rung."""
    cfg = L.rendered_config("gpu-ai")
    models = set(L.all_models_of(cfg))
    served_id = "qwen3.8-flash-next-radiance"
    assert served_id not in models, (
        f"cf-143 C04: {served_id} rendered as an OUTER llama-swap model — the peer join "
        "must not register it in the outer models map (local ids would shadow the peer)"
    )
    matrix = cfg.get("matrix") or {}
    vars_blob = yaml.safe_dump(matrix.get("vars") or {}) + yaml.safe_dump(matrix.get("sets") or {})
    assert served_id not in vars_blob, (
        "cf-143 C04: the radiance id joined a matrix var/set — peers are not matrix members"
    )
    # Neither disables the other: the strata peer is still live in the SAME
    # render the radiance appset entry serves beside (coexistence, Q5).
    assert "strata" in (cfg.get("peers") or {}), (
        "cf-143 C04: peers.strata gone from the render — nothing in this ticket disables strata"
    )


@helm_mark
def test_c15_q27_id_stays_out_of_the_outer_matrix_and_models():
    """C15 T2 (q27 sibling of the :223-240 idiom): the peers join is not a
    matrix join — the q27 wire id must never register in the outer models
    map or a matrix var/set (local ids would shadow the peer, the R3 Q5.2
    precedence law the fn leg mirrors). Green today (the id serves nowhere
    outer yet); it exists to catch dev D3 registering q27 wrong."""
    cfg = L.rendered_config("gpu-ai")
    models = set(L.all_models_of(cfg))
    served_id = "qwen3.8-27b-radiance"
    assert served_id not in models, (
        f"cf-143 C15: {served_id} rendered as an OUTER llama-swap model — the q27 peer join "
        "must not register it in the outer models map (shadow class, fn precedent)"
    )
    matrix = cfg.get("matrix") or {}
    vars_blob = yaml.safe_dump(matrix.get("vars") or {}) + yaml.safe_dump(matrix.get("sets") or {})
    assert served_id not in vars_blob, (
        "cf-143 C15: the q27 id joined a matrix var/set — peers are not matrix members (D56(8))"
    )
