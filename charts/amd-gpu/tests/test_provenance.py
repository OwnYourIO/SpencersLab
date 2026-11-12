# charts/amd-gpu provenance contract — RE-AUTHORED for the C08 T-A conversion:
# the D19 vendored-fork story (fork point 0.22.0, tag amd-gpu-helm-0.22.0,
# index digest, refresh policy) becomes the D23 FIRST-PARTY note — the chart
# is repo-owned, the app-template 5.0.1 dep is its only upstream, and the
# moved facts are line-for-line traceable (§R7-Q5). The blob-identity legs
# die with the vendored files, honestly: a first-party chart has no fork
# point to record, and the refresh debt the governance line carried no longer
# exists (renovate tracks the app-template dep; PR #122 staleness became
# irrelevant the day the templates went away).
#
# Red state at handoff (designed-red until C08): Chart.yaml dependency floor,
# Chart.lock + vendored tgz, .helmignore, the first-party header tokens and
# the vendored-text ABSENT arms all fail on today's vendored files; the
# renovate/docker-pin, digest-ledger, strategy-arg and ledger-block arms are
# PARITY witnesses — the conversion moves them (files change; facts don't).
#
# Pure file reads — no helm, no skip. Window joins use the flattened replay
# form (§12 law), compiled for Python 3.14 flag position (§12.5 law).

from __future__ import annotations

import re

import yaml

import amd_gpu_testlib as A

CHART_DIR = A.CHART_DIR


# --- Chart.yaml floors (T-A) ------------------------------------------------


def test_chart_yaml_first_party_floors():
    meta = A.chart_meta()
    assert meta.get("name") == "amd-gpu", (
        f"C08 T-A: Chart.yaml name is {meta.get('name')!r}, want amd-gpu — the name now holds appset-"
        "derivation meaning (Application gpu-ai-amd-gpu), not the D19 template-hardcode pin"
    )
    assert str(meta.get("version")) == "1.0.0", (
        f"C08 T-A: Chart.yaml version is {meta.get('version')!r} — an EXISTING chart: the no-hand-bump law "
        "stands (release.yaml owns the next bump; conversion is not a bump)"
    )
    assert str(meta.get("appVersion")) == A.PLUGIN_TAG, (
        f"C08: appVersion {meta.get('appVersion')!r}, want {A.PLUGIN_TAG} (keeps its image-pairing meaning)"
    )
    deps = meta.get("dependencies") or []
    assert deps == [{"name": "app-template", "version": "5.0.1",
                     "repository": "https://bjw-s-labs.github.io/helm-charts/"}], (
        "C08 T-A: Chart.yaml must carry EXACTLY the app-template 5.0.1 dependency (mirror "
        f"charts/radiance — first-party idiom, zero parent loader); deps: {deps}"
    )


def test_chart_lock_and_vendored_tgz():
    """The FRICTION §12 fresh-tree law extends to this chart with C08: the
    lock is the committed artifact, the tgz gitignored, and every render run
    follows `helm dependency update charts/amd-gpu`."""
    lock = CHART_DIR / "Chart.lock"
    assert lock.is_file(), "C08 T-A: charts/amd-gpu/Chart.lock missing (helm dependency update output, committed)"
    deps = yaml.safe_load(lock.read_text()).get("dependencies", [])
    assert len(deps) == 1 and deps[0].get("name") == "app-template" and str(deps[0].get("version")) == "5.0.1", (
        f"C08 T-A: Chart.lock must pin EXACTLY app-template 5.0.1, got {deps}"
    )
    assert list(CHART_DIR.glob("charts/app-template-5.0.1.tgz")), (
        "C08 T-A: the vendored charts/app-template-5.0.1.tgz is missing (run helm dependency update "
        "charts/amd-gpu before rendering — the fresh-tree trap, FRICTION §12)"
    )


def test_helmignore_present():
    """Repo standard (coder/llama-swap/radiance carry one); the two
    external-chart-era files didn't — C08 T-A adds it."""
    assert (CHART_DIR / ".helmignore").is_file(), "C08 T-A: charts/amd-gpu/.helmignore missing"


# --- the first-party header (D23 replaces D19) --------------------------------


def test_header_first_party_note_and_moved_facts():
    """The governance header rewrite is line-for-line traceable: the args
    trio / -v=5 law → values.yaml comment; the RBAC fact → "labeller-gated,
    renders NOTHING today; when the labeller returns, app-template
    serviceAccount/rbac.roles/rbac.bindings are the expression (§R7-Q5)";
    the name strain + one-sync swap pointer. Asserted across Chart.yaml +
    values.yaml header comments (where dev lands the prose is its choice;
    the TOKENS are the contract)."""
    blob = A.chart_meta_text() + "\n" + A.chart_values_text()
    flat = " ".join(blob.split())
    assert re.search(r"(?i)first[- ]party", flat), (
        "C08/D23: no first-party provenance note — the D19 vendored story must be replaced, not deleted silently"
    )
    for token, why in (
        ("serviceAccount", "the future-labeller RBAC route (§R7-Q5 expression keys)"),
        ("rbac", "the same — roles/bindings named as the expression"),
        ("R7", "the §R7-Q5 citation the T-A header mandates"),
        ("v=5", "the -v=5 runbook-log law, moved to the values comment"),
    ):
        assert token in flat, f"C08 T-A header: the moved-fact token {token!r} ({why}) is absent ticket-side"
    low = flat.lower()
    assert "nothing today" in low or "renders nothing" in low, (
        "C08 §R7-Q5: the RBAC zero-ship fact ('renders NOTHING today') is not recorded where the reader looks"
    )


def test_header_vendored_fork_text_absent():
    """The flip side of the rewrite: the refresh-debt prose DIES with the
    vendored files (D23). A stale 're-copy on upstream ≥0.23' instruction in
    a first-party chart is a lie the next contributor would obey."""
    text = A.chart_meta_text()
    low = text.lower()
    for dead in ("vendored", "vendor", "fork", "refresh", "0.22.0", "amd-gpu-helm", "791ada88", "pr #122"):
        assert dead not in low, (
            f"C08/D23: Chart.yaml header still carries the vendored-fork token {dead!r} — "
            "the fork/refresh-policy story must be GONE from the governance header (history lives in DECISIONS)"
        )


# --- values: the moved ship facts (parity witnesses) ---------------------------


def test_image_tag_renovate_pin_parses():
    """D19's pin migration FINALIZED here: the docker datasource comment sits
    above the tag wherever the app-template image block moved it (flattened
    window join, §12 law — the established replay form)."""
    lines = A.chart_values_text().splitlines()
    tag_idx = [i for i, ln in enumerate(lines)
               if re.match(r"^\s*tag:\s*[\"']?1\.31\.0\.12[\"']?\s*(#.*)?$", ln)]
    assert tag_idx, (
        f"C08: values.yaml carries no image tag line 1.31.0.12 — the pin the product naming ships on "
        "(§R6-Q2) must survive the rewrite inside the app-template image block"
    )
    window = " ".join(ln for i in tag_idx for ln in lines[max(0, i - 6):i + 1])
    assert re.search(
        r"#\s*renovate:\s*datasource=docker\s+depName=docker\.io/rocm/k8s-device-plugin", window
    ), (
        f"C08 AC6/D23: no `# renovate: datasource=docker depName=docker.io/rocm/k8s-device-plugin` "
        f"above the tag (window: {window[:200]!r}) — the pin moved out of services/ with C07 and "
        "must move WITH the values rewrite, not be rewritten away"
    )


def test_digest_ledger_moved_and_labeled():
    """D2 posture unchanged: tag + 64-hex amd64 manifest digest in a COMMENT,
    no digest field (the render leg asserts the field's absence)."""
    text = A.chart_values_text()
    digests = re.findall(r"sha256:[0-9a-f]{64}", text)
    assert digests, "C08: values.yaml lost the full 64-hex digest ledger through the rewrite (D2 posture holds)"
    assert any(d.startswith(A.PLUGIN_AMD64_DIGEST_PREFIX) for d in digests), (
        f"C08: no digest starting with {A.PLUGIN_AMD64_DIGEST_PREFIX} — the 6437c74f… ledger must move VERBATIM (D23)"
    )
    flat = " ".join(text.split())
    assert re.search(r"(?i)(amd64|image[- ]?manifest)", flat), (
        "C08: the digest comment lost its which-is-which label through the move"
    )


def test_strategy_arg_is_plain_and_plumbing_dead():
    """The dp.extraArgs plumbing dies with the vendored values (D23): the
    strategy must be a literal arg token in the app-template subtree — not a
    splice key (per-cluster override = the service-block law)."""
    text = A.chart_values_text()
    assert A.STRATEGY_FLAG in text, (
        f"C08 T-A: {A.STRATEGY_FLAG!r} absent from values.yaml — the product strategy must be an explicit arg now"
    )
    assert not re.search(r"^\s*extraArgs\s*:", text, re.M), (
        "C08 T-A/D23: an extraArgs plumbing key survived the rewrite — the hook belongs to the deleted templates "
        "(the dp.* namespace dies; service-block overrides carry any future per-cluster change)"
    )


def test_accepted_gaps_and_off_pairs_documented():
    """The conversion's documented concessions, each a comment where the
    values live: the updateStrategy gap (k8s default == today), the would-be
    nodeSelector pair recorded not shipped."""
    text = " ".join(A.chart_values_text().split())
    assert re.search(r"(?i)updateStrategy|update strategy", text) and re.search(r"(?i)default", text), (
        "C08 T-A: the accepted updateStrategy gap (app-template renders none; k8s default equals today's "
        "RollingUpdate/maxUnavailable 1) is not recorded in the values comment"
    )
    assert "feature.node.kubernetes.io/pci-0300_1002.present" in text and "amd64" in text, (
        "C08 T-A: the would-be nodeSelector pair must be recorded as a COMMENT (gated-off state preserved; "
        "the today's-values 89-91 fact carries)"
    )


def test_expected_names_ledger_block_survives():
    """AC3 (amendment): the ledger survives in charts/amd-gpu/values.yaml in
    the n4/testlib-readable form with the RULED names — 7551/C0 -> the
    R9700_POOL_NAME constant (patched-table provenance), 1586 -> the APU
    constant (carried-rows note), same-line row form, the fallback-trap word,
    AND the image-IDs-path WATCH line (mount-stops-applying ⇒ baked name
    returns ⇒ claim Pending; runbook receipts (a)-(c) catch it)."""
    text = A.chart_values_text()
    flat = " ".join(text.split())
    for device, revision, name in A.EXPECTED_NAME_LEDGER:
        if revision:
            ok = any((device in ln and revision in ln and name in ln) for ln in text.splitlines())
            assert ok or (device in flat and name in flat), (
                f"C08 AC3: the ledger row ({device},{revision}) -> {name} no longer parses from the same-line "
                "comment form the n4/testlib anchors read — the block may MOVE, the anchors may not die"
            )
        else:
            assert device in flat and name in flat, f"C08 AC3: ledger lost the {device} -> {name} pairing"
    assert f"amd.com/{A.R9700_POOL_NAME}" in text and f"amd.com/{A.APU_POOL_NAME}" in text, (
        "C08 AC3: the full amd.com/-prefixed names must appear verbatim (C02's cross-chart identity needle reads them here)"
    )
    assert re.search(r"(?i)fallback", text), "C08 AC3: the fallback trap left the ledger with the rewrite"
    low = text.lower()
    assert "watch" in low and re.search(r"(?i)(ids[ _-]?path|loadproductindex|mount)", low), (
        "C08 AC3(amendment): the WATCH line is missing — if the image moves its IDs lookup path the mount "
        "silently stops applying, the BAKED name returns, and radiance's claim goes Pending-forever; "
        "the ledger is where the next reader learns it (runbook receipts a-c catch it)"
    )
    assert re.search(r"(?i)superseded", low) or re.search(r"(?i)patched", low), (
        "C08/D24: the ledger never marks provenance (patched-table now; the baked-table name is superseded-by-mount)"
    )


# --- T-B leg (ii): table content parity vs the fetched authority -----------------


def _shipped_table_text() -> str:
    vals = A.chart_values()
    cms = ((vals.get("app-template") or {}).get("configMaps") or {})
    assert "amdgpu-ids" in cms, (
        "C08 T-B(ii): app-template.configMaps.amdgpu-ids missing — the patched table is not "
        f"in the values (keys: {sorted(cms)})"
    )
    data = (cms["amdgpu-ids"].get("data") or {})
    assert A.IDS_TABLE_KEY in data, (
        f"C08 T-B(ii): configMaps.amdgpu-ids.data lacks the {A.IDS_TABLE_KEY!r} key (keys: {sorted(data)})"
    )
    return data[A.IDS_TABLE_KEY]


def _row_fields(ln: str) -> tuple[str, str, str]:
    parts = ln.rstrip("\n").split(",")
    dev = parts[0].strip()
    rev = parts[1].strip() if len(parts) > 1 else ""
    prod = ",".join(parts[2:]).strip() if len(parts) > 2 else ""
    return dev, rev, prod


def _is_data_row(ln: str) -> bool:
    if ln.startswith("#") or not ln.strip():
        return False
    dev = ln.split(",")[0].strip()
    return len(dev) == 4 and all(c in "0123456789abcdefABCDEF" for c in dev)


def test_table_rows_match_the_fetched_authority():
    """AC7/T-B(ii), the grave-case enforcement: EVERY 1586 row of the fetched
    v1.31.0.12 baked table byte-equal (dropping any of them silently drops
    that SKU to bare amd.com/gpu — the C1/C3/C6/D1 rows carry the LIVE gpu-ai
    overlay consumer's pool, D21/B1: llama-swap would be Pending-forever on
    its next restart). Header/version lines present per the format; the 7551
    side is exactly the renamed C0 row; no other-device rows smuggled."""
    head_a, ver_a, rows_a = A.table_authority()
    a_1586 = sorted(ln for ln in rows_a if ln.split(",")[0].strip() == "1586")
    a_1586_revs = {_row_fields(ln)[1] for ln in a_1586}
    assert {"C1", "C3", "C6", "D1"} <= a_1586_revs, (
        f"C08 fixture drift: the authority lacks the 8060S revisions (have {sorted(a_1586_revs)})"
    )

    table = _shipped_table_text()
    lines = table.splitlines(keepends=True)
    assert any(ln.startswith("# List of AMDGPU IDs") for ln in lines), (
        "C08 AC7: the shipped table lacks the format header — LoadProductIndex/the table tooling "
        "parse against it (the fetched authority's header block is the model)"
    )
    data_rows = [ln for ln in lines if _is_data_row(ln)]
    s_1586 = sorted(ln for ln in data_rows if ln.split(",")[0].strip() == "1586")
    assert s_1586 == a_1586, (
        "C08 AC7/T-B THE APU-ROWS-MUST-CARRY LAW: the shipped 1586 rows diverge from the fetched "
        f"baked authority — dropped: {sorted(set(a_1586) - set(s_1586))}, added: "
        f"{sorted(set(s_1586) - set(a_1586))}, altered: {sorted((set(a_1586) & set(s_1586)) ^ set(a_1586) ^ set(s_1586))[:2]}. "
        "Every 1586 revision copies VERBATIM (byte-equal, tabs included); the C1/C3/C6/D1 rows "
        "derive the LIVE overlay pool — a drop strands gpu-ai llama-swap."
    )
    rows_7551 = [ln for ln in data_rows if ln.split(",")[0].strip() == "7551"]
    assert len(rows_7551) == 1, (
        f"C08 AC7: the 7551 side is {len(rows_7551)} rows, want exactly the ONE renamed C0 row "
        "(the R9700S/R9600D siblings are not this node's hardware — minimality)"
    )
    dev, rev, prod = _row_fields(rows_7551[0])
    assert (dev, rev) == ("7551", "C0"), f"C08 AC7: the 7551 row is {rows_7551[0]!r}, want device 7551 revision C0"
    assert prod == A.R9700_PRODUCT_STRING, (
        f"C08 AC7/T-B: the 7551/C0 product string is {prod!r}, want EXACTLY {A.R9700_PRODUCT_STRING!r} "
        "— the sanitizer-traced value the ruling picked"
    )
    assert A.sanitize_product(prod) == A.R9700_POOL_NAME, (
        f"C08/D24: sanitize({prod!r}) = {A.sanitize_product(prod)!r}, want {A.R9700_POOL_NAME!r} — "
        "the derivation (§R7-Q2) is the mechanism; a marketing string that sanitizes elsewhere is a silent rename"
    )
    assert A.sanitize_product("AMD Radeon AI PRO R9700") == A.HISTORICAL_R9700_POOL_NAME, (
        "C08: the sanitizer port no longer reproduces the pre-C08 baked name from the baked marketing "
        "string — the port that pins THIS lane's derivation rotted (fixture-trust leg)"
    )
    smuggled = [ln.rstrip() for ln in data_rows if ln.split(",")[0].strip() not in ("7551", "1586")]
    assert not smuggled, (
        f"C08 AC7 minimality: rows beyond the node's two cards are in the table: {smuggled} — every absent "
        "pair falls to bare amd.com/gpu (fallback trap) and a wide table is a maintenance surface, not a safety margin"
    )


def test_minimality_note_and_no_impossible_literal():
    """D24/T-B: the table is minimal BY DOCUMENTATION (values comment beside the
    data): absent pairs fall to bare amd.com/gpu (the C06 step-0 gate-(a)
    decision tree), the node is bounded by two cards, TP2 needs re-verification
    (rides the TP2 doc's law, T-E). And the unreachable string — amd.com/ +
    the product without the code-constant 'gpu-' prefix — must appear NOWHERE
    as anything claim-shaped (the literal is a code impossibility, §R7-Q1)."""
    text = A.chart_values_text()
    flat = " ".join(text.lower().split())
    assert "minimal" in flat and ("fallback" in flat or "bare" in flat), (
        "C08 T-B: the minimality note (patched table = the node's two cards; absent pairs "
        "take the already-shipped bare-fallback path) is not recorded beside the data"
    )
    impossible = "amd.com/" + "r9700-1"   # assembled: the rejected string, never present
    assert impossible not in text, (
        f"C08/D24: {impossible!r} shipped — the plugin's code constants make it UNREACHABLE; "
        "only amd.com/gpu-r9700-1 exists (the -1 carries no scheduling meaning)"
    )


# --- AC4: zero-stale sweep + new-name placement -----------------------------------


_SCAN_SCOPES = ("charts", "services", "tests", ".agents/notes")
_NEW_NAME_ALLOW = (
    "charts/amd-gpu/",              # table + ledger + comments (D24 home)
    "charts/radiance/",             # claim + comments + NOTES
    "charts/llama-swap/values.yaml",  # T-B comment-only carve site
    "charts/llama-swap/tests/",       # TEST-RECORD exemption (C08 dev round): the
    #                                   suites' TEST_SPEC ledger names the ruling
    #                                   string AS ITS SUBJECT, exactly like root
    #                                   tests/**; the stray guard stays sharp for
    #                                   every NON-test path under charts/.
    "services/gpu-ai/prod/values.yaml",  # T-B comment-only carve site
    ".agents/notes/radiance-",      # the two current docs (T-E sweep)
    "tests/",                       # bash suite constants + this test file's variables
)


def name_scope_violations(root):
    """The AC4 scan body — factored so the teeth probe below exercises the
    RED branch on a synthetic tree without touching the repo. Returns
    (old_hits, stray_hits) as rel-paths."""
    old = A.HISTORICAL_R9700_POOL_NAME
    new_pool = A.R9700_POOL_NAME
    old_hits, stray_hits = [], []
    for scope in _SCAN_SCOPES:
        base = root / scope
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*")):
            if not path.is_file() or "__pycache__" in path.parts:
                continue
            rel = str(path.relative_to(root))
            if rel.endswith((".tgz", ".pyc", ".png", ".ico")):
                continue
            try:
                body = path.read_text(errors="ignore")
            except OSError:
                continue
            if old in body:
                old_hits.append(rel)
            if new_pool in body and not rel.startswith(_NEW_NAME_ALLOW):
                stray_hits.append(rel)
    return old_hits, stray_hits


def test_zero_stale_name_and_new_name_placement():
    """AC4 (amendment): the pre-C08 pool name survives in NO file under
    charts/ services/ tests/ .agents/notes/ (history lives in
    DECISIONS/plan/TEST_SPEC/RESEARCH/git — outside this scan); the new pool
    name appears ONLY in the allowed sites. This file names the old string by
    ASSEMBLY (HISTORICAL_R9700_POOL_NAME) so the scan cannot trip its own
    needle — the vllm_testlib LEGACY_REF precedent. C08 dev-round re-pin:
    the false-positive was the scan's OWN test records (the llama-swap
    TEST_SPEC §12.x ledgers legitimately name the ruling pool; root tests/**
    was already admitted) — admitted via the test-record exemption above,
    teeth re-proven by the synthetic-tree leg below."""
    old_hits, stray_hits = name_scope_violations(A.REPO_ROOT)
    assert not old_hits, (
        "C08 AC4 zero-stale: the pre-C08 pool name survives in current surfaces "
        f"{old_hits} — the D24 sweep (T-B dev side + T-E docs) must land them all; "
        "assembled-literal scans prove the needle itself stays clean"
    )
    assert not stray_hits, (
        f"C08 AC4 placement: the renamed pool string appears OUTSIDE its sanctioned sites: {stray_hits} "
        "(allowed: amd-gpu, radiance, the two comment-only carve files incl. llama-swap TEST-RECORDS, "
        "the notes docs, tests/)"
    )


def test_placement_guard_teeth_on_synthetic_tree(tmp_path):
    """The allow list must remain a PLACEMENT rule, not an always-pass: a
    synthetic tree with the new name once in an admitted home and once in a
    NON-admitted charts/ path must yield exactly the stray. (C08 dev-round
    probe per the §12.5 class law — exercise green-time branches now, not at
    the next round.)"""
    root = tmp_path
    (root / "charts" / "amd-gpu").mkdir(parents=True)
    (root / "charts" / "other-chart").mkdir(parents=True)
    (root / "charts" / "amd-gpu" / "values.yaml").write_text(
        f"# sanctioned home\nclaim: {A.R9700_CLAIM}\n")
    (root / "charts" / "other-chart" / "values.yaml").write_text(
        f"# stray placement\nclaim: {A.R9700_CLAIM}\n")
    old_hits, stray = name_scope_violations(root)
    assert not old_hits, f"probe tree itself must be stale-clean: {old_hits}"
    assert stray == ["charts/other-chart/values.yaml"], (
        f"C08 AC4 teeth probe: expected exactly the one stray placement, got {stray} — "
        "the allow list has become an always-pass (or an over-broad admit)"
    )
