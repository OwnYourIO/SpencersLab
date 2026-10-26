# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- Plan of record: `2026-10-26-debug-flash-next-vulkan-oom.md` in this folder; validation = the plan's "Commands" (helm lint/template + chart pytest contract + readonly cluster probes); landing on main is user-owned (PR only), no hand-bumped chart versions/image tags anywhere in this ticket.
- `RESEARCH.md` will land next to the plan file before C03 is rewritten; every later agent reads it at run start.

## Decisions
- 2026-10-26 plan: Structure the ticket as evidence(C01) → containment(C02) → research-gated fix(C03) → cluster-verified landing(C04), with C03 explicitly unapproved until the post-research reintegration pass rewrites it. Alternatives rejected: (a) planning the fix now from hypotheses (violates the no-guesses research rule; the Vulkan-vs-driver-vs-arch split is exactly what agent-research must settle); (b) no initial plan until research lands (violates the user's explicit directed flow).
- 2026-10-26 plan: C02 containment = per-ID `disabled:` messages on gpu-ai's service values (established repo pattern; echo wins over enablement/cmd), gated on operator approval, and it doubles as the permanent landing if research concludes "unrunnable today". Rejected: removing the flash-next family from the chart catalog (rungs were enabled by the operator's accepted 2026-10-22 decision; deletion destroys the fit data and the matrix design; disable is reversible and consumer-visible).
- 2026-10-26 plan: treat `/api/hardware`'s gfx1151 "dedicated 512 MiB" reading as an *unverified lead*, not a fact — C01 must confirm the device-local budget from llama.cpp's own `--list-devices` and host `mem_info_*` before any conclusion depends on it. Rejected: building the plan's root-cause assumption directly on that number (single-sourced, parse semantics unknown).
- 2026-10-26 plan: any C04 load attempt requires operator-consented freeze protocol (one attempt, no retry loops, journal-clean proof) because the exact kernel signature of this crash previously froze the single-node cluster for ~30 min (2026-10-18/19, per the 2026-10-20 offline-investigation plan). Rejected: free reproduction on a live single-node cluster.

## Deferred
- C02 execution pending the operator's containment-vs-debug-live choice at plan approval.
- C03 branch selection (A flags / B kernel params / C engine / D accept) — post-research.
- The `/api/hardware` detector-version oddity (`v265` reported by an image pinned `unified-vulkan-266`) — C01 notes it; separate chore ticket if it proves real.
