#!/usr/bin/env bash
# Sync fan-out operator runbook contract — C15 re-pin (reopen4, R8; rewrite
# #5) (2026/2026-11-cf-139-feat-argocd-webhook-sync):
# .agents/notes/2026-11-17-argocd-sync-fanout.md, re-pinned to the LANDED
# fleet-blind shape (C13+C14 landed at c95cbaabf post-rebase — every parity grep
# reads the REAL workflow/script/roster bytes, not /tmp references).
#
# What the re-pin MOVES vs the C11 (rewrite #4) suite:
#  * r1's cross-artifact leg TRANSFORMS — the workflow's 22-row env
#    enumeration is gone, so "table == workflow env names" is structurally
#    dead. The new law: the runbook's §2 table names must match the filter
#    step's selection regex AS LANDED in the workflow bytes, and that regex
#    must equal the script's PAIR_KEY_RE — runbook ⇄ filter ⇄ script, three
#    surfaces, one law (the (i-adj-1) primary guard re-expressed for R8; the
#    workflow now enumerates ZERO names and a reappearance reddens this leg).
#    §2's OWNER work (mints block, 11-row table modulo the sanctioned
#    vars./secrets. prefix drop, the §2.4 trio leg) stays byte-equal against
#    the rewrite-#4 baseline (RUNBOOK_BASE, default c95cbaabf; pre-rebase
#    ad86dd576 dangles in origin/main's rebased history) — the
#    redesign changed how the job discovers keys, not how the vault holds
#    them. §2 URL values ⇄ §6 hosts equality SURVIVES.
#  * r2 = §5's new role: the first dispatch is the de-facto live validation
#    of the engine claims the owner chose to skip probing for (STATE
#    reopen4.owner_decision) — the claim-token legs (toJSON / RUNNER_TEMP /
#    filter-count / masking-log), the 3f330df1a revert-fallback sentence,
#    the fleet-drift honesty line (expect == VAULT reality), and the two
#    RULED failed rows (proxy-local 307, proxy-backup OQ9).
#  * r3's stale-vocabulary sweep EXTENDS to the enumeration-era claims
#    (enumeration row / 22-row / static enumeration / cannot index /
#    workflow rows / pair-lockstep / categories / oracle / the vars. and
#    secrets. expression forms) — with §2.4's `secrets.ARGOCD_SYNC_TOKENS`
#    delete-check line the ONLY sanctioned ARGOCD_SYNC_ expression-form
#    occurrence, per C15 AC4.
#  * r4 = the ruled pure-discovery envelope, pinned as the DECISIONS
#    2026-11-26 words state it: blank-one-token (j)-RED / delete-one-key
#    half-pair RED / delete-BOTH-keys quiet-drop-with-count-only /
#    stray-complete-pair quiet JOIN; decommission == delete both org keys,
#    zero repo edits; §8 names the branch-protection card
#    abkP2XsbuuPuuvri6 + org-name discipline + the escape-free masking edge;
#    §7's kill-lever and §8's rotation paragraphs byte-kept from baseline.
#  * r5's command law survives AND extends to the pairs-file recipe: the
#    PATH may ride an env prefix (paths are not secrets, DECISIONS (c));
#    VALUES never ride argv, no inline JSON map, no literal JWT material in
#    any fenced block.
#  * r6 spine + preflight rows + §6 identity note survive; the Appendix is
#    now pinned byte-equal to baseline (C15: note-only tables unchanged).
#
# The path/name stay (rewrite #3's spine survived #4 and #5). AC trace
# (chunks/C15.md "## Tests"): r1[AC3] r2[AC2] r3[AC4] r4[AC5] r5[AC6] r6[AC1].
#
# Fragment-needle discipline (the shipped strip-technique, C11 r3 map): the
# dead blob name and the dead grammar strings are ASSEMBLED here from
# fragments, so this tests/ file never contains the joined literals —
# consistent with the disposal sweep's tests/-inclusive grep.
#
# Run from the repo root (or FANOUT_ROOT at a synthetic tree for
# green-shape proofs):
#   bash tests/notes/argocd-fanout-runbook.sh            # r1..r6
#   bash tests/notes/argocd-fanout-runbook.sh r2 r5      # subset
# Env: FANOUT_RUNBOOK (doc under test), MAIN_SYNC_WF / FANOUT_SCRIPT /
#      FANOUT_ROSTER (parity sources; defaults = the landed repo files),
#      RUNBOOK_BASE (rewrite-#4 baseline ref for the invariance legs;
#      default = c95cbaabf, the post-rebase C13+C14 landing tip; mapped from
#      the dangling pre-rebase ad86dd576).
set -euo pipefail

cd "${FANOUT_ROOT:-$(git rev-parse --show-toplevel)}"

RUNBOOK="${FANOUT_RUNBOOK:-.agents/notes/2026-11-17-argocd-sync-fanout.md}"
WF="${MAIN_SYNC_WF:-.forgejo/workflows/main-sync.yaml}"
FANOUT="${FANOUT_SCRIPT:-scripts/argocd-fanout.py}"
ROSTER="${FANOUT_ROSTER:-scripts/argocd-fanout.json}"
RUNBOOK_BASE="${RUNBOOK_BASE:-c95cbaabf}"
RUNBOOK_PATH_IN_GIT=".agents/notes/2026-11-17-argocd-sync-fanout.md"

# Dead-grammar fragments (spaces keep the joined literal OUT of this file;
# the legs strip-join them at run time):
BLOB_NAME="ARGOCD_SYNC_TOK""ENS"                 # the reopen2 single-blob key
CAT_GRAMMAR="cat: token"                         # the superseded record form
PASTE_NAME="tokens- paste"                       # the compose-the-paste file

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 6); do WANT["r$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^r[1-6]$ ]] || fail "unknown leg id '$a' (expected r1..r6)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

command -v python3 >/dev/null 2>&1 || fail "python3 (+pyyaml) is required for the runbook walk"

WORK=$(mktemp -d /tmp/opencode/argocd-fanout-runbook.XXXXXX)
export RB_BLOB="$BLOB_NAME"
export RB_WORKDIR="$WORK" RB_FANOUT="$FANOUT" RB_WF="$WF" RB_ROSTER="$ROSTER"

[ -f "$RUNBOOK" ] ||
  fail "$RUNBOOK missing — the runbook (rewrite #3 landed it at this path) must exist for C15 to rewrite in place"

# Rewrite-#4 baseline: the §2/§7/§8/appendix invariance legs diff the doc
# under test against these bytes (C15's "surgery, not rewrite" made testable).
git show "$RUNBOOK_BASE:$RUNBOOK_PATH_IN_GIT" > "$WORK/baseline.md" 2>/dev/null ||
  fail "cannot read the rewrite-#4 baseline (git show $RUNBOOK_BASE:$RUNBOOK_PATH_IN_GIT) — repoint RUNBOOK_BASE to the pre-C15 landing tip"
export RB_BASE="$WORK/baseline.md"

# Shared walker + parity-source reader (every r-leg imports this).
cat > "$WORK/rbcommon.py" <<'PY'
"""Section walker + landed-source helpers for the C15 runbook legs."""
import importlib.util
import json
import os
import re
import sys


def load_doc(path):
    return open(path).read()


def heads_lines(lines):
    heads = {}
    order = []
    for i, ln in enumerate(lines):
        m = re.match(r"^#{1,6}\s*(?:Section\s+)?(\d+)(?=[.:)\s—–-]|$)", ln)
        if m and int(m.group(1)) not in heads:
            heads[int(m.group(1))] = i
            order.append(i)
    return heads, order


def make_section(lines, heads):
    def section(n):
        if n not in heads:
            raise AssertionError("no numbered section %d header" % n)
        nxt = heads[n] + 1
        while nxt < len(lines):
            m = re.match(r"^#{1,6}\s*(?:Section\s+)?(\d+)(?=[.:)\s—–-]|$)", lines[nxt])
            if m and int(m.group(1)) in heads and heads[int(m.group(1))] == nxt:
                break
            nxt += 1
        return "\n".join(lines[heads[n] + 1:nxt])
    return section


def fanout_module():
    path = os.environ.get("RB_FANOUT", "scripts/argocd-fanout.py")
    spec = importlib.util.spec_from_file_location("fanout_under_test", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod, path


def sync_fanout():
    import yaml
    wf = os.environ.get("RB_WF", ".forgejo/workflows/main-sync.yaml")
    jobs = (yaml.safe_load(open(wf)) or {}).get("jobs") or {}
    return (jobs.get("sync-fanout") or {}), wf


def workflow_env_names():
    job, wf = sync_fanout()
    names = []
    for src in [job.get("env") or {}] + [s.get("env") or {} for s in (job.get("steps") or [])
                                         if isinstance(s, dict)]:
        for k in src:
            if k.startswith("ARGOCD_SYNC_"):
                names.append(k)
    return names, wf


def filter_step():
    """The landed filter step (env carrying the toJSON blobs) — R8 anatomy
    home. Anchored on the blob env KEYS, not the step name wording."""
    job, wf = sync_fanout()
    for s in (job.get("steps") or []):
        env = (s.get("env") or {}) if isinstance(s, dict) else {}
        if "SECRETS_JSON" in env or "VARS_JSON" in env:
            return s, wf
    return None, wf


def step_names():
    job, _ = sync_fanout()
    return [str(s.get("name")) for s in (job.get("steps") or [])
            if isinstance(s, dict) and s.get("name")]


def fan_out_env():
    job, _ = sync_fanout()
    for s in (job.get("steps") or []):
        if isinstance(s, dict) and "fan out" in str(s.get("name", "")).lower():
            return {k: str(v) for k, v in (s.get("env") or {}).items()}
    return {}


def pair_table(text):
    """Extract the §2 creation rows: category -> (bare URL key name, URL
    value, bare TOKEN key name). Prefix-insensitive on purpose: rewrite #4
    wrote `vars.`/`secrets.` expression forms, rewrite #5 names the bare
    Actions-UI keys (AC4 bans the prefixed forms) — the OWNER'S work is the
    same set either way, and that equality is what this extraction pins."""
    rows = {}
    for ln in text.splitlines():
        if not ln.lstrip().startswith("|"):
            continue
        cells = [c.strip().strip("`* ") for c in ln.strip().strip("|").split("|")]
        if not cells or cells[0] in ("category", "---") or set(cells[0]) <= {"-"}:
            continue
        um = re.search(r"(?<![A-Z])ARGOCD_SYNC_([A-Z0-9_]+)_URL(?![A-Z0-9_])", ln)
        tm = re.search(r"(?<![A-Z])ARGOCD_SYNC_([A-Z0-9_]+)_TOKEN(?![A-Z0-9_])", ln)
        url = re.search(r"https://[^`\s|)]+", ln)
        if um and tm and url and cells[0].replace("-", "").isalnum():
            rows[um.group(1).lower().replace("_", "-")] = (
                "ARGOCD_SYNC_%s_URL" % um.group(1),
                url.group(0).rstrip("/"),
                "ARGOCD_SYNC_%s_TOKEN" % tm.group(1),
            )
    return rows
PY

# --- r1: §2 owner-work invariance + filter-law agreement + §4 anatomy parity --------
# (C15 AC3.) The 22-row equality of the C11 suite TRANSFORMS into the three-
# surface LAW agreement: runbook table names ⇄ the landed filter's selection
# regex ⇄ the script's PAIR_KEY_RE, plus §2 URL values ⇄ §6 hosts (survives).
# The workflow carrying ZERO enumerated names is asserted too — a resurrected
# enumeration breaks the doc's own premise.
if want r1; then
  if ! python3 - "$RUNBOOK" <<'PY'
import os, re, sys

sys.path.insert(0, os.environ["RB_WORKDIR"])
import rbcommon as rb

doc = rb.load_doc(sys.argv[1])
base = rb.load_doc(os.environ["RB_BASE"])
lines = doc.splitlines()
heads, order = rb.heads_lines(lines)
section = rb.make_section(lines, heads)
blines = base.splitlines()
bheads, _ = rb.heads_lines(blines)
bsection = rb.make_section(blines, bheads)


def bad(msg):
    print("FAIL: r1: %s" % msg, file=sys.stderr)
    sys.exit(1)


sec2 = section(2)

# --- §2 owner-work invariance vs rewrite #4 (AC3: "the owner's work did NOT
# change") — the mints block byte-equal; the table equal modulo the sanctioned
# prefix drop; the §2.4 trio leg intact.
def first_block(text):
    m = re.search(r"```[a-z]*\n(.*?)```", text, re.S)
    return m.group(1) if m else ""

mint_cur, mint_base = first_block(sec2), first_block(bsection(2))
if not mint_cur or mint_cur != mint_base:
    bad("§2.1's mint block is not byte-identical to the rewrite-#4 baseline (§2 work legs byte-unchanged — the 11 `argocd account generate-token` lines are the owner's procedure; a diff here means the surgery touched owner legs)")
if mint_cur.count("generate-token") != 11:
    bad("§2.1 carries %d mint lines, expected 11 (one mcp-bot JWT per fleet cluster)" % mint_cur.count("generate-token"))

rows_cur, rows_base = rb.pair_table(sec2), rb.pair_table(bsection(2))
if len(rows_base) != 11:
    bad("the BASELINE table extracted %d rows, expected 11 — the extractor or the baseline ref is wrong" % len(rows_base))
if rows_cur != rows_base:
    only_b = {c: v for c, v in rows_base.items() if rows_cur.get(c) != v}
    only_c = {c: v for c, v in rows_cur.items() if rows_base.get(c) != v}
    bad("the §2 creation table drifted from the owner's work: baseline-side %s, doc-side %s (C15 keeps the 11 pairs EXACTLY — names modulo the sanctioned vars./secrets. prefix drop, values, and sides)" % (only_b or 'none', only_c or 'none'))
if len(rows_cur) != 11:
    bad("the §2 table names %d categories, expected 11 (both sides per category)" % len(rows_cur))

# Org placement + repo-twin warning (survives; R8 kept the placement story).
if not re.search(r"(?is)org[\s\S]{0,40}settings[\s\S]{0,40}actions", sec2):
    bad("§2 does not place the keys in the prod instance's ORG Settings → Actions (org-scoped hygiene is unchanged by R8)")
if not (re.search(r"(?i)\bvars?\b", sec2) and re.search(r"(?i)secrets?\b", sec2)):
    bad("§2 must describe BOTH kinds: 11 org VARS (URL-side) and 11 org SECRETS (TOKEN-side)")
if not re.search(r"(?is)repo[- ](side|twin)[\s\S]{0,160}(win|shadow|never|silence)|(never|not)[\s\S]{0,60}repo[- ](side|level)", sec2):
    bad("§2 lacks the single-instance repo-twin warning (a repo key of either kind WINS silently — the placement law survives R8)")

# The trio leg intact (§2.4): all three dead names, delete verbs near.
for trio in ("ARGOCD_HOOK_URL", "ARGOCD_HOOK_SECRET", "ARGOCD_SYNC_TOK" "ENS"):
    if trio not in sec2:
        bad("§2.4's moot-trio delete-check no longer names %s (the cleanup leg is owner work and byte-unchanged)" % trio)

# --- the TRANSFORMED cross-surface law (r1 map): runbook ⇄ filter ⇄ script.
mod, _ = rb.fanout_module()
fs, wf_path = rb.filter_step()
if fs is None:
    bad("%s has no filter step (name carrying 'filter') — r1's law source moved; the fleet-blind workflow must have landed before this leg can pass" % wf_path)
m = re.search(r'sel = re\.compile\("(\^[^"]+\$)"\)', str(fs.get("run", "")))
if not m:
    bad("the landed filter step carries no `sel = re.compile(\"^…$\")` selection regex — r1's law must be READ from the workflow bytes, never re-typed")
filter_pat = m.group(1)
if filter_pat != mod.PAIR_KEY_RE.pattern:
    bad("filter regex %r != the script's PAIR_KEY_RE %r — the filter and the validator must enforce ONE pair law (DECISIONS 2026-11-26 a/b); drift means the CI channel and the local channel fork" % (filter_pat, mod.PAIR_KEY_RE.pattern))

wf_names, _ = rb.workflow_env_names()
if wf_names:
    bad("the landed workflow enumerates pair env names %s — this suite's premise is the fleet-blind job (C13 deleted the rows; a resurrected enumeration invalidates §2's law-equality leg and the runbook's anatomy)" % sorted(wf_names))

selre = re.compile(filter_pat)
bad_names = sorted(n for pair in rows_cur.values() for n in (pair[0], pair[2]) if not selre.match(n))
if bad_names:
    bad("§2 names that the LANDED filter would NOT select: %s — every key the runbook tells the owner to create must match the filter's regex, or CI silently drops its cluster" % bad_names)

# Script-side acceptance: doc names through the landed validator.
env = {name: ("https://cluster.example" if name.endswith("_URL")
              else "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhIiwic3FsIjoiZG9jLW5hbWUtdmFsaWRhdGlvbiJ9.SIGDOCVa1uE")
       for pair in rows_cur.values() for name in pair if name != pair[1]}
disc = mod.discover_targets(env)
if disc is mod.NOT_CONFIGURED:
    bad("discover_targets says NOT_CONFIGURED for the doc's TOKEN names — the runbook table would create a fleet the script does not see")
got = {t["name"] for t in disc["targets"]}
if got != set(rows_cur):
    bad("runbook names discover to categories %s, table rows are %s — the underscore→hyphen law must round-trip exactly" % (sorted(got), sorted(rows_cur)))

# --- §2 URL values == §6 hosts (route truth relocated here per micro-call f).
sec6 = section(6)
hosts6 = {}
for ln in sec6.splitlines():
    if not ln.lstrip().startswith("|"):
        continue
    cells = [c.strip().strip("`* ") for c in ln.strip().strip("|").split("|")]
    if len(cells) > 1:
        mm = re.search(r"https://([a-z0-9.-]+)|^(cluster\.[a-z0-9.-]+)$", cells[1])
        if mm:
            hosts6[cells[0].strip("`* ")] = "https://" + (mm.group(1) or mm.group(2)).rstrip("/")
if len(hosts6) < 11:
    bad("§6 table exposes %d host rows in scheme-extractable form, expected 11 (the route-truth surface: runbook §6 + --check + smoke)" % len(hosts6))
vdrift = {c: (rows_cur[c][1], hosts6[c]) for c in rows_cur if c in hosts6 and rows_cur[c][1] != hosts6[c]}
if vdrift:
    bad("§2 var values drift from the §6 measured hosts: %s — the org vars ARE these values; a mismatch means the paste-hunt bug class returns" % vdrift)
missing = sorted(set(hosts6) - set(rows_cur))
if missing:
    bad("§2 carries no URL value for %s (the table must be complete for all 11)" % missing)

# --- §4 anatomy string parity against the LANDED files (C15 AC3: strings
# READ from the sources so a re-typed quote reddens here).
doc_all = doc
fs_env = {k: str(v) for k, v in (fs.get("env") or {}).items()}
fan_env = rb.fan_out_env()
wf_raw = rb.load_doc(wf_path)
mod_src = open(os.environ["RB_FANOUT"]).read()

names = rb.step_names()
for want_name in ("resolve fan-out pairs", "fan out ArgoCD syncs"):
    if want_name not in names:
        bad("%s: the LANDED workflow has no step named %r (names present: %s) — anatomy parity reads the workflow, never this file" % (wf_path, want_name, names))
    if want_name not in doc_all:
        bad("the runbook never names the landed workflow step %r (§4 anatomy must quote the steps AS LANDED — fail source: %s)" % (want_name, wf_path))

if "SECRETS_JSON" not in fs_env or "VARS_JSON" not in fs_env:
    bad("%s: the filter step env lost the blob names (found %s) — §4's anatomy parity source moved" % (wf_path, sorted(fs_env)))
for blob_expr in ("toJSON(secrets)", "toJSON(vars)"):
    if blob_expr not in wf_raw:
        bad("the landed workflow no longer serializes %s — the anatomy claim's source moved (%s)" % (blob_expr, wf_path))
    if blob_expr not in doc_all:
        bad("the runbook's §4 does not name %s (the delivered blobs are the R8 anatomy)" % blob_expr)

m = re.search(r'print\("(filter: %d keys selected)"', wf_raw)
if not m:
    bad("the landed filter's count line changed shape — r1/r2 pins must follow the FILE (%s)" % wf_path)
count_pin = m.group(1)
if count_pin not in doc_all and count_pin.replace("%d", "<N>") not in doc_all:
    bad("the runbook never quotes the filter count line — expected the landed `%s` or the documented `%s` shape (byte parity, C15 §4)" % (count_pin, count_pin.replace("%d", "<N>")))
if 'os.chmod(path, 0o600)' not in wf_raw:
    bad("the landed filter no longer chmods 0600 (%s) — the mode-duty claim's source moved" % wf_path)
if not re.search(r"(?i)0600", doc_all):
    bad("the runbook never states the pairs file's 0600 mode (C15 §4: 0600, per-job ephemeral — the filter's duty per DECISIONS (f))")
pairs_file_key = "ARGOCD_PAIRS_FILE"
if pairs_file_key not in fan_env:
    bad("%s: the fan-out step env lost %s — the channel wiring's source moved" % (wf_path, pairs_file_key))
if pairs_file_key not in doc_all:
    bad("the runbook never names the %s channel (the script reads the pairs file in CI — §2.3's variant and §4's anatomy depend on it)" % pairs_file_key)
if "pairs.json" not in doc_all or "pairs.json" not in wf_raw:
    bad("the pairs.json file name must appear in BOTH the landed workflow and the runbook (the producer↔consumer contract)")
if "RUNNER_TEMP" not in wf_raw or "RUNNER_TEMP" not in doc_all:
    bad("RUNNER_TEMP (the per-job ephemeral home of pairs.json) must be named by the landed workflow and by the runbook alike")

# The kill-lane warning + pairs line + invocation, byte-exact off the sources
# (C11 legs that survive the re-pin — §4/§7 quote them).
warn = getattr(mod, "WARN_NOT_CONFIGURED", None)
if not warn or warn not in doc_all:
    bad("the runbook never quotes the script's kill-lane warning BYTE-EXACT (§4 quote + §7 proof-of-off depend on it); landed string: %r" % warn)
p2 = re.search(r'print\("(pairs: %d targets discovered \(values never printed\))"', mod_src)
if not p2:
    bad("the landed script's --check pairs line changed shape — r1's pin reads the FILE, and the runbook quotes it")
if p2.group(1).replace("%d", "11") not in doc_all:
    bad("the runbook's expected --check output line is not the landed `pairs: 11 targets discovered (values never printed)` (byte parity, §2.3 expectation)")
inv = 'python3 scripts/argocd-fanout.py --config scripts/argocd-fanout.json --ref "$REF"'
if inv not in wf_raw:
    bad("the LANDED workflow no longer contains the pinned invocation line — r1's parity source moved; re-pin the test session side")
if "python3 scripts/argocd-fanout.py" not in doc_all:
    bad("the runbook never quotes the script path the job invokes")
if "argocd-fanout.json --ref" in doc_all and inv not in doc_all:
    bad("the runbook quotes an invocation but NOT the landed full line — a mis-typed `--ref` tail is the classic stale-doc drift; the quote must be byte-equal: %r" % inv)
print("ok: r1")
PY
  then
    fail "r1: §2 invariance / law agreement / §4 anatomy parity are violated (reason printed above)"
  fi
  ok "r1: §2.1 mints + §2.2 table + §2.4 trio byte-equal to the rewrite-#4 baseline (owner work unchanged); the table's 22 names match the LANDED filter's regex == the script's PAIR_KEY_RE and round-trip through discover_targets; the workflow enumerates ZERO names (fleet-blind); §2 URLs == §6 hosts; §4 anatomy strings (step names, blobs, filter count line, 0600, ARGOCD_PAIRS_FILE, pairs.json, RUNNER_TEMP, warning, pairs-line, invocation) byte-true against the landed workflow/script (AC3)"
fi

# --- r2: §5 = the first dispatch as the live engine-claims validation (C15 AC2) -----
if want r2; then
  if ! python3 - "$RUNBOOK" <<'PY'
import os, re, sys

sys.path.insert(0, os.environ["RB_WORKDIR"])
import rbcommon as rb

doc = rb.load_doc(sys.argv[1])
lines = doc.splitlines()
heads, _ = rb.heads_lines(lines)
section = rb.make_section(lines, heads)
sec5 = section(5)


def bad(msg):
    print("FAIL: r2: %s" % msg, file=sys.stderr)
    sys.exit(1)


# 1. The revert fallback: hash + revert verb + the one-commit/zero-impact
#    shape (C15 §5 verbatim claim — the chunk's own parenthetical wording is
#    avoided because AC4 bans it; the pinned truth is the hash + scope).
#    Post-rebase the fallback is 3f330df1a (CANONICAL MAP: old d81831446
#    dangles in rebased history — a doc that names it points a human at an
#    unreachable commit; the doc-side session mirrors the map).
if not re.search(r"(?is)revert[\s\S]{0,160}?3f330df1a|3f330df1a[\s\S]{0,160}?revert", sec5):
    bad("§5 lacks the 3f330df1a revert-fallback sentence — the owner's no-probe ruling is only honest with the one-commit fallback pinned (STATE reopen4, C15 AC2; if the doc still names the pre-rebase d81831446, the DOC side owes the map mirror)")
if not re.search(r"(?is)3f330df1a[\s\S]{0,160}?(one commit|zero cluster impact)|(one commit|zero cluster impact)[\s\S]{0,160}?3f330df1a", sec5):
    bad("§5's fallback sentence must carry the landed scope claim (one commit, zero cluster impact)")

# 2. The engine-claim legs the skipped probes would have run (C15 §5(a)):
#    each claim token must appear in §5 with its consequence (windows tolerate
#    markdown reflow — presence pins, not phrasing pins).
for pat, why in (
        (r"(?i)toJSON", "expression-green ⇒ toJSON supported on this fork build [49][50][53]"),
        (r"(?i)filter:\s*(?:<N>|\d+|%d)[\s\S]{0,40}keys?\s+selected", "filter-count green ⇒ org+repo merge delivered complete [43][44][46]"),
        (r"(?i)RUNNER_TEMP", "step-2 found the file ⇒ RUNNER_TEMP persistence across run steps [40][51]"),
        (r"(?i)(log|search)[\s\S]{0,120}(raw|mask)|(raw|mask)[\s\S]{0,120}(log|blob)", "log value-search finds nothing raw ⇒ per-value masking survives blob serialization [40]"),
):
    if not re.search(pat, sec5):
        bad("§5's first-dispatch leg list lacks the %s claim token (%s — C15 AC2: the skipped probe legs BECOME these expectations)" % (pat, why))

# 3. Fleet-drift honesty: expected == VAULT reality, count = inventory/audit,
#    never softened into "the fan-out alerts on drift" (C15 dev note).
if not re.search(r"(?i)vault[\s\S]{0,60}reality|reality[\s\S]{0,40}vault", sec5):
    bad("§5 lacks the fleet-drift honesty line (the expected targets=N EQUALS VAULT REALITY — C15 §5/AC2)")
if not re.search(r"(?is)(not|never)[\s\S]{0,40}repo\s+(list|table|number)", sec5):
    bad("§5 must say the count expectation is NOT a repo list (the drift line's whole point)")
if not re.search(r"(?i)(log|count)[\s\S]{0,120}(inventory|audit)|(inventory|audit)[\s\S]{0,120}(log|count)", sec5):
    bad("§5 must point at the log/count as the fleet audit (pure discovery — no membership list exists to diff)")
if re.search(r"(?i)(fan-?out|the job) (alerts|warns|red)s? on drift", doc):
    bad("the runbook claims the fan-out ALERMS on clean drift — pure discovery it does NOT (count-only by ruling; C15 dev note: state the opposite plainly once)")

# 4. The two RULED failed rows survive unchanged (C15 §5(a)).
pl = [ln for ln in lines if "proxy-local" in ln and "307" in ln]
if not pl:
    bad("no line pairs proxy-local with 307 — the landed structural finding is a RULED expected-failed row (§5/§6), unchanged by R8")
if not re.search("(?i)(fail|expected|red|ruled|structural)", " ".join(pl)):
    bad("the proxy-local 307 rows never say it audits FAILED by ruling — expectation wording required (§5 smoke list)")
pb = [ln for ln in lines if "proxy-backup" in ln and re.search(r"(?i)fail", ln)]
if not pb:
    bad("no line pairs proxy-backup with a fail expectation (the OQ9 posture, unchanged by R7/R8)")

# 5. (b)/(c)/(d): the pre-check legs survive with the pairs-file variant added.
if "ARGOCD_PAIRS_FILE" not in sec5:
    bad("§5(b) lacks the pairs-file variant of the pre-check recipe (C15: (b) gains the file-channel form)")
if not re.search(r"(?i)--dry-run", sec5):
    bad("§5 dropped the --dry-run live leg (GETs only — the reachability proof)")

# 6. CLI-surface truth: the landed script exposes exactly the four flags and
#    the runbook must not advertise a CLI pairs flag (DECISIONS (c)).
mod_src = open(os.environ["RB_FANOUT"]).read()
flags = set(re.findall(r'add_argument\("--([a-z-]+)"', mod_src))
if flags != {"config", "ref", "check", "dry-run"}:
    bad("the landed script's flag surface is %s, expected exactly config/ref/check/dry-run — r2's CLI pin must follow the FILE" % sorted(flags))
if re.search(r"--pairs", doc):
    bad("the runbook advertises a --pairs CLI flag — the R8 channel is the ARGOCD_PAIRS_FILE ENV var, the argparse surface is frozen (DECISIONS (c))")
print("ok: r2")
PY
  then
    fail "r2: §5's first-dispatch-as-validation contract is violated (reason printed above)"
  fi
  ok "r2: 3f330df1a revert-fallback sentence (hash + one-commit/zero-impact scope); the four engine-claim tokens (toJSON / filter-count / RUNNER_TEMP / masking-log) as enumerated first-dispatch legs; the fleet-drift honesty line (vault reality, not a repo list, count-as-audit) with NO alert-on-drift softening; the two RULED failed rows intact; §5(b) carries the pairs-file variant; the landed flag surface is four and no --pairs flag is advertised (AC2)"
fi

# --- r3: stale-vocabulary sweep — enumeration-era claims die (C15 AC4) --------------
if want r3; then
  if ! python3 - "$RUNBOOK" "$RB_BLOB" "$CAT_GRAMMAR" "$PASTE_NAME" <<'PY'
import os, re, sys

runbook, blob = sys.argv[1], sys.argv[2]
cat_grammar = "".join(sys.argv[3].split())
paste_name = "".join(sys.argv[4].split())
doc = open(runbook).read()
lines = doc.splitlines()


def bad(msg):
    print("FAIL: r3: %s" % msg, file=sys.stderr)
    sys.exit(1)


# Kept dead-mechanics needles (joined forms arrive from fragments so THIS
# file never carries the literals — the disposal sweeps stay honest):
NEEDLES = [
    (cat_grammar, "the superseded blob record grammar"),
    (paste_name, "the compose-the-paste artifact"),
    ("::warning::sync-fanout not configured (org-level", "the SUPERSEDED warning wording (the script's own line — read by r1 — replaced the shell-guard text)"),
    ("[26]", "the per-line masking citation — the blob design that needed it is dead (one honest native-masking sentence, no [26] framing)"),
]
for pat, why in NEEDLES:
    if pat in doc:
        bad("the runbook still carries %r (%s) — dead mechanics are deleted, not softened (AC4)" % (pat, why))

# C15 AC4 + the launch brief's enumeration-era additions. Fragment needles,
# file-wide, with the §2.4 delete-check exemption for the expression forms.
for pat, why in (
        (r"(?i)newline[- /]?(delimited|record|grammar|form|style|lines)", "the newline-records ruling (OQ8 mechanics died with the blob)"),
        (r"(?i)comma[- ]?(separated|delimited)", "the delimiter-tolerance story (parser died with the blob)"),
        (r"(?i)per[- ]line (mask\w*)[^.\n]{0,80}(holds|verif|granular|wins|guarante|proof|ruling)|(verif|re-weigh)[^.\n]{0,40}per[- ]line|per[- ]line masking granularity", "AFFIRMING per-line masking (only the sentence calling the claim MOOT was ever allowed)"),
        (r"(?i)\bone (secret|vault)\b|single (secret|vault)\b|\bONE secret\b", "the ONE-secret phrasing (the vault holds per-cluster PAIRS)"),
        # enumeration-era claims (C15's sweep); multi-word needles use \s+ so a
        # markdown line-wrap cannot dodge them:
        (r"(?i)enumeration\s+rows?", "an enumeration-row claim — R8 deleted the rows; the script's own 'enumeration keys' MESSAGE phrase is exempt (it stays byte-true, quoted via r1's parity legs, and never says 'row')"),
        (r"(?i)22\s+org\s+pair\s+names|\b22[\s-]+rows?\b", "a workflow-row-count claim — the fleet-blind job carries none (a VAULT key count like '22 keys' is legitimate owner-work wording)"),
        (r"(?i)static\s+enumeration|static\s+rows|static[\s-]+map", "a static-enumeration claim survives — R8 retired it with the rows"),
        (r"(?i)cannot\s+index", "the refuted [21][25] indexing-premise claim — source-refuted, DECISIONS 2026-11-26"),
        (r"(?i)workflow\s+(enumeration\s+)?rows?", "a workflow-rows claim — fleet membership is vault-only, zero repo edits ever"),
        (r"(?is)(org\s+pair|key\s+pair|decommission|removing)[\s\S]{0,80}?(lockstep|same\s+release)|(lockstep|same\s+release)[\s\S]{0,80}?(org\s+pair|key\s+pair|workflow)", "a pair↔rows lockstep claim survives — micro-call (d) died with the rows (the tracked_repo↔annotations lockstep law is a DIFFERENT sentence and stays)"),
        (r"(?i)\bcategories\b", "the plural membership token — the declined oracle vocabulary is banned file-wide (pure discovery names this 'the fleet'; singular 'category' as the derivation token stays fine)"),
        (r"(?i)\boracle\b", "the declined membership-oracle vocabulary is banned file-wide — the branch-protection CARD is the named backstop, not an 'oracle'"),
):
    mm = re.search(pat, doc)
    if mm:
        bad("the runbook matches the banned pattern %r (%s) at: %r (AC4)" % (pat, why, doc[max(0, mm.start()-40):mm.end()+40]))

# Expression forms: the §2.4 delete-check line naming the dead blob key is
# the ONLY sanctioned ARGOCD_SYNC_ expression form in the file (AC4).
for i, ln in enumerate(lines, 1):
    if re.search(r"(?i)(vars|secrets)\.ARGOCD_SYNC_", ln):
        if "ARGOCD_SYNC_TOK" "ENS" not in ln:
            bad("line %d uses the %r expression form outside the sanctioned §2.4 delete-check line — rewrite #5 names the bare Actions-UI keys (the job selects them from the delivered map; no expression references a pair key any more): %r" % (i, re.search(r"(?i)(vars|secrets)\.ARGOCD_SYNC_[A-Za-z0-9_]*", ln).group(0)[:40], ln.strip()[:120]))

# The moot TRIO (unchanged discipline): hook pair names §2-only; the blob
# name exactly ONCE, on a line that also says delete.
def section_of(doc, n):
    heads = []
    lines_ = doc.splitlines()
    for i, ln in enumerate(lines_):
        m = re.match(r"^#{1,6}\s*(?:Section\s+)?(\d+)(?=[.:)\s—–-]|$)", ln)
        if m:
            heads.append((i, int(m.group(1))))
    bounds = []
    for idx, (i, nn) in enumerate(heads):
        j = heads[idx + 1][0] if idx + 1 < len(heads) else len(lines_)
        bounds.append((nn, "\n".join(lines_[i:j])))
    for nn, body in bounds:
        if nn == n:
            return body
    return ""


blob_lines = [i for i, ln in enumerate(lines) if blob in ln]
if len(blob_lines) != 1:
    bad("the dead blob name %r appears on %d lines, expected EXACTLY the one §2.4 delete-check line (AC4: named only as a key to remove)" % (blob, len(blob_lines)))
if blob_lines:
    i = blob_lines[0]
    window = "\n".join(lines[max(0, i - 3):i + 2])  # wrapping may split the verb and the key
    if not re.search(r"(?i)delete|remove|absence", window):
        bad("the single blob-name occurrence has no delete/remove/absence verb within its 3-line context (the sanctioned §2.4 mention shape): %r" % lines[i][:120])
for nn in (1, 3, 4, 5, 6, 7, 8):
    if "ARGOCD_HOOK" in section_of(doc, nn):
        bad("section %d mentions ARGOCD_HOOK_* keys — the moot pair is nameable ONLY in §2's delete-check (the trio discipline)" % nn)

# No webhook-creation tells (rewrite #3's spine survives).
if re.search(r"(?i)add webhook|settings\s*(→|->)\s*web ?hooks", doc):
    bad("a webhook-creation UI path survives (R1 option (c): the job IS the webhook; creation steps stay barred)")
print("ok: r3")
PY
  then
    fail "r3: stale vocabulary survives in the runbook (reason printed above)"
  fi
  ok "r3: zero hits for the kept dead mechanics (cat:token / tokens-paste / old-warning / [26] / newline-comma / per-line-masking / one-secret) AND the enumeration-era claims (enumeration row / 22-row / static enumeration / cannot index / workflow rows / pair-lockstep / categories / oracle / vars.-secrets. expression forms); the §2.4 delete-check line is the single sanctioned ARGOCD_SYNC_* expression form; the blob name sits once on a delete line; no webhook-creation tells (AC4)"
fi

# --- r4: the ruled pure-discovery envelope, pinned as contract (C15 AC5) -------------
# DECISIONS 2026-11-26 (1)-(4): half-delete RED / both-deleted QUIET (count is
# the only signal — asserted as DESIGNED, never hedged) / blanked-pair (j)-RED /
# stray-complete-pair QUIET JOIN. Plus §7's kill lever and §8's rotation
# paragraphs byte-kept from the rewrite-#4 baseline, and the carded backstop.
if want r4; then
  if ! python3 - "$RUNBOOK" <<'PY'
import os, re, sys

sys.path.insert(0, os.environ["RB_WORKDIR"])
import rbcommon as rb

doc = rb.load_doc(sys.argv[1])
base = rb.load_doc(os.environ["RB_BASE"])
lines = doc.splitlines()
heads, _ = rb.heads_lines(lines)
section = rb.make_section(lines, heads)
blines = base.splitlines()
bheads, _ = rb.heads_lines(blines)
bsection = rb.make_section(blines, bheads)

sec2, sec7, sec8 = section(2), section(7), section(8)
envelope = sec2 + "\n" + sec7 + "\n" + sec8


def bad(msg):
    print("FAIL: r4: %s" % msg, file=sys.stderr)
    sys.exit(1)


# --- the exact lever/envelope triad (C15 §2 closing + §7/§8):
# (a) blanking a token (value present, "") ⇒ (j) RED while configured
if not re.search(r"(?is)blank[\s\S]{0,400}?(\(j\)|\bRED\b)|\(\(?j\)?\)[\s\S]{0,400}?blank", envelope):
    bad("the doc never states that BLANKING a token (present-but-empty value) is (j)-RED while the fleet is configured — ruling (3) of the OQ-A answer")
# (b) deleting ONE key ⇒ half-pair RED naming the category
if not re.search(r"(?is)(one|single|one-sided)[\s\S]{0,200}?(key|side)[\s\S]{0,250}?(half[- ]pair|RED[\s\S]{0,120}?categor|categor[\s\S]{0,120}?RED)|half[- ]pair[\s\S]{0,250}?(RED|naming)", envelope):
    bad("the doc never states that deleting ONE side leaves a half-pair that is config RED naming the category until the twin follows — ruling (1); the runbook's §7 lever truth post-C14")
# (c) deleting BOTH ⇒ quiet drop, count-only signal, BY DESIGN
if not re.search(r"(?is)(both|two)[\s\S]{0,120}?keys?[\s\S]{0,400}?(silent|vanish|quiet|leaves? discovery|count[\s\S]{0,80}?(only|audit))|(silent|quiet|count-only|leaves? discovery|the (only|sole) signal)[\s\S]{0,400}?(both|decommission|clean delete)", envelope):
    bad("the doc never states the ruled QUIET class: deleting BOTH org keys retires the cluster silently, the summary count being the only signal, by design — ruling (2); the drift honesty must not be softened, nor this state claimed loud")
# (d) a stray COMPLETE pair joins silently
if not re.search(r"(?is)stray[\s\S]{0,250}?join|join[\w]* (the fleet )?silently|completing? a valid pair[\s\S]{0,120}?(is|enables|joins)", envelope):
    bad("the doc never states the stray-pair mirror: a complete valid pair JOINS silently — ruling (4) (and creating a pair IS the enablement leg)")

# Anti-claims (the envelope is RULED both ways — a doc may not ALSO teach the
# inverse of a quiet class; C15 dev note: the honesty must not soften, and
# half-states may not be called quiet):
if re.search(r"(?is)(both|clean)[\s\S]{0,80}?delet\w+[\s\S]{0,60}?\b(RED|loud)\b", envelope):
    m = re.search(r"(?is)(both|clean)[\s\S]{0,80}?delet\w+[\s\S]{0,60}?\b(RED|loud)\b", envelope)
    bad("the doc calls the CLEAN both-key delete RED/loud somewhere — ruling (2) pins it QUIET (the count is the only signal); the envelope sentence may list the half-state's RED only at a wider distance: %r" % envelope[max(0, m.start()-40):m.end()+40])
if re.search(r"(?is)(one|single)[\s\S]{0,60}?key[\s\S]{0,120}?(quiet|silent|vanish)", envelope):
    m = re.search(r"(?is)(one|single)[\s\S]{0,60}?key[\s\S]{0,120}?(quiet|silent|vanish)", envelope)
    bad("the doc calls a ONE-key delete quiet/silent — ruling (1): a half-pair is config RED, never a quiet drop (only blank-everything and both-key deletes are quiet): %r" % envelope[max(0, m.start()-40):m.end()+40])

# --- §7: decommission == delete both org keys, zero repo edits (AC5 leg) ----------
if not re.search(r"(?i)decommission[^.]{0,220}(delete both|both (org )?keys?)|(delete both|removing both|both (org )?keys?)[^.]{0,220}(decommission|retire)", sec7):
    bad("§7's decommission leg must equal 'delete BOTH org keys — that IS the decommission' (C15 §7; the runbook suite fails the lockstep-era wording)")
if not re.search(r"(?i)(no PR|zero PR|no repo edit|zero repo edit|no JSON line|never a workflow edit)", sec7):
    bad("§7's decommission leg lacks the zero-repo-edits clause (the whole point of pure discovery: fleet ops never touch git)")

# --- §7 kill lever byte-kept from baseline (C15 §7: 'lever byte-kept') --------------
lever = re.search(r"(?ms)^1\. \*\*The kill lever.*?(?=^2\. )", bsection(7))
if not lever:
    bad("cannot locate the baseline §7.1 kill-lever paragraph in the rewrite-#4 doc — the byte-keep pin's source is broken")
elif lever.group(0).rstrip() not in sec7:
    bad("§7's kill-lever paragraph is NOT byte-kept from rewrite #4 (C15 §7: the token-side lever claim was verified still-true — zero text change; the blob world delivers the identical warning)")

# --- §8: carded backstop + org-write law + rotation byte-kept ----------------------
if "abkP2XsbuuPuuvri6" not in sec8:
    bad("§8 does not name the branch-protection follow-up card abkP2XsbuuPuuvri6 — under pure discovery it is the NAMED substitute for the declined membership guard (C15 AC5; STATE reopen4)")
if not re.search(r"(?i)branch[- ]protection", sec8):
    bad("§8 never names branch protection as the lever beside the card id")
if not re.search(r"(?is)(org[\s\S]{0,50}?actions\s+write|write\s+(at|in)\s+the\s+org)[\s\S]{0,120}?fleet|(fleet|membership)[\s\S]{0,80}?org[\s\S]{0,40}?write", sec8):
    bad("§8 lacks the org-write-equals-fleet-config law (the ruled consequence of pure discovery)")
rot = re.search(r"(?ms)^- \*\*Rotation is PER KEY\*\*.*?(?=^- )", bsection(8))
if not rot:
    bad("cannot locate the baseline §8 rotation bullet — the byte-keep pin's source is broken")
elif rot.group(0).rstrip() not in sec8:
    bad("§8's per-key rotation bullet is NOT byte-kept from rewrite #4 (C15 §8: rotation unchanged)")

# --- masking edge honesty (C15 §8) -------------------------------------------------
if not re.search(r"(?i)(escape[- ]free|JSON[- ]escaped)[^.]{0,200}(mask|value)|(mask\w*)[^.]{0,200}(escape|charset|character set)", sec8):
    bad("§8 lacks the masking-edge honesty line (JSON-escaped values don't match the masker — keep values escape-free, RESEARCH [30][31])")
if not re.search(r"(?i)\[30\]\[31\]|\[31\]\[30\]|escape-free", sec8):
    bad("§8's charset rule must cite the escape-free shape source ([30][31]) or name the charset law")

# No pending markers (posture stated as ANSWERS, not hedges — C15 AC5).
if re.search(r"(?i)pending owner|owner (decision|call) (pending|open)|to be (decided|ruled)|oracle alternative|alternatives (considered|weighed)", doc):
    bad("an unresolved/hedged posture marker survives — the OQ-A round is ANSWERED; §2/§7/§8 state rulings, no oracle alternatives may be mentioned (AC5)")
print("ok: r4")
PY
  then
    fail "r4: the pure-discovery envelope or a byte-kept posture is violated (reason printed above)"
  fi
  ok "r4: the ruled envelope pinned as contract — blanked-token (j)-RED, one-key-delete half-pair RED, BOTH-keys-delete QUIET with the count as the only signal, stray-complete-pair QUIET JOIN; §7 decommission == delete-both-keys with a zero-repo-edits clause; §7.1 kill lever + §8 rotation byte-kept from the rewrite-#4 baseline; §8 names the card abkP2XsbuuPuuvri6 + org-write-is-fleet-config + the escape-free masking edge; no hedged posture markers (AC5)"
fi

# --- r5: human-executed markers + command law + the pairs-file recipe (C15 AC6) ------
if want r5; then
  if ! python3 - "$RUNBOOK" <<'PY'
import os, re, sys

doc = open(sys.argv[1]).read()
lines = doc.splitlines()


def bad(msg):
    print("FAIL: r5: %s" % msg, file=sys.stderr)
    sys.exit(1)


if not re.search(r"(?i)human[- \t]executed", "\n".join(lines)):
    bad("r5: no human-executed marker anywhere (the doc's own law: this repo never applies; every leg is human-owned)")

MARK = re.compile(r"(?i)\bhuman\b|\bowner (runs|executes|pastes|mints|performs|deletes|checks|creates|blanks|removes)\b|\byou (run|paste|mint|create)\b")
in_fence = False
fence_start = 0
blocks = []
for i, ln in enumerate(lines):
    if re.match(r"^\s*```", ln):
        if not in_fence:
            in_fence, fence_start = True, i
        else:
            in_fence = False
            blocks.append((fence_start, i))
if in_fence:
    bad("r5: unterminated code fence at line %d" % (fence_start + 1))
if not blocks:
    bad("r5: the runbook has no fenced command blocks — the procedure must be copy-pasteable")


def head_before(pos):
    h = ""
    for ln in lines[:pos]:
        if re.match(r"^#{1,6}\s", ln):
            h = ln
    return h


for a, b in blocks:
    body = lines[a + 1:b]
    if not any(l.strip() for l in body):
        continue
    context = "\n".join(lines[max(0, a - 12):a]) + "\n" + head_before(a)
    if not MARK.search(context):
        bad("r5: fenced block at line %d (`%s`...) has no human-executed marker in its heading or the 12 lines before it (command law survives C15 unchanged)" % (a + 1, body[0].strip()[:60]))
    for j, l in enumerate(body, start=a + 2):
        if re.search(r"\bkubectl\b", l) or re.search(r"\bhelm (install|upgrade)\b", l) \
           or re.search(r"\bgit push origin\b", l) or re.search(r"argocd app sync", l):
            bad("r5: line %d is a repo-mutating apply command in a fence (%s) — this repo NEVER applies" % (j, l.strip()[:80]))
        # argv-leak forms (C11 law, extended by C15 AC6 to the pairs-file
        # recipe): env(1) KEY=value puts values in a ps-visible argv; an
        # inline ARGOCD_SYNC_* assignment feeds the same leak; and a
        # PATH-valued ARGOCD_PAIRS_FILE= prefix is legal ONLY as a path —
        # an inline JSON map or JWT material in it is the values-in-argv
        # class the recipe exists to avoid (DECISIONS (c): paths are not
        # secrets, values are).
        if re.search(r"\benv\s+[A-Z][A-Z0-9_]*=", l):
            bad("r5: line %d uses the forbidden `env KEY=value cmd` shape — the plan pins the source-then-run recipe because this form puts values in a ps-visible argv" % j)
        if re.search(r"^[ \t]*ARGOCD_SYNC_[A-Z0-9_]*=.*\b(python3|argocd-fanout)", l):
            bad("r5: line %d assigns an ARGOCD_SYNC_* inline before the command — the pinned recipe is export-into-file + source pairs.env (or the dumped pairs FILE); values never ride the command line" % j)
        if re.search(r"ARGOCD_PAIRS_FILE=\S*(\{|eyJ|://)", l):
            bad("r5: line %d gives ARGOCD_PAIRS_FILE anything but a plain path (%s) — the file-channel recipe must dump the exported pairs to a temp JSON first; inlining a map or a value defeats the whole recipe (C15 AC6)" % (j, l.strip()[:80]))
        if "eyJ" in l:
            bad("r5: line %d carries literal JWT material in a fenced command (%s) — examples use placeholders (<paste-dev-jwt>), never real-looking tokens" % (j, l.strip()[:60]))

if "source pairs.env" not in doc.replace('"', "").replace("'", ""):
    bad("r5: the sourced-recipe form (write pairs.env with export lines → source pairs.env → run) is the PINNED local invocation shape and appears nowhere (AC6)")
# The pairs-file variant of the recipe (C15 §2): a dump of the exported
# pairs into a temp JSON, then ARGOCD_PAIRS_FILE=<path> --check — never
# values in argv (the fence scan above polices that).
if not re.search(r"(?is)startswith\(.?ARGOCD_SYNC_.{0,400}ARGOCD_PAIRS_FILE", doc):
    bad("r5: the pairs-file variant of the --check recipe is missing — C15 §2 pins it (python3 -c dump of the exported ARGOCD_SYNC_* names into a temp JSON, then ARGOCD_PAIRS_FILE=… --check)")
print("ok: r5")
PY
  then
    fail "r5: the command law is violated (reason printed above)"
  fi
  ok 'r5: every command block human-marked; zero apply-verbs; no "env KEY=value", no inline ARGOCD_SYNC_* assignment, no JSON/JWT material in any ARGOCD_PAIRS_FILE prefix or fence line; the source pairs.env recipe AND the dumped-pairs-file variant are both present (AC6)'
fi

# --- r6: structure + §6 header note + roster identity (C15 AC1) ----------------------
if want r6; then
  if ! python3 - "$RUNBOOK" <<'PY'
import json, os, re, sys

sys.path.insert(0, os.environ["RB_WORKDIR"])
import rbcommon as rb

lines = open(sys.argv[1]).read().splitlines()
base = rb.load_doc(os.environ["RB_BASE"]).splitlines()


def bad(msg):
    print("FAIL: r6: %s" % msg, file=sys.stderr)
    sys.exit(1)


seq = []
for ln in lines:
    m = re.match(r"^#{1,6}\s*(?:Section\s+)?(\d+)(?=[.:)\s—–-]|$)", ln)
    if m and int(m.group(1)) not in seq:
        seq.append(int(m.group(1)))
if seq != list(range(1, 9)):
    bad("r6: numbered section headers are %s, expected exactly 1..8 in order (rewrite #5 keeps the spine — surgery, not restructure)" % seq)
bseq = []
for ln in base:
    m = re.match(r"^#{1,6}\s*(?:Section\s+)?(\d+)(?=[.:)\s—–-]|$)", ln)
    if m and int(m.group(1)) not in bseq:
        bseq.append(int(m.group(1)))
if seq != bseq:
    bad("r6: section set drifted from the baseline (%s vs %s)" % (seq, bseq))
if not any(re.match(r"^#{1,6}\s*Appendix", ln, re.I) for ln in lines):
    bad("r6: no Appendix heading (the note-only anomaly rows ride it)")

CATS = {"dev", "gpu", "gpu-ai", "grow", "home", "infra", "media", "monitoring",
        "proxy-local", "proxy-backup", "proxy-remote"}
rows = set()
for ln in lines:
    if ln.lstrip().startswith("|"):
        first = [c.strip() for c in ln.strip().strip("|").split("|")][0].strip("`* ")
        if first in CATS:
            rows.add(first)
        if first in ("backups", "personal"):
            bad("r6: a preflight row for %s — no-root-app categories stay off every table" % first)
if len(rows) < 11:
    bad("r6: preflight table names %d of 11 categories (the route-truth surface lives HERE + --check + smoke)" % len(rows))

# §6 header note (the org-var identity line — survives rewrite #5).
def sec_slice(ls, n):
    i = next((k for k, ln in enumerate(ls) if re.match(r"^#{1,6}\s*%d(?=[.:)\s—–-]|$)" % n, ln)), None)
    if i is None:
        bad("r6: no section %d heading" % n)
    j = next((k for k in range(i + 1, len(ls)) if re.match(r"^#{1,6}\s*\d", ls[k])), len(ls))
    return ls[i:j]


sec6 = sec_slice(lines, 6)
note = any(("host" in ln.lower() or "value" in ln.lower())
           and ("org var" in ln.lower() or "ARGOCD_SYNC" in ln)
           for ln in sec6)
if not note:
    bad("r6: §6 lacks the header note that the table values ARE the org VARS (§2) — the route-truth doctrine lives here + --check + smoke")

# The Appendix is note-only and unchanged by C15: byte-equal to baseline.
def appendix(ls):
    i = next((k for k, ln in enumerate(ls) if re.match(r"^#{1,6}\s*Appendix", ln, re.I)), None)
    return "\n".join(ls[i:]) if i is not None else ""


if appendix(lines) != appendix(base):
    bad("r6: the Appendix drifted from the rewrite-#4 baseline — C15 keeps the note-only tables (public-A-record anomaly, home drift, [P2] runner-vantage matrix) byte-unchanged")

# Roster five-globals identity (C15 note: the roster stays exactly the five;
# the doc still names it and never claims endpoints).
roster = json.load(open(os.environ.get("RB_ROSTER", "scripts/argocd-fanout.json")))
if set(roster) != {"allowed_refs", "tracked_repo", "settle_seconds",
                   "target_timeout_seconds", "parallel_workers"}:
    bad("landed roster keys are %s (the five globals expected) — the parity source moved under the suite" % sorted(roster))
if "scripts/argocd-fanout.json" not in "\n".join(lines):
    bad("r6: the runbook never names the roster JSON (it still exists as the globals home)")
if not re.search(r"(?i)five globals", "\n".join(lines)):
    bad("r6: the runbook lost the roster five-globals identity sentence (C15 keeps §1's globals note; the file lists NO fleet)")
if re.search(r"(?i)roster[^.\n]{0,60}(11|targets|list of categories|endpoint list)", "\n".join(lines)):
    bad("r6: the runbook claims the roster carries endpoints — the delivered vault map IS the fleet; the roster is five globals")
print("ok: r6")
PY
  then
    fail "r6: the runbook structure is wrong (reason printed above)"
  fi
  ok "r6: sections 1..8 + appendix (spine identical to baseline), all 11 preflight rows, §6 carries the org-vars identity note, the Appendix table is byte-equal to rewrite #4, and the roster five-globals identity sentence stands (AC1)"
fi

rm -rf "$WORK"
printf 'PASS: argocd sync-fanout runbook contract checks (%d ok)\n' "$checks"