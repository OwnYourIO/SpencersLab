#!/usr/bin/env bash
# skills/seaweedfs-debug + ec-removal-runbook surface contract
# (2026/2026-11-feat-seaweedfs-debug-skill, agent-test round 2026-11-11):
# t1 the corrected runbook (C01), t2 the card-pointer spec file (C02),
# t3 the mechanics references (C03), t4 the skill entry + observability +
# probe script (C04), t5 the rulesync registration (C05), t7 the dev-family
# depth-2 plans deny (C07, friction-round addition: the blanket
# `.agents/plans/**` deny is replaced by `.agents/plans/*/*` on all seven
# dev-family sources + their generated mirrors, so plans-root dated
# deliverables fall through to the broad allow while every ticket folder and
# template stays denied).
#
# Contract source: chunks/C01..C05.md + chunks/C07.md "## Tests". AC trace:
# t1[C01 AC1-AC7] t2[C02 AC1-AC5] t3[C03 AC1-AC6] t4[C04 AC1-AC7]
# t5[C05 AC1,AC2,AC4,AC5] t7[C07 AC1,AC3,AC4,AC5 + the Tests'
# DEV_DEPLOY_SETTLED re-pin duty in tests/wekan-mcp/board-context.sh].
#
# No t6 arm: C06 was human-declined at approval (DECISIONS.md 2026-11-11).
# t7 never reuses the t6 number.
#
# Statics-only per the DECISIONS/EXPLORE rule (no live cluster, no network
# calls in suites). The single external command is t5.2's rulesync
# generate --check — a local regen diff — run through the skill-surface t6
# resolver ladder (PATH / npx cache, never npx --yes: fetching a package is
# a network call); t7.4 adds the S10 no-op half of the same gate. Red before
# implementation: t1's correction greps and the t2/t3/t4 existence arms; the
# t1.7 preservation checks, t4.7/t5.3 negatives and the t5.4 scope guard hold
# green at base as regressions. t7 is red before C07 dev: the depth-2 row is
# absent from all fourteen dev-family surfaces (t7.1), and until it moves the
# plans-root dated deliverable still resolves to deny through the blanket row
# (t7.3) while the pre-C07 DEV_DEPLOY_SETTLED byte fails the re-pin grep
# (t7.5).
#
# Usage:
#   bash tests/seaweedfs-debug/surface.sh            # t1..t5 + t7
#                                                    # (fail-fast, per the
#                                                    # wekan-mcp
#                                                    # skill-surface shape)
#   bash tests/seaweedfs-debug/surface.sh t2 t4      # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

RUNBOOK=".agents/plans/2026-11-10-dep-seaweedfs-ec-removal.md"
SKILL_DIR="skills/seaweedfs-debug"
SKILL="$SKILL_DIR/SKILL.md"
SPEC="$SKILL_DIR/references/mcp-server-spec.md"
ERRSIG="$SKILL_DIR/references/error-signatures.md"
WSHELL="$SKILL_DIR/references/weed-shell.md"
CLEC="$SKILL_DIR/references/collections-and-ec.md"
ENDPOINTS="$SKILL_DIR/references/endpoints-and-probes.md"
LOKI="$SKILL_DIR/references/loki-recipes.md"
PROBE="$SKILL_DIR/scripts/health-probe.sh"
AGENTS="AGENTS.md"
RULES_SRC=".rulesync/rules/overview.md"
CARD_PATH="skills/seaweedfs-debug/references/mcp-server-spec.md"
TICKET=".agents/plans/2026/2026-11-feat-seaweedfs-debug-skill"
BC="tests/wekan-mcp/board-context.sh"
# C07's surface: the seven dev-family sources and their seven generated
# mirrors, pairs adjacent (index 0/1 are the agent-dev-local pair — the
# verdict-arm exemplar named in C07's Tests).
DEVFILES=()
for _n in agent-dev-local agent-dev-pr agent-dev-deploy agent-dev-deploy-pr dev dev-local dev-pr; do
  DEVFILES+=(".rulesync/subagents/$_n.md" ".opencode/agents/$_n.md")
done

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }
skip() { printf 'skip: %s\n' "$1" >&2; }

# tok/noTok are case-SENSITIVE on purpose: the negative verb tokens (POST,
# PUT, DELETE) would false-fail on ordinary prose lowercased. Tokens the
# chunks quote case-insensitively go through toki.
tok()    { grep -qE -- "$2" "$1" || fail "$3"; }
toki()   { grep -qiE -- "$2" "$1" || fail "$3"; }
noTok()  { local hits; hits=$(grep -rnE -- "$2" "$1" 2>/dev/null || true); [ -z "$hits" ] || fail "$3: $hits"; }

TMP=$(mktemp -d /tmp/opencode/seaweedfs-surface.XXXXXX) || { echo "harness: mktemp failed" >&2; exit 2; }
trap '[ "$FAILED" -eq 1 ] || rm -rf "$TMP"' EXIT

# Window check for the chunks' "X near Y" criteria — line-anchored greps
# cannot express adjacency across the runbook's table/prose layouts.
cat >"$TMP/near.py" <<'PY'
import re, sys
path, ids, anchor, win = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
lines = open(path, encoding='utf-8', errors='replace').read().splitlines()
anch = re.compile(anchor, re.I)
missing = []
for ident in ids.split(','):
    pat = re.compile(ident)
    if not any(pat.search(l) and any(anch.search(lines[j])
               for j in range(max(0, i - win), min(len(lines), i + win + 1)))
               for i, l in enumerate(lines)):
        missing.append(ident)
if missing:
    print('; '.join(missing)); sys.exit(1)
PY

# C02 AC1 pins every PATH-spelling of the card-pointer to the byte-exact
# card string; a bare filename mention (no `skills/…` prefix) is not a
# path-spelling and stays out of scope.
cat >"$TMP/pathcheck.py" <<'PY'
import os, re, sys
CANON = sys.argv[1]
pat = re.compile(r'skills/seaweed[A-Za-z0-9_./-]*mcp-server-spec[A-Za-z0-9._-]*')
skip_dirs = {'.git', 'node_modules', 'worktrees'}
bad = []
for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in skip_dirs]
    for f in files:
        p = os.path.join(root, f)
        try:
            if os.path.getsize(p) > 4_000_000:
                continue
            with open(p, 'rb') as fh:
                if b'\0' in fh.read(512):
                    continue
            text = open(p, encoding='utf-8', errors='replace').read()
        except OSError:
            continue
        for m in pat.finditer(text):
            if m.group(0).rstrip('.,;:') != CANON:
                bad.append(f'{p}: {m.group(0)}')
if bad:
    print('\n'.join(bad[:10])); sys.exit(1)
PY

# t7 checker: the parsed depth-2 row contract across the fourteen dev-family
# surfaces. mode=presence asserts the exact row once per file, the stale
# blanket resource gone (any effect), adjacency to the tests/** deny and one
# shared index across files; mode=order asserts pivot < plans deny <
# skills/** allow per file (C07 AC3: position is load-bearing under
# last-match-wins).
cat >"$TMP/t7rows.py" <<'PY'
import re, sys, yaml
ROW = {"action": "edit", "resource": ".agents/plans/*/*", "effect": "deny"}
OLD_RES = ".agents/plans/**"
PIVOT = {"action": "edit", "resource": "*", "effect": "allow"}
TESTS = {"action": "edit", "resource": "tests/**", "effect": "deny"}
SKILLS = {"action": "edit", "resource": "skills/**", "effect": "allow"}
mode, files = sys.argv[1], sys.argv[2:]
def perms(path):
    m = re.match(r"^---\n(.*?)\n---\n", open(path, encoding="utf-8").read(), re.S)
    assert m, f"{path}: no YAML frontmatter"
    fm = yaml.safe_load(m.group(1)) or {}
    return (fm.get("opencode") or {}).get("permissions") or fm.get("permissions") or []
bad, idxs = [], []
for path in files:
    rows = perms(path)
    def ix(row):
        return [i for i, r in enumerate(rows) if r == row]
    h = ix(ROW)
    if len(h) != 1:
        bad.append(f"{path}: exact row {ROW} found {len(h)} times, want exactly 1")
        continue
    stale = [i for i, r in enumerate(rows)
             if r.get("action") == "edit" and r.get("resource") == OLD_RES]
    if mode == "presence":
        if stale:
            bad.append(f"{path}: blanket resource '{OLD_RES}' still on edit rows {stale} — C07 REPLACES it")
        t = ix(TESTS)
        if len(t) != 1:
            bad.append(f"{path}: tests/** deny anchor found {len(t)} times — adjacency unprovable")
        elif h[0] != t[0] + 1:
            bad.append(f"{path}: depth-2 row at {h[0]} but tests/** deny at {t[0]} — want immediately after")
        else:
            idxs.append(h[0])
    else:  # order
        p, s = ix(PIVOT), ix(SKILLS)
        if len(p) != 1 or len(s) != 1:
            bad.append(f"{path}: pivot/skills anchors not unique (pivot x{len(p)}, skills x{len(s)})")
        elif not (p[0] < h[0] < s[0]):
            bad.append(f"{path}: plans deny at {h[0]} not between the edit-'*' allow pivot {p[0]} "
                       f"and the skills/** allow {s[0]} (deny-before-pivot is dead code; the "
                       f"context allows must stay plans-path-free)")
if mode == "presence" and len(idxs) == len(files) and len(set(idxs)) > 1:
    bad.append(f"depth-2 row index differs across files: {dict(zip(files, idxs))} — C07 AC1 wants the SAME parsed index")
if bad:
    print("; ".join(bad)); sys.exit(1)
PY

# Control mutator: rewrite a copy with one of the two C07-named defects (the
# row's effect flipped to allow, or the row moved before the pivot). Refuses
# (assert) when the row is not exactly once — a control that cannot be applied
# is a harness fault, not a pass.
cat >"$TMP/t7ctl.py" <<'PY'
import re, sys, yaml
path, mode, out = sys.argv[1], sys.argv[2], sys.argv[3]
m = re.match(r"^---\n(.*?)\n---\n(.*)$", open(path, encoding="utf-8").read(), re.S)
assert m, f"{path}: no frontmatter (cannot apply control)"
fm = yaml.safe_load(m.group(1)) or {}
oc = fm.get("opencode")
target = oc if isinstance(oc, dict) and "permissions" in oc else fm
rows = target["permissions"]
i = [j for j, r in enumerate(rows)
     if r == {"action": "edit", "resource": ".agents/plans/*/*", "effect": "deny"}]
assert len(i) == 1, f"{path}: depth-2 row x{len(i)}, want exactly 1 — control not appliable"
i = i[0]
if mode == "flip-allow":
    rows[i] = dict(rows[i], effect="allow")
elif mode == "pre-pivot":
    rows.insert(0, rows.pop(i))
else:
    sys.exit(f"unknown control mode {mode}")
open(out, "w").write("---\n" + yaml.safe_dump(fm, sort_keys=False) + "---\n" + m.group(2))
PY

# t7's verdict simulator — copied VERBATIM from tests/standalone-agents/
# surface.sh (the repo's fnmatch-based policy.py) so the verdict arms ride the
# established simulator, per C07: "never a hand-rolled second matcher."
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

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 7; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t([1-5]|7)$ ]] || fail "unknown test id '$a' (expected t1..t5 or t7 — C06 was declined, no t6 arm, its number never reused)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

# --- t1: corrected runbook (C01 AC1–AC7) ----------------------------------------
if want t1; then
  [ -f "$RUNBOOK" ] || fail "t1: $RUNBOOK missing — C01 edits the dated runbook in place"

  awk '/ec\.decode/ && /-collection=""/ && /-volumeId/ {found=1} END {exit !found}' "$RUNBOOK" \
    || fail "t1.1 [C01 AC1]: no line teaches the per-volume decode form ec.decode -collection=\"\" -volumeId <vid> (C01 Phase 1: batch decode is mandatory-replaced per §R1.4)"
  bad=$(awk '/-collection=default/ && !/no-op|matches nothing/ {print NR": "$0}' "$RUNBOOK")
  [ -z "$bad" ] || fail "t1.1 [C01 AC1]: '-collection=default' sits on an instructional line — every occurrence must also carry the no-op/matches-nothing warning token: $bad"
  ok "t1.1 [C01 AC1]: per-volume ec.decode form present; -collection=default only in warning prose"

  tok "$RUNBOOK" 'aborts|first failing group' \
    "t1.2 [C01 AC2]: Phase 1 never states the batch-decode aborts-on-first-failing-group fact (§R1.4: decodes 1, aborts at 4 — why per-volumeId is mandatory)"
  tok "$RUNBOOK" 'ec\.rebuild' \
    "t1.2 [C01 AC2]: no ec.rebuild prerequisite for a missing data shard (448 pre-check, §R1.4 floor)"
  tok "$RUNBOOK" '_default' \
    "t1.2 [C01 AC2]: the _default unnamed-pool spelling is absent — §R1.4 equivalence note missing"
  python3 "$TMP/near.py" "$RUNBOOK" '(?<!\d)4(?!\d),(?<!\d)5(?!\d),(?<!\d)446(?!\d),(?<!\d)447(?!\d),(?<!\d)449(?!\d)' 'unrecoverable|RS floor' 3 \
    || fail "t1.2 [C01 AC2]: ids within ±3 lines of unrecoverable/RS floor — missing: (ids above)"
  ok "t1.2 [C01 AC2]: abort fact, ec.rebuild, _default, and 4/5/446/447/449-vs-unrecoverable all in place"

  awk '/check\.disk/ && /resurrectMissingNeedles/ {found=1} END {exit !found}' "$RUNBOOK" \
    || fail "t1.3 [C01 AC3]: no check.disk line carries -resurrectMissingNeedles (§R1.1 resurrection gate)"
  bad=$(awk '/check\.disk/ && /-apply/ && !/resurrectMissingNeedles/ {print NR": "$0}' "$RUNBOOK")
  [ -z "$bad" ] || fail "t1.3 [C01 AC3]: check.disk REPAIR line (-apply) without -resurrectMissingNeedles — it re-diagnoses instead of healing: $bad"
  tok "$RUNBOOK" 'compaction[- ]revision' \
    "t1.3 [C01 AC3]: the compaction-revision gate is not named (§R1.1: resurrection only into rev-0 replicas)"
  tok "$RUNBOOK" 'skipping readonly volume' \
    "t1.3 [C01 AC3]: the source-verified read-only skip line 'skipping readonly volume %d on %s' is absent"
  python3 "$TMP/near.py" "$RUNBOOK" 'fixReadOnly' 'EXPERIMENTAL|never' 3 \
    || fail "t1.3 [C01 AC3]: fixReadOnly is not marked EXPERIMENTAL/never-on-split-brain nearby (§R1.2)"
  tok "$RUNBOOK" 'volume\.copy' \
    "t1.3 [C01 AC3]: verdict branch vocabulary volume.copy missing (two-sided/one-sided procedure)"
  tok "$RUNBOOK" 'findMissingChunksInFiler' \
    "t1.3 [C01 AC3]: verdict branch classification via -findMissingChunksInFiler missing"
  tok "$RUNBOOK" 'revision 0|rev-0' \
    "t1.3 [C01 AC3]: the rev-0 / revision-0 branch condition is not spelled"
  ok "t1.3 [C01 AC3]: every check.disk -apply line resurrects; gate, skip line, fixReadOnly warning, all three branch tokens"

  awk '/fsck/ && /-collection logs/ {found=1} END {exit !found}' "$RUNBOOK" \
    || fail "t1.4 [C01 AC4]: no fsck line carries the literal -collection logs (fsck's -collection must match the pool)"
  bad=$(awk 'tolower($0) ~ /-collection media/ && tolower($0) !~ /caution|wrong|instead of|mistake|stale|historical/ {print NR": "$0}' "$RUNBOOK")
  [ -z "$bad" ] || fail "t1.4 [C01 AC4]: '-collection media' used as an instruction — it may only appear inside the cautionary note: $bad"
  awk 'tolower($0) ~ /media/ && tolower($0) ~ /caution|wrong|instead of|mistake|stale|historical/ {found=1} END {exit !found}' "$RUNBOOK" \
    || fail "t1.4 [C01 AC4]: the historical wrong-collection (media instead of logs) run is not recorded as a cautionary note"
  awk '/^#+ .*Phase 2/{f=1; next} /^#+ .*Phase 3/{f=0} f' "$RUNBOOK" | grep -qF '_default' \
    || fail "t1.4 [C01 AC4]: Phase 2 does not carry the _default spelling for the unnamed pool (the five unrecoverable groups)"
  ok "t1.4 [C01 AC4]: fsck collections literal-correct, cautionary note recorded, Phase 2 _default in place"

  tok "$RUNBOOK" 'argocd app sync infra-seaweedfs' \
    "t1.5 [C01 AC5]: the human argocd app sync infra-seaweedfs step is not stated (no agent grant)"
  tok "$RUNBOOK" 'automated' \
    "t1.5 [C01 AC5]: the root cause — Application has no automated: block — is not named"
  tok "$RUNBOOK" 'selfHeal' \
    "t1.5 [C01 AC5]: the services.infra.selfHeal annotation gate (§R1.6, U1) is not mentioned"
  tok "$RUNBOOK" 'RepeatedResourceWarning' \
    "t1.5 [C01 AC5]: duplicate Services warning-only / recurs-on-refresh fact missing"
  tok "$RUNBOOK" 'Applied \[maintenance\.erasure_coding\]' \
    "t1.5 [C01 AC5]: admin-log check 'Applied [maintenance.erasure_coding] settings from admin.toml' missing"
  tok "$RUNBOOK" 'relaxed placement' \
    "t1.5 [C01 AC5]: EC-churn-stops probe (placed with relaxed placement constraints) missing from the checklist"
  tok "$RUNBOOK" 'retry reading' \
    "t1.5 [C01 AC5]: Loki verification query (s3 retry reading rate → 0) missing"
  tok "$RUNBOOK" 'NoSuchKey' \
    "t1.5 [C01 AC5]: Loki verification query (NoSuchKey steady, not growing) missing"
  toki "$RUNBOOK" 'UNDEPLOYED|not deployed' \
    "t1.5 [C01 AC5]: the merged-but-UNDEPLOYED state (main 4b832237c, admin-0 from 10-25) is not stated"
  toki "$RUNBOOK" 'post[- ]?sync' \
    "t1.5 [C01 AC5]: no post-sync verification checklist anchor exists"
  ok "t1.5 [C01 AC5]: deploy-reality + 5-item post-sync checklist tokens all present"

  tok "$RUNBOOK" "2>&1 <<'EOF' \\| tee" \
    "t1.6 [C01 AC6]: no line uses the fixed 2>&1 <<'EOF' | tee ordering (a heredoc binds to the pipeline segment it is attached to — verified 2026-11-11)"
  noTok "$RUNBOOK" "\\| tee [^|]*<<'EOF'" \
    "t1.6 [C01 AC6]: broken '| tee … <<EOF' ordering survives — weed shell would receive no stdin"
  ok "t1.6 [C01 AC6]: corrected heredoc form present, broken form eliminated"

  tok "$RUNBOOK" '-nonRepairThreshold 1' \
    "t1.7 [C01 AC7]: -nonRepairThreshold 1 lost (default 0.3 refuses at up-to-46% divergence)"
  tok "$RUNBOOK" 'volume\.deleteEmpty -quietFor=24h' \
    "t1.7 [C01 AC7]: the husk-cleanup line volume.deleteEmpty -quietFor=24h lost"
  tok "$RUNBOOK" 'WEED_MAINTENANCE_ERASURE_CODING_ENABLED' \
    "t1.7 [C01 AC7]: the Phase-0 env-var name lost — the runbook no longer names what gets disabled"
  ok "t1.7 [C01 AC7]: still-valid content preserved (nonRepairThreshold, deleteEmpty, env var)"
fi

# --- t2: references/mcp-server-spec.md — card-pointer spec (C02 AC1–AC5) ---------
if want t2; then
  [ -f "$SPEC" ] || fail "t2.1 [C02 AC1]: $SPEC missing — card HhiinjT5hdi8D6fCY promises this exact path on main"
  python3 "$TMP/pathcheck.py" "$CARD_PATH" \
    || fail "t2.1 [C02 AC1]: a path-spelling of the card pointer deviates from the byte-exact '$CARD_PATH' (offenders above)"
  ok "t2.1 [C02 AC1]: $SPEC exists; every repo-wide path-spelling is byte-identical to the card's string"

  for t in '/dir/status' '/vol/status' '/dir/lookup' '/collection/info' '/api/admin' \
           '/api/files/properties' '404' '/dir/config' 'lock' 'exit 1|exits 1' '#11117' \
           'LoadClientTLS|cluster\.ps' 'stateless_http' 'httpx2' 'elicit' \
           'enable\(only=True\)|only=True' 'hivetools\.mcp' '/var/mnt' \
           'volume\.unmount' 'weed fix' 'unauthenticated'; do
    tok "$SPEC" "$t" "t2.2 [C02 AC2]: §R2 verdict coverage gap — mcp-server-spec.md never carries /$t/ (Q1–Q7 rows of RESEARCH.md §R2.8)"
  done
  ok "t2.2 [C02 AC2]: all §R2 verdict tokens (endpoints, 404-negatives, exit-code law, lock, TLS, FastMCP, build/deploy, onprem, auth) present"

  for t in 'ec8f97935' '4\.50' '>=4\.1,<5' '4\.1\.8' 'v1beta1' 'v0\.56\.0'; do
    tok "$SPEC" "$t" "t2.3 [C02 AC3]: verified pin /$t/ missing — the spec's build facts must pin to the deployed weed 4.50 + verified toolchain versions"
  done
  ok "t2.3 [C02 AC3]: pins ec8f97935 / 4.50 / >=4.1,<5 / 4.1.8 / v1beta1 / v0.56.0 all present"

  tok "$SPEC" 'RESEARCH\.md' \
    "t2.4 [C02 AC4]: no RESEARCH.md provenance line — the [T#] source labels must resolve to §R2"
  tok "$SPEC" 're-verify' \
    "t2.4 [C02 AC4]: the re-verify-on-bump standing rule (renovate 4.53.0 pending) is not stated"
  ok "t2.4 [C02 AC4]: provenance and re-verify-on-bump rule present"

  noTok "$SKILL_DIR" 'abliterated|strata|gguf' \
    "t2.5 [C02 AC5]: retired llama-swap/strata needles — live_code_grep (charts/llama-swap/tests) spans skills/ and turns those suites red"
  noTok "$SKILL_DIR" 'Bearer[[:space:]]+[A-Za-z0-9+/=._-]{10,}|token:[[:space:]]*[A-Za-z0-9+/=._-]{16,}' \
    "t2.5 [C02 AC5]: a credential-shaped literal (Bearer/token: with a value) — spec carries prose posture only, never values"
  ok "t2.5 [C02 AC5]: no retired needles, no credential literals"
fi

# --- t3: mechanics references (C03 AC1–AC6) ---------------------------------------
if want t3; then
  for f in "$ERRSIG" "$WSHELL" "$CLEC"; do
    [ -f "$f" ] || fail "t3.1 [C03 AC1]: $f missing (C03 ships the three mechanics references)"
  done
  ok "t3.1 [C03 AC1]: error-signatures.md, weed-shell.md, collections-and-ec.md all exist"

  for t in 'readDeleted' 'no entry is found in filer store' 'invalid task ID' \
           'relaxed placement' 'not enough copies' 'skipping readonly volume' \
           'error writing JSON status' 'idx references end=' 'summed delete_count' \
           'failed to stream logs/index' 'maybeReadHardLink' 'not resurrecting' \
           'Do NOT auto-repair|TWO-SIDED'; do
    tok "$ERRSIG" "$t" "t3.2 [C03 AC2]: error-signatures.md has no row for /$t/ (AC2 floor = 13 signatures from the incident's log vocabulary)"
  done
  ok "t3.2 [C03 AC2]: all 13 signature rows present in error-signatures.md"

  tok "$WSHELL" "<<'EOF' \\| tee" \
    "t3.3 [C03 AC3]: no heredoc-before-tee pattern line (<<'EOF' | tee) — the binding rule says tee goes LAST or the shell starves"
  noTok "$WSHELL" "\\| tee [^|]*<<'EOF'" \
    "t3.3 [C03 AC3]: the broken '| tee … <<EOF' form is taught — verified by experiment 2026-11-11 to feed tee, not weed shell"
  for t in 'lock' 'unlock' 'exit 1|exits 1' 'sticky' '_default' 'wildcard|matcher'; do
    tok "$WSHELL" "$t" "t3.3 [C03 AC3]: weed-shell.md never carries /$t/ (lock-first law, piped exit-code stickiness, or the collection-matcher table)"
  done
  ok "t3.3 [C03 AC3]: corrected heredoc pattern + lock/unlock + sticky exit codes + matcher table tokens"

  tok "$CLEC" '10 data shards|DATA shards' \
    "t3.4 [C03 AC4]: the decode ALL-10-DATA-shards requirement (§R1.4) is not stated"
  tok "$CLEC" '≥10|10 of 14' \
    "t3.4 [C03 AC4]: the ec.rebuild ≥10-of-14 floor is not stated"
  tok "$CLEC" 'aborts' \
    "t3.4 [C03 AC4]: the batch-decode abort fact is missing"
  tok "$CLEC" '\.vif' \
    "t3.4 [C03 AC4]: the read-only .vif persistence split (§R1.2) is not covered"
  tok "$CLEC" '840|14 min' \
    "t3.4 [C03 AC4]: the master auto-vacuum interval (840 s + jitter) is not stated (§R1.3)"
  tok "$CLEC" 'vacuum\.submit\.all' \
    "t3.4 [C03 AC4]: the guide-era phantom vacuum.submit.all is not warned as non-existent in 4.50"
  tok "$CLEC" 'delete\.emptyVault' \
    "t3.4 [C03 AC4]: the guide-era phantom delete.emptyVault is not warned as non-existent in 4.50"
  tok "$CLEC" 'minFreeSpacePercent|disk-space-low' \
    "t3.4 [C03 AC4]: the disk-space-low read-only trigger site is missing (§R1.2 five sites)"
  toki "$CLEC" 'collection' "t3.4 [C03 AC4]: collections-and-ec.md never mentions collection"
  tok "$CLEC" 'StorageClass|storage-classes|storage_classes' \
    "t3.4 [C03 AC4]: the unnamed-pool cause (CSI StorageClasses without a collection parameter) is not named"
  ok "t3.4 [C03 AC4]: EC arithmetic, read-only sites, vacuum sweep, phantoms, StorageClass cause — all present"

  for f in "$ERRSIG" "$WSHELL" "$CLEC"; do
    tok "$f" '2026-11-10-dep-seaweedfs-ec-removal\.md' \
      "t3.5 [C03 AC5]: $f must point at the dated runbook for repair sequences (DECISIONS: single normative home, no restated procedures)"
  done
  ok "t3.5 [C03 AC5]: all three files carry the runbook pointer"

  noTok "$SKILL_DIR" 'abliterated|strata|gguf' \
    "t3.6 [C03 AC6]: retired llama-swap/strata needles break the charts/llama-swap negative pins (live_code_grep spans skills/)"
  for f in "$ERRSIG" "$WSHELL" "$CLEC"; do
    tok "$f" '4\.50' "t3.6 [C03 AC6]: $f lacks the weed 4.50 pin (every source-verified fact pins to the deployed build)"
  done
  ok "t3.6 [C03 AC6]: clean negatives + 4.50 pin per file"
fi

# --- t4: SKILL.md + observability refs + probe script (C04 AC1–AC7) --------------
if want t4; then
  [ -f "$SKILL" ] || fail "t4.1 [C04 AC1]: $SKILL missing — C04 lands the entry point (written LAST in the chunk)"
  python3 - "$SKILL" "$SKILL_DIR" <<'PY' || fail "t4.1 [C04 AC1]: SKILL.md frontmatter contract violated (reason above)"
import os, re, sys
lines = open(sys.argv[1], encoding='utf-8').read().splitlines()
errs = []
if not lines or lines[0].strip() != '---':
    print('no opening --- frontmatter delimiter at line 1'); sys.exit(1)
end = next((i for i in range(1, len(lines)) if lines[i].strip() == '---'), None)
if end is None:
    print('frontmatter block never closes with ---'); sys.exit(1)
block = lines[1:end]
top = [re.match(r'^([A-Za-z_][A-Za-z0-9_-]*):[ ]?(.*)$', l) for l in block]
names = [m.group(1) for m in top if m]
if sorted(names) != ['description', 'name']:
    errs.append(f'frontmatter keys {names} — self-written skills carry exactly name + description (EXPLORE §2.1)')
cont = [l for l, m in zip(block, top) if not m and l.strip()]
if cont:
    errs.append(f'indented continuation lines in frontmatter (house pattern keeps description a single line): {cont[:2]}')
vals = {m.group(1): m.group(2).strip().strip('"\'') for m in top if m}
if vals.get('name') != os.path.basename(sys.argv[2]):
    errs.append(f"name {vals.get('name')!r} != directory name 'seaweedfs-debug'")
desc = vals.get('description', '')
if not desc:
    errs.append('description empty')
elif not re.search(r"even if the user doesn.t name this skill directly", desc):
    errs.append("description lacks the house closer 'even if the user doesn't name this skill directly'")
if errs:
    print('; '.join(errs)); sys.exit(1)
PY
  ok "t4.1 [C04 AC1]: frontmatter exactly name+description, name==seaweedfs-debug, single-line description with the house trigger closer"

  python3 - "$SKILL" "$SKILL_DIR" <<'PY' || fail "t4.2 [C04 AC2]: SKILL.md ↔ references/scripts bijection broken (reason above)"
import os, re, sys
skill = open(sys.argv[1], encoding='utf-8').read()
root = sys.argv[2]
real = set()
for sub in ('references', 'scripts'):
    d = os.path.join(root, sub)
    if os.path.isdir(d):
        real.update(f'{sub}/{f}' for f in os.listdir(d) if os.path.isfile(os.path.join(d, f)))
# AC2 fixes the completed shape at 7 files (6 references + 1 script); a
# smaller set means a C02/C03 deliverable went missing, not that the index
# is merely terse.
if len(real) < 7:
    print(f'only {sorted(real)} — the AC2 7-file set (6 references + the probe script) is incomplete'); sys.exit(1)
indexed = set(re.findall(r'(?:references|scripts)/[A-Za-z0-9._-]+', skill))
missing = [p for p in sorted(real) if os.path.basename(p) not in skill]
stale = [p for p in sorted(indexed) if p not in real and not os.path.isfile(os.path.join(root, p))]
if missing:
    print('not named in the SKILL.md index: ' + ', '.join(missing)); sys.exit(1)
if stale:
    print('index names a file that does not exist: ' + ', '.join(stale)); sys.exit(1)
PY
  ok "t4.2 [C04 AC2]: every references/ and scripts/ file is indexed, every indexed path exists (≥7 files)"

  [ -f "$ENDPOINTS" ] || fail "t4.3 [C04 AC3]: $ENDPOINTS missing"
  for t in '/dir/status' '/vol/status' '/api/admin' '/api/files/properties' '404' \
           '/status' '/dir/config' 'trailing slash' 'URL-encode|%2F' 'anonymous|auth-free'; do
    tok "$ENDPOINTS" "$t" "t4.3 [C04 AC3]: endpoints-and-probes.md never carries /$t/ (AC3: full §R2.4 table, BOTH 404-negatives, the properties trick, the auth posture)"
  done
  ok "t4.3 [C04 AC3]: endpoint table, 404-negatives, properties-trick and anonymous-posture tokens present"

  [ -f "$LOKI" ] || fail "t4.4 [C04 AC4]: $LOKI missing"
  tok "$LOKI" 'app_kubernetes_io_name="seaweedfs"' \
    "t4.4 [C04 AC4]: the stream-label fact is missing (there is NO 'app' label — LogQL selectors must use app_kubernetes_io_name)"
  toki "$LOKI" 'structured[ -]metadata' \
    "t4.4 [C04 AC4]: the pod-rides-structured-metadata matcher rule is not stated (never inside the stream selector)"
  tok "$LOKI" 'by[[:space:]]*\(pod\)' "t4.4 [C04 AC4]: no by (pod) aggregation shown"
  toki "$LOKI" 'self.?query' "t4.4 [C04 AC4]: the self-query-noise rule has no subsection — verification queries hit the very index objects stored on weed"
  toki "$LOKI" 'fresh[ -]window' "t4.4 [C04 AC4]: the fresh-window-rates wording of the self-query rule is absent (never historical totals)"
  for t in 'count_over_time' 'retry reading' 'NoSuchKey' 'max retry attempts' \
           'relaxed placement' 'idx references end=' 'not enough copies' \
           'is read only' 'error writing JSON status'; do
    tok "$LOKI" "$t" "t4.4 [C04 AC4]: loki-recipes.md lacks a query for /$t/ (AC4 carries ≥8 paste-ready queries; the chunk enumerates these)"
  done
  ok "t4.4 [C04 AC4]: label reality + structured-metadata rule + self-query-noise rule + all 9 enumerated query tokens"

  [ -f "$PROBE" ] || fail "t4.5 [C04 AC5]: $PROBE missing (DECISIONS: the bash probe ships, no Python helper)"
  bash -n "$PROBE" || fail "t4.5 [C04 AC5]: $PROBE fails bash -n — an unparseable probe is an operator hazard, not a helper"
  [ -x "$PROBE" ] || fail "t4.5 [C04 AC5]: $PROBE lacks the executable bit"
  tok "$PROBE" 'set -euo pipefail' "t4.5 [C04 AC5]: $PROBE has no set -euo pipefail — a probe that half-runs lies about health"
  tok "$PROBE" 'SW_MASTER_URL|SW_[A-Z_]*_URL' "t4.5 [C04 AC5]: $PROBE has no env-overridable base URL (SW_MASTER_URL/SW_ADMIN_URL per C04)"
  noTok "$PROBE" '\bkubectl\b|-X[[:space:]]?(POST|PUT|DELETE)|\bPOST\b|\bPUT\b|\bDELETE\b|weed shell' \
    "t4.5 [C04 AC5]: mutating/exec surface in the probe — AC5 is GET-only; mutations are human-paste blocks (no agent tier grants pod exec). Uppercase-only on purpose (prose 'put'/'post-repair' stay legal); the -X form is matched explicitly because -XPOST hides from word boundaries."
  ok "t4.5 [C04 AC5]: bash -n clean, executable, pipefail, env-overridable URLs, zero mutating verbs"

  body=$(awk 'NR==1 && /^---$/{fm=1; next} fm && /^---$/{fm=0; next} !fm' "$SKILL" | wc -l)
  [ "$body" -le 200 ] || fail "t4.6 [C04 AC6]: SKILL.md body is $body lines (> 200) — depth belongs in references/, the entry stays terse"
  tok "$SKILL" '2026-11-10-dep-seaweedfs-ec-removal\.md' \
    "t4.6 [C04 AC6]: SKILL.md does not point at the dated runbook (the repair sequence has one normative home)"
  ok "t4.6 [C04 AC6]: body ≤200 lines and the runbook pointer is present"

  noTok "$SKILL_DIR" 'abliterated|strata|gguf' \
    "t4.7 [C04 AC7]: retired needles in the finished skill dir (live_code_grep negative pins)"
  noTok 'skills-lock.json' 'seaweedfs-debug' \
    "t4.7 [C04 AC7]: the skill leaked into skills-lock.json — third-party integrity file, self-written skills never belong"
  for d in .rulesync/skills .agents/skills; do
    hits=$(grep -rnF seaweedfs-debug "$d" 2>/dev/null || true)
    [ -z "$hits" ] || fail "t4.7 [C04 AC7]: seaweedfs-debug found under $d — skills/ self-written tree only (EXPLORE §2.2: drift gate / integrity lock)"
  done
  hits=$(grep -nF seaweedfs-debug .opencode/opencode.jsonc 2>/dev/null || true)
  [ -z "$hits" ] || fail "t4.7 [C04 AC7]: .opencode/opencode.jsonc names the skill — discovery already resolves skills/, the plan forbids config edits for it"
  ok "t4.7 [C04 AC7]: clean negatives across skills-lock.json, rulesync/third-party skill dirs, and opencode config"
fi

# --- t5: rulesync registration (C05 AC1, AC2, AC4, AC5) --------------------------
if want t5; then
  for f in "$RULES_SRC" "$AGENTS"; do
    [ -f "$f" ] || fail "t5.1 [C05 AC1]: $f missing"
    python3 - "$f" <<'PY' || fail "t5.1 [C05 AC1]: $f does not list seaweedfs-debug in the self-written-skills inventory (reason above)"
import sys
lines = open(sys.argv[1], encoding='utf-8').read().splitlines()
anchor = [i for i, l in enumerate(lines) if 'self-written skills' in l]
if not anchor:
    print("no 'self-written skills' anchor line"); sys.exit(1)
# Windowed, not same-line: rulesync re-wraps the generated AGENTS.md, so the
# added name may land on a continuation line of the same bullet.
for i in anchor:
    if 'seaweedfs-debug' in '\n'.join(lines[i:i + 3]):
        break
else:
    print("'self-written skills' bullet does not name seaweedfs-debug within its first 3 lines"); sys.exit(1)
PY
  done
  ok "t5.1 [C05 AC1]: overview.md and AGENTS.md both list seaweedfs-debug in the self-written-skills bullet"

  RS=""
  if command -v rulesync >/dev/null 2>&1; then RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "t5.2: rulesync not resolvable here (PATH or npx cache) — the --check drift gate was not run (skill-surface t6 ladder precedent)"
  else
    timeout 180 $RS generate --check >"$TMP/rscheck.log" 2>&1 \
      || { tail -n 15 "$TMP/rscheck.log" >&2; fail "t5.2 [C05 AC2]: rulesync generate --check not clean — AGENTS.md is stale against the .rulesync sources (C05 must regenerate, never hand-edit)"; }
    ok "t5.2 [C05 AC2]: rulesync generate --check clean via $RS"
  fi

  hits=$(grep -rnF seaweedfs-debug skills-lock.json .rulesync/skills .agents/skills .opencode/opencode.jsonc 2>/dev/null || true)
  [ -z "$hits" ] || fail "t5.3 [C05 AC4]: seaweedfs-debug appears in a forbidden registration surface (lock file / rulesync skills / third-party skills / opencode config): $hits"
  ok "t5.3 [C05 AC4]: lock file, rulesync-owned and third-party skill dirs, and opencode config all stay clean"

  # The allow-list below carries the six pre-existing skill names because the
  # source bullet wraps: the removed side of the edit is the continuation
  # line, holding neither the anchor nor the new name.
  if git show-ref --verify --quiet refs/heads/main; then
    dl=$(git diff main...HEAD -- "$RULES_SRC" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' || true)
    if [ -n "$dl" ]; then
      bad=$(printf '%s\n' "$dl" | grep -vE 'seaweedfs-debug|self-written skills|helm-chart-creation|container-creation|llama-swap|wekan-mcp|wekan-api|wekan-board-provision' || true)
      [ -z "$bad" ] || fail "t5.4 [C05 AC5]: overview.md branch diff touches lines outside the self-written-skills bullet: $bad"
      printf '%s\n' "$dl" | grep -qF 'seaweedfs-debug' \
        || fail "t5.4 [C05 AC5]: overview.md branch diff adds no seaweedfs-debug line"
      ok "t5.4 [C05 AC5]: overview.md branch diff confined to the skills-inventory bullet and it adds the skill"
    else
      ok "t5.4 [C05 AC5]: overview.md branch diff empty (vacuous scope hold — active once C05 commits)"
    fi
  else
    skip "t5.4: no local main ref to diff against — run the scope check where main resolves"
  fi
fi

# --- t7: dev-family depth-2 plans deny (C07 AC1, AC3, AC4, AC5 + re-pin duty) ---
# Matcher-faithfulness pin (C07 "Grounded semantics", verified 2026-11-11): the
# shipped OpenCode v2.2.6 wildcard matcher is flat and whole-value — `*` matches
# ANY character INCLUDING `/` (so `**` is just two `*` wildcards, identical to
# `*`), `?` one char, match anchored at both ends; binary-extracted from
# ~/.nvm/versions/node/v26.5.0/lib/node_modules/@opencode/cli/bin/opencode.exe.
# For these patterns fnmatch behaves identically (same `*`->`.*`, whole-value
# anchor), so the verdict arms ride policy.py — the repo simulator copied
# verbatim from tests/standalone-agents/surface.sh — never a hand-rolled second
# matcher. Dependency guard: if upstream ever ships segment-scoped globs,
# `.agents/plans/*/*` silently narrows to exactly-2-segment paths and depth-3+
# bookkeeping falls through to allow — the t7.3 deny arms make that regression
# LOUD instead of silent.
if want t7; then
  for f in "${DEVFILES[@]}"; do
    [ -f "$f" ] || fail "t7.1 [C07 AC1]: $f missing — the seven dev-family sources and their seven generated mirrors are this arm's surface"
  done
  python3 "$TMP/t7rows.py" presence "${DEVFILES[@]}" \
    || fail "t7.1 [C07 AC1]: parsed row contract broken over the 7 sources + 7 mirrors — want the exact {edit, .agents/plans/*/*, deny} row once per file, immediately after the tests/** deny, at one shared index, with the blanket .agents/plans/** row gone (reason above; red until C07 dev lands the replace, green-now shape is the old row at index 4)"
  for f in "${DEVFILES[@]}"; do
    grep -qF -- '.agents/plans/*/*' "$f" \
      || fail "t7.1 [C07 AC1]: second-net literal grep finds no '.agents/plans/*/*' byte in $f — the parse passed but the literal is missing (mirrors are regenerated, never hand-edited)"
    hits=$(grep -nF -- '.agents/plans/**' "$f" || true)
    [ -z "$hits" ] || fail "t7.1 [C07 AC1]: the old blanket resource '.agents/plans/**' survives in $f — C07 REPLACES it, and a stale blanket deny anywhere in the list re-closes the plans-root deliverables (last match wins): $hits"
  done
  ok "t7.1 [C07 AC1]: depth-2 row exactly once per file across all fourteen surfaces, same parsed index, immediately after the tests/** deny; blanket resource absent (yaml parse + literal second net)"

  python3 "$TMP/t7rows.py" order "${DEVFILES[@]}" \
    || fail "t7.2 [C07 AC3]: ordering invariant broken in some dev-family file — the plans deny must sit AFTER the edit-'*' allow pivot (a deny before it is dead code under last-match-wins) and BEFORE the skills/** context allow (those allows must stay plans-path-free) — reason above"
  # Mutation controls (house style — TMP copies of the real file through the
  # same checkers; slug-stack/create-list discipline: prove the unmutated copy
  # green first, else the control is vacuously satisfied).
  for m in flip-allow pre-pivot; do
    cp "${DEVFILES[0]}" "$TMP/ctl-base.md"
    { python3 "$TMP/t7rows.py" presence "$TMP/ctl-base.md" >/dev/null 2>&1 \
      && python3 "$TMP/t7rows.py" order "$TMP/ctl-base.md" >/dev/null 2>&1; } \
      || fail "t7.2 control [harness]: the unmutated copy of ${DEVFILES[0]} already fails its own checks — control '$m' would prove nothing (t7.1 should have reddened first)"
    python3 "$TMP/t7ctl.py" "${DEVFILES[0]}" "$m" "$TMP/ctl-mut.md" \
      || fail "t7.2 control [harness]: mutation '$m' not appliable to ${DEVFILES[0]} — the depth-2 row is not exactly once (this control runs only against a compliant tree)"
    if python3 "$TMP/t7rows.py" presence "$TMP/ctl-mut.md" >/dev/null 2>&1 \
       && python3 "$TMP/t7rows.py" order "$TMP/ctl-mut.md" >/dev/null 2>&1; then
      fail "t7.2 control: the '$m' mutation slipped through — t7 must redden when the row's effect flips to allow or when it moves before the edit-'*' pivot (C07 AC3: position is load-bearing)"
    fi
  done
  ok "t7.2 [C07 AC3]: pivot < plans deny < skills/** allow holds in all fourteen files; both controls (effect->allow, row->pre-pivot) caught on TMP copies"

  # Verdict arms exactly as C07 AC4, on the agent-dev-local source AND mirror
  # (the spec's named exemplar pair). Controls are the unchanged classes AC4
  # lists, as concrete paths.
  mapfile -t VERDICTS <<EOF
edit|$RUNBOOK|allow
edit|$TICKET/STATE.json|deny
edit|$TICKET/2026-11-11-feat-seaweedfs-debug-skill.md|deny
edit|$TICKET/chunks/C01.md|deny
edit|$TICKET/FRICTION.md|deny
edit|$TICKET/DECISIONS.md|deny
edit|.agents/plans/templates/PLAN.md|deny
edit|skills/seaweedfs-debug/SKILL.md|allow
edit|.agents/notes/2026-11-10-seaweedfs-incident-findings.md|allow
edit|tests/seaweedfs-debug/surface.sh|deny
edit|AGENTS.md|deny
EOF
  for f in "${DEVFILES[0]}" "${DEVFILES[1]}"; do
    python3 "$TMP/policy.py" "$f" "${VERDICTS[@]}" \
      || fail "t7.3 [C07 AC4]: effective verdicts through the fnmatch simulator differ from AC4 on $f — the plans-root dated deliverable must fall through to allow while STATE.json / plan-of-record / chunks / FRICTION / DECISIONS / templates/PLAN.md stay deny and the unchanged controls hold (pre-C07 the root deliverable is still denied through the blanket row — designed red)"
  done
  # Control: flip ONE verdict expectation (root deliverable allow->deny) in a
  # TMP copy of the spec list — the compliant files must REJECT the flipped
  # expectation, else the verdict arm asserts nothing.
  sed '1s/|allow$/|deny/' <<EOF >"$TMP/verdicts-flip.txt"
${VERDICTS[0]}
EOF
  if python3 "$TMP/policy.py" "${DEVFILES[0]}" "$(cat "$TMP/verdicts-flip.txt")" >/dev/null 2>&1; then
    fail "t7.3 control: the flipped expectation ('$RUNBOOK' = deny) was ACCEPTED — the verdict arm is vacuous; either the depth-2 deny did not land or the simulator stopped tracking the shipped matcher"
  fi
  ok "t7.3 [C07 AC4]: root deliverable allow; STATE/plan-of-record/chunks/FRICTION/DECISIONS/templates deny; controls skills-allow, notes-allow, tests-deny, AGENTS.md-deny — on source AND mirror; flipped-expectation control caught"

  RS=""
  if command -v rulesync >/dev/null 2>&1; then RS="rulesync"
  elif npx --no-install rulesync --version >/dev/null 2>&1; then RS="npx --no-install rulesync"
  fi
  if [ -z "$RS" ]; then
    skip "t7.4: rulesync not resolvable here (PATH / npx cache ladder) — generate gate not run; its --check half is t5.2's base-green regression (S10 ladder precedent)"
  else
    timeout 180 $RS generate --check >"$TMP/t7check.log" 2>&1 \
      || { tail -n 15 "$TMP/t7check.log" >&2; fail "t7.4 [C07 AC5]: rulesync generate --check not clean — the seven dev-family mirrors must be regenerated with their sources (never hand-edit a mirror)"; }
    timeout 180 $RS generate >"$TMP/t7gen.log" 2>&1 \
      || { tail -n 15 "$TMP/t7gen.log" >&2; fail "t7.4 [C07 AC5]: rulesync generate failed"; }
    before=$(git status --porcelain)
    timeout 180 $RS generate >/dev/null 2>&1 || fail "t7.4 [C07 AC5]: second rulesync generate failed"
    after=$(git status --porcelain)
    [ "$before" = "$after" ] || fail "t7.4 [C07 AC5]: the second rulesync generate is not a no-op (sources and generated drifted — S10 idiom)"
    ok "t7.4 [C07 AC5]: generate --check clean; second generate a no-op (via $RS)"
  fi

  # Re-pin duty (C07 Tests, second file): the test wave moves
  # DEV_DEPLOY_SETTLED in board-context.sh byte-exactly onto the post-C07
  # dev-deploy matrix row; without it the t4 matrix walk reddens the instant
  # C07's permissions.md move lands. Grep-pinned so the duty cannot be skipped.
  [ -f "$BC" ] || fail "t7.5 [C07 Tests]: $BC missing"
  grep -qF -- 'everything below `.agents/plans/` root (depth-2 deny `.agents/plans/*/*`' "$BC" \
    || fail "t7.5 [C07 Tests]: $BC still carries the pre-C07 DEV_DEPLOY_SETTLED (the moved-row byte is missing) — the test-wave re-pin of the dev-deploy matrix row is a C07 Tests duty, not a dev task; t4 admits the post-C07 row byte-exactly only once this constant reads 'everything below \`.agents/plans/\` root (depth-2 deny \`.agents/plans/*/*\` ...'"
  ok "t7.5 [C07 Tests]: DEV_DEPLOY_SETTLED re-pinned in $BC to the depth-2 dev-deploy row (re-pin duty discharged; t4 engages the new byte when C07 dev moves the matrix)"
fi

printf 'PASS: seaweedfs-debug surface checks (%d ok)\n' "$checks"
