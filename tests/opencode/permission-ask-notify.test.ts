// C02 acceptance checks (2026-10-feat-ha-lifecycle-notify): the approval-ask test
// seam the question-notify plugin must grow — approvalTitle / approvalExcerpt /
// handlePermission(deps, event) — plus the cooldown gate the question path shares
// and the asked-only dispatch in the subscribe loop. Covers AC 3 and 7–11 of
// chunks/C02.md; the source-text checks (AC 4–6) and the legacy-suite md5 pin
// (AC 2) are the plan's Commands, run by review — they are not this file.
//
// Run from the repo root: node --test 'tests/opencode/*.test.ts' — the glob is
// quoted because a bare `tests/opencode` directory argument fails under this
// Node build (FRICTION 2026-10-26).
//
// Fixture shapes are the Permission.Request surface grounded against the
// installed CLI v2.1.4 (plan Grounding #8/#10): the durable event nests
// { id, sessionID, action, resources, message?, metadata? } under `data` and
// carries NO agent name — the title must come from a session lookup — and the
// V1-compat twin shares the `permission.asked` type string with
// { permission, patterns } instead of { action, resources }. Both envelopes are
// exercised, plus the flat variant, because the service build live at smoke
// time is user-owned (plan Risks: version drift).
//
// Everything stays offline, as in the C01 suite: fakes are the only
// collaborators, and the setup-level ctx keeps haMcpUrl on its no-URL path so
// nothing can open a socket. Consequence: every push attempt logs exactly one
// "no URL found" line from sendHANotify — the single transport chokepoint the
// question and permission paths share — so those lines count as pushes here.

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import * as plugin from "../../.opencode/plugin/question-notify/index.ts";

const MAX = 240;
const LONG = "a".repeat(300);

// Namespace import, so a module that has not grown the permission seam yet
// fails on the assertion below rather than as an ESM link error — a link error
// would take every other test in this file down with it and read as broken
// scaffolding (same reason C01 adopted it).
const mod = plugin as Record<string, any>;

function seam(name: string): (...args: any[]) => any {
  const fn = typeof mod[name] === "function" ? mod[name] : mod.default?.[name];
  if (typeof fn !== "function") {
    throw new Error(
      `plugin seam "${name}" is not exported (C02 Tasks: export approvalTitle, approvalExcerpt and handlePermission from .opencode/plugin/question-notify/index.ts)`,
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

// The server guarantees exactly one asked event per request ID, so a cooldown
// burst test varies the id: a second ask is a NEW request, gated only by the
// cooldown — never by any plugin-side per-id dedup.
const asked = (sessionID: string, overrides: any = {}) => ({
  type: "permission.asked",
  data: { id: "per_test1", sessionID, action: "shell", resources: ["ls -la"], ...overrides },
});

function fakePermissionDeps(opts: any = {}) {
  const calls: any = { allowPush: [], getSession: [], notify: [] };
  const deps = {
    // The setup-closure cooldown gate, injected (C02 Tasks: check the gate
    // BEFORE the session lookup) so the P3 matrix can pin gate-first.
    allowPush: (key: string) => {
      calls.allowPush.push(key);
      return opts.allowPush === undefined ? true : !!opts.allowPush;
    },
    getSession: async (sessionID: string) => {
      calls.getSession.push(sessionID);
      if (opts.getSessionThrows) throw new Error("session lookup failed");
      return typeof opts.getSession === "function" ? opts.getSession(sessionID) : undefined;
    },
    notify: async (title: string, message: string) => {
      calls.notify.push({ title, message });
    },
  };
  return { deps, calls };
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
// instance shared by the question hook and the stream dispatch is only possible
// when both paths run against the same setup() closure.
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

async function runPermission(deps: any, event: any) {
  let error: any = null;
  try {
    await seam("handlePermission")(deps, event);
  } catch (err) {
    error = err;
  }
  return error;
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

describe("R1 regression + permission seam export (AC 3, chunks/C02.md R1)", () => {
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

describe("P1 approvalTitle (AC 7)", () => {
  it("builds the needs-approval title from the agent name", () => {
    assert.equal(seam("approvalTitle")("agent-dev"), "OpenCode: agent-dev needs approval");
    assert.equal(seam("approvalTitle")("build"), "OpenCode: build needs approval");
  });
});

describe("P2 approvalExcerpt precedence (AC 9)", () => {
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

describe("P3 handlePermission dispatch matrix (AC 7, 10)", () => {
  it("pushes exactly one approval notification for a top-level ask", async () => {
    const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession() });
    const error = await runPermission(deps, asked("ses_top", { action: "shell", resources: ["rm -rf build"] }));
    assert.equal(error, null, `handlePermission must resolve, threw ${error?.message ?? error}`);
    assert.ok(calls.allowPush.includes("ses_top"), "the cooldown gate must key on the event sessionID");
    assert.ok(calls.getSession.includes("ses_top"), "the agent name comes from a session lookup");
    assert.equal(calls.notify.length, 1, `expected one push, got ${JSON.stringify(calls.notify)}`);
    assert.equal(calls.notify[0].title, "OpenCode: agent-coord needs approval");
    assert.equal(calls.notify[0].message, "shell: rm -rf build");
  });

  it("pushes for a child session too — scope-all-sessions (DECISIONS 2026-10-26)", async () => {
    const { deps, calls } = fakePermissionDeps({ getSession: async () => childSession() });
    assert.equal(await runPermission(deps, asked("ses_child")), null);
    assert.equal(calls.notify.length, 1, "a subagent blocked on approval must still reach the phone");
    assert.equal(calls.notify[0].title, "OpenCode: agent-test needs approval");
  });

  it("pushes with the session fallback label when the lookup rejects", async () => {
    const { deps, calls } = fakePermissionDeps({ getSessionThrows: true });
    assert.equal(
      await runPermission(deps, asked("ses_gone")),
      null,
      "a failed lookup must be swallowed, not thrown",
    );
    assert.equal(calls.notify.length, 1, "dropping an approval push is the worst outcome (DECISIONS lookup-failure policy)");
    assert.equal(calls.notify[0].title, "OpenCode: session needs approval");
  });

  it("pushes with the session fallback label when the record carries no agent", async () => {
    const gone = fakePermissionDeps({ getSession: async () => undefined });
    assert.equal(await runPermission(gone.deps, asked("ses_deleted")), null);
    assert.equal(gone.calls.notify.length, 1);
    assert.equal(gone.calls.notify[0].title, "OpenCode: session needs approval");

    const noAgent = fakePermissionDeps({ getSession: async () => ({ id: "ses_x", title: "x" }) });
    assert.equal(await runPermission(noAgent.deps, asked("ses_x")), null);
    assert.equal(noAgent.calls.notify.length, 1);
    assert.equal(noAgent.calls.notify[0].title, "OpenCode: session needs approval");
  });

  it("caps the pushed body at 240 characters", async () => {
    const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession() });
    assert.equal(await runPermission(deps, asked("ses_top", { message: LONG })), null);
    assert.equal(calls.notify.length, 1);
    assert.equal(calls.notify[0].message, LONG.slice(0, MAX));
  });

  it("stays silent and skips the session lookup when the cooldown gate says no", async () => {
    const { deps, calls } = fakePermissionDeps({ allowPush: false, getSession: async () => topSession() });
    assert.equal(await runPermission(deps, asked("ses_top")), null);
    assert.equal(calls.notify.length, 0);
    assert.equal(calls.getSession.length, 0, "the gate must run before the lookup (C02 Tasks: cooldown gate before session lookup)");
  });

  it("ignores every non-asked event type, carrying asked payload fields and all", async () => {
    const ignored = [
      "session.execution.succeeded",
      "session.execution.failed",
      "session.idle",
      "permission.replied",
      "form.created",
      "unknown.future.event",
    ];
    for (const type of ignored) {
      const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession() });
      const event = { type, data: { id: "per_x", sessionID: "ses_top", action: "shell", resources: ["ls"], message: "hi" } };
      assert.equal(await runPermission(deps, event), null, `${type} must not throw`);
      await settle();
      assert.equal(calls.notify.length, 0, `${type} must not push — dispatch is asked-only`);
    }
  });

  it("stays silent when the asked event carries no sessionID", async () => {
    const nested = fakePermissionDeps({ getSession: async () => topSession() });
    assert.equal(await runPermission(nested.deps, { type: "permission.asked", data: { id: "per_x" } }), null);
    const flat = fakePermissionDeps({ getSession: async () => topSession() });
    assert.equal(await runPermission(flat.deps, { type: "permission.asked" }), null);
    assert.equal(await runPermission(flat.deps, { type: "permission.asked", data: null }), null);
    await settle();
    assert.equal(nested.calls.notify.length, 0);
    assert.equal(flat.calls.notify.length, 0);
    assert.equal(
      nested.calls.allowPush.length + flat.calls.allowPush.length,
      0,
      "there is no gate key before the sessionID resolves (C02 Tasks: resolve, then check the gate)",
    );
  });

  it("dispatches a flat asked event (AC 10, C01 T7 dual-read convention)", async () => {
    const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession("agent-review") });
    const error = await runPermission(deps, {
      type: "permission.asked",
      id: "per_flat",
      sessionID: "ses_top",
      action: "edit",
      resources: ["src/a.ts"],
    });
    assert.equal(error, null);
    assert.equal(calls.notify.length, 1, "a flat-payload asked event must still push once");
    assert.equal(calls.notify[0].title, "OpenCode: agent-review needs approval");
    assert.equal(calls.notify[0].message, "edit: src/a.ts");
  });

  it("dispatches the V1-compat twin envelope", async () => {
    const { deps, calls } = fakePermissionDeps({ getSession: async () => topSession() });
    const error = await runPermission(deps, {
      type: "permission.asked",
      data: { id: "per_v1", sessionID: "ses_top", permission: "bash", patterns: ["git *"] },
    });
    assert.equal(error, null);
    assert.equal(calls.notify.length, 1);
    assert.equal(calls.notify[0].message, "bash: git *");
  });
});

describe("P4 cooldown shared with the question path (AC 8)", () => {
  it("collapses a question push and same-session asks into one phone push", async () => {
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
      assert.ok(await until(() => pushAttempts(cap.lines) >= 1), "the question path must reach the transport");

      stream.push(asked("ses_a"));
      stream.push(asked("ses_a", { id: "per_two" }));
      await settle();
      // Only one Map instance can produce this count: a per-path copy would let
      // both asks through the gate after the question push stamped ses_a.
      assert.equal(pushAttempts(cap.lines), 1, `question push + same-session asks must share one gate, saw ${JSON.stringify(cap.lines)}`);
      assert.ok(!seen.sessionIDs.includes("ses_a"), "a gated ask must bail before the session lookup");

      stream.push(asked("ses_b"));
      assert.ok(
        await until(() => pushAttempts(cap.lines) >= 2),
        "a different session keeps its own cooldown entry",
      );
      await settle();
      assert.equal(pushAttempts(cap.lines), 2, `exactly two pushes expected, saw ${JSON.stringify(cap.lines)}`);
    } finally {
      stream.stop();
      if (typeof cleanup === "function") cleanup();
      cap.restore();
    }
  });
});

describe("P5 subscribe loop wiring for permission events (AC 11)", () => {
  it("streams permission.asked events into the handler's session lookup", async () => {
    const stream = makeStream();
    const { ctx, seen } = fakeSetupCtx({ events: stream.iterable, sessions: { ses_p: topSession("agent-dev") } });
    let cleanup: any;
    try {
      cleanup = await openSetup(ctx);
      stream.push(asked("ses_p"));
      assert.ok(
        await until(() => seen.sessionIDs.includes("ses_p")),
        `the loop must dispatch asked events to handlePermission, saw ids ${JSON.stringify(seen.sessionIDs)}`,
      );
    } finally {
      stream.stop();
      if (typeof cleanup === "function") cleanup();
    }
  });

  it("keeps consuming after an event whose handling hits a throwing lookup", async () => {
    const stream = makeStream();
    const { ctx, seen } = fakeSetupCtx({
      events: stream.iterable,
      getThrowsFor: ["ses_boom"],
      sessions: { ses_ok: topSession("agent-build") },
    });
    let cleanup: any;
    try {
      cleanup = await openSetup(ctx);
      stream.push(asked("ses_boom"));
      stream.push(asked("ses_ok"));
      assert.ok(
        await until(() => seen.sessionIDs.includes("ses_ok")),
        `a throwing dispatch must not stop the loop, saw ids ${JSON.stringify(seen.sessionIDs)}`,
      );
    } finally {
      stream.stop();
      if (typeof cleanup === "function") cleanup();
    }
  });

  it("logs the first permission event's keys exactly once, on its own flag", async () => {
    const stream = makeStream();
    const { ctx, seen } = fakeSetupCtx({
      events: stream.iterable,
      sessions: { ses_p1: topSession(), ses_p2: childSession() },
    });
    const cap = captureErrors();
    let cleanup: any;
    try {
      cleanup = await openSetup(ctx);
      // The lifecycle event fires the C01 one-shot first; reusing that flag
      // would swallow the permission debug line entirely. "resources" is a
      // Permission.Request data key no other plugin log line contains, and
      // asking only for its presence and count avoids pinning the wording.
      stream.push({ type: "session.execution.succeeded", data: { sessionID: "ses_ghost" } });
      stream.push(asked("ses_p1"));
      assert.ok(await until(() => seen.sessionIDs.includes("ses_p1")));
      stream.push(asked("ses_p2", { id: "per_two" }));
      assert.ok(await until(() => seen.sessionIDs.includes("ses_p2")));
      await settle();
      const permDebug = cap.lines.filter((l) => l.includes("resources"));
      assert.equal(permDebug.length, 1, `first permission event must log its keys exactly once, saw ${JSON.stringify(cap.lines)}`);
      assert.ok(permDebug[0].includes("sessionID"), "the one-shot log must carry the data keys");
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
