# Contract suite for charts/vllm (born in 2026/2026-11-cf-105-feat-implement-
# vllm C02; re-pinned by 2026/2026-11-cf-131-feat-vllm-fp8-official): Chart.yaml
# metadata on the new-chart rule, the committed dependency lock + vendored tgz,
# the first-build image pin shape (on the pre-switch image until C02 flips it,
# then on the 0.30 re-export with its upstream ledger mirror), the values-level
# serveArgs recipe (D4 order, then the cf-131 D24 order, D36/D38/D40-amended), the cf-131 values
# record keys + comment law, the monitoring-annotations gate, the per-chart CI
# workflow ladder, and the C01 container surface: the thin re-export overlay
# + its one sanctioned flash-attn layer (the D34 amendment, install source
# re-pinned to the PyPI release by the D35 amendment — the one-ARG shape)
# and the retirement of the GGUF overlay it replaces.
# Generation branching is explained in vllm_testlib (cf-131 header); the C01
# container/retirement legs are unconditional because C01 is wave 1 — they are
# the designed-red that C01's own dev edit turns green.

from __future__ import annotations

import re
import subprocess
from pathlib import Path

import pytest
import yaml

import vllm_testlib as V

# Only the two helm-rendering tests below carry the skip gate; the pure file
# reads are NOT skipped when helm is absent — a missing chart must read as an
# assertion red, not a silent skip (the mass-skip trap of the repo's
# helm-guarded suites).
_helm_ok, _helm_reason = V.helm_ready()
helm_skip = pytest.mark.skipif(not _helm_ok, reason=_helm_reason)

CHART_DIR = V.CHART_DIR

# C02 serve-plane tests run only once the image pin names the cf-131
# re-export (see vllm_testlib for the witness law): before C02 lands, the
# generation-branch tests above hold the pre-switch contract instead.
c02_plane = pytest.mark.skipif(not V.cf131_plane(),
                               reason="cf-131 C02: the serve plane is not flipped yet on this commit")


# --- AC1 (lint leg) ------------------------------------------------------------


@helm_skip
def test_ac1_helm_lint_passes():
    out = subprocess.run(["helm", "lint", str(CHART_DIR)],
                         capture_output=True, text=True, timeout=300)
    assert out.returncode == 0, out.stdout + out.stderr


# --- AC6: chart metadata on the new-chart rule ----------------------------------


def test_ac6_chart_metadata():
    assert (CHART_DIR / "Chart.yaml").is_file(), "C02: charts/vllm/Chart.yaml missing — the chart is not implemented"
    meta = yaml.safe_load((CHART_DIR / "Chart.yaml").read_text())
    assert meta.get("name") == "vllm", f"Chart.yaml name is {meta.get('name')!r}, want vllm"
    # version 1.0.0 exactly: chart-releaser bumps the patch on every merge to
    # main — a new chart never starts on a hand-picked other number.
    assert str(meta.get("version")) == "1.0.0", (
        f"Chart.yaml version is {meta.get('version')!r}, want 1.0.0 (new-chart rule)"
    )
    # appVersion tracks the engine generation inside the pinned image: the
    # cf-105 base carried vLLM 0.33.0, the cf-131 C02 flip re-pins it to the
    # 0.30.0 tag commit (D24; the R3 L1.1 engine identity).
    want_app = "0.30.0" if V.cf131_plane() else "0.33.0"
    assert str(meta.get("appVersion")) == want_app, f"appVersion is {meta.get('appVersion')!r}, want {want_app}"
    # Exactly one dep: app-template bundles the common chart internally (zero
    # k8s objects of its own), so the C07 owner ruling voids C02's two-dep
    # shape — a second entry (common) re-introduces it.
    deps = meta.get("dependencies") or []
    assert deps == [{"name": "app-template",
                     "version": "5.0.1",
                     "repository": "https://bjw-s-labs.github.io/helm-charts/"}], (
        "C07 AC1: Chart.yaml dependencies must be EXACTLY one entry — app-template 5.0.1 on the "
        f"sibling repository form with the trailing slash (charts/llama-swap); deps: {deps}"
    )


def test_ac6_chart_lock_and_vendored_dependency():
    lock = CHART_DIR / "Chart.lock"
    assert lock.is_file(), "C02 AC6: Chart.lock missing (helm dependency update output, committed)"
    # helm writes Chart.lock as YAML, not JSON (v3.16.4 verified 2026-11-05) —
    # a JSON lock can never survive the workflow's `helm dependency update`
    # step, so the criterion parses through yaml (TEST-FAULTY repair).
    deps = yaml.safe_load(lock.read_text()).get("dependencies", [])
    assert len(deps) == 1, (
        "C07 AC1: Chart.lock must pin EXACTLY one dependency — [app-template 5.0.1] (the common "
        f"dep is void under the repo app-template idiom); deps: {deps}"
    )
    assert deps[0].get("name") == "app-template" and str(deps[0].get("version")) == "5.0.1", (
        f"C02 AC6: Chart.lock must pin app-template 5.0.1, got {deps}"
    )
    assert list(CHART_DIR.glob("charts/app-template-5.0.1.tgz")), (
        "C02 AC6: the vendored charts/app-template-5.0.1.tgz is missing (helm dependency update output)"
    )
    assert not list(CHART_DIR.glob("charts/common-*.tgz")), (
        "C07 AC1: a vendored charts/common-*.tgz survived — dropping the common dep must delete the "
        "stale tgz (helm dependency update does it; the tgz dir is gitignored, Chart.lock is the committed artifact)"
    )


def _image_nodes() -> list:
    nodes: list = []
    V.find_image_nodes(V.chart_values(), nodes)
    return nodes


def _scannable(path: Path) -> bool:
    # Compiled caches fold the assembled V.LEGACY_REF constant back into one
    # string, and vendored tgz data is not a reference surface; the scans
    # below read source files only.
    return path.is_file() and "__pycache__" not in path.parts and path.suffix not in (".pyc", ".pyo", ".tgz")


def test_ac6_image_pin_is_first_build_shape():
    """The in-repo image at tag main + pullPolicy Always + the PIN-ME
    comment (the strata first-build pattern): the first :v<run> pin lands as
    the runbook step-10 follow-through, never a hand edit. Which repository
    the shape sits on follows the generation witness — the pre-switch pin is
    C01's deliberately-unchanged stability witness, the cf-131 pin is C02's
    flip and additionally mirrors the upstream 0.30 identity (D23: the README
    is the ledger home, the chart comment the values-side mirror)."""
    values_path = CHART_DIR / "values.yaml"
    assert values_path.is_file(), "C02: charts/vllm/values.yaml missing"
    values_text = values_path.read_text()

    nodes = _image_nodes()
    assert nodes, "C02 AC6: no image spec (repository+tag node) in charts/vllm/values.yaml"
    want_repo = V.CF131_IMAGE_REPO if V.cf131_plane() else None
    for node in nodes:
        if want_repo is not None:
            assert node.get("repository") == want_repo, (
                f"C02 AC6: image repository is {node.get('repository')!r}, want {want_repo}"
            )
        assert str(node.get("tag")) == "main", (
            f"C02 AC6: first-build image tag must be main (rolling), got {node.get('tag')!r}"
        )
        assert node.get("pullPolicy") == "Always", (
            f"C02 AC6: pullPolicy Always must sit on the image spec beside the :main pin, got {node.get('pullPolicy')!r}"
        )
    assert re.search(r"PIN-ME", values_text, re.I), (
        "C02 AC6: values.yaml carries no PIN-ME comment — the first :v<run> pin obligation "
        "(runbook step 10) is undocumented"
    )
    if not V.cf131_plane():
        return
    # The upstream pin the re-export carries, as three independent fragments
    # (C02 task): a prose-wrapped comment may break a `repo:tag` composite
    # across lines, so the pairing that decides the pin is the README ledger
    # (tests/containers/vllm-radiance-mxfp4.sh), not comment adjacency here.
    for fragment in (V.UPSTREAM_IMAGE, V.UPSTREAM_TAG, "sha256:b73bf3e4"):
        assert fragment in values_text, (
            f"C02 AC6: the image block's ledger comment is missing the upstream fragment "
            f"{fragment!r} — the re-export must mirror the identity it pins (D23)"
        )
    # The retired overlay must be gone from the whole chart surface once the
    # flip landed (the tests/ files self-clean via the assembled V.LEGACY_REF).
    for path in sorted(CHART_DIR.rglob("*")):
        if path.relative_to(CHART_DIR).parts[0] == "charts":
            continue  # the vendored tgz dir is gitignored
        if not _scannable(path):
            continue
        assert V.LEGACY_REF not in path.read_text(errors="replace"), (
            f"C02 AC6: {path.relative_to(CHART_DIR)} still references the retired "
            "GGUF-overlay image after the serve-plane flip"
        )


# --- serveArgs values contract ---------------------------------------------------


def test_serveargs_values_carry_the_contract_recipe():
    """The values-level serveArgs list (under the app-template: subtree, the
    C07 idiom location) is what the template renders VERBATIM (C02 task): the
    contract flags present in the contract order. The rendered-args equality
    (order, values, model-path splice) is asserted at render level in
    test_render.py."""
    serve = (V.chart_values().get("app-template") or {}).get("serveArgs")
    assert isinstance(serve, list) and serve, (
        "C02: charts/vllm/values.yaml must carry the serveArgs list under the app-template: subtree"
    )
    if V.cf131_plane():
        # The args-start-with-the-model-path law (D24: the 0.30 entrypoint
        # supplies the verb) — the first list item is the model anchor, not a
        # flag, and no --model flag may exist anywhere in the list.
        assert serve[0] == V.MODEL_DIR, (
            f"C02 (cf-131): serveArgs must start with the model path {V.MODEL_DIR}, got {serve[0]!r}"
        )
        assert "--model" not in serve, (
            "C02 (cf-131): a --model flag sits in serveArgs — on the 0.30 entrypoint that "
            "double-specifies the model the positional path already carries"
        )
        recipe = V.RECIPE_CF131
    else:
        recipe = V.D4_RECIPE
    flags = [a for a in serve if isinstance(a, str) and a.startswith("--")]
    want_flags = [flag for flag, _ in recipe]
    assert flags == want_flags, (
        f"C02: serveArgs flags diverge from the contract recipe order\n  got:      {flags}\n  expected: {want_flags}"
    )


# --- cf-131 C02: the values record keys (AC8) -------------------------------------


@c02_plane
def test_c02_spec_and_kv_values_keys_carry_the_d24_record():
    app = V.chart_values()["app-template"]
    assert app.get("modelPath") == V.MODEL_DIR, (
        f"C02 AC8: app-template.modelPath is {app.get('modelPath')!r}, want the raw-release dir "
        f"{V.MODEL_DIR} (the round-2 Q8 ruling; the dual edit's chart side)"
    )
    assert app.get("kvCacheDtype") == "int4_per_token_head", (
        f"C02 AC8: app-template.kvCacheDtype is {app.get('kvCacheDtype')!r}, want "
        "int4_per_token_head — the D36 ship default (the owner's R6-Q1 ruling) splices into "
        "--kv-cache-dtype; fp8 is the documented toggle + the recorded fp8+R4D alternative"
    )
    assert app.get("specMethod") == "dflash", (
        f"C02 AC8: app-template.specMethod is {app.get('specMethod')!r}, want dflash (the round-2 "
        "Q1 confirmed shipped lane, native V2 DFlash2Speculator at 0.30)"
    )
    assert app.get("specConfig") == V.SPEC_CONFIG_DFLASH, (
        "C02 AC8: app-template.specConfig diverges from the shipped dflash JSON (D24/Q11 chain, "
        "D40-reverted pre-D39 literal — "
        f"got {app.get('specConfig')!r}"
    )
    assert str(app.get("rocrVisibleDevices")) == "0", (
        "C02: the chip-targeting key must stay \"0\" — the device-pin law carries unchanged"
    )


def _comment_block_before(lines: list, idx: int) -> str:
    """The contiguous comment block directly above lines[idx]: the record
    surface C02 mandates for the kv/spec keys' ruling text, stripped to its
    prose (the leading # markers removed and the block joined) so a JSON
    wrapped across comment lines still compares. Blank lines inside the
    block ride along; anything but a comment ends the walk."""
    block = []
    j = idx - 1
    while j >= 0:
        stripped = lines[j].strip()
        if stripped.startswith("#"):
            block.insert(0, stripped.lstrip("#").strip())
        elif stripped == "":
            block.insert(0, "")
        else:
            break
        j -= 1
    return " ".join(block)


@c02_plane
def test_c02_kv_cache_dtype_comment_carries_the_qualified_set():
    """AC8 comment leg (D36-amended, D38-extended): the kvCacheDtype key's comment records
    the ship default int4_per_token_head in TRITON_ATTN-only territory (the
    per-token-head family and fp8_e5m2 — R4D refuses them at the pin), the
    fp8/bf16/auto documented toggles as the R4D-capable set with the
    fp8+R4D recorded alternative, the boot-config gate reference (the 3.6
    promotion) and the owner's 48GB-RDNA3 headroom note."""
    lines = (CHART_DIR / "values.yaml").read_text().splitlines()
    idxs = [i for i, ln in enumerate(lines) if re.match(r"^\s*kvCacheDtype\s*:", ln)]
    assert idxs, "C02 AC8: no kvCacheDtype key in charts/vllm/values.yaml"
    window = " ".join(_comment_block_before(lines, i) for i in idxs)
    for token in ("int4_per_token_head", "fp8_e5m2", "TRITON_ATTN", "bf16",
                  "ALTERNATIVE", "3.6", "48"):
        assert token in window, (
            f"C02 AC8: the kvCacheDtype comment block lacks {token!r} — the D36 shape (ship "
            "default + TRITON-only territory, the R4D-capable toggles + recorded alternative, "
            "the 3.6 boot-config gate reference, the 48GB note) is that key's record"
        )


@c02_plane
def test_c02_spec_keys_comment_carries_the_mtp_toggle_pairing():
    """AC8 comment leg: the specMethod/specConfig comments carry BOTH spec
    JSONs (the shipped dflash splice + the documented mtp toggle), the
    RADIANCE_QUARK_BF16_MTP coupling record (the raw release's bf16 MTP-head
    load path, R3-Q6) and the drafter-skip record for the toggle."""
    lines = (CHART_DIR / "values.yaml").read_text().splitlines()
    window = ""
    for key in ("specMethod", "specConfig"):
        for i in (j for j, ln in enumerate(lines) if re.match(rf"^\s*{key}\s*:", ln)):
            window += " " + _comment_block_before(lines, i)
    compact = re.sub(r"\s+", "", window)
    assert re.sub(r"\s+", "", V.SPEC_CONFIG_MTP) in compact, (
        "C02 AC8: the spec keys' comments do not carry the mtp toggle JSON (D16/D24: "
        '{"method":"mtp","num_speculative_tokens":4,...} is the documented alternative)'
    )
    for token in ("RADIANCE_QUARK_BF16_MTP", "drafter", "skip"):
        assert token in window, (
            f"C02 AC8: the spec keys' comments lack {token!r} — the toggle's env coupling + "
            "the init's drafter-skip procedure are plan-record text (D24/D26)"
        )


# --- monitoring-annotations gate ---------------------------------------------------


def test_monitoring_gate_default_on():
    gate = ((V.chart_values().get("app-template") or {}).get("monitoring") or {}).get("annotations")
    assert gate, (
        "C02: the app-template.monitoring.annotations values key must default ON (D8) — the pod ships the two scrape annotations by default"
    )


@helm_skip
def test_monitoring_gate_off_disables_scrape():
    """Re-expresses the chunk's gate-OFF 'zero k8s.grafana.com/* keys' bar
    (TEST-FAULTY repair, test session 2026-11-04): app-template 5.0.1 tpl's
    the pod annotation map as a whole (common lib pod.metadata.annotations),
    so a values-level gate-OFF keeps the keys with inert values — live-verified
    on the vendored app-template-5.0.1.tgz (scrape renders '' and the key
    survives). Zero keys is mechanically unreachable by any such
    implementation; the functional contract instead is that no k8s.grafana.com/*
    annotation is enabled ('true'), so k8s-monitoring's annotationAutodiscovery
    does not scrape the pod. A key-dropping implementation would pass too —
    the bar checks the property, not the mechanism.

    C07 idiom rework (owner ruling 2026-11-06): the gate key moved one level
    down under app-template:, so the --set path is a layout pin re-pinned
    with the move. The planning probe (2026-11-06, helm v3.16.4) shows the
    OLD top-level path no longer gates: --set monitoring.annotations=false
    still renders k8s.grafana.com/scrape 'true' and metrics.portNumber
    '8000' — a test left on the old path would false-green, so it must read
    the new path to be a real gate check."""
    docs, _ = V.render(release="vllm", service=False, extra_set="--set app-template.monitoring.annotations=false")
    grafana = V.grafana_annotations(V.deployment(docs))
    assert "true" not in grafana.values(), (
        f"C02: with app-template.monitoring.annotations=false no k8s.grafana.com/* annotation "
        f"may be enabled (value 'true') — the gate must disable the scrape, got {grafana!r}"
    )


# --- scaffold files -----------------------------------------------------------------


def test_scaffold_common_loader_and_notes():
    """C07 flip of the C02 loader bar (owner ruling 2026-11-06): the repo
    app-template idiom renders the workload from the chart's own
    app-template: values — no parent-side loader file, no second dep, no
    bjw-s.common.* invocation in any parent-context template (the vendored
    app-template tgz bundles common internally; it generates no k8s objects
    of its own). NOTES.txt stays: the install-hint surface is chart-owned."""
    assert not (CHART_DIR / "templates" / "common.yaml").is_file(), (
        "C07 AC1: templates/common.yaml (the one-line bjw-s loader include) must be ABSENT — "
        "the repo app-template idiom renders without a parent-side loader"
    )
    # AC1's zero-common grep, text-only: exclude tests/ (this file carries the
    # needle literal in this absence-assert) and the gitignored vendored
    # charts/ tgz dir. Fixed-string needle — every real invocation starts with
    # bjw-s.common.*, and the regex-dot form of the needle would also match
    # prose like 'bjw-s common'.
    for path in sorted(CHART_DIR.rglob("*")):
        if not path.is_file():
            continue
        if path.relative_to(CHART_DIR).parts[0] in ("tests", "charts"):
            continue
        assert "bjw-s.common" not in path.read_text(), (
            f"C07 AC1: {path.relative_to(CHART_DIR)} still invokes the common chart "
            "(bjw-s.common.*) — the zero-common surface allows no parent-template include"
        )
    assert (CHART_DIR / "templates" / "NOTES.txt").is_file(), "C02: templates/NOTES.txt missing"


# --- cf-131 C01: the thin fork overlay (containers/vllm-radiance-mxfp4) -------------

CONTAINER_DIR = V.REPO_ROOT / "containers" / "vllm-radiance-mxfp4"


def _dockerfile_logical_lines(text: str) -> list:
    """The Dockerfile's executed instructions, one entry each: comments and
    blanks dropped, backslash continuations joined — the shape law counts
    LOGICAL instructions (the sanctioned flash-attn RUN spans four physical
    lines), so walking raw lines would red on the layer itself."""
    merged, buf = [], ""
    for raw in text.splitlines():
        ln = raw.strip()
        if not buf and (not ln or ln.startswith("#")):
            continue
        buf = f"{buf} {ln}".strip() if buf else ln
        if buf.endswith("\\"):
            buf = buf[:-1]
            continue
        merged.append(buf)
        buf = ""
    if buf:
        merged.append(buf)
    return merged


def test_c01_thin_overlay_dockerfile():
    """C01 AC1 (D34-amended, D35 source re-pin): the re-export Dockerfile is
    the thin digest-pinned FROM, the ONE sanctioned flash-attn layer (one
    version ARG + a single RUN — tests/containers/vllm-radiance-mxfp4.sh t7
    pins their content; the D35 block replaced D34's git ARG pair), and the
    record's EXPOSE 8000, in that order and nothing else — the 0.30 image is
    a self-contained terminal build (R3 L1.2), so a second RUN/ARG or any
    COPY/ENV/USER re-introduces the build story the base move deleted."""
    df = CONTAINER_DIR / "Dockerfile"
    assert df.is_file(), "C01 AC1: containers/vllm-radiance-mxfp4/Dockerfile missing"
    text = df.read_text()
    assert re.search(
        rf"^FROM[ \t]+docker\.io/{re.escape(V.UPSTREAM_IMAGE)}:{V.UPSTREAM_TAG}@{re.escape(V.UPSTREAM_DIGEST)}[ \t]*$",
        text, re.M,
    ), (
        f"C01 AC1: no FROM line pinning docker.io/{V.UPSTREAM_IMAGE}:{V.UPSTREAM_TAG}@{V.UPSTREAM_DIGEST} "
        "(the tag+digest form is the pin law, D23)"
    )
    assert re.search(r"^EXPOSE[ \t]+8000[ \t]*$", text, re.M), (
        "C01 AC1: no EXPOSE 8000 record line (serve = health = metrics, the port-8000 law)"
    )
    keywords = [ln.split(None, 1)[0].upper() for ln in _dockerfile_logical_lines(text)]
    offenders = [k for k in keywords if k not in ("FROM", "ARG", "RUN", "EXPOSE")]
    assert not offenders, (
        f"C01 AC1: instructions outside the sanctioned FROM/ARG/RUN/EXPOSE set: {offenders} "
        "— COPY/ENV/USER or a second RUN forks the pinned terminal build (the re-export law, D35 shape)"
    )
    assert keywords[:1] == ["FROM"] and keywords[-1:] == ["EXPOSE"], (
        f"C01 AC1: the flash-attn layer must sit between the FROM(+ledger) block and EXPOSE "
        f"(the R5.2 placement), got the instruction sequence {keywords}"
    )
    counts = {k: keywords.count(k) for k in ("FROM", "ARG", "RUN", "EXPOSE")}
    assert counts == {"FROM": 1, "ARG": 1, "RUN": 1, "EXPOSE": 1}, (
        f"C01 AC1 (D35): the law allows EXACTLY the flash-attn version ARG + single RUN "
        f"(the D34 git ARG pair is superseded), got {keywords}"
    )
    # The ledger header names what the FROM line cannot: the source commit,
    # the engine identity, the artifact size and the push date (C01 task).
    for token in (V.SRC_COMMIT[:12], V.ENGINE_COMMIT[:8], "4,079,863,554", "2026-10-18"):
        assert token in text, (
            f"C01 AC2: the Dockerfile ledger comment lacks {token!r} (source commit / engine "
            "identity / size / push date — the build-critical record dev re-verifies at the registry)"
        )


def test_c01_readme_ledger():
    """C01 AC2/AC3: the README is the ledger home — the tag→pin table, the
    tag↔commit law + the release-branch watch, the manual-bump procedure
    (Hub curl + registry probe + on-target re-bench) and the interface
    contract C02/C03 build against."""
    rd = CONTAINER_DIR / "README.md"
    assert rd.is_file(), "C01 AC2: containers/vllm-radiance-mxfp4/README.md missing — the ledger is not implemented"
    text = rd.read_text()
    flat = re.sub(r"\s+", " ", text)
    for token in (V.UPSTREAM_TAG, "sha-5b99d66c844f", V.SRC_COMMIT[:8], V.ENGINE_COMMIT[:8],
                  V.UPSTREAM_DIGEST, "0.30.0"):
        assert token in text, (
            f"C01 AC2: the ledger is missing the pin-set token {token!r} (the tag / the sha-"
            "sibling tag / the source commit / the engine identity / the digest)"
        )
    for token in ("torch", "triton", "AITER", "libr4d", "ROCm",
                  "2.12.0", "3.7.1", "0.1.20", "0.5.0", "7.14"):
        assert token in text, f"C01 AC2: the stack record is missing {token!r}"
    assert re.search(r"(?i)release[- ]branch", text), (
        "C01 AC2: no release-branch watch line — publishes are release-branch-only, the next "
        "1.0.<n>/sha pair is the bump trigger, NOT main movement (R3 conflict #4)"
    )
    assert re.search(r"(?i)bump", text), "C01 AC2: the watch/bump-trigger line is absent"
    assert "hub.docker.com" in text and re.search(r"(?i)manifest", text) and re.search(r"(?i)re-?bench", text), (
        "C01 AC2: the manual-bump procedure (Hub tags API curl + registry manifest probe + "
        "on-target re-bench) is not documented"
    )
    assert "org.opencontainers.image.revision" in text, (
        "C01 AC2: the bump procedure must name the config-blob OCI revision label read — the "
        "fourth corroboration of the pin (R3 L1.1)"
    )
    # AC3: the interface contract's five named laws + the entrypoint record.
    assert "/opt/radiance_entrypoint.sh" in text and "exec vllm serve" in flat, (
        'C01 AC3: the interface contract must name the entrypoint and the `exec vllm serve "$@"` '
        "form — the pod-args-start-with-the-model-path law falls out of it (R3 L1.3)"
    )
    assert re.search(r"(?i)args\s+start\s+with\s+the\s+model\s+path", flat), (
        "C01 AC3: the args-start-with-the-model-path law is not stated"
    )
    for token in ("/models", "/cache", "root", "AITER", "RADIANCE_"):
        assert token in text, f"C01 AC3: the interface contract is missing {token!r}"
    assert re.search(r"(?i)chat[- ]template", text), (
        "C01 AC3: the chat-template absence (the checkpoint-native default) is not recorded"
    )
    # The tag↔digest pairing across the two surfaces (the ledger law).
    df_digests = set(re.findall(r"sha256:[0-9a-f]{64}", (CONTAINER_DIR / "Dockerfile").read_text()))
    rd_digests = set(re.findall(r"sha256:[0-9a-f]{64}", text))
    assert df_digests & rd_digests, (
        "C01 AC2: the Dockerfile ledger digest and the README ledger table share no full "
        "sha256 digest — the tag↔digest pairing is inconsistent"
    )


def test_c01_vllm_rocm_retired():
    """C01 AC1: the GGUF overlay directory is gone and no FUNCTIONAL
    reference to it remains on the surfaces this chunk owns (containers/,
    .github/, charts/vllm/tests/). The chart's own image pin is C02's and is
    out of this scan set; the runbook names it until C05 — the wave order
    guarantees both."""
    legacy_dir = V.REPO_ROOT / "containers" / V.LEGACY_REF
    assert not legacy_dir.exists(), f"C01 AC1: {legacy_dir} still exists — the overlay must be git rm-ed"
    scanned = list((V.REPO_ROOT / "containers").rglob("*")) + list((V.REPO_ROOT / ".github").rglob("*")) \
        + list((CHART_DIR / "tests").rglob("*"))
    hits = []
    for path in scanned:
        if not _scannable(path):
            continue
        if V.LEGACY_REF in path.read_text(errors="replace"):
            hits.append(str(path.relative_to(V.REPO_ROOT)))
    assert not hits, (
        f"C01 AC1: functional references to the retired overlay remain at {hits} — update the "
        "trigger paths / ledger names, do not re-add the image"
    )


# --- AC7: the per-chart CI workflow ---------------------------------------------------


def test_ac7_workflow_exists_and_parses():
    assert V.WORKFLOW.is_file(), "C02 AC7: .github/workflows/vllm-render-tests.yaml missing"
    wf = yaml.safe_load(V.WORKFLOW.read_text())
    assert isinstance(wf, dict), "C02 AC7: the workflow YAML does not parse to a mapping"
    # YAML 1.1 parses the bare `on:` key as boolean True; accept both.
    on = wf.get("on", wf.get(True))
    assert isinstance(on, dict), "C02 AC7: the workflow has no on: trigger block"
    want_paths = {
        "charts/vllm/**",
        "containers/vllm-radiance-mxfp4/**",
        "services/gpu-ai/prod/values.yaml",
        ".github/workflows/vllm-render-tests.yaml",
    }
    for kind in ("push", "pull_request"):
        paths = set((on.get(kind) or {}).get("paths") or [])
        assert paths == want_paths, (
            f"C01 AC7: the {kind} trigger paths must be EXACTLY the 4-path set — missing "
            f"{sorted(want_paths - paths)}, stale {sorted(paths - want_paths)} (the C01 swap "
            "replaces the retired container path and nothing else moves)"
        )

    runs = []

    def walk(node):
        if isinstance(node, dict):
            if isinstance(node.get("run"), str):
                runs.append(node["run"])
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(wf)
    joined = "\n".join(runs)
    for ladder in ("helm dependency update charts/vllm", "pytest charts/vllm/tests", "helm lint charts/vllm"):
        assert ladder in joined, f"C02 AC7: the CI step ladder lacks '{ladder}'"
    template_steps = [r for r in runs if "helm template" in r and "charts/vllm" in r]
    assert template_steps, "C02 AC7: no helm template step over charts/vllm"
    assert any("-f" in r for r in template_steps), (
        "C02 AC7: the service-level -f render (the plan Commands pattern) is missing from the workflow"
    )
