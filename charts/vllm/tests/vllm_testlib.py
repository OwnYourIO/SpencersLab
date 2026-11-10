# Shared helpers for the charts/vllm render-contract suite
# (2026/2026-11-cf-105-feat-implement-vllm — C02; cf-131 rounds 1+2+3).
#
# Contract surface (plan "Commands"): the service-level render is produced
# with the documented extract-and-render pattern — the `vllm:` subtree of
# services/gpu-ai/prod/values.yaml dumped to a file and overlaid with -f,
# plus --set domain/clusterName (the appset injects those as top-level
# values). A second render uses the appset release name `gpu-ai-vllm`
# because the peer-hop DNS name (AC3) only resolves under that release name.
#
# cf-131 generation witness: one test session writes this suite before wave
# 1, but every chunk's green bar is the FULL suite on that chunk's commit —
# C01 still ships the pre-switch chart (its AC names the untouched legs as
# the stability witness), C02 flips the serve plane while the persistence
# legs must stand on the old mount shape, C03 moves the data plane. A single
# static expectation cannot serve three waves, so the legs C02/C03 re-pin
# branch on the generation read from the chart itself: the main-container
# image repository (cf131_plane) and the setup init container (staged_plane).
# Each branch asserts the COMPLETE contract of its generation, so the moment
# a chunk's flip lands every new constant binds at once and any half-moved
# state reds (a flipped marker with un-migrated env/recipe, or migrated
# mounts with the marker un-flipped). The next wave's contract never runs
# early and never needs a hand edit to the suite between chunks.

from __future__ import annotations

import functools
import shutil
import subprocess
import tempfile
from pathlib import Path

import yaml

CHART_DIR = Path(__file__).resolve().parent.parent  # charts/vllm
REPO_ROOT = CHART_DIR.parent.parent
SERVICE_VALUES = REPO_ROOT / "services" / "gpu-ai" / "prod" / "values.yaml"
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "vllm-render-tests.yaml"

# ---------------------------------------------------------------------------
# The cf-105 (GGUF) generation contract — the pre-switch stability witness.
# ---------------------------------------------------------------------------

# The D4 serve recipe (cf-105 plan locked decision D4, HR3 re-scoped): exact
# flag order and values. The MODEL placeholder is substituted with the
# values-driven modelPath.
D4_RECIPE = [
    ("--model", "MODEL"),
    ("--served-model-name", "qwen3.8-27b-vllm"),
    ("--scheduling-policy", "priority"),
    ("--max-model-len", "262144"),
    ("--max-num-seqs", "4"),
    ("--kv-cache-dtype", "fp8"),
    ("--gpu-memory-utilization", "0.95"),
    ("--enable-prefix-caching", None),
    ("--language-model-only", None),
    ("--enforce-eager", None),
    ("--watermark", "0.05"),
    ("--enable-sleep-mode", None),
    ("--disable-access-log-for-endpoints", "/health,/metrics,/ping"),
]

# The known Q4 GGUF location (RESEARCH Post Research V3: the live
# qwen3.8-27b-q4 rung's file, unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_XL,
# -hf auto-fetched by llama.cpp at the LLAMA_CACHE=/models root — no
# hub/ segment, that is the HUGGINGFACE_HUB_CACHE convention, not
# llama.cpp's). The values pin the live snapshot hash (discovered on
# target 2026-11-07), so the contract is layout + exact filename, never
# the full path.
MODEL_PREFIX = "/models/models--unsloth--Qwen3.8-27B-GGUF/snapshots/"
MODEL_FILENAME = "Qwen3.8-27B-UD-Q4_K_XL.gguf"

# ---------------------------------------------------------------------------
# The cf-131 (0.30 Radiance fork) generation contract — plan-derived pins.
# Every constant here is copied from the cf-131 plan of record: the round-3
# header + DECISIONS D23-D40 + the C01/C02/C03 chunk recipes (the dated
# amendments included). They are the ground truth dev must satisfy; a
# re-pin changes the plan first.
# ---------------------------------------------------------------------------

# The C01 thin-re-export target and the C02 flip of the chart image pin
# (D23: the repo's first-build artifact for the 0.30 Radiance stack).
CF131_IMAGE_REPO = "ghcr.io/ownyourio/vllm-radiance-mxfp4"
UPSTREAM_IMAGE = "magiccodingman/vllm-radiance"
UPSTREAM_TAG = "1.0.397"
UPSTREAM_DIGEST = "sha256:b73bf3e41bc0a1cf7aaa5935bebe31123f549639e69b61a3ffa81acd5f7313e0"
SRC_COMMIT = "5b99d66c844fd0a54e4a7eb93b40a1ece009a53d"          # the OCI revision label
ENGINE_COMMIT = "ced6857afa0ea7b2e3f0846a62e1394e90f15607"      # = the v0.30.0 tag commit

# The retired GGUF overlay's name, assembled so the literal never sits
# contiguously in this file: the retirement scans below walk
# charts/vllm/tests/ itself, and an intact literal would match its own
# absence-assertion (the bjw-s.common needle-exclusion precedent expressed
# without the exclusion).
LEGACY_REF = "vllm" "-rocm"

# The C02 modelPath dual edit (D24/D13, round-2 Q8 raw-release ruling): the
# served dir is exact and plain (no HF snapshot-hash segment — a re-fetch
# moves source-sha + marker + path together, the path pins the OUTPUT).
MODEL_DIR = "/models/Qwen3.8-27B-Quark-AWQ-MXFP4"
DRAFTER_DIR = "/models/Qwen3.8-27B-DFlash2-FP8"
TARGET_REPO = "amd/Qwen3.8-27B-Quark-AWQ-MXFP4"
DRAFTER_REPO = "tcclaviger/Qwen3.8-27B-DFlash2-FP8"
TARGET_SHA = "93245f7c00f1a8964b66a97c6e02e2fd09080be4"          # the post-mtp-exclude-fix revision
DRAFTER_SHA = "ee0cb26a8279b7910cc28d82a8a3e15e4728d56f"         # the qualified drafter revision
STAGED_MARKER = f".staged-mxfp4-{TARGET_SHA}-{DRAFTER_SHA}"      # both-sha-keyed (D14/D26)

# The shipped dflash spec JSON (D24: the R3 L2.3 0.30-native keys, K7 the
# top measured lane, draft max_model_len re-bound to the target's 262144 by
# the round-3 Q11 engine-cap chain — D40-reverted to the pre-D39 literal:
# the per-drafter kv_cache_dtype key is OUT; the drafter-side bf16 page
# becomes the model MAX page and 4096/1088 is not an integer, so
# unify_kv_cache_spec_page_size strided-pads ALL groups to it — the
# spec-key route inflates demand ×3.7647, dead at 262144 on this card.
# The drafter's bf16 arrives through the serveArgs pair
# --kv-cache-dtype-skip-layers sliding_window instead: the type name
# matches exactly the 5 drafter SWA layers (the target has zero), forces
# them auto/bf16 per-layer, and Phase-3 aligns their pages onto the int4
# page — equal pages, no padding, no block-size bump at this shape).
# The single-quoted YAML must render this byte-for-byte into the arg
# string — a quote drift reds the verbatim test.
SPEC_CONFIG_DFLASH = (
    '{"method":"dflash","model":"/models/Qwen3.8-27B-DFlash2-FP8",'
    '"num_speculative_tokens":7,"max_model_len":262144,'
    '"attention_backend":"TRITON_ATTN","disable_padded_drafter_batch":true}'
)
# The mtp toggle JSON is a values-COMMENT record, never the shipped splice
# (D16/D24); the comment test matches whitespace-stripped fragments.
SPEC_CONFIG_MTP = (
    '{"method":"mtp","num_speculative_tokens":4,"attention_backend":"R4D",'
    '"disable_padded_drafter_batch":true}'
)

# The D24 serve recipe (cf-131 plan of record + round-3 Q11 engine-cap
# ruling, D36-amended — the int4_per_token_head anchor, the TRITON_ATTN
# target backend, the ssm-bf16 pair after align, the 0.98 util ceiling,
# the owner's R6-Q1 q4 boot config — and D38-amended: the vision drop
# swaps the mm pair for the --language-model-only token, 45 -> 44, and
# D40-amended: the owner's R11-Q1 ruling puts the
# --kv-cache-dtype-skip-layers sliding_window pair directly after the
# --kv-cache-dtype pair, 44 -> 46 (the pair's why is on the
# SPEC_CONFIG_DFLASH header):
# exact flag order and values,
# rendered at the SERVICE level where only modelPath/rocrVisibleDevices
# are overridden. The recipe starts at
# --served-model-name because flag_pairs() skips the leading non-flag token
# — the args-START-with-the-model-path law (D24: the 0.30 entrypoint does
# `exec vllm serve "$@"`, so a `vllm`/`serve` token would double the verb)
# is asserted directly on args[0] by the verbatim test.
RECIPE_CF131 = [
    ("--served-model-name", "qwen3.8-27b-vllm"),
    ("--tensor-parallel-size", "1"),
    ("--max-num-seqs", "3"),
    ("--max-model-len", "262144"),
    ("--gpu-memory-utilization", "0.98"),
    ("--max-num-batched-tokens", "2560"),
    ("--kv-cache-dtype", "int4_per_token_head"),
    ("--kv-cache-dtype-skip-layers", "sliding_window"),
    ("--attention-backend", "TRITON_ATTN"),
    ("--enable-prefix-caching", None),
    ("--mamba-cache-mode", "align"),
    ("--mamba-ssm-cache-dtype", "bfloat16"),
    ("--no-async-scheduling", None),
    ("--enable-auto-tool-choice", None),
    ("--tool-call-parser", "qwen3_coder"),
    ("--reasoning-parser", "qwen3"),
    ("--generation-config", "auto"),
    ("--default-chat-template-kwargs", '{"reasoning_effort":"xhigh"}'),
    ("--trust-remote-code", None),
    ("--speculative-config", SPEC_CONFIG_DFLASH),
    ("--host", "0.0.0.0"),
    ("--port", "8000"),
    # the Q7 carries appended after the compose-baseline block (round-2):
    ("--scheduling-policy", "priority"),
    ("--watermark", "0.05"),
    # The D38 swap (the owner's R8-Q1 "C — drop vision" + R8b-Q1 "C + f2"):
    # the bool token ships IN PLACE OF the mm pair. The flag choice is
    # load-bearing (the image-0 trap): a bare {"image": 0} leaves qwen3_5's
    # other supported modality at its 999 default and the warmup profiles a
    # max-size VIDEO dummy — same peak, zero saving; --language-model-only
    # zeroes every modality limit at the getter and trips the registry's
    # text-only short-circuit [R8 201, R8b 226-227].
    # 48 GB-RDNA3 RE-ENABLE RIDER (the values serveArgs comment is the
    # authority — a copy-back, not archaeology [R8b.4e]): the pair returns
    # verbatim as
    #     ("--limit-mm-per-prompt", '{"image": 4}'),
    # replacing this token, together with the "image" input leg on the
    # three C04 catalog rows and the C05 marker rows. Its parse law rides:
    # the 0.30 stock CLI parses --limit-mm-per-prompt through json.loads —
    # a single-quoted JSON dict so the braces survive to the rendered arg;
    # the 0.27.1 fork launcher's `image=4` passthrough is NOT the stock
    # CLI's — it dies at CLI parse (verified on target at the first boot).
    ("--language-model-only", None),
]

# The D24 drop list — AC7's absence side. Each entry must be GONE from the
# shipped render, not merely unreferenced. Two classes among the D24-era
# six: the cf-105 trio at the top rode that recipe and died with the D24
# rewrite (shipped, then dropped); the three after it are never-shipped
# D24-era named bars — absent from every shipped recipe, the bar IS their
# whole contract. The list INVERTS on the D38 pair,
# the same shape the DROPPED_ENV_CF131 comment recorded for D34:
# --language-model-only went OUT (cf-105 rode it, D24 dropped it, the
# owner's vision ruling ships it again — its LOSS fails the recipe-verbatim
# equality above), --limit-mm-per-prompt came IN (the D38 drop — its
# presence is the drift the values re-enable rider bars until the
# 48 GB-RDNA3 card restores the pair).
DROPPED_FLAGS_CF131 = (
    "--enforce-eager",
    "--enable-sleep-mode",
    "--disable-access-log-for-endpoints",
    "--kv-cache-memory-bytes",   # the re-measure-gate law (D24): the chart ships NO pool pin
    "--mamba-cache-dtype",
    "--override-generation-config",
    "--limit-mm-per-prompt",
)

# The D25 21-var main-container env law, D34-restored and D38-extended:
# f2's VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS joins at the tail (the
# CUDA-graph pre-tax comes off the KV sizing; the graphs still capture at
# runtime and land on allocator slack — the recorded capture-bet, the
# engine's disabled-branch WARNING expected-and-priced [R8 209]). The
# other 20 vars are byte-stable — including the (8)-slot OQ12 ViT var:
# restored at D34 because the image carries the flash-attn package it
# binds, kept by D38 although text-only serving never runs the ViT that
# package qualifies (decorative-but-harmless; the exact-set law does not
# retire it). The exact set — the entrypoint's exit-64 combination gates
# make any var drift a boot failure, so equality IS the risk control.
# ROCR_VISIBLE_DEVICES splices from the service values key, the rest are
# literal.
def env_want_cf131(rocr_value: str) -> dict:
    return {
        "ROCR_VISIBLE_DEVICES": str(rocr_value),
        "HIP_VISIBLE_DEVICES": "0",           # the 8060S-exclusion twin
        "HF_HUB_OFFLINE": "1",
        "VLLM_CACHE_ROOT": "/cache/vllm",     # the four /cache/* re-declarations —
        "TORCHINDUCTOR_CACHE_DIR": "/cache/inductor",   # C03's mount lands the target
        "TRITON_CACHE_DIR": "/cache/triton",
        "AITER_ROOT_DIR": "/cache/aiter",
        "FLASH_ATTENTION_TRITON_AMD_ENABLE": "TRUE",    # (8) slot, D34-restored; kept decorative at text-only serving (D38)
        "RADIANCE_WEIGHT_QUANTIZATION": "auto",         # the entrypoint seam name (D25)
        "RADIANCE_MXFP4": "1",
        "RADIANCE_MXFP4_W4A8": "1",
        "RADIANCE_MXFP4_W4A8_MIN_M": "0",
        "RADIANCE_MXFP4_DECODE_MAX_M": "64",
        "RADIANCE_MXFP4_TN4_MIN_M": "2048",
        "RADIANCE_MXFP4_WPERM": "1",
        "RADIANCE_MXFP4_DECODE_NT": "1",
        "VLLM_USE_V2_MODEL_RUNNER": "1",      # the dflash V2-lane prerequisites
        "RADIANCE_FAST_DRAFT": "1",
        "RADIANCE_COMPILATION_CONFIG": '{"cudagraph_mode":"PIECEWISE"}',
        "HSA_TOOLS_DISABLE_REGISTER": "1",    # issue #6/#12 mitigation (R3-Q5)
        "VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS": "0",  # the D38 f2 leg (the shipped capture-bet, header)
    }

# Named individually because AC5 calls them out — the dict equality above
# already excludes them, but a failure message must name WHICH drop leaked.
# FLASH_ATTENTION_TRITON_AMD_ENABLE left this trio at D34: the exact set
# now REQUIRES it (the package it binds is installed in the image), so
# removing the var fails the dict equality above instead of leaking here.
DROPPED_ENV_CF131 = (
    "RADIANCE_GDN_LAZY",
    "HUGGINGFACE_HUB_CACHE",
    "VLLM_SERVER_DEV_MODE",
)

# Probe budget on the 0.30 boot class (D18 amended): 60 s + 15 s x 160 = the
# 40-min conservative envelope for the first-deploy (init staging + cold
# AITER-JIT boot). The startup probe is the LIVE-262144 risk's loud, gated
# refusal leg (D31) — the exact budget, not a floor, is the contract.
PROBES_CF131 = {"initialDelaySeconds": 60, "periodSeconds": 15, "failureThreshold": 160}

# The C03 init container bars (D26): the plan numbers, pinned exactly.
INIT_RESOURCES = {"requests": {"cpu": "2", "memory": "4Gi"}, "limits": {"memory": "8Gi"}}

# Probe ports may render as the numeric 8000 or the named container port
# "http" — the name is bound to 8000 by the containerPort contract
# (test_render), so both forms hit the same endpoint.
PROBE_PORT_OK = (8000, "http")


def helm_ready() -> tuple[bool, str]:
    # Binary check ONLY: an absent helm is an environment skip, but a missing
    # chart is implementation state — render tests must RED naming C02, not
    # skip (the mass-skip trap of the repo's helm-guarded suites, EXPLORE §4;
    # the app-template tgz is asserted by test_contract, not gated here).
    if shutil.which("helm") is None:
        return False, ("helm binary not on PATH (~/.local/bin/helm — export PATH; "
                       "without it the helm-guarded tests skip silently, EXPLORE §4)")
    return True, ""


def chart_values() -> dict:
    path = CHART_DIR / "values.yaml"
    assert path.is_file(), "C02: charts/vllm/values.yaml missing — the chart is not implemented yet"
    return yaml.safe_load(path.read_text())


def find_image_nodes(node, out: list):
    if isinstance(node, dict):
        if "repository" in node and "tag" in node:
            out.append(node)
        for v in node.values():
            find_image_nodes(v, out)
    elif isinstance(node, list):
        for v in node:
            find_image_nodes(v, out)


def cf131_plane(values: dict | None = None) -> bool:
    """True once the chart image pin names the cf-131 re-export (the C02
    flip). Every generation-branch reads exactly this marker so the render
    contract, the values contract and the CI witnesses switch together."""
    nodes: list = []
    find_image_nodes((values if values is not None else chart_values()), nodes)
    return any(node.get("repository") == CF131_IMAGE_REPO for node in nodes)


def service_vllm_block() -> dict:
    data = yaml.safe_load(SERVICE_VALUES.read_text())
    block = data.get("vllm")
    assert block is not None, (
        "C02: services/gpu-ai/prod/values.yaml has no top-level vllm: block "
        "— the ApplicationSet values block is not implemented yet"
    )
    return block


@functools.lru_cache(maxsize=None)
def _render_cache(release: str, service: bool, extra: str) -> tuple:
    with tempfile.TemporaryDirectory(prefix="vllm-test-") as tmp:
        cmd = [
            "helm", "template", release, str(CHART_DIR),
            "--set", "domain=spencerslab.com",
            "--set", "clusterName=gpu-ai",
        ]
        if service:
            vals = Path(tmp) / "vals.yaml"
            with vals.open("w") as fh:
                yaml.safe_dump(service_vllm_block(), fh)
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


def render(release: str = "vllm", service: bool = True, extra_set: str = ""):
    """(docs, raw stdout) of one render; raises AssertionError on helm failure."""
    return _render_cache(release, service, extra_set)


def deployment(docs) -> dict:
    deploys = [d for d in docs if d.get("kind") == "Deployment"]
    assert deploys, "C02: no Deployment rendered"
    assert len(deploys) == 1, f"C02: expected one Deployment, got {[d['metadata']['name'] for d in deploys]}"
    return deploys[0]


def main_container(deploy: dict) -> dict:
    containers = deploy["spec"]["template"]["spec"].get("containers", [])
    for c in containers:
        if c.get("name") == "vllm":
            return c
    raise AssertionError(f"C02: no container named 'vllm'; got {[c.get('name') for c in containers]}")


def init_container(deploy: dict) -> dict:
    """The C03 staging actor (D14): the rendered pod carries EXACTLY one init
    container, named 'setup' — more than one would run staging alongside
    something the plan never sanctioned."""
    inits = deploy["spec"]["template"]["spec"].get("initContainers") or []
    assert len(inits) == 1, f"C03: expected exactly one init container, got {[i.get('name') for i in inits]}"
    assert inits[0].get("name") == "setup", f"C03: the init container is named {inits[0].get('name')!r}, want setup"
    return inits[0]


def staged_plane(deploy: dict) -> bool:
    """True once the C03 data plane lands (the setup init container — the
    same artifact the persistence advancedMounts conversion writes in the
    same chunk, so the render's initContainers list is the C02/C03 marker)."""
    return bool(deploy["spec"]["template"]["spec"].get("initContainers"))


def pod_template(deploy: dict) -> dict:
    return deploy["spec"]["template"]


def env_map(container: dict) -> dict:
    return {e["name"]: e.get("value") for e in container.get("env", [])}


def services(docs) -> list:
    return [d for d in docs if d.get("kind") == "Service"]


def persistent_volume_claims(docs) -> list:
    return [d for d in docs if d.get("kind") == "PersistentVolumeClaim"]


def assert_model_path_shape(path, label: str) -> None:
    if cf131_plane():
        assert path == MODEL_DIR, (
            f"C02 (cf-131): {label} model path {path!r} must be EXACTLY {MODEL_DIR} — the raw-release "
            "dir of the 500 GiB weights PVC (the round-2 Q8 raw-release ruling; the source revision "
            f"{TARGET_SHA[:8]} pins the marker + the comment + the runbook, NOT the path)"
        )
        return
    assert isinstance(path, str) and path.startswith(MODEL_PREFIX), (
        f"C02: {label} --model path {path!r} must live under the LLAMA_CACHE-root "
        f"snapshot layout {MODEL_PREFIX} (the 500 GiB weights PVC, RESEARCH Post Research V3)"
    )
    assert path.endswith(MODEL_FILENAME), (
        f"C02: {label} --model path {path!r} must name the known Q4 GGUF file {MODEL_FILENAME}"
    )


def flag_pairs(args: list) -> list:
    """Rendered args as ordered [(flag, value|None), ...]. `--flag=value`
    splits on the first =; a following non-flag token is the value; a
    trailing/---prefixed successor makes the flag boolean."""
    out = []
    i = 0
    while i < len(args):
        tok = args[i]
        if not tok.startswith("--"):
            i += 1
            continue
        if "=" in tok:
            flag, val = tok.split("=", 1)
            out.append((flag, val))
            i += 1
        elif i + 1 < len(args) and not args[i + 1].startswith("--"):
            out.append((tok, args[i + 1]))
            i += 2
        else:
            out.append((tok, None))
            i += 1
    return out


def expected_recipe(model_path: str) -> list:
    if cf131_plane():
        return list(RECIPE_CF131)
    return [(flag, model_path if value == "MODEL" else value)
            for flag, value in D4_RECIPE]


def grafana_annotations(deploy: dict) -> dict:
    ann = (pod_template(deploy).get("metadata") or {}).get("annotations") or {}
    return {k: v for k, v in ann.items() if k.startswith("k8s.grafana.com/")}
