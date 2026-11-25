# cf-145 C01 — the k8s.grafana.com/* scrape-annotation pair on the radiance
# ENGINE pod (chunks/C01.md; AC1/AC4 + the T5 preserve pins). The owner-ruled
# mechanism (batched OQ-1 answer, DECISIONS D-8) is the charts/vllm D8 idiom:
# a `monitoring.annotations: true` gate inside the `app-template:` subtree +
# exactly two ternary-templated keys in the existing defaultPodOptions block.
# Consumed by gpu-ai's k8s-monitoring annotationAutodiscovery: portNumber ->
# podIP:8000, absent metrics.path -> /metrics, absent job annotation -> the
# `app.kubernetes.io/name` label fallback fills job `radiance` for BOTH
# releases (plan R5b). Live proof on the cluster is OWNER leg OE-2 (R5a —
# enabled-but-unproven on gpu-ai); these legs stop at the render contract.
#
# Exactness law (owner-verify A1, post ConfigMap-carrier refactor): the
# ruled pair is pinned as the EXACT k8s.grafana.com/* subset, and the full
# pod map is pinned against the known-complete key set — pair ∪
# {checksum/configMaps} — so any NEW annotation reddens too. T4 is a
# single-path ABSENCE guard — green before and after (it exists so the retired
# draft-1 ServiceMonitor path can never sneak in beside the annotations). T5
# preserve legs are green and must STAY green: the pair lands beside a
# byte-stable digest ledger (LEDGER_REGION_LINES) and no reloader annotation.
#
# Run per-directory: PATH=$HOME/.local/bin:$PATH python3 -m pytest charts/radiance/tests -v

from __future__ import annotations

import re
from pathlib import Path

import pytest

import radiance_testlib as R

_ok, _reason = R.helm_ready()
helm_skip = pytest.mark.skipif(not _ok, reason=_reason)

# The ruled pair (charts/vllm values.yaml:262-264 verbatim in shape). Values
# are STRINGS by k8s annotation law; the ternary renders "true"/"8000".
PAIR = {
    "k8s.grafana.com/scrape": "true",
    "k8s.grafana.com/metrics.portNumber": "8000",
}

# D35/D43 ConfigMap-carrier roll: the chart owns the fetch.sh/serve.sh ConfigMaps and app-template hashes them onto the pod — the one non-ruled key the map may carry, outside the k8s.grafana.com namespace (value is a rolling content hash, so the legs pin KEY-SET membership).
CHECKSUM_KEY = "checksum/configMaps"

# The keys the D8/Q5 exactly-two law deliberately leaves UNSHIPPED (plan R5b):
# metrics.path -> the autodiscovery default /metrics; metrics.scrapeInterval ->
# cadence rides the GLOBAL default, not the annotation — k8s-monitoring 4.5.5
# upstream default is 60 s, gpu-ai's EFFECTIVE cadence 15 s since the owner
# directive 2026-11-25 via the umbrella k8s-monitoring valuesObject
# scrapeInterval override; job -> the label fallback `radiance`.
BANNED_ANNOTATION_KEYS = (
    "k8s.grafana.com/job",
    "k8s.grafana.com/metrics.path",
    "k8s.grafana.com/metrics.scheme",
    "k8s.grafana.com/metrics.jobLabel",
    "k8s.grafana.com/metrics.scrapeInterval",
)

GPU_AI_TEMPLATES = R.REPO_ROOT / "services" / "gpu-ai" / "prod" / "templates"


def _pod_annotations(render_result) -> dict:
    docs, _raw = render_result
    return ((R.deployment(docs)["spec"]["template"].get("metadata") or {}).get("annotations") or {})


# --- T1 (AC1): the chart-default (fn) render carries EXACTLY the pair ---------


@helm_skip
def test_t1_fn_render_carries_exactly_the_pair():
    """The gate+pair ship in the CHART defaults, so the fn release inherits
    them without any overlay help. Exactly-two is the D8 law over the
    k8s.grafana.com/* namespace — no third ruled-namespace key, no legacy
    flavor — and the full map is pinned to the known-complete key set (pair +
    the D35/D43 checksum roll), so an unruled new annotation reddens too."""
    ann = _pod_annotations(R.render(service=False))
    assert ann, (
        "cf-145 C01: the fn pod annotation map is absent/EMPTY — neither the ruled pair nor the "
        "D35/D43 checksum roll reached pod metadata.annotations at all; the pair-missing case this "
        "guard fronts, with the key-by-key detail on the subset assertion below"
    )
    assert {k: v for k, v in ann.items() if k.startswith("k8s.grafana.com/")} == PAIR, (
        f"cf-145 C01 AC1: the ruled k8s.grafana.com/* subset of {ann} is not the pair — "
        "the vllm D8 pair, gate-resolved to \"true\"/\"8000\" (a missing key, a renamed "
        "key, or a non-string value each break the autodiscovery contract, plan R5b)"
    )
    assert set(ann) == set(PAIR) | {CHECKSUM_KEY}, (
        f"cf-145 C01 AC1: the full pod annotation map {sorted(ann)} is not the known-complete set "
        "(ruled pair ∪ checksum/configMaps) — any NEW annotation rides the engine pod only with a "
        "DECISIONS line behind it"
    )


@helm_skip
def test_t1_legacy_prometheus_io_flavor_absent():
    """prometheus.io/scrape etc. is a DIFFERENT discovery flavor this fleet's
    alloy chain does not read; shipping it beside the ruled pair is the
    double-wire class the exactly-two law blocks (plan Out-of-scope/T4 spirit)."""
    _docs, raw = R.render(service=False)
    _docs_q, raw_q = R.render_q27()
    for name, text in (("fn", raw), ("q27", raw_q)):
        assert "prometheus.io/" not in text, (
            f"cf-145 C01 AC1: a prometheus.io/* annotation reached the {name} render — "
            "the ruled path is k8s.grafana.com/* only (charts/vllm D8 precedent)"
        )


# --- T2 (AC1): the q27 overlay inherits the same pair (unified coverage) ------


@helm_skip
def test_t2_q27_render_inherits_pair():
    """One chart dir, releases deep-merge over the chart defaults and remove
    nothing (D26/D56), so q27's pod carries the identical ruled subset AND the
    same known-complete full-map pin as fn — the owner's unified-coverage
    intent made checkable. job identity stays `radiance` for BOTH (same
    app.kubernetes.io/name label fallback, R5b)."""
    ann = _pod_annotations(R.render_q27())
    assert {k: v for k, v in ann.items() if k.startswith("k8s.grafana.com/")} == PAIR, (
        f"cf-145 C01 AC1: the q27 ruled k8s.grafana.com/* subset of {ann} is not the pair — "
        "the pair must inherit through the overlay (if fn went green and this stayed "
        "red, the overlay would be stripping defaultPodOptions — a scope bug)"
    )
    assert set(ann) == set(PAIR) | {CHECKSUM_KEY}, (
        f"cf-145 C01 AC1: the q27 full pod annotation map {sorted(ann)} is not the known-complete set "
        "(ruled pair ∪ checksum/configMaps)"
    )
    docs, _raw = R.render_q27()
    labels = ((R.deployment(docs)["spec"]["template"].get("metadata") or {}).get("labels") or {})
    assert labels.get("app.kubernetes.io/name") == "radiance", (
        f"cf-145 C01 R5b: q27 pod label app.kubernetes.io/name is {labels.get('app.kubernetes.io/name')!r} "
        "— the job-`radiance` fallback identity reads THIS label; a rename silently renames the Prometheus job"
    )


# --- T3 (AC1): gate-OFF keeps the keys with inert EMPTY values ----------------


@helm_skip
def test_t3_gate_off_yields_inert_empty_pair():
    """The whole-map tpl law (app-template 5.0.1): `--set
    app-template.monitoring.annotations=false` keeps both ruled keys with empty
    values — an empty value is what disables the scrape (vllm comment law).
    Pinned so a future gate flip disables the scrape the DOCUMENTED way rather
    than the map disappearing and the contract drifting. The checksum roll
    keeps riding the map with the gate off (it is a different concern), so the
    empty-value law scopes the k8s.grafana.com/* subset while the full map
    stays the known-complete set."""
    ann = _pod_annotations(
        R.render(service=False, extra_set="--set app-template.monitoring.annotations=false")
    )
    ruled = {k: v for k, v in ann.items() if k.startswith("k8s.grafana.com/")}
    assert set(ruled) == set(PAIR), (
        f"cf-145 C01 AC1 (gate leg): with monitoring.annotations=false the render carries {sorted(ann)} — "
        "the ternary shape keeps the KEYS and empties the VALUES (keys vanishing means the "
        "pair is not ternary-templated; keys absent entirely means it has not landed at all)"
    )
    assert all(v == "" for v in ruled.values()), (
        f"cf-145 C01 AC1 (gate leg): gate-OFF ruled values {ruled} — both must be the EMPTY string "
        "(ternary \"\" branch); a non-empty value with the gate off is the flip the pin exists to catch"
    )
    assert set(ann) == set(PAIR) | {CHECKSUM_KEY}, (
        f"cf-145 C01 AC1: the gate-OFF full pod annotation map {sorted(ann)} is not the known-complete set "
        "(ruled pair keys ∪ checksum/configMaps)"
    )


# --- T4 (AC4): single-path guards — the retired monitor path stays dead -------


@helm_skip
def test_t4_no_banned_autodiscovery_annotations():
    """job/interval/path identity stays the GROUNDED fallback chain (R5b): the
    absence of k8s.grafana.com/job is what makes the Prometheus job `radiance`.
    Any addition beyond the pair needs a DECISIONS line (chunk Notes)."""
    for name, ann in (("fn", _pod_annotations(R.render(service=False))),
                      ("q27", _pod_annotations(R.render_q27()))):
        banned = [k for k in ann if k in BANNED_ANNOTATION_KEYS]
        assert not banned, (
            f"cf-145 C01 AC4: {name} render carries {banned} — the D8/Q5 exactly-two law "
            "leaves job and path to the documented fallback chain (job `radiance`, /metrics) and "
            "the cadence to the global default — upstream 60 s, gpu-ai EFFECTIVE 15 s per the "
            "umbrella scrapeInterval override (owner directive 2026-11-25); "
            "an annotation override key is a ruling, not a tweak"
        )


@helm_skip
def test_t4_charts_radiance_renders_carry_no_monitor_objects():
    """The annotation path and a raw monitor object are mutually exclusive
    wiring routes (double-scrape risk): the radiance chart renders neither
    ServiceMonitor nor PodMonitor in any release shape."""
    for name, (_docs, raw) in (("fn", R.render(service=False)), ("q27", R.render_q27())):
        for kind in ("ServiceMonitor", "PodMonitor"):
            assert not re.search(rf"kind:\s*{kind}\b", raw), (
                f"cf-145 C01 AC4: a kind: {kind} appeared in the {name} charts/radiance render — "
                "the owner ruled the annotations path (OQ-1 answer); a monitor object double-wires the scrape"
            )


def test_t4_gpu_ai_templates_have_no_monitor_objects():
    """The draft-1 alternative (a raw ServiceMonitor under the gpu-ai umbrella)
    is RETIRED (DECISIONS D-8): the umbrella templates stay monitor-free so the
    two paths can never coexist. Pure file walk — no helm needed, so this guard
    runs even where the binary is absent."""
    assert GPU_AI_TEMPLATES.is_dir(), (
        f"cf-145 C01: {GPU_AI_TEMPLATES} missing — the guard's host surface vanished"
    )
    hits = []
    for f in sorted(GPU_AI_TEMPLATES.rglob("*")):
        if not f.is_file():
            continue
        text = f.read_text()
        for kind in ("ServiceMonitor", "PodMonitor"):
            if re.search(rf"kind:\s*{kind}\b", text):
                hits.append(f"{f.relative_to(R.REPO_ROOT)}: kind {kind}")
    assert not hits, (
        f"cf-145 C01 AC4: raw monitor object(s) {hits} under services/gpu-ai/prod/templates/ — "
        "the ruled scrape path is the k8s.grafana.com/* annotation pair IN charts/radiance only; "
        "both surfaces at once is the double-wire this leg exists to block"
    )


# --- T5 (AC3/AC4 preserve pins): green today, green after ----------------------

# values.yaml:224-242 captured verbatim at plan-approval (branch @7219bf5) —
# the digest-ledger + renovate-pin region the zero-diff lift for C01 explicitly
# does NOT touch (plan Out-of-scope; DECISIONS D-8 "PRESERVE" law). Position
# may shift when dev inserts the gate above it; the BYTES may not.
LEDGER_REGION_LINES = [
    "          image:",
    "            repository: docker.io/stilldeadcode/radiance",
    "            # renovate: datasource=docker depName=docker.io/stilldeadcode/radiance",
    '            tag: "1.17.0"',
    "            pullPolicy: IfNotPresent",
    "            # DIGEST LEDGER (D2 — tag pin + digests-in-comment, NO digest",
    "            # field: the repo has no image.digest precedent). Which is which",
    "            # (RESEARCH RQ0/S4, verified against the Docker Hub API",
    "            # 2026-11-12):",
    "            #   amd64 IMAGE MANIFEST:",
    "            #     sha256:6fb0e99bfb862e17cc15cb7b2f116c7dbdc831df59f82456a0691122e6cf5330",
    "            #   tag INDEX (manifest-list wrapper — what `radiance:1.17.0`",
    "            #   itself resolves to; llmkube pins the manifest digest as",
    "            #   1.17.0@sha256:6fb0e99b...):",
    "            #     sha256:c2acbaa373c89272ec47a22befa1cf04d2ddf1de51c2baf534f5273e517f7100",
    "            # Tag-rebuild caution (the unified-vulkan-262 precedent: a tag",
    "            # CAN be rebuilt in place upstream, silently changing bytes under",
    "            # a held pin) — this ledger is the forensic anchor for exactly",
    "            # that case; a digest retarget is a DECISIONS line, not a drive-by.",
]


def test_t5_digest_ledger_region_byte_stable():
    """Read-text grep is the one authority for the ledger (chunk T5): the
    19-line image/digest region stays byte-identical and contiguous — the
    renovate docker pin in particular (a broken comment silently untracks the
    image bump; the cf-143 suite legs stay the behavior contract)."""
    lines = R.chart_values_text().splitlines()
    region = "\n".join(LEDGER_REGION_LINES)
    joined = "\n".join(lines)
    assert region in joined, (
        "cf-145 C01 AC4 (preserve): the values.yaml:224-242 digest-ledger/renovate region is NOT "
        "byte-identical anymore — C01's zero-diff lift covers the GATE + ANNOTATIONS region only; "
        "locate the drift with: git diff -- charts/radiance/values.yaml"
    )


@helm_skip
def test_t5_reloader_annotation_still_absent():
    """Complements the existing 46-green leg (test_render.test_reloader_annotation_absent)
    on the post-C01 annotation map: the scrape pair lands beside — never
    replacing — the on-purpose absence of reloader.stakater.com. The chart DOES
    mount one ConfigMap since the carrier refactor (radiance-fetch holding the
    fetch.sh/serve.sh FORMs, values.yaml:131-136, mounted :528-533), and the
    no-reloader rationale moved with it (values.yaml:325-329): the restart the
    carrier needs is already driven by the CHECKSUM_KEY roll (D35), the pod
    mounts no Secret surface at all, and a reloader would only add a second
    restart path. Green with the ruled pair + checksum roll on the map, must
    stay green."""
    ann = _pod_annotations(R.render(service=False))
    stale = [k for k in ann if "reloader.stakater.com" in k]
    assert not stale, f"cf-145 C01 AC3 (preserve): reloader annotation(s) {stale} reached the pod template"
