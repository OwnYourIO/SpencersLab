// C01 acceptance checks (2026/2026-11-bug-pipeline-locks-tick-pin): the aislop
// CLI version pin resolves to ONE value across its two hand-managed homes — the
// gate plugin constant (AISLOP_VERSION, .opencode/plugin/aislop-gate/index.ts)
// and the CI workflow pins (aislop@<v>, .github/workflows/aislop.yaml) — and
// both invocations stay in the explicit pinned npx form. Covers chunks/C01.md
// Tests P1-P3 and AC 3 (T-3 pin bumps) / AC 4 (the guard genuinely guards).
// "Bump both together" is prose in the workflow header; P1 is what turns it
// into a gate (DECISIONS 2026-11-02).
//
// Red before C01 dev: P2 only — both files still pin 0.18.1 while the decided
// value is 0.20.0. P1 and P3 pass on today's bytes BY DESIGN: parity and pin
// FORM already hold; only the decided VALUE moved, and a guard that was red
// before the drift it prevents would be noise, not a gate.
//
// The decided version is hardcoded in exactly one place beyond the two files:
// DECIDED_PIN below (P2's duty). Asserting it inside P1 too would make parity
// checks redundant and recreate the multi-home drift this ticket exists to
// kill — the value's authority stays the two pinned files; P2 is the
// bump-together tripwire, so a pin move means one change touching three places.
//
// Run from the repo root: node --test tests/opencode/aislop-pin-parity.test.ts
// (Node v26 type-strips; reads file bytes only — no import of the plugin, no
// deps, no network, no writes).

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const GATE = ".opencode/plugin/aislop-gate/index.ts";
const WORKFLOW = ".github/workflows/aislop.yaml";
const DECIDED_PIN = "0.20.0";
const SENTINEL = "10.10.10"; // bump probe for the synthetic-bytes guard proof

function extractPins(gateSrc: string, wfSrc: string): { gate: string[]; wf: string[] } {
  const gate = [...gateSrc.matchAll(/AISLOP_VERSION\s*=\s*"(\d+\.\d+\.\d+)"/g)].map((m) => m[1]);
  // Comments included: a version example in a comment is an invocation
  // instruction for whoever copies it (the workflow header's local-scan line).
  const wf = [...wfSrc.matchAll(/aislop@(\d+\.\d+\.\d+)/g)].map((m) => m[1]);
  return { gate, wf };
}

function allPins(gateSrc: string, wfSrc: string): string[] {
  const { gate, wf } = extractPins(gateSrc, wfSrc);
  return [...gate, ...wf];
}

function aislopRunLine(wfSrc: string): string {
  const lines = wfSrc.split(/\r?\n/).filter((l) => /^\s*run:\s*\S/.test(l) && l.includes("aislop"));
  assert.equal(lines.length, 1, `expected exactly one aislop run: line in ${WORKFLOW}, saw ${lines.length} — the gate step shape moved, update the probe`);
  return lines[0].trim();
}

const REAL_GATE = readFileSync(GATE, "utf8");
const REAL_WORKFLOW = readFileSync(WORKFLOW, "utf8");

describe("P1 gate and CI pins agree (AC3/T-3, AC4)", () => {
  it("every aislop pin in the two hand-managed files is one and the same version", () => {
    const { gate, wf } = extractPins(REAL_GATE, REAL_WORKFLOW);
    assert.equal(gate.length, 1, `${GATE} must declare AISLOP_VERSION exactly once, saw ${gate.length} — a duplicate assignment makes the read ambiguous`);
    assert.ok(wf.length >= 1, `${WORKFLOW} carries no aislop@<version> pin at all — CI floated off the pin form (P3 pins the run: line)`);
    const versions = new Set(allPins(REAL_GATE, REAL_WORKFLOW));
    assert.equal(versions.size, 1, `aislop pins drifted: ${JSON.stringify({ gate, wf })} — the gate plugin and the CI workflow bump together ("bump both together", ${WORKFLOW} header)`);
    assert.match([...versions][0], /^\d+\.\d+\.\d+$/, "the shared pin is a plain semver triple");
  });

  it("the parity duty fires on a one-sided bump and survives a floater (synthetic bytes)", () => {
    // The REAL files are never mutated here; the guard is proven on modified
    // copies so AC4's "temporarily reverting either pin makes it fail" holds
    // for any future bump, not just this ticket's.
    const gateBumped = REAL_GATE.replace(/AISLOP_VERSION\s*=\s*"\d+\.\d+\.\d+"/, `AISLOP_VERSION = "${SENTINEL}"`);
    assert.notEqual(gateBumped, REAL_GATE, "harness: the bump probe must match the gate constant");
    assert.ok(new Set(allPins(gateBumped, REAL_WORKFLOW)).size > 1, "a gate-only bump must break parity");

    const wfBumped = REAL_WORKFLOW.replace(/aislop@\d+\.\d+\.\d+/g, `aislop@${SENTINEL}`);
    assert.notEqual(wfBumped, REAL_WORKFLOW, "harness: the bump probe must match the workflow pins");
    assert.ok(new Set(allPins(REAL_GATE, wfBumped)).size > 1, "a workflow-only bump must break parity");

    const wfFloated = REAL_WORKFLOW.replace(/ aislop@\d+\.\d+\.\d+/g, " aislop");
    assert.ok(extractPins(REAL_GATE, wfFloated).wf.length === 0, "harness: the float probe must strip every workflow pin");
    assert.equal(extractPins(REAL_GATE, wfFloated).wf.length, 0, "a fully floated workflow must trip P1's no-pin assert");
    assert.doesNotMatch(aislopRunLine(wfFloated), /^run: npx --yes aislop@\d+\.\d+\.\d+ ci --changes/, "a floated run: line must trip P3's form assert");
  });
});

describe("P2 the decided pin is 0.20.0 (AC3/T-3; DECISIONS 2026-11-02)", () => {
  it("the single parity value equals the owner-decided version", () => {
    const versions = new Set(allPins(REAL_GATE, REAL_WORKFLOW));
    assert.equal(versions.size, 1, `parity must hold before the value check: ${JSON.stringify([...versions])}`);
    assert.equal(
      [...versions][0],
      DECIDED_PIN,
      `aislop pins resolve ${[...versions][0]}, not the decided ${DECIDED_PIN} — moving the pin is one change to three places: AISLOP_VERSION in the gate, every aislop@<v> in the workflow, and DECIDED_PIN here. The pins exist so the gate, the CI job, and the agents' ad-hoc final-state npx scans run one and the same scorer — ad-hoc resolves the registry latest, so pin-vs-registry drift silently changes findings (this ticket's plan Grounding, ITEM 2)`,
    );
  });
});

describe("P3 pinned invocation forms survive (AC4b/c)", () => {
  it("the gate calls npx --yes with the AISLOP_VERSION template, not a floating or inlined version", () => {
    assert.match(REAL_GATE, /"--yes",\s*`aislop@\$\{AISLOP_VERSION\}`/, `${GATE} must invoke ["--yes", \`aislop@\${AISLOP_VERSION}\`, …] — a literal there would leave P1's constant check blind to what actually runs`);
  });

  it("the workflow run: line is the pinned `npx --yes aislop@<v> ci --changes` form", () => {
    assert.match(
      aislopRunLine(REAL_WORKFLOW),
      /^run: npx --yes aislop@\d+\.\d+\.\d+ ci --changes/,
      `the CI gate must run the pinned CLI — floating npx aislop is forbidden in CI (.rulesync/skills/aislop SKILL.md: registry latest moves the scorer between runs)`,
    );
  });
});
