# RESEARCH — CuratedForest.com repo survey & the Immich→this-repo seam

Ticket: WeKan AI-Dev card #11 (`cf-11-feat-immich-hugo-pipeline`) · **Round 3 (repo survey)** 2026-10-31 · standalone companion to `RESEARCH.md` (rounds 1–2; settled constraints unchanged: Immich v3.x, derivatives-not-originals, albums-as-pages + opt-in tags, hourly/daily freshness, home cluster, Netlify).
Method: STORM, compressed repo-forensics shape — 4 perspectives (Hugo template architect · GitHub/Netlify delivery engineer · Immich export engineer · site owner/editor), each grounded in read-this-round evidence: the repo itself (read-only; paths cited `[n]` → Sources), image-dimension forensics, git/LFS metadata, plus fresh web verification of every load-bearing external claim (Hugo image-cache docs, Netlify LFS mechanics, GitHub LFS metered billing, Immich preview defaults, immich-go naming). Intermediates: `/tmp/opencode/storm-runs/cf-11-curatedforest-repo/`. **Two round-2 numbers are corrected by this round — see C2 in Contradictions.**

## TLDR (card-postable)

**What the repo does today:** CuratedForest.com is a Hugo 0.151.0 (pinned) docs site on the `onweru/compose` theme (Hugo Modules), deployed by **Netlify git builds only** — two sites: prod `curatedforest.com` (plain `hugo`) and drafts `curatedforest.farm` (`$HUGO_BUILD_FLAGS=-D`) [1][3][7]. Photos live as **originals committed via Git LFS** (74 files, **406.8 MB**: phone JPEGs 4080×3072 at 4.4–7.3 MB, PNGs up to 20 MB) inside **page bundles** under `content/plants/aeroponics/` [4][10][11][12][13]. Galleries render through a **bespoke, dependency-free `gallery` shortcode** (custom rewrite of the theme's): page-resource glob + Name-sort, Hugo `.Resize` 320px thumbs / 1600px lightbox, CSS-only `:target` lightbox [8][14][15]. There is **no automation of any kind** (no CI, one manual icon script) — but two files in `current-grows` are already **Immich-preview-like derivatives** (`YYYYMMDD-HHMMSS_<id>_<original>.jpg`, ~1.4k px long edge, 0.5–0.8 MB) from a past manual export, sitting next to 8 raw originals [10][12][23].

**Recommended seam:** one Immich **album → one page bundle** (`index.md` + preview derivatives) fed by the home-cluster sync job, emitted **`draft: true` + `author_reviewed: false`** so machine-generated pages flow through the repo's EXISTING curation gate (farm deploy → drafts/author-review rollups → human flips flags → prod) [7][8][10]. Filenames `{YYYYMMDD}-{HHMMSS}_{checksum8}_{safeOriginal}.jpg` (chronologically Name-sortable = the gallery's sort contract; checksum = idempotent re-exports) [8][29]. **Zero template changes required**; the only repo-side edits are additive (a `photos` docSection, an album archetype, optionally `caches.images.dir`).

**Keep-vs-alternatives verdict:** **Keep the committed-bundle shape and automate it (option A)** — it fits this repo's git-driven two-site flow, its PR-based human-in-the-loop, and its hand-built gallery ethos; derivatives-only (replacing today's originals) shrinks LFS ~10× and stays inside GitHub's **newly-verified 10 GiB/mo free LFS bandwidth** at ≤weekly build cadence [21][12]. Round-2's primary rec (in-cluster build + `netlify deploy --prod --no-build`, option C) remains the **scale path** (>~2–3k photos or daily freshness) but costs more here than round 2 assumed: it must reproduce the farm-drafts deploy and `enableGitInfo` git-history coupling, or run alongside git builds as a second deploy writer [1][3][7][27]. Option B (R2 bucket + Netlify Image CDN `remote_images`) is the middle road if image bytes must leave git without in-cluster builds [26]. Option D (build-time GetRemote/content-adapters on Netlify) stays rejected — Netlify build bots can't sanely reach the lab edge [28][29].

## Repo survey (evidence-backed)

### Identity & stack
- Hugo **0.151.0 pinned** in `netlify.toml:6` (`HUGO_VERSION`); build `command = "hugo -b $URL $HUGO_BUILD_FLAGS"` (`netlify.toml:3`), `publish = "public"`; extended edition required (SASS) [3][6].
- Theme `github.com/onweru/compose` as a **Hugo Module** (pinned `v0.0.0-20250714145138-0419b4c89f33` in `go.sum`), plus `lkhrs/hugo-dark-visitors v1.0.0`; PaperMod present in `go.mod` but commented out in `hugo.yaml:12` [1][2]. `go.mod` module path is inherited (`…/SpencersLab/sites/help`) and deliberately left alone [2][6].
- Single `hugo.yaml` at root; dark-mode-only enforced in 3 coordinated places; Fuse.js search requires `JSON` in `outputs.home` (`hugo.yaml:19-23`) [1][7].
- `enableGitInfo: true` (`hugo.yaml:6`) — `.Lastmod`/`.GitInfo` come from git history and feed the `drafts`/`recent`/`todos` rollup shortcodes under `content/search/` [1][7]. **Any delivery option that builds without git history, or commits machine-touches, moves these pages.**
- Layouts use the post-0.146 directory names (`_shortcodes/`, `_partials/`, `_markup/`) — consistent with the 0.151 pin [8][9][15].
- **No local `hugo` binary in agent environments** — verification is Netlify-build-based per `AGENTS.md` ("Verification" section) [7].

### Deployment flow
- **Netlify git builds only.** No `.github/` (zero workflows), no CLI-deploy config, no build hooks, no `[build.cache]` in `netlify.toml` [3][13].
- **Two sites from one repo**: prod `curatedforest.com` (plain `hugo`, drafts excluded) and `curatedforest.farm` (drafts enabled — `$HUGO_BUILD_FLAGS` set per-site in the Netlify UI; documented in `AGENTS.md` "Draft deployment (curatedforest.farm)") [3][7].
- **Git LFS fetch must be enabled on the Netlify sites** or images publish as ~130-byte pointers — `AGENTS.md` diagnostics row "Images publish as tiny text files on Netlify" shows this failure mode was actually hit; Netlify's mechanism is `GIT_LFS_ENABLED=true` for git-host LFS [7][22].

### Where the photo bytes live TODAY
- **All photo content is in `content/plants/aeroponics/` page bundles**, Git-LFS-tracked by `.gitattributes:1-6` (jpg/jpeg/png/gif/webp/svg) [4]:
  - `current-grows/` — **branch bundle** (`_index.md` + 10 sibling images): 8 raw phone originals (4080×3072, 4.4–7.3 MB, `IMG_*` names, shot dates 2025-04→2026-02) **+ 2 downscaled derivatives** (998×1326 @ 0.5 MB, 1068×1418 @ 0.78 MB) named `20250921-120050_18179443841_IMG_20250921_115827_912.jpg` / `20251201-172814_14244004796_IMG_20251130_100709_792.jpg` [10][12][13].
  - `past-designs/` — 21 JPEGs at its root (branch bundle, camera/signal originals 3120×4160, incl. `IMG_20190606_162948+1.jpg` dedup-suffix naming) + leaf bundles `grow-environments/` (17 PNGs, **9.8–20 MB each**), `water-supplies/` (5 PNGs 10.8–13.6 MB), `user-interfaces/` (3 screenshot PNGs 0.2–0.4 MB) [11][12].
  - `static/` holds only branding (logo/favicons/icons/backgrounds, 7.6 MB) — **not** photo content [13].
- Totals: **74 LFS files, 406.8 MB**; `.git/lfs` = 471 MB on disk while git packs are just 3.25 MiB; working tree 3.8 GB (mostly `.agents/worktrees/`, see hygiene) [13].
- Forensics: the two `current-grows` derivatives have a ~1.3–1.4k px long edge — **consistent with Immich preview derivatives (1440p default, jpeg/webp)** vs the 4080×3072 originals beside them; their `YYYYMMDD-HHMMSS_<numeric>_<originalName>` naming and the older `+1` dedup suffixes match the immich-go archive-export family's collision-safe renaming (producer unconfirmed → Open question 1) [10][12][23][24][25].
- All images landed via manual commits: `48529d6 "Add old pictures."` (current-grows set) and earlier reorg commits; there is **no sync script** — `scripts/` contains only `split_icons.py` (manual Pillow icon prep) [13][17].

### The gallery system (the consumption contract)
- `layouts/_shortcodes/gallery.html` is a **complete custom rewrite** of compose's trivial positional-args gallery — resource-driven, heavily commented, no JS lightbox libraries [8][15]. Contract an Immich feed must satisfy:
  1. Images must be **page resources** of the bundle containing the `{{< gallery >}}` call (`.Resources.Match <glob>` or `.ByType "image"`) [8:44-49].
  2. Ordering is **`sort` by resource `Name`** asc/desc → filenames must encode the desired order (chronology today) [8:50-54].
  3. Processing is `$r.Resize "320x"` (thumb) + `$r.Resize "1600x"` (lightbox, Hugo-capped at original width) → **sources ≤1600px make the full-size resize a near-passthrough** [8:60,68][19].
  4. Alt text is the **filename** (`$r.Name`) — machine filenames surface as alt text; better alt needs a (small) shortcode edit [8:63,79].
- CSS-only `:target` lightbox (grid + overlay CSS at `assets/sass/_custom.sass:316-410`); one JS assist relocates `.lightbox` nodes to `<body>` (`assets/js/custom.js` `relocateLightboxes`) because `.content`'s backdrop-filter would break fixed positioning [8][14].
- Usage (5 pages, all under aeroponics): `current-grows/_index.md:15` (`sort="desc"`, no glob — reverse-chronological firehose of the bundle), `past-designs/_index.md:13` (`match="*.[jJ][pP]*"` — a case-sensitivity workaround), `grow-environments/index.md:27,38,53,62,69,78` (six **semantic-prefix globs** `v6-*`…`v2-*`, `2017-pfc-*` — hand-renamed files power multi-gallery-per-page), `water-supplies/index.md:26,42`, `user-interfaces/index.md:20` [10][11].
- `layouts/_default/_markup/render-image.html` resolves plain-markdown images page-bundle → section → global assets, passes remote URLs through, warns on unresolved; exactly **one** content file uses inline images (`content/tech/kubernetes/k3s-tumbleweed.md:119`) [9][13].
- Search: compose's `layouts/index.json` indexes every non-search page (title/`.Plain`/link/section) → **new album pages enter the Fuse corpus with zero changes** [15].

### Content organization & authoring conventions
- Sections `tech/`, `plants/`, `software/`, `about/`, `search/`; docs layout via `params.docSections` (`hugo.yaml:75-84`, leading `""` load-bearing) [1]. Every section dir needs an `_index.md`; page bundles preferred for pages with own images; `weight` orders the sidebar [6][7].
- Front-matter convention on every page: `title`, `weight`, `type: docs`, `draft`, `todo:`, **`author_reviewed`/`editor_reviewed`** booleans; `content/search/` rollup pages (`drafts`, `todo`, `recent`, `author-review`, `editor-review`) are generated by bespoke shortcodes and visible on the farm deploy — a complete, home-grown **review pipeline** [7][13].
- Authoring in Obsidian (gitignored workspace files); wikilinks banned in favor of `{{< ref >}}` [5][7].
- The Immich doc page exists but is a draft stub (`content/software/productivity/immich/_index.md`, restore-from-backup notes referencing `pg-immich-rw` — confirming Immich runs on the lab's CloudNativePG stack) [16].

### Repo hygiene signals
- **10 git worktrees** registered under `.agents/worktrees/` (agent sessions), each materializing LFS content + built `resources/_gen` images → `.agents` = **3.4 GB** of the 3.8 GB tree [5][13].
- `main` is **2 commits ahead of origin** with uncommitted WIP (hugo.yaml `ignoreFiles` addition + label-based-features pages) — active human work in flight; the survey touched nothing [13].
- Repo age ~1 year (2025-10-09 → 2026-09-27), 160 commits [13].
- `resources/_gen/` gitignored (main tree holds only SASS artifacts); worktree `_gen` dirs contain the `*_hu_<hash>.jpg` thumb+full pairs, proving the per-build double-resize of every gallery image [5][13].

### What the user has done, honestly assessed
The user hand-built a genuinely good, self-contained gallery system (custom shortcode + CSS-only lightbox + review-flag curation machinery) and hand-populated it with **original-resolution photos committed through LFS** — including at least one manual Immich-derived export already mixed into `current-grows`. What works: presentation is dependency-free and fast to render (≤1600px display), curation/review flow is first-class, LFS keeps git packs tiny (3.25 MiB), and Netlify git builds keep delivery boring. What aches: the committed bytes are 4–13× larger than anything displayed; every build re-downloads ~407 MB of LFS (×2 sites) and **re-decodes every original** (no persisted image cache); gallery grouping in `past-designs` depends on hand-renamed semantic prefixes; and fresh photos reach the site only through a manual export→rename→commit→push ritual.

## Seam definition (Immich → THIS repo)

**Placement.** New top-level section `content/photos/<album-slug>/` (leaf bundle: `index.md` + derivatives), added to `params.docSections` (`hugo.yaml:75`) [1][7]. Rationale: keeps machine-synced bundles away from hand-curated `plants/aeroponics` pages whose **semantic-prefix globs must stay hand-authored** [11]; gives albums their own sidebar tier. (Alternative: nest under the related doc section per album — fine, but mixes sync-managed and hand-managed bundles in one tree.) `current-grows`-style "latest photos" pages can stay where they are and be fed by the same job (append derivatives into the existing branch bundle) [10].

**Bundle shape (consumed unchanged by `gallery.html`):**

```
content/photos/<album-slug>/
├── index.md          # front matter below; body = album description + {{< gallery sort="desc" >}}
├── 20250921-120050_a1b2c3d4_IMG_2025….jpg   # preview derivative, checksum-suffixed
└── …
```

- One album per bundle → `{{< gallery >}}` with **no glob** (`.ByType "image"` picks up exactly the album) [8:47-48].
- **Naming:** `{YYYYMMDD}-{HHMMSS}_{checksum8}_{safeOriginalName}.jpg` — capture date+time from asset metadata keeps `sort` chronological (asc or desc) [8:50-54]; `checksum8` (from `AssetResponseDto.checksum`) makes re-exports idempotent and digest-stable [29]; lowercase `.jpg` avoids the `*.[jJ][pP]*` pain [11]. Pull `size=preview` (1440p-class JPEG — EXIF/GPS-stripped by construction; matches the two derivatives already in the repo; `full=1600` resize becomes near-passthrough) [12][19][23][29].
- **Front matter** (per repo conventions [7]): `title` = album name, `date` = album `startDate`, `weight` = stable order (e.g. by startDate), `type: docs`, **`draft: true` + `author_reviewed: false` + `editor_reviewed: false`** → the album appears on `curatedforest.farm` and in the `drafts`/`author-review` rollups; the owner flips `draft`/flags to publish to prod. Album `description` → page body. This **reuses the existing human-review machinery as the pipeline's quality gate** — no new approval surface.
- **Curation model:** albums-as-pages + opt-in tag decides WHICH albums sync (`POST /search/metadata {albumIds|tagIds, type:IMAGE, updatedAfter}`; album metadata from `GET /albums` — name/description/startDate/assetCount/lastModifiedAssetTimestamp for cheap change probes) [29].
- **Sync job output = a git branch + PR** (matches the card's `Human in the Loop: PR` checklist and the repo's hard rule that main advances only via user-merged PRs) [7][13]. Hourly/daily cron probes `lastModifiedAssetTimestamp`; a run with changes commits new/updated derivatives + `_index` metadata refresh and opens/updates one PR per batch.

**Change-surface table (everything the seam touches):**

| Surface | File | Change | Kind |
|---|---|---|---|
| Sidebar/docs layout | `hugo.yaml:75` `params.docSections` | add `photos` | additive, 1 line |
| Image build cache (recommended under EVERY option) | `hugo.yaml` new `caches: images: dir: ':cacheDir/images'` | persist processed-image cache across Netlify builds | additive, 2 lines [19][20] |
| Album page template | `archetypes/` new `album.md` (front-matter contract above) | new file | additive [13] |
| Gallery shortcode | `layouts/_shortcodes/gallery.html` | **none required**; optional: alt-text from a sidecar/front-matter map instead of filename | optional edit [8:63] |
| Render hooks | `layouts/_default/_markup/render-image.html` | none (inline images in album bodies already resolve from the bundle) | none [9] |
| LFS filters | `.gitattributes` | none for JPEG previews; add `*.avif` only if avif derivatives ever pulled | conditional [4] |
| Netlify config | `netlify.toml` | none (git builds stay); `remote_images` block only under option B | conditional [3][26] |
| Modules | `go.mod`/`go.sum` | none (no new module needed) | none [2] |
| Sync job (SpencersLab side) | `containers/<sync>` + `charts/immich-hugo-sync` (cronjob) + ExternalSecret/Bitwarden (Immich API key least-privilege: `asset.read`/`asset.view`/`album.read`/`tag.read`; GitHub deploy key with PR-only rights) | new, in the LAB repo — not this repo | new [29][7-hard-rules] |
| Search | theme `layouts/index.json` | none — album pages enter the Fuse corpus automatically | none [15] |

## What aches at scale (hundreds → low thousands of synced photos)

1. **LFS bandwidth** (the binding constraint): every Netlify build downloads all LFS objects; **~407 MB today × 2 sites per push**. GitHub LFS free tier is now **10 GiB storage + 10 GiB bandwidth/month** (metered billing replaced data packs; default budget **$0 → overage BLOCKS LFS until the 1st**; metered $0.0875/GiB) [21]. Daily builds ≈ 24 GB/mo → blocked-or-billed; weekly ≈ 3.3 GB/mo → fits free. Derivatives-only shrinks the payload ~10× (1,000 previews ≈ 200–500 MB → daily ≈ 12–30 GB/mo still tight; weekly comfortably free) [12][21][30].
2. **Build time**: no image-cache persistence today → each build decodes every original (incl. 10–20 MB PNGs) twice (320 + 1600) [1][3][19]. At 1,000 photos that's minutes-to-tens-of-minutes per build × 2 sites. `caches.images.dir` + derivatives-as-sources fixes most of it [19][20].
3. **Repo growth/churn**: hash-stable names mean unchanged photos never create new blobs, but every edited/re-exported photo adds one; history grows monotonically; GitHub recommends ≤10 GB `.git` and generated binaries outside git [30]. Derivatives-only at settled scale stays far inside limits for years — originals-in-LFS (today's shape) would not.
4. **Worktree sprawl**: agent worktrees each materialize LFS + `_gen` (3.4 GB already at 10 worktrees) — more/ larger images multiply this per worktree [13].
5. **Manual authoring**: the export→rename→commit ritual is the thing the pipeline removes; the `past-designs` semantic-glob pages must stay manual (machine can't invent `v6-*` groupings) [11].

## Options for THIS repo

### A — Keep the committed-bundle shape, auto-populate it (RECOMMENDED phase 1)
Sync job (home-cluster CronJob per rounds 1–2 [29]) pulls preview derivatives → writes album bundles → opens a PR → user merges → **existing Netlify git builds** (both sites) take over. Optionally replace today's committed originals with derivatives in the same effort (one-time ~10× LFS shrink).
- Change surface: smallest of all options (table above); zero template edits; curation gate = the repo's own draft/review flow; PR gate = the card's `Human in the Loop: PR`.
- Cost/risk: LFS bandwidth caps effective build cadence (~weekly free-tier; set a small metered budget for daily) [21]; `.git` grows slowly and monotonically [30]; Netlify clones track history size.
- Effort: **Low–Medium** (sync container + git-push/PR glue; no Netlify-side changes).

### B — Externalize bytes: R2/public bucket + Netlify Image CDN `remote_images`
Derivatives sync to a bucket (R2 recommended: zero egress, custom domain + CF CDN [26]); git holds only `index.md` + a per-album manifest; `gallery.html` gains a URL-mode (or pages emit `/.netlify/images?url=<bucket>/…` links) so the CDN resizes/negotiates avif-webp per browser [26].
- Change surface: `gallery.html` edit (URL mode), `netlify.toml` `remote_images` regex, bucket ops + public hostname decision.
- Cost/risk: images leave git entirely (fast clones, GitHub-guidance-clean [30]); but LFS-free still needs the bucket; two storage systems during migration; Image CDN transform credits.
- Effort: **Medium**. Best when photo count >~2–3k or bandwidth becomes annoying, without running builds in-cluster.

### C — In-cluster build + `netlify deploy --prod --no-build` (round-2 primary rec)
CronJob: export → hugo build in-cluster → digest-diffed CLI deploy; images never touch git [27].
- **This repo raises C's price** (round 2 didn't know): it must reproduce **two deploys** (prod + farm `-D`) from one job, and `enableGitInfo` means the in-cluster builder needs real git history (clone + fetch depth) or `recent`/`drafts`/`todo`/Lastmod behavior changes [1][3][7]. Keeping Netlify git builds alongside (for content PRs/previews) means **two deploy writers** per site — workable (digest deploys, last-writer-wins) but an operational seam to design deliberately [27].
- Effort: **High** (container with hugo+netlify-cli+git, NETLIFY_AUTH_TOKEN + site IDs via ExternalSecret, dual-deploy logic, state on PVC). Payoff: zero git/LFS photo weight, hourly freshness, bandwidth = changed files only.
- Verdict: the **scale path**, not phase 1 for this repo.

### D — Build-time pull on Netlify (content adapters / `resources.GetRemote`) — REJECTED
Netlify build bots would have to reach the Immich API through the lab's zerotrust edge (geoblock/SSO; availability coupling) — the round-2 (c) analysis applies unchanged; Hugo-side mechanics (adapters since v0.126, GetRemote headers/caching) are fine at 0.151 but the network posture kills it [28][29]. Kept here so the option space is complete.

### Comparison

| Dimension | A keep+automate | B bucket+ImageCDN | C in-cluster+CLI |
|---|---|---|---|
| Template changes | none (optional alt-text) | gallery URL-mode | none |
| Netlify config changes | none | `remote_images` | none (git builds optionally kept) |
| Photos in git | yes (LFS, derivatives-only) | no (manifests only) | no |
| Farm-drafts deploy | free (existing) | free (existing) | must build 2nd variant in-cluster |
| `enableGitInfo`/Lastmod | native | native | needs git history in builder |
| Human gate | PR + draft/review flags (existing) | PR + flags | PR of content only; photos bypass review unless job emits drafts |
| Build cadence ceiling | LFS bandwidth (~weekly free; metered $ tiny for daily) | unlimited (bucket egress free on R2) | unlimited (digest diffs) |
| Scale ceiling | low-thousands OK; 10k+ strains clones | high | high |
| Ops burden | cron + PR glue | + bucket, CDN allowlist | + dual-deploy, tokens, PVC state |
| Effort | Low–Med | Med | High |
| Round-2 alignment | fallback (a) — **promoted by repo evidence** | runner-up (b) | primary (A+d) — **demoted to scale path by repo evidence** |

**Verdict:** **A now** (it *is* "keep what works, minus the manual ritual and minus the originals"), **B or C when scale or freshness demands** — C if in-cluster simplicity wins, B if git-build continuity wins. All three share the same sync/export core, so A→B/C migration reuses the job.

## Contradictions & weighing

1. **C1 — Round-2 delivery rec vs repo reality.** Round 2 recommended images-never-touch-git (C) without knowing the site is a two-deploy git-driven flow with `enableGitInfo` coupling and a draft-farm review culture [1][3][7]. Weighing: C's benefits (bandwidth, freshness) are real but its repo-side costs were invisible in rounds 1–2; A captures 80% of the value (derivatives-only, automation, review gate) at 20% of the cost **at the settled scale**. Resolution: A phase 1, C as the documented scale path.
2. **C2 — LFS verdict correction.** Round 2 said "avoid LFS: free = 1 GiB/1 GiB, daily builds exhaust it instantly" [RESEARCH.md 11]. Fresh verification: GitHub moved LFS to **metered billing with 10 GiB/10 GiB included** (Free/Pro; 250 GiB Team), data packs removed, default budget $0 blocks overage until reset [21]. The avoid-verdict **weakens for derivatives at ≤weekly cadence** (fits free) but **holds for originals or daily cadence** (today's 407 MB × 2 sites × daily ≈ 24 GB/mo → blocked-or-billed) — and GitHub's "generated binaries outside git" guidance is unchanged [30]. Net: A is viable precisely because the pipeline ships derivatives, not originals.
3. **C3 — Originals committed vs ≤1600px display.** The repo pays 4–20 MB/file for pixels it never shows (gallery caps at 1600px) [8][12]. Resolution: derivatives-only replacement is a pure win (10× smaller LFS, faster decodes, same visual output); originals stay safe in Immich (their actual job).
4. **C4 — Filename contract clash.** Round 2 suggested `{assetId}-{checksum8}` names [RESEARCH.md 186]; this repo's gallery sorts by `Name` → assetId-first names destroy chronological ordering [8:50-54]. Resolution: date-prefixed + checksum-infixed naming (also matches the shape of the two derivatives already in `current-grows` [10]).
5. **Agreements (all four perspectives):** page bundles + existing gallery shortcode are the right consumption surface; `draft:true`→farm→review-flags is the right human gate; album-per-bundle needs no template rewrite; `caches.images.dir` is a free win under every option [19][20].
6. **Blind spot found:** rounds 1–2 never accounted for the **second (farm/drafts) deploy** nor the **enableGitInfo** coupling — both materially change the delivery calculus (C1).

## Immediate wins (option-independent, this repo only)

1. `hugo.yaml`: add `caches: images: dir: ':cacheDir/images'` — Hugo's own Netlify guide's step 2; persists processed-image cache across Netlify builds [19][20].
2. Replace committed originals with ≤1440px JPEG derivatives (one-time; ~407 MB → ~30–60 MB LFS; gallery output visually unchanged since display caps at 1600px) [8][12][23].
3. Prune stale `.agents/worktrees/` (9 old trees ≈ 3.4 GB) — human decision, flagged not executed [13].
4. Note for docs hygiene: README/AGENTS claim `layouts/index.json` is a repo file; it never existed in git history — the Fuse corpus comes from the **theme's** `layouts/index.json` [6][7][13][15].

## Implications for the plan

1. Phase 1 = option A: `containers/immich-hugo-sync` (thin API glue — **not** immich-go: its archive naming is unstable across versions, v0.28 vs v0.30+ `~1`/sidecar regression [24][25]) + `charts/` cronjob on home cluster; output = branch + PR against `CuratedForest/CuratedForest.com`; secrets = Immich API key (least privilege) + GitHub deploy key (PR-scoped), ExternalSecret+Bitwarden [7][29].
2. Repo-side PR (tiny): `docSections += photos`, `caches.images.dir`, `archetypes/album.md`, optional gallery alt-text enhancement.
3. Curation contract: albums export as `draft: true`; publishing stays human (flip flags) — matches card's `Human in the Loop: PR` and the repo's review-flag culture [7].
4. Cadence: daily sync probe is fine; **merge/build cadence** is what spends LFS bandwidth — weekly merges fit free tier, or set a small GitHub LFS budget for daily [21].
5. Keep C (in-cluster build + dual CLI deploy) and B (R2 + remote_images) as documented phase-2 paths with the trigger conditions above; the sync/export core is shared [26][27].
6. `past-designs`-style semantic-glob pages stay hand-authored; the pipeline must never rewrite those bundles [11].

## Open questions (no-questions rule: best guesses + impact)

1. **Producer of the two existing derivative files?** Best guess: a manual immich-go `archive from-immich` run (naming family + `+1` dedup suffixes elsewhere) [10][24][25]. Impact: low — but confirming tells us whether the user already likes immich-go's output shape, and which Immich version/settings produced 1326/1418px (vs default 1440p) [23].
2. **GitHub LFS billing state for the CuratedForest org** (payment method? budget? current monthly bandwidth use?) Best guess: free tier, $0 budget, low build frequency (which is why it hasn't bitten) [21]. Impact: **high** — decides whether A can run daily or must stay ≤weekly / carry a metered budget.
3. **Netlify plan/credits + are both sites on git builds today?** Best guess: yes for both (per AGENTS.md) [7]. Impact: medium — option C's dual-deploy cost and Image CDN availability under B depend on plan.
4. **Should synced albums live under `content/photos/` or nest under related doc sections (e.g. `plants/`)?** Best guess: `content/photos/` (keeps sync-managed bundles isolated from hand-managed globs) [11]. Impact: medium — sidebar IA + weights; trivially changeable later via aliases.
5. **Do the 20 MB PNGs in `grow-environments/`/`water-supplies/` have Immich counterparts** (i.e. can derivatives replace them), or are they local-only exports? Best guess: most are in Immich (the whole library migrated) [16]. Impact: medium — decides whether win #2 covers all 407 MB or leaves a PNG tail.
6. **Farm-site build frequency** — does `curatedforest.farm` rebuild on every push (doubling LFS draw)? Best guess: yes, same repo webhook [7]. Impact: medium for the bandwidth math (×2 already assumed).
7. **Video (phase 2)** — unchanged default: link out (IPP/folio), no video bytes in this repo [RESEARCH.md R2.2]. Impact: none on phase 1.

## Adjacent (out of scope, noted)

- The repo's `examples`/`all-examples` shortcodes show the same page-resource pattern for non-image resources (`examples.md` via `.Resources.GetMatch` + `.RenderString`) — the sidecar-metadata idea (album JSON as a page resource the gallery reads for captions) has an in-repo precedent [13].
- `ignoreFiles` in `hugo.yaml:50-52` demonstrates the repo's pattern for keeping agent-facing files inside `content/` unpublished — the same mechanism could shield any pipeline state files if they ever live in the content tree [1].
- CuratedForest.com's AGENTS.md hard rules mirror SpencersLab's (never push/merge main; PR-only landing) — the sync job's git identity must respect them (deploy key → branch → PR, never main) [7].

## Reliability notes (self-review, round 3)

- **High confidence (read directly this round):** every repo claim (files cited by path/line) [1-18]; image dimensions/sizes (parsed from file headers this round) [12]; LFS inventory/totals and git metadata (`git lfs ls-files -s`, `count-objects`, `worktree list`) [13]; Hugo image-cache/Netlify guide text [19][20]; immich-go readme + issue #1192 [24][25]; theme module cache contents [15].
- **Medium confidence:** GitHub LFS metered-billing specifics (official docs + community thread read via search results, not the billing UI — account-level state unknown → Open question 2) [21]; Netlify `GIT_LFS_ENABLED` mechanics (support-forum thread, consistent with the repo's own AGENTS.md diagnostics row) [22][7]; Immich preview default 1440p (docs section via search snippet; matches round-2 full read [23]).
- **Inherited, not re-read:** Netlify Image CDN/`remote_images` [26], CLI digest deploys [27], content adapters [28], Immich v3 API shapes [29], GitHub repo-size guidance [30] — all verified in rounds 1–2 with primary sources; nothing this round contradicts them except the LFS quota figures (C2).
- **Weakest claim this round:** attributing the two derivative files to an Immich export (forensic: dimensions + naming shape; no tool receipt in repo) — flagged as Open question 1, and no recommendation depends on the answer.
- **Perspective balance:** the delivery engineer's lens drove the verdict shift (C1/C2); the template architect confirmed the seam is template-free; the owner lens supplied the draft/review gate design. No perspective was consulted on Netlify account internals — that's the main residual unknown (Open questions 2–3).

## Sources

Internal evidence (repo paths — read this round; repo is `/home/coder/CuratedForest.com`):
[1] `hugo.yaml` (theme imports 7-13, outputs 19-23, enableGitInfo 6, docSections 75-84, ignoreFiles 50-52, logo 107-109; no `caches:` key) — read in full.
[2] `go.mod` + `go.sum` (compose `v0.0.0-20250714145138-0419b4c89f33`, dark-visitors `v1.0.0`, PaperMod indirect; module path `…/SpencersLab/sites/help`).
[3] `netlify.toml:1-6` (command `hugo -b $URL $HUGO_BUILD_FLAGS`, publish `public`, `HUGO_VERSION = "0.151.0"`; no cache/context blocks).
[4] `.gitattributes:1-6` (LFS filters jpg/jpeg/png/gif/webp/svg).
[5] `.gitignore` (resources/_gen/, .agents/skills/, .agents/worktrees/, content/.obsidian/*).
[6] `README.md` (stack, LFS-on-Netlify requirement :77, layout claims, gotchas).
[7] `AGENTS.md` (agent layout, hard rules, golden rules, shortcode registry, "Draft deployment (curatedforest.farm)", Netlify deployment section, diagnostics cheat sheet incl. LFS-pointer row; read in full).
[8] `layouts/_shortcodes/gallery.html` (resource contract :40-54, Resize :60/:68, alt=Name :63/:79, lightbox mechanics comment :17-38).
[9] `layouts/_default/_markup/render-image.html` (resolution chain :14-18, remote passthrough :12, warnf :21).
[10] `content/plants/aeroponics/current-grows/` (`_index.md:15` gallery sort desc; folder listing: 8 originals + 2 derivative-named files; stub build pages).
[11] `content/plants/aeroponics/past-designs/` (`_index.md:13` glob; `grow-environments/index.md:27-78` v2–v6+2017-pfc globs; `water-supplies/index.md:26,42`; `user-interfaces/index.md:20`; `IMG_…+1.jpg` dedup names).
[12] Image-dimension forensics — python struct parse of JPEG SOF / PNG IHDR this round: full size/dimension table (originals 4080×3072 & 3120×4160 at 4.4–20 MB; the two derivatives 998×1326 & 1068×1418 at 0.5/0.78 MB).
[13] Git/LFS metadata this round — `git lfs ls-files -s` (74 files, 406.8 MB summed; endpoint github.com/CuratedForest/CuratedForest.com), `git count-objects -vH` (packs 3.25 MiB), `.git/lfs`=471 MB, `git worktree list` (10 trees), `git log` (160 commits since 2025-10-09; images added at `48529d6`/`8fcb624`; main 2 ahead of origin; uncommitted WIP), `layouts/index.json` absent from all history, content md counts per section, single inline-image page.
[14] `assets/sass/_custom.sass:316-410` (gallery grid + lightbox CSS) and `assets/js/custom.js` (`relocateLightboxes` :167-179, `forceDarkMode` :44-49).
[15] compose theme module cache `~/.cache/hugo_cache/modules/github.com/onweru/compose@v0.0.0-20250714145138-0419b4c89f33/` — `layouts/index.json` (Fuse corpus: all non-search pages, title/body/link/section + otherSearchableFields), theme `_shortcodes/gallery.html` + `image.html` (trivial; repo override confirmed by diff).
[16] `content/software/productivity/immich/_index.md` (draft stub; `pg-immich-rw` restore command — Immich on lab CNPG).
[17] `scripts/split_icons.py:1-25` (manual icon/favicon prep, Pillow; the repo's only script).
[18] `.agents/` (plans/, agents/{plan,code,ask,debug,review}.md, .gitignore), `.kilo` symlink, `skills-lock.json` (empty), `CuratedForest.com.code-workspace`, `archetypes/default.md`, `.opencode/` (agents/skills symlinks + plugin/.gitkeep).

Web sources (read this round):
[19] Hugo docs: Image processing — caching in the file-cache dir, CI guidance `[caches.images] dir = ':cacheDir/images'`, `--gc`, "scale down sources before build", HEIC not processable, metadata dropped by transforms — https://gohugo.io/content-management/image-processing/ (fetched 2026-10-31).
[20] Hugo docs: Deploy to Netlify — Step 2 sets `caches.images.dir: :cacheDir/images`; recommended build `hugo build --gc --minify`; HUGO_VERSION pin pattern — https://gohugo.io/host-and-deploy/host-on-netlify/ (fetched 2026-10-31).
[21] GitHub LFS billing (metered): included free = 10 GiB storage + 10 GiB bandwidth/mo (Free/Pro; 250 GiB Team/Ent), data packs removed, default budget $0 → LFS blocked for the month on overage without payment method, rates $0.0875/GiB bandwidth & $0.07/GiB-mo storage — https://docs.github.com/articles/about-billing-for-git-large-file-storage + https://github.com/orgs/community/discussions/61362 + https://github.com/orgs/community/discussions/151710 (search-read 2026-10-31).
[22] Netlify Answers: "LFS files aren't downloaded during build" — git-host LFS needs `GIT_LFS_ENABLED=true` (else pointer files); Large Media is either/or with git-host LFS — https://answers.netlify.com/t/lfs-files-arent-downloaded-during-build/21948 (search-read 2026-10-31).
[23] Immich docs: System Settings — 3 derivatives per asset (thumbhash blurred / small webp thumbnail / large preview jpeg|webp); preview resolution **1440p default**, lowerable to 1080p/720p; quality 1–100 — https://docs.immich.app/administration/system-settings (search-read 2026-10-31).
[24] immich-go README — `archive from-immich --from-server --from-api-key --write-to-folder`; "Immich V3 ready"; v0.32.0 ReplaceAsset removal — https://raw.githubusercontent.com/simulot/immich-go/main/readme.md (fetched 2026-10-31).
[25] immich-go issue #1192 "original file names not restored archive from-immich" — v0.30.0 emits `~1`/`~3` + JSON sidecars vs v0.28.0 original names; open, 4👍 — naming unstable across versions — https://github.com/simulot/immich-go/issues/1192 (fetched 2026-10-31).

Inherited from `RESEARCH.md` rounds 1–2 (verified there with primary sources; renumbered here, not re-read this round):
[26] Netlify Image CDN + `remote_images` allowlist — https://docs.netlify.com/build/image-cdn/overview/ (= RESEARCH.md [81]); Cloudflare R2 public buckets — https://developers.cloudflare.com/r2/buckets/public-buckets/ (= [101]).
[27] Netlify CLI `deploy --prod --no-build` + digest-based uploads — https://cli.netlify.com/commands/deploy/, https://www.netlify.com/knowledge-base/how-to-deploy-a-site-to-netlify/, https://github.com/netlify/cli/issues/5589 (= [83][84][85]).
[28] Hugo content adapters (v0.126+) — https://gohugo.io/content-management/content-adapters/ (= [28]; still listed in the v0.169 docs nav observed in [19]'s fetch).
[29] Immich v3 API shapes — OpenAPI spec v3.4.0-rc.0 + `asset-media.controller.ts` (search/metadata albumIds|tagIds|updatedAfter; thumbnail `size=preview` = Permission.AssetView; album `lastModifiedAssetTimestamp`; `AssetResponseDto.checksum`; least-privilege key asset.read/view + album.read + tag.read) (= RESEARCH.md [1][95][96]).
[30] GitHub repository limits — recommended `.git` ≤10 GB; "store programmatically generated files outside of Git"; directory width ≤3,000 — https://docs.github.com/en/repositories/creating-and-managing-repositories/repository-limits (= [91]).
