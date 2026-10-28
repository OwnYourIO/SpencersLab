# OFF-state byte parity — the run-2 plan's central preservation gate
# (Commands line "OFF parity"; chunks/C01.md AC1). The default render is
# captured byte-exact at the run-2 base commit (evidence/off-parity/, test-
# session property); ANY chart edit that changes what a default-OFF render
# produces — pod shape keys in the wrong (tree-global) place, a re-keyed
# globalMounts collision, a template that lost its gate — turns this red and
# is named r2-C01. It is green TODAY and must STAY green.

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
def test_c01_off_render_byte_identical_to_baseline():
    """The exact plan command, compared byte-for-byte — helm toYaml re-wrap
    is behavior here because the claim IS 'a default render changed nothing'
    (Q-C ruling; prototype-verified in the plan's architecture section)."""
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
