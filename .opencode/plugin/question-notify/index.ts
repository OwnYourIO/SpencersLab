// OpenCode V2 local plugin: pushes a notification to the user's phone via Home
// Assistant when (1) an agent-* session asks a question (question tool hook)
// or (2) a top-level session finishes an assistant turn or stops on a terminal
// execution failure (event stream). Hand-written — rulesync must never generate
// or delete this file (rulesync's hooks feature is OFF in rulesync.jsonc; no
// other writer exists).
//
// Why raw MCP JSON-RPC instead of the MCP tools: plugins run in the OpenCode
// server process, outside any agent session — MCP tools exist for models, not
// for plugins. The lab's ha-mcp servers are remote streamable-HTTP endpoints
// in the cluster, so the plugin speaks MCP directly (initialize →
// notifications/initialized → tools/call call_service). Deterministic: no
// model in the loop. The server URL is discovered at runtime from
// ctx.mcp.list() (falls back to parsing .opencode/opencode.jsonc), so nothing
// is hard-coded. The ADMIN endpoint is required: the readonly ha-mcp server
// runs READ_ONLY_MODE and rejects service calls.
//
// Failure policy: a notification must never delay or break the agent —
// everything here is fire-and-forget with stderr logging only. A lifecycle
// session lookup that fails suppresses its push rather than pinging about a
// session whose topology could not be verified.
//
// Verified against @opencode/plugin 2.1.2 types (dist/promise/tool.d.ts):
// the execute.before event carries { tool, sessionID, agent, messageID, id,
// input } directly — we read event.agent and keep a ctx.session.get fallback
// only because the installed CLI (v2.0.32) predates the checked types.
// Lifecycle triggers are the durable V2 execution pair below, grounded against
// the installed v2.0.32 binary (see .agents/plans/2026/2026-10-feat-ha-lifecycle-
// notify). They fire once per terminal outcome of an agent-loop run, so retries
// and transient status events need neither a heuristic nor a dedup map; legacy
// session.idle/session.error and interrupts stay ignored on purpose — the plan's
// grep commands pin the pair.
// Unverified at write time (watch ~/.local/share/opencode/log/opencode.log):
// - Whether this ha-mcp build accepts tools/call without the initialized
//   notification; we send the full handshake anyway.
// - The per-event envelope of the lifecycle stream. The loop logs the keys of
//   the first lifecycle event once, so the user-owned live smoke confirms the
//   shape; handleLifecycle's dual read already covers the flat variant.

const NOTIFY_DOMAIN = "notify";
const NOTIFY_SERVICE = "mobile_app_pixel_6";
const MCP_SERVER_KEY = "admin-global-homeassistant";
const AGENT_PREFIX = "agent-";
const COOLDOWN_MS = 15_000; // one push per session per question burst
const MAX_MESSAGE = 240;
const FINISHED_EVENT = "session.execution.succeeded";
const CRASH_EVENT = "session.execution.failed";

// Exported seam: tests/opencode/question-notify.test.ts drives the whole
// lifecycle decision matrix offline through handleLifecycle with fakes for the
// session lookups and the push, so no test needs a server or a socket.
// The helpers are pure.

// A non-string body collapses to "" rather than "undefined": a notification
// for a missing part is empty, never misleading.
export function truncate(value: any): string {
  return typeof value === "string" ? value.slice(0, MAX_MESSAGE) : "";
}

export function questionTitle(agent: string): string {
  return `OpenCode: ${agent} has a question`;
}

export function finishedTitle(agent: string): string {
  return `OpenCode: ${agent} finished`;
}

export function crashTitle(agent: string): string {
  return `OpenCode: ${agent} stopped`;
}

// A missing session record is unknown topology, not top-level: the failure
// policy suppresses on doubt rather than pinging about a session whose
// parentage could not be read.
export function isTopLevel(info: any): boolean {
  if (!info || typeof info !== "object") return false;
  return !info.parentID;
}

// Newest-first scan over assistant `content` parts only: a turn commonly ends
// on a tool or reasoning part, and the top-level `text` on user/system records
// is the user's own prompt — reading it would echo it back as the answer.
export function lastAssistantExcerpt(messages: any): string {
  if (!Array.isArray(messages)) return "";
  for (let i = messages.length - 1; i >= 0; i--) {
    const message = messages[i];
    if (message?.type !== "assistant" || !Array.isArray(message.content)) continue;
    for (let j = message.content.length - 1; j >= 0; j--) {
      const part = message.content[j];
      if (part?.type === "text" && typeof part.text === "string") return part.text;
    }
  }
  return "";
}

// Session.StructuredError puts the human-readable text in `message` and falls
// back to its discriminator; `status`/`response.body` are noise for a phone push.
export function crashExcerpt(error: any): string {
  if (typeof error?.message === "string" && error.message) return error.message;
  return typeof error?.type === "string" && error.type ? error.type : "unknown error";
}

export async function handleLifecycle(deps: any, event: any): Promise<void> {
  const type = event?.type;
  if (type !== FINISHED_EVENT && type !== CRASH_EVENT) return;
  try {
    // Dual read: the V2-native envelope nests the payload under `data`, the
    // compat layer may deliver it flat.
    const sessionID: string | undefined = event.data?.sessionID ?? event.sessionID;
    if (!sessionID) return;
    const info = await deps.getSession(sessionID);
    if (!isTopLevel(info)) return;
    const agent = typeof info.agent === "string" && info.agent ? info.agent : "session";
    if (type === FINISHED_EVENT) {
      const messages = await deps.getMessages(sessionID);
      await deps.notify(finishedTitle(agent), truncate(lastAssistantExcerpt(messages) || "no text output"));
    } else {
      await deps.notify(crashTitle(agent), truncate(crashExcerpt(event.data?.error ?? event.error)));
    }
  } catch (err: any) {
    // Swallowed by design: the caller's stream must keep consuming, and a
    // partial lookup must not reach the phone.
    console.error("[question-notify] lifecycle push suppressed:", err?.message ?? err);
  }
}

function firstQuestion(input: any): string {
  const q = input?.questions;
  if (Array.isArray(q) && q.length > 0) {
    const head = q[0];
    return String(head?.question ?? head?.header ?? "question pending");
  }
  return "question pending";
}

async function haMcpUrl(ctx: any): Promise<string | null> {
  try {
    const list = await ctx.mcp?.list?.();
    const entries: any[] = Array.isArray(list) ? list : (list?.servers ?? []);
    for (const entry of entries) {
      const [name, cfg] = Array.isArray(entry) ? entry : [entry?.name, entry];
      if (name === MCP_SERVER_KEY && typeof cfg?.url === "string") return cfg.url;
    }
  } catch {
    // fall through to config parsing
  }
  try {
    const { readFileSync } = await import("node:fs");
    const { join } = await import("node:path");
    const raw = readFileSync(join(ctx.location.directory, ".opencode", "opencode.jsonc"), "utf8");
    const idx = raw.indexOf(`"${MCP_SERVER_KEY}"`);
    if (idx < 0) return null;
    const m = raw.slice(idx).match(/"url"\s*:\s*"([^"]+)"/);
    return m ? m[1] : null;
  } catch {
    return null;
  }
}

let rpcSeq = 0;

async function mcpRequest(url: string, sessionID: string | null, method: string, params: any): Promise<{ body: any; sessionID: string | null }> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json, text/event-stream",
  };
  if (sessionID) headers["Mcp-Session-Id"] = sessionID;
  const isNotification = method.startsWith("notifications/");
  const payload: any = { jsonrpc: "2.0", method, params };
  if (!isNotification) payload.id = ++rpcSeq;
  const res = await fetch(url, { method: "POST", headers, body: JSON.stringify(payload) });
  const sid = res.headers.get("mcp-session-id") ?? sessionID;
  if (isNotification) return { body: null, sessionID: sid };
  const text = await res.text();
  if (!text) return { body: null, sessionID: sid };
  // Streamable HTTP may answer with SSE frames or plain JSON.
  if (text.includes("data:")) {
    const data = text.split("\n").filter((l) => l.startsWith("data:")).pop()?.slice(5);
    return { body: data ? JSON.parse(data) : null, sessionID: sid };
  }
  return { body: JSON.parse(text), sessionID: sid };
}

async function sendHANotify(ctx: any, title: string, message: string) {
  const url = await haMcpUrl(ctx);
  if (!url) {
    console.error("[question-notify] no URL found for", MCP_SERVER_KEY);
    return;
  }
  const init = await mcpRequest(url, null, "initialize", {
    protocolVersion: "2025-06-18",
    capabilities: {},
    clientInfo: { name: "opencode-question-notify", version: "1.0.0" },
  });
  await mcpRequest(url, init.sessionID, "notifications/initialized", {});
  const call = await mcpRequest(url, init.sessionID, "tools/call", {
    name: "call_service",
    arguments: {
      domain: NOTIFY_DOMAIN,
      service: NOTIFY_SERVICE,
      data: { title, message: truncate(message) },
    },
  });
  if (call.body?.error) console.error("[question-notify] call_service error:", JSON.stringify(call.body.error));
}

export default {
  id: "local.question-notify",
  async setup(ctx: any) {
    const lastNotified = new Map<string, number>();
    let debugLogged = false;
    let lifecycleDebugLogged = false;

    await ctx.tool.hook("execute.before", async (event: any) => {
      try {
        if (event.tool !== "question") return;
        if (!debugLogged) {
          debugLogged = true;
          console.error("[question-notify] execute.before event keys:", Object.keys(event ?? {}));
        }
        const sessionID: string | undefined = event.sessionID ?? event.context?.sessionID;
        let agent: unknown = event.agent;
        if (typeof agent !== "string" && sessionID) {
          try {
            agent = (await ctx.session.get({ sessionID }))?.agent;
          } catch {
            agent = undefined;
          }
        }
        if (typeof agent !== "string" || !agent.startsWith(AGENT_PREFIX)) return;

        const key = sessionID ?? agent;
        const now = Date.now();
        if (now - (lastNotified.get(key) ?? 0) < COOLDOWN_MS) return;
        lastNotified.set(key, now);

        void sendHANotify(ctx, questionTitle(agent), firstQuestion(event.input)).catch((err) =>
          console.error("[question-notify] notify failed:", err?.message ?? err),
        );
      } catch (err: any) {
        console.error("[question-notify] hook error:", err?.message ?? err);
      }
    });

    // The loop must not be awaited inside setup: a subscription stays open for
    // the life of the server, and blocking setup would hang plugin load. Each
    // event is dispatched fire-and-forget so one failed push cannot stop
    // consumption; the returned cleanup aborts the subscription on unload.
    const controller = new AbortController();
    const deps = {
      getSession: (sessionID: string) => ctx.session.get({ sessionID }),
      getMessages: (sessionID: string) => ctx.session.context({ sessionID }),
      notify: (title: string, message: string) => sendHANotify(ctx, title, message),
    };
    // A subscription that cannot start must not reject setup: the question hook
    // above is already registered and has its own verified-working contract.
    let stream: any;
    try {
      stream =
        typeof ctx.event?.subscribe === "function"
          ? ctx.event.subscribe({ signal: controller.signal })
          : undefined;
    } catch (err: any) {
      console.error("[question-notify] event subscription failed:", err?.message ?? err);
    }
    if (stream) {
      void (async () => {
        for await (const event of stream) {
          if ((event?.type === FINISHED_EVENT || event?.type === CRASH_EVENT) && !lifecycleDebugLogged) {
            lifecycleDebugLogged = true;
            console.error(
              "[question-notify] first lifecycle event keys:",
              Object.keys(event ?? {}),
              "data keys:",
              Object.keys(event?.data ?? {}),
            );
          }
          void handleLifecycle(deps, event).catch((err: any) =>
            console.error("[question-notify] lifecycle handler failed:", err?.message ?? err),
          );
        }
      })().catch((err: any) => console.error("[question-notify] event stream ended:", err?.message ?? err));
    }

    return () => controller.abort();
  },
};