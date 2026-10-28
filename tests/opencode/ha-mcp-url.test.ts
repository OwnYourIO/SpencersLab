// C04 acceptance checks (2026-10-feat-ha-lifecycle-notify): the haMcpUrl seam
// battery H1–H9 for the live silent-pushes incident. Since the 2026-10-25 fleet
// split the HA server lives only in the machine-global config, so the shipped
// chain resolves nothing: ctx.mcp.list() answers the v2.1.4 status view
// Mcp.Server{name,status,integrationID} (additionalProperties:false — no url,
// plan Grounding #20) and the project-jsonc fallback parses a file with 0 HA
// hits (94× "no URL found" in the coder pod stdout). The fix makes discovery
// primary through the ctx's MCP CONFIG VIEW — ctx.mcp.transform(callback),
// whose editor.get(name) returns full server configs including url, fed from
// ALL config documents (Grounding #18/#22) — demotes the list() scan to a
// compat fallback, and retires the jsonc parse. Covers AC 8/9 of chunks/C04.md.
//
// The two sibling test files are byte-pinned (AC 2, md5 8b5d8382… / 0a522f0f…);
// everything new lives here. That pin is load-bearing for one boundary in
// particular: the permission file's setup-level fakes pass ctx objects with
// mcp:{list:async()=>[]} and NO transform, and count pushes at sendHANotify's
// "no URL found" marker — so the new chain must resolve exactly null (never
// reject, never invent a url) for those ctx shapes. H2/H3/H5 pin that at the
// seam; AC 6's grep pins the marker itself, which is why nothing here asserts
// haMcpUrl's own stderr content — the marker belongs to sendHANotify, not to
// discovery (chunks/C04.md "Deliberate non-assertions").
//
// Offline, deterministic, fake-only: discovery has no transport, so there is
// nothing to fetch or socket-stub. The fakes mirror the binary-verified v2.1.4
// semantics: the transform callback fires BEFORE the Registration promise
// resolves and may re-fire on every state recompute until disposed (capture
// must be idempotent — Grounding #21); a callback that throws past itself
// fails the plugin's whole registration group and poisons every later
// transform for the process lifetime, so the guard must sit inside the
// callback (H6 pins it); dispose is awaited in a finally and its rejection
// swallowed (H1/H7).
//
// Run from the repo root: node --test 'tests/opencode/*.test.ts' — the glob is
// quoted because a bare `tests/opencode` directory argument fails under this
// Node build (FRICTION 2026-10-26). The file lives in the repo-root tests/
// tree, NOT under .opencode/, where plugin discovery could import it as a
// plugin entry at server startup (same placement rule as its siblings).

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import * as plugin from "../../.opencode/plugin/question-notify/index.ts";

// Namespace import so a module that has not grown the export yet fails on the
// seam() assertion below rather than as an ESM link error — a link error would
// take every other test in this file down with it and read as broken
// scaffolding (same reason C01 adopted it).
const mod = plugin as Record<string, any>;

const HA_KEY = "admin-global-homeassistant";
const HA_URL = "http://ha.invalid/mcp";
const HA_URL2 = "http://ha2.invalid/mcp";

function seam(name: string): (...args: any[]) => any {
  const fn = typeof mod[name] === "function" ? mod[name] : mod.default?.[name];
  if (typeof fn !== "function") {
    throw new Error(
      `plugin seam "${name}" is not exported (chunks/C04.md Tasks: export haMcpUrl as the URL-discovery test seam from .opencode/plugin/question-notify/index.ts)`,
    );
  }
  return fn;
}

// Every plugin log goes to console.error; the returned handle restores it in
// the caller's finally so a leak can never silence a later test.
function captureErrors() {
  const lines: string[] = [];
  const original = console.error;
  console.error = (...args: any[]) => {
    lines.push(args.map(String).join(" "));
  };
  return {
    lines,
    restore: () => {
      console.error = original;
    },
  };
}

// haMcpUrl must never reject on any input shape (AC 8) — capture instead of
// awaiting so each test asserts the rejection itself, never a thrown red that
// hides which contract broke.
async function callUrl(ctx: any): Promise<{ error: any; result: any }> {
  const haMcpUrl = seam("haMcpUrl");
  let error: any = null;
  let result: any = "unset";
  try {
    result = await haMcpUrl(ctx);
  } catch (err) {
    error = err;
  }
  return { error, result };
}

const tick = () => new Promise((resolve) => setTimeout(resolve, 5));

// The one fake ctx this battery needs: mcp.transform mirrors the v2.1.4
// registration lifecycle (callback over an editor view of the config map,
// fired synchronously before the Registration resolves — Grounding #21a), and
// mcp.list mirrors the two real entry shapes the retained compat scan
// tolerates (tuple [name, cfg] and object {name, ...cfg}). The dispose spy
// logs call and resolution as separate events with a real await between: a
// dispose that is fired-and-forgotten leaves its "disposed" event AFTER
// haMcpUrl resolves, so the event sequence distinguishes awaited from merely
// called (AC 8).
function fakeMcpCtx(opts: any = {}) {
  const events: string[] = [];
  const seen: any = {
    transformCalls: 0,
    cbFires: 0,
    cbEscapes: [] as any[],
    listCalls: 0,
    getNames: [] as string[],
    events,
    count: (marker: string) => events.filter((e) => e === marker).length,
    last: () => events[events.length - 1],
  };
  const entries: Map<string, any> =
    opts.entries instanceof Map ? opts.entries : new Map(Object.entries(opts.entries ?? {}));
  const editor = {
    list: () => Array.from(entries.entries()),
    get: (name: string) => {
      seen.getNames.push(name);
      if (opts.getThrows) throw new Error("editor.get boom");
      return entries.get(name);
    },
    set: (name: string, config: any) => {
      entries.set(name, config);
    },
    update: (_name: string, _config: any) => {},
    remove: (_name: string) => {},
  };
  const transform = (cb: any) => {
    seen.transformCalls++;
    events.push("transform");
    if (opts.transformThrows) throw new Error("transform boom");
    return (async () => {
      const fires = typeof opts.fires === "number" ? opts.fires : 1;
      for (let i = 0; i < fires; i++) {
        seen.cbFires++;
        try {
          cb(editor);
        } catch (err) {
          seen.cbEscapes.push(err);
        }
      }
      if (opts.reg === "none") return undefined;
      if (opts.reg === "bare") return {};
      return {
        dispose: async () => {
          events.push("dispose-call");
          await tick();
          if (opts.disposeRejects) throw new Error("dispose boom");
          events.push("disposed");
        },
      };
    })();
  };
  const mcp: any = {};
  if (!opts.noTransform) mcp.transform = transform;
  if (!opts.noList) {
    mcp.list = async () => {
      seen.listCalls++;
      events.push("list");
      if (opts.listRejects) throw new Error("list boom");
      return opts.listEntries ?? [];
    };
  }
  const ctx: any = { mcp };
  if (opts.location) ctx.location = opts.location;
  return { ctx, seen, entries };
}

const remote = (url = HA_URL, extra: any = {}) => ({ type: "remote", url, ...extra });
// Mcp.Server as the live OpenAPI describes it (Grounding #20): the status view
// the shipped chain kept getting — name and status, never a url.
const statusServer = () => ({ name: HA_KEY, status: { status: "connected" } });
const statusTuple = () => [HA_KEY, { status: { status: "connected" } }];

describe("H0 haMcpUrl seam export (AC 3)", () => {
  it("exports haMcpUrl as a named function taking exactly one ctx parameter", () => {
    const fn = seam("haMcpUrl");
    assert.equal(fn.length, 1, "the seam signature must be haMcpUrl(ctx) — plan Commands load+shape check pins exactly one parameter");
  });
});

describe("H1 config-view primary (AC 8, chunk Goal)", () => {
  it("resolves exactly the config-view url when only transform can see the server", async () => {
    // The incident's fixed world: mcp.list answers nothing (here: rejects,
    // doubling as the negative control proving leg 1 short-circuits) while the
    // config view carries the machine-global admin entry.
    const { ctx, seen } = fakeMcpCtx({ entries: { [HA_KEY]: remote() }, listRejects: true });
    const cap = captureErrors();
    let out: any;
    try {
      out = await callUrl(ctx);
    } finally {
      cap.restore();
    }
    assert.equal(out.error, null, `haMcpUrl must never reject: ${out.error?.message ?? out.error}`);
    assert.equal(out.result, HA_URL, "a config-view hit is the answer");
    assert.ok(seen.getNames.includes(HA_KEY), `the editor must be queried by the admin key exactly, saw ${JSON.stringify(seen.getNames)}`);
    assert.equal(seen.cbFires, 1, "transform must register a callback and await its Registration (Grounding #21a)");
    assert.equal(seen.listCalls, 0, "leg 1 hit short-circuits — the compat leg never runs on a hit");
    assert.deepEqual(seen.cbEscapes, [], "the registered callback must not throw past itself (H6's poison rule applies here too)");
    assert.equal(seen.count("dispose-call"), 1, "exactly one dispose per resolution");
    assert.equal(seen.count("disposed"), 1, "dispose must be AWAITED before haMcpUrl resolves, not merely called");
    assert.equal(seen.last(), "disposed", "the register→capture→await-dispose order must hold per call");
    assert.deepEqual(cap.lines, [], `a successful resolution is stderr-silent, saw ${JSON.stringify(cap.lines)}`);
  });

  it("captures idempotently across callback re-fires and still disposes once", async () => {
    // Grounding #21: recomputes re-invoke live registrations until dispose, so
    // the same callback runs N times per resolution. The capture must survive
    // being re-run — observable as: still the right url, still one dispose.
    const { ctx, seen } = fakeMcpCtx({ entries: { [HA_KEY]: remote() }, fires: 3, noList: true });
    const out = await callUrl(ctx);
    assert.equal(out.error, null);
    assert.equal(seen.cbFires, 3, "the fake re-fired the registration three times as a recompute would");
    assert.equal(out.result, HA_URL, "re-fires must not corrupt the captured url");
    assert.equal(seen.count("dispose-call"), 1, "three fires still balance one dispose");
  });
});

describe("H2 config-view miss shapes (AC 8)", () => {
  it("resolves null when get() answers undefined and there is no compat leg at all", async () => {
    // The permission file's setup-level ctx boundary starts here: absent API
    // members must resolve null, not throw (AC 2 keeps that file byte-identical).
    const { ctx, seen } = fakeMcpCtx({ entries: {}, noList: true });
    const out = await callUrl(ctx);
    assert.equal(out.error, null);
    assert.equal(out.result, null, "editor.get(name) → undefined is a miss, not an error (Grounding #18)");
    assert.equal(seen.count("dispose-call"), 1, "the finally disposes on misses too");
  });

  it("resolves null for a local-type entry that carries no url", async () => {
    const { ctx, seen } = fakeMcpCtx({
      entries: { [HA_KEY]: { type: "local", command: ["npx", "ha-mcp"] } },
      listEntries: [statusServer()],
    });
    const out = await callUrl(ctx);
    assert.equal(out.error, null);
    assert.equal(out.result, null, "only a string url matches; a local config has none (RemoteConfigEncoded shape, Grounding #19)");
    assert.equal(seen.count("dispose-call"), 1, "dispose still called");
  });

  it("queries the admin key only — a readonly tier's url must never be picked", async () => {
    // The plugin must speak to the ADMIN endpoint (READ_ONLY_MODE ha-mcp
    // rejects service calls); discovery may not settle for any other name.
    const { ctx, seen } = fakeMcpCtx({
      entries: { "readonly-global-homeassistant": remote("http://readonly.invalid/mcp") },
      listEntries: [["readonly-global-homeassistant", remote("http://readonly.invalid/mcp")]],
    });
    const out = await callUrl(ctx);
    assert.equal(out.error, null);
    assert.equal(out.result, null, "no admin-key entry ⇒ null, even with a same-family url sitting right there");
    assert.ok(seen.getNames.includes(HA_KEY), `the editor must be queried by the admin key exactly, saw ${JSON.stringify(seen.getNames)}`);
  });
});

describe("H3 status-view world — the incident itself (AC 7/8 regression pin)", () => {
  it("resolves null and never rejects when transform is absent and list() answers only status entries", async () => {
    // Hypothetical older build without the transform API, or a build whose
    // state group failed: exactly the 2026-10-28 failure signature — name +
    // status, no url — pinned as a HANDLED null outcome in both entry shapes,
    // and as proof the retained url check cannot false-positive on it.
    for (const view of [
      { label: "object entries", listEntries: [statusServer(), statusServer()] },
      { label: "tuple entries", listEntries: [statusTuple(), statusTuple()] },
    ]) {
      const { ctx, seen } = fakeMcpCtx({ noTransform: true, listEntries: view.listEntries });
      const out = await callUrl(ctx);
      assert.equal(out.error, null, `${view.label}: must never reject (AC 8)`);
      assert.equal(out.result, null, `${view.label}: the status view carries no url — nothing may match (Grounding #20)`);
      assert.equal(seen.listCalls, 1, `${view.label}: with no transform, the compat leg still runs`);
    }
  });
});

describe("H4 compat-leg hit — the demoted list() still has a job (AC 8)", () => {
  it("falls through to list() when transform registers but its callback never fires", async () => {
    // Grounding #21's failed-group world: the registration resolves without the
    // callback ever running. The retained scan must cover it, in both entry
    // forms, and the registration must still be disposed.
    for (const view of [
      { label: "tuple", listEntries: [[HA_KEY, remote()]] },
      { label: "object", listEntries: [{ name: HA_KEY, ...remote() }] },
    ]) {
      const { ctx, seen } = fakeMcpCtx({ entries: {}, fires: 0, listEntries: view.listEntries });
      const out = await callUrl(ctx);
      assert.equal(out.error, null);
      assert.equal(seen.transformCalls, 1, "leg 1 was attempted first — precedence is chain order, not ctx sniffing");
      assert.equal(seen.cbFires, 0, "the fake withheld every callback fire, mirroring a failed state group");
      assert.equal(out.result, HA_URL, `${view.label} form: the compat scan resolves the url a leg-1 miss could not`);
      assert.equal(seen.count("disposed"), 1, `${view.label} form: dispose awaited even on the fallback path`);
    }
  });
});

describe("H5 never-rejects matrix (AC 8)", () => {
  it("every degenerate collaborator shape resolves exactly null", async () => {
    const cases: Array<[string, any]> = [
      ["ctx = {}", {}],
      [
        "ctx.mcp = {}",
        { mcp: {} },
      ],
      [
        "mcp.transform throws synchronously",
        {
          mcp: {
            transform: () => {
              throw new Error("transform boom");
            },
          },
        },
      ],
      ["transform resolves undefined", fakeMcpCtx({ entries: {}, reg: "none" }).ctx],
      ["list() rejects", fakeMcpCtx({ entries: {}, listRejects: true }).ctx],
      [
        "wrong-named url entries everywhere",
        fakeMcpCtx({
          entries: {},
          listEntries: [["readonly-global-homeassistant", remote("http://readonly.invalid/mcp")], { name: "global-homeassistant", ...remote("http://ro2.invalid/mcp") }],
        }).ctx,
      ],
    ];
    for (const [label, ctx] of cases) {
      const out = await callUrl(ctx);
      assert.equal(out.error, null, `${label}: haMcpUrl never rejects (AC 8 / failure policy)`);
      assert.equal(out.result, null, `${label}: all-miss resolves exactly null (sendHANotify's truthy check and the "no URL found" marker own the rest)`);
    }
  });

  it("resolves null with a planted project jsonc in reach — the retired leg cannot resurrect (AC 5)", async () => {
    // The retired leg parsed <location.directory>/.opencode/opencode.jsonc.
    // Grepping the plugin to 0 hits is review's command; this is its
    // behavioral twin: with both ctx legs missing, a file the OLD code would
    // happily read must still produce null — no fs, no rescue, no throw.
    const dir = mkdtempSync(join(tmpdir(), "ha-mcp-url-fs-probe-"));
    try {
      mkdirSync(join(dir, ".opencode"), { recursive: true });
      writeFileSync(
        join(dir, ".opencode", "opencode.jsonc"),
        `{"mcp":{"servers":{"${HA_KEY}":{"type":"remote","url":"http://retired-leg.invalid/mcp"}}}}`,
      );
      const { ctx } = fakeMcpCtx({ entries: {}, listEntries: [], location: { directory: dir } });
      const out = await callUrl(ctx);
      assert.equal(out.error, null);
      assert.equal(out.result, null, "the config view is a strict superset — file parsing is retired, not a fallback (DECISIONS 2026-10-28)");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe("H6 callback poison isolation (AC 8, Grounding #21b)", () => {
  it("a throwing editor.get never escapes the callback, the compat leg still answers, and a later resolution still registers", async () => {
    // Load-bearing in v2.1.4, not style: a throw past the registered callback
    // fails the plugin's whole state registration group and makes every later
    // transform a silent no-op for the process lifetime. The fake catches at
    // ITS call site, so seen.cbEscapes is exactly "did the throw reach the
    // registration machinery" — it must stay empty.
    const { ctx, seen } = fakeMcpCtx({ getThrows: true, listEntries: [[HA_KEY, remote()]] });
    const out = await callUrl(ctx);
    assert.equal(out.error, null, `a poison attempt must not reject haMcpUrl: ${out.error?.message ?? out.error}`);
    assert.deepEqual(
      seen.cbEscapes.map((e: any) => e.message),
      [],
      "the capture must be guarded INSIDE the callback — an escaped throw marks the registration group failed (Grounding #21b)",
    );
    assert.equal(out.result, HA_URL, "resolution continues past the swallowed poison into the compat leg");
    assert.equal(seen.count("disposed"), 1, "the registration is still disposed even when the callback blew up");

    // Poison did not stick: a second resolution registers and completes too.
    const second = await callUrl(ctx);
    assert.equal(second.error, null);
    assert.equal(second.result, HA_URL, "a later push attempt behaves exactly like the first (no poisoned-group regression)");
    assert.equal(seen.transformCalls, 2, "each call makes its own registration — no cache survives the poison either");

    // And the guard's scope stays inside discovery: the approval seam keeps
    // its C03 contract against this same module instance.
    const timers = new Map<string, any>();
    let scheduled = 0;
    const deps = {
      timers,
      pendingMs: 15000,
      schedule: (_fn: any, _ms: number) => {
        scheduled++;
        return { id: scheduled };
      },
      cancel: (_handle: any) => {},
      allowPush: (_key: string) => true,
      getSession: async (_sessionID: string) => ({ id: "ses_poison", agent: "agent-coord" }),
      notify: async (_title: string, _message: string) => {},
    };
    let permError: any = null;
    try {
      await seam("handlePermission")(deps, { type: "permission.asked", data: { id: "per_poison", sessionID: "ses_poison" } });
    } catch (err) {
      permError = err;
    }
    assert.equal(permError, null, "handlePermission must still resolve after the poison attempt — the guard lives in the callback, not in shared state");
    assert.equal(scheduled, 1, "and still arms exactly one pending timer per ask (C03 contract intact)");
  });
});

describe("H7 registration robustness (AC 8)", () => {
  it("returns the captured url when the Registration carries no dispose", async () => {
    const { ctx, seen } = fakeMcpCtx({ entries: { [HA_KEY]: remote() }, reg: "bare" });
    const out = await callUrl(ctx);
    assert.equal(out.error, null, `a missing dispose must not throw: ${out.error?.message ?? out.error}`);
    assert.equal(out.result, HA_URL, "the url answer stands even when the Registration is malformed");
    assert.equal(seen.listCalls, 0, "still short-circuited — dispose-shape tolerance does not restart leg 2");
  });

  it("returns the captured url when dispose rejects — the rejection is swallowed", async () => {
    // The finally awaits dispose inside its own guard; an unhandled rejection
    // here would surface against the test process itself (same mechanism the
    // permission file's D8 relies on). No stderr requirement (chunks/C04.md H7).
    const { ctx } = fakeMcpCtx({ entries: { [HA_KEY]: remote() }, disposeRejects: true });
    const out = await callUrl(ctx);
    assert.equal(out.error, null, `a rejecting dispose must not reject haMcpUrl: ${out.error?.message ?? out.error}`);
    assert.equal(out.result, HA_URL, "dispose failure cannot undo a completed capture");
    // One more turn past the dispose timer's rejection point: a swallowed-on-paper
    // but unhandled rejection surfaces against the process only after it fires.
    await tick();
  });
});

describe("H8 disabled entry still resolves (AC 9)", () => {
  it("answers the url of a config-declared but disabled server", async () => {
    // The plugin speaks raw JSON-RPC straight to the endpoint, bypassing the
    // server's connection state, so a disabled config entry is as reachable as
    // a connected one (chunks/C04.md Task 1 / DECISIONS 2026-10-28).
    const { ctx } = fakeMcpCtx({ entries: { [HA_KEY]: remote(HA_URL, { disabled: true }) } });
    const out = await callUrl(ctx);
    assert.equal(out.error, null);
    assert.equal(out.result, HA_URL, "disabled:true must not filter the entry (AC 9)");
  });
});

describe("H9 no caching — fresh registration per push (AC 8)", () => {
  it("re-reads the config view on the next call after a fleet URL edit", async () => {
    // Pins the no-cache decision (DECISIONS 2026-10-28): a moved URL must take
    // effect on the NEXT push without a restart — memoizing would re-create
    // this incident's silent-failure class.
    const { ctx, seen, entries } = fakeMcpCtx({ entries: { [HA_KEY]: remote(HA_URL) } });
    const first = await callUrl(ctx);
    assert.equal(first.error, null);
    assert.equal(first.result, HA_URL);
    assert.equal(seen.last(), "disposed", "the first call fully closed its registration before returning");

    entries.set(HA_KEY, remote(HA_URL2));
    const second = await callUrl(ctx);
    assert.equal(second.error, null);
    assert.equal(second.result, HA_URL2, "the second call sees the edited url — nothing from call one may be cached");
    assert.equal(seen.transformCalls, 2, "each resolution registers its own transform");
    assert.equal(seen.count("disposed"), 2, "and disposes its own — register/dispose balance across calls");
    assert.equal(seen.listCalls, 0, "both calls short-circuited on config-view hits");
  });
});
