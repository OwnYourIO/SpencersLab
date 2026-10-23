# C03 autogen-wiring contract: initContainer, base.yaml ConfigMap, emptyDir
# /app/gen, main-container env, degrade path, and the identity-key merge
# safety that v262 -config/-config-dir demands.
#
# ALL tests here are RED at write time for the same right reason: the wiring
# does not exist yet — no initContainer `autogen`, no ConfigMap
# `llama-swap-autogen-base`, no LLAMA_SWAP_CONFIG_DIR env (the renders are the
# pre-C03 chart). The degrade-script tests extract the initContainer command
# FROM THE RENDER and execute it in a sandbox with a stubbed autogen CLI, so
# the fail-open behavior (criterion 3) is a hard test CI can run — no docker,
# no network. The real-tool / real-image proofs live (skippable) in
# test_autogen_integration.py.

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

import pytest
import yaml

import llama_swap_testlib as L

_ok, _reason = L.helm_ready()
pytestmark = pytest.mark.skipif(not _ok, reason=_reason)

CLUSTERS = ["gpu", "gpu-ai"]

SCAN_PATH = "/models/scanned"          # plan C03: autogen.scanPaths: [/models/scanned]
GEN_DIR = "/app/gen"                    # emptyDir, init + main globalMounts
GEN_FILE = f"{GEN_DIR}/10-scanned.yaml"
BASE_DIR = "/app/autogen"               # base.yaml ConfigMap mount (init only)
BASE_CM = "llama-swap-autogen-base"
BASE_FILE = f"{BASE_DIR}/base.yaml"

# Env that must survive the wiring untouched (C03 acceptance 1: main gains
# ONLY LLAMA_SWAP_CONFIG_DIR). Values pinned from the golden-era chart values.
PINNED_MAIN_ENV = {
    "TZ": "Etc/UTC",
    "LLAMA_CACHE": "/models",
    "LLAMA_SWAP_CONFIG": "/app/config/config.yaml",
    "LLAMA_SWAP_WATCH_CONFIG": "true",
}

# v262 merge facts (DECISIONS, source-proven at v262 internal/config/merge.go):
# the scanned half may re-emit top-level scalars ONLY with identical values,
# and must never carry the identity-map keys that live in the declared half.
MERGE_SCALAR_KEYS = ("healthCheckTimeout", "logLevel", "startPort")
MERGE_FORBIDDEN_KEYS = ("matrix", "hooks", "groups")


def base_yaml(cluster: str) -> dict:
    cfg = L.configmap_data(cluster, BASE_CM, "base.yaml")
    assert isinstance(cfg, dict), f"{cluster}: base.yaml did not parse to a mapping"
    return cfg


# ---------------------------------------------------------------------------
# Acceptance 1: pod surface (both clusters)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c03_1_initcontainer_autogen_pinned_image(cluster):
    c = L.init_container(cluster, "autogen")
    img = c["image"]
    assert img.startswith(f"{L.AUTOGEN_IMAGE}:"), f"{cluster}: init image is {img!r}"
    # New-container exception (DECISIONS "Planning decisions"): :main + Always
    # until the first immutable :v<run> tag exists post-merge.
    assert img.endswith(":main"), f"{cluster}: expected the documented :main exception, got {img!r}"
    assert c.get("imagePullPolicy") == "Always", f"{cluster}: pullPolicy must be Always with :main"


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c03_1_initcontainer_security(cluster):
    c = L.init_container(cluster, "autogen")
    sc = c.get("securityContext") or {}
    assert "ALL" in (sc.get("capabilities") or {}).get("drop", []), f"{cluster}: caps not dropped"
    assert sc.get("allowPrivilegeEscalation") is False, f"{cluster}: privilege escalation"
    assert sc.get("runAsNonRoot") is True, f"{cluster}: must run non-root"
    assert sc.get("runAsUser") == 65532, f"{cluster}: autogen image runs as uid 65532 (C01 contract)"


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c03_1_initcontainer_mounts(cluster):
    c = L.init_container(cluster, "autogen")
    mounts = L.mount_paths(c)
    assert GEN_DIR in mounts, f"{cluster}: no {GEN_DIR} mount on initContainer"
    assert BASE_DIR in mounts, f"{cluster}: no {BASE_DIR} mount on initContainer"
    assert mounts[BASE_DIR].get("readOnly") is True, f"{cluster}: {BASE_DIR} must be readOnly"
    assert "/models" in mounts, f"{cluster}: scanner needs the models volume"


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c03_1_volumes_gen_emptydir_base_configmap(cluster):
    spec = L.pod_spec(cluster)
    by_name = {v["name"]: v for v in spec.get("volumes", [])}
    gen_vol = [v for v in by_name.values() if "emptyDir" in v]
    assert gen_vol, f"{cluster}: no emptyDir volume for {GEN_DIR}"
    cm_vol = [v for v in by_name.values()
              if (v.get("configMap") or {}).get("name") == BASE_CM]
    assert cm_vol, f"{cluster}: {BASE_CM} ConfigMap not projected into a pod volume"
    main = L.container(cluster, "main")
    assert GEN_DIR in L.mount_paths(main), f"{cluster}: main must see {GEN_DIR} (llama-swap reads it)"
    assert BASE_DIR not in L.mount_paths(main), (
        f"{cluster}: main container mount surface must be unchanged (base.yaml is init-only)"
    )


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c03_1_main_env_gains_only_config_dir(cluster):
    env = L.env_map(L.container(cluster, "main"))
    assert env.get("LLAMA_SWAP_CONFIG_DIR") == GEN_DIR, (
        f"{cluster}: LLAMA_SWAP_CONFIG_DIR missing/wrong: {env.get('LLAMA_SWAP_CONFIG_DIR')!r}"
    )
    for k, v in PINNED_MAIN_ENV.items():
        assert env.get(k) == v, f"{cluster}: pre-wiring env {k} changed: {env.get(k)!r} != {v!r}"
    assert L.container(cluster, "main")["image"] == L.FLEET_IMAGE, (
        f"{cluster}: llama-swap image must not change in this feature"
    )


# ---------------------------------------------------------------------------
# Acceptance 2 (render half): base.yaml carries the generator's contract
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c03_2_base_yaml_scan_and_binary(cluster):
    b = base_yaml(cluster)
    assert isinstance(b.get("models"), list), (
        "base.yaml `models:` must be the generator's scan-path LIST "
        f"(pinned template.yaml shape), got {type(b.get('models')).__name__}"
    )
    assert SCAN_PATH in b["models"], f"{cluster}: scan path {SCAN_PATH} not in base.yaml models"
    macros = b.get("macros") or {}
    assert macros.get("binary") == "/usr/local/bin/llama-server", (
        f"{cluster}: macros.binary must point at the unified image's llama-server: {macros.get('binary')!r}"
    )


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c03_2_base_yaml_metadata_flags(cluster):
    """Plan C03: read_gguf_metadata on, vram_estimation off (the latter needs
    fit-params exec + --llama-bin, out of scope)."""
    b = base_yaml(cluster)
    assert b.get("read_gguf_metadata") is True, "read_gguf_metadata must be on"
    assert b.get("vram_estimation") in (False, None), "vram_estimation must stay off"


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c03_2_base_yaml_carries_no_declared_half_keys(cluster):
    """Two-file merge safety at the SOURCE level (DECISIONS "Merge-semantics
    refinement"): matrix in both halves is a v262 hard error (its children are
    identity keys), hooks/groups likewise; and any top-level scalar the
    generator re-emits must be IDENTICAL to the declared half or absent —
    differing scalars hard-error the load."""
    b = base_yaml(cluster)
    for k in MERGE_FORBIDDEN_KEYS:
        assert k not in b, f"{cluster}: base.yaml carries {k!r} — v262 merge load error"
    declared = L.rendered_config(cluster)
    for k in MERGE_SCALAR_KEYS:
        if k in b:
            assert b[k] == declared.get(k), (
                f"{cluster}: base.yaml {k}={b[k]!r} conflicts with declared {k}={declared.get(k)!r} "
                "(scalar mismatch across config sources is a hard error)"
            )


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c03_2_base_yaml_macros_are_a_superset_slice(cluster):
    """base.yaml `macros` render from config.macros (plan C03) — whatever it
    emits under those shared names must be byte-equal to the declared half, so
    the macro union across files cannot collide. (Extra generator-only macros
    like `binary` are fine: they simply don't exist on the declared side.)"""
    base = base_yaml(cluster)
    declared = L.rendered_config(cluster)
    shared = set((base.get("macros") or {})) & set(declared.get("macros") or {})
    bad = [m for m in shared
           if re.sub(r"\s+", " ", str(base["macros"][m]).strip())
           != re.sub(r"\s+", " ", str(declared["macros"][m]).strip())]
    assert not bad, f"{cluster}: base.yaml macros diverge from declared under shared names: {bad}"


# ---------------------------------------------------------------------------
# Acceptance 3: degrade path — executable contract on the RENDERED script
# ---------------------------------------------------------------------------


def _init_script(cluster: str) -> str:
    c = L.init_container(cluster, "autogen")
    argv = list(c.get("command") or []) + list(c.get("args") or [])
    assert argv, f"{cluster}: initContainer autogen has no command — degrade logic missing"
    if "-c" in argv:
        # The script is the element AFTER the last "-c"; the previous
        # `len(argv) - 1 - ...` form returned the "-c" token itself (coord-
        # routed defect C amendment, 2026-10-23).
        return argv[len(argv) - argv[::-1].index("-c")]
    return "\n".join(argv)


def _sandbox(cluster: str, tmp_path: Path, stub: str | None, ggufs: bool) -> tuple[Path, dict]:
    """Rewrite the rendered script's contract paths into a throwaway tree and
    expose the stub CLI on PATH. Path literals are pinned by the plan
    (/app/gen, /app/autogen, /models mounts) — a dev-side path change is a
    contract change, which is exactly what this test catches."""
    sb = tmp_path / "sb"
    script = _init_script(cluster)
    for lit in (BASE_DIR, GEN_DIR, "/models"):
        script = script.replace(lit, str(sb) + lit)
    assert str(sb) in script, (
        f"{cluster}: init script references none of the pinned mount paths "
        f"({BASE_DIR}, {GEN_DIR}, /models) — cannot run the degrade contract"
    )
    (sb / "app/gen").mkdir(parents=True, exist_ok=True)
    (sb / "app/autogen").mkdir(parents=True, exist_ok=True)
    (sb / "app/autogen/base.yaml").write_text("models: []\n")  # presence only; stub never reads it
    scanned = sb / "models/scanned"
    scanned.mkdir(parents=True, exist_ok=True)
    if ggufs:
        d = scanned / "fixture-model"
        d.mkdir(parents=True, exist_ok=True)
        (d / "fixture-Q4_K_M.gguf").write_bytes(b"GGUF")  # script only counts files
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    if stub is not None:
        (bin_dir / "llama-swap-config-autogen").write_text(stub)
        os.chmod(bin_dir / "llama-swap-config-autogen", 0o755)
    env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", HOME=str(tmp_path))
    return script, env


def _comment_only(path: Path) -> bool:
    if not path.exists():
        return False
    body = path.read_text()
    if not body.strip():
        return True
    lines = [ln for ln in body.splitlines() if ln.strip()]
    return all(ln.lstrip().startswith("#") for ln in lines) and bool(lines)


FAIL_STUB = """#!/bin/sh
echo "stub: simulating the pinned tool's empty-scan failure" >&2
echo 'ERROR: Generation failed: No models found.' >&2
exit 1
"""

OK_STUB = """#!/bin/sh
out=""
prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] || [ "$prev" = "--output" ] && out="$a"
  prev="$a"
done
printf 'models:\\n  fixture:Q4_K_M:\\n    ttl: 300\\n    cmd: ${binary} -m /models/scanned/fixture-model/fixture-Q4_K_M.gguf --port ${PORT} --host 0.0.0.0\\n    name: fixture:Q4_K_M\\n' > "$out"
exit 0
"""


def test_c03_3_degrade_empty_scan_is_comment_only_and_exit0(tmp_path):
    """Stock tool on an empty scan set exits nonzero "No models found"
    (RESEARCH reliability note; proven by the real pinned binary in the
    gated integration file). The initContainer must degrade: write a
    comment-only 10-scanned.yaml and EXIT 0 — fail-open (DECISIONS
    "Degrade path") because crashlooping costs the lab's live consumers."""
    script, env = _sandbox("gpu", tmp_path, stub=None, ggufs=False)
    r = subprocess.run(["/bin/sh", "-c", script], capture_output=True, text=True,
                       env=env, timeout=120, cwd=tmp_path)
    assert r.returncode == 0, f"degrade path must exit 0, got {r.returncode}\n{r.stderr}"
    assert _comment_only(tmp_path / "sb/app/gen/10-scanned.yaml"), (
        "empty scan did not leave a comment-only 10-scanned.yaml "
        f"(content: {(tmp_path / 'sb/app/gen/10-scanned.yaml').exists() and (tmp_path / 'sb/app/gen/10-scanned.yaml').read_text()[:200]!r})"
    )


def test_c03_3_degrade_generate_failure_is_fail_open(tmp_path):
    """If generate runs but exits nonzero (crash, bad GGUF in the tree), the
    script must still exit 0 with a comment-only file — never propagate the
    failure into a pod crashloop."""
    script, env = _sandbox("gpu", tmp_path, stub=FAIL_STUB, ggufs=True)
    r = subprocess.run(["/bin/sh", "-c", script], capture_output=True, text=True,
                       env=env, timeout=120, cwd=tmp_path)
    assert r.returncode == 0, f"fail-open violated: rc={r.returncode}\n{r.stderr}\n{r.stdout}"
    assert _comment_only(tmp_path / "sb/app/gen/10-scanned.yaml"), \
        "after generate failure the scanned file must be comment-only"


def test_c03_3_degrade_success_keeps_generated_content(tmp_path):
    """Happy path stays untouched: when the (stubbed) generator succeeds, the
    script must not clobber its output — the file must parse as a models map
    containing the generated ID."""
    script, env = _sandbox("gpu", tmp_path, stub=OK_STUB, ggufs=True)
    r = subprocess.run(["/bin/sh", "-c", script], capture_output=True, text=True,
                       env=env, timeout=120, cwd=tmp_path)
    assert r.returncode == 0, f"rc={r.returncode}\n{r.stderr}"
    f = tmp_path / "sb/app/gen/10-scanned.yaml"
    assert f.exists(), "successful generate left no output file"
    data = yaml.safe_load(f.read_text())
    assert isinstance(data, dict) and "fixture:Q4_K_M" in (data.get("models") or {}), \
        f"generated content was clobbered or lost: {data!r}"


# ---------------------------------------------------------------------------
# Acceptance 4 (pure half): identity-key namespace disjointness
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c03_4_declared_model_ids_are_colon_free(cluster):
    """Generated IDs live in the `<dir>:<QUANT>` namespace (pinned generator,
    source-verified). The declared half may therefore never use ':' in a model
    ID — structural guarantee that the two halves' `models` identity maps can
    not collide across files (duplicate children = v262 hard error)."""
    ids = set(L.all_models_of(L.rendered_config(cluster)))
    colon = [i for i in ids if ":" in i]
    assert not colon, f"{cluster}: declared model IDs in the scanned namespace: {colon}"


def test_c03_4_synthetic_scanned_half_disjoint_from_declared():
    """Merge safety against a synthetic scanned half shaped exactly like
    autogen output (ttl/cmd/name + generator-only macros). Disjoint model IDs
    and no same-name-different-value macros/scalars across the two files —
    the real-merge proof (full `llama-swap -validate`) is the gated
    docker test in test_autogen_integration.py."""
    scanned = yaml.safe_load((L.FIXTURES_DIR / "scanned_synthetic.yaml").read_text())
    for cluster in CLUSTERS:
        declared = L.rendered_config(cluster)
        overlap = set(scanned["models"]) & set(L.all_models_of(declared))
        assert not overlap, f"{cluster}: duplicate model identity keys across config files: {overlap}"
        shared_macros = set(scanned.get("macros") or {}) & set(declared.get("macros") or {})
        for m in shared_macros:
            assert str(scanned["macros"][m]).strip() == str(declared["macros"][m]).strip(), (
                f"{cluster}: macro {m!r} differs across the two config sources"
            )
        for k in MERGE_SCALAR_KEYS:
            if k in scanned:
                assert scanned[k] == declared.get(k), (
                    f"{cluster}: scanned half re-emits {k} with a conflicting value"
                )


# ---------------------------------------------------------------------------
# Reload semantics guard (plan C03 task 5 / DECISIONS reload statement)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c03_5_reloader_annotation_covers_both_configmaps(cluster):
    """The pod must roll on data change of EITHER ConfigMap: the annotation
    is already on the controller; if auto mode misses the new CM, an explicit
    reloader.stakater.com/match listing both is required (plan risks)."""
    for doc in L.render_docs(cluster):
        if doc.get("kind") == "Deployment":
            dep_ann = (doc.get("metadata") or {}).get("annotations") or {}
            pod_ann = (doc["spec"]["template"].get("metadata") or {}).get("annotations") or {}
            break
    else:
        raise AssertionError("no Deployment rendered")
    ann = {**dep_ann, **pod_ann}  # stakater reads either depending on mount path
    if ann.get("reloader.stakater.com/auto") == "true":
        return  # auto mode covers mounted ConfigMaps incl. the new one
    match = ann.get("reloader.stakater.com/match", "")
    needed = {"llama-swap-config", BASE_CM}
    assert needed <= set(match.split(",")), (
        f"{cluster}: neither auto-reload nor explicit match for both CMs: {ann}"
    )
