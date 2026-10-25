# C01 boot-safety contract (feature
# .agents/plans/2026/2026-10-bug-llama-swap-echo-proxy-port/, chunks/C01.md):
# every rendered llama-swap config must LOAD under the validator-bearing
# binary (unified-vulkan-262 rebuild .. v266 — internal/config/macros.go
# byte-identical across those releases, verified 2026-10-25). The 2026-10-25
# gpu crash-loop (`model ornith-1.5-122b-q3: proxy uses ${PORT} but cmd does
# not`) is the proof the binary enforces the rule at load; there is no docker
# in this env and the `-validate` path was never run, so these tests are the
# pre-merge offline proof (the sibling ticket's C05 evidence pass is the
# live check post-merge).
#
# The simulation lives in llama_swap_testlib (port_rule_violations /
# effective_proxy) and mirrors macros.go step for step — comment strip,
# default-proxy injection, mergeModelMacros + substituteMacroList, then the
# ${PORT} test on the EXPANDED strings — enumerating EVERY violator where
# Go stops at the first.
#
# Skipped when the helm binary or the chart's app-template dependency is
# missing (same gate as the rest of the suite; CI installs both).

from __future__ import annotations

import pytest

import llama_swap_testlib as L

_ok, _reason = L.helm_ready()
pytestmark = pytest.mark.skipif(not _ok, reason=_reason)


def _render_cfg(render: str) -> dict:
    if render == "default":
        return L.rendered_config_default()
    return L.rendered_config(render)


@pytest.mark.parametrize("render", ["default", "gpu", "gpu-ai"])
def test_c01_port_rule_invariant(render):
    """ACCEPTANCE C01-1: each render must survive the deployed binary's
    macros.go port rule (macros.go:182-184): a model's (expanded) proxy may
    use ${PORT} only when its (expanded) cmd does. Red at handoff:
    default — all 58 entries are default-disabled echoes (CATALOG_IDS),
    gpu — the 24 GPU_ECHO_IDS; gpu-ai is live-only and green (56 composed
    cmds carry ${server-cmd} whose value holds --port ${PORT}, whisper +
    rana raw cmds carry the literal). A green here is the pre-merge proof
    the config loads. Owner of the fix: C02."""
    cfg = _render_cfg(render)
    violations = L.port_rule_violations(cfg)
    assert not violations, (
        f"{render}: {len(violations)} model(s) fail the llama-swap port rule "
        f"(macros.go:182-184, identical v262-v266) - the binary would refuse "
        f"to load this config, the 2026-10-25 crash-loop: {violations} (C02)"
    )


@pytest.mark.parametrize("cluster", ["gpu", "gpu-ai"])
def test_c01_echo_entries_proxy_is_port_free(cluster):
    """ACCEPTANCE C01-2 (positive pin, RE-EXPRESSED — TEST_SPEC §7sexies):
    every fail-fast echo entry must proxy through a value that carries NO
    ${PORT} after macro expansion. 'No proxy key' is deliberately NOT the
    target state: the binary defaults a missing proxy to
    http://localhost:${PORT} (macros.go:127-129) BEFORE the rule runs, so key
    absence fails the very check this ticket fixes. Red at handoff on gpu
    (all 24 echoes carry the ${PORT} proxy); vacuous on gpu-ai (no echo
    entries). This is the compensating leg of the golden-proxy excision in
    test_c02_2_per_model_fields_deep_equal. Owner of the fix: C02."""
    cfg = L.rendered_config(cluster)
    offenders = [
        mid for mid in sorted(L.all_models_of(cfg))
        if L.is_echo_cmd(cfg["models"][mid].get("cmd") or "")
        and "${PORT}" in L.effective_proxy(cfg, mid)
    ]
    assert not offenders, (
        f"{cluster}: echo-shaped models proxy through ${{PORT}} but their cmd "
        f"never uses it - unloadable by the validator-bearing binary: "
        f"{offenders} (C02)"
    )
