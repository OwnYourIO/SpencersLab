#!/usr/bin/env bash
# Standalone-agent family surface suite (2026/2026-10-cf-58-feat-standalone-
# agent-merge, C04).
#
# Pins chunks/C04.md: the new standalone `dev` family (dev-local / dev-pr /
# plain dev alias) + hidden `role-dev` skill, the planner/debug/code fold-ins
# in their role skills, debug's git posture, the card's git-write matrix
# audit, and the permissions.md Standalone-agents subsection.
#
# AC trace: S1[AC1-files] S2[AC1-alias-parity] S3[AC1-block-equality]
# S4[AC2-role-dev] S5[AC3-planner/code/debug] S6[AC4-git-audit]
# S7[AC5-code/byte-unchanged/no-variants] S8[AC4+matrix-rows]
# S9[overview dev-family entry] S10[AC5-mirrors/regen].
#
# Red posture: S1-S4, S6 (dev-family arms), S8, S9, S10 are red before C04
# (dev*.md and role-dev absent — every red names the missing file/contract).
# S3's pinned-copy arm reconstructs the implementer block from the ticket
# base's agent-dev.md plus the C02 Tasks' git-row lists, so C04 can land
# before C02 (wave-1 order) and still assert "same block by construction";
# the dynamic compare against agent-dev-{local,pr}.md engages once C02 lands
# and must hold forever after — re-pinned by cf-76 C02 (D7) as the DELTA-AWARE
# form: the pipeline pair may differ from the standalone trio ONLY on the git
# add/commit effects (deny vs allow), everything else stays parsed-equal. S6's no-git-write roster + S7 are HOLD checks
# (card: "verified already true, pinned by a test") — green now, and they
# fail loudly if C04 grants writes where the card forbids them.
#
# Historical operational bases of the sibling suites (arm A=081b57889,
# arm B / integrated 124fc2ae8, f11bfcb85, 916044893) stay documented there;
# this suite's base is the ticket's own: TB=$(git merge-base main HEAD), the
# pre-cf-58 tree — byte-unchanged pins and the pinned-block reconstruction
# read from it, so no base drift can soften them.
#
# Offline-deterministic: pure tree/parse checks + the rulesync ladder arm
# (skip-warn per c7/t14 precedent). No server, no session, no MCP.
#
# Usage:
#   bash tests/standalone-agents/surface.sh              # S1..S10
#   bash tests/standalone-agents/surface.sh S3 S6        # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

TB="${CF58_BASE:-$(git merge-base main HEAD 2>/dev/null || git rev-parse HEAD)}"
git rev-parse --verify "${TB}^{commit}" >/dev/null 2>&1 \
  || { echo "harness: ticket base '$TB' is not a commit in this repo" >&2; exit 2; }

DEV=".rulesync/subagents/dev.md"
DEV_LOCAL=".rulesync/subagents/dev-local.md"
DEV_PR=".rulesync/subagents/dev-pr.md"
DEBUG_SRC=".rulesync/subagents/debug.md"
DEV_GEN=".opencode/agents/dev.md"
DEV_LOCAL_GEN=".opencode/agents/dev-local.md"
DEV_PR_GEN=".opencode/agents/dev-pr.md"
RDEV_SRC=".rulesync/skills/role-dev/SKILL.md"
RDEV_GEN=".opencode/skills/role-dev/SKILL.md"
RP_SRC=".rulesync/skills/role-planner/SKILL.md";  RP_GEN=".opencode/skills/role-planner/SKILL.md"
RC_SRC=".rulesync/skills/role-code/SKILL.md";     RC_GEN=".opencode/skills/role-code/SKILL.md"
RD_SRC=".rulesync/skills/role-debug/SKILL.md";    RD_GEN=".opencode/skills/role-debug/SKILL.md"
PERM_SRC=".rulesync/skills/agents-sync/references/permissions.md"
PERM_GEN=".opencode/skills/agents-sync/references/permissions.md"
ADEV_LOCAL=".rulesync/subagents/agent-dev-local.md"
ADEV_PR=".rulesync/subagents/agent-dev-pr.md"
RULES_SRC=".rulesync/rules/overview.md"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s (artifacts kept at %s)\n' "$1" "$TMP" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

TMP=$(mktemp -d /tmp/opencode/standalone-agents-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 10); do WANT["s$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^s([1-9]|10)$ ]] || fail "unknown check id '$a' (expected S1..S10)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- shared helpers -------------------------------------------------------------

cat >"$TMP/eq.py" <<'PY'
# Parsed permission-list equality (dict+order) between two agent files — the
# same comparison convention as tests/agent-perms/surface.sh (rulesync
# re-serializes the mirror; last-match-wins makes ORDER load-bearing, so
# order is part of the equality).
import re, sys, yaml
a, b = sys.argv[1], sys.argv[2]
def perms(p):
    m = re.match(r"^---\n(.*?)\n---\n", open(p).read(), re.S)
    assert m, f"{p}: no YAML frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    return (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
pa, pb = perms(a), perms(b)
if pa != pb:
    da = next((i for i, (x, y) in enumerate(zip(pa, pb)) if x != y), min(len(pa), len(pb)))
    print(f"lists differ at index {da}: {a}[{da}]={pa[da] if da < len(pa) else None} vs {b}[{da}]={pb[da] if da < len(pb) else None} (lengths {len(pa)}/{len(pb)})")
    sys.exit(1)
PY

cat >"$TMP/blockdiff.py" <<'PY'
# S3 pinned-copy arm: dev's local/pr blocks must equal the ticket base's
# agent-dev.md list (the block C02 says both variants copy verbatim, ORDER
# intact) PLUS the variant's git rows in the C02 Tasks' declared order,
# placed after the last existing git READ row (C02: "after the existing git
# reads"). Insertion offset between the reads and the MCP rows stays dev's
# layout choice; everything else is pinned — and nothing else may appear.
import re, sys, yaml
base_file, target, variant = sys.argv[1], sys.argv[2], sys.argv[3]
def perms(p):
    m = re.match(r"^---\n(.*?)\n---\n", open(p).read(), re.S)
    assert m, f"{p}: no YAML frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    return (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
def sh(res, eff): return {"action": "shell", "resource": res, "effect": eff}
# Isolation RE-PIN (2026-10-27, bug-coord-opencode-perms): every implementer
# block — standalone dev trio and pipeline agent-dev pair alike (the dynamic
# S3 arm pins the lists equal beyond the cf-76 git-effect delta) — additionally
# ends with the workspace-isolation rows: opencode worktree create/list +
# session move. execute stays UNGRANTED deliberately (these roles have no
# deny baseline, so Code Mode falls through to the global ask — interactive
# runs approve once, unattended pipeline devs stay blocked from minting
# surfaces their coordinator owns).
ISOLATE = [{"action": "opencode_worktree_create", "resource": "*", "effect": "allow"},
           {"action": "opencode_worktree_list",   "resource": "*", "effect": "allow"},
           {"action": "opencode_session_move",    "resource": "*", "effect": "allow"}]
SUFFIX = {
  "local": [sh("git add *", "allow"), sh("git commit *", "allow"), sh("git push*", "deny")],
  "pr": [sh("git add *", "allow"), sh("git commit *", "allow"), sh("git push*", "allow"),
         sh("git push*main*", "deny"), sh("git push --force*", "deny"), sh("git push -f*", "deny"),
         sh("git push * --force*", "deny"), sh("git push * -f*", "deny")],
}[variant] + ISOLATE
b, c = perms(base_file), perms(target)
if len(c) != len(b) + len(SUFFIX):
    print(f"{target}: {len(c)} rules, want {len(b)}+{len(SUFFIX)} (base block + the {variant} git rows, nothing else)"); sys.exit(1)
kept = []
for r in c:
    if any(r == s for s in SUFFIX) and r not in kept:
        kept.append(None)
    else:
        kept.append(r)
if [r for r in kept if r is not None] != b:
    print(f"{target}: the base block's rules or their order changed (must be copied verbatim)"); sys.exit(1)
idx = [i for i, r in enumerate(c) if r in SUFFIX and c.index(r) == i]
if len(idx) != len(SUFFIX):
    print(f"{target}: a {variant} git row is missing or duplicated"); sys.exit(1)
if idx != sorted(idx):
    print(f"{target}: git rows out of declared order at {idx}"); sys.exit(1)
last_read = max(i for i, r in enumerate(c) if r in b and r.get("action") == "shell" and str(r.get("resource", "")).startswith("git "))
if min(idx) <= last_read:
    print(f"{target}: git write rows must sit AFTER the existing git reads (read at {last_read}, first write at {min(idx)})"); sys.exit(1)
PY

cat >"$TMP/giteffect.py" <<'PY'
# cf-76 C02 sanctioned-delta comparator: pipeline agent-dev-{local,pr} vs
# standalone dev-{local,pr}. The two permission lists must be IDENTICAL
# (dict + order) except on the `git add *` / `git commit *` shell rows,
# where the pipeline variant carries DENY (the coordinator is the sole
# committer, D7) and the standalone keeps ALLOW (user-supervised, no
# coordinator exists to take the commit). argv: agent-file standalone-file
# variant. Any other divergence — an order shift, a lost isolation row, a
# re-equalized git effect — exits 1 with the reason.
import re, sys, yaml

def perms(p):
    m = re.match(r"^---\n(.*?)\n---\n", open(p).read(), re.S)
    assert m, f"{p}: no YAML frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    return (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []

agent, standalone, variant = sys.argv[1:4]
GIT_WRITE = ("git add *", "git commit *")

def split(p):
    rows = perms(p)
    git = [r for r in rows if r.get("action") == "shell" and r.get("resource") in GIT_WRITE]
    rest = [r for r in rows if not (r.get("action") == "shell" and r.get("resource") in GIT_WRITE)]
    return rows, git, rest

a_rows, a_git, a_rest = split(agent)
s_rows, s_git, s_rest = split(standalone)
want = {
    "local": {"git add *": "deny", "git commit *": "deny"},
    "pr": {"git add *": "deny", "git commit *": "deny"},
}[variant]
for r in a_git:
    if r["effect"] != want[r["resource"]]:
        print(f"{agent}: {r['resource']} effect {r['effect']}, want {want[r['resource']]} (cf-76 C02: pipeline implementers never commit)"); sys.exit(1)
for r in s_git:
    if r["effect"] != "allow":
        print(f"{standalone}: {r['resource']} effect {r['effect']}, want allow (the standalone dev family is UNCHANGED by cf-76 — D7 scope)"); sys.exit(1)
if len(a_git) != 2 or len(s_git) != 2:
    print(f"{agent}: {len(a_git)} / {standalone}: {len(s_git)} git-write rows, want the add+commit pair each"); sys.exit(1)
if a_rest != s_rest:
    i = next((i for i, (x, y) in enumerate(zip(a_rest, s_rest)) if x != y), min(len(a_rest), len(s_rest)))
    print(f"non-git-write blocks differ at index {i}: agent {a_rest[i] if i < len(a_rest) else None} vs standalone {s_rest[i] if i < len(s_rest) else None} (lengths {len(a_rest)}/{len(s_rest)}) — only the add/commit effects may diverge"); sys.exit(1)
PY

cat >"$TMP/policy.py" <<'PY'
# Last-match-wins simulation per the agents-sync permissions.md audit habit:
# fnmatch every rule for the action, keep the LAST matching effect. Asserts
# the effective verdict for concrete commands — the mechanism behind the
# plan's "hand-derive per the permissions.md audit habit" acceptance wording.
import fnmatch, re, sys, yaml
path = sys.argv[1]
m = re.match(r"^---\n(.*?)\n---\n", open(path).read(), re.S)
assert m, f"{path}: no YAML frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
perms = (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
def effective(action, resource):
    verdict = None  # unmatched stays None — a deny pin must come from a RULE, not silence
    for p in perms:
        if p.get("action") != action and not fnmatch.fnmatch(action, str(p.get("action", ""))):
            continue
        if fnmatch.fnmatch(str(resource), str(p.get("resource", "*"))):
            verdict = p.get("effect", "deny")
    return verdict
bad = []
for spec in sys.argv[2:]:
    action, resource, wantg = spec.split("|")
    got = effective(action, resource)
    if wantg == "allow" and got != "allow":
        bad.append(f"{action} '{resource}': want allow, effective {got}")
    if wantg == "deny" and got != "deny":
        bad.append(f"{action} '{resource}': want an EXPLICIT deny, effective {got}")
    # ask-effect means "cannot run unattended": an explicit ask, an explicit
    # deny, or no rule at all (client default prompts) all satisfy it.
    if wantg == "ask" and got not in ("ask", "deny", None):
        bad.append(f"{action} '{resource}': want ask-or-deny (blocked unattended), effective {got}")
if bad:
    print("; ".join(bad)); sys.exit(1)
PY

cat >"$TMP/pairsync.py" <<'PY'
# Source<->generated honesty (coord-inwork convention): bodies equal modulo
# frontmatter/blank space; meaningful frontmatter fields equal once parsed.
import re, sys, yaml
src, gen, kind = sys.argv[1], sys.argv[2], sys.argv[3]

def parts(path):
    text = open(path).read()
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    assert m, f"{path}: no parsable frontmatter"
    return yaml.safe_load(m.group(1)), m.group(2).strip("\n") + "\n"

f1, b1 = parts(src); f2, b2 = parts(gen)
if kind == "skill":
    n = lambda f: {k: f.get(k) for k in ("name", "description", "metadata", "disable-model-invocation")}
else:
    def n(f):
        oc = f.get("opencode") or {}
        return {"name": f.get("name"), "description": f.get("description"),
                "mode": oc.get("mode", f.get("mode")), "color": oc.get("color", f.get("color")),
                "permissions": oc.get("permissions", f.get("permissions"))}
if b1 != b2:
    print("body drift between source and generated mirror"); sys.exit(1)
if n(f1) != n(f2):
    print("frontmatter drift between source and generated mirror"); sys.exit(1)
PY

cat >"$TMP/win.py" <<'PY'
# Co-location window (rulesync-surface.sh convention): needles must read as
# one passage, not as scattered file-wide hits.
import sys
argv = sys.argv[1:]
ci = argv[0] == '--ci'
if ci:
    argv = argv[1:]
path, span = argv[0], int(argv[1])
needles = argv[2:]
text = open(path).read()
if ci:
    text = text.lower(); needles = [n.lower() for n in needles]
pts = []
for n in needles:
    start, found = 0, 0
    while True:
        i = text.find(n, start)
        if i < 0:
            break
        pts.append((i, n)); start = i + 1; found += 1
    if not found:
        print(f'missing needle: {n}'); sys.exit(1)
pts.sort()
need = len(set(needles))
cnt, have, best, left = {}, 0, None, 0
for right, (p, n) in enumerate(pts):
    cnt[n] = cnt.get(n, 0) + 1
    if cnt[n] == 1:
        have += 1
    while have == need:
        s = p - pts[left][0]
        if best is None or s < best:
            best = s
        cnt[pts[left][1]] -= 1
        if cnt[pts[left][1]] == 0:
            have -= 1
        left += 1
if best is None or best > span:
    print(f'no window of {span} chars covers all needles (min span {best})'); sys.exit(1)
PY

cat >"$TMP/section.py" <<'PY'
# Section-scoped needles (sectgrep's section mode, same convention): every
# line from the heading matching the anchor to EOF, then require the needles
# inside it — a row/section elsewhere in the file does not count.
import re, sys
argv = sys.argv[1:]
ci = argv[0] == '--ci'
if ci:
    argv = argv[1:]
path, anchor = argv[0], argv[1]
needles = argv[2:]
text = open(path).read()
m = re.search(r"(?ms)^#+[^\n]*" + re.escape(anchor) + r"[^\n]*\n.*", text)
if not m:
    print(f"{path}: no section '{anchor}'"); sys.exit(1)
hay = m.group(0).lower() if ci else m.group(0)
for n in needles:
    nn = n.lower() if ci else n
    if nn not in hay:
        print(f"{path}: '{n}' missing from the '{anchor}' section"); sys.exit(1)
PY

# --- S1: the dev family + role-dev sources and mirrors exist --------------------
if want s1; then
  for f in "$DEV" "$DEV_LOCAL" "$DEV_PR" "$DEV_GEN" "$DEV_LOCAL_GEN" "$DEV_PR_GEN" "$RDEV_SRC" "$RDEV_GEN"; do
    [ -f "$f" ] || fail "S1[AC1]: $f is missing (red before C04 — the standalone dev family ships three sources + three mirrors + the role-dev skill pair)"
  done
  ok "S1[AC1]: dev/dev-local/dev-pr sources and generated mirrors + role-dev pair all exist"
fi

# --- S2: plain dev is a parsed-equal alias of dev-local --------------------------
if want s2; then
  for f in "$DEV" "$DEV_LOCAL"; do [ -f "$f" ] || fail "S2[AC1]: $f missing (red before C04)"; done
  python3 "$TMP/eq.py" "$DEV" "$DEV_LOCAL" \
    || fail "S2[AC1]: dev alias permission list is not parsed-equal (dict+order) to dev-local — alias drift is the silent failure mode this plan pins"
  grep -qF 'commit-only alias of dev-local' "$DEV" \
    || fail "S2[AC1]: dev description lacks the '(commit-only alias of dev-local)' tag (C04 pins the alias marker)"
  grep -qE '^[[:space:]]*/pipeline-push-pr[[:space:]]*$' "$DEV" \
    && fail "S2[AC1]: the plain dev alias MUST-loads /pipeline-push-pr — aliases are commit-only, push wiring belongs to dev-pr alone"
  ok "S2[AC1]: dev == dev-local (parsed permission equality); alias tag present; no push wiring leaked onto the alias"
fi

# --- S3: block equality — pinned reconstruction now, dynamic agent-dev pair after C02 --
if want s3; then
  [ -f "$DEV_LOCAL" ] && [ -f "$DEV_PR" ] || fail "S3[AC1]: dev-local/dev-pr missing (red before C04)"
  if git cat-file -e "${TB}:.rulesync/subagents/agent-dev.md" 2>/dev/null; then
    git show "$TB:.rulesync/subagents/agent-dev.md" >"$TMP/base-agent-dev.md"
    python3 "$TMP/blockdiff.py" "$TMP/base-agent-dev.md" "$DEV_LOCAL" local \
      || fail "S3[AC1]: dev-local's block is not the ticket-base implementer list + [add allow, commit allow, push deny] + [worktree create/list, session move] after the git reads — C04 copies the C02 agent-dev-local block verbatim, the 2026-10-27 isolation landing appended its sanctioned rows"
    python3 "$TMP/blockdiff.py" "$TMP/base-agent-dev.md" "$DEV_PR" pr \
      || fail "S3[AC1]: dev-pr's block is not the ticket-base implementer list + [add allow, commit allow, push allow, main/force deny x5] + [worktree create/list, session move] after the git reads, in order"
    pinned_note="pinned-copy arm run vs ticket base"
  else
    [ -f "$ADEV_LOCAL" ] || fail "S3[AC1]: neither the ticket-base agent-dev.md nor agent-dev-local.md is readable — the pinned contract cannot be verified"
    pinned_note="agent-dev.md gone at base (post-landing) — dynamic arm only"
  fi
  if [ -f "$ADEV_LOCAL" ]; then
    # cf-76 C02 re-pin (D7): the pipeline implementers' block now DELIBERATELY
    # differs from the standalone trio on exactly the git add/commit effects
    # (deny vs allow — the coordinator owns commits; standalone dev commits
    # its own work). Everything else must still agree, list order included;
    # a silent re-equalization would undo C02, an unlisted drift would hide.
    python3 "$TMP/giteffect.py" "$ADEV_LOCAL" "$DEV_LOCAL" local \
      || fail "S3[AC1]: dev-local vs agent-dev-local drifted beyond the sanctioned cf-76 git add/commit effect delta"
    python3 "$TMP/giteffect.py" "$ADEV_PR" "$DEV_PR" pr \
      || fail "S3[AC1]: dev-pr vs agent-dev-pr drifted beyond the sanctioned cf-76 git add/commit effect delta"
    pinned_note="$pinned_note; dynamic agent-dev pair compare ENGAGED (cf-76 delta-aware)"
  else
    pinned_note="$pinned_note; agent-dev pair absent (C04 before C02)"
  fi
  # MUST-load order: /executing-plans then /role-dev (+ /pipeline-push-pr after /role-dev on dev-pr)
  python3 "$TMP/win.py" "$DEV_LOCAL" 200 '/executing-plans' '/role-dev' \
    || fail "S3[AC1]: dev-local MUST-load order is not /executing-plans then /role-dev (C04 Tasks)"
  python3 "$TMP/win.py" "$DEV_PR" 300 '/role-dev' '/pipeline-push-pr' \
    || fail "S3[AC1]: dev-pr does not add /pipeline-push-pr after /role-dev in its MUST-load list"
  grep -qE '^[[:space:]]*/pipeline-push-pr[[:space:]]*$' "$DEV_LOCAL" \
    && fail "S3[AC1]: dev-local references /pipeline-push-pr — the -local variant must never load the push skill"
  ok "S3[AC1]: dev family permission blocks match the pinned implementer contract ($pinned_note); MUST-load order pinned"
fi

# --- S4: role-dev hidden-contract skill (AC2) ------------------------------------
if want s4; then
  for f in "$RDEV_SRC" "$RDEV_GEN"; do
    [ -f "$f" ] || fail "S4[AC2]: $f missing (red before C04)"
    python3 "$TMP/win.py" --ci "$f" 600 'one-session' 'deliverable' \
      || fail "S4[AC2]: $f lacks the one-session-sized implementer framing (deliverable is the edit; scope tripwire to the pipeline)"
    python3 "$TMP/win.py" --ci "$f" 600 'variants' 'dev-pr' 'pipeline-push-pr' \
      || fail "S4[AC2]: $f has no Variants section routing dev-pr's push strictly through pipeline-push-pr"
    python3 "$TMP/win.py" --ci "$f" 500 'ticket folder' 'pipeline-conventions' 'pipeline-role-dev' \
      || fail "S4[AC2]: $f lacks the pipeline-support clause naming BOTH /pipeline-conventions and /pipeline-role-dev for a handed ticket folder"
    python3 "$TMP/win.py" --ci "$f" 300 'comment-slop' 'aislop-gate' \
      || fail "S4[AC2]: $f lacks the quality-gate paragraph (one contract voice with pipeline-role-dev)"
    python3 "$TMP/win.py" --ci "$f" 600 'never push' 'main' 'AGENTS.md' \
      || fail "S4[AC2]: $f lacks the git-safety never-push/never-merge-main rule with the AGENTS.md Hard-rules citation"
    python3 "$TMP/win.py" --ci "$f" 400 'readonly' 'admin' 2>/dev/null \
      || python3 "$TMP/win.py" --ci "$f" 400 'read-only' 'ask' \
      || fail "S4[AC2]: $f lacks the MCP privilege rule (readonly free, admin asks)"
    python3 "$TMP/win.py" --ci "$f" 500 'RESULT' 'deviations' \
      || fail "S4[AC2]: $f lacks the RESULT-shaped final report (files changed / commands run / deviations / open questions)"
    python3 "$TMP/win.py" --ci "$f" 300 'pre-completion' 'validations' \
      || fail "S4[AC2]: $f lacks the pre-completion checklist"
  done
  python3 - "$RDEV_SRC" <<'PY' || fail "S4[AC2]: role-dev frontmatter is not the hidden-contract shape"
import re, sys, yaml
m = re.match(r"^---\n(.*?)\n---\n", open(sys.argv[1]).read(), re.S)
assert m, "no YAML frontmatter"
fm = yaml.safe_load(m.group(1)) or {}
assert fm.get("name") == "role-dev", fm.get("name")
assert fm.get("disable-model-invocation") is True
assert (fm.get("metadata") or {}).get("opencode/autoinvoke") == "false"
assert fm.get("targets") == ["*"], fm.get("targets")
assert "never auto-selected." in str(fm.get("description") or "")
PY
  ok "S4[AC2]: role-dev carries the sections (What you are / Variants / pipeline-support clause / quality gate / git safety / MCP rule / RESULT report / pre-completion) and the hidden frontmatter shape"
fi

# --- S5: role-planner / role-code / role-debug folds (AC3) ------------------------
if want s5; then
  for f in "$RP_SRC" "$RP_GEN"; do
    [ -f "$f" ] || fail "S5[AC3]: $f missing"
    grep -qF '## Commands' "$f" \
      || fail "S5[AC3]: $f has no literal '## Commands' plan-section (the mandatory validation-commands section folded out of free-text Verification — red before C04)"
    python3 "$TMP/win.py" --ci "$f" 400 'commands' 'mandatory' \
      || fail "S5[AC3]: $f's ## Commands is not stated as mandatory in its own passage"
    python3 "$TMP/win.py" --ci "$f" 500 'pipeline' 'recommend' \
      || fail "S5[AC3]: $f lacks the pipeline-handoff rule (multi-session / cross-subsystem / new-interface work → recommend the agent-* pipeline)"
  done
  for f in "$RC_SRC" "$RC_GEN"; do
    [ -f "$f" ] || fail "S5[AC3]: $f missing"
    grep -qF 'No pipeline context:' "$f" \
      || fail "S5[AC3]: $f lacks the verbatim-greppable 'No pipeline context:' clause (C04 pins the opener — red before C04)"
    python3 "$TMP/win.py" --ci "$f" 500 'ticket folder' 'stop' \
      || fail "S5[AC3]: $f's no-pipeline-context clause does not say to STOP when handed a pipeline ticket folder"
    if grep -qF 'pipeline-conventions' "$f"; then
      fail "S5[AC3]: $f references pipeline-conventions — role-code must never load pipeline-* skills"
    fi
  done
  for f in "$RD_SRC" "$RD_GEN"; do
    [ -f "$f" ] || fail "S5[AC3]: $f missing"
    for title in 'Method' 'Repo validation discipline' 'Quality gate' 'Git hygiene' 'Scope tripwire' 'Reporting'; do
      grep -qiE "^#{1,6}[[:space:]].*${title}" "$f" \
        || fail "S5[AC3]: $f has no '${title}' section — role-debug is a FULL rewrite with the six agent-* guidance sections (Q8), not a patch"
    done
    if grep -qF 'Guidelines:' "$f"; then
      fail "S5[AC3]: $f still carries the old 'Guidelines:' bullet form — the rewrite replaces it (no residue except preserved semantics)"
    fi
    python3 "$TMP/win.py" --ci "$f" 900 '5-7' '1-2' 'confirm' 'minimal' \
      || fail "S5[AC3]: $f's Method section does not carry the preserved core (enumerate 5-7, distill 1-2, confirm the diagnosis, minimal fix) in one passage"
    python3 "$TMP/win.py" --ci "$f" 300 'comment-slop' 'aislop-gate' \
      || fail "S5[AC3]: $f lacks the shared quality-gate paragraph (same contract voice as role-dev)"
    python3 "$TMP/win.py" --ci "$f" 500 'never push' 'force' \
      || fail "S5[AC3]: $f's Git hygiene lacks the never-push/never-force posture"
    python3 "$TMP/win.py" --ci "$f" 400 'accidental' 'stop' \
      || fail "S5[AC3]: $f lacks the accidental-push rule (stop and tell the user — no self-remediation)"
    python3 "$TMP/win.py" --ci "$f" 400 'planner' 'pipeline' \
      || fail "S5[AC3]: $f's scope tripwire does not hand off to planner/pipeline when the fix grows"
    python3 "$TMP/win.py" --ci "$f" 300 'RESULT' 'diagnosis' \
      || fail "S5[AC3]: $f lacks the RESULT-shaped reporting section naming the diagnosis"
  done
  # debug.md subagent: explicit push DENY appended, add/commit stay at the ask baseline
  [ -f "$DEBUG_SRC" ] || fail "S5[AC3]: $DEBUG_SRC missing"
  grep -qF 'git push*' "$DEBUG_SRC" \
    || fail "S5[AC3]: $DEBUG_SRC has no explicit 'git push*' deny row (C04 appends it — a drifted debug fails loudly instead of asking)"
  python3 "$TMP/policy.py" "$DEBUG_SRC" \
    'shell|git push origin feature-x|deny' \
    'shell|git add foo|ask' 'shell|git commit -m x|ask' \
    || fail "S5[AC3]: debug's effective git policy is not [push deny, add/commit at ask baseline] — interactive agent, push never"
  ok "S5[AC3]: planner mandatory ## Commands + handoff rule; code 'No pipeline context:' clause; debug full rewrite (six sections, old form gone) + push deny + ask-baseline add/commit"
fi

# --- S6: the card's git-write matrix audit (AC4) ----------------------------------
if want s6; then
  for f in .rulesync/subagents/planner.md .rulesync/subagents/ask.md .rulesync/subagents/review.md \
           .rulesync/subagents/agent-plan.md .rulesync/subagents/agent-research.md .rulesync/subagents/agent-review.md; do
    [ -f "$f" ] || fail "S6[AC4]: $f missing (the no-git-write roster names it)"
    writes=$(python3 - "$f" <<'PY'
import re, sys, yaml
m = re.match(r"^---\n(.*?)\n---\n", open(sys.argv[1]).read(), re.S)
fm = yaml.safe_load(m.group(1)) or {}
perms = (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
bad = [p for p in perms if p.get("action") == "shell" and p.get("effect") == "allow"
       and re.search(r"git (add|commit|push)", str(p.get("resource", "")))]
print("; ".join(str(b) for b in bad))
PY
)
    [ -z "$writes" ] || fail "S6[AC4]: $f carries an allow git-write row ($writes) — planner/ask/review/agent-plan/agent-research/agent-review keep read-only git (card requirement)"
  done
  for f in "$DEV" "$DEV_LOCAL"; do
    python3 "$TMP/policy.py" "$f" \
      'shell|git status --porcelain|allow' 'shell|git commit -am x|allow' 'shell|git push origin feature-x|deny' 'shell|git push origin main|deny' \
      || fail "S6[AC4]: $f's effective git policy is not [reads+commit allow, push deny] (red before C04 — file may be absent)"
  done
  python3 "$TMP/policy.py" "$DEV_PR" \
    'shell|git commit -am x|allow' \
    'shell|git push origin feature-x|allow' \
    'shell|git push origin main|deny' \
    'shell|git push HEAD:main|deny' \
    'shell|git push feature:main|deny' \
    'shell|git push --force origin feature-x|deny' \
    'shell|git push -f origin feature-x|deny' \
    'shell|git push origin feature-x --force|deny' \
    || fail "S6[AC4]: dev-pr is not the sole standalone push-allow shape — feature push allow with trailing main/force denies (red before C04)"
  python3 "$TMP/policy.py" "$DEV" \
    'shell|git merge main|ask' 'shell|git merge other-branch|ask' \
    || fail "S6[AC4]: dev-family git merge is not ask-effect (merging is human/coord territory)"
  ok "S6[AC4]: git-write audit — no-write roster clean; dev/dev-local commit-allow push-deny; dev-pr push-allow with main/force denies; merge at ask"
fi

# --- S7: code.md pipeline-clean, no code variants, byte-unchanged fold-free files --
if want s7; then
  grep -qE '^[[:space:]]*/pipeline' .rulesync/subagents/code.md \
    && fail "S7[AC5]: code.md MUST-loads a pipeline-* skill — the standalone code agent runs WITHOUT pipeline context"
  variants=$(ls .rulesync/subagents/code-*.md 2>/dev/null || true)
  [ -z "$variants" ] || fail "S7[AC5]: code variants exist ($variants) — the card is explicit: NO variants for code"
  # code.md left the byte-freeze with the isolation landing (2026-10-27,
  # bug-coord-opencode-perms): its sanctioned delta is the three opencode_*
  # workspace-isolation rows, pinned present below; the pipeline-MUST-load
  # and no-variants pins above stay the file's real invariants.
  moved=$(git diff --name-only "$TB" -- .rulesync/subagents/ask.md .rulesync/subagents/review.md \
          .rulesync/subagents/planner.md | grep -v '^$' || true)
  [ -z "$moved" ] || fail "S7[AC5]: $moved changed vs ticket base $TB — these three subagent files must be byte-unchanged (the fold-ins land in their role SKILLs, not the agent files)"
  for row in opencode_worktree_create opencode_worktree_list opencode_session_move; do
    grep -qF "action: $row" .rulesync/subagents/code.md \
      || fail "S7[AC5]: code.md lost the workspace-isolation row '$row' (sanctioned 2026-10-27; execute deliberately ungranted — Code Mode falls to the global ask)"
  done
  ok "S7[AC5]: code.md clean of pipeline MUST-loads and unvarianted, carrying the sanctioned isolation rows; ask/review/planner subagent files byte-unchanged vs $TB"
fi

# --- S8: permissions.md Standalone-agents subsection + mirror integrity -----------
if want s8; then
  for f in "$PERM_SRC" "$PERM_GEN"; do
    [ -f "$f" ] || fail "S8: $f missing"
    python3 "$TMP/section.py" --ci "$f" 'Standalone agents' 'dev-pr' 'push' 'planner' 'debug' \
      || fail "S8[AC4]: $f has no 'Standalone agents' subsection naming the dev family rows (dev-pr as the push-allow exception), the debug posture and the no-git-write roster (red before C04)"
  done
  cmp -s "$PERM_SRC" "$PERM_GEN" \
    || fail "S8[AC4]: permissions.md source and generated mirror are not byte-identical — rulesync copies this reference verbatim (agent-perms A5 convention)"
  ok "S8[AC4+matrix]: permissions.md carries the Standalone-agents subsection (source + byte-identical mirror)"
fi

# --- S9: overview/AGENTS.md name the standalone dev family (C04 overview task) -----
if want s9; then
  for f in "$RULES_SRC" AGENTS.md; do
    python3 - "$f" <<'PY' || fail "S9: $f does not name the standalone dev family on its own line (red before C04) — a line mentioning dev-local AND dev-pr without the agent- prefix, so the pipeline family cannot satisfy it"
import sys
lines = open(sys.argv[1]).read().splitlines()
hits = [l for l in lines if "dev-local" in l and "dev-pr" in l]
standalone = [l for l in hits if "agent-dev-local" not in l and "agent-dev-pr" not in l]
sys.exit(0 if standalone else 1)
PY
  done
  ok "S9: rules source + AGENTS.md carry a standalone dev-family entry (variants + alias naming, distinct from the agent-dev pair)"
fi

# --- S10: source<->mirror honesty for every pair + generator gate ------------------
if want s10; then
  for p in "$DEV|$DEV_GEN|agent" "$DEV_LOCAL|$DEV_LOCAL_GEN|agent" "$DEV_PR|$DEV_PR_GEN|agent" \
           "$RDEV_SRC|$RDEV_GEN|skill" "$RP_SRC|$RP_GEN|skill" "$RC_SRC|$RC_GEN|skill" \
           "$RD_SRC|$RD_GEN|skill"; do
    IFS='|' read -r s g k <<<"$p"
    [ -f "$s" ] && [ -f "$g" ] || fail "S10[AC5]: pair incomplete ($s / $g) — red before C04 (sources + generated land together)"
    python3 "$TMP/pairsync.py" "$s" "$g" "$k" \
      || fail "S10[AC5]: source/generated pair out of sync for $s ($k) — regenerate, never hand-edit .opencode/"
  done
  if git diff --quiet "$TB" -- "$DEBUG_SRC" 2>/dev/null; then
    skip "S10: debug.md still byte-equal to the ticket base — the C04 push-deny edit has not landed (S5 already reds on that)"
  fi
  RS=""
  if command -v rulesync >/dev/null 2>&1; then
    RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then
    RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "S10: rulesync not resolvable — generate gate skipped with warning (c7/t14 precedent)"
    ok "S10[AC5]: seven standalone pairs honest; generator gate skipped with warning"
  else
    timeout 180 $RS generate --check >"$TMP/check.log" 2>&1 \
      || { tail -n 15 "$TMP/check.log" >&2; fail "S10[AC5]: rulesync generate --check is not clean — generated surfaces stale"; }
    timeout 180 $RS generate >"$TMP/gen.log" 2>&1 || { tail -n 15 "$TMP/gen.log" >&2; fail "S10[AC5]: rulesync generate failed"; }
    before=$(git status --porcelain)
    timeout 180 $RS generate >/dev/null 2>&1 || fail "S10[AC5]: second generate failed"
    after=$(git status --porcelain)
    [ "$before" = "$after" ] || fail "S10[AC5]: the second rulesync generate is not a no-op"
    ok "S10[AC5]: seven standalone pairs honest; generate --check clean; second generate a no-op (via $RS)"
  fi
fi

printf 'PASS: standalone-agents contract checks (%d ok)\n' "$checks"
