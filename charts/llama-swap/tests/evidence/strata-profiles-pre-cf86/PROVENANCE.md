# strata-profile fixtures — pre-cf-86 state

Captured 2026-10-29 by the cf-86 agent-test session from the default chart
`strata-profile` ConfigMap DATA (render_on path: `helm template
gpu-ai-llama-swap charts/llama-swap --set domain=test.example.com` + the
seven strata flags), branch tip `4f7126689`, CLEAN tree (plan/research
commits only — no cf-86 dev edit existed), helm v3.16.4 + app-template 5.0.1.

Both JSONs are parse-valid (json.loads asserted at capture).

Purpose: cf-86 adds inner-matrix rungs (C01 abliterated, C02 orca, C06
q4) whose chunk ACs pin "the existing two profiles byte-unchanged".
Byte-unchanged is enforced against THESE fixtures (deep parse equality —
helm's toPrettyJson key order is a writer artifact, the parsed run-config
is the contract), never against a re-capture of the current render.

Test-author property: dev never edits this directory; a needed re-pin
routes coord -> test session (same rule as the goldens and
`../strata-peers-expected.yaml`).
