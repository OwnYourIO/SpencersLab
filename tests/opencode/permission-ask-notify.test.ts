// C03 acceptance checks (2026-10-feat-ha-lifecycle-notify): the pending-only
// approval push. The user's OpenChamber client runs "Permissions: accept
// everything": the server publishes permission.asked and the client answers in
// milliseconds, so C02's push-on-arrival rang the phone for asks nobody was
// waiting on (live bug report, 2026-10-27). Contract: permission.asked starts a
// timer keyed by the request id; a permission.replied for that id — ANY reply
// value, every server resolution path emits it (plan Grounding #13/#14) —
// cancels the pending push; the push fires only if the ask is still pending
// when the timer expires. The cooldown gate moved to the push attempt, so the
// timer callback — not the arrival — consults allowPush, and a cancelled ask
// consumes nothing (DECISIONS 2026-10-27).
//
// This file supersedes its own C02 version in place. permission.replied is no
// longer an ignored type: it is wired for cancellation, pinned by D2/D3.
// approvalTitle / approvalExcerpt / handlePermission keep their C02 seam shape;
// the timer plumbing travels inside the deps object (AC 3: no new exports).
//
// Covers AC 7–14 of chunks/C03.md. AC 1–6 and 15 are the plan-file Commands
// (node --test counts, the md5 pin, load+shape, grep pins, env-read placement),
// run by review — not this file. The legacy question-notify.test.ts is
// byte-pinned and owns every question/lifecycle re-test.
//
// Offline determinism (AC 1: no test sleeps ≥ 15 s): seam-level tests inject
// fake schedule/cancel/timers/pendingMs into handlePermission and invoke the
// recorded callback by hand — the 15000 default is asserted as a value, never
// slept; setup-level tests use the OPENCODE_NOTIFY_PENDING_MS env knob, set
// before each openSetup (read inside setup per AC 15) and always unset in a
// finally so the knob cannot leak between tests.
//
// Fixture shapes come from v2.1.4 grounding: asked nests Permission.Request
// fields {id, sessionID, action, resources, message?, metadata?} under `data`
// (the V1 twin swaps permission/patterns but keeps `id`); replied carries
// {sessionID, requestID, reply} with identical field names in both envelope
// twins (Grounding #13) — only the nesting position varies, so every fixture
// below exists in a nested and a flat shape. No agent name rides on the ask:
// the title comes from a session lookup, and only at fire time.
//
// Everything stays offline: fakes are the only collaborators, and the
// setup-level ctx keeps haMcpUrl on its no-URL path so nothing can open a
// socket. Every push attempt therefore logs exactly one "no URL found" line
// from sendHANotify — the single transport chokepoint the question and approval
// paths share — so those lines count as pushes here.
//
// Run from the repo root: node --test 'tests/opencode/*.test.ts' — the glob is
// quoted because a bare `tests/opencode` directory argument fails under this
// Node build (FRICTION 2026-10-26).

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import * as plugin from "../../.opencode/plugin/question-notify/index.ts";

const MAX = 240;
const LONG = "a".repeat(300);
// The PENDING_NOTIFY_MS constant, pinned as the deps.pendingMs the seam must
// schedule with. It is compared, never awaited.
const PENDING_MS = 15000;

// Namespace import, so a module that has not grown the timer deps yet fails on
// the seam() / fireScheduled() assertions below rather than as an ESM link
// error — a link error would take every other test in this file down with it
// and read as broken scaffolding (same reason C01 adopted it).
const mod = plugin as Record<string, any>;

function seam(name: string): (...args: any[]) => any {
  const fn = typeof mod[name] === "function" ? mod[name] : mod.default?.[name];
  if (typeof fn !== "function") {
    throw new Error(
      `plugin seam "${name}" is not exported (chunks/C03.md: handlePermission keeps its export; the timer deps travel inside the deps object)`,
    );
  }
  return fn;
}

const topSession = (agent = "agent-coord") => ({ id: "ses_top", agent, title: "top" });
const childSession = (agent = "agent-test") => ({
  id: "ses_child",
  agent,
  title: "child",
  parentID: "ses_top",
});

// `flat` moves the payload to the envelope root (the compat twin shape C01's
// dual read covers); the V1 twin replaces action/resources with
// permission/patterns but keeps the required `id` field (plan Grounding #10/#16
// — the timer key exists in both twins).
const asked = (sessionID: string, overrides: any = {}) => {
  const { flat, ...payload } = overrides;
  const data = { id: "per_test1", sessionID, action: "shell", resources: ["ls -la"], ...payload };
  return flat ? { type: "permission.asked", ...data } : { type: "permission.asked", data };
};

const replied = (requestID: string | undefined, sessionID: string, reply = "once", flat = false, extra: any = {}) => {
  const data: any = { sessionID, reply, ...extra };
  if (requestID !== undefined) data.requestID = requestID;
  return flat ? { type: "permission.replied", ...data } : { type: "permission.replied", data };
};

// The C03 deps contract (chunks/C03.md Tasks): schedule/cancel/timers/pendingMs
// joined the C02 getSession/notify/allowPush. The fake records the callback
// instead of arming anything, so fire-path tests stay instant and deterministic;
// a throwing dep simulates a collaborator failure at exactly one seam call.
function fakePermissionDeps(opts: any = {}) {
  const calls: any = { allowPush: [], getSession: [], notify: [], scheduled: [], cancelled: [] };
  const timers = new Map<string, any>();
  let seq = 0;
  const deps = {
    timers,
    pendingMs: opts.pendingMs === undefined ? PENDING_MS : opts.pendingMs,
    schedule: (fn: any, ms: number) => {
      if (opts.scheduleThrows) throw new Error("schedule boom");
      const handle = { fn, ms, seq: ++seq };
      calls.scheduled.push(handle);
      return handle;
    },
    cancel: (handle: any) => {
      calls.cancelled.push(handle);
      if (opts.cancelThrows) throw new Error("cancel boom");
    },
    allowPush: (key: string) => {
      calls.allowPush.push(key);
      if (typeof opts.gate === "function") return !!(opts.gate as any)(key);
      return opts.gate === undefined ? true : !!opts.gate;
    },
    getSession: async (sessionID: string) => {
      calls.getSession.push(sessionID);
      if (opts.getSessionThrows) throw new Error("session lookup failed");
      return typeof opts.getSession === "function" ? opts.getSession(sessionID) : undefined;
    },
    notify: async (title: string, message: string) => {
      calls.notify.push({ title, message });
      if (opts.notifyRejects) throw new Error("notify boom");
    },
  };
  return { deps, calls };
}

// Mirrors the production gate's observable contract (first call per key stamps
// and allows, repeats deny). The seam tests must prove WHEN the gate is
// consulted — at the push attempt, not at arrival — which is call-site timing,
// not window arithmetic; the window itself is proven at setup level by P4
// against the real closure.
function makeStampingGate() {
  const seen: string[] = [];
  const stamped = new Set<string>();
  return {
    seen,
    allowPush: (key: string) => {
      seen.push(key);
      if (stamped.has(key)) return false;
      stamped.add(key);
      return true;
    },
  };
}

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

// Mirrors the plugin ctx surface setup() consumes, extended over C01's T8 fake
// to CAPTURE the execute.before handler: proving the cooldown map is one
// instance shared by the question hook and the fired approval path is only
// possible when both run against the same setup() closure.
function fakeSetupCtx(opts: any = {}) {
  const seen: any = { hookNames: [], hooks: {}, subscribeArgs: [], sessionIDs: [] };
  const ctx = {
    tool: {
      hook: async (name: string, handler: any) => {
        seen.hookNames.push(name);
        seen.hooks[name] = handler;
      },
    },
    event: {
      subscribe: (arg: any) => {
        seen.subscribeArgs.push(arg);
        return (
          opts.events ?? {
            [Symbol.asyncIterator]: () => ({ next: async () => ({ value: undefined, done: true }) }),
          }
        );
      },
    },
    session: {
      get: async (arg: any) => {
        const sessionID = arg?.sessionID ?? arg;
        seen.sessionIDs.push(sessionID);
        if (Array.isArray(opts.getThrowsFor) && opts.getThrowsFor.includes(sessionID)) {
          throw new Error(`lookup failed for ${sessionID}`);
        }
        return opts.sessions?.[sessionID];
      },
      context: async (arg: any) => {
        const sessionID = arg?.sessionID ?? arg;
        return opts.messages?.[sessionID] ?? [];
      },
    },
    // Empty list plus a directory with no opencode.jsonc keeps haMcpUrl on its
    // no-URL path, so a test that reaches the notify helper cannot open a socket.
    mcp: { list: async () => [] },
    location: { directory: "/tmp/opencode/question-notify-no-config" },
  };
  return { ctx, seen };
}

async function until(cond: () => boolean, ms = 1000): Promise<boolean> {
  const deadline = Date.now() + ms;
  while (!cond()) {
    if (Date.now() > deadline) return false;
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  return true;
}

// For the "must stay silent" cases: a late push is still a contract violation,
// so give the fire-and-forget chain time to reach the transport before counting.
async function settle() {
  await new Promise((resolve) => setTimeout(resolve, 50));
}

// Every plugin log goes to console.error; the returned handle restores it in
// the caller's finally so a leak can never silence a later test.
function captureErrors() {
  const lines: string[] = [];
  const original = console.error;
  console.error = (...args: any[]) => {
    lines.push(args.map(String).join(" "));
  };
  return { lines, restore: () => { console.error = original; } };
}

const pushAttempts = (lines: string[]) => lines.filter((l) => l.includes("no URL found")).length;

// The env knob exists so the REAL setTimeout path is testable without ever
// waiting out PENDING_NOTIFY_MS (AC 1/15); restoring in a finally stops the
// knob leaking between tests.
async function withKnob(value: string | null, body: () => Promise<void>) {
  const saved = process.env.OPENCODE_NOTIFY_PENDING_MS;
  if (value === null) delete process.env.OPENCODE_NOTIFY_PENDING_MS;
  else process.env.OPENCODE_NOTIFY_PENDING_MS = value;
  try {
    await body();
  } finally {
    if (saved === undefined) delete process.env.OPENCODE_NOTIFY_PENDING_MS;
    else process.env.OPENCODE_NOTIFY_PENDING_MS = saved;
  }
}

async function runPermission(deps: any, event: any) {
  let error: any = null;
  try {
    await seam("handlePermission")(deps, event);
  } catch (err) {
    error = err;
  }
  return error;
}

// Invokes the timer callback the fake schedule recorded. The presence assert
// runs first so the pre-dev absence of the seam fails here with the AC-7
// message instead of a TypeError — a broken-scaffolding red would hide that
// the wiring, not the harness, is what is missing.
async function fireScheduled(calls: any, index: number, id: string) {
  const handle = calls.scheduled[index];
  assert.ok(
    handle,
    `no timer scheduled for request id ${id}: asked must register deps.schedule(fn, pendingMs), not push on arrival (AC 7) — recorded schedules ${calls.scheduled.length}, pushes ${calls.notify.length}`,
  );
  assert.equal(typeof handle.fn, "function", "deps.schedule must be called with the push callback");
  let error: any = null;
  try {
    await handle.fn();
  } catch (err) {
    error = err;
  }
  assert.equal(error, null, `the timer callback must never reject (AC 12): ${error?.message ?? error}`);
  await settle();
  return handle;
}

// Bounded: a loop awaited inside setup never settles against a still-open
// stream, and would hang the run rather than report the contract it breaks.
async function openSetup(ctx: any) {
  const pending = Symbol("setup still pending");
  const settled = await Promise.race([
    mod.default.setup(ctx),
    new Promise((resolve) => setTimeout(() => resolve(pending), 1000)),
  ]);
  assert.notEqual(settled, pending, "setup must return while the event stream is still open");
  return settled;
}

describe("R1 regression + permission seam export (AC 3, unedited pins)", () => {
  it("keeps the plugin loadable with its verified default-export shape", async () => {
    assert.equal(mod.default?.id, "local.question-notify");
    assert.equal(typeof mod.default?.setup, "function");
  });

  it("exports handlePermission alongside the C01 lifecycle seam", () => {
    for (const name of ["handlePermission", "approvalTitle", "approvalExcerpt", "handleLifecycle"]) {
      assert.equal(typeof seam(name), "function", `${name} must be exported (plan Commands load+shape check)`);
    }
  });
});

describe("P1 approvalTitle (AC 14: byte-unchanged despite the deferral)", () => {
  it("builds the needs-approval title from the agent name", () => {
    assert.equal(seam("approvalTitle")("agent-dev"), "OpenCode: agent-dev needs approval");
    assert.equal(seam("approvalTitle")("build"), "OpenCode: build needs approval");
  });
});

describe("P2 approvalExcerpt precedence (pure helper, unchanged; fired pushes re-run tiers in D1/P3/D5)", () => {
  it("prefers a non-empty message over every other field", () => {
    const excerpt = seam("approvalExcerpt");
    assert.equal(
      excerpt({ message: "approve deploy to prod", action: "shell", resources: ["rm -rf /"] }),
      "approve deploy to prod",
    );
  });

  it("joins the action with the resources when there is no message", () => {
    assert.equal(seam("approvalExcerpt")({ action: "shell", resources: ["rm -rf x"] }), "shell: rm -rf x");
  });

  it("keeps at most the first three resources", () => {
    assert.equal(
      seam("approvalExcerpt")({ action: "edit", resources: ["a", "b", "c", "d", "e"] }),
      "edit: a, b, c",
    );
  });

  it("degrades to the action word alone for empty, absent or non-string resources", () => {
    const excerpt = seam("approvalExcerpt");
    assert.equal(excerpt({ action: "read" }), "read");
    assert.equal(excerpt({ action: "grep", resources: [] }), "grep");
    assert.equal(excerpt({ action: "edit", resources: undefined }), "edit");
    assert.equal(excerpt({ action: "grep", resources: [null, 42, "real"] }), "grep: real");
  });

  it("uses the V1-compat permission/patterns twin only when the V2 fields are absent", () => {
    const excerpt = seam("approvalExcerpt");
    assert.equal(excerpt({ permission: "bash", patterns: ["git *"] }), "bash: git *");
    assert.equal(excerpt({ permission: "edit", patterns: ["p1", "p2", "p3", "p4", "p5"] }), "edit: p1, p2, p3");
    assert.equal(excerpt({ permission: "bash" }), "bash");
    assert.equal(
      excerpt({ action: "shell", resources: ["ls"], permission: "bash", patterns: ["git *"] }),
      "shell: ls",
    );
  });

  it("falls back to \"permission request\" when nothing readable is present", () => {
    const excerpt = seam("approvalExcerpt");
    for (const payload of [undefined, null, {}, { message: 42, action: {} }, { message: "", action: 7, resources: [] }]) {
      assert.equal(excerpt(payload), "permission request", `payload ${JSON.stringify(payload)}`);
    }
  });

  it("never renders metadata", () => {
    const excerpt = seam("approvalExcerpt");
    assert.equal(
      excerpt({ message: "", action: "edit", metadata: { filepath: "meta/only.ts", diff: LONG } }),
      "edit",
    );
    assert.equal(
      excerpt({
        action: "edit",
        resources: ["src/a.ts"],
        metadata: { filepath: "meta/only.ts", diff: "SECRET-DIFF-TEXT" },
      }),
      "edit: src/a.ts",
    );
  });
});

// C02's asked matrix rewritten for the deferred contract: every "asked pushes"
// case becomes "asked schedules, the fired callback pushes" (AC 7), and the
// ignored-types list DROPS permission.replied — replies cancel instead of being
// ignored, pinned by D2/D3 (DECISIONS 2026-10-27 inverted C02's pin by design).
describe("P3 dispatch matrix: asked schedules, the fired push carries C02's content contract (AC 7)", () => {
  it("pushes for a child session too — scope-all-sessions (DECISIONS 2026-10-26)", async () => {
    const { deps, calls } = fakePermissionDeps({ getSession: async () => childSession() });
    assert.equal(await runPermission(deps, asked("ses_child")), null);
    await fireScheduled(calls, 0, "per_test1");
    assert.equal(calls.notify.length, 1, "a subagent whose ask stays pending must still reach the phone");
    assert.equal(calls.notify[0].title, "OpenCode: agent-test needs approval");
  });

  it("pushes with the session fallback label when the lookup rejects", async () => {
    const { deps, calls } = fakePermissionDeps({ getSessionThrows: true });
    assert.equal(await runPermission(deps, asked("ses_gone")), null);
    await fireScheduled(calls, 0, "per_test1");
    assert.equal(calls.notify.length, 1, "dropping an approval push is the worst outcome (DECISIONS lookup-failure policy)");
    assert.equal(calls.notify[0].title, "OpenCode: session needs approval");
  });

  it("pushes with the session fallback label when the record carries no agent", async () => {
    const gone = fakePermissionDeps({ getSession: async () => undefined });
    assert.equal(await runPermission(gone.deps, asked("ses_deleted")), null);
    await fireScheduled(gone.calls, 0, "per_test1");
    assert.equal(gone.calls.notify.length, 1);
    assert.equal(gone.calls.notify[0].title, "OpenCode: session needs approval");

    const noAgent = fakePermissionDeps({ getSession: async () => ({ id: "ses_x", title: "x" }) });
    assert.equal(await runPermission(noAgent.deps, asked("ses_x", { id: "per_noagent" })), null);
    await fireScheduled(noAgent.calls, 0, "per_noagent");
    assert.equal(noAgent.calls.notify.length, 1);
    assert.equal(noAgent.calls.notify[0].title, "OpenCode: session needs approval");
  });

  it("caps the fired push body at 240 characters (excerpt rendered from the asked payload, not the reply)", async () => {
    const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession() });
    assert.equal(await runPermission(deps, asked("ses_top", { message: LONG })), null);
    await fireScheduled(calls, 0, "per_test1");
    assert.equal(calls.notify.length, 1);
    assert.equal(calls.notify[0].message, LONG.slice(0, MAX));
  });

  it("consults the cooldown gate at the push attempt and bails before the lookup when it says no", async () => {
    const { deps, calls } = fakePermissionDeps({ gate: false, getSession: async () => topSession() });
    assert.equal(await runPermission(deps, asked("ses_top")), null);
    assert.equal(calls.allowPush.length, 0, "arrival must not consult the gate — a cancelled ask must not consume a stamp (AC 9)");
    await fireScheduled(calls, 0, "per_test1");
    assert.deepEqual(calls.allowPush, ["ses_top"], "the gate keys on the asked session at fire time");
    assert.equal(calls.notify.length, 0);
    assert.equal(calls.getSession.length, 0, "gate-before-lookup ordering survives verbatim INSIDE the deferred path (DECISIONS 2026-10-27)");
  });

  it("ignores every non-permission event type, scheduling nothing and cancelling nothing", async () => {
    const ignored = [
      "session.execution.succeeded",
      "session.execution.failed",
      "session.idle",
      "form.created",
      "unknown.future.event",
    ];
    for (const type of ignored) {
      const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession() });
      const event = { type, data: { id: "per_x", sessionID: "ses_top", action: "shell", resources: ["ls"], message: "hi" } };
      assert.equal(await runPermission(deps, event), null, `${type} must not throw`);
      await settle();
      assert.equal(calls.notify.length, 0, `${type} must not push`);
      assert.equal(calls.scheduled.length, 0, `${type} must not start a pending timer`);
      assert.equal(calls.cancelled.length, 0, `${type} must not cancel a pending timer — only a matching permission.replied does (chunks/C03.md Notes for dev)`);
      assert.equal(deps.timers.size, 0, `${type} must leave the timers map untouched`);
    }
  });
});

// AC 9 at the transport boundary, with the REAL setup-closure gate: one Map
// instance shared by the question hook and the fired approval path is only
// provable when both run in one setup(). The zero-push/zero-lookup check inside
// the arrival→fire window is what keeps this non-vacuous: C02's code pushed and
// looked up at arrival, so it fails here instead of silently matching counts
// (the vacuation the plan Risks entry warns about).
describe("P4 shared cooldown at setup level via the env knob (AC 9)", () => {
  it("question push, then a same-session ask that fires is denied while a fresh session's fired ask pushes", async () => {
    // 40ms (chunk suggested 20): the early window-check needs a margin over
    // until()'s 5ms poll so a fired early-enough cannot read as a miss.
    await withKnob("40", async () => {
      const stream = makeStream();
      const { ctx, seen } = fakeSetupCtx({
        events: stream.iterable,
        sessions: { ses_b: { id: "ses_b", agent: "agent-dev", title: "b" } },
      });
      const cap = captureErrors();
      let cleanup: any;
      try {
        cleanup = await openSetup(ctx);
        const hook = seen.hooks["execute.before"];
        assert.equal(typeof hook, "function", "setup must keep registering the question tool hook");

        await hook({
          tool: "question",
          sessionID: "ses_a",
          agent: "agent-coord",
          input: { questions: [{ question: "approve the plan?" }] },
        });
        assert.ok(
          await until(() => pushAttempts(cap.lines) >= 1),
          "the question path must keep pushing on attempt, undelayed (chunks/C03.md: question hook unchanged)",
        );
        const questionStamp = cap.lines.length;

        stream.push(asked("ses_a", { id: "per_a2" }));
        stream.push(asked("ses_b", { id: "per_b3" }));
        await new Promise((resolve) => setTimeout(resolve, 10));
        assert.equal(pushAttempts(cap.lines), 1, `asked must defer the push to the pending timer (AC 7) — saw pushes: ${JSON.stringify(cap.lines.slice(0, questionStamp + 2))}`);
        assert.ok(!seen.sessionIDs.includes("ses_a") && !seen.sessionIDs.includes("ses_b"), `arrival must not look up sessions (AC 7/9), saw ${JSON.stringify(seen.sessionIDs)}`);

        assert.ok(
          await until(() => seen.sessionIDs.includes("ses_b"), 2000),
          "the knob timer must arm the real path so a pending ask eventually fires",
        );
        await settle();
        assert.equal(pushAttempts(cap.lines), 2, `fired same-session ask denied by the question stamp, fired fresh-session ask pushed — one shared Map instance, saw ${JSON.stringify(cap.lines)}`);
        assert.ok(!seen.sessionIDs.includes("ses_a"), "the gate denies the fired push before any lookup");
      } finally {
        stream.stop();
        if (typeof cleanup === "function") cleanup();
        cap.restore();
      }
    });
  });
});

// The subscribe loop is unchanged in C03 (events still all dispatch to
// handlePermission), so the deferral and cancellation must be observable
// through ctx side effects only: lookups now happen at fire time, never at
// arrival, and a replied-before-fire session is never looked up at all.
describe("P5 subscribe loop wiring under the deferred contract (AC 7, 8, 12, 13)", () => {
  it("streams asked into the timer, with the session lookup deferred to the fire (AC 7, loop-observable)", async () => {
    await withKnob("40", async () => {
      const stream = makeStream();
      const { ctx, seen } = fakeSetupCtx({ events: stream.iterable, sessions: { ses_p: topSession("agent-dev") } });
      const cap = captureErrors();
      let cleanup: any;
      try {
        cleanup = await openSetup(ctx);
        stream.push(asked("ses_p"));
        await new Promise((resolve) => setTimeout(resolve, 10));
        assert.ok(!seen.sessionIDs.includes("ses_p"), "arrival must not reach ctx.session.get — only the fired callback looks up");
        assert.equal(pushAttempts(cap.lines), 0, "arrival must not reach the transport");
        assert.ok(
          await until(() => seen.sessionIDs.includes("ses_p"), 2000),
          `the knob timer must fire the push path, saw ids ${JSON.stringify(seen.sessionIDs)}`,
        );
        assert.ok(await until(() => pushAttempts(cap.lines) >= 1), "the fired ask reaches the transport once");
      } finally {
        stream.stop();
        if (typeof cleanup === "function") cleanup();
        cap.restore();
      }
    });
  });

  it("cancels on permission.replied at the setup level so the session is never looked up (AC 8)", async () => {
    const stream = makeStream();
    const { ctx, seen } = fakeSetupCtx({ events: stream.iterable, sessions: { ses_q: topSession("agent-dev") } });
    const cap = captureErrors();
    let cleanup: any;
    try {
      // No knob: the default 15 s pending window is what makes the early
      // silence meaningful, and the reply must cancel it — if cancel were
      // broken, cleanup's timer sweep (D9) plus this bounded settle keep the
      // suite instant either way.
      cleanup = await openSetup(ctx);
      stream.push(asked("ses_q"));
      stream.push(replied("per_test1", "ses_q", "once"));
      await settle();
      await settle();
      assert.equal(pushAttempts(cap.lines), 0, `a replied ask must never push, saw ${JSON.stringify(cap.lines)}`);
      assert.ok(!seen.sessionIDs.includes("ses_q"), "the cancelled ask must never reach the session lookup");
    } finally {
      stream.stop();
      if (typeof cleanup === "function") cleanup();
      cap.restore();
    }
  });

  it("keeps consuming, and pushes both degraded and titled fired asks, when a fired lookup throws", async () => {
    await withKnob("40", async () => {
      const stream = makeStream();
      const { ctx, seen } = fakeSetupCtx({
        events: stream.iterable,
        getThrowsFor: ["ses_boom"],
        sessions: { ses_ok: topSession("agent-build") },
      });
      const cap = captureErrors();
      let cleanup: any;
      try {
        cleanup = await openSetup(ctx);
        stream.push(asked("ses_boom", { id: "per_boom" }));
        stream.push(asked("ses_ok", { id: "per_ok" }));
        assert.ok(
          await until(() => seen.sessionIDs.includes("ses_ok"), 2000),
          `a throwing fired callback must not stop the loop, saw ids ${JSON.stringify(seen.sessionIDs)}`,
        );
        assert.ok(
          await until(() => pushAttempts(cap.lines) >= 2),
          "the lookup failure degrades the title but never suppresses the push (DECISIONS 2026-10-26)",
        );
        await settle();
        assert.ok(seen.sessionIDs.includes("ses_boom"));
        assert.equal(pushAttempts(cap.lines), 2, `exactly one push per pending ask, saw ${JSON.stringify(cap.lines)}`);
      } finally {
        stream.stop();
        if (typeof cleanup === "function") cleanup();
        cap.restore();
      }
    });
  });

  it("logs the first permission event's keys exactly once, on arrival — replied adds no debug line", async () => {
    const stream = makeStream();
    const { ctx } = fakeSetupCtx({
      events: stream.iterable,
      sessions: { ses_p1: topSession(), ses_p2: childSession() },
    });
    const cap = captureErrors();
    let cleanup: any;
    try {
      cleanup = await openSetup(ctx);
      // The lifecycle event fires the C01 one-shot first; reusing that flag
      // would swallow the permission debug line entirely. Arrival-time logging
      // is unchanged by C03 (chunks/C03.md Tasks), so the waits key on the
      // debug lines themselves — "resources" is a Permission.Request data key
      // no other plugin log line contains, and asking only for its presence and
      // count avoids pinning the wording.
      stream.push({ type: "session.execution.succeeded", data: { sessionID: "ses_ghost" } });
      stream.push(asked("ses_p1"));
      assert.ok(
        await until(() => cap.lines.some((l) => l.includes("resources"))),
        `the one-shot permission debug line must fire at arrival, saw ${JSON.stringify(cap.lines)}`,
      );
      stream.push(asked("ses_p2", { id: "per_two" }));
      await settle();
      const permDebug = cap.lines.filter((l) => l.includes("resources"));
      assert.equal(permDebug.length, 1, `first permission event must log its keys exactly once, saw ${JSON.stringify(cap.lines)}`);
      assert.ok(permDebug[0].includes("sessionID"), "the one-shot log must carry the data keys");
      stream.push(replied("per_two", "ses_p2", "always"));
      await settle();
      assert.equal(
        cap.lines.filter((l) => l.includes("event keys:")).length,
        2,
        "exactly the lifecycle and permission one-shot lines — no new debug line for replied",
      );
    } finally {
      stream.stop();
      if (typeof cleanup === "function") cleanup();
      cap.restore();
    }
  });

  it("still aborts the subscription on cleanup (T8 contract, unedited)", async () => {
    const { ctx, seen } = fakeSetupCtx();
    const cleanup = await openSetup(ctx);
    assert.ok(await until(() => seen.subscribeArgs.length > 0), "setup must subscribe to ctx.event");
    const signal = seen.subscribeArgs[0]?.signal;
    assert.equal(typeof signal?.addEventListener, "function", "subscribe must pass an AbortSignal ({ signal })");
    cleanup();
    assert.ok(
      await until(() => seen.subscribeArgs[0]?.signal?.aborted === true),
      "cleanup must abort the subscription's AbortSignal",
    );
  });
});

describe("D1 deferral (AC 7)", () => {
  it("asked registers exactly one timer under the request id and pushes nothing until it fires", async () => {
    const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession() });
    assert.equal(await runPermission(deps, asked("ses_top", { action: "shell", resources: ["rm -rf build"] })), null);
    assert.equal(calls.notify.length, 0, "arrival must not push (AC 7) — only a still-pending ask at timer fire may");
    assert.equal(calls.allowPush.length, 0, "the cooldown gate is consulted at the push attempt, not at arrival (AC 9, DECISIONS 2026-10-27)");
    assert.equal(calls.getSession.length, 0, "no session lookup at arrival — the record is read only when the push actually fires");
    assert.equal(calls.scheduled.length, 1, `exactly one pending timer per ask (AC 7) — saw schedules ${calls.scheduled.length}, pushes ${calls.notify.length}`);
    assert.equal(deps.pendingMs, PENDING_MS, "the seam default pendingMs is the PENDING_NOTIFY_MS constant — compared, never slept (AC 1)");
    assert.equal(calls.scheduled[0].ms, deps.pendingMs, "the timer is scheduled with pendingMs");
    assert.equal(deps.timers.get("per_test1"), calls.scheduled[0], "the map is keyed by the asked request id — that key is what permission.replied cancels (AC 8)");

    await fireScheduled(calls, 0, "per_test1");
    assert.equal(calls.notify.length, 1, "the fired push reaches notify exactly once");
    assert.equal(calls.notify[0].title, "OpenCode: agent-coord needs approval");
    assert.equal(calls.notify[0].message, "shell: rm -rf build");
    assert.equal(deps.timers.size, 0, "the fired callback removes its own entry");
  });
});

describe("D2 cancellation on every reply value (AC 8)", () => {
  it("once, always, and reject — including reject-with-feedback — all cancel identically; the cancelled callback never pushes", async () => {
    const variants: Array<[string, any]> = [
      ["once", undefined],
      ["always", undefined],
      ["reject", undefined],
      // Grounding #14: the reject-with-feedback branch emits the same event —
      // a human answering "no" is a human who answered.
      ["reject", { message: "use a safer command" }],
    ];
    for (const [reply, extra] of variants) {
      const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession() });
      assert.equal(await runPermission(deps, asked("ses_top", { id: "per_cancel" })), null);
      assert.equal(calls.scheduled.length, 1, `asked must schedule before the reply (AC 7), reply variant ${reply}`);
      const handle = calls.scheduled[0];
      assert.equal(await runPermission(deps, replied("per_cancel", "ses_top", reply, false, extra)), null);
      assert.equal(calls.cancelled.length, 1, `permission.replied must cancel the pending timer (AC 8), reply ${reply}`);
      assert.equal(calls.cancelled[0], handle, "cancel must be called with the recorded handle, nothing else");
      assert.equal(deps.timers.has("per_cancel"), false, "the entry is deleted so the fire can no longer find it");
      assert.equal(calls.allowPush.length, 0, "cancellation must not consult the cooldown gate — a cancelled ask consumes nothing (AC 9)");
      assert.equal(calls.notify.length, 0);
      // A cancel that only cleared the map but left the callback push-capable is
      // the AC 8 misbehaving-harness case — a real timer can be armed in a race.
      await fireScheduled(calls, 0, "per_cancel");
      assert.equal(calls.notify.length, 0, `the cancelled callback must not push when invoked anyway (AC 8), reply ${reply}`);
    }
  });
});

describe("D3 replied robustness (AC 8)", () => {
  it("a replied with an unknown requestID is a silent no-op that leaves the live timer intact", async () => {
    const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession() });
    assert.equal(await runPermission(deps, asked("ses_top")), null);
    assert.equal(calls.scheduled.length, 1, `asked must schedule (AC 7) — saw pushes ${calls.notify.length}`);
    assert.equal(await runPermission(deps, replied("per_never_asked", "ses_top")), null);
    assert.equal(calls.cancelled.length, 0, "an unknown requestID must not cancel anything");
    assert.equal(deps.timers.get("per_test1"), calls.scheduled[0], "the live timer stays keyed");
    await fireScheduled(calls, 0, "per_test1");
    assert.equal(calls.notify.length, 1, "the unaffected timer still fires once");
  });

  it("a replied missing its requestID never rejects and never cancels the live timer", async () => {
    const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession() });
    assert.equal(await runPermission(deps, asked("ses_top")), null);
    assert.equal(calls.scheduled.length, 1, `asked must schedule (AC 7) — saw pushes ${calls.notify.length}`);
    assert.equal(await runPermission(deps, replied(undefined, "ses_top")), null, "nested replied without requestID must resolve");
    // The compat envelope may deliver the fields flat — the dual read must not
    // throw even on this malformed shape.
    assert.equal(await runPermission(deps, { type: "permission.replied", sessionID: "ses_top", reply: "once" }), null, "flat replied without requestID must resolve");
    assert.equal(calls.cancelled.length, 0);
    await fireScheduled(calls, 0, "per_test1");
    assert.equal(calls.notify.length, 1);
  });

  it("a replied that arrives after the timer fired is a no-op — exactly one push total", async () => {
    const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession() });
    assert.equal(await runPermission(deps, asked("ses_top")), null);
    await fireScheduled(calls, 0, "per_test1");
    assert.equal(calls.notify.length, 1);
    assert.equal(await runPermission(deps, replied("per_test1", "ses_top")), null);
    assert.equal(calls.cancelled.length, 0, "nothing left to cancel after the fire must still be a silent no-op (AC 8)");
    assert.equal(calls.notify.length, 1, "the late replied must not resurrect a second push");
  });

  it("a replied for one request leaves the other request's timer live", async () => {
    const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession("agent-dev") });
    assert.equal(await runPermission(deps, asked("ses_a", { id: "per_a" })), null);
    assert.equal(await runPermission(deps, asked("ses_b", { id: "per_b" })), null);
    assert.equal(calls.scheduled.length, 2, `both asked events must schedule (AC 7) — saw pushes ${calls.notify.length}`);
    assert.equal(await runPermission(deps, replied("per_a", "ses_a")), null);
    assert.equal(calls.cancelled.length, 1);
    assert.equal(deps.timers.has("per_b"), true, "the other request's entry survives");
    await fireScheduled(calls, 1, "per_b");
    assert.equal(calls.notify.length, 1, "only the cancelled ask went silent");
    assert.equal(calls.notify[0].title, "OpenCode: agent-dev needs approval");
  });
});

describe("D4 cooldown timing: the stamp lives at the push attempt (AC 9)", () => {
  it("a cancelled ask consumes no gate call and a later fired ask for the same session pushes", async () => {
    const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession() });
    assert.equal(await runPermission(deps, asked("ses_s", { id: "per_a" })), null);
    assert.equal(await runPermission(deps, replied("per_a", "ses_s")), null);
    assert.equal(calls.cancelled.length, 1, `replied must cancel (AC 8) — saw pushes ${calls.notify.length}`);
    assert.equal(calls.allowPush.length, 0, "a cancelled ask must never consult the gate (AC 9)");
    assert.equal(await runPermission(deps, asked("ses_s", { id: "per_b" })), null);
    await fireScheduled(calls, 1, "per_b");
    assert.deepEqual(calls.allowPush, ["ses_s"], "the gate is consulted exactly once — at the fire");
    assert.equal(calls.notify.length, 1, "the cancelled ask burned nothing: the fired follow-up pushes");
  });

  it("two overlapping asks both fire but the shared gate admits only the first push", async () => {
    const gate = makeStampingGate();
    const { deps, calls } = fakePermissionDeps({ gate: gate.allowPush, getSession: async () => topSession() });
    assert.equal(await runPermission(deps, asked("ses_s", { id: "per_1" })), null);
    assert.equal(await runPermission(deps, asked("ses_s", { id: "per_2" })), null);
    assert.equal(gate.seen.length, 0, "neither arrival consulted the gate (AC 9)");
    assert.equal(calls.scheduled.length, 2, `two distinct ids schedule two timers (AC 7) — saw pushes ${calls.notify.length}`);
    await fireScheduled(calls, 0, "per_1");
    assert.equal(calls.notify.length, 1);
    await fireScheduled(calls, 1, "per_2");
    assert.equal(calls.notify.length, 1, "one push per session per window survives the deferral: the gate denies the second fire");
    assert.deepEqual(gate.seen, ["ses_s", "ses_s"], "both fires consulted the gate at push time");
    assert.equal(calls.getSession.length, 1, "the denied fire bails before the lookup (gate-first ordering, DECISIONS 2026-10-27)");
  });
});

describe("D5 envelope tolerance for the timer pair (AC 10)", () => {
  it("nested and flat asked events both schedule under the request id", async () => {
    const nested = fakePermissionDeps({ getSession: async () => topSession() });
    assert.equal(await runPermission(nested.deps, asked("ses_top", { id: "per_n1" })), null);
    assert.equal(nested.calls.scheduled.length, 1, `nested asked must schedule (AC 7) — saw pushes ${nested.calls.notify.length}`);
    assert.equal(nested.deps.timers.get("per_n1"), nested.calls.scheduled[0]);
    const flat = fakePermissionDeps({ getSession: async () => topSession() });
    assert.equal(await runPermission(flat.deps, asked("ses_top", { id: "per_f1", flat: true })), null);
    assert.equal(flat.calls.notify.length, 0, "flat asked must not push at arrival");
    assert.equal(flat.calls.scheduled.length, 1, "flat asked must schedule");
    assert.equal(flat.deps.timers.get("per_f1"), flat.calls.scheduled[0], "the flat asked id resolves via the dual read (event.data?.id ?? event.id)");
  });

  it("every asked×replied envelope combination cancels, V1-twin payload included", async () => {
    const combos: Array<[boolean, boolean]> = [
      [true, true],
      [true, false],
      [false, true],
      [false, false],
    ];
    for (const [askedFlat, repliedFlat] of combos) {
      const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession() });
      assert.equal(await runPermission(deps, asked("ses_top", { id: "per_x", flat: askedFlat })), null);
      assert.equal(calls.scheduled.length, 1, `asked flat=${askedFlat} must schedule`);
      assert.equal(await runPermission(deps, replied("per_x", "ses_top", "once", repliedFlat)), null);
      assert.equal(calls.cancelled.length, 1, `replied flat=${repliedFlat} must cancel the id scheduled by an asked flat=${askedFlat}`);
      assert.equal(calls.notify.length, 0, "no cross-envelope combination may push at arrival");
      await fireScheduled(calls, 0, "per_x");
      assert.equal(calls.notify.length, 0, "the cross-envelope cancelled callback must not push (AC 8)");
    }

    const v1 = fakePermissionDeps({ getSession: async () => topSession() });
    assert.equal(
      await runPermission(v1.deps, {
        type: "permission.asked",
        data: { id: "per_v1", sessionID: "ses_top", permission: "bash", patterns: ["git *"] },
      }),
      null,
    );
    assert.equal(v1.calls.scheduled.length, 1, `V1-twin asked must schedule (AC 10) — saw pushes ${v1.calls.notify.length}`);
    await fireScheduled(v1.calls, 0, "per_v1");
    assert.equal(v1.calls.notify[0].message, "bash: git *", "the fired push still renders the V1-twin excerpt");
  });
});

describe("D6 replace-on-redelivery (Grounding #17)", () => {
  it("the same request id asked twice keeps exactly one live handle and pushes once on fire", async () => {
    const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession() });
    assert.equal(await runPermission(deps, asked("ses_top", { id: "per_dup" })), null);
    assert.equal(await runPermission(deps, asked("ses_top", { id: "per_dup" })), null);
    assert.equal(calls.scheduled.length, 2, `each arrival arms its own replacement timer (belt for stream reconnects) — saw pushes ${calls.notify.length}`);
    assert.equal(calls.cancelled.length, 1, "the first handle is cancelled before the replacement is registered");
    assert.equal(calls.cancelled[0], calls.scheduled[0], "cancel got the FIRST handle");
    assert.equal(deps.timers.size, 1, "one live entry per request id");
    assert.equal(deps.timers.get("per_dup"), calls.scheduled[1], "the map holds the newest handle");
    await fireScheduled(calls, 1, "per_dup");
    assert.equal(calls.notify.length, 1, "exactly one push for the request");
  });
});

describe("D7 malformed asked (AC 11)", () => {
  it("an asked without a request id schedules nothing — a timer with no cancel key cannot be trusted to push", async () => {
    const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession() });
    assert.equal(await runPermission(deps, { type: "permission.asked", data: { sessionID: "ses_top", action: "shell", resources: ["ls"] } }), null);
    assert.equal(await runPermission(deps, { type: "permission.asked", sessionID: "ses_top", action: "shell" }), null);
    await settle();
    assert.equal(calls.scheduled.length, 0, "no id means no timer (AC 11)");
    assert.equal(calls.allowPush.length, 0, "and no gate consumption");
    assert.equal(calls.getSession.length, 0, "and no lookup");
    assert.equal(calls.notify.length, 0, "and definitely no push");
  });

  it("an asked without a sessionID and garbage events stay silent and never reject", async () => {
    const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession() });
    const malformed: any[] = [
      { type: "permission.asked", data: { id: "per_x" } },
      { type: "permission.asked", data: null },
      { type: "permission.asked" },
      undefined,
      null,
      {},
      { type: 42 },
      [],
    ];
    for (const event of malformed) {
      assert.equal(await runPermission(deps, event), null, `${JSON.stringify(event)} must resolve`);
    }
    await settle();
    assert.equal(calls.scheduled.length, 0);
    assert.equal(calls.allowPush.length, 0, "there is no gate key before the sessionID resolves");
    assert.equal(calls.notify.length, 0);
  });
});

describe("D8 failure policy: dispatch and callback both never reject (AC 12)", () => {
  it("a throwing schedule is swallowed at dispatch with a stderr log and leaves nothing pushable", async () => {
    const { deps, calls } = fakePermissionDeps({ scheduleThrows: true });
    const cap = captureErrors();
    let error: any = null;
    try {
      error = await runPermission(deps, asked("ses_top"));
    } finally {
      cap.restore();
    }
    assert.equal(error, null, "dispatch must resolve even when deps.schedule throws (AC 12)");
    assert.equal(calls.scheduled.length, 0, "a failed schedule must not leave a recorded timer (AC 12)");
    assert.equal(calls.notify.length, 0, `nothing is pushable when the timer could not be armed (AC 12) — saw pushes ${calls.notify.length}: the plugin still pushes on arrival`);
    assert.ok(
      cap.lines.some((l) => l.includes("schedule boom")),
      `the failure must be logged to stderr, saw ${JSON.stringify(cap.lines)}`,
    );
  });

  it("a throwing cancel on replied is swallowed with a stderr log", async () => {
    const { deps, calls } = fakePermissionDeps({ cancelThrows: true, getSession: async () => topSession() });
    const cap = captureErrors();
    let error: any = null;
    try {
      assert.equal(await runPermission(deps, asked("ses_top")), null, "the ask must still schedule cleanly");
      error = await runPermission(deps, replied("per_test1", "ses_top"));
    } finally {
      cap.restore();
    }
    assert.equal(calls.scheduled.length, 1, `replied cancellation requires the asked seam first (AC 7) — saw pushes ${calls.notify.length}`);
    assert.equal(error, null, "dispatch must resolve even when deps.cancel throws (AC 12)");
    assert.equal(calls.cancelled.length, 1, "the cancel was attempted before it threw");
    assert.ok(
      cap.lines.some((l) => l.includes("cancel boom")),
      `the failure must be logged to stderr, saw ${JSON.stringify(cap.lines)}`,
    );
  });

  it("a notify rejection inside the fired callback is swallowed — no unhandled rejection escapes the timer", async () => {
    const { deps, calls } = fakePermissionDeps({ notifyRejects: true, getSession: async () => topSession() });
    const cap = captureErrors();
    try {
      assert.equal(await runPermission(deps, asked("ses_top")), null);
      await fireScheduled(calls, 0, "per_test1");
      assert.equal(calls.notify.length, 1, "notify was attempted once");
      assert.ok(
        cap.lines.some((l) => l.includes("notify boom")),
        `the swallowed rejection must be logged, saw ${JSON.stringify(cap.lines)}`,
      );
    } finally {
      cap.restore();
    }
    // An unhandledRejection here would be reported against the test process by
    // node --test itself — surviving to this line is the assertion.
    await settle();
  });
});

describe("D9 setup-level timers: cleanup sweep and the env knob (AC 13, 15)", () => {
  it("cleanup cancels the still-pending knob timer — no push and no lookup ever fire — and keeps the abort", async () => {
    await withKnob("5000", async () => {
      const stream = makeStream();
      const { ctx, seen } = fakeSetupCtx({ events: stream.iterable, sessions: { ses_z: topSession("agent-dev") } });
      const cap = captureErrors();
      let cleanup: any;
      try {
        cleanup = await openSetup(ctx);
        stream.push(asked("ses_z", { id: "per_z" }));
        await new Promise((resolve) => setTimeout(resolve, 10));
        cleanup();
        assert.ok(
          await until(() => seen.subscribeArgs[0]?.signal?.aborted === true),
          "cleanup must still abort first — the legacy T8 order survives the timer sweep",
        );
        // Far short of the 5 s window: any line here can only come from an
        // arrival-time push (C02 behavior) — cleanup must have cleared the
        // handle, so the sweep is provable without sleeping through the window.
        await new Promise((resolve) => setTimeout(resolve, 300));
        assert.equal(pushAttempts(cap.lines), 0, `a cancelled-on-unload timer must never push (AC 13), saw ${JSON.stringify(cap.lines)}`);
        assert.ok(!seen.sessionIDs.includes("ses_z"), "and never reach the session lookup");
      } finally {
        stream.stop();
        if (typeof cleanup === "function") cleanup();
        cap.restore();
      }
    });
  });

  it("pendingMs is read per setup() call, not cached at module load (AC 15)", async () => {
    const streamA = makeStream();
    const { ctx: ctxA, seen: seenA } = fakeSetupCtx({ events: streamA.iterable, sessions: { ses_w: topSession("agent-dev") } });
    let cleanupA: any;
    const capA = captureErrors();
    try {
      await withKnob("30", async () => {
        cleanupA = await openSetup(ctxA);
        streamA.push(asked("ses_w", { id: "per_w" }));
        assert.ok(
          await until(() => pushAttempts(capA.lines) >= 1, 2000),
          "a setup built with the knob set must fire on it — a module-load read would arm the real 15 s instead (AC 15)",
        );
        assert.ok(seenA.sessionIDs.includes("ses_w"), "the knob-fired push performs the deferred session lookup");
      });
    } finally {
      streamA.stop();
      if (typeof cleanupA === "function") cleanupA();
      capA.restore();
    }

    const streamB = makeStream();
    const { ctx: ctxB, seen: seenB } = fakeSetupCtx({ events: streamB.iterable, sessions: { ses_y: topSession("agent-dev") } });
    const capB = captureErrors();
    let cleanupB: any;
    try {
      cleanupB = await openSetup(ctxB);
      assert.equal(typeof cleanupB, "function");
      streamB.push(asked("ses_y", { id: "per_y" }));
      await new Promise((resolve) => setTimeout(resolve, 150));
      assert.equal(pushAttempts(capB.lines), 0, `a setup built with the knob unset must use the 15 s constant (AC 15), saw ${JSON.stringify(capB.lines)}`);
      assert.ok(!seenB.sessionIDs.includes("ses_y"), "and its lookup stays deferred past the window");
    } finally {
      streamB.stop();
      if (typeof cleanupB === "function") cleanupB();
      capB.restore();
    }
  });

  it("a non-numeric or negative knob falls back to the 15 s constant", async () => {
    // Not "" — Number("") is 0, which the "finite number ≥ 0" rule makes a
    // legal immediate window; only genuinely invalid values may fall back.
    for (const value of ["-5", "not-a-number"]) {
      await withKnob(value, async () => {
        const stream = makeStream();
        const { ctx, seen } = fakeSetupCtx({ events: stream.iterable, sessions: { ses_v: topSession("agent-dev") } });
        const cap = captureErrors();
        let cleanup: any;
        try {
          cleanup = await openSetup(ctx);
          stream.push(asked("ses_v", { id: "per_v" }));
          await new Promise((resolve) => setTimeout(resolve, 120));
          assert.equal(pushAttempts(cap.lines), 0, `OPENCODE_NOTIFY_PENDING_MS=${value} must not shorten the window, saw ${JSON.stringify(cap.lines)}`);
          assert.ok(!seen.sessionIDs.includes("ses_v"), `OPENCODE_NOTIFY_PENDING_MS=${value} must fall back to PENDING_NOTIFY_MS`);
        } finally {
          stream.stop();
          if (typeof cleanup === "function") cleanup();
          cap.restore();
        }
      });
    }
  });
});