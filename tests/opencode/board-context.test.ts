// C04 acceptance checks (2026/2026-10-cf-75-bug-wekan-mcp-skill): the
// board-context prefetch plugin's test seam — formatBlock / resolveBoardContext
// / createPromptHandler / isBoardCoordAgent / resolveMcpUrl / unwrapToolResult
// / parseSseData plus the exported FETCH_TIMEOUT_MS and DEFAULT_ENABLED — and
// the single prompt-hook registration in setup. Covers chunks/C04.md AC 1-4
// and AC 6's degrade gate shape; AC 5's question-notify sibling run and the
// live-fire readback are plan Commands / dev-run duties, not this file.
//
// Run from the repo root: node --test tests/opencode/board-context.test.ts
// (Node v26 type-strips the .ts directly; no build step, no npm deps, no
// network — the fakes below are the only collaborators.)
//
// This file lives in the repo-root tests/ tree, deliberately NOT under
// .opencode/: plugin discovery loads every .ts it scans there, so a test file
// inside the plugin dir would be imported as a plugin entry at server startup
// (the question-notify.test.ts convention this suite copies).
//
// Red before C04: the module does not exist yet, so the import below fails
// the whole file with ERR_MODULE_NOT_FOUND — an honest structural red naming
// the missing implementation, never a broken harness.
//
// SEAM CONTRACT (what dev must export from .opencode/plugin/board-context/index.ts):
//   formatBlock(fields) -> string                       fields = { collectedAt,
//     serverId, boardId, swimlaneId, lists, customFields, labels }; the list
//     arrays carry {name, id} entries; pure, no clock read.
//   resolveBoardContext(deps, opts) -> Promise<string>  deps = { callTool(name,
//     args) }; opts = { boardTitle, swimlaneTitle, serverId, collectedAt };
//     runs list_boards -> get_board -> list_swimlanes -> list_lists ->
//     list_custom_fields, filters lists by swimlane id, maps the custom-field
//     `name` key (NOT title), formats via formatBlock.
//   createPromptHandler(deps, opts?) -> (event) => Promise<void>
//     deps = { getAgent(sessionID), resolve(serverId), log(message),
//     fetchTimeoutMs? }; opts = { enabled? } defaulting to DEFAULT_ENABLED;
//     agent read = event.agent with a getAgent fallback (the tolerant
//     question-notify shape — the prompt event carries no agent field).
//   isBoardCoordAgent(agent) -> boolean; BOARD_COORD_AGENTS: string[].
//   resolveMcpUrl(deps) -> Promise<string|null>         deps = { mcpList(),
//     readConfig() }; named-server match, no credentials.
//   unwrapToolResult(rpcBody) -> any; parseSseData(text) -> any|null.
//   FETCH_TIMEOUT_MS: number (the admission-latency budget); DEFAULT_ENABLED:
//   boolean; default export { id, setup } matching the two shipped plugins'
//   working shape (plain object with async setup(ctx), NOT the docs'
//   Plugin.define). setup registers exactly one ctx.session.hook("prompt", ...).
//
// The EXPECTED block below transcribes the C01 canonical schema with the
// plan's verified-fact ids; skill-surface.sh t3 pins the schema's single
// markdown owner. If C01's skill text drifts from this transcription, this
// suite fails on a real two-owners drift — the fix is adjudicated through the
// C02 validation-fix route, never by weakening the constant.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import * as plugin from "../../.opencode/plugin/board-context/index.ts";

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

// Verified facts 2026-10-27 (live dev-boards probe) from the plan file —
// the Test list is inside the In Process swimlane, so a swimlane filter
// keeps it: the collector reports board structure, not the pipeline ideal.
const EXPECTED_BLOCK = [
  `Board context (collected ${COLLECTED_AT}, ${SERVER_ID})`,
  "board_id: TNQJ2BrXenZovngTS",
  "swimlane_id: jLzy39L7djCRr67SF",
  "lists: Not Started=XhDyShvuwhGWzWH2z, Executing=qZ9CLZqCRbv7NQQ6R, Review=2B6wWGJ8Tetp5QWDJ, Rework=y9tsvb3AguKWhzCoF, Finished=DHw56fMKy3qyfudz4, Low Priority=M4JS9LfaypJbB97At, Test=jNYNdCPPkX8Bs95s4",
  "custom_fields: slug=RaNeqvh9YoT4bnkZ8, session=zZw4PwMoLeodJy3eT",
  "labels: Research=ysSmS5, Ready for Work=mkbxeo",
  "card and checklist ids are never pre-collected — they stay live",
].join("\n");

const FIELDS = {
  collectedAt: COLLECTED_AT,
  serverId: SERVER_ID,
  boardId: "TNQJ2BrXenZovngTS",
  swimlaneId: "jLzy39L7djCRr67SF",
  lists: [
    { name: "Not Started", id: "XhDyShvuwhGWzWH2z" },
    { name: "Executing", id: "qZ9CLZqCRbv7NQQ6R" },
    { name: "Review", id: "2B6wWGJ8Tetp5QWDJ" },
    { name: "Rework", id: "y9tsvb3AguKWhzCoF" },
    { name: "Finished", id: "DHw56fMKy3qyfudz4" },
    { name: "Low Priority", id: "M4JS9LfaypJbB97At" },
    { name: "Test", id: "jNYNdCPPkX8Bs95s4" },
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
// (server.py _slim_*): lists/swimlanes/boards key on `title`, custom fields
// and labels key on `name` — the mapping asymmetry this suite pins.
const LISTS_PROJECTION = [
  ...FIELDS.lists.map((l, i) => ({ id: l.id, title: l.name, swimlane_id: "jLzy39L7djCRr67SF" })),
  { id: "FARMONLY000000001", title: "Backlog", swimlane_id: "FARM-SWIM-0001" },
];

function fakeCallTool(opts: any = {}) {
  const calls: any[] = [];
  const callTool = async (name: string, args: any) => {
    calls.push({ name, args });
    if (opts.throwOn === name) throw new Error(`tools/call ${name} failed`);
    switch (name) {
      case "list_boards":
        return [{ id: "OTHERBOARD000001", title: "Farm Ops" }, { id: "TNQJ2BrXenZovngTS", title: "AI-Dev" }];
      case "get_board":
        return {
          id: "TNQJ2BrXenZovngTS",
          title: "AI-Dev",
          labels: [
            { id: "ysSmS5", name: "Research", color: "red" },
            { id: "mkbxeo", name: "Ready for Work", color: "green" },
          ],
        };
      case "list_swimlanes":
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
      default:
        throw new Error(`unexpected tool call ${name}`);
    }
  };
  return { callTool, calls };
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
describe("S1 formatBlock — one formatter, byte-exact schema (AC 2)", () => {
  it("emits the schema block byte-for-byte for the verified-fact fields", () => {
    assert.equal(seam("formatBlock")(FIELDS), EXPECTED_BLOCK);
  });

  it("is pure: the collected stamp comes from the input, never a clock read", () => {
    const changed = seam("formatBlock")({ ...FIELDS, collectedAt: "2026-11-01T00:00:00Z", serverId: "admin-global-wekan" });
    assert.ok(changed.startsWith("Board context (collected 2026-11-01T00:00:00Z, admin-global-wekan)"), changed.split("\n")[0]);
    assert.equal(changed.slice(changed.indexOf("\n")), EXPECTED_BLOCK.slice(EXPECTED_BLOCK.indexOf("\n")));
  });

  it("cross-checks the C01 schema owner carries the same header text", () => {
    // By C04 review time C01 has landed (wave 1 dependency), so an absent or
    // divergent skill is drift between the schema's two homes — loud, not
    // skipped.
    const skill = readFileSync("skills/wekan-mcp/SKILL.md", "utf8");
    assert.ok(skill.includes("Board context (collected"), "SKILL.md lost the canonical schema header");
    for (const label of ["board_id", "swimlane_id", "custom_fields", "labels"]) {
      assert.ok(skill.includes(label), `SKILL.md schema no longer names the ${label} field`);
    }
  });
});

describe("S2 resolveBoardContext — resolution sequence and projections (AC 2, AC 3)", () => {
  it("runs the five calls and formats the swimlane-filtered block", async () => {
    const { callTool, calls } = fakeCallTool();
    const block = await seam("resolveBoardContext")(
      { callTool },
      { boardTitle: "AI-Dev", swimlaneTitle: "In Process", serverId: SERVER_ID, collectedAt: COLLECTED_AT },
    );
    assert.equal(block, EXPECTED_BLOCK);
    assert.deepEqual(
      calls.map((c) => c.name),
      ["list_boards", "get_board", "list_swimlanes", "list_lists", "list_custom_fields"],
      "the collector sequence is the C01 skill's resolution order",
    );
  });

  it("maps custom fields by name and lists by title, and drops other swimlanes", async () => {
    const { callTool } = fakeCallTool();
    const block = await seam("resolveBoardContext")(
      { callTool },
      { boardTitle: "AI-Dev", swimlaneTitle: "In Process", serverId: SERVER_ID, collectedAt: COLLECTED_AT },
    );
    assert.ok(!block.includes("FARMONLY000000001"), "a Farm-swimlane list leaked into the In Process block");
    assert.ok(block.includes("slug=RaNeqvh9YoT4bnkZ8"), "custom fields must key on the name field");
    assert.ok(block.includes("Not Started=XhDyShvuwhGWzWH2z"), "lists must map title=name, id=id");
  });

  it("propagates a mid-sequence tool failure so the caller degrades", async () => {
    const { callTool } = fakeCallTool({ throwOn: "list_swimlanes" });
    await assert.rejects(
      seam("resolveBoardContext")(
        { callTool },
        { boardTitle: "AI-Dev", swimlaneTitle: "In Process", serverId: SERVER_ID, collectedAt: COLLECTED_AT },
      ),
    );
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

describe("S4 once-guard — per sessionID, never per messageID (AC 1)", () => {
  // RESEARCH.md matrix "Retries": the command path mints a fresh messageID
  // per attempt and server id-dedup never sees it, so a message-id guard
  // would silently re-inject on every retry. The guard must key the session.
  it("injects once per session even when each attempt carries a fresh messageID", async () => {
    const { deps, calls } = fakeHandlerDeps({ agent: "agent-board-coord" });
    const handler = seam("createPromptHandler")(deps, { enabled: true });
    const first = coordEvent("ses_a", "msg_1");
    const second = coordEvent("ses_a", "msg_2");
    assert.equal(await runHandler(handler, first), null);
    assert.ok(first.prompt.text.endsWith(`\n\n${EXPECTED_BLOCK}`), "first prompt gets \\n\\n + block appended after the expanded gate text");
    assert.ok(first.prompt.text.startsWith("run the hourly board gate"), "append must keep the original prompt a byte-exact prefix (stale-offset rule)");
    assert.equal(await runHandler(handler, second), null);
    assert.equal(second.prompt.text, "run the hourly board gate", "fresh messageID must not defeat the per-session guard");
    assert.equal(calls.resolve.length, 1, `one board fetch per session, saw ${calls.resolve.length}`);
  });

  it("keeps the guard per-session: a different session still gets its block", async () => {
    const { deps } = fakeHandlerDeps({ agent: "agent-board-coord" });
    const handler = seam("createPromptHandler")(deps, { enabled: true });
    const a = coordEvent("ses_a", "msg_1");
    const b = coordEvent("ses_b", "msg_2");
    await handler(a);
    assert.equal(await runHandler(handler, b), null);
    assert.ok(b.prompt.text.includes(EXPECTED_BLOCK), "the guard must not be global");
  });

  it("skips non-coord sessions without consuming their once-slot", async () => {
    const { deps, calls } = fakeHandlerDeps({ agent: "agent-coord" });
    const handler = seam("createPromptHandler")(deps, { enabled: true });
    const plain = coordEvent("ses_p", "msg_1");
    assert.equal(await runHandler(handler, plain), null);
    assert.equal(plain.prompt.text, "run the hourly board gate");
    assert.equal(calls.resolve.length, 0, "a non-coord session must never be fetched for");
  });
});

describe("S5 idempotence — a pasted block is never double-injected (AC 2)", () => {
  it("leaves a prompt already carrying the schema header untouched", async () => {
    const { deps, calls } = fakeHandlerDeps({ agent: "agent-board-coord" });
    const handler = seam("createPromptHandler")(deps, { enabled: true });
    const pasted = coordEvent("ses_a", "msg_1", `schedule text\n${EXPECTED_BLOCK}`);
    const before = pasted.prompt.text;
    assert.equal(await runHandler(handler, pasted), null);
    assert.equal(pasted.prompt.text, before, "the header scan is the second belt after the once-guard");
    assert.equal(calls.resolve.length, 0, "no fetch when the block is already present");
  });
});

describe("S6 never-throw degrade — failing and hanging legs must not block admission (AC 4)", () => {
  it("a rejecting resolve leaves the prompt untouched, logs once, and resolves", async () => {
    const { deps, calls } = fakeHandlerDeps({ agent: "agent-board-coord", resolveThrows: true });
    const handler = seam("createPromptHandler")(deps, { enabled: true });
    const ev = coordEvent("ses_a", "msg_1");
    const err = await runHandler(handler, ev);
    assert.equal(err, null, `the hook must never reject — a rejection means the prompt is never admitted (${err})`);
    assert.equal(ev.prompt.text, "run the hourly board gate");
    assert.equal(calls.log.length, 1, `exactly one stderr line per failure, saw ${calls.log.length}`);
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
  // the offline fake exercises — resolveNever above never settles on purpose.
  it("settles within the fetch budget when the resolve leg hangs", async (t) => {
    t.timeout(5000);
    const { deps, calls } = fakeHandlerDeps({ agent: "agent-board-coord", resolveHangs: true, fetchTimeoutMs: 30 });
    const handler = seam("createPromptHandler")(deps, { enabled: true });
    const ev = coordEvent("ses_a", "msg_1");
    const err = await runHandler(handler, ev);
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

describe("S9 setup wiring — one prompt hook, explicit enabled gate (AC 1, AC 6)", () => {
  function fakeCtx() {
    const seen: any = { registrations: [] };
    const ctx = {
      session: {
        hook: async (name: string, handler: any) => {
          seen.registrations.push({ name, handler });
        },
        get: async () => undefined,
      },
      mcp: { list: async () => [] },
      location: { directory: "/tmp/opencode/board-context-no-config" },
      storage: {
        items: new Map(),
        get: async (_k: string, d: any) => d,
        set: async (_k: string, _v: any) => {},
      },
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
});
