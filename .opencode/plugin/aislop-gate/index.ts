// OpenCode V2 local plugin: after edit/write tools, run aislop on changed files
// and append findings to the tool result the model sees.
// Hand-written — rulesync must never generate or delete this file (rulesync's
// hooks feature is OFF in rulesync.jsonc; no other writer exists).
//
// Design notes:
// - Plain default export (not Plugin.define) so there is no runtime
//   @opencode/plugin resolution dependency.
// - node:child_process (V2 no longer injects Bun's $).
// - `--changes` with human output: the aislop JSON schema is not depended on;
//   the readable report is forwarded, truncated. Swap in `--json` and parse
//   after checking the real shape with `npx aislop scan --changes --json | head`.
// - Debounce + dedupe stop multi-file edits from spamming the context.
// - Pinned CLI version via npx --yes (repo has no package.json; the CI gate
//   pins the same version). First run pays the download; npx caches it.
//
// Unverified at write time (watch and adjust):
// - V2 tool IDs for patch-style edits (patch/apply_patch/multiedit). To check:
//   temporarily add console.error(event.tool, Object.keys(event.input ?? {})).
// - Whether result.content or result.output is the field the model sees;
//   appendText writes whichever exists.
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);
const EDIT_TOOLS = new Set(["edit", "write", "multiedit", "patch", "apply_patch"]);
const CODE = /\.(m?[jt]sx?|cjs|py|go|rs|rb|php|cs|c|cc|cpp|h|hpp)$/i;
const DEBOUNCE_MS = 1500;
const MAX_CHARS = 4000;
const AISLOP_VERSION = "0.18.1";

function appendText(result: any, text: string) {
  if (!result) return;
  if (typeof result.content === "string") result.content += "\n\n" + text;
  else if (Array.isArray(result.content)) result.content.push({ type: "text", text });
  else if (typeof result.output === "string") result.output += "\n\n" + text;
  else result.content = text;
}

export default {
  id: "local.aislop-gate",
  async setup(ctx: any) {
    const cwd: string = ctx.location.directory;
    let lastRun = 0;
    let lastReport = "";

    await ctx.tool.hook("execute.after", async (event: any) => {
      if (event.status !== "completed" || !EDIT_TOOLS.has(event.tool)) return;
      const file = event.input?.filePath ?? event.input?.path;
      if (typeof file === "string" && !CODE.test(file)) return;

      const now = Date.now();
      if (now - lastRun < DEBOUNCE_MS) return;
      lastRun = now;

      let out = "";
      try {
        ({ stdout: out } = await run(
          "npx",
          ["--yes", `aislop@${AISLOP_VERSION}`, "scan", "--changes"],
          { cwd, timeout: 120_000, maxBuffer: 8 * 1024 * 1024 },
        ));
      } catch (err: any) {
        out = err?.stdout ?? ""; // non-zero exit can still mean "findings printed"
        if (!out) return; // aislop missing or crashed: stay silent, never break the edit
      }
      out = out.trim();
      if (!out || out === lastReport) return;
      lastReport = out;
      appendText(
        event.result,
        "aislop findings (changed files). Fix before finishing:\n" + out.slice(0, MAX_CHARS),
      );
    });
  },
};
