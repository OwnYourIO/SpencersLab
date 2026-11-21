# C03-fix: runbook rework — main-sync origin, Actions-vault secret, job+door, dual-dialect smoke, kill switch
size: S   wave: 6   depends_on: [C02-fix, C04]   fixes: C03 (done @ a3c2c2f15/0ccf80196)

## Goal

Bring `.agents/notes/2026-11-17-argocd-hook-relay.md` to the ruled design: the trigger is
the main-sync `hook-relay` job (no webhook is created — R1), the shared HMAC now lives in
two vaults (Bitwarden + the prod instance's Actions secrets — R4 rename included), the
public edge stands as the documented future door (R2), the smoke runs gain the dispatch
trigger and the plain-hex dialect, and the rollback gains the real kill switch (unset the
instance key — instant, no git).

## Tasks

- [ ] Header (line 6): the four setup legs become (Bitwarden items, per-cluster token
      mints, custom-values UUID fill, **Actions vault key placement**) — drop "GitHub
      webhook".
- [ ] §1: one more bullet — **origin**: canonical trigger = main-sync `hook-relay`
      job after `push-gh` (fleet still sources GitHub 9/9 per [P], so firing after the
      mirror push is what makes fan-out resolve the NEW revision); dialect line: relay
      accepts `X-Hub-Signature-256` (prefixed) and `X-Forgejo-Signature` (plain hex),
      first-present header wins, no fallback; rename line: `/secrets/hook-secret`.
- [ ] §2 Step 0: item 1 wording — "fresh random high-entropy **shared relay<->main-sync
      HMAC**"; filename/key references → `hook-secret`; ADD leg: on the PROD forge
      instance set repo Actions **secret `ARGOCD_HOOK_SECRET` = the `argocd-hook` item
      password** and repo Actions **var `ARGOCD_HOOK_URL` = the relay URL the runner
      reaches** (mesh or public name — owner's instance-side call; the dispatch smoke
      proves whichever); note the value lives twice (Bitwarden item password + Actions
      secret) and both must agree, a 401 in the job log means they don't.
- [ ] §4 replaced wholesale (was "Step 2 — GitHub webhook (human)"): "Step 2 — trigger:
      the main-sync hook job (nothing to create)". Explain: merge + one push to main on
      the prod forge runs it automatically; on prod it fires after push-gh lands GitHub;
      dev/unset-ROLE fire nothing; unset `ARGOCD_HOOK_URL`/`SECRET` ⇒ job logs the skip
      warning (that IS the kill switch). **Future door (R2)**: the public
      `https://argocd-hook.spencerslab.com/` entry stays; if the owner ever wants a real
      webhook, the race-free option is a GitHub-repo webhook (prefixed dialect, the apps
      track GitHub anyway) — a raw Forgejo push webhook must NOT be created (fires before
      push-gh ⇒ syncs the previous revision — [P §3]); Forgejo-type webhook header/signature
      behavior is already supported but Test-Delivery payload shape is unverified if ever
      used live.
- [ ] §5 smoke rewritten: **(a) trigger smoke** — `workflow_dispatch` main-sync on the
      prod instance: push-gh runs (no-op if up to date), hook-relay logs
      `ok: relay accepted code=202 …`, relay audit shows `push accepted
      ref=refs/heads/main delivery=<run-tag> targets=11` + per-target lines (dispatch
      fallbacks make the payload without a push event — call this out); **(a2)** optional
      non-matching ref still 200 no-op (b′ logic via a hand dispatch is not possible —
      keep b′ as signed curl); **(b)** signed synthetic curl: BOTH recipes — the existing
      hub prefixed one AND plain-hex (`awk '{print $NF}'`, header
      `X-Forgejo-Signature`) — each expect 202; wrong-value expectations (401) documented;
      **(b′)** unchanged; **(c)** real merge end-to-end, latency now = mirror push-gh +
      relay fan-out (seconds-to-minute), watch app status not just relay logs (home note
      stands).
- [ ] §7 rollback leg 1 replaced: **instant source stop = unset the prod instance's
      `ARGOCD_HOOK_URL`/`ARGOCD_HOOK_SECRET`** (Actions UI, human; job then warns-and-skips
      every run — fleet reverts to manual sync, no git churn); if a GitHub webhook was ever
      created under the R2 door, disable/delete it there too (Recent Deliveries stays).
      Leg 2 (git revert PR of chart/wiring/job + one manual root sync) stands; note
      reverting also removes the hook job once the PR lands.
- [ ] §8 limitations: add **R1 failure posture** — fan-out trigger failure (job skip, POST
      dead, relay down mid-run) ⇒ that push lands as no-op at the old revision; no
      redelivery exists for Actions runs; the NEXT push to main self-heals (fan-out is
      SHA-agnostic); fallback otherwise = manual sync, as today. "No replay" bullet
      reworded to the job origin.
- [ ] Sweep for stale GitHub framing repo-wide in docs: grep `github-webhook` and
      webhook-creation phrasing in the runbook ⇒ zero; relay README + chart README parity
      (already C01/C02-fix scope — verify, don't re-edit).
- [ ] Re-pinned `tests/notes/argocd-hook-runbook.sh` green; all other ticket suites
      re-run as the regression set.

## Files in scope

- `.agents/notes/2026-11-17-argocd-hook-relay.md`
- (test re-pin: `tests/notes/argocd-hook-runbook.sh` — agent-test session, before dev)

## Acceptance criteria

1. §4 contains NO webhook-creation steps for any platform as a required step; it states
   the job trigger, the unset kill switch, the R2 door with its race warning against a
   raw Forgejo push webhook, and the GitHub-webhook-if-ever choice.
2. §2 lists the Actions vault leg with the exact key names (`ARGOCD_HOOK_SECRET`,
   `ARGOCD_HOOK_URL`) and the two-vaults-must-agree sentence; the HMAC secret is described
   as shared relay<->main-sync (no "GitHub HMAC" framing remains; the R2 door paragraph may
   name GitHub as future webhook provider).
3. `hook-secret` used for the key/file everywhere; `github-webhook` grep = 0 in the
   runbook.
4. §5 smoke: dispatch leg (a) present with expected log tokens; signed curl shows BOTH
   dialects with exact recipes; (b′) non-matching-ref 200 case intact; (c) latency wording
   includes the mirror step.
5. §7/§8: unset-keys kill switch leg1; R1 no-op-at-old-revision + next-push self-heal
   limitation present; no GitHub-Webhook-creation-only rollback remnants (disable-if-
   exists wording OK).
6. Parity: every token in §1/§2/§5 matches the shipped C01-fix/C04 (header names, payload
   fallback defaults, `X-GitHub-Event: push` unchanged event gate, code=202 expectation);
   reviewer greps the workflow file for each quoted string.
7. All four suites green (relay, wiring, runbook, forgejo-main-sync) + base/chart
   regression Commands from the plan; diff scope = runbook file only.

## Tests (agent-test re-pins, review runs)

`tests/notes/argocd-hook-runbook.sh` re-pinned:
- forbidden leg: `github-webhook` absent; no required-webhook-creation block (greps the
  GitHub Settings path token only inside the R2 door sentence context).
- required legs: `ARGOCD_HOOK_SECRET` + `ARGOCD_HOOK_URL` (§2), `hook-secret` (§2/§3/§5),
  `X-Forgejo-Signature` + `awk '{print $NF}'` (§5 plain-hex recipe), dispatch smoke tokens
  (`workflow_dispatch`, `code=202`), kill-switch tokens (§7 `unset`, warning-skip),
  R1 limitation tokens (`no-op at the old revision`, `next push`), parity grep against
  `.forgejo/workflows/main-sync.yaml` (each quoted job token exists in the file).
- t-rows/sections/preflight legs (unchanged sections 1–3,6–8 shape) still green.

## Notes for dev

- Sections 3 (bootstrap), 6 (preflight table) keep their content — final-review fixes
  already verified hosts/home-drift wording; only touch them for origin/dialect renames.
- Human-executed marker discipline unchanged on every command.
- Do not create the Actions var/secret or dispatch anything live — you edit docs; the
  runbook instructs the owner.
- comment-slop/aislop; commit is coord's.

## Review notes (review agent fills)
