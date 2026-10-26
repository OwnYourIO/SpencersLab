# Pre-chunk render baseline — debug-flash-next-vulkan-oom (C03/C04 blast radius)

`gpu.config.yaml` / `gpu-ai.config.yaml` are the verbatim `config.yaml`
ConfigMap DATA strings of the two documented extract-and-render commands
(TEST_SPEC §1 method, `llama_swap_testlib.render_docs` inputs) captured by the
agent-test session **2026-10-26** at commit `561d0559e` (clean tree — no
C01/C03/C04 edits existed yet; C02 was skipped by the operator, so the service
layer carries no flash-next containment either).

Toolchain: helm **v3.16.4** (`get.helm.sh`, same version as the 2026-10-22
goldens), app-template **5.0.1**, python **3.14.4**, `pyyaml` as imported by
the harness. Round-trip verified at capture: re-rendering via
`llama_swap_testlib.render_docs` and extracting the same data key reproduces
these files byte-for-byte.

Contract role: chunks/C03.md AC2 ("zero changes outside the flash-next family
IDs") and AC3 ("the gpu render is byte-identical to pre-chunk") diff the live
render against these fixtures — this is the "approved pre-chunk table" the
plan's Commands section names. Unlike `tests/golden/` (which predates the
flash-next/ornith catalog and can only pin the golden-era IDs), this baseline
covers the entire current surface.

The flash-next family itself is the sanctioned divergence zone
(`llama_swap_testlib.FLASHNEXT_FAMILY_IDS`); see TEST_SPEC §8 for the one
documented exception on the gpu side (derived display fields).
