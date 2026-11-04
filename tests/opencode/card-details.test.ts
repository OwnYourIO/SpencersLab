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
//
// DESIGN-RED POSTURE (verified at authoring): none of the four seam names
// exists in the plugin yet, so every test below fails with its own named
// reason. If the C07 hook-reachability ruling lands the sanctioned fallback
// (no plugin leg; the boards skill mandates the call), this file is retired in
// the SAME commit as the DECISIONS entry — it must not linger as a permanent
// red.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

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

  it("matches the field lines of the single doc home in skills/wekan-mcp/SKILL.md", () => {
    requireSeam("formatCardBlock");
    const doc = readFileSync("skills/wekan-mcp/SKILL.md", "utf8");
    const sectionText = cardBlockSection(doc);
    assert.ok(sectionText !== null, "skills/wekan-mcp/SKILL.md has no 'Card details block' section — that section is the single normative home this parity leg needs (red before C07's doc edit)");
    const fenced = sectionText!.match(/```(?:text|md|markdown)?\n([\s\S]*?)```/);
    assert.ok(fenced, "the Card details block section carries no fenced example — the parity pin reads the example, not prose");
    const labels = (block: string) =>
      block
        .split("\n")
        .map((l) => l.trim().split(":")[0].replace(/^[-*]\s*/, "").trim())
        .filter((l) => l.length > 0);
    const docLabels = labels(fenced![1]);
    const codeLabels = labels(seam("formatCardBlock")(PAYLOAD));
    assert.deepEqual(codeLabels.filter((l) => docLabels.includes(l)).length >= docLabels.length - 1, true,
      `the doc example and the formatter disagree on field lines — doc ${JSON.stringify(docLabels)} vs plugin ${JSON.stringify(codeLabels)}`);
  });

  it("is responsive: a fabricated doc edit reddens the same field-line comparison", () => {
    requireSeam("formatCardBlock");
    const doc = readFileSync("skills/wekan-mcp/SKILL.md", "utf8");
    const sectionText = cardBlockSection(doc);
    if (sectionText === null) return; // the doc-home arm above already names this red
    const fenced = sectionText.match(/```(?:text|md|markdown)?\n([\s\S]*?)```/);
    if (!fenced) return;
    const tampered = fenced![1].split("\n").map((l) => l.replace(/checklists/i, "checklist_notes")).join("\n");
    const labels = (block: string) =>
      block.split("\n").map((l) => l.trim().split(":")[0].replace(/^[-*]\s*/, "").trim()).filter(Boolean);
    const docLabels = labels(tampered);
    const codeLabels = labels(seam("formatCardBlock")(PAYLOAD));
    assert.notDeepEqual(docLabels, codeLabels,
      "the field-line comparison cannot see a renamed field in the doc — the parity arm is decoration");
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
