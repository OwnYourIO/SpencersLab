# charts/amd-gpu render contract — RE-AUTHORED for the C08 T-A first-party
# app-template 5.0.1 shape (chunks/C08.md Tests; AC1; DECISIONS D22 item 5 /
# D23; RESEARCH §R7-Q5). The conversion deletes all six vendored templates and
# expresses the SAME pod from the app-template: values subtree; the law is
# PARITY, NOT IMPROVEMENT — the authority is evidence/pre-c08-deviceplugin-ds.
# yaml, the vendored render captured by the test round at eef04f9c3.
#
# Red state at handoff (designed-red until C08 dev): the values-shape leg,
# the updateStrategy-absence leg, the Chart.yaml/lock/.helmignore floors, the
# first-party-header legs, the table ConfigMap/mount/parity legs (T-B,
# amendment 2026-11-12: owner lane ruling = table-mount rename to the pool in
# the CONSTANTS BLOCK), and the zero-stale/placement leg are RED on today's
# tree (old name still in radiance/llama-swap/services surfaces — the sweep
# is the dev's). The render PARITY legs (args, image, pod facts, hostPaths,
# lint, names-coherence, ledger strings via constants, renovate/digest) are
# GREEN today by construction: the conversion moves files, not facts; a
# red there after C08 is behavior drift, not test drift.
#
# Run per-directory: python3 -m pytest charts/amd-gpu/tests -v

from __future__ import annotations

import subprocess

import pytest

import amd_gpu_testlib as A

_ok, _reason = A.helm_ready()
helm_skip = pytest.mark.skipif(not _ok, reason=_reason)

# Python 3.14 rejects inline global flags mid-pattern (§12.5 law): every
# regex here passes flags as arguments, never (?x) embedded outside position 0.


def _oracle_container(oracle: dict) -> dict:
    return oracle["spec"]["template"]["spec"]["containers"][0]


# --- AC1: the chart renders and is ONE DaemonSet, nothing else ------------------


@helm_skip
def test_helm_lint_passes():
    out = subprocess.run(["helm", "lint", str(A.CHART_DIR)],
                         capture_output=True, text=True, timeout=300)
    assert out.returncode == 0, out.stdout + out.stderr


@helm_skip
def test_renders_exactly_one_daemonset():
    docs, _ = A.render()
    dss = [d for d in docs if d.get("kind") == "DaemonSet"]
    assert len(dss) == 1, f"C08 AC1: rendered DaemonSets: {[d['metadata']['name'] for d in dss]}"


# --- AC1: args / image / -v=5 (parity witnesses) --------------------------------


@helm_skip
def test_args_are_the_four_plain_items():
    """The restated CMD FLAG TRIO + the strategy arg as one plain 4-list
    (§R7-Q5; the dp.extraArgs plumbing DIES with the vendored values — the
    strategy is now a literal arg, per-cluster override = the service-block
    law).

    C09 AC5(ii) anchor: the command fix is ADDITIVE, so this exact equality
    is the proof the four flags did NOT migrate into `command`. GREEN today,
    and it must STAY green when dev lands the key — a red here after the fix
    means the flags moved, which is out of contract."""
    docs, _ = A.render()
    args = A.dp_container(docs).get("args")
    assert args == A.ARGS_CONTRACT, (
        f"C08 AC1: args are {args}, want exactly {A.ARGS_CONTRACT} "
        "(CMD trio restated — declaring args drops the CMD — + strategy arg literal)"
    )


@helm_skip
def test_container_command_carries_the_plugin_binary():
    """C09 AC5(i) — THE FIX's witness, DESIGNED-RED until dev adds the one
    values key. The pinned image ships NO ENTRYPOINT and its CMD's first
    element is the relative binary; the AC3 authority
    (evidence/image-config-1.31.0.12.json, registry-fetched) is what makes
    `/root/k8s-device-plugin` a DERIVATION (WorkingDir + Cmd[0]) rather than
    a floating string — so the leg validates that fixture first. Declaring
    args without command makes args[0] the exec path: the live
    RunContainerError crashloop (§D1.1) that left both product pools
    un-advertised and radiance + the gpu-ai overlay pod Pending."""
    A.image_config_authority()
    docs, _ = A.render()
    command = A.dp_container(docs).get("command")
    assert command == A.PLUGIN_COMMAND, (
        f"C09 AC5(i)/D25: container command is {command!r}, want exactly {A.PLUGIN_COMMAND!r} — "
        "without it the args-only shape execs '-logtostderr=true' (exit 128). The fix is the "
        "ONE values key app-template.controllers.device-plugin-daemonset.containers.deviceplugin.command "
        "(list form per charts/betanin/archon/radiance precedent; §D1.4 library surface)"
    )


@helm_skip
def test_command_and_args_joint_invariant():
    """C09 AC5(iii) — the class law made executable for THIS container: command
    and args must BOTH be present. Args-only is legal only where the image
    carries an Entrypoint (the radiance main container is that case, §D1.5);
    the plugin image has none (§D1.6/AC3 evidence), so args-only is the
    shipped defect. Command-only would drop the naming strategy and the -v=5
    log law. Red with the same fix; green together or not at all."""
    docs, _ = A.render()
    ctr = A.dp_container(docs)
    command, args = ctr.get("command"), ctr.get("args")
    assert command and args, (
        f"C09 AC5(iii): command={command!r} args={args!r} — the device-plugin container needs "
        "BOTH (binary via command, the four flags via args); args-only is the live defect"
    )
    assert command == A.PLUGIN_COMMAND and args == A.ARGS_CONTRACT, (
        "C09 AC5(iii): the both-fields shape drifted from the ruled split "
        f"(command={A.PLUGIN_COMMAND}, args={A.ARGS_CONTRACT})"
    )


@helm_skip
def test_v5_leg_is_asserted_separately():
    """-v=5 alone: runbook-log-bearing, NOT cosmetic — receipt (b) greps the
    enumeration logs the plugin only prints at -v=5 (D19 law survives the
    conversion; C08 T-A moves its comment to values.yaml)."""
    docs, _ = A.render()
    args = A.dp_container(docs).get("args") or []
    assert "-v=5" in args, "C08 AC1: -v=5 missing from the args — enumeration logs die silently (runbook gate (b))"


@helm_skip
def test_image_pin_matches_oracle():
    docs, _ = A.render()
    image = A.dp_container(docs)["image"]
    want = _oracle_container(A.oracle_ds())["image"]
    assert image == want, (
        f"C08 AC1: image is {image!r}, want the oracle's {want!r} (1.31.0.12 — the "
        "product-naming release; D2 posture: no digest FIELD)"
    )
    assert "@" not in image, "C08 AC1: a digest field pinned the image (D2 posture: tag + ledger comment)"


# --- AC1: pod-fact parity against the oracle ------------------------------------


@helm_skip
def test_pod_facts_parity_with_oracle():
    """priorityClassName, tolerations, the container securityContext, and
    today's ABSENT-ness legs (nodeSelector/imagePullSecrets OFF, resources
    nothing) — value-for-value against the captured vendored render."""
    docs, _ = A.render()
    spec = A.pod_spec(docs)
    o_spec = A.oracle_ds()["spec"]["template"]["spec"]
    assert spec.get("priorityClassName") == o_spec.get("priorityClassName") == "system-node-critical", (
        f"C08 AC1: priorityClassName {spec.get('priorityClassName')!r} != oracle "
        f"{o_spec.get('priorityClassName')!r} — today's template hardcode becomes the "
        "app-template pod.priorityClassName EXPRESSION, the value must not drift"
    )
    assert spec.get("tolerations") == o_spec.get("tolerations"), (
        f"C08 AC1: tolerations {spec.get('tolerations')} != oracle {o_spec.get('tolerations')} "
        "(CriticalAddonsOnly Exists)"
    )
    sc = A.dp_container(docs).get("securityContext") or {}
    o_sc = _oracle_container(A.oracle_ds()).get("securityContext") or {}
    assert sc == o_sc, f"C08 AC1: container securityContext {sc} != oracle {o_sc} (drop ALL + no-PE, byte-preserved)"
    assert not spec.get("nodeSelector"), (
        "C08 AC1: a nodeSelector rendered — today's is gated OFF (would-be pair belongs in a values COMMENT only)"
    )
    assert not spec.get("imagePullSecrets"), f"C08 AC1: imagePullSecrets rendered: {spec.get('imagePullSecrets')}"
    res = A.dp_container(docs).get("resources") or {}
    assert not res.get("requests") and not res.get("limits"), (
        f"C08 AC1: resources {res} — today's empty dp.resources renders NOTHING; the conversion omits too "
        "(parity, not improvement: do NOT invent requests/limits)"
    )


@helm_skip
def test_three_hostpath_volumes_byte_parity():
    """The REAL hostPath volumes today (§R7-Q5): device-plugins dir + /sys +
    the metrics-exporter health dir (DirectoryOrCreate, mountPath WITH
    trailing slash byte-equal) — each oracle volume byte-present and the
    hostPath SET equal; the fourth, configMap-sourced volume is D24's table
    mount (next leg). NO /dev/kfd, NO /dev/dri — the plugin pod registers
    through the unix socket; Allocate() hands devices to kubelet (§R7 fact
    correcting the item-5 phrasing)."""
    docs, _ = A.render()
    vols = {v["name"]: v for v in A.pod_spec(docs).get("volumes", [])}
    o_vols = {v["name"]: v for v in A.oracle_ds()["spec"]["template"]["spec"].get("volumes", [])}
    hp = {n: v for n, v in vols.items() if "hostPath" in v}
    assert hp == o_vols, (
        f"C08 AC1: hostPath volumes {hp} != oracle {o_vols} — three byte-equal "
        "(dp=/var/lib/kubelet/device-plugins, sys=/sys REQUIRED for naming, health=/var/lib/amd-metrics-exporter/ DirectoryOrCreate)"
    )
    paths = {v.get("hostPath", {}).get("path") for v in hp.values()}
    assert not any(p.startswith("/dev/") for p in paths), (
        f"C08: device-node hostPaths {paths} — §R7 corrected fact: the plugin mounts NO /dev/kfd//dev/dri"
    )
    mounts = A.dp_container(docs).get("volumeMounts", [])
    o_mounts = _oracle_container(A.oracle_ds()).get("volumeMounts", [])
    missing = [m for m in o_mounts if m not in mounts]
    assert not missing, (
        f"C08 AC1: oracle volumeMounts missing from the render: {missing} (mountPath strings "
        "byte-equal INCLUDING the health trailing slash)"
    )
    extra = [m for m in mounts if m not in o_mounts]
    assert all(m.get("mountPath") == A.IDS_PATH for m in extra), (
        f"C08: unexpected extra volumeMounts {extra} — only the ids-table mount over {A.IDS_PATH} is sanctioned"
    )
    assert any(m.get("mountPath") == "/sys" for m in mounts), (
        "C08: /sys mount missing — product naming reads sysfs directly (PR #246 design note; runbook gate (a) depends)"
    )


# --- AC1: the conversion's absence laws ------------------------------------------


@helm_skip
def test_update_strategy_absent_accepted_gap():
    """DESIGNED-RED until C08: today's DS carries explicit RollingUpdate/maxUnavailable
    1; app-template 5.0.1 renders NO updateStrategy, and the k8s default EQUALS
    today's value — the ACCEPTED, documented gap (D23). Asserted ABSENT with
    the equivalence comment in values; a future OnDelete needs rawResources or
    upstream — do not fight the library."""
    docs, _ = A.render()
    us = A.daemonset(docs)["spec"].get("updateStrategy")
    assert us is None, (
        f"C08 AC1: DaemonSet still carries updateStrategy {us} — the conversion drops it "
        "(app-template gap row §R7-Q5; k8s default == today's RollingUpdate/maxUnavailable 1, zero behavior delta)"
    )


@helm_skip
def test_ships_only_what_today_ships_no_rbac_no_service():
    """§R7-Q5 verified fact: RBAC/SA were labeller-gated and render NOTHING
    today (oracle kinds: DaemonSet only). The conversion's ONLY addition is
    the patched-table ConfigMap (D24 lane); a SA/ClusterRole/Service here is
    an invented surface. The future-labeller route is app-template
    serviceAccount/rbac.roles/rbac.bindings, recorded as a comment, not
    shipped."""
    docs, _ = A.render()
    kinds = sorted({d["kind"] for d in docs})
    assert set(kinds) <= {"DaemonSet", "ConfigMap"}, (
        f"C08 AC1: rendered kinds {A.docs_kinds(docs)} — beyond the oracle DaemonSet only the "
        "amdgpu-ids ConfigMap is sanctioned (D24 table mount); §R7: zero RBAC ships"
    )
    for forbidden in ("ServiceAccount", "ClusterRole", "ClusterRoleBinding", "Service", "Ingress"):
        found = [d["metadata"]["name"] for d in docs if d.get("kind") == forbidden]
        assert not found, f"C08 AC1: {forbidden} objects rendered: {found}"
    cms = [d for d in docs if d.get("kind") == "ConfigMap"]
    assert len(cms) == 1 and A.IDS_TABLE_KEY in (cms[0].get("data") or {}), (
        f"C08 AC1(amendment): the ConfigMap set is {[c['metadata']['name'] for c in cms]} — "
        f"exactly ONE, carrying the {A.IDS_TABLE_KEY!r} data key (the patched table)"
    )
    assert [k for k in A.oracle_kinds()] == [k for k in A.docs_kinds(docs) if k.startswith("DaemonSet")], (
        "C08 AC1: the DaemonSet object drifted from the oracle's kind/name set"
    )


# --- T-B leg (i): the table mount (amendment 2026-11-12) -------------------------


@helm_skip
def test_table_configmap_mounts_over_the_ids_path_via_subpath():
    """The lane mechanism, render-asserted: the patched table rides a
    ConfigMap mounted OVER the plugin's const IDsPath (/usr/share/libdrm/
    amdgpu.ids, the plain os.Open the binary reads — §R7-Q2) via a subPath
    SINGLE-FILE mount, readOnly, into the plugin container; the DaemonSet is
    the only consumer. The subPath never-live-updates law (repo gotcha 1) is
    INTENTIONAL here — the plugin reads the table once at startup
    (LoadProductIndex); a table edit propagates as the DS rollout, not a
    in-place reload; do NOT widen to directory-mount reload idioms."""
    docs, _ = A.render()
    cms = [d for d in docs if d.get("kind") == "ConfigMap"]
    assert cms, "C08 T-B(i): no ConfigMap rendered — the patched table is not shipped"
    cm_name = cms[0]["metadata"]["name"]
    spec = A.pod_spec(docs)
    vols = {v["name"]: v for v in spec.get("volumes", []) if v.get("configMap")}
    assert vols, f"C08 T-B(i): no configMap-sourced volume on the DS ({sorted({v['name'] for v in spec.get('volumes', [])})})"
    assert any(v["configMap"].get("name") == cm_name for v in vols.values()), (
        f"C08 T-B(i): configMap volumes {vols} do not reference the rendered table {cm_name!r}"
    )
    mounts = [m for m in A.dp_container(docs).get("volumeMounts", [])
              if m.get("mountPath") == A.IDS_PATH]
    assert mounts, (
        f"C08 T-B(i): nothing mounts at {A.IDS_PATH} — the LoadProductIndex const path is where "
        "the binary reads the table (Dockerfile COPY law); a wrong path means the mount NEVER applies (the WATCH case)"
    )
    m = mounts[0]
    assert m.get("subPath") == A.IDS_TABLE_KEY, (
        f"C08 T-B(i): mount at {A.IDS_PATH} is {m} — must be a subPath '{A.IDS_TABLE_KEY}' single-file "
        "overlay (a directory mount would replace the whole /usr/share/libdrm tree)"
    )
    assert m.get("readOnly") is True, f"C08 T-B(i): the ids mount is writable: {m}"
    # The DS is the only consumer: no other workload in the render references the CM.
    other_consumers = [f"{d['kind']}/{d['metadata']['name']}" for d in docs
                       if d.get("kind") in ("Deployment", "StatefulSet", "Job", "CronJob")]
    assert not other_consumers, f"C08 T-B(i): unexpected workload consumers: {other_consumers}"


# --- D23 name strain: coherence either way ---------------------------------------


@helm_skip
def test_live_names_coherent_or_rename_set_enumerated():
    """D23 strain 1, adjudicated per OBJECT (C08 dev-round re-pin, coord-
    routed). The library reality (§R7-Q5, dev-captured): app-template
    classes/_daemonset.tpl HARDCODES spec.selector.matchLabels to the
    app.kubernetes.io {name, instance, controller} triple — the live
    `name: amd-gpu-dp-ds` label is UNREACHABLE by any values shape, and the
    container name IS the controller identifier. So the old all-or-nothing
    triple rule could not pass either strain, and its rename branch crashed
    (TypeError) on the selector=None read.

    Coherence now, per named object (DaemonSet name, container name): either
    byte-identical to live OR enumerated in the values ledger rename-set —
    mixed per-object shapes are legitimate (nameOverride can land the DS
    name identical while the identifier-renamed container cannot). The
    selector's invariant is asserted as SELF-coherence instead: the DS's
    matchLabels must be a subset of the pod-template labels — the property
    the old hand-written label carried. Teeth preserved: an unnamed shape
    (neither live nor enumerated), a selector that selects nothing, or a
    rename-set string missing from the ledger all red, never a TypeError."""
    docs, _ = A.render()
    ds = A.daemonset(docs)
    blob = A.chart_values_text()
    problems = []
    for label, value, live in (("DaemonSet", ds["metadata"]["name"], A.LIVE_DS_NAME),
                               ("container", A.dp_container(docs)["name"], A.LIVE_CONTAINER_NAME)):
        if value == live:
            continue
        if value not in blob:
            problems.append(
                f"{label} name {value!r} is neither the live name ({live!r}) nor enumerated in "
                "the values.yaml rename-set (D23 strain 1: renames land WITH the ledger)"
            )
    labels = (ds["spec"]["template"].get("metadata") or {}).get("labels") or {}
    selector = (ds["spec"].get("selector") or {}).get("matchLabels") or {}
    assert selector, "C08/D23: the DS renders no selector matchLabels at all"
    missing = {k: v for k, v in selector.items() if labels.get(k) != v}
    assert not missing, (
        f"C08/D23: selector matches nothing — matchLabels {missing} absent from pod labels "
        f"{sorted(labels)} (the app.kubernetes.io triple is library-hardcoded; the DS must "
        "still select its own pods)"
    )
    assert not problems, "C08/D23 incoherent name shape: " + "; ".join(problems)


# --- T-A values shape: first-party, render-plane ---------------------------------


@helm_skip
def test_values_shape_is_first_party_app_template():
    """DESIGNED-RED until C08: the whole pod must be expressed from the
    app-template: subtree (repo idiom — charts/radiance/Chart.yaml verbatim
    law, NO parent loader template, NO vendored-era keys). File-deletion laws
    are asserted here on the RENDER PLANE (values shape + oracle equality
    above), never by ls of templates/."""
    vals = A.chart_values()
    assert "app-template" in vals, (
        "C08 T-A: charts/amd-gpu/values.yaml has no app-template: subtree — the pod is not "
        "expressed first-party yet (vendored dp:/* templates era, D19, is superseded by D23)"
    )
    at = vals["app-template"]
    ctrls = at.get("controllers") or {}
    assert ctrls, "C08 T-A: app-template.controllers missing"
    kinds = {k: (c or {}).get("type") for k, c in ctrls.items()}
    assert "daemonset" in {str(v).lower() for v in kinds.values()}, (
        f"C08 T-A: no controller declares type: daemonset — app-template DEFAULTS TO deployment; "
        f"the device plugin MUST set it explicitly (§R7-Q5 caveat, chunk Notes-for-dev); controllers: {kinds}"
    )
    # The vendored-era keys DIE with the conversion (D23): no plumbing key, no
    # toggles, the lbl: dead key gone.
    for dead in ("dp", "labeller", "nfd"):
        assert dead not in vals, (
            f"C08 T-A/D23: the vendored values key '{dead}:' survived — dp.extraArgs plumbing and the "
            "labeller/nfd toggles die with the vendored files (per-cluster override = the service-block law)"
        )
    assert "service" not in at or not at.get("service"), (
        "C08 T-A: an app-template service: block declared — today ships none (parity)"
    )
