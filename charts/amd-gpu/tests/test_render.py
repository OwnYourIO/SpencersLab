# charts/amd-gpu render contract — C07 AC1 (chunks/C07.md Tests bullet 1).
#
# The vendored DaemonSet must render the ARGS HOOK EXACTLY: the restated
# image CMD trio plus the values-spliced product-strategy flag, under
# name-pinned objects (the Application source-flip repo->git-path lands
# orphan-free only if every object keeps the pre-ticket names), with the
# labeller/nfd classes still rendering nothing (the live node has zero
# amd.com/* labels — don't wake the labeller) and the upstream volumes/
# security shape preserved.
#
# Red state at handoff (designed): EVERY leg here is red until C07 lands —
# charts/amd-gpu/ does not exist yet (missing chart = loud red naming C07,
# never a skip; only the helm binary may skip, and it skips LOUDLY with the
# PATH-export reason).
#
# Run per-directory: python3 -m pytest charts/amd-gpu/tests -v

from __future__ import annotations

import subprocess

import pytest

import amd_gpu_testlib as A

_ok, _reason = A.helm_ready()
helm_skip = pytest.mark.skipif(not _ok, reason=_reason)


# --- AC1: the args trio + the strategy flag ------------------------------------


@helm_skip
def test_args_restate_the_cmd_plus_product_strategy():
    """The container args == the restated CMD trio + -resource_naming_strategy=
    product (D18/D19). Order matters: the restated trio first (CMD parity,
    the hook then splices dp.extraArgs via `toYaml | nindent 6`)."""
    docs, _ = A.render()
    args = A.dp_container(docs).get("args")
    assert isinstance(args, list) and args, (
        "C07 AC1: the plugin container carries no args list — the args hook is not "
        "implemented (declaring args drops the image CMD, so the trio MUST be restated)"
    )
    assert args == A.CMD_RESTATED + [A.STRATEGY_FLAG], (
        f"C07 AC1: args are {args}, want {A.CMD_RESTATED + [A.STRATEGY_FLAG]} "
        "(CMD trio restated in full, then the values-spliced product flag)"
    )


@helm_skip
def test_v5_leg_is_asserted_separately():
    """-v=5 alone: runbook-log-bearing, NOT cosmetic — the R6-Q4-5 receipt (b)
    greps the plugin's enumeration logs ("Loaded N GPU products…",
    "Reporting 1 devices as amd.com/gpu-…"), which exist only at -v=5."""
    docs, _ = A.render()
    args = A.dp_container(docs).get("args") or []
    assert "-v=5" in args, (
        "C07 AC1: -v=5 missing from the restated CMD — omitting it silently drops the "
        "enumeration logs the C06 runbook receipt (b) needs (RESEARCH §R6-Q2 step 1)"
    )


@helm_skip
def test_extra_args_are_values_plumbed():
    """The hook is a `with .Values.dp.extraArgs` splice, not hardcoded args:
    an overlay with extraArgs: [] renders the trio ONLY (the strategy flag
    must be removable at values level), and a custom value splices through."""
    docs, _ = A.render("dp:\n  extraArgs: []\n")
    args = A.dp_container(docs).get("args") or []
    assert args == A.CMD_RESTATED, (
        f"C07: with dp.extraArgs=[] the args are {args} — must be the restated CMD trio "
        "exactly (the strategy flag is VALUES data, not template text)"
    )
    docs2, _ = A.render('dp:\n  extraArgs: ["-pulse=5s"]\n')
    args2 = A.dp_container(docs2).get("args") or []
    assert args2 == A.CMD_RESTATED + ["-pulse=5s"], (
        f"C07: dp.extraArgs splice rendered {args2} — the extraArgs list must pass through verbatim"
    )


# --- AC1: image pin ------------------------------------------------------------


@helm_skip
def test_image_is_the_product_naming_plugin_tag():
    docs, _ = A.render()
    image = A.dp_container(docs)["image"]
    assert image == f"{A.PLUGIN_REPO}:{A.PLUGIN_TAG}", (
        f"C07 AC1: image is {image!r}, want {A.PLUGIN_REPO}:{A.PLUGIN_TAG} — the first "
        "release carrying the product strategy (PR #246 merged 2026-10-19, shipped .12)"
    )
    assert "@" not in image, (
        "C07 AC1: a digest FIELD pins the image — the D2 posture is tag + digest-in-comment "
        "(ledger), no image.digest anywhere in this repo"
    )


# --- AC1: name-pinned objects, no orphan-rename --------------------------------


@helm_skip
def test_object_names_are_pinned_to_the_pre_ticket_ds():
    """The source-flip repo->git-path swaps the SAME Application
    (gpu-ai-amd-gpu); Argo's prune then removes anything whose NAME changed.
    The rendered DaemonSet name + pod selector must equal the live DS
    identity (RESEARCH §R6-Q2, EXPLORE §3)."""
    docs, _ = A.render()
    ds = A.daemonset(docs)
    assert ds["metadata"]["name"] == A.DS_NAME, (
        f"C07 AC1: DaemonSet renders as {ds['metadata']['name']!r}, want {A.DS_NAME!r} — "
        "a renamed vendored object is ORPHANED by the Application source-flip"
    )
    assert ds["spec"]["selector"]["matchLabels"] == A.DS_SELECTOR, (
        f"C07 AC1: selector {ds['spec']['selector']['matchLabels']} != {A.DS_SELECTOR}"
    )
    assert A.DS_CONTAINER in [c["name"] for c in ds["spec"]["template"]["spec"]["containers"]], (
        "C07 AC1: the plugin container is not named amd-gpu-dp-cntr (the live identity)"
    )
    # No rendered object left the amd-gpu name family (Chart.yaml name pin):
    renames = [f"{d['kind']}/{d['metadata']['name']}" for d in docs
               if not str(d["metadata"]["name"]).startswith("amd-gpu")]
    assert not renames, (
        f"C07 AC1: objects outside the amd-gpu* name family: {renames} — the vendored "
        "Chart.yaml name field must stay PINNED to `amd-gpu` (templates hardcode .Chart.Name)"
    )


@helm_skip
def test_labeller_and_nfd_render_nothing():
    """labeller.enabled: false + nfd.enabled: false AS TODAY — the live node
    has zero amd.com/* labels; waking the labeller class is a behavior change
    this chunk does not make."""
    vals = A.chart_values()
    dp = vals.get("labeller") or {}
    assert dp.get("enabled") is False, f"C07 AC1: labeller.enabled must be false, got {dp}"
    nfd = vals.get("nfd") or {}
    assert nfd.get("enabled") is False, f"C07 AC1: nfd.enabled must be false, got {nfd}"
    docs, raw = A.render()
    wake = [d["metadata"]["name"] for d in docs
            if "labeller" in str(d["metadata"]["name"]) or "nfd" in str(d["metadata"]["name"]).lower()]
    assert not wake, f"C07 AC1: labeller/nfd objects rendered with the flags off: {wake}"


# --- AC1: volumes + security preserved upstream --------------------------------


@helm_skip
def test_hostpath_volumes_and_security_upstream_shaped():
    """The /sys and kubelet device-plugins hostPaths exist (the plugin's
    enumeration + registration surfaces) and the pod stays drop-ALL
    non-privileged; NO new hostPath class appears (C07 preserves upstream,
    it does not grow device mounts)."""
    docs, _ = A.render()
    spec = A.daemonset(docs)["spec"]["template"]["spec"]
    paths = {v.get("hostPath", {}).get("path") for v in spec.get("volumes", []) if "hostPath" in v}
    assert "/sys" in paths, f"C07 AC1: /sys hostPath missing — product naming reads sysfs directly (PR #246 design note), {paths}"
    assert "/var/lib/kubelet/device-plugins" in paths, (
        f"C07 AC1: the kubelet device-plugins socket dir hostPath missing: {paths}"
    )
    pod_sc = spec.get("securityContext") or {}
    ctr = A.dp_container(docs)
    ctr_sc = ctr.get("securityContext") or {}
    assert not pod_sc.get("privileged") and not ctr_sc.get("privileged"), (
        "C07 AC1: privileged appeared on the plugin pod — upstream is drop-ALL non-privileged"
    )
    drop = ((ctr_sc.get("capabilities") or {}).get("drop") or [])
    assert "ALL" in drop, f"C07 AC1: container capabilities.drop lacks ALL: {ctr_sc}"


@helm_skip
def test_update_strategy_stays_rolling():
    """R6-Q4-4: the DS rollout restarts ONLY the plugin pod — the rolling
    strategy is what keeps that property (OnDelete would stall the naming
    wave; Recreate would double the deregistration gap)."""
    docs, _ = A.render()
    us = A.daemonset(docs)["spec"].get("updateStrategy", {"type": "RollingUpdate"})
    assert us.get("type", "RollingUpdate") == "RollingUpdate", (
        f"C07 AC1: DaemonSet updateStrategy is {us} — must stay the upstream RollingUpdate"
    )


# --- AC3 companion: lint + template run clean ----------------------------------


@helm_skip
def test_helm_lint_passes():
    out = subprocess.run(["helm", "lint", str(A.CHART_DIR)],
                         capture_output=True, text=True, timeout=300)
    assert out.returncode == 0, out.stdout + out.stderr
