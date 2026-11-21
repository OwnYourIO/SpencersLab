# cf-145 C03 — the runbook step-9 note rewrite (chunks/C03.md; AC1-AC3).
# `.agents/notes/radiance-on-target-acceptance.md` step 9 stops DEFERRING the
# dashboard question ("FOLLOW-UP CARD #2 … Do NOT edit services/monitoring/
# prod/values.yaml in this run") and records what C01/C02 actually wired: the
# k8s.grafana.com annotation pair in charts/radiance (job `radiance` via the
# label fallback), the grafana.dashboards.inference.radiance entry at the
# pinned tag, the owner's two unconditional manual syncs (DECISIONS D-10), and
# the /stats line kept strictly as the honest-retirement CONTINGENCY (plan R3/
# OQ-6 — never the default). All greps are window-scoped between the
# `## Step 9` and `## Step 10` headings: the phrases may live elsewhere in the
# note's history and that is not C03's surface (parser idiom off testlib's
# q27_region_text).
#
# Red state at handoff (designed): every leg RED until C03-dev lands the edit
# (T1: both retirement phrases are live in the window today; T2: none of the
# landed-surface pointers are). T3 additionally goes RED if either landed
# surface RENAMES after the note is written — the strings are DERIVED from the
# C01/C02 files, not duplicated from this test's constants.
#
# Run per-directory: PATH=$HOME/.local/bin:$PATH python3 -m pytest charts/radiance/tests -v

from __future__ import annotations

import re

import yaml

import radiance_testlib as R

NOTE = R.REPO_ROOT / ".agents" / "notes" / "radiance-on-target-acceptance.md"
MONITORING_VALUES = R.REPO_ROOT / "services" / "monitoring" / "prod" / "values.yaml"

# The deferral prose C03 retires WITH the paragraph (T1, exact phrases).
RETIRED_PHRASES = ("FOLLOW-UP CARD #2", "Do NOT edit")


def step9_window() -> str:
    """Raw text between the `## Step 9` heading and the next `## Step `
    heading — C03's whole surface. Heading loss is a RED naming the parser's
    contract (the rewrite stays inside step 9; nothing else in the note
    moves)."""
    assert NOTE.is_file(), f"cf-145 C03: {NOTE} missing — the runbook note has no host"
    lines = NOTE.read_text().splitlines()
    start = next((i for i, ln in enumerate(lines) if re.match(r"^## Step 9\b", ln)), None)
    assert start is not None, "cf-145 C03: no `## Step 9` heading found — the window's authority moved"
    end = next((i for i in range(start + 1, len(lines)) if re.match(r"^## Step \d+\b", lines[i])), len(lines))
    return "\n".join(lines[start:end])


def _chart_annotation_keys() -> list[str]:
    """The landed C01 pair, read from charts/radiance values (one authority):
    app-template.defaultPodOptions.annotations keys."""
    vals = R.chart_values()
    ann = (((vals.get("app-template") or {}).get("defaultPodOptions") or {}).get("annotations"))
    assert isinstance(ann, dict) and ann, (
        "cf-145 C03 T3: charts/radiance carries no defaultPodOptions.annotations pair yet — "
        "C01 has not landed (the note must pin the LANDED keys; wave-2 dependency)"
    )
    return sorted(ann)


def _monitoring_entry() -> tuple[str, str, str, str]:
    """(provider name, entry key, folder display, url tag segment) from the
    landed C02 surfaces — parsed, never hardcoded here."""
    vals = yaml.safe_load(MONITORING_VALUES.read_text())
    g = vals.get("grafana") or {}
    dashboards = g.get("dashboards") or {}
    hits = [(pk, ek) for pk, entries in dashboards.items() for ek in (entries or {}) if ek == "radiance"]
    assert hits, (
        "cf-145 C03 T3: no grafana.dashboards.<provider>.radiance entry in services/monitoring "
        "values — C02 has not landed (wave-2 dependency)"
    )
    (pk, ek) = hits[0]
    prov = [p for p in ((g.get("dashboardProviders") or {}).get("dashboardproviders.yaml") or {}).get("providers", [])
            if p.get("name") == pk]
    assert prov, f"cf-145 C03 T3 (R8): dashboards key {pk!r} has no same-named provider — C02 landed half-wired"
    url = (dashboards[pk][ek] or {}).get("url", "")
    m = re.search(r"/tag/(v[^/]+)/", url)
    assert m, f"cf-145 C03 T3: radiance entry url {url!r} carries no /tag/v…/ segment to pin"
    return pk, ek, prov[0].get("folder", ""), m.group(1)


# --- T1 (AC1): the deferral prose is retired from the window -------------------


def test_t1_followup_card_deferral_retired():
    window = step9_window()
    assert RETIRED_PHRASES[0] not in window, (
        "cf-145 C03 AC1: `FOLLOW-UP CARD #2` still defers inside the step-9 window — "
        "cf-145 IS that card; the paragraph must record the landed state (designed-red until the rewrite)"
    )


def test_t1_do_not_edit_prohibition_retired():
    window = step9_window()
    assert RETIRED_PHRASES[1] not in window, (
        "cf-145 C03 AC1: the `Do NOT edit services/monitoring/prod/values.yaml in this run` "
        "prohibition retired WITH its paragraph (C02 landed the edit) — no defanged copy either"
    )


# --- T2 (AC2): the window names every wired surface ----------------------------


def test_t2_scrape_surface_pointers():
    window = step9_window()
    for needle in ("charts/radiance", "k8s.grafana.com"):
        assert needle in window, (
            f"cf-145 C03 AC2: step-9 window never names {needle!r} — the rewrite must point the "
            "scrape at the annotation pair shipped in charts/radiance"
        )


def test_t2_job_identity_pointer():
    """The job shape is the label-fallback `radiance` (plan R5b) — the note
    states it; the monitor-object `<ns>/<name>` flavor must NOT appear."""
    window = step9_window()
    assert re.search(r"job[^.\n]{0,40}radiance\b", window, re.I), (
        "cf-145 C03 AC2: no `job radiance` identity in the window (R5b: annotationAutodiscovery "
        "fills job from the app.kubernetes.io/name label — the note names the job the owner will query)"
    )
    assert "default/radiance" not in window, (
        "cf-145 C03 AC2: the window carries the retired `<ns>/<monitor-name>` job shape — "
        "that identity belongs to the rejected ServiceMonitor path (D-8), not the annotation pair"
    )


def test_t2_dashboard_entry_and_tag_pointers():
    window = step9_window()
    assert "grafana.dashboards.inference.radiance" in window, (
        "cf-145 C03 AC2: the window does not name the grafana.dashboards.inference.radiance "
        "entry (NEW inference provider folder, display Inference) — the owner ruling OQ-4 landing"
    )
    assert "v1.17.0" in window, "cf-145 C03 AC2: the v1.17.0 tag pin is not stated in the window"


def test_t2_manual_sync_owner_note():
    """F-β/R1: neither sync is automated, so the note keeps the appearance
    promise owner-side — both Application names plus the sync act, in
    unconditional wording (DECISIONS D-10)."""
    window = step9_window()
    for needle in ("gpu-ai", "monitoring-grafana"):
        assert needle in window, (
            f"cf-145 C03 AC2: the window omits the {needle} Application — live scrape + dashboard "
            "appearance require the owner's manual syncs; the note must name them"
        )
    assert re.search(r"sync", window, re.I) and re.search(r"owner", window, re.I), (
        "cf-145 C03 AC2: no owner+sync framing in the window — the rollout-gated download law (R1) "
        "stays stated owner-side, never promised by the entry landing"
    )


def test_t2_stats_contingency_present_and_honest():
    """/stats stays the ONE-SENTENCE contingency for the honest-retirement
    branch (plan R3/OQ-6): present, and never restated as the wired mechanism."""
    window = step9_window()
    assert "/stats" in window, (
        "cf-145 C03 AC2: the /stats contingency sentence is missing — the R3 fallback path "
        "(404 -> point the dashboard question at step-time series and RETIRE the metrics claim) "
        "must be on the page, explicitly contingent (field table UNVERIFIED per RESEARCH §R14)"
    )
    assert re.search(r"(unverif|contingenc|if )", window, re.I), (
        "cf-145 C03 AC5: the /stats line carries no contingency/unverified marker — "
        "an unhedged /stats sentence restates the claim instead of holding the retirement branch"
    )


# --- T3 (AC3): cross-equality — the note pins the LANDED strings ---------------


def test_t3_annotation_key_identity_matches_landed_chart():
    """Derived, not duplicated: each key that charts/radiance actually ships
    (prefix k8s.grafana.com pinned by T2, suffix per key here) must appear in
    the window — a rename in EITHER surface turns this RED instead of leaving
    the note silently stale."""
    window = step9_window()
    for key in _chart_annotation_keys():
        assert key.startswith("k8s.grafana.com/"), (
            f"cf-145 C03 T3: landed annotation key {key!r} is outside the ruled k8s.grafana.com/ "
            "namespace — the pair's identity itself moved (re-rule, then rewrite the note)"
        )
        suffix = key[len("k8s.grafana.com/"):]
        assert suffix in window, (
            f"cf-145 C03 AC3: landed key suffix {suffix!r} (charts/radiance values) is absent from "
            "the step-9 window — the note and the shipped pair disagree"
        )


def test_t3_provider_entry_identity_matches_landed_values():
    window = step9_window()
    pk, ek, folder, tag = _monitoring_entry()
    assert f"grafana.dashboards.{pk}.{ek}" in window, (
        f"cf-145 C03 AC3: the window names a different entry path than the landed "
        f"grafana.dashboards.{pk}.{ek} — provider/entry rename desyncs note from values"
    )
    if folder:
        assert folder in window, (
            f"cf-145 C03 AC3: the landed provider folder display {folder!r} is absent from the window"
        )
    assert tag in window, f"cf-145 C03 AC3: the landed url tag {tag!r} is absent from the window"
    assert tag == f"v{R.IMAGE_TAG}", (
        f"cf-145 C03 AC3: landed url tag {tag!r} != v+IMAGE_TAG {R.IMAGE_TAG!r} — the C02 "
        "tag-coupling law broke between the surfaces (test_dashboard_filing T3 names it too)"
    )


def test_t3_job_name_matches_chart_identity_authority():
    """The job identity is a DERIVED fact: app-template builds the pod label
    app.kubernetes.io/name from the chart name authority (global.nameOverride
    == radiance); the note's job word must track it, not float free."""
    vals = R.chart_values()
    name = ((vals.get("app-template") or {}).get("global") or {}).get("nameOverride")
    assert name == "radiance", (
        f"cf-145 C03 T3: charts/radiance nameOverride is {name!r}, want radiance — the label-fallback "
        "job identity (R5b) moved, so BOTH the note and this pin need the fresh ruling"
    )
    assert re.search(r"job[^.\n]{0,40}radiance\b", step9_window(), re.I), (
        "cf-145 C03 AC3: the window's job pointer does not equal the chart-derived `radiance`"
    )
