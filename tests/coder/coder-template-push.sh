#!/usr/bin/env bash
# C03 workflow static contract (2026/2026-11-cf-56-feat-forgejo-coder-
# template-pipeline) for .forgejo/workflows/coder-template-push.yaml — the
# sixth .forgejo/workflows/ file. AC trace (chunks/C03.md AC2-AC6):
# w1[AC1 the workflow parses as YAML] w2[AC2 trigger shape: exactly push
#    (main + the charts/coder/coder-templates/** path filter) +
#    workflow_dispatch (the templates input with all four keys); NO
#    pull_request key anywhere in the file] w3[AC3 guard shape: every job
#    if: is contains(vars.ROLE,'dev') || contains(vars.ROLE,'prod'), no
#    == null clause — the narrow-on-unset polarity, grep-pinned]
# w4[AC4 shape: concurrency.cancel-in-progress false; the push job has
#    needs + fail-fast false + a matrix over fromJSON(...changed-
#    templates); NO container: field on any job; NO image/tag line of any
#    kind in the file; every job runs-on ubuntu-24.04] w5[AC5 env-only
#    doctrine: every secrets.* reference sits inside an env: block (never
#    argv); the value-var set is exactly vars.CODER_URL (plus the
#    documented guard vars.ROLE, AC3 — the OQ5-minimal vault is one var +
#    one secret; any further value var reddens); the secrets.* set is
#    exactly {CODER_SESSION_TOKEN}; zero instance URL literals; no
#    token-shaped literal] w6[AC6 wiring: the detect job invokes
#    scripts/coder-template-detect.sh detect with its checkout pinned
#    fetch-depth: 0; the push job's diag calls coder version (the D43
#    toolchain check); the push step invokes scripts/coder-template-push.sh
#    with the matrix template].
#
# Designed-RED until C03 lands the workflow: a missing file is the
# not-yet-implemented state, not a skip.
#
# The legs are python3 walks (the plan Commands' YAML-parse shape) under the
# house ok/fail harness; the grep-pinned bans run as file-wide text sweeps
# so a comment cannot hide a banned key.
#
# Run from the repo root:
#   bash tests/coder/coder-template-push.sh        # w1..w6
#   bash tests/coder/coder-template-push.sh w3     # subset
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

WF=".forgejo/workflows/coder-template-push.yaml"

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
  for i in $(seq 1 6); do WANT["w$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^w[1-6]$ ]] || fail "unknown leg id '$a' (expected w1..w6)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

command -v python3 >/dev/null 2>&1 || fail "python3 is required for the YAML walk"

# Joined-literal URL needles (the fanout-runbook technique): the suite file
# stays free of the joined forms, so a repo-wide needle sweep never
# self-matches this test.
U1="coder.dev."; U2="scifi.farm"
U3="coder.spencerslab"; U4=".com"

# --- w1: the workflow exists and parses (AC1) ------------------------------
if want w1; then
  [ -f "$WF" ] ||
    fail "w1: $WF does not exist (designed-red: C03's workflow is not implemented)"
  if python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' "$WF"; then
    ok "w1: $WF parses as YAML"
  else
    fail "w1: $WF is not parseable YAML"
  fi
fi

# --- w2: trigger shape (AC2) ----------------------------------------------
if want w2; then
  [ -f "$WF" ] || fail "w2: $WF does not exist (designed-red)"
  if ! python3 - "$WF" <<'PY'
import sys, yaml

wf = sys.argv[1]


def bad(msg):
    print("FAIL: w2: %s" % msg, file=sys.stderr)
    sys.exit(1)


d = yaml.safe_load(open(wf))
# PyYAML reads the YAML 1.1 boolean on: as the key True.
on = d.get("on", d.get(True))
if not isinstance(on, dict):
    bad("no on: trigger block")
if set(on) != {"push", "workflow_dispatch"}:
    bad("the on: keys are %s — AC2 is EXACTLY push + workflow_dispatch: a PR leg is banned (fork heads carry empty secrets and a PR would mint an active version), and no other trigger may join" % sorted(str(k) for k in on))
push = on["push"]
if push.get("branches") != ["main"]:
    bad("push.branches is %s — exactly [main] (the templates live on main; a PR leg is the banned alternative)" % push.get("branches"))
if push.get("paths") != ["charts/coder/coder-templates/**"]:
    bad("push.paths is %s — exactly ['charts/coder/coder-templates/**'] (a push mints a version, so only a template-tree change may fire it)" % push.get("paths"))
wd = on["workflow_dispatch"]
t = wd.get("inputs", {}).get("templates")
if not isinstance(t, dict):
    bad("workflow_dispatch.inputs.templates is missing — the dispatch escape hatch (an empty list pushes nothing) is the containers-build.yaml shape")
if t.get("description") != "Template names to push (comma/space separated)":
    bad("templates.description is %r — the escape-hatch input must carry the containers-build.yaml description" % t.get("description"))
if t.get("required") is not False:
    bad("templates.required is %s — the input is optional (an empty list is the designed no-op)" % t.get("required"))
if t.get("default") != "":
    bad("templates.default is %r — the default is the empty list (pushes nothing)" % t.get("default"))
if t.get("type") != "string":
    bad("templates.type is %s — the containers-build.yaml shape is type: string (comma/space separated)" % t.get("type"))
print("ok: w2")
PY
  then
    fail "w2: the trigger shape is violated (reason printed above)"
  fi
  if grep -qE '^[[:space:]]*pull_request:' "$WF"; then
    fail "w2: a pull_request: key line enters the file — the PR leg is banned: fork heads carry empty secrets, and a PR push would mint an active template version"
  fi
  ok "w2: trigger is exactly push(main + the templates path filter) + workflow_dispatch(the templates input, all four keys); no pull_request key anywhere"
fi

# --- w3: guard shape — narrow on unset (AC3) ------------------------------
if want w3; then
  [ -f "$WF" ] || fail "w3: $WF does not exist (designed-red)"
  if ! python3 - "$WF" <<'PY'
import sys, yaml

wf = sys.argv[1]


def bad(msg):
    print("FAIL: w3: %s" % msg, file=sys.stderr)
    sys.exit(1)


d = yaml.safe_load(open(wf))
jobs = d.get("jobs", {})
if not jobs:
    bad("no jobs block")
for name, job in jobs.items():
    guard = job.get("if")
    if not isinstance(guard, str):
        bad("job %s has no if: guard — every job must carry the ROLE membership guard" % name)
    if "contains(vars.ROLE, 'dev')" not in guard or "contains(vars.ROLE, 'prod')" not in guard:
        bad("job %s guard is %r — it must test membership with contains(vars.ROLE, 'dev') || contains(vars.ROLE, 'prod') (a case-insensitive substring that never errors on a hand-typed value)" % (name, guard))
    if "== null" in guard:
        bad("job %s guard carries a == null clause (the widens-on-unset polarity) — this pipeline publishes to an external service, so it must NEVER fire unconfigured: the release.yaml fail-safe class, narrow on unset" % name)
print("ok: w3")
PY
  then
    fail "w3: a job guard is not the narrow-on-unset membership shape (reason printed above)"
  fi
  if grep -qF 'vars.ROLE == null' "$WF"; then
    fail "w3: 'vars.ROLE == null' appears in the file — the narrow-on-unset polarity bans the null clause: an unset ROLE must skip, not fire (the release.yaml fail-safe class for external-service publishes)"
  fi
  ok "w3: every job if: is contains(vars.ROLE,'dev') || contains(vars.ROLE,'prod'); no == null clause (narrow on unset)"
fi

# --- w4: job-image-as-today shape (AC4) -----------------------------------
if want w4; then
  [ -f "$WF" ] || fail "w4: $WF does not exist (designed-red)"
  if ! python3 - "$WF" <<'PY'
import sys, yaml

wf = sys.argv[1]


def bad(msg):
    print("FAIL: w4: %s" % msg, file=sys.stderr)
    sys.exit(1)


d = yaml.safe_load(open(wf))
conc = d.get("concurrency", {})
if conc.get("cancel-in-progress") is not False:
    bad("concurrency.cancel-in-progress is %s — it must be false: the capacity-1 runner queues instead, because a cancelled matrix would push half a template set (the containers-build.yaml rationale)" % conc.get("cancel-in-progress"))
jobs = d.get("jobs", {})
if not jobs:
    bad("no jobs block")
for name, job in jobs.items():
    if "container" in job:
        bad("job %s carries a container: field — the job runs on the lab's job image exactly as today (runs-on: ubuntu-24.04 is the whole routing; the Coder CLI is behind the label the label already routes to). The renovate.yaml container: job is the suite's SOLE deviation — one tool with no upstream-lab fit — not the shape" % name)
    if job.get("runs-on") != "ubuntu-24.04":
        bad("job %s runs-on is %s — the four non-renovate workflows all schedule ubuntu-24.04, and this one keeps the same shape" % (name, job.get("runs-on")))
pushjobs = [n for n, j in jobs.items() if "matrix" in j.get("strategy", {})]
if len(pushjobs) != 1:
    bad("expected exactly one matrix job (the push leg), got %s" % pushjobs)
pj = jobs[pushjobs[0]]
if not pj.get("needs"):
    bad("the push job has no needs: — it must queue behind the detect job")
mt = pj.get("strategy", {}).get("matrix", {}).get("template")
mt = str(mt)
if "fromJSON" not in mt or "changed-templates" not in mt:
    bad("the matrix template is %r — it must be the changed-templates output through fromJSON(...) so the matrix is built from the detect job's JSON array" % mt)
if pj.get("strategy", {}).get("fail-fast") is not False:
    bad("strategy.fail-fast is %s — it must be false: per-template isolation (one template's 401 must not kill the siblings' pushes)" % pj.get("strategy", {}).get("fail-fast"))
print("ok: w4")
PY
  then
    fail "w4: the job shape is violated (reason printed above)"
  fi
  if grep -qE '^[[:space:]]*container:' "$WF"; then
    fail "w4: a container: line enters the file — the job-image-as-today shape bans it (the runs-on label routes to the baked runner image)"
  fi
  if grep -qE '^[[:space:]]*image:' "$WF"; then
    fail "w4: an image: line enters the file — no image/tag line of any kind may appear (no container job, no job-level image)"
  fi
  ok "w4: concurrency.cancel-in-progress false; one matrix job with needs + fail-fast false + fromJSON(...changed-templates); no container: / image: line anywhere; every job on ubuntu-24.04"
fi

# --- w5: env-only doctrine + the exact vault set (AC5) --------------------
if want w5; then
  [ -f "$WF" ] || fail "w5: $WF does not exist (designed-red)"
  if ! python3 - "$WF" <<'PY'
import re, sys, yaml

wf = sys.argv[1]


def bad(msg):
    print("FAIL: w5: %s" % msg, file=sys.stderr)
    sys.exit(1)


text = open(wf).read()
d = yaml.safe_load(open(wf))

# Tag every string that references vars./secrets. with the mapping key it
# sits under, so the env-only check can see guard (if:) strings separately
# from env-wired ones.
refs = []


def walk(node, key, in_env):
    if isinstance(node, dict):
        for k, v in node.items():
            walk(v, k, in_env or k == "env")
    elif isinstance(node, list):
        for v in node:
            walk(v, key, in_env)
    elif isinstance(node, str):
        if re.search(r"\b(vars|secrets)\.", node):
            refs.append((key, node, in_env))


walk(d, None, False)

# Tokens are env-only, never argv (the argocd-fanout.py doctrine).
for key, s, in_env in refs:
    if "secrets." in s and not in_env:
        bad("a secrets.* reference sits outside an env: block (key %r): %s — the token must never reach argv, only the env block" % (key, s))
# The value var is env-wired the same way.
for key, s, in_env in refs:
    if "vars.CODER_URL" in s and not in_env:
        bad("vars.CODER_URL sits outside an env: block: %s" % s)

# The exact vault set. vars.ROLE is the documented guard (AC3), not a value
# var; the OQ5-minimal ruling is one var (CODER_URL) + one secret
# (CODER_SESSION_TOKEN) — any further value var reddens.
varkeys = set(re.findall(r"\bvars\.([A-Za-z_][A-Za-z0-9_]*)", text))
secretkeys = set(re.findall(r"\bsecrets\.([A-Za-z_][A-Za-z0-9_]*)", text))
if "CODER_URL" not in varkeys:
    bad("vars.CODER_URL is never referenced — the endpoint must come from the instance-side repo var")
if not varkeys <= {"ROLE", "CODER_URL"}:
    bad("vars.* keys beyond {ROLE, CODER_URL}: %s — the OQ5-minimal ruling allows exactly one value var (CODER_URL) plus the guard (ROLE); template input values ride the in-repo tfvars, not value vars" % sorted(varkeys))
if secretkeys != {"CODER_SESSION_TOKEN"}:
    bad("secrets.* keys are %s — exactly {CODER_SESSION_TOKEN} (one secret per instance; a second secret is a vault the ruling did not rule)" % sorted(secretkeys))

# Zero instance URL literals (the main-sync doctrine: the file is identical-
# safe to host on both instances; the instance-side placement is what the
# runbook documents).
for lit in ("coder.dev." + "scifi.farm", "coder.spencerslab" + ".com"):
    if lit in text:
        bad("the instance URL literal %s enters the file — no URL literal may appear (identical-safe to host; the endpoint comes from vars.CODER_URL)" % lit)

# No token-shaped literal: a pasted credential prefix, or a long opaque
# alphanumeric run (pure-hex runs are the digest-comment class, allowed).
if re.search(r"ghp_|gho_|ghs_|ghr_|github_pat_|glpat-|\bgj_", text):
    bad("a token prefix (ghp_/gho_/ghs_/ghr_/github_pat_/glpat-/gj_) enters the file — no credential literal may be pasted in")
for i, ln in enumerate(text.splitlines(), 1):
    for m in re.finditer(r"[A-Za-z0-9]{24,}", ln):
        s = m.group(0)
        if re.fullmatch(r"[0-9a-f]+", s, re.I) is None:
            bad("line %d carries a token-shaped literal (%s...) — a long opaque run is the pasted-credential shape" % (i, s[:30]))
print("ok: w5")
PY
  then
    fail "w5: the env-only doctrine or the vault shape is violated (reason printed above)"
  fi
  if grep -qF "${U1}${U2}" "$WF" || grep -qF "${U3}${U4}" "$WF"; then
    fail "w5: an instance URL literal appears in the file (the grep-pinned twin of the python walk)"
  fi
  ok "w5: every secrets.* reference is env-only; the vault is exactly vars.CODER_URL + secrets.CODER_SESSION_TOKEN (the guard's vars.ROLE aside); zero URL literals, no token-shaped literal"
fi

# --- w6: script wiring + the toolchain diag (AC6) -------------------------
if want w6; then
  [ -f "$WF" ] || fail "w6: $WF does not exist (designed-red)"
  if ! python3 - "$WF" <<'PY'
import sys, yaml

wf = sys.argv[1]


def bad(msg):
    print("FAIL: w6: %s" % msg, file=sys.stderr)
    sys.exit(1)


d = yaml.safe_load(open(wf))
jobs = d.get("jobs", {})


def runs(job):
    return [s.get("run", "") or "" for s in job.get("steps", [])]


det = [j for j in jobs.values() if any("coder-template-detect.sh" in r for r in runs(j))]
if len(det) != 1:
    bad("expected exactly one job invoking scripts/coder-template-detect.sh, got %d" % len(det))
dj = det[0]
co = [s for s in dj.get("steps", []) if str(s.get("uses", "")).startswith("actions/checkout")]
if not co:
    bad("the detect job has no actions/checkout step")
if co[0].get("with", {}).get("fetch-depth") != 0:
    bad("the detect job's checkout fetch-depth is %s — it must pin 0: detection diffs the whole before..sha range, and at the depth-1 default the endpoints do not exist locally (the containers-build rationale, the V-6-1 shallow-clone law)" % co[0].get("with", {}).get("fetch-depth"))
if not any("bash scripts/coder-template-detect.sh detect" in r for r in runs(dj)):
    bad("no step invokes 'bash scripts/coder-template-detect.sh detect' — the detect subcommand is the C02 contract entry point")
push = [j for j in jobs.values() if any("coder-template-push.sh" in r for r in runs(j))]
if len(push) != 1:
    bad("expected exactly one job invoking scripts/coder-template-push.sh, got %d" % len(push))
pj = push[0]
pstep = [r for r in runs(pj) if "coder-template-push.sh" in r]
if not any("matrix.template" in r for r in pstep):
    bad("the push step does not pass the matrix template to scripts/coder-template-push.sh — the per-template matrix cell is the isolation unit")
if not any("coder version" in r for r in runs(pj)):
    bad("the push job's diag does not call 'coder version' — the plain call IS the toolchain check (D43): a pre-bake runner image dies here loudly (the runbook's UA3/UA4 sequencing state, not a pipeline bug)")
print("ok: w6")
PY
  then
    fail "w6: the script wiring is violated (reason printed above)"
  fi
  ok "w6: the detect job runs 'bash scripts/coder-template-detect.sh detect' with fetch-depth: 0; the push job's diag calls coder version; the push step invokes scripts/coder-template-push.sh with the matrix template"
fi

printf 'PASS: coder template push workflow checks (%d ok)\n' "$checks"
