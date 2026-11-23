# Decisions — cf-6-feat-builder-bootstrap-3 (lane deployed, build failed)

Append-only. New entries at the bottom.

## Kickoff (compaction handoff)

- 2026-11-22 human: "Ok, so I deployed the builder and ran it, but it failed on the build:" — ERROR TEXT TRUNCATED (message ended at the colon). The deployment claims (owner merged run -2, dispatched the lane, the BUILD failed) are treated as REPORTED, to be verified from the instance, not assumed.
- 2026-11-22 coord (predecessor, ses_e1aba0810ffeZkojwF052VItVK): compaction fired mid-session; handoff protocol executed — run -2 STATE carries the post_close block (intake + candidate roots), this folder seeded. Successor coord: read the folder chain in order (this folder → run -2 folder incl. post_close → plan files), load MUST-load skills, then scout-first (`agent-explore`): the failure is observable live — origin/main merge state, builder-bootstrap Actions runs (which STEP died: login vs walk vs build vs push), registry state, gpu runner pod + dind PVC usage. Leading candidates recorded in run -2's post_close (PVC space on the first multi-GB FROM-pull is the top hint, per cf-55's standing caveat) — GROUND, do not pick. No board lock held; starts unclaimed, direct-task.
- 2026-11-22T22:3x coord: COMPACTION HANDOFF executed in DEGRADED form, logged so nobody hunts a phantom successor: (1) STATE made current ✓ (run -2 `post_close` block + this folder seeded). (2) Successor spawn FAILED ON MECHANISM — no session-create tool exists in the reachable catalog (only move/rename/worktree tools), and `agent-coord` refuses subagent launch by design (coords are top-level-only in this permission shape). (3) Degradation: the parent (this) session CONTINUES as coordinator on the compacted context — the seeded folder chain carries the full state for any future fresh start; `pipeline_release` handoff N/A (pipeline_status verified this session holds no lock — the two visible groups belong to other sessions). (4) Substantive progress dispatched regardless: agent-explore (flash) to ground the deploy claim and locate the build failure — the truncated paste is NOT blocking; the instance is the evidence.
- 2026-11-22 coord: SCOUT VERDICT RECORDED (EXPLORE.md) — the missing error text replaced by evidence: run #215 died in `build and push` after 2m32s on the Dockerfile helm-bake curl: **TLS exit 35 to get.helm.sh = the D33 egress class** (mitigations already documented in-chart at values.yaml:74-81); PVC-space/timeout/job-start/secret/base-image ALL refuted with proof. Run -2 IS merged (rebased trio, GitHub also caught up by hand). SECOND FINDING bigger than the user's question: the INFRA FLEET IS DEAD since 00:59:19Z — live runner config still maps the four labels to the ghcr image that 403s anonymous pulls, because `Application/gpu-forgejo-runner-gpu` went OutOfSync 22:22:34Z and never synced ⇒ run -1's instance-registry label map unapplied AND run -2's credential fix never executed; registries confirmed never minted anything. Heal order is now dependency-locked: egress fixed (or transient-pass) lane dispatch → mint → **UA-10 proven against a real public instance package (live gate, not a deferred card)** → sync the runner Applications → jobs start. Family-note correction recorded: the anonymous Actions per-run DETAIL endpoint + job UI HTML are RICH (the "API sparse" note applies to the runs-LIST only) — future probes use these first.
- 2026-11-22 coord: agent-plan (flash) launched for the run -3 landing: egress-hardening choice (Dockerfile curl-retry as the recommended first-line — t3-compatible addition; lane --network=host as the build-line/teeth-moving alternative; chart dind --mtu 1450 as the persistent-class escalation), each with its exact teeth deltas, PLUS the separated owner-leg package (re-dispatch vs fix-first presented to the owner; mint→UA-10→sync→start chain; auth-mount conditional on UA-10 fail; dev-copy + GitHub fan-out legs). Landing mechanics: new branch from origin/main `dcc54c091`; the uncommitted record tail (run -2 STATE post_close + this folder) rides the eventual coord record commit.
- 2026-11-23 human (batched round, run -3): **Q1 NO early re-dispatch** (fix first, dispatch once on hardened main — the plan's O-0 experiment option withdrawn, retry-safety law stays recorded as fact, unused), **Q2 (a)+(c) CONFIRMED** (Dockerfile retry budget `--retry 5 --retry-all-errors --retry-delay 2` ×3 bake fetches + chart dind `--mtu=1450`), **Q3 BOTH releases** (fleet-wide daemon change at each release's heal-sync), **Q4 facts ride the legs** (in-job egress probe, step-log stderr, ROLE verbatim, docker-data usage, org package-visibility). No scope fork — plan ships as written; `plan_status`: draft → **approved** (coord). TEST wave launching: containers-fr t3/t4 extension, gpu g7 fourth-class re-arm, dev-suite dind-args pin per the chunk red-posture list — (b)-fallback documented only, not built.
- 2026-11-23 coord: TEST RECORDED — authored-reds exactly per the red-posture table (fr@t3, dev@t2, gpu clean-green), SIM-full all-green incl. the render proof; pair law symmetric under battery; two chunk-authority resolutions noted (quote-anchored tarball pin defeats the sidecar-prefix class; literal retry-5 exactness rides AC1 grep not the leg regex); misplacement-on-runner green-at-g7 is BY DESIGN (placement is the dev-suite render pin's job). FRICTION seeded retroactively (own miss, booked). DEV launching (retry trio in Dockerfile + mtu pair in chart values, shapes fixed by the chunk).
- 2026-11-23 coord: DEV LANDED + C01 REVIEW APPROVED + FINAL WHOLE-PLAN APPROVED (2 minors, both actioned: fr t3 fail-text truthed by its author and AMENDED into the landing tip while unpushed → `5414581eb`, replacing dbd3346ad, 5-file shape + walker teeth unchanged, 8/8 + mutation-verified; plan-file stale Q1 recommendation correction routed to its author, in flight). Reviewer-promoted ORDERING LAW for the owner package: 'sync BOTH' is never one step — dev release sync rides only after dev copy + dev-side probe pass (pull-death trap). Owner legs stand: O-1 merge → O-2 bare hardened dispatch (mints 26.11.1; Nov confirmed) → O-3 UA-10 LIVE GATE → O-4 GPU sync+restart (quiet window) → O-5 dev copy→probe→sync → O-6 fan-out (first healed main-sync completes its ghcr leg on PUSH_TOKEN_GH for the first time) → O-7 verifications. Record commit imminent once the plan correction lands.

## Plan (run -3, agent-plan, 2026-11-22)

- 2026-11-22 plan: FAMILY RANKING recorded, SIM-measured all directions (trees
  /tmp/opencode/cf6-b3-sim-{a,b,c} + cf6-b3-render; repo never mutated). **(a) Dockerfile retry** =
  3 fetches get `--retry 5 --retry-all-errors --retry-delay 2`; existing containers suite 8/8 GREEN
  vs the flagged file (flags invisible to t3/t4's shape greps; hadolint clean); the extended t3/t4
  pins measured RED-vs-old / GREEN-vs-new. Covers lane AND both containers-build arms for THIS image
  (their build lines share the dind NAT path — containers-build.yaml:348/:405 read). **(c) chart dind
  --mtu=1450** = the class answer; g7 blast-radius measured RED on the un-armed chart edit, a
  fourth-class re-arm (value-exact pair, chart-values-scoped, add-side-only, absence-legal) measured
  GREEN-clean / GREEN-full (+1 ok → gpu 20) / RED-half / RED-remove — surgical per the docker_host
  precedent; render proof: docker:29.9.2-dind ENTRYPOINT dockerd-entrypoint.sh with NO Cmd → args
  are dockerd-prefixed, unix-socket default and all pinned dind fields survive (helm template
  verified). **(b) lane --network=host** REJECTED as chosen family: measured 20/20 GREEN both ways —
  the brief's "b5/b8 build-line anchors move" hypothesis is FALSE (b8 anchors `^docker build` +
  final-token context; flag insertion is structurally tolerated) — so (b) costs the same file+pin
  pair as (a) while protecting strictly LESS (lane-only; containers-build keeps the NAT path), and
  it unfreezes a file that (a)/(c) leave byte-frozen. Recommendation: **(a)+(c) combined**; (a)
  protects what died, (c) protects the class, both ride the one commit; (b) held as the fallback if
  O-0 P1's in-job probe shows reachability only via the host path.
- 2026-11-22 plan: fix-lands-regardless ruling. Re-dispatch-first (EXPLORE §5 A) is presented as the
  FIRST cheap experiment in the batched round (retry-safe by the lane's N+1/gaps law, warm-ish
  docker-data), but the class is recurrence-PROVEN (git log -S mtu=1450 empty = the documented
  mitigation was NEVER applied; D33 first-fire ECONNRESET + #215 TLS-35 = two deaths, one host) —
  a transient pass does not cancel C01. Retry-vs-hard-block risk stated: systematic MTU black-holing
  makes retries die LOUDER (later, logged), not quieter — which is the argument FOR pairing (c), not
  against (a).
- 2026-11-22 plan: ONE chunk (C01, M, wave 1), C02-style validation folded in; the (a)/(c) sub-pairs
  are disjoint so an owner scope-answer shrinks C01 rather than splitting it — no fleet repo chunk
  (the heal is owner legs O-0..O-7, dependency-ordered with UA-10 as the LIVE blocking gate O-3:
  sync-into-pull-death re-creates the 403 fleet kill; fail ⇒ A′ auth-mount rides the NEXT ticket).
  Rejected: minting a C02 for the chart half (reviewability gain none; one ruling, one commit);
  fleet-wide --retry retrofit of the other downloading Dockerfiles (coder-workspace bake is bare-
  curl precedent — out of scope; (c) is the general answer); --retry-connrefused (subsumed: our code
  is 35 and retry-all-errors covers it; connrefused targets refusals).
- 2026-11-22 plan: owner-leg command shapes cited only from chain-verified texts (probe/UA-10 pair =
  EXPLORE §4.3 + debug-1 L2 verbatim shapes; app/STSet names = EXPLORE §2.3 event + debug-1
  EXPLORE:213/337; ArgoCD sync leg left as UI-or-owner-CLI spelling because the Application CRD is
  unresolvable via readonly MCP — no invented kubectl sync command). GitHub main == dcc54c091 already
  hand-synced (scout) — O-6 confirms rather than commands.
