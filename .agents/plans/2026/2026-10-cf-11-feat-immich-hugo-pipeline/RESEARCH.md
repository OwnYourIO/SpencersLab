# RESEARCH — Immich → Hugo pipeline: export-to-files vs embed/iframe

Ticket: WeKan AI-Dev card #11 (`cf-11-feat-immich-hugo-pipeline`) · **Round 2 (final)** 2026-10-31 · supersedes round-1 open questions with settled user answers
Method: STORM (6 perspectives × grounded interviews; round 1 = 77 sources; round 2 = Netlify/GitHub/Cloudflare docs, IPP+folio source reads, Immich v3 spec + server-controller verification; 106 sources total, keys `[n]` resolve to the Sources list). Primary sources used wherever possible: canonical Immich OpenAPI spec (v3.4.0-rc.0, fetched from `immich-app/immich@main`), Immich server controller source, IPP/folio source+docs, official Netlify/GitHub/Cloudflare docs, GitHub API health metadata (all pulled 2026-10-31).

## TLDR

- **Settled**: Hugo site on **Netlify**; hundreds–low-thousands of curated photos; albums-as-pages + opt-in tags; **derivatives (preview/fullsize), not originals**; photos only in phase 1; Immich **v3.x**; home cluster owns the pipeline; hourly/daily sync acceptable.
- **Recommended delivery (A+d)**: home-cluster CronJob (bjw-s app-template `controller.type: cronjob`) → pull Immich `size=preview` derivatives via API-key → build Hugo in-cluster → **`netlify deploy --prod --no-build`** — Netlify's digest-based deploy uploads only changed files, skips Netlify builds entirely, and images **never touch git** [83][84][85][47]. The git repo (if kept) holds templates+content only; build hooks cover content-only commits [79].
- **Runner-up (b)**: derivatives to an S3-compatible bucket (**Cloudflare R2**: zero egress, public custom domain behind Cloudflare CDN) + Netlify git builds + **Image CDN `remote_images`** allowlist so `/.netlify/images?url=<bucket>/…` resizes and serves avif/webp per browser [101][81]. Choose this if Netlify-side builds/PR previews of content matter more than pipeline simplicity.
- **Avoid**: git-LFS for derivatives — GitHub free LFS = **1 GiB storage + 1 GiB/month bandwidth**, every build re-fetches, overage disables LFS; Netlify Large Media is deprecated since 2023 [94][93][88]; and hotlinking the lab as primary delivery — the zerotrust edge geoblocks US/CA + SSO-gates subdomains, so anonymous worldwide visitors break, and site availability couples to the home uplink [106][56]. GitHub's own guidance: store generated binaries outside git [91].
- **Bonus simplification**: Netlify Image CDN (`/.netlify/images`) does on-demand resize + avif/webp content negotiation at the CDN [81] → Hugo's image processing (and its unfixed WebP decode-contrast bug [23][24][25]) can be bypassed entirely; templates just emit CDN URLs.
- **B′ companion: viable, recommended as link-out, not iframe-in**: run immich-public-proxy (2.4k★, AGPL, k8s docs) or immich-folio (MIT; CDN mode, webhook cache-invalidation, stale-buffering) on the home cluster behind a dedicated **no-auth public subdomain**; Hugo links out per album. IPP sets no frame-blocking headers by default (config-driven `ipp.responseHeaders` can even allowlist `frame-ancestors` to the Netlify site), so iframing non-password shares works — password shares inside iframes hit the third-party-cookie wall (Safari blocks) [97][98][103][104]. Keep `allowDownload=false` (GPS-in-originals trap [42]).
- **v3 API verified for the chosen selection model** (spec + server source): `GET /albums?isOwned=true` → album pages; `GET /tags` → opt-in tag discovery (hierarchical); `POST /search/metadata {albumIds|tagIds, updatedAfter, type:IMAGE}` → assets; `GET /assets/{id}/thumbnail?size=preview` (Permission.AssetView) → derivatives; hotlink shape `…/api/assets/{id}/thumbnail?size=preview&key={shareKey}` works key-less (`sharedLink:true` routes) [1][95][96].

## Settled constraints (user answers, round 2 — no longer open)

| Question (round 1) | Settled answer | Consequence for the plan |
|---|---|---|
| Hosting | **Netlify** (public CDN, git-backed builds); lab proxy/zerotrust stack also available | Delivery = round-2 analysis below; lab edge usable for B′ companion |
| Scale | Hundreds → low thousands, curated | Git-commit option survives only at the low end; digest-upload or bucket options scale freely |
| Selection | Albums-as-pages + opt-in tags fine; open to whatever the system supports | v3 supports albumIds+tagIds in one search; hierarchical tags exist (realistic conventions enumerated in the v3-verification section) |
| Originals vs derivatives | **Derivatives** (preview/fullsize) | EXIF/GPS stripped by construction [35]; no strip step; no HEIC problem [26] |
| Video | Photos only, phase 1 | No ffmpeg leg; video later via B′ link-out or phase 2 |
| Immich version | **v3.x** | Code against v3 shapes ([2] breaking changes); `size=original` on thumbnail endpoint deprecated [95] |
| Pipeline owner | **home cluster** | CronJob chart in `services/home/prod/`; in-cluster reach to Immich; ExternalSecret+Bitwarden for the API key |
| Freshness | Hourly/daily cron acceptable | Polling is sufficient; v3 Workflows (`AssetTagged`) remain a later spike, not a dependency [1][46] |

Round-1 background (option space, approach A/B anatomy, practitioner scan, automation, tradeoff matrix, licensing, contradictions) is unchanged below; round-2 sections follow the tradeoff matrix.

## The option space

| Class | Shape | Off-the-shelf examples | Fit for "Hugo site" ask |
|---|---|---|---|
| **A — export to files** | Sync job pulls assets → files land in Hugo content tree → Hugo builds static site | immich-go `archive from-immich` [6][7], album-downloader family [9][10][11][12][44][74], DD Photos/ddphotos [66][67][100], immich-static-gallery (Thumbsup, unlicensed, stale) [68] | **Direct fit** — Hugo owns presentation |
| **B — embed/iframe** | Hugo page iframes/links an Immich public share URL | none official; users improvise iframes [54] | Poor UX, unsupported [54] |
| **B′ — runtime proxy-gallery** | Separate web app renders shares/albums, Immich stays private; Hugo links or frames it | immich-public-proxy (2.4k★, AGPL-3.0, v4.1.2 2026-10-23) [56][57], immich-folio (MIT, v0.21.0, pushed 2026-10-31) [69][99], 11notes/immich-share-proxy [58], immich-event-gallery [70] | Good for "live gallery as its own app"; Hugo links out — companion, not the pipeline |

## Approach A — export-to-files, end to end

### A1. Selection (tags/albums) — API is fully sufficient
From the canonical OpenAPI spec (v3.4.0-rc.0) [1]:
- `POST /search/metadata` accepts `albumIds[]`, `tagIds[]`, `updatedAfter`/`updatedBefore`, `checksum`, `withExif`, `type` (IMAGE/VIDEO), paging/order — one query covers "everything in album X or tag Y, changed since T". v3 returns `SearchResponseDto {albums, assets}` [1].
- `GET /albums` / `GET /albums/{id}`: since v3 the album response no longer embeds assets (use the search endpoint) but carries `assetCount` + `lastModifiedAssetTimestamp` — a cheap per-album "did anything change?" probe; `GET /albums` v3 params: `isOwned` (true=owned, false=shared-with-me), `isShared`, `name`, `assetId` [1][2].
- `AssetResponseDto` includes `checksum`, `originalFileName`, `exifInfo`, `tags[]`, `thumbhash`, `updatedAt`, `width/height`, `livePhotoVideoId` — everything needed for stable filenames, dedup and incremental sync [1].
- Auth: `x-api-key` header; API keys are fine-grained (Permission enum ~140 values) [1][4]. Least-privilege export key (verified against v3 server controllers): `asset.read`, `asset.view` (thumbnail endpoint), `album.read`, `tag.read` — add `asset.download` only for originals/zip [95][96].

### A2. Derivatives — the "convert" step is usually redundant
- `GET /assets/{id}/thumbnail?size=` with enum `original | fullsize | preview | thumbnail`; `GET /assets/{id}/original` for the stored file; `size=original` on the thumbnail endpoint is **deprecated** in v3 source ("Use the :id/original endpoint instead") [1][95].
- Immich already generates per asset: blurred thumbhash, small thumbnail (webp), large **preview** (jpeg or webp — admin-configurable; default 1440p, lowerable to 1080p/720p; quality 1–100; optional Display-P3) [5].
- Immich generates these with **sharp** (libvips) [34], which strips EXIF/XMP/IPTC by default (keeping metadata requires explicit `.withMetadata()`) [35] → **previews are privacy-clean by construction**; originals carry full GPS/EXIF.
- Hugo's docs advise downscaling sources before build [26] — pulling 1440p previews instead of 50MP originals is the documented-aligned move. **On Netlify, Image CDN can replace Hugo processing altogether** (resize + avif/webp negotiation at the CDN) [81].
- If re-encoding is ever wanted outside Hugo: libvips/sharp lead (1.2–1.3s per 1000 JPEG resizes, 18–22MB peak on 8K vs ImageMagick 3.8s/380MB, Pillow 5.4s/420MB); AVIF native via libheif; `<picture>` AVIF + fallback recommended [38][36][37].
- HEIC caveat: Hugo cannot process HEIC/HEIF [26] — moot with derivative-pull (Immich already transcoded).

### A3. Export tooling
- **immich-go** (7,132★, AGPL-3.0, pushed 2026-10-31, v0.32.0): single Go binary; `archive from-immich --from-server --from-api-key --write-to-folder` exports server→folder with filtering [6][7][8]. Strongest ready-made export leg; migration-oriented, not gallery-aware.
- Downloader long tail: zckyachmd (Bun+SQLite state, resume, checksums; license NOASSERTION) [9]; notherealmarco (Python, MIT, stale) [10]; johnravi (Dockerized Node, MIT) [11]; NiklasRosenstein Deno gist (zip endpoint; large videos blow memory in zip-js → shells to unzip) [12]; jwest (cron) [44]; jon6fingrs/immich-dl (MIT) [74]; immichalbumpull [75]; immich-export PyPI [14]. Many small tools, none gallery-aware, mixed licensing — custom glue is normal.
- Bulk path: `POST /download/archive` (zip; also accepts share `key`) + `POST /download/info` [1][96].

### A4. Hugo-side ingestion — two architectures
1. **Classic page bundles** (kaiser.gallery pattern): one bundle per album (`content/photos/<album>/index.md` + images), templates iterate `.Resources`; proven at 5,000+ photos / 200+ albums with seconds-long rebuilds (warm cache) [18]. Themes: nicokaiser/hugo-theme-gallery (762★, MIT) [22], bep/gallerydeluxe (218★, MIT, by Hugo's co-lead) [20], mfg92/hugo-shortcode-gallery (426★, MIT) [76]. Hugo reads EXIF but not IPTC [18].
2. **Build-time pull (no committed images)**: content adapters (v0.126.0+) create pages from remote JSON [28][29]; `resources.GetRemote` supports `headers` (x-api-key), POST+body, disk cache with explicit `key`, `timeout`; 404→nil, unhandled errors fail the build [27]. On Netlify this couples every build to Immich reachability from Netlify's build bots through the lab edge (geoblock/SSO problems — see round 2 (c)) → **disfavored for the Netlify setup**; the lab-side build (option d) removes the issue.
- Processing facts either way: Crop/Fill/Fit/Resize/Filter/Process cached in `resources/_gen` (persist in CI), `hugo build --gc`, transforms drop metadata [26].
- **WebP trap**: golang/go#40173 still OPEN [25]; Hugo#8879 stale-closed unfixed [24]; "recommendation is not to use WebP images in Hugo" [23]. Mitigations: JPEG previews for any Hugo-reprocessed path, pass webp through untouched, `images.Contrast +15` workaround [24] — or bypass via Netlify Image CDN [81].

### A5. Repo-bloat / storage placement
- Practitioner consensus: keep images OUT of the site repo (S3-style external storage speeds builds) [30][31][32]; Git LFS is the pointer mechanism if binaries must be in git [33] — but see the round-2 LFS bandwidth trap [94][93]. GitHub's official guidance: LFS for binaries, "store programmatically generated files outside of Git, such as in object storage" [91].

## Approach B — embed/iframe, end to end

### B1. Iframe reality check
- Discussion #21521 (closed as duplicate): maintainer — "Have you tried just putting a shared album link into an iframe or such?"; author — "technically an iframe does work, but… you have the header… you are limited to the dimensions of the iframe, which is super annoying." [54]. No official embed block exists.
- Community CSP guides exist [55]; nothing shows Immich shipping frame-busting headers by default.

### B2. Share-link mechanics
- Public links: "random URL, which acts as a secret to avoid the link being guessed" (~64-char keys); options: expiry, password, allowDownload (default **true**), allowUpload, showMetadata (default **true**) [16][1]. v3 added slugs (`/s/my-album`) [1][56].
- Share `key` works as query param on asset endpoints (`thumbnail`, `original`, `download/archive`) → key-less public reads of exactly the shared assets; v3 server source confirms these routes are `sharedLink: true` [1][95][96].
- v3 breaking changes: password auth moved to `POST /shared-links/login` cookie flow; `SharedLinkResponse.token` removed [2].

### B3. Why not just reverse-proxy Immich's /share path
- Reddit pattern: shared.domain → Immich, external-domain setting — "it just works" [61]. Counter: viewing a shared album also needs `/api/` public → "any existing or future vulnerability… can compromise your whole Immich instance" [56]. Immich's own guide: never port-forward 2283; VPN/Tailscale shield zero-days [59].

### B4. The maintained B-side building blocks
- **IPP** — 2,403★, AGPL-3.0, v4.1.2 (2026-10-23) [57]. Stateless, no API key, read-only, validates+sanitizes, honors expiry/trash/locked-folder, visitor uploads in a separate container, "small enough to audit", Kubernetes install documented; ideal topology = Immich behind mTLS/VPN, only IPP public [56][57].
- **immich-folio** — MIT, 38★, v0.21.0, pushed 2026-10-31 [69]. Reverse-proxy portfolio: key never reaches browser, opaque encrypted asset tokens, only listed albums reachable; CDN mode, webhook cache invalidation, stale-buffering (round-2 detail [99]).
- **immich-event-gallery** (AGPL, 5★) [70]; **11notes/immich-share-proxy** (same-domain) [58]; frames: immich-kiosk 1,733★ [71], ImmichFrame 2,409★ [72].

### B5. Privacy traps unique to B
- `allowDownload` serves **original files** with full EXIF/GPS; `showMetadata=off` only hides display [42][43]. Client-side JS calling `/api/` directly would leak an API key — share-key endpoints exist so clients don't need keys [1][56].

## What practitioners actually use today

- awesome.immich.app indexes 22 client apps / 15 CLI tools / 7 integrations / 13 tools and itself flags "Unmaintained (8)" + "Vibe-Coded (12)" [73].
- Center of gravity: frames/kiosks (2.4k★/1.7k★) and IPP (2.4k★) — B′ runtime tools [71][72][57]. A-class builders are young or generic: ddphotos generator (181★, AGPL, pushed 2026-10-31; deploys "to… nginx… AWS S3, or… any static hosting service" — S3/static-host export is the established practitioner destination) [100], DD Photos app (17★, desktop) [67], immich-static-gallery (11★, unlicensed, stale) [68], Thumbsup (864★, MIT, not Immich-specific) [39][40].
- DD Photos author's critique of pure-B: one album per link, descriptions hidden, date order, "the link only works while your Immich server is up and reachable from the internet" [66].
- kaiser.gallery proves the A-pattern at Hugo scale [18]. **No maintained Immich→Hugo bridge exists** [64][65] — this card fills a real gap.

## Automation & sync cadence

- Polling is the shipped norm: cron downloaders [44][9], `scan.intervalMinutes` [68], GetRemote date-keys [27], Thumbsup incremental rebuilds [39].
- Event-driven, emerging: Immich v3 **Workflows + Plugins** — spec-confirmed endpoints and `WorkflowTrigger` enum `AssetCreate | AssetMetadataExtraction | AssetOcrExtraction | AssetTagged` [1]; `workflow.controller.ts` + `plugin.controller.ts` present in the repo's `server/src/controllers/` listing on main (GitHub API, 2026-10-31) [78]; action details only in a secondary blog [46] → spike-worthy, not dependable. General webhooks still a feature request [45]. folio already ships a `WEBHOOK_SECRET` cache-invalidation endpoint that would pair with such triggers [99].
- Schema-coupled hack (not adoptable): pg LISTEN/NOTIFY trigger on `album_asset` [65].
- Incremental mechanisms: `updatedAfter` windows, per-asset `checksum`, per-album `lastModifiedAssetTimestamp`/`assetCount` [1]; SQLite tool state [9]; Hugo cache keys [27].
- Vehicles: GHA with persisted `resources/_gen`+module caches (peaceiris/actions-hugo) [50][51][52][53]; Kubernetes CronJob [49] — bjw-s app-template supports `controller.type: cronjob` natively [47][48].

## Tradeoff matrix (round 1, still valid at the class level)

| Dimension | A — export to files (Hugo static) | B — iframe raw share pages | B′ — runtime proxy app (IPP/folio) |
|---|---|---|---|
| UX / design control | Full (Hugo themes, layouts, branding) [18][20][22] | None (app chrome, trapped lightbox) [54] | App's gallery UX; theming within app limits [57][69] |
| Privacy default | Best: derivatives EXIF/GPS-stripped by construction [35][26] | Risky: allowDownload serves GPS originals [42] | Good: key never in browser, opaque tokens [69]; downloads still governed by share settings [42] |
| Public attack surface | Static files only — minimal | Immich /share **+ /api** exposed [56][61] | Small auditable read-only proxy [56][57][69] |
| Availability coupling | Decoupled [66] | Hard dependency on Immich [66] | Hard dependency (folio buffers via STALE_MAX_AGE [99]) |
| Freshness | Lag = sync cadence | Real-time | Real-time |
| Storage/repo cost | Derivatives stored twice [30] | None | None (stateless) [56] |
| Video | Needs ffmpeg leg [39] | Native (HLS) [1] | Native [57][69] |
| SEO / archival | Static HTML, indexable | SPA behind share key, poor | SSR-ish, runtime-dependent (folio returns 503-not-404 for SEO [99]) |
| Maintenance burden | Custom glue + v3-major re-verification [2] | ~zero (and ~zero quality) | Adopt-a-project [57][69] |
| Hugo-native? | **Yes** | No | No (companion) |

---

# ROUND 2 — the two open problems

## R2.1 The Netlify delivery problem (how derivatives get INTO the build)

### (a) Export job commits derivatives into the Hugo repo (Netlify git build)
- GitHub **official guidance**: recommended on-disk `.git` ≤10GB; "Use Git LFS for binary files. **Store programmatically generated files outside of Git, such as in object storage.**"; directory width ≤3,000 entries (→ album subfolders, not one flat dir) [91]. Per-file limits: 50MiB warning / 100MiB hard block; single push ≤2GiB [92].
- Math at settled scale: 1,000 photos × ~200–500KB (1440p preview) ≈ **200–500MB working tree**. With content-hash filenames (`{assetId}-{checksum8}.ext` — checksum is on every AssetResponseDto [1]), unchanged photos never create new blobs; edits/re-exports do, and history grows monotonically. Every Netlify build clones the repo → clone cost tracks history size; GitHub explicitly warns large repos "slow down fetch operations and increase clone times for… CI" [91].
- **LFS variant is a trap**: Netlify Large Media deprecated 2023-09-01, Netlify's replacement advice is plain "Git LFS directly with your Git provider" [88]; GitHub free LFS quota = **1 GiB storage + 1 GiB bandwidth/month**, and exceeding bandwidth without a payment method **disables LFS until next month** [94][93]. Netlify builds fetch LFS objects each build → a ~0.5GB library on a daily build exhausts free bandwidth in ~2 days; hourly = instantly. Paid data packs fix it at ongoing cost.
- Verdict: acceptable **only** at the low end (≤~1k photos, derivatives-only, hash-stable names, no LFS), against GitHub's own guidance; clone times creep as the library churns.

### (b) Export to S3-compatible object storage; Hugo references URLs
- Managed flavor: **Cloudflare R2** — S3-compatible API, **zero egress fees**, public buckets via `r2.dev` subdomain or custom domain; custom domain brings Cloudflare CDN caching, WAF, even Zero Trust Access protection [101].
- Lab flavor: SeaweedFS already runs on proxy-local (repo storage pattern [106]) — but anonymous public serving must traverse the zerotrust edge (geoblock/SSO problems, see (c)) unless a no-auth subdomain is carved out.
- Hugo/Netlify integration: templates emit absolute bucket URLs directly; better, Netlify **Image CDN `remote_images`** (regex allowlist in netlify.toml) lets `/.netlify/images?url=https://bucket/…&w=…` transform bucket-hosted images — avif/webp content negotiation, CDN-cached, 304 on repeat [81]. One derivative per photo in the bucket suffices; the CDN derives all display sizes.
- Verdict: **cleanest separation** — git repo stays text-only (fast clones, PR preview deploys of content still work via Netlify git builds), matches GitHub guidance [91] and practitioner consensus [30]. Cost: bucket ops + a public hostname decision (R2 custom domain recommended).

### (c) Hotlink/proxy through the lab zerotrust stack
- **Direct hotlink** (visitor browser → lab hostname): traffic hits `proxy-remote.<domain>` = **geoblock US/CA-only** + crowdsec + per-subdomain userAuth/Keycloak-SSO middleware chain (repo-verified) [106] → anonymous worldwide visitors break unless a dedicated subdomain entry is configured **without** the auth chain and geoblock. Home uplink bandwidth and availability become the public site's image SLA. Immich-origin hotlinking also re-opens the /api exposure argument [56] — though the key-less URL shape is legitimate: `{host}/api/assets/{id}/thumbnail?size=preview&key={shareKey}` (v3 routes are `sharedLink:true`; AssetView permission) [95][1].
- **Netlify proxy-rewrite variant**: `/photos/* https://lab-origin/:splat 200` — "requests… proxied through… straight from our CDN servers without an additional connection from the browser"; CDN caches responses honoring ETags/Last-Modified; custom request headers can be injected toward the origin (an x-api-key could be added server-side, never shipped to browsers); **signed proxy redirects** add a JWS HMAC-HS256 `x-nf-sign` header (payload: site_url, netlify_id, exp) so the lab origin can verify traffic came via the Netlify site and refuse direct hits [80]. Limits: **26s proxy timeout** (video streams risk it), one hop, relative-path assets in proxied pages need absolute paths/`<base>` [80].
- Catch: Netlify CDN egress is worldwide → the lab geoblock (US/CA) may intermittently block proxied fetches from non-US POPs [106][80].
- Verdict: elegant seam (signed, same-origin URLs, zero duplication) but couples the **public site's** image availability/speed to the home lab and fights the zerotrust posture; use (if at all) for the B′ gallery path, not as primary delivery for A.

### (d) Netlify-side mechanisms
- **Build hooks**: a unique URL triggers build+deploy on request [79] — the lab export job can poke it after content-only commits.
- **CLI/API deploy (the unlock)**: `netlify deploy --prod --no-build` uploads an already-built folder as-is ("Manual CLI deploys skip the build. netlify deploy uploads what's already on disk" [84]; CLI builds or skips, uploads static files/functions, processes redirects/headers [83]). Deploys are **file-digest based**: the CLI/API hashes files and uploads only what the deploy doesn't already have (`/api/v1/deploys/{id}/files` exposes a deploy's file map) [85]. → **Lab-side CronJob: export → hugo build → netlify deploy**: images never enter git; only changed derivatives traverse the wire per run; Netlify build compute is not consumed (spends bandwidth/storage credits instead — note Netlify moved to credit-based plans for new accounts 2025-09-04; free plan = hard limits, legacy free was 100GB bandwidth + 300 build-min) [89][90].
- **Blobs**: deploy/site-scoped KV for Functions/Edge/build plugins; max 5GB per object [86][87]; **no public URLs** → right for sync-state JSON, wrong for photo delivery.
- **Edge Functions**: 20MB code, 512MB memory, **50ms CPU/request** [105] → cannot serve/transform gallery image bytes; not a delivery vehicle.
- Verdict: (d) is the mechanism that makes the git-free pipeline real; pair with in-cluster Hugo builds.

### R2.1 Recommendation (delivery)
**Primary: (d) + A** — home-cluster CronJob (app-template cronjob [47]): sync derivatives (API key via ExternalSecret+Bitwarden, least-privilege [95]) to a PVC or SeaweedFS volume → `hugo` build in-cluster → `netlify deploy --prod --no-build` (digest upload = changed files only [85]). Keep a small git repo for templates/content (Netlify git builds + build hooks [79] still available for content edits; PR previews of *content* work). Emit `/.netlify/images?url=…` links so Image CDN handles all display sizes + avif/webp negotiation [81] — Hugo image processing (and the WebP bug [23][25]) stays out of the loop.
**Runner-up: (b)** — R2 public bucket (custom domain) + Netlify git builds + `remote_images` allowlist [101][81], if Netlify-side builds are preferred over lab-side ones.
**Acceptable low-end fallback: (a)** plain-git derivatives-only with hash-stable names, ≤~1k photos [91][92].
**Avoid**: LFS [94][93][88]; (c) as primary [106][80][56].

## R2.2 B′ companion on Netlify (user said: evaluate — verdict below)

### Placement & reachability
- IPP/folio run on the **home cluster** (need in-cluster reach to Immich). Public exposure options: (i) the repo's zerotrust edge with a **dedicated subdomain entry lacking the userAuth/SSO chain** (the standard chain is SSO-gated for humans [106]) and geoblock lifted or accepted (US/CA-only audience?); or (ii) a Cloudflare Tunnel published-application route (public hostname → local service, no port forwarding, no public IP) [102]. Immich's **External domain** server setting then points share links at that hostname (IPP README step 4 [57]; reddit shared.domain pattern [61]).

### Iframe / CORS / mixed-origin posture (source-verified)
- **IPP sets no frame-blocking headers**: `addResponseHeaders` applies only the operator-configured `ipp.responseHeaders` map; nothing sets X-Frame-Options/CSP frame-ancestors by default [98][97]. → IPP galleries ARE iframeable, and the operator can explicitly add `Content-Security-Policy: frame-ancestors https://<netlify-site>` to allowlist exactly the Hugo site [98].
- **Cookie wall for password shares**: a cross-site iframe is a third-party context — cookies need `SameSite=None; Secure` on Chrome/Edge; **Safari blocks**, Firefox partitions; CHIPS `Partitioned` cookies / Storage Access API / token auth are the workarounds [103][104]. IPP password shares use a cookie unlock flow + no-store headers [97][98] → password-protected galleries inside iframes are fragile on Safari. Non-password shares have no cookie dependency and frame cleanly.
- **CORS is a non-issue** for `<img>`/iframe navigation (no cross-origin fetch happens); it would matter only for canvas/fetch pixel reuse. Mixed-origin is fine with HTTPS on both sides (Netlify + proxy edge).
- **Same-origin illusion**: Netlify proxy rewrite `/gallery/* → IPP 200` [80] + `x-nf-sign` JWS verification on the lab side; caveats: 26s timeout (don't proxy video playback — link out), absolute paths needed in proxied pages [80].

### Folio-specific strengths for this role (deployment docs, read [99])
- `CDN_URL` — native "serve photos and videos through a pull CDN" mode.
- `TRUSTED_PROXY_HOPS` — designed for traefik/nginx (=1) or +Cloudflare (=2) chains; without it, spoofable client IPs defeat password brute-force limits → fits the lab stack, must be set correctly.
- `WEBHOOK_SECRET` — `POST /api/webhook` cache invalidation; pairs naturally with Immich v3 Workflows (`AssetTagged`/`AssetCreate`) [1] for near-realtime freshness.
- Resilience: serves last-known-good data up to `STALE_MAX_AGE` when Immich is unreachable; **503-not-404** when nothing cached (SEO-safe) [99] — partially answers the "link only works while the server is up" critique [66].

### What practitioners do
- Observed norm is **link out**, not iframe-in: IPP users set Immich's external domain to the proxy and share its links [62][63][57]; reddit users share the proxied subdomain [61]; nobody in the sources iframes a gallery into a separate CMS site as the primary pattern. ddphotos targets S3/static hosts for its output [100].

### R2.2 Recommendation (B′ companion)
**Adopt as companion, phase 2 (or alongside phase 1 if cheap)**: run **IPP** (mature: 2.4k★, AGPL, k8s-documented, no-API-key design [56][57]) on the home cluster behind a dedicated no-auth public subdomain (or Cloudflare Tunnel [102]); choose **folio** instead if portfolio features (journals, proofing, CDN mode, webhook invalidation [99]) outweigh youth (38★, MIT). Hugo pages **link out** per album ("View live gallery"); iframe only non-password shares, with `frame-ancestors` allowlisted via `ipp.responseHeaders` [98]. Public shares: `allowDownload=false` (GPS-in-originals trap [42]), `showMetadata` per taste. Set Immich External domain to the companion hostname [57]. Do NOT proxy video through Netlify rewrites (26s timeout) [80].

## R2.3 Immich v3 API verification for the settled selection model

Verified against spec v3.4.0-rc.0 + `server/src/controllers/*` on main (2026-10-31) [1][95][96]:
- **Realistic selection conventions** (all first-class in v3): (i) albums-as-pages — `GET /albums?isOwned=true` lists albums; `AlbumResponseDto` gives `albumName`, `description`, `startDate/endDate`, `albumThumbnailAssetId`, `assetCount`, `lastModifiedAssetTimestamp`, `hasSharedLink` — a complete front-matter source; (ii) opt-in tag — `GET /tags` (hierarchical via `parentId` — e.g. a `web` parent tag with per-section children); `POST /search/metadata {tagIds:[…]}`; (iii) hybrid — albums define pages, a tag adds singles/extras; (iv) favorites/ratings — `isFavorite`, `rating` filters exist in the same search DTO if curation ever moves there [1].
- **Export call chain**: `POST /search/metadata {albumIds|tagIds, type:"IMAGE", updatedAfter:<last run>, withExif:true, page/size}` → per asset `GET /assets/{id}/thumbnail?size=preview` (or `fullsize`) → write `{assetId}-{checksum8}.{ext}` (checksum from AssetResponseDto [1]). Bulk alternative: `POST /download/archive {assetIds}` (zip; AssetDownload) [96].
- **Auth**: job uses `x-api-key` header [1]; **least-privilege key = `asset.read` + `asset.view` + `album.read` + `tag.read`** (viewAsset is `Permission.AssetView`, verified in controller source [95]); `asset.download` only if originals/zips are ever pulled [95][96]. Sessions/cookies are for humans; API keys don't expire by default and are scoped per user.
- **Hotlink-vs-pull URL formats**: pull = authenticated `GET {host}/api/assets/{id}/thumbnail?size=preview` with `x-api-key`; hotlink (public, key-less) = `GET {host}/api/assets/{id}/thumbnail?size=preview&key={shareKey}` — controller routes carry `sharedLink:true` [95], spec shows `key`+`slug` query params on thumbnail/original/download endpoints [1]; share web URLs are `/share/{key}` or `/s/{slug}` [16][57]. `GET /shared-links/me?key=` returns the share incl. `assets[]` [1]. `size=original` on the thumbnail endpoint is deprecated → `GET /assets/{id}/original` [95].
- **Caveat carried from round 1**: v2→v3 broke many shapes [2]; pin the export glue to the server's spec version (generated TS SDK [3]) and re-verify on Immich major upgrades.

---

## Licensing & maintenance health (checked 2026-10-31, GitHub API)

| Tool | Role | License | Stars | Last push | Verdict |
|---|---|---|---|---|---|
| immich-app/immich | platform | AGPL-3.0 | 117,803 | 2026-10-31 | v3.3.5 (2026-10-21); v3 broke APIs [2] — pin & re-verify [78][2] |
| simulot/immich-go | export leg | AGPL-3.0 | 7,132 | 2026-10-31 | Healthy; v0.32.0 (2026-06) [6][8] |
| alangrainger/immich-public-proxy | B′ proxy | AGPL-3.0 | 2,403 | 2026-10-29 | Healthy; v4.1.2; k8s docs; iframe-friendly headers [57][98] |
| ralksta/immich-folio | B′ portfolio | MIT | 38 | 2026-10-31 | Young, very active; v0.21.0; CDN mode + webhook invalidation [69][99] |
| dougdonohoe/ddphotos | static generator CLI | AGPL-3.0 | 181 | 2026-10-31 | Healthy; headless; S3/static-host deploy [100] |
| dougdonohoe/ddphotos-app | desktop front-end | AGPL-3.0 | 17 | 2026-10-31 | Active; desktop-only [67] |
| damongolding/immich-kiosk | frame | AGPL-3.0 | 1,733 | 2026-10-28 | Healthy [71] |
| immichFrame/ImmichFrame | frame | GPL-3.0 | 2,409 | 2026-10-15 | Healthy [72] |
| thumbsup/thumbsup | static generator | MIT | 864 | 2026-02-28 | Mature, slower cadence [40] |
| carmolim/immich-static-gallery | A off-the-shelf | **none** | 11 | 2025-10-30 | Unlicensed + stale — do not adopt [68] |
| zckyachmd/immich-album-downloader | export leg | NOASSERTION | 11 | 2026-07-21 | License unclear [9] |
| notherealmarco/immich-album-downloader | export leg | MIT | 6 | 2025-06-15 | Stale [10] |
| jon6fingrs/immich-dl | export leg | MIT | 15 | 2026-10-05 | OK [74] |
| v411e/photostream-album-sync | sync microservice | **none** | 4 | 2026-07-02 | Pattern reference only [65] |
| nicokaiser/hugo-theme-gallery | Hugo theme | MIT | 762 | 2026-05-28 | Healthy; documents WebP bug [22][23] |
| bep/gallerydeluxe | Hugo theme | MIT | 218 | 2026-09-18 | Healthy [20] |
| mfg92/hugo-shortcode-gallery | Hugo component | MIT | 426 | 2026-02-21 | Healthy [76] |
| gohugoio/hugo | SSG | Apache-2.0 | 90,305 | 2026-10-30 | Healthy [77] |
| lovell/sharp, libvips, ImageMagick, Pillow | converters | Apache-2.0 / LGPL-2.1+ / custom / MIT-like | 32k/11k/17k/14k | all 2026-06 | Healthy [38][37] |

AGPL note: immich-go / IPP / ddphotos are AGPL-3.0 — fine to **run** as separate containers/services; obligations bite only on modification+distribution. A small custom sync script calling the API has no license entanglement.

## Contradictions & weighing (round 1 + round-2 resolutions)

1. **"Just iframe it" (maintainer [54]) vs documented iframe UX failures ([54])** — framing works, quality doesn't. Round-2 resolution: B′ link-out + optional framed non-password IPP gallery with explicit `frame-ancestors` allowlist [98].
2. **shared.domain reverse proxy "just works" [61] vs "/api must be public too" [56][59]** — functionally vs security-wise; sanitized-proxy consensus wins for internet exposure [57][62][63].
3. **WebP first-class [5][26] vs "do not use WebP in Hugo" [23][24][25]** — the Go bug is decode-side; round-2 resolution: Netlify Image CDN does the format negotiation instead of Hugo [81], making the bug moot for served derivatives.
4. **"Convert and place" vs derivatives-already-converted [5][34][35][26]** — conversion optional; decisions are which `size=` to pull and who resizes (answer: Image CDN) [81].
5. **Polling everywhere vs event-driven [1][46][65]** — settled: hourly/daily cron is acceptable to the user; Workflows stay a later spike.
6. **Trap**: `showMetadata=false` ≠ sanitized downloads; `allowDownload` serves GPS originals [42][43] → companion shares ship with `allowDownload=false`.
7. **Round-2, resolved**: the user's storage split (git vs S3 vs PVC vs proxy) — evidence breaks the tie: GitHub's own "generated files outside git" guidance [91] + LFS free-bandwidth trap [94][93] + Netlify digest-upload making git-free deploys first-class [83][84][85] → **lab-side build + CLI deploy, images on lab storage**; bucket (R2) is the runner-up; git-commit only as a low-end fallback; proxy-hotlink not as primary [106][80].

## Implications for the plan (updated for round 2)

1. **Architecture (recommended)**: `charts/immich-hugo-sync/` (or similar) with `controller.type: cronjob` [47] on the **home** cluster: container = custom sync+build image (`containers/` per repo conventions; immich-go or thin API glue + hugo extended + netlify-cli) → PVC/SeaweedFS volume holds derivatives + Hugo site state → `netlify deploy --prod --no-build` ships digest-diffed output [83][85]. Secrets: Immich API key (least-privilege: asset.read/view, album.read, tag.read [95]) + `NETLIFY_AUTH_TOKEN` + site ID, all ExternalSecret+Bitwarden. Renovate pins images.
2. **Content repo**: small git repo (Hugo config, templates, content adapters/markdown, netlify.toml with `remote_images` only if (b) is chosen) — optionally wired to Netlify git builds + build hooks for content-only edits [79][82]; image bytes never committed [91].
3. **Image serving**: emit `/.netlify/images?url=…&w=…` (relative sources from the deploy, or `remote_images`-allowlisted bucket URLs) so the CDN negotiates avif/webp and resizes [81]; skip Hugo `.Resize`/`.Fill` in templates (also dodges the WebP decode bug [23][25]).
4. **Sync logic**: `POST /search/metadata {albumIds|tagIds, type:IMAGE, updatedAfter}` + per-album `lastModifiedAssetTimestamp` probe [1]; filenames `{assetId}-{checksum8}` for idempotent digest uploads [85][1]; state file (last-run timestamps) on the PVC or Netlify Blobs [86].
5. **B′ companion (phase 2 or parallel)**: IPP chart (k8s-documented [56][57]) or folio [69][99] on home cluster + dedicated no-auth public subdomain via proxy-remote entry (auth chain off; geoblock decision explicit) or Cloudflare Tunnel [102][106]; Immich External domain → companion hostname [57]; Hugo links out per album; iframe only non-password shares with `frame-ancestors` allowlist [98][103]; `allowDownload=false` [42].
6. **Cadence**: hourly or daily CronJob (user-settled); `concurrencyPolicy: Forbid` [47]; no Workflows dependency [1][46].
7. **Upgrade discipline**: pin glue to the Immich server's spec version (generated SDK [3]); add a re-verify task on Immich major upgrades (v3 proved churn [2]).
8. **Theme**: adopt hugo-theme-gallery or gallerydeluxe vs custom templates over page bundles — both proven at scale [18][20][22]; with Image CDN serving sizes, theme choice is mostly layout/CSS.

## Residual unknowns (final round — recommended defaults, not blocking questions)

1. **Netlify plan/credit budget** — unknown which plan the user's site is on (credit-based for new accounts since 2025-09 [89][90]). Default: the CLI-deploy pattern minimizes build-credit spend; verify bandwidth credits cover ~0.5–2GB initial upload + deltas.
2. **Geoblock policy for the companion subdomain** — the lab edge geoblocks US/CA [106]. Default: lift geoblock for the gallery host if the audience is international; keep crowdsec.
3. **IPP vs folio** — Default: IPP (maturity, 2.4k★, AGPL, k8s docs) unless portfolio features (journals/proofing/CDN mode) are wanted → folio (MIT, 38★, very active) [57][69][99].
4. **Bucket choice if runner-up (b) is picked** — Default: Cloudflare R2 custom domain (zero egress, CF CDN/WAF) [101]; lab SeaweedFS only with a carved-out no-auth public hostname.
5. **Content-repo hosting** — a second small GitHub repo for Hugo templates/content vs keeping everything in-cluster. Default: small private GitHub repo (enables Netlify git builds/build hooks + PR previews of content) [79][82].
6. **Immich External-domain change side effects** — pointing share links at the companion hostname changes ALL share-link URLs instance-wide [57][61]. Default: acceptable; verify existing shared links with family still resolve.
7. **Video (phase 2)** — Default: link out to IPP/folio for video playback rather than adding an ffmpeg leg [39][99]; revisit only if in-site video becomes a requirement.
8. **Whether ddphotos could shortcut phase 1** — it is a maintained headless generator with Immich pull + S3/static deploy [100][66], but it is NOT Hugo; the card asks for Hugo. Default: stay Hugo; keep ddphotos as design reference.

## Adjacent (out of scope but noted)

- immich-exif (Majorfi): syncs Immich DB metadata back INTO original files — relevant if exports should carry curated captions [41].
- Immich HLS endpoints (`/assets/{id}/video/stream/main.m3u8`) could feed a future video phase without files [1].
- v3 plugin system (`/plugins*`, `plugin.*` permissions) may eventually host a first-party "publish to web" plugin — watch, don't wait [1].
- Netlify n8n/Zapier deploy integrations exist [82] — the lab runs n8n; a no-code trigger path is possible but the CronJob is simpler.

## Reliability notes (self-review, rounds 1+2)

- **High confidence (primary/canonical, read directly)**: Immich v3 API surface, permissions, hotlink shapes (spec + controller source [1][95][96]); Netlify proxy rewrites incl. signed JWS + 26s timeout, Image CDN incl. remote_images, build hooks, CLI-deploy semantics, Blobs/Edge limits (official docs, read [80][81][79][83][84][86][105]); digest-based deploys (CLI issue + KB [85][84]); GitHub repo/LFS limits (official docs + verified mirror [91][92][93]); Large Media deprecation (Netlify's own forum [88]); LFS free quota 1GiB/1GiB (multiple concordant sources [94]); IPP header behavior (source read [97][98]); folio deployment features (docs read [99]); R2 public-bucket facts (official docs [101]); iframe third-party-cookie posture (MDN [103]); lab zerotrust chain (repo-internal, recently verified [106]); tool health (same-day GitHub API).
- **Medium confidence**: Netlify credit-pricing specifics for the user's actual plan (third-party explainers + pricing page [89][90] — account-specific); "Netlify builds fetch LFS objects each build" (consistent with LFS mechanics and the deprecation notice's advice [88], not separately load-tested); ddphotos headless CI usability (README claims [100], not executed).
- **Low confidence / flagged**: v3 Workflow webhook actions (spec confirms triggers/endpoints [1]; action surface only secondary [46]); clone-depth behavior of Netlify builds (not documented in sources found — checkout-cost claim rests on GitHub's general CI warning [91]).
- **Weakest round-2 claim**: that CLI-deploy bandwidth credits will comfortably cover the workload — depends on the user's plan and library churn; verification: check the account's credit balance after the first full upload (~library size) and one delta run.
- **Perspective balance**: round 2 leaned on docs/source reads over practitioner reports (few people publish Netlify+Immich write-ups; ddphotos' S3 destination [100] and the IPP link-out norm [62][63][61] are the main practitioner anchors).

## Sources

[1] Immich OpenAPI spec v3.4.0-rc.0 (canonical; fetched from immich-app/immich@main 2026-10-31; endpoints/DTOs/Permission enum analyzed locally; re-verified round 2: /tags, GET /albums params, SearchResponseDto, key/slug query params) — https://raw.githubusercontent.com/immich-app/immich/main/open-api/immich-openapi-specs.json
[2] Immich blog: Migrating to v3 — breaking API changes (read in full) — https://immich.app/blog/v3-migration
[3] Immich docs: API — OpenAPI generator, TS/Dart SDKs; AGPL v3 footer — https://docs.immich.app/api/
[4] Immich API docs: Getting started — API keys, fine-grained permissions (search snippet; JS-rendered page) — https://api.immich.app/getting-started
[5] Immich docs: System Settings — thumbhash/thumbnail(webp)/preview(jpeg|webp), 1440p default, quality, wide gamut (section read) — https://docs.immich.app/administration/system-settings/
[6] simulot/immich-go — archive from-immich export; AGPL-3.0; 7,132★ — https://github.com/simulot/immich-go
[7] immich-go readme — `archive from-immich --write-to-folder` usage — https://raw.githubusercontent.com/simulot/immich-go/main/readme.md
[8] GitHub API repo metadata (stars/license/pushed) — health-check pattern for all tools — https://api.github.com/repos/simulot/immich-go
[9] zckyachmd/immich-album-downloader — Bun, SQLite state, resume, checksums — https://github.com/zckyachmd/immich-album-downloader
[10] notherealmarco/immich-album-downloader — Python, resume-by-skip, MIT — https://github.com/notherealmarco/immich-album-downloader
[11] johnravi/Immich-Album-Exporter — Dockerized Node.js exporter, MIT — https://github.com/johnravi/Immich-Album-Exporter
[12] NiklasRosenstein Immich Album Downloader gist — Deno; zip endpoint; active 2026-07 (read) — https://gist.github.com/NiklasRosenstein/91d1bfc22485a4530271959300a69acf
[13] MrEAlderson gist — Python per-album download script (Sep 2026) — https://gist.github.com/MrEAlderson/f8edee1ece8e9a8348f254b750fd6ca8
[14] immich-export on PyPI 1.0.2 — https://pypi.org/project/immich-export/
[15] immich-go GUI docs — Archive from-immich workflow — https://shitan198u.github.io/immich-go-gui/user-guide/archive-workflows/
[16] Immich docs: Sharing — public links, random-URL-as-secret, expiry/password/actions (read) — https://docs.immich.app/features/sharing/
[17] Immich discussion #6910 — granular API-key permissions history — https://github.com/immich-app/immich/discussions/6910
[18] Hugo Discourse: Building a photo gallery site with Hugo — kaiser.gallery 5k photos/200 albums, seconds-long rebuilds, EXIF-not-IPTC, nginx serving (read) — https://discourse.gohugo.io/t/building-a-photo-gallery-site-with-hugo/43277
[19] nicokaiser/kaiser.gallery — source of the 5k-photo gallery — https://github.com/nicokaiser/kaiser.gallery
[20] bep/gallerydeluxe — MIT; 218★; pushed 2026-09-18 — https://github.com/bep/gallerydeluxe
[21] Gallery Deluxe on Hugo themes — https://themes.gohugo.io/themes/gallerydeluxe/
[22] nicokaiser/hugo-theme-gallery — MIT; 762★; README warns about WebP bug — https://github.com/nicokaiser/hugo-theme-gallery
[23] hugo-theme-gallery#102 "WebP contrast issues" — "recommendation is not to use WebP images in Hugo" (read) — https://github.com/nicokaiser/hugo-theme-gallery/issues/102
[24] gohugoio/hugo#8879 — WebP resize contrast bug; created 2021-08-11; closed 2025-12-16 by stale-bot (NOT fixed); Contrast +15 workaround — https://github.com/gohugoio/hugo/issues/8879
[25] golang/go#40173 — x/image/webp decode contrast issue; STILL OPEN 2026-10-31 — https://github.com/golang/go/issues/40173
[26] Hugo docs: Image processing — methods, caching, --gc, scale-down guidance, metadata-not-preserved, format table (AVIF processable, HEIC not) (read) — https://gohugo.io/content-management/image-processing/
[27] Hugo docs: resources.GetRemote — headers/method/body/key/timeout, disk caching, 404→nil, try-error idiom (read) — https://gohugo.io/functions/resources/getremote/
[28] Hugo docs: Content adapters — create pages at build time from remote JSON (new v0.126.0) — https://gohugo.io/content-management/content-adapters/
[29] Hugo Discourse: Pages from a Data Source — GetRemote+FromString API-to-pages pattern — https://discourse.gohugo.io/t/pages-from-a-data-source/36277
[30] Hugo Discourse: 10GB-of-images thread — separate images from site; S3; faster builds — https://discourse.gohugo.io/t/large-really-large-hugo-sites-10gb-of-images/38950
[31] Half-Elf on Tech: Hugo and a Lot of Images — CI rebuild pain — https://halfelf.org/2024/hugo-and-a-lot-of-images/
[32] Hugo Discourse: image processing best practice for git-hosted blogs — repo size concerns — https://discourse.gohugo.io/t/hugo-and-image-processing-best-practice-for-git-hosted-deployed-blogs/43001
[33] Git LFS — large-file pointers — https://git-lfs.com/
[34] Immich issue #29477 — sharp (webp2vips) stack trace in AssetGenerateThumbnails: Immich uses sharp — https://github.com/immich-app/immich/issues/29477
[35] sharp docs: withMetadata — metadata kept ONLY when requested (default strips EXIF/XMP/IPTC) (read) — https://sharp.pixelplumbing.com/api-output
[36] sharp docs: Performance — 4-5x faster than quickest ImageMagick/GraphicsMagick — https://sharp.pixelplumbing.com/performance/
[37] lovell/sharp README — libvips-based; 32.4k★ — https://github.com/lovell/sharp
[38] Pi Stack benchmark (June 2026): libvips/sharp/ImageMagick/Pillow speed+memory; AVIF via libheif; <picture> fallback advice (read) — https://www.pistack.xyz/posts/2026-06-20-image-optimization-libraries-libvips-sharp-imagemagick-pillow/
[39] Thumbsup — static gallery generator: resize, thumbnails, video re-encode — https://thumbsup.github.io/
[40] thumbsup/thumbsup — MIT, 864★, pushed 2026-02-28; incremental rebuilds — https://github.com/thumbsup/thumbsup
[41] Majorfi/immich-exif — sync Immich DB metadata back into files — https://github.com/Majorfi/immich-exif
[42] IPP docs: Sharing from Immich — allowDownload serves ORIGINAL files; showMetadata hides display only (read) — https://docs.ipp.nz/how-to-use
[43] IPP docs: Metadata — share owner's show-metadata precedence — https://docs.ipp.nz/config/metadata
[44] jwest/immich-album-downloader — cron-scheduled album downloads (pattern evidence) — https://github.com/jwest/immich-album-downloader
[45] Immich discussion #13181 — webhook feature request; websocket-system preference — https://github.com/immich-app/immich/discussions/13181
[46] instagit deep-dive: Immich workflow definitions/triggers/use cases incl. webhook plugins (secondary source) — https://instagit.com/immich-app/immich/immich-workflow-definition-execution-use-cases/
[47] bjw-s common library values — controller.type cronjob: schedule/concurrencyPolicy/restartPolicy — https://raw.githubusercontent.com/bjw-s/helm-charts/923ef40a39520979c98f354ea23963ee54f54433/charts/library/common/values.yaml
[48] bjw-s app-template docs — https://bjw-s-labs.github.io/helm-charts/docs/app-template/
[49] Kubernetes docs: CronJob — crontab-line semantics — https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/
[50] SSG Production: Caching Hugo Builds in GitHub Actions — resources/_gen + module cache — https://www.ssg-production.com/production-ready-deployment-cicd-workflows/incremental-builds-and-build-caching-for-ssgs/caching-hugo-builds-in-github-actions/
[51] SSG Production: GitHub Actions for Hugo — measured build times — https://ssg-production.com/production-ready-deployment-cicd-workflows/github-actions-for-automated-ssg-builds/how-to-set-up-github-actions-for-hugo-deployments/
[52] peaceiris/actions-hugo — standard Hugo setup action — https://github.com/peaceiris/actions-hugo
[53] MarketLens: production Hugo GHA workflow — pinned version, caches, link-check gate, previews — https://marketlens.work/blog/ci-cd-github-actions-hugo-deployment/
[54] Immich discussion #21521 — HTML embed block request; iframe "technically works" + limitations; maintainer reply; closed as duplicate (read in full) — https://github.com/immich-app/immich/discussions/21521
[55] Immich discussion #13043 — community CSP setup guide (frame-ancestors implications) — https://github.com/immich-app/immich/discussions/13043
[56] IPP docs: Introduction — /share+/api exposure problem; stateless/no-key/read-only design; mTLS ideal (read in full) — https://docs.ipp.nz/introduction
[57] alangrainger/immich-public-proxy — AGPL-3.0; 2,403★; v4.1.2 (2026-10-23); visitor-upload container; PhotoSwipe; External-domain setup step (README read) — https://github.com/alangrainger/immich-public-proxy
[58] 11notes/immich-share-proxy — same-domain share-only proxy — https://hub.docker.com/r/11notes/immich-share-proxy
[59] Immich docs: Remote Access — never port-forward 2283; VPN/Tailscale zero-day protection (read) — https://docs.immich.app/guides/remote-access/
[60] Immich docs: Reverse Proxy — header forwarding requirements — https://docs.immich.app/administration/reverse-proxy/
[61] r/immich — shared.domain nginx seam + external-domain setting; "it just works" — https://www.reddit.com/r/immich/comments/1dotjwm/how_to_correctly_share_via_public_link_while_not/
[62] XDA (2026): IPP deployment walkthrough + external-domain setting — https://www.xda-developers.com/how-securely-share-self-hosted-immich-albums-without-risking-home-network/
[63] bigiron.cc guide (Jul 2026): sharing publicly without exposing the server — https://www.bigiron.cc/guides/sharing-immich-albums-publicly-without-exposing-the-server
[64] GitHub repo search "immich hugo" — total_count=1 (2026-10-31) — https://api.github.com/search/repositories?q=immich+hugo
[65] v411e/photostream-album-sync — album→folder microservice; Postgres LISTEN/NOTIFY trigger on album_asset (README read) — https://github.com/v411e/photostream-album-sync
[66] Immich discussion #31795 — DD Photos show-and-tell; author's critique of share links (read) — https://github.com/immich-app/immich/discussions/31795
[67] dougdonohoe/ddphotos-app — AGPL-3.0; 17★; pushed 2026-10-31; desktop static builder pulling Immich albums — https://github.com/dougdonohoe/ddphotos-app
[68] carmolim/immich-static-gallery — album sync + Thumbsup + Cloudflare Pages + webhook notify; 11★; NO LICENSE; stale 2025-10 (README read) — https://github.com/carmolim/immich-static-gallery
[69] ralksta/immich-folio — MIT; 38★; v0.21.0; reverse-proxy portfolio; key never reaches browser; opaque asset tokens (README read) — https://github.com/ralksta/immich-folio
[70] PottiMc/immich-event-gallery — AGPL-3.0; event-guest photo portal — https://github.com/PottiMc/immich-event-gallery
[71] damongolding/immich-kiosk — AGPL-3.0; 1,733★; pushed 2026-10-28 — https://github.com/damongolding/immich-kiosk
[72] immichFrame/ImmichFrame — GPL-3.0; 2,409★; pushed 2026-10-15 — https://github.com/immichFrame/ImmichFrame
[73] Awesome Immich — community index; flags Unmaintained(8)/Vibe-Coded(12) (read) — https://awesome.immich.app/
[74] jon6fingrs/immich-dl — MIT; 15★; 2026-10 — https://github.com/jon6fingrs/immich-dl
[75] immichalbumpull — album pull CLI — https://git.orenit.solutions/open/immichalbumpull
[76] mfg92/hugo-shortcode-gallery — MIT; 426★; 2026-02 — https://github.com/mfg92/hugo-shortcode-gallery
[77] gohugoio/hugo — Apache-2.0; 90,305★; pushed 2026-10-30 — https://github.com/gohugoio/hugo
[78] immich-app/immich — AGPL-3.0; 117,803★; v3.3.5 (2026-10-21) — https://github.com/immich-app/immich
[79] Netlify docs: Build hooks — URL-triggered builds/deploys — https://docs.netlify.com/build/configure-builds/build-hooks/
[80] Netlify docs: Rewrites and proxies — 200-rewrite proxies served from Netlify CDN, ETag/Last-Modified caching, custom request headers, signed JWS `x-nf-sign` proxy redirects, 26s timeout, one-hop + absolute-path limits (read) — https://docs.netlify.com/manage/routing/redirects/rewrites-proxies/
[81] Netlify docs: Image CDN overview — `/.netlify/images` on-demand transforms, avif/webp content negotiation, CDN caching/304s, `remote_images` regex allowlist for other-domain sources, limitations (read) — https://docs.netlify.com/build/image-cdn/overview/
[82] Netlify docs: Create deploys — deploy paths: Git, CLI, drag-and-drop, API endpoints, build hooks, Zapier/n8n (read) — https://docs.netlify.com/deploy/create-deploys/
[83] Netlify CLI: deploy command reference — `--prod`, `--no-build`, uploads static files/functions/edge functions, processes redirects/headers — https://cli.netlify.com/commands/deploy/
[84] Netlify KB: How to deploy a site to Netlify — "Manual CLI deploys skip the build. netlify deploy uploads what's already on disk." — https://www.netlify.com/knowledge-base/how-to-deploy-a-site-to-netlify/
[85] netlify/cli#5589 — deploy file-digest mechanism; `/api/v1/deploys/{id}/files`; hash-based upload of only changed files — https://github.com/netlify/cli/issues/5589
[86] Netlify docs: Netlify Blobs — deploy/site-scoped KV store for Functions/Edge Functions/build plugins (no public URLs) — https://docs.netlify.com/build/data-and-storage/netlify-blobs/
[87] Netlify Answers: Blobs maximum object size — docs quoted: "An individual object's total size cannot exceed 5 GB" — https://answers.netlify.com/t/blobs-maximum-number-of-keys-in-store/115843
[88] Netlify Answers: Large Media deprecated (2023-09-01) — replacement advice: "use Git Large File Storage (LFS) directly with your Git provider" — https://answers.netlify.com/t/large-media-feature-deprecated-but-not-removed/100804
[89] Netlify pricing — free plan = hard monthly limits; paid plans credit-based with auto-recharge — https://www.netlify.com/pricing/
[90] Netli.fyi: Netlify Pricing and Limits in 2026 — credit-based since 2025-09-04; legacy free = 100GB bandwidth + 300 build minutes — https://netli.fyi/blog/netlify-pricing-and-limits
[91] GitHub docs: Repository limits — recommended on-disk .git ≤10GB; "Use Git LFS for binary files. Store programmatically generated files outside of Git, such as in object storage."; directory width ≤3,000 (read) — https://docs.github.com/en/repositories/creating-and-managing-repositories/repository-limits
[92] HyperObserve: GitHub limits (verified Aug 2026 against official docs) — 50MiB file warning / 100MiB hard block; 2GiB single push; LFS object max 2GB Free/Pro (read) — https://hyperobserve.com/limits/github/
[93] GitHub docs: Git LFS billing — included bandwidth/storage quotas; LFS disabled on bandwidth overage without payment method — https://docs.github.com/en/billing/concepts/product-billing/git-lfs
[94] Pixels May Jitter: Git LFS and GitHub Free Tier — 1 GiB free storage + 1 GiB/month free bandwidth — https://ryp.github.io/2023/git-lfs-and-github-free-tier/
[95] Immich server source: asset-media.controller.ts — viewAsset = `Permission.AssetView` + `sharedLink:true`; downloadAsset = `Permission.AssetDownload` + `sharedLink:true`; "size=original is deprecated. Use the :id/original endpoint"; fullsize-thumbnail may redirect to downloadAsset (read) — https://raw.githubusercontent.com/immich-app/immich/main/server/src/controllers/asset-media.controller.ts
[96] Immich server source: download.controller.ts — archive/info endpoints = `Permission.AssetDownload`, `sharedLink:true` (read) — https://raw.githubusercontent.com/immich-app/immich/main/server/src/controllers/download.controller.ts
[97] IPP source: app/src/index.ts — express server; no X-Frame-Options/CSP set; cookie unlock flow + no-store for password shares (read) — https://raw.githubusercontent.com/alangrainger/immich-public-proxy/main/app/src/index.ts
[98] IPP source: shared/src/http.ts — `addResponseHeaders` applies ONLY the operator-configured `ipp.responseHeaders` map; `addNoStoreHeaders` for password shares/errors (read) — https://raw.githubusercontent.com/alangrainger/immich-public-proxy/main/shared/src/http.ts
[99] immich-folio docs/deployment.md — `CDN_URL` pull-CDN mode; `TRUSTED_PROXY_HOPS` for proxy chains; `WEBHOOK_SECRET` POST /api/webhook cache invalidation; `STALE_MAX_AGE` buffering with 503-not-404 (read) — https://raw.githubusercontent.com/ralksta/immich-folio/main/docs/deployment.md
[100] dougdonohoe/ddphotos — headless static-gallery generator CLI; 181★; AGPL-3.0; pushed 2026-10-31; output deploys "to… Apache or nginx, to AWS S3, or… any static hosting service" — https://github.com/dougdonohoe/ddphotos
[101] Cloudflare R2 docs: Public buckets — r2.dev managed subdomain vs custom domain (Cloudflare CDN caching, WAF, Zero Trust Access); zero egress fees — https://developers.cloudflare.com/r2/buckets/public-buckets/
[102] Cloudflare One docs: Published applications — Cloudflare Tunnel publishes local applications on public hostnames without port forwarding — https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/
[103] MDN: CHIPS Partitioned cookies — per-top-site cookie jars for third-party contexts (iframe cookie partitioning) — https://developer.mozilla.org/en-US/docs/Web/Privacy/Guides/Third-party_cookies/Partitioned_cookies
[104] Stack Overflow: How SameSite cookie settings work with iframes — third-party-cookie blocking is browser-controlled beyond SameSite — https://stackoverflow.com/questions/79078942/how-samesite-cookie-settings-works-with-iframes
[105] Netlify docs: Edge Functions limits — 20MB code, 512MB memory, 50ms CPU per request — https://docs.netlify.com/build/edge-functions/limits/
[106] SpencersLab internal: skills/helm-chart-creation/references/proxying.md (verified 2026-09-07) — zerotrust seam: proxy-remote edge (geoblock US/CA + crowdsec), autossh :443 tunnel, proxy-local per-subdomain userAuth/Keycloak-SSO middleware chains, ExternalName fan-out, seaweedfs-csi on proxy-local — repo path (no URL)
