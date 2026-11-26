# PLAN: containers-build last-built marker diff (O2)
feature: 2026/2026-11-cf-6-debug-detect-rerun
plan-file-of-record — replaces nothing; this ticket folder continues (EXPLORE + RESEARCH are its factual base).

## Goal

Make `containers-build` detection delivery-loss-proof by changing the push arm's
diff BASE from the payload's `before` to a **last-built marker**: a ref on the
Forgejo repo advanced to a run's sha only by push runs whose whole build matrix
published green. The trigger stays as-is (owner Q3 reframe: "the trigger is ok,
what it detects is incorrect"); a dead-or-missed build is re-covered by the NEXT
push's `marker..sha` range instead of being permanently skipped.

## Out of scope

- The PR arm (merge-base..head, per-container `pr-<branch>-<sha>`) — byte-untouched;
  the marker is push-side only.
- The dispatch arm — unchanged; it names its own set and NEVER advances the marker.
- O1 reconcile sweep / cron resync — ranked #1 by research, declined by the owner
  in favor of O2; the lazy-heal window it would have closed is carried as a Risk.
- Bucket-C build-step failures (gpt-researcher, coder-workspace/debian base,
  opencode — Nov 24 class) — separate family (`cf-6-debug-forge-runner-docker`
  lineage); they GATE the bootstrap legs, not the code chunk.
- Upstream Forgejo issue — owner Q5: declined; bucket-A trigger over-fire stays
  as noise (under marker semantics each spurious wake costs only a ref read).
- The 26.11.x month-cross pin-pair card — unchanged, tracked on the family.
- ghcr/GitHub-side marker — none: Q4 rules the Forgejo side as source of truth;
  the marker ref is Forgejo-local (main-sync mirrors `refs/heads/main` only).

## Design (ruled by this plan; grounds cited)

1. **Marker ref: `refs/heads/ci/containers-built`** (a branch ref, NOT `refs/ci/*`,
   NOT a tag). Grounding: pushability of `refs/heads/*` from a workflow on the
   instance itself is PROVEN in-repo — release.yaml L176-177 pushes
   `git push origin HEAD:refs/heads/main` with the checkout's automatic same-repo
   credential, no secret (the release.yaml R3/D5 loop-guard: job-credential pushes
   re-trigger nothing). `refs/ci/*` custom-namespace push support on Forgejo
   15.0.10 is ungroundable at agent tier (OQ-1); tags need force-move, which
   violates the family's every-push-plain law. Event safety PROVEN by the five
   `.forgejo` workflows' own `on:` blocks: every push trigger carries
   `branches: [main]` (containers-build L73-75, main-sync L43-44, release L30-31),
   renovate is schedule/dispatch, builder-bootstrap dispatch-only — a push of
   `refs/heads/ci/containers-built` fires nothing, doubly (filter + no-re-trigger).
   The 100-branch inventory + absent-marker state measured live via anonymous
   `git ls-remote` (2026-11-25). Cosmetic cost: the marker shows in the branch
   list — owner-vetoable via OQ-1.
2. **Detection change.** New resolver step in `detect-changes` (before the detect
   step): on push events `git ls-remote origin refs/heads/ci/containers-built`;
   empty → output empty (bootstrap: marker missing); 40-hex → reachability-check
   with `git cat-file -e` against the depth-0 checkout — unreachable (orphaned by
   a history rewrite) → LOUD fail naming the sha + owner note, never a silent
   downgrade (family style, d13 kin); non-hex garbage → fatal. PR/dispatch:
   outputs empty, no network. The detect step gains a 7th env accessor
   `MARKER_SHA: ${{ steps.marker.outputs.sha }}`. `detect()` push-arm base
   selection: `before`-sanity laws stay FIRST and unconditional (empty before
   still `die`s — A5), then marker wins if non-empty; else the shipped
   all-zero→tip-only / before chain verbatim. Range echo gains a stable
   `base=marker|before|tip-only` token. An unreachable MARKER that reaches the
   script still dies 128 through the unmasked `git diff` — t15's no-masking law
   covers the new path unchanged.
3. **Warn/info law (Q3 reframe wording law).** marker-resolved empty set =
   the GOOD case: plain info log line, NO `::warning::` — marker..sha empty
   PROVES nothing was missed (this replaces the empty-push warning only where
   the marker proves it). marker==sha = same info exit (quiet re-run semantics,
   see 7). Bootstrap (marker missing) keeps every existing exemption/warning
   byte-for-byte, including the `before==sha` no-op silence. PR empty keeps its
   warning untouched.
4. **Marker advance = full success only.** New `advance-marker` job:
   `if: forgejo.event_name == 'push' && needs.build-release.result == 'success'`,
   `needs: [detect-changes, build-release]`, checkout `fetch-depth: 0` (the
   push-negotiation law, main-sync L54-55 / release L156-158 precedent), one
   plain `git push origin HEAD:refs/heads/ci/containers-built`. No own ROLE guard
   (piggybacks build-release's prod polarity; unset-ROLE widen stays
   containers-build's exclusive per ci-surface t6). A partial failure leaves the
   marker put: re-runs then retry the residue — INCLUDING re-publishing the legs
   that succeeded (calendar N+1 again; the gaps-by-design law absorbs it; stated
   honestly in Risks). Per-container markers REJECTED (RESEARCH: complexity) —
   no cheap form found within the common-library/matrix shape. The push itself is
   the monotonicity guard: a non-FF advance is refused by git, loudly red (never
   force — the law); empty-set runs do NOT advance (build-release skipped ⇒
   dependent skipped) — provably harmless: tree(marker)==tree(sha) over
   containers/ makes the next run's range content-equivalent.
5. **Auto-creation + bootstrap ordering (owner legs).** First green push run after
   the code merge auto-CREATES the marker at its sha (branch creation is trivially
   allowed) — that is sound coverage (its own diff base was `before`, the old law).
   The bootstrap sequence then decides when marker semantics take over from
   before-semantics: **B0** bucket-C health check → **B1** one-time full-fleet
   dispatch (14 names listed below; existing dispatch arm verified post-run-4 at
   YAML L82-88) all-green → **B2** `git push <forge-url> <T1>:refs/heads/ci/containers-built`
   from owner creds at exactly the published tip (with the `git diff T1 <main-tip> -- containers/`
   empty proof if anything landed between) → **B3** merge C01. EITHER ORDER IS SAFE —
   proved: pre-merge the marker is inert (no accessor exists); post-merge pre-B2 the
   resolver finds it absent and runs the exact shipped fallback (d18 pins it). B0 is
   NOT yet green (see Bootstrap section) — that gates B1/B2, not B3.
6. **Teeth + docs, one change set (x5 parity law).** Reword in the SAME commit:
   the script doc header, the YAML `Detection.` header paragraph (L43-56), and the
   doc trio `.rulesync/rules/overview.md` L237-248 → `rulesync generate` twin
   AGENTS.md L239-248 + `skills/container-creation/SKILL.md` L58-84 — the hard-rule
   sentence must restate: pushes diff `marker..sha` (delivery-loss-proof),
   first-ever/missing marker falls back to `before..sha`, marker advances only on
   a fully-successful push run. x5 grows one MARKERS tuple (`marker..sha`); its
   ban list (no annotation-render claims — the info line is job-log text) and its
   docker-build/workflow_dispatch co-naming rules stay. Suite: t13 re-pin (7 keys,
   "six"→"seven"), t14 extended (echo token list + MARKER_SHA in harness base env
   + 3 new scenarios), NEW t16 (advance-job shape + push-line bytes + no-force
   absence) and NEW t17 (executed offline monotonicity: scratch bare "remote" —
   create ok, non-FF refused; resolver absent→empty/present→sha/garbage→fatal),
   NEW d16-d19 (marker precedence, marker==sha, before-fallback regression pin,
   orphan/garbage marker 128). d14/d15/t12/t15/r-*/x1-x4/g1/b-suite: green,
   byte-untouched. Final expected count: **47 ok** (was 41).
7. **Re-run law audit (the O2 semantic shift, stated plainly).** Today's stored-
   payload re-run idempotence (proven on runs 240/104-184/244-246) CHANGES CLASS:
   a re-run of a FULLY SUCCEEDED push run now diffs marker..sha where the marker
   HAS advanced ⇒ empty ⇒ info-exit — it no longer reproduces attempt-1's publish
   list; the re-run becomes a harmless verify. Failure-class re-runs keep the old
   behavior exactly (marker unmoved ⇒ same range ⇒ same set, re-publishing
   succeeded legs included — identical churn to today). PR-arm re-run idempotence
   is byte-preserved (arm untouched). Verdict: acceptable — the law was written
   to block mutable-REF surprises and marker-monotonicity blocks the same class
   harder; RESEARCH named this shift as O2's price and the owner accepted O2
   knowing. This paragraph is the DECISIONS restatement seed.

## Bootstrap status measured (2026-11-25, B0)

Anonymous runs API (max id 296, no new containers-build run since 288 / Nov 24
06:38): last main-side BUILD = push idx 240 (id 257) Nov 23 18:29 SUCCESS
(forgejo-runner published after the run-4 bake fix — the 9ed416baf content);
last dispatch = idx 246 (id 263) coder-workspace FAILED Nov 23 19:43 (dind era);
Nov 24 PR wave mixed — forgejo-runner/renovate-mcp/music-assistant builds GREEN,
gpt-researcher (idx 250), debian:13-slim-base/coder-workspace (idx 251) and
opencode (idx 257) FAILED IN BUILD, root cause auth-gated and undiagnosed since.
**Verdict: the daemon class demonstrably works, but the bucket-C named failures
are OPEN** — B1's full-fleet dispatch would very likely red-leg on them, so B1/B2
wait for the build class (owner: fetch idx 250/251/257 + 246 logs — commands in
EXPLORE §8 — or re-run those PRs, heads proven fetchable; fixes ride the
forge-runner-docker family). C01 merges regardless (fallback proof, design 5).
Fleet for B1 (14, measured at origin/main tip): brother-ptouch-automation,
coder-workspace, forgejo-host-runner, forgejo-runner, gpt-researcher-frontend,
gpt-researcher, music-assistant, okd-enketo, renovate-mcp, snapcast, strata,
traefik-mqtt-allowlist, vllm-radiance-mxfp4, wekan-mcp. B1 may run as one
dispatch or grouped dispatches (capacity-1 runner, 30-min/job ceiling — strata
and vllm-radiance-mxfp4 are the long ones); EVERY name needs a green release leg
before B2 may init.

**B1 gate, amended 2026-11-25 after the bucket-C verdict (EXPLORE §Bucket-C,
STATE bucket_c):** a full-fleet dispatch cannot go green today and the gate is
ONE commit plus three owner discriminators — **(G1) C02 landed on main** (the
coder-workspace node-layer `v` fix, proven content bug, 0-green/15-red since
`3713c83d1` 2026-10-20; until it lands, every coder-workspace leg reddens
deterministically at ~1m13-16s — dispatching B1 before C02 guarantees failure);
**(G2) owner re-run of idx 250** (gpt-researcher backend, head 90c305c30 still
fetchable — transient ⇒ green / deterministic ⇒ same 1m1s, then the job-880 log
fetch is the decider; class remains unknown-only-with-logs); **(G3) owner
re-runs of the strata legs** (PR13/PR98, heads still fetchable per EXPLORE C.6
— last real try Nov 21 55s red, job 614, all pins live). The three never-
CI-built containers (snapcast, brother-ptouch-automation, wekan-mcp) are NOT
C02's scope — their pins are live from the workspace but runner-egress-unproven;
B1 is their first real try and any red leg there is NEW information, owner-
visible, each unknown until first build.

## Commands (the validation bar — landing tree, BASE = post-merge origin/main)

```bash
export PATH=$HOME/.local/bin:$PATH
bash tests/services/forgejo-containers-build.sh      # 47 ok — was 41; +t16,t17,d16-d19; t13/t14/x5 re-pinned
bash tests/services/forgejo-ci-surface.sh            # recorded posture: identical red set to BASE (edits keep
                                                     # FORGE_PUSH_TOKEN/PUSH_TOKEN_GH + no widened unset-polarity
                                                     # clause outside containers-build.yaml)
bash tests/services/forgejo-builder-bootstrap.sh     # 20 ok — b-suite non-use pins (L755) stay byte-green
bash tests/services/forgejo-packages.sh              # ok — sibling-token provenance intact
bash tests/services/forgejo-release.sh               # ok — untouched
bash tests/services/forgejo-main-sync.sh             # 8 ok — untouched
bash tests/containers/forgejo-runner.sh              # 8 ok — untouched
# byte-proof fences (each EMPTY vs BASE — the frozen scope):
git diff $BASE --exit-code -- containers/ charts/ services/ custom-values/ .github/ \
    .forgejo/workflows/main-sync.yaml .forgejo/workflows/release.yaml \
    .forgejo/workflows/renovate.yaml .forgejo/workflows/builder-bootstrap.yaml
# non-empty pins (fingerprints of the change):
grep -c 'refs/heads/ci/containers-built' .forgejo/workflows/containers-build.yaml   # => 2 (resolver ls-remote + advance push line)
! grep -r 'refs/heads/ci/containers-built' .forgejo/workflows/ | grep -v containers-build.yaml   # the ref is named in ONE workflow file
grep -c 'MARKER_SHA' scripts/forgejo-container-detect.sh   # => >=2 (env read + base echo token)
grep -c 'MARKER_SHA' .forgejo/workflows/containers-build.yaml   # => >=3 (resolver output, detect env, echo/guard)
npx rulesync generate                              # overview.md edited => AGENTS.md twin, commit together
npx rulesync generate --check                      # must pass
npx --yes aislop ci --changes                      # quality gate (score floor, zero errors)
# helm: N/A — no chart touched (fence above). docker build: N/A — no Dockerfile touched.
# CI-primary live legs (owner, post-merge; NOT agent-session executable):
#   first green push run => its advance job creates the marker; verify
#   git ls-remote https://git.spencerslab.com/CuratedForest/SpencersLab refs/heads/ci/containers-built

# --- C02 block (amended 2026-11-25; lands independently of C01) ---
bash tests/coder-workspace/image-structure.sh        # BASE posture MEASURED 2026-11-25: 45 pass / 1 fail —
                                                     # the 1 is PRE-EXISTING (c2 demands the '# renovate:
                                                     # datasource=docker depName=debian' comment that cf-95
                                                     # f9a08f133 removed as dead — owner-ledger, NOT C02's
                                                     # to touch). C02 target: +6 node-layout/vacuity legs
                                                     # red-at-authoring (old-form negative-control leg
                                                     # green-at-authoring) => landing tree 52 pass / 1 fail,
                                                     # the pre-existing c2 red UNCHANGED in identity.
bash tests/renovate/dockerfile-pins.sh               # 37 pass / 0 fail — measured at BASE; must stay byte-
                                                     # green (ARG NODE_VERSION stays bare: the
                                                     # datasource=node-version contract, pin L89)
bash tests/coder-workspace/startup-script.sh         # 38/0 — untouched (startup file not in C02's diff)
bash tests/coder-workspace/startup-sso-behavior.sh   # 22/0 — untouched
bash tests/services/forgejo-containers-build.sh      # C02 must not move it (47 once C01 lands; 41 before)
# post-fix non-empty pins (fingerprints):
grep -c 'nodejs.org/dist/v${NODE_VERSION}' containers/coder-workspace/Dockerfile   # => 2
grep -c 'node-v${NODE_VERSION}-linux-x64.tar.xz' containers/coder-workspace/Dockerfile # => 5
grep -F 'test "$(node --version)" = "v${NODE_VERSION}"' containers/coder-workspace/Dockerfile
! grep -E 'nodejs\.org/dist/\$\{NODE_VERSION\}|node-\$\{NODE_VERSION\}' containers/coder-workspace/Dockerfile # no bare form left
# mutation probe (the class-of-failure teeth proof): re-introduce the bare
# interpolation in a scratch copy — the new legs must redden; and the OLD
# verify line executed against a fixture whose SHASUMS matches nothing must
# exit 0 (documented vacuity), the NEW guard on the same fixture must exit
# non-zero (agent-test authors both; see chunks/C02.md Tests).
# no-daemon law unchanged: docker build => CI-deferred; live proof = the
# coder-workspace PR legs (idx 251/257 shapes) re-run after merge (owner).
npx --yes aislop ci --changes                        # comment line rides the why-only law (comment-slop)
# byte-proof fences for C02 (each EMPTY): every other containers/ dir, all of
# tests/coder-workspace except image-structure.sh's new legs, .forgejo/, scripts/, charts/:
git diff $BASE --exit-code -- containers/ ':!containers/coder-workspace/Dockerfile'
```

No cluster mutation, no push to main, no secret changes, no dispatch in ANY agent
session. Owner legs only: B0-B3, the live probes.

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | marker diff: detector + workflow + docs trio + teeth | L | 1 | [] | — |
| C02 | coder-workspace node-v fix (pre-B1 unblocker) | S | 2 | [] | NONE — file sets disjoint from C01 (containers/coder-workspace/Dockerfile + tests/coder-workspace/ vs C01's script/YAML/docs-trio/services-suite); lands before/after/with C01 freely. Wave 2 is a dispatch-order courtesy beside the concurrent C01 test wave; C02's real role is the B1 GATE: must be on main before the full-fleet publish (PR merge order is the owner's call). |

One chunk by the fewer-chunks rule and by force: the x5 doc-parity pins bind
script + YAML + overview.md + AGENTS.md + SKILL.md + suite into one committable
set; splitting the new legs into a C02 would mint a chunk that ships red docs or
red pins. Task sizes inside C01 are M-class cohesive (single subsystem); L labels
the whole per role rules — it stands alone.

## Wave order

1. C01 — test authored-red wave (8 red: t13, t14, t16, t17, x5, d16, d17, d19;
   d18 green-at-authoring regression pin) → dev implements → review re-runs.
2. C02 — INDEPENDENT of C01 (disjoint files; depends_on empty; wave 2 is
   dispatch-order beside the concurrent C01 test wave, not a dependency).
   Test authored-red wave (6 red vs the current Dockerfile; the old-form
   vacuity negative-control leg green-at-authoring) → dev lands the ~6-line
   node-layer fix → review re-runs.

## Risks

- **THE semantic shift (design 7):** re-run idempotence is REPLACED by
  marker-monotonicity. Accepted (owner chose O2 knowing); the plan's honest
  ledger: PR-arm idempotence and failure-class re-run behavior survive verbatim;
  only the re-run-of-a-succeeded-push changes (publish → verify, strictly fewer
  republishes than today).
- **Lazy heal (the O1 decline):** a lost build stays invisible until the next
  containers/** push wakes the marker range; a quiet December keeps AD-133-class
  drift in the dark until January. Known and accepted; the dispatch hatch remains
  the manual heal; the cron resync stays unbuilt.
- **Bucket-C gate:** B1/B2 cannot close while named container builds fail
  (gpt-researcher, coder-workspace, opencode class, Nov 24) — marker semantics
  stay dormant-but-safe meanwhile (fallback = today). SAY SO per brief: the
  switch waits, the merge does not.
- **Partial-failure re-run churn:** global marker re-publishes succeeded legs
  (calendar N+1). Identical to today's re-run behavior; gaps-by-design absorbs;
  per-container markers rejected.
- **Orphaned marker / history rewrite:** resolver dies loud with an owner note
  (reset or delete the ref — deleting degrades gracefully to fallback). FF-only
  integration (the owner's standing workflow) makes this rare.
- **Marker branch deleted or rewound by a human:** deletion → silent-but-correct
  fallback; rewind-attempt → refused non-FF push, red advance job, loud.
- **Queued-run race:** a stale queued push whose sha is behind the advanced
  marker reds on the refused advance after harmlessly over-building; capacity-1
  serialization makes it vanishing. Never rewinds the marker (git-enforced).
- **Job-credential push of a non-main branch is near-proven, not proven**
  (release.yaml proves refs/heads/main; a same-credential refs/heads/ci/* push
  is the same ACL class) — first live advance run is the proof leg; refusal ⇒
  red advance, publishes intact, owner re-points the design at a scoped PAT
  (main-sync idiom) or the refs/ci spelling. OQ-2.
- **Repo visibility:** the marker is read anonymously today (public repo —
  measured). If it ever goes private, checkout's credential covers the
  ls-remote; the CVE-2026-27771 note stays registry-side only (reads there
  already wear PATs).

## Open questions (all best-guess-resolved, owner-vetoable; no blockers)

- OQ-1: `refs/heads/ci/containers-built` chosen over `refs/ci/containers-built`
  because custom-namespace push support on Forgejo 15.0.10 could not be grounded
  at agent tier (docs/search inconclusive); cost is one entry in the branch list.
- OQ-2: if the job credential refuses the non-main push live (OQ-1's residual),
  fall back to a minted repo-write-scoped PAT with the main-sync URL idiom — a
  one-line change + t16 re-pin (secret name: owner-minted).
- OQ-3: the verified-empty info line wording (`changed set verified empty:
  marker..sha` proposed, plain echo, no `::notice::` — runner v13.2.0 does not
  interpret it, RESEARCH proven); t14 pins whatever spelling lands.

## References

EXPLORE.md §1-§7 + Forensics (payload laws, 9 reproductions, teeth map, over-fire
proof); RESEARCH.md §E/§H (marker-ref analysis, poisoned-pointer caveat: a
last-SUCCESSFUL-RUN pointer is rejected — green-empty runs poison it; the moved
ref is the only event-anchored cure), §4 table row O2, §5 O2 delta; DECISIONS.md
kickoff + batched-round rulings (Q1-Q5).
