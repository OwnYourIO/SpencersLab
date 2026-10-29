// C04 acceptance checks (2026/2026-10-cf-76-feat-parallel-pipeline-loops): the
// heartbeat & lifecycle engine — the 30 s throttle, set-wide lock-lost (D18),
// the strict lock-lost guard (D16), child-session mapping (handoff B.9), the
// idle-stale / execution lifecycle (D12, D20) and the cleanup contract — all
// driven offline through injected deps, a fake clock and fake timers. Covers
// chunks/C04.md AC 1-7; the core suite re-run and the four pre-existing
// suites are plan Commands duties.
//
// Human-stop policy (D20): there is NO waiting-detection machinery — the
// clock keeps ticking through stop points and an idle lock simply goes
// stale. This suite pins that absence (AC 6: the question/permission grep)
// as load-bearing as the presence of anything else.
//
// Run from the repo root: node --test tests/opencode/pipeline-locks-engine.test.ts
// (Node v26 type-strips; no build, no deps, no network — tmp dirs + fakes.)
//
// Red before C04: the engine seams are not exported yet — seam() names the
// missing export instead of failing as an ESM link error (the convention of
// this repo's tests/opencode suites). claimLockSet fixtures come from C03.
//
// SEAM CONTRACT — additions on top of the core contract (pipeline-locks-core.
// test.ts documents the store seams; the SAME env object flows into both):
//   engine seams take an env extended with:
//     sessToRoot: Map<sessionID, rootID>,  executing: Set<sessionID>,
//     lastBeat: Map<pipelineKey, epochMs>, negative: Map<sessionID, expiresAtMs>,
//     sessionGet(sessionID) -> Promise<{parentID?}|undefined>  (the ONLY
//       session-read dep — callers must defer it, never await it inline in
//       the event loop, handoff #55318),
//     timers?: {setInterval(fn, ms), clearInterval(h), setTimeout(fn, ms),
//       clearTimeout(h)}  (default real; faked here),
//     config: {staleMs, timerMs, reapEveryMs, hookThrottleMs,
//       releaseOnFailure, strictLockLoss, haNotify, maxWorkers}
//   resolveRoot(env, sessionID) -> Promise<string|null>
//     sessToRoot hit -> mapped root; else the deferred parent-walk over
//     sessionGet until a session holding a claim (env.claims) or a top
//     session; unknown -> the sessionID itself, cached negative for 60 s
//     (re-checked after env.advance past the window).
//   heartbeatSet(env, rootID, source, force) -> Promise<void>
//     every member of the root's claim (env.claims first, storage fallback):
//     non-forced beats are throttled 30 s PER pipelineKey; forced beats
//     always write. A re-read finding a missing or foreign-owned member
//     takes the lock-lost path (never a per-file half beat).
//   toolBefore(env, event{tool, sessionID}) / toolAfter(env, event)
//     beat the caller root's set (pipeline_* tools skipped — they beat via
//     their own executors); toolBefore additionally runs the strict guard:
//     for tools edit|write|bash on a lock-lost root it throws
//     Error("PIPELINE LOCK LOST — stop; do not commit or move the card")
//     (config strictLockLoss, default ON). Lock-lost itself marks a claim
//     lost when ANY member file is missing or stolen: delete the surviving
//     members at once (freeing those pipelines), clear maps/storage, audit
//     lock_lost naming the set, pin the STOP instruction; NEVER recreate a
//     file.
//   handleEvent(env, event) -> Promise<void>   (the for-await loop body just
//     dispatches into setTimeout(() => handleEvent(...), 0) — it must not
//     await session reads inline)
//     session.created|session.updated with a parentID under a locked root:
//     map child -> root (deferred resolveRoot), storage write, immediate
//     FORCE beat, audit child_mapped; parents without a lock map nothing.
//     session.execution.started: mark executing + force beat.
//     session.execution.succeeded / other terminals: clear executing —
//     succeeded NEVER releases the lock (turn end ≠ iteration end, B.9).
//     session.execution.failed|interrupted on a root: state:"failed" in
//     every member file + audit exec_failed, timer beats stop;
//     config.releaseOnFailure=true deletes the set immediately instead.
//     Payload reads are dual-read (data?.X ?? data?.info?.X). Non-session
//     events and unmapped sessions are ignored (#58707-safe).
//   runBeatTick(env) -> Promise<void>  the beat-timer body: beats only the
//     claims whose root OR a mapped descendant is in env.executing — idle
//     roots get nothing (D20: that is what lets human stops go stale).
//   startEngine(env) -> { stop() }  schedules the beat interval (env.config.
//     timerMs) and the reap interval (env.config.reapEveryMs ->
//     env.reapStale({trigger:"timer"})) through env.timers; stop() clears
//     every handle. setup's returned cleanup calls the same stop path and
//     aborts the event subscription.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
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

const T0 = Date.parse("2026-10-29T12:00:00Z");

function fakeTimers() {
  const intervals: any[] = [];
  const timeouts: any[] = [];
  const cleared: any[] = [];
  return {
    intervals,
    timeouts,
    cleared,
    api: {
      setInterval: (fn: any, ms: number) => {
        const h = { fn, ms, id: intervals.length };
        intervals.push(h);
        return h;
      },
      clearInterval: (h: any) => void cleared.push(h),
      setTimeout: (fn: any, ms: number) => {
        const h = { fn, ms, id: timeouts.length, fired: false };
        timeouts.push(h);
        return h;
      },
      clearTimeout: (h: any) => void cleared.push(h),
    },
    flushTimeouts() {
      const pending = timeouts.filter((t) => !t.fired);
      for (const t of pending) {
        t.fired = true;
        t.fn();
      }
    },
  };
}

function baseEnv(opts: any = {}) {
  const runtimeDir = mkdtempSync("/tmp/opencode/pllocks-engine.XXXXXX");
  const timers = fakeTimers();
  const sessionCalls: string[] = [];
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
    sessToRoot: new Map(),
    executing: new Set(),
    lastBeat: new Map(),
    negative: new Map(),
    storage: null,
    pin: opts.pin ?? null,
    reapStale: opts.reapStale ?? (async () => ({})),
    timers: opts.timers ?? timers.api,
    sessionGet: async (sessionID: string) => {
      sessionCalls.push(sessionID);
      if (opts.hangSessions?.includes(sessionID)) return new Promise(() => {});
      return opts.sessions?.[sessionID];
    },
    config: {
      staleMs: 7200000,
      timerMs: 300000,
      reapEveryMs: 600000,
      hookThrottleMs: 30000,
      releaseOnFailure: false,
      strictLockLoss: true,
      haNotify: true,
      maxWorkers: null,
      ...(opts.config ?? {}),
    },
  };
  return { env, timers, sessionCalls };
}

function fakePin() {
  const puts: any[] = [];
  const removes: any[] = [];
  return { puts, removes, api: { put: async (...a: any[]) => void puts.push(a), remove: async (...a: any[]) => void removes.push(a) } };
}

function lockFiles(env: any): string[] {
  if (!existsSync(env.locksDir)) return [];
  return readdirSync(env.locksDir).filter((n) => n.endsWith(".json")).sort();
}

function readRecord(env: any, key: string): any {
  return JSON.parse(readFileSync(join(env.locksDir, `${key}.json`), "utf8"));
}

function readEvents(env: any): any[] {
  if (!existsSync(env.eventsPath)) return [];
  return readFileSync(env.eventsPath, "utf8")
    .split("\n")
    .filter((l) => l.trim())
    .map((l) => JSON.parse(l));
}

async function claimed(env: any, sessionID: string, pipelines: string[], cardId = "card1") {
  const res = await seam("claimLockSet")(env, { cardId, pipelines, sessionID });
  assert.equal(res.ok, true, `fixture claim failed: ${JSON.stringify(res)}`);
  return res;
}

async function until(cond: () => boolean, ms = 1500): Promise<boolean> {
  const deadline = Date.now() + ms;
  while (!cond()) {
    if (Date.now() > deadline) return false;
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  return true;
}

describe("E1 heartbeatSet — throttle per pipelineKey, forced beats, whole-set beats (AC 2)", () => {
  it("three non-forced beats inside 30 s write the file once; the window's expiry writes again (AC 2)", async () => {
    const { env } = baseEnv();
    await claimed(env, "s1", ["a"]);
    const h0 = readRecord(env, "a").heartbeatAt;
    env.advance(1000);
    await seam("heartbeatSet")(env, "s1", "hook", false);
    const h1 = readRecord(env, "a").heartbeatAt;
    assert.notEqual(h1, h0, "the first beat after the claim must write");
    env.advance(10000);
    await seam("heartbeatSet")(env, "s1", "hook", false);
    env.advance(20000);
    await seam("heartbeatSet")(env, "s1", "hook", false);
    assert.equal(readRecord(env, "a").heartbeatAt, h1, "beats inside the 30 s throttle window must not rewrite");
    env.advance(10000); // 31 s after the accepted beat
    await seam("heartbeatSet")(env, "s1", "hook", false);
    assert.notEqual(readRecord(env, "a").heartbeatAt, h1, "the throttle window must expire after hookThrottleMs");
  });

  it("forced beats always write, even inside the window (AC 2)", async () => {
    const { env } = baseEnv();
    await claimed(env, "s1", ["a"]);
    env.advance(1);
    await seam("heartbeatSet")(env, "s1", "manual", true);
    const h1 = readRecord(env, "a").heartbeatAt;
    env.advance(1);
    await seam("heartbeatSet")(env, "s1", "manual", true);
    assert.notEqual(readRecord(env, "a").heartbeatAt, h1, "force bypasses the throttle (child_mapped, execution.started, pipeline_heartbeat)");
  });

  it("a two-pipeline claim gets BOTH member files beaten (AC 2)", async () => {
    const { env } = baseEnv();
    await claimed(env, "s1", ["a", "b"]);
    const before = [readRecord(env, "a").heartbeatAt, readRecord(env, "b").heartbeatAt];
    env.advance(5000);
    await seam("heartbeatSet")(env, "s1", "hook", false);
    assert.notEqual(readRecord(env, "a").heartbeatAt, before[0]);
    assert.notEqual(readRecord(env, "b").heartbeatAt, before[1], "heartbeatSet beats EVERY lock file of the claim set (D18)");
  });

  it("an unlocked session beating changes nothing (location isolation)", async () => {
    const { env } = baseEnv();
    await claimed(env, "s1", ["a"]);
    const h0 = readRecord(env, "a").heartbeatAt;
    env.advance(5000);
    await seam("heartbeatSet")(env, "ses-nobody", "hook", true);
    assert.equal(readRecord(env, "a").heartbeatAt, h0);
  });
});

describe("E2 lock-lost is SET-wide (AC 3, D18/D16)", () => {
  it("one member file deleted under a live 2-pipeline claim: the next hook audits lock_lost naming the set, deletes the survivor, clears the maps, pins the STOP message, recreates nothing", async () => {
    const pin = fakePin();
    const { env } = baseEnv({ pin: pin.api });
    const res = await claimed(env, "s1", ["a", "b"]);
    rmSync(join(env.locksDir, "a.json"));
    await seam("toolBefore")(env, { tool: "read", sessionID: "s1" });
    const evs = readEvents(env);
    const lost = evs.find((l) => l.ev === "lock_lost");
    assert.ok(lost, `no lock_lost audit line, saw ${JSON.stringify(evs.map((e) => e.ev))}`);
    assert.equal(lost.setId, res.setId);
    assert.deepEqual([...lost.pipelineSet].sort(), ["a", "b"], "the audit names the whole set");
    assert.deepEqual(lockFiles(env), [], "the surviving member is deleted immediately — those pipelines free up (D18)");
    assert.equal(env.claims.has("s1"), false, "maps/storage are cleared");
    const stop = pin.puts.filter((p: any[]) => p[1] === "pipeline-lock").pop();
    assert.ok(stop && /PIPELINE LOCK LOST/.test(stop[2]), "the pin is updated to the STOP instruction");
    env.advance(60000);
    await seam("heartbeatSet")(env, "s1", "hook", true);
    assert.deepEqual(lockFiles(env), [], "a lost claim is NEVER re-created (D18)");
  });

  it("with strictLockLoss ON the before-hook throws for edit/write/bash and only those tools (AC 3)", async () => {
    for (const [tool, shouldThrow] of [["edit", true], ["write", true], ["bash", true], ["read", false], ["grep", false], ["webfetch", false]] as const) {
      const { env } = baseEnv();
      await claimed(env, "s1", ["a"]);
      rmSync(join(env.locksDir, "a.json"));
      let err: any = null;
      try {
        await seam("toolBefore")(env, { tool, sessionID: "s1" });
      } catch (e) {
        err = e;
      }
      if (shouldThrow) {
        assert.ok(err && /PIPELINE LOCK LOST/.test(String(err.message)), `${tool}: expected the PIPELINE LOCK LOST throw, saw ${err}`);
      } else {
        assert.equal(err, null, `${tool}: the guard must stay off non-write tools`);
      }
      assert.ok(!existsSync(join(env.locksDir, "a.json")), "detection never recreates the file");
    }
  });

  it("a stolen member (foreign sessionID) takes the same set-wide path", async () => {
    const { env } = baseEnv();
    await claimed(env, "s1", ["a", "b"]);
    const rec = readRecord(env, "b");
    rec.sessionID = "s-thief";
    writeFileSync(join(env.locksDir, "b.json"), JSON.stringify(rec));
    await seam("toolBefore")(env, { tool: "read", sessionID: "s1" });
    assert.deepEqual(lockFiles(env), [], "a stolen member loses the WHOLE set");
    assert.ok(readEvents(env).some((l) => l.ev === "lock_lost"));
  });

  it("a session that holds no claim is never guarded and never lost", async () => {
    const { env } = baseEnv();
    await claimed(env, "s1", ["a"]);
    await seam("toolBefore")(env, { tool: "bash", sessionID: "ses-unlocked" });
    assert.deepEqual(lockFiles(env), ["a.json"]);
  });

  it("the guard also fires through a MAPPED CHILD session (root resolution)", async () => {
    const { env, timers } = baseEnv({ sessions: {} });
    await claimed(env, "s1", ["a"]);
    env.sessToRoot.set("ses_child", "s1");
    rmSync(join(env.locksDir, "a.json"));
    await assert.rejects(seam("toolBefore")(env, { tool: "edit", sessionID: "ses_child" }), /PIPELINE LOCK LOST/);
    void timers;
  });
});

describe("E3 child mapping via events (AC 4, handoff B.9)", () => {
  it("session.created under a locked root maps the child, force-beats the set and audits child_mapped (AC 4)", async () => {
    const { env } = baseEnv();
    await claimed(env, "s1", ["a", "b"]);
    env.advance(5000);
    const before = readRecord(env, "a").heartbeatAt;
    await seam("handleEvent")(env, { type: "session.created", data: { sessionID: "ses_c", parentID: "s1" } });
    assert.equal(env.sessToRoot.get("ses_c"), "s1");
    assert.notEqual(readRecord(env, "a").heartbeatAt, before, "the mapping force-beats every member immediately");
    assert.notEqual(readRecord(env, "b").heartbeatAt, before);
    assert.ok(readEvents(env).some((l) => l.ev === "child_mapped"), "the mapping is audited");
  });

  it("reads parentID from the info envelope too (dual-read, AC 4/6)", async () => {
    const { env } = baseEnv();
    await claimed(env, "s1", ["a"]);
    await seam("handleEvent")(env, { type: "session.created", data: { info: { sessionID: "ses_c2", parentID: "s1" } } });
    assert.equal(env.sessToRoot.get("ses_c2"), "s1");
  });

  it("session.updated first behaves identically to session.created (dual-event coverage, AC 4)", async () => {
    const { env } = baseEnv();
    await claimed(env, "s1", ["a"]);
    await seam("handleEvent")(env, { type: "session.updated", data: { sessionID: "ses_c3", parentID: "s1" } });
    assert.equal(env.sessToRoot.get("ses_c3"), "s1");
    assert.ok(readEvents(env).some((l) => l.ev === "child_mapped"));
  });

  it("a child of an unlocked or unknown parent maps nothing (location isolation, AC 4)", async () => {
    const { env } = baseEnv({ sessions: { ses_free: { id: "ses_free" } } });
    await claimed(env, "s1", ["a"]);
    env.advance(5000);
    const before = readRecord(env, "a").heartbeatAt;
    await seam("handleEvent")(env, { type: "session.created", data: { sessionID: "ses_x", parentID: "ses_free" } });
    await seam("handleEvent")(env, { type: "session.created", data: { sessionID: "ses_y", parentID: "ses-nowhere" } });
    assert.equal(env.sessToRoot.get("ses_x"), undefined, "a top-level unlocked parent must not adopt children into a foreign claim");
    assert.equal(env.sessToRoot.get("ses_y"), undefined);
    assert.equal(readRecord(env, "a").heartbeatAt, before, "unrelated children beat nothing");
    assert.ok(!readEvents(env).some((l) => l.ev === "child_mapped"));
  });

  it("resolveRoot walks the parent chain and caches negative results for 60 s (task: deferred parent-walk)", async () => {
    const { env, sessionCalls } = baseEnv({
      sessions: { ses_g: { id: "ses_g", parentID: "ses_f" }, ses_f: { id: "ses_f", parentID: "s1" } },
    });
    await claimed(env, "s1", ["a"]);
    assert.equal(await seam("resolveRoot")(env, "ses_g"), "s1", "a grandchild resolves through the chain to the locked root");
    const after = sessionCalls.length;
    assert.equal(await seam("resolveRoot")(env, "ses_g"), "s1");
    assert.equal(sessionCalls.length, after, "the resolved mapping is cached (sessToRoot)");
    await seam("resolveRoot")(env, "ses_top");
    const negCount = sessionCalls.length;
    await seam("resolveRoot")(env, "ses_top");
    assert.equal(sessionCalls.length, negCount, "a negative result is cached, not re-walked");
    env.advance(61000);
    await seam("resolveRoot")(env, "ses_top");
    assert.ok(sessionCalls.length > negCount, "the 60 s negative cache window expires");
  });
});

describe("E4 execution lifecycle — idle-stale, resume, failure (AC 5, D12/D20)", () => {
  it("an idle locked root gets ZERO timer beats; a started root beats again (D20 clock keeps ticking)", async () => {
    const { env } = baseEnv();
    await claimed(env, "s1", ["a"]);
    env.advance(300000);
    const h0 = readRecord(env, "a").heartbeatAt;
    await seam("runBeatTick")(env);
    assert.equal(readRecord(env, "a").heartbeatAt, h0, "no executing member -> no beat (this is what lets human stops and abandoned runs go stale)");
    await seam("handleEvent")(env, { type: "session.execution.started", data: { sessionID: "s1" } });
    env.advance(300000);
    await seam("runBeatTick")(env);
    assert.notEqual(readRecord(env, "a").heartbeatAt, h0, "activity resumes heartbeats — no special state in between (D20)");
  });

  it("a mapped CHILD's started beats the root's set (B.9 subagent keep-alive)", async () => {
    const { env } = baseEnv();
    await claimed(env, "s1", ["a"]);
    await seam("handleEvent")(env, { type: "session.created", data: { sessionID: "ses_c", parentID: "s1" } });
    await seam("handleEvent")(env, { type: "session.execution.started", data: { sessionID: "ses_c" } });
    env.advance(300000);
    const h0 = readRecord(env, "a").heartbeatAt;
    await seam("runBeatTick")(env);
    assert.notEqual(readRecord(env, "a").heartbeatAt, h0);
  });

  it("succeeded clears executing but NEVER releases the lock (B.9: turn end != iteration end)", async () => {
    const { env } = baseEnv();
    const res = await claimed(env, "s1", ["a"]);
    await seam("handleEvent")(env, { type: "session.execution.started", data: { sessionID: "s1" } });
    await seam("handleEvent")(env, { type: "session.execution.succeeded", data: { sessionID: "s1" } });
    env.advance(300000);
    const h0 = readRecord(env, "a").heartbeatAt;
    await seam("runBeatTick")(env);
    assert.equal(readRecord(env, "a").heartbeatAt, h0, "after a terminal event the root is idle again");
    assert.ok(existsSync(join(env.locksDir, "a.json")), "succeeded must not release — the release rides the Review move (D6)");
    assert.equal(lockFiles(env).length, 1);
    void res;
  });

  it("root failed/interrupted stamps state:failed in EVERY member file, stops beats, audits exec_failed (AC 5, D12)", async () => {
    for (const type of ["session.execution.failed", "session.execution.interrupted"]) {
      const { env } = baseEnv();
      await claimed(env, "s1", ["a", "b"]);
      await seam("handleEvent")(env, { type, data: { sessionID: "s1" } });
      assert.equal(readRecord(env, "a").state, "failed", `${type} must mark the set failed`);
      assert.equal(readRecord(env, "b").state, "failed");
      assert.ok(readEvents(env).some((l) => l.ev === "exec_failed"));
      env.advance(300000);
      const h0 = readRecord(env, "a").heartbeatAt;
      await seam("runBeatTick")(env);
      assert.equal(readRecord(env, "a").heartbeatAt, h0, "a failed lock stops receiving timer beats and goes stale for the reaper (releaseOnFailure:false)");
    }
  });

  it("with releaseOnFailure=true the whole set is deleted immediately instead (D12 config leg)", async () => {
    const { env } = baseEnv({ config: { releaseOnFailure: true } });
    await claimed(env, "s1", ["a", "b"]);
    await seam("handleEvent")(env, { type: "session.execution.failed", data: { sessionID: "s1" } });
    assert.deepEqual(lockFiles(env), [], "the flip releases at once — the card stays where it is, no reap");
    assert.equal(env.claims.has("s1"), false);
  });

  it("a CHILD's failure changes nothing on the root's locks (AC 5)", async () => {
    const { env } = baseEnv();
    await claimed(env, "s1", ["a"]);
    await seam("handleEvent")(env, { type: "session.created", data: { sessionID: "ses_c", parentID: "s1" } });
    const before = JSON.stringify(readRecord(env, "a"));
    await seam("handleEvent")(env, { type: "session.execution.failed", data: { sessionID: "ses_c", error: { type: "x" } } });
    assert.equal(JSON.stringify(readRecord(env, "a")), before, "only the ROOT's terminal events touch the set state");
  });

  it("unknown/foreign events are ignored without throwing", async () => {
    const { env } = baseEnv();
    await claimed(env, "s1", ["a"]);
    for (const ev of [
      { type: "session.idle", data: { sessionID: "s1" } },
      { type: "file.edited", data: { file: "x" } },
      { type: "session.execution.started", data: { sessionID: "ses-elsewhere" } },
      { type: "permission.updated", data: { sessionID: "s1" } },
    ]) {
      await seam("handleEvent")(env, ev);
    }
    assert.equal(lockFiles(env).length, 1);
  });
});

describe("E5 hooks — beat on tool execution, pipeline_* skip (task)", () => {
  it("toolAfter beats the caller root's set, and the pipeline_* tools themselves are skipped", async () => {
    const { env } = baseEnv();
    await claimed(env, "s1", ["a"]);
    env.advance(40000);
    const h0 = readRecord(env, "a").heartbeatAt;
    await seam("toolAfter")(env, { tool: "bash", sessionID: "s1" });
    assert.notEqual(readRecord(env, "a").heartbeatAt, h0);
    env.advance(40000);
    const h1 = readRecord(env, "a").heartbeatAt;
    await seam("toolBefore")(env, { tool: "pipeline_heartbeat", sessionID: "s1" });
    await seam("toolAfter")(env, { tool: "pipeline_claim", sessionID: "s1" });
    assert.equal(readRecord(env, "a").heartbeatAt, h1, "pipeline_* tool hooks would double-beat the executors — the hooks skip them");
  });
});

describe("E6 structural guards on the module text (AC 6)", () => {
  it("the for-await event loop never reads sessions or storage inline (#55318)", () => {
    const starts = [...PLUGIN_SRC.matchAll(/for await/g)].map((m) => m.index!);
    assert.ok(starts.length >= 1, "the engine must consume ctx.event through a for-await loop");
    for (const at of starts) {
      const window = PLUGIN_SRC.slice(at, at + 700);
      assert.ok(!/session\.get\(|sessionGet\(/.test(window), "#55318: a session read textually inside the event-loop window — dispatch through the deferred path");
      assert.ok(!/storage\s*[.\[]\s*get/.test(window), "storage reads inline in the loop body are forbidden — same hang class");
    }
    assert.ok(/setTimeout\(/.test(PLUGIN_SRC), "the deferral idiom is setTimeout(..., 0) (C04 Tasks: ALL session reads deferred)");
  });

  it("payload reads use the dual-read envelope idiom (AC 6)", () => {
    assert.ok(/\?\.[A-Za-z_]*[Ii]nfo/.test(PLUGIN_SRC) || /data\?\./.test(PLUGIN_SRC), "no dual-read (`d?.X ?? d?.info?.X`) envelope reads found");
  });

  it("question/permission waiting machinery stayed EXCISED (D20, AC 6)", () => {
    for (const line of PLUGIN_SRC.split("\n")) {
      const t = line.trim();
      const isComment = t.startsWith("//") || t.startsWith("*") || t.startsWith("/*");
      for (const banned of ["question", "permission"]) {
        if (line.toLowerCase().includes(banned)) {
          assert.ok(isComment, `non-comment line mentions "${banned}" — the waiting-detection machinery was rejected with the keep-alive design (D20)`);
        }
      }
    }
  });

  it("no OS cron, no keep-alive-through-stop machinery textually (D20, out-of-scope guard)", () => {
    assert.ok(!/crontab|node-cron/i.test(PLUGIN_SRC), "an OS-level reaper is out of scope (plan)");
  });
});

describe("E7 timers + cleanup (AC 7, task: both timers cleared)", () => {
  it("startEngine schedules the beat (timerMs) and reap (reapEveryMs) intervals and stop() clears them all (AC 7)", async () => {
    const { env, timers } = baseEnv();
    const engine = seam("startEngine")(env);
    const beat = timers.intervals.find((i: any) => i.ms === env.config.timerMs);
    const reap = timers.intervals.find((i: any) => i.ms === env.config.reapEveryMs);
    assert.ok(beat, `beat interval at ${env.config.timerMs}ms missing, saw ${JSON.stringify(timers.intervals.map((i: any) => i.ms))}`);
    assert.ok(reap, `reap interval at ${env.config.reapEveryMs}ms missing`);
    engine.stop();
    assert.equal(timers.cleared.length, timers.intervals.length, "cleanup clears every timer it started");
  });

  it("the reap timer fires the reap hook with a trigger (C04 timer -> C05 reaper)", async () => {
    const reaps: any[] = [];
    const { env, timers } = baseEnv({ reapStale: async (input: any) => void reaps.push(input) });
    const engine = seam("startEngine")(env);
    const reap = timers.intervals.find((i: any) => i.ms === env.config.reapEveryMs);
    await reap.fn();
    assert.equal(reaps.length, 1);
    assert.equal(typeof reaps[0].trigger, "string");
    engine.stop();
  });

  it("timer callbacks swallow their own errors — an unhandled rejection kills the host", async () => {
    const { env, timers } = baseEnv({ reapStale: async () => { throw new Error("boom"); } });
    const engine = seam("startEngine")(env);
    const reap = timers.intervals.find((i: any) => i.ms === env.config.reapEveryMs);
    await reap.fn(); // must resolve quietly
    engine.stop();
  });
});

describe("E8 setup wiring — subscribe shape, deferral under a hung read, abort on cleanup (AC 6, AC 7)", () => {
  function makeStream() {
    const queue: any[] = [];
    let waiting: ((r: any) => void) | null = null;
    let closed = false;
    const iterable = {
      [Symbol.asyncIterator]() {
        return {
          next() {
            if (queue.length) return Promise.resolve({ value: queue.shift(), done: false });
            if (closed) return Promise.resolve({ value: undefined, done: true });
            return new Promise((resolve) => {
              waiting = resolve;
            });
          },
          return() {
            closed = true;
            return Promise.resolve({ value: undefined, done: true });
          },
        };
      },
    };
    return {
      iterable,
      push(event: any) {
        const resolve = waiting;
        waiting = null;
        if (resolve) resolve({ value: event, done: false });
        else queue.push(event);
      },
      stop() {
        closed = true;
        const resolve = waiting;
        waiting = null;
        if (resolve) resolve({ value: undefined, done: true });
      },
    };
  }

  function fakeCtx(opts: any) {
    const seen: any = { subscribeArgs: [], hookNames: [], toolSpecs: [] };
    const ctx = {
      tool: {
        transform: async (fn: any) => {
          await fn({ namespace: "", add: (s: any) => void seen.toolSpecs.push(s) });
        },
        hook: async (name: string, _h: any) => {
          seen.hookNames.push(name);
        },
      },
      command: { transform: async (fn: any) => void fn({ add: () => {} }) },
      event: {
        subscribe: (arg: any) => {
          seen.subscribeArgs.push(arg);
          return opts.events;
        },
      },
      session: {
        get: opts.sessionGet,
        prompt: async () => {},
        instructions: { entry: { put: async () => {}, remove: async () => {} } },
      },
      mcp: { list: async () => [] },
      storage: opts.storage,
      location: { directory: opts.runtimeDir },
    };
    return { ctx, seen };
  }

  it("subscribes with a signal and WITHOUT a types filter (v2.1.4, DECISIONS)", async () => {
    const runtimeDir = mkdtempSync("/tmp/opencode/pllocks-engine-ctx.XXXXXX");
    const stream = makeStream();
    const { ctx, seen } = fakeCtx({ events: stream.iterable, runtimeDir, sessionGet: async () => undefined });
    let cleanup: any;
    try {
      cleanup = await Promise.race([
        mod.default.setup(ctx),
        new Promise((_r, rej) => setTimeout(() => rej(new Error("setup blocked on the event loop")), 2000)),
      ]);
      assert.ok(await until(() => seen.subscribeArgs.length > 0), "setup must subscribe to ctx.event");
      const arg = seen.subscribeArgs[0];
      assert.equal(typeof arg?.signal?.addEventListener, "function", "subscribe must pass { signal }");
      assert.ok(!("types" in arg), "the types filter is >=2.2.0 — subscribing with it on 2.1.4 would silently drop events (AC 6)");
      assert.ok(seen.hookNames.includes("execute.before") && seen.hookNames.includes("execute.after"), `tool hooks missing, saw ${JSON.stringify(seen.hookNames)}`);
    } finally {
      stream.stop();
      if (cleanup) cleanup();
    }
  });

  it("a never-settling session read must not stall the loop — later events still get consumed (AC 6, #55318)", async () => {
    const runtimeDir = mkdtempSync("/tmp/opencode/pllocks-engine-hang.XXXXXX");
    const stream = makeStream();
    // Every session read hangs forever: if the loop awaited anything inline,
    // it would stop consuming and this test would time out red — the honest
    // offline repro of the #55318 stall class.
    const sessionGet = () => new Promise(() => {});
    const { ctx, seen } = fakeCtx({ events: stream.iterable, runtimeDir, sessionGet });
    let consumed = 0;
    const countingStream = {
      [Symbol.asyncIterator]: () => {
        const it = stream.iterable[Symbol.asyncIterator]();
        return {
          next: async (...a: any[]) => {
            consumed++;
            return (it as any).next(...a);
          },
        };
      },
    };
    ctx.event.subscribe = (arg: any) => {
      seen.subscribeArgs.push(arg);
      return countingStream;
    };
    let cleanup: any;
    try {
      cleanup = await Promise.race([
        mod.default.setup(ctx),
        new Promise((_r, rej) => setTimeout(() => rej(new Error("setup blocked")), 2000)),
      ]);
      await until(() => seen.subscribeArgs.length > 0);
      for (const id of ["ses_h1", "ses_h2", "ses_h3"]) {
        stream.push({ type: "session.created", data: { sessionID: id, parentID: `p_hang_${id}` } });
        assert.ok(
          await until(() => consumed >= 1 + ["ses_h1", "ses_h2", "ses_h3"].indexOf(id) + 1),
          `the loop stalled after a pushed event — an inline await on the hanging session read (#55318)`,
        );
      }
    } finally {
      stream.stop();
      if (cleanup) cleanup();
    }
  });

  it("cleanup aborts the subscription signal (AC 7)", async () => {
    const runtimeDir = mkdtempSync("/tmp/opencode/pllocks-engine-clean.XXXXXX");
    const stream = makeStream();
    const { ctx, seen } = fakeCtx({ events: stream.iterable, runtimeDir, sessionGet: async () => undefined });
    const cleanup = await Promise.race([
      mod.default.setup(ctx),
      new Promise((_r, rej) => setTimeout(() => rej(new Error("setup blocked")), 2000)),
    ]);
    await until(() => seen.subscribeArgs.length > 0);
    stream.stop();
    cleanup();
    assert.equal(seen.subscribeArgs[0]?.signal?.aborted, true, "cleanup must abort the event stream");
  });
});
