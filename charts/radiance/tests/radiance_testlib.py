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
    # own budget — pool 42.70 + kv-resident host mirror ~32 + arena 2.00 +
    # placement 1.18 + staging = "pinned by this process 71.04 GiB" (report 2)
    # vs a 64.00 cgroup => OOM. D28 planned the ladder ceiling 96; asked "which
    # value should charts/radiance ship for gpu-ai?", the owner answered
    # verbatim "110 GiB (your figure)" — D29 records the ruling (D28's reasoning
    # stands as history, append-only). 110 is NOT a radiance plan figure in the
    # repo (§D6.1): it is STRATA's own limit on this node (charts/llama-swap/
    # values.yaml:1319-1325, the owner's proven "container dies BEFORE the node"
    # envelope) — the ruling EXTENDS that node law to radiance. Slack: 110 -
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
    "guaranteedMemoryGi": 110,
    "hostPoolMib": 43000,
    "maxModelLen": 200000,
    "maxNumSeqs": 8,
    "cpuCores": 8,
}
KV_RESIDENT_TOKENS = 32768        # the owner's KV-to-RAM lever (D3/D17); excludes prefix tier

# The serveArgs contract — ORDER-INSENSITIVE set equality (AC3): every pair
# once; the model path splices the values anchor. `--host ::` (IPv6-any),
# keyless (no --api-key), ngram on disk, spec 3, chunks 4096.
FULL_PROFILE = {
    "--model": MODEL_PATH,
    "--port": "8000",
    "--host": "::",
    "--tp": "1",
    "--max-model-len": "200000",
    "--max-num-seqs": "8",
    "--placement": "expert_tiered",
    "--host-pool-mib": "43000",
    "--gpu-headroom-mib": "96",
    "--kv-cache-dtype": "fp8",
    "--kv-resident": "32768",
    "--num-speculative-tokens": "3",
    "--max-num-batched-tokens": "4096",
    "--checkpoint-interval": "4096",
    "--ngram-placement": "disk",
    "--served-model-name": SERVED_ID,
}

# Absence law (AC3 — each is a named bar, RESEARCH 'Guide corrections' + D8):
# the engine has NO `serve` verb; --expert-vs-cache-ratio is a stale guide
# flag; --prefix-cache-mib is MUTUALLY EXCLUSIVE with --kv-resident (the
# 8-session lever IS kv-resident); no --api-key (keyless); NO ROCR/HIP env
# (the named pool selects the card — plugin injects devices, sets no env).
ABSENT_FLAGS = (
    "--expert-vs-cache-ratio",
    "--prefix-cache-mib",
    "--api-key",
    "--api-key-env",
)
ABSENT_ENV = ("ROCR_VISIBLE_DEVICES", "HIP_VISIBLE_DEVICES")

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
# BusyBox hash applets (md5_sha1_sum.c getopt32 "^" "scwbt" — short options only,
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
# 1000m => 8-23 min; MORE THAN 1 CORE IS POINTLESS (single-threaded applet).
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
