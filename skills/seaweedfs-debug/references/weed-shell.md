# weed shell — operating discipline

How to drive `weed shell` safely in this lab: run form, stdin binding, the cluster lock, exit
codes, the `-collection` matcher, and paste-block conventions. Mechanics facts behind the
choices live in the sibling references (`collections-and-ec.md`, `error-signatures.md`); the
endpoint table is `mcp-server-spec.md` §3; repair SEQUENCES are never here — they have one
normative home: `.agents/plans/2026-11-10-dep-seaweedfs-ec-removal.md`.

Pin: weed **4.50** (`ec8f97935`). No agent tier grants pod exec — every block below is
human-pasteable text; agents contribute the read-only HTTP probes instead. Re-verify flag
shapes after any version bump (renovate carries 4.53.0 pending).

## Run form

The lab-standard paste block, from the master pod:

```bash
kubectl -n default exec -i seaweedfs-master-0 -c seaweedfs -- \
  weed shell -master=localhost:9333 -filer=seaweedfs-filer-client.default:8888 \
  2>&1 <<'EOF' | tee /tmp/sw_run_$(date +%Y%m%d_%H%M).log
lock
<verbs, one per line>
unlock
EOF
```

Binding rule: a heredoc body feeds the ONE pipeline segment it is attached to, not the whole
line — place the marker after `tee` and the commands feed `tee`'s stdin while `weed shell`
starves and executes nothing, silently (verified by experiment 2026-11-11; one of the traps
the runbook's corrections header records). `tee` goes LAST in the pipeline. Short single-shot
flows can skip the heredoc: `printf 'lock\n<cmd>\nunlock\n' | weed shell -master=…`.

- `2>&1` BEFORE the marker: per-command failure detail goes to stderr as `error: <detail>` —
  the redirect puts it in the tee'd log, so the log alone explains a failed run.
- Piped mode prints no interactive prompt, so the log is plain command output.
- `exec -i` keeps stdin attached; without it a piped session gets no commands at all.

## Lock-first law

- Mutation verbs fail with `need to run "lock" first to continue` unless the SAME session
  holds the cluster-wide exclusive admin-shell lock: `lock` / `<cmd>` / `unlock` in one piped
  run (verified 4.50 source, §R2.1).
- `lock` BLOCKS while another holder has it — typically the admin server's maintenance worker
  or a human shell — a wedged block at `lock` means wait, not kill-and-retry; the holder is
  queryable via the master's `GetAdminLockStatus`.
- A broken pipe mid-run leaves the CLUSTER LOCKED: recover with
  `echo "unlock" | weed shell -master=…` before re-pasting anything.
- Read-only verbs neither need nor take the lock; the dry-run no-lock stance resets per
  command and never leaks into the next one.

## Exit-code law (piped mode)

Present in 4.50 (PR #11117, merged 2026-09-03) — builds predating it exit 0 on failed piped
commands; re-check per build (§R2.1).

- A piped run **exits 1** if ANY command failed. `lastErr` is sticky: later successes never
  clear an earlier failure, and earlier successes never save a later failure — the exit code
  says "something failed somewhere", the stderr `error: <detail>` lines say where.
- Interactive sessions exit 0 even after errors (the operator sees them); the law is
  piped-mode only — drive scripted flows piped and trust `$?`, never eyeball a live session
  for pass/fail.
- Usage/syntax errors (unknown verb, bad flag) exit **2**, command failures **1**.
- Unknown commands count as failures — a verb removed or renamed upstream breaks a script
  loudly instead of printing nothing.

## `-collection` matcher law

Every shell `-collection` flag runs through `wildcard.CompileCollectionMatcher`
(weed 4.50, `weed/util/wildcard`; §R1.4):

| Pattern | Matches | Notes |
|---|---|---|
| `""` (or omitted) | every collection — verb-dependent | `ec.decode` excepts: `compileCollectionPattern("")` maps `""` to the `_default` sentinel, so there `""` ≡ the unnamed pool only |
| `*` | every collection | same verb-dependence; `volume.fsck`/`volume.vacuum` accept it as "all" |
| `_default` | the unnamed pool, exactly | sentinel exists precisely to avoid colliding with a collection literally named `default`; `volume.mark` help names it |
| a literal name (`logs`, `media`, `default`, …) | only that exact name | the pool's DISPLAY name in the admin UI is not a shell pattern — see the trap below |

- The admin UI renders the unnamed pool as "default"; the shell does NOT alias it.
  `-collection=default` on this cluster matches nothing and exits 0 — a silent no-op
  (`ec decode volumes: []`). Target the pool with `-collection=""` or `-collection=_default`.
- `-volumeId` scoping is collection-free: name the volume and drop the collection flag rather
  than risk a mismatch. A wrong collection next to `-volumeId` narrows the set to zero and the
  tool then "succeeds" reporting nothing — a fsck run against the wrong pool scans nothing and
  tells you nothing, indistinguishable from a clean bill of health.
- The same discipline covers `volume.fsck`, `volume.vacuum`, `volume.mark`: literal names for
  named pools, `_default` for the unnamed one (runbook Phases 1–3 demonstrate).

## Simulate-first discipline

- `volume.check.disk` and `volume.fsck` WITHOUT `-apply` are read-only diagnostics — run the
  simulation first, read the printed verdicts, then branch to the matching repair. The verdict
  texts and all branches: runbook Phase 3 step 2 (link, not restated).
- Mutation verbs change cluster state the moment they run; anything scoped by `-collection`
  should get a read-only `volume.list` / `volume.list -readonly` pre-check in the same block,
  so a paste reflects live truth instead of a stale note.

## Long-run realities

- check.disk / fsck take HOURS on 13–24k-entry indexes: run in tmux/screen with the tee log.
- fsck reverse mode (`-findMissingChunksInFiler`) is silent by design: progress lines are
  `-v`-gated and the FIRST finding can only print after the volume-side set is collected AND
  the entire filer has been walked (tens of millions of chunk references here). A quiet fsck
  is WORKING, not hung (runbook Phase 4 note).
- Cheap probes while waiting: `volume.list -readonly` (mark set), `volume.list` per-volume
  stats fields `file_count` / `deleted_file` (backlog drain), master `/vol/status` for the
  same fields over HTTP (mcp-server-spec.md §3).

## Paste-block conventions

- One command per line in heredoc bodies — output stays attributable per command, and each
  mutation keeps its own line inside the `lock`…`unlock` bracket. (Short read-only one-shots
  like `echo 'lock; volume.list; unlock' | weed shell …` are the runbook's single-line
  alternate for quick checks.)
- The quoted heredoc body reaches `weed shell` VERBATIM — no shell expansion happens there,
  so bash idioms in the body (brace shorthand, `$VAR`, globs) do not expand: spell every node
  FQDN and volume id out on every line, even when lines repeat.
- Source-check any flag against the RUNNING version before relying on it: `help <cmd>` inside
  `weed shell` (or `<cmd> -h`) prints the deployed verb set and flags. Flags churn across
  versions — at 4.50 the apply switch is `-apply` and `-force` survives only as a deprecated
  alias on the `volume.deleteEmpty` family.
- Prefer idempotent verbs in blocks that may be pasted twice (`volume.mark … -writable` is),
  and put read-only pre-checks first so a re-paste confirms rather than assumes.
- Keep the `lock`…`unlock` bracket symmetric; if a block might abort midway (broken pipe),
  pair it with the stuck-lock recovery above.
