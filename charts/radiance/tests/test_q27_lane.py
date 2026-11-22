# cf-143 C15 — the q27 lane contract (chunks/C15.md T3/T4/T6; AC1/AC2/AC3/
# AC4/AC8/AC10). A SECOND RELEASE of the same chart dir: the gpu-ai roster
# gains radiance-q27 with a `chart: radiance` override (D56(1) — one chart,
# two releases), and every q27 truth ships as a whole-list replacement in
# the top-level `radiance-q27:` overlay subtree of
# services/gpu-ai/prod/values.yaml. charts/radiance/values.yaml stays a
# ZERO-DIFF file by design — which is why the q27 arms read the OVERLAY and
# render the chart with the q27 release name, never the chart defaults.
#
# Red state at handoff (designed): every subtree/render/comment leg is RED
# against today's tree (no radiance-q27 subtree exists yet) and greens with
# C15-dev's single commit (D1-D8). The legs that stay GREEN now are drift
# bars: the keyless grep ban (AC4), the base-appset lever needle, and the
# CI extraction leg that works before AND after the subtree lands (C01
# gotcha-14 idiom).
#
# Run per-directory: python3 -m pytest charts/radiance/tests -v

from __future__ import annotations

import collections
import re
import subprocess

import pytest
import yaml

import radiance_testlib as R

_ok, _reason = R.helm_ready()
helm_skip = pytest.mark.skipif(not _ok, reason=_reason)

BASE_APPSET = R.REPO_ROOT / "charts" / "base" / "templates" / "appset-charts.yaml"


def _q27_docs():
    docs, _raw = R.render_q27()
    return docs


# --- AC1: the roster entry and the name law -------------------------------------


def test_c15_roster_entry_is_the_chart_override():
    """C15 AC1 / D1: the gpu-ai charts: map carries
    {appName: radiance-q27, chart: radiance, namespace: default,
    ServerSideApply: "false"} EXACTLY — the roster `chart:` key is the
    documented second-release lever (D56; precedents zigbee2mqtt /
    actualbudget), and ServerSideApply "false" clones the llama-swap-family
    shape of the fn entry (gotcha 6)."""
    doc = yaml.safe_load(R.SERVICE_VALUES.read_text())
    entry = (doc.get("charts") or {}).get(R.Q27_APP_NAME)
    assert isinstance(entry, dict), (
        "cf-143 C15: charts.radiance-q27 missing from services/gpu-ai/prod/values.yaml — "
        "dev D1 (the roster entry) has not landed; designed-red naming C15"
    )
    assert entry == R.Q27_ROSTER, (
        f"cf-143 C15: charts.radiance-q27 is {entry}, want EXACTLY {R.Q27_ROSTER} "
        "(internal chart, chart-dir override, no version/repository keys)"
    )


def test_c15_appset_chart_lever_and_name_derivation_present():
    """Name-law evidence (the coexistence n1 idiom): the base appset derives
    the Application name as {{serviceName}}-{{ .appName }} (→
    gpu-ai-radiance-q27 — the host the peers.radiance-q27 hop points at) and
    resolves the git PATH through the `hasKey "chart"` branch (charts/base/
    templates/appset-charts.yaml:83). Green today, drift-barred: if either
    shape moves, the second release silently breaks and this names C15."""
    text = BASE_APPSET.read_text()
    assert 'name: "{{ `{{ .serviceName }}` }}-{{ `{{ .appName }}` }}"' in text, (
        "cf-143 C15: the base appset Application-name derivation changed — the q27 "
        "Application name gpu-ai-radiance-q27 derives from exactly this template"
    )
    assert '{{ if hasKey . "chart" }}{{ .chart }}{{ else }}{{ .appName }}{{ end }}' in text, (
        'cf-143 C15: the appset `chart:` path branch is gone — D56\'s topology (one chart dir, '
        "two releases) has no lever; re-read charts/base before trusting any q27 wiring"
    )


# --- AC2: the pod truth of the q27 release ---------------------------------------


@helm_skip
def test_c15_q27_release_renders_rc0():
    """The §D54 probe's promise as a leg: the SAME chart dir renders cleanly
    under release name gpu-ai-radiance-q27 with the subtree overlaid
    (helm rc 0 — the render helper raises AssertionError naming C15 on any
    failure, missing subtree included)."""
    R.render_q27()


@helm_skip
def test_c15_q27_pod_rests_at_zero_replicas():
    """D54(1): git renders replicas: 0 — the honest resting state. An idle
    pod at 1 would Pend forever (capacity-1 pool + non-subtractable claim,
    D26) and LOOK like a defect; the owner flips the lane by scaling."""
    deploy = R.deployment(_q27_docs())
    assert deploy["spec"].get("replicas") == R.Q27_REPLICAS, (
        f"cf-143 C15: q27 Deployment replicas is {deploy['spec'].get('replicas')!r}, want 0 "
        "(the shipped resting state — pod-swap, not co-residency; §R19/§D54-H arithmetic)"
    )


@helm_skip
def test_c15_q27_composed_vector_is_the_profile_set_equality():
    """C15 AC2, re-anchored by owner ruling D43 (2026-11-22): what equals the
    Q27_PROFILE constant as a set is no longer the RENDERED ARGS but the vector
    the chart-owned serve wrapper COMPOSES when it boots on this lane's
    rendered env (extra flag as red as a missing one — the fn AC3 idiom), each
    flag once. --model is compared at the composed vector AND the env AND the
    subtree ledger (the three-place anchor — the era's "ARGS literal" was the
    reverse-trap wording; the trap shape moved with the carrier). Designed-red
    until dev round 3 lands the wrapper and the lane env."""
    comp = R.lane_composition(R.Q27_APP_NAME)
    facts = comp["facts"]
    assert facts["rc"] == 0, (
        f"C15/D43: the q27 compose died on the lane env (rc {facts['rc']}, stderr {facts['stderr'][:200]!r})"
    )
    args = facts["argv"]
    assert args, "C15/D43: the q27 engine stub never ran — no composed vector"
    pairs = R.flag_pairs(args)
    want = {f: str(v) for f, v in R.Q27_PROFILE.items()}
    missing = {f: v for f, v in want.items() if pairs.get(f) != v}
    extra = {f: v for f, v in pairs.items() if f not in want}
    assert not missing and not extra, (
        "cf-143 C15 AC2/D43: q27 composed vector diverges from the D54-ratified profile\n"
        f"  missing/incorrect: {missing}\n  extra: {extra}"
    )
    seen = collections.Counter(a for a in args if a.startswith("--"))
    dupes = {f: c for f, c in seen.items() if c > 1}
    assert not dupes, f"cf-143 C15: duplicated q27 flags {dupes}"


@helm_skip
def test_c15_q27_absence_set():
    """C15 AC2 / D56(7), re-anchored by D43 (2026-11-22): the q27 profile omits
    eight fn/expert flags, each a named bar — see the Q27_ABSENT_FLAGS reasons
    in the testlib (dense model: no streaming mirror, no n-gram/PLE layer, no
    experts, drafter in-pack; keyless per D8/D54). Under the env-fed compose
    model absence is TWO laws: the composed vector must not carry the flag, AND
    the lane env must not author the env name that would emit it (a dense lane
    feeding RADIANCE_PLACEMENT is a lane lying about its family)."""
    comp = R.lane_composition(R.Q27_APP_NAME)
    args = comp["facts"]["argv"]
    assert args, "C15/D43: no composed vector (see the profile-set leg)"
    pairs = R.flag_pairs(args)
    for flag in R.Q27_ABSENT_FLAGS:
        assert flag not in pairs, (
            f"cf-143 C15: {flag} composed in the q27 vector — "
            + (
                "keyless ruling D8/D54(2) (the owner's api-key rider is DROPPED)"
                if "api-key" in flag
                else "the arch REFUSES kv-resident on a non-streaming dense model (§R19-Q1(iii))"
                if flag == "--kv-resident"
                else "q27's family has no n-gram/PLE layer (§R19-Q7)"
                if flag in ("--ngram-placement",)
                else "no experts to place and no host pool to size (§R19-Q7, D56(7))"
                if flag in ("--placement", "--host-pool-mib")
                else "co-residency etiquette only — moot in a pod-swap (§R19-Q6)"
                if flag == "--gpu-headroom-mib"
                else "the DFlash2 drafter is IN-PACK; 'the flag simply doesn't own the drafter' (§R19-Q5)"
            )
        )
        env_names = [n for n, f in R.ENV_TO_FLAG.items() if f == flag]
        for env_name in env_names:
            assert env_name not in comp["env"], (
                f"C15/D43: q27 authors env {env_name} for the barred flag {flag} — env-absent is "
                "the absence mechanism; a dense lane must not carry the expert-family channel"
            )
    assert "serve" not in args, (
        "cf-143 C15: a `serve` VERB token in the q27 vector — the engine takes args "
        "directly (the fn RQ0 law is engine-wide, not per-release)"
    )


@helm_skip
def test_c144_q27_guaranteed_pair_with_overlay_pinned_claim():
    """D54(3)/AC2 pair truth, re-pinned by cf-144 C01 (P05): memory 24Gi
    request==limit stays overlay-authored; cpu "8" stays chart-INHERITED;
    the R9700 pool claim (GPU_CLAIM, from the amd-gpu constants) arrives
    OVERLAY-PINNED at "1" — under the
    TP2 chart pair (2) plain inheritance would render 2 and strand q27
    Pending beside a live fn, so the subtree must author the claim itself
    (D26: overlays ADD/UPDATE, never REMOVE — an UPDATE is the lawful
    mechanism). The rendered pair equals exactly {cpu 8, memory 24Gi, claim
    1} in BOTH requests and limits; the independence proof re-pinned under
    C03/D35 (the chart ships no claim to track) is the test_c144_ pair of
    legs below."""
    res = R.resources(R.serve_container(R.deployment(_q27_docs())))
    want = {"cpu": str(R.SCALARS["cpuCores"]), "memory": R.Q27_MEMORY, R.GPU_CLAIM: "1"}
    assert res.get("requests") == want, (
        f"cf-144 C01 AC2: q27 requests {res.get('requests')} != {want} — the 24Gi pair authored "
        "at the overlay, cpu chart-INHERITED (non-subtractable, D26), the claim OVERLAY-PINNED "
        "at 1 (post-flip inheritance renders the chart's 2 — wrong)"
    )
    assert res.get("limits") == want, f"cf-144 C01 AC2: q27 limits {res.get('limits')} != {want}"


@helm_skip
def test_c144_q27_subtree_authors_the_claim_pin_exactly():
    """cf-144 C01 AC2 (authored-value view): the pin must be REAL bytes in the
    subtree — both maps carry the R9700 claim at "1" beside the 24Gi pair and
    NOTHING else. A render-only pass could still let a future edit drift the
    pin; this leg pins the authored map itself. C03 carrier re-aim: the chart
    ships no resources map any more (mechanism-only shell), so cpu is
    AUTHORED beside the pair too — the exactness is unchanged, the map grew
    the one key inheritance used to supply."""
    block = R.q27_service_block()
    assert isinstance(block, dict), (
        "cf-144 C01: no radiance-q27 subtree — designed-red naming C01"
    )
    res = block["app-template"]["controllers"]["radiance"]["containers"]["radiance"]["resources"]
    want = {"cpu": R.Q27_CPU, "memory": R.Q27_MEMORY, R.GPU_CLAIM: "1"}
    for m in ("requests", "limits"):
        assert res.get(m) == want, (
            f"cf-144 C01 AC2: q27 subtree {m} is {res.get(m)!r}, want exactly {want!r} — "
            "the overlay authors the 24Gi pair PLUS the explicit claim-1 pin (P05); cpu joins the "
            "map because the C03 shell ships none to inherit (the exactness bar stands)"
        )


@helm_skip
def test_c144_q27_claim_does_not_track_the_chart_count():
    """cf-144 C01 AC2 (independence proof), re-pinned by C03/D35: the sim
    render it ran is dead because there is no chart-level count to track any
    more — the mechanism-only chart ships NO claim, so overlay inheritance
    cannot propagate one (the old teeth arm, "strip the pin → chart value
    propagates", has no chart value to propagate; the authored-exactness leg
    above guards the pin's bytes). The executable shape today: zero live GPU
    claim lines in the bare chart render, and the q27 release still renders
    exactly 1/1 — its claim has exactly one author, the subtree."""
    _docs, raw = R.render(service=False)
    live = [ln.strip() for ln in raw.splitlines()
            if R.GPU_CLAIM in ln and not ln.lstrip().startswith("#")]
    assert not live, (
        f"C03 AC2: the bare chart render carries live claim lines {live} — a shell claim is the "
        "count every lane would track, which is exactly the coupling cf-144 C01 retired"
    )
    res = R.resources(R.serve_container(R.deployment(_q27_docs())))
    got = {m: (res.get(m) or {}).get(R.GPU_CLAIM) for m in ("requests", "limits")}
    assert got == {"requests": "1", "limits": "1"}, (
        f"cf-144 C01: q27 renders claim {got} with the chart shipping none — the subtree pin is "
        "the claim's only author (1/1 expected)"
    )


@helm_skip
def test_c15_q27_kinds_banned():
    """AC2 / D8 inherited: the q27 release renders NO Secret, ExternalSecret,
    Ingress or ServiceAccount — keyless (no secret chain to wake), internal-only
    (no ingress invented), tokenless (createDefaultServiceAccount false is
    chart-baked and the overlay cannot re-open it)."""
    docs = _q27_docs()
    for kind, why in (
        ("Ingress", "radiance is internal-only — the trio law's proxy leg stays SKIPPED (D56(8))"),
        ("Secret", "keyless D8/D54(2) — no secret surface on the q27 lane either"),
        ("ExternalSecret", "keyless — no bitwarden leg, no fourth custom-values leg"),
        ("ServiceAccount", "createDefaultServiceAccount=false (chart-baked, the overlay inherits it)"),
    ):
        found = [d["metadata"]["name"] for d in docs if d.get("kind") == kind]
        assert not found, f"cf-143 C15: {kind} rendered by the q27 release ({why}): {found}"


@helm_skip
def test_c15_q27_names_dedup_to_the_release():
    """AC2 (the §D54 probe's witnessed fullname law): exactly one Service and
    one Deployment, both named gpu-ai-radiance-q27 (the release name dedups,
    NOTES.txt's fullname idiom), Service on port 8000 — the peer proxy's
    target."""
    docs = _q27_docs()
    deps = [d for d in docs if d.get("kind") == "Deployment"]
    svcs = R.services(docs)
    assert len(deps) == 1 and len(svcs) == 1, (
        f"cf-143 C15: q27 render carries {len(deps)} Deployments / {len(svcs)} Services — "
        "the controller-name dedup the probe witnessed broke"
    )
    for obj, kind in ((deps[0], "Deployment"), (svcs[0], "Service")):
        assert obj["metadata"]["name"] == R.Q27_RELEASE, (
            f"cf-143 C15: {kind} name {obj['metadata']['name']!r}, want {R.Q27_RELEASE!r}"
        )
    ports = (svcs[0]["spec"].get("ports") or [])
    assert len(ports) == 1 and ports[0].get("port") == 8000, (
        f"cf-143 C15: q27 Service ports {ports}, want exactly 8000 (the peer hop's clone shape)"
    )


@helm_skip
def test_c15_q27_render_sentinel_free():
    """AC10's q27 half: the release render carries no OVERRIDE_* sentinel —
    the lane ships no bitwardenIds, so nothing resolves per-environment."""
    _docs, raw = R.render_q27()
    assert "OVERRIDE_" not in raw, (
        "cf-143 C15: the q27 render leaks a sentinel: "
        f"{[ln for ln in raw.splitlines() if 'OVERRIDE_' in ln][:3]}"
    )


# --- AC3: the init grammar guards BOTH renders ------------------------------------


@helm_skip
def test_c15_q27_init_carries_the_four_pack_literals():
    """C15 AC3, re-anchored by D35: the q27 lane's RENDERED script — the
    chart-owned FORM with this lane's scalars substituted (the configMap
    carrier; the anchor pair helper refuses the interim command shape and a
    missing carrier, both naming C03 round 2) — pins the pack ledger as
    runnable values — LFS_SHA a4908940…, PACK the q27 .rad, MARKER the
    .staged-<sha> success artifact, URL the HF resolve path (the marker
    accepts the $-interpolated fn idiom or the expanded form, same three
    shapes the fn marker law accepted)."""
    _init, body = R.fetch_script_and_init(_q27_docs())
    assert f"LFS_SHA={R.Q27_PACK_LFS_SHA}" in body, (
        "cf-143 C15: the q27 init does not assign the ledgered lfs sha in full — "
        "the marker/gate provenance chain starts here"
    )
    assert f"PACK={R.Q27_MODEL_PATH}" in body, (
        f"cf-143 C15: q27 init PACK is not {R.Q27_MODEL_PATH} — one pack, one path"
    )
    assert re.search(r"MARKER=/models/radiance/\.staged-(\$LFS_SHA|" + R.Q27_PACK_LFS_SHA + r")", body), (
        "cf-143 C15: no .staged-<lfs-sha> MARKER (interpolated or expanded) — the vllm/fn "
        "marker law carries to the second call site"
    )
    assert f"URL={R.Q27_PACK_URL}" in body, (
        f"cf-143 C15: q27 init URL is not the ungated resolve path {R.Q27_PACK_URL}"
    )


@helm_skip
def test_c15_q27_init_grammar_is_the_portable_equality():
    """C15 AC3 / D27 class law at the q27 render, parse anchor moved by D35 to
    the rendered configMap script (chart FORM with the lane's scalars
    substituted — the anchor-pair helper rejects the interim command body and
    a missing carrier loudly, naming C03 round 2): the script must use the
    BusyBox-portable compute+compare equality gate (the C11 shape), carry the
    rejected GNU forms (--check/--status/-cs/-c -s) as ABSENT from its
    hash-applet lines, keep curl --continue-at - with the rc-0/33 tolerance,
    and touch the marker only AFTER the guard (exit-1 precedes touch). Under
    D35 there is ONE FORM and two rendered substitutions; D27's law guards
    both renders — the fn-side twin lives in test_render.py."""
    _init, script = R.fetch_script_and_init(_q27_docs())
    lines = script.splitlines()

    def _has_all(tokens, line):
        return all(tok in line for tok in tokens)

    assert any(_has_all(R.EQ_GATE_TOKENS, ln) for ln in lines), (
        f"cf-143 C15: no compute line {' '.join(R.EQ_GATE_TOKENS)!r} in the q27 script — "
        "the portable equality gate is absent (the live CrashLoop shape, C11 class)"
    )
    assert any(_has_all(R.NEQ_TEST_TOKENS, ln) and ln.strip().startswith("if") for ln in lines), (
        'cf-143 C15: no [ "$actual" != "$LFS_SHA" ] test in the q27 script'
    )
    assert any(_has_all(R.MISMATCH_ECHO_TOKENS, ln) for ln in lines), (
        "cf-143 C15: the q27 MISMATCH echo must name BOTH expected= and actual= on one line"
    )
    touch_i = next((i for i, ln in enumerate(lines) if 'touch "$MARKER"' in ln), None)
    assert touch_i is not None, "cf-143 C15: touch $MARKER vanished from the q27 script"
    neq_i = next(i for i, ln in enumerate(lines) if _has_all(R.NEQ_TEST_TOKENS, ln))
    exit_i = next((i for i, ln in enumerate(lines) if "exit 1" in ln and i > neq_i), None)
    assert exit_i is not None and exit_i < touch_i, (
        "cf-143 C15: marker-touch must follow the guard's exit-1 (loud-failure shape, "
        "the C11 ordering law at the second call site)"
    )
    curl_line = next((ln for ln in lines if ln.strip().startswith("curl ")), None)
    assert curl_line and "--continue-at -" in curl_line and '-output "$PACK"' in curl_line, (
        "cf-143 C15: the q27 curl staging line lost --continue-at - / $PACK output (the "
        "resume + rc-33 tolerance is the interrupted-fetch survival mechanism)"
    )
    assert any("-ne 33" in ln for ln in lines), (
        "cf-143 C15: the rc-33 (already-retrieved) tolerance is missing — a completed "
        "download without a marker would boot-loop"
    )
    problems = []
    for ln in lines:
        if not R.HASH_APPLET_RE.search(ln):
            continue
        stripped = ln.strip()
        if re.search(r"--[A-Za-z-]+", stripped):
            problems.append(("GNU long option dies in BusyBox (exit 1 → no marker)", stripped))
        for bad_form in R.REJECTED_GATE_FORMS:
            if bad_form in stripped:
                problems.append((f"rejected D27 shape {bad_form!r}", stripped))
    assert not problems, (
        "cf-143 C15: q27 checksum-gate grammar vs the pinned BusyBox image family —\n  "
        + "\n  ".join(f"{why}: {line}" for why, line in problems[:6])
    )


@helm_skip
def test_c15_q27_init_image_stays_busybox_family():
    """Under D35 the lane block authors neither command nor image — the init
    IMAGE is chart-baked (the pinned curlimages/curl — BusyBox family, §D3b
    premise) and rides the container while the FORM rides the configMap.
    This leg guards that no later edit swaps the family per lane: a q27 swap
    silently un-rules the grammar law (the C11 identity-gate lesson, re-armed
    at the second render)."""
    init = R.fetch_init(R.deployment(_q27_docs()))
    repo = str(init.get("image", "")).rsplit(":", 1)[0]
    assert repo in R.BUSYBOX_FAMILY_REPOS, (
        f"cf-143 C15: q27 init image repo {repo!r} left the BusyBox-family set — the grammar "
        "ban must be re-ruled against the new family, not pass vacuously"
    )


# --- T4/AC8: the overlay's comment-carried law ------------------------------------


def test_c15_q27_pack_ledger_comment_verbatim():
    """C15 T4 (the fn :96-117 leg's shape, applied at the NEW home): the
    overlay's ledger comment stays verbatim-complete — repo, file,
    19,377,119,232 bytes (18.05 GiB), lfs sha in full, ungated. A truncated
    ledger is the drift class this ticket keeps paying for."""
    flat = " ".join(R.q27_region_text().split())
    assert R.Q27_PACK_REPO in flat, "cf-143 C15: the q27 ledger omits the HF repo"
    assert R.Q27_PACK_FILE in flat, "cf-143 C15: the q27 ledger omits the pack file name"
    assert re.search(r"19[,_]?377[,_]?119[,_]?232", flat), (
        f"cf-143 C15: the pack byte count {R.Q27_PACK_BYTES:,} is not in the q27 ledger"
    )
    assert re.search(r"18\.05[^\n]{0,16}GiB", flat, re.I), (
        "cf-143 C15: the ~(18.05 GiB) human figure is missing (the staging math the docs cite)"
    )
    assert R.Q27_PACK_LFS_SHA in flat, "cf-143 C15: the q27 ledger truncates the lfs sha"
    assert re.search(r"(?i)ungated", flat), "cf-143 C15: 'ungated' is not stated (§R19-S1)"


def _idle_law_missing(text):
    """The idle-hop interlock validator (C15 review-r2 re-pin of the 503
    arm — the code was a coord-side parenthetical treated as evidence; the
    reviewer's sourced truth from llama-swap proxy/peerproxy.go +
    internal/router/peer.go: network errors surface as a structured
    502 peer proxy error, and a replicas-0 Service has no endpoints, so the
    dial itself fails). 'Loud, never silent' survives; 503 does not.
    Returns the missing-token list: empty means the carrier speaks the
    canonical law — 502 + 'peer proxy error' + 'no endpoints' + loud +
    never silent — and has purged every 503 claim. Dev writes EXACTLY the
    canonical shape (D54(4): no figure or code ships without its source);
    the five interlock tokens are the agreed vocabulary, nothing else."""
    missing = []
    if re.search(r"(?<![0-9])503(?![0-9])", text):
        missing.append("still claims the 503 code (wrong and unsourced — the sourced code is 502)")
    for pat, tok in (
        (r"(?<![0-9])502(?![0-9])", "502"),
        (r"(?i)peer proxy error", "peer proxy error"),
        (r"(?i)\bno endpoints\b", "no endpoints"),
        (r"(?i)\bloud\b", "loud"),
        (r"(?i)never silent", "never silent"),
    ):
        if not re.search(pat, text):
            missing.append(f"interlock token {tok!r}")
    return missing


# Fixtures the leg proves itself with (§12.14 green-both-ways): the canonical
# sentence must PASS, a bare-503 carrier and a token-dropping carrier must
# FAIL. Dev's carriers (the service-values regions, the peers block comment,
# the catalog comment, the skill rows) are re-pointed at this shape in C15-r2.
_IDLE_CANON = ("while q27 rests at replicas 0, the peers.radiance-q27 hop "
               "fails with a 502 peer proxy error (the Service has no endpoints; "
               "llama-swap neither health-checks nor hides peers) — loud, never silent")
_IDLE_BAD_503 = ("while q27 rests at replicas 0, the peers.radiance-q27 hop "
                 "answers 503 — loud, never silent")
_IDLE_NO_HEADCOUNT = ("while q27 rests at replicas 0, the hop fails with a "
                      "502 peer proxy error (the Service has no endpoints)")


def test_c15_q27_switch_discipline_comments():
    """C15 AC8 (T3(h)): the radiance-q27 subtree's comments carry the five
    switch facts, grep-token armed and review-verified:
    1. scale ORDER — fn DOWN first, THEN q27 UP (both-up lands Pending, not
       OOM — three independent blockers, §R19/§D54-H);
    2. RESTING STATE — git renders fn 1 / q27 0;
    3. the D31/D32 law — any SYNC re-applies git over hand-scales, OutOfSync
       through the window is EXPECTED (the parked state, not a defect);
    4. the idle-hop law — RE-PINNED at review r2 from the unsourced 503 to
       the sourced 502 interlock (_idle_law_missing, self-proven on the
       fixtures below every run); DESIGNED-RED naming C15-r2 until dev
       re-words the carrier to the canonical sentence;
    5. the no-key ruling — the owner's --api-key rider is DROPPED (D54),
       WITHOUT writing the env token itself (AC4's grep scopes services/)."""
    # Teeth first (§12.14): the validator must green the canonical shape and
    # redden both lie shapes, or it is half a tripwire — this holds on EVERY
    # run, independent of where the carrier stands.
    assert _idle_law_missing(" ".join(_IDLE_CANON.split())) == [], (
        "cf-143 C15-r2: the idle-law validator fails its own canonical fixture — a broken "
        "arm cannot bless dev's carrier; the TEST lane owns this repair"
    )
    assert _idle_law_missing(" ".join(_IDLE_BAD_503.split())), (
        "cf-143 C15-r2: the idle-law validator PASSES a bare-503 carrier — half tripwire"
    )
    assert _idle_law_missing(" ".join(_IDLE_NO_HEADCOUNT.split())), (
        "cf-143 C15-r2: the idle-law validator PASSES a carrier dropping loud/never-silent "
        "— half tripwire"
    )
    flat = " ".join(R.q27_region_text().split())
    missing = []
    down = re.search(r"(?i)\bfn\b[^\n]{0,90}(down|scaled?[^\n]{0,25}\b0\b|replicas[=: ]{1,2}0)", flat)
    up = re.search(r"(?i)q27[^\n]{0,90}(up|scaled?[^\n]{0,25}\b1\b|replicas[=: ]{1,2}1)", flat)
    if not (down and up and re.search(r"(?i)(first|before|then|order)", flat)):
        missing.append("scale order (fn DOWN first, then q27 UP)")
    if not re.search(r"(?i)pending", flat):
        missing.append("the both-up lands Pending reason (§R19/§D54-H)")
    if not re.search(r"(?i)resting|git renders", flat):
        missing.append("the resting-state marker")
    if not re.search(r"(?i)fn\s*1\s*/\s*q27\s*0|fn\s*1[^\n]{0,40}q27\s*0|q27\s*0[^\n]{0,40}fn\s*1", flat):
        missing.append("the resting pair (fn 1 / q27 0)")
    if not re.search(r"(?i)D31", flat) or not re.search(r"(?i)D32", flat):
        missing.append("the D31/D32 citation")
    if not re.search(r"(?i)sync[^\n]{0,100}(re-?applies?|revert|over[rs])", flat):
        missing.append("any-sync-reapplies-git law")
    if not re.search(r"(?i)outofsync[^\n]{0,100}(expected|by design|parked|is the parked|not a defect)", flat):
        missing.append("OutOfSync-through-the-window is EXPECTED")
    missing += [f"idle-hop law: {m}" for m in _idle_law_missing(flat)]
    if not re.search(r"(?i)api-?key", flat) or not re.search(r"(?i)(dropped|keyless)", flat):
        missing.append("the no-key ruling (rider DROPPED, D54)")
    assert not missing, (
        "cf-143 C15 / AC8: the radiance-q27 subtree comments lack: " + "; ".join(missing) +
        " — an idle-hop-law item names C15-r2: dev re-points the carrier to the canonical "
        "502 sentence (peer proxy error / no endpoints / loud / never silent, no 503)"
    )


def test_c15_q27_headroom_arithmetic_commented():
    """D54(1) leg c, now CONSUMING the Q27_HEADROOM_GIB constant (C15-r2
    gap close: a constant next to a spec claim with no reader is how the
    spec starts lying about coverage). The overlay's own comment must carry
    the arithmetic that makes co-scheduling arithmetically dead — the node
    figure 125.08 and the resulting 9.80 GiB free at fn's 110 — so the
    replicas-0 resting state keeps its WHY where the next reader looks, not
    only in DECISIONS."""
    flat = " ".join(R.q27_region_text().split())
    assert R.Q27_HEADROOM_GIB in flat, (
        f"cf-143 C15: the radiance-q27 subtree comment does not state the {R.Q27_HEADROOM_GIB} GiB "
        "node-free headroom at fn's 110 (§D54-H: 125.08 − 110 − 4.125 − 1.158) — the resting "
        "replicas 0 must carry its arithmetic"
    )
    assert "125.08" in flat, (
        "cf-143 C15: the 125.08 GiB allocatable term of the co-scheduling death is missing "
        "from the q27 subtree comment — a bare 9.80 without its inputs is vocabulary, not law"
    )


def test_c15_q27_subtree_model_path_matches_the_composed_model():
    """C15-r2 enforcement parity (the review's open question), re-anchored by
    owner ruling D43 (2026-11-22): the law stayed three-place, the places
    moved. Era: modelPath here / the ARGS --model / the init PACK. D43:
    subtree modelPath == rendered env RADIANCE_MODEL_PATH == the --model the
    compose wrapper emits at boot — and the env value must equal the profile
    literal. The line still renders nothing by itself; what changed is that
    the served path is no longer a literal in the pod spec, so the silent
    one-sided retarget this leg exists to catch now breaks the env/compose
    equality instead of an args needle. Designed-red until dev round 3 lands
    the wrapper + lane env (naming it, not skipping)."""
    block = R.q27_service_block()
    assert isinstance(block, dict), (
        "cf-143 C15: no radiance-q27 subtree (dev D2) — designed-red naming C15"
    )
    sub = (block.get("app-template") or {})
    assert sub.get("modelPath") == R.Q27_PROFILE["--model"], (
        f"cf-143 C15-r2: the q27 subtree re-pins app-template.modelPath {sub.get('modelPath')!r}, "
        f"want {R.Q27_PROFILE['--model']!r} — the value the profile carries. The line renders nothing "
        "but is part of the three-place pack truth (modelPath / env / composed --model): a retarget "
        "moves all three together (the fn dual-edit law's second-release twin)"
    )
    comp = R.lane_composition(R.Q27_APP_NAME)
    env_model = comp["env"].get(R.ENV_MODEL_PATH)
    assert env_model == R.Q27_PROFILE["--model"], (
        f"C15/D43: q27 rendered env {R.ENV_MODEL_PATH}={env_model!r}, want the profile pack path"
    )
    argv = comp["facts"]["argv"]
    assert argv and R.flag_pairs(argv)["--model"] == sub.get("modelPath"), (
        "C15/D43: the composed --model broke the three-place anchor "
        f"(ledger {sub.get('modelPath')!r} / env {env_model!r} / composed "
        f"{R.flag_pairs(argv)['--model'] if argv else None!r})"
    )


def test_c15_503_swept_from_the_idle_law_carriers():
    """The class arm for the r2 re-pin (§12.14's law made grep-style, the
    AC4 idiom): the unsourced 503 may not survive in ANY prose carrier of
    the idle-hop law — services/, .opencode/, .rulesync/ (word-boundary, so
    ports like 5030/gnetId 15038 are naturally excluded). DESIGNED-RED
    naming C15-r2: dev replaces every carrier with the canonical 502
    sentence (the reviewer sourced llama-swap's ErrorHandler → 502 Bad
    Gateway 'peer proxy error'; replicas 0 means no endpoints, and
    llama-swap neither health-checks nor hides peers — loud, never silent,
    but at the RIGHT code)."""
    out = subprocess.run(
        ["git", "grep", "-nw", "503", "--", "services", ".opencode", ".rulesync"],
        capture_output=True, text=True, cwd=R.REPO_ROOT, timeout=120,
    )
    hits = [ln for ln in out.stdout.splitlines() if ln.strip()]
    assert out.returncode == 1 and not hits, (
        "cf-143 C15-r2: the unsourced 503 idle-code claim survives in law carriers —\n  "
        + "\n  ".join(hits[:8])
        + "\nreplace each with the canonical sentence (502 peer proxy error / no endpoints / "
        "loud / never silent); the token ban is D54(4)-class: a status code is a number and "
        "ships only with its source"
    )


def test_c15_keyless_grep_stays_clean():
    """AC4: git grep -l "RADIANCE_API"+"_KEY" over charts services
    custom-values tests .github prints NOTHING. Green TODAY (zero hits
    repo-wide, §D54-D) and the ban that must STAY green: a dev comment
    quoting the owner's rider verbatim reddens HERE. The fn ABSENT_FLAGS
    legs (test_serve_args) stay green untouched — this leg inherits the ban
    onto the new subtree and this suite."""
    out = subprocess.run(
        ["git", "grep", "-l", R.keyless_env_token(), "--",
         "charts", "services", "custom-values", "tests", ".github"],
        capture_output=True, text=True, cwd=R.REPO_ROOT, timeout=120,
    )
    assert out.returncode == 1 and not out.stdout.strip(), (
        f"cf-143 C15/AC4: the keyless env name appears in {out.stdout.split()!r} — D54(2) "
        "rules it out; name the dropped rider WITHOUT writing the token (the ban scopes tests/ too)"
    )


# --- T6: the CI leg ---------------------------------------------------------------


def test_c15_ci_workflow_gains_the_q27_extraction_step():
    """C15 T6 / AC9: radiance-render-tests.yaml carries the hardened
    d.get('radiance-q27') or {} extraction + a q27 render leg (the workflow
    file's own line is what CI executes; the path-set pin at
    test_contract.py:113-120 needs NO re-pin — dev D7 adds STEPS, not trigger
    paths). Designed-red until D7 lands."""
    text = R.WORKFLOW.read_text()
    assert "d.get('radiance-q27') or {}" in text, (
        "cf-143 C15: the CI workflow lacks the hardened q27 extraction step — the leg must "
        "work BEFORE (yielding {}) and AFTER the subtree lands (gotcha 14, the C01 lesson)"
    )
    assert R.Q27_RELEASE in text, (
        f"cf-143 C15: no {R.Q27_RELEASE} render leg in the workflow — the q27 subtree is not "
        "covered by CI until D7 adds it"
    )


def test_c15_q27_extraction_expression_works_pre_land():
    """The executable half (offline, no helm): running the workflow's
    extraction expression against the live service values yields a DICT in
    BOTH wave states — {} pre-C15, the subtree after (the AC6
    generation-witness law extended to the second release)."""
    doc = yaml.safe_load(R.SERVICE_VALUES.read_text())
    extracted = doc.get("radiance-q27") or {}
    assert isinstance(extracted, dict), (
        f"cf-143 C15: the q27 extraction yields {type(extracted).__name__}, want a dict"
    )
