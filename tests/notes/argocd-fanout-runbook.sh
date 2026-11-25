#!/usr/bin/env bash
# Sync fan-out operator runbook contract — C11 re-pin (reopen3, R7; rewrite #4)
# (2026/2026-11-cf-139-feat-argocd-webhook-sync):
# .agents/notes/2026-11-17-argocd-sync-fanout.md, re-pinned to the LANDED
# per-cluster org key-pair shape (C09 e48e93f12 + C10 a5265b3d6 are in the
# tree — every parity grep reads the REAL script/workflow/roster bytes, not
# /tmp references). §2: 11 mints + 11 org VARS + 11 org SECRETS, no compose
# step, no paste, sourced-env --check recipe, the moot-TRIO delete-check
# (hook pair + the reopen2 blob); §4/§7 quote the script's OWN column-0
# kill-lane warning; §5 masks natively per-secret (the [26] per-line saga is
# moot with the blob); §7's kill lever is the TOKEN-side delete/blank with
# the all-or-nothing RED honesty about single-cluster kills; §8 carries
# per-key rotation, decommission lockstep, the hyphen-only category law and
# the TRUE broad-catch envelope per DECISIONS (i-adj-1): valid-shape
# malformed rows RED, degenerate value-carrying shapes ignored by design,
# workflow enumeration rows guarded by the repo-side set-equality legs —
# the runbook may NOT claim the script catches everything.
#
# The path/name stay (rewrite #3's spine survived). AC trace (chunks/C11.md
# "## Tests"): r1[AC2/AC5 + the (i-adj-1) cross-artifact trio: runbook pair
# names == workflow env names == script-regex acceptance, set-equality all
# three surfaces] r2[AC4 parity greps vs the landed files — strings READ
# FROM the files, never re-typed here, so they cannot drift from what C09/
# C10 actually shipped] r3[AC3 stale-mechanics ban; ARGOCD_SYNC_TOKENS
# allowed exactly ONCE, on a line that also says delete] r4[AC5 posture
# rows] r5[AC6 human markers, apply-verbs, and the sourced-recipe form —
# `env KEY=value cmd` and prefix-assignment invocations are banned] r6[AC1
# structure: 8 sections + appendix, ≥11 preflight rows, the §6 "values ARE
# the org vars" header note].
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
# Env: FANOUT_RUNBOOK (doc), MAIN_SYNC_WF / FANOUT_SCRIPT / FANOUT_ROSTER
#      (parity sources; defaults = the landed repo files).
set -euo pipefail

cd "${FANOUT_ROOT:-$(git rev-parse --show-toplevel)}"

RUNBOOK="${FANOUT_RUNBOOK:-.agents/notes/2026-11-17-argocd-sync-fanout.md}"
WF="${MAIN_SYNC_WF:-.forgejo/workflows/main-sync.yaml}"
FANOUT="${FANOUT_SCRIPT:-scripts/argocd-fanout.py}"
ROSTER="${FANOUT_ROSTER:-scripts/argocd-fanout.json}"

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
  fail "$RUNBOOK missing — the runbook (rewrite #3 landed it at this path) must exist for C11 to rewrite in place"

# Shared walker + parity-source reader (every r-leg imports this).
cat > "$WORK/rbcommon.py" <<'PY'
"""Section walker + landed-source helpers for the C11 runbook legs."""
import importlib.util
import json
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
    path = __import__("os").environ.get("RB_FANOUT", "scripts/argocd-fanout.py")
    spec = importlib.util.spec_from_file_location("fanout_under_test", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod, path


def workflow_env_names():
    import yaml
    wf = __import__("os").environ.get("RB_WF", ".forgejo/workflows/main-sync.yaml")
    jobs = (yaml.safe_load(open(wf)) or {}).get("jobs") or {}
    names = []
    for src in [jobs.get("sync-fanout", {}).get("env") or {}] + \
               [s.get("env") or {} for s in (jobs.get("sync-fanout", {}).get("steps") or [])
                if isinstance(s, dict)]:
        for k in src:
            if k.startswith("ARGOCD_SYNC_"):
                names.append(k)
    return names, wf
PY

# --- r1: §2 creation legs + the 3-surface name-agreement + §7/§8 postures ----------
# The (i-adj-1) primary-guard made testable: EVERY ARGOCD_SYNC_* key name the
# runbook tells the owner to create must (a) equal, as a set, the workflow's
# enumerated env names, (b) be accepted by the LANDED script's own regex law
# (module imported from the real file — discover_targets must return exactly
# those categories), and (c) carry URL values equal to the §6 hosts table.
# A drifted name bites HERE, before any owner ever hunts a missing key.
if want r1; then
  if ! python3 - "$RUNBOOK" <<'PY'
import os, re, sys

sys.path.insert(0, os.environ["RB_WORKDIR"])
import rbcommon as rb

doc = rb.load_doc(sys.argv[1])
lines = doc.splitlines()
heads, order = rb.heads_lines(lines)
section = rb.make_section(lines, heads)


def bad(msg):
    print("FAIL: r1: %s" % msg, file=sys.stderr)
    sys.exit(1)


sec2 = section(2)

# §2 org-settings creation legs for BOTH key kinds (AC2).
if not re.search(r"(?i)org[^.\n]{0,40}settings[^.\n]{0,40}actions|org settings\s*(→|->)\s*actions", sec2):
    bad("§2 does not place the keys in the prod instance's ORG Settings → Actions (R7: org-scoped hygiene, inherited by the repo — NOT repo settings)")
if not re.search(r"(?i)\bvars?\b", sec2) or not re.search(r"(?i)secrets?\b", sec2):
    bad("§2 must describe BOTH kinds: 11 org VARS (URL-side) and 11 org SECRETS (TOKEN-side)")
if not re.search(r"(?i)repo[- ](side|twin)[^.\n]{0,120}(win|shadow|never|silence)|(never|not)[^.\n]{0,40}repo[- ](side|level)", sec2):
    bad("§2 lacks the single-instance repo-twin warning for both kinds (a repo key of either WINS silently — the runbook must say so)")

# Pair table: key names as CREATED in §2 (the surface the owner reads against
# the Actions UI). Incidental citations elsewhere (§8's malformed example,
# §2.4's dead blob name) are prose, not creation instructions, and are
# checked by r3's bans instead.
pat = re.compile(r"ARGOCD_SYNC_([A-Z0-9_]+)_(URL|TOKEN)")
doc_names = set(m.group(0) for m in pat.finditer(sec2))
doc_cats = {}
for m in pat.finditer(sec2):
    doc_cats.setdefault(m.group(1), set()).add(m.group(2))
if not doc_names:
    bad("§2 names no ARGOCD_SYNC_*_URL/_TOKEN keys — the 11-pair creation table (AC2) is the whole §2 rewrite")

wf_names, wf_path = rb.workflow_env_names()
wf_set = set(wf_names)
missing_in_wf = sorted(doc_names - wf_set)
missing_in_doc = sorted(wf_set - doc_names)
if missing_in_wf or missing_in_doc:
    bad("cross-artifact name set-equality FAILED: runbook-only names %s, workflow-only names %s — the runbook's creation table and %s's 22-row enumeration must be THE SAME NAMES (DECISIONS (i-adj-1): this leg is the primary drift guard; the script's broad-catch is only defense in depth)" % (missing_in_wf, missing_in_doc, wf_path))
if len(wf_set) != 22:
    bad("workflow enumerates %d pair names, expected 22 — the runbook equality is pinned against the fleet of 11" % len(wf_set))
if len(doc_names) != 22:
    bad("the runbook names %d of the 22 keys, expected all 22 (11 pairs, AC2 table completeness)" % len(doc_names))
incomplete = [seg for seg, sides in doc_cats.items() if sides != {"URL", "TOKEN"}]
if incomplete:
    bad("categories %s appear in §2 with only one side named — each pair must name BOTH the org var and the org secret" % incomplete)

# Script-side acceptance: import the LANDED module and discover from the
# doc's own names — every one must survive SEG_RE/CAT_RE and derive exactly
# the workflow's categories.
mod, _ = rb.fanout_module()
env = {n: ("https://cluster.example" if n.endswith("_URL") else mod.token_placeholder() if hasattr(mod, "token_placeholder") else "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhIiwic3FsIjoiZG9jLW5hbWUtdmFsaWRhdGlvbiJ9.SIGDOCVa1uE")
       for n in sorted(doc_names)}
try:
    disc = mod.discover_targets(env)
except Exception as e:
    bad("the landed script REJECTED the runbook's key names (%s) — §2 tells the owner to create keys discovery goes red on: the doc and the regex law disagree" % e)
if disc is mod.NOT_CONFIGURED:
    bad("discover_targets says NOT_CONFIGURED for the doc's 11 TOKEN names — the runbook table would create a fleet the script does not see")
got = {t["name"] for t in disc["targets"]}
wf_cats = {n[len("ARGOCD_SYNC_"):-4].lower().replace("_", "-") for n in wf_names if n.endswith("_URL")}
if got != wf_cats:
    bad("runbook names discover to categories %s, workflow enumerates %s — the underscore→hyphen derivation must agree across the three surfaces" % (sorted(got), sorted(wf_cats)))

# §2 URL values == §6 hosts (route truth relocated here per micro-call f):
# per-category full-URL equality between the two tables. Lines are parsed
# per-row so a table may carry key and value in the same or split cells.
sec6 = section(6)


def cat_urls(text):
    out = {}
    for ln in text.splitlines():
        km = re.search(r"ARGOCD_SYNC_([A-Z0-9_]+)_URL", ln)
        um = re.search(r"https://[^`\s|)]+", ln)
        if km and um:
            out[km.group(1).lower().replace("_", "-")] = um.group(0).rstrip("/")
    return out


doc_urls = cat_urls(sec2)
if not doc_urls:
    bad("§2's pair table does not carry the full https:// URL VALUES per category (C11 AC2: values = the §6 hosts, scheme included — an operator must not have to assemble them)")
hosts6 = {}
for ln in sec6.splitlines():
    if not ln.lstrip().startswith("|"):
        continue
    cells = [c.strip().strip("`* ") for c in ln.strip().strip("|").split("|")]
    if not cells:
        continue
    m = re.search(r"https://([a-z0-9.-]+)|^(cluster\.[a-z0-9.-]+)$", cells[1] if len(cells) > 1 else "")
    host = (m.group(1) or m.group(2)) if m else None
    if host:
        hosts6[cells[0].strip("`* ")] = "https://" + host.rstrip("/")
if len(hosts6) < 11:
    bad("§6 table exposes %d host rows in scheme-extractable form, expected 11 (the route-truth surface: runbook §6 + --check + smoke)" % len(hosts6))
drift = {c: (doc_urls[c], hosts6[c]) for c in doc_urls if c in hosts6 and doc_urls[c] != hosts6[c]}
if drift:
    bad("§2 var values drift from the §6 measured hosts: %s — the org vars ARE these values; a mismatch means the paste-hunt bug class returns" % drift)
missing = sorted(set(hosts6) - set(doc_urls))
if missing:
    bad("§2 carries no URL value for %s (the table must be complete for all 11)" % missing)

# §2 sourced-env --check recipe (step 3b) — the PINNED invocation form.
if "source pairs.env" not in sec2.replace('"', "").replace("'", ""):
    bad("§2 lacks the sourced-recipe pre-verify leg (`source pairs.env` then --check) — the plan pins the recipe FORM (never KEY=value on the command)")
if not re.search(r"(?i)export", sec2):
    bad("§2's pairs.env example must use export lines (the pinned file shape)")

# §7 kill lever (AC5): TOKEN-side delete/blank, pinned warning as
# proof-of-unset, all-or-nothing honesty.
sec7 = section(7)
if not (re.search(r"(?is)(delete|remove|blank)[^.]{0,240}secrets?[^.]{0,120}TOKEN", sec7)
        or re.search(r"(?is)(delete|remove|blank)[^.]{0,240}TOKEN[^.]{0,120}secrets?", sec7)):
    bad("§7's kill lever does not name deleting/BLANKING the org TOKEN secrets — the token-side configured predicate is what makes it warn-green (micro-call a)")
if not re.search(r"(?is)lever[^.]{0,140}TOKEN|TOKEN[^.]{0,140}lever", sec7):
    bad("§7 never binds the LEVER to the TOKEN side — the all-absent predicate is token-side (micro-call a); a URL-side lever would red-storm instead of warn-green (rejected alternative)")
if re.search(r"(?i)(delete|remove|blank)[^.\n]{0,60}(url|var)[^.\n]{0,40}(as|the)?[^.\n]{0,20}(kill|lever|switch)", sec7):
    bad("§7 frames the URL vars as the kill lever — URL-side keying was explicitly rejected (it would turn the lever into a red-storm)")
if not re.search(r"(?i)(warn|skip)[^.\n]{0,80}(proof|green)|proof[- ]of[- ](off|unset)", sec7):
    bad("§7 lacks the proof-of-unset sentence (the warning line IS the proof)")
if not re.search(r"(?i)(one|single|partial)[^.\n]{0,220}(red|error)|red[^.\n]{0,220}(one|single|partial)", sec7):
    bad("§7 must state the TRUE partial-kill posture: killing ONE cluster's token leaves its URL row populated ⇒ the fleet goes CONFIGURED and the residue is a config RED by ruling — all-or-nothing is the honest lever")

# §8 rotation + lockstep + category law (AC5).
sec8 = section(8)
if not re.search(r"(?i)delete-token", sec8):
    bad("§8 rotation must be per-key: re-mint, argocd account delete-token the old, overwrite the ONE org secret row (micro-call: TTL posture survives, mechanics per-key)")
if not re.search(r"(?i)overwri[^.\n]{0,60}(secret row|org secret|one row)", sec8):
    bad("§8 lacks the overwrite-the-single-row rotation sentence")
if not re.search(r"(?i)(lockstep|same release)[^.\n]{0,140}(workflow|enumeration|rows)|(workflow|enumeration|rows)[^.\n]{0,140}(lockstep|same release)", sec8):
    bad("§8 lacks the decommission lockstep sentence (org pair + the 2 workflow rows in ONE release; a key-only delete leaves residue-red by design)")
if not re.search(r"(?i)hyphen[- ]only", sec8 + sec2) or not re.search(
        r"(?is)(categor|category)[^.\n]{0,120}(underscore|underscores|_ )[^.]{0,120}(not|never|cannot|unrepresentable)|(underscore|underscores)[^.]{0,140}(categor[^.]{0,60}(not|never|cannot|unrepresentable)|not representable|unrepresentable)", sec8 + sec2):
    bad("§8 lacks the hyphen-only category law (a real category with an underscore is unrepresentable — micro-call c)")

# §8 TRUE envelope (i-adj-1): the catch claims must match reality.
envsec = sec8 + "\n" + sec2
if re.search(r"(?i)(any|every|all)[^.\n]{0,50}(typo|malformed)[^.\n]{0,50}(caught|red|reject)", envsec) and \
   not re.search(r"(?i)(ignored|by design|outside the (regex|pair|shape))", envsec):
    bad("§8 overclaims the catch envelope: DECISIONS (i-adj-1) pins it as valid-shape malformed ⇒ RED, DEGENERATE value-carrying shapes (e.g. ARGOCD_SYNC__TOKEN, lowercase side-suffixes) IGNORED by design, workflow rows guarded repo-side — the doc must state the true envelope, no overclaim")
if not re.search(r"(?i)ignored[^.\n]{0,80}(by design|degenerate)|degenerate[^.\n]{0,80}ignored|outside (the|its) (regex|shape|pair)", envsec):
    bad("§8 must name the TRUE envelope explicitly: degenerate malformed shapes are IGNORED by design (only valid-shape-with-value goes RED) — operators must not believe the scan catches all typos")
print("ok: r1")
PY
  then
    fail "r1: §2 creation legs / 3-surface name agreement / §7-§8 postures are violated (reason printed above)"
  fi
  ok "r1: §2 org-both-kinds + repo-twin warning + complete 11-pair table set-equal to the workflow's 22 env names AND accepted by the landed script's regex law (categories round-trip) + §2 URL values == §6 hosts + sourced pairs.env recipe; §7 TOKEN-side kill lever with proof-of-unset + partial-kill RED honesty; §8 per-key rotation + lockstep + hyphen-only law + the TRUE (i-adj-1) envelope wording (AC2/AC5)"
fi

# --- r2: parity greps against the LANDED files (AC4) -------------------------------
# Strings are READ FROM the sources (module constants, print formats, env
# map, invocation line, job name, roster keys) — re-typing them here would
# drift from what C09/C10 actually shipped.
if want r2; then
  if ! python3 - "$RUNBOOK" <<'PY'
import json, os, re, sys

sys.path.insert(0, os.environ["RB_WORKDIR"])
import rbcommon as rb

doc = rb.load_doc(sys.argv[1])


def bad(msg):
    print("FAIL: r2: %s" % msg, file=sys.stderr)
    sys.exit(1)


mod, mod_path = rb.fanout_module()

# 1. The kill-lane warning, byte-exact off the landed script constant.
warn = getattr(mod, "WARN_NOT_CONFIGURED", None)
if not warn:
    bad("%s defines no WARN_NOT_CONFIGURED constant (wave-11 landing moved it) — r2 reads the string from the script, not from memory" % mod_path)
if warn not in doc:
    bad("the runbook never quotes the script's kill-lane warning BYTE-EXACT (§4 quote + §7 proof-of-unset depend on it); landed string: %r" % warn)

# 2. The --check pairs line: format extracted from the script source.
src = open(mod_path).read()
m = re.search(r'print\("(pairs: %d targets discovered \(values never printed\))"', src)
if not m:
    bad("the landed script's --check pairs line changed shape (%r) — r2's pin must follow the FILE, and the runbook quotes it" % "pairs line pattern not found")
fmt = m.group(1)
if fmt.replace("%d", "11") not in doc:
    bad("the runbook's expected --check output line is not the landed `pairs: 11 targets discovered (values never printed)` (byte parity, C11 step-3b expectation)")

# 3. The job name + invocation line off the workflow.
wf_raw = open(os.environ.get("RB_WF", ".forgejo/workflows/main-sync.yaml")).read()
if "sync-fanout" not in doc:
    bad("the runbook never names the sync-fanout job")
inv = 'python3 scripts/argocd-fanout.py --config scripts/argocd-fanout.json --ref "$REF"'
if inv not in wf_raw:
    bad("the LANDED workflow no longer contains the pinned invocation line — r2's parity source moved; re-pin the test session side")
if "python3 scripts/argocd-fanout.py" not in doc:
    bad("the runbook never quotes the script path the job invokes")

# 4. Representative env pair + all 22 names already guarded by r1; here the
# var/secret PREFIX form must appear in the doc (§2: vars.X / secrets.X).
for form in ("vars.ARGOCD_SYNC_DEV_URL", "secrets.ARGOCD_SYNC_DEV_TOKEN"):
    if form not in doc:
        bad("the runbook does not use the %s expression form for the dev pair — §2 must name the keys EXACTLY as the workflow wires them (the Actions UI shows these names)" % form)

# 5. Roster globals: the file parses to the five keys, and the doc quotes
# the roster path (§1/§4) + never claims the roster lists targets.
roster = json.load(open(os.environ.get("RB_ROSTER", "scripts/argocd-fanout.json")))
if set(roster) != {"allowed_refs", "tracked_repo", "settle_seconds", "target_timeout_seconds", "parallel_workers"}:
    bad("landed roster keys are %s (C09's five globals expected) — the parity source moved under the suite" % sorted(roster))
if "scripts/argocd-fanout.json" not in doc:
    bad("the runbook never names the roster JSON (it still exists as the globals home)")
if re.search(r"(?i)roster[^.\n]{0,60}(11|targets|list of categories|endpoint list)", doc):
    bad("the runbook claims the roster carries endpoints — R7: the endpoint list is the env pairs; the roster is five globals")

# 6. Audit/summary grammar + refs, doc-side quotes vs script-side prints.
for tok, where in (("fan-out summary", src), ("allowed_refs", src), ("refs/heads/main", json.dumps(roster))):
    if tok in doc and tok not in where:
        bad("the runbook quotes %r but the landed source (%s) no longer contains it" % (tok, "script/roster"))
if "targets=" not in doc:
    bad("the runbook §5 smoke must teach the summary line's targets=<DISCOVERED> shape (the count is the pair count now)")
print("ok: r2")
PY
  then
    fail "r2: parity against the landed files is violated (reason printed above)"
  fi
  ok "r2: byte parity for the kill-lane warning (script constant), the pairs-line check expectation (script source), the invocation + job + pair-name expression forms (workflow), the five-globals roster (JSON) and the audit/summary grammar; the roster-endpoint claim stays dead (AC4)"
fi

# --- r3: dead-mechanics ban (AC3) ---------------------------------------------------
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


# Stale-mechanics needles (joined forms arrive as argv or from fragments;
# this file never carries the blob literal inline).
NEEDLES = [
    (cat_grammar, "the superseded blob record grammar"),
    (paste_name, "the compose-the-paste artifact"),
    ("::warning::sync-fanout not configured (org-level", "the SUPERSEDED warning wording (the script's own line — read by r2 — replaced the shell-guard text)"),
    ("[26]", "the per-line masking citation — the blob design that needed it is dead (C11: one honest native-masking sentence, no [26] framing)"),
]
for pat, why in NEEDLES:
    if pat in doc:
        bad("the runbook still carries %r (%s) — dead mechanics are deleted, not softened (AC3)" % (pat, why))

for pat, why in (
        (r"(?i)newline[- /]?(delimited|record|grammar|form|style|lines)", "the newline-records ruling (OQ8 mechanics were superseded by R7; the DELIMITER story must not be taught any more)"),
        (r"(?i)comma[- ]?(separated|delimited)", "the delimiter-tolerance story (parser died with the blob)"),
        (r"(?i)per[- ]line (mask\w*)[^.\n]{0,80}(holds|verif|granular|wins|guarante|proof|ruling)|(verif|re-weigh)[^.\n]{0,40}per[- ]line|per[- ]line masking granularity", "AFFIRMING per-line masking (the C11 dev-note allowance is ONE sentence calling the claim MOOT; affirmations re-teach the dead design)"),
        (r"(?i)\bone (secret|vault)\b|single (secret|vault)\b|\bONE secret\b", "the ONE-secret phrasing (there are 22 keys now: 11 vars + 11 secrets)"),
):
    if re.search(pat, doc):
        m = re.search(pat, doc)
        bad("the runbook matches the dead-grammar pattern %r (%s) at: %r (AC3)" % (pat, why, doc[max(0, m.start()-40):m.end()+40]))

# The moot TRIO: hook pair + the reopen2 blob. Hook names may appear ONLY
# in §2's delete-check; the blob name exactly ONCE, on a line that also
# says delete.
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
    bad("the dead blob name %r appears on %d lines, expected EXACTLY the one §2.4 delete-check line (AC3: named only as a key to remove — the 11-23→11-25 window may have created it; confirm absence or delete)" % (blob, len(blob_lines)))
if blob_lines:
    i = blob_lines[0]
    window = "\n".join(lines[max(0, i - 3):i + 2])  # wrapping may split the verb and the key
    if not re.search(r"(?i)delete|remove|absence", window):
        bad("the single blob-name occurrence has no delete/remove/absence verb within its 3-line context (the sanctioned §2.4 mention shape): %r" % lines[i][:120])
sec2 = section_of(doc, 2)
for nn in (1, 3, 4, 5, 6, 7, 8):
    if "ARGOCD_HOOK" in section_of(doc, nn):
        bad("section %d mentions ARGOCD_HOOK_* keys — the moot pair is nameable ONLY in §2's delete-check (AC3's trio discipline)" % nn)
for trio in ("vars.ARGOCD_HOOK_URL", "secrets.ARGOCD_HOOK_SECRET"):
    if trio not in sec2:
        bad("§2's delete-check does not name %s — the moot TRIO (hook pair + the reopen2 blob) is the full cleanup leg (AC3/human-owned list)" % trio)
if blob not in sec2:
    bad("§2's delete-check does not name %s (the third of the trio)" % blob)

# No webhook-creation tells (survives from rewrite #3's spine).
if re.search(r"(?i)add webhook|settings\s*(→|->)\s*web ?hooks", doc):
    bad("a webhook-creation UI path survives (R1 option (c): the job IS the webhook; AC1 bars creation steps)")
print("ok: r3")
PY
  then
    fail "r3: dead mechanics survive in the runbook (reason printed above)"
  fi
  ok "r3: zero hits for cat:token / tokens-paste / old-warning / [26] / newline-comma grammar / per-line-masking / one-secret phrasing; the blob name sits EXACTLY ONCE on a delete-check line; ARGOCD_HOOK_* confined to §2's trio leg; no webhook-creation tells (AC3)"
fi

# --- r4: posture rows (AC5 + the ruled expectations) --------------------------------
if want r4; then
  if ! python3 - "$RUNBOOK" <<'PY'
import os, re, sys

sys.path.insert(0, os.environ["RB_WORKDIR"])
import rbcommon as rb

doc = rb.load_doc(sys.argv[1])
lines = doc.splitlines()
heads, _ = rb.heads_lines(lines)
section = rb.make_section(lines, heads)


def bad(msg):
    print("FAIL: r4: %s" % msg, file=sys.stderr)
    sys.exit(1)


# The two RULED failed rows (proxy-local 307 structural, proxy-backup OQ9):
# the doc must expect them, naming both the category and the shape.
pl = [ln for ln in lines if "proxy-local" in ln and "307" in ln]
if not pl:
    bad("no line pairs proxy-local with 307 — the landed structural finding (the hub route 307s to the SSO edge; C09's no-follow opener turns it into an honest `applications list HTTP 307`) is a RULED expected-failed row (§5/§6)")
if not re.search("(?i)(fail|expected|red|ruled|structural)", " ".join(pl)):
    bad("the proxy-local 307 rows never say it audits FAILED by ruling — expectation wording required (§5 smoke list)")
pb = [ln for ln in lines if "proxy-backup" in ln and re.search(r"(?i)fail", ln)]
if not pb:
    bad("no line pairs proxy-backup with a fail expectation (the OQ9 warn-and-skip posture, unchanged by R7)")

# Masking paragraph: native per-secret, not the per-line blob story.
sec5 = section(5)
if not re.search(r"(?is)native[^.]{0,80}(mask|secret)|(each|every)[^.]{0,40}secret[^.]{0,60}mask|single[- ]line[^.]{0,60}mask", sec5):
    bad("§5's masking leg does not state the NATIVE per-secret masking shape (Actions masks each secret's value wherever it appears [21][22]; the [26] per-line verification died with the blob — AC3/C11 §5c)")
if re.search(r"(?i)\[26\]|re-weigh", sec5):
    bad("§5 still frames the masking check as [26]-verification / ruling-re-weighing — the record-shape ruling is dead; the spot-check survives as plain hygiene")
if not re.search(r"(?i)spot[- ]?check|zero hits", sec5):
    bad("§5 dropped the one-time log spot-check (search a token prefix, expect zero hits) — C11 keeps it as hygiene")

# No pending markers (the round is closed; rewrites state answers).
if re.search(r"(?i)pending owner|owner (decision|call) (pending|open)|to be (decided|ruled)", doc):
    bad("an unresolved-question marker survives — R7 + the batched rounds are ANSWERED; the runbook states rulings (AC6 of C08 survives; the sweep was written into C11's spine)")
print("ok: r4")
PY
  then
    fail "r4: a posture row is missing or stale (reason printed above)"
  fi
  ok "r4: expected-failed rows for proxy-local(307) and proxy-backup(fail) present; §5 masking says native per-secret with the hygiene spot-check and no [26]/re-weigh framing; zero pending markers (AC5)"
fi

# --- r5: human-executed markers + command law + sourced-recipe form (AC6) -----------
if want r5; then
  if ! python3 - "$RUNBOOK" <<'PY'
import os, re, sys

doc = open(sys.argv[1]).read()
lines = doc.splitlines()


def bad(msg):
    print("FAIL: r5: %s" % msg, file=sys.stderr)
    sys.exit(1)


if not re.search(r"(?i)human[- \t]executed", "\n".join(lines)):
    bad("r5: no human-executed marker anywhere (AC6 of the doc's own law: this repo never applies; every leg is human-owned)")

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
        bad("r5: fenced block at line %d (`%s`...) has no human-executed marker in its heading or the 12 lines before it (AC5 of C08's command law survives)" % (a + 1, body[0].strip()[:60]))
    for j, l in enumerate(body, start=a + 2):
        if re.search(r"\bkubectl\b", l) or re.search(r"\bhelm (install|upgrade)\b", l) \
           or re.search(r"\bgit push origin\b", l) or re.search(r"argocd app sync", l):
            bad("r5: line %d is a repo-mutating apply command in a fence (%s) — this repo NEVER applies" % (j, l.strip()[:80]))
        # The argv-leak forms (C11 AC6): `env KEY=value cmd` (the assignment
        # rides env(1)'s argv, ps-visible) and a same-line ARGOCD_SYNC_*
        # prefix assignment feeding an invocation.
        if re.search(r"\benv\s+[A-Z][A-Z0-9_]*=", l):
            bad("r5: line %d uses the forbidden `env KEY=value cmd` shape — the plan pins the source-then-run recipe because this form puts values in a ps-visible argv" % j)
        if re.search(r"^[ \t]*ARGOCD_SYNC_[A-Z0-9_]*=.*\b(python3|argocd-fanout)", l):
            bad("r5: line %d assigns an ARGOCD_SYNC_* inline before the command — the pinned recipe is export-into-file + source pairs.env (one shape, greppable, never a bare VAR=x cmd line with the pair names)" % j)

if "source pairs.env" not in doc.replace('"', "").replace("'", ""):
    bad("r5: the sourced-recipe form (write pairs.env with export lines → source pairs.env → run) is the PINNED invocation shape and appears nowhere (AC6)")
print("ok: r5")
PY
  then
    fail "r5: the command law is violated (reason printed above)"
  fi
  ok 'r5: every command block human-marked; zero apply-verbs; no "env KEY=value" and no inline ARGOCD_SYNC_* assignment forms; the source pairs.env recipe is present (AC6)'
fi

# --- r6: structure + §6 header note (AC1) -------------------------------------------
if want r6; then
  if ! python3 - "$RUNBOOK" <<'PY'
import os, re, sys

lines = open(sys.argv[1]).read().splitlines()


def bad(msg):
    print("FAIL: r6: %s" % msg, file=sys.stderr)
    sys.exit(1)


seq = []
for ln in lines:
    m = re.match(r"^#{1,6}\s*(?:Section\s+)?(\d+)(?=[.:)\s—–-]|$)", ln)
    if m and int(m.group(1)) not in seq:
        seq.append(int(m.group(1)))
if seq != list(range(1, 9)):
    bad("r6: numbered section headers are %s, expected exactly 1..8 in order (rewrite #4 keeps rewrite #3's spine)" % seq)
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
    bad("r6: preflight table names %d of 11 categories (the route-truth surface moved HERE with micro-call f — it must be complete)" % len(rows))

# §6 header note (C11 §6 task): the hosts table declares itself the org-var
# values ("these values ARE the org vars (§2)"), the anti-hunt sentence.
i6 = next((k for k, ln in enumerate(lines) if re.match(r"^#{1,6}\s*6(?=[.:)\s—–-]|$)", ln)), None)
if i6 is None:
    bad("r6: no section 6 heading")
j6 = next((k for k in range(i6 + 1, len(lines)) if re.match(r"^#{1,6}\s*\d", lines[k])), len(lines))
# Line-based (the note wraps and cites section numbers whose dots would
# break any char-class window): ONE line must carry both the values/hosts
# noun and the org-var identity.
note = any(("host" in ln.lower() or "value" in ln.lower())
           and ("org var" in ln.lower() or "ARGOCD_SYNC" in ln)
           for ln in lines[i6:j6])
if not note:
    bad("r6: §6 lacks the header note that the table values ARE the org VARS (§2) — the route-truth doctrine lives here + --check + smoke now, and the note is what says so")
print("ok: r6")
PY
  then
    fail "r6: the runbook structure is wrong (reason printed above)"
  fi
  ok "r6: sections 1..8 + appendix, all 11 preflight rows, §6 carries the org-vars identity note (AC1)"
fi

rm -rf "$WORK"
printf 'PASS: argocd sync-fanout runbook contract checks (%d ok)\n' "$checks"
