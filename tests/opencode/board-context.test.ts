// Board-context prefetch plugin test seam — formatBlock / resolveBoardContext
// / createPromptHandler / isBoardCoordAgent / resolveMcpUrl / unwrapToolResult
// / parseSseData plus the exported FETCH_TIMEOUT_MS and DEFAULT_ENABLED — and
// the setup wiring: exactly one prompt hook and (cf-123 C03) the one
// /reload-board-context command. Covers the cf-75 C04 block contract, the
// cf-123 C01 strict-YAML fence with per-list cards (ask B) and the cf-123 C03
// durable once-mark + refresh command (ask D).
//
// Run from the repo root: node --test tests/opencode/board-context.test.ts
// (Node v26 type-strips the .ts directly; no build step, no npm deps, no
// external network — the fakes below are the only collaborators; the
// setup-level command arms loop a 127.0.0.1 MCP stub in-process, the
// card-details.test.ts precedent).
//
// This file lives in the repo-root tests/ tree, deliberately NOT under
// .opencode/: plugin discovery loads every .ts it scans there, so a test file
// inside the plugin dir would be imported as a plugin entry at server startup
// (the question-notify.test.ts convention this suite copies).
//
// cf-123 test wave (2026-11-07, agent-test): the EXPECTED block below is the
// C01 re-pin — the body under the UNCHANGED canonical header line parses as
// one strict YAML document (owner ruling #1), every In Process list carries
// its cards group (card_number derived <boardKey>-<cardNumber> per ruling #2,
// card_id, label names), and the footer prose is # comment lines. S10 is the
// DELIBERATE INVERSION of the enable-as-is-era scope guards: the cards:
// absence arm becomes a presence arm, the five-leg arm becomes six legs, and
// the list_cards_in_list ban STAYS (Option 1 assembles from preload_board,
// never the by-list projection). Never weaken an inverted arm back to its
// old shape — the old shape pins the pre-C01 block.
//
// SEAM CONTRACT (what dev must export from .opencode/plugin/board-context/index.ts):
//   formatBlock(fields) -> string                       fields = { collectedAt,
//     serverId, boardId, swimlaneId, boardKey, lists, customFields, labels };
//     boardKey is the board document's `key` (the C04 projection) or absent/
//     falsy in the pre-rollout degrade; the list arrays carry { name, id,
//     cards } entries and each card { cardNumber, cardId, labels } with the
//     RAW number — the "<boardKey>-<cardNumber>" derivation (JSON.stringify
//     quoted, bare String(cardNumber) + the pinned note line when boardKey is
//     falsy) is the formatter's job; pure, no clock read.
//   resolveBoardContext(deps, opts) -> Promise<string>  deps = { callTool(name,
//     args), log? }; opts = { boardTitle, swimlaneTitle, serverId,
//     collectedAt }; runs list_boards -> get_board -> list_swimlanes ->
//     list_lists -> list_custom_fields -> preload_board, the preload leg
//     called with { board_id } ONLY (client-side In Process scoping from the
//     own list_swimlanes/list_lists legs); the board key rides the existing
//     get_board leg; cards join by list id from the preload's swimlane
//     grouping, sort ascending, archived skipped, label ids resolved through
//     the preload's label_names with an unknown id emitted raw; a list the
//     grouping lacks renders cards: [] from the list_lists leg; a successful
//     preload with the swimlane grouping absent renders every list empty
//     cards + one stderr line (deps.log or console.error), never a throw.
//   createPromptHandler(deps, opts?) -> (event) => Promise<void>
//     deps = { getAgent(sessionID), resolve(serverId), log(message),
//     fetchTimeoutMs?, storage? }; opts = { enabled? } defaulting to
//     DEFAULT_ENABLED; agent read = event.agent with a getAgent fallback.
//     storage = the durable once-mark adapter { get(key), set(key, value),
//     remove(key) } (positional set, get -> undefined when absent), key
//     once/<sessionID>, value an epoch-ms stamp; absent storage degrades to
//     the per-process in-memory Map (today's behavior). A prompt already
//     carrying the canonical header is marked without injecting; the first
//     attempt CONSUMES the mark whether the fetch succeeds or fails
//     (ruling #5); a stale mark older than 6 h is ignored and removed on
//     encounter.
//   isBoardCoordAgent(agent) -> boolean; BOARD_COORD_AGENTS: string[].
//   resolveMcpUrl(deps) -> Promise<string|null>         deps = { mcpList(),
//     readConfig() }; named-server match, no credentials.
//   unwrapToolResult(rpcBody) -> any; parseSseData(text) -> any|null.
//   FETCH_TIMEOUT_MS: number (the admission-latency budget); DEFAULT_ENABLED:
//   boolean; default export { id, setup } matching the two shipped plugins'
//   working shape (plain object with async setup(ctx), NOT the docs'
//   Plugin.define). setup registers exactly one ctx.session.hook("prompt",
//   ...) and (C03) the one ctx.command.transform spec named
//   "reload-board-context" when the host provides it — with one degrade
//   stderr line and the same one prompt hook when it does not. The command's
//   execute fetches a fresh block through the same resolve path (the
//   FETCH_TIMEOUT_MS budget) and answers via ctx.session.prompt on the
//   invocation's envelope (text on the arg); a failed fetch answers one line,
//   leaves the mark untouched, and never throws.
//
// The EXPECTED block below is the landed C01 schema fence byte-for-byte,
// carrying the plan's verified-fact ids; skill-surface.sh t3 pins the schema's
// single markdown owner. If C01's skill text drifts from this transcription,
// this suite fails on a real two-owners drift — the fix is adjudicated
// through the validation-fix route, never by weakening the constant.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { createServer, type Server, type AddressInfo } from "node:http";

import * as plugin from "../../.opencode/plugin/board-context/index.ts";
// The single formatter the hook's collectedAt now rides (cf-96 C09 T2) — the
// test imports it directly to prove both geometries flow through it.
import { localIso } from "../../.opencode/plugin/pipeline-locks/index.ts";

const mod = plugin as Record<string, any>;

function seam(name: string): (...args: any[]) => any {
  const fn = typeof mod[name] === "function" ? mod[name] : mod.default?.[name];
  if (typeof fn !== "function") {
    throw new Error(
      `plugin seam "${name}" is not exported (see the SEAM CONTRACT header — dev must export it from .opencode/plugin/board-context/index.ts)`,
    );
  }
  return fn;
}

const COLLECTED_AT = "2026-10-27T12:00:00Z";
const SERVER_ID = "dev-boards";

// The board's key rides the get_board leg (the C04 projection; the deployed
// pre-rollout build lacks it — the degrade arms below run that shape).
const BOARD_KEY = "AD";

// The C01 schema fence byte-for-byte (plan chunks/C01.md "The new fence"):
// header line UNCHANGED (the five-artifact idempotence anchor), the body one
// strict YAML document — list mappings with cards: sequences, mapping keys /
// list titles / label names / card_number JSON.stringify-quoted, ids bare —
// and the footer prose as # comment lines. Fixture evidence per the C01 test
// list: >=2 lists, the ONE empty list (Rework — the export drops cardless
// lists), one card without labels, one card whose label id is NOT in
// label_names (jXX4GM), one archived card that must not render (99), and the
// sort-order proof (the Not Started cards arrive out of order and render
// ascending).
const EXPECTED_BLOCK = `Board context (collected ${COLLECTED_AT}, ${SERVER_ID})
board_id: TNQJ2BrXenZovngTS
swimlane_id: jLzy39L7djCRr67SF
lists:
  - title: "Not Started"
    id: XhDyShvuwhGWzWH2z
    cards:
      - card_number: "AD-7"
        card_id: CARD0000000000007
        labels: ["Research"]
      - card_number: "AD-123"
        card_id: xdrvXPW3LeF2TGpGD
        labels: ["Pipeline: Context", "Provider: API"]
  - title: "Executing"
    id: qZ9CLZqCRbv7NQQ6R
    cards:
      - card_number: "AD-42"
        card_id: CARD0000000000042
        labels: []
  - title: "Review"
    id: 2B6wWGJ8Tetp5QWDJ
    cards:
      - card_number: "AD-11"
        card_id: CARD0000000000011
        labels: ["jXX4GM", "Research"]
  - title: "Rework"
    id: y9tsvb3AguKWhzCoF
    cards: []
  - title: "Finished"
    id: DHw56fMKy3qyfudz4
    cards:
      - card_number: "AD-3"
        card_id: CARD0000000000003
        labels: []
  - title: "Low Priority"
    id: M4JS9LfaypJbB97At
    cards:
      - card_number: "AD-15"
        card_id: CARD0000000000015
        labels: ["Ready for Work"]
  - title: "Test"
    id: jNYNdCPPkX8Bs95s4
    cards:
      - card_number: "AD-1"
        card_id: CARD0000000000001
        labels: []
custom_fields:
  "slug": RaNeqvh9YoT4bnkZ8
  "session": zZw4PwMoLeodJy3eT
labels:
  "Research": ysSmS5
  "Ready for Work": mkbxeo
# Cards are a collection-time snapshot — the walk's get_card confirmation
# and claim-before-move absorb drift. Checklist ids are not included — they
# are live per-card data, resolved at use time. On any id-shaped call
# error, re-resolve this block against the live board before retrying.`;

// The pinned degrade note (ruling #2): the get_board answer without a truthy
// key renders bare quoted card_numbers plus exactly this one comment line as
// the FIRST trailing-comment line. The degrade is visible per snapshot, never
// silent and never stderr-only (scheduled-tick consumers read the block).
const DEGRADED_NOTE = "# card_number values are bare: the get_board projection carried no board key at collection time.";

// The degrade form is the same fence with the prefix derivation stripped and
// the note line inserted — derived, not re-transcribed, so the two shapes
// cannot drift apart.
const DEGRADED_BLOCK = EXPECTED_BLOCK
  .replace(/card_number: "AD-(\d+)"/g, 'card_number: "$1"')
  .replace(/^# Cards are a collection-time snapshot/m, `${DEGRADED_NOTE}\n# Cards are a collection-time snapshot`);

const FIELDS = {
  collectedAt: COLLECTED_AT,
  serverId: SERVER_ID,
  boardId: "TNQJ2BrXenZovngTS",
  swimlaneId: "jLzy39L7djCRr67SF",
  boardKey: BOARD_KEY,
  lists: [
    {
      name: "Not Started",
      id: "XhDyShvuwhGWzWH2z",
      cards: [
        { cardNumber: 7, cardId: "CARD0000000000007", labels: ["Research"] },
        { cardNumber: 123, cardId: "xdrvXPW3LeF2TGpGD", labels: ["Pipeline: Context", "Provider: API"] },
      ],
    },
    { name: "Executing", id: "qZ9CLZqCRbv7NQQ6R", cards: [
      { cardNumber: 42, cardId: "CARD0000000000042", labels: [] },
    ] },
    { name: "Review", id: "2B6wWGJ8Tetp5QWDJ", cards: [
      { cardNumber: 11, cardId: "CARD0000000000011", labels: ["jXX4GM", "Research"] },
    ] },
    { name: "Rework", id: "y9tsvb3AguKWhzCoF", cards: [] },
    { name: "Finished", id: "DHw56fMKy3qyfudz4", cards: [
      { cardNumber: 3, cardId: "CARD0000000000003", labels: [] },
    ] },
    { name: "Low Priority", id: "M4JS9LfaypJbB97At", cards: [
      { cardNumber: 15, cardId: "CARD0000000000015", labels: ["Ready for Work"] },
    ] },
    { name: "Test", id: "jNYNdCPPkX8Bs95s4", cards: [
      { cardNumber: 1, cardId: "CARD0000000000001", labels: [] },
    ] },
  ],
  customFields: [
    { name: "slug", id: "RaNeqvh9YoT4bnkZ8" },
    { name: "session", id: "zZw4PwMoLeodJy3eT" },
  ],
  labels: [
    { name: "Research", id: "ysSmS5" },
    { name: "Ready for Work", id: "mkbxeo" },
  ],
};

// Raw projections exactly as the deployed wekan-mcp tools answer them
// (server.py _slim_* / preload_board): lists/swimlanes/boards key on `title`,
// custom fields and labels key on `name` — the mapping asymmetry this suite
// pins. The In Process swimlane carries six of the seven lists: Rework has no
// cards, so the export drops it (the plugin must render it empty from its own
// list_lists leg).
const LISTS_PROJECTION = [
  ...FIELDS.lists.map((l) => ({ id: l.id, title: l.name, swimlane_id: "jLzy39L7djCRr67SF" })),
  { id: "FARMONLY000000001", title: "Backlog", swimlane_id: "FARM-SWIM-0001" },
];

// The preload's whole-board answer (repo server.py shape, re-probed live
// 2026-11-07): swimlane/list titles beside ids, the 8-field cards, board-wide
// label_names. Rework is ABSENT (cardless lists drop out of the export); the
// Not Started cards arrive OUT of sort order (123 before 7) so the suite
// proves the plugin's own ascending sort, not the server's; the Farm swimlane
// list must not leak into the In Process block.
const PRELOAD_PROJECTION = {
  board_id: "TNQJ2BrXenZovngTS",
  swimlanes: [
    {
      id: "jLzy39L7djCRr67SF",
      title: "In Process",
      lists: [
        {
          id: "XhDyShvuwhGWzWH2z",
          title: "Not Started",
          cards: [
            { id: "xdrvXPW3LeF2TGpGD", card_number: 123, label_ids: ["3PGnrD", "f3sKNX"], slug: null, archived: false, sort: 2, parent_id: null, checklists: [] },
            { id: "CARD0000000000007", card_number: 7, label_ids: ["ysSmS5"], slug: null, archived: false, sort: 1, parent_id: null, checklists: [] },
            { id: "CARD0000000000099", card_number: 99, label_ids: [], slug: null, archived: true, sort: 3, parent_id: null, checklists: [] },
          ],
        },
        { id: "qZ9CLZqCRbv7NQQ6R", title: "Executing", cards: [
          { id: "CARD0000000000042", card_number: 42, label_ids: [], slug: null, archived: false, sort: 1, parent_id: null, checklists: [] },
        ] },
        { id: "2B6wWGJ8Tetp5QWDJ", title: "Review", cards: [
          { id: "CARD0000000000011", card_number: 11, label_ids: ["jXX4GM", "ysSmS5"], slug: null, archived: false, sort: 1, parent_id: null, checklists: [] },
        ] },
        { id: "DHw56fMKy3qyfudz4", title: "Finished", cards: [
          { id: "CARD0000000000003", card_number: 3, label_ids: [], slug: null, archived: false, sort: 1, parent_id: null, checklists: [] },
        ] },
        { id: "M4JS9LfaypJbB97At", title: "Low Priority", cards: [
          { id: "CARD0000000000015", card_number: 15, label_ids: ["mkbxeo"], slug: null, archived: false, sort: 1, parent_id: null, checklists: [] },
        ] },
        { id: "jNYNdCPPkX8Bs95s4", title: "Test", cards: [
          { id: "CARD0000000000001", card_number: 1, label_ids: [], slug: null, archived: false, sort: 1, parent_id: null, checklists: [] },
        ] },
      ],
    },
    {
      id: "FARM-SWIM-0001",
      title: "Farm",
      lists: [
        { id: "FARMONLY000000001", title: "Backlog", cards: [
          { id: "CARD0000000000098", card_number: 98, label_ids: [], slug: null, archived: false, sort: 1, parent_id: null, checklists: [] },
        ] },
      ],
    },
  ],
  dependencies: [],
  label_names: {
    ysSmS5: "Research",
    mkbxeo: "Ready for Work",
    "3PGnrD": "Pipeline: Context",
    f3sKNX: "Provider: API",
    // jXX4GM is deliberately NOT in the map — the unknown-id raw-emission arm
  },
  field_names: { RaNeqvh9YoT4bnkZ8: "slug", zZw4PwMoLeodJy3eT: "session" },
};

// The six leg answers the setup-level command arms run the real resolve path
// against (loopback stub; card-details.test.ts startBoardStub shape).
const SIX_LEG_ANSWERS = {
  list_boards: [
    { id: "OTHERBOARD000001", title: "Farm Ops" },
    { id: "TNQJ2BrXenZovngTS", title: "AI-Dev" },
  ],
  get_board: {
    id: "TNQJ2BrXenZovngTS",
    title: "AI-Dev",
    key: BOARD_KEY,
    permission: "private",
    color: "blue",
    archived: false,
    labels: [
      { id: "ysSmS5", name: "Research", color: "red" },
      { id: "mkbxeo", name: "Ready for Work", color: "green" },
    ],
  },
  list_swimlanes: [
    { id: "UPNEXT-SWIM-0001", title: "Up Next" },
    { id: "jLzy39L7djCRr67SF", title: "In Process" },
    { id: "FARM-SWIM-0001", title: "Farm" },
  ],
  list_lists: LISTS_PROJECTION,
  list_custom_fields: [
    { id: "RaNeqvh9YoT4bnkZ8", name: "slug", type: "text" },
    { id: "zZw4PwMoLeodJy3eT", name: "session", type: "text" },
  ],
  preload_board: PRELOAD_PROJECTION,
};

function fakeCallTool(opts: any = {}) {
  const calls: any[] = [];
  const callTool = async (name: string, args: any) => {
    calls.push({ name, args });
    if (opts.throwOn === name) throw new Error(`tools/call ${name} failed`);
    switch (name) {
      case "list_boards":
        return [{ id: "OTHERBOARD000001", title: "Farm Ops" }, { id: "TNQJ2BrXenZovngTS", title: "AI-Dev" }];
      case "get_board": {
        // boardKey default "AD" (the canonical expectation); boardKeyAbsent
        // models the DEPLOYED pre-rollout projection — no key field at all.
        const board: any = {
          id: "TNQJ2BrXenZovngTS",
          title: "AI-Dev",
          permission: "private",
          color: "blue",
          archived: false,
          labels: [
            { id: "ysSmS5", name: "Research", color: "red" },
            { id: "mkbxeo", name: "Ready for Work", color: "green" },
          ],
        };
        if (!opts.boardKeyAbsent) board.key = opts.boardKey === undefined ? "AD" : opts.boardKey;
        return board;
      }
      case "list_swimlanes":
        if (opts.swimlanes !== undefined) return opts.swimlanes;
        return [
          { id: "UPNEXT-SWIM-0001", title: "Up Next" },
          { id: "jLzy39L7djCRr67SF", title: "In Process" },
          { id: "FARM-SWIM-0001", title: "Farm" },
        ];
      case "list_lists":
        return LISTS_PROJECTION;
      case "list_custom_fields":
        return [
          { id: "RaNeqvh9YoT4bnkZ8", name: "slug", type: "text" },
          { id: "zZw4PwMoLeodJy3eT", name: "session", type: "text" },
        ];
      case "preload_board":
        if (opts.preload !== undefined) return opts.preload;
        return PRELOAD_PROJECTION;
      default:
        throw new Error(`unexpected tool call ${name}`);
    }
  };
  return { callTool, calls };
}

// The durable once-mark seam (C03): positional set(key, value), get(key) ->
// undefined when absent, remove(key) — the tolerant adapter shape
// pipeline-locks probes confirmed on v2.1.4.
function fakeStorage(seed: Record<string, number> = {}) {
  const items: Record<string, number> = { ...seed };
  const calls = { get: 0, set: 0, remove: 0 };
  const storage = {
    items,
    calls,
    get: async (key: string) => {
      calls.get++;
      return key in items ? items[key] : undefined;
    },
    set: async (key: string, value: number) => {
      calls.set++;
      items[key] = value;
    },
    remove: async (key: string) => {
      calls.remove++;
      delete items[key];
    },
  };
  return storage;
}

function fakeHandlerDeps(opts: any = {}) {
  const calls = { getAgent: [], resolve: [], log: [] };
  const deps = {
    getAgent: async (sessionID: string) => {
      calls.getAgent.push(sessionID);
      if (opts.getAgentThrows) throw new Error("session lookup failed");
      return typeof opts.agent === "function" ? opts.agent(sessionID) : opts.agent;
    },
    resolve: async (serverId: string) => {
      calls.resolve.push(serverId);
      if (opts.resolveThrows) throw new Error("board fetch failed");
      if (opts.resolveHangs) return new Promise(() => {});
      if (opts.resolveValue !== undefined) return opts.resolveValue;
      return EXPECTED_BLOCK;
    },
    log: (message: string) => {
      calls.log.push(message);
    },
    fetchTimeoutMs: opts.fetchTimeoutMs,
    storage: opts.storage,
  };
  return { deps, calls };
}

async function runHandler(handler: any, event: any): Promise<any> {
  try {
    await handler(event);
    return null;
  } catch (err) {
    return err;
  }
}

const coordEvent = (sessionID: string, messageID: string, text = "run the hourly board gate") => ({
  sessionID,
  messageID,
  prompt: { text },
});

// RESEARCH.md Implication 2: a hook that throws or hangs blocks prompt
// admission outright ("If preparation fails or is interrupted, OpenCode does
// not admit the prompt") — so every failing arm below must resolve normally
// and leave the prompt untouched. Never-throw is a correctness requirement,
// not a style rule.

// The body under the header line, parsed as strict YAML (the ruling #1
// contract). python3 + PyYAML: the suite stays dependency-free Node-side, and
// a parse failure is a thrown execFileSync, which fails the arm.
function yamlBody(block: string): any {
  const body = block.slice(block.indexOf("\n") + 1);
  const out = execFileSync(
    "python3",
    ["-c", "import json, sys, yaml\nprint(json.dumps(yaml.safe_load(sys.stdin.read())))"],
    { input: body, encoding: "utf8" },
  );
  return JSON.parse(out);
}

describe("S1 formatBlock — one formatter, byte-exact strict-YAML fence (C01 AC 1)", () => {
  it("emits the re-pinned fence byte-for-byte for the verified-fact fields", () => {
    assert.equal(seam("formatBlock")(FIELDS), EXPECTED_BLOCK);
  });

  it("is pure: the collected stamp comes from the input, never a clock read", () => {
    const changed = seam("formatBlock")({ ...FIELDS, collectedAt: "2026-11-01T00:00:00Z", serverId: "admin-global-wekan" });
    assert.ok(changed.startsWith("Board context (collected 2026-11-01T00:00:00Z, admin-global-wekan)"), changed.split("\n")[0]);
    assert.equal(changed.slice(changed.indexOf("\n")), EXPECTED_BLOCK.slice(EXPECTED_BLOCK.indexOf("\n")));
  });

  it("the header line is the UNCHANGED canonical anchor (ruling #1: no move, no # comment header)", () => {
    const block = seam("formatBlock")(FIELDS);
    const header = block.split("\n")[0];
    assert.ok(header.startsWith("Board context (collected"), `the canonical header prefix moved: ${header}`);
    // CANONICAL_HEADER is the five-artifact idempotence anchor: the byte the
    // scan matches must stay the sentence prefix, not a re-invented line.
    assert.match(block, /^Board context \(collected [^\n]+\nboard_id: /m);
  });

  it("the body under the header line parses as ONE strict YAML document (ruling #1)", () => {
    const doc = yamlBody(EXPECTED_BLOCK);
    assert.equal(doc.board_id, "TNQJ2BrXenZovngTS");
    assert.equal(doc.swimlane_id, "jLzy39L7djCRr67SF");
    assert.equal(doc.lists.length, 7, "every In Process list renders, empty ones included");
    for (const entry of doc.lists) {
      assert.ok(typeof entry.title === "string" && entry.title.length > 0, "list entries are title/id mappings");
      assert.ok(Array.isArray(entry.cards), "every list carries a cards: sequence (ruling #3: all lists, no cap)");
    }
    const notStarted = doc.lists.find((l: any) => l.title === "Not Started");
    assert.deepEqual(notStarted.cards.map((c: any) => c.card_number), ["AD-7", "AD-123"], "cards render sort-ascending with the derived prefix");
    assert.deepEqual(notStarted.cards[1].labels, ["Pipeline: Context", "Provider: API"], "label ids resolve to names through the preload's label_names");
    const rework = doc.lists.find((l: any) => l.title === "Rework");
    assert.deepEqual(rework.cards, [], "the list the export drops renders cards: [] from the list_lists leg");
    const review = doc.lists.find((l: any) => l.title === "Review");
    assert.deepEqual(review.cards[0].labels, ["jXX4GM", "Research"], "an unknown label id emits RAW beside the resolved names");
    assert.ok(!JSON.stringify(doc).includes("AD-99"), "the archived card must not render");
    assert.equal(doc.custom_fields["slug"], "RaNeqvh9YoT4bnkZ8");
    assert.equal(doc.labels["Ready for Work"], "mkbxeo");
  });

  it("card_number stays a YAML STRING in both derive states — the quoting keeps the type stable across the degrade", () => {
    const doc = yamlBody(DEGRADED_BLOCK);
    for (const entry of doc.lists) {
      for (const card of entry.cards ?? []) {
        assert.equal(typeof card.card_number, "string", `card_number ${card.card_number} parsed as ${typeof card.card_number} — a bare scalar would be an int (the DECISIONS type-unstable rejection)`);
      }
    }
  });

  it("derives the prefix from the boardKey input — data-driven, never a hardcoded literal (ruling #2)", () => {
    const zk = seam("formatBlock")({ ...FIELDS, boardKey: "ZK" });
    // Swapping the prefix back must restore the canonical fence exactly: the
    // derivation is the ONLY difference between key values.
    assert.equal(zk.replace(/"ZK-/g, `"${BOARD_KEY}-`), EXPECTED_BLOCK);
    assert.ok(!zk.includes(DEGRADED_NOTE), "a truthy key emits no degrade note");
  });

  it("renders the pinned degrade form when the boardKey is absent or falsy (the deployed pre-rollout shape)", () => {
    for (const boardKey of [undefined, null, ""]) {
      const block = seam("formatBlock")({ ...FIELDS, boardKey });
      assert.equal(block, DEGRADED_BLOCK, `boardKey ${String(boardKey)} must render the bare form with the pinned note line`);
      assert.ok(!block.includes(`${BOARD_KEY}-`), "no prefixed form survives the degrade");
    }
    // The note is the FIRST trailing-comment line (before the footer).
    const noteIdx = DEGRADED_BLOCK.indexOf(DEGRADED_NOTE);
    const footerIdx = DEGRADED_BLOCK.indexOf("# Cards are a collection-time snapshot");
    assert.ok(noteIdx >= 0 && footerIdx > noteIdx, "the degrade note precedes the footer comments");
  });

  it("cross-checks the C01 schema owner carries the same fence tokens and the degrade note bytes", () => {
    const skill = readFileSync("skills/wekan-mcp/SKILL.md", "utf8");
    assert.ok(skill.includes("Board context (collected"), "SKILL.md lost the canonical schema header");
    for (const label of ["board_id", "swimlane_id", "custom_fields", "labels"]) {
      assert.ok(skill.includes(label), `SKILL.md schema no longer names the ${label} field`);
    }
    // The inversion's owner-side half: the cards group tokens and the
    // documented degrade note bytes ride the schema section (C01 AC 6).
    for (const label of ["card_number", "card_id"]) {
      assert.ok(skill.includes(label), `SKILL.md schema no longer names the ${label} per-card field`);
    }
    assert.ok(skill.includes(DEGRADED_NOTE), "SKILL.md no longer documents the pinned degrade note bytes (the probe/degrade law must be visible to consumers)");
    assert.ok(/board.{0,12}key/i.test(skill), "SKILL.md no longer names the board key as the card_number derivation source");
  });
});

describe("S2 resolveBoardContext — six-leg sequence and per-list card assembly (C01 AC 2-5)", () => {
  it("runs the six calls in order, the preload leg with { board_id } ONLY, and formats the re-pinned block", async () => {
    const { callTool, calls } = fakeCallTool();
    const block = await seam("resolveBoardContext")(
      { callTool },
      { boardTitle: "AI-Dev", swimlaneTitle: "In Process", serverId: SERVER_ID, collectedAt: COLLECTED_AT },
    );
    assert.equal(block, EXPECTED_BLOCK);
    assert.deepEqual(
      calls.map((c) => c.name),
      ["list_boards", "get_board", "list_swimlanes", "list_lists", "list_custom_fields", "preload_board"],
      "the collector sequence is the C01 skill's resolution order — the sixth (preload) leg is serial, after list_custom_fields",
    );
    const preload = calls.find((c) => c.name === "preload_board");
    assert.ok(preload, "the preload leg was never called");
    assert.deepEqual(
      preload.args,
      { board_id: "TNQJ2BrXenZovngTS" },
      "the preload leg passes { board_id } ONLY — client-side In Process scoping, build-tolerant and drift-safe (the swimlane_titles filter would render an empty board on a renamed swimlane)",
    );
  });

  it("maps custom fields by name, lists by title, and keeps the scope to the In Process swimlane", async () => {
    const { callTool } = fakeCallTool();
    const block = await seam("resolveBoardContext")(
      { callTool },
      { boardTitle: "AI-Dev", swimlaneTitle: "In Process", serverId: SERVER_ID, collectedAt: COLLECTED_AT },
    );
    assert.ok(!block.includes("FARMONLY000000001"), "a Farm-swimlane list leaked into the In Process block");
    assert.ok(!block.includes("CARD0000000000098"), "a Farm-swimlane card leaked into the In Process block");
    assert.ok(block.includes('"slug": RaNeqvh9YoT4bnkZ8'), "custom fields must key on the JSON.stringify-quoted name field");
    assert.ok(block.includes('- title: "Not Started"') && block.includes("id: XhDyShvuwhGWzWH2z"), "lists must map title (quoted) = name, id bare");
  });

  it("joins per-list cards from the preload grouping: empty-list render, archived skip, sort ascending, unknown label raw (C01 AC 2/4)", async () => {
    const { callTool } = fakeCallTool();
    const block = await seam("resolveBoardContext")(
      { callTool },
      { boardTitle: "AI-Dev", swimlaneTitle: "In Process", serverId: SERVER_ID, collectedAt: COLLECTED_AT },
    );
    const reworkAt = block.indexOf('- title: "Rework"');
    assert.ok(reworkAt >= 0, "Rework (absent from the export) must still render from the list_lists leg");
    assert.ok(block.slice(reworkAt, reworkAt + 60).includes("cards: []"), "the list the preload grouping does not carry renders cards: []");
    assert.ok(!block.includes("AD-99") && !block.includes("CARD0000000000099"), "the archived card must not render");
    assert.ok(block.indexOf('card_number: "AD-7"') < block.indexOf('card_number: "AD-123"'),
      "cards render sort-ascending — the fixture preload delivers them out of order, so only the plugin's own sort explains the pin");
    assert.ok(block.includes('labels: ["jXX4GM", "Research"]'), "an unknown label id emits the raw id beside the resolved names");
  });

  it("derives the prefixed card_numbers from the get_board leg's key (no extra leg — the key rides the existing call)", async () => {
    const { callTool, calls } = fakeCallTool();
    const block = await seam("resolveBoardContext")(
      { callTool },
      { boardTitle: "AI-Dev", swimlaneTitle: "In Process", serverId: SERVER_ID, collectedAt: COLLECTED_AT },
    );
    assert.equal(block, EXPECTED_BLOCK);
    assert.equal(calls.filter((c) => c.name === "get_board").length, 1, "the board key must ride the EXISTING get_board leg — a seventh leg is the over-fetch this design rejects");
  });

  it("degrades to bare card_numbers + the pinned note when the get_board projection carries no key (the deployed pre-rollout shape)", async () => {
    const { callTool } = fakeCallTool({ boardKeyAbsent: true });
    const block = await seam("resolveBoardContext")(
      { callTool },
      { boardTitle: "AI-Dev", swimlaneTitle: "In Process", serverId: SERVER_ID, collectedAt: COLLECTED_AT },
    );
    assert.equal(block, DEGRADED_BLOCK, "the deployed pre-rollout projection (no key field) renders the bare form with the pinned degrade note — the probe/degrade law, never silent");
  });

  it("rejects when the In Process swimlane is missing from the OWN list_swimlanes leg (loud no-block — the client-side scoping throw)", async () => {
    const { callTool } = fakeCallTool({ swimlanes: [
      { id: "UPNEXT-SWIM-0001", title: "Up Next" },
      { id: "FARM-SWIM-0001", title: "Farm" },
    ] });
    await assert.rejects(
      seam("resolveBoardContext")(
        { callTool },
        { boardTitle: "AI-Dev", swimlaneTitle: "In Process", serverId: SERVER_ID, collectedAt: COLLECTED_AT },
      ),
      /swimlane/i,
      "a renamed or missing swimlane throws into the hook's no-block degrade — a block that reads as an empty board is the silent danger the client-side scoping exists to avoid",
    );
  });

  it("renders every list cards: [] with exactly one stderr line when a SUCCESSFUL preload carries no swimlane grouping (never a throw, C01 AC 4)", async () => {
    const lines: string[] = [];
    const origError = console.error;
    console.error = (...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    };
    try {
      const { callTool } = fakeCallTool({ preload: { board_id: "TNQJ2BrXenZovngTS", dependencies: [], label_names: {}, field_names: {} } });
      const block = await seam("resolveBoardContext")(
        { callTool, log: (m: string) => lines.push(m) },
        { boardTitle: "AI-Dev", swimlaneTitle: "In Process", serverId: SERVER_ID, collectedAt: COLLECTED_AT },
      );
      assert.equal((block.match(/cards: \[\]/g) ?? []).length, 7, "every list renders empty cards when the grouping is absent");
      assert.ok(block.startsWith("Board context (collected"), "the block still ships (degraded, visible) — a half-shaped silence is not this path");
      assert.equal(lines.length, 1, `exactly one stderr line names the degraded grouping, saw ${JSON.stringify(lines)}`);
    } finally {
      console.error = origError;
    }
  });

  it("propagates a mid-sequence tool failure so the caller degrades — the preload leg included (S6 family, C01 AC 5)", async () => {
    for (const leg of ["list_swimlanes", "preload_board"]) {
      const { callTool } = fakeCallTool({ throwOn: leg });
      await assert.rejects(
        seam("resolveBoardContext")(
          { callTool },
          { boardTitle: "AI-Dev", swimlaneTitle: "In Process", serverId: SERVER_ID, collectedAt: COLLECTED_AT },
        ),
        `a failed ${leg} leg must reject the whole resolve — no half-shaped block ships`,
      );
    }
  });
});

describe("S3 agent filter — the three whole board-coord ids (AC 1)", () => {
  it("accepts exactly the three explicit ids and nothing else", () => {
    const is = seam("isBoardCoordAgent");
    for (const agent of ["agent-board-coord", "agent-board-coord-local", "agent-board-coord-pr"]) {
      assert.equal(is(agent), true, `${agent} must pass the filter`);
    }
    for (const agent of ["agent-coord", "agent-board", "code", "agent-coord-local", "build", "", undefined, null]) {
      assert.equal(is(agent as any), false, `${String(agent)} must not pass the filter`);
    }
  });

  it("lists the roster as whole values — no globs, no prefixes", () => {
    const roster = (mod.BOARD_COORD_AGENTS ?? mod.default?.BOARD_COORD_AGENTS) as string[];
    assert.ok(Array.isArray(roster), "BOARD_COORD_AGENTS must be exported");
    assert.deepEqual([...roster].sort(), ["agent-board-coord", "agent-board-coord-local", "agent-board-coord-pr"]);
    for (const entry of roster) assert.ok(!entry.includes("*"), `roster entry ${entry} is a glob, not a whole value`);
  });
});

describe("S4 once-guard — durable per-session mark, never per messageID (C03 AC 1, re-pin of the in-memory era)", () => {
  // RESEARCH.md matrix "Retries" + the cf-123 EXPLORE §D root cause: the two
  // live opencode server processes load the plugin independently, so an
  // in-memory map re-injects on a follow-up that rides the other process
  // (this ticket's own coord session re-injected at 02:55Z with no restart).
  // The mark must live in shared durable storage; the seam is one fake
  // storage across two handler instances.
  it("a mark set through one handler instance prevents injection through a second (the cross-process seam, C03 AC 1)", async () => {
    const storage = fakeStorage();
    const a = fakeHandlerDeps({ agent: "agent-board-coord", storage });
    const b = fakeHandlerDeps({ agent: "agent-board-coord", storage });
    const ha = seam("createPromptHandler")(a.deps, { enabled: true });
    const hb = seam("createPromptHandler")(b.deps, { enabled: true });
    const first = coordEvent("ses_a", "msg_1");
    assert.equal(await runHandler(ha, first), null);
    assert.ok(first.prompt.text.endsWith(`\n\n${EXPECTED_BLOCK}`), "first prompt gets \\n\\n + block appended after the expanded gate text");
    assert.ok(first.prompt.text.startsWith("run the hourly board gate"), "append must keep the original prompt a byte-exact prefix (stale-offset rule)");
    assert.equal(typeof storage.items["once/ses_a"], "number", "the first attempt consumes the mark durably at once/<sessionID> with an epoch-ms stamp");
    const second = coordEvent("ses_a", "msg_2");
    assert.equal(await runHandler(hb, second), null);
    assert.equal(second.prompt.text, "run the hourly board gate", "a second handler instance (the other server process) must not re-inject the same session");
    assert.equal(a.calls.resolve.length + b.calls.resolve.length, 1, `one board fetch for the session across BOTH instances, saw ${a.calls.resolve.length + b.calls.resolve.length}`);
  });

  it("keeps the guard per-session (not global): a different session still gets its block", async () => {
    const storage = fakeStorage();
    const { deps } = fakeHandlerDeps({ agent: "agent-board-coord", storage });
    const handler = seam("createPromptHandler")(deps, { enabled: true });
    await handler(coordEvent("ses_a", "msg_1"));
    const b = coordEvent("ses_b", "msg_2");
    assert.equal(await runHandler(handler, b), null);
    assert.ok(b.prompt.text.includes(EXPECTED_BLOCK), "the guard must key the sessionID, not be global");
    assert.equal(typeof storage.items["once/ses_b"], "number", "the second session consumed its own mark");
  });

  it("fresh messageIDs never defeat the guard (the command path mints a new one per attempt)", async () => {
    const storage = fakeStorage();
    const { deps, calls } = fakeHandlerDeps({ agent: "agent-board-coord", storage });
    const handler = seam("createPromptHandler")(deps, { enabled: true });
    await handler(coordEvent("ses_a", "msg_1"));
    for (const messageID of ["msg_2", "msg_3", "msg_4"]) {
      const ev = coordEvent("ses_a", messageID);
      assert.equal(await runHandler(handler, ev), null);
      assert.equal(ev.prompt.text, "run the hourly board gate", `${messageID} must not re-inject`);
    }
    assert.equal(calls.resolve.length, 1, "one fetch for the session no matter how many messageIDs ride it");
  });

  it("skips non-coord sessions without consuming their once-slot", async () => {
    const storage = fakeStorage();
    const { deps, calls } = fakeHandlerDeps({ agent: "agent-coord", storage });
    const handler = seam("createPromptHandler")(deps, { enabled: true });
    const plain = coordEvent("ses_p", "msg_1");
    assert.equal(await runHandler(handler, plain), null);
    assert.equal(plain.prompt.text, "run the hourly board gate");
    assert.equal(calls.resolve.length, 0, "a non-coord session must never be fetched for");
    assert.ok(!("once/ses_p" in storage.items), "a non-coord session must not consume the mark");
  });

  it("absent storage degrades to the per-process in-memory guard — per-instance once, NOT shared (C03 AC 2: today's behavior, kept as the fallback)", async () => {
    const a = fakeHandlerDeps({ agent: "agent-board-coord" });
    const ha = seam("createPromptHandler")(a.deps, { enabled: true });
    const first = coordEvent("ses_f", "msg_1");
    assert.equal(await runHandler(ha, first), null);
    assert.ok(first.prompt.text.includes(EXPECTED_BLOCK), "absent storage: the hook still injects");
    const second = coordEvent("ses_f", "msg_2");
    assert.equal(await runHandler(ha, second), null);
    assert.equal(second.prompt.text, "run the hourly board gate", "absent storage: per-instance once semantics hold (today's guard)");
    // The second instance has NO view of the first's in-memory map — the
    // documented fallback shape, red against a (wrongly) shared fallback.
    const b = fakeHandlerDeps({ agent: "agent-board-coord" });
    const hb = seam("createPromptHandler")(b.deps, { enabled: true });
    const third = coordEvent("ses_f", "msg_3");
    assert.equal(await runHandler(hb, third), null);
    assert.ok(third.prompt.text.includes(EXPECTED_BLOCK), "the in-memory fallback must stay per-process — sharing it would silently fix the wrong layer");
  });

  it("ignores a stale mark older than 6 h, removes it on encounter, and re-stamps fresh (C03 AC 3, TTL)", async () => {
    const stale = Date.now() - 7 * 60 * 60 * 1000;
    const storage = fakeStorage({ "once/ses_t": stale });
    const { deps, calls } = fakeHandlerDeps({ agent: "agent-board-coord", storage });
    const handler = seam("createPromptHandler")(deps, { enabled: true });
    const ev = coordEvent("ses_t", "msg_1");
    assert.equal(await runHandler(handler, ev), null);
    assert.ok(ev.prompt.text.includes(EXPECTED_BLOCK), "a stale mark does not block a fresh injection");
    assert.equal(calls.resolve.length, 1);
    assert.notEqual(storage.items["once/ses_t"], stale, "the stale mark was removed on encounter");
    assert.equal(typeof storage.items["once/ses_t"], "number", "and the fresh attempt re-consumed the mark");
  });
});

describe("S5 idempotence — a pasted block is never double-injected, and the scan marks durably (C03 re-pin)", () => {
  it("leaves a prompt already carrying the schema header untouched, no fetch, and marks the session in storage", async () => {
    const storage = fakeStorage();
    const { deps, calls } = fakeHandlerDeps({ agent: "agent-board-coord", storage });
    const handler = seam("createPromptHandler")(deps, { enabled: true });
    const pasted = coordEvent("ses_a", "msg_1", `schedule text\n${EXPECTED_BLOCK}`);
    const before = pasted.prompt.text;
    assert.equal(await runHandler(handler, pasted), null);
    assert.equal(pasted.prompt.text, before, "the header scan is the second belt after the once-guard");
    assert.equal(calls.resolve.length, 0, "no fetch when the block is already present");
    assert.equal(typeof storage.items["once/ses_a"], "number", "the scan marks WITHOUT injecting (pasted blocks and the refresh command's own reply ride it)");
    // Durability: a second instance honors the scan mark the first set.
    const b = fakeHandlerDeps({ agent: "agent-board-coord", storage });
    const hb = seam("createPromptHandler")(b.deps, { enabled: true });
    const next = coordEvent("ses_a", "msg_2");
    assert.equal(await runHandler(hb, next), null);
    assert.equal(next.prompt.text, "run the hourly board gate", "the header-scan mark must survive across handler instances");
    assert.equal(b.calls.resolve.length, 0);
  });
});

describe("S6 never-throw degrade — failing and hanging legs must not block admission (AC 4)", () => {
  it("a rejecting resolve leaves the prompt untouched, logs once, resolves — and STILL consumes the mark (ruling #5: consume-once-whether-successful)", async () => {
    const storage = fakeStorage();
    const { deps, calls } = fakeHandlerDeps({ agent: "agent-board-coord", resolveThrows: true, storage });
    const handler = seam("createPromptHandler")(deps, { enabled: true });
    const ev = coordEvent("ses_a", "msg_1");
    const err = await runHandler(handler, ev);
    assert.equal(err, null, `the hook must never reject — a rejection means the prompt is never admitted (${err})`);
    assert.equal(ev.prompt.text, "run the hourly board gate");
    assert.equal(calls.log.length, 1, `exactly one stderr line per failure, saw ${calls.log.length}`);
    assert.equal(typeof storage.items["once/ses_a"], "number",
      "a FAILED first attempt consumes the mark — re-firing the fetch on every later prompt would pay the 8 s budget per degraded prompt, and block absence is designed-normal (owner ruling #5)");
    const ev2 = coordEvent("ses_a", "msg_2");
    assert.equal(await runHandler(handler, ev2), null);
    assert.equal(calls.resolve.length, 1, "no re-fetch on the follow-up after a failed first attempt");
  });

  it("a rejecting session lookup degrades the same way (tolerant dual-read)", async () => {
    const { deps, calls } = fakeHandlerDeps({ getAgentThrows: true });
    const handler = seam("createPromptHandler")(deps, { enabled: true });
    const ev = coordEvent("ses_a", "msg_1");
    assert.equal(await runHandler(handler, ev), null);
    assert.equal(ev.prompt.text, "run the hourly board gate");
    assert.equal(calls.log.length, 1);
  });

  it("prefers event.agent and only falls back to the session lookup", async () => {
    const { deps, calls } = fakeHandlerDeps({ agent: "agent-coord" });
    const handler = seam("createPromptHandler")(deps, { enabled: true });
    const ev = { sessionID: "ses_a", messageID: "msg_1", agent: "agent-board-coord-pr", prompt: { text: "hi" } };
    await handler(ev);
    assert.equal(calls.getAgent.length, 0, "the dual-read must not pay a lookup when the event carries the agent");
    assert.ok(ev.prompt.text.includes(EXPECTED_BLOCK));
  });

  it("a garbage block (unknown board title) never injects", async () => {
    const { deps, calls } = fakeHandlerDeps({ agent: "agent-board-coord", resolveValue: "" });
    const handler = seam("createPromptHandler")(deps, { enabled: true });
    const ev = coordEvent("ses_a", "msg_1");
    assert.equal(await runHandler(handler, ev), null);
    assert.equal(ev.prompt.text, "run the hourly board gate");
    assert.equal(calls.log.length, 1);
  });

  // A hook whose fetch leg hangs blocks admission for the whole budget; the
  // bounded race inside the handler (not the transport's abort) is the guard
  // the offline fake exercises — the hanging resolve arm never settles on
  // purpose. TestContext.timeout is absent on this box's Node v26.5.0
  // (probed: typeof undefined), so the budget is a hand-raced watchdog below.
  it("settles within the fetch budget when the resolve leg hangs", async () => {
    const { deps, calls } = fakeHandlerDeps({ agent: "agent-board-coord", resolveHangs: true, fetchTimeoutMs: 30 });
    const handler = seam("createPromptHandler")(deps, { enabled: true });
    const ev = coordEvent("ses_a", "msg_1");
    const budgetMs = 5000;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const err = await Promise.race([
      runHandler(handler, ev).then((outcome) => {
        clearTimeout(timer);
        return outcome;
      }),
      new Promise<string>((resolve) => {
        timer = setTimeout(() => resolve("hang"), budgetMs);
      }),
    ]);
    assert.notEqual(err, "hang", `hook never settled within ${budgetMs}ms — a hanging leg stalls prompt admission (AC 4)`);
    assert.equal(err, null, "a hanging leg must resolve the hook, not stall it");
    assert.equal(ev.prompt.text, "run the hourly board gate");
    assert.equal(calls.log.length, 1);
  });

  it("ships a bounded production fetch budget (roughly 8 s, never unbounded)", () => {
    const ms = mod.FETCH_TIMEOUT_MS ?? mod.default?.FETCH_TIMEOUT_MS;
    assert.equal(typeof ms, "number", "FETCH_TIMEOUT_MS must be exported");
    assert.ok(ms >= 4000 && ms <= 15000, `FETCH_TIMEOUT_MS=${ms} is outside the admission-latency budget (RESEARCH: ~8 s, delays only the dispatch HTTP response)`);
  });
});

describe("S7 URL discovery — named-server match, config fallback, no credentials (AC 3)", () => {
  const BOARD_URL = "https://mcp.example.test/dev-boards/mcp";

  it("prefers a ctx.mcp.list hit for the dev-boards server", async () => {
    const url = await seam("resolveMcpUrl")({
      mcpList: async () => [{ name: "dev-playwright", url: "https://mcp.example.test/other/mcp" }, { name: "dev-boards", url: BOARD_URL }],
      readConfig: async () => null,
    });
    assert.equal(url, BOARD_URL);
  });

  it("falls back to parsing the project config, matching the named server only", async () => {
    const jsonc = `{
  "mcp": {
    "dev-playwright": { "type": "remote", "url": "https://mcp.example.test/playwright/mcp" },
    "dev-boards": { "type": "remote", "url": "${BOARD_URL}" }
  }
}`;
    const url = await seam("resolveMcpUrl")({
      mcpList: async () => [],
      readConfig: async () => jsonc,
    });
    assert.equal(url, BOARD_URL);
  });

  it("survives a throwing mcp.list via the config arm, and answers null with no source", async () => {
    const jsonc = `{ "mcp": { "dev-boards": { "url": "${BOARD_URL}" } } }`;
    const url = await seam("resolveMcpUrl")({ mcpList: async () => { throw new Error("catalog unavailable"); }, readConfig: async () => jsonc });
    assert.equal(url, BOARD_URL);
    const none = await seam("resolveMcpUrl")({ mcpList: async () => [], readConfig: async () => null });
    assert.equal(none, null, "no URL is the documented degrade, not an invented default");
  });

  it("carries no credentials and the plugin source hardcodes no ingress host (OIDC disabled — no token needed)", () => {
    const source = readFileSync(".opencode/plugin/board-context/index.ts", "utf8");
    for (const banned of ["mcp.dev.scifi.farm", "wekan.spencerslab.com", "WEKAN_TOKEN", "WEKAN_PASSWORD", "Authorization"]) {
      assert.ok(!source.includes(banned), `plugin source contains ${banned} — discovery must resolve at runtime and credentials never live in the plugin (wekan-mcp-ops.md: OIDC disabled on the wekan-mcp deployments)`);
    }
  });
});

describe("S8 result unwrap — structuredContent vs text double-parse (AC 2)", () => {
  const PAYLOAD = { boards: [{ id: "TNQJ2BrXenZovngTS", title: "AI-Dev" }] };

  it("both SSE frame shapes answer", () => {
    const parse = seam("parseSseData");
    const sse = parse(`event: message\ndata: {"jsonrpc":"2.0","id":1,"result":{"ok":true}}\n`);
    assert.deepEqual(sse, { jsonrpc: "2.0", id: 1, result: { ok: true } });
    assert.deepEqual(parse(`{"jsonrpc":"2.0","id":2,"result":{"ok":"plain"}}`), { jsonrpc: "2.0", id: 2, result: { ok: "plain" } });
    assert.equal(parse("no json here"), null, "an unparseable frame degrades to null, never throws");
  });

  it("structuredContent and a JSON-encoded text part yield the same payload", () => {
    const unwrap = seam("unwrapToolResult");
    const structured = unwrap({ result: { content: [{ type: "text", text: "unrelated" }], structuredContent: { result: PAYLOAD } } });
    const doubleParsed = unwrap({ result: { content: [{ type: "text", text: JSON.stringify(PAYLOAD) }] } });
    assert.deepEqual(structured, PAYLOAD);
    assert.deepEqual(doubleParsed, PAYLOAD);
  });
});

describe("S9 setup wiring — one prompt hook, the one refresh command, explicit enabled gate (C03 AC 4)", () => {
  // The S9 fakeCtx storage fake carries remove alongside get/set (C03: the
  // adapter needs all three) and stays tolerant — the plugin must never throw
  // on a partial storage surface.
  function fakeCtx() {
    const seen: any = { registrations: [], cmdSpecs: [] };
    const ctx: any = {
      session: {
        hook: async (name: string, handler: any) => {
          seen.registrations.push({ name, handler });
        },
        get: async () => undefined,
      },
      mcp: { list: async () => [] },
      location: { directory: "/tmp/opencode/board-context-no-config" },
      storage: fakeStorage(),
    };
    return { ctx, seen };
  }

  it("loads with the shipped default-export shape and registers exactly one prompt hook", async () => {
    assert.equal(typeof mod.default?.setup, "function", "the plugin must match the two shipped plugins' plain { id, setup } shape");
    assert.ok(typeof mod.default?.id === "string" && mod.default.id.length > 0);
    const { ctx, seen } = fakeCtx();
    const settled: any = await Promise.race([
      mod.default.setup(ctx),
      new Promise((resolve) => setTimeout(() => resolve("pending"), 1000)),
    ]);
    assert.notEqual(settled, "pending", "setup must return; a awaited-forever setup hangs plugin load");
    assert.equal(seen.registrations.length, 1, `exactly one hook registration, saw ${JSON.stringify(seen.registrations.map((r: any) => r.name))}`);
    assert.equal(seen.registrations[0].name, "prompt", "the hook must be the prompt-admission hook");
  });

  it("defaults follow DEFAULT_ENABLED — OFF until the live-fire proof is recorded in the source (AC 6 degraded outcome)", () => {
    const enabled = mod.DEFAULT_ENABLED ?? mod.default?.DEFAULT_ENABLED;
    assert.equal(typeof enabled, "boolean", "DEFAULT_ENABLED must be an explicit boolean gate");
    if (enabled === true) {
      const source = readFileSync(".opencode/plugin/board-context/index.ts", "utf8");
      assert.match(source, /live-fire/i, "shipping the hook ON requires the live-fire proof recorded in the source (AC 6); no half-broken hook stays on");
    }
  });

  it("the enabled:false arm never touches the prompt and never fetches", async () => {
    const { deps, calls } = fakeHandlerDeps({ agent: "agent-board-coord" });
    const handler = seam("createPromptHandler")(deps, { enabled: false });
    const ev = coordEvent("ses_a", "msg_1");
    assert.equal(await runHandler(handler, ev), null);
    assert.equal(ev.prompt.text, "run the hourly board gate");
    assert.equal(calls.resolve.length, 0);
    assert.equal(calls.log.length, 0, "the OFF arm is the shipped degrade path — silent, not an error log per prompt");
  });

  it("with no opts the handler behaves exactly like the shipped default", async () => {
    const { deps, calls } = fakeHandlerDeps({ agent: "agent-board-coord" });
    const handler = seam("createPromptHandler")(deps);
    const ev = coordEvent("ses_a", "msg_1");
    await handler(ev);
    const enabled = mod.DEFAULT_ENABLED ?? mod.default?.DEFAULT_ENABLED;
    assert.equal(calls.resolve.length, enabled ? 1 : 0, "default wiring must track DEFAULT_ENABLED in both eras");
    assert.equal(ev.prompt.text.includes(EXPECTED_BLOCK), Boolean(enabled));
  });

  it("registers the /reload-board-context command through ctx.command.transform when the host provides it (C03 AC 4)", async () => {
    const { ctx, seen } = fakeCtx();
    const cmdSeen: any = { specs: [] };
    ctx.command = {
      transform: async (fn: any) => void fn({ add: (s: any) => cmdSeen.specs.push(s) }),
    };
    const settled: any = await Promise.race([
      mod.default.setup(ctx),
      new Promise((resolve) => setTimeout(() => resolve("pending"), 1000)),
    ]);
    assert.notEqual(settled, "pending", "setup must return with the command surface");
    assert.equal(cmdSeen.specs.length, 1, `exactly one command spec registered, saw ${JSON.stringify(cmdSeen.specs.map((s: any) => s.name))}`);
    const spec = cmdSeen.specs[0];
    assert.equal(spec.name, "reload-board-context", "the command is the human-typed refresh surface (D30: never a loop-body one)");
    assert.equal(typeof spec.description, "string");
    assert.ok(spec.description.length > 0, "the spec carries its description (the catalog text)");
    assert.equal(typeof spec.execute, "function", "the spec carries its execute");
    assert.equal(seen.registrations.length, 1, "the command rides ctx.command.transform — the prompt hook count stays one");
  });

  it("degrades WITHOUT ctx.command.transform: setup settles, one prompt hook, exactly one stderr degrade line (C03 AC 4)", async () => {
    const { ctx, seen } = fakeCtx();
    const lines: string[] = [];
    const origError = console.error;
    console.error = (...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    };
    let threw: unknown = null;
    let settled: any;
    try {
      settled = await Promise.race([
        mod.default.setup(ctx),
        new Promise((resolve) => setTimeout(() => resolve("pending"), 1000)),
      ]);
    } catch (e) {
      threw = e;
    } finally {
      console.error = origError;
    }
    assert.equal(threw, null, `setup threw with no ctx.command.transform: ${threw}`);
    assert.notEqual(settled, "pending", "an absent transform must not hang plugin load");
    assert.equal(seen.registrations.length, 1, "still exactly one prompt hook when the command degrades");
    const degrade = lines.filter((l) => /command|reload/i.test(l));
    assert.equal(degrade.length, 1, `exactly one stderr degrade line names the missing command surface, saw ${JSON.stringify(lines)}`);
  });
});

describe("C03 /reload-board-context — the executor answers through session.prompt (C03 AC 5)", () => {
  // The loopback MCP stub (card-details.test.ts startBoardStub shape): the
  // setup-level arms run the REAL resolve path (six legs over JSON-RPC)
  // against in-process answers — no external network.
  async function startBoardStub(answers: Record<string, any>) {
    const reads: Array<{ name: string; args: any }> = [];
    const server: Server = createServer((req, res) => {
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", () => {
        const rpc = JSON.parse(body || "{}");
        const reply = (payload: any) => {
          res.writeHead(200, { "content-type": "application/json" });
          res.end(JSON.stringify({ jsonrpc: "2.0", id: rpc.id ?? 0, ...payload }));
        };
        if (rpc.method === "initialize" || String(rpc.method).startsWith("notifications/")) {
          res.writeHead(200, { "content-type": "application/json", "mcp-session-id": "test-session" });
          res.end(JSON.stringify({ jsonrpc: "2.0", id: rpc.id ?? 0, result: {} }));
          return;
        }
        if (rpc.method === "tools/call") {
          reads.push({ name: rpc.params?.name, args: rpc.params?.arguments });
          const payload = answers[rpc.params?.name];
          reply(payload === undefined
            ? { result: { isError: true, content: [{ type: "text", text: `stub has no answer for ${rpc.params?.name}` }] } }
            : { result: { structuredContent: { result: payload } } });
          return;
        }
        reply({ error: { code: -32601, message: `unexpected method ${rpc.method}` } });
      });
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const { port } = server.address() as AddressInfo;
    return {
      url: `http://127.0.0.1:${port}/mcp`,
      reads,
      close: () => {
        server.closeAllConnections?.();
        return new Promise<void>((resolve) => server.close(() => resolve()));
      },
    };
  }

  function setupCtx(opts: { url: string; storage?: any }) {
    const seen: any = { handlers: [], cmdSpecs: [], prompts: [] };
    const ctx: any = {
      location: { directory: process.cwd() },
      mcp: { list: async () => [{ name: "dev-boards", url: opts.url }] },
      session: {
        get: async () => ({ agent: "agent-board-coord" }),
        hook: async (name: string, handler: any) => {
          seen.handlers.push({ name, handler });
        },
        prompt: async (arg: any) => {
          seen.prompts.push(arg);
        },
      },
      tool: { hook: async () => {} },
      storage: opts.storage,
    };
    ctx.command = {
      transform: async (fn: any) => void fn({ add: (s: any) => seen.cmdSpecs.push(s) }),
    };
    return { ctx, seen };
  }

  it("success: one reply carrying the fresh block; the reply's header scan marks the session and a following plain prompt stays clean", async () => {
    const stub = await startBoardStub(SIX_LEG_ANSWERS);
    const storage = fakeStorage();
    const { ctx, seen } = setupCtx({ url: stub.url, storage });
    try {
      await mod.default.setup(ctx);
      const spec = seen.cmdSpecs.find((s: any) => s.name === "reload-board-context");
      assert.ok(spec, "setup must register the reload-board-context command spec");
      assert.equal(seen.handlers.length, 1, "exactly one prompt hook registration");
      const handler = seen.handlers[0].handler;

      await spec.execute({ sessionID: "ses_x" });
      assert.equal(seen.prompts.length, 1, "the reply rides ctx.session.prompt exactly once (the pipeline-locks say pattern)");
      assert.equal(seen.prompts[0].sessionID, "ses_x", "the reply posts on the invocation's own envelope");
      const text = String(seen.prompts[0].text);
      const headerAt = text.indexOf("Board context (collected");
      assert.ok(headerAt >= 0, `the reply must carry the block for the hook's header scan to mark the session, got ${JSON.stringify(text.slice(0, 160))}`);
      const expectedRest = EXPECTED_BLOCK.slice(EXPECTED_BLOCK.indexOf("\n"));
      assert.ok(text.slice(headerAt).endsWith(expectedRest), "the reply's block body is the re-pinned fence byte-for-byte (only the collection stamp is fresh)");
      assert.equal(stub.reads.length, 6, "the refresh fetches through the same six-leg resolve path");

      // The host dispatches the synthetic reply through the prompt hook: the
      // header scan marks WITHOUT injecting (the reply already carries it).
      assert.ok(!("once/ses_x" in storage.items), "the executor itself must not pre-mark — the mark lands on the reply's header scan");
      const replyEvent = { sessionID: "ses_x", messageID: "m_reply", prompt: { text } };
      assert.equal(await runHandler(handler, replyEvent), null);
      assert.equal(replyEvent.prompt.text, text, "the reply is never double-injected");
      assert.equal(typeof storage.items["once/ses_x"], "number", "the reply's header scan marked the session durably");

      // And a following plain prompt stays clean: no re-inject, no re-fetch.
      const plain = coordEvent("ses_x", "m_plain");
      assert.equal(await runHandler(handler, plain), null);
      assert.equal(plain.prompt.text, "run the hourly board gate", "a plain prompt after a successful refresh must not re-inject the block");
      assert.equal(stub.reads.length, 6, "and must not re-fetch the board");
    } finally {
      await stub.close();
    }
  });

  it("failure: one-line reply, the mark stays untouched, and it never throws (C03 AC 5)", async () => {
    const stub = await startBoardStub({}); // no answers: the first leg degrades
    const storage = fakeStorage();
    const { ctx, seen } = setupCtx({ url: stub.url, storage });
    try {
      await mod.default.setup(ctx);
      const spec = seen.cmdSpecs.find((s: any) => s.name === "reload-board-context");
      assert.ok(spec, "setup must register the reload-board-context command spec");
      let threw: unknown = null;
      try {
        await spec.execute({ sessionID: "ses_f" });
      } catch (e) {
        threw = e;
      }
      assert.equal(threw, null, `the command must never throw, got ${threw}`);
      assert.equal(seen.prompts.length, 1, "a failed refresh still answers — the human typed the command, and silence is not an answer");
      const text = String(seen.prompts[0].text);
      assert.ok(text.length > 0 && !text.includes("\n"), `the failure reply is one line, got ${JSON.stringify(text)}`);
      assert.ok(!text.includes("Board context (collected"), "no half-shaped block in the failure reply");
      assert.ok(!("once/ses_f" in storage.items), "a failed fetch leaves the mark untouched — the session's first prompt still gets its own attempt (consume-once belongs to the PROMPT hook, ruling #5)");
    } finally {
      await stub.close();
    }
  });
});

// C03 (2026/2026-10-chore-board-tick-cleanup) shipped the enable-as-is decision;
// cf-123 C01 IS the deferred follow-up it pointed at — the block gains the
// per-list cards group from ONE extra preload leg. These arms are the
// deliberate inversion of the old scope guards: they pin the NEW scope, and
// the list_cards_in_list ban STAYS because Option 1 assembles from
// preload_board, never the by-list projection (WeKan strips cardNumber/
// labelIds there server-side).
describe("S10 scope guards — INVERTED for cf-123 (C01 AC 2; the old cards-absence arm is retired on purpose)", () => {
  const PLUGIN = ".opencode/plugin/board-context/index.ts";

  it("carries the cards: projection the enable-as-is era deferred (the presence arm — the inversion of the old absence pin)", () => {
    const source = readFileSync(PLUGIN, "utf8");
    assert.ok((source.match(/cards:/g) ?? []).length >= 1,
      "the plugin source lost the cards: section marker — cf-123 C01 ships the per-list cards; re-pinned deliberately, never weakened back to the absence shape");
  });

  it("lists the six resolution legs it internalizes, preload_board included — and still bans list_cards_in_list", () => {
    const source = readFileSync(PLUGIN, "utf8");
    for (const leg of ["list_boards", "get_board", "list_swimlanes", "list_lists", "list_custom_fields", "preload_board"]) {
      assert.ok(source.includes(leg), `leg ${leg} vanished — the shipped six-leg structure+cards prefetch is the enabled surface`);
    }
    assert.ok(!source.includes("list_cards_in_list"),
      "list_cards_in_list joined the prefetch — WeKan's by-list endpoint strips cardNumber/labelIds server-side; the cards come from preload_board's whole-board export (Option 1, the plan's MCP-tool evaluation)");
  });

  it("an ON constant only ships with the live-fire runbook citation beside it (era arm, unchanged)", () => {
    const enabled = mod.DEFAULT_ENABLED ?? mod.default?.DEFAULT_ENABLED;
    if (enabled !== true) return; // OFF era: nothing to certify yet
    const source = readFileSync(".opencode/plugin/board-context/index.ts", "utf8");
    assert.match(source, /live-fire 2026-\d\d-\d\dT/,
      "the flip needs the runbook-shaped proof citation (C03 Citation line: 'live-fire <stamp> (worktree probes)') — no half-proven hook ships on");
    assert.match(source, /worktree probes/,
      "the citation must claim exactly what ran: worktree-instance evidence, not main-checkout proof (C03 Notes for dev: do not claim location proof the run never had)");
  });
});

describe("cf-96 C09 zone coverage — the collection stamp header in both geometries (AC3)", () => {
  it("stamps local-with-offset when $TZ resolves and UTC Z when it does not (cf-96 AC3)", () => {
    const STAMP_SHAPE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(?:Z|[+-]\d{2}:\d{2})$/;
    // The shape's own anchors must not survive embedding mid-pattern.
    const headerRe = new RegExp(`^Board context \\(collected ${STAMP_SHAPE.source.slice(1, -1)}, dev-boards\\)$`);
    const savedTZ = process.env.TZ;
    try {
      process.env.TZ = "America/Denver";
      assert.match(seam("formatBlock")({ ...FIELDS, collectedAt: localIso() }).split("\n")[0], headerRe,
        "the offset stamp keeps the header sentence true — an offset IS ISO-8601 (C09 T2)");
      delete process.env.TZ;
      assert.match(seam("formatBlock")({ ...FIELDS, collectedAt: localIso() }).split("\n")[0], headerRe,
        "$TZ unset: the Z-fallback stamp renders the same header shape");
    } finally {
      if (savedTZ === undefined) delete process.env.TZ; else process.env.TZ = savedTZ;
    }
  });
});
