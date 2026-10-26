# C03 regime contract — flash-next family renders in the mmap placement
# (ticket 2026/2026-10-debug-flash-next-vulkan-oom, chunks/C03.md AC1/AC4).
#
# Why effective-cmd assertions: llama-swap expands `use:` macros only at
# config load, so the raw render may legitimately carry placement inside any
# macro name the dev picks. The contract is the EXPANDED stream (C03 "dev
# picks the cleanest [mechanism] that renders the exact target cmd") —
# asserted via llama_swap_testlib.effective_cmd, the harness's macros.go port.
#
# Skipped when the helm binary or the chart's app-template dependency is
# missing (same gate as test_render.py; the skip is the contract-prescribed
# degradation — plan Commands NOTE, FRICTION 2026-10-26).

from __future__ import annotations

import os
import re
import urllib.request

import pytest

import llama_swap_testlib as L

_ok, _reason = L.helm_ready()

FN = L.FLASHNEXT_FAMILY_IDS
EXPERT_OT = r"\.ffn_.*_exps\.=CPU"

# Gate-2 MTP shape (the first-cut absence window closed through C04's gate 2:
# hc-layout verdict EVIDENCE.md §5 + journal-clean load §13.2-4 + operator
# DECISIONS GO; chart commit eb0a0cf92). The draft sidecar arrives via -hfd,
# the spec block renders --spec-type/--spec-draft-n-max literals with no
# p-min; orca-q6 carries the spec ALONE — embedded MTP is the qwen38-orca
# publisher convention, see the probe-on-miss note in values.yaml.
FN_ORCA = "qwen3.8-flash-next-orca-q6"


def _skip_without_helm() -> None:
    # Degradation contract (plan Commands NOTE): no helm => a loud skip, never
    # a vacuous pass. Checked at run time so the YAML-only tests keep running.
    if not _ok:
        pytest.skip(_reason)


def _expanded(cluster: str, mid: str) -> str:
    _skip_without_helm()
    cfg = L.rendered_config(cluster)
    model = L.all_models_of(cfg).get(mid)
    assert model is not None, f"{cluster}: {mid} not rendered at all"
    assert not L.is_echo_cmd(model["cmd"]), (
        f"{cluster}/{mid}: rendered as fail-fast echo — AC1 requires the q3 "
        "test rung live (C02 was skipped, nothing to un-disable, nothing to re-disable)"
    )
    return L.effective_cmd(cfg, mid)


def _flag_values(cmd: str, flag: str) -> list[str]:
    """All values passed to `flag`, in stream order, pair or =-form.
    llama.cpp is rightmost-wins, so the effective value is [-1]."""
    toks = list(L.cmd_tokens(cmd).elements())
    vals = []
    for i, t in enumerate(toks):
        if t == flag and i + 1 < len(toks):
            vals.append(toks[i + 1])
        elif t.startswith(f"{flag}="):
            vals.append(t.split("=", 1)[1])
    return vals


# --- AC1: the mmap regime, per family rung, on the expanded stream ----------


@pytest.mark.parametrize("mid", FN)
def test_c03_ac1_load_mode_mmap_and_never_none(mid):
    cmd = _expanded("gpu-ai", mid)
    vals = _flag_values(cmd, "--load-mode")
    assert "none" not in vals, (
        f"{mid}: --load-mode none still in the expanded cmd {vals} — the GTT-pinned "
        "regime is the bug C03 removes (plan Root cause; a rightmost-wins shadow "
        "does NOT satisfy AC1's 'contains no --load-mode none')"
    )
    assert vals and vals[-1] == "mmap", (
        f"{mid}: effective --load-mode is {vals[-1] if vals else None!r}, contract is 'mmap' "
        "(C03 branch A: file-backed CPU_Mapped placement instead of Vulkan_Host GTT pins)"
    )


@pytest.mark.parametrize("mid", FN)
def test_c03_ac1_fit_off_present(mid):
    cmd = _expanded("gpu-ai", mid)
    vals = _flag_values(cmd, "--fit")
    assert vals and vals[-1] == "off", (
        f"{mid}: --fit is {vals[-1] if vals else None!r}, contract is explicit 'off' "
        "(skip the LOAD_MODE_NONE dry-loads that mis-account GTT — RESEARCH §4.2(c))"
    )


@pytest.mark.parametrize("mid", FN)
def test_c04_gate2_mtp_draft_spec_readded(mid):
    """Replaces test_c03_ac1_first_cut_has_no_mtp_draft_or_spec (TEST_SPEC
    §8.2 gate-2 ledger): C03's first cut rendered no draft/spec, and C04's
    gate 2 re-added them (EVIDENCE.md §13.7). Contract is the re-added shape
    exactly as landed in eb0a0cf92: draft-mtp spec with draft_n_max 2 on all
    five rungs, and the unsloth sidecar on -hfd for the four unsloth rungs;
    orca-q6 stays spec-only (embedded MTP, probe-on-miss)."""
    cmd = _expanded("gpu-ai", mid)
    toks = set(L.cmd_tokens(cmd))
    st = _flag_values(cmd, "--spec-type")
    assert st and st[-1] == "draft-mtp", (
        f"{mid}: --spec-type is {st[-1] if st else None!r}, gate-2 contract is 'draft-mtp'"
    )
    nmax = _flag_values(cmd, "--spec-draft-n-max")
    assert nmax and nmax[-1] == "2", (
        f"{mid}: --spec-draft-n-max is {nmax[-1] if nmax else None!r}, gate-2 spec block carries draft_n_max: 2"
    )
    assert "--spec-draft-p-min" not in toks, (
        f"{mid}: --spec-draft-p-min rendered — gate-2 re-add restored the exact removed lines, which carry no p-min (EVIDENCE.md §13.7)"
    )
    hfd = _flag_values(cmd, "-hfd")
    if mid == FN_ORCA:
        assert not hfd, (
            f"{mid}: -hfd {hfd[-1] if hfd else None!r} rendered — orca rides embedded MTP; wiring a "
            "standalone sidecar is a contract change, re-home it through the test session"
        )
    else:
        assert hfd and hfd[-1] == L.C04_FLASHNEXT_DRAFT, (
            f"{mid}: -hfd is {hfd[-1] if hfd else None!r}, gate-2 sidecar ref is {L.C04_FLASHNEXT_DRAFT!r}"
        )


@pytest.mark.parametrize("mid", FN)
def test_c03_ac1_ngl99_and_expert_offload_leg(mid):
    """AC1's leg is the -ot regex OR C01's justified --n-cpu-moe substitute —
    both accepted, macro-name-agnostic because this reads the expanded stream."""
    cmd = _expanded("gpu-ai", mid)
    ngl = _flag_values(cmd, "-ngl")
    assert ngl and ngl[-1] == "99", f"{mid}: -ngl is {ngl[-1] if ngl else None!r}, contract 99"
    ot = _flag_values(cmd, "-ot")
    ncm = _flag_values(cmd, "--n-cpu-moe")
    if ot:
        assert ot[-1] == EXPERT_OT, (
            f"{mid}: -ot value {ot[-1]!r} is neither the catalog placement regex "
            f"{EXPERT_OT!r} nor replaced by --n-cpu-moe (C03 AC1 disjunction)"
        )
    else:
        assert ncm and re.match(r"^\d+$", ncm[-1]), (
            f"{mid}: no expert-offload leg — expected -ot {EXPERT_OT!r} or "
            f"--n-cpu-moe N (the #27836 substitute allowed by AC1 per C01's tensor dump)"
        )


def test_c03_ac1_q3_rung_specifics():
    """The q3 TEST RUNG additionally keeps its approved shard ref and ttl 300 —
    the regime change must not disturb the data identity of the rung C04 loads."""
    _skip_without_helm()
    cfg = L.rendered_config("gpu-ai")
    m = L.all_models_of(cfg)["qwen3.8-flash-next-q3"]
    assert L.cmd_flag_value(m["cmd"], "-hf") == L.C04_HF_REFS["qwen3.8-flash-next-q3"], (
        "q3: -hf ref moved off the approved shard list — C03 changes placement, not the model"
    )
    assert m.get("ttl") == 300, f"q3: ttl {m.get('ttl')!r}, guardrail pins 300 (C03 'keep every guardrail')"


# --- AC4 (C02-skipped branch): nothing gains a disabled stub ----------------


def test_c03_ac4_service_layer_carries_no_flash_next_disable():
    """C02 was SKIPPED at approval (DECISIONS 2026-10-26: debug-live), so the
    AC4 "un-disable q3 only" bookkeeping is vacuous — the durable contract is
    that nobody introduces containment during C03: every flash-next family
    stays enabled and no flash-next ID gains a `disabled:` in the gpu-ai
    models layer. Needs only YAML — runs even without helm."""
    overlay = L.service_overlay("gpu-ai")
    cfg_layer = overlay.get("config") or {}
    fams = cfg_layer.get("families") or {}
    for fam in ("qwen3.8-flash-next", "qwen3.8-flash-next-orca"):
        assert (fams.get(fam) or {}).get("enabled") is True, (
            f"{fam}: gpu-ai family enablement lost — rungs must stay live (operator's debug-live choice)"
        )
    models_layer = cfg_layer.get("models") or {}
    stubs = [mid for mid in models_layer if mid in FN and "disabled" in (models_layer[mid] or {})]
    assert not stubs, f"flash-next ids with a disabled: stub in gpu-ai values: {stubs}"


# --- AC5: flag-existence audit against the pinned b11810 build --------------


@pytest.mark.skipif(
    os.environ.get("RUN_FLAG_AUDIT") != "1",
    reason=(
        "evidence gate: RUN_FLAG_AUDIT=1 audits --load-mode/--fit/--no-host "
        "existence in llama.cpp@b11810 common/arg.cpp (network; plan Commands "
        "'flag-existence audit' — must run before dev uses the flags)"
    ),
)
def test_c03_ac5_flags_exist_in_b11810():
    url = "https://api.github.com/repos/ggml-org/llama.cpp/contents/common/arg.cpp?ref=b11810"
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github.raw+json"})
    try:
        src = urllib.request.urlopen(req, timeout=60).read().decode()
    except Exception as exc:  # noqa: BLE001 - the gate distinguishes "unverifiable" from "absent"
        pytest.skip(f"b11810 arg.cpp unreachable ({exc}) — retry or audit offline per plan Commands")
    for flag in ("--load-mode", "--fit", "--no-host"):
        assert f'"{flag}"' in src, (
            f"{flag} not defined in b11810 arg.cpp — C03 AC5: a used flag missing from the "
            "build is a HARD FAIL of the chunk, not a silent skip"
        )
    for mode in ("MMap", "mmap"):
        if mode in src:
            break
    else:
        pytest.fail("--load-mode mmap value spelling not found in b11810 arg.cpp — verify manually")
