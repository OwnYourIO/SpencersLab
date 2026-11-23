# PLAN: builder-bootstrap-3 — D33 egress hardening (repo) + the fleet heal package (owner legs)
feature: 2026/2026-11-cf-6-feat-builder-bootstrap-3
status: draft — run -3 of the bootstrap family; the scout verdict (EXPLORE.md) is the base, its §5/§7
re-derived into the owner-leg package below. Model routing: every tier `openrouter/qwen/qwen3.8-flash`
(standing human directive, STATE.kickoff).

## Goal

Lane dispatch #215 died on the Dockerfile helm-bake `curl` reaching `get.helm.sh` with **TLS exit 35**
— the D33 egress class the chart header itself documents (values.yaml:76-81) and which has now
recurred twice (first release fire: ECONNRESET at job runtime; #215: TLS-35 at build time). Harden the
class repo-side in ONE commit (recommended package: Dockerfile retry budget + dind `--mtu=1450`, each
with its measured test pair), then hand the owner one batched decision round (re-dispatch-first
experiment + which family) followed by the dependency-locked heal chain:
merge → mint → **UA-10 live gate** → runner-app syncs → jobs start.

> **2026-11-23 CORRECTION (governs): owner Q1 = NO early re-dispatch; O-2's single dispatch runs
> ONLY on the hardened main post-O-1-merge. The re-dispatch-experiment option above is WITHDRAWN;
> retry-safety law stands as recorded fact, unused.** The stale recommendation surfaces this block
> overrides are, for any plan-only reader, exactly three — the Goal's "(re-dispatch-first
> experiment…)" parenthetical just above, O-0's Q1 bullet (its command shape is now history, not an
> owner step), and Open questions #1 ("recommended yes"). The round is ANSWERED: see
> STATE.plan.owner_round + DECISIONS 2026-11-23 for the family/scope answers that govern execution.

## Out of scope

- Executing anything in the owner-leg list (O-1..O-7): dispatches, merges, package visibility, ArgoCD
  syncs, registry copies, restarts — all human-owned; agents stay readonly.
- The UA-10 **fail path**: if the instance package is not anonymously pullable after the mint, the
  A′ auth-mount amendment (`/data/.docker/config.json` via the chart, run-0 family) is the NEXT
  ticket — nothing here pre-builds it, and O-3 forbids syncing into pull-death meanwhile.
- A fleet-wide `--retry` retrofit of the other downloading Dockerfiles (coder-workspace,
  forgejo-host-runner, snapcast, music-assistant — fact F2): this ticket hardens the proven-failing
  bake; (c) is what covers the class generally.
- Any move of `.forgejo/workflows/*`, `.github/workflows/*`, `scripts/forgejo-container-detect.sh`,
  `Chart.yaml` version, board cards, or the inherited deferred set (26.11.2 re-pin pair, ghcr settle,
  cf-55 retests, ci-surface t4, t9-exemption, lane-design card).
- Fixing the collateral itself (fleet dead, registries never minted): those are owner legs, not repo
  work — EXPLORE §2.3/§3 is the record; DECISIONS carries the scout verdict.

## Verified facts (this plan session, read-only + /tmp SIMs; BASE = origin/main `dcc54c091`,
## worktree tree == BASE, per EXPLORE §1 — nothing to merge)

- **F1 — the build path is shared.** The lane builds at `builder-bootstrap.yaml:183`
  (`docker build "${build_args[@]}" "containers/forgejo-runner"`); containers-build builds the same
  Dockerfile through the same in-pod dind daemon at `containers-build.yaml:348` (release arm) and
  `:405` (PR arm). A lane-only network change protects strictly less than a build-content or daemon
  change. (reads)
- **F2 — no retry precedent in the repo's Dockerfiles.** Every bake download
  (`containers/*/Dockerfile`, grep over all) is bare `curl -fsSL` / `wget`; the strata precedent
  handled the same class by re-pointing apt mirrors, not by retrying. Family (a) introduces the
  `--retry` idiom deliberately, scoped to the proven-failing image.
- **F3 — the mitigation was documented, never applied.** `git log -S 'mtu=1450' --all` is EMPTY; the
  values.yaml header (L76-81) still only *names* `--mtu 1450` / per-job host net as candidates from
  forgejo/runner#1779 research. The class is recurrent (two documented deaths), so a transient-pass
  re-dispatch today would leave the class unhardened — the fix lands regardless of Q1's answer.
- **F4 — (a) moves ZERO existing container-suite teeth; its new pins are pair-honest both ways.**
  SIM (measured): shipped `tests/containers/forgejo-runner.sh` = 8/8 GREEN against a retry-flagged
  Dockerfile (t3/t4 grep the URL/verify/install/assert shapes; flags inside the curl operand are
  invisible to them; hadolint t7 error-threshold stays clean). An extended t3/t4 (retry-budget greps
  anchored `curl -fsSL --retry [0-9]+ --retry-all-errors[^&|]*…`) reads RED against the shipped
  Dockerfile and GREEN against the flagged one. Baseline re-ran LIVE here: containers 8 ok, bb 20 ok.
- **F5 — the brief's (b) teeth hypothesis is FALSE by measurement.** Adding `--network=host` to the
  lane build line keeps the shipped bb suite 20/20 (b5/b8/b10 do NOT move — b8 anchors `^docker build
  ` and the final-token context; the bt battery still bites). A candidate b8 pin (the build line must
  carry `--network=host`) measures RED against the shipped lane, GREEN against the flagged one — so
  (b) is the same cost shape as (a) (file + in-suite pin), with narrower coverage (F1).
- **F6 — (c) moves one EXISTING leg and needs a bounded re-arm: g7.** SIM (measured): the ORIGINAL
  `gpu-forgejo-runner.sh` g7 blast-radius leg goes RED on a chart edit that adds the dind args
  (`moves non-comment, non-label lines: ['+          args:', '+            - --mtu=1450']`); a
  re-armed g7 with a FOURTH sanctioned class (value-exact two-line pair, `charts/forgejo-runner/values.yaml`
  only, add-side only, absence legal) is GREEN vs clean, GREEN vs the full pair (+1 ok line → gpu
  suite 19→20 at BASE-pinned diff), and RED vs a half-applied pair (surgical, per the docker_host
  precedent's review lessons). g7 contributes 3 oks today (count file measured).
- **F7 — the dind render contract tolerates the flag.** The pinned `docker:29.9.2-dind` image config
  (anonymous dockerhub probe: amd64 manifest → config blob) has `Entrypoint: ["dockerd-entrypoint.sh"]`
  and **no Cmd** — args starting with `-` are `dockerd`-prefixed by the entrypoint, and the unix-socket
  default the probes/tests pin stays the default. `helm template` with the args renders
  `args: ['--mtu=1450']` on the dind initContainer with image/restartPolicy/privileged/probes
  byte-unchanged. dev t2 pins those fields but does NOT inspect dind args (nor does t13) → no dev
  breakage; the positive render proof belongs in t2 as a TEST-authored extension (RED before DEV's
  chart edit, GREEN after).
- **F8 — the retry flag set is deterministic for exit 35.** The bake runs on the act-24.04 base
  (Ubuntu 24.04, curl 8.5.0): `--retry-all-errors` exists since 7.54 and is REQUIRED here — plain
  `--retry` only re-tries curl's transient-class list, and TLS-connect (35) classification is not
  guaranteed; `--retry-connrefused` (7.52, ref class) is subsumed and unnecessary. Proposed budget:
  `--retry 5 --retry-all-errors --retry-delay 2` on all three bake fetches (helm tarball, sidecar, cr).
- **F9 — registries remain empty and nothing new happened** between the scout probes (23:16–23:23Z)
  and this session: infra+dev `curatedforest/forgejo-runner` NAME_UNKNOWN + pkg-api `[]`, ghcr 403 —
  EXPLORE §3 stands; the first successful lane mint on infra derives `26.11.1` from the empty walk
  (single-registry law), which is exactly what both pin sites (chart L141-145, dev slice L194-198)
  already name.
- **F10 — heal-chain identities are chain-grounded, not invented:** Application
  `gpu-forgejo-runner-gpu` (gpu cluster ns default, OutOfSync since 22:22:34Z, event-proven; ArgoCD
  CRD unreadable via readonly MCP → owner-side), dev twin Application `dev-forgejo-runner-dev`,
  statefulsets `gpu-forgejo-runner-gpu` / `dev-forgejo-runner-dev`, reloader auto-roll with the
  documented `kubectl -n default rollout restart statefulset/...` fallback, ArgoCD apps follow
  **GitHub** main (debug-1 EXPLORE:213) and GitHub main is ALREADY == `dcc54c091` (hand-synced,
  EXPLORE §1) — so after O-1 the only repo-side gate to the fleet map is the sync itself, gated by
  UA-10.

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | D33 egress hardening: Dockerfile retry budget + t3/t4 pins, chart dind `--mtu=1450` + g7 re-arm + dev t2 render pin — one change (scope set by the owner round; (a)/(c) sub-pairs are independently landable) | M | 1 | [] | — |

One chunk: the two mitigations are one ruling package (F1/F3 argue jointly); their file sets are
disjoint and each sub-pair (file + its pins) is whole in itself, so an owner pick of (a)-only or
(c)-only just shrinks pending C01 — no chunk is ever half-landed (one-change pair law: a pinned suite
against an unshipped file is a RED tree BY DESIGN).

## Wave order

1. **C01** — TEST first: extend `tests/containers/forgejo-runner.sh` t3/t4 with the retry-budget greps
   (authored-RED vs the shipped Dockerfile, GREEN after dev's edit — F4) and, if (c) is in scope,
   re-arm g7 in `tests/services/gpu-forgejo-runner.sh` (green-vs-clean + red-vs-half, F6) plus extend
   dev t2's dind block with the args render pin (authored-RED vs the clean chart, F7). Then DEV: the
   three curl lines + bake comments in the Dockerfile; the dind `args` pair + the header
   "documented→applied" note in `charts/forgejo-runner/values.yaml`. One commit (coord).

## Commands (the validation bar — landing tree)

```bash
export PATH=$HOME/.local/bin:$PATH
BASE=dcc54c091   # ALWAYS resolve-check: git cat-file -t $BASE => commit (vacuous-green law)
bash tests/containers/forgejo-runner.sh        # 8 ok — t3/t4 now carry the retry-budget pins
bash tests/services/forgejo-builder-bootstrap.sh   # 20 ok — lane file byte-untouched (byte-proof below)
bash tests/services/dev-forgejo-runner.sh      # 58 ok — t2 dind args render pin (in-leg, count stays)
GPU_RUNNER_DIFF_BASE=$BASE bash tests/services/gpu-forgejo-runner.sh
                                               # 20 ok — g7 fourth-class line green at the full pair
                                               # (19 while the class is absent — F6; record which fired)
bash tests/services/forgejo-containers-build.sh    # 41 ok — untouched
bash tests/services/forgejo-main-sync.sh       # 8 ok — untouched
bash tests/services/forgejo-release.sh         # 20 ok — untouched
bash tests/services/forgejo-renovate.sh        # 8 ok + t9 default-off skip — untouched
bash tests/renovate/forgejo-move-config.sh     # 8 ok — untouched
bash tests/services/forgejo-ci-surface.sh      # ONLY-t4-red, the two carried D29 FAIL lines byte-identical
# chart validation (AGENTS hard rule for charts/** edits):
helm lint charts/forgejo-runner && helm template charts/forgejo-runner >/dev/null
# byte-proofs (each EMPTY vs BASE) — the frozen scope of this run:
git diff $BASE --exit-code -- .forgejo/workflows/ .github/workflows/ scripts/ containers/coder-workspace/
git diff $BASE --exit-code -- charts/forgejo-runner/Chart.yaml charts/forgejo-runner/templates/
git diff $BASE --exit-code -- services/ custom-values/
# (a)-pins (NON-empty):
grep -c -- '--retry 5 --retry-all-errors' containers/forgejo-runner/Dockerfile   # => 3
# (c)-pins (NON-empty) — rendered proof. The suite-native proof is dev t2's extended args pin;
# the standalone shape runs against a /tmp dependency-built copy (charts/**/charts is gitignored —
# keep it out of the worktree; this session verified the landed render exactly this way):
SIM=/tmp/opencode/cf6-b3-render   # RE-COPY the landed chart into a dependency-built /tmp copy first
helm template fr $SIM/forgejo-runner | python3 -c "
import sys, yaml
for d in yaml.safe_load_all(sys.stdin):
    if d and d.get('kind') == 'StatefulSet':
        c = next(c for c in d['spec']['template']['spec']['initContainers'] if c['name'] == 'dind')
        assert c.get('args') == ['--mtu=1450'] and c.get('command') is None and c['image'] == 'docker:29.9.2-dind'
        print('ok: dind args rendered exactly')
"
# rulesync: N/A — no .rulesync source moves (docs stay inside the chart header + Dockerfile comments)
npx --yes aislop ci --changes                  # quality gate (score floor, zero errors)
# docker build => no-daemon, CI-deferred (t8 designed passing shape; the live build proof is O-2)
```

No cluster mutation, no dispatch, no merge, no secret changes in ANY agent session.

## Owner legs (all user-owned; dependency-ordered — the O-3 gate is the spine)

- **O-0 — the batched round (answer BEFORE acting):**
  Q1 re-dispatch #215 now? — **2026-11-23 CORRECTION (governs, per the block under Goal): ANSWERED
  NO — WITHDRAWN as an owner step; everything in this bullet below is kept as history, do not
  execute it.** — recorded for history, the pure experiment was: Actions UI → builder-bootstrap → Run workflow
  (bare, no input) on infra, or
  `curl -u "<user>:<token>" -X POST "https://git.spencerslab.com/api/v1/repos/CuratedForest/SpencersLab/actions/tasks/builder-bootstrap/schedule?ref=main"`
  — retry-safe by the lane's own N+1/gaps law; a warm docker-data store makes it cheaper than #215.
  Recommended: run it while the PR review completes; the fix lands regardless (F3).
  Q2 which family: (a)+(c) recommended / (a) only / (c) only / (b) instead (F5 gives its honest cost).
  Q3 accept `--mtu=1450` fleet-wide (it lands on BOTH runner releases via the one chart — F7 — and
  takes effect only at O-4's sync+daemon restart).
  P1 (fact, not choice) — the probes that settle the class:
  `kubectl -n default exec gpu-forgejo-runner-gpu-0 -c dind -- curl -fsSv -o /dev/null https://get.helm.sh/helm-v3.22.1-linux-amd64.tar.gz`
  (daemon-namespace path vs the job-NAT death; EXPLORE §4.3.3), plus the §4.3.2 disk-usage pair,
  the §4.3.1 job step log ("build and push" of run 215 — names which curl and the stderr), and the
  §4.3.5 vars/secrets reads (ROLE verbatim).
- **O-1** — merge the run-3 PR (rebase per owner style; GitHub main must end == forge main again —
  the hand-sync trap of §1 is the current fan-out state while main-sync is dead).
- **O-2** — dispatch the lane on INFRA after O-1 (bare button; under (a) the retry budget is in the
  Dockerfile the job checks out from main; mints 26.11.1 ×{tag,latest,main} to the infra registry
  ONLY — B law; nothing reaches ghcr from this lane).
- **O-3 — UA-10 LIVE GATE (blocking — do NOT proceed on a fail):** the just-minted package must be
  PUBLIC + anonymous-pullable. Owner: infra instance → org CuratedForest → Packages → forgejo-runner
  → visibility = public (not push-settable), then
  `TOK=$(curl -s "https://git.spencerslab.com/v2/token?scope=repository:curatedforest/forgejo-runner:pull" | jq -r .token)` ;
  `curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOK" "https://git.spencerslab.com/v2/curatedforest/forgejo-runner/manifests/26.11.1"` ⇒ 200 ;
  belt: logged-out `docker pull git.spencerslab.com/curatedforest/forgejo-runner:26.11.1`.
  FAIL ⇒ STOP: no O-4 sync (that would recreate the 403-pull fleet death on the other host); the A′
  auth-mount amendment (/data/.docker/config.json, run-0 family) becomes the next ticket with the
  probe evidence.
- **O-4** — fleet heal, infra half: sync Application `gpu-forgejo-runner-gpu` (gpu cluster, ns
  default; OutOfSync since 22:22:34Z) — ArgoCD UI sync (the exact kubectl/argocd-CLI shape is
  owner-side: the Application CRD is unreadable through the readonly MCP, EXPLORE §6.5 — both
  spellings left to the owner; nothing in this repo may `kubectl apply`); the reloader annotation
  rolls the pod (fallback `kubectl -n default rollout restart statefulset/gpu-forgejo-runner-gpu`);
  the restarted dind daemon now also carries the (c) flag if chosen. The sync re-applies run -1's
  per-instance label map AND the (c) chart half — one sync heals both.
- **O-5** — dev leg: manual copy of the EXACT minted tag (F9: 26.11.1 unless the month crossed) to
  the dev registry (OL3 shape, debug-1 L1): pull from `git.spencerslab.com/curatedforest/forgejo-runner:26.11.1`,
  retag `git.scifi.farm/curatedforest/forgejo-runner:26.11.1`, login + push with a dev-side
  write:package PAT; set the dev package PUBLIC; UA-10 probe dev-side (same pair, dev host); sync
  Application `dev-forgejo-runner-dev` (+ reloader roll, fallback rollout restart on
  `statefulset/dev-forgejo-runner-dev`).
- **O-6** — fan-out verification: GitHub main already == `dcc54c091` (scout: `curl
  https://api.github.com/repos/OwnYourIO/SpencersLab/branches/main` — confirm it moved to the O-1 tip
  too or hand-push per debug-1 L4 shape, plain non-FF-guarded push, owner-only). Then the first
  healed main-sync run finally tests BOTH the `PUSH_TOKEN_GH` credential fix (never executed) and the
  fan-out.
- **O-7** — verifications: open/re-run a renovate-class PR touching containers/** (PR arm starts on
  the baked image); watch containers-build release arms (their next full green mints 26.11.2 DUAL —
  which re-arms the inherited 26.11.2 re-pin-pair deferred card); fleet-wide green across main-sync /
  release / containers-build / builder-bootstrap.

## Risks / merge caveats

- **Retry can mask a hard block:** if `get.helm.sh` is systematically black-holed from the job NAT
  path (deterministic MTU drop), five attempts die anyway — LOUDER (later, more log), not quieter.
  That is the honest case for O-0 P1 and for (c) being the class answer; it does not argue against
  (a), which costs 3 flag groups.
- **`--mtu=1450` side effects:** bridge-driver networks inside dind only (job→outside paths); the
  pod-level socket contract is untouched (F7 render proof); RESEARCH names the flag as candidate with
  no recorded measured side effect — the accepted-delta is a slight throughput ceiling on large
  pushes through the bridge and a fleet-wide daemon config change (BOTH releases) that activates at
  O-4. Owner accepts at Q3 or rejects → (a)-only.
- **Sync-before-pullable trap (the ordering law of this run):** syncing the runner apps while the
  instance package is private/absent re-creates exactly the 403 job-start death that killed the fleet
  on ghcr. O-3 gates O-4/O-5; a fail STOPs the chain into the A′ amendment ticket.
- **If the owner picks (b) as fallback:** `--network=host` puts the build's RUN containers in the
  dind daemon's (pod) netstack. Grounded against the pod-local design (cf-97 trust boundary,
  values.yaml:184-188): the marginal privilege is ~nil — jobs ALREADY hold the privileged daemon's
  socket by design ("unprivileged is not the same as unreachable"), so a job can today start its own
  host-network container; (b) merely removes the NAT path for one build. The honest objection is
  coverage (lane-only, F1/F5), not security. RESEARCH Q5 also notes host-net is what the upstream
  k8s dind example itself ships for jobs — so it is sanctioned precedent if ever chosen.
- **Month-cross:** registries empty at probe time (F9); if O-1..O-2 slip past Nov 30 the lane mints
  `26.12.1` while both pin sites say `26.11.1` — the standing owner amend-pair coupling applies.
- **Cold-ish retry:** the base layers were proven reachable (the build got into a RUN; §4.2e refuted);
  a retry starts warm in docker-data. The 30 m runner ceiling stays the bound; a timeout red is
  retry-safe by the same law. (cf-55 prune caveat stands: O-0 P1's disk read settles it.)
- **Half-pair trees are RED by design:** do not land the Dockerfile without the t3/t4 pins, or the
  chart pair without the g7 re-arm + dev t2 pin; a re-scoped C01 (one family only) must keep each
  landed sub-pair whole.

## Open questions (the batched owner round — see O-0)

1. Re-dispatch #215 NOW (zero-code transient-pass experiment) — recommended yes, with the fix landing
   regardless (recurrence-proven class, F3).
2. Which mitigation family: **(a)+(c) combined (recommended)** / (a) only / (c) only / (b) instead of
   (c) (F5: same teeth-cost, lane-only coverage).
3. Accept `--mtu=1450` on BOTH runner releases' dind daemons (fleet activation at O-4 sync)?
4. P1 probe answers (job-path reachability, ROLE verbatim, docker-data usage, step-log stderr) — facts
   that can flip 2/3 after the fact, and always feed O-3's package-visibility check early (org default
   visibility decides whether O-3 passes at all).

## Deferred / carried (unchanged, inherited from run -2 STATE)

lane-design card; UA-10 probe card (NOW consumed by O-3 as the live gate — retire on O-3's execution);
run-1 carried set: 26.11.2 re-pin pair (re-armed by O-7's first release-arm mint), ghcr settle,
cf-55 retest-first, ci-surface t4, t9-exemption retirement.
