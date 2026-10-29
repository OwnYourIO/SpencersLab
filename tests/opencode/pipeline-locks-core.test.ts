// C03 acceptance checks (2026/2026-10-cf-76-feat-parallel-pipeline-loops): the
// pipeline-locks plugin core — pipeline-set derivation (D17), the lock store,
// the all-or-nothing set claim (D18), release/status/atomic primitives, the
// lock-root resolution chain (D10), and the degrade-never-throw setup shape.
// Covers chunks/C03.md AC 1-10; the regression run of the four pre-existing
// tests/opencode suites is a plan Commands duty, not this file.
//
// Run from the repo root: node --test tests/opencode/pipeline-locks-core.test.ts
// (Node v26 type-strips the .ts directly; no build step, no npm deps, no
// network — tmp dirs and the fakes below are the only collaborators).
//
// This file lives in the repo-root tests/ tree, deliberately NOT under
// .opencode/: plugin discovery loads every .ts it scans there, so a test file
// inside the plugin dir would be imported as a plugin entry at server startup
// (the question-notify.test.ts / board-context.test.ts placement rule).
//
// Red before C03: the module does not exist yet, so the import below fails
// the whole file with ERR_MODULE_NOT_FOUND — an honest structural red naming
// the missing implementation, never a broken harness.
//
// SEAM CONTRACT (what dev must export from .opencode/plugin/pipeline-locks/index.ts
// — named exports, also reachable off the default export object; the C04/C05/C06
// suites import what C03–C06 add, so the export surface stays additive):
//   Constants (each defined exactly once — AC10, the single sources C07's
//   parity greps read):
//     LABEL_PREFIX: "Pipeline:"          the D17 label prefix, case-sensitive
//     DEFAULT_PIPELINE: "default"        the no-label pipeline (D17)
//     TOOL_NAMES: ["pipeline_claim","pipeline_release","pipeline_heartbeat",
//                  "pipeline_status"]    the visible tool names (D- conventions)
//   derivePipelineSet(labelNames: string[]) -> string[]
//     keep the `Pipeline:`-prefixed names, trim the remainder, drop empty
//     remainders, dedupe, sort; empty result -> [DEFAULT_PIPELINE]  (AC4)
//   sanitizePipelineKey(name: string) -> string
//     output matches ^[A-Za-z0-9._-]{1,100}$; clean names pass through
//     unchanged; idempotent; long names are bounded, never thrown  (AC5)
//   resolveLockRoot(deps, startDir: string) -> Promise<string>   (D10, AC8)
//     deps = { canonical?: string|null, readFile?: (path)=>Promise<string> }
//     chain: canonical -> worktree `.git` file gitdir: <root>/.git/worktrees/
//     <name> (strip the suffix) -> startDir; every miss falls through; never
//     throws. Reads startDir/.git through deps.readFile.
//   newLockRecord(input) -> object   (handoff B.1 shape + D18 identity, v1)
//     input = { pipeline, cardId, sessionID, setId, pipelineSet, cardTitle?,
//     now? }; version: 1; claimedAt/heartbeatAt ISO-8601 UTC from now;
//     pipelineSet stored sorted.
//   Lock/store seams — the injected env (deps) is the same object across a
//   session's calls; its fs member is a node:fs/promises subset (open,
//   readFile, writeFile, rename, rm, mkdir, readdir, stat, utimes); tests
//   back it with real tmp dirs and override single fs members for failure
//   injection. All timestamps derive from env.now (epoch ms).
//     env = { runtimeDir, locksDir, eventsPath, metaPath, now(): number,
//             fs?, claims: Map<sessionID, {setId, cardId, pipelineSet}>,
//             storage?: {get(key,def), set(key,value), remove(key)} | null,
//             pin?: {put(sessionID, key, value), remove(sessionID, key)} | null,
//             reapStale?: (input:{trigger:string}) => Promise<any> }
//   writeLockAtomic(env, path, record) -> Promise<void>            (AC6)
//     tmp sibling whose name contains ".tmp", fs.rename onto path, fs.utimes
//     touch; no ".tmp" entry may remain in the directory on success; a
//     failing tmp write leaves the pre-existing file intact.
//   readLock(env, path) -> Promise<object|null>   parse error / missing ->
//     null; a valid JSON object comes back with unknown keys preserved (the
//     older-schema tolerance contract).
//   appendEvent(env, obj) -> Promise<void>  one JSONL line {at, ...obj} onto
//     env.eventsPath (fire-and-forget: a broken path logs, never rejects).
//   claimLockSet(env, {cardId, pipelines?, cardTitle?, sessionID})
//     -> Promise<{ok:true, setId, lockPaths}|{ok:false, reason:"locked",
//        pipeline, holder}|{ok:false, reason:"already_held", ...}>  (D18)
//     normalizes empty/missing pipelines to [DEFAULT_PIPELINE], sanitizes,
//     sorts, awaits env.reapStale({trigger:"claim"}) first, refuses a second
//     claim from a session that already holds one, then acquires every key
//     with O_EXCL ("wx") in sorted order; on any EEXIST reads the holder,
//     unlinks everything already taken (audit claim_rollback), returns
//     reason:"locked" naming the contended pipeline and the holder record.
//     Success: one file locksDir/<key>.json per member carrying the shared
//     identity (same setId/cardId/sessionID, full sorted pipelineSet), the
//     claim bookkeeping in env.claims AND env.storage when present, the
//     "pipeline-lock" instruction pin when env.pin is present, audit claim.
//   releaseLockSet(env, {sessionID, outcome}) -> Promise<{ok:true}|
//     {ok:false, reason:"not_owner", pipeline}>  (AC7)
//     resolves the session's claim from storage/claims, owner-checks EVERY
//     member file, deletes the whole set only when all owners match, audit
//     release with outcome, clears claims/storage, removes the pin.
//   lockStatus(env, {sessionID?}) -> Promise<{groups: Array<{setId, cardId,
//     holder, pipelineSet, ageMs, state}>, session, lastReap}>  (C03 status)
//     one group per claim (grouped by setId/card), age from env.now,
//     lastReap read from env.metaPath (null when absent; C05 writes it).
//   setup(ctx) registers exactly the TOOL_NAMES tools through
//     ctx.tool.transform(editor.add({name, description, inputSchema,
//     execute(args, context)})) — the VISIBLE names are pipeline_claim etc.
//     (C01 fact 1 fallback: flat names). The claim tool's input schema names
//     cardId and pipelines; the release tool's names outcome.
//   default export: { id: "local.pipeline-locks", async setup(ctx) } — the
//   plain-object shape of the two shipped plugins (NOT Plugin.define);
//   setup never throws (every ctx member optional-chained with a stderr
//   line, board-context degrade policy) and returns a callable cleanup fn.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
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

function constVal(name: string): any {
  const v = mod[name] ?? mod.default?.[name];
  if (v === undefined) {
    throw new Error(`plugin constant "${name}" is not exported (SEAM CONTRACT header, AC10)`);
  }
  return v;
}

const PLUGIN_SRC = readFileSync(".opencode/plugin/pipeline-locks/index.ts", "utf8");

const T0 = Date.parse("2026-10-29T12:00:00Z");
const iso = (ms: number) => new Date(ms).toISOString();

// Real-tmp-dir env: the offline store is exercised against actual O_EXCL and
// rename semantics — a fake fs would only prove the fake. Single fs members
// are overridden where a test needs failure injection.
function baseEnv(opts: any = {}) {
  const runtimeDir = mkdtempSync("/tmp/opencode/pllocks-core.XXXXXX");
  const env: any = {
    runtimeDir,
    locksDir: join(runtimeDir, "locks"),
    eventsPath: join(runtimeDir, "events.log"),
    metaPath: join(runtimeDir, "meta", "lastReap"),
    clock: T0,
    now: () => env.clock,
    advance: (ms: number) => {
      env.clock += ms;
    },
    claims: new Map(),
    storage: opts.storage ?? null,
    pin: opts.pin ?? null,
    reapStale: opts.reapStale ?? (async () => ({})),
  };
  return env;
}

function fakeStorage() {
  const items = new Map<string, any>();
  const calls: any[] = [];
  return {
    items,
    calls,
    api: {
      get: async (key: string, def: any) => (items.has(key) ? items.get(key) : def),
      set: async (key: string, value: any) => {
        calls.push({ key, value });
        items.set(key, value);
      },
      remove: async (key: string) => {
        items.delete(key);
      },
    },
  };
}

function fakePin() {
  const puts: any[] = [];
  const removes: any[] = [];
  return { puts, removes, api: { put: async (...a: any[]) => void puts.push(a), remove: async (...a: any[]) => void removes.push(a) } };
}

function lockFiles(env: any): string[] {
  if (!existsSync(env.locksDir)) return [];
  return readdirSync(env.locksDir)
    .filter((n) => n.endsWith(".json"))
    .sort();
}

function readEvents(env: any): any[] {
  if (!existsSync(env.eventsPath)) return [];
  return readFileSync(env.eventsPath, "utf8")
    .split("\n")
    .filter((l) => l.trim())
    .map((l) => JSON.parse(l));
}

async function callTool(ctxSpecs: any[], name: string, args: any, context: any): Promise<any> {
  const spec = ctxSpecs.find((s) => s.name === name);
  if (!spec) throw new Error(`tool "${name}" was not registered (visible names must be the TOOL_NAMES)`);
  return spec.execute(args, context);
}

function fakeSetupCtx(opts: any = {}) {
  const seen: any = { toolSpecs: [], hookNames: [], cmdSpecs: [], promptCalls: [], subscribeArgs: [] };
  const runtimeDir = opts.runtimeDir;
  const ctx = {
    tool: {
      transform: async (fn: any) => {
        const editor = {
          namespace: "",
          add: (spec: any) => {
            seen.toolSpecs.push(spec);
          },
        };
        await fn(editor);
      },
      hook: async (name: string, _handler: any) => {
        seen.hookNames.push(name);
      },
    },
    command: {
      transform: async (fn: any) => {
        await fn({ add: (spec: any) => void seen.cmdSpecs.push(spec) });
      },
    },
    event: {
      subscribe: (arg: any) => {
        seen.subscribeArgs.push(arg);
        return opts.events ?? { [Symbol.asyncIterator]: () => ({ next: async () => ({ value: undefined, done: true }) }) };
      },
    },
    session: {
      get: async () => undefined,
      prompt: async (arg: any) => void seen.promptCalls.push(arg),
      instructions: { entry: { put: async () => {}, remove: async () => {} } },
    },
    mcp: { list: async () => [] },
    storage: opts.storage ?? undefined,
    location: runtimeDir ? { directory: runtimeDir } : { directory: "/tmp/opencode/pipeline-locks-no-config" },
  };
  return { ctx, seen };
}

async function setupBounded(ctx: any): Promise<any> {
  const settled = await Promise.race([
    mod.default.setup(ctx),
    new Promise((resolve) => setTimeout(() => resolve("pending"), 2000)),
  ]);
  assert.notEqual(settled, "pending", "setup must return while long-lived work runs in the background (board-context precedent)");
  return settled;
}

describe("K1 constants and module hygiene (AC 10)", () => {
  it("defines LABEL_PREFIX, DEFAULT_PIPELINE and the tool-visible names once each", () => {
    assert.equal(constVal("LABEL_PREFIX"), "Pipeline:");
    assert.equal(constVal("DEFAULT_PIPELINE"), "default");
    assert.deepEqual(constVal("TOOL_NAMES"), ["pipeline_claim", "pipeline_release", "pipeline_heartbeat", "pipeline_status"]);
    // Single sources for C07's parity greps: each literal occurs exactly once
    // in the module (a second occurrence means a second owner of the truth).
    assert.equal((PLUGIN_SRC.match(/"Pipeline:"/g) ?? []).length, 1, '"Pipeline:" is spelled in more than one place');
    assert.equal((PLUGIN_SRC.match(/"default"/g) ?? []).length, 1, '"default" is spelled in more than one place — it must ride on DEFAULT_PIPELINE');
    for (const name of constVal("TOOL_NAMES")) {
      assert.equal((PLUGIN_SRC.match(new RegExp(`"${name}"`, "g")) ?? []).length, 1, `"${name}" is spelled in more than one place — it must ride on TOOL_NAMES`);
    }
    assert.equal((PLUGIN_SRC.match(/const\s+LABEL_PREFIX\b/g) ?? []).length, 1);
    assert.equal((PLUGIN_SRC.match(/const\s+DEFAULT_PIPELINE\b/g) ?? []).length, 1);
    assert.equal((PLUGIN_SRC.match(/const\s+TOOL_NAMES\b/g) ?? []).length, 1);
  });

  it("uses the shipped plain-object plugin shape, not Plugin.define (AC 10, verified fact 1)", () => {
    assert.ok(!PLUGIN_SRC.includes("Plugin.define"), "the docs' Plugin.define shape is not what this repo ships (question-notify/board-context precedent)");
    assert.equal(mod.default?.id, "local.pipeline-locks");
    assert.equal(typeof mod.default?.setup, "function");
  });

  it("carries no hardcoded MCP URLs, hosts or credentials (AC 10)", () => {
    for (const banned of ["http://", "https://", "scifi.farm", "spencerslab", "Authorization"]) {
      assert.ok(!PLUGIN_SRC.includes(banned), `plugin source contains ${banned} — URLs are discovered at runtime (board-context/question-notify precedent)`);
    }
  });

  it("gitignores the runtime lock directory (AC 10)", () => {
    const ignore = readFileSync(".gitignore", "utf8");
    assert.ok(ignore.split("\n").some((l) => l.trim() === ".pipeline/" || l.trim() === "/.pipeline/"), ".gitignore must carry the .pipeline/ entry — lock state is never committed");
  });
});

describe("K2 derivePipelineSet — the D17 label projection (AC 4)", () => {
  it("keeps, trims, dedupes and sorts the Pipeline:-prefixed remainder", () => {
    assert.deepEqual(seam("derivePipelineSet")(["Pipeline: payments", "Pipeline:infra ", "Research"]), ["infra", "payments"]);
  });

  it("falls back to the single default pipeline when nothing survives (AC 4)", () => {
    const d = constVal("DEFAULT_PIPELINE");
    for (const input of [["Pipeline:"], ["Pipeline:   "], ["Research"], []]) {
      assert.deepEqual(seam("derivePipelineSet")(input as string[]), [d], `${JSON.stringify(input)} must fold to [${d}]`);
    }
  });

  it("matches the prefix case-sensitively and dedupes repeats", () => {
    assert.deepEqual(seam("derivePipelineSet")(["pipeline: x", "PIPELINE: x"]), [constVal("DEFAULT_PIPELINE")]);
    assert.deepEqual(seam("derivePipelineSet")(["Pipeline: a", "Pipeline: a", "Pipeline:  a"]), ["a"]);
  });
});

describe("K3 sanitizePipelineKey + resolveLockRoot (AC 5, AC 8)", () => {
  it("keeps sanitize output inside the lock-filename charset (AC 5)", () => {
    const sanitize = seam("sanitizePipelineKey");
    assert.match(sanitize("../../x y/z"), /^[A-Za-z0-9._-]{1,100}$/);
    assert.equal(sanitize("payments"), "payments", "a clean name must pass through unchanged (derived labels stay readable on the card)");
    assert.equal(sanitize(sanitize("../../x y/z")), sanitize("../../x y/z"), "sanitizing is idempotent");
    assert.ok(sanitize("p".repeat(500)).length <= 100, "over-long names are bounded by the 100-char charset limit");
  });

  it("prefers the canonical leg when present (AC 8, D10)", async () => {
    const root = await seam("resolveLockRoot")({ canonical: "/main/checkout", readFile: async () => { throw new Error("no fs"); } }, "/wt/dir");
    assert.equal(root, "/main/checkout");
  });

  it("derives the main checkout root from a worktree .git file (AC 8)", async () => {
    const reads: string[] = [];
    const root = await seam("resolveLockRoot")(
      { readFile: async (p: string) => { reads.push(p); return "gitdir: /repo/.git/worktrees/feature-wt\n"; } },
      "/wt/feature-wt",
    );
    assert.equal(root, "/repo");
    assert.ok(reads.some((p) => p.endsWith("/.git")), `the chain must read the .git file, saw ${JSON.stringify(reads)}`);
  });

  it("falls through to the start dir on every miss and never throws (AC 8)", async () => {
    const throwing = { readFile: async () => { throw new Error("EISDIR"); } };
    assert.equal(await seam("resolveLockRoot")(throwing, "/plain/repo"), "/plain/repo", "a main checkout (.git is a directory) resolves to itself");
    const garbage = { readFile: async () => "not a gitdir line" };
    assert.equal(await seam("resolveLockRoot")(garbage, "/wt"), "/wt");
    const linked = { readFile: async () => "gitdir: /elsewhere/.git" };
    assert.equal(await seam("resolveLockRoot")(linked, "/wt"), "/wt", "a gitdir that is not a worktree layout falls through — only the .git/worktrees/<name> suffix strips");
  });
});

describe("K4 claimLockSet — identity, normalization, storage and pin legs (AC 3, AC 5)", () => {
  it("writes one lock per member carrying the shared claim identity, sorted set included (AC 5)", async () => {
    const env = baseEnv();
    const res = await seam("claimLockSet")(env, { cardId: "card1", pipelines: ["b", "a"], cardTitle: "cf-76", sessionID: "s1" });
    assert.equal(res.ok, true, JSON.stringify(res));
    assert.deepEqual(lockFiles(env), ["a.json", "b.json"]);
    const recs = lockFiles(env).map((f) => JSON.parse(readFileSync(join(env.locksDir, f), "utf8")));
    const setIds = new Set(recs.map((r) => r.setId));
    assert.equal(setIds.size, 1, "every file of one claim carries the same setId (D18)");
    assert.equal(recs[0].cardId, "card1");
    for (const r of recs) {
      assert.equal(r.version, 1);
      assert.equal(r.sessionID, "s1");
      assert.equal(r.setId, res.setId);
      assert.deepEqual(r.pipelineSet, ["a", "b"], "the full sorted pipelineSet rides in every member file");
      assert.ok(!Number.isNaN(Date.parse(r.heartbeatAt)), "heartbeatAt is ISO-8601");
    }
    assert.equal(JSON.parse(readFileSync(join(env.locksDir, "a.json"), "utf8")).pipeline, "a");
    assert.deepEqual(res.lockPaths.map((p: string) => p.split("/").pop()).sort(), ["a.json", "b.json"]);
  });

  it("normalizes an omitted or empty set to the default pipeline (D17, D2 carry-over)", async () => {
    for (const pipelines of [undefined, []]) {
      const env = baseEnv();
      const res = await seam("claimLockSet")(env, { cardId: "c", pipelines, sessionID: "s1" });
      assert.equal(res.ok, true, JSON.stringify(res));
      assert.deepEqual(lockFiles(env), [`${constVal("DEFAULT_PIPELINE")}.json`]);
    }
  });

  it("refuses a second claim from the same root session on a different set (AC 3)", async () => {
    const env = baseEnv();
    assert.equal((await seam("claimLockSet")(env, { cardId: "c1", pipelines: ["a"], sessionID: "s1" })).ok, true);
    const second = await seam("claimLockSet")(env, { cardId: "c2", pipelines: ["b"], sessionID: "s1" });
    assert.equal(second.ok, false);
    assert.equal(second.reason, "already_held", "one card per iteration — a locked session cannot pick up a second claim");
    assert.deepEqual(lockFiles(env), ["a.json"], "the refused claim must leave no new files");
  });

  it("records the claim through the ctx.storage seam and the in-memory fallback (both legs)", async () => {
    const store = fakeStorage();
    const env = baseEnv({ storage: store.api });
    const res = await seam("claimLockSet")(env, { cardId: "c1", pipelines: ["a"], sessionID: "s1" });
    assert.equal(res.ok, true);
    assert.ok(store.calls.length >= 1, "the claim must persist its session bookkeeping through the storage seam (C04 rebuilds from it)");
    const entry = store.calls.find((c) => c.key.includes("s1") || JSON.stringify(c.value).includes("s1"));
    assert.ok(entry, `no storage entry names the root session, saw ${JSON.stringify(store.calls.map((c) => c.key))}`);
    assert.ok(JSON.stringify(entry.value).includes(res.setId) && JSON.stringify(entry.value).includes("pipelineSet"), "the storage record carries the setId and the set for release/status correlation");
    assert.ok(env.claims.get("s1"), "the in-process cache mirrors the claim even when storage exists");

    const envNoStore = baseEnv();
    const res2 = await seam("claimLockSet")(envNoStore, { cardId: "c2", pipelines: ["a"], sessionID: "s2" });
    assert.equal(res2.ok, true, "no ctx.storage must not block a claim — the in-memory Map + disk locks are the documented fallback");
    assert.ok(envNoStore.claims.get("s2"), "the fallback leg records the claim in the provided in-memory map");
  });

  it("arms the claim-time reap and pins the instruction when the seam exists (D16)", async () => {
    const reaps: any[] = [];
    const pin = fakePin();
    const env = baseEnv({ reapStale: async (input: any) => void reaps.push(input), pin: pin.api });
    const res = await seam("claimLockSet")(env, { cardId: "c1", pipelines: ["a"], sessionID: "s1" });
    assert.equal(res.ok, true);
    assert.equal(reaps.length, 1, "claim awaits the reap hook exactly once before acquiring");
    assert.equal(typeof reaps[0].trigger, "string");
    assert.ok(pin.puts.some((p: any[]) => p[1] === "pipeline-lock" && typeof p[2] === "string" && p[2].length > 0), "the claim pins the pipeline-lock instruction (C04 updates it on lock-lost)");
  });
});

describe("K5 claim races — all-or-nothing over intersecting sets (AC 2, AC 3)", () => {
  it("overlapping sets {a,b} vs {b,c}: exactly one wins, the loser rolls back everything (AC 2)", async () => {
    let sawRollback = 0;
    for (let round = 0; round < 20; round++) {
      const env = baseEnv();
      const [r1, r2] = await Promise.all([
        seam("claimLockSet")(env, { cardId: "c1", pipelines: ["a", "b"], sessionID: "s1" }),
        seam("claimLockSet")(env, { cardId: "c2", pipelines: ["b", "c"], sessionID: "s2" }),
      ]);
      const oks = [r1, r2].filter((r) => r.ok === true);
      const loser = r1.ok ? r2 : r1;
      const winner = r1.ok ? r1 : r2;
      assert.equal(oks.length, 1, `round ${round}: exactly one claim may win, saw ${JSON.stringify([r1, r2])}`);
      assert.equal(loser.reason, "locked");
      assert.equal(loser.pipeline, "b", "the error names the contended pipeline");
      assert.equal(loser.holder?.sessionID, winner === r1 ? "s1" : "s2", "the loser reports the winner as holder");
      const files = lockFiles(env);
      const winnerKeys = winner === r1 ? ["a.json", "b.json"] : ["b.json", "c.json"];
      assert.deepEqual(files, winnerKeys, `round ${round}: the loser must leave zero partial lock files`);
      assert.equal(env.claims.has(loser === r1 ? "s1" : "s2"), false, "the rollback must also drop the loser's in-process claim");
      const raw = existsSync(env.eventsPath) ? readFileSync(env.eventsPath, "utf8") : "";
      if (raw.includes("claim_rollback")) sawRollback++;
    }
    assert.ok(sawRollback > 0, "across 20 rounds at least one rollback path (acquire-then-contend) must have been exercised and audited");
  });

  it("same-set concurrent claims: exactly one wins (AC 3)", async () => {
    for (let round = 0; round < 10; round++) {
      const env = baseEnv();
      const [r1, r2] = await Promise.all([
        seam("claimLockSet")(env, { cardId: "c1", pipelines: ["a", "b"], sessionID: "s1" }),
        seam("claimLockSet")(env, { cardId: "c2", pipelines: ["a", "b"], sessionID: "s2" }),
      ]);
      assert.equal([r1, r2].filter((r) => r.ok === true).length, 1, `round ${round}: same-set claims serialize`);
    }
  });

  it("disjoint concurrent sets both win (AC 3)", async () => {
    const env = baseEnv();
    const [r1, r2] = await Promise.all([
      seam("claimLockSet")(env, { cardId: "c1", pipelines: ["a"], sessionID: "s1" }),
      seam("claimLockSet")(env, { cardId: "c2", pipelines: ["b"], sessionID: "s2" }),
    ]);
    assert.equal(r1.ok, true);
    assert.equal(r2.ok, true);
    assert.deepEqual(lockFiles(env), ["a.json", "b.json"]);
  });
});

describe("K6 writeLockAtomic / readLock / appendEvent / newLockRecord (AC 6)", () => {
  const record = (extra: any = {}) => ({ version: 1, pipeline: "a", cardId: "c", sessionID: "s", setId: "set1", pipelineSet: ["a"], heartbeatAt: iso(T0), ...extra });

  it("leaves no .tmp behind on success and touches the file (AC 6)", async () => {
    const env = baseEnv();
    mkdirSync(env.locksDir, { recursive: true });
    const path = join(env.locksDir, "a.json");
    const utimesCalls: string[] = [];
    const realFs = await import("node:fs/promises");
    env.fs = { ...realFs, utimes: async (p: string, at: any, mt: any) => { utimesCalls.push(p); return (realFs as any).utimes(p, at, mt); } };
    await seam("writeLockAtomic")(env, path, record());
    assert.deepEqual(JSON.parse(readFileSync(path, "utf8")).pipeline, "a");
    const left = readdirSync(env.locksDir).filter((n) => n.includes(".tmp"));
    assert.deepEqual(left, [], "a completed atomic write must leave no tmp file");
    assert.ok(utimesCalls.length >= 1, "writeLockAtomic must fs.utimes the lock (mtime tracks the heartbeat record — the reaper's max(heartbeatAt, mtime) rule)");
  });

  it("keeps the pre-existing content when the tmp write fails (AC 6)", async () => {
    const env = baseEnv();
    mkdirSync(env.locksDir, { recursive: true });
    const path = join(env.locksDir, "a.json");
    const realFs = await import("node:fs/promises");
    await seam("writeLockAtomic")({ ...env, fs: realFs }, path, record({ v: "first" }));
    const before = readFileSync(path, "utf8");
    const failFs = {
      ...realFs,
      writeFile: async (p: string, ...rest: any[]) => {
        if (String(p).includes(".tmp")) throw new Error("injected tmp-write failure");
        return (realFs as any).writeFile(p, ...rest);
      },
      open: async (p: string, ...rest: any[]) => {
        if (String(p).includes(".tmp")) throw new Error("injected tmp-open failure");
        return (realFs as any).open(p, ...rest);
      },
    };
    await assert.rejects(seam("writeLockAtomic")({ ...env, fs: failFs }, path, record({ v: "second" })));
    assert.equal(readFileSync(path, "utf8"), before, "a failed tmp write must never clobber the live lock");
  });

  it("readLock answers null for corrupt or missing files and preserves unknown keys", async () => {
    const env = baseEnv();
    const realFs = await import("node:fs/promises");
    env.fs = realFs;
    mkdirSync(env.locksDir, { recursive: true });
    const good = join(env.locksDir, "good.json");
    await seam("writeLockAtomic")(env, good, record({ futureField: { keep: "me" } }));
    writeFileSync(join(env.locksDir, "bad.json"), "{ not json");
    assert.equal(JSON.parse(readFileSync(good, "utf8")).futureField.keep, "me");
    assert.equal(await seam("readLock")(env, join(env.locksDir, "bad.json")), null);
    assert.equal(await seam("readLock")(env, join(env.locksDir, "absent.json")), null);
    const rec = await seam("readLock")(env, good);
    assert.equal(rec?.futureField?.keep, "me", "the older-schema tolerance contract: unknown keys survive the read");
  });

  it("appendEvent writes parseable JSONL and never rejects on a broken path", async () => {
    const env = baseEnv();
    await seam("appendEvent")(env, { ev: "claim", setId: "set1" });
    const lines = readEvents(env);
    assert.equal(lines.length, 1);
    assert.equal(lines[0].ev, "claim");
    assert.ok(!Number.isNaN(Date.parse(lines[0].at)), "appendEvent stamps at");
    const broken = { ...env, eventsPath: join(env.runtimeDir, "no-such-dir", "events.log") };
    await seam("appendEvent")(broken, { ev: "audit-should-not-throw" });
  });

  it("newLockRecord builds the v1 record with the D18 identity and ISO stamps", () => {
    const rec = seam("newLockRecord")({
      pipeline: "a",
      cardId: "c1",
      sessionID: "s1",
      setId: "set-9",
      pipelineSet: ["b", "a"],
      now: T0,
    });
    assert.equal(rec.version, 1);
    assert.equal(rec.cardId, "c1");
    assert.equal(rec.setId, "set-9");
    assert.deepEqual(rec.pipelineSet, ["a", "b"], "the record stores the set sorted");
    assert.equal(rec.heartbeatAt, iso(T0));
    assert.equal(rec.claimedAt, iso(T0));
  });
});

describe("K7 releaseLockSet — owner checks and the set delete (AC 7)", () => {
  it("a mismatched owner on any member blocks the WHOLE release and touches nothing", async () => {
    const env = baseEnv();
    const res = await seam("claimLockSet")(env, { cardId: "c1", pipelines: ["a", "b"], sessionID: "s1" });
    assert.equal(res.ok, true);
    const bPath = join(env.locksDir, "b.json");
    const bRec = JSON.parse(readFileSync(bPath, "utf8"));
    bRec.sessionID = "thief";
    writeFileSync(bPath, JSON.stringify(bRec));
    const out = await seam("releaseLockSet")(env, { sessionID: "s1", outcome: "done" });
    assert.equal(out.ok, false);
    assert.equal(out.reason, "not_owner");
    assert.equal(out.pipeline, "b", "the error names the file whose owner mismatched");
    assert.deepEqual(lockFiles(env), ["a.json", "b.json"], "a partial release is never performed — all files stay in place");
  });

  it("the owner deletes the whole set, audits the release and cleans bookkeeping + pin", async () => {
    const pin = fakePin();
    const store = fakeStorage();
    const env = baseEnv({ pin: pin.api, storage: store.api });
    const res = await seam("claimLockSet")(env, { cardId: "c1", pipelines: ["a", "b"], sessionID: "s1" });
    const out = await seam("releaseLockSet")(env, { sessionID: "s1", outcome: "done" });
    assert.equal(out.ok, true);
    assert.deepEqual(lockFiles(env), [], "release removes every member file of the set (D18)");
    assert.equal(env.claims.has("s1"), false);
    assert.ok(pin.removes.some((p: any[]) => p[1] === "pipeline-lock"), "release removes the instruction pin");
    const lines = readEvents(env);
    const rel = lines.find((l) => l.ev === "release");
    assert.ok(rel, `no release audit line, saw ${JSON.stringify(lines.map((l) => l.ev))}`);
    assert.equal(rel.outcome, "done");
    assert.equal(rel.setId, res.setId);
    assert.equal(rel.cardId, "c1");
    assert.deepEqual(rel.pipelineSet, ["a", "b"]);
    assert.ok(!Number.isNaN(Date.parse(rel.at)));
    const abandoned = await seam("claimLockSet")(env, { cardId: "c2", pipelines: ["a"], sessionID: "s2" });
    await seam("releaseLockSet")(env, { sessionID: "s2", outcome: "abandoned" });
    const rel2 = readEvents(env).filter((l) => l.ev === "release").pop();
    assert.equal(rel2.outcome, "abandoned", "the outcome distinction (done|abandoned) rides the audit — D6/D11");
    void abandoned;
  });
});

describe("K8 lockStatus — set-grouped view, session claim, lastReap meta", () => {
  it("groups each claim as one unit with age/state/holder and names the caller's claim", async () => {
    const env = baseEnv();
    const r1 = await seam("claimLockSet")(env, { cardId: "c1", pipelines: ["a", "b"], sessionID: "s1" });
    env.advance(5000);
    await seam("claimLockSet")(env, { cardId: "c2", pipelines: ["c"], sessionID: "s2" });
    const status = await seam("lockStatus")(env, {});
    assert.equal(status.groups.length, 2, "two claims read as two groups");
    const g1 = status.groups.find((g: any) => g.cardId === "c1");
    assert.deepEqual(g1.pipelineSet, ["a", "b"], "a multi-pipeline claim reads as one unit (D18)");
    assert.equal(g1.holder, "s1");
    assert.equal(g1.setId, r1.setId);
    assert.ok(typeof g1.ageMs === "number" && g1.ageMs >= 0);
    assert.equal(typeof g1.state, "string");
    const mine = await seam("lockStatus")(env, { sessionID: "s2" });
    assert.ok(mine.session && JSON.stringify(mine.session).includes("c2"), "this session's claim is called out");
    const none = await seam("lockStatus")(env, { sessionID: "s-none" });
    assert.ok(none.session === null || none.session === undefined, "an unlocked session has no claim");
  });

  it("surfaces the reaper's meta/lastReap once C05 has written it", async () => {
    const env = baseEnv();
    const before = await seam("lockStatus")(env, {});
    assert.equal(before.lastReap, null, "no meta yet -> null (the meta is a C05 product)");
    const realFs = await import("node:fs/promises");
    await realFs.mkdir(join(env.runtimeDir, "meta"), { recursive: true });
    writeFileSync(env.metaPath, JSON.stringify({ at: iso(T0), trigger: "tick" }));
    const after = await seam("lockStatus")(env, {});
    assert.equal(after.lastReap?.at, iso(T0));
  });
});

describe("K9 setup — plain-object shape, visible tool names, degrade path (AC 9)", () => {
  it("registers the four tools under their exact visible names against a real tmp root", async () => {
    const runtimeDir = mkdtempSync("/tmp/opencode/pllocks-setup.XXXXXX");
    const { ctx, seen } = fakeSetupCtx({ runtimeDir });
    const cleanup = await setupBounded(ctx);
    try {
      for (const name of constVal("TOOL_NAMES")) {
        assert.ok(seen.toolSpecs.some((s: any) => s.name === name), `tool ${name} not registered with the visible name (C01 fact 1: ${JSON.stringify(seen.toolSpecs.map((s: any) => s.name))})`);
      }
      const claimSpec = seen.toolSpecs.find((s: any) => s.name === "pipeline_claim");
      assert.ok(JSON.stringify(claimSpec).includes("cardId") && JSON.stringify(claimSpec).includes("pipelines"), "the claim tool's schema declares cardId + pipelines");
      const releaseSpec = seen.toolSpecs.find((s: any) => s.name === "pipeline_release");
      assert.ok(JSON.stringify(releaseSpec).includes("outcome"), "the release tool's schema declares outcome");
      // End-to-end through the executor: the tool writes the lock under the
      // tmp repo root (the resolveLockRoot fallback leg).
      const out = await callTool(seen.toolSpecs, "pipeline_claim", { cardId: "c1", pipelines: ["alpha"] }, { sessionID: "ses_k9" });
      const text = typeof out === "string" ? out : JSON.stringify(out ?? {});
      assert.match(text, /"?(ok|setId)"?[:=]/i, `the claim tool must answer the lock result, saw ${text}`);
      assert.ok(existsSync(join(runtimeDir, ".pipeline", "locks", "alpha.json")), "the claim executor writes locks under the resolved root's .pipeline/");
    } finally {
      if (typeof cleanup === "function") cleanup();
    }
  });

  it("degrades without throwing on an empty ctx and still returns a cleanup function (AC 9)", async () => {
    const cleanup = await setupBounded({});
    assert.equal(typeof cleanup, "function", "setup must always return a cleanup fn (the host calls it unconditionally)");
    cleanup();
  });
});
