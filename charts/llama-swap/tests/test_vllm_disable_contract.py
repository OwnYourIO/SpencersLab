# cf-143 C01 — the GitOps-disable contract for the vllm lane (chunks/C01.md
# Tests, bullets 2-3 + 5; owner Q3 ruling, DECISIONS D6). The vllm engine
# (charts/vllm — the magiccodingman/vllm-radiance FORK, NOT the cf-143
# radiance engine this card adds) is disabled COMMENTED-OUT everywhere:
# the charts.vllm ApplicationSet entry and the peers.vllm block go to
# comments, the top-level `vllm:` block survives as an EMPTY `vllm: {}`
# key (the workflow-extraction survivor, EXPLORE gotcha 14), and the CI
# extraction hardens to `d.get('vllm') or {}` so the job also survives the
# owner's later cleanup of the key itself. charts/vllm/** stays
# byte-untouched — its pytest suite passing unchanged is the
# reversible-while-disabled guarantee (AC3, run-side, not asserted here).
#
# Pure file reads + one subprocess per leg: no helm needed, NO skip gate —
# a violated shape reads as an assertion red naming C01, never a silent
# skip (the repo mass-skip lesson, EXPLORE §4 / vllm_testlib helm_ready).
#
# Red state at handoff (designed): every leg is red until C01's dev lands
# the values/workflow/jsonc edits. The gpu-ai golden legs live in the
# re-pinned test_vllm_peer.py T4 and the parity wave-leg, not here.
#
# Run with the suite (per-directory): python3 -m pytest charts/llama-swap/tests -v

from __future__ import annotations

import json
import re
import subprocess

import pytest
import yaml

import llama_swap_testlib as L
import strata_testlib as S

SERVICE = L.REPO_ROOT / "services" / "gpu-ai" / "prod" / "values.yaml"
WORKFLOW = L.REPO_ROOT / ".github" / "workflows" / "vllm-render-tests.yaml"
JSONC = L.REPO_ROOT / ".opencode" / "opencode.jsonc"


def _svc() -> dict:
    assert SERVICE.is_file(), f"C01: {SERVICE} missing"
    return yaml.safe_load(SERVICE.read_text())


def _strip_jsonc_comments(text: str) -> str:
    """String-aware comment stripper — the suite's catalog loader
    (test_catalog_contract.py, cf-86 C05) copied verbatim: AC5 demands the
    catalog keep parsing through the SAME loader after the comment-out."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            out.append(c)
            i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\":
                    out.append(text[i:i + 2])
                    i += 2
                    continue
                out.append(text[i])
                i += 1
            out.append('"')
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            i = n if end == -1 else end + 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


# --- AC1: the three live shapes of the GitOps disable --------------------------


def test_ac1_charts_entry_gone():
    """C01 AC1: `d['charts']` has no live vllm key — the ApplicationSet stops
    rendering the gpu-ai-vllm Application (gpu-ai-vllm already sits at
    replicas 0 out-of-band; this makes the disable declarative)."""
    charts = _svc().get("charts") or {}
    assert "vllm" not in charts, (
        "cf-143 C01 AC1: charts.vllm is still a live entry — comment it out (the "
        "reversible disable), do not delete the block"
    )


def test_ac1_peers_entry_gone_top_key_empty():
    """C01 AC1 legs 2+3: peers.vllm gone from the LIVE parsed subtree, and the
    top-level vllm key exists and equals EXACTLY {} — the `{}` flow-mapping,
    not a null value (`vllm:` with nothing parses to None and the extraction
    leg `d.get('vllm') or {}` would hide that drift as fine; the workflow's
    own dump-then-render path is the authority for keeping the key real)."""
    peers = ((_svc().get("llama-swap") or {}).get("config") or {}).get("peers") or {}
    assert "vllm" not in peers, (
        "cf-143 C01 AC1: llama-swap.config.peers.vllm is still live — the peer block "
        "must be commented out with its law comments (reversible disable, Q3)"
    )
    assert "vllm" in _svc(), "cf-143 C01 AC1: the top-level vllm: key must REMAIN (empty-key shape, gotcha 14)"
    assert _svc()["vllm"] == {}, (
        f"cf-143 C01 AC1: top-level vllm is {_svc()['vllm']!r}, want the explicit empty "
        "flow map {} (overrides commented underneath, key kept)"
    )


# --- AC2 + gotcha 14, both directions: the workflow extraction leg ------------


def _extraction_script() -> str:
    """The workflow's service-level-values step verbatim (the run block), so
    THIS test executes what CI executes — a hardened needle that drifted
    away from the actual step is caught, not papered over."""
    wf = yaml.safe_load(WORKFLOW.read_text())
    steps = ((wf.get("jobs") or {}).get("test") or {}).get("steps") or []
    if not steps:
        for job in (wf.get("jobs") or {}).values():
            steps = job.get("steps") or []
            if steps:
                break
    runs = [s.get("run") for s in steps if isinstance(s, dict) and isinstance(s.get("run"), str)]
    hits = [r for r in runs if "values.yaml" in r and "vllm" in r and "helm template" in r]
    assert hits, "cf-143 C01 AC2: no service-level-values extraction+render step found in vllm-render-tests.yaml"
    return hits[0]


def _run_extraction(values_text: str, script: str) -> dict:
    """Execute the workflow's extraction line against a scratch copy of the
    service values (the step reads services/gpu-ai/prod/values.yaml by fixed
    path — rewrite the two path literals to the scratch pair), then dump the
    extracted subtree back for the assertion."""
    import os
    import tempfile

    with tempfile.TemporaryDirectory(prefix="cf143-extract-") as td:
        src = os.path.join(td, "values.yaml")
        with open(src, "w") as fh:
            fh.write(values_text)
        out_vals = os.path.join(td, "extracted.yaml")
        py = script.replace("services/gpu-ai/prod/values.yaml", src)
        py = re.sub(r"/tmp/vllm-vals\.yaml", out_vals, py)
        # Run ONLY the python one-liner(s) of the step — the helm template
        # line follows and is irrelevant to the extraction contract.
        lines = [ln for ln in py.splitlines() if ln.strip().startswith("python3 ")]
        assert lines, "cf-143 C01 AC2: the extraction step has no python3 line to execute"
        for ln in lines:
            proc = subprocess.run(ln, shell=True, capture_output=True, text=True, timeout=120)
            assert proc.returncode == 0, (
                f"cf-143 C01 AC2: the workflow extraction line raised (gotcha 14 violated): "
                f"{proc.stderr.strip()[:300]}"
            )
        with open(out_vals) as fh:
            return yaml.safe_load(fh.read())


def test_ac2_workflow_hardened_and_survives_empty_key():
    """C01 AC2 + Tests bullet 3, direction 1: the amended expression, run
    against the amended live values, yields {} without raising."""
    script = _extraction_script()
    assert "d.get('vllm') or {}" in script, (
        "cf-143 C01 AC2: the workflow extraction is not hardened to d.get('vllm') or {} "
        "— the bare d['vllm'] raises the moment the owner cleans the empty key up"
    )
    extracted = _run_extraction(SERVICE.read_text(), script)
    assert extracted == {}, (
        f"cf-143 C01 AC2: the hardened extraction of the live values yields {extracted!r}, "
        "want {} (the empty-key shape is the survivor leg of gotcha 14)"
    )


def test_ac2_workflow_survives_absent_key():
    """C01 AC2, direction 2 (belt-and-suspenders per the chunk): with the
    top-level vllm key REMOVED entirely (the owner's later cleanup), the same
    extraction still yields {} — the ` or {}` half of the hardening."""
    script = _extraction_script()
    doc = _svc()
    doc.pop("vllm", None)
    extracted = _run_extraction(yaml.safe_dump(doc), script)
    assert extracted == {} or extracted is None, (
        f"cf-143 C01 AC2: extraction of a key-removed values file yielded {extracted!r}, "
        "want the empty dict (d.get + or {} — no raise, no None rendered into helm -f)"
    )
    assert extracted == {}, (
        "cf-143 C01 AC2: the step dumped None rather than {} — `d.get('vllm') or {}` is the "
        "pinned expression; a plain d.get would dump null"
    )


# --- AC5: the provider catalog keeps parsing; no live vllm rows ---------------


def test_ac5_catalog_parses_and_vllm_rows_dead():
    """C01 AC5: the jsonc still parses via the suite's catalog loader and NO
    live qwen3.8-27b-vllm* row key remains (the three rows are commented out
    with a cf-143 note, one-edit-reversible)."""
    raw = JSONC.read_text()
    try:
        doc = json.loads(_strip_jsonc_comments(raw))
    except json.JSONDecodeError as exc:
        raise AssertionError(
            f"cf-143 C01 AC5: .opencode/opencode.jsonc no longer parses through the suite's "
            f"catalog loader after the comment-out — JSONC comment hygiene (no trailing comma "
            f"left dangling into the map close) is part of the disable: {exc}"
        )
    models = ((doc.get("providers") or {}).get("gpu-ai") or {}).get("models") or {}
    live = [k for k in models if k.startswith("qwen3.8-27b-vllm")]
    assert not live, (
        f"cf-143 C01 AC5: live vllm catalog rows remain: {live} — comment the three rows "
        "(qwen3.8-27b-vllm, -urgent, -low) out with the cf-143 marker"
    )


def test_ac7_cf143_markers_at_every_disable_site():
    """C01 AC7: every commented-out block carries a cf-143 marker so a
    re-enable is locate-and-uncomment. Region-scoped checks (not a file-wide
    count — the marker must sit where the reader looks for it): inside the
    charts block, inside the llama-swap config peers region, at the top-level
    vllm empty key, and in the jsonc beside the commented rows."""
    text = SERVICE.read_text()

    def region(start_re: str, end_re: str) -> str:
        m = re.search(start_re, text, re.M)
        assert m, f"cf-143 C01 AC7: region anchor {start_re!r} not found in service values"
        rest = text[m.end():]
        e = re.search(end_re, rest, re.M)
        return rest[: e.start() if e else len(rest)]

    sites = {
        # the charts block ends at the next top-level key
        "charts": region(r"^charts:\s*$", r"^[a-z]"),
        # the peers subtree runs from the peers: key to the matrix block
        "peers": region(r"^    peers:\s*$", r"^    matrix:"),
        # the top-level vllm block runs to the end of file (last key today)
        "vllm-key": region(r"^vllm:\s*$", r"^\S"),
    }
    missing = [name for name, blob in sites.items() if "cf-143" not in blob]
    assert not missing, (
        f"cf-143 C01 AC7: the commented-out block at {missing} carries no cf-143 marker — "
        "a re-enable must be a locate-and-uncomment operation (owner Q3)"
    )
    assert "cf-143" in JSONC.read_text(), (
        "cf-143 C01 AC7: .opencode/opencode.jsonc carries no cf-143 marker beside the "
        "commented vllm provider rows"
    )


# --- AC6 (sentinel half) + the naming-landmine bar ----------------------------


def test_sentinel_parity_full_llama_swap_render():
    """C01 Tests bullet 5, read against gotcha 5 (the only reading that can
    hold on the live tree): the FULL charts/llama-swap render on the service
    subtree legitimately carries the hf-token OVERRIDE_VIA_CUSTOM_VALUES
    sentinel string (custom-values injects the real UUID at the appset merge;
    the suite's existing sentinel arms are line-scoped for exactly this
    reason). The cf-143 C01 promise is that the vllm comment-out strands NO
    sentinel of its own: zero OVERRIDE_ lines mentioning vllm/radiance."""
    ok, reason = L.helm_ready()
    if not ok:
        pytest.skip(f"cf-143 C01 sentinel leg needs helm: {reason}")
    rendered = yaml.dump(L.render_docs("gpu-ai"))
    hits = [ln for ln in rendered.splitlines()
            if "OVERRIDE_" in ln and re.search(r"vllm|radiance", ln, re.I)]
    assert not hits, (
        f"cf-143 C01: the render carries {len(hits)} OVERRIDE_ strings on vllm/radiance lines, "
        f"e.g. {hits[0][:120] if hits else ''} — the disable must not strand a sentinel (gotcha 5)"
    )


def test_disable_comments_disambiguate_the_naming_landmine():
    """C01 Notes-for-dev: this chunk touches the vllm-RADIANCE fork surface;
    at least one disable comment must say so, or a later reader confuses the
    dormant fork with the cf-143 radiance engine (DECISIONS naming law)."""
    text = SERVICE.read_text()
    disabled = [ln for ln in text.splitlines()
                if ln.lstrip().startswith("#") and "cf-143" in ln]
    assert disabled, "cf-143 C01: no cf-143 comment lines in the service values at all (see AC7)"
    joined = " ".join(disabled).lower()
    assert "fork" in joined or "charts/vllm" in joined, (
        "cf-143 C01: the disable comments never disambiguate — they must name the "
        "vllm-radiance FORK surface (charts/vllm, magiccodingman/vllm-radiance) where "
        "'radiance' could be misread as the new engine"
    )


# --- the retirement pair that lives on the values surface ---------------------


def test_runbook_doc_kept_superseded_and_script_retired():
    """C01 Tasks/AC6 as a file-shape pin: the vllm runbook NOTE gets a
    DORMANT supersession header (body untouched), its contract SUITE retires
    (deleted — its doc target goes dormant). The negative needle also lives
    in surface.sh M4 (the chunk's Tests bullet 4); this pytest arm keeps the
    header CONTENT check beside the path check.

    S.REPO_ROOT names the repo root from the chart tests dir (strata_testlib
    home), the suite's convention for repo-wide file pins."""
    suite = S.REPO_ROOT / "tests" / "notes" / "vllm-runbook.sh"
    doc = S.REPO_ROOT / ".agents" / "notes" / "vllm-on-target-acceptance.md"
    assert not suite.exists(), (
        "cf-143 C01 AC6: tests/notes/vllm-runbook.sh still exists — the suite retires with "
        "the lane (delete it and record the retirement in TEST_SPEC §12)"
    )
    assert doc.is_file(), "cf-143 C01 AC6: .agents/notes/vllm-on-target-acceptance.md must remain (header-only edit)"
    head = "\n".join(doc.read_text().splitlines()[:30])
    assert "cf-143" in head and re.search(r"superseded", head, re.I), (
        "cf-143 C01 AC6: the runbook header does not name cf-143 + superseded within its "
        "first 30 lines (engine dormant, owner circles back — header only, body untouched)"
    )
