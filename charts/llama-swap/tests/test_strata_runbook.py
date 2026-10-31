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
    VOID); docs may NAME its non-existence but never instruct with it.
    Line-scoped scan — doc authors: keep the negation on the token's own
    line, prose hard-wrap can push it off and read as a miss (cf-77 r2
    FRICTION)."""
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
    apply' occurrence must be inside that prohibition. Line-scoped scan —
    doc authors: keep the negation on the token's own line (cf-77 r2
    FRICTION)."""
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


# --- cf-86 C06 docs round: the shipped PAIRS doctrine, pinned per doc ---------
#
# The pod cgroup and the engine's --memory-limit-mib move as one unit (#1601),
# and C06 put a SECOND pair in play (100Gi + 95232 for the UD-Q4_K_XL arena)
# while the render itself shows only one cgroup — so the docs are the only
# place the two-pair doctrine exists, and a doc drift there is invisible to the
# render arms. Each doc is pinned AS WRITTEN: the note spells the conversation
# cache "32768 MiB x 16-slot" and the README "32 GiB × 16 slots"; that is house
# style, so the token sets are per-file and no doc is edited to unify them.
#
# Docs hard-wrap, so a pair can straddle a line break; the pairing checks run on
# paragraph-joined text (wrapped lines joined, blank-line paragraph breaks kept)
# and each pin keeps a bounded, period-free window so a match cannot be
# manufactured across a sentence or paragraph boundary.

DOC_TOKENS: dict[str, tuple[tuple[str, str], ...]] = {
    "runbook note": (
        (r"32768 MiB\s+x 16-slot conversation cache", "note's IQ3-class cache shape (MiB spelling)"),
        (r"8192 MiB\s+x 16", "note's Q4 cache trim"),
        (r"135[\u2013-]160\s*GB", "the q3-era area budget, kept (run-1 RESEARCH §4)"),
        (r"111,334,654,784\s*B", "the Q4 family byte total the budget grows by"),
        (r"df -h\s+/models/strata", "the human capacity gate around the first q4 run"),
        (r"before the\s+`q4`\s+token first runs", "when that capacity gate fires"),
        (r"97,473,155,200\s*B", "the orca IQ4_XS trio Σ (C08 docs round; == the live-pinned shards, see the c08-note arm below)"),
        (r"packs/orca-iq4_xs", "the IQ4_XS pack path the profile serves and the df gate measures"),
    ),
    "parent README": (
        (r"32\s*GiB\s+.\s+16\s*slots", "README's IQ3-class cache shape (GiB spelling)"),
        (r"8\s*GiB\s+.\s+16", "README's Q4 cache trim"),
        (r"135[\u2013-]160\s*GB", "the capacity budget survived the pair rewrite"),
        (r"unsloth\s+UD-Q4_K_XL", "the README names the Q4 arena's source family"),
    ),
}

# Per doc: both shipped pairs must appear as PAIRS (cgroup within a short window
# of the cap), and the pod-vs-rung distinction that makes "two pairs" readable
# when the render carries one cgroup.
DOC_PAIRS: tuple[tuple[str, str], ...] = (
    (r"96Gi[^.]{0,140}?92160", "the IQ3-class pair: 96Gi cgroup + 92160 engine cap"),
    (r"100Gi[^.]{0,140}?95232", "the Q4 pair: 100Gi cgroup + 95232 engine cap"),
)
PER_RUNG_DOCTRINE = (
    r"(per-rung|the cgroup is the\s+pod.s|inside (the )?one strata pod|inside the same cgroup)"
)

SUPERSEDED_CAP_FIGURES = {
    "66560": re.compile(r"superseded|retired|no longer|was the|old", re.I),
}
SUPERSEDED_SLIPS = ("111,334,256,784",)


def _flat(text: str) -> str:
    """Join wrapped lines; keep blank-line paragraph breaks as line breaks so a
    windowed pattern cannot span paragraphs. Indentation from the wrap collapses
    to one space, so patterns use \\s+ at any point a doc may have wrapped."""
    joined = text.replace("\r\n", "\n").replace("\n\n", "\x00").replace("\n", " ").replace("\x00", "\n")
    return re.sub(r"[ \t]+", " ", joined)


def test_c06_both_docs_name_both_shipped_cgroup_pairs():
    """#1601's pair is per-rung: a doc that names only one pair re-opens the
    2026-10-29 failure mode (one leg moved alone)."""
    problems = []
    for label, path in (("runbook note", S.RUNBOOK_NOTE), ("parent README", S.PARENT_README)):
        flat = _flat(S.read(path, "cf-86 C06 docs round"))
        for pat, why in DOC_PAIRS:
            if not re.search(pat, flat):
                problems.append(f"{label}: no {why} (window {pat!r})")
    assert not problems, "shipped pairs missing from the docs:\n" + "\n".join(problems)


def test_c06_both_docs_name_the_pod_vs_rung_distinction():
    """The cgroup belongs to the pod, the cap to whichever arena is loaded.
    Without that sentence, two named pairs read as two live cgroups — which the
    render contradicts."""
    offenders = [
        label for label, path in (("runbook note", S.RUNBOOK_NOTE), ("parent README", S.PARENT_README))
        if not re.search(PER_RUNG_DOCTRINE, _flat(S.read(path, "cf-86 C06 docs round")))
    ]
    assert not offenders, f"docs missing the per-rung/one-pod distinction: {offenders}"


def test_c06_cache_shapes_pinned_per_doc_house_style():
    """Every doc carries its own envelope vocabulary; the shipped numbers must
    be present in the spelling that doc uses (MiB vs GiB, 'x' vs '×')."""
    texts = {
        "runbook note": _flat(S.read(S.RUNBOOK_NOTE, "cf-86 C06 docs round")),
        "parent README": _flat(S.read(S.PARENT_README, "cf-86 C06 docs round")),
    }
    missing = [
        f"  {label}: {pat!r} — {why}"
        for label, specs in DOC_TOKENS.items()
        for pat, why in specs
        if not re.search(pat, texts[label])
    ]
    assert not missing, "doc token missing (label, pattern, rationale):\n" + "\n".join(missing)


def test_c06_session_files_path_named_in_both_docs():
    """The Q4 rung round-trips deep conversations through engine session files;
    the path is a shipped value (Q4_SLOT_SAVE_PATH) and the docs are the operator's
    only pointer to it."""
    offenders = []
    for label, path in (("runbook note", S.RUNBOOK_NOTE), ("parent README", S.PARENT_README)):
        flat = _flat(S.read(path, "cf-86 C06 docs round"))
        if S.Q4_SLOT_SAVE_PATH not in flat:
            offenders.append(f"{label}: {S.Q4_SLOT_SAVE_PATH} not named")
            continue
        linked = re.search(
            rf"session files?[^.]{{0,160}}{re.escape(S.Q4_SLOT_SAVE_PATH)}"
            rf"|{re.escape(S.Q4_SLOT_SAVE_PATH)}[^.]{{0,160}}session files?",
            flat,
        )
        if not linked:
            offenders.append(f"{label}: {S.Q4_SLOT_SAVE_PATH} named but not tied to session files")
    assert not offenders, "session-files doctrine missing:\n" + "\n".join(offenders)


def test_c06_capacity_growth_qualifies_the_q3_era_budget():
    """135–160 GB is a q3-era area figure; a doc that keeps it without the Q4
    growth in the same breath under-promise by ~111 GB of shards."""
    note = _flat(S.read(S.RUNBOOK_NOTE, "cf-86 C06 docs round"))
    readme = _flat(S.read(S.PARENT_README, "cf-86 C06 docs round"))
    for label, text in (("runbook note", note), ("parent README", readme)):
        assert re.search(r"135[\u2013-]160\s*GB", text), f"{label} lost the 135–160 GB capacity budget"
    assert re.search(r"135[\u2013-]160\s*GB.{0,700}?111,334,654,784", note, re.S), (
        "the note keeps the q3-era budget without the Q4 shard total beside it — the number "
        "reads as the whole picture"
    )


def test_c06_doc_and_comment_byte_totals_agree_with_the_pinned_shards():
    """The 398,000 B slip class: a cited total that is not the sum of the cited
    shards. The live-pinned per-shard bytes (test_strata_q4_rung.py) are the
    authority; docs and the chart comment must sum to the same number, and the
    superseded slip must not come back."""
    from test_strata_q4_rung import Q4_PACK_TOTAL, Q4_SHARD_BYTES

    assert Q4_PACK_TOTAL == 111_334_654_784, (
        f"pinned shard sum {Q4_PACK_TOTAL} moved — re-run the live source gate before "
        "re-pinning the docs"
    )
    cited = {}
    for label, path in (("runbook note", S.RUNBOOK_NOTE), ("parent README", S.PARENT_README),
                        ("chart values.yaml", S.CHART_DIR / "values.yaml")):
        text = _flat(S.read(path, "cf-86 C06 docs round"))
        cited[label] = text
        for slip in SUPERSEDED_SLIPS:
            assert slip not in text, f"{label} carries the superseded total {slip}"
    assert f"{Q4_PACK_TOTAL:,} B" in cited["runbook note"], (
        f"the note's cited total is not the pinned {Q4_PACK_TOTAL:,} B"
    )
    for size in Q4_SHARD_BYTES.values():
        assert f"{size:,} B" in cited["chart values.yaml"], (
            f"chart comment no longer states shard {size:,} B — its arithmetic can no longer "
            "be checked against the live tree"
        )
    assert f"{Q4_PACK_TOTAL:,} B" in cited["chart values.yaml"], (
        f"chart comment's stated sum is not {Q4_PACK_TOTAL:,} B — the sum of its own cited shards"
    )


def test_c06_superseded_cap_figures_stay_labeled():
    """A retired envelope number may be named only as retired (same
    line-scoped discipline as the kubectl-apply and VOID-token arms — doc
    authors: keep the marker on the figure's own line, prose wraps)."""
    offenders = []
    for label, path in (("runbook note", S.RUNBOOK_NOTE), ("parent README", S.PARENT_README)):
        text = S.read(path, "cf-86 C06 docs round")
        for figure, marker in SUPERSEDED_CAP_FIGURES.items():
            offenders += [
                f"{label}: {ln.strip()[:90]}"
                for ln in text.splitlines()
                if re.search(rf"(?<![\d.]){figure}(?![\d.])", ln) and not marker.search(ln)
            ]
    assert not offenders, "superseded cap figure stated without a supersession marker:\n" + "\n".join(offenders)


def test_c08_note_arithmetic_and_cleanup_trio_agree_with_the_pinned_ship():
    """C08 docs-round law: the note's orca IQ4_XS block must SUM to the live-
    pinned trio (same anti-slip discipline as the q4 totals arm — a cited
    total that is not the sum of its cited shards is the 398,000 B class),
    and the claim-cleanup trio must keep the coord-ruling shape: the tier-
    independent `.pack-orca` marker line FIRST, and `.setup-ABL` spelled as
    the driver actually writes it (MARK=.setup-$TOK — dev's correction of the
    coord draft's wrong path, recorded in TEST_SPEC 9.18). The strix row's
    honest no-cap shape is pinned too: #1601's pairing covers three rungs,
    not four, and a doc that hides that re-opens the one-leg-as-pod-budget
    misread."""
    from test_strata_c08_rung_shifts import IQ4_PACK_TOTAL, IQ4_SHARD_BYTES

    assert IQ4_PACK_TOTAL == 97_473_155_200, (
        f"the pinned orca trio sum {IQ4_PACK_TOTAL} moved — re-run the live tree arm "
        "before re-pinning the note"
    )
    note = _flat(S.read(S.RUNBOOK_NOTE, "cf-86 C08 docs round"))
    problems = []
    if f"{IQ4_PACK_TOTAL:,} B" not in note:
        problems.append(f"note's orca Σ is not the pinned {IQ4_PACK_TOTAL:,} B")
    for size in IQ4_SHARD_BYTES.values():
        if f"{size:,}" not in note:
            problems.append(f"note no longer cites shard {size:,} B — its Σ cannot be re-derived by hand")
    if "orca-iq3_xxs" not in note:
        problems.append("the cleanup block stopped naming the swept packs/orca-iq3_xxs — nothing gets reclaimed")
    for pat, why in (
        (r"FIRST[^.]{0,90}?\.pack-orca", "the marker line goes FIRST or nothing gets reclaimed"),
        (r"\.pack-orca`?\s+is\s+tier-INDEPENDENT", "the WHY of the marker-first order"),
        (r"rm\s+-f\s+/models/strata/\.pack-orca", "the exact FIRST command (coord ruling 2026-10-31)"),
        (r"\.setup-ABL\b", "the swept abl token's marker, spelled as the driver writes it (.setup-$TOK)"),
        (r"strix row carries no\s+`?--memory-limit-mib", "strix's honest no-cap shape"),
        (r"strix [^|]{0,60}?\|\s*none declared", "the caps table keeps strix's cap cell honest"),
    ):
        if not re.search(pat, note):
            problems.append(f"missing (window {pat!r}): {why}")
    assert not problems, "orca-quant/cleanup doctrine drifted in the runbook note:\n" + "\n".join(problems)
