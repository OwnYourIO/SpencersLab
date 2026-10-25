# Decisions — 2026-10-bug-llama-swap-echo-proxy-port

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- Immutable-tests rule carries over from the sibling ticket: C01 runs ONLY in
  the agent-test session; tests it writes are the contract for C02 dev; a test
  judged faulty routes back to the test session (coord→user), never edited by
  the coder. Amendment discipline = TEST_SPEC.md §7-chain style (old-vs-new
  assertion audit + arithmetic + goldens-diff-empty proof).
- Goldens (`charts/llama-swap/tests/golden/*.config.yaml`) stay byte-untouched.
  Where the fix is deliberately STRICTER than a golden (echo proxy lines), the
  divergence is an explicit recorded supersession in TEST_SPEC, never a golden
  edit.
- Echo cmd STRINGS stay byte-exact (P3 bar) — this ticket removes only the
  proxy line from echo entries.
- Comment quality: comment-slop rules apply to the one new why-comment in C02
  and the rewritten image comment in C03 (constraint + provenance, no
  restatement, no falsified claims left standing).

## Decisions
- 2026-10-25 human: fast-lane fix ticket on branch
  bug-llama-swap-echo-proxy-port (worktree
  /home/coder/.local/share/opencode/worktree/5e680f/bug-llama-swap-echo-proxy-port,
  cut from origin/main 90e660569). Alternative rejected: fold the fix into the
  sibling ticket's aftermath — production gpu box is down, separate tight scope.
- 2026-10-25 human: proper image pin IN THIS TICKET (immutable versioned
  unified tag if it exists, else digest pin; keep the image honest — whisper
  bootstrap needs a unified-lineage image). Alternative rejected: fix config
  only and pin later — the mutable pin is half the root cause.
- 2026-10-25 plan: FALSIFIED ASSUMPTION 1 — tag-content drift. The chart
  comment claimed `unified-vulkan-262` was a release-versioned tag "so the
  digest is stable"; upstream rebuilt the tag in place, and the rebuilt content
  carries internal/config/macros.go's `${PORT}`-proxy check (verified present
  in ALL of v262–v266 source tarballs at /tmp/opencode/ls266, identical error
  string at macros.go:183). The pre-incident node ran the PRE-rebuild content.
  Consequence: trust only digests + re-verification, never tag reputation; C03
  records the pin's digest and adds renovate management.
- 2026-10-25 plan: FALSIFIED ASSUMPTION 2 — golden-as-boot-proof gap. The
  golden gpu.config.yaml carries `proxy: http://localhost:${PORT}` on its 6
  disabled echoes and the box booted with it for weeks — the golden encodes the
  OLD binary's tolerance, not a validator-checked truth. Byte parity against
  that golden therefore CANNOT prove boot-safety under a validator-bearing
  binary. Consequence: the C01 boot-safety invariant (a faithful offline
  simulation of macros.go) is the new standing bar, deliberately stricter than
  the golden where the golden encoded pre-check tolerance; the 3
  golden-survivor echo proxy lines are an explicit recorded supersession.
- 2026-10-25 plan: fix shape = conditional proxy emission keyed on the FINAL
  composed cmd's post-expansion `${PORT}` content (mirrors macros.go exactly:
  the check runs after user-macro expansion). Rejected: (a) drop proxy from
  ALL entries — breaks the golden-pinned proxy lines on live entries and moves
  gpu-ai's CM sha; (b) add `${PORT}` to echo cmds — mutates P3 byte-pinned
  echo strings and changes llama-swap's port-allocation semantics.
- 2026-10-25 plan: pin target recommendation = `unified-vulkan-266`
  (release-versioned unified tag for the current llama-swap release v266;
  existence verified via registry enumeration; digest recorded at plan time
  for a two-pull stability check). Alternative for the user's eye at approval:
  digest-pin of the CURRENT unified-vulkan-262 resolution
  (sha256:038bb0938868...) — freezes exactly the binary the cluster runs once
  the config is fixed, but is opaque provenance, un-auditable llama.cpp rev
  (no docker daemon here), and un-renovatable. User ruling already prefers the
  versioned unified tag when one exists; the alternative stays a recorded
  fallback if the 266 stability check fails.
- 2026-10-25 plan: the pre-existing main-branch test failure
  (test_render.py python 3.12.15 vs renovate-bumped 3.15.1) is handled in C01
  via the §7 amendment discipline — renovate is the source of truth for
  managed tags, so the test follows the chart, never the reverse. Rejected:
  revert the renovate bump; leave the failure standing (the ticket's green bar
  must be honest — verified baseline is 1f/118p/1s, not the 0f/119p/1s the
  kickoff assumed).
- 2026-10-25 human: PLAN APPROVED with pin target `unified-vulkan-266`
  (option 1 at approval round). The digest-of-current-262 alternative stays
  recorded as the fallback if C03's two-pull stability check on 266 fails —
  in that case dev reports via RESULT before pinning. Compressed kickoff model
  routing confirmed: plan=qwen3.8-2.4t-a95b, rest=qwen3.8-27b (no override).
- 2026-10-25 plan: wave order — C01 (test session) first; C02 then C03 in wave
  2 (id order). C02 and C03 file sets are independent; id order keeps one
  unambiguous suite bar (C02 flips the C01 reds green; C03 re-runs the green
  suite).

## Deferred
- flash-next-q3 fit work (live investigation, separate ticket).
- Cluster-side boot verification: this ticket cannot observe the pod until the
  PR lands and ArgoCD syncs (user-owned). The sibling ticket's C05 evidence
  pass (c05_expected_evidence.yaml gpu_box "config load + model count") IS the
  live verification of this fix.
## 2026-10-25 — C01 finding: third falsified assumption + reshaped C02 mechanism (coord)

- FALSIFIED: "echo entries render WITHOUT a proxy key" (approved plan's C02
  mechanism). macros.go:127-129 (byte-identical v262-v266) injects the default
  `http://localhost:${PORT}` proxy into any model lacking the key BEFORE the
  port rule runs; upstream's own config_test.go:228 pins that a key-less,
  PORT-less cmd fails with the exact incident error. Dropping the key
  reproduces the crash-loop.
- CONTROLLING REWORD for C02 acceptance (supersedes the plan file's "24 proxy
  lines removed" + "proxy absent" wording; user-ruled 2026-10-25): echo-shaped
  entries render an EXPLICIT `${PORT}`-free proxy — literal `proxy: "none"`
  (C01-verified url.Parse-safe at load.go:188; runtime-inert since the
  fail-fast cmd exits before any proxying). GPU CM diff = exactly 24 proxy
  lines CHANGED to `none`, nothing else; gpu-ai CM sha 9f359249cee7 unchanged.
- C01's committed contract (c48c0b270) already pins the reshaped property
  (port-free effective proxy) - dev implements to the contract, review audits
  both.
