# r2-C01 chart-side contract — the strata controller INSIDE charts/llama-swap
# (run-2 chunks/C01.md AC1–AC6; run-1 pod-shape facts relocated unchanged in
# KIND, plan of record 2026-10-28-cf-77-feat-strata-llama-swap-1.md).
#
# The OFF state renders today (the chart body lands with C01); every ON-shape
# assertion is RED until r2-C01 lands — the render helpers raise with the
# failing shape, and each test cites the chunk that clears it.

from __future__ import annotations

import os
import subprocess

import pytest
import yaml

import strata_testlib as S

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)

ON_OBJECT_DELTA = {
    ("Deployment", S.STRATA_OBJECT_NAME),
    ("Service", S.STRATA_OBJECT_NAME),
    ("ConfigMap", S.CM_CONFIG),
    ("ConfigMap", S.CM_PROFILE),
}


def _off():
    return S.render_off()[0]


def _on():
    return S.render_on()[0]


# --- AC1: OFF state lints, renders, and stays alone ----------------------------


@helm
def test_c01_off_helm_lint_passes():
    out = subprocess.run(["helm", "lint", str(S.CHART_DIR)],
                         capture_output=True, text=True, timeout=300)
    assert out.returncode == 0, out.stdout + out.stderr


@helm
def test_c01_off_render_has_no_strata_workload():
    """Default-OFF means the bare render must not grow ANY strata object —
    the seven data flags (not a re-capture) are the whole ON switch (Q-C)."""
    docs = _off()
    assert docs, "chart renders no documents"
    offenders = [f"{k}/{n}" for k, n in S.obj_ids(docs)
                 if S.STRATA_OBJECT_NAME in str(n) or str(n) in (S.CM_CONFIG, S.CM_PROFILE)]
    assert not offenders, f"strata objects leak into the default-OFF render: {offenders}"


@helm
def test_c01_off_render_has_no_external_secret():
    """C-A: the secret chain is GONE in every flag state (r2 Test-authority
    item 2) — asserted on the OFF render; the ON render has its own copy."""
    docs = _off()
    assert not S.find_kind(docs, "ExternalSecret"), (
        "ExternalSecret rendered at all — the keyless ruling (C-A) removed the whole chain"
    )


# --- AC2: ON state — exact object-set delta -------------------------------------


@helm
def test_c01_on_render_object_set_is_exact():
    """ON = OFF + EXACTLY {Deployment, Service gpu-ai-llama-swap-strata,
    ConfigMaps strata-config, strata-profile}. A ServiceAccount delta would
    re-open Q-A (single tree SA); any other addition steps outside the
    consolidation shape."""
    off_ids, on_ids = S.obj_ids(_off()), S.obj_ids(_on())
    added = on_ids - off_ids
    removed = off_ids - on_ids
    assert added == ON_OBJECT_DELTA, (
        f"ON-vs-OFF added-object delta diverged: +{sorted(added - ON_OBJECT_DELTA)} "
        f"(missing), -{sorted(ON_OBJECT_DELTA - added)} (unexpected)"
    )
    assert not removed, f"ON render removed OFF objects: {sorted(removed)}"


@helm
def test_c01_on_render_has_no_external_secret():
    docs = _on()
    assert not S.find_kind(docs, "ExternalSecret"), (
        "ExternalSecret in the ON render — r2-C01 C-A deletion not landed"
    )
    stdout = S.render_on()[1]
    for tok in ("strata-api-key", "STRATA_API_KEY", "PENDING-OPERATOR"):
        assert tok not in stdout, f"secret-chain token {tok!r} survived in the ON render (C-A)"


@helm
def test_c01_strata_service_identity():
    docs = _on()
    svc = S.by_name_kind(docs, "Service", S.STRATA_OBJECT_NAME)
    assert svc["spec"]["type"] == "ClusterIP", (
        "the consolidated strata Service stays ClusterIP — Q4 internal-only ruling, "
        "peers is the sanctioned path"
    )
    assert any(p.get("port") == 8080 for p in svc["spec"]["ports"]), svc["spec"]["ports"]


@helm
def test_c01_no_ingress_objects_in_on_render():
    docs = _on()
    assert not S.find_kind(docs, "Ingress"), (
        "ingress rendering contradicts the Q4 internal-only ruling (deliberate trio deviation)"
    )


# --- AC3: mount-exactness (golden law) -------------------------------------------


@helm
def test_c01_main_containers_mount_sets_byte_preserved():
    """globalMounts attach to EVERY enabled controller — C01 re-keys `config`
    and `tools` to advancedMounts enumerating current consumers precisely so
    the llama-swap main/tools containers' mount sets render IDENTICAL between
    OFF and ON (r2 DECISIONS mount-exactness; 'improving' anything away here
    is golden churn, forbidden)."""
    off, on = _off(), _on()
    off_ctrs, on_ctrs = S.main_pod_containers(off), S.main_pod_containers(on)
    assert set(off_ctrs) == set(on_ctrs), (
        f"main pod container set changed OFF→ON: {sorted(set(off_ctrs) ^ set(on_ctrs))}"
    )
    problems = []
    for name in sorted(set(off_ctrs) & set(on_ctrs)):
        a, b = S.mount_triples(off_ctrs[name]), S.mount_triples(on_ctrs[name])
        if a != b:
            problems.append(f"{name}: OFF {a} -> ON {b}")
    assert not problems, "main/tools volumeMount triples diverged OFF→ON:\n" + "\n".join(problems)


@helm
def test_c01_strata_container_mounts_exact_paths():
    ctr = S.strata_container(_on())
    paths = [m["mountPath"] for m in ctr.get("volumeMounts") or []]
    assert sorted(paths) == sorted(
        ["/app/config", "/models", "/dev/dri", "/dev/kfd", "/dev/shm", "/profile"]
    ), f"strata container mount set diverged (exact six, no dupes): {paths}"


@helm
def test_c01_strata_config_and_profile_are_directory_mounts():
    """subPath mounts never receive ConfigMap updates — the repo-learned
    hot-reload killer; the plan pins both strata config surfaces as directory
    mounts even after consolidation."""
    for path in ("/app/config", "/profile"):
        m = [m for m in (S.strata_container(_on()).get("volumeMounts") or [])
             if m["mountPath"] == path]
        assert m and not m[0].get("subPath"), f"{path} must be a directory mount (hot reload)"


# --- AC3: pod shape (run-1 facts, relocated keys) --------------------------------


@helm
def test_c01_recreate_and_grace_420_invariant():
    dep = S.strata_deployment(_on())
    assert dep["spec"]["strategy"]["type"] == "Recreate", (
        "RollingUpdate would overlap two pinned arenas on the node (#2257 class — run-1 DECISIONS)"
    )
    grace = dep["spec"]["template"]["spec"].get("terminationGracePeriodSeconds")
    assert grace == 420, f"grace {grace}"
    cfg = S.inner_config(_on())
    unload_to = cfg["models"][S.PRIMARY_ID].get("unloadTimeout")
    assert unload_to, (
        f"{S.PRIMARY_ID}: per-model unloadTimeout missing — the 10s global default "
        "force-kills the arena unload (run-1 RESEARCH contradictions #4)"
    )
    assert grace > unload_to + 30, (
        f"420 > unloadTimeout({unload_to}) + --shutdown-timeout drain(30) violated"
    )


@helm
def test_c01_privileged_hostpath_devices():
    pod = S.strata_pod(_on())
    ctr = S.strata_container(_on())
    assert ctr.get("securityContext", {}).get("privileged") is True, (
        "privileged is the run-1 device-access ruling (mixed gfx1201+8060S node; "
        "the amd-gpu plugin cannot name the card — the fallback stays a comment, not a build)"
    )
    hostpaths = {v.get("hostPath", {}).get("path") for v in pod["spec"].get("volumes", [])
                 if "hostPath" in v}
    assert {"/dev/kfd", "/dev/dri"} <= hostpaths, f"hostPath devices: {sorted(hostpaths)}"


@helm
def test_c01_probes_on_llama_swap_health_only():
    ctr = S.strata_container(_on())
    startup = ctr.get("startupProbe") or {}
    assert startup.get("httpGet", {}).get("path") == "/health"
    assert startup.get("failureThreshold") == 150 and startup.get("periodSeconds") == 10, (
        "150x10s absorbs the cold arena pin (run-1 plan Goal; a narrower window kills the pod mid-pin)"
    )
    for probe in ("livenessProbe", "readinessProbe"):
        spec = ctr.get(probe) or {}
        assert spec.get("httpGet", {}).get("path") == "/health", f"{probe} off the /health contract"
        # A probe at a model/upstream endpoint triggers loads (run-1 probes
        # ruling; peers/upstream passthrough caveat, run-1 RESEARCH §3).
        assert "/upstream" not in yaml.safe_dump(spec)


@helm
def test_c01_memory_cgroup_and_engine_cap():
    """Post-OOM doctrine (2026-10-29): an UNCAPPED page-lock on a node where
    the llama.cpp trio is uncapped too is what reaped cluster system pods.
    The pinned shape is cgroup-cap + engine-awareness as a PAIR (PR #1601):
    limits.memory bounds the blast radius, --memory-limit-mib keeps the
    arena inside it."""
    ctr = S.strata_container(_on())
    res = ctr.get("resources", {})
    req = res.get("requests", {})
    assert req.get("memory") == "64Gi", f"request {req}"
    assert req.get("cpu") in ("8", 8, "8000m"), f"request {req}"
    limits = res.get("limits") or {}
    assert limits.get("memory") == "96Gi", (
        f"limits {limits} — strata MUST be cgroup-bounded (2026-10-29 OOM: "
        "unbounded pin + unbounded trio = kernel harvesting system pods)"
    )
    cap = dict(S.arg_pairs(S.profile_json(_on(), S.PROFILE_PRIMARY_FILE))).get("--memory-limit-mib")
    assert cap and int(cap) <= 96 * 1024, (
        f"--memory-limit-mib {cap!r}: the engine must be TOLD its cgroup "
        "(#1601 pairing) and size inside it — a limit without the flag "
        "just gets the arena OOM-killed mid-pin"
    )
    assert "amd.com/gpu" not in {**req, **limits}, (
        "the amd.com/gpu resource contradicts the privileged+hostPath device ruling"
    )


@helm
def test_c01_shm_emptydir_2gi():
    pod = S.strata_pod(_on())
    mounts = {m["mountPath"]: m for m in S.strata_container(_on()).get("volumeMounts", [])}
    assert "/dev/shm" in mounts, "/dev/shm mount missing (DOCKER.md runtime contract via C01 README)"
    vol = {v["name"]: v for v in pod["spec"]["volumes"]}[mounts["/dev/shm"]["name"]]
    assert "emptyDir" in vol
    assert vol["emptyDir"].get("sizeLimit") == "2Gi", f"emptyDir {vol['emptyDir']}"


@helm
def test_c01_models_share_existing_llama_swap_claim():
    """Q3 shared claim, now chart-internal: the strata pod references the
    parent's OWN llama-swap PVC (the object is in both renders — the ON-vs-OFF
    delta test proves no new PVC is created)."""
    pod = S.strata_pod(_on())
    claims = {v["persistentVolumeClaim"]["claimName"] for v in pod["spec"]["volumes"]
              if "persistentVolumeClaim" in v}
    assert claims == {"llama-swap"}, f"claims: {claims}"


@helm
def test_c01_pod_shape_keys_ride_the_controller_not_default_pod_options():
    """defaultPodOptions is TREE-GLOBAL — grace/seccomp/supplementalGroups
    living there would diff the MAIN pod and break OFF parity (r2 plan:
    'Pod-shape keys ride controllers.strata.pod'). Machine-pinned via the
    values SOURCE: the parent's defaultPodOptions must not name the strata
    keys while controllers.strata.pod carries them."""
    text = S.read(S.CHART_DIR / "values.yaml", "r2-C01 task 1 grows the parent values")
    region = S.values_region(text, "controllers")
    assert "strata" in region, "no strata controller body in app-template.controllers yet (r2-C01)"
    assert "420" in region, (
        "terminationGracePeriodSeconds 420 must live under controllers.strata.pod — "
        "a tree-global defaultPodOptions placement diffs the main pod (plan risk note)"
    )
    dpo = S.values_region(text, "defaultPodOptions") if "defaultPodOptions:" in text else ""
    assert "420" not in dpo and "supplementalGroups" not in dpo, (
        "pod-shape keys found in defaultPodOptions — that is the tree-global trap the "
        "plan's risk note names (missed keys silently inherit and would diff the main pod)"
    )


@helm
def test_c01_supplementalgroups_and_rocr_values_keys_survive_relocation():
    """run-1's runbook hooks (rocminfo retarget + render/video GIDs) must be
    findable in the PARENT values tree under the relocated keys."""
    text = S.read(S.CHART_DIR / "values.yaml", "r2-C01 relocates the strata: values container")
    assert "rocrVisibleDevices" in text, "rocrVisibleDevices key missing — C04's on-target gate retargets via values, never a template edit"
    assert "supplementalGroups" in text, "supplementalGroups key missing (runbook resolves render/video GIDs)"


@helm
def test_c01_rocr_overlay_reaches_inner_config():
    docs = S.render_on_overlay({"strata": {"rocrVisibleDevices": "3"}})[0]
    m = S.inner_config(docs)["models"][S.PRIMARY_ID]
    env = S.env_list(m)
    assert "ROCR_VISIBLE_DEVICES=3" in env, f"strata.rocrVisibleDevices overlay did not reach the model env: {env}"


@helm
def test_c01_gate_uses_index_form_never_dotted_access():
    """Dotted `.Values.app-template` through a hyphenated key is a Go-lexer
    error (prototype-verified); AC6 pins the index form across the two moved
    templates + NOTES."""
    files = ["configmap-strata.yaml", "configmap-strata-profile.yaml", "NOTES.txt"]
    offenders = []
    for f in files:
        p = S.STRATA_TEMPLATES_DIR / f
        assert p.is_file(), f"charts/llama-swap/templates/{f} missing — r2-C01 template move not landed"
        text = p.read_text()
        if f == "NOTES.txt":
            assert "strata" in text.lower(), "NOTES.txt lost the gated strata section (consolidated name + peers caution)"
            continue
        if "index .Values.app-template.controllers.strata \"enabled\"" not in text \
                and 'index .Values "app-template" "controllers" "strata" "enabled"' not in text:
            offenders.append(f)
        dotted = [ln for ln in text.splitlines()
                  if ".Values.app-template." in ln and not ln.lstrip().startswith("#")]
        if dotted:
            offenders.append(f"{f}: dotted access {dotted[0].strip()[:60]!r}")
    assert not offenders, f"template gate form violations: {offenders}"


# --- AC5: subset-flag divergence guards ------------------------------------------


@helm
def test_c01_subset_guard_persistence_without_controller_fails_canonically():
    """DECISIONS-verified mechanism: an advancedMounts targeting a DISABLED
    controller hard-fails with app-template's canonical error naming the
    identifier. RED until C01 lands the persistence bodies (today the flags
    alone produce only an incomplete-entry schema complaint, not the
    canonical controller message)."""
    rc, out = S.render_subset(S.SEVEN_FLAGS_PERSISTENCE)  # the 5 persistence flags only
    assert rc != 0, "render succeeded with persistence ON and controller OFF — the guard is dead"
    assert S.CANONICAL_MISSING_CONTROLLER.search(out), (
        f"partial set failed, but not with the canonical loud error naming the identifier:\n{out[-400:]}"
    )


@helm
def test_c01_subset_guard_service_without_controller_fails_canonically():
    rc, out = S.render_subset(("app-template.service.strata.enabled=true",))
    assert rc != 0, "render succeeded with service ON and no controller — services→controller guard missing"
    assert S.CANONICAL_MISSING_CONTROLLER.search(out), (
        f"not the canonical identifier error:\n{out[-400:]}"
    )


@helm
def test_c01_subset_guard_controller_only_fails_loudly():
    """AC5's 'controller-only-on' probe: must fail LOUDLY naming strata
    (mechanism is C01's — a required-mount check or equivalent). NOTE: this
    probe may pass accidentally BEFORE C01 (today the flag-only render errors
    on the empty controller body); the canonical-message probes above are the
    ones that stay red."""
    rc, out = S.render_subset(S.SEVEN_FLAGS_CONTROLLER_SERVICE)
    assert rc != 0, "render succeeded with controller+service ON and persistence OFF"
    assert "strata" in out.lower(), f"loud failure must name the identifier:\n{out[-400:]}"


@helm
def test_c01_full_on_render_succeeds():
    """The guard's mirror: the COMPLETE set renders (raises inside render_on
    if not)."""
    docs = _on()
    assert S.obj_ids(docs) >= ON_OBJECT_DELTA


# --- run-1 guards carried through the consolidation -------------------------------


@helm
def test_r1_void_env_token_never_appears_in_executable_surfaces():
    """STRATA_KV_GROW_HOLD is VOID (run-1 RESEARCH §2, 0 upstream hits). It
    may not appear in any executable or config surface; markdown docs are the
    one place its non-existence may be NAMED, pinned to negative-only
    contexts by the runbook suite (test_strata_runbook.py)."""
    offenders = []
    roots = [r for r in (S.CHART_DIR, S.CONTAINER_DIR) if r.is_dir()]
    for root in roots:
        for path in sorted(root.rglob("*")):
            if not path.is_file() or path.suffix == ".md":
                continue
            if path.suffix in {".tgz", ".pyc"} or f"{os.sep}tests{os.sep}" in str(path):
                continue
            if S.VOID_ENV_TOKEN in path.read_text(errors="replace"):
                offenders.append(str(path.relative_to(S.REPO_ROOT)))
    assert not offenders, f"{S.VOID_ENV_TOKEN} found in: {offenders}"
