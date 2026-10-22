# C03/C04 real-runtime EVIDENCE tests, deliberately skip-gated: they run the
# pinned autogen tool (venv install from the commit tarball) and the fleet
# image (`llama-swap -validate`) — the plan's Commands section. The CI job
# (llama-swap-tools-tests.yaml) never provisions these (image pull is GBs; a
# hard test CI can never run would be a faulty validation by construction),
# so the chunk acceptance evidence is: run locally with LLAMA_SWAP_EVIDENCE=1
# before the wave gate, exactly as the chunk files' skip-guard notes require.
#
#   LLAMA_SWAP_EVIDENCE=1  pytest charts/llama-swap/tests/test_autogen_integration.py -v
#   RUN_HF_CHECK=1 additionally enables the HuggingFace API re-verification
#   (needs network to huggingface.co; HF_TOKEN for gated repos).
#
# Skips always carry the reason so review knows whether evidence RAN or was
# DEFERRED (chunks/C03.md "Tests").

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

import llama_swap_testlib as L

EVIDENCE = os.environ.get("LLAMA_SWAP_EVIDENCE") == "1"

pytestmark = pytest.mark.skipif(
    not EVIDENCE,
    reason=(
        "evidence-gated (deferred): run with LLAMA_SWAP_EVIDENCE=1 where docker/"
        "network exist — see TEST_SPEC.md; CI defers these by design"
    ),
)


@pytest.fixture(scope="session")
def autogen_cli(tmp_path_factory):
    """venv with the pinned autogen tarball (plan Commands verbatim).
    Skips with the pip error if the environment can't build it."""
    root = tmp_path_factory.mktemp("autogen-venv")
    venv = root / "venv"
    py = sys.executable
    try:
        subprocess.run([py, "-m", "venv", str(venv)], check=True, timeout=300)
        subprocess.run(
            [str(venv / "bin" / "pip"), "install", "--quiet",
             f"llama-swap-config-autogen @ {L.AUTOGEN_TARBALL_URL}"],
            check=True, timeout=900,
        )
    except (subprocess.SubprocessError, subprocess.CalledProcessError) as e:
        output = getattr(e, "output", b"") or b""
        pytest.skip(f"pinned autogen install unavailable: {e} {output[:300]!r}")
    return str(venv / "bin" / "llama-swap-config-autogen")


@pytest.fixture(scope="session")
def fleet_image():
    ok, reason = L.docker_ready()
    if not ok:
        pytest.skip(f"docker evidence needs a daemon: {reason}")
    inspect = subprocess.run(["docker", "image", "inspect", L.FLEET_IMAGE],
                             capture_output=True, text=True, timeout=60)
    if inspect.returncode != 0:
        pull = subprocess.run(["docker", "pull", L.FLEET_IMAGE],
                              capture_output=True, text=True, timeout=2400)
        if pull.returncode != 0:
            pytest.skip(f"fleet image unavailable offline (pull failed): {pull.stderr[:300]}")
    return L.FLEET_IMAGE


def _rendered_base_yaml(cluster: str, tmp_path: Path, scan_dir: Path | None = None) -> Path:
    assert L.helm_ready()[0], "helm required to render base.yaml for evidence"
    body = L.configmap_data(cluster, "llama-swap-autogen-base", "base.yaml")
    if scan_dir is not None:
        # Evidence sandbox: point the scan paths at a writable fixture tree.
        # Path rewriting is legitimate here because the host has no /models.
        body = {**body, "models": [str(scan_dir)]}
    out = tmp_path / f"base-{cluster}.yaml"
    out.write_text(yaml.safe_dump(body))
    return out


# ---------------------------------------------------------------------------
# Acceptance C03-2/3: base.yaml parses for the pinned tool; empty scan fails
# exactly the stock "No models found" way (proves the degrade trigger state).
# ---------------------------------------------------------------------------

PARSE_ERROR_MARKERS = ("not of type", "Input should be", "validation error", "pydantic")


@pytest.mark.parametrize("cluster", ["gpu", "gpu-ai"])
def test_c03_2_3_base_yaml_parses_and_empty_scan_fails_stock(cluster, autogen_cli, tmp_path):
    base = _rendered_base_yaml(cluster, tmp_path, scan_dir=tmp_path / "empty-scan")
    r = subprocess.run([autogen_cli, "generate", "--config", str(base),
                        "-o", str(tmp_path / "out.yaml")],
                       capture_output=True, text=True, timeout=300)
    combined = r.stdout + r.stderr
    assert r.returncode != 0, (
        f"{cluster}: stock generate unexpectedly exited 0 on an empty scan set — "
        "the premise of the fail-open degrade path (RESEARCH note 8/10) is broken"
    )
    assert "No models found" in combined, f"{cluster}: wrong failure mode:\n{combined[:500]}"
    for marker in PARSE_ERROR_MARKERS:
        assert marker.lower() not in combined.lower(), (
            f"{cluster}: rendered base.yaml is not schema-valid for the pinned "
            f"generator ({marker}):\n{combined[:800]}"
        )


# ---------------------------------------------------------------------------
# Acceptance C03-4 (tool half): fixture GGUF scan tree -> generate -> validate
# ---------------------------------------------------------------------------

GGUF_MAKER = """
import sys
sys.path.insert(0, {scripts!r})
import gguf
from pathlib import Path
root = Path({root!r})
for name, quant in (("mini", "Q4_K_M"), ("big", "BF16")):
    d = root / f"fixture-{{name}}"
    d.mkdir(parents=True, exist_ok=True)
    w = gguf.GGUFWriter(d / f"model-{{quant}}.gguf", "qwen3")
    w.add_string("general.name", name)
    w.write_header_to_file()
    w.write_kv_data_to_file()
    w.write_tensors_to_file()
    w.close()
"""

_ID_NS = re.compile(r"^[a-z0-9._/-]+:(Q\d(_[A-Z0-9]+)+|BF16|F16)$")


def test_c03_4_scanned_half_generates_validates_and_is_disjoint(autogen_cli, tmp_path):
    scan = tmp_path / "scanned"
    scan.mkdir()
    maker = GGUF_MAKER.format(scripts=str(L.CHART_DIR / "scripts" / "gguf-py"), root=str(scan))
    subprocess.run([os.path.dirname(autogen_cli) + "/python", "-c", maker],
                   check=True, capture_output=True, text=True, timeout=300)

    base = _rendered_base_yaml("gpu", tmp_path, scan_dir=scan)
    out = tmp_path / "10-scanned.yaml"
    gen = subprocess.run([autogen_cli, "generate", "--config", str(base), "-o", str(out)],
                         capture_output=True, text=True, timeout=300)
    assert gen.returncode == 0, f"generate failed on a valid fixture tree:\n{gen.stderr[:800]}"
    scanned = yaml.safe_load(out.read_text())
    ids = set(L.all_models_of(scanned))
    assert ids, "generate produced no models over a tree with GGUFs"
    assert all(_ID_NS.match(i) for i in ids), f"generated IDs outside <dir>:<QUANT> namespace: {ids}"

    val = subprocess.run([autogen_cli, "validate", str(out), "-q"],
                         capture_output=True, text=True, timeout=120)
    assert val.returncode == 0, f"generated half fails the tool's own validator:\n{val.stdout}{val.stderr}"

    declared = L.rendered_config("gpu")
    assert not ids & set(L.all_models_of(declared)), "generated/declared identity collision"
    for k in ("healthCheckTimeout", "logLevel", "startPort"):
        if k in scanned:
            assert scanned[k] == declared.get(k), (
                f"generated half re-emits {k}={scanned[k]!r} vs declared {declared.get(k)!r} "
                "— v262 scalar-conflict load error waiting on the cluster"
            )
    for m in set(scanned.get("macros") or {}) & set(declared.get("macros") or {}):
        assert str(scanned["macros"][m]).strip() == str(declared["macros"][m]).strip(), (
            f"macro {m!r} differs across the two config sources"
        )


# ---------------------------------------------------------------------------
# Acceptance C03-4/5 + C04-4: llama-swap's own -validate on the merged config
# (the definitive cross-file load proof — same flag fleet ops will use).
# ---------------------------------------------------------------------------


def _write_declared(cluster: str, dest_dir: Path) -> Path:
    assert L.helm_ready()[0], "helm required to render the declared half"
    body = L.configmap_data(cluster, "llama-swap-config", "config.yaml")
    f = dest_dir / "config.yaml"
    f.write_text(yaml.safe_dump(body))
    return f


def _llama_swap_validate(fleet_image: str, declared: Path, gen_dir: Path, tag: str) -> None:
    r = subprocess.run(
        ["docker", "run", "--rm",
         "-v", f"{declared.parent}:/c/declared:ro",
         "-v", f"{gen_dir}:/c/gen",
         fleet_image,
         "-config", "/c/declared/config.yaml", "-config-dir", "/c/gen", "-validate"],
        capture_output=True, text=True, timeout=600,
    )
    assert r.returncode == 0, f"{tag}: llama-swap -validate rejected the merged config:\n{r.stdout[-2000:]}\n{r.stderr[-2000:]}"


def test_c03_5_declared_only_with_empty_config_dir_validates(fleet_image, tmp_path):
    """Empty -config-dir alongside -config is valid (v262 listYAMLFiles) —
    today's steady state after the degrade path."""
    declared = _write_declared("gpu", tmp_path / "declared")
    gen = tmp_path / "gen"
    gen.mkdir()
    _llama_swap_validate(fleet_image, declared, gen, "gpu declared-only")


def test_c03_4_merged_declared_plus_scanned_validates(fleet_image, autogen_cli, tmp_path):
    """The split's whole point: declared half + a real autogen-scanned half
    merge-load in the fleet image with zero identity/scalar conflicts."""
    scan = tmp_path / "scanned"
    scan.mkdir()
    maker = GGUF_MAKER.format(scripts=str(L.CHART_DIR / "scripts" / "gguf-py"), root=str(scan))
    subprocess.run([os.path.dirname(autogen_cli) + "/python", "-c", maker],
                   check=True, capture_output=True, text=True, timeout=300)
    base = _rendered_base_yaml("gpu", tmp_path, scan_dir=scan)
    gen = tmp_path / "gen"
    gen.mkdir()
    r = subprocess.run([autogen_cli, "generate", "--config", str(base),
                        "-o", str(gen / "10-scanned.yaml")],
                       capture_output=True, text=True, timeout=300)
    assert r.returncode == 0, r.stderr[:500]
    declared = _write_declared("gpu", tmp_path / "declared")
    _llama_swap_validate(fleet_image, declared, gen, "gpu merged")


@pytest.mark.parametrize("cluster", ["gpu", "gpu-ai"])
def test_c04_4_full_roster_declared_validates(fleet_image, cluster, tmp_path):
    """C04 acceptance 4: per-cluster declared render (including the enlarged
    new-family roster once C04 lands) passes `-validate` in the fleet image.
    Config-level proof only — no gpu-ai serving (DECISIONS)."""
    declared = _write_declared(cluster, tmp_path / "declared")
    gen = tmp_path / "gen"
    gen.mkdir()
    _llama_swap_validate(fleet_image, declared, gen, f"{cluster} roster")


# ---------------------------------------------------------------------------
# C04-1 HF re-verification (run at review per chunks/C04.md; CI network-gated)
# ---------------------------------------------------------------------------


def test_c04_1_hf_repo_tags_resolve():
    if os.environ.get("RUN_HF_CHECK") != "1":
        pytest.skip("RUN_HF_CHECK=1 to re-verify every -hf/-hfd ref against the HF API")
    sys.path.insert(0, str(L.TESTS_DIR))
    import hf_check
    problems = hf_check.collect_problems(hf_check.refs_from_renders())
    assert not problems, "HF refs failed to resolve:\n" + "\n".join(problems)
