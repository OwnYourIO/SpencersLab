#!/usr/bin/env bash
# Sync-fan-out operator runbook contract (2026/2026-11-cf-139-feat-argocd-webhook-sync, C08):
# .agents/notes/2026-11-17-argocd-sync-fanout.md — the vault-direct runbook
# (rewrite #3, renamed with git mv from the relay-era file): human legs
# collapsed to 11 token mints + ONE org-level vault paste + deleting the two
# moot keys; zero Bitwarden; dispatch smoke with the [26] masking
# spot-check; the RULED postures (OQ8 newline records, OQ9 proxy-backup
# warn-and-skip preflight row, OQ10 indefinite TTL + delete-token revoke,
# ORG-level scope) stated as answers, never pending questions.
#
# This suite is the renamed carrier of the relay-era runbook suite (test
# session executes the rename; C08 lands the doc rename+rewrite — the suite
# is the designed-red carrier until then, the kickoff script.sh posture).
# Contract source: chunks/C08.md "## Tests". AC trace:
# r1[AC2] r2[AC3] r3[AC4] r4[AC6] r5[AC5] r6[AC1]
# (AC1's suite-green half is this file running; the stale-shape bans reuse
# the shipped fragment-needle technique so this harness never self-matches
# the joinable relay literals, keeping the C07 disposal sweep clean.)
#
# Doc-vs-command law: every command in this runbook is HUMAN-executed by
# ruling (plan Human-owned list; AGENTS.md never-apply law) — r5 pins the
# marker per command block AND bars repo-mutating verbs (no kubectl, no helm
# install/upgrade, no argocd app sync — token MINTS via argocd account
# generate-token are the one argocd verb allowed, and repo-side
# python3 scripts/argocd-fanout.py checks are read-mostly CI-lane siblings).
#
# Run from the repo root (or point FANOUT_ROOT at a synthetic tree for
# green-shape proofs):
#   bash tests/notes/argocd-fanout-runbook.sh            # r1..r6
#   bash tests/notes/argocd-fanout-runbook.sh r2 r4      # subset
# Env: FANOUT_ROOT (default repo root), FANOUT_RUNBOOK (doc path override),
#      MAIN_SYNC_WF / FANOUT_SCRIPT / FANOUT_ROSTER (parity sources),
#      CHUNK_BASE for the r6 scope diff.
set -euo pipefail

cd "${FANOUT_ROOT:-$(git rev-parse --show-toplevel)}"

RUNBOOK="${FANOUT_RUNBOOK:-.agents/notes/2026-11-17-argocd-sync-fanout.md}"
WF="${MAIN_SYNC_WF:-.forgejo/workflows/main-sync.yaml}"
FANOUT="${FANOUT_SCRIPT:-scripts/argocd-fanout.py}"
ROSTER="${FANOUT_ROSTER:-scripts/argocd-fanout.json}"
BASE="${CHUNK_BASE:-HEAD}"
N1="argocd-"
N2="hook"
OLD_NAME="2026-11-17-${N1}${N2}-relay.md"       # retired doc filename, joined only here
RELEASE="proxy-local-${N1}${N2}"                 # retired release name, joined only here

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

command -v python3 >/dev/null 2>&1 || fail "python3 is required for the runbook walk"

WORK=$(mktemp -d /tmp/opencode/argocd-fanout-runbook.XXXXXX)

# --- r1: path swap + stale-reference sweep (AC2) ---------------------------------
if want r1; then
  [ -f "$RUNBOOK" ] ||
    fail "r1: $RUNBOOK missing — C08 (runbook rewrite #3 + git mv) is not implemented (designed-red carrier)"
  if [ -e ".agents/notes/$OLD_NAME" ]; then
    fail "r1: the relay-era runbook path .agents/notes/$OLD_NAME still exists — C08 git-mv's it to the honest name"
  fi
  git rev-parse --git-dir >/dev/null 2>&1 ||
    fail "r1: FANOUT_ROOT is not a git checkout — the stale-reference sweep needs the tracked tree"
  stale=$(git grep -lF "$OLD_NAME" -- ':!.agents/plans' 2>/dev/null || true)
  if [ -n "$stale" ]; then
    fail "r1: files outside the ticket tree still reference the retired runbook path: $(printf '%s\n' "$stale" | tr '\n' ' ') — the chart/custom-values pointers died in C07, the doc itself moved in C08 (AC2)"
  fi
  ok "r1: new runbook path exists, old path absent, zero stale references outside .agents/plans (AC2)"
fi

# --- r2: docs-parity against the landed sources (AC3) -----------------------------
if want r2; then
  if ! python3 - "$RUNBOOK" "$WF" "$FANOUT" "$ROSTER" <<'PY'
import json, re, sys

runbook, wf, fanout, roster = sys.argv[1:5]


def bad(msg):
    print("FAIL: r2: %s" % msg, file=sys.stderr)
    sys.exit(1)


try:
    doc = open(runbook).read()
except OSError as e:
    bad("%s unreadable (r1 covers absence; this is the read)" % runbook)
sources = {}
for label, path in (("workflow", wf), ("script", fanout), ("roster", roster)):
    try:
        sources[label] = open(path).read()
    except OSError:
        bad("parity source %s (%s) is absent — the runbook documents the LANDED C05/C06 shape; docs may not precede the code they pin" % (path, label))
wf_src, script_src, roster_src = sources["workflow"], sources["script"], sources["roster"]

# Every token the runbook quotes must exist byte-true in the file it quotes
# (the shipped t2 parity technique, ported: docs-vs-code drift is the bug
# class this leg kills — reopen1's final review produced it twice).
PAIRS = [
    ("scripts/argocd-fanout.py", wf_src, "the script path the job invokes"),
    ("scripts/argocd-fanout.json", wf_src, "the roster path the job invokes"),
    ("ARGOCD_SYNC_TOKENS", wf_src, "the vault key the job wires"),
    ("sync-fanout", wf_src, "the job name"),
    ("sync-fanout not configured", wf_src, "the unset-skip warning the runbook quotes (the exact guard line is t12's pin; this is the doc-side agreement)"),
    ("ARGOCD_SYNC_TOKENS", script_src, "the env var the script reads"),
    ("--check", script_src, "the offline validate mode"),
    ("--dry-run", script_src, "the GET-only smoke mode"),
    ("target=", script_src, "the audit-line grammar token"),
    ("fan-out summary", script_src, "the summary line the smoke reads"),
    ("refs/heads/main", roster_src, "the shipped allowed_ref"),
]
for tok, src, what in PAIRS:
    if tok not in doc:
        bad("the runbook never mentions %r (%s) — operators must be able to find every landed surface in the doc (AC3)" % (tok, what))
    if tok not in src:
        bad("the runbook quotes %r (%s) but its source file does not contain it (AC3 parity)" % (tok, what))

# The org-scope agreement: workflow header, §2 create leg and §7 unset leg
# must all speak ORG scope for the tokens secret (ruled 2026-11-23; the
# three surfaces claiming different scopes is the failure this pins).
def org_scoped(text):
    return bool(re.search(r"(?i)\borg[- /]?(level|scoped)\b", text)
                or re.search(r"(?i)\borg\b[^.\n]{0,80}secret", text))


header = "\n".join(ln for ln in wf_src.splitlines() if ln.lstrip().startswith("#"))
if not org_scoped(header):
    bad("the workflow header carries no org-scope wording for the tokens secret — C06's pinned sentence is the runbook's counterpart")
heads = {}
for i, ln in enumerate(runbook_lines := open(runbook).read().splitlines()):
    m = re.match(r"^#{1,6}\s*(?:Section\s+)?(\d+)(?=[.:)\s—–-]|$)", ln)
    if m and int(m.group(1)) not in heads:
        heads[int(m.group(1))] = i


def section(n):
    if n not in heads:
        bad("no numbered section %d header — AC1 structure (r6 walks it; r2 needs §2/§5/§7/§8 for the parity+posture legs)" % n)
    nxt = heads[n] + 1
    while nxt < len(runbook_lines):
        m = re.match(r"^#{1,6}\s*(?:Section\s+)?(\d+)(?=[.:)\s—–-]|$)", runbook_lines[nxt])
        if m and int(m.group(1)) in heads and heads[int(m.group(1))] == nxt:
            break
        nxt += 1
    return "\n".join(runbook_lines[heads[n] + 1:nxt])


for n in (2, 7):
    if not org_scoped(section(n)):
        bad("section %d (create/unset leg) does not name the ORG-level scope — the runbook must agree with the workflow header so operators don't hunt a repo-level key (AC3/AC6)" % n)

# The 11 roster hosts appear in the doc (the reachability appendix table
# moves verbatim from [P2 §1]; a drifted host in the doc is exactly reopen1's
# wrong-hosts bug class).
roster = json.loads(roster_src)
missing = [t["url"] for t in roster.get("targets", []) if t["url"] not in doc]
if missing:
    bad("roster URLs absent from the runbook: %s (every fan-out target host the script will dial must be documented for the owner's vantage checks)" % missing)
print("ok: r2")
PY
  then
    fail "r2: runbook-vs-landed-files parity is violated (reason printed above)"
  fi
  ok "r2: every quoted token (paths, key, job, modes, grammar, refs, 11 hosts) exists byte-true in workflow/script/roster; org scope agrees across header + §2 + §7 (AC3)"
fi

# --- r3: stale-shape ban sweep (AC4) ----------------------------------------------
if want r3; then
  if ! python3 - "$RUNBOOK" "$OLD_NAME" "$RELEASE" <<'PY'
import re, sys

runbook, old_name, release = sys.argv[1:4]
doc = open(runbook).read()


def bad(msg):
    print("FAIL: r3: %s" % msg, file=sys.stderr)
    sys.exit(1)


# Joined needles are built from fragments (or handed in as argv above), so
# THIS suite file stays free of the joined forms — C07's tests/ needle sweep
# must find zero hits in it (the shipped harness's strip-technique).
NEEDLES = [
    ("hook-" + "relay", "the retired job name"),
    ("hook-" + "secret", "the relay HMAC key filename"),
    ("X-Hub-Signature", "the hub signature header (the relay's dialect)"),
    ("X-Forgejo-" + "Signature", "the forge signature header (the relay's dialect)"),
    ("sha256=", "the HMAC prefix form"),
    ("openssl dgst", "the HMAC signing recipe"),
    ("github-" + "webhook", "the retired relay key/payload vocabulary"),
    ("bitwardenIds", "the Bitwarden override-key structure (zero Bitwarden by ruling — the word Bitwarden may appear only inside the state-the-absence sentence, never a key name)"),
    ("OVERRIDE_NEEDED", "the never-filled sentinel fill leg (gone with the chart)"),
    ("targets.json", "the relay ConfigMap roster (the roster is now scripts/argocd-fanout.json)"),
    ("RELAY_URL", "the trigger env wiring"),
    ("RELAY_SECRET", "the trigger env wiring"),
    (release, "the retired helm release name"),
    ("Add webhook", "a webhook-creation instruction (R1 option (c): the job IS the webhook; AC1 bars creation steps)"),
    ("Settings → Webhooks", "a webhook-creation UI path"),
]
for pat, why in NEEDLES:
    if pat in doc:
        bad("the runbook still carries %r (%s) — stale-shape ban AC4: the relay/Bitwarden/HMAC paragraphs are deleted, not softened" % (pat, why))

# The moot KEYS may be named ONLY in the §2 DELETE leg.
heads = []
lines = doc.splitlines()
for i, ln in enumerate(lines):
    m = re.match(r"^#{1,6}\s*(?:Section\s+)?(\d+)(?=[.:)\s—–-]|$)", ln)
    if m:
        heads.append((i, int(m.group(1))))
bounds = []
for idx, (i, n) in enumerate(heads):
    j = heads[idx + 1][0] if idx + 1 < len(heads) else len(lines)
    bounds.append((n, "\n".join(lines[i:j])))
for n, body in bounds:
    if n != 2 and "ARGOCD_HOOK" in body:
        bad("section %d mentions ARGOCD_HOOK_* keys — the moot pair is nameable ONLY in the §2 delete leg (AC4)" % n)
if old_name in doc:
    bad("the runbook references its own retired filename (r1's sweep covers the repo; this is the doc itself)")
print("ok: r3")
PY
  then
    fail "r3: stale relay-era shapes survive in the runbook (reason printed above)"
  fi
  ok "r3: zero hits for the stale-shape set (job/key/header/HMAC/sentinel/release/UI-path needles); moot key names confined to the §2 delete leg (AC4)"
fi

# --- r4: ruled-posture rows (AC6) --------------------------------------------------
if want r4; then
  if ! python3 - "$RUNBOOK" <<'PY'
import re, sys

lines = open(sys.argv[1]).read().splitlines()
doc = "\n".join(lines)


def bad(msg):
    print("FAIL: r4: %s" % msg, file=sys.stderr)
    sys.exit(1)


heads = {}
for i, ln in enumerate(lines):
    m = re.match(r"^#{1,6}\s*(?:Section\s+)?(\d+)(?=[.:)\s—–-]|$)", ln)
    if m and int(m.group(1)) not in heads:
        heads[int(m.group(1))] = i


def section(n):
    if n not in heads:
        bad("no numbered section %d header" % n)
    nxt = heads[n] + 1
    while nxt < len(lines):
        m = re.match(r"^#{1,6}\s*(?:Section\s+)?(\d+)(?=[.:)\s—–-]|$)", lines[nxt])
        if m and int(m.group(1)) in heads and heads[int(m.group(1))] == nxt:
            break
        nxt += 1
    return "\n".join(lines[heads[n] + 1:nxt])


def need(text, pat, what, flags=0):
    if not re.search(pat, text, flags):
        bad("r4: %s lacks %r (AC6: the ruled postures are stated as answers)" % (what, pat))


CATS = ["dev", "gpu", "gpu-ai", "grow", "home", "infra", "media", "monitoring",
        "proxy-local", "proxy-backup", "proxy-remote"]

sec2 = section(2)
need(sec2, r"generate-token --account mcp-bot", "§2 (the mint command shape)")
missing = [c for c in CATS if not re.search(r"(?<![\w.-])%s(?![\w-])" % re.escape(c), sec2)]
if missing:
    bad("r4: §2 does not name every category: %s (11 mints against each cluster's OWN route host — AC6/human legs)" % missing)
need(sec2, r"cat:token", "§2 (the ruled OQ8 record grammar, named in its documented form)")
need(sec2, r"(?i)one per line|per line|newline", "§2 (newline records wording)")
recs = [ln for ln in lines if re.fullmatch(r"(%s):[^\s:][^\s]*" % "|".join(map(re.escape, CATS)), ln.strip())]
if len(recs) < 11:
    bad("r4: only %d display lines shaped like a `cat:token` record; the grammar leg shows the newline form (≥11 record lines, one per category)" % len(recs))
seen_cats = {ln.split(":", 1)[0] for ln in recs}
if len(seen_cats & set(CATS)) < 11:
    bad("r4: the record lines do not cover all 11 categories (%s)" % sorted(seen_cats))
need(sec2, r"(?i)inherit", "§2 (the repo inherits the org secret — the sentence that stops operators hunting a repo key)")
need(sec2, r"(?is)delete.{0,120}ARGOCD_HOOK|ARGOCD_HOOK.{0,120}delete", "§2 (the moot-pair DELETE leg names both keys as the disposal action)")

sec5 = section(5)
need(sec5, r"workflow_dispatch", "§5 (smoke = a dispatch of main-sync on the prod instance)")
need(sec5, r"(?i)mask|token prefix|\*\*\*", "§5 (the [26] masking spot-check leg — the owner greps their own token prefixes in the run log; the claim was read via a search index and this leg verifies it live)")
need(sec5, r"(?i)zero (hits|occurrences)|expect.{0,40}(none|zero|\*\*\*)", "§5 (the spot-check's expected answer is stated, not left to interpretation)")
backup = [ln for ln in lines if "proxy-backup" in ln and re.search(r"(?i)fail", ln)]
if not backup:
    bad("r4: no line pairs proxy-backup with a fail expectation — the RULED OQ9 posture: its row is an honest failed audit line, never a silent drop, until the owner's vantage check concludes")
need(sec5, r"(?i)--dry-run|--check", "§5 (the manual preflight legs: env-mapped token paste, never argv)")

sec8 = section(8)
need(sec8, r"delete-token", "§8 (OQ10: revocation is argocd account delete-token)")
need(sec8, r"(?i)(vault|paste)[^.\n]{0,60}overwri|overwri[^.\n]{0,60}(vault|secret)", "§8 (OQ10: rotation-by-vault-overwrite)")
need(sec8, r"(?i)indefinite|no expiry|never expire", "§8 (OQ10: the TTL ruling as an answer — no expiry treadmill, mcp-bot is apiKey-only)")

sec7 = section(7)
need(sec7, r"(?is)(delete|remove|overwri).{0,120}(org|secret)|org.{0,120}(delete|remove|overwri)", "§7 (the kill switch is the ORG-level secret's presence — unset happens in org settings; the repo carries no key to unset)")
need(sec7, r"(?i)revert", "§7 (revert-the-PR rollback survives)")

if re.search(r"(?i)pending owner|owner (decision|call) (pending|open)|to be (decided|ruled)", doc):
    bad("r4: an unresolved-question marker survives — the batched round of 2026-11-23 ANSWERED OQ8/OQ9/OQ10 + the org scope; the runbook states rulings, not open questions (AC6)")
print("ok: r4")
PY
  then
    fail "r4: a ruled posture row is missing (reason printed above)"
  fi
  ok "r4: §2 mints+11 cats+cat:token newline display+inherit+delete-leg; §5 dispatch+masking spot-check+proxy-backup failed row; §7 org-scope kill switch; §8 indefinite TTL+revoke+vault rotation; zero pending markers (AC6)"
fi

# --- r5: human-executed markers + command law (AC5) --------------------------------
if want r5; then
  if ! python3 - "$RUNBOOK" <<'PY'
import re, sys

lines = open(sys.argv[1]).read().splitlines()


def bad(msg):
    print("FAIL: r5: %s" % msg, file=sys.stderr)
    sys.exit(1)


if not re.search(r"(?i)human[- \t]executed", "\n".join(lines)):
    bad("r5: no human-executed marker anywhere (AC5: this repo never applies; the whole runbook is human legs)")

MARK = re.compile(r"(?i)\bhuman\b|\bowner (runs|executes|pastes|mints|performs|deletes|checks)\b|\byou (run|paste|mint)\b")
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
    bad("r5: the runbook has no fenced command blocks — the procedure must be copy-pasteable (human-executed, marked)")


def head_before(pos):
    h = ""
    for ln in lines[:pos]:
        if re.match(r"^#{1,6}\s", ln):
            h = ln
    return h


for a, b in blocks:
    body = lines[a + 1:b]
    if not any(l.strip() for l in body):
        continue  # diagram/table fences carry no commands
    context = "\n".join(lines[max(0, a - 12):a]) + "\n" + head_before(a)
    if not MARK.search(context):
        bad("r5: fenced block at line %d (`%s`...) has no human-executed marker in its heading or the 12 lines before it — every command here is human-owned by ruling (AC5)" % (a + 1, body[0].strip()[:60]))
    for j, l in enumerate(body, start=a + 2):
        if re.search(r"\bkubectl\b", l) or re.search(r"\bhelm (install|upgrade)\b", l) \
           or re.search(r"\bgit push origin\b", l) or re.search(r"argocd app sync", l):
            bad("r5: line %d is a repo-mutating apply command inside a fenced block (%s) — this repo NEVER applies (AGENTS.md); syncs are the fan-out's, mints are the owner's (AC5)" % (j, l.strip()[:80]))
print("ok: r5")
PY
  then
    fail "r5: the human-executed/command law is violated (reason printed above)"
  fi
  ok "r5: every command block is human-marked; zero kubectl/helm-install/upgrade/git-push-origin/argocd-app-sync in fences (AC5)"
fi

# --- r6: structure + preflight table + scope (AC1) ----------------------------------
if want r6; then
  if ! python3 - "$RUNBOOK" <<'PY'
import re, sys

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
    bad("r6: numbered section headers are %s, expected exactly 1..8 in order (the shipped spine transfers; rewrite #3 keeps it)" % seq)
if not any(re.match(r"^#{1,6}\s*Appendix", ln, re.I) for ln in lines):
    bad("r6: no Appendix heading — the note-only anomalies (the public-A leak row, OQ4) and the [P2] reachability table ride the appendix")

CATS = {"dev", "gpu", "gpu-ai", "grow", "home", "infra", "media", "monitoring",
        "proxy-local", "proxy-backup", "proxy-remote"}
rows = set()
for ln in lines:
    if ln.lstrip().startswith("|"):
        first = [c.strip() for c in ln.strip().strip("|").split("|")][0].strip("`* ")
        if first in CATS:
            rows.add(first)
        if first in ("backups", "personal"):
            bad("r6: the preflight table carries a %s row — those categories have no root app and stay off the roster (the [P2] matrix row arithmetic)" % first)
if len(rows) < 11:
    bad("r6: preflight table names %d of the 11 categories — the §6 table keeps one row per target (incl. the RULED proxy-backup warn-and-skip row)" % len(rows))
print("ok: r6")
PY
  then
    fail "r6: the runbook structure is wrong (reason printed above)"
  fi
  git rev-parse --verify --quiet "$BASE" >/dev/null ||
    fail "r6: CHUNK_BASE '$BASE' does not resolve (review passes the pre-chunk commit; default HEAD)"
  { git diff --name-only "$BASE" 2>/dev/null || true; git ls-files --others --exclude-standard; } |
    sort -u > "$WORK/changed.txt"
  if grep -Ev '^(\.agents/notes/|\.agents/plans/|tests/notes/|\.pipeline/)' "$WORK/changed.txt" | grep -q .; then
    offenders=$(grep -Ev '^(\.agents/notes/|\.agents/plans/|tests/notes/|\.pipeline/)' "$WORK/changed.txt" | head -20)
    fail "r6: C08 changed files beyond notes + plans + the runbook test surface (pure-docs chunk by the wave table — code edits route back through coord): $(printf '%s\n' "$offenders" | head -5)"
  fi
  ok "r6: sections 1..8 in order, appendix present, preflight covers all 11 categories, and the change set stays docs+tests (AC1)"
fi

rm -rf "$WORK"
printf 'PASS: argocd sync-fanout runbook contract checks (%d ok)\n' "$checks"
