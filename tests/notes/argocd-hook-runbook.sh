#!/usr/bin/env bash
# argocd-hook relay runbook contract (2026/2026-11-cf-139-feat-argocd-webhook-sync, C03):
# .agents/notes/2026-11-17-argocd-hook-relay.md — the human-executed operator
# runbook (Bitwarden items + per-cluster mcp-bot tokens + custom-values UUID
# fill + GitHub webhook) with the live preflight table, smoke procedure,
# rollback and honest limitations.
#
# Contract source: chunks/C03.md "## Tests". AC trace:
# t1[AC1] t2[AC2] t3[AC3] t4[AC4] t5[AC5] t6[AC7]
# (AC6 is the plan-Commands suite — C01/C02 harnesses + helm ladder — re-run by
# review, not scripted a second time here.)
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
  if python3 - "$RUNBOOK" <<'PY'
import re, sys

runbook = sys.argv[1]
lines = open(runbook).read().splitlines()


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


sec1 = section(1)
need(sec1, r"allowed_refs", "section 1 (ref model)")
need(sec1, r"refs/heads/main", "section 1 (shipped default set)")
need(sec1, r"allowedRefs", "section 1 (the widening values key)")
need(sec1, r"(?i)widen", "section 1 (widening procedure)")
need(sec1, r"(?i)(selfHeal|kill.?switch)", "section 1 (kill-switch posture)")
need(sec1, r"(?i)(stay|keep|untouched|never|not )", "section 1 (annotations stay)")

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

sec4 = section(4)
need(sec4, r"argocd-hook\.spencerslab\.com", "section 4 (payload URL host)")
need(sec4, r"application/json", "section 4 (content type — form-encoded unsupported)")
need(sec4, r"(?i)\bpush\b", "section 4 (event)")
need(sec4, r"(?i)secret", "section 4 (HMAC secret placement)")

sec5 = section(5)
need(sec5, r"(?i)ping", "section 5 (smoke a: GitHub Test ping)")
need(sec5, r"202", "section 5 (smoke b: accepted push answers 202)")
need(sec5, r"(?i)(curl|synthetic|signed)", "section 5 (smoke b: signed synthetic push recipe)")
need(sec5, r"(?i)(no.?op|not in|non.?allowed|foreign)", "section 5 (smoke b′: non-allowed-ref push proves the filter live)")
print("ok: t2 — section 1 states the allowed_refs config-list + widening; Step 0 names both items, all 11 fields, the mint command, the merge-first/OVERRIDE_NEEDED/crash-loop posture and the exact custom-values file; the webhook step pins URL/content-type/secret/push; the smoke step covers ping + 202 + the non-allowed-ref case (AC2)")
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
print("ok: t4 — runbook Service name == hub entry == render; table roster == targets.json roster (11 categories); both OVERRIDE_NEEDED quotes match the shipped custom-values block (AC4)")
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

checks = (
    (r"(?i)(disable|remove|delete)[^\n]{0,60}webhook|webhook[^\n]{0,60}(disable|remove|delete)", "leg 1: the GitHub webhook disable/remove step"),
    (r"Recent Deliveries", "Recent Deliveries/redelivery inspection is named"),
    (r"(?i)revert", "leg 2: the git-revert path for the proxy-local entries + chart"),
    (r"(?i)residual|nothing else changes|exactly back|back to (the )?(today|manual)|manual workflow", "the no-residual-impact statement (syncPolicy never moved, no prune ever ran)"),
)
missing = [what for pat, what in checks if not re.search(pat, body)]
if missing:
    bad("t5: rollback section lacks %s (AC5: both legs + the explicit no-residual argument)" % missing)
print("ok: t5 — rollback names webhook disable with Recent Deliveries, the revert path, and the no-residual statement (AC5)")
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
  if grep -Ev '^(\.agents/notes/2026-11-17-argocd-hook-relay\.md$|\.agents/plans/|tests/[^/]+/argocd-hook-|\.pipeline/)' "$WORK/changed.txt" | grep -q .; then
    offenders=$(grep -Ev '^(\.agents/notes/2026-11-17-argocd-hook-relay\.md$|\.agents/plans/|tests/[^/]+/argocd-hook-|\.pipeline/)' "$WORK/changed.txt" | head -20)
    fail "t6: C03 changed files beyond the runbook + plan folder + test surface (AC7 — probe-found defects route back as review findings, not silent edits here): $offenders"
  fi
  ok "t6: change set is runbook + chunk notes + test surface only (AC7)"
fi

rm -rf "$WORK"
printf 'PASS: argocd-hook runbook contract checks (%d ok)\n' "$checks"
