// OpenCode V2 location plugin: lease locks for parallel board-coord loops
// (card #76). One lock file per pipeline lives at the CANONICAL repo root
// under .pipeline/locks/<pipelineKey>.json, so worktree sessions of one repo
// serialize on shared pipelines and parallelize on disjoint ones. A claim is
// all-or-nothing over the card's whole pipeline set (D18): keys are acquired
// with O_EXCL in sorted order — the same order for every claimant is the
// deadlock argument — and the first contention rolls back everything the
// claim already took. Every file of one claim carries the shared identity
// (sessionID + cardId + setId + full pipelineSet) so release, status, the
// C05 reaper and the board/alert legs can correlate the set.
//
// Why disk locks instead of an in-process mutex: one server process loads
// this plugin once per location dir (D27, probed on v2.1.4), so no object in
// memory can serialize claims across worktrees; O_EXCL creates and atomic
// tmp+rename writes are the cross-process primitives.
//
// Pipeline identity is board LABELS (D17): the worker derives the set from
// the card's `Pipeline:` labels (boards skill) and passes it to pipeline_claim
// — this plugin never reads the board. A card with no such label runs on the
// single default pipeline.
//
// Signalling (D28/D29, C01 probe verdicts for the pinned v2.1.4): the docs'
// session-instruction entry API is absent at runtime, so the PRIMARY
// lock-identity channel is the tool responses themselves; the instruction pin
// arms stay capability-gated and light up silently on a future release.
//
// Precedents: .opencode/plugin/question-notify/ and board-context/ — the
// plain `{ id, async setup(ctx) }` default-export object those two ship (the
// docs' wrapper-based authoring example is not the shape this repo ships;
// the core suite pins this one), degrade-never-throw, and store seams taking
// an injected deps env so the suites run offline against tmp dirs.
// Hand-written; rulesync must never generate or delete this file.
//
// Chunk map (cf-76): C03 (this state) = the lock store + the four tools. C04
// grows the heartbeat/lifecycle engine (tool hooks, timers, the parent-walk
// resolveRoot), C05 replaces the env.reapStale hook with the real reaper +
// board/HA legs, C06 adds the tick command and the config loader. The seam
// export surface stays ADDITIVE — later chunks extend this file, never
// reshape what the core suite pins.

import { randomUUID } from "node:crypto";
import fsp from "node:fs/promises";
import { basename, join } from "node:path";

// Single sources for C07's parity greps — each of these literals must occur
// exactly once in this file (core suite K1, A15's python parity reader).
export const LABEL_PREFIX = "Pipeline:";
export const DEFAULT_PIPELINE = "default";
export const TOOL_NAMES = ["pipeline_claim", "pipeline_release", "pipeline_heartbeat", "pipeline_status"];

// The instruction-entry key the claim pins and release removes (D16 lineage).
const PIN_KEY = "pipeline-lock";
// Runtime dir at the canonical root and its members (conventions: DECISIONS
// header — locks/, events.log, meta/lastReap written by C05).
const RUNTIME_DIR = ".pipeline";
const LOCKS_DIR = "locks";
const EVENTS_FILE = "events.log";
// Storage keys live in one flat namespace per plugin id (ctx.storage is
// plugin-id + project-id scoped and shared across worktrees — D26, so the
// claim bookkeeping rebuilds after a server restart from any location).
const CLAIM_KEY_PREFIX = "claim/";

// An O_EXCL create publishes the file name before its body lands; a
// contending reader can briefly see an empty file. Bounded retry so the
// loser's holder report names the real winner instead of null.
const HOLDER_READ_DELAYS_MS = [0, 2, 5, 15, 40];

export function sanitizePipelineKey(name: string): string {
  // Lock files are named after the key, so everything outside
  // [A-Za-z0-9._-] folds to "-" and the 100-char filesystem-safe bound holds;
  // clean names pass through unchanged so the derived label stays readable on
  // the card. Idempotent by construction (no character is ever introduced
  // that a second pass would rewrite).
  const cleaned = String(name ?? "").replace(/[^A-Za-z0-9._-]/g, "-").slice(0, 100);
  return cleaned.length > 0 ? cleaned : DEFAULT_PIPELINE;
}

export function derivePipelineSet(labelNames: string[]): string[] {
  // D17: keep the Pipeline:-prefixed labels, the trimmed remainder is the
  // pipeline name; prefix match is case-sensitive; empty remainder, wrong
  // case, or no labels at all fold to the single default pipeline.
  const kept = (Array.isArray(labelNames) ? labelNames : [])
    .filter((name) => typeof name === "string" && name.startsWith(LABEL_PREFIX))
    .map((name) => name.slice(LABEL_PREFIX.length).trim())
    .filter((name) => name.length > 0);
  const set = [...new Set(kept)];
  return set.length > 0 ? set.sort() : [DEFAULT_PIPELINE];
}

export async function resolveLockRoot(deps: any, startDir: string): Promise<string> {
  // D10 chain: ctx.location.project.canonical (probe-confirmed string path
  // equal to the main checkout root) → git-common-dir derivation from a
  // worktree .git file → the start dir. Pure fs reads through the injected
  // readFile; every miss falls through and the function never throws — a bad
  // guess at the root is worse than the start dir it came from.
  const canonical = typeof deps?.canonical === "string" && deps.canonical ? deps.canonical : null;
  if (canonical) return canonical;
  try {
    if (typeof deps?.readFile === "function" && typeof startDir === "string" && startDir) {
      const raw = String(await deps.readFile(join(startDir, ".git")));
      const gitdir = /^gitdir:\s*(.+?)\s*$/m.exec(raw)?.[1];
      // Only the .git/worktrees/<name> suffix strips; any other gitdir target
      // (plain linked worktrees, submodule layouts) is not a provable common
      // dir and falls through instead of guessing.
      const common = gitdir ? /^(.*)\/\.git\/worktrees\/[^/]+$/.exec(gitdir)?.[1] : null;
      if (common) return common;
    }
  } catch {
    // .git is a directory in a main checkout (or unreadable): the leg missed.
  }
  return typeof startDir === "string" && startDir ? startDir : process.cwd();
}

export function newLockRecord(input: any): any {
  // Handoff B.1 shape, version 1, plus the D18 shared claim identity. Every
  // timestamp is an ISO-8601 UTC string (D25) — epoch-ms in lock files is a
  // contract violation; the age math downstream parses these against env.now.
  const at = new Date(input?.now ?? Date.now()).toISOString();
  const record: any = {
    version: 1,
    pipeline: input?.pipeline,
    cardId: input?.cardId,
    sessionID: input?.sessionID,
    setId: input?.setId,
    pipelineSet: [...(input?.pipelineSet ?? [])].sort(),
    state: "live",
    claimedAt: at,
    heartbeatAt: at,
  };
  if (input?.cardTitle) record.cardTitle = input.cardTitle;
  return record;
}

function storeFs(env: any): any {
  // Tests inject single fs members to exercise failure legs; production rides
  // the promises API (a sync fs call here would block the server event loop).
  return env?.fs ?? fsp;
}

function lockPathOf(env: any, pipelineKey: string): string {
  return join(env.locksDir, `${pipelineKey}.json`);
}

function claimKeyOf(sessionID: string): string {
  return `${CLAIM_KEY_PREFIX}${sessionID}`;
}

function logNote(env: any, line: string): void {
  const text = `[pipeline-locks] ${line}`;
  if (typeof env?.log === "function") env.log(text);
  else console.error(text);
}

export async function writeLockAtomic(env: any, path: string, record: any): Promise<void> {
  // tmp sibling + rename: readers never observe a half-written lock. On a
  // failed tmp write or rename the live file must keep its previous bytes —
  // the tmp is what fails, never the target.
  const fsx = storeFs(env);
  const tmp = `${path}.${randomUUID()}.tmp`;
  try {
    await fsx.writeFile(tmp, JSON.stringify(record, null, 2));
    await fsx.rename(tmp, path);
  } catch (err: any) {
    try {
      await fsx.rm(tmp, { force: true });
    } catch {
      // a tmp that never landed needs no cleanup
    }
    throw err;
  }
  const stamp = new Date(env?.now?.() ?? Date.now());
  try {
    // mtime must move with every rewrite: the reaper's staleness formula is
    // max(heartbeatAt, mtime), so a hand-touched or stale-clock file cannot
    // hide behind an old mtime and a corrupt record cannot fake freshness.
    await fsx.utimes(path, stamp, stamp);
  } catch (err: any) {
    logNote(env, `utimes after atomic write failed for ${basename(path)}: ${String(err?.code ?? err)}`);
  }
}

export async function readLock(env: any, path: string): Promise<any | null> {
  // Parse error or missing → null. A valid JSON object comes back verbatim:
  // unknown keys survive, which is the older-schema tolerance contract the
  // reaper and status legs ride on.
  try {
    const parsed = JSON.parse(await storeFs(env).readFile(path, "utf8"));
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch {
    return null;
  }
}

export async function appendEvent(env: any, obj: any): Promise<void> {
  // JSONL audit. Fire-and-forget semantics: a broken path logs one line and
  // resolves — an audit write must never fail or block the action it records.
  const line = JSON.stringify({ at: new Date(env?.now?.() ?? Date.now()).toISOString(), ...obj }) + "\n";
  try {
    await storeFs(env).writeFile(String(env?.eventsPath), line, { encoding: "utf8", flag: "a" });
  } catch (err: any) {
    logNote(env, `audit append failed: ${String(err?.code ?? err)}`);
  }
}

function normalizePipelineSet(pipelines: any): string[] {
  const keys = (Array.isArray(pipelines) ? pipelines : [])
    .map((name: any) => sanitizePipelineKey(String(name ?? "")))
    .filter((key: string) => key.length > 0);
  const set = [...new Set(keys)];
  return set.length > 0 ? set.sort() : [DEFAULT_PIPELINE];
}

async function readHolder(env: any, path: string): Promise<any | null> {
  for (const delay of HOLDER_READ_DELAYS_MS) {
    if (delay) await new Promise((resolve) => setTimeout(resolve, delay));
    const rec = await readLock(env, path);
    if (rec) return rec;
  }
  return null;
}

// Acquisition and rollback in one seam: walking the sorted keys is the
// deadlock argument between overlapping claims, and the first EEXIST (or any
// other fs failure) unlinks every file this pass already took before
// returning — the walk order and its undo can never drift apart (D18).
async function acquireSetWithRollback(env: any, claim: any): Promise<{ ok: true } | { ok: false; reason: string; pipeline: string; holder?: any; error?: string }> {
  const fsx = storeFs(env);
  const taken: string[] = [];
  for (const pipeline of claim.pipelineSet) {
    const path = lockPathOf(env, pipeline);
    try {
      const handle = await fsx.open(path, "wx");
      try {
        await handle.writeFile(JSON.stringify(newLockRecord({ ...claim, pipeline, now: env?.now?.() ?? Date.now() }), null, 2));
      } finally {
        await handle.close();
      }
      taken.push(path);
    } catch (err: any) {
      for (const p of taken) {
        try {
          await fsx.rm(p, { force: true });
        } catch {
          // best-effort: a file this pass took that cannot be removed reads
          // to the reaper as any other orphan and ages out
        }
      }
      if (err?.code !== "EEXIST") {
        return { ok: false, reason: "store_error", pipeline, error: String(err?.code ?? err) };
      }
      const holder = await readHolder(env, path);
      if (taken.length > 0) {
        await appendEvent(env, { ev: "claim_rollback", ...claim, rolledBack: taken.map((p) => basename(p, ".json")), pipeline });
      }
      return { ok: false, reason: "locked", pipeline, holder };
    }
  }
  return { ok: true };
}

export async function claimLockSet(env: any, input: any): Promise<any> {
  const sessionID = String(input?.sessionID ?? "") || "unknown";
  const set = normalizePipelineSet(input?.pipelines);
  const cardId = input?.cardId;

  try {
    // Reap-before-claim: the hook is a no-op stub until C05 lands; awaiting
    // it here keeps the claim-time ordering contract stable across chunks.
    if (typeof env?.reapStale === "function") await env.reapStale({ trigger: "claim" });
  } catch (err: any) {
    logNote(env, `claim-time reap hook failed, continuing: ${String(err?.code ?? err?.message ?? err)}`);
  }

  // One card per iteration: refuse while this root session already holds a
  // claim. Checked against the storage bookkeeping too, because a server
  // restart empties the in-process cache while the disk locks persist.
  const held = await findClaim(env, sessionID);
  if (held) return { ok: false, reason: "already_held", held };

  await storeFs(env).mkdir(env.locksDir, { recursive: true });

  const setId = randomUUID();
  const claim = { cardId, sessionID, setId, cardTitle: input?.cardTitle, pipelineSet: set };
  const acquisition = await acquireSetWithRollback(env, claim);
  if (!acquisition.ok) {
    env?.claims?.delete(sessionID);
    return acquisition;
  }

  const entry = { setId, cardId, pipelineSet: set, sessionID };
  env?.claims?.set(sessionID, entry);
  try {
    // ctx.storage is durable and shared across worktree locations (D26) —
    // the restart-resume rebuild C04 relies on starts here. A storage miss
    // never voids the disk locks, which remain the truth.
    if (env?.storage) await env.storage.set(claimKeyOf(sessionID), entry);
  } catch (err: any) {
    logNote(env, `claim bookkeeping persist failed (cache + disk locks still hold): ${String(err?.code ?? err)}`);
  }
  try {
    // Capability-gated per D28: env.pin is null on v2.1.4 (the tool response
    // below is the primary identity channel) and the pin lights up silently
    // when a newer server exposes the instructions entry API.
    if (env?.pin) {
      await env.pin.put(sessionID, PIN_KEY, `PIPELINE LOCK card=${String(cardId ?? "")} pipelines=${set.join(",")} setId=${setId} — release with pipeline_release when the card moves to Review.`);
    }
  } catch (err: any) {
    logNote(env, `instruction pin failed (tool-response channel still authoritative): ${String(err?.code ?? err)}`);
  }
  await appendEvent(env, { ev: "claim", setId, cardId, sessionID, pipelineSet: set });
  return { ok: true, setId, lockPaths: set.map((pipeline) => lockPathOf(env, pipeline)) };
}

async function findClaim(env: any, sessionID: string): Promise<any | null> {
  const cached = env?.claims?.get(sessionID) ?? null;
  if (cached) return cached;
  if (env?.storage) {
    try {
      return (await env.storage.get(claimKeyOf(sessionID), null)) ?? null;
    } catch {
      return null;
    }
  }
  return null;
}

export async function releaseLockSet(env: any, input: any): Promise<any> {
  const sessionID = String(input?.sessionID ?? "");
  const entry = await findClaim(env, sessionID);
  // Idempotent by design: a release for a session holding nothing succeeds
  // quietly, so C04/C05 teardown legs can fire it without racing a claim.
  if (!entry) return { ok: true, released: [] };
  const set: string[] = Array.isArray(entry.pipelineSet) ? entry.pipelineSet : [];

  // Owner-check the WHOLE set first — a release that deletes half of a set
  // whose other member was stolen would free one pipeline under a thief.
  const records = new Map<string, any>();
  for (const pipeline of set) {
    const rec = await readLock(env, lockPathOf(env, pipeline));
    if (rec && String(rec.sessionID) !== sessionID) {
      return { ok: false, reason: "not_owner", pipeline };
    }
    records.set(pipeline, rec);
  }

  const fsx = storeFs(env);
  for (const pipeline of set) {
    try {
      await fsx.rm(lockPathOf(env, pipeline), { force: true });
    } catch (err: any) {
      logNote(env, `release could not remove ${pipeline}: ${String(err?.code ?? err)}`);
    }
  }
  await appendEvent(env, {
    ev: "release",
    outcome: input?.outcome,
    setId: entry.setId,
    cardId: entry.cardId,
    sessionID,
    pipelineSet: set,
  });
  env?.claims?.delete(sessionID);
  try {
    if (env?.storage) await env.storage.remove(claimKeyOf(sessionID));
  } catch (err: any) {
    logNote(env, `release storage cleanup failed: ${String(err?.code ?? err)}`);
  }
  try {
    if (env?.pin) await env.pin.remove(sessionID, PIN_KEY);
  } catch (err: any) {
    logNote(env, `release pin cleanup failed: ${String(err?.code ?? err)}`);
  }
  return { ok: true, released: set, setId: entry.setId };
}

export async function lockStatus(env: any, input: any = {}): Promise<any> {
  // Every lock file, grouped by setId/card so a multi-pipeline claim reads as
  // ONE unit (D18). lastReap is a C05 product — absent until then.
  const fsx = storeFs(env);
  let names: string[] = [];
  try {
    names = (await fsx.readdir(env.locksDir)).filter((name: string) => name.endsWith(".json")).sort();
  } catch {
    // no locks dir yet = nothing held
  }

  const groups = new Map<string, any>();
  for (const name of names) {
    const rec = await readLock(env, join(env.locksDir, name));
    if (!rec) continue;
    const key = String(rec.setId ?? `${String(rec.cardId)}|${String(rec.sessionID)}`);
    let group = groups.get(key);
    if (!group) {
      const stamp = Date.parse(String(rec.heartbeatAt ?? rec.claimedAt ?? ""));
      group = {
        setId: rec.setId ?? null,
        cardId: rec.cardId,
        holder: rec.sessionID,
        pipelineSet: Array.isArray(rec.pipelineSet) ? [...rec.pipelineSet] : [],
        pipelines: [] as string[],
        state: String(rec.state ?? "live"),
        ageMs: Number.isFinite(stamp) ? Math.max(0, (env?.now?.() ?? Date.now()) - stamp) : 0,
      };
      groups.set(key, group);
    }
    if (rec.pipeline && !group.pipelines.includes(rec.pipeline)) group.pipelines.push(rec.pipeline);
  }
  const groupList = [...groups.values()];
  for (const group of groupList) {
    // A legacy record without pipelineSet still reads complete through its
    // observed members; the union keeps the set view honest either way.
    group.pipelineSet = [...new Set([...group.pipelineSet, ...group.pipelines])].sort();
  }

  let session: any = null;
  if (input?.sessionID) {
    const entry = await findClaim(env, String(input.sessionID));
    const group = groupList.find((g) => String(g.holder) === String(input.sessionID)) ?? null;
    session = entry && group ? { ...group, ...entry } : entry ?? group;
  }
  return { groups: groupList, session: session ?? null, lastReap: await readLock(env, env?.metaPath) };
}

// The tool response IS the lock-identity channel (D28). `content` is the
// field the 2.1.4 host renders for the agent — the probe's { content: ... }
// return is the proven shape, and a raw-object return surfaced through Code
// Mode answers "undefined" (live-observed 2026-10-29) — so the full result
// rides the content JSON; the same fields are spread first-class for direct
// (offline-suite) readers. Executor failures answer structured too: a throw
// would surface as an opaque host error instead of lock state.
async function respond(fn: () => Promise<any>): Promise<any> {
  let result: any;
  try {
    result = await fn();
  } catch (err: any) {
    result = { ok: false, reason: "error", error: String(err?.code ?? err?.message ?? err) };
  }
  return { ...result, content: JSON.stringify(result) };
}

async function toolClaim(env: any, args: any, context: any): Promise<any> {
  const cardId = typeof args?.cardId === "string" && args.cardId ? args.cardId : null;
  if (!cardId) return { ok: false, reason: "invalid_input", error: "cardId is required" };
  const root = await resolveRoot(env, context?.sessionID);
  return await claimLockSet(env, { cardId, pipelines: args?.pipelines, cardTitle: args?.cardTitle, sessionID: root });
}

async function toolRelease(env: any, args: any, context: any): Promise<any> {
  const outcome = args?.outcome === "done" || args?.outcome === "abandoned" ? args.outcome : null;
  if (!outcome) return { ok: false, reason: "invalid_input", error: "outcome must be done or abandoned" };
  const root = await resolveRoot(env, context?.sessionID);
  return await releaseLockSet(env, { sessionID: root, outcome });
}

async function toolHeartbeat(env: any, _args: any, context: any): Promise<any> {
  const root = await resolveRoot(env, context?.sessionID);
  const entry = await findClaim(env, root);
  if (!entry) return { ok: false, reason: "no_claim", sessionID: root };
  const set: string[] = Array.isArray(entry.pipelineSet) ? entry.pipelineSet : [];
  const beaten: string[] = [];
  const missing: string[] = [];
  for (const pipeline of set) {
    const path = lockPathOf(env, pipeline);
    const rec = await readLock(env, path);
    if (!rec || String(rec.sessionID) !== root) {
      missing.push(pipeline);
      continue;
    }
    await writeLockAtomic(env, path, { ...rec, heartbeatAt: new Date(env?.now?.() ?? Date.now()).toISOString() });
    beaten.push(pipeline);
  }
  // The set-wide lock-lost reaction (delete survivors, stop the claim) is
  // C04's engine; the response names it so the worker can stop.
  return { ok: missing.length === 0, reason: missing.length > 0 ? "lock_lost" : undefined, setId: entry.setId, cardId: entry.cardId, beaten, missing };
}

async function toolStatus(env: any, _args: any, context: any): Promise<any> {
  return await lockStatus(env, { sessionID: await resolveRoot(env, context?.sessionID) });
}

function buildToolSpecs(env: any): any[] {
  const definitions = [
    {
      callAs: "tools.pipeline_claim",
      blurb: "Acquire the lease-lock set for a board card, all-or-nothing over every pipeline the card's labels name: every pipeline is taken or none is (a contended claim rolls back and names the holder). cardId required; pipelines is the derived Pipeline:-label set (omit it or pass an empty list for the default pipeline).",
      schema: {
        type: "object",
        properties: {
          cardId: { type: "string", description: "WeKan card id the claim is held for" },
          pipelines: { type: "array", items: { type: "string" }, description: "Pipeline names derived from the card's Pipeline: labels (D17); empty or omitted means the single default pipeline" },
          cardTitle: { type: "string", description: "Card title, recorded in the lock for status and alert text" },
        },
        required: ["cardId"],
        additionalProperties: false,
      },
      execute: (args: any, context: any) => respond(() => toolClaim(env, args, context)),
    },
    {
      callAs: "tools.pipeline_release",
      blurb: "Release the whole lock set held by this session's root. outcome is done (card handed to Review) or abandoned; a member owned by another session refuses the release and touches nothing.",
      schema: {
        type: "object",
        properties: {
          outcome: { type: "string", enum: ["done", "abandoned"], description: "done when the card reached Review (D6), abandoned when the run gives up on it" },
        },
        required: ["outcome"],
        additionalProperties: false,
      },
      execute: (args: any, context: any) => respond(() => toolRelease(env, args, context)),
    },
    {
      callAs: "tools.pipeline_heartbeat",
      blurb: "Force-beat every lock file of this session's root claim (rewrites heartbeatAt and touches mtime). Takes no arguments.",
      schema: { type: "object", properties: {}, additionalProperties: false },
      execute: (args: any, context: any) => respond(() => toolHeartbeat(env, args, context)),
    },
    {
      callAs: "tools.pipeline_status",
      blurb: "Read the lock state: every held set grouped per claim with age, holder and pipeline set, plus this session's own claim. Takes no arguments; the answer is the primary lock-identity channel (D28).",
      schema: { type: "object", properties: {}, additionalProperties: false },
      execute: (args: any, context: any) => respond(() => toolStatus(env, args, context)),
    },
  ];

  // Visible name rides flat (name = the full pipeline_* id, no namespace
  // option): adding options.namespace on top of an already-prefixed name
  // joins a second prefix on the real registry (probe: the effective name is
  // namespace_name), and the cf-76 core contract pins the full visible name
  // on the spec — the flat shape lands the exact ids DECISIONS D29 requires,
  // live-restamped 2026-10-29 when this plugin loaded into a v2.1.4 session
  // and Code Mode listed the tools under exactly these names.
  return TOOL_NAMES.map((name, i) => ({
    name,
    description: `${definitions[i].blurb} On OpenCode v2.1.4 plugin tools are reachable ONLY through Code Mode: call ${definitions[i].callAs} from the execute tool (probe fact, D29) — never as a native provider tool.`,
    inputSchema: definitions[i].schema,
    // The docs' add() example names the schema field `input` while the C03
    // seam contract pins `inputSchema`; both keys point at one object, so
    // the registry read and the pinned contract cannot drift apart.
    input: definitions[i].schema,
    execute: definitions[i].execute,
  }));
}

async function resolveRoot(env: any, sessionID: any): Promise<string> {
  // Minimal for C03: a session IS its own root unless the claim bookkeeping
  // says otherwise. C04 grows this into the deferred parent-walk over
  // session reads with a negative cache — the name stays stable across.
  const id = String(sessionID ?? "");
  if (!id) return "unknown";
  const entry = await findClaim(env, id);
  return String(entry?.sessionID ?? id);
}

function bindStorage(ctx: any): any {
  // ctx.storage probes confirmed on 2.1.4: positional set(key, value),
  // get(key) answering undefined for absent keys. Adapter normalizes to the
  // (key, default) seam shape the store uses; adapter failure degrades to
  // the cache + disk-locks truth, never to a lost claim.
  const store = ctx?.storage;
  if (typeof store?.set !== "function" || typeof store?.get !== "function" || typeof store?.remove !== "function") return null;
  return {
    get: async (key: string, def: any) => {
      try {
        const value = await store.get(key);
        return value ?? def;
      } catch {
        return def;
      }
    },
    set: async (key: string, value: any) => store.set(key, value),
    remove: async (key: string) => store.remove(key),
  };
}

function bindPin(ctx: any): any {
  // D28 capability gate: the instructions entry API is in the current docs
  // but absent from the pinned v2.1.4 runtime — null here means the pin arms
  // no-op silently and the tool responses carry the identity instead.
  const entry = ctx?.session?.instructions?.entry;
  if (typeof entry?.put !== "function" || typeof entry?.remove !== "function") return null;
  return {
    put: async (sessionID: string, key: string, value: string) => entry.put({ sessionID, key, value }),
    remove: async (sessionID: string, key: string) => entry.remove({ sessionID, key }),
  };
}

export default {
  id: "local.pipeline-locks",
  async setup(ctx: any): Promise<() => void> {
    // Aborting this signal is the cancellation channel for any background
    // work this location instance runs; the host calls the returned cleanup
    // unconditionally, so it is returned even on the degrade path (AC9).
    const shutdown = new AbortController();
    const log = (line: string) => console.error(`[pipeline-locks] ${line}`);
    try {
      // D31: the whole body sits inside try/catch — a sync throw in setup
      // wedged an ephemeral location load in the C01 probe, and a plugin
      // load failure would poison the server's plugin group.
      const startDir = typeof ctx?.location?.directory === "string" ? ctx.location.directory : process.cwd();
      const root = await resolveLockRoot(
        {
          canonical: typeof ctx?.location?.project?.canonical === "string" ? ctx.location.project.canonical : null,
          readFile: async (path: string) => fsp.readFile(path, "utf8"),
        },
        startDir,
      );
      const env = {
        runtimeDir: join(root, RUNTIME_DIR),
        locksDir: join(root, RUNTIME_DIR, LOCKS_DIR),
        eventsPath: join(root, RUNTIME_DIR, EVENTS_FILE),
        metaPath: join(root, RUNTIME_DIR, "meta", "lastReap"),
        now: () => Date.now(),
        claims: new Map<string, any>(),
        storage: bindStorage(ctx),
        pin: bindPin(ctx),
        // C05 replaces this hook with the reaper; the claim awaits it now so
        // the ordering contract does not change when it does.
        reapStale: async () => ({}),
        signal: shutdown.signal,
      };
      if (typeof ctx?.tool?.transform === "function") {
        await ctx.tool.transform((editor: any) => {
          for (const spec of buildToolSpecs(env)) editor.add(spec);
        });
      } else {
        log("degraded: no ctx.tool.transform — lock tools not registered, store seams still load");
      }
    } catch (err: any) {
      log(`setup degraded: ${String(err?.message ?? err)}`);
    }
    return () => shutdown.abort();
  },
};
