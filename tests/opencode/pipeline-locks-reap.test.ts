// C05 acceptance checks (2026/2026-10-cf-76-feat-parallel-pipeline-loops): the
// reaper — stale detection (max(heartbeatAt, mtime), default 2 h per D21), the
// cross-process mkdir guard, the race restore, the set-grouped board move +
// comment + HA alert (D18/D22), the timeouts.jsonl degrade (the interim
// contract until the D22 follow-up card lands), the reap/status command
// routing, and the module's credential-free constants. Covers chunks/C05.md
// AC 1-9; the earlier-suites re-run is a plan Commands duty.
//
// Run from the repo root: node --test tests/opencode/pipeline-locks-reap.test.ts
// (Node v26 type-strips; no build, no deps, no network — tmp dirs, a fake
// clock and recording board/notify seams are the only collaborators.)
//
// Red before C05: reapStale et al. are not exported yet; seam() names the
// missing export. Claim/store fixtures come from the C03 seams; lock files
// for the reaper are seeded via them plus utimes for mtime control.
//
// SEAM CONTRACT — additions (env keeps growing; C03/C04 headers document the
// rest):
//   env = { ..., staleMs?, timeoutsPath, client?, notify?, moveCardToTimeout? }
//     client is the dev-boards MCP surface {callTool(name, args) -> Promise<
//     payload>}; notify is the HA alert sender; both null/absent = unavailable
//     -> degrade, never throw. The reaper derives reaperGuard =
//     runtimeDir/reaper.lock and reapedDir = locksDir/.reaped from env.
//   reapStale(env, {trigger}) -> Promise<{reaped: Array<{pipeline,...}>,
//     skipped?: boolean}>                                     (AC 2-7, AC 9)
//     guard: mkdir reaper.lock; EEXIST -> if the dir mtime is older than
//     5 min (env.clock basis) remove + retry once, else resolve {skipped:
//     true}; the guard is removed in a finally. Stale iff env.now −
//     max(Date.parse(heartbeatAt), mtimeMs) >= env.config.staleMs (default
//     7200000, D21). A parse-error or missing-heartbeatAt file falls back to
//     mtime. Each stale file is claimed by rename into .reaped/<name>.<ts>.
//     json, then RE-READ: a fresh heartbeatAt in the reaped copy -> rename
//     back + audit reap_raced (no board leg, no alert). On a confirmed reap:
//     audit reaped {at, ev, pipeline, setId, cardId, sessionID, ageMin,
//     trigger}, write meta/lastReap, clear claims/storage for sessions this
//     instance owns. Then the CARD legs: reaps grouped by cardId, exactly
//     ONE env.moveCardToTimeout + ONE env.notify per card, each carrying the
//     union of the pass's reaped pipelines with every record's pipelineSet
//     (a partially-reaped set still reads complete). env.moveCardToTimeout /
//     env.notify default to the real seams; alert fires AFTER the file move;
//     a rejecting leg changes nothing about the reap outcome.
//   moveCardToTimeout(env, {cardId, pipelines, sessionID, setId}) ->
//     Promise<void>                                            (AC 4)
//     client.callTool sequence: get_card -> list_lists -> move_card ->
//     add_comment. get_card answers {id, list_id, swimlane_id, label_ids};
//     the Timeout list is the list_lists entry titled env.config.board.
//     timeoutListTitle whose swimlane_id equals the card's CURRENT swimlane
//     (the human-created list lives in the same swimlane as the working
//     lists — "In Process"). move_card({board_id, card_id?, from_list_id,
//     to_list_id}); add_comment text matches
//     /^Timed out: no heartbeat for 2h \(session .+, pipelines .+\)$/.
//     ANY leg failing — including a Timeout list that does not exist yet
//     (the normal state pre-D22-follow-up) and a null client — appends
//     {at, cardId, setId, pipelines, sessionID, reason} to timeouts.jsonl
//     and audits board_move_err. It never throws into the reaper.
//   sendHaReapAlert(env, {cardId, pipelines, ageMin, sessionID}) ->
//     Promise<void>                                            (AC 7)
//     env.callHA(toolName, args) (bound at setup to admin-global-homeassistant
//     discovery — transform -> list fallback, NO config-text leg, question-
//     notify precedent) with toolName "call_service", domain notify, service
//     notify.mobile_app_pixel_6, title "OpenCode: pipeline lock reaped",
//     message `card=<cardId> pipelines=<a>,<b> age=<n>min session=<id>`
//     truncated to <= 240 chars (the question-notify MAX_MESSAGE shape).
//     Rejections land on env.log only — an alert must never delay or fail
//     a reap (D11).
//   Command registrations (pipeline-reap, pipeline-status) route through
//     reapStale/lockStatus; the captured executors run against the setup env.
//   Module constants (AC 8): the two MCP server keys appear ONLY as named
//     constants (`"dev-boards"`, `"admin-global-homeassistant"` — one quoted
//     occurrence each); the staleMs default literal is 7200000; the 3-hour
//     value is gone; no URL/host/credential literal anywhere.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, readdirSync, utimesSync, writeFileSync, mkdirSync, rmSync } from "node:fs";
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
// Wall clock (not a frozen epoch): the reaper compares env.now against REAL
// file mtimes, and the guard dir's age is judged the same way — a frozen
// base would make the mkdir guard look stale/fresh by hours depending on
// when the test runs. Ages are relative to env.clock, seeded via utimesSync.
const iso = (ms: number) => new Date(ms).toISOString();
const secs = (ms: number) => ms / 1000;

function baseEnv(opts: any = {}) {
  const runtimeDir = mkdtempSync("/tmp/opencode/pllocks-reap.XXXXXX");
  const env: any = {
    runtimeDir,
    locksDir: join(runtimeDir, "locks"),
    eventsPath: join(runtimeDir, "events.log"),
    timeoutsPath: join(runtimeDir, "timeouts.jsonl"),
    metaPath: join(runtimeDir, "meta", "lastReap"),
    clock: opts.clock ?? Date.now(),
    now: () => env.clock,
    advance: (ms: number) => {
      env.clock += ms;
    },
    claims: new Map(),
    storage: null,
    pin: null,
    config: {
      staleMs: 7200000,
      timerMs: 300000,
      reapEveryMs: 600000,
      hookThrottleMs: 30000,
      releaseOnFailure: false,
      strictLockLoss: true,
      haNotify: true,
      maxWorkers: null,
      board: { boardTitle: "AI-Dev", swimlaneTitle: "In Process", timeoutListTitle: "Timeout" },
      ...(opts.config ?? {}),
    },
    log: opts.log ?? (() => {}),
  };
  if (opts.fs) env.fs = opts.fs;
  if (opts.client !== undefined) env.client = opts.client;
  if (opts.moveCardToTimeout) env.moveCardToTimeout = opts.moveCardToTimeout;
  if (opts.notify) env.notify = opts.notify;
  return env;
}

// Hand-write a lock file the way a heartbeat left it: ISO heartbeatAt plus a
// matching mtime (the reaper's max(heartbeatAt, mtime) rule needs BOTH under
// the stale threshold — a fresh mtime legitimately rescues the file).
function seedLock(env: any, rec: any, ageMs: number, extra: Record<string, any> = {}) {
  mkdirSync(env.locksDir, { recursive: true });
  const path = join(env.locksDir, `${rec.pipeline}.json`);
  const full = {
    version: 1,
    cardId: "c1",
    sessionID: "s1",
    setId: "set1",
    pipelineSet: [rec.pipeline],
    state: "live",
    claimedAt: iso(env.clock - Math.max(ageMs, 0)),
    heartbeatAt: iso(env.clock - ageMs),
    ...rec,
    ...extra,
  };
  writeFileSync(path, JSON.stringify(full));
  utimesSync(path, secs(env.clock - ageMs), secs(env.clock - ageMs));
  return full;
}

function lockFiles(env: any): string[] {
  if (!existsSync(env.locksDir)) return [];
  return readdirSync(env.locksDir).filter((n) => n.endsWith(".json")).sort();
}

function reapedFiles(env: any): string[] {
  const dir = join(env.locksDir, ".reaped");
  return existsSync(dir) ? readdirSync(dir).sort() : [];
}

function readEvents(env: any): any[] {
  if (!existsSync(env.eventsPath)) return [];
  return readFileSync(env.eventsPath, "utf8")
    .split("\n")
    .filter((l) => l.trim())
    .map((l) => JSON.parse(l));
}

function readTimeouts(env: any): any[] {
  if (!existsSync(env.timeoutsPath)) return [];
  return readFileSync(env.timeoutsPath, "utf8")
    .split("\n")
    .filter((l) => l.trim())
    .map((l) => JSON.parse(l));
}

function recordingClient(legs: Record<string, any> = {}) {
  const calls: any[] = [];
  return {
    calls,
    api: {
      callTool: async (name: string, args: any) => {
        calls.push({ name, args });
        if (legs[`${name}Throws`] || legs[name] instanceof Error) throw legs[name] ?? new Error(`${name} failed`);
        if (name in legs) return typeof legs[name] === "function" ? legs[name](args) : legs[name];
        switch (name) {
          case "get_card":
            return { id: args.cardId ?? args.card_id ?? "c1", list_id: "L-exec", swimlane_id: "SW-in", label_ids: [] };
          case "list_lists":
            return [
              { id: "L-not", title: "Not Started", swimlane_id: "SW-in" },
              { id: "L-exec", title: "Executing", swimlane_id: "SW-in" },
              { id: "L-timeout", title: "Timeout", swimlane_id: "SW-in" },
              { id: "L-bt", title: "Timeout", swimlane_id: "SW-backlog" },
            ];
          case "move_card":
            return { ok: true };
          case "add_comment":
            return { ok: true };
          default:
            throw new Error(`unexpected board tool ${name}`);
        }
      },
    },
  };
}

describe("R1 stale reap happy path (AC 2)", () => {
  it("3-hour-old locks move to .reaped with a reaped audit + lastReap meta; a 10-minute lock and a fresh-mtime lock survive", async () => {
    const env = baseEnv();
    seedLock(env, { pipeline: "a", cardId: "c1", setId: "set1", sessionID: "s1", pipelineSet: ["a"] }, 3 * HOUR);
    seedLock(env, { pipeline: "z", cardId: "c2", setId: "set2", sessionID: "s2", pipelineSet: ["z"] }, 10 * 60000);
    seedLock(env, { pipeline: "r", cardId: "c3", setId: "set3", sessionID: "s3", pipelineSet: ["r"] }, 3 * HOUR, {});
    utimesSync(join(env.locksDir, "r.json"), secs(env.clock), secs(env.clock)); // stale heartbeat, fresh mtime
    const moveCalls: any[] = [];
    env.moveCardToTimeout = async (info: any) => void moveCalls.push(info);
    env.notify = async () => {};
    env.claims.set("s1", { setId: "set1", cardId: "c1", pipelineSet: ["a"] });
    const res = await seam("reapStale")(env, { trigger: "tick" });
    assert.ok(res && Array.isArray(res.reaped), `reapStale must answer a summary, saw ${JSON.stringify(res)}`);
    assert.deepEqual(lockFiles(env), ["r.json", "z.json"], "max(heartbeatAt, mtime) rescues a hand-edited stale heartbeat — the formula from the tasks is load-bearing (lockFiles sorts; survivors are exactly {r, z})");
    assert.equal(reapedFiles(env).length, 1);
    assert.match(reapedFiles(env)[0], /^a\..+\.json$/, "reaped files land as .reaped/<name>.<ts>.json");
    const evs = readEvents(env);
    const reaped = evs.find((l) => l.ev === "reaped");
    assert.ok(reaped, "the reap is audited");
    assert.equal(reaped.pipeline, "a");
    assert.equal(reaped.setId, "set1");
    assert.equal(reaped.cardId, "c1");
    assert.equal(reaped.sessionID, "s1");
    assert.equal(reaped.ageMin, 180);
    assert.equal(reaped.trigger, "tick");
    assert.ok(existsSync(env.metaPath), "meta/lastReap is written");
    assert.ok(!Number.isNaN(Date.parse(JSON.parse(readFileSync(env.metaPath, "utf8")).at)));
    assert.equal(env.claims.has("s1"), false, "cache cleanup for sessions this instance owns");
  });

  it("a parse-error lock and an old-schema lock (no heartbeatAt) reap by mtime", async () => {
    const env = baseEnv();
    mkdirSync(env.locksDir, { recursive: true });
    writeFileSync(join(env.locksDir, "junk.json"), "{ broken");
    utimesSync(join(env.locksDir, "junk.json"), secs(env.clock - 4 * HOUR), secs(env.clock - 4 * HOUR));
    seedLock(env, { pipeline: "old" }, 5 * HOUR, { heartbeatAt: undefined });
    const p = join(env.locksDir, "old.json");
    const rec = JSON.parse(readFileSync(p, "utf8"));
    delete rec.heartbeatAt;
    writeFileSync(p, JSON.stringify(rec));
    utimesSync(p, secs(env.clock - 5 * HOUR), secs(env.clock - 5 * HOUR));
    env.moveCardToTimeout = async () => {};
    env.notify = async () => {};
    const res = await seam("reapStale")(env, { trigger: "timer" });
    assert.equal(lockFiles(env).length, 0, "missing heartbeatAt falls back to mtime (older-schema tolerance)");
    assert.equal(reapedFiles(env).length, 2);
    assert.equal(res.reaped.length, 2);
  });
});

describe("R2 set-grouped card legs (AC 3)", () => {
  it("two stale members of ONE claim produce exactly ONE board move, ONE comment leg and ONE alert naming BOTH pipelines", async () => {
    const env = baseEnv();
    seedLock(env, { pipeline: "a", cardId: "c1", setId: "set1", sessionID: "s1", pipelineSet: ["a", "b"] }, 3 * HOUR);
    seedLock(env, { pipeline: "b", cardId: "c1", setId: "set1", sessionID: "s1", pipelineSet: ["a", "b"] }, 3 * HOUR);
    const moves: any[] = [];
    const alerts: any[] = [];
    env.moveCardToTimeout = async (info: any) => void moves.push(info);
    env.notify = async (info: any) => void alerts.push(info);
    await seam("reapStale")(env, { trigger: "tick" });
    assert.equal(moves.length, 1, "one board leg per CARD, not per file");
    assert.deepEqual([...moves[0].pipelines].sort(), ["a", "b"]);
    assert.equal(moves[0].cardId, "c1");
    assert.equal(alerts.length, 1, "one HA alert per reaped card (AC 7)");
    assert.deepEqual([...alerts[0].pipelines].sort(), ["a", "b"], "the alert names EVERY pipeline of the reaped claim");
    assert.equal(alerts[0].ageMin, 180);
  });

  it("a partially-reaped set still reads COMPLETE: the union rides the record's pipelineSet", async () => {
    const env = baseEnv();
    seedLock(env, { pipeline: "a", cardId: "c1", setId: "set1", sessionID: "s1", pipelineSet: ["a", "b"] }, 3 * HOUR);
    seedLock(env, { pipeline: "b", cardId: "c1", setId: "set1", sessionID: "s1", pipelineSet: ["a", "b"] }, 60000);
    const moves: any[] = [];
    env.moveCardToTimeout = async (info: any) => void moves.push(info);
    env.notify = async () => {};
    await seam("reapStale")(env, { trigger: "tick" });
    assert.equal(moves.length, 1);
    assert.deepEqual([...moves[0].pipelines].sort(), ["a", "b"], "the comment/alert set = reaped ∪ record pipelineSet (D18 leg)");
    assert.deepEqual(lockFiles(env), ["b.json"], "the fresh member is left in place — only reaped files move");
  });

  it("a legacy record without pipelineSet contributes just its own pipeline name", async () => {
    const env = baseEnv();
    const rec = seedLock(env, { pipeline: "solo", cardId: "c9", setId: "set9", sessionID: "s9", pipelineSet: ["solo"] }, 3 * HOUR);
    delete (rec as any).pipelineSet;
    writeFileSync(join(env.locksDir, "solo.json"), JSON.stringify(rec));
    // The rewrite stamps mtime to the real wall clock; the pinned
    // max(heartbeatAt, mtime) formula would then (correctly) skip the file —
    // stale it again the same way the R1 mtime legs do.
    utimesSync(join(env.locksDir, "solo.json"), secs(env.clock - 3 * HOUR), secs(env.clock - 3 * HOUR));
    const moves: any[] = [];
    env.moveCardToTimeout = async (info: any) => void moves.push(info);
    env.notify = async () => {};
    await seam("reapStale")(env, { trigger: "tick" });
    assert.deepEqual(moves[0].pipelines, ["solo"]);
  });
});

describe("R3 degrade legs — timeouts.jsonl is the interim contract (AC 4, D22)", () => {
  it("each failing board leg appends the full card row and the reap still succeeds", async () => {
    for (const failing of ["get_card", "list_lists", "move_card", "add_comment"]) {
      const env = baseEnv({ client: recordingClient({ [failing]: new Error(`${failing} exploded`) }) });
      seedLock(env, { pipeline: "a", cardId: "c1", setId: "set1", sessionID: "s1", pipelineSet: ["a", "b"] }, 3 * HOUR);
      env.notify = async () => {};
      await seam("reapStale")(env, { trigger: "tick" });
      const rows = readTimeouts(env);
      assert.equal(rows.length, 1, `${failing}: the card row must queue in timeouts.jsonl`);
      assert.equal(rows[0].cardId, "c1");
      assert.equal(rows[0].setId, "set1");
      assert.equal(rows[0].sessionID, "s1");
      assert.deepEqual([...rows[0].pipelines].sort(), ["a", "b"], "the degrade row keeps the FULL pipeline list");
      assert.equal(typeof rows[0].reason, "string");
      assert.ok(!Number.isNaN(Date.parse(rows[0].at)));
      assert.equal(lockFiles(env).length, 0, "the reap itself still succeeded");
      assert.ok(readEvents(env).some((l) => l.ev === "board_move_err"), `${failing}: the failed leg is audited`);
      assert.ok(existsSync(join(env.locksDir, ".reaped")), "degrade never reverses the file move");
    }
  });

  it("a board with NO Timeout list degrades the same way (the normal state until the D22 follow-up card lands)", async () => {
    const env = baseEnv({
      client: recordingClient({
        list_lists: [
          { id: "L-not", title: "Not Started", swimlane_id: "SW-in" },
          { id: "L-exec", title: "Executing", swimlane_id: "SW-in" },
        ],
      }),
    });
    seedLock(env, { pipeline: "a", cardId: "c1", setId: "set1", sessionID: "s1" }, 3 * HOUR);
    env.notify = async () => {};
    await seam("reapStale")(env, { trigger: "tick" });
    assert.equal(readTimeouts(env).length, 1);
    assert.equal(env.client.calls.filter((c: any) => c.name === "move_card").length, 0, "nothing to move to — no move_card against a board without the list");
  });

  it("a null client (no dev-boards URL discovered) still queues the card and reaps", async () => {
    const env = baseEnv({ client: null });
    seedLock(env, { pipeline: "a", cardId: "c1", setId: "set1", sessionID: "s1" }, 3 * HOUR);
    env.notify = async () => {};
    const res = await seam("reapStale")(env, { trigger: "tick" });
    assert.equal(res.reaped.length, 1);
    assert.equal(readTimeouts(env).length, 1);
  });
});

describe("R4 heartbeat race restore (AC 5)", () => {
  it("a reaped copy showing a fresh heartbeat is renamed back, audited reap_raced, with no board leg and no alert", async () => {
    const env = baseEnv();
    seedLock(env, { pipeline: "a", cardId: "c1", setId: "set1", sessionID: "s1", pipelineSet: ["a"] }, 3 * HOUR);
    const realFs = await import("node:fs/promises");
    const FRESH = JSON.stringify({
      version: 1,
      pipeline: "a",
      cardId: "c1",
      sessionID: "s1",
      setId: "set1",
      pipelineSet: ["a"],
      state: "live",
      claimedAt: iso(env.clock - 4 * HOUR),
      heartbeatAt: iso(env.clock),
    });
    env.fs = {
      ...realFs,
      readFile: async (p: any, ...rest: any[]) => {
        const path = String(p);
        if (path.includes(".reaped") && path.includes("a.")) return FRESH;
        return (realFs as any).readFile(p, ...rest);
      },
    };
    const moves: any[] = [];
    const alerts: any[] = [];
    env.moveCardToTimeout = async (info: any) => void moves.push(info);
    env.notify = async (info: any) => void alerts.push(info);
    const res = await seam("reapStale")(env, { trigger: "tick" });
    assert.ok(existsSync(join(env.locksDir, "a.json")), "the raced file is restored to the live lock dir");
    assert.equal(reapedFiles(env).filter((f) => f.startsWith("a.")).length, 0, "the .reaped copy is renamed back, not copied");
    assert.ok(readEvents(env).some((l) => l.ev === "reap_raced"), "the race is audited");
    assert.equal(moves.length, 0, "a raced lock gets no board leg");
    assert.equal(alerts.length, 0, "a raced lock gets no alert");
    void res;
  });
});

describe("R5 reaper-lock guard (AC 6)", () => {
  it("a concurrent second reapStale is skipped while the first holds the guard", async () => {
    const env = baseEnv({ client: recordingClient() });
    seedLock(env, { pipeline: "a", cardId: "c1", setId: "set1", sessionID: "s1" }, 3 * HOUR);
    let release: any;
    const gate = new Promise((resolve) => {
      release = resolve;
    });
    env.moveCardToTimeout = async () => {
      await gate; // hold the first pass inside its board leg
    };
    env.notify = async () => {};
    const first = seam("reapStale")(env, { trigger: "tick" });
    await until(() => lockFiles(env).length === 0, "first reap reached its board leg");
    const second = await seam("reapStale")(env, { trigger: "command" });
    assert.equal(second.skipped, true, "the mkdir guard serializes cross-process reaps ({skipped:true})");
    release(undefined);
    await first;
  });

  it("a guard dir older than 5 minutes is recovered and the reap runs; the guard is gone afterwards", async () => {
    const env = baseEnv();
    const guard = join(env.runtimeDir, "reaper.lock");
    mkdirSync(guard, { recursive: true });
    utimesSync(guard, secs(env.clock - 6 * 60000), secs(env.clock - 6 * 60000));
    seedLock(env, { pipeline: "a", cardId: "c1", setId: "set1", sessionID: "s1" }, 3 * HOUR);
    env.moveCardToTimeout = async () => {};
    env.notify = async () => {};
    const res = await seam("reapStale")(env, { trigger: "tick" });
    assert.notEqual(res.skipped, true, "a stale guard is removed and the reap retries once");
    assert.equal(res.reaped.length, 1);
    assert.ok(!existsSync(guard), "the guard is removed in a finally");
  });

  it("the guard does not leak after a successful reap", async () => {
    const env = baseEnv();
    seedLock(env, { pipeline: "a" }, 3 * HOUR);
    env.moveCardToTimeout = async () => {};
    env.notify = async () => {};
    await seam("reapStale")(env, { trigger: "tick" });
    assert.ok(!existsSync(join(env.runtimeDir, "reaper.lock")));
  });
});

describe("R6 HA alert legs (AC 7)", () => {
  it("the alert seam rejecting changes NOTHING about the reap outcome", async () => {
    const env = baseEnv();
    seedLock(env, { pipeline: "a", cardId: "c1", setId: "set1", sessionID: "s1" }, 3 * HOUR);
    env.moveCardToTimeout = async () => {};
    env.notify = async () => {
      throw new Error("ha down");
    };
    const res = await seam("reapStale")(env, { trigger: "tick" });
    assert.equal(res.reaped.length, 1);
    assert.equal(lockFiles(env).length, 0);
    assert.ok(existsSync(env.metaPath), "a dead HA still reaps (alert is AFTER the file move, never a dependency)");
  });

  it("sendHaReapAlert fires call_service with the pinned title/message shape, truncated to 240 chars", async () => {
    const calls: any[] = [];
    const env = baseEnv();
    env.callHA = async (toolName: string, args: any) => {
      calls.push({ toolName, args });
    };
    await seam("sendHaReapAlert")(env, { cardId: "c1", pipelines: ["a", "b"], ageMin: 180, sessionID: "s1" });
    assert.equal(calls.length, 1);
    assert.equal(calls[0].toolName, "call_service");
    const args = calls[0].args;
    assert.equal(args.domain, "notify");
    assert.match(String(args.service), /mobile_app_pixel_6/);
    const data = args.data ?? args.service_data ?? {};
    assert.equal(data.title, "OpenCode: pipeline lock reaped");
    assert.equal(data.message, "card=c1 pipelines=a,b age=180min session=s1");
    const long = { cardId: "c".repeat(50), pipelines: ["p".repeat(40), "q".repeat(40)], ageMin: 999, sessionID: "s".repeat(50) };
    await seam("sendHaReapAlert")(env, long);
    assert.ok(String(calls[1].args.data.message).length <= 240, "the question-notify MAX_MESSAGE shape (240) is the alert truncation contract");
  });

  it("a rejecting callHA is swallowed — sendHaReapAlert never rejects (D11 fire-and-forget)", async () => {
    const env = baseEnv();
    const logged: string[] = [];
    env.log = (l: string) => void logged.push(l);
    env.callHA = async () => {
      throw new Error("ha refused");
    };
    let rejected = false;
    try {
      await seam("sendHaReapAlert")(env, { cardId: "c1", pipelines: ["a"], ageMin: 180, sessionID: "s1" });
    } catch {
      rejected = true;
    }
    assert.equal(rejected, false, "an alert failure must never surface to the caller — it would delay or fail the reap");
    void logged;
  });
});

describe("R7 moveCardToTimeout unit legs (AC 4)", () => {
  it("the happy sequence moves the card and comments with the 2h text naming the set", async () => {
    const env = baseEnv({ client: recordingClient() });
    env.notify = async () => {};
    await seam("moveCardToTimeout")(env, { cardId: "c1", pipelines: ["a", "b"], sessionID: "s1", setId: "set1" });
    const names = env.client.calls.map((c: any) => c.name);
    assert.deepEqual(names, ["get_card", "list_lists", "move_card", "add_comment"], "the task's exact resolution sequence");
    const move = env.client.calls.find((c: any) => c.name === "move_card").args;
    assert.equal(move.from_list_id, "L-exec", "from the card's current list");
    assert.equal(move.to_list_id, "L-timeout", "to the Timeout list in the card's swimlane — the SW-backlog namesake must not be picked");
    const comment = env.client.calls.find((c: any) => c.name === "add_comment");
    const text = JSON.stringify(comment.args);
    assert.match(text, /Timed out: no heartbeat for 2h/, "D21: the 2 h window is what the card says");
    assert.ok(!/3h/.test(text), "the retired 3 h wording must not resurface (D11 was superseded by D21)");
    assert.match(text, /pipelines: [^"]*\ba\b[^"]*\bb\b|\bb\b[^"]*\ba\b/, "the comment names every pipeline of the reaped claim");
    assert.match(text, /session[^\w]*s1/);
  });

  it("accepts the client FLAT ({callTool}) and NESTED ({api:{callTool}}) identically (C05 Minor-3, deviation-5 convergence)", async () => {
    // The suite header documented the flat shape while the fixture nests
    // under .api; the implementation tolerates both (flat checked FIRST).
    // Pin both arms against the SAME scenario so future drift — a
    // flat-only or nested-only refactor — goes red here, not silently in
    // production discovery. The live call-shapes addendum: add_comment's
    // body key is `comment`, so it rides here too.
    const outcomes: any[] = [];
    for (const shape of ["flat", "nested"]) {
      const rec = recordingClient();
      const env = baseEnv();
      env.client = shape === "flat" ? { callTool: rec.api.callTool } : rec.api;
      await seam("moveCardToTimeout")(env, { cardId: "c1", pipelines: ["a", "b"], sessionID: "s1", setId: "set1" });
      outcomes.push({
        names: rec.calls.map((c: any) => c.name),
        move: rec.calls.find((c: any) => c.name === "move_card")?.args,
        comment: JSON.stringify(rec.calls.find((c: any) => c.name === "add_comment")?.args),
      });
      assert.deepEqual(readTimeouts(env), [], `${shape}: a fully working client must never queue a degrade row`);
    }
    assert.deepEqual(outcomes[0].names, ["get_card", "list_lists", "move_card", "add_comment"], "flat arm keeps the D24 sequence");
    assert.deepEqual(outcomes[1].names, outcomes[0].names, "nested arm must converge on the same sequence");
    assert.deepEqual(outcomes[1].move, outcomes[0].move, "same move args from both shapes");
    assert.equal(outcomes[1].comment, outcomes[0].comment, "byte-identical comment leg from both shapes");
    assert.match(String(JSON.parse(outcomes[0].comment).comment ?? ""), /Timed out: no heartbeat for 2h/, "the comment body rides the `comment` key (live call-shape, reviewed (e))");
  });
});

describe("R8 module hygiene (AC 8)", () => {
  it("no credential, host or URL literal; the two server keys ride on named constants; staleMs is 2 h", () => {
    for (const banned of ["http://", "https://", "scifi.farm", "spencerslab", "Authorization", "token", "password"]) {
      assert.ok(!PLUGIN_SRC.includes(banned), `plugin source contains ${banned} — dev-boards mints its login server-side and HA discovery is runtime-only`);
    }
    assert.equal((PLUGIN_SRC.match(/"dev-boards"/g) ?? []).length, 1, "dev-boards appears once — as the named constant");
    assert.equal((PLUGIN_SRC.match(/"admin-global-homeassistant"/g) ?? []).length, 1, "admin-global-homeassistant appears once — as the named constant");
    assert.match(PLUGIN_SRC, /staleMs[^\n]*7200000/, "the staleMs default constant is 7200000 (D21)");
    assert.ok(!PLUGIN_SRC.includes("10800000"), "the 3 h window was ruled out — no trace may remain");
    assert.match(PLUGIN_SRC, /no heartbeat for 2h/, "the user-facing reap text carries the 2 h window");
  });
});

async function until(cond: () => boolean, _label = "", ms = 1500): Promise<void> {
  const deadline = Date.now() + ms;
  while (!cond()) {
    if (Date.now() > deadline) throw new Error(`condition not met (${_label}) within ${ms}ms`);
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

describe("R9 command executors route through the seams (AC 9)", () => {
  it("/pipeline-reap reaps and answers a summary; /pipeline-status answers the lock view", async () => {
    const runtimeDir = mkdtempSync("/tmp/opencode/pllocks-cmd.XXXXXX");
    const locksDir = join(runtimeDir, ".pipeline", "locks");
    mkdirSync(locksDir, { recursive: true });
    const staleAt = Date.now() - 3 * HOUR;
    writeFileSync(
      join(locksDir, "goner.json"),
      JSON.stringify({ version: 1, pipeline: "goner", cardId: "c1", setId: "set1", sessionID: "s1", pipelineSet: ["goner"], state: "live", heartbeatAt: new Date(staleAt).toISOString() }),
    );
    utimesSync(join(locksDir, "goner.json"), staleAt / 1000, staleAt / 1000);
    const seen: any = { cmdSpecs: [], promptCalls: [] };
    const ctx = {
      tool: { transform: async (fn: any) => void fn({ namespace: "", add: () => {} }), hook: async () => {} },
      command: { transform: async (fn: any) => void fn({ add: (s: any) => void seen.cmdSpecs.push(s) }) },
      event: { subscribe: () => ({ [Symbol.asyncIterator]: () => ({ next: async () => ({ value: undefined, done: true }) }) }) },
      session: { get: async () => undefined, prompt: async (a: any) => void seen.promptCalls.push(a), instructions: { entry: { put: async () => {}, remove: async () => {} } } },
      mcp: { list: async () => [] },
      location: { directory: runtimeDir },
    };
    const settled = await Promise.race([
      mod.default.setup(ctx),
      new Promise((r) => setTimeout(() => r("pending"), 2000)),
    ]);
    assert.notEqual(settled, "pending");
    const cleanup = settled;
    try {
      const cmdName = (s: any) => String(s.name).replace(/^\//, "");
      const reap = seen.cmdSpecs.find((s: any) => cmdName(s) === "pipeline-reap");
      const status = seen.cmdSpecs.find((s: any) => cmdName(s) === "pipeline-status");
      assert.ok(reap && status, `reap/status commands not registered, saw ${JSON.stringify(seen.cmdSpecs.map(cmdName))}`);
      const outReap = await reap.execute({ sessionID: "ses_cmd", prompt: "/pipeline-reap", delivery: "auto" });
      const reapText = seen.promptCalls.map((p: any) => p.text ?? "").join("\n") + String(outReap ?? "");
      assert.match(reapText, /reap/i, "the summary message names the reap");
      assert.ok(!existsSync(join(locksDir, "goner.json")), "the executor reaped through the real store");
      writeFileSync(
        join(locksDir, "alpha.json"),
        JSON.stringify({ version: 1, pipeline: "alpha", cardId: "cA", setId: "setA", sessionID: "sA", pipelineSet: ["alpha"], state: "live", heartbeatAt: new Date().toISOString() }),
      );
      const outStatus = await status.execute({ sessionID: "ses_cmd", prompt: "/pipeline-status", delivery: "auto" });
      const statusText = seen.promptCalls.map((p: any) => p.text ?? "").join("\n") + String(outStatus ?? "");
      assert.match(statusText, /alpha/, "the status message carries the lock view (set-grouped pipeline names)");
      rmSync(locksDir, { recursive: true, force: true });
    } finally {
      cleanup();
    }
  });
});

describe("R10 audit-line shape battery (C05 Tests-list leg, Minor-2 close)", () => {
  // "every events.log line parses as JSON with at + ev" was implicit until
  // now (readEvents JSON.parses the whole file, so a malformed line reddens
  // four legs indirectly). This leg makes it explicit AND pins the record
  // shape of the three reap-era audit classes against the suite's own
  // conventions, so a future appendEvent refactor that renames or drops a
  // correlating field fails here instead of silently breaking status/alert
  // forensics.
  function assertAuditLines(env: any, expectedEvents: string[]) {
    const raw = readFileSync(env.eventsPath, "utf8");
    const lines = raw.split("\n").filter((l) => l.trim());
    assert.ok(lines.length >= expectedEvents.length, `expected at least ${expectedEvents.length} audit lines, saw ${lines.length}`);
    const evs: string[] = [];
    for (const line of lines) {
      let obj: any;
      assert.doesNotThrow(() => (obj = JSON.parse(line)), `unparseable JSONL audit line: ${line.slice(0, 120)}`);
      assert.ok(typeof obj.ev === "string" && obj.ev.length > 0, "every audit line carries a non-empty ev");
      assert.ok(!Number.isNaN(Date.parse(obj.at)), `every audit line carries an ISO at, saw ${JSON.stringify(obj.at)}`);
      evs.push(obj.ev);
    }
    for (const want of expectedEvents) {
      assert.ok(evs.includes(want), `no ${want} line in the log, saw ${JSON.stringify(evs)}`);
    }
    return lines.map((l) => JSON.parse(l));
  }

  it("reaped, board_move_err and lock_lost records carry their contract fields beside at+ev", async () => {
    // (a) reap pass over a stale lock whose board leg rejects: the file
    // moves, the card degrades — both halves must be audited completely.
    const envA = baseEnv({ client: recordingClient({ get_card: new Error("board exploded") }) });
    envA.notify = async () => {};
    seedLock(envA, { pipeline: "aud", cardId: "cA", setId: "setA", sessionID: "sA", pipelineSet: ["aud"] }, 3 * HOUR);
    await seam("reapStale")(envA, { trigger: "command" });
    const recsA = assertAuditLines(envA, ["reaped", "board_move_err"]);
    const reaped = recsA.find((r) => r.ev === "reaped");
    for (const field of ["pipeline", "setId", "cardId", "sessionID", "ageMin", "trigger"]) {
      assert.ok(reaped[field] !== undefined, `the reaped record lost ${field} — status/alert correlation depends on it`);
    }
    assert.equal(typeof reaped.ageMin, "number");
    assert.equal(reaped.trigger, "command");
    const bme = recsA.find((r) => r.ev === "board_move_err");
    for (const field of ["cardId", "setId", "sessionID", "reason"]) {
      assert.ok(bme[field] !== undefined && String(bme[field]).length > 0, `board_move_err lost ${field} — the degrade must name why the card stayed`);
    }

    // (b) lock_lost from the engine path on this suite's env: a deleted
    // member under a live two-pipeline claim names the WHOLE set + cause
    // (D18 set-wide signal, reviewed C04 (b)).
    const envB = baseEnv();
    envB.sessToRoot = new Map();
    envB.executing = new Set();
    envB.lastBeat = new Map();
    envB.negative = new Map();
    seedLock(envB, { pipeline: "x1", cardId: "cB", setId: "setB", sessionID: "sB", pipelineSet: ["x1", "x2"] }, 60000);
    seedLock(envB, { pipeline: "x2", cardId: "cB", setId: "setB", sessionID: "sB", pipelineSet: ["x1", "x2"] }, 60000);
    envB.claims.set("sB", { setId: "setB", cardId: "cB", pipelineSet: ["x1", "x2"] });
    rmSync(join(envB.locksDir, "x1.json"));
    await seam("toolBefore")(envB, { tool: "read", sessionID: "sB" });
    const recsB = assertAuditLines(envB, ["lock_lost"]);
    const lost = recsB.find((r) => r.ev === "lock_lost");
    assert.equal(lost.setId, "setB");
    assert.equal(lost.cardId, "cB");
    assert.equal(lost.sessionID, "sB");
    assert.deepEqual([...lost.pipelineSet].sort(), ["x1", "x2"], "the lock_lost record names the whole lost set, not just the trigger member");
    assert.ok(typeof lost.cause === "string" && lost.cause.length > 0, "the cause half of the reviewed (b) shape");
    assert.deepEqual(lockFiles(envB), [], "the owned survivor is freed beside the audit");
  });
});
