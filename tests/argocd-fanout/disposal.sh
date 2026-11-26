#!/usr/bin/env bash
# Relay-layer disposal contract (2026/2026-11-cf-139-feat-argocd-webhook-sync, C07):
# the shipped-but-never-deployed relay layer is branch-local `git rm`'d entirely
# (ruling R6; [P2] proved no Deployment, no Ingress, unfilled sentinels — zero
# cluster-side choreography, rollback = revert the PR). This suite pins the
# ABSENCE half: directories, trio hunks, the custom-values block, the two
# relay-era suites, and the sentinel pairing recomputed post-deletion; plus the
# containers-build detect-guard proof that a deleted container dir can never
# re-enter the CI build set (RESEARCH §5.7). (Post-rebase the caller is
# build-containers.yaml, invoked by main-sync's prod-main fan; the detect
# script and this pin's contract are unchanged.)
#
# The old 1:1 sentinel-pairing checks (charts side) become an absence-pair
# check here: the relay-era bitwardenIds block is gone AND every surviving
# OVERRIDE_VIA_CUSTOM_VALUES sentinel is still backed by a UUID line (no
# orphan, no un-filled sentinel).
#
# NOTE the deliberate scope exclusions (C07 AC3): `.forgejo/` cleanliness is
# C06's t10 duty (chunk separation under the parallel wave — disposal must not
# gate the job rename, and the hook job's disappearance is pinned by t3's job
# set + t10's file-wide ban, not here); `.agents/` history files and the
# old-path runbook are out of the sweep (the ticket tree keeps history; C08
# renames the runbook and its suite's r1 owns the stale-path ban).
#
# Needle discipline (AC3): the relay component name is assembled from
# fragments at run time so this file never contains the joined literal and the
# tests/-inclusive sweep cannot self-match.
#
# Run from anywhere in the worktree:
#   bash tests/argocd-fanout/disposal.sh             # d1..d7
#   bash tests/argocd-fanout/disposal.sh d1 d6       # subset
# Env: DISPOSAL_ROOT=<tree> points the suite at a synthetic tree
#      (green-shape proofs; must be a git checkout for the ls-files/diff legs);
#      CHUNK_BASE=<ref> for the d7 scope diff (review passes the pre-chunk
#      commit; default HEAD).
set -euo pipefail

ROOT="${DISPOSAL_ROOT:-$(git rev-parse --show-toplevel)}"
cd "$ROOT"

N1="argocd-"
N2="hook"
RELAY="${N1}${N2}"                       # the relay component name, joined only here
RELAY_SUITES=("${RELAY}-relay.sh" "${RELAY}-wiring.sh")
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

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 7); do WANT["d$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^d[1-7]$ ]] || fail "unknown leg id '$a' (expected d1..d7)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

command -v python3 >/dev/null 2>&1 || fail "python3 (+pyyaml) is required for the structural legs"
WORK=$(mktemp -d /tmp/opencode/argocd-fanout-disposal.XXXXXX)

# --- d1: relay directories absent on disk and in git (AC2) -----------------------
if want d1; then
  for d in "charts/$RELAY" "containers/$RELAY"; do
    [ ! -e "$d" ] || fail "d1: $d still exists on disk — C07's git rm has not landed (the port is done in C05; the old home is disposal-bound)"
  done
  tracked=$(git ls-files -- "charts/$RELAY" "containers/$RELAY")
  [ -z "$tracked" ] || fail "d1: git ls-files still tracks relay paths: $(printf '%s' "$tracked" | head -5)"
  ok "d1: charts/ and containers/ relay dirs absent on disk AND untracked (AC2)"
fi

# --- d2: relay-needle sweep, five scope dirs, zero hits (AC3) ---------------------
if want d2; then
  # Scope is exactly the five dirs; tests/ is included and can only stay
  # green because every suite in the reopen2 test surface assembles the
  # joined literal from fragments (this file's own technique).
  hits=$(grep -rn --include='*' -e "$RELAY" charts/ containers/ services/ custom-values/ tests/ 2>/dev/null || true)
  if [ -n "$hits" ]; then
    fail "d2: $RELAY needle survives $(printf '%s\n' "$hits" | wc -l) place(s), e.g.:
$(printf '%s\n' "$hits" | head -8)
  — the five scope dirs must be relay-free (AC3; .forgejo/ is C06's duty, .agents/ is history)"
  fi
  ok "d2: joined relay needle has zero hits across charts/ containers/ services/ custom-values/ tests/ (AC3)"
fi

# --- d3: relay-era suites absent, unreferenced (AC6) ------------------------------
if want d3; then
  for f in "tests/containers/${RELAY_SUITES[0]}" "tests/services/${RELAY_SUITES[1]}"; do
    [ ! -e "$f" ] || fail "d3: $f still exists — the relay suites die with their implementation (C07's removal set; the test session left them designed-to-die on purpose)"
  done
  for name in "${RELAY_SUITES[@]}"; do
    refs=$(grep -rlnF "$name" tests/ 2>/dev/null || true)
    [ -z "$refs" ] || fail "d3: $(printf '%s\n' "$refs" | tr '\n' ' ') still reference the retired suite basename $name"
  done
  ok "d3: both relay suites absent; no surviving tests/ file names them (AC6)"
fi

# --- d4: proxy-local values structurally relay-free (AC4) -------------------------
if want d4; then
  if ! python3 - services/proxy-local/prod/values.yaml "$RELAY" <<'PY'
import re, sys

path, relay = sys.argv[1:3]


def load(p):
    # chart values carry YAML anchors/aliases a safe_load of the raw slice
    # would choke on; strip them (the same helper the shipped wiring suite
    # uses — anchor identity is irrelevant to key-set questions).
    lines = []
    with open(p) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    import yaml
    return yaml.safe_load(''.join(lines)) or {}


doc = load(path)
charts = doc.get("charts") or {}
subs = ((doc.get("proxy") or {}).get("subdomains") or {})
if relay in charts:
    print("FAIL: d4: %s still has a charts: entry (the trio hunk is disposal-bound; with the chart gone the appset would render an Application for a nonexistent chart)" % path, file=sys.stderr)
    sys.exit(1)
if relay in subs:
    print("FAIL: d4: %s still has the proxy.subdomains %s entry — the R2 public door dies with its backend (plan Disposal bullet: crowdsec-only exception removed)" % (path, relay), file=sys.stderr)
    sys.exit(1)
print("ok: d4")
PY
  then
    fail "d4: the proxy-local values are not relay-free (reason printed above)"
  fi
  ok "d4: services/proxy-local charts:/proxy.subdomains key sets are structurally relay-free (AC4)"
fi

# --- d5: custom-values block absent + sentinel pairing recomputed (AC4) -----------
if want d5; then
  if ! python3 - custom-values/proxy-local/prod-values.yaml services/proxy-local/prod/values.yaml "$RELAY" <<'PY'
import re, sys

cv_path, sv_path, relay = sys.argv[1:4]
import yaml


def load(p):
    lines = []
    with open(p) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}


def leaves(node, path=(), out=None):
    # bitwardenIds leaf map: (chart-slice path, key) -> value. The pairing
    # questions are per-KEY (the override slices live under chart names on
    # the custom-values side and may sit at the top or under a chart on the
    # services side), so keys are the join column.
    if out is None:
        out = {}
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "bitwardenIds" and isinstance(v, dict):
                for kk, vv in v.items():
                    out[kk] = vv
            else:
                leaves(v, path + (k,), out)
    return out


def bad(msg):
    print("FAIL: d5: %s" % msg, file=sys.stderr)
    sys.exit(1)


cv = load(cv_path)
if relay in cv:
    bad("%s still carries the %s bitwardenIds block (OQ5's never-filled pair is moot — nothing crash-loops any more)" % (cv_path, relay))
cv_leafs = leaves(cv)
unfilled = [k for k, v in cv_leafs.items() if v == "OVERRIDE_NEEDED"]
if unfilled:
    bad("un-filled OVERRIDE_NEEDED sentinels survive after the deletion: %s (the crash-loop posture died with the chart; no sentinel may ship unfilled now)" % unfilled)
for orphan in ("%s-secret" % relay, "%s-tokens" % relay):
    if orphan in cv_leafs:
        bad("relay-era leaf %r survives as an orphan (its block was deleted as a unit; a leftover line would silently re-wire a consumed key)" % orphan)

sv = load(sv_path)
sentinels = [k for k, v in leaves(sv).items() if v == "OVERRIDE_VIA_CUSTOM_VALUES"]
uuids = {k for k, v in cv_leafs.items() if re.fullmatch(r"[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}", str(v))}
missing = sorted(set(sentinels) - uuids)
if missing:
    bad("sentinel without a custom-values UUID: %s (custom-values bitwardenIds leaves seen: %s) — the repo rule is 1:1: every OVERRIDE_VIA_CUSTOM_VALUES placeholder matched by a custom-values entry — post-deletion parity must HOLD, not degrade" % (missing, sorted(cv_leafs)))
print("ok: d5")
PY
  then
    fail "d5: the custom-values disposal/pairing contract is violated (reason printed above)"
  fi
  ok "d5: relay bitwardenIds block gone; zero un-filled sentinels or orphans; surviving sentinel↔UUID pairing recomputed 1:1 (AC4)"
fi

# --- d6: build-containers detect can never re-enter a deleted dir (AC5) ------------
if want d6; then
  # Static pin: the HEAD `-f` guard line RESEARCH §5.7 cites. This leg is
  # designed-GREEN today and after C07 — it is the regression pin C07 rides
  # (the build lane needs no edit precisely because this line exists).
  grep -Eq '\[ -f "containers/\$n/Dockerfile" \]' scripts/forgejo-container-detect.sh ||
    fail "d6: scripts/forgejo-container-detect.sh lost its [ -f containers/\$n/Dockerfile ] HEAD guard — without it a deleted container dir re-enters the build set from a diff range and CI fails on a phantom name"

  # Functional no-op proof: a range that ADDED then DELETED a container dir
  # yields the empty build set, and a dispatch that NAMES the dead dir is
  # likewise filtered (the gate applies to every input per the detect
  # contract — the shape cf-139's branch history would hit).
  SCRATCH="$WORK/detect-repo"
  mkdir -p "$SCRATCH/containers/deadimg" "$SCRATCH/scripts"
  cp scripts/forgejo-container-detect.sh "$SCRATCH/scripts/"
  (
    cd "$SCRATCH"
    git init -q .
    git config user.email disposal@test.invalid
    git config user.name "disposal suite"
    printf 'FROM scratch\n' > containers/deadimg/Dockerfile
    git add -A && git commit -q -m "add deadimg"
    c1=$(git rev-parse HEAD)
    git rm -q -r containers/deadimg
    git commit -q -m "delete deadimg"
    c2=$(git rev-parse HEAD)
    out=$(EVENT_NAME=push EVENT_BEFORE="$c1" SHA="$c2" bash scripts/forgejo-container-detect.sh detect 2>/dev/null)
    [ "$out" = "[]" ] || { echo "d6-func: push-range detect returned $out, expected [] (a deleted dir must never enter the build set)"; exit 1; }
    out=$(EVENT_NAME=workflow_dispatch MANUAL_CONTAINERS=deadimg bash scripts/forgejo-container-detect.sh detect 2>/dev/null)
    [ "$out" = "[]" ] || { echo "d6-func: dispatch of a deleted name returned $out, expected [] (the HEAD guard covers dispatch inputs too)"; exit 1; }
  ) || fail "d6: the detect no-op proof failed (detail above)"
  ok "d6: detect-guard present AND proven by a synthetic add-then-delete range + a dispatch naming the dead dir — both yield [] (AC5, RESEARCH §5.7)"
fi

# --- d7: gate-untouched diff scope (AC7) ------------------------------------------
if want d7; then
  git rev-parse --verify --quiet "$BASE" >/dev/null ||
    fail "d7: CHUNK_BASE '$BASE' does not resolve (review passes the pre-chunk commit; default HEAD)"
  { git diff --name-only "$BASE" 2>/dev/null || true; git ls-files --others --exclude-standard; } |
    sort -u > "$WORK/changed.txt"
  offenders=$(grep -E '(^|/)templates/appset\.yaml$|^charts/base/|^renovate\.json$' "$WORK/changed.txt" || true)
  if [ -n "$offenders" ]; then
    fail "d7: the change set touches gate-protected paths (appset templates / charts/base / renovate.json are OUT of scope by ruling OQ1): $(printf '%s\n' "$offenders" | head -5)"
  fi
  ok "d7: no appset template, charts/base, or renovate.json path in the diff scope (AC7)"
fi

rm -rf "$WORK"
printf 'PASS: argocd-fanout disposal checks (%d ok)\n' "$checks"
