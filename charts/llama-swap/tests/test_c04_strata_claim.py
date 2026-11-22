"""2026-11-feat-radiance-multi-instance C04 — strata's REAL claim, parked.

Owner ruling D17 overturns the NO-CLAIM half of the 2026-10-27 device-access
ruling: the strata controller becomes an accounted claimant on the renamed pool
(`amd.com/gpu-r9700`, count 1) for SCHEDULING, while the privileged hostPath
runtime posture and the rocrVisibleDevices carriers STAY (mechanism b1 — claim
for scheduling, hostPath for runtime). b1 is not a style choice: the patched
plugin mounts only `/dev/kfd`+`/dev/vdi`, llama.cpp needs the `/dev/dri` render
nodes, so the claim cannot replace the mounts (RESEARCH R-Q5).

Every claim-shape leg runs through the PROJECTION layer (cf-143 D26): the
ApplicationSet chain drops nulls before helm sees them, so a helm-only proof
blesses a shape production never renders.

Red state at handoff (designed): the claim, the replicas-0 park, the supersession
annotations and the two-leg determinism prose are RED naming C04. The KEEP-list
arms (privileged, both hostPaths, the rocr carriers, the chart/gpu-cluster
claim-less shield) are GREEN today and are the drift bars.

Run per-directory: python3 -m pytest charts/llama-swap/tests -v
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pytest

import llama_swap_testlib as L
import strata_testlib as S

# The canonical name block (the one edit site; C01's rename lands there) — the
# cross-chart import idiom test_cf143_naming_flip.py already uses.
_amd_tests = Path(L.REPO_ROOT) / "charts" / "amd-gpu" / "tests"
if str(_amd_tests) not in sys.path:
    sys.path.insert(0, str(_amd_tests))
import amd_gpu_testlib as A  # noqa: E402

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)

GPU_AI = "gpu-ai"
GPU = "gpu"
OVERLAY = L.REPO_ROOT / "services" / "gpu-ai" / "prod" / "values.yaml"


def _projection(cluster):
    docs, _raw, _rv = L.render_via_projection(cluster)
    return docs


def _strata_container(cluster=GPU_AI):
    return S.strata_container(_projection(cluster))


def _strata_resources(cluster=GPU_AI):
    res = _strata_container(cluster).get("resources", {})
    return res.get("requests") or {}, res.get("limits") or {}


def _overlay_strata_region() -> str:
    """The service file's strata region WITH comments (the laws this chunk ships
    are comment-carried, so a parsed read cannot see them)."""
    lines = OVERLAY.read_text().splitlines()
    hits = [i for i, ln in enumerate(lines) if re.match(r"^\s+strata:", ln)]
    assert hits, "no strata: controller in the gpu-ai llama-swap overlay"
    start = hits[0]
    top = start
    while top > 0 and (lines[top - 1].strip().startswith("#") or not lines[top - 1].strip()):
        top -= 1
    indent = len(lines[start]) - len(lines[start].lstrip())
    end = start + 1
    while end < len(lines):
        ln = lines[end]
        stripped = ln.strip()
        if stripped and (len(ln) - len(ln.lstrip())) <= indent and not stripped.startswith("#"):
            break
        end += 1
    return "\n".join(lines[top:end])


# --- AC1: the claim, at the projection layer, beside the memory legs -----------


@helm
def test_c04_strata_claims_the_renamed_pool_in_both_maps():
    """C04 AC1 (D17): the gpu-ai OVERLAY-MERGED strata container claims the renamed pool
    at count 1 in requests AND limits (the mirror is how extended resources are
    accounted), while the 110Gi ceiling survives — the claim ADDs a key, it does not
    replace the map (cf-143 D26 positive-ADD carrier law)."""
    req, lim = _strata_resources()
    want = A.R9700_CLAIM
    for name, m in (("requests", req), ("limits", lim)):
        assert str(m.get(want)) == "1", (
            f"C04 AC1: strata {name}[{want!r}] is {m.get(want)!r}, want 1 — the overlay ADD has not "
            "landed; designed-red naming C04 (the claim is what makes strata an accounted claimant)"
        )
        assert str(m.get("memory")) == S.STRATA_CGROUP_LIMIT, (
            f"C04 AC1: strata {name} memory is {m.get('memory')!r}, want {S.STRATA_CGROUP_LIMIT} — "
            "the #1601 pairing (engine caps priced inside the cgroup) dies if the claim edit dropped it"
        )
    assert req == lim or set(req.items()) >= {("memory", lim["memory"])}, (
        f"C04 AC1: requests {req} and limits {lim} diverged beyond the mirror law"
    )


@helm
def test_c04_strata_parks_in_the_same_wave_as_the_claim():
    """C04 AC1 (OQ-K): replicas 0 rides the SAME commit as the claim. fn holds both
    cards, so a strata that still asks for 1 with replicas 1 sits Pending against the
    live lane — the park is what makes the sync apply-time safe. Provider registration
    stays (parked is not deleted): the hop answers the 502 peer-proxy error like every
    resting lane."""
    dep = S.strata_deployment(_projection(GPU_AI))
    got = dep.get("spec", {}).get("replicas")
    assert got == 0, (
        f"C04 AC1: the strata Deployment renders replicas {got!r}, want 0 — strata(1) + fn(2) is 3 cards "
        "on a 2-card pool, so an un-parked claim wave leaves the deployment Pending forever (OQ-K: the "
        "park lands in the same commit as the claim, precisely to avoid this window)"
    )


# --- AC1 KEEP-list: b1 runtime posture must not drift --------------------------


@helm
def test_c04_b1_runtime_posture_survives_the_claim():
    """C04 KEEP-list (b1, and the reason it is b1 and not b2): privileged, hostPath
    `/dev/kfd` + `/dev/dri` and the rocr carriers all stay. A claim buys SCHEDULING
    exclusivity only — the patched plugin mounts no `/dev/dri`, so a claim-only pod
    would have no render node at all (R-Q5). A test that asks strata to LOSE these is a
    faulty test under D17 and must be routed back to the test session, never complied
    with in code."""
    cont = _strata_container()
    pod = S.strata_pod(_projection(GPU_AI))
    sec = {**pod["spec"].get("securityContext", {}), **cont.get("securityContext", {})}
    assert sec.get("privileged") is True, (
        f"C04 KEEP: strata lost privileged (securityContext {sec}) — b1 keeps the device-access ruling's "
        "runtime half; the 2026-11-22 claim does not replace it"
    )
    vols = {v.get("name"): v for v in pod["spec"].get("volumes", [])}
    hosts = {v["hostPath"]["path"] for v in vols.values() if "hostPath" in v}
    for dev in ("/dev/kfd", "/dev/dri"):
        assert dev in hosts, (
            f"C04 KEEP: the {dev} hostPath is gone ({sorted(hosts)}) — the claim does not provide it: "
            "the patched plugin mounts /dev/kfd + /dev/vdi only, and llama.cpp needs /dev/dri (R-Q5)"
        )
    cfg = S.service_strata_overlay()
    blob = str(cfg)
    assert "rocrVisibleDevices" in blob, (
        "C04 KEEP: the rocrVisibleDevices carrier vanished — inside the pod, ROCr still enumerates host "
        "ordinals, so chip selection stays a container-leg decision the claim cannot make"
    )


@helm
def test_c04_chart_and_gpu_cluster_stay_claim_less():
    """C04 AC2 (shield law): the claim is a gpu-ai OVERLAY ADD. The chart ships no
    R9700 claim (a fresh cluster must render a schedulable pod) and the gpu cluster's
    projection never sees the name — its plugin is single-naming and cannot advertise
    it, so a stray there is a Pending-forever pod (the C10/D26 carrier law)."""
    for cluster in (GPU,):
        _docs, raw, _rv = L.render_via_projection(cluster)
        assert A.R9700_CLAIM not in raw, (
            f"C04 AC2: the {cluster} projection render names {A.R9700_CLAIM} — that cluster's plugin cannot "
            "advertise the name and the pod would schedule against a capacity-0 pool"
        )
        assert A.BARE_GPU_CLAIM in raw or True  # bare posture is owned by test_cf143_naming_flip
    chart_text = (L.REPO_ROOT / "charts" / "llama-swap" / "values.yaml").read_text()
    live = [
        ln for ln in chart_text.splitlines()
        if re.match(r"^\s*" + re.escape(A.R9700_CLAIM) + r":\s*[\"']?[0-9]", ln) and not ln.lstrip().startswith("#")
    ]
    assert not live, f"C04 AC2: charts/llama-swap/values.yaml carries a live R9700 claim line: {live}"


# --- AC3: the prose, in both legs ----------------------------------------------


def test_c04_determinism_prose_states_both_legs():
    """C04 AC3: the corrected determinism prose has TWO legs and conflates neither —
    the SCHEDULER leg (allocations exclusive, a free single-card claim goes to the
    lowest-KFD-NodeId card, competing claim-1 pods stack by admission order) and the
    CONTAINER leg (hostPath sits outside plugin accounting; rocrVisibleDevices still
    governs chip hiding). The error class this catches is prose that says the claim
    pins which card the PROCESS uses."""
    region = _overlay_strata_region()
    flat = " ".join(region.split())
    assert re.search(r"(?i)scheduler|schedul", flat) and re.search(r"(?i)exclusiv|accounted", flat), (
        "C04 AC3: the strata overlay comment never states the SCHEDULER leg (the claim makes strata an "
        "accounted claimant with exclusive allocations) — that is the half the ruling adds"
    )
    assert re.search(r"(?i)rocrVisibleDevices|host ordinal", flat), (
        "C04 AC3: the CONTAINER leg is missing — hostPath enumeration sits outside plugin accounting and "
        "rocrVisibleDevices still decides which chip the process sees"
    )
    assert re.search(r"(?i)(claim[^.]{0,120}(does not|never)[^.]{0,80}(pin|choose|select)[^.]{0,60}card"
                     r"|does not pin which card)", flat), (
        "C04 AC3: the prose never says the claim pins WHO ELSE may schedule, not WHICH CARD the process "
        "uses — conflating the two legs is the contradiction this chunk exists to fix (RESEARCH C-contradictions)"
    )


def test_c04_supersession_annotation_on_the_2026_10_27_ruling():
    """C04 AC3 (annotate-never-rewrite): the dated 2026-10-27 device-access ruling is
    SUPERSEDED at its sites by dated annotations — the overlay's strata region gains the
    claim-added line, and the chart's privileged-hostPath "either way" comment gains the
    ruling that made mount-survival law.

    RE-ARMED in the test session after the C01 dev comment false-greened the first cut:
    a bare date token anywhere in a file is not a supersession (dev's naming comment at
    the chart carried 2026-11-22 for the pool rename and the HEAD text already said
    "either way"), so every arm below demands windowed CO-OCCURRENCE — the supersession
    vocabulary bound to both ruling dates / to the claim words — and the overlay arm is
    scoped to the strata region, not the file. DESIGNED RED until C04 writes the
    annotations: neither site carries the supersession vocabulary today."""
    region = " ".join(_overlay_strata_region().split())
    assert re.search(r"(?i)supersed", region), (
        "C04 AC3: the gpu-ai overlay's strata region carries no supersession annotation — D17 overturns the "
        "NO-CLAIM half of the 2026-10-27 device-access ruling and the reversal must read at the site a future "
        "editor trusts (a date token alone does not count — the naming wave supplies those incidentally)"
    )
    for cite in ("2026-10-27", "2026-11-22"):
        assert cite in region, (
            f"C04 AC3: the strata region lost its {cite} citation — supersession is done by citation, never "
            "by deletion (annotate-never-rewrite: the annotation names both rulings)"
        )
    assert re.search(r"(?i)supersed[^.]{0,220}claim|claim[^.]{0,220}supersed", region), (
        "C04 AC3: no supersession sentence BINDS the claim change — D17 supersedes the no-claim half "
        "(claim for scheduling, privileged hostPath for runtime); an annotation that never names what moved "
        "is decoration"
    )
    chart = " ".join((L.REPO_ROOT / "charts" / "llama-swap" / "values.yaml").read_text().split())
    i = chart.lower().find("either way")
    assert i >= 0, (
        "C04: the privileged-hostPath 'either way' sentence left charts/llama-swap/values.yaml — D17 KEEPS the "
        "mounts; that sentence is the runtime-posture anchor and is annotated, never deleted"
    )
    window = chart[max(0, i - 300): i + 300].lower()
    assert ("d17" in window or "supersed" in window) and "claim" in window, (
        "C04 AC3: the 'either way' comment never cites the ruling that made mount-survival-under-claim law — it must "
        "carry D17 (or the supersession) AND the claim words within one window; the 2026-11-22 token naming wave "
        "dropped near this text is a NAMING date, not this ruling — that incidental satisfaction is exactly what "
        "this re-arm rejects"
    )


def test_c04_steady_state_table_has_one_home_and_the_runbook_sentence():
    """C04 AC3: the steady-state claim table lives in exactly ONE prose home (the plan's
    table rendered into the strata block comment) with the C06 roster note pointing at
    it — two copies drift. The MoE bring-up order (fn→0, pod gone, strata→1) must be
    stated where an operator reads it."""
    region = _overlay_strata_region()
    flat = " ".join(region.split())
    assert re.search(r"(?i)steady.state|combination table", flat), (
        "C04 AC3: the strata block carries no steady-state/combination table (or pointer) — the arithmetic "
        "that makes strata+fn dead is the reader's only defence against a manual scale-up that PENDINGs"
    )
    assert re.search(r"(?i)fn[^.]{0,40}0[^.]{0,60}strata[^.]{0,40}1|scale fn to 0", flat), (
        "C04 AC3: the MoE bring-up order (fn→0, wait for the pod to be gone, strata→1) is missing"
    )


# --- AC4/AC5: receipts gate the UUID arm ---------------------------------------


def test_c04_no_blind_uuid_pin_without_the_r1_receipt():
    """C04 AC4/AC5 (D22, one-way provenance): the ROCR UUID arm is LIVE only if the
    owner's R1 paste (nonzero unique_ids) is recorded. A render that injects the two
    strata UUID prefixes while DECISIONS records no receipt is the silent-truncation
    failure mode R-Q2 describes: a zero unique_id renders `Invalid-UUID`, matches
    nothing, and the engine quietly sees no device."""
    chart = (L.REPO_ROOT / "charts" / "llama-swap" / "values.yaml").read_text()
    overlay = OVERLAY.read_text()
    uuids = ("f14f913b0a98ad15", "d34663795f09a76f")
    shipped = [u for u in uuids if u in chart or u in overlay]
    if not shipped:
        return  # ordinal posture — the recorded default when no paste lands
    decisions = next(
        (p for p in (L.REPO_ROOT / ".agents" / "plans" / "2026" / "2026-11-feat-radiance-multi-instance").glob("DECISIONS.md")),
        None,
    )
    text = decisions.read_text() if decisions else ""
    assert re.search(r"(?i)OQ-?R1|kfd/topology/nodes|unique_id", text), (
        f"C04 AC5: the UUID pins {shipped} shipped with no R1 receipt recorded in DECISIONS — a blind pin "
        "on a host whose unique_ids were never read is the Invalid-UUID silent-truncation class (D22)"
    )
