# Shared helpers for the strata render-contract suite, run-2 shape
# (.agents/plans/2026/2026-10-cf-77-feat-strata-llama-swap-1 — chunks r2-C01..C04).
# Re-homed from the run-1 standalone-chart suite; the parent chart now owns the
# strata workload as a second app-template controller (seven default-OFF data
# flags) and the standalone chart dir retires (Q-C ruling).
#
# Contract literals below are frozen plan facts — each cites its r2 chunk/AC and
# the run-1 RESEARCH section it pins. Tests aim at not-yet-written behavior by
# design: a missing file or failing helm render is a RED naming its chunk, not
# a skip. Only tooling absence (helm binary, jsonschema lib) may skip.

from __future__ import annotations

import functools
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import yaml

CHART_DIR = Path(__file__).resolve().parent.parent       # charts/llama-swap
TESTS_DIR = Path(__file__).resolve().parent              # charts/llama-swap/tests
REPO_ROOT = CHART_DIR.parent.parent
SCHEMA_DIR = TESTS_DIR / "schema"
EVIDENCE_DIR = TESTS_DIR / "evidence"
PEERS_EVIDENCE = EVIDENCE_DIR / "strata-peers-expected.yaml"
OFF_FIXTURE = EVIDENCE_DIR / "off-parity" / "render-default.yaml"
OFF_PROVENANCE = EVIDENCE_DIR / "off-parity" / "PROVENANCE.md"
SERVICE_VALUES = REPO_ROOT / "services" / "gpu-ai" / "prod" / "values.yaml"
GPU_VALUES = REPO_ROOT / "services" / "gpu" / "prod" / "values.yaml"
CUSTOM_VALUES = REPO_ROOT / "custom-values" / "gpu-ai" / "prod-values.yaml"
RUNBOOK_NOTE = REPO_ROOT / ".agents" / "notes" / "strata-host-prep-gpu-ai.md"
PARENT_README = CHART_DIR / "README.md"
CONTAINER_DIR = REPO_ROOT / "containers" / "strata"
# C07 (U9.4 revision): the model-fetch logic lifts from the values.yaml init
# into build-context files baked at /opt/strata/bin/. The suite reads the
# SOURCES here — the laws that used to run over the rendered script body move
# with the code, one source of truth at every wave (chunks/C07.md).
FETCH_SH = CONTAINER_DIR / "files" / "fetch_models.sh"
HF_FETCH_PY = CONTAINER_DIR / "files" / "hf_fetch.py"
BYTE_PINS_ENV = CONTAINER_DIR / "files" / "byte_pins.env"
BIN = "/opt/strata/bin"
STRATA_TEMPLATES_DIR = CHART_DIR / "templates"
RELEASE_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "release.yaml"
GITIGNORE = REPO_ROOT / ".gitignore"

# The retired standalone-chart dir. C02's repo grep (r2-C02 AC3) forbids live
# code paths from referencing it — this suite asserts that grep, so it must not
# itself contain the literal path string: the Path is COMPOSED, never written.
STANDALONE_CHART_DIR = REPO_ROOT / "charts" / "strata"
STANDALONE_CHART_PATH_TEXT = "charts" + "/" + "strata"

# --- r2-C01 chart interface ---------------------------------------------------
RELEASE = "gpu-ai-llama-swap"                 # the single Application/release
STRATA_OBJECT_NAME = "gpu-ai-llama-swap-strata"   # app-template fullname + controller key
NAMESPACE = "default"
CM_CONFIG = "strata-config"
CM_PROFILE = "strata-profile"

# Default-OFF is seven native data flags (plan architecture, prototype-verified):
# a partial set must fail loudly — an advancedMounts into a DISABLED controller
# hard-fails the render, which is why the persistence entries carry flags too.
SEVEN_FLAGS = (
    "app-template.controllers.strata.enabled=true",
    "app-template.service.strata.enabled=true",
    "app-template.persistence.strata-config.enabled=true",
    "app-template.persistence.strata-profile.enabled=true",
    "app-template.persistence.strata-kfd.enabled=true",
    "app-template.persistence.strata-dri.enabled=true",
    "app-template.persistence.strata-shm.enabled=true",
)
FLAG_PATHS = tuple(f.rsplit("=", 1)[0] for f in SEVEN_FLAGS)
# FLAG_PATHS carry the chart-root key path (already app-template.-prefixed) —
# the same string is BOTH the --set key (with =value appended in SEVEN_FLAGS)
# and the service-overlay dig path: overlay and chart gate path spelling must
# be IDENTICAL, and that identity is itself r2-C03's contract. Derived proper
# subsets for the divergence guards (--set needs key=value, never bare keys):
SEVEN_FLAGS_PERSISTENCE = SEVEN_FLAGS[2:]
SEVEN_FLAGS_CONTROLLER_SERVICE = SEVEN_FLAGS[:2]
CANONICAL_MISSING_CONTROLLER = re.compile(r"No enabled controller found with identifier")

# --- run-1 constants that survive consolidation (values re-keyed, facts not) --
PEER_NAME = "strata"
PRIMARY_ID = "qwen3.8-flash-next-strata"
STRIX_ID = "qwen3.8-flash-next-strata-strix"
PROFILE_PRIMARY_FILE = "strata-iq3_s.json"
PROFILE_STRIX_FILE = "strata-strix-iq3_s.json"

# T0 (owner ruling 2026-11-01, DECISIONS U13): the engine's per-request
# accounting line — `request prompt P cached C output O prompt_read R ms total
# S ms prefill X tok/s decode Y tok/s`. The serve progress chatter counts a
# reused prefix in its position and clocks from admission, so it is not a rate;
# this is the measurement the published R9700 numbers are comparable against
# (RESEARCH R6 [R6-12][R6-21]). Logging-only, and it belongs on EVERY arena —
# a rate without an arena label is how the ~500-vs-2,800 confusion started.
REQUEST_LINES_ENV = "STRATA_REQUEST_LINES=1"

# 2026-11-10 envelope round, on EVERY arena env: glibc retains evicted
# conversation-cache parks in the heap, so the engine's RAM gate refuses
# forever (Strata #5697, open); mmap-backed large allocations return on free.
MALLOC_MMAP_ENV = "MALLOC_MMAP_THRESHOLD_=1048576"

# The pod cgroup and the per-rung declared caps. Declared HERE rather than in
# the envelope block below because PRIMARY_REQUIRED_PAIRS needs the value at
# definition time. U14 (owner ruling 2026-11-01): the flagship declared 92160
# against term-sums of ~91.84 GiB — 46.84 arena + 32 conversation cache + ~13
# worst-case 4-slot KV — so parking was refused inside its own number while the
# node sat idle; 110592 (108 GiB) inside the cgroup — 116Gi at U14, lowered
# to 110Gi by the 2026-11-10 envelope round — keeps the reserve style the q4
# rung already rides.
PRIMARY_MEMORY_LIMIT_MIB = 110592

# Era-mapped frozen captures for the byte-unchanged preservation arms
# (TEST_SPEC 9.16/9.20): C07's sanctioned 0.1.52->0.1.54 and C09's
# 0.1.54->0.1.55 halo re-pins moved the strix profile's era. The primary's era
# moved twice, both OWNER-RULED posture changes on 2026-11-01: T3 (the prompt
# chunk cap) and U14 (the declared cap fitting its own term-sums). Each step's
# delta is pinned by test_strata_strix.py's primary chain guard — one flag per
# era, membership unchanged — so the whole-file deep-equal here stays a law
# with no exempt-key hole. The engine-re-pin eras (c07/c09) must never carry a
# primary file: an engine re-pin cannot move its era (version-free claim root).
PROFILE_FIXTURE_ERA = {
    PROFILE_PRIMARY_FILE: "strata-profiles-u14-repin",
    PROFILE_STRIX_FILE: "strata-profiles-c09-repin",
    # cf-141 adds whole-file anchors for q4/orca (era 0 =
    # "strata-profiles-cf141-pre", the CF141_PRE_ERA constant defined with the
    # cf-141 block at the file tail and asserted equal there); profile_fixture
    # resolves the chain TIP, so these entries are the fallback floor,
    # consumed by the envelope/bump-era arms. The q4/orca key strings are
    # spelled literally because the frozen-id constants they alias are defined
    # further down (the tail assert keeps the two spellings one fact).
    # Ornith has no capture and none is added (the ticket never moves it).
    "strata-q4.json": "strata-profiles-cf141-pre",
    "strata-orca-iq4_xs.json": "strata-profiles-cf141-pre",
}


def profile_fixture(file: str) -> dict:
    """Parsed JSON of a profile's CURRENT frozen-era capture: the newest
    landed cf-141 chain step (contiguous from the rung's anchor) when the
    ticket's era dirs exist, else the pre-cf-141 map era above. Consumption
    moves to the new era automatically at each capture — a values move whose
    step dir was never captured keeps reading the old era and goes red
    naming the missing step (the era dirs are the ledger, cf-141 law 7)."""
    era = cf141_era_tip(file) or PROFILE_FIXTURE_ERA[file]
    return json.loads((EVIDENCE_DIR / era / file).read_text())

# C01 interface contract (containers/strata/README.md freezes these; the
# container itself is untouched by run 2 — RESEARCH §1).
SERVE_ENTRY = "/opt/strata/terminal/bin/strata"
ENGINE_ROOT = "/opt/strata/components/engine"
ENGINE_LABEL_RE = re.compile(r"^\d+\.\d+\.\d+-linux-x86_64-hip-(rx9070|halo)$")

# r2-C01 task: serve takes only these flags (run-1 RESEARCH §2); all engine
# tuning lives in the profile JSON.
SERVE_FLAGS = {"--profile", "--host", "--port"}

PRIMARY_ENV_FIVE = [
    "STRATA_PF_FUSED=1", "STRATA_PF_GEMM=1", "STRATA_PA_FAST=1",
    "STRATA_HIP_WMMA=1", "STRATA_SELECT_WMMA=1",
]

# run-1 RESEARCH §2 measured absence: the env var does not exist upstream; any
# appearance in chart/container surfaces is the card guide's misattribution.
VOID_ENV_TOKEN = "STRATA_KV_GROW_HOLD"

PRIMARY_FORBIDDEN_FLAGS = [
    "--resident-budget-gib", "--prompt-cache", "--kv-grow", "--vision",
    # --ple-io (any value): the engine default maps the 28.8 GiB n-gram
    # table from disk; setup's node-probed `ram` choice + the trio warm is
    # what OOM-killed the node 2026-10-29. Re-admitting it is a test-
    # session re-pin paired with a real capacity plan, not a silent edit.
    "--ple-io",
    # --kv-resident was listed under the run-1 reading of RESEARCH §5
    # ("batch-column item"); the generated run-config for THIS node proves
    # setup itself pairs it with --ple-io ram outside any --batch context
    # (2026-10-29 transplant), so it is baseline now, not forbidden.
]
# Baseline = the generated run-config (2026-10-29 transplant) PLUS the
# owner budget ruling of the same day: Strata-data paths and --kv-resident
# required so a revert to the seed guesses goes red; --memory-limit-mib 92160
# inside the 96Gi cgroup (#1601 pair); conversation-cache 32768 x 16 explicit.
# --mtp-window stays absent (toggle); --batch-mtp on neither list
# (one-at-a-time posture). --prefill moved from setup's `auto` at the 2026-11-01
# T3 ruling (owner "go"): bare auto = 16,384 chunks on gfx12, 32,768 is the
# PR #3636 chunk that measured ~2,519 tok/s on this node class — the file's own
# comment had reserved the override for exactly this --plan/bench evidence.
PRIMARY_REQUIRED_PAIRS = [
    ("--pack", "/models/strata/Strata-data/packs/iq3_s"),
    ("--native", "/models/strata/Strata-data/models/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf"),
    ("--expert-cache", "auto"),
    ("--max-context", "262144"),
    ("--kv", "int8"),
    ("--spec", "4"),
    ("--spec-min-p", "0.5"),
    ("--prefill", "auto:32768"),
    ("--kv-resident", "32768"),
    # 2026-10-29 OOM pairing: a cgroup limit without the engine knowing it
    # gets the arena killed mid-pin; this pair is the #1601 contract. U14
    # (2026-11-01) moved 92160 -> 110592: the rung's terms are 46.84 arena +
    # 32 conv + ~13 KV ≈ 91.84 GiB, which the 90 GiB declaration never covered
    # (first-boot evidence: parking refused at "3259 MiB available"), and the
    # pod cgroup grew to 116Gi the same day.
    ("--memory-limit-mib", str(PRIMARY_MEMORY_LIMIT_MIB)),
    # Owner budget ruling 2026-10-29: 32 GiB parked-conversation budget,
    # 16 slots (IQ3_S full-256k park ~= 3.3 GiB of it). cf-141 C03 landing
    # round (§9.28): the conv-mib value is the one entry a ruling moves
    # without a re-pin ritual (row-H shipped 16384; a future scale-back
    # moves it again), so the SHIPPED number resolves from the primary's
    # era-chain tip — see primary_required_pairs(). The stored value is the
    # 2026-10-29 ruling's number, kept as the pre-row-H readable history;
    # consumers must use the resolver.
    ("--conversation-cache-mib", "32768"),
    ("--conversation-cache-slots", "16"),
]
PRIMARY_REQUIRED_FLAGS = [
    "--pack", "--native", "--ple-gguf", "--expert-profile", "--mtp",
]

# cf-141 C03 landing round (TEST_SPEC §9.28): the era-resolved pair values —
# flags whose shipped number a ruling legitimately moves (row-H: conv
# 32768→16384). The arm's law intent — "required-arg-pair presence at the
# SHIPPED number" — must survive literal churn: resolving from the chain tip
# keeps the pin anchored to the captured ledger (each step's delta is law-
# verified) instead of a table copy that goes stale at the next ruling — the
# validation-at-fault class the static entry produced at C03.
PRIMARY_ERA_RESOLVED_FLAGS = ("--conversation-cache-mib",)


def primary_required_pairs() -> list[tuple[str, str]]:
    tip = dict(arg_pairs(profile_fixture(PROFILE_PRIMARY_FILE)))
    out = []
    for flag, value in PRIMARY_REQUIRED_PAIRS:
        if flag in PRIMARY_ERA_RESOLVED_FLAGS:
            assert flag in tip, (
                f"the primary's era-chain-tip capture carries no {flag} pair — "
                "the required-pair law cannot resolve its shipped value"
            )
            value = tip[flag]
        out.append((flag, value))
    return out


def required_pair_violations(present: dict, required) -> list[str]:
    """Pure membership check shared by the arm and its mutation probe."""
    return [f"{flag} {want!r} missing — render reads {present.get(flag)!r}"
            for flag, want in required if present.get(flag) != want]

# run-1 RESEARCH §7 verbatim eight-set — spellings are upstream literals;
# normalizing them (case, prefixes) breaks the engine's env parsing.
STRIX_EIGHT_SET = [
    "STRATA_PF_FUSED=1", "STRATA_PF_GEMM=1", "STRATA_HC_UPMIX=1",
    "STRATA_PA_FAST=1", "STRATA_HIP_WMMA=1", "STRATA_SELECT_WMMA=1",
    "STRATA_PF_SWITCH_MIN_T=4096", "STRATA_PREFILL_STREAM_MIN=128",
]

# C-A keyless (r2 DECISIONS): "api_key": "none" is the shipped default in BOTH
# run-config profiles; the secret chain (ExternalSecret, bitwardenIds,
# ${env.STRATA_API_KEY}, secretKeyRef) is REMOVED, not guarded-off.
API_KEY_NONE = "none"
SECRET_CHAIN_TOKENS = [
    "strata-api-key", "STRATA_API_KEY", "PENDING-OPERATOR",
    "ExternalSecret", "secretKeyRef", "bitwarden",
]

# r2-C03 / evidence: the consolidated pod is a controller of THIS release, so
# the peers proxy flips to the app-prefixed Service name. Single source:
# evidence/strata-peers-expected.yaml — this constant mirrors it, and the
# wiring tests assert render==evidence, so drift between the two is loud.
PEERS_PROXY = f"http://{STRATA_OBJECT_NAME}.{NAMESPACE}.svc.cluster.local:8080"

# Peers evidence is a WAVE TABLE, not one list: cf-86 grew the outer
# models_allowed one id per landed Strata rung (C01 → C02 → C06), and the
# suite must stay correct at every intermediate wave because dev lands the
# chunks in order. models_allowed is the C08-final set (four ids — the
# abliterated arena was swept by U9.3); models_states pins every sanctioned
# wave list, oldest first, history included. The one sanctioned SHRINK is a
# removal-only transition dropping exactly the swept abliterated id (the
# law below); a peers list that matches no state is still a phantom or a
# lost entry.
def strata_peers_evidence() -> dict:
    if not PEERS_EVIDENCE.exists():
        raise AssertionError(f"{PEERS_EVIDENCE.name} evidence is missing")
    data = yaml.safe_load(PEERS_EVIDENCE.read_text())
    if not isinstance(data, dict) or not isinstance(data.get("strata"), dict):
        raise AssertionError(f"{PEERS_EVIDENCE.name} must carry a strata: mapping")
    ev = data["strata"]
    states = ev.get("models_states")
    if not isinstance(states, list) or not states:
        raise AssertionError(
            f"{PEERS_EVIDENCE.name} needs models_states — every wave's exact "
            "ordered peer list is pinned so consumers stay wave-correct"
        )
    final = ev.get("models_allowed")
    if not isinstance(final, list) or not final or states[-1] != final:
        raise AssertionError(
            f"{PEERS_EVIDENCE.name}: last models_states must equal models_allowed "
            "(the ruled final peer set)"
        )
    prev: set = set()
    for i, ids in enumerate(states):
        if not isinstance(ids, list) or not ids or len(set(ids)) != len(ids):
            raise AssertionError(f"models_states[{i}] must be a non-empty duplicate-free list")
        if not set(ids) <= set(final) | {ABL_ID}:
            # The swept abliterated arena may appear in HISTORY states but not
            # in the final allowed set (C08 U9.3, TEST_SPEC 9.17); every other
            # id outside models_allowed is a phantom.
            raise AssertionError(f"models_states[{i}] names a peer outside the final set")
        if prev:
            removed = prev - set(ids)
            if removed and removed != {ABL_ID}:
                raise AssertionError(
                    f"models_states[{i}] drops {sorted(removed)} — additions are the rule; "
                    "the ONE sanctioned shrink is the C08 sweep of the abliterated arena"
                )
        prev = set(ids)
    return ev


def expected_strata_peers(served_model_ids) -> list:
    """The sanctioned ordered peers list for the strata rungs this render
    actually serves (wave lookup against models_states)."""
    ev = strata_peers_evidence()
    served = set(served_model_ids)
    for ids in ev["models_states"]:
        if set(ids) <= served and served <= set(ev["models_allowed"]):
            if set(ids) == (served & set(ev["models_allowed"])):
                return ids
    raise AssertionError(
        f"served strata ids {sorted(served)} match no sanctioned peers wave — "
        f"states {[sorted(s) for s in ev['models_states']]}"
    )

# --- cf-86 frozen ids / pins (plan 2026-10-29 + DECISIONS "Renumap +
# final-shape decisions" + C06 FINAL pins) -----------------------------------
# The inner ids frozen by the plan; C05 consumes them verbatim and the peers
# evidence lists them in this order. Profile filenames are frozen by the chunk
# cmd literals (C02 strata-orca-iq3_xxs.json at authoring; C08's U9.2 ruling
# renamed it in place to strata-orca-iq4_xs.json — same arena id, new quant),
# C06 strata-q4.json. ABL_ID stays defined for the C08 absence arms: the swept
# id must be provably ABSENT from every live surface.
ABL_ID = "qwen3.8-flash-next-strata-abliterated"        # C01, swept by C08
ORCA_INNER_ID = "qwen3.8-flash-next-strata-orca"        # C02
Q4_ID = "qwen3.8-flash-next-strata-q4"                  # C06
ORNITH_ID = "ornith-1.5-122b-strata-q4"                 # C09 (fresh id family)
PROFILE_ABL_FILE = "strata-abliterated-iq3_xxs.json"    # swept; absence-pinned
PROFILE_ORCA_FILE = "strata-orca-iq4_xs.json"
PROFILE_Q4_FILE = "strata-q4.json"
PROFILE_ORNITH_FILE = "strata-ornith-q4.json"
INNER_IDS = (PRIMARY_ID, STRIX_ID, ORCA_INNER_ID, Q4_ID, ORNITH_ID)
# Inner matrix letters frozen by the chunks: vars grow p|s -> +c (C01) -> +o
# (C02) -> +q (C06), C08's sweep removes c again, and C09 adds n. The retired
# c is NEVER reused (frozen-table hygiene — a fresh letter names a fresh rung).
INNER_MATRIX_VARS = {
    "p": PRIMARY_ID, "s": STRIX_ID, "o": ORCA_INNER_ID, "q": Q4_ID, "n": ORNITH_ID,
}
# C02 gated-pack marker (manual-pack idempotency contract).
ORCA_PACK_MARKER = "/models/strata/.pack-orca"
# C09 claim-checkout migration: marker carries image-version + carry-N so a
# future bump re-fires. cf-141 C04 re-pin: the pair below IS the bumped
# literals (content-compared; the tail assert keeps the two spellings — this
# constant and the CF141 block at the file tail — one fact). The laws that
# consume them: test_strata_c09_ornith_carry.py (keyed + content-compared +
# ordering) and the runbook/host-prep marker surface.
CHECKOUT_MARKER = "/models/strata/.checkout-0.2.13-carry1"
CHECKOUT_MARKER_ID = "0.2.13-carry-1"
# Completeness marker for the GGUF-direct ornith leg (no .pack-* equivalent —
# q36 has no iq_pack step).
ORNITH_DL_MARKER = "/models/strata/.dl-ornith"

# C06 FINAL envelope, re-pinned at the executed on-target gate (2026-11-01,
# owner half-restore ruling), raised AGAIN by U14 the same day, and LOWERED
# 116Gi -> 110Gi by the 2026-11-10 envelope round — the container must die
# before the node (that day's SystemOOM crashloop), and no cap moved. The pod
# cgroup is ONE number for the whole strata container (STRATA_CGROUP_LIMIT —
# named Q4_* until U14, when the flagship started riding it too), and the
# declared caps are PER-RUNG inside it: 110592 primary, 103680 q4, 92160 orca.
# #1601's law is declared <= cgroup, and every leg keeps its own reserve: at
# 110Gi the cgroup sits ~8.75 GiB above the q4 cap and 2 GiB above the
# primary's. The conv term moved 8192 -> 16384
# when the claim-compiled HIP engine rejected --slot-save-path at argv (session
# files are CUDA-trial: the Round-3 caveat, now measured), which voided the
# trim's U8 compensation; --slot-save-path is a NEGATIVE pin (Q4_SESSION_FLAG).
# PLE: no --ple-io flag anywhere. --ple-io ram stays forbidden (the v0.2.7
# +28.8 GiB RAM-resident hazard, the 2026-10-29 OOM) and --ple-io mmap was
# RETIRED at U14 — the first boot measured the resolution as `direct` with the
# engine's own probe at 120,960 rows/s against a 15,000 warning line, so the
# documented ~11% would be paid for in page cache inside this same cgroup.
# (PRIMARY_MEMORY_LIMIT_MIB lives with the contract literals above — the
# PRIMARY_REQUIRED_PAIRS table needs it at definition time.)
Q4_MEMORY_LIMIT_MIB = 103680
STRATA_CGROUP_LIMIT = "110Gi"
Q4_CGROUP_LIMIT = STRATA_CGROUP_LIMIT  # deprecated alias; the cgroup is pod-level
Q4_CONV_CACHE_MIB = 16384
Q4_CONV_CACHE_SLOTS = 16
Q4_SESSION_FLAG = "--slot-save-path"
# The dir creation STAYS (fetch_models.sh owns it; one home only — the chart
# must not mkdir it): harmless bookkeeping for a possible future HIP session
# -files build, asserted by the init/image suites.
Q4_SESSION_DIR = "/models/strata/sessions"
Q4_FORBIDDEN_TOKENS = ("--batch", "--layer-split", "--ple-io")

# Inner model id -> the run-config file its cmd's --profile names. The
# strata-profile ConfigMap's key set must equal exactly this table for the
# arenas the inner config serves — a profile with no arena (or an arena with
# no profile) is a render bug, and the count grows one per landed rung.
INNER_PROFILE_FILES = {
    PRIMARY_ID: PROFILE_PRIMARY_FILE,
    STRIX_ID: PROFILE_STRIX_FILE,
    ORCA_INNER_ID: PROFILE_ORCA_FILE,
    Q4_ID: PROFILE_Q4_FILE,
    ORNITH_ID: PROFILE_ORNITH_FILE,
}

# C09 GGUF-direct ornith leg — live-verified tree read 2026-10-31 (anonymous):
# ungated repo (tree 200, gated=false), ranged resolve of a shard answers 206
# with GGUF magic and no Bearer challenge — the exact opposite premise of
# orca's gated trio, which is why the orn legs ride hf_fetch's ANON mode and
# HF_TOKEN must never touch them. Paths and sizes verbatim from that read.
HF_REPO_ORNITH = "unsloth/Ornith-1.5-122B-GGUF"
ORNITH_SHARD_PATHS = (
    "UD-Q4_K_XL/Ornith-1.5-122B-UD-Q4_K_XL-00001-of-00003.gguf",
    "UD-Q4_K_XL/Ornith-1.5-122B-UD-Q4_K_XL-00002-of-00003.gguf",
    "UD-Q4_K_XL/Ornith-1.5-122B-UD-Q4_K_XL-00003-of-00003.gguf",
)
ORNITH_SHARD_BYTES = (10942929, 49971099680, 29731729056)
ORNITH_TOTAL_BYTES = 79713771665  # == sum(ORNITH_SHARD_BYTES), R5 [C7]


def expected_profile_files(inner_ids) -> set:
    served = set(inner_ids)
    unknown = served - set(INNER_PROFILE_FILES)
    assert not unknown, f"inner arena ids outside the frozen profile table: {sorted(unknown)}"
    return {INNER_PROFILE_FILES[i] for i in served}


def profile_files(docs) -> set:
    """Key set of the rendered strata-profile ConfigMap (the run-config files
    the supervisor mounts)."""
    cm = by_name_kind(docs, "ConfigMap", CM_PROFILE)
    return set(cm.get("data") or {})


def profile_file_of(model: dict) -> str:
    """The /profile/<file> name a serve cmd points at ('' when absent)."""
    m = re.search(r"--profile\s+(\S+)", str(model.get("cmd") or ""))
    return m.group(1).rsplit("/", 1)[-1] if m else ""


def serve_path_secret_hits(docs) -> list[str]:
    """The C-A keyless law, scoped to the SERVE path: strata main container,
    the inner supervisor config, and every rendered run-config profile. cf-86
    C02 (R-d ruling) sanctions the hf-token Secret as a DOWNLOAD-ONLY consumer
    on the model-fetch init, so initContainers are deliberately NOT part of
    this scan — test_strata_orca_rung.py pins that exception's placement."""
    hits = []
    pod = strata_pod(docs)
    for ctr in pod["spec"].get("containers") or []:
        blob = yaml.safe_dump(ctr)
        hits += [f"container {ctr.get('name')}: {tok}" for tok in SECRET_CHAIN_TOKENS + ["HF_TOKEN"]
                 if tok in blob]
    cm_profile = by_name_kind(docs, "ConfigMap", CM_PROFILE)
    blob = yaml.safe_dump(cm_profile.get("data") or {})
    hits += [f"{CM_PROFILE}: {tok}" for tok in SECRET_CHAIN_TOKENS if tok in blob]
    hits += [f"inner config: {tok}" for tok in SECRET_CHAIN_TOKENS if tok in yaml.safe_dump(inner_config(docs))]
    return hits


# ---------------------------------------------------------------------------
# Environment gating
# ---------------------------------------------------------------------------


def env_ready() -> tuple[bool, str]:
    """Only TOOLING absence may skip a test; a missing render or failing helm
    run must stay RED and name its chunk."""
    if shutil.which("helm") is None:
        return False, "helm binary not on PATH (~/.local/bin/helm — export PATH; run-2 FRICTION)"
    return True, ""


def jsonschema_ready() -> tuple[bool, str]:
    try:
        import jsonschema  # noqa: F401
    except ImportError:
        return False, "jsonschema not installed (pip install jsonschema)"
    return True, ""


def read(path: Path, why: str) -> str:
    assert path.is_file(), f"{path.relative_to(REPO_ROOT)} missing — {why}"
    return path.read_text()


# ---------------------------------------------------------------------------
# Helm rendering (parent chart; OFF = defaults, ON = the seven flags)
# ---------------------------------------------------------------------------


def _values_file_arg(overlay: dict) -> list[str]:
    """Overlay values via a temp file (helm merges -f layers into chart
    values). File lives until the render completes — cleanup after run."""
    fd, p = tempfile.mkstemp(prefix="strata-test-", suffix=".yaml")
    with open(fd, "w") as fh:
        yaml.safe_dump(overlay, fh)
    return ["-f", p]


@functools.lru_cache(maxsize=None)
def _render_cached(release: str, sets_key: tuple, overlay_key: str) -> tuple:
    cmd = ["helm", "template", release, str(CHART_DIR)]
    tmp_path = None
    if overlay_key:
        tmp_path = _values_file_arg(yaml.safe_load(overlay_key))
        cmd += tmp_path
    for kv in sets_key:
        cmd += ["--set", kv]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    if tmp_path:
        Path(tmp_path[1]).unlink(missing_ok=True)
    if out.returncode != 0:
        raise AssertionError(
            f"helm template failed (release {release}, sets {sets_key}):\n{out.stderr}"
        )
    docs = tuple(d for d in yaml.safe_load_all(out.stdout) if d)
    return tuple(docs), out.stdout


DOMAIN_SET = ("domain=test.example.com",)


def render_off() -> tuple:
    """Default-OFF render — the exact plan-Commands command line."""
    return _render_cached(RELEASE, DOMAIN_SET, "")


def render_on(sets_extra: tuple = ()) -> tuple:
    """Fully ON render: domain + the seven flags (r2-C01 AC2)."""
    return _render_cached(RELEASE, DOMAIN_SET + SEVEN_FLAGS + sets_extra, "")


def render_on_overlay(overlay: dict, sets_extra: tuple = ()) -> tuple:
    """ON render with an extra values overlay (synthetic fixtures, e.g.
    rocrVisibleDevices retargets under the strata: values container)."""
    overlay_key = yaml.safe_dump(overlay, sort_keys=True)
    return _render_cached(RELEASE, DOMAIN_SET + SEVEN_FLAGS + sets_extra, overlay_key)


def render_subset(subset: tuple[str, ...]) -> tuple[int, str]:
    """Non-raising render with a PROPER SUBSET of the seven flags (plus
    domain): (returncode, stdout+stderr) — for the loud-fail guards."""
    cmd = ["helm", "template", RELEASE, str(CHART_DIR), "--set", "domain=test.example.com"]
    for f in subset:
        cmd += ["--set", f]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    return out.returncode, out.stdout + out.stderr


def service_strata_overlay() -> dict:
    doc = yaml.safe_load(SERVICE_VALUES.read_text())
    block = doc["llama-swap"]
    assert "strata" in block, (
        "services/gpu-ai/prod/values.yaml llama-swap block has no strata: sub-key — r2-C03 not landed"
    )
    return block["strata"]


def render_service_overlay(cluster: str = "gpu-ai") -> tuple:
    """Extract-and-render of the service's llama-swap block onto the parent
    chart under the REAL appset release name (gpu-ai-llama-swap). L.
    render_docs cannot serve here: it renders as release `llama-swap`, so
    every object name loses the cluster prefix — while the consolidated
    identity (gpu-ai-llama-swap-strata) the peers evidence pins IS what this
    render must produce. Returns (docs, raw stdout) for line-scoped scans."""
    block = yaml.safe_load(SERVICE_VALUES.read_text())["llama-swap"]
    docs_t, raw = _render_cached(RELEASE, DOMAIN_SET + (f"clusterName={cluster}",),
                                 yaml.safe_dump(block, sort_keys=True))
    return docs_t, raw


# ---------------------------------------------------------------------------
# Rendered-object extraction
# ---------------------------------------------------------------------------


def find_kind(docs, kind: str) -> list:
    return [d for d in docs if d.get("kind") == kind]


def by_name_kind(docs, kind: str, name: str):
    hits = [d for d in docs if d.get("kind") == kind
            and d.get("metadata", {}).get("name") == name]
    assert len(hits) == 1, f"{kind}/{name}: expected exactly one, got {len(hits)}"
    return hits[0]


def obj_ids(docs) -> set:
    return {(d.get("kind"), d.get("metadata", {}).get("name")) for d in docs}


def strata_pod(docs) -> dict:
    dep = by_name_kind(docs, "Deployment", STRATA_OBJECT_NAME)
    return dep["spec"]["template"]


def strata_container(docs) -> dict:
    return strata_pod(docs)["spec"]["containers"][0]


def strata_deployment(docs) -> dict:
    return by_name_kind(docs, "Deployment", STRATA_OBJECT_NAME)


def main_pod_containers(docs) -> dict[str, dict]:
    """Containers of the llama-swap MAIN pod, keyed by name — the mount-
    exactness comparison surface (r2-C01 AC3)."""
    pod = by_name_kind(docs, "Deployment", RELEASE)["spec"]["template"]
    return {c["name"]: c for c in pod["spec"]["containers"]}


def mount_triples(container: dict) -> list:
    return sorted((m["name"], m["mountPath"], bool(m.get("readOnly")))
                  for m in container.get("volumeMounts") or [])


def inner_config(docs) -> dict:
    cm = by_name_kind(docs, "ConfigMap", CM_CONFIG)
    return yaml.safe_load(cm["data"]["config.yaml"])


def profile_json(docs, filename: str) -> dict:
    """One run-config profile rendered VERBATIM as JSON (valid JSON is itself
    the red when it fails — run-1 AC5 lineage)."""
    cm = by_name_kind(docs, "ConfigMap", CM_PROFILE)
    assert filename in cm.get("data", {}), (
        f"ConfigMap {CM_PROFILE} has no data key {filename!r}; keys: {sorted(cm.get('data', {}))}"
    )
    return json.loads(cm["data"][filename])


def env_list(model: dict) -> list[str]:
    return [str(e) for e in (model.get("env") or [])]


def cmd_flag_tokens(cmd: str) -> list[str]:
    return re.findall(r"(?<![^\s])--[\w-]+", cmd)


def norm_ws(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def arg_pairs(profile: dict) -> list[tuple[str, str]]:
    """Flatten `args` (list of strings, each possibly a whole flag+value
    group) into (flag, value) pairs in order."""
    toks = []
    for a in profile.get("args") or []:
        toks += str(a).split()
    pairs = []
    for i, t in enumerate(toks):
        if t.startswith("--") and i + 1 < len(toks) and not toks[i + 1].startswith("--"):
            pairs.append((t, toks[i + 1]))
    return pairs


def arg_tokens(profile: dict) -> list[str]:
    toks = []
    for a in profile.get("args") or []:
        toks += str(a).split()
    return toks


def engine_exe_paths(text: str) -> set[str]:
    """Full exe paths of the contract form /opt/strata/components/engine/<label>/<binary>.
    The label dir is pinned; the FILENAME is whatever C01's build-log capture
    recorded in the container README — the seam tests compare chart literal to
    README literal, so nothing is invented here."""
    out = set()
    for m in re.finditer(
        re.escape(ENGINE_ROOT) + r"/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)", text
    ):
        if ENGINE_LABEL_RE.match(m.group(1)):
            out.add(f"{ENGINE_ROOT}/{m.group(1)}/{m.group(2)}")
    return out


# ---------------------------------------------------------------------------
# Matrix DSL expansion (r2-C01 inner solver alternation)
# ---------------------------------------------------------------------------
# llama-swap expands a set expression to DNF COMBOS: '&' joins vars into one
# combo, '|' alternates combos, '+name' inlines another set (skill: "(g | q |
# m) & v" → [g,v],[q,v],[m,v]; a combo listing two models admits their
# co-residency, only the requested model starts). Flat membership of the var
# references is the wrong bar for the C01-era "(p | s)" contract, and stays
# wrong for today's five-letter sets.main: the alternation names every arena
# while no combo may ever hold more than one.


_M_DSL_TOKEN = re.compile(r"&|\||\(|\)|\+[A-Za-z0-9_]+|[A-Za-z0-9_]+")
_M_DNF_CAP = 4096


def _m_tokens(expr: str) -> list[str]:
    return _M_DSL_TOKEN.findall(str(expr))


def _m_parse_expr(toks: list[str], i: int, sets: dict) -> tuple[list, int]:
    terms, i = _m_parse_and(toks, i, sets)
    while i < len(toks) and toks[i] == "|":
        rhs, i = _m_parse_and(toks, i + 1, sets)
        terms = terms + rhs
    return terms, i


def _m_parse_and(toks: list[str], i: int, sets: dict) -> tuple[list, int]:
    terms, i = _m_parse_term(toks, i, sets)
    while i < len(toks) and toks[i] == "&":
        rhs, i = _m_parse_term(toks, i + 1, sets)
        terms = [a | b for a in terms for b in rhs]
        assert len(terms) <= _M_DNF_CAP, f"DNF explosion ({len(terms)} combos) — malformed matrix?"
    return terms, i


def _m_parse_term(toks: list[str], i: int, sets: dict) -> tuple[list, int]:
    t = toks[i]
    if t == "(":
        terms, i = _m_parse_expr(toks, i + 1, sets)
        assert i < len(toks) and toks[i] == ")", "unbalanced parentheses in matrix expression"
        return terms, i + 1
    if t.startswith("+"):
        name = t[1:]
        assert name in sets, f"+{name} references an undefined matrix set"
        return _m_parse_expr(_m_tokens(sets[name]), 0, sets)
    return [frozenset({t})], i + 1


def matrix_expansions(cfg: dict) -> dict[str, list[set[str]]]:
    """Per matrix set: the DNF combos of MODEL IDs (vars resolved). An
    unresolved var token raises — the load-error class assert_matrix_closure
    pins for the outer config."""
    matrix = cfg.get("matrix") or {}
    vars_ = matrix.get("vars") or {}
    sets = matrix.get("sets") or {}
    out: dict[str, list[set[str]]] = {}
    for name, expr in sets.items():
        toks = _m_tokens(expr)
        terms, i = _m_parse_expr(toks, 0, sets)
        assert i == len(toks), f"matrix set {name}: unparsed trailing tokens in {expr!r}"
        combos = []
        for term in terms:
            unknown = term - set(vars_)
            assert not unknown, f"matrix set {name}: undefined vars {sorted(unknown)}"
            combos.append({vars_[v] for v in term})
        out[name] = combos
    return out


# ---------------------------------------------------------------------------
# Vendored v266 config schema (re-homed with the suite from run-1's
# standalone-chart test directory)
# ---------------------------------------------------------------------------


def v266_schema() -> dict:
    """Load + integrity-check the vendored schema before use. Provenance
    guard mirrors scripts/converter-source.json's pattern (recorded digest).
    v266 = the deployed llama-swap pin's schema — main-only keys would
    false-fail (run-1 RESEARCH 'Validation')."""
    raw = (SCHEMA_DIR / "config-schema.v266.json").read_bytes()
    prov = json.loads((SCHEMA_DIR / "PROVENANCE.json").read_text())
    digest = hashlib.sha256(raw).hexdigest()
    assert digest == prov["sha256"], (
        f"vendored schema drifted from PROVENANCE.json ({digest} != {prov['sha256']}) — "
        "re-fetch the v266 tag and record the new digest"
    )
    return json.loads(raw)


def schema_errors(cfg: dict, schema: dict | None = None) -> list:
    import jsonschema
    schema = schema if schema is not None else v266_schema()
    v = jsonschema.Draft7Validator(schema)
    return sorted(v.iter_errors(cfg), key=lambda e: str(list(e.absolute_path)))


def strip_legacy_performance_keys(cfg: dict) -> dict:
    """Pre-cf-77 divergence pin (carried from run-1): the outer config's
    `performance.enable` key predates this ticket on both clusters and the
    cf-77 runs forbid touching that block, so the outer-config schema gate
    runs with the subtree carved out. Carve-out + peers-subtree validation
    together still prove every peers spelling."""
    out = json.loads(json.dumps(cfg))
    out.pop("performance", None)
    return out


# ---------------------------------------------------------------------------
# Values-source readers (comments are invisible in loaded data)
# ---------------------------------------------------------------------------


def body_lines(text: str) -> list[tuple[int, str]]:
    """Numbered script lines that can execute — comment lines carry the
    staging rationale and NAME forbidden clients to forbid them, so invocation
    laws run over non-comment lines only (the C01 review's scoping)."""
    return [(n, ln) for n, ln in enumerate(text.splitlines())
            if not ln.strip().startswith("#")]


def staged_paths(script: str, fn: str, tier: str) -> dict:
    """The staging layout from one pack function's assignments (dir/pack/stem/
    shard paths), expanded with the quant tier the loop passes. Shared by the
    render-era and image-era pairing arms so the pairing law survives the C07
    lift without being re-derived differently on each side. A missing
    assignment raises — the layout changing shape must red, never silently
    vacate the law."""
    import re as _re

    body = _re.search(rf"^{fn}\(\) \{{\n(.*?)\n\}}$", script, _re.S | _re.M)
    assert body, f"no {fn} function in the staging script — the pack step is not landed where expected"
    block = body.group(1)

    def assign(name: str) -> str:
        m = _re.search(rf"^\s*{name}=(\S+)\s*$", block, _re.M)
        assert m, f"{fn} assigns no {name} — the staging layout changed shape, re-express this arm"
        return m.group(1)

    def expand(value: str, seen: dict) -> str:
        out = value.replace("$tierl", tier.lower()).replace("$tier", tier)
        for name, val in seen.items():
            out = out.replace(f"${name}", val)
        return out

    paths, order = {}, ("dir", "pack", "stem", "s1", "s2", "s3")
    for name in order:
        try:
            paths[name] = expand(assign(name), paths)
        except AssertionError:
            if name in ("s2", "s3"):
                continue  # a two-shard pack has no s3 and a one-shard pack no s2
            raise
    return paths


def values_region(text: str, key: str) -> str:
    """Raw source of one values key's block — from the key line to the next
    line at shallower-or-equal indent. Used where the WHY-comments THEMSELVES
    are contractual (toggles, VERIFY markers, runbook pointers)."""
    lines = text.splitlines()
    start = next((i for i, ln in enumerate(lines) if ln.strip().startswith(f"{key}:")), None)
    assert start is not None, f"{key}: not found in values source"
    indent = len(lines[start]) - len(lines[start].lstrip())
    end = next(
        (i for i in range(start + 1, len(lines))
         if lines[i].strip() and len(lines[i]) - len(lines[i].lstrip()) <= indent
         and not lines[i].lstrip().startswith("#")),
        len(lines),
    )
    return "\n".join(lines[start:end])


def dig(d, path: str):
    """Walk a dotted key path through nested dicts; returns (found, value).

    Real YAML keys may themselves contain dots (arena ids like
    `qwen3.8-flash-next-strata`), which a plain split-on-"." path can never
    resolve — so when the bare segment misses, the walk extends the segment
    with following parts until a key matches. Shortest match first keeps
    every dot-free path resolving exactly as the naive split did."""
    parts = path.split(".")
    cur = d
    i = 0
    while i < len(parts):
        if not isinstance(cur, dict):
            return False, None
        for j in range(i, len(parts)):
            key = ".".join(parts[i:j + 1])
            if key in cur:
                cur = cur[key]
                i = j + 1
                break
        else:
            return False, None
    return True, cur


def live_code_grep(needle: str) -> list[str]:
    """Repo-wide text search for `needle` over live surfaces only: services/,
    custom-values/, charts/, containers/, skills/, .github/. Excludes
    .agents/ (both plan folders are sanctioned history/plan references per
    r2-C02 AC3), the tests dir of THIS suite (its own negative pins embed
    needles), caches and binary/vendor blobs."""
    roots = [REPO_ROOT / p for p in
             ("services", "custom-values", "charts", "containers", "skills", ".github")]
    hits = []
    for root in roots:
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue
            s = str(path)
            if (f"{os.sep}tests{os.sep}" in s or "__pycache__" in s
                    or ".pytest_cache" in s or path.suffix in {".tgz", ".pyc", ".gz"}):
                continue
            if needle in path.read_text(errors="replace"):
                hits.append(str(path.relative_to(REPO_ROOT)))
    return hits


# ---------------------------------------------------------------------------
# cf-141 tuning frame (AD-141) — plan 2026/2026-11-cf-141-refactor-strata-…
#
# The era dirs are the ledger: a landed capture step is what flips era-scoped
# arms between a chunk's before-state and its after-state, so a dev edit and
# its capture round gate as one unit and a moved value whose step dir was
# never written stays red naming the missing step. The step sets and file
# membership below are owner rulings (Q1 the L2 pin, Q9 the 8-everywhere
# envelope with Q17(a) ship-at-the-pin, Q10 row-H, Q16 the experimental-flag
# posture, Q13(a)/Q15 the two-PR landing) — the captures prove the render
# matched the ruling, never the other way round.
# ---------------------------------------------------------------------------

TUNING_RUNBOOK = REPO_ROOT / ".agents" / "notes" / "strata-parallel-tuning-runbook.md"

CF141_PRE_ERA = "strata-profiles-cf141-pre"           # era-0 anchor: q4/orca (C02/C03 chain head)
CF141_ERA_L2 = "strata-profiles-cf141-l2"             # C02: delta exactly {env}
CF141_ERA_ROWH = "strata-profiles-cf141-rowh"         # C03: shape step {args, env, parallel}
CF141_ERA_STRIX8 = "strata-profiles-cf141-strix8"     # C03: delta {parallel}
CF141_ERA_ORCA8 = "strata-profiles-cf141-orca8"       # C03: delta {parallel}
CF141_ERA_Q4P8 = "strata-profiles-cf141-q4parallel8"  # C03: delta {parallel} (q4 step 2)
CF141_ERA_BUMP = "strata-profiles-cf141-bump"         # C04: the merged bump era

# Pinned step-set per cf-141 era dir (top-level run-config keys the step may
# move; row-H is the one sanctioned multi-key step — a SINGLE owner ruling
# (Q9+Q10) whose exact surface set is pinned, per DECISIONS round 2 "step
# kinds"). Anything else riding a step is red by this table.
CF141_ERA_STEP: dict[str, frozenset] = {
    CF141_ERA_L2: frozenset({"env"}),
    CF141_ERA_ROWH: frozenset({"args", "env", "parallel"}),
    CF141_ERA_STRIX8: frozenset({"parallel"}),
    CF141_ERA_ORCA8: frozenset({"parallel"}),
    CF141_ERA_Q4P8: frozenset({"parallel"}),
    CF141_ERA_BUMP: frozenset({"drafting"}),
}

# C04's bump is ONE merge (the ledger moves every version literal in one
# commit, and the drafting config obligation rides the same PR-2 state), so
# its era is one dir whose per-file step widens where the rung also moves:
# strix alone changes its packaged root too — {exe, lib_dirs} riding the
# {drafting} step (C04 chunks: "same dir or adjacent era ... test session
# picks the shape" — picked: merged, because the render between the two
# edits does not exist as a capturable state). The pure engine-re-pin era
# law (c07/c09 never carry a primary file) survives; the bump era carries
# every flash-next file because the bump arms drafting on all four.
CF141_ERA_STEP_FILE: dict[tuple[str, str], frozenset] = {
    (CF141_ERA_BUMP, PROFILE_STRIX_FILE): frozenset({"exe", "lib_dirs", "drafting"}),
}


def cf141_step_for(file: str, era_dir: str) -> frozenset:
    return CF141_ERA_STEP_FILE.get((era_dir, file), CF141_ERA_STEP[era_dir])

# Ordered era chain per rung profile file ((dir, owning chunk)); the anchor
# entries exist from plan approval on, later steps land with their chunk's
# capture round (§9.16 ritual). Ornith is absent on purpose: no step moves it.
CF141_ERA_CHAIN: dict[str, tuple[tuple[str, str], ...]] = {
    PROFILE_PRIMARY_FILE: ((CF141_ERA_ROWH, "C03"), (CF141_ERA_BUMP, "C04")),
    PROFILE_STRIX_FILE: ((CF141_ERA_STRIX8, "C03"), (CF141_ERA_BUMP, "C04")),
    PROFILE_ORCA_FILE: ((CF141_PRE_ERA, "anchor"), (CF141_ERA_ORCA8, "C03"),
                         (CF141_ERA_BUMP, "C04")),
    PROFILE_Q4_FILE: ((CF141_PRE_ERA, "anchor"), (CF141_ERA_L2, "C02"),
                      (CF141_ERA_Q4P8, "C03"), (CF141_ERA_BUMP, "C04")),
}

# The JSON files each cf-141 era dir may carry (cross-file purity: the
# engine-re-pin-no-primary law generalized — an era dir holding a file its
# step did not move is a smuggled second change).
CF141_ERA_FILES: dict[str, frozenset] = {
    CF141_PRE_ERA: frozenset({PROFILE_Q4_FILE, PROFILE_ORCA_FILE}),
    CF141_ERA_L2: frozenset({PROFILE_Q4_FILE}),
    CF141_ERA_ROWH: frozenset({PROFILE_PRIMARY_FILE}),
    CF141_ERA_STRIX8: frozenset({PROFILE_STRIX_FILE}),
    CF141_ERA_ORCA8: frozenset({PROFILE_ORCA_FILE}),
    CF141_ERA_Q4P8: frozenset({PROFILE_Q4_FILE}),
    CF141_ERA_BUMP: frozenset({PROFILE_PRIMARY_FILE, PROFILE_STRIX_FILE,
                               PROFILE_ORCA_FILE, PROFILE_Q4_FILE}),
}

# The shipped after-states, byte-pinned (values render AND note rows must
# agree with these at their era). Quoted strings are the engine contract:
# STRATA_MMQ_KQ reads getenv(...)[0]=='1' [RESEARCH 32], STRATA_PLE_AUTO_RAM
# likewise [26] — an int-form pin is a silent engine-side default.
CF141_Q4_ENV_ARMED = {"STRATA_MMQ_KQ": "1"}
CF141_PRIMARY_ENV_ARMED = {"STRATA_PLE_AUTO_RAM": "0"}
CF141_DRAFTING_VALUE = "mtp"
FLASH_NEXT_PROFILES = (PROFILE_PRIMARY_FILE, PROFILE_STRIX_FILE,
                       PROFILE_ORCA_FILE, PROFILE_Q4_FILE)

# Per-rung slot rulings — `parallel` LEFT the cross-rung byte-identical set
# by owner Q9 ("8 slots everywhere... crash it and scale back from there",
# 2026-11-10/11, plan-approved Q17(a)); each count is per-rung data carrying
# its own ruling so a later single-rung scale-back (parallel: 4) cannot
# violate a cross-rung law. The citation strings are contract: the envelope
# table arms print them and the runbook rows must match them.
CF141_PARALLEL_RULINGS: dict[str, tuple[int, str]] = {
    PROFILE_PRIMARY_FILE: (8, "Q9+Q10 row-H (owner 2026-11-10; conv 16384 + PLE-direct)"),
    PROFILE_STRIX_FILE: (8, "Q9 8-everywhere at the pin (owner 2026-11-10/11; boot-read gate applies)"),
    PROFILE_ORCA_FILE: (8, "Q9 8-everywhere at the pin (owner 2026-11-10/11; park refusals expected)"),
    PROFILE_Q4_FILE: (8, "Q9 supersedes a6e493b78's 4-slot ruling (owner 2026-11-10/11)"),
    PROFILE_ORNITH_FILE: (1, "q36 surface law survives Q9 (plan read re-confirmed by Q17; ornith is not a flash-next rung)"),
}

# The pre-envelope state (the C01/C02 waves' shipped truth, and every rung's
# scale-back target per the runbook ladder).
CF141_PARALLEL_PRE = {f: 4 for f in FLASH_NEXT_PROFILES} | {PROFILE_ORNITH_FILE: 1}

# The cross-rung engine-identity siblings after cf-141's law move
# (C03 task 2.1): per-node facts stay byte-identical, the slot count does
# not. test_strata_q4_rung.py's loop iterates exactly this set, and the
# envelope arms guard the membership.
CF141_SIBLING_KEYS = ("exe", "cwd", "lib_dirs", "backend", "gpu", "host")

# Bump-era literals (C04 lands them; PR-2). Version-free legs (claim-compiled
# exe paths, the supervisor pin, the services block) do NOT move here.
CF141_STRATA_VERSION = "0.2.13"
CF141_ENGINE_VERSION = "0.1.59"
CF141_ENGINE_HALO_LABEL = f"{CF141_ENGINE_VERSION}-linux-x86_64-hip-halo"
CF141_ENGINE_RX9070_LABEL = f"{CF141_ENGINE_VERSION}-linux-x86_64-hip-rx9070"
CF141_CLONE_TAG = f"v{CF141_STRATA_VERSION}"
CF141_FROM_TAGS = (f"{CF141_STRATA_VERSION}-rocm-gfx120x", f"{CF141_STRATA_VERSION}-rocm-gfx1151")
# Spelled here and at the CHECKOUT_MARKER constant above; the tail assert keeps
# the two spellings one fact (C04 flips both, era chain as the ledger).
CF141_CHECKOUT_MARKER = "/models/strata/.checkout-0.2.13-carry1"
CF141_CHECKOUT_MARKER_ID = "0.2.13-carry-1"
CF141_PREVIOUS_STRATA_VERSION = "0.2.9"
CF141_PREVIOUS_ENGINE_VERSION = "0.1.55"
CF141_SUPERVISOR_TAG = "unified-vulkan-266"

# Host-budget arithmetic (RESEARCH R2-C/R2 tables; the KV law 13,728 B/token
# int8 = 13 KV-bearing layers x 1,056 B survives at BOTH pins [57][58][59]).
# The arena terms are the [M-node] measured values; ~6 GiB is the supervisor +
# misc term the rungs-research budget law counts. These numbers are what the
# runbook's envelope rows must reproduce — the derivation arm recomputes them
# from the RENDER (parallel/conv/cgroup are rendered facts; the arena bytes
# are the measured constants), so a budget sentence is proven, not echoed.
CF141_KV_BYTES_PER_TOKEN = 13728
CF141_FLASHNEXT_CTX = 262144
CF141_RUNG_ARENA_GIB = {"primary": 46.84, "orca": 57.7, "q4": 71.73}
CF141_BUDGET_MISC_GIB = 6.0


def cf141_host_total_gib(rung: str, parallel: int, conv_mib: int,
                         ctx: int = CF141_FLASHNEXT_CTX) -> float:
    """(N+1) full-context pinned-KV budget law: arena + (parallel+1) x ctx x
    13,728 B + conversation cache + ~6 GiB, in GiB."""
    kv_gib = (parallel + 1) * ctx * CF141_KV_BYTES_PER_TOKEN / 1024**3
    return CF141_RUNG_ARENA_GIB[rung] + kv_gib + conv_mib / 1024 + CF141_BUDGET_MISC_GIB


# C03's envelope step per rung file (ornith None: no step raises or moves it;
# the scale-back of ONE rung re-pins CF141_PARALLEL_RULINGS' row — TEST_SPEC).
CF141_ENVELOPE_STEP: dict[str, str | None] = {
    PROFILE_PRIMARY_FILE: CF141_ERA_ROWH,
    PROFILE_STRIX_FILE: CF141_ERA_STRIX8,
    PROFILE_ORCA_FILE: CF141_ERA_ORCA8,
    PROFILE_Q4_FILE: CF141_ERA_Q4P8,
    PROFILE_ORNITH_FILE: None,
}


def cf141_era_landed(file: str, era_dir: str) -> bool:
    return (EVIDENCE_DIR / era_dir / file).is_file()


def cf141_chain_present(file: str) -> list[str]:
    """The rung's contiguous landed chain (anchor included when present); a
    gap stops the walk — the later step is not half-trusted. Rungs with no
    cf-141 chain (ornith) walk empty."""
    out = []
    for d, _chunk in CF141_ERA_CHAIN.get(file, ()):
        if cf141_era_landed(file, d):
            out.append(d)
        else:
            break
    return out


def cf141_era_tip(file: str) -> str | None:
    chain = cf141_chain_present(file)
    return chain[-1] if chain else None


def cf141_next_step(file: str) -> tuple[str, str] | None:
    """First (dir, chunk) of the rung's chain not on disk yet — the name a
    chain-arm red must print."""
    for d, chunk in CF141_ERA_CHAIN.get(file, ()):
        if not cf141_era_landed(file, d):
            return d, chunk
    return None


def cf141_envelope_landed(file: str) -> bool:
    """True once C03's step for this rung has captured — the gate every
    per-rung before/after leg reads (the era chain is the ledger)."""
    step = CF141_ENVELOPE_STEP[file]
    return step is not None and cf141_era_landed(file, step)


def era_delta(prev: dict, nxt: dict) -> frozenset:
    """Top-level run-config keys whose values differ between two captures."""
    return frozenset(k for k in set(prev) | set(nxt) if prev.get(k) != nxt.get(k))


def render_parallel_map(docs) -> dict[str, int]:
    return {file: profile_json(docs, file).get("parallel")
            for file in INNER_PROFILE_FILES.values()}


def parallel_violations(rendered: dict, rulings: dict) -> list[str]:
    """(rung, wanted, got, citation) lines for a per-rung parallel table
    mismatch. Driven by the ruling table, never a cross-rung loop — a
    scale-back of ONE rung is a re-pin of the table row, not a law break."""
    out = []
    for file, (want, citation) in rulings.items():
        got = rendered.get(file)
        if got != want:
            out.append(f"{file}: parallel {got!r}, ruling table says {want!r} ({citation})")
    return out


def sibling_divergences(a: dict, b: dict, keys=CF141_SIBLING_KEYS) -> list[str]:
    """Cross-rung identity over the engine-sibling keys only; divergent
    `parallel` is NOT a violation here by owner Q9 (cf-141 C03 law move)."""
    return [f"{k}: {a.get(k)!r} != {b.get(k)!r}" for k in keys if a.get(k) != b.get(k)]


def env_pin_violations(env, want: dict) -> list[str]:
    """Exact-dict + JSON-string-value check for a profile-layer env pin
    (keys-vs-values class: an int 1 or an extra key each fail by name)."""
    if not isinstance(env, dict):
        return [f"profile env is {env!r}, want the exact dict {want!r}"]
    out = []
    if set(env) != set(want):
        out.append(f"env keys {sorted(env)} != the pinned {sorted(want)}")
    for k, v in want.items():
        if env.get(k) != v:
            out.append(f"env[{k!r}] = {env.get(k)!r}, want the JSON string {v!r}")
    return out


def drafting_violations(profiles: dict[str, dict]) -> list[str]:
    """C04's config obligation as a pure law: "drafting": "mtp" on exactly
    the four flash-next profiles, no drafting key on the ornith q36 surface
    (closed-world check). Shared by the render arm and the non-vacuity
    probes so the mutant and the live check cannot drift apart."""
    out = []
    for file in FLASH_NEXT_PROFILES:
        prof = profiles.get(file) or {}
        if prof.get("drafting") != CF141_DRAFTING_VALUE:
            out.append(f"{file}: drafting {prof.get('drafting')!r}, want the string "
                       f"{CF141_DRAFTING_VALUE!r} (0.2.13 shapes drafting unconditionally [79])")
    if "drafting" in (profiles.get(PROFILE_ORNITH_FILE) or {}):
        out.append(f"{PROFILE_ORNITH_FILE}: drafting key rides the q36 surface — its ruling "
                   "is separate (DECISIONS round 2)")
    return out


def flavor_pair_violations(tags: list[str]) -> list[str]:
    """The ledger pair as a pure law: exactly the two bumped flavor tags, no
    half-moved state (a two-stage image with one flavor of each release)."""
    want = sorted(CF141_FROM_TAGS)
    return [] if sorted(tags) == want else [f"FROM strata tags {sorted(tags)} != the bumped pair {want}"]


def marker_pair_violations(script: str) -> list[str]:
    """Bump-era marker law as a pure check: both marker literals at the
    0.2.13 pair and the retired 0.2.9 spelling gone (content-compared, so
    the first boot re-fires the migration)."""
    out = []
    if f"CHECKOUT_MARKER={CF141_CHECKOUT_MARKER}" not in script:
        out.append(f"no CHECKOUT_MARKER={CF141_CHECKOUT_MARKER} assignment")
    if f"CHECKOUT_MARKER_ID={CF141_CHECKOUT_MARKER_ID}" not in script:
        out.append(f"no CHECKOUT_MARKER_ID={CF141_CHECKOUT_MARKER_ID} assignment")
    if "0.2.9-carry" in script:
        out.append("a retired 0.2.9-carry marker literal survives")
    return out


@functools.lru_cache(maxsize=1)
def chart_values_dict() -> dict:
    """The chart values parsed — the note validator resolves arm-table
    key-paths against this (AC3's 'every row's key-path resolves')."""
    return yaml.safe_load((CHART_DIR / "values.yaml").read_text())


def provenance_violations(dirpath: Path, files) -> list[str]:
    """An era dir's PROVENANCE.md must name every capture file it carries
    (JSON set == `files`), record each file's live-recomputed sha256, state
    the double-capture, and carry a date + commit ref (a copied-not-re-read
    digest has no provenance to verify — the C04 non-vacuity class)."""
    out = []
    prov = dirpath / "PROVENANCE.md"
    if not prov.is_file():
        return [f"{dirpath.name}/PROVENANCE.md missing — era captures are provenance-first"]
    text = prov.read_text()
    present = {p.name for p in dirpath.glob("*.json")}
    if present != set(files):
        out.append(f"{dirpath.name} carries {sorted(present)}, expected {sorted(files)}")
    for name in sorted(files):
        fp = dirpath / name
        if not fp.is_file():
            out.append(f"{dirpath.name}/{name} missing")
            continue
        digest = hashlib.sha256(fp.read_bytes()).hexdigest()
        if digest not in text:
            out.append(f"{dirpath.name}/{name}: sha256 {digest} not recorded in PROVENANCE "
                       "(re-read live vs a copied digest)")
    if "double-capture" not in text.lower():
        out.append(f"{dirpath.name}/PROVENANCE.md does not state the double-capture determinism")
    if not re.search(r"\d{4}-\d{2}-\d{2}", text):
        out.append(f"{dirpath.name}/PROVENANCE.md has no capture date")
    if not re.search(r"`?[0-9a-f]{7,40}`?", text):
        out.append(f"{dirpath.name}/PROVENANCE.md names no commit/tree ref")
    return out


# The PROFILE_FIXTURE_ERA anchor entries for q4/orca spell the anchor dir as
# a literal (the map is defined before this block); this import-time check
# keeps the two spellings one fact.
assert PROFILE_FIXTURE_ERA[PROFILE_Q4_FILE] == CF141_PRE_ERA
assert PROFILE_FIXTURE_ERA[PROFILE_ORCA_FILE] == CF141_PRE_ERA


def cf141_expected_profile_env(file: str) -> dict:
    """The profile-layer env the era chain says this rung renders with: the
    chain-tip capture's env (armed states are DATA: q4 gets STRATA_MMQ_KQ at
    the cf141-l2 step, the primary gets STRATA_PLE_AUTO_RAM at row-H), ornith
    — the one rung with no capture — stays {} by its surface state."""
    if file == PROFILE_ORNITH_FILE:
        return {}
    return profile_fixture(file).get("env") or {}


# The C04-era spellings are one fact across the two blocks of this file.
assert CHECKOUT_MARKER == CF141_CHECKOUT_MARKER
assert CHECKOUT_MARKER_ID == CF141_CHECKOUT_MARKER_ID


def ledger_pair_violations(readme: str, tags, retired_digests, engine_version: str) -> list[str]:
    """The bump-era tag→digest ledger as a pure STRUCTURE law (offline by
    doctrine — the digest VALUES are live re-reads the landing round owes the
    ledger's recorded method: anonymous token + manifest HEAD): every bumped
    flavor tag pairs within its ledger window with a 64-hex digest that is
    NOT one of the retired pair (copied-not-re-read), the dated re-read is
    recorded, and the com.strata.engine label names the engine version.
    Shared with test_strata_c09_ornith_carry.py; the containers suite keeps a
    deliberate twin (the two suites cannot import each other by design)."""
    out = []
    for tag in tags:
        if tag not in readme:
            out.append(f"ledger never names the bumped flavor tag {tag}")
            continue
        idx = readme.index(tag)
        window = readme[max(0, idx - 300): idx + 800]
        digests = set(re.findall(r"sha256:[0-9a-f]{64}", window))
        if not digests:
            out.append(f"{tag}: no 64-hex digest paired in its ledger window")
        elif digests <= set(retired_digests):
            out.append(f"{tag}: every digest by its row is a retired pair value — "
                       "copied, not re-read")
    if not re.search(r"com\.strata\.engine[^\n]{0,300}" + re.escape(engine_version)
                     + r"|" + re.escape(engine_version) + r"[^\n]{0,300}com\.strata\.engine",
                     readme, re.S):
        out.append(f"no com.strata.engine {engine_version} label proof recorded")
    if not re.search(r"(anonymous token|manifest HEAD|re-read)[^\n]{0,200}\d{4}-\d{2}-\d{2}"
                     r"|\d{4}-\d{2}-\d{2}[^\n]{0,200}(re-read|anonymous token|manifest HEAD)",
                     readme):
        out.append("no dated re-read record for the new pair")
    return out
