// cf-106 C07 acceptance checks (2026/2026-11-cf-106-feat-coord-fixes): the
// claim-time single-card preload leg of the board-context plugin. Covers
// chunks/C07.md AC3 (hook predicate matrix), AC4 (the prompt-hook path stays
// untouched), the formatter half of AC5 (one block format, doc and plugin in
// parity), and the degrade law.
//
// Run from the repo root: node --test tests/opencode/card-details.test.ts
// (Node type-strips the .ts directly; no build step, no npm deps, no network.
// Every collaborator below is a fake.)
//
// Lives in the repo-root tests/ tree, NOT under .opencode/ — plugin discovery
// loads every .ts it scans there, so a test file inside the plugin dir would be
// imported as a plugin entry at server startup (the board-context.test.ts and
// question-notify.test.ts convention).
//
// SEAM CONTRACT (what dev must export from .opencode/plugin/board-context/index.ts
// for this chunk; every arm fails with the name of the missing piece, so a red
// file points straight at the gap):
//   CARD_DETAILS_TOOL: string                          the tool this leg calls
//                                                      ("get_card_details").
//   CARD_DETAILS_BUDGET_MS: number                     its OWN budget, a value
//                                                      distinct from FETCH_TIMEOUT_MS
//                                                      (the 8 s prompt-hook budget
//                                                      stays untouched — AC4).
//   formatCardBlock(payload, opts?) -> string          payload = the
//     get_card_details response; opts = { collectedAt }. Pure, no clock read;
//     the footer names the tool so a stale block is visible.
//   createClaimHandler(deps, opts?) -> (event) => Promise<string | undefined>
//     deps = { callTool(name, args), getAgent(sessionID), log(message),
//              budgetMs? (defaults to CARD_DETAILS_BUDGET_MS) };
//     event = { agent, tool, args, result, sessionID }.
//     Returns the claim answer with the formatted block appended when the leg
//     applies, undefined when it does not; never throws; at most one card read
//     per claimed card.
//   default.setup(ctx) registers ctx.tool.hook("execute.after", …) and writes
//     the amended text back to event.result.content — the only path by which
//     the block reaches the model. The "live wiring" arms below drive that
//     registration, so the seam arms cannot go green on an unregistered leg.
//
// The doc-parity arm compares skills/wekan-mcp/SKILL.md's example block against
// the bytes the loaded plugin actually appends to a claim answer, so it pins
// the doc↔output relation without naming the plugin's formatter.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createServer, type Server, type AddressInfo } from "node:http";

import * as plugin from "../../.opencode/plugin/board-context/index.ts";

const CLAIM_TOOL = "tools.pipeline_claim";
const CARD_ID = "Q8yGpKx3mZtLwRbNf";
const AGENTS = ["agent-board-coord", "agent-board-coord-local", "agent-board-coord-pr"];

const PAYLOAD = {
  id: CARD_ID,
  card_number: 106,
  title: "feat: coord fixes",
  description: "the plan of record",
  list_id: "L1",
  swimlane_id: "S1",
  archived: false,
  sort: 12,
  parent_id: null,
  label_ids: ["lbl-1"],
  labels: { "lbl-1": "Pipeline: default" },
  custom_fields: { slug: "[cf-106-feat-coord-fixes](http://oc/s/1)" },
  slug_stack: ["cf-106-feat-coord-fixes"],
  current_slug: "cf-106-feat-coord-fixes",
  checklists: [
    { id: "cl-1", title: "Lifecycle", items: [{ title: "Plan", finished: true }, { title: "Dev", finished: false }] },
    { id: "cl-2", title: "Human in the Loop", items: [] },
  ],
  dependencies: [{ to_id: "other-card", type: "blocks", color: "red" }],
};

function cardBlockSection(doc: string): string | null {
  // JS has no inline regex flags: walk the headings instead (and the section
  // is a markdown heading, so line scanning is the honest reader).
  const lines = doc.split("\n");
  const at = lines.findIndex((l) => /^#{2,3}\s.*Card details block/i.test(l));
  if (at < 0) return null;
  const rest = lines.slice(at + 1);
  const next = rest.findIndex((l) => /^#{2,3}\s/.test(l));
  return (next < 0 ? rest : rest.slice(0, next)).join("\n");
}

function seam(name: string): any {
  return (plugin as any)[name];
}

function requireSeam(...names: string[]): void {
  const missing = names.filter((n) => seam(n) === undefined);
  if (missing.length) {
    assert.fail(`the plugin does not export ${missing.join(", ")} — the C07 claim-time leg has not landed (designed red before C07 dev, not a harness fault)`);
  }
}

function claimEvent(agent: string, result: unknown, cardId = CARD_ID) {
  return { agent, tool: CLAIM_TOOL, args: { cardId }, result, sessionID: "ses_test" };
}

function harness(opts: { claim?: string; agent?: string; cardId?: string; callTool?: (name: string, args: any) => any; budgetMs?: number } = {}) {
  requireSeam("createClaimHandler", "formatCardBlock", "CARD_DETAILS_TOOL");
  const logs: string[] = [];
  const calls: Array<[string, any]> = [];
  const deps = {
    callTool: opts.callTool ?? (async (name: string, args: any) => { calls.push([name, args]); return PAYLOAD; }),
    getAgent: async () => opts.agent ?? "agent-board-coord",
    log: (m: string) => logs.push(m),
    budgetMs: opts.budgetMs,
  };
  const handler = seam("createClaimHandler")(deps, {});
  const run = async (result = opts.claim ?? "lock held") =>
    handler(claimEvent(opts.agent ?? "agent-board-coord", result, opts.cardId));
  return { handler, run, calls, logs };
}

describe("seam presence (the contract this file pins)", () => {
  it("exports the card-details tool name, its own budget constant, the formatter and the claim handler", () => {
    requireSeam("CARD_DETAILS_TOOL", "CARD_DETAILS_BUDGET_MS", "formatCardBlock", "createClaimHandler");
    assert.equal(typeof seam("CARD_DETAILS_TOOL"), "string");
    assert.equal(seam("CARD_DETAILS_TOOL"), "get_card_details", "the leg must call the tool C07 adds, by name");
    assert.ok(Number.isFinite(seam("CARD_DETAILS_BUDGET_MS")) && seam("CARD_DETAILS_BUDGET_MS") > 0,
      "CARD_DETAILS_BUDGET_MS must be a positive number");
  });

  it("keeps its budget independent of the prompt-hook budget (AC4)", () => {
    requireSeam("CARD_DETAILS_BUDGET_MS");
    assert.notEqual(seam("CARD_DETAILS_BUDGET_MS"), (plugin as any).FETCH_TIMEOUT_MS,
      "the claim-time leg shares the 8 s prompt-hook budget — C07 requires its own constant so the prompt prefetch stays untouched");
  });
});

describe("predicate matrix — when the leg fires", () => {
  for (const agent of AGENTS) {
    it(`fires for a successful claim from ${agent}`, async () => {
      const h = harness({ agent });
      const out = await h.run("lock held for cf-106");
      assert.ok(typeof out === "string", `${agent}: a successful claim must come back amended (got ${typeof out})`);
      assert.ok(out!.startsWith("lock held for cf-106"), `${agent}: the claim answer must be preserved as the prefix`);
      assert.equal(h.calls.length, 1, `${agent}: expected exactly one get_card_details call`);
      assert.equal(h.calls[0][0], "get_card_details");
      assert.equal(h.calls[0][1].card_id ?? h.calls[0][1].cardId, CARD_ID, "the card read must address the claimed card");
    });
  }

  const refusals: Array<[string, unknown]> = [
    ["a failed claim", { ok: false, reason: "occupied" }],
    ["a locked claim", { ok: false, reason: "locked" }],
    ["an already-held claim", { ok: false, reason: "already_held" }],
    ["a null answer", null],
    ["a no-card claim", { ok: true, reason: "no_work" }],
  ];
  for (const [label, result] of refusals) {
    it(`does NOT fire on ${label}`, async () => {
      const h = harness();
      const out = await h.run(result as any);
      assert.equal(out, undefined, `${label}: the claim answer must be returned unmodified`);
      assert.equal(h.calls.length, 0, `${label}: the card read must not be issued`);
    });
  }

  it("does NOT fire for a non-board-coord agent", async () => {
    const h = harness({ agent: "agent-coord-local" });
    const out = await h.run("lock held");
    assert.equal(out, undefined, "a non-board family session must not get the block");
    assert.equal(h.calls.length, 0);
  });

  it("does NOT fire twice for the same claimed card", async () => {
    const h = harness();
    const first = await h.run("lock held");
    const second = await h.run("heartbeat");
    assert.ok(typeof first === "string", "the first claim must be amended");
    assert.equal(second, undefined, "a second event for the same cardId must not re-read the card");
    assert.equal(h.calls.length, 1, "the card read is once per claimed card");
  });
});

describe("degrade law — never throw, never hang, answer untouched", () => {
  it("returns the claim answer unmodified and logs one line when the card read throws", async () => {
    const h = harness({
      callTool: async () => {
        throw new Error("connection refused");
      },
    });
    const out = await h.run("lock held");
    assert.equal(out, undefined, "a failed card read must leave the claim answer byte-unchanged");
    assert.equal(h.logs.length, 1, `a degrade must log exactly one stderr line (got ${JSON.stringify(h.logs)})`);
  });

  it("returns the claim answer unmodified when the tool is absent from the catalog", async () => {
    const h = harness({
      callTool: async () => {
        throw new Error("tool not found");
      },
    });
    const out = await h.run("lock held");
    assert.equal(out, undefined);
    assert.equal(h.logs.length, 1, "the absent-tool branch degrades with one note, like the preload law");
  });

  it("gives up on a card read that outruns its own budget", async () => {
    const h = harness({
      budgetMs: 20,
      callTool: () => new Promise((resolve) => setTimeout(() => resolve(PAYLOAD), 5_000)),
    });
    const started = Date.now();
    const out = await h.run("lock held");
    const elapsed = Date.now() - started;
    assert.equal(out, undefined, "a budget breach must degrade, never stall the claim answer");
    assert.ok(elapsed < 1_000, `the leg waited ${elapsed} ms — the budget must bound it (CARD_DETAILS_BUDGET_MS is the default)`);
    assert.equal(h.logs.length, 1, "the breach is reported once on stderr");
  });
});

describe("the block format has one home (AC5)", () => {
  it("appends exactly what the formatter produces for the fixture payload", async () => {
    requireSeam("formatCardBlock", "createClaimHandler");
    const h = harness();
    const out = await h.run("lock held");
    const block = seam("formatCardBlock")(PAYLOAD);
    assert.ok(typeof out === "string" && out!.endsWith(block),
      "the appended block must equal the formatter's output byte-for-byte (the plugin never re-formats)");
    assert.match(block, /get_card_details/, "the footer names the tool so a stale block is visible");
    assert.match(block, /Lifecycle/, "the block carries the checklist state");
    assert.match(block, /cf-106-feat-coord-fixes/, "the block carries the parsed slug stack");
  });

  it("matches the field lines of the single doc home in skills/wekan-mcp/SKILL.md", async () => {
    const doc = readFileSync("skills/wekan-mcp/SKILL.md", "utf8");
    const sectionText = cardBlockSection(doc);
    assert.ok(sectionText !== null, "skills/wekan-mcp/SKILL.md has no 'Card details block' section — that section is the single normative home this parity leg needs");
    const fenced = sectionText!.match(/```(?:text|md|markdown)?\n([\s\S]*?)```/);
    assert.ok(fenced, "the Card details block section carries no fenced example — the parity pin reads the example, not prose");
    const observed = await claimBlock();
    assert.deepEqual(fieldShape(observed), fieldShape(fenced![1]),
      `the doc example and what the plugin appends to a claim answer disagree on field lines (indent + label, both directions) — doc ${JSON.stringify(fieldShape(fenced![1]))} vs plugin ${JSON.stringify(fieldShape(observed))}`);
  });

  // The three doc edits the reviewer named, plus the indent law: each must
  // redden the comparison above. They fabricate the doc, never the plugin, so
  // they stay honest whatever the formatter is called.
  const docTamper: Array<[string, (line: string) => string | null, string]> = [
    ["renames the current_slug field", (l) => (l.startsWith("current_slug:") ? `slug_current: <slug>` : l), "a renamed field in the doc"],
    ["drops the parent_id line", (l) => (l.startsWith("parent_id:") ? null : l), "a field the block renders but the doc does not list"],
    ["invents an assignees field", (l) => (l.startsWith("dependencies:") ? ["assignees: <user>, <user>", l].join("\n") : l), "a doc field the block never renders"],
    ["re-indents the dependency continuation", (l) => (l.startsWith("  dependency:") ? `    ${l.trimStart()}` : l), "a broken continuation indent"],
  ];
  for (const [what, edit, why] of docTamper) {
    it(`is responsive: a doc that ${what} reddens the same comparison`, async () => {
      const doc = readFileSync("skills/wekan-mcp/SKILL.md", "utf8");
      const sectionText = cardBlockSection(doc);
      assert.ok(sectionText !== null, "no Card details block section — the parity arm above names this red");
      const fenced = sectionText!.match(/```(?:text|md|markdown)?\n([\s\S]*?)```/);
      assert.ok(fenced, "no fenced example in the Card details block section");
      const tampered = fenced![1]
        .split("\n")
        .map((l) => edit(l))
        .filter((l) => l !== null)
        .join("\n");
      assert.notDeepEqual(fieldShape(tampered), fieldShape(await claimBlock()),
        `the parity arm cannot see the doc ${why} — the comparison is decoration`);
    });
  }
});

// ── the live wiring: setup() → tool.hook("execute.after") ──────────────────
// The seam arms above can stay green with the registration deleted, so these
// arms load the plugin the way the server does (default export → setup(fake
// ctx)) and drive the handler it registers. The card read is the plugin's real
// MCP-over-HTTP client, so a loopback JSON-RPC stub answers it; the plugin's
// board identity is private, so the stub reads the names it searches for out of
// the source instead of re-pinning them.

const pluginSource = readFileSync(".opencode/plugin/board-context/index.ts", "utf8");

function pluginConst(name: string): string {
  const value = new RegExp(`^const ${name} = "([^"]+)"`, "m").exec(pluginSource)?.[1];
  assert.ok(value, `${name} must stay a source-level string constant — the live-wiring arms answer the plugin's board identity by that name`);
  return value as string;
}

interface BoardStub {
  url: string;
  reads: Array<{ name: string; args: any }>;
  close: () => Promise<void>;
}

async function startBoardStub(answers: Record<string, any>): Promise<BoardStub> {
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

async function loadedPlugin(answers: Record<string, any>, sessionAgent: string | null = "agent-board-coord") {
  const stub = await startBoardStub(answers);
  const toolHooks: Array<{ name: string; handler: (event: any) => any }> = [];
  const sessionHooks: string[] = [];
  const ctx: any = {
    directory: process.cwd(),
    location: { directory: process.cwd() },
    mcp: { list: async () => [{ name: pluginConst("MCP_SERVER_KEY"), url: stub.url }] },
    session: {
      get: async ({ sessionID }: any) => ({ id: sessionID, agent: sessionAgent ?? undefined }),
      hook: async (kind: string) => void sessionHooks.push(kind),
    },
    tool: { hook: async (name: string, handler: (event: any) => any) => void toolHooks.push({ name, handler }) },
  };
  await (plugin as any).default.setup(ctx);
  return {
    stub,
    toolHooks,
    sessionHooks,
    executeAfter: toolHooks.find((h) => h.name === "execute.after")?.handler,
    close: stub.close,
  };
}

const CLAIM_ANSWER = "lock held for cf-106-feat-coord-fixes";

// The event as the 2.1.4 host hands execute.after — host-shaped (input/result),
// not the seam's event shape: the adapter in between is what these arms pin.
function hookEvent(agent: string | null, tool = CLAIM_TOOL, result: any = { ok: true, cardId: CARD_ID, content: CLAIM_ANSWER }) {
  return { agent, tool, input: { cardId: CARD_ID }, result, sessionID: "ses_test" };
}

const BOARD_ANSWER = () => [{ id: "BOARD-1", title: pluginConst("BOARD_TITLE") }];

// The block as the plugin appends it to a live claim answer — the observable
// output the doc example is pinned against (no plugin-side symbol required).
async function claimBlock(): Promise<string> {
  const run = await loadedPlugin({ list_boards: BOARD_ANSWER(), get_card_details: PAYLOAD });
  try {
    const after = run.executeAfter;
    assert.ok(after, "setup() registers no execute.after tool hook, so no card block can reach the answer");
    const event = hookEvent("agent-board-coord");
    await after!(event);
    const content = event.result.content;
    assert.ok(typeof content === "string" && content.startsWith(`${CLAIM_ANSWER}\n\n`),
      `the card block must be appended after the untouched claim answer, got ${JSON.stringify(content?.slice(0, 120))}`);
    return content.slice(CLAIM_ANSWER.length + 2);
  } finally {
    await run.close();
  }
}

// Field lines only: (indent, label) pairs, deduplicated — a doc example showing
// one checklist cannot repeat the plugin's two, but it may not add, drop,
// rename or re-indent a field either.
function fieldShape(block: string): string[] {
  const seen: string[] = [];
  for (const line of block.split("\n")) {
    const m = /^(\s*)([a-z_]+):/.exec(line);
    if (!m) continue;
    const token = `${m[1].length}\u0000${m[2]}`;
    if (!seen.includes(token)) seen.push(token);
  }
  return seen;
}

describe("the claim-time block reaches the answer through the registered hook", () => {
  it("registers execute.after (never execute.before) and keeps the prompt hook", async () => {
    const run = await loadedPlugin({ list_boards: BOARD_ANSWER(), get_card_details: PAYLOAD });
    try {
      const names = run.toolHooks.map((h) => h.name);
      assert.ok(names.includes("execute.after"),
        `setup() must register the execute.after hook that appends the card block — without it the claim-time leg is dead code and every seam arm above still passes (saw ${JSON.stringify(names)})`);
      assert.ok(!names.includes("execute.before"),
        "a claim must not be intercepted before the call: the block may only cost itself, never the lock-identity answer");
      assert.ok(run.sessionHooks.includes("prompt"),
        "the prompt prefetch hook moved — the prompt path stays untouched");
    } finally {
      await run.close();
    }
  });

  it("rewrites result.content with the block, over one board-scoped card read", async () => {
    const run = await loadedPlugin({ list_boards: BOARD_ANSWER(), get_card_details: PAYLOAD });
    try {
      const event = hookEvent("agent-board-coord");
      await run.executeAfter?.(event);
      const content = event.result.content;
      assert.ok(typeof content === "string", "a successful board-coord claim must have its answer amended in result.content, the field the host renders");
      assert.ok(content.startsWith(`${CLAIM_ANSWER}\n\n`), "the claim answer must survive as the block's prefix");
      assert.match(content, /^card_details: feat: coord fixes \(#106\)$/m, "the appended block must carry the card header");
      assert.match(content, /^current_slug: cf-106-feat-coord-fixes$/m, "the appended block must carry the parsed slug stack");
      assert.deepEqual(run.stub.reads.map((r) => r.name), ["list_boards", "get_card_details"],
        "the card read is board-scoped: resolve the board once, then read the claimed card");
      assert.deepEqual(run.stub.reads[1]?.args, { board_id: "BOARD-1", card_id: CARD_ID },
        "get_card_details must be called with the resolved board id and the claimed card id");
    } finally {
      await run.close();
    }
  });

  it("leaves the answer byte-unchanged for a refused claim", async () => {
    const run = await loadedPlugin({ list_boards: BOARD_ANSWER(), get_card_details: PAYLOAD });
    try {
      const event = hookEvent("agent-board-coord", CLAIM_TOOL, { ok: false, reason: "lock held by another session" });
      await run.executeAfter?.(event);
      assert.deepEqual(event.result, { ok: false, reason: "lock held by another session" },
        "a failed claim must not be amended — the refusal text is the contract other runs read");
      assert.deepEqual(run.stub.reads.map((r) => r.name), [], "a refused claim must not pay for a card read");
    } finally {
      await run.close();
    }
  });

  it("leaves the answer untouched and reads nothing for a non-board-coord session", async () => {
    const run = await loadedPlugin({ list_boards: BOARD_ANSWER(), get_card_details: PAYLOAD });
    try {
      const event = hookEvent("agent-dev-local");
      await run.executeAfter?.(event);
      assert.equal(event.result.content, CLAIM_ANSWER, "a non-board-coord claim must be byte-unchanged");
      assert.deepEqual(run.stub.reads.map((r) => r.name), [],
        "the agent gate must precede board discovery — every execute.after call must not pay an MCP round trip");
    } finally {
      await run.close();
    }
  });
});

describe("the prompt-hook path stays as it is (AC4)", () => {
  it("still registers exactly one prompt hook and leaves the 8 s constant alone", async () => {
    const hooks: string[] = [];
    const ctx: any = {
      session: { hook: (kind: string) => void hooks.push(`session:${kind}`) },
      tool: { hook: (kind: string) => void hooks.push(`tool:${kind}`) },
      config: () => undefined,
      client: {},
      getProvider: async () => undefined,
      app: {},
      worktree: {},
      path: {},
      info: () => undefined,
      event: () => undefined,
      events: () => undefined,
      dispose: async () => undefined,
    };
    await (plugin as any).default.setup(ctx);
    assert.ok(hooks.includes("session:prompt"),
      "the prompt hook registration changed — AC4 requires the prompt path untouched (FETCH_TIMEOUT_MS, the once-per-session guard, the block footer)");
    assert.equal((plugin as any).FETCH_TIMEOUT_MS, 8_000, "FETCH_TIMEOUT_MS moved — the 8 s board-context budget is a standing ruling");
  });
});
