# r2-C04 doc-completeness contract — the anti-amnesia check, re-authored for
# the keyless consolidated shape (run-2 chunks/C04.md; docs are the runbook
# note + the PARENT chart README after the re-home).
#
# Surviving run-1 gates must keep their tokens verbatim ("Surviving gates kept
# verbatim" — C04 task 1); the secret chain's tokens must now be ABSENT; the
# new-shape tokens (keyless, swap sequencing, consolidated Service name) must
# be PRESENT. RED until r2-C04 rewrites the prose.

from __future__ import annotations

import re

import strata_testlib as S

DOC_PATHS = (S.RUNBOOK_NOTE, S.PARENT_README)


def _union_text() -> str:
    """Both docs joined; each must exist (C04 task 1 + the parent-README
    re-home task)."""
    return "\n".join(S.read(p, "r2-C04 docs deliverable") for p in DOC_PATHS)


# (token, rationale) — every entry names the plan/chunk line it pins.
REQUIRED_TOKENS: list[tuple[str, str]] = [
    # — host-prep + enablement gates (run-1 survivors, kept verbatim per C04) —
    ("ttm.pages_limit=29360128", "GRUB/sdbootutil cmdline target value"),
    ("ttm.page_pool_size=29360128", "cmdline pair partner"),
    ("sdbootutil", "the cmdline mechanism itself"),
    ("amd_iommu=off", "cmdline item"),
    ("iommu=pt", "tradeoff note"),
    ("20251125", "linux-firmware version to avoid — MES 0x83"),
    ("UMA", "BIOS carve-out gate"),
    ("ReBAR", "BIOS Above-4G/ReBAR gate"),
    ("ASPM", "BIOS power gate"),
    ("16GT/s", "OCuLink x4 link-speed check"),
    ("lspci", "link + device-ID preflight command"),
    ("rocminfo", "ROCR_VISIBLE_DEVICES index resolution"),
    ("ROCR_VISIBLE_DEVICES", "device-retarget values path"),
    ("getent group", "render/video numeric GIDs -> supplementalGroups"),
    ("supplementalGroups", "the values key the GIDs feed"),
    ("AppArmor", "MAC-mode assumption to confirm on-target"),
    ("LimitNOFILE", "k3s systemd drop-in"),
    ("LimitMEMLOCK", "drop-in partner; pinned-arena memlock"),
    ("1048576", "LimitNOFILE target value"),
    ("infinity", "LimitMEMLOCK=infinity"),
    ("#2399", "nofile raise still open — why the wrapper/drop-in stay"),
    ("#2398", "found the fd ceiling, closed unmerged"),
    ("524288", "ulimit -n wrapper value = the PR's hard-limit figure"),
    ("ulimit", "in-container ulimit -n/-l proof points"),
    ("hipMemCreate", "the PR's fd-experiment failure mode at soft 1024"),
    ("THP", "transparent huge pages gate"),
    ("#771", "THP issue reference"),
    # — on-target gates (kept; the Bitwarden pre-sync rung is GONE) —
    ("--plan --output json", "the R1 pre-sync reconciliation command"),
    ("strata serve", "the serve CLI the gate runs"),
    ("expert-cache", "the --plan gate names which shipped values it finalizes"),
    ("unloadTimeout", "the binding stop constraint to prove timed"),
    ("POST /api/models/unload", "inner escape hatch + timed-unload proof endpoint"),
    ("strata bench run", "acceptance protocol command"),
    ("standard-v1", "bench suite name"),
    ("dmesg", "watch source for 128K/200K needle runs"),
    ("STRATA_KV_GROW=1", "the documented kv-grow env alias"),
    ("--gpu-roles", "deferred split-mode pointer"),
    ("--layer-split", "deferred split-mode pointer"),
    ("TheRock", "2B source-build escalation facts"),
    ("tune_hipblaslt", "self-tune path for the missing gfx1201 table"),
    ("100401", "hipBLASLt version the table question turns on"),
    ("#1128", "kv-grow trim risk WITHOUT the void mitigation (R4)"),
    ("#1250", "page-cache drop_caches note on the shared claim"),
    ("drop_caches", "the #1250 mitigation command"),
    ("#1715", "Strix 128GB expert-cache OOM fix-class"),
    ("#2706", "HC_UPMIX split hazard — strix log-check"),
    ("#2257", "the RollingUpdate overlap class behind strategy: Recreate"),
    ("MemAvailable", "pre-sync free-RAM check"),
    ("allocatable", "node allocatable schedule check"),
    ("96Gi", "the strata pod request the pre-sync math runs against"),
    ("trio", "RAM law: first Strata request only with the llama.cpp trio idle"),
    # — r2 new-shape tokens (C04 task: keyless + swap sequencing + identity) —
    ("keyless", "C-A: the keyless confirmation replaces the enforcement probe"),
    ("strata cold", "swap precondition: first request needs trio idle AND strata cold"),
    ("gpu-ai-strata", "the pruned standalone Application, named in the swap sequence"),
    ("gpu-ai-llama-swap-strata", "the consolidated Service/Deployment identity"),
    ("blip", "Q-B: the accepted seconds-blip on the strata route"),
    ("seven keys", "enable-flags paragraph: the seven flags flip together"),
    ("#3421", "the manual-bump digest ledger's WHY (re-homed with the ledger)"),
]

REQUIRED_PATTERNS: list[tuple[str, str]] = [
    (r"135[\u2013-]160", "/models/strata capacity budget 135–160 GB, either dash (run-1 RESEARCH §4)"),
    (r"getenforce|aa-status", "MAC-mode check commands"),
    (r"rpm -q|rpm -qa|Tumbleweed", "kernel/firmware package preflight"),
    (r"one sync|single sync", "swap sequencing: prune + re-render in ONE sync (Q-B)", ),
    (r'api_key[^A-Za-z\n]{0,8}none', "the shipped keyless default named in docs (C-A)"),
]

# Tokens the keyless ruling (C-A) deletes from the prose — an appearance is
# amnesia of the ruling, not documentation.
FORBIDDEN_TOKENS: list[tuple[str, str]] = [
    ("PENDING-OPERATOR", "the retired Bitwarden placeholder (C-A deletes the human step)"),
    ("strata-api-key", "the retired ExternalSecret name"),
]


def _occurrence_lines(token: str) -> list[str]:
    out = []
    for p in DOC_PATHS:
        text = S.read(p, "r2-C04 runbook deliverable")
        out += [ln for ln in text.splitlines() if token in ln]
    return out


def test_c04_required_tokens_present():
    text = _union_text()
    missing = [f"  {t}: {why}" for t, why in REQUIRED_TOKENS if t not in text]
    assert not missing, "runbook amnesia — token (rationale):\n" + "\n".join(missing)


def test_c04_required_patterns_present():
    text = _union_text()
    missing = [pat for pat, why, *_ in REQUIRED_PATTERNS if not re.search(pat, text, re.I)]
    assert not missing, f"patterned tokens missing: {missing}"


def test_c04_forgotten_secret_tokens_absent():
    offenders = []
    for tok, why in FORBIDDEN_TOKENS:
        for p in DOC_PATHS:
            text = S.read(p, "r2-C04 docs deliverable")
            if tok in text:
                offenders.append(f"{p.name}: {tok} ({why})")
    assert not offenders, "C-A deleted the secret chain; prose still speaks it:\n" + "\n".join(offenders)


def test_c04_strand_design_language_gone():
    """The "strand" vocabulary described the run-1 fail-fast gate; the keyless
    shape has no strand mechanism, so the word must not survive in these
    docs."""
    hits = [ln for ln in _occurrence_lines("strand") + _occurrence_lines("Strand")
            if re.search(r"\bstrands?\b|\bSTRAND", ln)]
    assert not hits, "strand-design language survived C-A's deletion:\n" + "\n".join(hits)


def test_c04_bitwarden_only_in_non_strata_context():
    """The repo keeps Bitwarden for OTHER services (hf-token); any Bitwarden
    line in the strata docs must be visibly about that other consumer."""
    NON_STRATA = re.compile(r"hf-token|HuggingFace|gated|other service|not strata", re.I)
    offenders = []
    for p in DOC_PATHS:
        text = S.read(p, "r2-C04 docs deliverable")
        offenders += [ln.strip()[:90] for ln in text.splitlines()
                      if re.search(r"bitwarden", ln, re.I) and not NON_STRATA.search(ln)]
    assert not offenders, f"Bitwarden named in a strata context (C-A removed it):\n" + "\n".join(offenders)


def test_c04_no_dangling_standalone_chart_paths():
    """C04 sweep: prose points at the PARENT chart paths, never the retired
    standalone dir (composed needle — see strata_testlib for why)."""
    offenders = _occurrence_lines(S.STANDALONE_CHART_PATH_TEXT)
    assert not offenders, f"dangling {S.STANDALONE_CHART_PATH_TEXT} paths in the docs:\n" + "\n".join(offenders)


def test_c04_void_token_only_in_negative_context():
    """STRATA_KV_GROW_HOLD is the card guide's fiction (run-1 RESEARCH §2:
    VOID); docs may NAME its non-existence but never instruct with it."""
    NEGATION = re.compile(
        r"void|does not exist|doesn.t exist|nonexistent|no such|not.*(exist|found)|"
        r"misattribut|never|don.t (use|set)|do not (use|set)|myth|fiction|bogus",
        re.I,
    )
    offenders = [
        ln for ln in _occurrence_lines(S.VOID_ENV_TOKEN) if not NEGATION.search(ln)
    ]
    assert not offenders, "KV_GROW_HOLD in a non-void context:\n" + "\n".join(offenders)


def test_c04_no_kubectl_apply_instruction():
    """AGENTS.md hard rule: the runbook documents re-PR flows; any 'kubectl
    apply' occurrence must be inside that prohibition."""
    NEGATION = re.compile(r"never|no |don.t|do not|prohibit|forbid|instead|via (a )?pr|re-pr", re.I)
    offenders = [
        ln for ln in _occurrence_lines("kubectl apply") if not NEGATION.search(ln)
    ]
    assert not offenders, "runbook instructs raw kubectl apply:\n" + "\n".join(offenders)


def test_c04_acceptance_cites_research_epoch_not_card_table():
    """Carried run-1 bar: acceptance numbers cite the PR #3636 measurement
    with provenance labels; the superseded card table is not restated."""
    text = _union_text()
    assert "one-at-a-time" in text or "one at a time" in text, (
        "the accepted bench posture must be named (the batch column was rejected)"
    )
    assert "2026-10-21" in text, "PR #3636 provenance date missing from the acceptance citation"
    assert "10%" in text, "the ~10% reproduction gate not stated"


def test_c04_parent_readme_homes_the_strix_fallback_section():
    """Run-1's C05 fallback runbook re-homes with the rest of the README
    knowledge — History vs current-epoch citations are the bar: the
    1,265/59.1 @8K row is engine-0.1.40-era while the bundled engine is
    0.1.52; restating old numbers unlabeled is the perf-myth failure mode."""
    text = S.read(S.PARENT_README, "r2-C04 re-homes the strata README into charts/llama-swap")
    lowered = text.lower()
    assert "strix" in lowered and "fallback" in lowered, "no strix fallback section in the parent README"
    window = lowered[lowered.index("strix"):]
    assert "0.1.40" in window, "History citation not epoch-labeled (engine-0.1.40-era)"
    assert any(tok in text for tok in ("1,265", "1265")) and "59.1" in text, "History perf row not cited"
    assert any(tok in text for tok in ("KL-gated", "KL gated")), "the 'rounds differ' caveat is part of the contract"


def test_c04_parent_readme_homes_the_image_contract():
    """C04 task 2: image contract lines survive the re-home — serve entry,
    the manual-bump ledger, escalation, deferred modes (reviewer diffs the
    retired README against this section)."""
    text = S.read(S.PARENT_README, "r2-C04 parent README")
    for tok, why in (
        (S.SERVE_ENTRY, "serve entry (the C01 image interface)"),
        (S.ENGINE_ROOT, "engine roots referenced from profile exe"),
        ("manual", "the manual-bump cadence (ruling (b) carried by run 2)"),
        ("split", "deferred split-mode pointer"),
    ):
        assert tok.lower() in text.lower(), f"parent README lost {why} ({tok!r})"
