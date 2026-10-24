# CA4: entrypoint relocation — degrade logic moves from k8s yaml into the image
size: M   wave: 4   depends_on: [CA1 (wiring + image contract re-expressed against the repo-side entrypoint)]
# parallel with CA3: behaviorally independent (different values sections + containers/**); coord may serialize (shared worktree/values.yaml).

## Goal
`containers/llama-swap-autogen` owns the generate/degrade/fail-open logic as the image
ENTRYPOINT (`entrypoint.sh`); the chart wires image + args + mounts only — no shell script in
k8s yaml. Behavior is contract-identical: fail-open exit 0, comment-only `10-scanned.yaml`,
success never clobbered, tool stderr preserved on the container log, HOME/cache lands on the
init-only emptyDir (explicit `--home` arg replaces C03's passwd-fallback reasoning).

## Tasks
- [ ] `containers/llama-swap-autogen/entrypoint.sh` (new): POSIX sh, `#!/bin/sh`, flags
      `--scan-dir DIR` (repeatable) `--base FILE` `--out FILE` `--home DIR`; missing/dup/empty
      required flags → usage message to stderr + nonzero exit (wiring bug = loud; rc0 degrade
      stays reserved for scan-empty/generate-fail ONLY); `export HOME=<dir>` before invoking
      the generator; logic ports the current inline script verbatim-equivalent: quick-find
      (`-iname '*.gguf'`, per-dir, early-exit), no-GGUF → degrade comment file + exit 0;
      `llama-swap-config-autogen generate --config $BASE -o $OUT` failure → degrade overwrite
      + echo of tool output above + exit 0; success → keep generated file, exit 0.
      (Deferred-(e) `find -print -quit` restructure MAY fold in here — C03 review sanctioned
      it as the correct shape once the script moves; not required.)
- [ ] `containers/llama-swap-autogen/Dockerfile`: `COPY entrypoint.sh /entrypoint.sh`,
      `RUN chmod 0755` (or `COPY --chmod=755`), `ENTRYPOINT ["/entrypoint.sh"]`; user/uid/
      pin/renovate-ARG lines untouched; console script stays on PATH (gated evidence runs it
      via `--entrypoint` override).
- [ ] `charts/llama-swap/values.yaml` initContainers.autogen: DELETE the `command:` script
      block; add `args: [--scan-dir, /models/scanned, --base, /app/autogen/base.yaml, --out,
      /app/gen/10-scanned.yaml, --home, /home/autogen]` (rendered from the same values keys
      where possible); image/securityContext/resources/mounts unchanged (autogen-home
      emptyDir mount STAYS).
- [ ] `_helpers-llama-swap.tpl` `llama-swap.autogenBase` drift guard re-armed, still
      fail-fast-on-disagreement: parse the initContainer `args` — the `--scan-dir` SET must
      equal `autogen.scanPaths` (sorted, both directions, same "edit both or neither" error);
      `base.yaml` path arg must equal the CM mount path; ANY initContainer `command:` on the
      autogen container fails the render (shell-reintroduction tripwire — enforces "no shell
      in k8s yaml"); missing args → fail.
- [ ] Keep all values comments that carry the fail-open/EROFS rationale; move them next to the
      args block (the reasoning now lives half in entrypoint.sh — cross-reference).

## Files in scope
- containers/llama-swap-autogen/entrypoint.sh (new), containers/llama-swap-autogen/Dockerfile
- charts/llama-swap/values.yaml (app-template initContainers section + autogen block only)
- charts/llama-swap/templates/_helpers-llama-swap.tpl (autogenBase guard)
- charts/llama-swap/templates/configmap-autogen-base.yaml (comment only, if needed)

## Acceptance criteria
1. CA1-re-expressed wiring tests green: rendered initContainer has image+args, NO command;
   degrade trio passes executing `sh containers/llama-swap-autogen/entrypoint.sh` with stub
   CLI (empty-scan rc0+comment-only; stub-fail rc0+degrade; stub-success content preserved);
   usage-error case (missing flag) exits nonzero.
2. Drift-guard probes fail the render: args scan-dir ≠ `autogen.scanPaths` → fail;
   a reintroduced `command:` → fail.
3. `helm lint --strict` + three renders pass; pod JSON delta vs CA3 tip = exactly
   command→args swap (mounts, secCtx, volumes incl. autogen-home, main container byte-identical).
4. Image tests green: Dockerfile COPY+exec+ENTRYPOINT shape; gated docker cases keep the
   console-script check via `--entrypoint` override (skip honestly, waiver scope unchanged).
5. Declared-half ConfigMap bytes + base.yaml CM sha unchanged vs CA3 tip (this chunk must not
   touch model rendering); suite reds = CA2 scope only.

## Tests (agent-test writes, review runs)
All CA1-written (wiring degrade/args/guard + image entrypoint). Review re-runs suite, the two
guard probes, and a fresh rendered-pod diff vs the CA3 tip.

## Notes for dev
- The degrade semantics are the CONTRACT (fail-open DECISIONS 2026-10-22): port them
  exactly; do not "improve" the exit codes of the scan/generate paths.
- entrypoint.sh is the shipped entrypoint for a python-slim image: `/bin/sh` exists (debian);
  no bash-isms; quote paths; `set -u`.
- Post-merge the image rebuilds via docker-build.yaml; chart keeps `:main`+Always (existing
  new-container exception; pin first `:v<run>` later — post-merge obligation unchanged).
- aislop + comment-slop rules apply to the shell file like any source.

## Review notes (review agent fills)

### Round 1 — 2026-10-24 (fresh-context review; commit 601073581; verdict: **APPROVED**)

**1. Bars re-run (all exact):**
- `helm dependency update` + `helm lint` + `helm lint --strict` => pass (only the
  standing icon INFO).
- `helm template` x3 (default / gpu / gpu-ai, extract-and-render) => 62476 /
  64134 / 81162 B, all rc0 — guards + tripwire silent on default values ✓.
- `pytest charts/llama-swap/tests -v` => **13 failed / 134 passed / 12 skipped**;
  FAILED set name-identical to CA3's recorded CA2-13 (parity P1[gpu]+P5[gpu] = 2,
  schema 3 value-shape + 6 fam_* = 9, roster exact[gpu] + isolation-flip = 2) —
  zero CA4-scope reds, zero new. The 8 CA4 flips verified PASSED by name
  (degrade trio, usage, --home, args-not-command x2, entrypoint relocation), plus
  both drift probes PASSED.
- Existing CI 4 files => **33/33**. `LLAMA_SWAP_EVIDENCE=1` gates => **3p/5s**
  (same 5 honest daemon/binary skips; waiver scope unchanged).
- Scope: `git show 601073581 --name-only` = exactly the 4 declared files;
  `git diff ebceb56c7..601073581 -- tests/` => **0 lines** (tests untouched).
- `aislop scan charts` + `containers` => 0 diagnostics attributable to the four
  CA4 files (rc1 = warnings-only noise in pre-existing files; FRICTION-confirmed).

**2. §7bis-K carry-forward — HEADLINE DUTY DISCHARGED.** Re-ran both drift
probes directly against helm (not via pytest) and confirmed they now fail for
**args-guard reasons**, the old script-guard messages gone from the codebase
(grep: zero `SCAN_DIRS` refs in templates):
- scanPaths ⊃ args: `autogen.scanPaths (/models/extra /models/scanned) and the
  initContainer --scan-dir args (/models/scanned) disagree - edit both or neither` rc1 ✓
- REVERSE direction (args-only extra `--scan-dir /models/extra`): same disagree
  message, sets swapped ✓ — "both directions" claim verified.
- `command: [/bin/sh, -c, …]`: tripwire message ✓. `command: []`: fires ✓.
  `command: null`: render also fails (rc1), but at the app-template subchart
  **schema gate**, not the tripwire message — behavior (loud) preserved; see
  minor-1 for the phrasing nuance.
- `--base` pinning (deviation-2): `--base /somewhere/else/base.yaml` => "is not
  the base.yaml ConfigMap mount file (/app/autogen/base.yaml) - edit both or
  neither" ✓. Empty args => "args carry no --scan-dir flag" ✓. Emptied
  advancedMounts => dedicated fail via `firstMountPath` returning "" ✓ — the
  FRICTION helm-dig-cannot-descend-slices define is sane (kindIs guards, index-0,
  dig with default, trim; the `$a` shadow inside the range is scoped-safety
  proven by base-CM sha equality).

**3. entrypoint.sh fresh-eyes read + MY OWN executed replay.** All runs under
**dash** (host /bin/sh -> dash, matching the debian-slim image env); `dash -n`
pass. No bashisms (`[[`, arrays, `local`, `$'…'` absent; `printf`/`case`/`$(( ))`
all POSIX). Contracts proven by execution, not by trust:
- **Empty-scan short-circuit before tool exec**: sentinel-stub PATH run (stub
  records invocation then fails) => rc0, comment-only 4-line `#` file, sentinel
  NEVER created — tool-never-ran independently proven. HOME-export correctly
  sits AFTER the short-circuit (never fires on empty scan).
- **Generate-failure degrade**: real pinned CLI (ag-venv c7357e68) + junk GGUF
  => rc0, tool's ERROR line kept on stderr above the degrade notice, file
  comment-only. (Bonus evidence: with an ALIGNED base but no CLI on PATH,
  rc127 still degrades to comment-only + rc0 — fail-open is total.)
- **Success never clobbers**: real CLI + gguf-py fixture (mirrors the gated
  integration maker) => rc0, file is the generated models map (`fixture-mini:Q4_K_M`),
  not overwritten.
- **`--home` export = C03 finding-#1 continuity**: on the success run,
  `$HOME/.cache/llama_swap_config_autogen` was created under the `--home`
  directory (proven by ls) — HOME -> --home, passwd-fallback reasoning properly
  superseded per DECISIONS 2026-10-24; values.yaml cache comments rewritten to
  match; `autogen-home` emptyDir mount stays (volumes diff = 6 identical).
- **Usage rc discipline**: missing --out rc2, duplicate --base rc2, unknown flag
  rc2, empty flag-value caught by the `[ -n ]` final checks rc2, dangling
  `--scan-dir` (flag last, no value) rc2 — degrade-rc0 stays reserved. rc is
  only ever 2 (usage) or 0 (post-parse); `if ! generate` shields the tool rc from
  escaping.
- **Quoting**: scan-dir/paths quoted everywhere; spaces-in-paths run passed
  (quick-find + OUT write both fine with spaces; IFS-newline split is
  space-safe). See nits 2/3 for glob chars and empty-string --scan-dir.
- Comments are all why-cards (exit-code contract, two-views-of-paths, -print
  -quit rationale) — no slop.

**4. Dockerfile.** Diff vs C01 tip (5b3dbb58d) = exactly the two intended hunks:
`COPY --chmod=755 entrypoint.sh` (+contract comment) and
`ENTRYPOINT ["/entrypoint.sh"]` exec-form. Renovate `git-refs` pin line,
`ARG AUTOGEN_COMMIT=c7357e68…`, pip archive-tarball install, groupadd/useradd
uid-65532 lines, `USER 65532:65532`, base pin — all byte-untouched (pinned-parse
tests green, including the renovate.json-custom-manager regex test). In-tree
mode 100755 (belt-and-suspenders with --chmod; COPY before USER => root-owned
0755, immutable under readOnlyRootFilesystem ✓; `--chmod` needs BuildKit,
docker-build.yaml builds with Buildx ✓). Console script stays on PATH via the
unchanged pip line; the gated docker checks' `--entrypoint
llama-swap-config-autogen` override remains statically valid — **no daemon here:
the actual in-image run (entrypoint exec, `find` presence under GNU findutils
for `-print -quit`, --entrypoint override) is a C05-with-daemon item, unchanged
waiver scope**. Args-absent behavior (usage rc2) is NOT a contract conflict:
DECISIONS 2026-10-24 mandates loud usage errors, the image test (amendment L)
pins ENTRYPOINT=["/entrypoint.sh"], and the chart guard makes an args-less
initContainer un-renderable (probe G) — the two contracts interlock.

**5. Chart delta audit (re-derived from git-archive render at e671e1c26).**
Per cluster (default/gpu/gpu-ai): doc inventory equal; ConfigMap data shas
EQUAL for all CMs incl. `llama-swap-config` (declared half) and
`llama-swap-autogen-base`; pod-spec leaf diff = **exactly 11 leaves = the init
command->args swap** (3 command leaves removed, 8 args leaves added) — main
container byte-identical, securityContext/mounts untouched, 6 volumes identical
(autogen-home stays init-only). Rendered initContainer `autogen`: `NO-COMMAND`,
args = the 4 flag pairs; both clusters carry `--scan-dir /models/scanned` ==
their `autogen.scanPaths` (no per-cluster scanPaths overrides — grep clean) ==
their base.yaml `models:` list (args-not-command tests green both clusters).

**6. Post-CA4 exact-13-ID sweep (CA3 lesson): ZERO residual** in all three HEAD
renders and across `services/ custom-values/ charts/ skills/ .rulesync/
.opencode/ containers/ .github/` (tests/golden frozen records excluded). CA4's
values/helpers edits reintroduced nothing.

**FINDINGS** — none blocking:
1. **minor** Deviation-3 phrasing vs mechanism (handoff record, not code):
   "tripwire fires on ANY command: key incl null" — for `command: null` the
   render fails at the app-template **schema validation** gate before the
   tripwire message (`command: []` and lists do hit the tripwire message —
   probes B/D verified). Loud-fail outcome holds; correct the wording if the
   STATE handoff is ever quoted as spec.
2. **nit** `for d in $SCAN_DIRS` (unquoted by design for IFS-newline split) is
   glob-expansion-active: `--scan-dir '<path>*'` with a matching filesystem
   entry iterates the MATCHES, not the literal path (demonstrated). Chart paths
   are constants and services never override scanPaths — add `set -f` next to
   `set -u` in a hardening chore if ever touched.
3. **nit** `--scan-dir ""` counts toward SCAN_COUNT (passes the no-scan-dir
   check) then silently degrades rc0 (`[ -d "" ]` false). Unreachable via the
   guard-pinned chart args; a `[ -n "$2" ]` in the case arm would close it.
4. **nit** `range $i, $a := $args` shadows the outer `$a` (`.Values.autogen`) —
   scoping verified harmless (binary macro still resolves; CM sha-equal);
   rename (`$arg`) for readability.
5. **nit** `firstMountPath` inspects only advancedMounts entry 0 — with a
   hypothetical second mount for the autogen container the guard would pin the
   first only. Current values carry exactly one entry; adequate.

**Continuity observations (no action):** degrade-file write failure (`> "$OUT"`
on an unwritable gen mount) still exits 0 silently — identical to the C03-era
script (verbatim-equivalent port), and the mount presence is pinned by the green
c03_1 mount tests. Old-script message wording is preserved modulo the
`-print -quit` fold (sanctioned, deferred-(e) item now CLOSED).
Chunk-task "rendered from the same values keys where possible": args are
literals, but the drift guard enforces equality with `autogen.scanPaths`/mount
paths at render time — equivalent guarantee, and CA2's values conversion touches
these sections anyway. Observation, not a deviation.

**Deferred:** in-image `find` + entrypoint execution under a real daemon -> C05
(docker-waiver scope unchanged; already STATE-flagged post-merge obligation).

Verdict: **APPROVED** — all 5 acceptance criteria met and covered by executed
validation; §7bis-K carry-forward discharged (both probes green with new-guard
reasons; reverse direction and --base pin additionally proven). CA2 (wave 5) may
proceed.
