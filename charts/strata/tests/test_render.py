# C02 render contract — charts/strata pod shape (chunks/C02.md AC1–AC3, AC6).
#
# RED until C02 lands: the chart does not exist yet, so the helm gate passes
# (binary present) and every render fails naming C02. Provenance of each
# literal: the cited AC/task line of chunks/C02.md + RESEARCH.md.

from __future__ import annotations

import os
import re
import subprocess

import pytest
import yaml

import strata_testlib as S

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)

SENTINEL_SETS = ("domain=test.example.com", "bitwardenIds.strata-api-key=test-uuid")


def _default_render():
    return S.render_strata()


# --- chart metadata (C02 task 1; repo law: new chart gets version 1.0.0) ----


def test_c02_chart_yaml_new_chart_version():
    text = S.read(S.CHART_DIR / "Chart.yaml", "C02 task 1 creates the chart")
    doc = yaml.safe_load(text)
    assert doc.get("version") == "1.0.0", (
        f"Chart.yaml version {doc.get('version')!r} — repo law: 1.0.0 only for a "
        "brand-new chart, release.yaml bumps later; a hand-bumped version is the violation"
    )
    deps = {d.get("name"): d for d in (doc.get("dependencies") or [])}
    assert "app-template" in deps, "app-template dependency missing (repo standard chart base)"
    assert deps["app-template"].get("version") == "5.0.1", (
        f"app-template {deps.get('app-template', {}).get('version')} — repo standard is 5.0.1 (C02 task 1)"
    )


# --- AC1: lint + bare template -----------------------------------------------


@helm
def test_c02_ac1_helm_lint_passes():
    if not (S.CHART_DIR / "Chart.yaml").is_file():
        raise AssertionError("charts/strata missing — C02 not landed")
    out = subprocess.run(["helm", "lint", str(S.CHART_DIR)], capture_output=True, text=True, timeout=300)
    assert out.returncode == 0, out.stdout + out.stderr


@helm
def test_c02_ac1_bare_template_passes():
    docs, _raw = _default_render()
    assert docs, "chart renders no documents"


# --- AC3: sentinel hygiene ----------------------------------------------------


@helm
def test_c02_ac3_test_set_render_has_no_override_sentinels():
    docs, raw = S.render_strata(sets=SENTINEL_SETS)
    assert docs
    offenders = [ln for ln in raw.splitlines() if re.search(r"OVERRIDE_[A-Z_]+", ln)]
    assert not offenders, "OVERRIDE_ sentinel leaked into the render:\n" + "\n".join(offenders)


# --- AC2: pod shape -----------------------------------------------------------


@helm
def test_c02_ac2_deployment_recreate_grace_420():
    docs, _ = _default_render()
    deps = S.find_kind(docs, "Deployment")
    assert deps, "no Deployment rendered (C02: type deployment)"
    dep = deps[0]
    assert dep["spec"]["strategy"]["type"] == "Recreate", (
        "RollingUpdate would overlap two pinned arenas on the node (#2257 class — DECISIONS)"
    )
    grace = dep["spec"]["template"]["spec"].get("terminationGracePeriodSeconds")
    assert grace == 420, f"grace {grace}"
    # The invariant the grace value exists for (DECISIONS amend RESEARCH §3):
    # kubelet's SIGKILL must land after unloadTimeout + engine drain, else
    # llama-swap's force-kill or a half-pinned arena beats a clean stop.
    cfg = S.inner_config(docs)
    unload_to = cfg["models"][S.PRIMARY_ID].get("unloadTimeout")
    assert unload_to, (
        f"{S.PRIMARY_ID}: per-model unloadTimeout missing — the 10s global default "
        "force-kills the arena unload (RESEARCH contradictions #4)"
    )
    assert grace > unload_to + 30, (
        f"420 > unloadTimeout({unload_to}) + --shutdown-timeout drain(30) violated"
    )


@helm
def test_c02_ac2_privileged_hostpath_devices():
    docs, _ = _default_render()
    pod = S.the_pod(docs)
    ctr = S.main_container(docs)
    assert ctr.get("securityContext", {}).get("privileged") is True, (
        "privileged is the DECISIONS device-access ruling (mixed gfx1201+8060S node; "
        "the amd-gpu plugin cannot name the card — chart comment carries the fallback)"
    )
    hostpaths = {v.get("hostPath", {}).get("path") for v in pod["spec"].get("volumes", []) if "hostPath" in v}
    assert {"/dev/kfd", "/dev/dri"} <= hostpaths, f"hostPath devices: {sorted(hostpaths)}"


@helm
def test_c02_ac2_probes_on_llama_swap_health_only():
    docs, _ = _default_render()
    ctr = S.main_container(docs)
    startup = ctr.get("startupProbe") or {}
    assert startup.get("httpGet", {}).get("path") == "/health"
    assert startup.get("failureThreshold") == 150 and startup.get("periodSeconds") == 10, (
        "150x10s absorbs the cold arena pin (plan Goal; a narrower window kills the pod mid-pin)"
    )
    for probe in ("livenessProbe", "readinessProbe"):
        spec = ctr.get(probe) or {}
        assert spec.get("httpGet", {}).get("path") == "/health", f"{probe} off the /health contract"
        # A probe at a model/upstream endpoint triggers loads (DECISIONS probes
        # ruling; peers/upstream passthrough caveat, RESEARCH §3).
        assert "/upstream" not in yaml.safe_dump(spec)


@helm
def test_c02_ac2_memory_request_no_limit():
    docs, _ = _default_render()
    ctr = S.main_container(docs)
    req = ctr.get("resources", {}).get("requests", {})
    assert req.get("memory") == "96Gi", f"request {req}"
    assert req.get("cpu") in ("8", 8, "8000m"), f"request {req}"
    limits = ctr.get("resources", {}).get("limits") or {}
    assert "memory" not in limits, (
        "limits.memory would cgroup-kill the pinned arena (DECISIONS Q2/lazy posture, "
        "RESEARCH §4 — no container memory limit is also DOCKER.md's runtime contract)"
    )
    assert "amd.com/gpu" not in {**req, **limits}, (
        "the amd.com/gpu resource contradicts the privileged+hostPath device ruling (DECISIONS)"
    )


@helm
def test_c02_ac2_shm_emptydir_2gi():
    docs, _ = _default_render()
    pod = S.the_pod(docs)
    mounts = {m["mountPath"]: m for m in S.main_container(docs).get("volumeMounts", [])}
    assert "/dev/shm" in mounts, "/dev/shm mount missing (DOCKER.md runtime contract via C01 README)"
    vol = {v["name"]: v for v in pod["spec"]["volumes"]}[mounts["/dev/shm"]["name"]]
    assert "emptyDir" in vol
    assert vol["emptyDir"].get("sizeLimit") == "2Gi", f"emptyDir {vol['emptyDir']}"


@helm
def test_c02_ac2_config_and_profile_directory_mounts():
    """subPath mounts never receive ConfigMap updates — the repo-learned hot-
    reload killer (charts/llama-swap persistence comment); C02 AC2 pins both
    config surfaces as directory mounts."""
    docs, _ = _default_render()
    mounts = S.main_container(docs).get("volumeMounts", [])
    for path in ("/app/config", "/profile"):
        got = [m for m in mounts if m["mountPath"] == path]
        assert got, f"{path} not mounted"
        for m in got:
            assert not m.get("subPath"), f"{path} mounted via subPath — kills hot reload"


@helm
def test_c02_ac2_models_mount_is_shared_llama_swap_claim():
    """DECISIONS Q3: existingClaim llama-swap, never a chart-created PVC; the
    engine area must not sit in llama.cpp's LLAMA_CACHE=/models file layout."""
    docs, _ = _default_render()
    pod = S.the_pod(docs)
    claims = {v["persistentVolumeClaim"]["claimName"] for v in pod["spec"]["volumes"] if "persistentVolumeClaim" in v}
    assert claims == {"llama-swap"}, f"claims: {claims}"
    assert not S.find_kind(docs, "PersistentVolumeClaim"), "chart must not create a PVC (Q3)"


@helm
def test_c02_ac2_default_render_has_no_external_secret():
    """AC2's last clause (plan Commands "WITHOUT the bitwardenIds set"):
    the chart default bitwardenIds: {} must render NO ExternalSecret — the
    guard keeps clusters without the secret wiring render-clean (repo law).
    The set side (sentinel-free render + ES with test UUID) is C03's
    extract-and-render half, in test_wiring.py."""
    docs, _raw = _default_render()
    assert not S.find_kind(docs, "ExternalSecret"), (
        "ExternalSecret rendered with bitwardenIds unset — the strata-api-key "
        "guard is not cluster-optional"
    )


# --- AC6: no ingress, ClusterIP 8080 ------------------------------------------


@helm
def test_c02_ac6_internal_only_surface():
    docs, _ = _default_render()
    assert not S.find_kind(docs, "Ingress"), (
        "ingress rendering contradicts the Q4 internal-only ruling (deliberate trio deviation)"
    )
    svcs = S.find_kind(docs, "Service")
    assert len(svcs) == 1, f"{len(svcs)} Services rendered"
    svc = svcs[0]
    assert svc["spec"]["type"] == "ClusterIP"
    ports = svc["spec"]["ports"]
    assert any(p.get("port") == 8080 for p in ports), f"ports {ports}"


# --- C02 task 4: values-configurable runbook hooks ----------------------------


def test_c02_rocr_and_supplementalgroups_values_keys():
    text = S.read(S.CHART_DIR / "values.yaml", "C02 task 2/4")
    assert "rocrVisibleDevices" in text, (
        "rocrVisibleDevices values key missing — the on-target rocminfo gate (C04) "
        "must be able to retarget the device without a template edit"
    )
    assert "supplementalGroups" in text, "supplementalGroups key missing (runbook resolves render/video GIDs)"


def test_c02_void_env_token_never_appears():
    """STRATA_KV_GROW_HOLD is VOID (0 upstream hits, RESEARCH §2) — the card
    guide's fiction. It may not appear in any executable or config surface
    (chart templates, values, Dockerfile); markdown docs are the one place
    its non-existence may be NAMED (the R4 deferral rationale says so), and
    there it is pinned to negative-only contexts by C04's own test
    test_c04_void_token_only_in_negative_context."""
    offenders = []
    roots = [r for r in (S.CHART_DIR, S.CONTAINER_DIR) if r.is_dir()]
    for root in roots:
        for path in sorted(root.rglob("*")):
            if not path.is_file() or path.suffix == ".md":
                continue
            if f"{os.sep}tests{os.sep}" in str(path):
                continue
            if S.VOID_ENV_TOKEN in path.read_text(errors="replace"):
                offenders.append(str(path.relative_to(S.REPO_ROOT)))
    assert not offenders, f"{S.VOID_ENV_TOKEN} found in: {offenders}"


# --- C03's NOTES contract input: the rendered Service identity ----------------
# (The peers proxy-URL equality itself rides test_wiring.py; this pins the
# name/DNS shape the C03 seam was written from.)


@helm
def test_c02_service_named_as_the_appset_release():
    docs, _raw = S.render_strata(sets=SENTINEL_SETS)
    assert S.rendered_service_name(docs) == S.RELEASE, (
        f"Service name != {S.RELEASE}: the peers proxy URL in services/gpu-ai/prod/values.yaml "
        "must be re-derived from NOTES.txt (C03 dev note: never guess the DNS string)"
    )
