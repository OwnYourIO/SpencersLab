# C03 autogen-wiring contract: initContainer, base.yaml ConfigMap, emptyDir
# /app/gen, main-container env, degrade path, and the identity-key merge
# safety that v262 -config/-config-dir demands.
#
# C03-era tests: the wiring existed as RED-vs-green through C03; post-C03
# they pin the landed surface (all green at CA1 handoff except where CA4
# re-bases them).
#
# REPLAN rebase (amendment K, 2026-10-24, CR4): the degrade logic MOVES OUT of
# the k8s yaml into containers/llama-swap-autogen/entrypoint.sh. The three
# fail-open contracts are now executed DIRECTLY against that repo file with
# flags (--scan-dir/--base/--out/--home + a stub CLI on PATH) — daemon-free,
# CI-runnable; red at CA1 handoff because the file does not exist yet (CA4).
# The pod assertions FLIP: initContainer carries image + args + mounts and NO
# command; the drift probes pin that the helper FAILS THE RENDER when args and
# scanPaths disagree or when any command: is (re)introduced.

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


ENTRYPOINT = L.ENTRYPOINT_FILE

# Stubbed autogen CLI (on PATH for the sandboxed entrypoint runs). FAIL_STUB
# replays the pinned tool's real empty-scan behavior (source + live verified:
# exit 1, "No models found" on stderr); OK_STUB emits the real generated-half
# shape (ttl/cmd/name + <dir>:<QUANT> id).
FAIL_STUB = """#!/bin/sh
echo "stub: simulating the pinned tool's empty-scan failure" >&2
echo 'ERROR: Generation failed: No models found.' >&2
exit 1
"""

OK_STUB = """#!/bin/sh
out=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-o" ] || [ "$prev" = "--output" ]; then out="$a"; fi
  prev="$a"
done
printf 'models:\n  fixture:Q4_K_M:\n    ttl: 300\n    cmd: ${binary} -m /models/scanned/fixture-model/fixture-Q4_K_M.gguf --port ${PORT} --host 0.0.0.0\n    name: fixture:Q4_K_M\n' > "$out"
exit 0
"""



def _require_entrypoint() -> str:
    assert ENTRYPOINT.is_file(), (
        f"{ENTRYPOINT} missing — CA4 has not landed the image entrypoint that "
        "owns the generate/degrade/fail-open logic"
    )
    return str(ENTRYPOINT)


def _ep_sandbox(tmp_path, stub: str | None, ggufs: bool, home: str | None = None):
    """Flag-driven sandbox (no path rewriting — the entrypoint takes flags).
    Returns argv + env for `sh entrypoint.sh --scan-dir … --base … --out …
    --home …`."""
    sb = tmp_path / "sb"
    (sb / "app/gen").mkdir(parents=True, exist_ok=True)
    (sb / "app/autogen").mkdir(parents=True, exist_ok=True)
    (sb / "app/autogen/base.yaml").write_text("models: []\n")
    scanned = sb / "models/scanned"
    scanned.mkdir(parents=True, exist_ok=True)
    if ggufs:
        d = scanned / "fixture-model"
        d.mkdir(parents=True, exist_ok=True)
        (d / "fixture-Q4_K_M.gguf").write_bytes(b"GGUF")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    if stub is not None:
        sp = bin_dir / "llama-swap-config-autogen"
        sp.write_text(stub)
        import os
        os.chmod(sp, 0o755)
    home_dir = sb / ("home" if home is None else home)
    argv = ["sh", _require_entrypoint(),
            "--scan-dir", str(scanned),
            "--base", str(sb / "app/autogen/base.yaml"),
            "--out", str(sb / "app/gen/10-scanned.yaml"),
            "--home", str(home_dir)]
    env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", HOME=str(tmp_path / "unset-home"))
    return argv, env, (sb / "app/gen/10-scanned.yaml"), home_dir


import os  # noqa: E402  (used by _ep_sandbox env PATH building; kept explicit for stub chmod)


def test_c03_3_degrade_empty_scan_is_comment_only_and_exit0(tmp_path):
    """Stock tool on an empty scan set exits nonzero "No models found"
    (RESEARCH reliability note; proven by the real pinned binary in the
    gated integration file). The initContainer must degrade: write a
    comment-only 10-scanned.yaml and EXIT 0 — fail-open (DECISIONS
    "Degrade path") because crashlooping costs the lab's live consumers."""
    argv, env, out_f, _home = _ep_sandbox(tmp_path, stub=None, ggufs=False)
    r = subprocess.run(argv, capture_output=True, text=True, env=env, timeout=120, cwd=tmp_path)
    assert r.returncode == 0, f"degrade path must exit 0, got {r.returncode}\n{r.stderr}"
    assert _comment_only(out_f), (
        f"empty scan did not leave a comment-only 10-scanned.yaml "
        f"(exists={out_f.exists()}, content={out_f.read_text()[:200]!r})"
        if out_f.exists() else
        "empty scan left no 10-scanned.yaml at all"
    )


def test_c03_3_degrade_generate_failure_is_fail_open(tmp_path):
    """If generate runs but exits nonzero (crash, bad GGUF in the tree), the
    script must still exit 0 with a comment-only file — never propagate the
    failure into a pod crashloop."""
    argv, env, out_f, _home = _ep_sandbox(tmp_path, stub=FAIL_STUB, ggufs=True)
    r = subprocess.run(argv, capture_output=True, text=True, env=env, timeout=120, cwd=tmp_path)
    assert r.returncode == 0, f"fail-open violated: rc={r.returncode}\n{r.stderr}\n{r.stdout}"
    assert _comment_only(out_f), "after generate failure the scanned file must be comment-only"


def test_c03_3_degrade_success_keeps_generated_content(tmp_path):
    """Happy path stays untouched: when the (stubbed) generator succeeds, the
    script must not clobber its output — the file must parse as a models map
    containing the generated ID."""
    argv, env, out_f, _home = _ep_sandbox(tmp_path, stub=OK_STUB, ggufs=True)
    r = subprocess.run(argv, capture_output=True, text=True, env=env, timeout=120, cwd=tmp_path)
    assert r.returncode == 0, f"rc={r.returncode}\n{r.stderr}"
    f = out_f
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


# ---------------------------------------------------------------------------
# CR4/CA4 additions — red at CA1 handoff, all naming CA4
# ---------------------------------------------------------------------------

HOME_STUB = """#!/bin/sh
out=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-o" ] || [ "$prev" = "--output" ]; then out="$a"; fi
  prev="$a"
done
printf 'HOME=%s\n' "${HOME-unset}" > "__RECORD__"
printf 'models:\n  fixture:Q4_K_M:\n    ttl: 300\n    cmd: ${binary} -m /models/scanned/fixture-model/fixture-Q4_K_M.gguf --port ${PORT} --host 0.0.0.0\n    name: fixture:Q4_K_M\n' > "$out"
exit 0
"""


def test_c04_entrypoint_missing_required_flag_is_usage_error(tmp_path):
    """CR4: a wiring bug must surface LOUDLY — missing --out exits nonzero with
    a usage message. Degrade-rc0 stays reserved for scan-empty/generate-fail,
    never for arg errors."""
    ep = _require_entrypoint()
    sb = tmp_path / "sb"
    (sb / "scanned").mkdir(parents=True)
    scanned_dir = tmp_path / "scan"
    scanned_dir.mkdir()
    r = subprocess.run(["sh", ep,
                        "--scan-dir", str(scanned_dir),
                        "--base", str(sb / "nonexistent-base.yaml"),
                        "--home", str(sb / "home")],
                       capture_output=True, text=True, timeout=120, cwd=tmp_path)
    assert r.returncode != 0, "missing --out was silently accepted (usage error required)"
    assert (r.stdout + r.stderr).strip(), "usage error produced no message"


def test_c04_entrypoint_home_flag_drives_generate_home(tmp_path):
    """CR4: --home exports HOME before invoking the generator — making the
    C03-review writable-cache contract (finding #1) explicit on the CLI."""
    record = tmp_path / "home-record"
    stub = HOME_STUB.replace("__RECORD__", str(record))
    argv, env, _out, home_dir = _ep_sandbox(tmp_path, stub=stub, ggufs=True)
    r = subprocess.run(argv, capture_output=True, text=True, env=env, timeout=120, cwd=tmp_path)
    assert r.returncode == 0, r.stderr
    assert record.exists(), "stub never ran — generate not invoked"
    seen = record.read_text().strip()
    assert seen == f"HOME={home_dir}", (
        f"--home not exported to generator (saw {seen!r}, want HOME={home_dir})"
    )


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c04_initcontainer_args_not_command(cluster):
    """CR4 pod shape: image + args + mounts ONLY — no shell in k8s yaml.
    args carry the four flags; the --scan-dir set equals the base.yaml scan
    list (both render from autogen.scanPaths); --base/--out match the mount
    contract paths; --home present (the init-only writable cache)."""
    c = L.init_container(cluster, "autogen")
    assert not c.get("command"), (
        f"{cluster}: initContainer still has a command script — CA4 moves it into the image entrypoint"
    )
    args = [str(a) for a in (c.get("args") or [])]
    assert args, f"{cluster}: initContainer has neither command nor args — CA4 wiring missing"
    scan_dirs = [args[i + 1] for i, a in enumerate(args) if a == "--scan-dir"]
    base = L.configmap_data(cluster, BASE_CM, "base.yaml")
    assert sorted(scan_dirs) == sorted(base["models"]), (
        f"{cluster}: args scan-dirs {scan_dirs} != base.yaml models {base['models']}"
    )
    assert "--base" in args and args[args.index("--base") + 1] == BASE_FILE
    assert "--out" in args and args[args.index("--out") + 1] == GEN_FILE
    assert "--home" in args


def _render_rc(cluster: str, overlay: dict) -> tuple[int, str]:
    """helm template rc for an overlay render WITHOUT raising (drift probes
    assert failure, which render_docs' raising helper cannot express)."""
    import json
    import tempfile
    with tempfile.TemporaryDirectory(prefix="llamaswap-probe-") as tmp:
        vals = L.extract_service_values(cluster, Path(tmp) / "vals.yaml")
        ov = Path(tmp) / "ov.yaml"
        ov.write_text(yaml.safe_dump(overlay))
        cmd = ["helm", "template", "llama-swap", str(L.CHART_DIR), "-f", str(vals),
               "-f", str(ov), "--set", "domain=spencerslab.com", "--set", f"clusterName={cluster}"]
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        del json
        return out.returncode, out.stdout + out.stderr


def test_c04_drift_probe_scanpaths_disagreement_fails_render():
    """CR4 drift guard (args-driven re-arm): autogen.scanPaths gaining a path
    the args don't carry must fail the render — 'disagree - edit both or
    neither'. Red at handoff if HEAD's (script-based) guard lets it through."""
    rc, _ = _render_rc("gpu", {"autogen": {"scanPaths": ["/models/scanned", "/models/extra"]}})
    assert rc != 0, (
        "scanPaths/args disagreement did not fail the render — CA4 args guard missing"
    )


def test_c04_drift_probe_command_reintroduction_fails_render():
    """CR4 shell-reintroduction tripwire: ANY initContainer command on the
    autogen container fails the render (the k8s yaml must stay shell-free).
    At CA1 handoff the CURRENT chart legitimately HAS a command, so this is
    expected-red until CA4 lands; the overlay proves the guard must reject
    regardless of source."""
    rc, out = _render_rc("gpu", {
        "app-template": {"controllers": {"llama-swap": {"initContainers": {
            "autogen": {"command": ["/bin/sh"]}}}}}})
    assert rc != 0, "a command:/bin/sh passed the render — tripwire not armed (CA4)"
