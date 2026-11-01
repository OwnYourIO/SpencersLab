#!/usr/bin/env bash
# agent-explore subagent + roster/permissions/docs wiring contract
# (2026/2026-10-cf-96-feat-dep-tracking-card-pickup, C02).
#
# Pins chunks/C02.md "## Tests" + AC2-AC5: the new read-only scouting
# subagent's permission-block shape (mirrors agent-research with the ruled
# deltas), its roster allow-row on ALL SIX coord twins (sources AND
# generated mirrors, same relative position), alias-pair parsed parity,
# the permissions.md matrix/drift updates, the AGENTS.md roster currentness,
# and the EXPLORE.md artifact contract inside pipeline-conventions (file
# semantics AND the numbered read order, after RESEARCH.md).
#
# The agent-perms re-pin (roster-set enumeration arms) and the rulesync
# regeneration land in C02's DEV commit — doc/parity pins are never red
# between commits (DECISIONS convention); this file is the designed-red
# contract for the new surfaces. No new pipeline-role-explore skill exists
# by design (inline role contract until the role grows, plan decision
# 2026-11-01) — t6 negative-pins its absence so a premature skill dir does
# not sneak in unapproved.
#
# AC trace: t1[C02 AC5-t1 / T1 — permission-block shape pins on the parsed
# frontmatter, not line numbers] t2[AC2 — six-source + six-mirror roster
# rows at the pinned relative position] t3[AC2 — alias-pair parsed parity,
# the same invariant agent-perms A10/A12 guard] t4[AC3 — permissions.md
# explore row + coord cells + No-git-write sentence + drift history]
# t5[AC3/AC4 — AGENTS.md roster + rules source + pipeline-conventions
# EXPLORE.md in BOTH sections, sources and mirrors] t6[harness honesty —
# no pipeline-role-explore skill dir; source↔mirror existence pairing].
#
# Red posture: DESIGNED RED until C02 dev lands — verified at authoring
# 2026-11-01: .rulesync/subagents/agent-explore.md does not exist, no coord
# twin carries an agent-explore row, AGENTS.md does not name agent-explore,
# pipeline-conventions carries no EXPLORE.md. Every red names the missing
# surface. Frontmatter is parsed as YAML and compared as parsed dicts —
# rulesync re-serializes mirrors, so byte equality is the wrong invariant
# (agent-perms law).
#
# Usage:
#   bash tests/agent-explore/surface.sh            # t1..t6
#   bash tests/agent-explore/surface.sh t2         # subset
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

EXPLORE_SRC=".rulesync/subagents/agent-explore.md"
EXPLORE_GEN=".opencode/agents/agent-explore.md"
TWINS_SRC=(.rulesync/subagents/agent-coord.md .rulesync/subagents/agent-coord-local.md
           .rulesync/subagents/agent-coord-pr.md .rulesync/subagents/agent-board-coord.md
           .rulesync/subagents/agent-board-coord-local.md .rulesync/subagents/agent-board-coord-pr.md)
TWINS_GEN=.opencode/agents
PERMS=".rulesync/skills/agents-sync/references/permissions.md"
PERMS_GEN=".opencode/skills/agents-sync/references/permissions.md"
RULES=".rulesync/rules/overview.md"
CONV_SRC=".rulesync/skills/pipeline-conventions/SKILL.md"
CONV_GEN=".opencode/skills/pipeline-conventions/SKILL.md"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    lc=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    [[ "$lc" =~ ^t[1-6]$ ]] || fail "unknown check id '$a' (expected t1..t6)"
    WANT["$lc"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

TMP=$(mktemp -d /tmp/opencode/agent-explore-test.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

# Shared parsed-frontmatter projection (same shape as agent-perms' family.py
# fm/perms: rules as dicts in order — the honest pair invariant).
cat >"$TMP/perms.py" <<'PY'
import re, sys, yaml

def fm(path):
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", open(path).read(), re.S)
    assert m, f"{path}: no YAML frontmatter"
    return (yaml.safe_load(m.group(1)) or {}, m.group(2))

def perms(path):
    f, _ = fm(path)
    return (f.get("opencode") or {}).get("permissions") or f.get("permissions") or []

def body(path):
    return fm(path)[1]
PY

# --- t1: agent-explore's own permission block (C02 T1) ----------------------------
if want t1; then
  [ -f "$EXPLORE_SRC" ] \
    || fail "t1[C02 T1]: $EXPLORE_SRC does not exist yet — the agent-explore source is C02's first task (designed red before C02 dev, not a harness fault)"
  if ! python3 - "$TMP/perms.py" "$EXPLORE_SRC" <<'PY'
import ast, sys
sys.path.insert(0, ".")
ns = {}
exec(open(sys.argv[1]).read(), ns)
perms, body, fm = ns["perms"], ns["body"], ns["fm"]
path = sys.argv[2]
p = perms(path)
def bad(m):
    print(f"t1: {m}"); sys.exit(1)
def has(action, resource, effect):
    return any(r.get("action") == action and r.get("resource") == resource and r.get("effect") == effect for r in p)
def idx(action, resource):
    hits = [i for i, r in enumerate(p) if r.get("action") == action and r.get("resource") == resource]
    return hits[0] if len(hits) == 1 else None

f, _ = fm(path)
if f.get("name") != "agent-explore":
    bad(f"frontmatter name is {f.get('name')!r}, want agent-explore")
# the edit grant: plans-only, deny-all BEFORE the allow (last-match wins)
d, a = idx("edit", "*"), idx("edit", ".agents/plans/**")
if d is None or a is None or d > a:
    bad("edit must be '*' deny followed by '.agents/plans/**' allow — the EXPLORE.md grant, same posture as research's RESEARCH.md (C02 T1)")
if not has("subagent", "*", "deny"):
    bad("missing 'subagent * deny' — agent-explore launches nothing")
if has("websearch", "*", "allow") or not has("websearch", "*", "deny"):
    bad("websearch must be DENIED (scouting, not research — a web-research need bubbles via RESULT; the OQ10/T1 ruling)")
if not has("webfetch", "*", "allow"):
    bad("webfetch must be allowed (read of pinned upstream sources during grounding)")
if not has("question", "*", "allow"):
    bad("question must stay allowed — the AGENTS.md hard rule (silently-denied questions break gates)")
if not has("admin*", "*", "deny"):
    bad("missing 'admin* deny' — the research MCP posture")
for tier in ("readonly*", "global*", "dev*"):
    if not has(tier, "*", "allow"):
        bad(f"missing '{tier} allow' — explore must ground cluster/MCP ids (C02 T1 mirrors the research tier grants)")
if not has("shell", "*", "ask"):
    bad("shell must default to ask")
for g in ("git status *", "git log *", "git diff *", "ls *"):
    i = idx("shell", g)
    if i is None or p[i].get("effect") != "allow":
        bad(f"missing read-only shell allow row 'shell {g} allow'")
# body contract: inline role contract, no separate skill
b = body(path)
if "/pipeline-conventions" not in b:
    bad("body must MUST-load /pipeline-conventions (C02 T1)")
if "EXPLORE.md" not in b:
    bad("body must name its deliverable EXPLORE.md next to the plan file")
import re as _re
if not _re.search(r"never load.*pipeline-role-|NEVER load.*pipeline-role-", b, _re.I | _re.S):
    bad("body must forbid loading other roles' pipeline-role-* contracts (the coordination-law carry-over)")
print("ok: t1 — agent-explore permission block parsed: plans-only edit, subagent deny, websearch deny, tier grants, question allow, inline contract")
PY
  then fail "t1[C02 AC5]: the agent-explore permission-block shape pins failed (reason above)"; fi
  ok "t1[C02 T1]: agent-explore permission block matches the research-minus-websearch contract"
fi

# --- t2: the roster row on all six coord twins, sources AND mirrors (C02 T3) -------
if want t2; then
  if ! python3 - "$TMP/perms.py" "${TWINS_SRC[@]}" <<'PY'
import sys
sys.path.insert(0, ".")
ns = {}
exec(open(sys.argv[1]).read(), ns)
perms = ns["perms"]
for path in sys.argv[2:]:
    seq = [r.get("resource") for r in perms(path) if r.get("action") == "subagent" and r.get("effect") == "allow"]
    if "agent-explore" not in seq:
        print(f"t2: {path} carries no agent-explore subagent allow — C02 T3 widens ALL SIX coord twins in one commit (designed red before C02 dev)"); sys.exit(1)
    if not ("agent-research" in seq and seq.index("agent-explore") > seq.index("agent-research")):
        print(f"t2: {path} — the explore row must ride the existing roster block AFTER agent-research (same relative position across twins)"); sys.exit(1)
    deploy = [x for x in ("agent-dev-deploy", "agent-dev-deploy-pr") if x in seq]
    if deploy and seq.index("agent-explore") > seq.index(deploy[0]):
        print(f"t2: {path} — explore row sits after the deploy row; the T3 anchor is before the deploy row's comment block"); sys.exit(1)
print("ok: t2 — six coord sources carry agent-explore between research and the deploy row")
PY
  then fail "t2[C02 AC2]: the six-source roster pin failed (reason above)"; fi
  for gen in "${TWINS_GEN}"/agent-coord.md "${TWINS_GEN}"/agent-coord-local.md "${TWINS_GEN}"/agent-coord-pr.md \
             "${TWINS_GEN}"/agent-board-coord.md "${TWINS_GEN}"/agent-board-coord-local.md "${TWINS_GEN}"/agent-board-coord-pr.md; do
    grep -qE 'resource: agent-explore' "$gen" \
      || fail "t2[C02 AC2/AC1]: $gen — the generated mirror lacks the agent-explore row; sources AND mirrors commit together (rulesync regeneration)"
  done
  [ -f "$EXPLORE_GEN" ] \
    || fail "t2[C02 T2/AC1]: $EXPLORE_GEN missing — rulesync generate must produce the mirror in the same commit as the source"
  if ! python3 - "$TMP/perms.py" "$EXPLORE_SRC" "$EXPLORE_GEN" <<'PY'
import sys
sys.path.insert(0, ".")
ns = {}
exec(open(sys.argv[1]).read(), ns)
perms = ns["perms"]
src, gen = sys.argv[2], sys.argv[3]
if perms(src) != perms(gen):
    print("t2: the agent-explore mirror's parsed permission list differs from its source (dict+order equality — the rulesync-parity invariant)")
    sys.exit(1)
print("ok: mirror parses equal to source")
PY
  then fail "t2[C02 AC1]: explore source↔mirror parity failed (reason above)"; fi
  ok "t2[C02 AC2]: agent-explore allow present on all six sources + six mirrors at the pinned position, explore mirror parses equal"
fi

# --- t3: alias pairs stay parsed-equal with the new row (C02 AC2) ------------------
if want t3; then
  if ! python3 - "$TMP/perms.py" <<'PY'
import sys
sys.path.insert(0, ".")
ns = {}
exec(open(sys.argv[1]).read(), ns)
perms = ns["perms"]
fm = ns["fm"]
pairs = [("agent-coord", "agent-coord-local"), ("agent-board-coord", "agent-board-coord-local")]
for a, b in pairs:
    pa, pb = f".rulesync/subagents/{a}.md", f".rulesync/subagents/{b}.md"
    if perms(pa) != perms(pb):
        print(f"t3: alias pair ({a},{b}) permission lists drifted — the explore row must land on BOTH twins in one commit (agents-sync same-commit parity law)"); sys.exit(1)
    na = (fm(pa)[0] or {}).get("name"); nb = (fm(pb)[0] or {}).get("name")
    if na != a or nb != b:
        print(f"t3: alias pair ({a},{b}) name tags wrong ({na},{nb}) — twins differ ONLY in name/description"); sys.exit(1)
print("ok: t3 — alias pairs parsed-equal, name tags intact")
PY
  then fail "t3[C02 AC2]: alias-pair parity through the parsed projection failed (reason above)"; fi
  ok "t3[C02 AC2]: (coord, coord-local) and (board-coord, board-coord-local) stay parsed-equal with the explore row"
fi

# --- t4: permissions.md matrix + roster sentence + drift history (C02 T4) ----------
if want t4; then
  for f in "$PERMS" "$PERMS_GEN"; do
    [ -f "$f" ] || fail "t4[harness]: $f missing"
    if ! python3 - "$f" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
lines = text.splitlines()
# the matrix grows one row for the new role (the table's first column is the
# role name — same shape as the existing `| research | ...` row)
if not any(re.match(r"^\|\s*`?explore`?\s*\|", l) for l in lines):
    print(f"t4: {path} has no `explore` row in the role matrix (as research, minus websearch, EXPLORE.md artifact — designed red before C02 dev)"); sys.exit(1)
explore_row = next(l for l in lines if re.match(r"^\|\s*`?explore`?\s*\|", l))
if "EXPLORE.md" not in explore_row:
    print(f"t4: {path} — the explore matrix row does not name the EXPLORE.md artifact (its deliverable column)"); sys.exit(1)
if not any(re.match(r"^\|\s*`?coord", l) and "explore" in l for l in lines):
    print(f"t4: {path} — the coord rows' subagent cells were not widened with explore (plan/research/explore/test/… sequence)"); sys.exit(1)
if not any("No-git-write roster" in l and "agent-explore" in l for l in lines):
    print(f"t4: {path} — the No-git-write roster sentence does not name agent-explore (C02 T4)"); sys.exit(1)
if not re.search(r"cf-96[^\n]*[Ee]xplore|[Ee]xplore[^\n]*cf-96", text):
    print(f"t4: {path} — no drift-history line records the cf-96 explore add (permissions.md logs every roster move)"); sys.exit(1)
print("ok")
PY
    then fail "t4[C02 AC3]: permissions.md pins failed (reason above)"; fi
  done
  ok "t4[C02 T4]: permissions.md carries the explore row, widened coord cells, the roster sentence, and the drift-history line (source + mirror)"
fi

# --- t5: AGENTS.md roster + rules source + conventions EXPLORE.md (C02 T5/T6) ------
if want t5; then
  grep -qF "agent-explore" "$RULES" \
    || fail "t5[C02 T5]: $RULES does not name agent-explore — the roster paragraph is edited in the rules SOURCE, then regenerated (designed red before C02 dev)"
  grep -qF "agent-explore" AGENTS.md \
    || fail "t5[C02 AC3]: AGENTS.md does not name agent-explore — the generated mirror must be committed with the rules source (never hand-edit)"
  for f in "$CONV_SRC" "$CONV_GEN"; do
    [ -f "$f" ] || fail "t5[harness]: $f missing"
    grep -qF "EXPLORE.md" "$f" \
      || fail "t5[C02 T6/AC4]: $f never names EXPLORE.md — pipeline-conventions must carry the artifact contract (file semantics AND the numbered read order)"
    python3 - "$f" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
sem = re.search(r"(?ms)^- `EXPLORE\.md`.*?\n(?=[-*] |\n#)", t)
if not sem:
    print("t5: the plan-folder file-semantics list has no `EXPLORE.md` bullet (agent-explore writes it next to the plan file; everyone reads at run start if present)"); sys.exit(1)
order = re.search(r"(?ms)^## Files are the bus.*?(?=^## |\Z)", t)
if not order or "EXPLORE.md" not in order.group(0):
    print("t5: the numbered read order does not include EXPLORE.md (it joins after RESEARCH.md — C02 T6)"); sys.exit(1)
pos_r = order.group(0).find("RESEARCH.md"); pos_e = order.group(0).find("EXPLORE.md")
if pos_e < pos_r:
    print("t5: EXPLORE.md sits BEFORE RESEARCH.md in the read order — the pinned position is after (C02 T6)"); sys.exit(1)
print("ok")
PY
  done \
    || fail "t5[C02 AC4]: the conventions EXPLORE.md pins failed (reason above)"
  ok "t5[C02 T5/T6]: AGENTS.md + rules name agent-explore; pipeline-conventions carries EXPLORE.md in both sections (source + mirror)"
fi

# --- t6: negative — no premature contract skill; regenerate check posture ----------
if want t6; then
  [ ! -d ".rulesync/skills/pipeline-role-explore" ] \
    && [ ! -d ".opencode/skills/pipeline-role-explore" ] \
    || fail "t6[C02 design]: a pipeline-role-explore skill dir exists — the plan ruled the role ships with an INLINE contract (smallest sensible delta); revisit only via a new ticket, not by sneaking a skill in"
  ok "t6[C02 design]: no pipeline-role-explore skill dir (inline-contract decision intact)"
fi

printf 'PASS: agent-explore subagent/wiring checks (%d ok)\n' "$checks"
