#!/usr/bin/env bash
# argocd-hook relay runbook contract (2026/2026-11-cf-139-feat-argocd-webhook-sync, C03-fix):
# .agents/notes/2026-11-17-argocd-hook-relay.md — the human-executed operator
# runbook (Bitwarden items + per-cluster mcp-bot tokens + custom-values UUID
# fill + Actions vault key placement) with the live preflight table, smoke
# procedure, rollback and honest limitations.
#
# C03-fix re-cut (rulings R1-R4): the trigger is the main-sync hook-relay
# job, NOT a created webhook (R1 option (c)) — §4 states "nothing to create"
# and carries the never-create-a-raw-Forgejo-push-webhook race warning plus
# the R2 future-GitHub-webhook door; §2 adds the Actions vault pair
# (repo Actions secret ARGOCD_HOOK_SECRET = the argocd-hook item password,
# repo Actions var ARGOCD_HOOK_URL) with the two-vaults-must-agree sentence;
# the HMAC key file is hook-secret everywhere (R4); §5 smoke runs the
# workflow_dispatch trigger plus BOTH signed-curl dialects (hub prefixed and
# plain-hex with the exact awk recipe C04 uses); §7's leg 1 is the unset-
# keys kill switch; §8 carries the R1 no-op-at-old-revision limitation with
# next-push self-heal. t2 additionally greps the workflow file itself —
# every token the docs quote must exist there (AC6 parity, designed-red
# until C04 lands).
#
# Contract source: chunks/C03-fix.md "## Tests". AC trace:
# t1[AC1] t2[AC2/AC3/AC4/AC8 + AC6 parity] t3[AC3 rows] t4[AC4 render parity]
# t5[AC5] t6[diff scope]
# (AC7 is the all-suites regression set — plan Commands — re-run by review,
# not scripted a second time here.)
#
# Doc-vs-command law: this runbook's commands are all HUMAN-executed by ruling
# (the plan's Human-owned list) — the script therefore bars only the one thing
# no runbook may ever contain: a command line that mutates the
# services.<cat>.selfHeal cluster-secret annotations (OQ1: kill-switch kept).
# Prose MENTIONING the annotations staying untouched is required, not barred.
#
# t4 is a live-parity leg: it renders charts/argocd-hook the same way
# tests/services/argocd-hook-wiring.sh does (helm ladder, /tmp copy, dependency
# update) and diffs the runbook's pins against the render — C03 depends on C02,
# so a missing chart is a hard fail, while an unreachable chart repo degrades to
# a skip with a warning (same convention as the other helm suites).
#
# Run from the repo root:
#   bash tests/notes/argocd-hook-runbook.sh           # t1..t6
#   bash tests/notes/argocd-hook-runbook.sh t1 t2     # subset
# Env: CHUNK_BASE=<ref> for the t6 scope diff (review passes the pre-chunk
#      commit; default HEAD).
set -euo pipefail
export PATH=$HOME/.local/bin:$PATH   # FRICTION seed: helm discovery for the t4 parity leg

cd "$(git rev-parse --show-toplevel)"

RUNBOOK="${HOOK_RUNBOOK:-.agents/notes/2026-11-17-argocd-hook-relay.md}"
CHART="${HOOK_CHART:-charts/argocd-hook}"
PROXY_VALS="${HOOK_PROXY_VALS:-services/proxy-local/prod/values.yaml}"
CV="${HOOK_CUSTOM_VALUES:-custom-values/proxy-local/prod-values.yaml}"
# t2's parity legs grep the C04 caller; overridable for mutation testing.
WF="${MAIN_SYNC_WF:-.forgejo/workflows/main-sync.yaml}"
RELEASE="proxy-local-argocd-hook"
DOMAIN="test.example.com"
BASE="${CHUNK_BASE:-HEAD}"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

skip() {
  printf 'skip: %s\n' "$1" >&2
}

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 6); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-6]$ ]] || fail "unknown test id '$a' (expected t1..t6)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

command -v python3 >/dev/null 2>&1 || fail "python3 (+pyyaml) is required for the runbook walk"

WORK=$(mktemp -d /tmp/opencode/argocd-hook-runbook.XXXXXX)

if want t1 || want t2 || want t3 || want t4 || want t5; then
  [ -f "$RUNBOOK" ] ||
    fail "$RUNBOOK missing — C03 (the human runbook + preflight) is not implemented"
fi

# --- t1: existence, 8 numbered sections, human marker, annotation-command bar ----
if want t1; then
  if python3 - "$RUNBOOK" <<'PY'
import re, sys

runbook = sys.argv[1]
lines = open(runbook).read().splitlines()


def bad(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)


heads = []
for i, ln in enumerate(lines):
    m = re.match(r"^#{1,6}\s*(?:Section\s+)?(\d+)(?=[.:)\s—–-]|$)", ln)
    if m:
        heads.append((i, int(m.group(1))))
seq = []
for _, n in heads:
    if n not in seq:
        seq.append(n)
if seq != list(range(1, 9)):
    bad("t1: numbered section headers are %s, expected exactly 1..8 in order (C03 runbook sections are numbered and ordered by the plan)" % (seq,))
if len(re.findall(r"(?i)human[- \t]executed", "\n".join(lines))) == 0:
    bad("t1: no human-executed marker anywhere — every live command in this runbook is human-owned by ruling and must say so (AC1)")

# Fence scan: the only barred shapes are annotation-mutating commands and
# selfHeal=true set lines inside executable (fenced) blocks; prose mentions are
# REQUIRED (section 1 explains the kill-switch staying put).
in_fence = False
for i, ln in enumerate(lines):
    if re.match(r"^\s*```", ln):
        in_fence = not in_fence
        continue
    if not in_fence:
        continue
    if re.search(r"kubectl\b[^\n]*\b(annotate|patch|edit|replace)\b", ln) and re.search(r"selfHeal|cluster", ln):
        bad("t1: line %d is an annotation-mutating kubectl command in an executable block — the services.<cat>.selfHeal cluster secret is human-out-of-band and off-limits in this ticket (OQ1; AC1): %s" % (i + 1, ln.strip()[:120]))
    if re.search(r'selfHeal\s*=\s*\\?["\x27]?true', ln):
        bad("t1: line %d sets selfHeal=true inside an executable block (AC1 forbids the flip; the pattern must stay absent from commands, mention-only OK)" % (i + 1,))
print("ok: t1 — runbook exists with sections 1..8 in order, carries the human-executed marker, and its fenced commands never touch the selfHeal annotations (AC1)")
PY
  then
    ok "t1 passed (AC1)"
  else
    fail "t1: the runbook structure/command law is violated (reason printed above)"
  fi
fi

# --- t2: section-scoped content tokens (AC2) -------------------------------------
if want t2; then
  if python3 - "$RUNBOOK" "$WF" <<'PY'
import re, sys

runbook, wf_path = sys.argv[1:3]
lines = open(runbook).read().splitlines()
doc = "\n".join(lines)


def bad(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)


heads = {}
order = []
for i, ln in enumerate(lines):
    m = re.match(r"^#{1,6}\s*(?:Section\s+)?(\d+)(?=[.:)\s—–-]|$)", ln)
    if m and int(m.group(1)) not in heads:
        heads[int(m.group(1))] = i
        order.append(i)


def section(n):
    if n not in heads:
        bad("t2: no numbered section %d header" % n)
    nxt = heads[n] + 1
    while nxt < len(lines):
        m = re.match(r"^#{1,6}\s*(?:Section\s+)?(\d+)(?=[.:)\s—–-]|$)", lines[nxt])
        if m and int(m.group(1)) in heads and heads[int(m.group(1))] == nxt:
            break
        nxt += 1
    return "\n".join(lines[heads[n] + 1:nxt])


def need(text, pat, where, flags=0):
    if not re.search(pat, text, flags):
        bad("t2: %s lacks %r (AC2/plan section list)" % (where, pat))


old_fn = "github-" "webhook"  # retired key filename, split: no old literal in this harness

sec1 = section(1)
need(sec1, r"allowed_refs", "section 1 (ref model)")
need(sec1, r"refs/heads/main", "section 1 (shipped default set)")
need(sec1, r"allowedRefs", "section 1 (the widening values key)")
need(sec1, r"(?i)widen", "section 1 (widening procedure)")
need(sec1, r"(?i)(selfHeal|kill.?switch)", "section 1 (kill-switch posture)")
need(sec1, r"(?i)(stay|keep|untouched|never|not )", "section 1 (annotations stay)")
# C03-fix §1 origin/dialect/rename bullets:
need(sec1, r"main-sync", "section 1 (origin: the canonical trigger is the main-sync hook-relay job, R1)")
need(sec1, r"push-gh", "section 1 (the job fires AFTER push-gh advanced GitHub — the race resolution)")
need(sec1, r"X-Forgejo-Signature", "section 1 (dialect line: plain hex, R3)")
need(sec1, r"X-Hub-Signature-256", "section 1 (dialect line: prefixed form kept for the door)")
need(sec1, r"(?i)(first-present|no fallback)", "section 1 (selection rule: first present header wins, no cross-dialect fallback)")
need(sec1, r"hook-secret", "section 1 (rename line, R4)")

sec2 = section(2)
need(sec2, r"argocd-hook-tokens", "section 2 (Step 0 item name)")
need(sec2, r"(?i)bitwarden", "section 2 (Bitwarden items)")
need(sec2, r"(?i)generate-token", "section 2 (mcp-bot mint command shape, admin argocd account generate-token)")
need(sec2, r"OVERRIDE_NEEDED", "section 2 (sentinel fill posture)")
need(sec2, r"(?i)crash.?loop", "section 2 (accepted crash-loop sentence, OQ5)")
need(sec2, r"(?i)(post.?merge|merge first|through the merge)", "section 2 (OQ5 merge-first wording)")
need(sec2, r"custom-values/proxy-local/prod-values\.yaml", "section 2 (the file C02 created)")
CATS = ["dev", "gpu", "gpu-ai", "grow", "home", "infra", "media", "monitoring", "proxy-local", "proxy-backup", "proxy-remote"]
missing = [c for c in CATS if not re.search(r"(?<![\w.-])%s(?![\w-])" % re.escape(c), sec2)]
if missing:
    bad("t2: section 2 (Step 0) does not name the token field(s) %s — the Bitwarden item's one-field-per-category list must be complete (AC2)" % missing)
# C03-fix §2: four setup legs now — Bitwarden, mints, UUID fill, ACTIONS VAULT.
need(sec2, r"ARGOCD_HOOK_SECRET", "section 2 (repo Actions secret, exact key name — R4/vault leg)")
need(sec2, r"ARGOCD_HOOK_URL", "section 2 (repo Actions var, exact key name — mesh-or-public choice is the owner's)")
need(sec2, r"(?i)actions", "section 2 (the vault is repo Actions settings, not the cluster)")
need(sec2, r"(?i)agree", "section 2 (both vaults must AGREE — the sentence that makes a 401 diagnosable)")
need(sec2, r"401", "section 2 (the disagreement symptom named where the keys are placed)")
need(sec2, r"hook-secret", "section 2 (key/file references renamed, R4)")
if re.search(r"(?i)github hmac", sec2):
    bad("t2: section 2 still frames the HMAC as GitHub's — the shared secret is relay<->main-sync under R1/R3 (AC2)")

sec4 = section(4)
# C03-fix rewrote §4 wholesale: trigger = the main-sync hook-relay job,
# nothing to create, the unset-keys kill switch, and the R2 door.
need(sec4, r"hook-relay", "section 4 (the trigger names the job)")
need(sec4, r"(?i)nothing to create", "section 4 (R1 option (c) headline: no webhook is created anywhere)")
need(sec4, r"push-gh", "section 4 (fires after push-gh lands GitHub on prod; dev/unset-ROLE fire nothing)")
need(sec4, r"(?i)(must not|never|do not|don.t|no reason to) create[^.]{0,80}webhook|webhook[^.]{0,80}must not (be )?created?", "section 4 (the RACE WARNING: a raw Forgejo push webhook fires before push-gh and would sync the PREVIOUS revision — the doc must forbid creating one, [P §3])")
need(sec4, r"(?i)spencerslab\.com", "section 4 (the public edge stays as the future door, R2)")
need(sec4, r"(?i)(door|future|if you ever|if the owner ever)", "section 4 (R2 wording: the entry is a documented door, not the shipped trigger)")
need(sec4, r"GitHub", "section 4 (the race-free future webhook is the GitHub-repo one — apps track GitHub under (c))")
need(sec4, r"(?i)unset[^.]{0,120}ARGOCD_HOOK|ARGOCD_HOOK[^.]{0,120}unset", "section 4 (the unset-keys skip IS the kill switch, same sentence as §7)")

sec5 = section(5)
# C03-fix §5: (a) workflow_dispatch trigger smoke (fallbacks make the
# payload without a push event), (b) signed curl in BOTH dialects with the
# exact C04 recipes, (b′) non-matching ref 200, (c) real merge with mirror
# latency.
need(sec5, r"workflow_dispatch", "section 5 (smoke a: dispatch main-sync on prod — push-gh no-ops when up to date, hook-relay still fires)")
need(sec5, r"hook-relay", "section 5 (smoke a greps the JOB's log line)")
need(sec5, r"code=202", "section 5 (smoke a: the job's audit echo token — must match the workflow exactly, parity leg below)")
need(sec5, r"(?i)fallback", "section 5 (smoke a: the dispatch payload comes from the fallback defaults, call-out required)")
need(sec5, r"202", "section 5 (smoke b: accepted push answers 202)")
need(sec5, r"(?i)(curl|synthetic|signed)", "section 5 (smoke b: signed synthetic push recipes)")
need(sec5, r"sha256=", "section 5 (smoke b: the hub prefixed recipe stays documented — the door's dialect)")
need(sec5, r"X-Forgejo-Signature", "section 5 (smoke b: the plain-hex recipe, C04's dialect)")
need(sec5, r"awk '\{print \$NF\}'", "section 5 (smoke b: the plain-hex recipe must be byte-identical to the workflow's signing line — grep it there too, parity leg below)")
need(sec5, r"(?i)(401)", "section 5 (wrong-value expectations documented for the signed curls)")
need(sec5, r"(?i)(no.?op|not in|non.?allowed|foreign)", "section 5 (smoke b′: non-allowed-ref push proves the filter live)")
need(sec5, r"push-gh", "section 5 (smoke c: latency now includes the mirror push-gh step)")

sec8 = section(8)
need(sec8, r"(?i)no-op.{0,40}old revision|old revision.{0,40}no-op", "section 8 (R1 documented limitation: fan-out trigger failure lands the push as a no-op at the old revision)")
need(sec8, r"(?i)next push", "section 8 (self-heal wording: the next push covers it — the fan-out is SHA-agnostic)")
need(sec8, r"(?i)redeliver", "section 8 (no Actions redeliveries exist — the asymmetry vs a real webhook must be stated)")

# Doc-wide forbidden sweep:
if old_fn in doc:
    bad("t2: the retired key filename '%s' survives in the runbook (AC3: grep 0 — R4 rename ripple)" % old_fn)
# The creation-step tell is the UI path token (`Settings → Webhooks → Add
# webhook`). It must vanish doc-wide; the RACE WARNING sentence ("must NOT
# be created") is required content and deliberately not matched here.
if re.search(r"(?i)add webhook", doc):
    bad("t2: a webhook-creation step survives (`add webhook`) — AC1 bars ANY platform's webhook creation as a required step; R1: the mirror job IS the webhook, and the R2 door may describe a future choice, never instruct the button")

# AC6 parity: every token the docs quote about the job must exist in the
# shipped workflow. Designed-red until C04 lands (job absent).
try:
    wf_raw = open(wf_path).read()
except OSError as ex:
    bad("t2: cannot read %s for the parity sweep (C03-fix depends on C04): %s" % (wf_path, ex))
for tok in ("hook-relay", "vars.ARGOCD_HOOK_URL", "secrets.ARGOCD_HOOK_SECRET",
            "X-Forgejo-Signature", "X-GitHub-Event: push", "workflow_dispatch",
            "awk '{print $NF}'", "relay accepted", "code="):
    if tok not in wf_raw:
        bad("t2: parity — the runbook quotes %r but %s does not contain it (AC6: reviewer greps the workflow for each quoted string; docs-vs-caller drift is the bug class this leg kills)" % (tok, wf_path))
print("ok: t2 — sections 1/2 carry origin+dialect+rename, the Actions vault pair with the must-agree sentence and hook-secret; §4 is the nothing-to-create job trigger with the race warning, the R2 door and the unset kill switch; §5 has the dispatch smoke and both curl dialects with the exact C04 recipe; §8 states the R1 no-op/next-push-self-heal/redelivery asymmetry; zero retired-name or webhook-creation hits doc-wide; every quoted job token exists in main-sync.yaml (AC1-AC4/AC6/AC8)")
PY
  then
    ok "t2 passed (AC2)"
  else
    fail "t2: runbook section content is incomplete (reason printed above)"
  fi
fi

# --- t3: preflight roster (AC3) ---------------------------------------------------
if want t3; then
  if python3 - "$RUNBOOK" <<'PY'
import re, sys

runbook = sys.argv[1]
lines = open(runbook).read().splitlines()


def bad(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)


CATS = ["dev", "gpu", "gpu-ai", "grow", "home", "infra", "media", "monitoring", "proxy-local", "proxy-backup", "proxy-remote"]
rows = {}
for ln in lines:
    if not ln.lstrip().startswith("|"):
        continue
    cells = [c.strip() for c in ln.strip().strip("|").split("|")]
    if not cells:
        continue
    first = cells[0].strip("`* ")
    if first in CATS:
        rows[first] = cells
    if first in ("backups", "personal"):
        bad("t3: preflight table carries a %s row — those categories have no root app and must stay off the roster (AC3)" % first)

missing = [c for c in CATS if c not in rows]
if missing:
    bad("t3: no preflight row for %s (AC3 demands one row per the 11 categories)" % missing)

not_reachable = {c for c, cells in rows.items() if "not-reachable" in " ".join(cells)}
if not {"proxy-backup", "proxy-remote"} <= not_reachable:
    bad("t3: not-reachable rows are %s, expected at least [proxy-backup, proxy-remote] — the two clusters with no readonly MCP (EXPLORE §5)" % sorted(not_reachable))
extra = sorted(not_reachable - {"proxy-backup", "proxy-remote", "media"})
if extra:
    bad("t3: categories %s are marked not-reachable but every cluster except proxy-remote/proxy-backup and the media retry case has a readonly MCP probe — AC3's row arithmetic is 9 probe rows (+media retried-or-manual) + 2 not-reachable" % extra)

for c, cells in rows.items():
    body = " ".join(cells)
    if not re.search(r"gated-off|automated-present|not-reachable", body):
        bad("t3: row %s has no status token from {gated-off, automated-present, not-reachable}: %s" % (c, body[:120]))
    if c not in not_reachable and len(cells) < 5:
        bad("t3: row %s has %d cells, expected >=5 (cluster | root syncPolicy | child sample | OutOfSync set | probe status)" % (c, len(cells)))

reason = [ln for ln in lines
          if not ln.lstrip().startswith("|")
          and "backups" in ln and "personal" in ln
          and re.search(r"(?i)(no|without|never).{0,40}root", ln)]
if not reason:
    bad("t3: the one-line reason for omitting backups/personal (no root apps) is missing (AC3)")
print("ok: t3 — all 11 roster rows present with {syncPolicy|child|OutOfSync|status} columns, exactly the two no-MCP clusters marked not-reachable, backups/personal absent with their stated reason (AC3)")
PY
  then
    ok "t3 passed (AC3)"
  else
    fail "t3: the preflight table does not meet the roster contract (reason printed above)"
  fi
fi

# --- t4: live parity against the C02 render (AC4) ---------------------------------
if want t4; then
  [ -d "$CHART" ] ||
    fail "t4: $CHART missing — AC4 parity pins against C02's shipped chart; the runbook cannot be verified before C02 lands (wave order)"

  find_helm() {
    # Each branch prints exactly one path AND returns 0 (dev-mcp-fleet F01 lesson).
    local cand
    if [ -n "${HELM_BIN:-}" ] && [ -x "${HELM_BIN}" ]; then
      printf '%s' "$HELM_BIN"
      return 0
    fi
    if command -v helm >/dev/null 2>&1; then
      command -v helm
      return 0
    fi
    if [ -x /home/coder/.local/bin/helm ]; then
      printf '%s' "/home/coder/.local/bin/helm"
      return 0
    fi
    cand=$(find /tmp/opencode -maxdepth 4 -type f -name helm -perm -u+x 2>/dev/null | head -n 1 || true)
    if [ -n "$cand" ]; then
      printf '%s' "$cand"
      return 0
    fi
    return 1
  }

  helm_bin=$(find_helm || true)
  if [ -z "$helm_bin" ]; then
    skip "t4: no helm binary; the runbook<->render parity leg was not run (the doc-vs-render pins are AC4 — re-run where helm resolves)"
  else
    chart_copy="$WORK/chart-copy"
    cp -R "$CHART"/. "$chart_copy"/
    dep_log="$chart_copy/dependency-update.log"
    if ! (cd "$chart_copy" && "$helm_bin" dependency update .) >"$dep_log" 2>&1; then
      skip "t4: helm dependency update could not reach the chart repo here; parity leg not run (log kept at $dep_log)"
      helm_bin=""
    fi
  fi
  if [ -n "$helm_bin" ]; then
    render="$WORK/render.yaml"
    if ! "$helm_bin" template "$RELEASE" "$chart_copy" \
        --set "domain=$DOMAIN" \
        --set "bitwardenIds.argocd-hook-secret=test-uuid" \
        --set "bitwardenIds.argocd-hook-tokens=test-uuid" \
        >"$render" 2>"$WORK/render.err"; then
      tail -n 20 "$WORK/render.err" >&2
      fail "t4: helm template of $CHART failed (log kept at $WORK/render.err)"
    fi
    if python3 - "$RUNBOOK" "$render" "$PROXY_VALS" "$CV" "$RELEASE" <<'PY'
import json, re, sys, yaml

runbook_path, render, proxy_vals_path, cv_path, release = sys.argv[1:6]
rb = open(runbook_path).read()


def bad(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)


def load(path):
    lines = []
    with open(path) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}


docs = [d for d in yaml.safe_load_all(open(render)) if d]
svc_names = sorted((d.get("metadata") or {}).get("name") for d in docs if d.get("kind") == "Service")
if release not in svc_names:
    bad("t4: rendered Service names %s do not include %s (C02 AC3 pinned the pair; the runbook can only be right if the render is)" % (svc_names, release))
hub_service = (((load(proxy_vals_path).get("proxy") or {}).get("subdomains") or {}).get("argocd-hook") or {}).get("service")
if hub_service != release:
    bad("t4: hub subdomain service is %r, expected %s" % (hub_service, release))
if release not in rb:
    bad("t4: the runbook never names the rendered Service/child-app %r — step 3's sync target and the hub entry must quote the shipped name (AC4 parity)" % release)

CATS = {"dev", "gpu", "gpu-ai", "grow", "home", "infra", "media", "monitoring", "proxy-local", "proxy-backup", "proxy-remote"}
blob = None
for d in docs:
    if d and d.get("kind") == "ConfigMap" and "targets.json" in (d.get("data") or {}):
        blob = json.loads(d["data"]["targets.json"])
if blob is None:
    bad("t4: render has no targets.json ConfigMap")
json_cats = {e.get("name") for e in (blob.get("targets") or [])}
if json_cats != CATS:
    bad("t4: rendered roster categories %s != the 11 the plan's fan-out roster names %s" % (sorted(json_cats), sorted(CATS)))
table_cats = set()
for ln in rb.splitlines():
    if ln.lstrip().startswith("|"):
        first = [c.strip() for c in ln.strip().strip("|").split("|")][0].strip("`* ")
        if first in CATS:
            table_cats.add(first)
if table_cats != json_cats:
    bad("t4: runbook table roster %s != rendered targets.json roster %s (the runbook must document the SHIPPED list, not the drafted one)" % (sorted(table_cats), sorted(json_cats)))

cv = load(cv_path)
sent = [k for k, v in ((cv.get("argocd-hook") or {}).get("bitwardenIds") or {}).items() if v == "OVERRIDE_NEEDED"]
if len(sent) != 2:
    bad("t4: custom-values argocd-hook.bitwardenIds has %d OVERRIDE_NEEDED lines, expected exactly 2 until the owner fills post-merge (OQ5)" % len(sent))
if rb.count("OVERRIDE_NEEDED") < 2:
    bad("t4: the runbook quotes OVERRIDE_NEEDED fewer than 2 times — step 0 must show both sentinel lines the owner replaces (AC4 parity)")

# C03-fix parity against the RENAMED render (waves 4-5 ship the new key):
# the filename the §2/§5 instructions hand the owner must be the filename
# the ExternalSecret actually writes into the mounted secret dir.
render_raw = open(render).read()
if "secretKey: hook-secret" not in render_raw:
    bad("t4: the rendered ES does not carry secretKey hook-secret — the runbook's key story cannot precede C02-fix's render (parity pins the SHIPPED filename)")
if "hook-secret" not in rb:
    bad("t4: the runbook never names hook-secret while the render ships it (R4 parity: the doc follows the chart, not the draft)")
print("ok: t4 — runbook Service name == hub entry == render; table roster == targets.json roster (11 categories); both OVERRIDE_NEEDED quotes match the shipped custom-values block; the render's secretKey hook-secret and the runbook key story agree (AC4/C03-fix)")
PY
    then
      ok "t4 passed (AC4)"
    else
      fail "t4: runbook-vs-render parity violated (reason printed above)"
    fi
  fi
fi

# --- t5: rollback legs (AC5) -------------------------------------------------------
if want t5; then
  if python3 - "$RUNBOOK" <<'PY'
import re, sys

lines = open(sys.argv[1]).read().splitlines()


def bad(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)


head7 = None
head8 = None
for i, ln in enumerate(lines):
    m = re.match(r"^#{1,6}\s*(?:Section\s+)?(\d+)(?=[.:)\s—–-]|$)", ln)
    if not m:
        continue
    n = int(m.group(1))
    if n == 7 and head7 is None:
        head7 = i
    if n == 8 and head8 is None:
        head8 = i
        break
if head7 is None:
    bad("t5: no section 7 (Rollback) header")
body = "\n".join(lines[head7 + 1:head8 if head8 is not None else len(lines)])

# C03-fix AC5: leg 1 is the INSTANT source stop — unset the prod instance's
# ARGOCD_HOOK_URL/ARGOCD_HOOK_SECRET (Actions UI, human; the job then
# warns-and-skips every run, fleet reverts to manual sync, no git churn).
# The GitHub webhook disable survives only as disable-IF-EXISTS wording
# under the R2 door; Recent Deliveries stays. leg 2 (revert PR) stands and
# must note the revert also removes the hook job.
checks = (
    (r"(?i)unset[^.]{0,120}ARGOCD_HOOK|ARGOCD_HOOK[^.]{0,120}unset", "leg 1: the unset-keys kill switch (exact Actions key names)"),
    (r"(?i)(warn|skip)", "the job's warn-and-skip consequence of the unset"),
    (r"(?i)actions", "leg 1 lives in the repo Actions settings (no git churn)"),
    (r"Recent Deliveries", "Recent Deliveries/redelivery inspection is named (door-era residue note, stays)"),
    (r"(?i)revert", "leg 2: the git-revert path for the proxy-local entries + chart"),
    (r"(?i)hook.?relay|hook job", "leg 2 notes the revert also removes the hook-relay job"),
    (r"(?i)residual|nothing else changes|exactly back|back to (the )?(today|manual)|manual workflow", "the no-residual-impact statement (syncPolicy never moved, no prune ever ran)"),
)
missing = [what for pat, what in checks if not re.search(pat, body)]
if missing:
    bad("t5: rollback section lacks %s (AC5: unset-keys leg 1 + revert leg 2 + the explicit no-residual argument)" % missing)
if re.search(r"(?i)(settings|web ?hooks)\s*(→|->)\s*[^.\n]{0,60}disable", body):
    # Allowed ONLY as a conditional door-era sentence, never the headline leg.
    if not re.search(r"(?i)(if (one|it|a github)|ever created|were created|under the)", body):
        bad("t5: rollback frames webhook-disable as the unconditional leg-1 — the GitHub webhook exists only if the owner ever used the R2 door; conditional wording required (AC5)")
print("ok: t5 — rollback leg 1 is the unset-keys Actions kill switch with the warn-and-skip consequence, webhook-disable survives only conditional (door-era), the revert leg names the hook-relay removal, Recent Deliveries and the no-residual statement stand (AC5/C03-fix)")
PY
  then
    ok "t5 passed (AC5)"
  else
    fail "t5: the rollback section is incomplete (reason printed above)"
  fi
fi

# --- t6: diff scope (AC7) ----------------------------------------------------------
if want t6; then
  git rev-parse --verify --quiet "$BASE" >/dev/null ||
    fail "t6: CHUNK_BASE '$BASE' does not resolve (review passes the pre-chunk commit; default HEAD)"
  { git diff --name-only "$BASE" 2>/dev/null || true; git ls-files --others --exclude-standard; } |
    sort -u > "$WORK/changed.txt"
  if grep -Ev '^(\.agents/notes/2026-11-17-argocd-hook-relay\.md$|\.agents/plans/|tests/[^/]+/argocd-hook-|tests/services/forgejo-main-sync\.sh$|\.pipeline/)' "$WORK/changed.txt" | grep -q .; then
    offenders=$(grep -Ev '^(\.agents/notes/2026-11-17-argocd-hook-relay\.md$|\.agents/plans/|tests/[^/]+/argocd-hook-|tests/services/forgejo-main-sync\.sh$|\.pipeline/)' "$WORK/changed.txt" | head -20)
    fail "t6: C03 changed files beyond the runbook + plan folder + test surface (AC7 — probe-found defects route back as review findings, not silent edits here): $offenders"
  fi
  ok "t6: change set is runbook + chunk notes + test surface only (AC7)"
fi

rm -rf "$WORK"
printf 'PASS: argocd-hook runbook contract checks (%d ok)\n' "$checks"
