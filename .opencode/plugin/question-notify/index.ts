// OpenCode V2 local plugin: when an agent-* session asks a question
// (question tool), push a notification to the user's phone via Home Assistant.
// Hand-written — rulesync must never generate or delete this file (rulesync's
// hooks feature is OFF in rulesync.jsonc; no other writer exists).
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
// Failure policy: a notification must never delay or break a question —
// everything here is fire-and-forget with stderr logging only.
//
// Verified against @opencode/plugin 2.1.2 types (dist/promise/tool.d.ts):
// the execute.before event carries { tool, sessionID, agent, messageID, id,
// input } directly — we read event.agent and keep a ctx.session.get fallback
// only because the installed CLI (v2.0.32) predates the checked types.
// Unverified at write time (watch ~/.local/share/opencode/log/opencode.log):
// - Whether this ha-mcp build accepts tools/call without the initialized
//   notification; we send the full handshake anyway.

const NOTIFY_DOMAIN = "notify";
const NOTIFY_SERVICE = "mobile_app_pixel_6";
const MCP_SERVER_KEY = "admin-global-homeassistant";
const AGENT_PREFIX = "agent-";
const COOLDOWN_MS = 15_000; // one push per session per question burst
const MAX_MESSAGE = 240;

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

async function sendHANotify(ctx: any, agent: string, message: string) {
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
      data: { title: `OpenCode: ${agent} has a question`, message: message.slice(0, MAX_MESSAGE) },
    },
  });
  if (call.body?.error) console.error("[question-notify] call_service error:", JSON.stringify(call.body.error));
}

export default {
  id: "local.question-notify",
  async setup(ctx: any) {
    const lastNotified = new Map<string, number>();
    let debugLogged = false;

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

        void sendHANotify(ctx, agent, firstQuestion(event.input)).catch((err) =>
          console.error("[question-notify] notify failed:", err?.message ?? err),
        );
      } catch (err: any) {
        console.error("[question-notify] hook error:", err?.message ?? err);
      }
    });
  },
};