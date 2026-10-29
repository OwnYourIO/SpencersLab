// C06 acceptance checks (2026/2026-10-cf-76-feat-parallel-pipeline-loops):
// the /pipeline-tick executor (reap-before-prompt + the worker prompt pins),
// the .pipeline/config.json option loader (D8), the loop-file bytes, and the
// TICK_PROMPT constant both contract sides ride on. Covers chunks/C06.md
// AC 2-4 and the structural part of the Tests list; AC 1/AC 5 are harness/
// rulesync duties and AC 6 + the Live-smoke checklist are the human/deferred
// gate — deliberately NOT encoded here (they need the real
// OpenChamber+OpenCode server; per the plan's Commands section they live in
// chunks/C06.md's Review notes). Body contract per DECISIONS r4 D30 (C01
// fact 4 amendment): the loop file SHIPS the plain-text worker body; the
// /pipeline-tick body swap rides the live-smoke gate, not these tests.
//
// Run from the repo root: node --test tests/opencode/pipeline-locks-tick.test.ts
// (Node v26 type-strips; no build, no deps, no network — tmp dirs and fake
// ctx are the only collaborators.)
//
// Red before C06: loadConfig/TICK_PROMPT not exported yet — seam()/constVal()
// name the missing export instead of an ESM link error.
//
// SEAM CONTRACT — additions:
//   TICK_PROMPT: string  — the constant the tick executor sends as the
//     session prompt; it names the boards skill, pipeline_status-first and
//     exactly one iteration (C07's skill text must agree — pinned on the bash
//     side by tests/agent-perms/surface.sh A15).
//   loadConfig(deps, dir) -> Promise<config>
//     deps = { readFile?: (path)=>Promise<string>  (rejects when absent),
//              log?: (line)=>void }
//     dir is the runtime dir; reads <dir>/config.json. Baked defaults
//     (D8/D21/D13): {staleMs: 7200000, timerMs: 300000, reapEveryMs: 600000,
//     hookThrottleMs: 30000, releaseOnFailure: false, strictLockLoss: true,
//     haNotify: true, maxWorkers: null, board: {boardTitle: "AI-Dev",
//     swimlaneTitle: "In Process", timeoutListTitle: "Timeout"}}.
//     Legal keys override; wrong-typed values fall back per KEY (no type
//     coercion); unknown keys are ignored (incl. inside board); malformed
//     JSON -> whole-config defaults + exactly one stderr line via deps.log;
//     never throws.
//   setup reads config ONLY through loadConfig (no fs read at module scope —
//     the structural assert below; plugin syntax already rides on this file's
//     own import, per the plan's Commands).
//   /pipeline-tick executor (registered via ctx.command.transform, visible
//     name pipeline-tick): awaits the reap BEFORE prompting (AC 2 — fake-call
//     ordering), audits the tick, then ctx.session.prompt({sessionID, text})
//     with text === TICK_PROMPT (or text containing it verbatim), exactly
//     once, using the executor context's sessionID.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import * as plugin from "../../.opencode/plugin/pipeline-locks/index.ts";

const mod = plugin as Record<string, any>;

function seam(name: string): (...args: any[]) => any {
  const fn = typeof mod[name] === "function" ? mod[name] : mod.default?.[name];
  if (typeof fn !== "function") {
    throw new Error(
      `plugin seam "${name}" is not exported (see the SEAM CONTRACT header — dev must export it from .opencode/plugin/pipeline-locks/index.ts)`,
    );
  }
  return fn;
}

const PLUGIN_SRC = readFileSync(".opencode/plugin/pipeline-locks/index.ts", "utf8");

const HOUR = 3600000;

const DEFAULTS = {
  staleMs: 7200000,
  timerMs: 300000,
  reapEveryMs: 600000,
  hookThrottleMs: 30000,
  releaseOnFailure: false,
  strictLockLoss: true,
  haNotify: true,
  maxWorkers: null,
  board: { boardTitle: "AI-Dev", swimlaneTitle: "In Process", timeoutListTitle: "Timeout" },
};

function loadDeps(content: string | null, opts: any = {}) {
  const logs: string[] = [];
  return {
    logs,
    deps: {
      readFile: async (path: string) => {
        if (opts.pathCheck) assert.match(path, /config\.json$/, "loadConfig must read the runtime config.json");
        if (content === null) throw Object.assign(new Error("ENOENT"), { code: "ENOENT" });
        return content;
      },
      log: (line: string) => void logs.push(line),
    },
  };
}

describe("T1 loadConfig — defaults, overrides, malformed, wrong-type (AC 4, D8/D13/D21)", () => {
  it("answers the baked defaults when no config file exists", async () => {
    const { deps, logs } = loadDeps(null);
    assert.deepEqual(await seam("loadConfig")(deps, "/runtime"), DEFAULTS);
    assert.equal(logs.length, 0, "a missing optional file is the normal state, not a warn");
  });

  it("applies legal overrides key-by-key and keeps the rest default", async () => {
    const { deps } = loadDeps(JSON.stringify({ staleMs: 60000, releaseOnFailure: true, board: { timeoutListTitle: "Dead" } }));
    const cfg = await seam("loadConfig")(deps, "/runtime");
    assert.equal(cfg.staleMs, 60000);
    assert.equal(cfg.releaseOnFailure, true);
    assert.deepEqual(cfg.board, { ...DEFAULTS.board, timeoutListTitle: "Dead" });
    assert.equal(cfg.timerMs, DEFAULTS.timerMs);
  });

  it("malformed JSON falls back to defaults with exactly one stderr line, never a throw", async () => {
    const { deps, logs } = loadDeps("{ this is not json");
    assert.deepEqual(await seam("loadConfig")(deps, "/runtime"), DEFAULTS);
    assert.equal(logs.length, 1, "one stderr line per malformed file (D8) — silent fallback hides drift");
  });

  it("wrong-typed values fall back per key WITHOUT coercion surprises", async () => {
    const { deps } = loadDeps(JSON.stringify({ staleMs: "2h", timerMs: "300000", releaseOnFailure: 1, board: "AI-Dev" }));
    const cfg = await seam("loadConfig")(deps, "/runtime");
    assert.equal(cfg.staleMs, 7200000, '"2h" is not a number — the default stands (D21 default must not be silently string-coerced)');
    assert.equal(cfg.timerMs, DEFAULTS.timerMs);
    assert.equal(cfg.releaseOnFailure, false);
    assert.deepEqual(cfg.board, DEFAULTS.board);
  });

  it("unknown keys are ignored, top-level and inside board", async () => {
    const { deps } = loadDeps(JSON.stringify({ nope: 1, maxWorkersPlus: true, board: { mystery: "x" } }));
    assert.deepEqual(await seam("loadConfig")(deps, "/runtime"), DEFAULTS);
  });

  it("carries the reserved maxWorkers key through when set (D13 — reserved, unimplemented)", async () => {
    const { deps } = loadDeps(JSON.stringify({ maxWorkers: 3 }));
    const cfg = await seam("loadConfig")(deps, "/runtime");
    assert.equal(cfg.maxWorkers, 3, "loader accepts the reserved key; capping arrives with its own ticket");
  });
});

describe("T2 the loop file — OpenChamber shape, shipped disabled (AC 3)", () => {
  const LOOP = ".agents/loops/pipeline-worker.md";

  function parseFrontmatter(text: string): { fields: Record<string, string>; body: string } {
    const m = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/.exec(text);
    assert.ok(m, `${LOOP}: no YAML frontmatter block`);
    const fields: Record<string, string> = {};
    for (const line of m[1].split(/\r?\n/)) {
      const fm = /^([A-Za-z_-]+):(.*)$/.exec(line);
      if (fm) fields[fm[1]] = fm[2].trim().replace(/^"(.*)"$/, "$1");
    }
    return { fields, body: m[2] };
  }

  it("carries exactly the five documented fields with the decided values", () => {
    const { fields } = parseFrontmatter(readFileSync(LOOP, "utf8"));
    assert.deepEqual(Object.keys(fields).sort(), ["agent", "enabled", "model", "name", "schedule"], "exactly the verified OpenChamber frontmatter fields");
    assert.equal(fields.name, "pipeline-worker");
    assert.equal(fields.agent, "agent-board-coord", "the tick session runs as the board-coord ALIAS (D15)");
    assert.equal(fields.model, "openrouter/qwen/qwen3.8-flash", "Q2 ruling: the loop/worker session runs the code tier");
    assert.equal(fields.schedule, "0 * * * *", "hourly cadence spans the 2 h stale window twice (D21)");
    assert.match(readFileSync(LOOP, "utf8"), /^enabled:\s*false$/m, "the bytes carry the literal `enabled: false` — a careless flip must fail loudly (AC 3)");
  });

  it("ships the D30 plain-text worker body as the DEFAULT (fact 4 live-deferred on v2.1.4)", () => {
    // D30 (C01 fact 4: opencode run "/cmd" sent the literal text): slash
    // dispatch from a loop body is unproven, so the SHIPPED body is the
    // verbatim worker sentence; the /pipeline-tick bare-command swap is the
    // live-smoke checklist item 3 — human-gated, and deliberately NOT
    // asserted beyond its presence as documented swap target here.
    const raw = readFileSync(LOOP, "utf8");
    const { body } = parseFrontmatter(raw);
    const prose = body
      .replace(/<!--[\s\S]*?-->/g, "")
      .split(/\r?\n/)
      .map((l) => l.trim())
      .filter(Boolean)
      .join(" ");
    const D30_BODY =
      "Load the boards skill and run exactly one Parallel pipeline loops iteration. First call pipeline_status, then follow the skill.";
    assert.equal(prose, D30_BODY, "the shipped prompt is the D30 sentence verbatim — dev may not paraphrase the worker text into a drift the skill-parity tests cannot see");
    assert.ok(!prose.includes("/pipeline-tick"), "a slash command in the SHIPPED body would arrive as literal text until the live-smoke gate proves dispatch");
    assert.ok(raw.includes("/pipeline-tick"), "the bare-command swap target stays documented in the file's header docs (checklist item 3)");
  });
});

describe("T3 the tick executor — reap before prompt (AC 2)", () => {
  it("reaps via the real store, THEN prompts once with TICK_PROMPT and the executor's sessionID", async () => {
    const runtimeRoot = mkdtempSync("/tmp/opencode/pllocks-tick.XXXXXX");
    const runtimeDir = join(runtimeRoot, ".pipeline");
    const locksDir = join(runtimeDir, "locks");
    mkdirSync(locksDir, { recursive: true });
    // staleMs 60000 via the config file: a 1 h-old lock only reaps when the
    // loader actually fed setup — the seam-through-config structural duty.
    writeFileSync(join(runtimeDir, "config.json"), JSON.stringify({ staleMs: 60000 }));
    const old = Date.now() - HOUR;
    writeFileSync(
      join(locksDir, "goner.json"),
      JSON.stringify({ version: 1, pipeline: "goner", cardId: "c-tick", setId: "set-t", sessionID: "s-old", pipelineSet: ["goner"], state: "live", claimedAt: new Date(old).toISOString(), heartbeatAt: new Date(old).toISOString() }),
    );
    utimesSync(join(locksDir, "goner.json"), old / 1000, old / 1000);

    const seen: any = { cmdSpecs: [], promptCalls: [] };
    const events: string[] = [];
    const ctx: any = {
      tool: { transform: async (fn: any) => void fn({ namespace: "", add: () => {} }), hook: async () => {} },
      command: { transform: async (fn: any) => void fn({ add: (s: any) => void seen.cmdSpecs.push(s) }) },
      event: { subscribe: () => ({ [Symbol.asyncIterator]: () => ({ next: async () => ({ value: undefined, done: true }) }) }) },
      session: {
        get: async () => undefined,
        prompt: async (arg: any) => {
          // Snapshot the lock dir AT PROMPT TIME: the reap must already have
          // moved the stale file (fake-call ordering, AC 2).
          const live = readdirSync(locksDir).filter((n) => n.endsWith(".json")).join(",");
          events.push(`prompt:${live}:${existsSync(join(locksDir, ".reaped")) ? "reaped-dir" : "no-reaped-dir"}`);
          seen.promptCalls.push(arg);
        },
        instructions: { entry: { put: async () => {}, remove: async () => {} } },
      },
      mcp: { list: async () => [] },
      location: { directory: runtimeRoot },
    };
    const settled = await Promise.race([
      mod.default.setup(ctx),
      new Promise((r) => setTimeout(() => r("pending"), 2000)),
    ]);
    assert.notEqual(settled, "pending", "setup must return with the tick wiring done in the background");
    const cleanup = settled;
    try {
      const tick = seen.cmdSpecs.find((s: any) => String(s.name).replace(/^\//, "") === "pipeline-tick");
      assert.ok(tick, `pipeline-tick not registered, saw ${JSON.stringify(seen.cmdSpecs.map((s: any) => s.name))}`);
      const ret = await tick.execute({ sessionID: "ses_tick", prompt: "/pipeline-tick", delivery: "auto" });
      assert.equal(seen.promptCalls.length, 1, "exactly one worker prompt per tick");
      assert.equal(events[0], "prompt::reaped-dir", "the stale lock is reaped BEFORE the prompt is sent (AC 2 ordering)");
      assert.ok(!existsSync(join(locksDir, "goner.json")));
      const text = String(seen.promptCalls[0].text ?? "");
      const TICK_PROMPT = mod.TICK_PROMPT ?? mod.default?.TICK_PROMPT;
      assert.equal(typeof TICK_PROMPT, "string", "the tick prompt ships as an exported constant (C06 Notes: both contract sides pin it)");
      assert.ok(text.includes(TICK_PROMPT) || text === TICK_PROMPT, `the executor sends the TICK_PROMPT constant verbatim, saw ${JSON.stringify(text.slice(0, 120))}`);
      assert.ok(/boards/.test(TICK_PROMPT), "the prompt names the boards skill");
      assert.ok(/pipeline_status/.test(TICK_PROMPT), "the prompt demands the pipeline_status-first read");
      assert.ok(/one/.test(TICK_PROMPT) && /iteration/.test(TICK_PROMPT), "the prompt pins exactly ONE iteration");
      assert.equal(seen.promptCalls[0].sessionID, "ses_tick", "the prompt rides the executor context's sessionID (C01 fact 4)");
      void ret;
    } finally {
      if (typeof cleanup === "function") cleanup();
      rmSync(runtimeRoot, { recursive: true, force: true });
    }
  });

  it("the tick audits itself and the board/HA degrade legs cannot block the prompt", async () => {
    const runtimeRoot = mkdtempSync("/tmp/opencode/pllocks-tick2.XXXXXX");
    const runtimeDir = join(runtimeRoot, ".pipeline");
    const locksDir = join(runtimeDir, "locks");
    mkdirSync(locksDir, { recursive: true });
    writeFileSync(join(runtimeDir, "config.json"), JSON.stringify({ staleMs: 60000 }));
    const old = Date.now() - HOUR;
    writeFileSync(
      join(locksDir, "gone2.json"),
      JSON.stringify({ version: 1, pipeline: "gone2", cardId: "c2", setId: "set-2", sessionID: "s2", pipelineSet: ["gone2"], state: "live", heartbeatAt: new Date(old).toISOString() }),
    );
    utimesSync(join(locksDir, "gone2.json"), old / 1000, old / 1000);
    const seen: any = { cmdSpecs: [], promptCalls: [] };
    const ctx: any = {
      tool: { transform: async (fn: any) => void fn({ namespace: "", add: () => {} }), hook: async () => {} },
      command: { transform: async (fn: any) => void fn({ add: (s: any) => void seen.cmdSpecs.push(s) }) },
      event: { subscribe: () => ({ [Symbol.asyncIterator]: () => ({ next: async () => ({ value: undefined, done: true }) }) }) },
      session: { get: async () => undefined, prompt: async (a: any) => void seen.promptCalls.push(a), instructions: { entry: { put: async () => {}, remove: async () => {} } } },
      mcp: { list: async () => [] },
      location: { directory: runtimeRoot },
    };
    const cleanup = await Promise.race([mod.default.setup(ctx), new Promise((r) => setTimeout(() => r("pending"), 2000))]);
    assert.notEqual(cleanup, "pending");
    try {
      const tick = seen.cmdSpecs.find((s: any) => String(s.name).replace(/^\//, "") === "pipeline-tick");
      // No dev-boards URL resolves offline (empty mcp.list, no config text) —
      // the card leg MUST degrade to timeouts.jsonl and the tick still prompt.
      await tick.execute({ sessionID: "ses_tick2", prompt: "/pipeline-tick", delivery: "auto" });
      assert.equal(seen.promptCalls.length, 1, "a degraded board/alert must never eat the tick");
      assert.ok(existsSync(join(runtimeDir, "timeouts.jsonl")), "the degraded card queued in timeouts.jsonl (D22 interim)");
      const raw = existsSync(join(runtimeDir, "events.log")) ? readFileSync(join(runtimeDir, "events.log"), "utf8") : "";
      assert.ok(/"ev":"tick"/.test(raw) || raw.includes('"tick"'), `the tick is audited, events.log: ${JSON.stringify(raw.slice(0, 200))}`);
    } finally {
      if (typeof cleanup === "function") cleanup();
      rmSync(runtimeRoot, { recursive: true, force: true });
    }
  });
});

describe("T4 structural — config reads go through the seam (C06 Tests)", () => {
  it("the module never touches a synchronous fs read (Node async-fs plugin precedent)", () => {
    assert.ok(!/readFileSync|writeFileSync|existsSync|readdirSync/.test(PLUGIN_SRC), "sync fs calls in the plugin runtime risk blocking the event loop; the shipped plugins use the promises API");
    assert.match(PLUGIN_SRC, /"config\.json"|config\.json/, "the config file name appears — the loader seam owns the read (D8)");
  });

  it("setup resolves options through loadConfig, not a baked-in-at-import default", async () => {
    const runtimeRoot = mkdtempSync("/tmp/opencode/pllocks-tick3.XXXXXX");
    const runtimeDir = join(runtimeRoot, ".pipeline");
    const locksDir = join(runtimeDir, "locks");
    mkdirSync(locksDir, { recursive: true });
    // An IMPOSSIBLE-as-default staleMs is the probe: only a real read of
    // this file can make the 10-minute-old lock reap.
    writeFileSync(join(runtimeDir, "config.json"), JSON.stringify({ staleMs: 60000 }));
    const old = Date.now() - 10 * 60000;
    writeFileSync(
      join(locksDir, "probe.json"),
      JSON.stringify({ version: 1, pipeline: "probe", cardId: "cp", setId: "sp", sessionID: "spr", pipelineSet: ["probe"], state: "live", heartbeatAt: new Date(old).toISOString() }),
    );
    utimesSync(join(locksDir, "probe.json"), old / 1000, old / 1000);
    const seen: any = { cmdSpecs: [] };
    const ctx: any = {
      tool: { transform: async (fn: any) => void fn({ namespace: "", add: () => {} }), hook: async () => {} },
      command: { transform: async (fn: any) => void fn({ add: (s: any) => void seen.cmdSpecs.push(s) }) },
      event: { subscribe: () => ({ [Symbol.asyncIterator]: () => ({ next: async () => ({ value: undefined, done: true }) }) }) },
      session: { get: async () => undefined, prompt: async () => {}, instructions: { entry: { put: async () => {}, remove: async () => {} } } },
      mcp: { list: async () => [] },
      location: { directory: runtimeRoot },
    };
    const cleanup = await Promise.race([mod.default.setup(ctx), new Promise((r) => setTimeout(() => r("pending"), 2000))]);
    assert.notEqual(cleanup, "pending");
    try {
      const reap = seen.cmdSpecs.find((s: any) => String(s.name).replace(/^\//, "") === "pipeline-reap");
      assert.ok(reap);
      await reap.execute({ sessionID: "ses_probe", prompt: "/pipeline-reap", delivery: "auto" });
      assert.ok(!existsSync(join(locksDir, "probe.json")), "setup read config.json through loadConfig — the default 2 h window could not have reaped a 10-minute lock");
    } finally {
      if (typeof cleanup === "function") cleanup();
      rmSync(runtimeRoot, { recursive: true, force: true });
    }
  });
});
