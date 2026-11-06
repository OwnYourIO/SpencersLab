# APPLY-INSTRUCTIONS — porting the C06 staging to CuratedForest.com (C07)

This folder is staging/transport: the live checkout at
`/home/coder/CuratedForest.com` is dirty and pre-Forgejo and stays
untouched. C07 applies this staging to the Forgejo clone —
`git.spencerslab.com/CuratedForest/CuratedForest.com` — as a branch + PR
(the site repo carries the same rules as this lab repo: `main` advances
only via a PR the user merges).

## Copy list (the entire staging set)

Copy exactly three files, into the repo root:

| Staged path                    | Repo destination               |
|--------------------------------|--------------------------------|
| `.forgejo/workflows/deploy.yml` | `.forgejo/workflows/deploy.yml` |
| `.forgejo/workflows/sync.yml`   | `.forgejo/workflows/sync.yml`   |
| `sync-albums.yaml`              | repo root, beside `hugo.yaml`   |

Nothing else ships: no archetype, no section `_index.md`, no `hugo.yaml`
edit of any kind (the N3 final fold — albums map into existing pages
only; the sync never creates pages or sections). The `tests/` subfolder
of this staging is the ticket's validation gate, not site content — it
is not copied.

## Precondition: LFS objects must have migrated with the repo

`content/plants/aeroponics/**` is LFS-tracked (`.gitattributes`), and the
hugo build `.Resize`s those originals. The Forgejo migration must carry
the LFS objects, not just the pointers:

```
git lfs ls-files | wc -l     # expect the full inventory (~74 files today)
git lfs fetch --all && git lfs pull
```

Without the objects the build "succeeds" on pointer-sized images
(~130 bytes each) — the failure mode the live repo's AGENTS.md already
documents — and the galleries would publish broken thumbnails to
Netlify.

## Branch + PR recipe

```
git fetch origin main
git checkout -b cf-11-site-artifacts origin/main
# copy the three staged files into the working tree (table above)
git add .forgejo/workflows/ sync-albums.yaml
git commit -m "cf-11: site workflows (deploy + daily sync) and the album allowlist"
git push -u origin cf-11-site-artifacts
```

Open the PR against `main` on Forgejo. The PR event fires
`deploy.yml`'s farm leg — the curatedforest.farm preview doubles as the
render proof of this staging. Do not merge: landing on `main` is the
user's decision alone.

## Secrets before the first live run

The repo secrets `IMMICH_API_KEY`, `NETLIFY_AUTH_TOKEN`,
`NETLIFY_SITE_ID`, `NETLIFY_SITE_ID_FARM` and `FORGEJO_SYNC_PAT` are
seeded ONE-SHOT, manually, into the CuratedForest.com repo settings on
Forgejo, from the hugo-build-* Bitwarden items (owner action; plan user
action 8). The workflows reference the secrets by name only. Until that
seed is in place the first workflow run fails loud at its first secret
use (rotation = manual re-seed).

## Verification (scratch render — never the live checkout)

From the SpencersLab repo root, with the site's exact hugo pin on PATH
(0.151.0+extended per `netlify.toml`):

```
export PATH="$HOME/.local/bin:$PATH"
python3 -m pytest .agents/plans/2026/2026-10-cf-11-feat-immich-hugo-pipeline/site-staging/tests/ -v
```

The render gate (t5) copies the site to `/tmp/opencode` (rsync,
excluding `.git/lfs/` and `.agents/worktrees/`), applies this staging to
the copy, hand-builds the fixture sync states, and renders. The
full-repo render needs the hugo modules: without a `go` binary/network
that leg reports SKIP-BLOCKED (by design, never a fake pass); an
environment with `go` and a warm module cache runs it green.
