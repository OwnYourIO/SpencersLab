# C04 doc-completeness contract — the anti-amnesia check (chunks/C04.md
# "Tests"; no cluster, no helm).
#
# Every on-target [VERIFY] item and ruling marker from the plan must appear in
# the runbook docs with its concrete command or values-key path, so no such
# fact lives only in the WeKan card. STRATA_KV_GROW_HOLD may appear ONLY in a
# void/negative context — the card guide's fiction must not resurface as an
# actionable instruction.

from __future__ import annotations

import re

import strata_testlib as S

DOC_PATHS = (S.RUNBOOK_NOTE, S.CHART_DIR / "README.md")


def _union_text() -> str:
    """Both docs joined; each must exist (C04 task 1 / C02+C05 own the README)."""
    return "\n".join(S.read(p, "C04 runbook deliverable") for p in DOC_PATHS)


# (token, rationale) — every entry names the plan/chunk line it pins.
REQUIRED_TOKENS: list[tuple[str, str]] = [
    ("ttm.pages_limit=29360128", "GRUB/sdbootutil cmdline target value (plan human-step 2)"),
    ("ttm.page_pool_size=29360128", "cmdline pair partner (plan on-target list)"),
    ("sdbootutil", "the cmdline mechanism itself (plan human-step 2: GRUB/sdbootutil)"),
    ("amd_iommu=off", "cmdline item (plan human-step 2)"),
    ("iommu=pt", "tradeoff note (C04 task 1)"),
    ("20251125", "linux-firmware version to avoid — MES 0x83 (plan human-step 2)"),
    ("UMA", "BIOS carve-out gate (plan on-target list)"),
    ("ReBAR", "BIOS Above-4G/ReBAR gate (plan on-target list)"),
    ("ASPM", "BIOS power gate (plan on-target list)"),
    ("16GT/s", "OCuLink x4 link-speed check (plan on-target list)"),
    ("lspci", "link + device-ID preflight command (C04 task 1)"),
    ("rocminfo", "ROCR_VISIBLE_DEVICES index resolution (plan human-step 2)"),
    ("ROCR_VISIBLE_DEVICES", "device-retarget values path (C02 key)"),
    ("getent group", "render/video numeric GIDs -> supplementalGroups (C04 task 1)"),
    ("supplementalGroups", "the values key the GIDs feed (C02 task 4)"),
    ("AppArmor", "MAC-mode assumption to confirm on-target (k3s/OpenSUSE)"),
    ("LimitNOFILE", "k3s systemd drop-in (plan human-step 2)"),
    ("LimitMEMLOCK", "drop-in partner; pinned-arena memlock (plan human-step 2)"),
    ("1048576", "LimitNOFILE target value (C04 facts)"),
    ("infinity", "LimitMEMLOCK=infinity (C04 facts)"),
    ("#2399", "nofile raise still open — why the wrapper/drop-in stay (RESEARCH §2)"),
    ("#2398", "found the fd ceiling, closed unmerged (RESEARCH contradiction #5)"),
    ("524288", "ulimit -n wrapper value = the PR's hard-limit figure (C02 cmd)"),
    ("ulimit", "in-container ulimit -n/-l proof points (plan on-target list)"),
    ("hipMemCreate", "the PR's fd-experiment failure mode at soft 1024 (C04 task 2)"),
    ("THP", "transparent huge pages gate (plan on-target list)"),
    ("#771", "THP issue reference (plan on-target list)"),
    ("--plan --output json", "the R1 pre-sync reconciliation command (human step 3)"),
    ("strata serve", "the serve CLI the gate runs (RESEARCH §2)"),
    ("expert-cache", "the --plan gate names which shipped values it finalizes — C02 sizing (C04 AC1)"),
    ("unloadTimeout", "the binding stop constraint to prove timed (plan on-target list)"),
    ("POST /api/models/unload", "inner escape hatch + timed-unload proof endpoint (RESEARCH §3)"),
    ("strata bench run", "acceptance protocol command (plan Commands/C04)"),
    ("standard-v1", "bench suite name (C04 facts)"),
    ("dmesg", "watch source for 128K/200K needle runs (C04 task 3)"),
    ("PENDING-OPERATOR-UUID", "the Bitwarden human prerequisite placeholder (Q5)"),
    ("Bitwarden", "the secret backend (repo law)"),
    ("STRATA_KV_GROW=1", "the documented kv-grow env alias (RESEARCH §2)"),
    ("--gpu-roles", "deferred split-mode pointer (C04 task 4)"),
    ("--layer-split", "deferred split-mode pointer (C04 task 4)"),
    ("TheRock", "2B source-build escalation facts (C04 task 4)"),
    ("tune_hipblaslt", "self-tune path for the missing gfx1201 table (RESEARCH §6)"),
    ("100401", "hipBLASLt version the table question turns on (RESEARCH §6)"),
    ("#1128", "kv-grow trim risk WITHOUT the void mitigation (R4)"),
    ("#1250", "page-cache drop_caches note on the shared claim (C04 task 3)"),
    ("drop_caches", "the #1250 mitigation command"),
    ("#1715", "Strix 128GB expert-cache OOM fix-class (RESEARCH §7)"),
    ("#2706", "HC_UPMIX split hazard — strix log-check (C05/C04)"),
    ("#2257", "the RollingUpdate overlap class behind strategy: Recreate (C02)"),
    ("MemAvailable", "pre-sync free-RAM check (C04 facts)"),
    ("allocatable", "node allocatable schedule check (plan human-step 3)"),
    ("96Gi", "the strata pod request the pre-sync math runs against (C04 facts)"),
    ("trio", "RAM law: first Strata request only with the llama.cpp trio idle (Q2/human step 3)"),
]

# regex-checked entries: spellings with alternation the substring list cannot carry
REQUIRED_PATTERNS: list[tuple[str, str]] = [
    (r"135[\u2013-]160", "/models/strata capacity budget 135–160 GB, either dash (RESEARCH §4)"),
    (r"getenforce|aa-status", "MAC-mode check commands (C04 task 1; plan on-target list: SELinux-vs-AppArmor)"),
    (r"rpm -q|rpm -qa|Tumbleweed", "kernel/firmware package preflight (plan on-target list item 1)"),
]


def _occurrence_lines(token: str) -> list[str]:
    out = []
    for p in DOC_PATHS:
        text = S.read(p, "C04 runbook deliverable")
        out += [ln for ln in text.splitlines() if token in ln]
    return out


def test_c04_required_tokens_present():
    text = _union_text()
    missing = [f"  {t}: {why}" for t, why in REQUIRED_TOKENS if t not in text]
    assert not missing, "runbook amnesia — token (rationale):\n" + "\n".join(missing)


def test_c04_required_patterns_present():
    text = _union_text()
    missing = [pat for pat, why in REQUIRED_PATTERNS if not re.search(pat, text)]
    assert not missing, f"patterned tokens missing: {missing}"


def test_c04_void_token_only_in_negative_context():
    """Every STRATA_KV_GROW_HOLD line must negate it (VOID/does-not-exist
    phrasing); an un-negated appearance means the card guide's fiction is back
    as actionable instruction."""
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
    """AGENTS.md hard rule, stated by C04 AC4: the runbook documents re-PR
    flows; any 'kubectl apply' occurrence must be inside that prohibition."""
    NEGATION = re.compile(r"never|no |don.t|do not|prohibit|forbid|instead|via (a )?pr|re-pr", re.I)
    offenders = [
        ln for ln in _occurrence_lines("kubectl apply") if not NEGATION.search(ln)
    ]
    assert not offenders, "runbook instructs raw kubectl apply:\n" + "\n".join(offenders)


def test_c04_acceptance_cites_research_epoch_not_card_table():
    """C04 AC3: acceptance numbers cite RESEARCH §5 with epoch/provenance
    labels; the superseded card table must not be restated as truth. Pin: the
    docs carry the one-at-a-time headline figures with their provenance."""
    text = _union_text()
    assert "one-at-a-time" in text or "one at a time" in text, (
        "the accepted bench posture must be named (the batch column was rejected)"
    )
    assert "2026-10-21" in text, "PR #3636 provenance date missing from the acceptance citation"
    assert "10%" in text, "the ~10% reproduction gate (C04 task 3) not stated"
