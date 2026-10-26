# RESEARCH — card #70: WeKan 9.99→12.64 removed Enter-to-submit on input fields

Commissioned by agent-board-coord, round 1 of the research-only loop
(card labelled `Research`), 2026-10-26. Method note: as in the sibling
upgrade RESEARCH (`2026-10-dep-wekan-v12-upgrade/RESEARCH.md`, cited
**[U1]**), the STORM interview stage is realized as evidence-gathering
against primary sources — five perspectives were followed as separate
tracks: upstream-changelog historian, Meteor-source forensicist, self-host
operator, community-issue watcher, UX-design reader. Every claim below was
read first-hand 2026-10-26 from the v9.99 / v12.64 / main source tarballs
(local `/tmp/opencode/wekan-r70/wekan-{9.99,12.64,main}`) or GitHub. No
implementation, no mutations.

## TLDR

Not a bug and not a regression to fight — it is an intentional upstream
change (wekan/wekan#4236) with a built-in switch. Since v12.07 all "add"
fields are multiline textareas that save on Ctrl/Cmd+Enter by default;
**Member Settings → Change Settings → "Submit editors with Enter"** (per-user,
saved server-side, takes effect instantly) restores plain-Enter-saves /
Shift+Enter-newline exactly as it was on v9.99. One click on
wekan.spencerslab.com fixes it — no repo, chart, image or cluster change.

## Q1 — Root cause (what changed between 9.99 and 12.64)

**Two upstream changes, both landed after v9.99 (released 2026-07-17) and
both are in 12.64; together they explain "EVERY input field":**

1. **#4236 "The processing strategy for the enter key is different"**
   (opened 2021-12-14, closed **completed** by xet7 2026-07-09 in commit
   `a9a5ac7a07050cbea746ab0a0a33e2e1f0f8dc1f`, shipped v9.82/v9.83,
   old-CHANGELOG/2026/07-part2.md L3447). Standardized multiline editors:
   submit ONLY on Enter+Ctrl/Cmd; plain Enter and Shift+Enter insert a
   newline — via the new pure rule `isSubmitKey()` in
   `models/lib/editorSubmitKey.js`.
2. **v12.07 (2026-09-27) commit `88e234f05`** — *"Make text editors
   multiline and resizable, honor the Enter preference"*
   (old-CHANGELOG/2026/09-part2.md L1401-1420): converted *ordinary titles,
   names, descriptions, labels, rule text and other prose fields* from
   single-line inputs to multiline textareas and applied the Enter rule
   **consistently** across them. This is the change the card is feeling —
   it swept the add-fields (checklist title, checklist item, label, list,
   board, comment, subtask, card title/description) all behind the same gate.

Source-level before/after (verified by reading both tags):

| Field | v9.99 handler | v12.64 handler |
|---|---|---|
| Add checklist item | `client/components/cards/checklists.js` L231-234: `keydown textarea.js-add-checklist-item` → `keyCode === 13 && !shiftKey` → submit — **plain Enter always saved** | same file L428-430: `isSubmitKey(event, { submitOnEnter: <user pref> })` — **plain Enter makes a newline unless the user enabled the pref** |
| Any inline add-form textarea (Add checklist/label/etc.) | `client/lib/inlinedform.js` L79-80: only Ctrl/Cmd+Enter handled | same file L81-85: shared `isSubmitKey` gate with the user pref |
| Add card at list bottom | `listBody.js` L567 "Pressing Enter should submit the card" | L918-919: `isSubmitKey` gate with the user pref |
| Global fallback | — | `client/lib/editorSubmit.js`: document-level keydown clicks the editor's visible submit button, gated by the same pref (with single-submit, validation, IME-composition and mention guards) |

The lab skipped v10.00…v12.63 in one bump [U1 §Q1], so the user experienced
the whole redesign as a single overnight regression.

## Q2 — Built-in option (YES — this is the fix)

v12.64 ships the exact toggle the card asks for.

- **UI:** avatar menu → **Change Settings** (`.js-change-settings`,
  `client/components/users/userHeader.jade` L94) → menu row **"Submit
  editors with Enter"** (`.js-toggle-submit-on-enter`, same file L435-440,
  icon `fa-level-down`). English label strings: `en.i18n.json` L1957
  `"submit-on-enter": "Submit editors with Enter"`; L1960 description:
  *"When on, pressing Enter saves the card title, description and other
  inline editors; Shift+Enter inserts a new line. When off, Ctrl/Cmd+Enter
  saves and Enter inserts a new line."*
- **Storage:** per-user `profile.submitOnEnter` (Boolean, optional, **off by
  default** — `models/users.js` L495-503), written only by the DDP method
  `Meteor.call('toggleSubmitOnEnter')` (`server/models/users.js` L988-994:
  requires a logged-in user, updates own profile, no admin needed).
  Server-side → applies to that user in every browser/device; because both
  lab frontends (`wekan.spencerslab.com` + `boards.spencerslab.com`) share
  one MongoDB [U1 §Q1], **toggling once covers both URLs**.
- **Live effect:** `docs/DeveloperDocs/Editor-Enter-Audit.md`: "The current
  user preference is read on each keypress, so switching it does not require
  a reload."
- **Keyboard shortcut without touching anything:** Ctrl/Cmd+Enter already
  saves every affected field (and Ctrl+Shift+Enter — "Ctrl wins", per the
  unit test). The user's "must click the add button" is partly undiscovered
  shortcut, not just missing Enter.
- **Scope:** the audit doc table covers all the card's examples — checklist
  titles/items, labels, lists/swimlanes, board, card title/description,
  comments/replies, subtasks, custom text fields, rule text. Single-line
  fields (search/filter, passwords, URLs, numbers, dates) were NOT changed:
  Enter still works natively there — the user's "every input field" is every
  *add/edit prose* field.
- **There is NO admin-panel setting, NO per-board setting, NO env var, and
  NO REST route** for it: `submitOnEnter` appears only in the client
  components, the model, the toggle DDP method, tests and the OpenAPI *schema
  docs* — `PUT /api/users/:userId` accepts only `takeOwnership`/
  `disableLogin`/`enableLogin` (`server/models/users.js` L2616-2644). New
  users (including OIDC-provisioned ones) start default-off. Bulk-setting is
  possible only via direct DB write (§Q4).

The README itself lists it as a headline feature: "Change Settings: Show
desktop drag handles, **Submit editors with Enter**, Open many cards at
once, …" (main README L66 area, same in v12.64 tree).

## Q3 — Upstream state

- **#4236** — closed **completed** 2026-07-09 by commit `a9a5ac7a`
  (resolution = Ctrl/Cmd standardization + the opt-in setting, commits
  `b8bb00465037389eb5829157441f2b75819353d9` feature entry +
  `bb6b0d5477368a97ba5cc1c01bdb598dcbe68cd2` setting UI, released **v10.01
  2026-07-18**, old-CHANGELOG/2026/07.md L6453-6470: "restores the fast
  Enter-to-save workflow for users who prefer it without regressing #4236").
- **Latest release: v12.65** (published 2026-10-25, GitHub API
  `releases/latest`). Mechanism **identical in v12.64 and current main**
  (verified byte-equal: `models/lib/editorSubmitKey.js`,
  `client/lib/editorSubmit.js`, `client/lib/inlinedform.js`,
  `client/components/cards/checklists.js`, `userHeader.js`; the later
  listBody/users.js diffs contain no Enter-related hunk). Default remains
  off. **Nothing to gain by rolling forward for this issue.**
- **Open issues:** GitHub issue search finds **zero open issues** with Enter
  submit in title, and the only hit for "submit on enter" created
  2026-06→2026-10 is #6700 (duplicate-checklist bug, closed same day,
  unrelated). Upstream considers this settled-by-setting; no newer fix or
  flag exists, and no PR is pending that changes the default.
- Executable coverage proves the behaviour is intentional and guarded:
  `tests/editorSubmitKey.test.cjs`, `tests/editorSubmitRouting.test.cjs`,
  `tests/playwright/specs/editor-enter-preference.e2e.js` — all present in
  the v12.64 tag.

## Q4 — Workaround paths for a self-hosted 12.64 (ranked)

1. **Toggle the built-in setting (recommended).** Human logs into
   wekan.spencerslab.com → avatar → Change Settings → "Submit editors with
   Enter". Zero repo/cluster surface, survives every future upgrade
   (it IS the upstream design), reversible in one click.
2. **Bulk server-side default for existing users** (only if multiple humans
   exist or they want bots/accounts pre-set): user-run mongosh against
   `home-mongodb` (AGENTS forbids agent pod-exec — present, don't run):
   `mongosh mongodb://home-mongodb:27017/wekan --eval 'db.users.updateMany({},{$set:{"profile.submitOnEnter":true}})'`
   (from a port-forward or the DB pod as the user chooses). Caveat: OIDC
   auto-creates new users with the pref unset → still default-off; would need
   re-running or per-user toggling. Not needed for a one-human board.
3. **Roll to v12.65** — irrelevant to this issue (no mechanism change); do
   it only on the lab's normal renovate/upgrade cadence [U1].
4. **Client-side patch / userscript / image customization** — possible
   (the affected code is client Blaze JS; a Tampermonkey keydown shim could
   re-add Enter-submit) but **actively harmful to maintainability**: it
   re-implements badly what option 1 does first-party, breaks on each
   minified-bundle change, and there is no supported mount for custom client
   JS in the ghcr image (no values knob in chart 12.64 either). Reject.
5. **Rollback to v9.99** — absurd here: loses the v12 multi-action-rule
   cutover the board itself runs on, and the lab's DB has already been
   forward-migrated by v12 startup schema steps [U1 §Q2]. Reject.

## Q5 — Recommendation & follow-up card shape

**Recommend:** option 1 — the setting is the fix; this ticket closes as
"working as intended upstream; built-in preference enabled". No repo change,
no PR, no image bump, no userscript.

Implementation card (if coord wants one):
- **Services checklist item: `home`** — wekan + boards live in
  `services/home/prod` (Chart.yaml wekan deps + values; [U1] §Q1). Note the
  fix touches NO files there; if a repo record is wanted, the honest homes
  are `.agents/notes/` or the `wekan-api` skill's human-UI section (type
  `docs`), not a values edit.
- Concrete steps: (a) human toggles the setting on one of the lab URLs;
  (b) verifies Enter saves on: checklist item add, checklist title add,
  label add, comment, card title, add-card-at-bottom; (c) confirms
  Shift+Enter now makes a newline there; (d) optional: note the Ctrl/Cmd+
  Enter shortcut for users who keep the pref off; (e) if any add-field still
  refuses Enter with the pref ON, capture field + version → that is a real
  upstream bug → file an issue (needs the user's go + GitHub identity, same
  gate as the checkItem-typo report in [U1]).
- Keep it research-adjacent: bots are unaffected (pipeline drives WeKan via
  REST/MCP — no keyboards involved), so no wekan-mcp/`containers/` work.

## Contradictions / cautions

- **Schema-comment cross-ref:** `models/users.js` cites "#4236/#6480" but
  **#6480 is a FerretDB-performance issue** (closed 2026-07-21) — the #6480
  half of the citation is loose/wrong; the real trail is #4236 + commits
  `a9a5ac7a`/`b8bb004650`/`88e234f05`. Don't cite #6480 in the card comment.
- **"They used to submit on enter"** — true for the add-fields (v9.99
  checklists.js L234 unconditional), but **card title already behaved
  Ctrl+Enter-only in v9.99** (v9.99 cardDetails L1533 comment; #4236's title
  fix shipped v9.82, before 9.99). The perceived "everything changed at
  once" is the one-step 9.99→12.64 bump swallowing ~3.5 months of releases
  [U1].
- **"EVERY input field"** — overstated: the audit doc explicitly keeps
  search/filter/URL/credential/date/number/color fields single-line with
  native Enter. Expect some fields to keep working on Enter (they do).
- The user reported *clicking the add button required* — consistent with
  default-off multiline editors where Enter silently inserts a newline
  (looks like "nothing happens"); Ctrl/Cmd+Enter works today as a stopgap.

## Implications for the follow-up implementation

- Plan **no repo change**; the deliverable is the one-click UI toggle plus a
  short verification sweep. Anyone planning a "patch keyup handlers" or a
  userscript chunk would be solving a solved problem — this RESEARCH.md
  exists to stop that.
- If the lab later wants org-wide defaults, the mongosh `updateMany` (§Q4.2)
  is the only bulk lever; document it as user-run.
- Re-check on the *next* upgrade: mechanism byte-identical 12.64→main, so
  low churn risk; if upstream ever flips the default this note becomes moot.

## Open questions (for the batched round)

1. Does enabling the setting fully satisfy the card, or does some field
   still ignore Enter with it ON? — Best guess taken: fully (the audit + e2e
   tests cover the sweep of fields; single-line fields were never affected).
   Impact: a straggler field would flip the ticket from "setting" to a real
   upstream bug worth an issue/PR.
2. Are there multiple human users who should get it pre-set via the mongosh
   bulk command? — Best guess taken: the lab owner only, so UI toggle is
   enough; no DB write proposed.
3. Should the follow-up card be typed `chore`/`docs` (record the finding)
   rather than `debug` as best-guessed at kickoff? — Best guess taken: keep
   `debug` unless the human wants a note committed to `.agents/notes/`/the
   wekan-api skill, then `docs`.
4. Does the human want this finding answered back on the upstream tracker?
   — Best guess taken: no — nothing to report; #4236 resolution covers it.

## Adjacent

- The same Member Settings popup holds related v12 QoL toggles: "Open many
  cards at once" (#6531), checklist ding sound (#5427), keep #tags in card
  title (#1273), sidebar width — worth a one-time look while the popup is
  open.
- Upstream docs for this feature: `docs/DeveloperDocs/Editor-Enter-Audit.md`
  (in-tree; not yet on the public docs site as far as could be seen).

## Sources (all read first-hand 2026-10-26)

- [S1] wekan@v12.64 tarball — `/tmp/opencode/wekan-r70/wekan-12.64`:
  `models/lib/editorSubmitKey.js` (full), `client/lib/editorSubmit.js`
  (full), `client/lib/inlinedform.js` L20/81-85,
  `client/components/cards/checklists.js` L231-430, `minicard.js` L819,
  `subtasks.js` L121, `comments.js` L145, `listBody.js` L918-919,
  `rulesList.js` L111, `users/userHeader.jade` L94/L435-440,
  `users/userHeader.js` L492-556, `server/models/users.js` L988-994 and
  L2616-2650, `models/users.js` L495-503, `imports/i18n/data/en.i18n.json`
  L1957-1960, `docs/DeveloperDocs/Editor-Enter-Audit.md` (full),
  `tests/editorSubmitKey.test.cjs`, `README.md` L66,
  `old-CHANGELOG/2026/{07,07-part2,09-part2,09-part5}.md` entries.
- [S2] wekan@v9.99 tarball — `wekan-9.99`: `client/components/cards/checklists.js`
  L231-234, `checklists.jade` L73 (`textarea rows=1`),
  `inlinedform.js` L79-80, `listBody.js` L567, `cardDetails.js` L1533/1742,
  `labels.jade` L3, `cardDescription.js` L26, `mentionKeyGuard.js` (whole
  `isSubmitKey`-free Enter handling).
- [S3] wekan@main tarball (v12.65.0 per `package.json`) — diff vs 12.64 of
  all Enter-mechanic files (byte-equal or Enter-irrelevant).
- [S4] GitHub API: issue #4236 (state closed-completed, closed_at
  2026-07-09, closing commit `a9a5ac7a…`), issue #4236 timeline (referenced
  commits `984ec160…`, `bb6b0d54…`, `cbe4e4fc…`), issue #6480
  (performance issue — citation caution), issue search "submit on enter"
  2026-06..10 → only #6700 (closed), open-Enter-title search → 0,
  `releases/latest` → v12.65 published 2026-10-25.
- [S5] [U1] `.agents/plans/2026/2026-10-dep-wekan-v12-upgrade/RESEARCH.md` —
  deployed version/pin (chart 12.64.0 = image ghcr v12.64), one-step bump
  history, shared-DB topology, `services/home/prod` location.
- [S6] WeKan README (main branch render via search snippet) — "Change
  Settings: … Submit editors with Enter …" feature listing.

## Reliability notes (peer review)

- Root cause (design change #4236 + v12.07 multiline sweep) — **10/10**:
  issue, commits, changelog entries, and both tags' source all read directly.
- Built-in setting exists in the DEPLOYED 12.64 and does what the card wants
  — **9/10**: code + docs + tests all read at the tag; the missing point is
  that live-browser confirmation on the lab instance hasn't been done (that
  is the follow-up card's verification step, §Q5).
- "No env/admin/REST knob; per-user only" — **9/10** (exhaustive grep of the
  12.64 tree for `submitOnEnter`; OpenAPI schema is read-documentation only).
- "Nothing gained from rolling to v12.65" — **8/10** (byte-diff of the
  mechanic files between 12.64 and main; residual: a 12.65 changelog entry
  elsewhere could alter an edge field — none found by changelog grep).
- Weakest claim: "both lab frontends share the pref because they share the
  DB" — **7/10**: inferred from [U1]'s verified two-pods-one-MONGO_URL
  topology, not re-tested live; harmless either way (toggle on the URL the
  human actually uses).
