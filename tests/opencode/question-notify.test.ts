// C01 acceptance checks (2026-10-feat-ha-lifecycle-notify): the lifecycle test
// seam the question-notify plugin must export — truncate / titles / isTopLevel /
// lastAssistantExcerpt / crashExcerpt / handleLifecycle(deps, event) — plus the
// subscribe-loop wiring, and the regression guard that the existing question
// path still loads and registers its tool hook. Covers AC 1-9 of chunks/C01.md;
// the source-text checks (AC 3/4/5) are the plan's grep commands, not this file.
//
// T9/T10 (2026/2026-10-chore-board-tick-cleanup C02): the no-work suppression
// reader — noWorkSuppressed(info) plus the handleLifecycle FINISHED matrix.
// The scope ruling (OQ4, user 2026-10-29) is a CONJUNCTION: well-formed
// metadata.pipelineNoop AND metadata.openchamber.kind === "scheduled" — marker
// presence alone never mutes a run, every unknown shape alerts (fail-loud).
// The writer/reader home pins are grep arms in tests/noop-marker/surface.sh;
// the suppression-leg live proof is C03's LF6, unit arms are C02's proof
// surface (chunk Notes for dev). Red before dev by design: the
// noWorkSuppressed seam does not exist yet.
//
// Run from the repo root: node --test tests/opencode/question-notify.test.ts
// (Node v26 runs the .ts directly via type stripping; no build step, no npm
// deps, no network — the fakes below are the only collaborators.)
//
// This file lives in the repo-root tests/ tree, deliberately NOT under
// .opencode/: plugin discovery loads every .ts it scans in .opencode/plugin(s)/,
// so a test file there could be imported as a plugin entry at server startup.
//
// Fixture shapes are copied from the live v2.0.32 surface (`opencode api get
// /api/session/<id>/context`): context returns the message array, assistant
// messages hold `content` parts of {type:"text"|"reasoning"|"tool"} with the
// body in `text`, and user/system messages carry `text` at their top level — so
// an excerpt scan that only looks at the newest message, or at any `text`
// field, reads the user's own prompt back to them. Real turns also end on a
// tool part, which is why the scan must skip assistant messages without text.

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import * as plugin from "../../.opencode/plugin/question-notify/index.ts";

const MAX = 240;
const LONG = "a".repeat(300);

// Namespace import, so a module that has not grown the seam yet fails on the
// assertion below rather than as an ESM link error — a link error would take
// every other test in this file down with it and read as broken scaffolding.
const mod = plugin as Record<string, any>;

function seam(name: string): (...args: any[]) => any {
  const fn = typeof mod[name] === "function" ? mod[name] : mod.default?.[name];
  if (typeof fn !== "function") {
    throw new Error(
      `plugin seam "${name}" is not exported (C01 Tasks: export the test seam from .opencode/plugin/question-notify/index.ts)`,
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

const textPart = (text: string) => ({ type: "text", text });
const reasoningPart = (text: string) => ({ type: "reasoning", text });
const toolPart = (callID: string) => ({
  type: "tool",
  callID,
  tool: "read",
  state: { status: "completed", input: {}, output: "ok" },
});
const assistant = (...parts: any[]) => ({
  id: "msg_assistant",
  type: "assistant",
  agent: "agent-coord",
  content: parts,
});
const user = (text: string) => ({ id: "msg_user", type: "user", text });

const succeededEvent = (sessionID: string) => ({
  type: "session.execution.succeeded",
  data: { sessionID },
});
const failedEvent = (sessionID: string, error: any) => ({
  type: "session.execution.failed",
  data: { sessionID, error },
});

// deps keys are pinned by C01 "Notes for dev": the real deps bind
// ctx.session.get / ctx.session.context, and notify takes the full title.
function fakeDeps(opts: any = {}) {
  const calls: any = { getSession: [], getMessages: [], notify: [] };
  const deps = {
    getSession: async (sessionID: string) => {
      calls.getSession.push(sessionID);
      if (opts.getSessionThrows) throw new Error("session lookup failed");
      return typeof opts.getSession === "function" ? opts.getSession(sessionID) : undefined;
    },
    getMessages: async (sessionID: string) => {
      calls.getMessages.push(sessionID);
      if (opts.getMessagesThrows) throw new Error("context lookup failed");
      return opts.messages ?? [];
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

// Mirrors the plugin ctx surface setup() consumes: the tool hook the question
// path registers, plus the V2 event stream the lifecycle loop subscribes to.
function fakeCtx(opts: any = {}) {
  const seen: any = { hookNames: [], subscribeArgs: [], sessionIDs: [] };
  const ctx = {
    tool: {
      hook: async (name: string, _handler: any) => {
        seen.hookNames.push(name);
      },
    },
    event: {
      subscribe: (arg: any) => {
        seen.subscribeArgs.push(arg);
        return opts.events ?? { [Symbol.asyncIterator]: () => ({ next: async () => ({ value: undefined, done: true }) }) };
      },
    },
    session: {
      get: async (arg: any) => {
        const sessionID = arg?.sessionID ?? arg;
        seen.sessionIDs.push(sessionID);
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
// so give the fire-and-forget chain time to reach notify before counting.
async function settle() {
  await new Promise((resolve) => setTimeout(resolve, 50));
}

async function runLifecycle(deps: any, event: any) {
  let error: any = null;
  try {
    await seam("handleLifecycle")(deps, event);
  } catch (err) {
    error = err;
  }
  return error;
}

describe("S1 question path regression (plan Out of scope: question notify unchanged)", () => {
  it("keeps the plugin loadable with its verified default-export shape (AC 2)", async () => {
    assert.equal(mod.default?.id, "local.question-notify");
    assert.equal(typeof mod.default?.setup, "function");
  });

  it("still registers the execute.before tool hook when setup runs", async () => {
    const { ctx, seen } = fakeCtx();
    await mod.default.setup(ctx);
    assert.ok(
      seen.hookNames.includes("execute.before"),
      `setup must keep registering the question tool hook, saw: ${JSON.stringify(seen.hookNames)}`,
    );
  });
});

describe("T0 lifecycle seam export (AC 2)", () => {
  it("exports handleLifecycle as a function", () => {
    assert.equal(typeof mod.handleLifecycle, "function", "handleLifecycle must be a named export (plan Commands load+shape check)");
  });

  it("exports the pure helpers the matrix is built from", () => {
    for (const name of [
      "truncate",
      "isTopLevel",
      "questionTitle",
      "finishedTitle",
      "crashTitle",
      "lastAssistantExcerpt",
      "crashExcerpt",
    ]) {
      assert.equal(typeof seam(name), "function", `${name} must be exported`);
    }
  });
});

describe("T1 truncate (AC 9)", () => {
  it("is identical to s.slice(0, 240) across the boundary", () => {
    const truncate = seam("truncate");
    for (const length of [0, 1, 239, MAX, MAX + 1, 500]) {
      const input = "u".repeat(length);
      assert.equal(truncate(input), input.slice(0, MAX), `length ${length}`);
    }
  });

  it("returns short and exactly-240 strings unchanged, 241 truncated to 240", () => {
    const truncate = seam("truncate");
    assert.equal(truncate("short one"), "short one");
    const at = "b".repeat(MAX);
    assert.equal(truncate(at), at);
    assert.equal(truncate(`${at}c`), at);
  });

  it("maps non-string and missing input to the empty string", () => {
    const truncate = seam("truncate");
    for (const input of [undefined, null, 123, {}, []]) {
      assert.equal(truncate(input as any), "", `input ${JSON.stringify(input)}`);
    }
  });
});

describe("T2 titles (AC 6, 7, 9)", () => {
  it("keeps the legacy question title byte-identical", () => {
    assert.equal(seam("questionTitle")("agent-coord"), "OpenCode: agent-coord has a question");
  });

  it("builds the finished and stopped titles", () => {
    assert.equal(seam("finishedTitle")("agent-coord"), "OpenCode: agent-coord finished");
    assert.equal(seam("crashTitle")("agent-coord"), "OpenCode: agent-coord stopped");
  });

  it("uses the session agent, not a hard-coded name", () => {
    assert.equal(seam("finishedTitle")("build"), "OpenCode: build finished");
    assert.equal(seam("crashTitle")("build"), "OpenCode: build stopped");
  });
});

describe("T3 isTopLevel (AC 6, 7)", () => {
  it("treats an absent parentID as top-level", () => {
    const isTopLevel = seam("isTopLevel");
    assert.equal(isTopLevel({ agent: "agent-coord", parentID: undefined }), true);
    assert.equal(isTopLevel({ agent: "build" }), true);
  });

  it("treats a present parentID as a subagent", () => {
    assert.equal(seam("isTopLevel")(childSession()), false);
  });

  it("treats a missing session record as unknown topology — not top-level", () => {
    const isTopLevel = seam("isTopLevel");
    assert.equal(isTopLevel(undefined), false);
    assert.equal(isTopLevel(null), false);
  });
});

describe("T4 lastAssistantExcerpt (AC 6)", () => {
  // The 240 cap is asserted at the notify boundary (T6), where AC 6 and AC 7
  // put it; asserting it here too would pin which helper owns the truncation.
  it("returns the last text part of the last assistant message", () => {
    const messages = [
      user("do the thing"),
      assistant(reasoningPart("thinking"), textPart("first answer"), toolPart("call_1"), textPart("final answer")),
    ];
    assert.equal(seam("lastAssistantExcerpt")(messages), "final answer");
  });

  it("skips assistant messages that hold only reasoning or tool parts", () => {
    const messages = [
      assistant(textPart("earlier turn")),
      assistant(reasoningPart("still working"), toolPart("call_2")),
    ];
    assert.equal(seam("lastAssistantExcerpt")(messages), "earlier turn");
  });

  it("ignores user and system messages' top-level text", () => {
    const messages = [assistant(textPart("assistant said this")), user("user echoed that"), { type: "system", text: "system note" }];
    assert.equal(seam("lastAssistantExcerpt")(messages), "assistant said this");
  });

  it("returns the empty string for no messages and for no assistant text", () => {
    const excerpt = seam("lastAssistantExcerpt");
    assert.equal(excerpt([]), "");
    assert.equal(excerpt([user("only a prompt")]), "");
    assert.equal(excerpt(undefined), "");
  });

  it("passes through a long turn's text part verbatim", () => {
    assert.equal(seam("lastAssistantExcerpt")([assistant(textPart(LONG))]), LONG);
  });
});

describe("T5 crashExcerpt (AC 7)", () => {
  it("prefers the StructuredError message, falls back to its type", () => {
    const crashExcerpt = seam("crashExcerpt");
    assert.equal(crashExcerpt({ type: "provider_error", message: "429 too many requests" }), "429 too many requests");
    assert.equal(crashExcerpt({ type: "provider_auth_failure" }), "provider_auth_failure");
  });

  it("names an unknown error when the payload carries nothing", () => {
    const crashExcerpt = seam("crashExcerpt");
    assert.equal(crashExcerpt({}), "unknown error");
    assert.equal(crashExcerpt(undefined), "unknown error");
    assert.equal(crashExcerpt(null), "unknown error");
  });

  it("keeps status and response body out of the push", () => {
    const crashExcerpt = seam("crashExcerpt");
    const error = {
      type: "provider_error",
      message: "upstream exploded",
      status: 503,
      response: { body: "<html>503</html>" },
    };
    assert.equal(crashExcerpt(error), "upstream exploded");
  });
});

describe("T6 handleLifecycle dispatch (AC 6, 7, 8)", () => {
  it("pushes exactly one finished notification for a top-level succeeded turn", async () => {
    const { deps, calls } = fakeDeps({
      getSession: async () => topSession(),
      messages: [user("prompt"), assistant(reasoningPart("hm"), textPart("done — three charts changed"))],
    });
    const error = await runLifecycle(deps, succeededEvent("ses_top"));
    assert.equal(error, null, `handleLifecycle must resolve, threw ${error?.message ?? error}`);
    assert.ok(calls.getSession.includes("ses_top"), "topology must be looked up by the event's sessionID");
    assert.equal(calls.notify.length, 1, `expected one push, got ${JSON.stringify(calls.notify)}`);
    assert.equal(calls.notify[0].title, "OpenCode: agent-coord finished");
    assert.equal(calls.notify[0].message, "done — three charts changed");
  });

  it("caps the finished excerpt at 240 characters", async () => {
    const { deps, calls } = fakeDeps({
      getSession: async () => topSession(),
      messages: [assistant(textPart(LONG))],
    });
    assert.equal(await runLifecycle(deps, succeededEvent("ses_top")), null);
    assert.equal(calls.notify.length, 1);
    assert.equal(calls.notify[0].message.length, MAX);
    assert.equal(calls.notify[0].message, LONG.slice(0, MAX));
  });

  it("says \"no text output\" when the finished turn produced no text", async () => {
    const { deps, calls } = fakeDeps({
      getSession: async () => topSession(),
      messages: [assistant(reasoningPart("thinking"), toolPart("call_9"))],
    });
    assert.equal(await runLifecycle(deps, succeededEvent("ses_top")), null);
    assert.equal(calls.notify.length, 1);
    assert.equal(calls.notify[0].title, "OpenCode: agent-coord finished");
    assert.equal(calls.notify[0].message, "no text output");
  });

  it("stays silent for a subagent's succeeded turn", async () => {
    const { deps, calls } = fakeDeps({
      getSession: async () => childSession(),
      messages: [assistant(textPart("child finished"))],
    });
    const error = await runLifecycle(deps, succeededEvent("ses_child"));
    assert.equal(error, null);
    await settle();
    assert.equal(calls.notify.length, 0, "subagent sessions must never receive lifecycle pushes");
  });

  it("pushes exactly one stopped notification carrying the crash message", async () => {
    const { deps, calls } = fakeDeps({
      getSession: async () => topSession(),
      messages: [],
    });
    const error = await runLifecycle(
      deps,
      failedEvent("ses_top", { type: "provider_error", message: "exhausted retries: 429 too many requests", status: 429 }),
    );
    assert.equal(error, null, `handleLifecycle must resolve, threw ${error?.message ?? error}`);
    assert.equal(calls.notify.length, 1, `expected one push, got ${JSON.stringify(calls.notify)}`);
    assert.equal(calls.notify[0].title, "OpenCode: agent-coord stopped");
    assert.equal(calls.notify[0].message, "exhausted retries: 429 too many requests");
  });

  it("caps the crash message at 240 characters and falls back to the error type", async () => {
    const longError = fakeDeps({ getSession: async () => topSession() });
    assert.equal(await runLifecycle(longError.deps, failedEvent("ses_top", { type: "provider_error", message: LONG })), null);
    assert.equal(longError.calls.notify.length, 1);
    assert.equal(longError.calls.notify[0].message.length, MAX);

    const typeOnly = fakeDeps({ getSession: async () => topSession() });
    assert.equal(await runLifecycle(typeOnly.deps, failedEvent("ses_top", { type: "provider_auth_failure" })), null);
    assert.equal(typeOnly.calls.notify.length, 1);
    assert.equal(typeOnly.calls.notify[0].message, "provider_auth_failure");

    const noPayload = fakeDeps({ getSession: async () => topSession() });
    assert.equal(await runLifecycle(noPayload.deps, failedEvent("ses_top", undefined)), null);
    assert.equal(noPayload.calls.notify.length, 1);
    assert.equal(noPayload.calls.notify[0].message, "unknown error");
  });

  it("stays silent for a subagent's crash", async () => {
    const { deps, calls } = fakeDeps({ getSession: async () => childSession() });
    const error = await runLifecycle(deps, failedEvent("ses_child", { type: "provider_error", message: "boom" }));
    assert.equal(error, null);
    await settle();
    assert.equal(calls.notify.length, 0);
  });

  it("ignores every other event type, including V1-compat and retry events", async () => {
    const ignored = [
      "session.idle",
      "session.error",
      "session.status",
      "session.execution.interrupted",
      "session.retry.scheduled",
      "permission.updated",
      "file.edited",
      "unknown.future.event",
    ];
    for (const type of ignored) {
      const { deps, calls } = fakeDeps({
        getSession: async () => topSession(),
        messages: [assistant(textPart("should not be pushed"))],
      });
      const error = await runLifecycle(deps, { type, data: { sessionID: "ses_top" } });
      assert.equal(error, null, `${type} must not throw`);
      await settle();
      assert.equal(calls.notify.length, 0, `${type} must not push`);
    }
  });

  it("suppresses the push without rejecting when the session lookup fails", async () => {
    const getter = fakeDeps({ getSessionThrows: true });
    const error = await runLifecycle(getter.deps, succeededEvent("ses_gone"));
    assert.equal(error, null, `a failed session lookup must be swallowed, not thrown (${error?.message ?? error})`);
    await settle();
    assert.equal(getter.calls.notify.length, 0, "unknown topology must not ping the user");

    const failed = fakeDeps({ getSessionThrows: true });
    const error2 = await runLifecycle(failed.deps, failedEvent("ses_gone", { type: "provider_error", message: "boom" }));
    assert.equal(error2, null);
    await settle();
    assert.equal(failed.calls.notify.length, 0);
  });

  it("suppresses the finished push when the context lookup fails", async () => {
    const { deps, calls } = fakeDeps({ getSession: async () => topSession(), getMessagesThrows: true });
    const error = await runLifecycle(deps, succeededEvent("ses_top"));
    assert.equal(error, null);
    await settle();
    assert.equal(calls.notify.length, 0);
  });

  it("stays silent when the event names a session that no longer exists", async () => {
    const { deps, calls } = fakeDeps({ getSession: async () => undefined });
    const error = await runLifecycle(deps, succeededEvent("ses_deleted"));
    assert.equal(error, null);
    await settle();
    assert.equal(calls.notify.length, 0);
  });
});

describe("T7 event envelope tolerance (C01 Notes for dev: defensive dual-read)", () => {
  it("reads the sessionID from a flat event payload too", async () => {
    const { deps, calls } = fakeDeps({
      getSession: async () => topSession(),
      messages: [assistant(textPart("flat envelope finished"))],
    });
    const error = await runLifecycle(deps, { type: "session.execution.succeeded", sessionID: "ses_top" });
    assert.equal(error, null);
    assert.equal(calls.notify.length, 1, "a flat-payload succeeded event must still push once");
    assert.equal(calls.notify[0].message, "flat envelope finished");
  });

  it("reads error from a flat crash payload too", async () => {
    const { deps, calls } = fakeDeps({ getSession: async () => topSession() });
    const error = await runLifecycle(deps, {
      type: "session.execution.failed",
      sessionID: "ses_top",
      error: { type: "provider_error", message: "flat envelope crash" },
    });
    assert.equal(error, null);
    assert.equal(calls.notify.length, 1);
    assert.equal(calls.notify[0].message, "flat envelope crash");
  });
});

// A scheduled-launch record ended without ever claiming or writing: the shape
// the coord's read-merge-write leaves on the session (C02.md Marker contract).
const NOOP_AT = 1761730800000;
const marker = (value: any) => ({ pipelineNoop: value });
const scheduled = (extra: any = {}) => ({
  openchamber: { kind: "scheduled", ...(extra.openchamber ?? {}) },
  ...(extra.pipelineNoop !== undefined ? { pipelineNoop: extra.pipelineNoop } : {}),
});

function withConsoleErrorCapture(fn: () => Promise<any>): Promise<{ error: any; lines: string[] }> {
  return new Promise(async (resolve) => {
    const lines: string[] = [];
    const original = console.error;
    console.error = (...args: any[]) => lines.push(args.map(String).join(" "));
    try {
      const error = await fn();
      resolve({ error, lines });
    } finally {
      console.error = original;
    }
  });
}

describe("T9 noWorkSuppressed — the reader conjunction (C02 OQ2/OQ4, AC 2)", () => {
  const suppressedCase = { metadata: scheduled({ pipelineNoop: { at: NOOP_AT, reason: "no-cards" } }) };
  const suppressedCaseNoAt = { metadata: scheduled({ pipelineNoop: { reason: "no-claimable-cards" } }) };
  // The reader's well-formedness test is the reason field alone (C02.md
  // predicate item 3): `at` is the writer's audit stamp, never a gate — a
  // marker whose epoch leg died still marks the no-op, and dropping it from
  // the conjunction is what keeps the safe direction (alert) impossible to
  // reach by shape accident.
  it("exports the pure predicate (C02 Tasks: noWorkSuppressed(info))", () => {
    assert.equal(typeof mod.noWorkSuppressed, "function", "noWorkSuppressed must be an exported pure seam (red before C02 dev)");
  });

  it("true only on well-formed marker AND scheduled kind — the conjunction both ways", () => {
    const p = seam("noWorkSuppressed");
    assert.equal(p(suppressedCase), true, "scheduled + {at, reason} marker suppresses");
    assert.equal(p(suppressedCaseNoAt), true, "a non-empty string reason alone is the reader's well-formedness (OQ2)");
    assert.equal(p({ metadata: { pipelineNoop: { at: NOOP_AT, reason: "no-cards" } } }), false, "marker alone must never mute (OQ4): absent kind alerts");
    assert.equal(p({ metadata: scheduled({ pipelineNoop: { reason: "no-cards" }, openchamber: { kind: "manual" } }) }), false, "manual launches keep alerting (OQ4 by name)");
    assert.equal(p({ metadata: scheduled({ openchamber: { kind: "auto" } }) }), false, "scheduled without a marker alerts");
  });

  it("malformed markers all alert (fail-loud default)", () => {
    const p = seam("noWorkSuppressed");
    for (const bad of ["no-cards", true, 42, null, [], {}, { reason: "" }, { reason: 7 }, { at: NOOP_AT }]) {
      assert.equal(p({ metadata: scheduled({ pipelineNoop: bad }) }), false, `marker ${JSON.stringify(bad)} on a scheduled launch must NOT suppress`);
    }
  });

  it("absent, null or non-object metadata alerts; no shape throws", () => {
    const p = seam("noWorkSuppressed");
    for (const info of [undefined, null, {}, { metadata: undefined }, { metadata: null }, "session", 42]) {
      assert.equal(p(info as any), false, `${JSON.stringify(info)} must resolve to alert, not throw`);
    }
  });

  it("tolerates both record envelopes (the dual-read habit of this codebase)", () => {
    const p = seam("noWorkSuppressed");
    assert.equal(p({ data: suppressedCase }), true, "a {data: ...}-wrapped record suppresses identically");
    assert.equal(p({ data: { metadata: { pipelineNoop: { reason: "no-cards" } } } }), false, "envelope tolerance never widens the conjunction");
  });
});

describe("T10 handleLifecycle FINISHED suppression matrix (C02 AC 1/2, OQ4 both directions)", () => {
  it("scheduled + well-formed marker: no push, no message fetch, one session lookup, suppression logged", async () => {
    const { deps, calls } = fakeDeps({
      getSession: async () => ({ id: "ses_top", agent: "agent-board-coord", title: "tick", metadata: scheduled({ pipelineNoop: { at: NOOP_AT, reason: "no-cards" } }) }),
      messages: [assistant(textPart("RESULT status: NEEDS_INFO — no cards"))],
    });
    const { error, lines } = await withConsoleErrorCapture(() => runLifecycle(deps, succeededEvent("ses_top")));
    assert.equal(error, null);
    await settle();
    assert.equal(calls.notify.length, 0, "the scheduled no-op tick is the exact case OQ1/OQ2/OQ4 silences");
    assert.equal(calls.getSession.length, 1, "the conjunction rides the already-performed getSession (C02: zero extra round-trips)");
    assert.equal(calls.getMessages.length, 0, "suppression returns before getMessages — an unmarked session pays nothing (C02 Notes for dev)");
    assert.ok(
      lines.some((l) => l.includes("[question-notify] suppressed no-work finished push ses_top")),
      `expected the stderr audit line, saw ${JSON.stringify(lines)}`,
    );
    assert.ok(
      !lines.some((l) => l.includes("lifecycle push suppressed")),
      "the no-work path is a distinct decision from the T6 doubt-suppression path",
    );
  });

  it("manual launch + well-formed marker STILL pushes (OQ4 ruling, loud direction)", async () => {
    const { deps, calls } = fakeDeps({
      getSession: async () => ({ id: "ses_top", agent: "agent-board-coord", title: "manual", metadata: { pipelineNoop: { at: NOOP_AT, reason: "no-cards" } } }),
      messages: [assistant(textPart("clean no-op end"))],
    });
    assert.equal(await runLifecycle(deps, succeededEvent("ses_top")), null);
    assert.equal(calls.notify.length, 1, "a manual /pipeline-boards no-op keeps alerting — the marker is forensic evidence, not a mute button");
  });

  it("scheduled + absent or malformed marker pushes", async () => {
    for (const noop of [undefined, "no-cards", {}, { reason: "" }, true]) {
      const metadata: any = { openchamber: { kind: "scheduled" } };
      if (noop !== undefined) metadata.pipelineNoop = noop;
      const { deps, calls } = fakeDeps({
        getSession: async () => ({ id: "ses_top", agent: "agent-board-coord", metadata }),
        messages: [assistant(textPart("real completion"))],
      });
      assert.equal(await runLifecycle(deps, succeededEvent("ses_top")), null);
      assert.equal(calls.notify.length, 1, `scheduled + marker ${JSON.stringify(noop)} must alert (every unknown shape pushes)`);
    }
  });

  it("kind scheduled-like but not the literal (manual/auto/other) pushes", async () => {
    for (const kind of ["manual", "auto", "user", "Scheduled", ""]) {
      const { deps, calls } = fakeDeps({
        getSession: async () => ({ id: "ses_top", agent: "agent-board-coord", metadata: scheduled({ pipelineNoop: { reason: "no-cards" }, openchamber: { kind } }) }),
        messages: [assistant(textPart("done"))],
      });
      assert.equal(await runLifecycle(deps, succeededEvent("ses_top")), null);
      assert.equal(calls.notify.length, 1, `kind "${kind}" is not the scheduled discriminator — alert`);
    }
  });

  it("CRASH event with marker + scheduled still pushes (predicate is FINISHED-only)", async () => {
    const { deps, calls } = fakeDeps({
      getSession: async () => ({ id: "ses_top", agent: "agent-board-coord", metadata: scheduled({ pipelineNoop: { reason: "no-cards" } }) }),
    });
    assert.equal(await runLifecycle(deps, failedEvent("ses_top", { type: "provider_error", message: "boom" })), null);
    assert.equal(calls.notify.length, 1, "a crash push never consults the no-work predicate (C02 predicate item 1)");
    assert.equal(calls.notify[0].title, "OpenCode: agent-board-coord stopped");
  });

  it("child session with both shapes present: topology filter first, no push (unchanged)", async () => {
    const { deps, calls } = fakeDeps({
      getSession: async () => ({ ...childSession(), metadata: scheduled({ pipelineNoop: { reason: "no-cards" } }) }),
      messages: [assistant(textPart("child done"))],
    });
    assert.equal(await runLifecycle(deps, succeededEvent("ses_child")), null);
    await settle();
    assert.equal(calls.notify.length, 0, "subagents never receive lifecycle pushes — before the conjunction is ever read");
  });

  it("suppression consumes no cooldown: a later real completion still pushes", async () => {
    const allowPushCalls: string[] = [];
    const records: any[] = [
      { id: "ses_top", agent: "agent-board-coord", metadata: scheduled({ pipelineNoop: { reason: "no-cards" } }) },
      { id: "ses_top", agent: "agent-board-coord", metadata: scheduled() },
    ];
    const { deps, calls } = fakeDeps({ getSession: async () => records.shift(), messages: [assistant(textPart("real work finished"))] });
    (deps as any).allowPush = (key: string) => {
      allowPushCalls.push(key);
      return true;
    };
    assert.equal(await runLifecycle(deps, succeededEvent("ses_top")), null);
    await settle();
    assert.equal(calls.notify.length, 0);
    assert.deepEqual(allowPushCalls, [], "a suppression must not stamp the shared cooldown gate (C02 Tasks)");
    assert.equal(await runLifecycle(deps, succeededEvent("ses_top")), null);
    assert.equal(calls.notify.length, 1, "the next scheduled completion within the window rings regardless of the earlier silence");
  });
});

describe("T8 subscribe loop wiring (C01 Tasks: wire the live loop in setup)", () => {
  it("consumes the event stream, filters through the seam, and aborts on cleanup", async () => {
    const stream = makeStream();
    const { ctx, seen } = fakeCtx({
      events: stream.iterable,
      sessions: { ses_child: childSession(), ses_child2: childSession("agent-review") },
    });
    let cleanup: any;
    try {
      // Bounded: a loop awaited inside setup instead of backgrounded would
      // never settle against this still-open stream, and would hang the run
      // rather than report the contract it breaks.
      const pending = Symbol("setup still pending");
      const settled = await Promise.race([
        mod.default.setup(ctx),
        new Promise((resolve) => setTimeout(() => resolve(pending), 1000)),
      ]);
      assert.notEqual(
        settled,
        pending,
        "setup must return while the event stream is still open — a subscription loop awaited inside setup blocks plugin load",
      );
      cleanup = settled;
      assert.ok(
        await until(() => seen.subscribeArgs.length > 0),
        "setup must subscribe to ctx.event within the awaited timeout",
      );
      const signal = seen.subscribeArgs[0]?.signal;
      assert.equal(typeof signal?.addEventListener, "function", "subscribe must pass an AbortSignal ({ signal })");
      assert.equal(typeof cleanup, "function", "setup must return a cleanup function");

      // Child sessions resolve through the topology check and stop before the
      // notify path, so this proves the loop reaches handleLifecycle offline.
      stream.push(succeededEvent("ses_child"));
      assert.ok(
        await until(() => seen.sessionIDs.includes("ses_child")),
        `the loop must look up the event's session, saw ids ${JSON.stringify(seen.sessionIDs)}`,
      );

      stream.push({ type: "session.status", data: { sessionID: "ses_noise" } });
      stream.push(succeededEvent("ses_child2"));
      assert.ok(
        await until(() => seen.sessionIDs.includes("ses_child2")),
        "a non-lifecycle event must not break the loop — no further events were consumed",
      );

      await settle();
    } finally {
      stream.stop();
    }

    cleanup();
    assert.ok(
      await until(() => seen.subscribeArgs[0]?.signal?.aborted === true),
      "cleanup must abort the subscription's AbortSignal",
    );
  });
});
