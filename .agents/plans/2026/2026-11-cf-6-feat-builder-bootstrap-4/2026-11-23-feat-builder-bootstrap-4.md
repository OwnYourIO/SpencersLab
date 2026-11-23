# PLAN: builder-bootstrap-4 — kill the get.helm.sh bake: digest-pinned OCI tool images (family A)
feature: 2026/2026-11-cf-6-feat-builder-bootstrap-4
status: draft — run -4 of the bootstrap family; RESEARCH.md (23 sources) is the base, its family A
verdict re-derived into one chunk below. Model routing: every tier `openrouter/qwen/qwen3.8-flash`
(standing human directive, STATE.kickoff). BASE = origin/main `bc4b2a3fa`, branch
`cf-6-feat-builder-bootstrap-4` (recorded in STATE.kickoff.branch).
Owner-channel context: the owner round transmission FAILED (DECISIONS 2026-11-23); this plan proceeds
on the recommended family A, fully reversible (unmerged branch ⇒ total rollback), with the owner's
pre-merge veto standing and P1 as the belt — except P1 was also EXECUTED in this plan session with a
green result (fact F4), which materially de-risks the reversibility posture.

## Goal

Replace the two bake FETCHes in `containers/forgejo-runner/Dockerfile` (get.helm.sh helm tarball +
sidecar, github.com cr archive) with multi-stage `COPY --from` of TWO digest-pinned OCI tool images —
`docker.io/alpine/helm:3.22.1@sha256:8191701a…` and official `ghcr.io/helm/chart-releaser:v1.10.1-amd64@sha256:f04f886a…` —
so a cluster-path build touches no single-host artifact CDN at all; re-anchor build-time integrity on
in-image binary-hash asserts against the official release checksum chain. Move every pin that describes
the old fetch SHAPES in the same commit (the containers-fr suite inverts to red-first-against-main, the
renovate.json v3-hold gains the docker-datasource twin, the two chart comments + README + Dockerfile
header tell the new truth dated).

## Out of scope

- Executing any owner leg (dispatch, merge, visibility, syncs — O-1..O-7 as the run-3 package STOOD).
- `.forgejo/workflows/*`, `.github/workflows/*`, `scripts/` — byte-frozen (bb suite b5/b8/b10 pins the
  lane; the lane header does NOT narrate the bake — verified, nothing to edit there).
- The chart label pins (`26.11.1` refs) and any dind `--mtu=1450`/args rendering change — mtu/retry
  stay deployed; this run edits only the two COMMENT sites that narrate them (F8).
- coder-workspace and every other container: its get.helm.sh bake runs from a DIFFERENT, working egress
  (the workspace; its own test helpers fetch there daily — F10). Only forgejo-runner's cluster-path bake
  is blocked; no fleet-wide retrofit (run-3 said the same).
- The run-3 retry-budget pins' TEXT survives in git history only: retired honestly in the suite with a
  dated note (run-3 hardened a path proven dead by run -4 — the pins move with the source change).
- Family D (GitHub-lane build + ghcr→instance copy) stays the RESERVED fallback if the owner vetoes the
  community helm image pre-merge; family C (instance mirror) the escalation if a second host blocks.

## Verified facts (this plan session — live reads + registry probes + SIMs; BASE `bc4b2a3fa`)

- **F1 — the retry-budget shape IS in the base** (brief's verify-myself asked): Dockerfile :58/:59/:73
  carry `--retry 5 --retry-all-errors --retry-delay 2`; t3/t4 pin them (suite :146-149, :173).
  `bash tests/containers/forgejo-runner.sh` = 8/8 green at BASE — the authored-RED posture inverts for
  this run (F6).
- **F2 — alpine/helm:3.22.1 as served:** the tag is an OCI **index**, digest `8191701ad1f82ee3695c87211fcbfe6d7b1bb7df92ac1c8de9ccdb0995a6a2c1`
  (== RESEARCH S8 index); the amd64 manifest is `83dd7afc…`. Its layer `90ff3544` carries
  `usr/bin/helm` — **binary sha256 `46aeab5e043f62d01f7c168823b392cabc1cea3807b67906296290483791be43`**,
  static (no PT_INTERP ⇒ runs on the Ubuntu act base; the alpine/musl carrier image proving it runs there
  is itself static-linkage evidence).
- **F3 — cr official image as served:** `v1.10.1-amd64` is an OCI **manifest**, digest `f04f886affa5ba55b004788591b56f35bfd79abca9f85f0cb2f61c2f90bbe84c`
  (== RESEARCH S5); index of `v1.10.1` = `51758f90…`. Layer `78f50f28` carries `usr/local/bin/cr` —
  **binary sha256 `ca45e76c0aa7a159425cd5b4b63269b8cb5ee481a2667c9f8ffcf092a33402fc`**, static. Probe
  gotcha recorded: ghcr 404s the OCI manifest/index unless the Accept names the exact OCI media type
  (`*/*` included returns MANIFEST_UNKNOWN here) — the digest-pinned FROM itself is unaffected.
- **F4 — P1 EXECUTED this session, GREEN (the identity proof):** official `helm-v3.22.1-linux-amd64.tar.gz`
  fetched from get.helm.sh here, `sha256sum -c` against the published `896cf636…` OK, inner binary ==
  F2's image binary byte-for-byte; official cr archive `ce46baf9…` (== current `CR_SHA256`) OK, inner
  `cr` == F3's image binary. ⇒ the community image ships THE official binaries; the digest-pinned COPY
  chain is provably the official artifact chain. **Correction vs the brief's design 2: the bake anchors
  are the BINARY hashes (`46aeab5e…`, `ca45e76c…`), not the ARCHIVE hashes — archive sha ≠ binary sha by
  construction (gzip+tar wrapper), and a plan that baked `896cf636…` as a `sha256sum` of the copied
  binary would fail every build.** The archive hashes survive as the provenance story in the comment
  (+ the renovate github-releases ARG pins keep tracking the releases whose bodies publish them).
- **F5 — assert shapes re-verified on the exact bytes:** `helm version --short` → `v3.22.1+gd6c1a0e`,
  `grep -q "^v3.22.1"` OK — the copied-binary assert shape survives. But **`cr --version` is BROKEN**
  (`unknown flag`, non-zero rc — measured): chart-releaser 1.10.1 wants the `version` SUBCOMMAND
  (`cr version` → `GitVersion: v1.10.1`, rc 0). The current Dockerfile's `cr --version` line is a
  latent build-killer that never fired only because the fetch always died first (RESEARCH finding 4
  said the arm never executed — this is why it must not be kept by habit). New pin:
  `cr version | grep -q "v${CR_VERSION}"`.
- **F6 — the new pin classes MEASURED (SIM `/tmp/opencode/cf6-b4-sim/Dockerfile`):** stage FROM greps,
  COPY-pair greps, binary-sha anchor, `cr version`, RUN-scoped fetch absence — every one RED against
  main's curl-form Dockerfile, GREEN against the family-A shape; t1's `FROM` count moves 1→3; the
  t6 bans need the `COPY --from` carve-out (bare `COPY`/`ADD` stay banned). hadolint at the error
  threshold: SIM clean; its one DL4006 warning is the `printf … | sha256sum -c -` idiom ALREADY present
  in main's line 74 and already tolerated at the repo bar (measured t7 green) — inherited shape, not
  new risk.
- **F7 — re-pin inventory (containers-fr):** t1 (single-FROM law → exactly-three-FROM law: two named
  tool stages + digest-pinned act final stage), t2 (keep HELM_VERSION/CR_VERSION check_pin pairs as-is;
  CR_SHA256 arms → HELM_BIN_SHA256 + CR_BIN_SHA256 manual-pin pairs), t3/t4 (fetch-shape pins →
  COPY-from + binary-anchor pins + RUN-scoped absence bans), t6 (COPY carve-out; apt/USER/root-shell-deviation
  bans unchanged), t5 (GREEN untouched — destination paths `/usr/local/bin/helm|cr` still match its
  positive pins; its `.cr-bin|GITHUB_PATH` ban survives because the stages are named `helmtool`/`crtool`),
  t7/t8 designed-line. The retry-budget leg texts retire with a dated header note.
- **F8 — docs residue measured:** `get.helm.sh` in LIVE surfaces outside this folder = exactly: the
  Dockerfile (header + RUNs), this suite's comments/pins, `containers/forgejo-runner/README.md` (why-para,
  Baked-tools table), `charts/forgejo-runner/values.yaml` (header block :80-84 + dind block :198-200),
  and workspace-side test HELPERS (`download_helm` fetchers in ~10 tests/services/* — they run on the
  WORKSPACE egress that works, out of scope, F10). **AGENTS.md, .rulesync/, .forgejo/, .github/,
  scripts/: zero hits.** The release suite's t19 file-wide bans are scoped to `.forgejo/workflows/release.yaml`
  (read :1000-1035) — a Dockerfile with get.helm.sh HISTORY comments does not touch them.
- **F9 — renovate.json measured:** 10 packageRules; the helm hold (:267) matches `helm/helm` (github-releases
  + constraints) — it does NOT cover the docker-datasource name `docker.io/alpine/helm`. Insertion SIM
  at position 5 (right after the hold): count→11, calendar rule still found by SCOPE (v3's own comment :138-139
  says index is not its anchor), kubectl-hold↔floor adjacency preserved. Suite posture:
  `kubernetes-mcp-version-floor.sh` **k2 is PRE-EXISTING RED at BASE** (expects 8, tree has 10 — measured;
  ledger it, do not fix here — same class as ci-surface t4); `services-values-pins.sh` v3 is GREEN and
  asserts 10 ⇒ **its count literal + ok-line must re-pin 10→11 in the same commit as the rule**.
  Hold value best-guess: `allowedVersions: "/^3\\./"` (docker tags carry no `v` — the mirror of the
  helm/helm law, slash-wrapped per the rule's own documented lesson).
- **F10 — untouched suites measured or scoped:** bb 20 ok (ran); dockerfile-pins 37 ok (ran — its
  expectations bind coder-workspace/gpt files and the config managers, never forgejo-runner ARGs; the
  new file adds no branch=/git-refs shape for the all-files legs g5/g6); services-values-pins 8 ok (ran;
  v3 moves per F9); containers-build 41 (grep: no Dockerfile-content pins — scratch fixtures only);
  release 20 (t19 scoped to release.yaml, F8); main-sync 8 / forgejo-renovate 8+skip / move-config 8
  (no overlap with these files); dev 58 (dind render legs — comment-only chart edit); gpu 19 @
  BASE-pinned (g7's fourth-class moves only on non-comment chart lines — measured rule F6 of run -3);
  ci-surface recorded posture (zero Dockerfile references — carried t4 + two D29 FAIL lines byte-identical).
  **[SUPERSEDED-CLAUSE 2026-11-23, test wave + coord ruling: the "move-config 8 (no overlap with these
  files)" claim is WRONG — `tests/renovate/forgejo-move-config.sh` m5 (leg line :197) pins repo-wide
  `len(packageRules) == 10`, GREEN at BASE, and the AC6 hold-rule insertion reddens it exactly like v3.
  FOLD-IN ruled per the pair-whole law (cf-6 run-2 9→10 precedent): the m5 count re-pin 10→11 joins the
  one-change landing set — authored-RED at BASE (11-pin vs the 10-rule tree), GREEN once DEV's rule
  lands; the test session applies that edit (the file is NOT dev's to touch) and it rides the same
  commit. The plan-side SIM matrix missed the collateral suite; lesson recorded in FRICTION.
  SECOND STRIKE, 2026-11-23 DEV wave, same class: `tests/services/forgejo-renovate.sh` t8 ALSO pins
  the repo packageRules count (`len(rules) == 10` at BASE, GREEN there; RED at the landed 11-rule
  config — DEV isolation-proved), so the plan's "forgejo-renovate 8+skip — untouched" claim was
  equally wrong, and coord ruled FOLD again: the t8 count re-pin (need-literal + message; its ok-line
  carries no count word; the github-actions-scope / renovatebot / 13-legs identity pins stay
  byte-intact) joins the fold set, test-session edit, same commit. Corrected landing set: Dockerfile
  (restructure + header) + renovate.json (idx-5 rule) + TWO doc files (values ×2 comment sites,
  README) + FOUR test files (containers-fr, services-values-pins v3, forgejo-move-config m5,
  forgejo-renovate t8). One class, two misses — the FRICTION law escalates: the collateral grep must
  cover the FULL suite set including tests/services/forgejo-* before ANY untouched claim; the SIM
  matrix owes a packageRules-count sweep across all suites.]**
- **F11 — egress/limits posture:** the build's new pulls are docker.io (F2 image, FIRST daemon-side use
  in a build — kubelet-side docker.io proven by the cluster's own pods per RESEARCH S22) + ghcr (the act
  base already pulls there today). Anonymous docker.io pull ceilings (per-IP rate limits) are the named
  residual risk: no pre-warm step is added (lane byte-frozen, b-suite pins it; OQ2 best-guess = first
  dispatch IS P2, family C = escalation). Build time: the 129 s+ TLS death and two tarball fetches are
  gone; ~65 MB compressed of tool-image layers pull once then cache in the persistent dind layer store —
  the 30 m runner ceiling gets strictly MORE margin (RESEARCH adjacent: noise vs the ~10 GB base).

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Family-A Dockerfile (stage FROMs + COPY pair + binary anchors + asserts), containers-fr re-pin (t1-t6 inversion, retry pins retired), renovate hold + count re-pins (services-values-pins v3, forgejo-move-config m5, forgejo-renovate t8 — per the F10 superseded-clause, two strikes folded), docs truth-move (Dockerfile header, values 2 comments, README Baked tools) — one change | M | 1 | [] | — |

One chunk: the parity pins (suite literals ↔ Dockerfile shapes ↔ renovate counts ↔ docs sentences that
the bb b9 pair greps) force every piece into ONE commit — a split would ship a RED tree by design (the
run-3 one-change pair law, mirrored). Size M: a few files, one subsystem.

## Wave order

1. **C01** — TEST first: rewrite `tests/containers/forgejo-runner.sh` t1-t6 per the F7 inventory
  (authored-RED vs main, F6 measured), re-pin `services-values-pins.sh` v3 count 10→11 (authored-RED
  vs the un-edited renovate.json — the count moves only after DEV's rule lands: pair-whole law), re-pin
  `forgejo-move-config.sh` m5 count 10→11 (same posture — F10 superseded-clause, coord FOLD ruling; the
  test session owns that file's edit, it is not dev's to touch), re-pin `forgejo-renovate.sh` t8 count
  10→11 (second strike, same class and same ruling — need-literal + message only, identity pins intact,
  test-session edit), extend
  the suite header's retirement note. Then DEV in the same commit: the Dockerfile restructure (F2/F3
  digests, F4 anchors, F5 assert shapes — header comment travels with it), the renovate.json rule (F9
  insertion point), the two doc files (values ×2 comment sites, README; F8). One commit (coord).

## Commands (the validation bar — landing tree)

```bash
export PATH=$HOME/.local/bin:$PATH
BASE=bc4b2a3fa   # resolve-check: git cat-file -t $BASE => commit (vacuous-green law)
bash tests/containers/forgejo-runner.sh        # 8 ok — NEW shapes: COPY-from stages + binary anchors + cr version
bash tests/renovate/services-values-pins.sh    # 8 ok — v3 at 11 packageRules (re-pinned with the new hold rule)
bash tests/renovate/dockerfile-pins.sh         # 37 ok — untouched (measured green at BASE; forgejo-runner not its subject)
bash tests/services/forgejo-builder-bootstrap.sh   # 20 ok — lane byte-untouched; b9 doc pair survives the README move
bash tests/services/forgejo-containers-build.sh    # 41 ok — untouched
bash tests/services/forgejo-release.sh         # 20 ok — untouched (t19 bans are release.yaml-scoped, F8)
bash tests/services/forgejo-main-sync.sh       # 8 ok — untouched
bash tests/services/forgejo-renovate.sh        # 8 ok + t9 default-off skip — t8 count re-pin 10→11
                                               # FOLDED (second strike, F10 clause; authored-RED at
                                               # BASE vs the 10-rule tree, GREEN on the landed config;
                                               # identity pins byte-intact; test-session edit)
bash tests/renovate/forgejo-move-config.sh     # 8 ok — m5 count pin re-pinned 10→11 by this change
                                               # (authored-RED at BASE vs the 10-rule tree, GREEN once
                                               # DEV's hold rule lands — F10 superseded-clause;
                                               # test-session edit, same commit; not dev's file to touch)
bash tests/services/dev-forgejo-runner.sh      # 58 ok — untouched (render legs; chart edit is comments-only)
GPU_RUNNER_DIFF_BASE=$BASE bash tests/services/gpu-forgejo-runner.sh
                                               # 19 ok — g7 fourth-class unmoved by comment-only chart edits (F10)
bash tests/services/forgejo-ci-surface.sh      # recorded posture: ONLY the carried t4 red + two D29 FAIL
                                               # lines byte-identical to BASE (no Dockerfile references, F10)
bash tests/renovate/kubernetes-mcp-version-floor.sh  # k2 PRE-EXISTING RED ledger line: count message shifts
                                               # "expected 8" from 10 to 11 — same red arm, no new class
# chart validation (AGENTS hard rule — chart COMMENT touched):
helm lint charts/forgejo-runner && helm template charts/forgejo-runner >/dev/null
# renovate config validation (rule added):
npx --yes renovate-config-validator renovate.json   # or the global-renovate validate_config/lint MCP pair
# byte-proofs (each EMPTY vs BASE) — the frozen scope:
git diff $BASE --exit-code -- .forgejo/workflows/ .github/workflows/ scripts/ containers/coder-workspace/
git diff $BASE --exit-code -- charts/forgejo-runner/Chart.yaml charts/forgejo-runner/templates/
git diff $BASE --exit-code -- services/ custom-values/ AGENTS.md .rulesync/
# non-empty pins (the change's fingerprints):
grep -c '^COPY --from=' containers/forgejo-runner/Dockerfile        # => 2
grep -cE '^FROM ' containers/forgejo-runner/Dockerfile              # => 3
! sed -e ':a' -e 'N' -e '$!ba' -e 's/\\\n[[:space:]]*/ /g' containers/forgejo-runner/Dockerfile \
    | grep -E '^RUN' | grep -qE 'get\.helm\.sh|releases/download'   # zero fetch RUNs (comments exempt, F8)
# rulesync: N/A — no .rulesync source moves (docs ride inside chart comments + container README)
npx --yes aislop ci --changes                  # quality gate (score floor, zero errors)
# docker build => no-daemon, CI-deferred (t8 designed passing shape; live build proof = O-2 dispatch)
```

No cluster mutation, no dispatch, no merge, no secret changes in ANY agent session.

## Owner legs after merge (the run-3 package AS IT STOOD — compact restatement)

- **O-1'** — merge this branch (owner style: rebase; GitHub main ends == forge main — the hand-sync state
  of run -3 EXPLORE §1 still governs while main-sync is dead). Owner pre-merge veto on family A is
  preserved: the P1 cross-check this session came GREEN (F4), so the veto's subject (community-image
  identity) is now measured fact, not assumption.
- **O-2'** — ONE lane dispatch on infra (bare button): the hardened retry path is GONE from the bake, so
  this is the first build that should pass end-to-end — it touches no get.helm.sh operand; mints
  **26.11.1** ×{tag, latest, main} to the infra registry ONLY (B law), and it IS probe P2 for the
  docker.io daemon-class pull (log names the stage pulls). Build time expected DOWN vs #215's 159 s death
  (fetch+retries replaced by ~65 MB of once-cached pulls).
- **O-3'** — UA-10 gate EXACTLY as run -3 wrote it (public + anonymous-pullable proof on the fresh
  package; FAIL ⇒ STOP, no sync, A′ amendment ticket).
- **O-4'/O-5'** — heal-sync `gpu-forgejo-runner-gpu` (reloader roll; rollout-restart fallback), dev-side
  manual copy of the minted tag + visibility + sync — unchanged from run -3 O-4/O-5 (the mtu flag lands
  with the same sync; it STAYS applied fleet hardening, just no longer load-bearing for the bake — the
  values comment this run writes says exactly that).
- **O-6'/O-7'** — fan-out verify + first release-arm flows; the next containers-build green re-arms the
  inherited 26.11.2 re-pin-pair card. **Month-cross now LIVE:** today IS Nov 23 — mint stays 26.11.1/
  26.11.2-per-walk; if O-1' slips past Nov 30 the lane mints 26.12.1 and BOTH pin sites (chart labels +
  dev slice) need the owner amend-pair.

## Risks / merge caveats

- **alpine/helm community trust:** anchored three ways — (a) RESEARCH-verified rehost (its Dockerfile
  wgets the official tarball; S9), (b) THIS session's byte-exact binary-anchor proof (F4) made
  permanent by the build's `sha256sum -c` of `46aeab5e…` (a bump that changes bytes dies the build
  until hashes are consciously refreshed — strictly stronger than the remote `.sha256sum` sidecar the
  change deletes, which lived on the blocked host anyway), (c) owner pre-merge veto + P1 belt.
- **docker.io anonymous-pull ceilings at build time** (F11): first daemon-side Hub pulls; mitigation
  declined in-lane (OQ2), first dispatch is the probe, family C the escalation.
- **`cr version` rename (F5)**: the OLD suite pin (`cr --version`) must die with the old Dockerfile;
  keeping it would re-plant the latent build-killer. The new pin text is `cr version | grep`.
- **Half-pair trees are RED by design:** do not land the Dockerfile without the suite re-pin; do not
  land the renovate rule without the v3 count re-pin.
- **k2 pre-existing red grows its number** (8 vs 11): ledger note only; its fix belongs to whoever
  rebaselines that ticket, not here.
- **Rollback:** unmerged branch ⇒ delete branch. Post-merge-but-pre-dispatch: revert commit; no fleet
  state touched by the repo change alone.

## Open questions (best-guess-first; owner round may be batched — recommendations ship reversibly)

1. **Digest-vs-tag pin style on the stage FROMs** — best guess (adopted above): inline `tag@digest`
   pinning the digest THE TAG SERVES (helm: index `8191701a…`; cr: manifest `f04f886a…`), no renovate
   annotation on the stage lines (built-in dockerfile manager tracks FROM natively — RESEARCH S21;
   siblings act-base/vllm-radiance/renovate-mcp all pin tag@digest inline; forgejo-host-runner is the
   annotated-tag sibling for the no-digest case). Digest-ARG indirection (`FROM img:tag@${DIGEST}`) was
   considered and REJECTED: the dockerfile manager would not extract through it and the repo has zero
   precedent for ARG-fed digests.
2. **docker.io mirror pre-pull in the lane** (RESEARCH OQ3) — best guess: NO lane change (b-suite pins
   the file byte-shapes; the first dispatch IS the P2 probe; a Hub throttle shows as a loud named pull
   error and the escalation is family C, not a repo diff).
3. **Hold rule for cr's image too?** — best guess: NO — `helm/chart-releaser` has no 2.x line to hold
   (YAGNI); the binary-anchor assert catches any future major-crossing bump at build. Cheap to add later.

## Deferred / carried (unchanged, inherited)

lane-design card; UA-10 probe card (consumed by O-3'); run-1 carried set: 26.11.2 re-pin pair, ghcr
settle, cf-55 retest-first, ci-surface t4, t9-exemption retirement; run-3 fallback family (b) host-net
(RETIRED by the source change); **the run-3 retry-budget hardening itself now survives only as fleet
path-hardening history — the Dockerfile flags it added die with this change by design (dated note in
the suite header).**
