# cf-141 C01 — the tuning-runbook artifact validator. The note
# .agents/notes/strata-parallel-tuning-runbook.md is C01's deliverable and the
# ticket's attribution control: every later chunk's shipped state must agree
# with a row of it (C02 AC5 byte-agreement, C03 per-rung render legs, C04 the
# gate-appendix shipped-state leg). Absent note = every note-reading leg RED
# naming C01 (missing artifact); the laws themselves are proven satisfiable by
# the synthetic compliant fixture below (§8.4 doctrine), so a red here is
# always "artifact missing or falsified", never "law broken".
#
# Window laws, not blanket absences: a forbidden command form may appear
# inside a labeled user-run / documented-alternative / forbidden window —
# non-vacuity is proven both directions by the synthetic probes.

from __future__ import annotations

import re

import pytest

import strata_testlib as S

# ---------------------------------------------------------------------------
# Text helpers
# ---------------------------------------------------------------------------


def _note_text() -> str:
    """The note as written; missing file fails LOUD naming C01 (the chunk
    brief's red posture: dev gets a target, not a shrug)."""
    return S.read(S.TUNING_RUNBOOK, "cf-141 C01 must land the tuning runbook")


def _flat(text: str) -> str:
    """Join hard-wrapped lines; blank-line paragraph breaks stay (the
    windowed patterns must not manufacture matches across paragraphs)."""
    joined = text.replace("\r\n", "\n").replace("\n\n", "\x00").replace("\n", " ").replace("\x00", "\n")
    return re.sub(r"[ \t]+", " ", joined)


def _section(text: str, name_pat: str) -> str:
    """One heading-delimited section, from the heading matching name_pat to
    the next line-start heading (or EOF)."""
    lines = text.splitlines()
    start = next((i for i, ln in enumerate(lines)
                  if re.match(r"^#{1,6}\s", ln) and re.search(name_pat, ln, re.I)), None)
    if start is None:
        return ""
    end = next((i for i in range(start + 1, len(lines))
                if re.match(r"^#{1,6}\s", lines[i])), len(lines))
    return "\n".join(lines[start:end])


# ---------------------------------------------------------------------------
# AC1 — the eleven sections
# ---------------------------------------------------------------------------

NOTE_SECTIONS: tuple[tuple[str, str], ...] = (
    (r"state board", "§1 Pin & envelope state board"),
    (r"U1 capture", "§2 U1 capture (at-pin)"),
    (r"U1-v2", "§3 U1-v2 capture (post-bump)"),
    (r"bump.?gate appendix", "§4 Bump-gate appendix"),
    (r"benchmark procedure", "§5 Benchmark procedure"),
    (r"envelope table", "§6 Envelope table + scale-back ladder"),
    (r"arm table", "§7 Arm table"),
    (r"(quality|decision) record", "§8 Quality/decision record"),
    (r"verdict.?record template", "§9 Verdict-record template"),
    (r"corrections ledger", "§10 Corrections ledger"),
    (r"cross.?reference", "§11 Cross-references"),
)


def _law_sections(text: str) -> list[str]:
    return [why for pat, why in NOTE_SECTIONS if not _section(text, pat)]


# ---------------------------------------------------------------------------
# AC2 — attribution law + forbidden forms + the Q12 absence arm
# ---------------------------------------------------------------------------

EXEC_RE = re.compile(r"kubectl\b[^\n]*\bexec\b|\bstrata (serve|bench|--version)\b|sysctl|drop_caches|rocminfo|lspci")
USER_RUN_RE = re.compile(r"run_by:\s*user|user[- ]run|user leg|operator|human[- ]run|RUN BY THE (OPERATOR|HUMAN)", re.I)
# workflow_dispatch / kubectl set image: allowed ONLY in a labeled documented-
# alternative block (the GitOps caveat rides with it — plan law 4, Q13a).
ALT_LABEL_RE = re.compile(r"documented[- ]alternative|alternative shape|NOT chosen|hand-swap", re.I)
GITOPS_CAVEAT_RE = re.compile(r"GitOps", re.I)
FORBIDDEN_NEGATION_RE = re.compile(
    r"never|\bnot\b|do not|don.t|forbid|hazard|prohibit|must not|only as (a )?(forbidden|experimental)|"
    r"negative[- ]pin|out of scope|declined", re.I)
# The U3-v2 cgroup-detection probes the owner declined at Q12 — law-pinned
# absence, no window admits them (a declined probe recorded as a scheduled
# leg is the "mistaken for answered" class DECISIONS round 3 forbids).
U3V2_PROBE_RE = re.compile(r"/proc/[^\s]*(cgroup)|/sys/fs/cgroup|memory\.limit_in_bytes|memory\.max\b")
ROW_G_PREMISE_RE = re.compile(r"(row[ -]?G).{0,160}(UNMEASURED|unmeasured)|(UNMEASURED|unmeasured).{0,160}row[ -]?G", re.S)
ROW_G_OWN_PROBE_RE = re.compile(r"own (probe|cgroup-detection)|probe.{0,80}(own|itself|again)|declin", re.I | re.S)


def _law_attribution(text: str) -> list[str]:
    out = []
    blocks = [b for b in re.split(r"\n\s*\n", text) if b.strip()]
    for block in blocks:
        if EXEC_RE.search(block) and not USER_RUN_RE.search(block):
            first = block.strip().splitlines()[0][:90]
            out.append(f"executable command block without user-run/operator attribution: {first!r}")
    for tok in ("workflow_dispatch", "kubectl set image", "set image"):
        for block in blocks:
            if tok in block and not ALT_LABEL_RE.search(block):
                out.append(f"{tok!r} appears outside a labeled documented-alternative block")
        for block in blocks:
            if tok in block and ALT_LABEL_RE.search(block) and not GITOPS_CAVEAT_RE.search(block):
                out.append(f"{tok!r} in the alternative block without the GitOps caveat")
    return out


def _law_forbidden_forms(text: str) -> list[str]:
    out = []
    for n, ln in enumerate(text.splitlines(), 1):
        for tok in ("strata update", "--ple-io ram", "--resident-experts"):
            if tok in ln and not FORBIDDEN_NEGATION_RE.search(ln):
                out.append(f"line {n}: {tok!r} without a forbidden/never/declined marker")
    return out


def _law_u3v2_absence(text: str) -> list[str]:
    out = [f"line {n}: declined U3-v2 cgroup probe appears ({ln.strip()[:90]!r})"
           for n, ln in enumerate(text.splitlines(), 1) if U3V2_PROBE_RE.search(ln)]
    flat = _flat(text)
    if not ROW_G_PREMISE_RE.search(flat):
        out.append("no row-G premise sentence marked UNMEASURED — Q12's decline was recorded, not silence")
    if not ROW_G_OWN_PROBE_RE.search(flat):
        out.append("row-G's row does not say a future authorization must carry its own probe")
    return out


# ---------------------------------------------------------------------------
# AC3 — arm-table fidelity vs values.yaml
# ---------------------------------------------------------------------------

ARM_ROWS: tuple[tuple[str, str, str, str, str], ...] = (
    # (row label, values key-path, before token, after token, shipped-in marker)
    ("L2", "strata.config.engineProfileStrataQ4.env", "{}", "STRATA_MMQ_KQ", "C02"),
    ("envelope-primary", "strata.config.engineProfile.parallel", "4", "8", "C03"),
    ("envelope-strix", "strata.config.engineProfileStrix.parallel", "4", "8", "C03"),
    ("envelope-orca", "strata.config.engineProfileOrca.parallel", "4", "8", "C03"),
    ("envelope-q4", "strata.config.engineProfileStrataQ4.parallel", "4", "8", "C03"),
    ("envelope-ornith", "strata.config.engineProfileStrataOrnith.parallel", "1", "1", "unchanged"),
)

# The follow-up arms C01 documents without shipping (Q2/Q3/Q4/Q5-answers, L5,
# L6'): their key-paths must resolve so a later PR starts from a real seam.
FOLLOWUP_ARM_TOKENS: tuple[tuple[str, str], ...] = (
    ("L1", "STRATA_CKPT_POOL"),
    ("L3", "STRATA_BATCH_MTP"),
    ("L4", "--kv q4_0"),
    ("L5", "--vram-reserve-mib"),
    ("L6'", "STRATA_PREFILL_CPU_SHARE_BATCH"),
)


def _law_arm_rows(text: str) -> list[str]:
    out = []
    for label, path, before, after, shipped in ARM_ROWS:
        rows = [ln for ln in text.splitlines() if path in ln]
        if not rows:
            out.append(f"{label}: no arm row names the key-path {path!r}")
            continue
        row = " ".join(rows)
        if shipped not in ("unchanged",) and shipped not in row:
            out.append(f"{label}: row lacks its shipped-in: {shipped} marker")
        if shipped == "unchanged" and not re.search(r"unchanged|kept|—|negative pin", row):
            out.append(f"{label}: ornith row must mark the 1-slot negative pin kept")
        if before != after:
            for tok in (before, after):
                hit = ("{}" in row) if tok == "{}" else bool(re.search(rf"\b{re.escape(tok)}\b", row))
                if not hit:
                    out.append(f"{label}: row must state {before} before and {after} after (token {tok!r} missing)")
        found, _ = S.dig(S.chart_values_dict(), path)
        if not found:
            out.append(f"{label}: key-path {path!r} does not resolve in charts/llama-swap/values.yaml")
    if re.search(r"STRATA_MMQ_KQ[^\n]*?\b1\b", text) and '"1"' not in text:
        out.append("the L2 row's after-state must show the JSON STRING \"1\" (engine reads getenv(...)[0])")
    for label, tok in FOLLOWUP_ARM_TOKENS:
        if tok not in text:
            out.append(f"arm table missing the {label} follow-up row (token {tok!r})")
    return out


def _law_arm_values_current(text: str) -> list[str]:
    """Before-legs vs the LIVE values while a step's era dir is unlanded; the
    shipped-in legs byte-check once the step lands (era chain as the ledger)."""
    out = []
    vals = S.chart_values_dict()
    l2 = S.cf141_era_landed(S.PROFILE_Q4_FILE, S.CF141_ERA_L2)
    found, env = S.dig(vals, "strata.config.engineProfileStrataQ4.env")
    want_env = S.CF141_Q4_ENV_ARMED if l2 else {}
    if found and env != want_env:
        out.append(f"q4 env renders {env!r}, era ledger (cf141-l2 {'landed' if l2 else 'unlanded'}) "
                   "says it must be " + repr(want_env))
    for file, path in ((S.PROFILE_PRIMARY_FILE, "strata.config.engineProfile.parallel"),
                       (S.PROFILE_STRIX_FILE, "strata.config.engineProfileStrix.parallel"),
                       (S.PROFILE_ORCA_FILE, "strata.config.engineProfileOrca.parallel"),
                       (S.PROFILE_Q4_FILE, "strata.config.engineProfileStrataQ4.parallel"),
                       (S.PROFILE_ORNITH_FILE, "strata.config.engineProfileStrataOrnith.parallel")):
        landed = S.cf141_envelope_landed(file)
        want = S.CF141_PARALLEL_RULINGS[file][0] if landed else S.CF141_PARALLEL_PRE[file]
        found, got = S.dig(vals, path)
        if found and got != want:
            out.append(f"{file}: values parallel = {got!r}, era state says {want!r} "
                       f"({'C03 envelope landed' if landed else 'pre-envelope state held'})")
    return out


# ---------------------------------------------------------------------------
# AC4 — envelope rows, shipped-anyway annotations, ladder structure
# ---------------------------------------------------------------------------

ENVELOPE_NUMBERED_ROWS: tuple[tuple[str, str], ...] = (
    ("99.0", r"primary|row[ -]?H|8x262144.*conv 16|conv ?16"),
    ("123.9", r"q4"),
    ("101.9", r"orca"),
    ("96.2", r"row[ -]?G|file[ -]tier"),
    ("30.15", r"KV|kv"),
    ("13,728", r"B/token|per.token|law"),
)
SHIPPED_ANYWAY_RE = re.compile(r"ship\w* (it )?anyway|knowingly (over|beyond|past)|authorized[- ]overshoot|shipped anyway per Q9", re.I)
LADDER_RUNG_RE = re.compile(r"parallel:\s*4", re.I)
LADDER_OWNER_WORD_RE = re.compile(r"explicit in-round owner|owner word", re.I)
LADDER_NO_AGENT_RE = re.compile(r"never agent[- ]discretion|not agent[- ]discretion|no agent discretion|never exercise the ladder|agent discretion", re.I)


def _law_envelope(text: str) -> list[str]:
    out = []
    flat = _flat(text)
    for num, ctx in ENVELOPE_NUMBERED_ROWS:
        if not re.search(rf"{re.escape(num)}[^\n]{{0,200}}(?:{ctx})|(?:{ctx})[^\n]{{0,200}}{re.escape(num)}", flat, re.I):
            out.append(f"envelope row {num} ({ctx}) not found in its verdict window")
    for rung in ("q4", "orca", "strix"):
        rows = " ".join(ln for ln in text.splitlines()
                        if re.search(rf"\b{rung}\b", ln, re.I) and re.search(r"8|over|ship", ln))
        if not SHIPPED_ANYWAY_RE.search(rows):
            out.append(f"{rung}: no shipped-anyway/knowingly-over annotation tied to Q9")
    if not re.search(r"3\.09.{0,40}3\.35|3\.09[–-]3\.35|band 3\.09", flat, re.S):
        out.append("KV band 3.09–3.35 not stated")
    if not re.search(r"\(N\+1\)|N\+1.{0,80}(pin|law)|9 sessions|9x", flat, re.I):
        out.append("the (N+1)-sessions pinning law is not cited")
    if not re.search(r"survives (at )?(both|BOTH) pins|holds at (both|BOTH) pins|both pins", flat):
        out.append("the envelope law must cite the (N+1)/KV laws surviving BOTH pins [57][58][59]")
    if not re.search(r"walkdown.{0,120}(post.?bump|0\.1\.59|grace)|(post.?bump|0\.1\.59).{0,120}walkdown", flat, re.I):
        out.append("VRAM walkdown grace not marked post-bump-only")
    return out


def _law_ladder(text: str) -> list[str]:
    out = []
    win = _section(text, r"envelope table") or text
    flat = _flat(win)
    rungs = 0
    for rung in ("primary", "strix", "orca", "q4"):
        row = [ln for ln in win.splitlines() if re.search(rf"\b{rung}\b", ln, re.I) and LADDER_RUNG_RE.search(ln)]
        if row:
            rungs += 1
    if "a6e493b78" not in win:
        out.append("q4 ladder row must document the a6e493b78 posture as its scale-back target")
    if rungs != 4:
        out.append(f"scale-back ladder must carry a `parallel: 4` revert line for each of the 4 raised rungs (found {rungs})")
    if not LADDER_OWNER_WORD_RE.search(flat) or not LADDER_NO_AGENT_RE.search(flat):
        out.append("ladder discipline line missing: scale-back only on an explicit in-round owner word, never agent discretion")
    if not re.search(r"boot.?read|batch_slots", flat, re.I):
        out.append("ladder gate line missing: gate = startup read when that arena loads")
    g_row = [ln for ln in text.splitlines()
             if re.search(r"row[ -]?G|\|\s*G\s*\|", ln) and re.search(r"experiment", ln, re.I)]
    if not g_row or not re.search(r"unmeasured|never (a )?default|not scheduled", " ".join(g_row), re.I):
        out.append("row G not marked experiment-authorized with the unmeasured premise / never-default")
    return out


# ---------------------------------------------------------------------------
# AC5 — bump-gate appendix completeness
# ---------------------------------------------------------------------------

GATE_ISSUE_IDS = ("#5559", "#5608", "#5635", "#5614", "#5558", "#5564", "#5701", "#5629",
                  "#5020", "#3364", "#3693", "#3734", "#3574")
SOAK_SIGNATURES: tuple[tuple[str, str], ...] = (
    ("libhsa-runtime64", "libhsa-runtime64"),
    ("hsa_signal load/store vtable pair", r"hsa_signal_load[^\n]{0,20}store_relaxed|hsa_signal_load_relaxed|hsa_signal_store_relaxed"),
    ("REMOVE_QUEUE MES wedge", "REMOVE_QUEUE"),
    ("gfxhub page-fault class", "gfxhub"),
    ("MemAvailable load-peak class", "MemAvailable"),
    ("non-finite logit probes", "non-finite"),
)
STOP_CONDITION_RE = re.compile(r"stop condition[^.]{0,140}binding|binding[^.]{0,140}stop condition", re.I)
REVERT_NO_FIXFORWARD_RE = re.compile(r"revert PR[^.]{0,200}no fix.?forward|no fix.?forward[^.]{0,200}revert PR", re.I | re.S)


def _law_bump_appendix(text: str) -> list[str]:
    out = []
    win = _section(text, r"bump.?gate appendix") or ""
    flat = _flat(win)
    for i in range(1, 7):
        if not re.search(rf"gate\s*{i}\b", win, re.I):
            out.append(f"appendix lacks condensed gate {i}")
    missing = [t for t in GATE_ISSUE_IDS if t not in win]
    if missing:
        out.append(f"crash-cluster table missing issue ids: {missing}")
    if not re.search(r"(last fetch|re.?fetch|re-checked)[^.]{0,80}\d{4}-\d{2}-\d{2}|\d{4}-\d{2}-\d{2}[^.]{0,80}(re.?fetch|fetched)", win, re.I):
        out.append("gate 1 table carries no dated re-fetch row (C04's same-day gate needs the stamp)")
    if not re.search(r"zero maintainer|no maintainer reply", win, re.I):
        out.append("gate 1 must state the zero-maintainer-reply posture")
    if not re.search(r"0\.1\.59[^.]{0,120}(failing|confirmed|crashes|stops)|(failing set|crash)[^.]{0,120}0\.1\.59", win, re.I):
        out.append("0.1.59 confirmed in the failing set is not recorded")
    missing_sig = [label for label, pat in SOAK_SIGNATURES
                   if not re.search(pat, win)]
    if missing_sig:
        out.append(f"soak signatures missing: {missing_sig}")
    if not STOP_CONDITION_RE.search(flat):
        out.append("the stop condition is not labeled binding")
    if not REVERT_NO_FIXFORWARD_RE.search(flat):
        out.append("revert-PR-prepared / no-fix-forward is not stated")
    if not re.search(r"post-merge production watch", win) or not re.search(r"chosen|Q13", win):
        out.append("the CHOSEN soak shape must be named as chosen per Q13(a)")
    if not re.search(r"workflow_dispatch", win) or not re.search(r"GitOps", win):
        out.append("the alternative soak shape is not documented with its GitOps caveat")
    if not re.search(r"0\.1\.57 clean[^.]{0,120}(dead|corrected|superseded)|\(dead|superseded|corrected\)[^.]{0,80}0\.1\.57 clean", win, re.I | re.S):
        out.append("the eval's \"0.1.57 clean\" premise is not marked dead/corrected")
    if not re.search(r"#5317|#5341", win) or not re.search(r"#5327", win):
        out.append("the #5317/#5341 citations are not marked corrected to #5327")
    if not re.search(r"parallel 2|concurrencyLimit", win) or not re.search(r"superseded|not copied|stale", win, re.I):
        out.append("the eval's stale \"parallel 2 + concurrencyLimit 1\" sentence is not marked superseded, not copied")
    if "2026-11-10-dep-strata-engine-0213-eval.md" not in text or not re.search(r"superseded", text):
        out.append("the superseded bump-eval plan is not pointed at (superseded-as-executed-by-AD-141 at gate 6)")
    return out


# ---------------------------------------------------------------------------
# AC6 — quality scaffolding with measured rows
# ---------------------------------------------------------------------------

KV4159_PAIRS: tuple[tuple[str, str], ...] = (
    ("0.055", "94.9"),
    ("2.762", "int8"),
    ("0.130", "91.7"),
    ("2.793", "q4_0"),
    ("0.090", "0.200"),
)


def _law_quality_scaffold(text: str) -> list[str]:
    out = []
    flat = _flat(text)
    if "#4159" not in text:
        out.append("the #4159 quality rows are not cited")
    for a, b in KV4159_PAIRS:
        if not re.search(rf"{re.escape(a)}[^\n]{{0,120}}{re.escape(b)}|{re.escape(b)}[^\n]{{0,120}}{re.escape(a)}", flat):
            out.append(f"measured pair {a}/{b} missing from the #4159 rows")
    if not re.search(r"PR #21|#21[^.]{0,120}(preserved|refuted|not in)|(\+8.{0,3}12|8.12)[^.]{0,160}(not|refuted|unsupported)", flat, re.I | re.S):
        out.append("the guide's \"+8-12% PPL\" claim is not refuted at PR #21")
    if not re.search(r"--kv[^.]{0,200}(mirr|re.pin|test session)|(mirr|re.pin)[^.]{0,200}--kv", flat, re.I | re.S):
        out.append("the --kv-mirroring law re-pin route (through the test session) is not named")
    if not re.search(r"109\.2", flat) or not re.search(r"arena term|wall", flat, re.I):
        out.append("q4_0's nil 8-slot value (109.2, arena term is the wall) is not stated")
    if not re.search(r"halv[^.]{0,120}4.slot|4.slot[^.]{0,120}halv", flat, re.I):
        out.append("the 4-slot deep-park halving value of q4_0 is not recorded")
    l2_or_drafting = _flat(text)
    if not re.search(r"(STRATA_MMQ_KQ|drafting)[^\n]{0,300}experimental|experimental[^\n]{0,300}(STRATA_MMQ_KQ|drafting)",
                     l2_or_drafting, re.I):
        out.append("Q16 posture missing: the L2/drafting rows must say experimental at the new engine")
    for ln in text.splitlines():
        if re.search(r"intent.?pinning|settled intent", ln, re.I) and not re.search(r"\bnot\b|never", ln, re.I):
            out.append(f"line reads as settled-intent-pinning (Q16 forbids): {ln.strip()[:90]!r}")
    return out


# ---------------------------------------------------------------------------
# AC7 — stop criteria count + sweep localization
# ---------------------------------------------------------------------------

BENCH_SWEEPS = (
    (r"1, ?2, ?4, ?8", "primary sweep set {1,2,4,8} (post-C03, row H fits)"),
    (r"boot.?read", "non-primary sweeps gated on the boot-read read-back"),
    (r"degrade", "a degraded batch_slots rung sweeps to its REAL serving count"),
    (r"standard-v1", "standard-v1 suite named"),
    (r"parallel-mixed-v1", "parallel-mixed-v1 suite named"),
    (r"8K[^\n]{0,40}32K[^\n]{0,40}128K[^\n]{0,40}256K", "depth sweep {8K,32K,128K,256K}"),
    (r"SHA-?256", "frozen prompts hashed (SHA-256)"),
    (r"node_memory_MemAvailable_bytes", "per-cell Grafana memory watch"),
    (r"kube_pod_container_status_restarts_total", "restart counter watch"),
    (r'container="strata"', "LogQL strata-container selector"),
    (r"drop_caches", "host drop_caches precondition (user leg)"),
    (r"ornith[^.\n]{0,80}\{?1\}?", "ornith sweep stays {1}"),
)


def _law_bench_localization(text: str) -> list[str]:
    out = []
    win = _section(text, r"benchmark procedure")
    flat = _flat(win)
    missing = [why for pat, why in BENCH_SWEEPS if not re.search(pat, flat, re.I)]
    if missing:
        out += [f"benchmark section lacks: {m}" for m in missing]
    block = win or text
    m = re.search(r"stop criteria(.*?)(?=\n#{1,6}\s|\Z)", block, re.I | re.S)
    criteria = re.findall(r"^\s*(?:[1-9][.)]|-\s*\*\*\d)\s", m.group(1), re.M) if m else []
    if len(criteria) != 5:
        out.append(f"§10.6 stop criteria count is {len(criteria)}, must be exactly 5 (numbered items)")
    if m and not re.search(r"timeout", m.group(1), re.I):
        out.append("the usability-floor criterion must be tied to fleet agent timeouts")
    return out


def _law_corrections_ledger(text: str) -> list[str]:
    out = []
    win = _section(text, r"corrections ledger")
    cited = [ln for ln in win.splitlines() if re.search(r"\[\d+\]|\[M\]|\[E\]|\[V\]|\[I\]|RESEARCH|#\d{3,4}|[a-f0-9]{9,10}", ln)]
    if len(cited) < 16:
        out.append(f"corrections ledger carries {len(cited)} citation-bearing rows, want >= 16")
    blob = _flat(win)
    required = (
        r"parallel.{0,80}--batch|--batch.{0,80}parallel",
        r"STRATA_KV_GROW_HOLD",
        r"vram-reserve-mib[^.]{0,60}700|700[^.]{0,60}vram-reserve-mib",
        r"parallel-mixed-v1|standard-v1|suites exist",
        r"k8v4",
        r"conversation cache[^.]{0,120}8192|auto-sizes[^.]{0,60}8192|8192[^.]{0,60}auto",
        r"hipBLASLt",
        r"nice",
        r"--resident-experts",
        r"route.tail",
        r"drafting\.apply|drafting apply",
        r"file.cache[^.]{0,200}(cgroup|excluded|UNMEASURED|unmeasured)",
        r"0\.1\.57 clean",
        r"#5327",
        r"PARALLEL_MAX",
        r"a6e493b78[^.]{0,160}(superseded|Q9)|(superseded|Q9)[^.]{0,160}a6e493b78",
    )
    missing = [pat for pat in required if not re.search(pat, blob, re.I | re.S)]
    if missing:
        out.append(f"corrections ledger missing rows: {missing}")
    return out


# ---------------------------------------------------------------------------
# §8/§9/§11 — disposition table, verdict template, cross-references
# ---------------------------------------------------------------------------

def _law_disposition_and_templates(text: str) -> list[str]:
    out = []
    for q in range(1, 18):
        if not re.search(rf"\bQ{q}\b", text):
            out.append(f"disposition table never names Q{q}")
    flat = _flat(text)
    if not re.search(r"Q12[^.]{0,120}declin|declin[^.]{0,120}Q12", flat, re.I):
        out.append("Q12's decline is not visible in the disposition table")
    if not re.search(r"Q11[^.]{0,120}experiment|experiment[^.]{0,120}Q11", flat, re.I):
        out.append("Q11's experiment-only authorization is not visible")
    if not re.search(r"Q17[^.]{0,160}(\(a\)|resolved|approved|stands)|(?:\(a\)|resolved|approved)[^.]{0,160}Q17", flat, re.I):
        out.append("Q17's disposition (approved as option (a)) is not recorded")
    win = _section(text, r"verdict.?record template")
    for tok in ("pre-read", "sweep", "stop criteria", "retain", "revert", "gate"):
        if tok not in win:
            out.append(f"verdict-record template lacks {tok!r}")
    for row in ("L2", "boot-read", "soak"):
        if not re.search(row, win, re.I):
            out.append(f"verdict template lacks the pre-filled {row} round")
    xref = _section(text, r"cross.?reference")
    for tok in ("strata-host-prep-gpu-ai.md", "2026-11-10-research-strata-q3-q4-rungs",
                "2026-11-10-dep-strata-engine-0213-eval.md", "README"):
        if tok not in xref:
            out.append(f"cross-references do not name {tok}")
    return out


NOTE_LAWS: tuple[tuple[str, "callable"], ...] = (
    ("AC1 sections", _law_sections),
    ("AC2 attribution", _law_attribution),
    ("AC2 forbidden forms", _law_forbidden_forms),
    ("AC2 U3-v2 absence", _law_u3v2_absence),
    ("AC3 arm rows", _law_arm_rows),
    ("AC4 envelope rows", _law_envelope),
    ("AC4 ladder", _law_ladder),
    ("AC5 bump appendix", _law_bump_appendix),
    ("AC6 quality scaffold", _law_quality_scaffold),
    ("AC7 bench localization", _law_bench_localization),
    ("AC7b corrections ledger", _law_corrections_ledger),
    ("AC8 disposition/verdict/cross-ref", _law_disposition_and_templates),
)


# ---------------------------------------------------------------------------
# Synthetic compliant note (§8.4: satisfiability proven, so a red is always
# the artifact, never the law). Kept in a fixture string, never written out.
# ---------------------------------------------------------------------------

SYNTHETIC_NOTE = """
# Strata parallel-tuning runbook (synthetic validator fixture)

## Pin & envelope state board

| date | kind | state |
| --- | --- | --- |
| 2026-11-10 | pin | Strata 0.2.9 / engine 0.1.55 at commit a6e493b78 — pre-PR-1 baseline |
| 2026-11-10 | ruling Q5 | Open the envelope to 8 slots |
| 2026-11-10/11 | ruling Q9 | "8 slots everywhere. I know it won't fit, but I also know I won't be running 8 sessions at full context. I'd rather crash it and scale back from there." Accepted outcomes: engine fit-down, park refusals, contained cgroup kills |
| 2026-11-10 | ruling Q10 | row-H for the primary (conv 16384 + PLE-direct) |
| 2026-11-10 | ruling Q8 | bump un-deferred |
| 2026-11-10 | ruling Q13 | (a) pin-first, bump gated |
| 2026-11-10 | ruling Q15 | two PRs: PR-1 = C01+C02+C03, PR-2 = C04 |
| 2026-11-10 | ruling Q12 | probe declined |
| pending C03 | shipped row | per-rung parallel 8/8/8/8/1 (primary, strix, orca, q4, ornith); primary conv 16384, PLE auto off |

The bump-eval plan 2026-11-10-dep-strata-engine-0213-eval.md is superseded-as-executed-by-AD-141 at gate 6; its gates 1-5 live in the appendix below.

## U1 capture (at-pin, gates every arm)

Run by the operator, one session (README ladder rungs 1-2; the note layers on strata-host-prep-gpu-ai.md and never restates its [VERIFY] cells):

    # operator-run leg (run_by: user) — README ladder rung 1
    kubectl -n default exec deploy/gpu-ai-llama-swap-strata -- /opt/strata/terminal/bin/strata --version

Run by the operator — startup log blocks for the q4 AND primary arenas: the
INFO batch_slots line, the expert cache auto -> N slots line, the slot
sessions take ... GiB line, the K/V pinned-RAM GiB line (settles the
3.09-3.35 band), the hipBLASLt line (silence expected), the --ple-io/residency
line. This note never runs `strata update` in the container.

## U1-v2 capture (post-bump, re-arms §2 on the new build)

User leg, run by the operator after PR-2: strata --version + engine label
dirs 0.1.59-linux-x86_64-hip-halo, the [strata] drafting: line, arch-default
lines (MMQ K-quant on UD-Q4-class packs, STRATA_SELECT_WMMA, ALT_MIN_TOKENS,
chunked GDN), the bare-auto prefill ceiling, the vram_fit window walkdown
lines 20480 -> 8192 -> 4096, the "starting again without a drafter" warning,
the KV streaming: % hit line, and a re-grep that STRATA_REQUEST_LINES,
STRATA_PREFILL_CPU_SHARE, STRATA_PF_FUSED, MALLOC_MMAP_THRESHOLD_,
ROCR_VISIBLE_DEVICES still parse. There is no U3-v2 leg here: the row-G
cgroup-detection premise stays UNMEASURED and any future row-G authorization
must carry its own probe.

## Bump-gate appendix (C04 satisfies; Q13(a) fixed the shape)

Gate 1 re-fetch table (last fetch 2026-11-10: all open, zero maintainer
replies; #5559 #5608 #5635 #5614 #5558 #5564 #5701 #5629 class; #5020 #3364
#3693 #3734 #3574; 0.1.59 confirmed in the failing set). Gate 2 ledger-law
build. Gate 3 soak, chosen shape: post-merge production watch, the hourly
fleet IS #5559's traffic shape; signatures dmesg libhsa-runtime64 GPF,
hsa_signal_load/store_relaxed vtable pairs, gfxhub REMOVE_QUEUE MES wedge,
MemAvailable load-peak class, non-finite logit probes. The documented
alternative shape (user workflow_dispatch branch image + hand-swap) is NOT
chosen and carries the GitOps-revert caveat (ArgoCD reverts a hand-swap).
Gate 4 on-node --plan re-checks against the post-PR-1 posture; the eval's
stale "parallel 2 + concurrencyLimit 1" sentence is superseded, not copied;
its "0.1.57 clean" premise is dead (corrected) and #5317/#5341 correct to
#5327. Gate 5 re-bench with the bump-attribution sheet (MMQ fold,
SELECT_WMMA +5.7%, bare-auto 32768, GDN) — L2's env pin is the engine
default at 0.1.59 and is explicitly not double-counted (Q16). Gate 6 owner
gate: gates 1-5 are this ticket's work. Stop condition, binding: a
reproduced signature means the bump leg STOPS and a revert PR is prepared —
no fix-forward.

## Benchmark procedure

Preconditions per run (user leg, operator-run): fresh engine start; host
drop_caches (echo 3 > /proc/sys/vm/drop_caches, operator); GPU idle; nothing
else on the node. Suites: standard-v1 baseline, parallel-mixed-v1 sweeps.
Sweep sets: primary {1, 2, 4, 8} post-C03 (row H genuinely fits); every
other rung sweeps ONLY after its boot-read gate confirmed real 8-slot
service — a degraded batch_slots rung sweeps to its real serving count with
that recorded. ornith sweep {1}. Depth sweep {8K, 32K, 128K, 256K} with
frozen prompts (SHA-256), distinct suffixes, stream/max_tokens/reasoning_effort.
Per-cell logging via Grafana/Loki: node_memory_MemAvailable_bytes,
kube_pod_container_status_restarts_total on the strata container,
LogQL {container="strata"} (method from the q4-oom debug note).

Stop criteria (five, guide §10.6 adapted):
1. first-token latency past the fleet agent timeout — usability floor
2. prompt rate under the §3.4a bar by more than the accepted drift
3. decode tok/s below the band floor under agent traffic
4. restart storm or cgroup kill inside the window
5. any quality probe falsified (near-tie answer flips)

## Envelope table (honest math) + scale-back ladder

| row | shape | GiB | verdict |
| --- | --- | --- | --- |
| H | primary 8x262144 int8 conv 16 + PLE-direct | 99.0 <= 108 <= 110 | fits AT THE PIN |
| A' | q4 bare 8x262144 int8 | 123.9 | over cgroup — shipped anyway per Q9, expect degrade or kill |
| — | orca 8x262144 | 101.9 | over its 90 cap — shipped anyway per Q9, park refusals expected |
| — | strix 8x262144 | own UMA ruling class | shipped anyway per Q9, boot-read gate applies |
| — | ornith | stays 1 | surface law, not a flash-next rung |
| G | q4 file-tier resident-budget | 96.2 anon | experiment authorized (Q11) only, premise UNMEASURED (Q12), never default, no pre-committed chunk |
| A'/E | rows above | — | evidence for why G is an experiment, not a default |

Laws cited: (N+1) sessions pin the whole max-context at engine start —
9 sessions pin 30.15 GiB at 8x262144 — and survive both pins [57][58][59];
the KV constant is 13,728 B/token int8 with the measured band 3.09-3.35
GiB/slot@262K; 9 sessions take roughly 0.4-0.56 GiB VRAM each before cache
auto; the vram_fit walkdown grace exists post-bump only.

Scale-back ladder (structure; C03 fills the shipped rows; one rung per
commit, an explicit in-round owner word required, no agent discretion):

| rung | shipped parallel | budget verdict at the pin | first symptom | revert value | gate = startup read when that arena loads |
| --- | --- | --- | --- | --- | --- |
| primary | 8 | fits (row H) | degraded INFO batch_slots | parallel: 4 | batch_slots read |
| strix | 8 | own UMA class | degraded batch_slots | parallel: 4 | batch_slots read |
| orca | 8 | 101.9 over cap | park refusals | parallel: 4 | batch_slots read |
| q4 | 8 | 123.9 over cgroup | cgroup kill + restart pair (kube_pod_container_status_restarts_total) | parallel: 4 (the a6e493b78 posture is q4's scale-back target) | batch_slots read |

Scale-back executes only on an explicit in-round owner word — never agent
discretion; degrade is recorded, not success.

## Arm table (exact diffs, one change per merge)

| arm | key-path | before | after | effect | citation | risk | on-target check | revert | shipped-in |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| L2 | strata.config.engineProfileStrataQ4.env | {} | {"STRATA_MMQ_KQ": "1"} | +10.3/14.3/16.8% prompts | [32][61][62] | near-tie flips | U1 read | one line | C02 |
| envelope | strata.config.engineProfile.parallel | 4 | 8 | row H fits at 99.0 | Q9 Q10 | crash-and-scale-back | boot-read gate | parallel: 4 | C03 |
| envelope | strata.config.engineProfileStrix.parallel | 4 | 8 | Q9 8-everywhere at the pin | Q9 | boot-read subject | boot-read gate | parallel: 4 | C03 |
| envelope | strata.config.engineProfileOrca.parallel | 4 | 8 | Q9 8-everywhere at the pin | Q9 | park refusals | boot-read gate | parallel: 4 | C03 |
| envelope | strata.config.engineProfileStrataQ4.parallel | 4 | 8 | Q9 supersedes a6e493b78 | Q9 | 123.9 over cgroup | boot-read gate | parallel: 4 | C03 |
| envelope | strata.config.engineProfileStrataOrnith.parallel | 1 | 1 | unchanged negative pin | q36 law | none | none | n/a | unchanged |
| L1 | strata.config.engineProfileStrataQ4.env | {} | STRATA_CKPT_POOL nine-var stack | manual HIP stack, never auto on HIP | [14][38] | unqualified | bench | remove block | follow-up (Q2) |
| L3 | strata.config.engineProfileStrataQ4.env | {} | STRATA_BATCH_MTP: "1" | env form, per-slot drafters | [6] | shrinks cache | bench | remove line | follow-up (Q3) |
| L4 | --kv q4_0 | int8 | decision scaffolding only (#4159: int8 KL 0.055 / top-1 94.9 / PPL 2.762; q4_0 KL 0.130 / top-1 91.7 / PPL 2.793; agent segment 0.090 vs 0.200; PR #21 refutes the guide's +8-12% PPL — the merged body preserves perplexity) | 109.2 stays over: the arena term is the wall, 8-slot value nil; halves deep-park KV at the 4-slot posture | [42][43] | agent KL x2.2 | owner gate | none | decision-only (Q4) |
| L5 | --vram-reserve-mib 2048 | 700 default | 2048 | reserve floor | [18] | low priority | bench | drop flag | follow-up |
| L6' | STRATA_PREFILL_CPU_SHARE_BATCH=1 | off | 1 | CPU pool beside slots | [69] | 0.1.59-only | bench | remove line | follow-up |

Post-bump posture (Q16): STRATA_MMQ_KQ=1 and "drafting": "mtp" stay PRESENT
at 0.1.59, each carrying an experimental-flag comment — experimental at the
new engine, not settled intent; the intent-pinning reading is explicitly NOT
the posture; the engine default already applies (user-set wins [61][62]) and
IQ3_S primary is not in the flip's scope. The --kv mirroring law re-pin
routes through the test session, never a dev edit. --ple-io ram stays
forbidden (hazard law) and --resident-experts stays out (unproven on
gfx1201). `strata update` never runs in the container.

## Quality/decision record

Q1 yes (ship L2), Q2 no (document), Q3 documented, Q4 no, Q5 open envelope,
Q6 new note, Q7 yes corrections, Q8 re-plan with bump, Q9 8 everywhere,
Q10 row-H yes, Q11 experiment only, Q12 declined (no U3-v2 probe run in this
run; a future row-G decision must run its own probe — declined, recorded),
Q13 (a), Q14 fold seven, Q15 two PRs, Q16 experimental flags, Q17 resolved:
approved as option (a).

## Verdict-record template

Per round: pre-read startup table, sweep table, stop criteria hit,
Grafana/Loki links, decision (retain/revert/gate), follow-ups. Pre-filled
rows: C02 L2 round, C03 per-rung boot-read + scale-backs, C04 soak watch +
re-bench.

## Corrections ledger

- `parallel:` IS `--batch` via parallel_args [5] — settled OQ-1.
- STRATA_KV_GROW_HOLD does exist at 0.2.9 [V] — EXPLORE gotcha corrected.
- --vram-reserve-mib default is 700 [18].
- standard-v1 and parallel-mixed-v1 suites exist at the pin [31].
- k8v4 repetition bug fixed pre-pin [41]; streams with --kv-resident.
- conversation cache auto-sizes up to 8192 on the serve path [27].
- hipBLASLt: silence expected on gfx1201 [22][23][24].
- nice no-op on R9700-only rungs; live only on strix [16].
- --resident-experts is not a plan arm [21][48][49].
- route-tail skip default at the pin [9][12].
- drafting.apply() runs unconditionally at 0.2.13 [79]; the "drafting": "mtp"
  pins are EXPERIMENTAL-flagged per Q16.
- file-cache arena rescue excluded under cgroups [67] — and whether ours is
  detected is UNMEASURED (Q12 declined).
- "0.1.57 clean" premise dead (reporter corrected) [74].
- #5327 (not #5317/#5341) is the #5531 issue [68].
- PARALLEL_MAX = 8 survives at 0.1.59 [57].
- hipBLASLt still a no-op at 0.2.13 [71].
- a6e493b78's q4 4-slot ruling is superseded by Q9; the 110Gi containment +
  MALLOC protections survive into the 8-everywhere posture as its safety net.

## Cross-references

strata-host-prep-gpu-ai.md §3.3/§3.4/§3.4a/§3.5/§4/§5/§6 (this note layers
on it and never restates its [VERIFY] cells); charts/llama-swap/README.md
ladder rungs 1-4; containers/strata/README.md ledger;
2026-11-10-dep-strata-engine-0213-eval.md (superseded pointer);
2026-11-10-research-strata-q3-q4-rungs.md.
"""


def _run_laws(text: str) -> list[str]:
    out = []
    for name, law in NOTE_LAWS:
        out += [f"{name}: {v}" for v in law(text)]
    return out


# ---------------------------------------------------------------------------
# Arms (each names the AC it pins)
# ---------------------------------------------------------------------------


def test_c01_note_sections_present():
    """AC1: the note exists with the eleven pinned-name sections."""
    problems = _law_sections(_note_text())
    assert not problems, "runbook sections missing:\n" + "\n".join(problems)


def test_c01_attribution_and_forbidden_forms():
    """AC2: operator attribution on every executable block; forbidden forms
    only inside labeled windows; the Q12 decline is law-pinned: no U3-v2
    probe line exists AND the standing row-G-precondition note does."""
    text = _note_text()
    problems = _law_attribution(text) + _law_forbidden_forms(text) + _law_u3v2_absence(text)
    assert not problems, "attribution/forbidden-form law broken:\n" + "\n".join(problems)


def test_c01_arm_fidelity_vs_shipped_values():
    """AC3: every arm row's key-path resolves in values.yaml, before/after
    states and shipped-in marks present; the live values side byte-agrees
    with the era ledger (L2 flips at C02's capture, the envelope rows per-
    rung at C03's)."""
    text = _note_text()
    problems = _law_arm_rows(text) + _law_arm_values_current(text)
    assert not problems, "arm-table fidelity broken:\n" + "\n".join(problems)


def test_c01_envelope_and_ladder():
    """AC4: envelope row↔verdict windows with the honest math, the Q9
    shipped-anyway annotations, the (N+1)/KV band citations surviving both
    pins, and the structurally complete four-rung scale-back ladder."""
    text = _note_text()
    problems = _law_envelope(text) + _law_ladder(text)
    assert not problems, "envelope/ladder law broken:\n" + "\n".join(problems)


def test_c01_bump_appendix_gate_completeness():
    """AC5: the six condensed gates, the dated re-fetch table with the full
    issue-id set, the soak signatures, the binding stop condition, the
    chosen-vs-alternative shapes named per Q13(a), and the superseded eval
    sentences marked not copied."""
    text = _note_text()
    problems = _law_bump_appendix(text)
    assert not problems, "bump-gate appendix incomplete:\n" + "\n".join(problems)


def test_c01_quality_scaffold_measured_rows():
    """AC6: #4159 measured rows exact, the PR-#21 refutation, the
    --kv-mirroring re-pin route, and the Q16 experimental posture with
    settled-intent phrasing banned."""
    text = _note_text()
    problems = _law_quality_scaffold(text)
    assert not problems, "quality scaffolding law broken:\n" + "\n".join(problems)


def test_c01_stop_criteria_and_sweep_localization():
    """AC7: exactly five §10.6 stop criteria, the per-rung sweep sets
    (primary {1,2,4,8}, others boot-read gated, ornith {1}), the depth sweep,
    and the Grafana/Loki per-cell method."""
    text = _note_text()
    problems = _law_bench_localization(text)
    assert not problems, "stop-criteria/sweep localization broken:\n" + "\n".join(problems)


def test_c01_corrections_ledger():
    """AC7b: at least sixteen citation-bearing ledger rows including the Q9
    supersession of a6e493b78's ruling."""
    text = _note_text()
    problems = _law_corrections_ledger(text)
    assert not problems, "corrections ledger incomplete:\n" + "\n".join(problems)


def test_c01_disposition_verdict_and_crossref_sections():
    """§8/§9/§11: Q1-Q17 dispositioned with the Q11/Q12 declines visible, the
    verdict-record template with its pre-filled rounds, and the five
    cross-reference homes."""
    text = _note_text()
    problems = _law_disposition_and_templates(text)
    assert not problems, "record/template/cross-ref law broken:\n" + "\n".join(problems)


# ---------------------------------------------------------------------------
# Preservation legs that must NOT depend on the note (green today, stay green)
# ---------------------------------------------------------------------------

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)


@helm
def test_c01_kv_int8_still_everywhere_it_states():
    """The Q4 answer keeps `--kv int8` shipped on the flash-next rungs; the
    note's q4_0 rows are decision scaffolding only. The render leg is the
    control the note is checked against."""
    docs = S.render_on()[0]
    for file in S.FLASH_NEXT_PROFILES:
        args = dict(S.arg_pairs(S.profile_json(docs, file)))
        assert args.get("--kv") == "int8", (
            f"{file}: --kv moved to {args.get('--kv')!r} — q4_0 adoption is owner-gated (Q4), "
            "this ticket documents it, never ships it"
        )


@helm
def test_c01_pre_envelope_parallel_held_until_c03():
    """The C01-era before-leg: while no envelope step dir has landed, the
    values must still read {4,4,4,4,1}; the after-leg (the ruling table)
    lives in test_strata_cf141_envelope.py and flips green per-rung when
    C03's captures land."""
    docs = S.render_on()[0]
    rendered = S.render_parallel_map(docs)
    pre_live = {f: (S.CF141_PARALLEL_PRE[f], "pre-envelope state (scale-back target)")
                for f in S.CF141_PARALLEL_PRE if not S.cf141_envelope_landed(f)}
    problems = S.parallel_violations(rendered, pre_live)
    assert not problems, ("values diverged from the pre-envelope parallel state while its era step "
                          "dirs are still unlanded (the era chain says the envelope wave has not "
                          "captured yet):\n" + "\n".join(problems))


# ---------------------------------------------------------------------------
# Satisfiability + non-vacuity probes (green by construction; the teeth)
# ---------------------------------------------------------------------------


def test_c01_synthetic_compliant_note_satisfies_every_law():
    problems = _run_laws(SYNTHETIC_NOTE)
    assert not problems, ("the synthetic compliant note fails the laws — a law is broken, "
                          "not the artifact missing:\n" + "\n".join(problems))


def test_c01_laws_reject_falsified_mutants():
    """Each mutation of the compliant fixture reddens its owning law by name
    — proves the window laws are not blanket passes."""
    mutated = {
        "probe": SYNTHETIC_NOTE + "\ncat /sys/fs/cgroup/memory.max for the row-G premise\n",
        "wd": SYNTHETIC_NOTE.replace("\n## Benchmark procedure",
                                     "\nRun workflow_dispatch to ship it.\n\n## Benchmark procedure"),
        "update": SYNTHETIC_NOTE + "\nstrata update fixes the drift.\n",
        "settled": SYNTHETIC_NOTE + "\nThe env pin is settled intent-pinning at the new engine.\n",
        "gate6": SYNTHETIC_NOTE.replace("Gate 6 owner", "Gate X owner"),
    }
    expectations = (
        ("probe", "AC2 U3-v2 absence"),
        ("wd", "AC2 attribution"),
        ("update", "AC2 forbidden forms"),
        ("settled", "AC6 quality scaffold"),
        ("gate6", "AC5 bump appendix"),
    )
    for key, law_name in expectations:
        violations = _run_laws(mutated[key])
        assert any(law_name in v for v in violations), f"mutation {key!r} must redden {law_name!r} (got {violations[:3]})"
    # Ladder rung dropped: delete q4's revert line only, the count law must fire.
    no_q4 = "\n".join(ln for ln in SYNTHETIC_NOTE.splitlines()
                      if not re.search(r"^\| q4 \| 8 \|", ln))
    assert any("AC4 ladder" in v for v in _run_laws(no_q4))
    # Corrections row dropped: remove the supersession bullet.
    no_super = "\n".join(ln for ln in SYNTHETIC_NOTE.splitlines() if "superseded by Q9" not in ln)
    assert any("AC7b corrections ledger" in v for v in _run_laws(no_super))


# ---------------------------------------------------------------------------
# Era-scoped cross-legs: the shipped-in flips (red naming their chunk)
# ---------------------------------------------------------------------------


@helm
def test_cf141_c02_l2_shipped_in_leg():
    """C02 AC5: the note's L2 row and the values edit are byte-agreeing —
    values q4 env == {"STRATA_MMQ_KQ": "1"} (JSON string) once C02 lands.
    RED until C02, naming C02 (the note itself is checked by the C01 arms)."""
    env = S.profile_json(S.render_on()[0], S.PROFILE_Q4_FILE).get("env")
    problems = S.env_pin_violations(env, S.CF141_Q4_ENV_ARMED)
    assert not problems, ("cf-141 C02 not landed: " + "; ".join(problems)
                          + " — the L2 row's shipped-in: C02 leg waits for the q4 env pin")


@helm
def test_cf141_c03_envelope_shipped_in_legs_per_rung():
    """C03's runbook cross-leg (per-rung form, C01 AC3): the note's envelope
    rows must state the shipped per-rung truth — values parallel == the
    ruling table {8,8,8,8,1}, each rung's row citing its own ruling.
    RED until C03, naming C03 per rung (the scale-back path re-greens a row
    through the ruling table, never through a loop)."""
    _note_text()  # the shipped annotation moves WITH the note; absent note = C01 red first
    found_vals = S.chart_values_dict()
    rendered = {}
    for file, path in ((S.PROFILE_PRIMARY_FILE, "strata.config.engineProfile.parallel"),
                       (S.PROFILE_STRIX_FILE, "strata.config.engineProfileStrix.parallel"),
                       (S.PROFILE_ORCA_FILE, "strata.config.engineProfileOrca.parallel"),
                       (S.PROFILE_Q4_FILE, "strata.config.engineProfileStrataQ4.parallel"),
                       (S.PROFILE_ORNITH_FILE, "strata.config.engineProfileStrataOrnith.parallel")):
        ok, v = S.dig(found_vals, path)
        assert ok, f"key-path {path} vanished from values.yaml — the note rows resolve against nothing"
        rendered[file] = v
    problems = S.parallel_violations(rendered, S.CF141_PARALLEL_RULINGS)
    assert not problems, ("cf-141 C03 envelope not landed (per-rung rulings):\n"
                          + "\n".join(problems))


@helm
def test_cf141_c03_boot_read_gates_written():
    """C03 AC6/law-3 leg in the note: every raised rung carries its
    boot-read gate (startup batch_slots read, park-refusal / kill+restart
    first symptoms) and the degrade-is-not-success discipline — dev and
    review only verify the gates ARE WRITTEN, never exercise them."""
    text = _note_text()
    win = _section(text, r"envelope table") or text
    problems = []
    for rung in ("primary", "strix", "orca", "q4"):
        rows = "\n".join(ln for ln in win.splitlines() if re.search(rf"^\| {rung} \|", ln, re.I))
        if not rows or not re.search(r"batch_slots|boot.?read", rows, re.I):
            problems.append(f"{rung}: ladder row lacks its boot-read gate line")
    if not re.search(r"degrade[^.]{0,120}(record|not success|isn.t success)|(record|not success)[^.]{0,120}degrade",
                     _flat(win), re.I):
        problems.append("degrade != success discipline not stated in the ladder")
    assert not problems, ("cf-141 C03 boot-read gates missing:\n" + "\n".join(problems))


def test_cf141_c04_runbook_shipped_state_leg():
    """C04 AC6 in the note: once the bump ships (Dockerfile FROM tags read
    0.2.13 — the era fact this leg keys on), the shipped-state board must
    carry the dated 0.2.13/0.1.59 PR-2 row and the attribution sheet must
    keep L2's delta out of the bump's. RED until C04 lands, naming C04."""
    dockerfile = S.read(S.CONTAINER_DIR / "Dockerfile", "C04's ledger moves these tags")
    bumped = all(t in dockerfile for t in S.CF141_FROM_TAGS)
    if not bumped:
        pytest.fail("cf-141 C04 not landed (Dockerfile FROM tags still pre-0.2.13) — "
                    "the runbook's shipped-state row for PR-2 correctly does not exist yet")
    text = _note_text()
    problems = []
    if not [ln for ln in text.splitlines()
            if "0.2.13" in ln and "0.1.59" in ln and re.search(r"shipped|PR-2|live on :main", ln, re.I)]:
        problems.append("no state-board row naming 0.2.13 + 0.1.59 as shipped (PR-2)")
    if not re.search(r"(not double-counted|NOT double-counted)", text):
        problems.append("the attribution sheet does not exclude L2 from the bump's deltas")
    assert not problems, ("cf-141 C04 runbook shipped-state leg unsatisfied:\n" + "\n".join(problems))
