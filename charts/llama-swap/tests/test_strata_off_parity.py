# OFF-state byte parity — the run-2 plan's central preservation gate
# (Commands line "OFF parity"; chunks/C01.md AC1). The default render is
# captured byte-exact at the run-2 base commit (evidence/off-parity/, test-
# session property); ANY chart edit that changes what a default-OFF render
# produces — pod shape keys in the wrong (tree-global) place, a re-keyed
# globalMounts collision, a template that lost its gate — turns this red and
# is named r2-C01.
#
# cf-86 grows the catalog deliberately, and CR1.4/P5 renders every catalog id in
# every render, so the OFF render's models map is the one surface allowed to
# move. The file splits the gate in two: the structural arm pins what may move
# (only approved cf-86 ids, arriving as id-prefixed fail-fast echoes; everything
# else byte-identical) and is chunk-independent; the byte arm stays pinned to the
# fixture and is re-baselined by the test session in the landing chunk's round —
# never while the structural arm is red, which would bake a dev leak into the new
# baseline. Provenance + era chain: evidence/off-parity/PROVENANCE.md.

from __future__ import annotations

import subprocess

import pytest

import strata_testlib as S

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)


def test_c01_off_parity_provenance_fixture_present():
    assert S.OFF_FIXTURE.is_file(), (
        "evidence/off-parity/render-default.yaml missing — fixture breakage, not a code red "
        "(test-session property; regenerate ONLY via the test session)"
    )
    assert S.OFF_PROVENANCE.is_file(), "off-parity PROVENANCE.md missing"


@helm
def test_c01_off_render_changed_only_by_sanctioned_catalog_growth():
    """The byte gate's chunk-independent companion, added because cf-86 grows the
    catalog on purpose (C03/C04 each add a llama.cpp family, and CR1.4/P5 renders
    every catalog id everywhere, so the OFF render's models map MUST grow).
    Everything that byte-parity was actually built to catch — pod shape keys in
    the wrong tree-global place, a globalMounts re-key, a template that lost its
    gate, a strata leak into the OFF render — must stay identical, and each
    allowed addition must arrive as an id-prefixed fail-fast echo. Green here is
    what makes a fixture re-baseline safe; red means dev changed the OFF render,
    and a re-baseline is NOT the fix."""
    import llama_swap_testlib as L

    out = subprocess.run(
        ["helm", "template", S.RELEASE, str(S.CHART_DIR), "--set", "domain=test.example.com"],
        capture_output=True, text=True, timeout=300,
    )
    assert out.returncode == 0, out.stderr
    cur = _docs_of(out.stdout)
    base = _docs_of(S.OFF_FIXTURE.read_text())

    same_kind = {(d.get("kind"), d.get("metadata", {}).get("name")) for d in cur}
    base_kind = {(d.get("kind"), d.get("metadata", {}).get("name")) for d in base}
    assert same_kind == base_kind, (
        f"OFF render gained/lost objects: +{sorted(same_kind - base_kind)} -{sorted(base_kind - same_kind)} "
        "— a template appeared or lost its gate"
    )
    cur_cm, base_cm = _config_map(cur), _config_map(base)
    name = cur_cm["metadata"]["name"]
    assert name == base_cm["metadata"]["name"], "the llama-swap config ConfigMap was renamed (r2-C01)"

    def _others(docs):
        return [d for d in docs if not (d.get("kind") == "ConfigMap" and d["metadata"]["name"] == name)]

    assert _others(cur) == _others(base), (
        f"a rendered object other than the {name} ConfigMap changed — pod shape, mounts, "
        "or a template gate moved in the default-OFF render (r2-C01)"
    )
    assert {k: v for k, v in cur_cm.items() if k != "data"} == {k: v for k, v in base_cm.items() if k != "data"}, (
        f"the {name} ConfigMap metadata diverged"
    )

    cur_cfg = S.yaml.safe_load(cur_cm["data"]["config.yaml"])
    base_cfg = S.yaml.safe_load(base_cm["data"]["config.yaml"])
    strays = sorted(
        k for k in (set(cur_cfg) | set(base_cfg)) - {"models", "matrix"} if cur_cfg.get(k) != base_cfg.get(k)
    )
    assert not strays, (
        f"OFF config changed outside the models map and matrix: {strays} — "
        "macros/peers/hooks/scalars are off-scope in the default-OFF state"
    )
    # The chart-level matrix vars join every render, OFF included; the confined
    # growth law pins which letters may appear and forbids any combo change.
    diffs = L.cf86_matrix_growth_violations(base_cfg, cur_cfg)
    assert not diffs, "OFF render matrix growth outside the sanctioned cf-86 shape:\n" + "\n".join(diffs)
    gained = sorted(set(cur_cfg["models"]) - set(base_cfg["models"]))
    lost = sorted(set(base_cfg["models"]) - set(cur_cfg["models"]))
    assert not lost, f"OFF render lost model entries: {lost}"
    assert set(gained) <= set(L.CF86_NEW_IDS), (
        f"OFF render gained ids outside the cf-86 approved table: {sorted(set(gained) - set(L.CF86_NEW_IDS))}"
    )
    for mid in gained:
        entry = cur_cfg["models"][mid]
        cmd = str(entry.get("cmd") or "")
        assert L.is_echo_cmd(cmd), f"OFF render makes {mid} runnable: {cmd!r}"
        assert mid in cmd and "${" not in cmd, f"OFF render/{mid} echo wrong shape: {cmd!r}"
    for mid in sorted(set(base_cfg["models"]) & set(cur_cfg["models"])):
        assert cur_cfg["models"][mid] == base_cfg["models"][mid], (
            f"OFF render/{mid} entry changed — existing catalog entries are frozen in the OFF state"
        )


def _docs_of(stdout: str) -> list:
    return [d for d in S.yaml.safe_load_all(stdout) if isinstance(d, dict)]


def _config_map(docs) -> dict:
    """The rendered object holding the llama-swap config.yaml — named by the
    chart, not the release name, so it is found by payload rather than by name."""
    hits = [d for d in docs if d.get("kind") == "ConfigMap" and "config.yaml" in (d.get("data") or {})]
    assert len(hits) == 1, f"expected one config.yaml ConfigMap, got {[d['metadata']['name'] for d in hits]}"
    return hits[0]


@helm
def test_c01_off_render_byte_identical_to_baseline():
    """The exact plan command, compared byte-for-byte — helm toYaml re-wrap
    is behavior here because the claim IS 'a default render changed nothing'
    (Q-C ruling; prototype-verified in the plan's architecture section).
    Catalog growth (C03/C04) is the one sanctioned way this fixture moves: it is
    re-baselined by the test session in the landing chunk's round, and only while
    test_c01_off_render_changed_only_by_sanctioned_catalog_growth is green."""
    out = subprocess.run(
        ["helm", "template", S.RELEASE, str(S.CHART_DIR), "--set", "domain=test.example.com"],
        capture_output=True, text=True, timeout=300,
    )
    assert out.returncode == 0, out.stderr
    baseline = S.OFF_FIXTURE.read_text()
    if out.stdout == baseline:
        return
    a, b = out.stdout.splitlines(), baseline.splitlines()
    first = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
    ctx = "\n".join(
        f"  render L{i}: {a[i]!r}" for i in range(max(0, first - 2), min(len(a), first + 3))
    ) if a else "  render: EMPTY"
    raise AssertionError(
        f"OFF render diverged from the baseline at line {first + 1} "
        f"(len {len(a)} vs {len(b)}):\n{ctx}\n"
        "This is the byte-parity gate: default-OFF must render exactly the "
        "pre-C01 tree — r2-C01 (or a re-baseline routed through the test session)."
    )
