# cf-143 C02 — charts/radiance render contract (chunks/C02.md Tests bullet 1;
# AC1/AC2). The shape: a NON-privileged Guaranteed peer Deployment claiming
# the R9700 by its named product pool, Q7 verbatim. The absence needles here
# are LOAD-BEARING per the owner ruling — privileged and hostPath kfd/dri are
# the strata/vllm-era device access this chart must NOT carry (the named-pool
# plugin Allocate() injects /dev/kfd + the card/render); a pod that grows
# them back is a silent Q7 violation, so they assert as reds, not style.
#
# Red state at handoff (designed): every leg red until C02 lands — the chart
# does not exist (missing chart = loud red naming C02; only a missing helm
# binary skips, LOUDLY with the PATH-export reason).
#
# Run per-directory: python3 -m pytest charts/radiance/tests -v

from __future__ import annotations

import re

import subprocess

import pytest

import radiance_testlib as R

_ok, _reason = R.helm_ready()
helm_skip = pytest.mark.skipif(not _ok, reason=_reason)
c04_wiring = pytest.mark.skipif(
    not R.SERVICE_VALUES.is_file() or not R.service_block_present(),
    reason="cf-143 C04: the service radiance: subtree is not on this commit yet "
           "(chart-default legs run without it — AC6)",
)


# --- AC1: lint + template run clean --------------------------------------------


@helm_skip
def test_ac1_helm_lint_passes():
    out = subprocess.run(["helm", "lint", str(R.CHART_DIR)],
                         capture_output=True, text=True, timeout=300)
    assert out.returncode == 0, out.stdout + out.stderr


@helm_skip
def test_ac1_chart_defaults_template_renders():
    R.render(service=False)  # raises AssertionError naming C02 on any failure


# --- AC2: the non-privileged security shape (Q7) ---------------------------------


@helm_skip
def test_ac2_privileged_and_hostpath_absent_everywhere():
    """The load-bearing absence legs of Q7: NO privileged anywhere, NO
    hostPath at all (the plugin injects /dev/kfd + card/render — the strata
    kfd/dri hostPath class and the vllm privileged shape are both out)."""
    docs, raw = R.render(service=False)
    deploy = R.deployment(docs)
    assert "privileged" not in raw or "privileged: false" in raw, (
        "C02 AC2: a privileged field reached the render — Q7 ships NON-privileged; "
        "do not copy charts/vllm's privileged block"
    )
    spec = R.pod_spec(deploy)
    host_paths = [v for v in spec.get("volumes", []) if "hostPath" in v]
    assert not host_paths, (
        f"C02 AC2: hostPath volumes rendered {host_paths} — the named pool makes kfd/dri "
        "hostPaths obsolete (and illegal): RESEARCH §R6-Q1, plugin Allocate injects devices"
    )
    for c in spec.get("containers", []) + spec.get("initContainers", []):
        sc = c.get("securityContext") or {}
        assert not sc.get("privileged"), f"C02 AC2: container {c['name']} is privileged"
    pod_sc = spec.get("securityContext") or {}
    assert not pod_sc.get("privileged"), "C02 AC2: pod-level privileged"


@helm_skip
def test_ac2_pod_security_context():
    """seccomp Unconfined (io_uring/NUMA law), supplementalGroups [486] (kfd —
    live-verified GID, RESEARCH RQ3; render/video join is the C06 receipt,
    one-edit service override), dedicated non-root UID/GID + fsGroup (the
    staged .rad stays group-readable; fresh per-UID io_uring memlock budget,
    llmkube precedent)."""
    docs, _ = R.render(service=False)
    spec = R.pod_spec(R.deployment(docs))
    pod_sc = spec.get("securityContext") or {}
    assert (pod_sc.get("seccompProfile") or {}).get("type") == "Unconfined", (
        f"C02 AC2: seccompProfile is {pod_sc.get('seccompProfile')} — io_uring needs Unconfined (Q7)"
    )
    assert pod_sc.get("supplementalGroups") == R.SUPPLEMENTAL_GROUPS, (
        f"C02 AC2: supplementalGroups {pod_sc.get('supplementalGroups')} — kfd GID 486 is the "
        "live-verified non-privileged device access (RQ3); render/video join per the C06 receipt"
    )
    assert isinstance(pod_sc.get("runAsUser"), int) and pod_sc["runAsUser"] != 0, (
        f"C02 AC2: runAsUser {pod_sc.get('runAsUser')!r} — dedicated non-root UID (per-UID "
        "io_uring memlock budget, llmkube/witness precedent)"
    )
    assert isinstance(pod_sc.get("runAsGroup"), int) and pod_sc["runAsGroup"] != 0, (
        "C02 AC2: runAsGroup must name the dedicated group"
    )
    assert isinstance(pod_sc.get("fsGroup"), int), (
        "C02 AC2: fsGroup missing — the serve container reads the staged 113.6 GiB .rad group-readable"
    )


@helm_skip
def test_ac2_container_capabilities_and_escalation():
    docs, _ = R.render(service=False)
    ctr = R.serve_container(R.deployment(docs))
    sc = ctr.get("securityContext") or {}
    caps = sc.get("capabilities") or {}
    assert caps.get("drop") == ["ALL"], f"C02 AC2: capabilities.drop is {caps.get('drop')}, want exactly [ALL]"
    assert "IPC_LOCK" in (caps.get("add") or []), (
        f"C02 AC2: capabilities.add {caps.get('add')} lacks IPC_LOCK — io_uring/locked buffers (Q7)"
    )
    assert sc.get("allowPrivilegeEscalation") is False, "C02 AC2: allowPrivilegeEscalation must be false"


# --- AC2: Guaranteed QoS via named-pool claim -----------------------------------


@helm_skip
def test_ac2_guaranteed_pair_with_named_pool():
    """requests == limits EXACTLY on the serve container, extended resource
    included: {cpu 8, memory 110Gi (C12 AC1 amendment: the 64 era died at the
    live OOM — the engine printed a 71.04 GiB budget — and the owner ruled 110
    "your figure", D29), GPU_CLAIM: 1} — extended
    resources require equal integer pairs and Guaranteed is the ruling's pod
    class (Q7 + D15 + Q9 named pool)."""
    docs, _ = R.render(service=False)
    ctr = R.serve_container(R.deployment(docs))
    res = R.resources(ctr)
    want = {"cpu": str(R.SCALARS["cpuCores"]), "memory": f"{R.SCALARS['guaranteedMemoryGi']}Gi",
            R.GPU_CLAIM: "1"}
    assert res.get("requests") == want, (
        f"C02 AC2: serve requests {res.get('requests')} != Guaranteed pair {want} "
        "(single-source scalars splice both sides)"
    )
    assert res.get("limits") == want, f"C02 AC2: serve limits {res.get('limits')} != {want}"
    assert R.GPU_CLAIM_BARE not in (res.get("requests") or {}) and R.GPU_CLAIM_BARE not in (res.get("limits") or {}), (
        "C02 AC2: a bare amd.com/gpu claim — after C07's flip the name does not exist on the "
        f"node; the claim is {R.GPU_CLAIM}, the product pool (Q9 naming, D24-renamed)"
    )


@helm_skip
def test_ac2_init_container_is_guaranteed_too():
    """D15: Guaranteed is a POD-class property — ANY container without equal
    pairs silently downgrades the pod to Burstable. The radiance-fetch init
    carries the equal pair (1000m/2Gi — C12 raises the cpu knob on §D4's
    CPU-quota-bound hash law; separable revert is one line) and the matching
    UID posture."""
    docs, _ = R.render(service=False)
    init = R.fetch_init(R.deployment(docs))
    res = R.resources(init)
    want = {"cpu": R.INIT_PAIR["cpu"], "memory": R.INIT_PAIR["memory"]}
    assert res.get("requests") == want and res.get("limits") == want, (
        f"C02 AC2/D15: init resources {res} — must be the equal {want} pair; without it the "
        "whole pod silently leaves the Guaranteed class (comment the law where it renders)"
    )
    sc = init.get("securityContext") or {}
    assert not sc.get("privileged"), "C02 AC2: the init must not be privileged (Q7)"


@helm_skip
def test_ac2_pod_law_recreate_grace_and_no_placement_keys():
    docs, _ = R.render(service=False)
    deploy = R.deployment(docs)
    assert deploy["spec"].get("strategy", {}).get("type") == "Recreate", (
        "C02 AC2: strategy must be Recreate (a second radiance pod would double-pin the host pool)"
    )
    assert R.pod_spec(deploy).get("terminationGracePeriodSeconds") == R.GRACE_SECONDS, (
        f"C02 AC2: grace {R.pod_spec(deploy).get('terminationGracePeriodSeconds')} — 180 s, the "
        "engine drains ~60-120 s on SIGTERM; NOT strata's 420 child-choreography number"
    )
    spec = R.pod_spec(deploy)
    assert not spec.get("nodeSelector"), "C02 AC2: nodeSelector on a single untainted k3s node — the named pool does the placement"
    assert not spec.get("tolerations"), "C02 AC2: tolerations not sanctioned by the plan"


# --- AC2: probes / service / absence surfaces -----------------------------------


@helm_skip
def test_ac2_probes_are_plain_health_on_8000():
    """Probe law (gotcha 10): /health only, key-exempt; startup 180x10s."""
    docs, _ = R.render(service=False)
    ctr = R.serve_container(R.deployment(docs))
    for kind in ("startupProbe", "livenessProbe", "readinessProbe"):
        p = ctr.get(kind) or {}
        http = (p.get("httpGet") or {})
        assert http.get("path") == "/health", f"C02 AC2: {kind} path {http.get('path')!r}, want /health"
        assert http.get("port") in (8000, "http"), f"C02 AC2: {kind} port {http.get('port')!r}, want 8000 (or the named http port)"
    sp = ctr.get("startupProbe") or {}
    assert sp.get("failureThreshold") * sp.get("periodSeconds", 1) >= 1800, (
        f"C02 AC2: startupProbe budget {sp.get('failureThreshold')}x{sp.get('periodSeconds')} — "
        "the shipped envelope is 180x10s (cold-load minutes-class, llmkube probe law R6-S9)"
    )


@helm_skip
def test_ac2_no_serviceaccount_secret_or_ingress():
    """D8: no secret surface; internal-only: no ingress; tokenless SA: none
    (global.createDefaultServiceAccount false)."""
    docs, _ = R.render(service=False)
    for kind, why in (("Ingress", "internal-only — the peer URL is the only route (Q4 mirror)"),
                      ("Secret", "keyless D8 — no secret surface anywhere on this lane"),
                      ("ExternalSecret", "keyless D8 + ungated packs — no bitwarden leg"),
                      ("ServiceAccount", "createDefaultServiceAccount=false (vllm tokenless precedent)")):
        found = [d["metadata"]["name"] for d in docs if d.get("kind") == kind]
        assert not found, f"C02 AC2: {kind} rendered ({why}): {found}"


@helm_skip
def test_ac2_service_is_clusterip_8000_only():
    docs, _ = R.render(service=False)
    svcs = R.services(docs)
    assert len(svcs) == 1, f"C02 AC2: expected exactly one Service, got {[s['metadata']['name'] for s in svcs]}"
    svc = svcs[0]
    assert svc["spec"].get("type") == "ClusterIP", f"C02 AC2: Service type {svc['spec'].get('type')}"
    ports = svc["spec"].get("ports") or []
    assert len(ports) == 1 and ports[0].get("port") == 8000, (
        f"C02 AC2: Service ports {ports}, want exactly port 8000 (the engine's OpenAI-compat surface)"
    )


# --- AC2: storage shape -----------------------------------------------------------


@helm_skip
def test_ac2_models_claim_shared_and_shm():
    """models: existingClaim llama-swap (the shared 500Gi claim; serve RO,
    fetch RW — advancedMounts, the vllm mount law with its do-not-delete
    warning); shm: emptyDir medium Memory 2Gi at /dev/shm; NO kfd/dri."""
    docs, _ = R.render(service=False)
    spec = R.pod_spec(R.deployment(docs))
    vols = {v["name"]: v for v in spec.get("volumes", [])}
    assert not [n for n, v in vols.items() if "hostPath" in v], f"C02 AC2: hostPath volumes: {sorted(vols)}"
    shm = [v for v in vols.values()
           if (v.get("emptyDir") or {}).get("medium") == "Memory"]
    assert shm and shm[0]["emptyDir"].get("sizeLimit") == "2Gi", (
        f"C02 AC2: no /dev/shm emptyDir Memory 2Gi among {sorted(vols)}"
    )
    pvc_claims = {v.get("persistentVolumeClaim", {}).get("claimName") for v in vols.values()}
    assert "llama-swap" in pvc_claims, (
        f"C02 AC2: the models volume must reuse the shared llama-swap claim, claims: {pvc_claims} "
        "(the 113.6 GiB .rad stages there; do-not-delete GGUF warning mirrors vllm 542-552)"
    )
    # Mount polarity: serve reads /models read-only; the init writes it.
    serve_mounts = {m["mountPath"]: m for m in R.serve_container(R.deployment(docs)).get("volumeMounts", [])}
    init_mounts = {m["mountPath"]: m for m in R.fetch_init(R.deployment(docs)).get("volumeMounts", [])}
    assert serve_mounts.get("/models", {}).get("readOnly") is True, (
        f"C02 AC2: serve /models mount {serve_mounts.get('/models')} — must be READ-ONLY "
        "(advancedMounts: serve RO, fetch RW)"
    )
    assert init_mounts.get("/models") and not init_mounts["/models"].get("readOnly"), (
        f"C02 AC2: fetch-init /models mount {init_mounts.get('/models')} — staging needs WRITE"
    )
    assert "/dev/shm" in serve_mounts, "C02 AC2: /dev/shm not mounted into the serve container"


@helm_skip
def test_ac2_no_rocr_hip_env():
    """The named pool selects the card; the plugin injects devices and sets
    NO env — host enumeration is irrelevant inside the container (C02
    absence-law: NO ROCR/HIP env, do not copy charts/vllm 307/310)."""
    docs, _ = R.render(service=False)
    deploy = R.deployment(docs)
    for c in R.pod_spec(deploy).get("containers", []) + R.pod_spec(deploy).get("initContainers", []):
        leaked = sorted(set(R.env_map(c)) & set(R.ABSENT_ENV))
        assert not leaked, f"C02 AC2: {c['name']} carries {leaked} — named pools make host enumeration illegal here"


@helm_skip
def test_ac2_staging_init_shape():
    """D10 staging contract: the radiance-fetch command stages the ungated HF
    pack by curl-resume onto the shared claim with the `.staged-<lfs-sha>`
    marker (vllm setup-init idiom), loud-failing at container start; the
    init image is the pinned curl staging image OR the engine image — nothing
    else (a third image smuggles a build story this ticket does not own)."""
    docs, _ = R.render(service=False)
    init = R.fetch_init(R.deployment(docs))
    command = init.get("command") or []
    assert command and all(isinstance(tok, str) for tok in command), (
        "C02/D10: the fetch-init renders no command list (exec-form boot guard: loud fail at "
        "start, never a sleeping container with a missing script)"
    )
    body = "\n".join(command)
    assert ".staged-0af5e962" in body or (
        ".staged-" in body and R.PACK_LFS_SHA in body
    ) or (".staged-" in body and any(ln.count("$") >= 1 for ln in body.splitlines() if ".staged-" in ln)), (
        "C02/D10: no .staged-<lfs-sha> marker (literal, full-sha, or $-interpolated — the vllm "
        "marker law) in the staging command"
    )
    assert R.PACK_LFS_SHA in body or "0af5e962" in body, (
        "C02/D10: the staging command never names the pack lfs sha 0af5e962… — the marker IS "
        "the landed-file provenance (C06 step 4 sha256sums against it)"
    )
    assert f"{R.PACK_REPO}/resolve" in body or "huggingface.co" in body, (
        "C02/D10: no HF resolve URL for the ungated pack — staging reads the ledgered repo "
        f"{R.PACK_REPO}"
    )
    assert "curl" in body.lower() or "curl" in str(init.get("image", "")).lower(), (
        "C02/D10: curl-resume staging is the ruled mechanism (the resume flag is what survives "
        "an interrupted 113.6 GiB fetch)"
    )
    image = str(init.get("image", ""))
    assert image.startswith(("docker.io/curlimages/curl", "curlimages/curl", R.IMAGE_REPO)), (
        f"C02/D10: init image {image!r} must be the pinned curl staging image or the engine "
        "image (the chunk's two sanctioned shapes)"
    )
    if "curlimages" in image:
        values_text = R.CHART_DIR.joinpath("values.yaml").read_text()
        assert "renovate: datasource=docker depName=" in values_text, (
            "C02: the curl staging image is pinned without its renovate docker comment"
        )


# --- C11: applet-family + checksum-GRAMMAR legs (D27; §D3b) ---------------------


def _staging_script():
    docs, _ = R.render(service=False)
    init = R.fetch_init(R.deployment(docs))
    command = init.get("command") or []
    assert len(command) >= 3 and command[0] == "sh" and command[1] == "-c", (
        "C11: the fetch-init is no longer [sh -c <script>] — the grammar legs' parse anchor "
        "moved; re-read §D3b and re-pin (not silently vacuous)"
    )
    return init, command[2]


@helm_skip
def test_ac2_staging_image_identity_pinned_and_digest_ledged():
    """C11 AC4.1/AC4.3 image-identity gate: the grammar law's premise is the
    init image's applet FAMILY. The repo must stay inside the BusyBox-family
    set AND the family must be PINNED, not inferred from a floating tag — a
    64-hex digest-ledger comment beside the init image block (repo D2
    posture; seed = the live imageID 3fb7e13e…, §D3b.1). If someone swaps to
    a GNU-family image, THIS leg reddens and forces the re-ruling of the
    grammar ban (AC1's equality survives both families — the swap is then
    allowed only with the premise pinned anew; the ban leg refuses to
    silently pass on a swapped family).

    Honest split: the family half is GREEN today (curlimages/curl is in the
    set); the digest-ledger half is DESIGNED-RED until dev adds the one
    comment line (AC4.3)."""
    init, _script = _staging_script()
    image = str(init.get("image", ""))
    repo = image.rsplit(":", 1)[0]
    assert repo in R.BUSYBOX_FAMILY_REPOS, (
        f"C11 premise-pin: init image repo {repo!r} left the BusyBox-family set {R.BUSYBOX_FAMILY_REPOS} "
        "— the option-grammar law below must be re-ruled against the new family, not pass vacuously"
    )
    lines = R.chart_values_text().splitlines()
    idx = [i for i, ln in enumerate(lines) if R.BUSYBOX_FAMILY_REPOS[0] in ln and "repository" in ln]
    assert idx, "C11 AC4.3: the curl staging image block vanished from values.yaml"
    # flattened window join (the str.join-of-lists class, 12.6 law applies to itself)
    window = " ".join(ln for i in idx for ln in lines[max(0, i - 6):i + 14])
    assert re.search(re.escape(R.INIT_IMAGE_ID_SEED) + r"[0-9a-f]{48}", window), (
        f"C11 AC4.3 (DESIGNED-RED): no 64-hex digest ledger comment seeded {R.INIT_IMAGE_ID_SEED} "
        "beside the init image — the applet set the grammar law guards must be PINNED (repo D2 "
        "tag+digest-in-comment posture); dev adds the ledger line naming the live imageID"
    )


@helm_skip
def test_ac2_staging_grammar_matches_the_init_image_applets():
    """C11 AC4.1 grammar ban — THE red leg today (`--check` at values 346):
    inside a BusyBox-family image, GNU LONG options die at option parse
    (getopt32 "^" "scwbt" short-only, md5_sha1_sum.c; live banner v1.37.0
    bracketed by 1_36_1<->master byte-identity) → exit 1 → set -e → marker
    unreachable → CrashLoop (§D3b/D27). Therefore: NO `--…` long option on
    any hash-applet line; NO lone -s/-w (BusyBox-only quiet/warn — GNU has
    no short -s, its own FIXME says so); NO -c without an explicit operand
    (GNU stdin-implicit asymmetry half-dies). D27's rejected forms
    (--check/--status/-cs/-c -s) are asserted absent outright: nobody may
    'fix' the gate into either family's exclusive shape.

    Parse-based (rendered script lines), never a whole-file grep — vocabulary
    legs are exactly what failed to catch this defect for four review rounds.
    Runtime end-to-end proof belongs to CI/on-target (AC6 receipt walk) — this
    repo has no docker daemon in agent sessions; what CAN be proven offline —
    image family + option grammar — is proven here."""
    import re as _re

    init, script = _staging_script()
    repo = str(init.get("image", "")).rsplit(":", 1)[0]
    if repo not in R.BUSYBOX_FAMILY_REPOS:
        pytest.fail(
            f"C11: init repo {repo!r} is off the family set — the identity gate leg owns that "
            "swap; the grammar ban refuses to pass vacuously on an unruled premise"
        )
    problems = []
    for ln in script.splitlines():
        if not R.HASH_APPLET_RE.search(ln):
            continue
        stripped = ln.strip()
        if _re.search(r"--[A-Za-z-]+", stripped):
            problems.append(("GNU long option dies in BusyBox (exit 1 → no marker)", stripped))
        if _re.search(r"(?<!\S)-[sw](?![a-zA-Z])", stripped) and "-c" not in stripped:
            problems.append(("BusyBox-only short -s/-w without -c (GNU has no short -s)", stripped))
        for bad_form in R.REJECTED_GATE_FORMS:
            if bad_form in stripped:
                problems.append((f"rejected D27 shape {bad_form!r}", stripped))
        if _re.search(r"(?<!\S)-c(?=\s|$)", stripped) and not _re.search(r"-c[ \t]+[^ \t-]", stripped):
            problems.append(("-c without an explicit operand (GNU implicit-stdin asymmetry)", stripped))
    assert not problems, (
        "C11 AC1/§D3b/D27: checksum-gate grammar vs the pinned BusyBox image family —\n  "
        + "\n  ".join(f"{why}: {line}" for why, line in problems[:6])
        + "\nPortable AC1 shape: compute + shell equality, touch marker AFTER the guard."
    )


@helm_skip
def test_ac2_staging_checksum_gate_is_the_portable_equality():
    """C11 AC4.1 positive arms — the ONE replacement shape (green only when
    dev lands AC1 verbatim, red today): the equality gate computes via
    `sha256sum "$PACK" | cut -d' ' -f1` (the two-space output form both
    families print), tests [ "$actual" != "$LFS_SHA" ], echoes MISMATCH
    naming BOTH expected= and actual=, exits non-zero, and `touch "$MARKER"`
    sits AFTER the guard — marker-unreachable-on-failure asserted as
    RENDER-SHAPE ordering. Missing/partial file needs no extra guard: the
    applet's error goes to stderr, the pipeline's stdout is empty, and an
    empty actual can never equal the 64-hex ledger value (loud MISMATCH) —
    the D27 adjudication. Loud-failure EXECUTION is CI/on-target territory
    (no docker daemon here — stated honestly, not faked); the render-order
    assertions below are the offline share of it."""
    _init, script = _staging_script()
    lines = script.splitlines()
    def _has_all(tokens, line):
        return all(tok in line for tok in tokens)

    eq_line = next((ln for ln in lines if _has_all(R.EQ_GATE_TOKENS, ln)), None)
    assert eq_line is not None, (
        f"C11 AC1: no compute line {' '.join(R.EQ_GATE_TOKENS)!r} in the staging script — "
        "the equality gate is absent (this is the live CrashLoop shape)"
    )
    neq_line = next((ln for ln in lines if _has_all(R.NEQ_TEST_TOKENS, ln) and ln.strip().startswith("if")), None)
    assert neq_line is not None, (
        'C11 AC1: no [ "$actual" != "$LFS_SHA" ] test — the gate cannot fail loudly without it'
    )
    echo_line = next((ln for ln in lines if _has_all(R.MISMATCH_ECHO_TOKENS, ln)), None)
    assert echo_line is not None, (
        "C11 AC1: the MISMATCH echo must name BOTH expected= and actual= on ONE line — the "
        "owner-facing digests-on-one-line requirement (D27; -c - rejected for exactly this)"
    )
    idx = {ln: i for i, ln in enumerate(lines)}
    touch_i = next((i for i, ln in enumerate(lines) if 'touch "$MARKER"' in ln), None)
    assert touch_i is not None, "C02/C11: touch $MARKER vanished (success artifact must survive)"
    exit_i = next((i for i, ln in enumerate(lines) if "exit 1" in ln and i > idx[neq_line]), None)
    assert exit_i is not None, "C11 AC1: no `exit 1` after the mismatch test — set -e alone is not the guard"
    assert exit_i < touch_i, (
        "C11 AC1 loud-failure shape: exit-1 must PRECEDE touch — on mismatch the marker stays "
        "unreachable (the CrashLoop-without-marker class returns otherwise)"
    )
    curl_line = next((ln for ln in lines if ln.strip().startswith("curl ")), None)
    assert curl_line is not None and "--continue-at -" in curl_line and \
        '-output "$PACK"' in curl_line, (
        "C11 AC1 invariants: the curl download part is BYTE-UNCHANGED — resume no-op is proven, "
        "flag churn is out of contract (§D3.6: the failure was never a timeout)"
    )


# --- AC6: sentinel-free renders ----------------------------------------------------


@helm_skip
def test_ac6_chart_default_render_is_sentinel_free():
    docs, raw = R.render(service=False)
    assert "OVERRIDE_" not in raw, (
        f"C02 AC6: the chart-default render leaks sentinels: {[ln for ln in raw.splitlines() if 'OVERRIDE_' in ln][:3]}"
    )


@c04_wiring
@helm_skip
def test_ac6_service_level_render_is_sentinel_free():
    """AC6 + the radiance workflow's second leg, run early here: the extracted
    radiance: service subtree overlays cleanly and the render stays clean
    (D8: no bitwardenIds leg to wake a secret template)."""
    docs, raw = R.render(release="gpu-ai-radiance", service=True)
    assert "OVERRIDE_" not in raw, (
        f"C04 AC7: the service-level render leaks sentinels: {[ln for ln in raw.splitlines() if 'OVERRIDE_' in ln][:3]}"
    )


@helm_skip
def test_reloader_annotation_absent():
    """C02: reloader annotation OFF — the chart ships NO ConfigMaps, there is
    nothing to reload (the why is the plan's note; a stale reloader:auto on a
    configless pod is drift)."""
    docs, _ = R.render(service=False)
    ann = (R.deployment(docs)["spec"]["template"].get("metadata") or {}).get("annotations") or {}
    assert not [k for k in ann if "reloader.stakater.com" in k], f"C02: reloader annotations present: {ann}"


@helm_skip
def test_main_container_stays_command_absent_entrypoint_witnessed():
    """C09 AC5 optional hardening (test-session discretion): the C09 command
    requirement is CONTAINER-SPECIFIC, and the radiance main container is the
    opposite half of the §D1.6 law — its image DOES carry
    Entrypoint ["radiance"] (EXPLORE §D1.5, registry-verified at the pinned
    digest 6fb0e99b…), so the args-only shape is SAFE and CORRECT here.
    Copying the command key across "for consistency" would be a regression
    (command replaces the ENTRYPOINT, and the image's own exec resolution is
    what makes the current form work). Green today; it exists to catch a
    future copy-paste of the fix."""
    docs, _ = R.render(service=False)
    ctr = R.serve_container(R.deployment(docs))
    assert "command" not in ctr, (
        "C09 §D1.6: the radiance serve container gained a command key — its image HAS an "
        "ENTRYPOINT ([radiance], §D1.5 registry receipt), args-only is the ruled shape; "
        "removing this leg requires new Entrypoint-absence evidence of its own"
    )
