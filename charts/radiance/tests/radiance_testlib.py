# Shared helpers for the charts/radiance render-contract suite
# (2026-11-cf-143-feat-radiance-replaces-strata, C02).
#
# radiance here is the ENGINE: docker.io/stilldeadcode/radiance v1.17.0 — the
# standalone C++/HIP engine (RESEARCH RQ0), NOT the magiccodingman/vllm-radiance
# fork behind charts/vllm, and unrelated to Strata (Niko1221/Strata). Naming
# law per DECISIONS.
#
# Contract surface: the service-level render uses the documented
# extract-and-render pattern (the `radiance:` subtree of
# services/gpu-ai/prod/values.yaml dumped and overlaid with -f) — and per
# AC6 the CI extraction leg is `d.get('radiance') or {}`: the chart-default
# render (service=False) is always available; service-level legs are gated
# on the block's existence and name C04 when it is missing (cf-131
# generation-witness law, vllm_testlib header: the next wave's contract
# never runs early and never needs a hand edit between chunks).
#
# helm_ready is the vllm law: binary absence is the ONLY skip (loudly, with
# the PATH-export reason); a missing chart is implementation state — the
# render legs RED naming C02, never a silent skip (repo mass-skip trap,
# EXPLORE §4; the app-template tgz is asserted by test_contract).

from __future__ import annotations

import functools
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import yaml

CHART_DIR = Path(__file__).resolve().parent.parent      # charts/radiance
REPO_ROOT = CHART_DIR.parent.parent
SERVICE_VALUES = REPO_ROOT / "services" / "gpu-ai" / "prod" / "values.yaml"
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "radiance-render-tests.yaml"
AMD_GPU_VALUES = REPO_ROOT / "charts" / "amd-gpu" / "values.yaml"
RAD_PEERS_EVIDENCE = REPO_ROOT / "charts" / "llama-swap" / "tests" / "evidence" / "radiance-peers-expected.yaml"

# --- the served id (C02 single authority; C04/C05 consume it) -------------------
SERVED_ID = "qwen3.8-flash-next-radiance"

# --- the FULL serving profile (Q10 ruling / DECISIONS D17; the plan "Key pinned
# facts" line is the authority, numbers from RESEARCH "Serving envelope") --------
MODEL_PATH = "/models/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad"
PACK_REPO = "StillDeadcode/qwen3.8-next-flash-fp8-iq4r-moe"
PACK_BYTES = 121_969_901_568
PACK_LFS_SHA = "0af5e96244e80c21ac8edca1719dae49b8a201b94a2f3994c3e24026ceaa4d20"
SCALARS = {
    # C12 AC1 (amendment 2026-11-13, D29) — SHIPPED VALUE 110, OWNER RULING.
    # The 64 shipped at C02/D17 was a PLANNING miss: the live boot printed its
    # own budget — "pinned by this process 71.04 GiB" (report 2) against a 64.00
    # cgroup => OOM. The tier words (pool 42.70, kv-resident host mirror ~32,
    # arena 2.00, placement 1.18, staging) OVERLAP: the printed parts sum to
    # 77.88 against the printed whole 71.04 — 71.04 is a BOUNDED residual, the
    # figure to price against, never a decomposition to re-add (D30(2)); the
    # disk n-gram tier is O_DIRECT — its table never enters page cache, so the
    # page-cache-starvation claim D30(3) records ("would STARVE the host page
    # cache") stands REFUTED. D28 planned the ladder ceiling 96; asked
    # "Which value should charts/radiance ship for gpu-ai?", the owner answered
    # verbatim "110 GiB (your figure)" — D29 records the ruling (D28's reasoning
    # stands as history, append-only). 110 is NOT a radiance plan figure in the
    # repo (§D6.1): it is STRATA's own limit on this node (charts/llama-swap/
    # values.yaml:1319-1325, the owner's proven "container must die BEFORE the
    # node" envelope) — the ruling EXTENDS that node law to radiance. Slack: 110 -
    # 71.04 = 38.96 >= 4 with margin (vs 96's 24.96); the RAM-ngram tier is
    # DEAD at BOTH (71.04+47.68 = 118.72 > 110, §D6/AC2-iv) — 110 is slack,
    # not a tier enabler. Schedulability (§D6.2 exact terms): strata DOWN
    # 110 + router 4.125 + system floor 1.158 = 115.28 <= 125.08, 9.80 GiB
    # free; strata UP 110 + 64 + 6.3 = 180.3 > 125.08 => designed Pending
    # (step-3 handshake unchanged, inverted restore-back at 110). The live 94
    # is a LIMIT-ONLY hand-edit (req 64) => the pod is Burstable RIGHT NOW;
    # the 110 PAIR restores Guaranteed at sync (AC6) — repo is the source of
    # truth, 94 exists nowhere in git. Class law: sum the tiers the engine
    # PRINTS before shipping a memory scalar.
    #
    # cf-144 C01 (TP2 flip; P11 OWNER ruling 2026-11-21 "Hold 110, re-pin
    # after the print"): guaranteedMemoryGi STAYS 110 through this wave — the
    # draft-shipped 48 is REJECTED (P11 supersedes P03), so no 48 memory value
    # appears anywhere in this test set; the DOWN re-pin to the printed class
    # (~30-35 GiB; the llmkube req 40 / lim 48 witness stays the recorded
    # bracket) is a POST-TP2-BOOT OWNER-RECEIPT leg, never a shipped value —
    # the first-boot PRINT is the budget authority (D30(2) applied to the TP2
    # topology). hostPoolMib moves 43000→12288: the TP2 pool is PER RANK
    # (2×12288 MiB ≈ 24 GiB pinned, doc §7/P04).
    "guaranteedMemoryGi": 110,
    "hostPoolMib": 12288,
    "maxModelLen": 200000,
    "maxNumSeqs": 8,
    "cpuCores": 8,
}
# KV_RESIDENT_TOKENS RETIRED at cf-144 C01 (P04): the TP2 recipe drops
# --kv-resident outright — tier back, mirror gone (mutual exclusion, doc §7).
# The 32768 lever was the single-card shape (D3/D17 history above); no fn leg
# may demand it again. Its polarity replacement lives in ABSENT_FLAGS.

# The serveArgs contract — ORDER-INSENSITIVE set equality (AC3): every pair
# once; the model path splices the values anchor. `--host ::` (IPv6-any),
# keyless (no --api-key), ngram on disk, spec 3.
# cf-144 C01 re-pin (P04/OQ-C "Confirm as specced"): the doc §7 TP2 recipe —
# `--tp 2`, `--tp-wire wht6` (a PURE ADD, present nowhere in the TP1 set;
# verified verbatim against flashnext.yaml/HF card per RQ4), per-rank pool
# 12288, chunk 4096→2048, `--prefix-cache-mib 4096` IN (the tier is
# affordable again), `--kv-resident` OUT (tier/mirror mutual exclusion);
# retained at TP2: checkpoint-interval 4096, ngram disk, served-name, host::,
# port 8000, the model anchor. maxModelLen/maxNumSeqs/headroom/spec unchanged
# (P09: the profile move is tp-pinned, not ctx-pinned).
FULL_PROFILE = {
    "--model": MODEL_PATH,
    "--port": "8000",
    "--host": "::",
    "--tp": "2",
    "--tp-wire": "wht6",
    "--max-model-len": "200000",
    "--max-num-seqs": "8",
    "--placement": "expert_tiered",
    "--host-pool-mib": "12288",
    "--gpu-headroom-mib": "96",
    "--kv-cache-dtype": "fp8",
    "--prefix-cache-mib": "4096",
    "--num-speculative-tokens": "3",
    "--max-num-batched-tokens": "2048",
    "--checkpoint-interval": "4096",
    "--ngram-placement": "disk",
    "--served-model-name": SERVED_ID,
}

# Absence law (AC3 — each is a named bar, RESEARCH 'Guide corrections' + D8;
# cf-144 C01 polarity flip per P04): the engine has NO `serve` verb;
# --expert-vs-cache-ratio is a stale guide flag (never ship); --kv-resident
# NOW joins the fn absence list — the TP2 recipe ships the prefix-cache tier
# and the mirror is mutually exclusive with it (tier back, mirror gone,
# doc §7) — while --prefix-cache-mib LEAVES it (it ships); no --api-key
# (keyless); NO ROCR/HIP env (the named pool selects the cards — plugin
# injects devices, sets no env; TP2's two-card claim changes nothing here).
ABSENT_FLAGS = (
    "--expert-vs-cache-ratio",
    "--kv-resident",
    "--api-key",
    "--api-key-env",
)
ABSENT_ENV = ("ROCR_VISIBLE_DEVICES", "HIP_VISIBLE_DEVICES")

# Recipe constants dev may ledger as scalars instead of list literals (C01:
# "dev picks the carrier shape"). The splice guard in test_serve_args reddens
# any HALF-MOVE: a scalarized key here must equal the rendered arg. A scalar
# under any other name is an unledgered edit — the set-equality leg alone
# decides it.
TP2_LEDGER_KEYS = {
    "tp": "--tp",
    "prefixCacheMib": "--prefix-cache-mib",
    "maxNumBatchedTokens": "--max-num-batched-tokens",
    "checkpointInterval": "--checkpoint-interval",
}

# The fn GPU claim COUNT (cf-144 C01, shape A ruling OQ-A/P02): one pod
# claiming BOTH R9700s — the extended-resource equal-integer pair renders
# "2" in requests AND limits. ONE edit site (the pool NAME resolves through
# the amd_gpu_testlib canonical block above; the count is this wave's move).
FN_GPU_CLAIM_COUNT = "2"

# --- pod shape (Q7 verbatim + Q9 named pools; AC2) --------------------------------
# The GPU resource-name constants resolve from the CANONICAL block in
# charts/amd-gpu/tests/amd_gpu_testlib.py (the D24 lane ruling — the R9700
# pool was renamed via the patched-table mount; a future lane change edits
# that ONE block, never needles here). The sys.path join is the §12.4/12.5
# sanctioned cross-chart read: this suite's cross-chart identity leg IS the
# join point, so the names must not be forked.
import sys as _sys

_amd_tests = REPO_ROOT / "charts" / "amd-gpu" / "tests"
assert _amd_tests.is_dir(), (
    "radiance suite: charts/amd-gpu/tests (the GPU-name canonical block home) missing — "
    "the constants have no other source by design (one edit site per the C08 ruling)"
)
if str(_amd_tests) not in _sys.path:
    _sys.path.insert(0, str(_amd_tests))
import amd_gpu_testlib as AMDNAMES  # noqa: E402

GPU_CLAIM = AMDNAMES.R9700_CLAIM                  # pending-lane resolved by D24: the renamed pool
GPU_CLAIM_BARE = AMDNAMES.BARE_GPU_CLAIM         # GONE from the gpu-ai node post-flip — stray = Pending-forever
APU_CLAIM = AMDNAMES.APU_CLAIM                  # llama-swap's pool (must NOT be radiance's)
SUPPLEMENTAL_GROUPS = [486]                 # kfd, live-verified (RESEARCH RQ3); render/video join per C06 receipt
GRACE_SECONDS = 180                         # engine drains ~60-120 s on SIGTERM — NOT strata's 420 child-choreography number
INIT_NAME = "radiance-fetch"
SERVE_NAME = "radiance"
# --- C11 applet-grammar law constants (ONE site; DECISIONS D27, EXPLORE §D3b) ----
# A container image's coreutils-applet FAMILY is part of the image contract:
# BusyBox hash applets (md5_sha1_sum.c getopt32 "^" "scwbt" — argv elided from
# the §D3b call quote; short options only,
# byte-identical 1_36_1<->master so v1.37.0 is bracketed) reject GNU LONG
# options at parse (exit 1, "unrecognized option"), while GNU coreutils has no
# BusyBox `-s` (quiet) — the portable shape is neither flag, it is shell
# EQUALITY on the two-space compute output. The live authority for the init
# image's family is the container's own banner ("BusyBox v1.37.0", §D3b) —
# vocabulary legs (tokens present) NEVER proved grammar; these constants let
# the suite gate on IMAGE IDENTITY + OPTION GRAMMAR (the §12.10 class law).
BUSYBOX_FAMILY_REPOS = (
    "docker.io/curlimages/curl",  # the pinned init image (values 313-317); live
    #                                imageID seed sha256:3fb7e13e… (§D3b.1) — digest
    #                                ledgered in values by AC4.3's upgrade
    "curlimages/curl", "docker.io/alpine", "alpine", "busybox",
)
INIT_IMAGE_ID_SEED = "sha256:3fb7e13e"           # live forensic anchor (§D3b.1/AC4.3)
import re as _c11_re
HASH_APPLET_RE = _c11_re.compile(r"\b(?:md5|sha1|sha224|sha256|sha384|sha512)sum\b")
# AC1's portable gate — TOKEN needles anchored on the §D3b.4 block dev lands
# verbatim (plain substrings survive every quoting layer; a shape change must
# touch this ONE site, never scattered regexes). The two-space compute form +
# cut is what BOTH applet families print, so equality is portable grammar.
EQ_GATE_TOKENS = ("actual=$(sha256sum", "$PACK", "| cut", "-f1)")
NEQ_TEST_TOKENS = (f'$actual" != "$LFS_SHA',)  # inside [ ... ]
MISMATCH_ECHO_TOKENS = ("MISMATCH", "expected=", "actual=")
# D27's rejected shapes — each dies on one family or the other (or both):
REJECTED_GATE_FORMS = ("--check", "--status", "-cs", "-c -s")

# D15: Guaranteed is a POD-class property — the init must carry the equal pair
# too or the pod silently downgrades to Burstable.
# C12 AC1 raises the cpu knob 200m -> 1000m on §D4's measured law: the
# first-ever hash is CPU-QUOTA-bound, not disk-bound (busybox sha256sum is
# single-threaded, no SHA-NI path; live 0.2000 core exactly + io PSI 0).
# Wall = 121,969,901,568 B / (cores x 150-350 MB/s): 200m => 30-70 min,
# 1000m => ~5.8-13.6 min (30-70 ÷ 5, D30(6): the drafted 8-23 was §D4.4's
# UN-QUOTED counterfactual — an unthrottled core on a FULL-FEED disk — re-used
# as if cap-bound, ~1.5x wrong; C13 AC1 same-wave correction). MORE THAN 1
# CORE IS POINTLESS (single-threaded applet).
# Every pod loss before completion throws the whole elapsed away (the hash
# restarts at byte 0; only the download resumes). SEPARABLE KNOB: reverting
# this pair is a one-line no-op to the memory fix (owner's call if the
# 30-70 min status quo is preferred). Memory stays 2Gi/2Gi (measured
# workingSet 4.1 MB — generous by design; do not shrink).
INIT_PAIR = {"cpu": "1000m", "memory": "2Gi"}

# --- image ledger (D2: tag + digest-in-comment, NO digest field) ------------------
IMAGE_REPO = "docker.io/stilldeadcode/radiance"
IMAGE_TAG = "1.17.0"
AMD64_IMAGE_MANIFEST = "sha256:6fb0e99bfb862e17cc15cb7b2f116c7dbdc831df59f82456a0691122e6cf5330"
INDEX_DIGEST = "sha256:c2acbaa373c89272ec47a22befa1cf04d2ddf1de51c2baf534f5273e517f7100"

# The peer URL the NOTES print + C04's evidence consume (appset name
# derivation: serviceName gpu-ai + appName radiance, no /v1 — the request
# path appends verbatim).
PEER_URL = "http://gpu-ai-radiance.default.svc.cluster.local:8000"

# --- cf-143 C15 q27 lane (D54 owner rulings; §R19; §D54 file-map) ------------
# The q27 truth lives in the SERVICE OVERLAY (the top-level radiance-q27:
# subtree of services/gpu-ai/prod/values.yaml), never in the chart: the
# topology is one chart dir, two releases (D56 — roster `chart: radiance`
# override), and charts/radiance/values.yaml stays a ZERO-DIFF file by
# design so the fn suite's 46 green legs cannot move (DECISIONS D56(1)).
# Every value here is the owner-ruled constant (C15/D54) — dev conforms the
# subtree to it, never the reverse.
Q27_APP_NAME = "radiance-q27"
Q27_RELEASE = "gpu-ai-radiance-q27"          # Application name = serviceName+appName;
#                                             # renders fn's own Service+Deployment name
Q27_SERVED_ID = "qwen3.8-27b-radiance"       # honest-id law (D7 pattern): the served
#                                             # name is the model, not fn's trio
Q27_MODEL_PATH = "/models/radiance/qwen3.8-27b-mxfp4.rad"   # the chart's model dir idiom;
#                                             # the anchor trap runs in REVERSE here: the
#                                             # overlay args carry the path LITERALLY
Q27_PACK_REPO = "StillDeadcode/qwen3.8-27b-mxfp4"
Q27_PACK_FILE = "qwen3.8-27b-mxfp4.rad"
Q27_PACK_BYTES = 19_377_119_232              # ~18.05 GiB (§R19-S1/S5)
Q27_PACK_LFS_SHA = "a4908940c568f5f9dd24e88f46aefe9ac2ae07dfec023a2eaa1d14dcaa3df4f8"
Q27_PACK_URL = f"https://huggingface.co/{Q27_PACK_REPO}/resolve/main/{Q27_PACK_FILE}"

# The D54-ratified serving profile (owner recipe MINUS the --api-key rider —
# D54(2) keyless; host normalized to the lane's `::` idiom — plan OQ-15
# resolved; served-name added per the honest-id law). Set equality is
# EXACT and order-insensitive (AC2, the fn AC3 idiom): an extra flag is as
# red as a missing one.
Q27_PROFILE = {
    "--model": Q27_MODEL_PATH,
    "--tp": "1",
    "--max-num-seqs": "8",
    "--max-model-len": "200000",
    "--kv-cache-dtype": "fp8",
    "--prefix-cache-mib": "4096",             # Wilde's operational patch, NOT the card's
    #                                          # (§R19-Q2); below one 200K fp8 conversation,
    #                                          # so the boot warning is EXPECTED
    "--host": "::",
    "--port": "8000",
    "--served-model-name": Q27_SERVED_ID,
}

# Each absence is a named bar with its reason (AC2; §R19-Q1/Q5, D54/D8):
# --api-key/--api-key-env — keyless ruling, the four D8 bans inherited;
# --kv-resident — the arch REFUSES it ("dense attention reads the whole
# history every step", §R19-Q1(iii)); --ngram-placement + --placement +
# --host-pool-mib — q27's family has no n-gram/PLE layer and no experts
# (§R19-Q7, D56(7)); --gpu-headroom-mib — co-residency etiquette only,
# moot in a pod-swap; --num-speculative-tokens — the DFlash2 drafter is
# in-pack, "the flag simply doesn't own the drafter" (§R19-Q5).
Q27_ABSENT_FLAGS = (
    "--api-key",
    "--api-key-env",
    "--kv-resident",
    "--ngram-placement",
    "--placement",
    "--host-pool-mib",
    "--gpu-headroom-mib",
    "--num-speculative-tokens",
)

Q27_MEMORY = "24Gi"     # request==limit Guaranteed pair (D54(3)); cpu "8" was
#                        # chart-INHERITED while the chart shipped a resources
#                        # map (map deep-merge adds/updates, never removes —
#                        # D26). C03 moved the chart to a mechanism-only shell:
#                        # the subtree now AUTHORS cpu beside the pair, so the
#                        # exactness leg must count it.
Q27_CPU = "8"           # the subtree's authored cpu pair value (post-C03)
Q27_REPLICAS = 0        # the shipped resting state (D54(1) pod-swap); the
#                        # 125.08-110-4.125-1.158 = 9.80 GiB node-free headroom
#                        # makes co-scheduling arithmetically dead — both-up
#                        # lands Pending, not OOM (§R19/§D54-H).
Q27_HEADROOM_GIB = "9.80"
Q27_CATALOG_PRIOS = {   # OQ-16 approved: each STRICTLY below fn's 9/5/1,
    "urgent": 8,        # higher-wins polarity NOT inverted, fn rows
    "default": 4,       # byte-unchanged. priority-0 SEMANTICS UNVERIFIED —
    "low": 0,           # C16's smoke read confirms; the arms pin the
}                       # AUTHORED value, not a claimed behaviour.
Q27_CTX = 200000        # per-session ceiling (--max-model-len); the
#                        # ~335-409K aggregate is a CONCURRENCY caveat, not a
#                        # context number (§R19-Q1).
Q27_CAPS_INPUT = ["text", "image"]           # in-pack vision tower (Q8 pattern);
#                                             # the C16 smoke retires the claim on failure
Q27_PEER_FLOOR = 4      # q27's default class; fn's 5 floor is NOT reused
#                        # (D54 records "fn's ranks are NOT stolen")
Q27_PEER_URL = f"http://{Q27_RELEASE}.default.svc.cluster.local:8000"   # NO /v1
Q27_PEERS_EVIDENCE = REPO_ROOT / "charts" / "llama-swap" / "tests" / "evidence" / "radiance-q27-peers-expected.yaml"
Q27_ROSTER = {"namespace": "default", "ServerSideApply": "false", "chart": "radiance"}

# AC4's keyless ban scopes `tests` too, so this suite may not embed the env
# name contiguously — the token is ASSEMBLED at read time. A source that
# spells it out would green the ban by absence of evidence; assembling keeps
# the grep leg honest about its own files.
_KEYLESS_ENV_TOKEN = "RADIANCE_API" + "_KEY"


def keyless_env_token() -> str:
    return _KEYLESS_ENV_TOKEN


def q27_service_block() -> dict | None:
    """The top-level radiance-q27: block of the gpu-ai service values, or
    None while C15-dev's D2 has not landed (designed-red naming C15, never a
    skip — the subtree and these legs ship in ONE commit-wave)."""
    if not SERVICE_VALUES.is_file():
        return None
    return yaml.safe_load(SERVICE_VALUES.read_text()).get(Q27_APP_NAME)


def q27_region_text() -> str:
    """Raw text of the radiance-q27: subtree INCLUDING its law comments —
    YAML parses no comments, and AC8's switch discipline is comment-carried,
    so the comment arms read this window (the leading comment block plus the
    subtree lines up to the next top-level key)."""
    assert SERVICE_VALUES.is_file(), (
        "cf-143 C15: services/gpu-ai/prod/values.yaml missing — the q27 overlay has no host"
    )
    lines = SERVICE_VALUES.read_text().splitlines()
    start = next((i for i, ln in enumerate(lines) if re.match(r"^" + Q27_APP_NAME + r":", ln)), None)
    assert start is not None, (
        "cf-143 C15: no top-level radiance-q27: subtree in the gpu-ai service values — dev D2 "
        "has not landed (comment legs are designed-red until the overlay block exists; C15 owns it)"
    )
    top = start
    while top > 0:
        prev = lines[top - 1]
        if prev.strip() == "" or prev.lstrip().startswith("#"):
            top -= 1
            continue
        break
    end = next((i for i in range(start + 1, len(lines)) if re.match(r"^[^ \t#]", lines[i])), len(lines))
    return "\n".join(lines[top:end])


def radiance_q27_peers_evidence() -> dict:
    """Load + self-validate the q27 peer evidence (the fn loader's model laws:
    a non-empty duplicate-free models_states chain whose last state equals
    models_allowed). D13 per-key law: the fn file stays byte-untouched; this
    sibling is the q27 block's single source, and dev conforms values to it."""
    assert Q27_PEERS_EVIDENCE.is_file(), (
        f"cf-143 C15: {Q27_PEERS_EVIDENCE} missing — the q27 peer evidence is the "
        "test-session single source (D13 per-key extension)"
    )
    data = yaml.safe_load(Q27_PEERS_EVIDENCE.read_text())
    assert isinstance(data, dict) and isinstance(data.get(Q27_APP_NAME), dict), \
        "radiance-q27-peers-expected.yaml must carry a radiance-q27: mapping"
    ev = data[Q27_APP_NAME]
    states = ev.get("models_states")
    assert isinstance(states, list) and states, \
        "q27 evidence needs models_states — every wave's exact peer list is pinned"
    final = ev.get("models_allowed")
    assert isinstance(final, list) and final and states[-1] == final, \
        "q27 evidence: last models_states must equal models_allowed"
    for i, ids in enumerate(states):
        assert isinstance(ids, list) and ids and len(set(ids)) == len(ids), \
            f"models_states[{i}] must be a non-empty duplicate-free list"
    return ev


def expected_radiance_q27_peer(ev: dict, models: list) -> dict:
    """The sanctioned rendered peers.radiance-q27 block for one models list —
    proxy/timeouts/filters verbatim from the evidence, models one of the
    states (the wave law). Derives nothing it does not read."""
    assert models in ev["models_states"], (
        f"peers.radiance-q27 models {models} is not one of the sanctioned waves "
        f"{ev['models_states']} — wave changes route through the test session"
    )
    return {
        "proxy": ev["proxy"],
        "models": models,
        "timeouts": ev["timeouts"],
        "filters": ev["filters"],
    }


@functools.lru_cache(maxsize=None)
def _render_q27_cache() -> tuple:
    """Render the SAME chart dir with release name gpu-ai-radiance-q27 and
    the extracted radiance-q27 subtree (the appset-merge shape: per-app
    values = merge $extraValues (index $.Values $appName)). Missing subtree
    is a RED naming C15, not a skip: the subtree is C15-dev's own landing."""
    block = q27_service_block()
    assert isinstance(block, dict), (
        "cf-143 C15: services/gpu-ai/prod/values.yaml carries no top-level radiance-q27: "
        "subtree — dev D2 has not landed; the q27 render legs are designed-red until it does "
        "(no q27 subtree exists against today's tree — §12 red-first law)"
    )
    with tempfile.TemporaryDirectory(prefix="radiance-q27-test-") as tmp:
        vals = Path(tmp) / "vals.yaml"
        with vals.open("w") as fh:
            yaml.safe_dump(block, fh)
        out = subprocess.run(
            [
                "helm", "template", Q27_RELEASE, str(CHART_DIR),
                "-f", str(vals),
                "--set", "domain=spencerslab.com",
                "--set", "clusterName=gpu-ai",
            ],
            capture_output=True, text=True, timeout=300,
        )
        if out.returncode != 0:
            raise AssertionError(
                f"C15: helm template failed for the q27 release ({Q27_RELEASE}):\n{out.stderr}"
            )
        docs = tuple(d for d in yaml.safe_load_all(out.stdout) if d)
        return docs, out.stdout


def render_q27():
    """(docs, raw stdout) for the gpu-ai-radiance-q27 release render."""
    ok, reason = helm_ready()
    assert ok, reason
    return _render_q27_cache()


def helm_ready() -> tuple[bool, str]:
    if shutil.which("helm") is None:
        return False, ("helm binary not on PATH (~/.local/bin/helm — export PATH; "
                       "without it the helm-guarded tests skip silently, EXPLORE §4)")
    return True, ""


def chart_values() -> dict:
    return yaml.safe_load(chart_values_text())


def chart_values_text() -> str:
    path = CHART_DIR / "values.yaml"
    assert path.is_file(), (
        "C02: charts/radiance/values.yaml missing — the radiance engine chart is not "
        "implemented yet (missing chart reads as a named red, never a bare trace)"
    )
    return path.read_text()


def service_block() -> dict | None:
    """The top-level radiance: block of the gpu-ai service values, or None
    while C04 has not landed (d.get-style, mirroring the workflow's hardened
    extraction — AC6: the CI leg works BEFORE and AFTER the block lands)."""
    if not SERVICE_VALUES.is_file():
        return None
    return yaml.safe_load(SERVICE_VALUES.read_text()).get("radiance")


def service_block_present() -> bool:
    return isinstance(service_block(), dict)


def radiance_peers_evidence() -> dict:
    assert RAD_PEERS_EVIDENCE.is_file(), (
        f"cf-143 C02/C04: {RAD_PEERS_EVIDENCE} missing — the radiance peer evidence is the "
        "test-session single source (D13)"
    )
    data = yaml.safe_load(RAD_PEERS_EVIDENCE.read_text())
    assert isinstance(data, dict) and isinstance(data.get("radiance"), dict), \
        "radiance-peers-expected.yaml must carry a radiance: mapping"
    return data["radiance"]


@functools.lru_cache(maxsize=None)
def _render_cache(release: str, service: bool, extra: str) -> tuple:
    with tempfile.TemporaryDirectory(prefix="radiance-test-") as tmp:
        cmd = [
            "helm", "template", release, str(CHART_DIR),
            "--set", "domain=spencerslab.com",
            "--set", "clusterName=gpu-ai",
        ]
        if service:
            block = service_block()
            assert block is not None, (
                "C04: services/gpu-ai/prod/values.yaml has no top-level radiance: block — "
                "the service subtree leg waits on C04 (the chart-default legs run without it)"
            )
            vals = Path(tmp) / "vals.yaml"
            with vals.open("w") as fh:
                yaml.safe_dump(block, fh)
            cmd += ["-f", str(vals)]
        if extra:
            cmd += extra.split()
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        if out.returncode != 0:
            raise AssertionError(
                f"C02: helm template failed (release={release}, service={service}):\n{out.stderr}"
            )
        docs = tuple(d for d in yaml.safe_load_all(out.stdout) if d)
        return docs, out.stdout


def render(release: str = "radiance", service: bool = False, extra_set: str = ""):
    """(docs, raw stdout); raises AssertionError on helm failure. Default is
    the CHART-DEFAULTS render (C02's own surface); service=True is the C04-
    gated overlay leg (AC6)."""
    return _render_cache(release, service, extra_set)


def deployment(docs) -> dict:
    deps = [d for d in docs if d.get("kind") == "Deployment"]
    assert deps, "C02: no Deployment rendered"
    assert len(deps) == 1, f"C02: expected one Deployment, got {[d['metadata']['name'] for d in deps]}"
    return deps[0]


def pod_spec(deploy: dict) -> dict:
    return deploy["spec"]["template"]["spec"]


def serve_container(deploy: dict) -> dict:
    for c in pod_spec(deploy).get("containers", []):
        if c.get("name") == SERVE_NAME:
            return c
    raise AssertionError(
        f"C02: no container named {SERVE_NAME!r}; got {[c.get('name') for c in pod_spec(deploy).get('containers', [])]}"
    )


def fetch_init(deploy: dict) -> dict:
    inits = pod_spec(deploy).get("initContainers") or []
    assert len(inits) == 1, f"C02: expected exactly one init container, got {[i.get('name') for i in inits]}"
    assert inits[0].get("name") == INIT_NAME, f"C02: the init container is named {inits[0].get('name')!r}, want {INIT_NAME}"
    return inits[0]


def env_map(container: dict) -> dict:
    return {e["name"]: e.get("value") for e in container.get("env", [])}


def flag_pairs(args: list) -> dict:
    """Rendered args as {flag: value-or-None} (duplicates would clobber — the
    set-equality test asserts uniqueness separately)."""
    out: dict = {}
    i = 0
    while i < len(args):
        tok = args[i]
        if not isinstance(tok, str) or not tok.startswith("--"):
            i += 1
            continue
        if "=" in tok:
            flag, val = tok.split("=", 1)
            out[flag] = val
            i += 1
        elif i + 1 < len(args) and not str(args[i + 1]).startswith("--"):
            out[tok] = args[i + 1]
            i += 2
        else:
            out[tok] = None
            i += 1
    return out


def resources(container: dict) -> dict:
    return container.get("resources") or {}


def services(docs) -> list:
    return [d for d in docs if d.get("kind") == "Service"]


def amd_gpu_ledger_names() -> dict:
    """The device->pool map from the vendored chart's expected-names ledger
    (C07's values-comment authority — RESEARCH §R6-Q1). Line-scoped: a
    comment line that names the PCI device id (7551/1586) must also name the
    pool (`gpu-...` token, with or without the amd.com/ prefix) on the same
    line — so the cross-chart identity leg reads ONE authority, no second
    copy. Returns {"7551": <pool-name-without-prefix>, "1586": ...} for the
    ledger rows found (the R9700 row additionally expected to name C0)."""
    assert AMD_GPU_VALUES.is_file(), (
        "C02 AC4: charts/amd-gpu/values.yaml missing — the vendored plugin chart (C07) must "
        "land first; it is the sole producer of the pool names this chart claims"
    )
    out: dict[str, str] = {}
    for ln in AMD_GPU_VALUES.read_text().splitlines():
        if not ln.lstrip().startswith("#"):
            continue
        m = re.search(r"(amd\.com/)?(gpu-[a-z0-9][a-z0-9.-]*)", ln)
        if not m:
            continue
        for device in ("7551", "1586"):
            if device in ln and device not in out:
                out[device] = m.group(2)
    return out


# --- 2026-11-feat-radiance-multi-instance C05: the four-lane roster -------------
# Two RESTING releases join fn + q27 (ask 4's 4x deployment). The values here are
# the ticket's SPECS, authored in the test session; dev conforms
# services/gpu-ai/prod/values.yaml to them (the D13 single-source law the evidence
# YAMLs carry). Priority classes come from
# tests/pipeline-models/TEST_SPEC.md §3 as resolved by the coordinator's follow-up
# ruling (urgent/def cross-lane unique and strictly below the live lanes, trios
# strictly decreasing per lane, no negative rung, the fn/27b-tp2 low tie ACCEPTED
# — separate engines never compete for queue slots); keys are the catalog SUFFIX
# classes: urgent > default > low under higher-wins, matching surface.sh M9-A's
# table. Do not "simplify" a row without re-running that proof.
FLASH_TP1_APP_NAME = "radiance-flash-tp1"
FLASH_TP1_RELEASE = "gpu-ai-" + FLASH_TP1_APP_NAME
FLASH_TP1_SERVED_ID = "qwen3.8-flash-next-radiance-tp1"
FLASH_TP1_MEMORY = "110Gi"          # the fn pair held: same working set, same cgroup price
FLASH_TP1_CLAIM_COUNT = "1"         # one card, quoted string (the shipped claim shape)
FLASH_TP1_PEER_FLOOR = 3            # == this lane's own default class, never fn's 5
FLASH_TP1_CATALOG_PRIOS = {"urgent": 7, "default": 3, "low": 2}
FLASH_TP1_ROSTER = {"namespace": "default", "ServerSideApply": "false", "chart": "radiance"}
FLASH_TP1_PEER_URL = f"http://{FLASH_TP1_RELEASE}.default.svc.cluster.local:8000"   # NO /v1
FLASH_TP1_PEERS_EVIDENCE = (
    REPO_ROOT / "charts" / "llama-swap" / "tests" / "evidence" / "radiance-flash-tp1-peers-expected.yaml"
)
# The transcription source, named by commit: the cf-143 TP1-era array (the file as
# it stood BEFORE e7536b2c9 flipped the fn lane to TP2). The lane is that array with
# EXACTLY one value swapped — the served-model-name — so the proof leg is a diff,
# not a re-derived flag list.
FLASH_TP1_TRANSCRIPTION = ("e7536b2c9^", "charts/radiance/values.yaml")

Q27_TP2_APP_NAME = "radiance-q27-tp2"
Q27_TP2_RELEASE = "gpu-ai-" + Q27_TP2_APP_NAME
Q27_TP2_SERVED_ID = "qwen3.8-27b-radiance-tp2"
Q27_TP2_MEMORY = "24Gi"             # q27's pair held (D28(6): the boot print adjudicates)
Q27_TP2_CLAIM_COUNT = "2"           # both cards: the TP2 shape of the same pool
Q27_TP2_PEER_FLOOR = 2              # == this lane's own default class
Q27_TP2_CATALOG_PRIOS = {"urgent": 6, "default": 2, "low": 1}
Q27_TP2_ROSTER = {"namespace": "default", "ServerSideApply": "false", "chart": "radiance"}
Q27_TP2_PEER_URL = f"http://{Q27_TP2_RELEASE}.default.svc.cluster.local:8000"        # NO /v1
Q27_TP2_PEERS_EVIDENCE = (
    REPO_ROOT / "charts" / "llama-swap" / "tests" / "evidence" / "radiance-q27-tp2-peers-expected.yaml"
)
Q27_TP2_EXTRA_FLAGS = ("--tp", "2", "--tp-wire", "wht6")   # the ONLY add over the q27 array

# The roster's four releases, in ladder order. `resting` lanes ship replicas 0 and
# are never a default route; `live` lanes are the ones the tables name today.
LANES = {
    FLASH_TP1_APP_NAME: {
        "release": FLASH_TP1_RELEASE,
        "served_id": FLASH_TP1_SERVED_ID,
        "memory": FLASH_TP1_MEMORY,
        "claim": FLASH_TP1_CLAIM_COUNT,
        "floor": FLASH_TP1_PEER_FLOOR,
        "prios": FLASH_TP1_CATALOG_PRIOS,
        "roster": FLASH_TP1_ROSTER,
        "peer_url": FLASH_TP1_PEER_URL,
        "evidence": FLASH_TP1_PEERS_EVIDENCE,
        "pack": (MODEL_PATH, PACK_REPO, PACK_BYTES, PACK_LFS_SHA),
        "resting": True,
    },
    Q27_TP2_APP_NAME: {
        "release": Q27_TP2_RELEASE,
        "served_id": Q27_TP2_SERVED_ID,
        "memory": Q27_TP2_MEMORY,
        "claim": Q27_TP2_CLAIM_COUNT,
        "floor": Q27_TP2_PEER_FLOOR,
        "prios": Q27_TP2_CATALOG_PRIOS,
        "roster": Q27_TP2_ROSTER,
        "peer_url": Q27_TP2_PEER_URL,
        "evidence": Q27_TP2_PEERS_EVIDENCE,
        "pack": (Q27_MODEL_PATH, Q27_PACK_REPO, Q27_PACK_BYTES, Q27_PACK_LFS_SHA),
        "resting": True,
    },
}
NEW_LANE_NAMES = tuple(LANES)


def lane(name: str) -> dict:
    spec = LANES.get(name)
    assert spec is not None, f"no C05 lane spec named {name!r} (known: {sorted(LANES)})"
    return spec


def lane_block(name: str) -> dict | None:
    """The top-level <lane>: block of the gpu-ai service values, or None while
    C05-dev has not landed it — a designed red naming C05, never a skip."""
    if not SERVICE_VALUES.is_file():
        return None
    return yaml.safe_load(SERVICE_VALUES.read_text()).get(name)


def lane_region_text(name: str) -> str:
    """Raw text (comments included) of one lane's top-level subtree — the
    comment-carried laws (skip paragraph, 502-idle sentence, switch discipline)
    are only visible here."""
    lines = SERVICE_VALUES.read_text().splitlines()
    start = next((i for i, ln in enumerate(lines) if re.match(r"^" + re.escape(name) + r":", ln)), None)
    assert start is not None, (
        f"C05: services/gpu-ai/prod/values.yaml carries no top-level {name}: block — dev's lane "
        "has not landed (the comment legs are designed-red naming C05 until it does)"
    )
    top = start
    while top > 0:
        prev = lines[top - 1]
        if prev.strip() == "" or prev.lstrip().startswith("#"):
            top -= 1
            continue
        break
    end = next((i for i in range(start + 1, len(lines)) if re.match(r"^[^ \t#]", lines[i])), len(lines))
    return "\n".join(lines[top:end])


@functools.lru_cache(maxsize=None)
def _render_lane_cache(name: str) -> tuple:
    block = lane_block(name)
    assert isinstance(block, dict), (
        f"C05: no {name}: subtree to render — the lane is designed-red until dev lands it"
    )
    with tempfile.TemporaryDirectory(prefix=f"radiance-lane-{name}-") as tmp:
        vals = Path(tmp) / "vals.yaml"
        with vals.open("w") as fh:
            yaml.safe_dump(block, fh)
        out = subprocess.run(
            ["helm", "template", lane(name)["release"], str(CHART_DIR),
             "-f", str(vals), "--set", "domain=spencerslab.com", "--set", "clusterName=gpu-ai"],
            capture_output=True, text=True, timeout=300,
        )
        if out.returncode != 0:
            raise AssertionError(
                f"C05: helm template failed for the {name} lane ({lane(name)['release']}):\n{out.stderr}"
            )
        return tuple(d for d in yaml.safe_load_all(out.stdout) if d), out.stdout


def render_lane(name: str):
    """(docs, raw stdout) for one resting lane's release render."""
    ok, reason = helm_ready()
    assert ok, reason
    return _render_lane_cache(name)


def lane_peers_evidence(name: str) -> dict:
    """Load + self-validate a resting lane's peer evidence (the q27 loader's laws,
    the D13 per-key scope: each lane owns one file, siblings stay untouched)."""
    path = lane(name)["evidence"]
    assert path.is_file(), (
        f"C05: {path} missing — the resting lanes' peer evidence is test-session-authored "
        "(the D13 per-key single source dev conforms to)"
    )
    data = yaml.safe_load(path.read_text())
    assert isinstance(data, dict) and isinstance(data.get(name), dict), f"{path.name} must carry a {name}: mapping"
    ev = data[name]
    states = ev.get("models_states")
    assert isinstance(states, list) and states, f"{name} evidence needs models_states (the wave law)"
    final = ev.get("models_allowed")
    assert isinstance(final, list) and final and states[-1] == final, \
        f"{name} evidence: last models_states must equal models_allowed"
    for i, ids in enumerate(states):
        assert isinstance(ids, list) and ids and len(set(ids)) == len(ids), \
            f"{name} models_states[{i}] must be a non-empty duplicate-free list"
    return ev
