#!/usr/bin/env bash
# C03 workflow static contract + the C04 called-run extension
# (2026/2026-11-cf-56-feat-forgejo-coder-template-pipeline) for
# .forgejo/workflows/coder-template-push.yaml — the sixth
# .forgejo/workflows/ file, re-pinned to the C15 called-run shape under
# the batched round 2 rulings (OQ10 fan member, OQ11 shared marker, OQ12
# step-owned warning). AC trace (chunks/C03.md AC2-AC6 + chunks/C04.md):
# w1[AC1 the workflow parses as YAML]
# w2[C04 on: shape: exactly {workflow_dispatch, workflow_call} — NO push arm
#    (the C15 re-aim: main-sync's prod-main fan calls the workflow; path
#    filtering lives in the marker..sha detection) and NO pull_request key
#    anywhere in the file (fork heads carry empty secrets and a PR would
#    mint an active version); the templates dispatch input byte-frozen (all
#    four keys)] w3[AC3 guard shape: every job if: is
#    contains(vars.ROLE,'dev') || contains(vars.ROLE,'prod'), no == null
#    clause — the narrow-on-unset polarity, grep-pinned]
# w4[AC4 shape + C04 job set: concurrency.cancel-in-progress false; the job
#    set is the detect/push pair ONLY (no advance-named job — retired:
#    main-sync's aggregate is the single marker writer, the D54 poison
#    ruling); the push job has needs + fail-fast false + a matrix over
#    fromJSON(...changed-templates); NO container: field on any job; NO
#    image/tag line of any kind in the file; every job runs-on
#    ubuntu-24.04] w5[AC5 env-only doctrine: every secrets.* reference
#    sits inside an env: block (never argv); the value-var set is exactly
#    vars.CODER_URL (plus the documented guard vars.ROLE, AC3 — the
#    OQ5-minimal vault is one var + one secret; any further value var
#    reddens); the secrets.* set is exactly {CODER_SESSION_TOKEN}; zero
#    instance URL literals; no token-shaped literal]
# w6[C04 wiring: the detect job invokes scripts/coder-template-detect.sh
#    detect with its checkout pinned fetch-depth: 0; the resolve-marker
#    step (id: marker) sits inside the detect job before the detect step;
#    the detect step's env: accessors are exactly FIVE and byte-exact
#    (EVENT_NAME, EVENT_BEFORE, SHA, MANUAL_TEMPLATES, MARKER_SHA — the
#    5th from steps.marker.outputs.sha; the PR keys stay absent); the
#    verdict echo names marker=; the push job's diag calls coder version
#    (the D43 toolchain check); the push step invokes
#    scripts/coder-template-push.sh with the matrix template; the header
#    carries the fan story (names the main-sync caller) with zero bare
#    old-name tokens (the D24 sweep, the tokens named in w6)]
# w7[C04 resolver step shape, executed offline on a scratch bare remote:
#    the gate on a non-call event (workflow_dispatch) stays network-free
#    and emits empty sha= + exit 0 (a dispatch never reads the marker);
#    an absent marker → empty sha= + exit 0 (the bootstrap); a
#    present+reachable marker → its sha; an orphaned marker → LOUD fail
#    naming the value + the reset-or-delete owner note; non-hex garbage
#    (PATH-shimmed ls-remote) → fatal naming the value]
# w8[C04 fence shape: NO advance-named job in the file; ZERO git push
#    statements naming refs/heads/ci/last-built anywhere (we are a
#    READER, not a writer); the resolver names the shared ref; the on:
#    block carries workflow_call: {} (the called-run trigger present)]
# w9[C04 step-owned warning law — the staged detect-step body + the shipped
#    detector executed in a scratch git repo, eight shapes: an empty
#    dispatch (any list, incl. the all-ungated case — the retired C02
#    divergence) silent; workflow_call + no marker + empty tip-only range
#    step-silent (the script's bootstrap announce is the signal); a real
#    empty push range without a marker (defensive) warns; a real empty
#    before == sha (defensive no-op) silent; a non-empty set silent (marker
#    set: the echo names the marker endpoint); a called run + marker
#    present + empty range → the plain verified-empty info line (no
#    ::warning::, no ::notice:: — the runner does not interpret it, the
#    cf-6 OQ-3 class — "verified empty" required, the echo names marker=);
#    marker == sha the same info posture; a defensive push + marker
#    present + empty range the same (the calm gate reads MARKER_SHA
#    presence for any event, the round-5 C15 M1 law). Job-log legibility
#    only, no UI-chip claim.]
#
# Designed-RED through C04 on the fan-shape legs (w2 the on: shape, w6's
# marker wiring, w7, w8, w9): the workflow is still the C03 push-trigger
# shape on the current tree; the C03 legs (w1, w3, w4, w5) stay green.
#
# The legs are python3 walks (the plan Commands' YAML-parse shape) under the
# house ok/fail harness; the grep-pinned bans run as file-wide text sweeps
# so a comment cannot hide a banned key; the w7/w9 behavioral legs stage
# the workflow's step bodies + the shipped detector into a scratch git
# repo (the forgejo-build-containers.sh t17/t14 house shape) — network-
# free.
#
# Run from the repo root:
#   bash tests/coder/coder-template-push.sh        # w1..w9
#   bash tests/coder/coder-template-push.sh w3     # subset
# Env: CODER_WF / CODER_DETECT (point the parity sources at a synthetic
#      tree for green-shape proofs — the runbook-suite convention).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

WF="${CODER_WF:-.forgejo/workflows/coder-template-push.yaml}"
DETECT="${CODER_DETECT:-scripts/coder-template-detect.sh}"

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
  for i in $(seq 1 9); do WANT["w$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^w[1-9]$ ]] || fail "unknown leg id '$a' (expected w1..w9)"
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

# --- w2: trigger shape — the C04 fan re-aim (C04 AC6) --------------------
# The push arm died with the C15 re-aim: main-sync's prod-main fan CALLS
# the workflow; path filtering lives in the marker..sha detection instead.
# The dispatch hatch is byte-frozen (the dev-side leg + the per-template
# escape hatch — a dispatch never advances the shared marker, the fan law).
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
if "push" in on:
    bad("a push: arm survives the on: block — the push arm RETIRED with the C15 re-aim: main-sync's prod-main fan calls the workflow, path filtering lives in the marker..sha detection instead (a push arm would re-open the trigger the fan replaced)")
if set(on) != {"workflow_dispatch", "workflow_call"}:
    bad("the on: keys are %s — C04 is EXACTLY workflow_dispatch + workflow_call: the call trigger is the C15 called-run contract, a PR leg is banned (fork heads carry empty secrets and a PR would mint an active version), and no other trigger may join" % sorted(str(k) for k in on))
if on.get("workflow_call") not in (None, {}):
    bad("workflow_call is %r — the called-run trigger is the bare {} (no inputs: the called workflow needs none — its detection reads the event payload + the shared marker)" % (on.get("workflow_call"),))
wd = on["workflow_dispatch"]
t = wd.get("inputs", {}).get("templates")
if not isinstance(t, dict):
    bad("workflow_dispatch.inputs.templates is missing — the dispatch escape hatch (an empty list pushes nothing) is the build-containers.yaml shape")
if t.get("description") != "Template names to push (comma/space separated)":
    bad("templates.description is %r — the escape-hatch input must carry the build-containers.yaml description" % t.get("description"))
if t.get("required") is not False:
    bad("templates.required is %s — the input is optional (an empty list is the designed no-op)" % t.get("required"))
if t.get("default") != "":
    bad("templates.default is %r — the default is the empty list (pushes nothing)" % t.get("default"))
if t.get("type") != "string":
    bad("templates.type is %s — the build-containers.yaml shape is type: string (comma/space separated)" % t.get("type"))
print("ok: w2")
PY
  then
    fail "w2: the trigger shape is violated (reason printed above)"
  fi
  if grep -qE '^[[:space:]]*pull_request:' "$WF"; then
    fail "w2: a pull_request: key line enters the file — the PR leg is banned: fork heads carry empty secrets, and a PR push would mint an active template version"
  fi
  ok "w2: trigger is exactly workflow_dispatch(the templates input, all four keys byte-frozen) + workflow_call — NO push arm (the C15 re-aim: the fan calls the workflow, path filtering lives in the marker..sha detection), no pull_request key anywhere"
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
        bad("job %s guard carries a == null clause (the widens-on-unset polarity) — this pipeline publishes to an external service, so it must NEVER fire unconfigured: the build-charts.yaml fail-safe class, narrow on unset" % name)
print("ok: w3")
PY
  then
    fail "w3: a job guard is not the narrow-on-unset membership shape (reason printed above)"
  fi
  if grep -qF 'vars.ROLE == null' "$WF"; then
    fail "w3: 'vars.ROLE == null' appears in the file — the narrow-on-unset polarity bans the null clause: an unset ROLE must skip, not fire (the build-charts.yaml fail-safe class for external-service publishes)"
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
    bad("concurrency.cancel-in-progress is %s — it must be false: the 10-poller-pod × capacity-1 runner queues instead, because a cancelled matrix would push half a template set (the build-containers.yaml rationale, the D57 topology)" % conc.get("cancel-in-progress"))
jobs = d.get("jobs", {})
if not jobs:
    bad("no jobs block")
if len(jobs) != 2:
    bad("the job set is %s — C04 is EXACTLY the detect/push pair: the advance-marker job is RETIRED (main-sync's aggregate is the single marker writer — a per-builder advance on the shared ref is the D54 poison), and no other job may join" % sorted(jobs))
adv = [n for n in jobs if "advance" in str(n)]
if adv:
    bad("advance-named job(s) %s enter the file — the t16 fence shape bans them (the single-writer fence: we are a reader of the shared ci/last-built marker, never a writer)" % adv)
for name, job in jobs.items():
    if "container" in job:
        bad("job %s carries a container: field — the job runs on the lab's job image exactly as today (runs-on: ubuntu-24.04 is the whole routing; the Coder CLI is behind the label the label already routes to). The renovate.yaml container: job is the suite's SOLE deviation — one tool with no upstream-lab fit — not the shape" % name)
    if job.get("runs-on") != "ubuntu-24.04":
        bad("job %s runs-on is %s — the five non-renovate workflows all schedule ubuntu-24.04, and this one keeps the same shape" % (name, job.get("runs-on")))
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
  ok "w4: concurrency.cancel-in-progress false (10-poller-pod × capacity-1, D57); the job set is the detect/push pair ONLY (no advance-named job — the fence shape); one matrix job with needs + fail-fast false + fromJSON(...changed-templates); no container: / image: line anywhere; every job on ubuntu-24.04"
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

# --- w6: script wiring + the C04 marker wiring + the toolchain diag (AC6 re-pin)
if want w6; then
  [ -f "$WF" ] || fail "w6: $WF does not exist (designed-red)"
  if ! python3 - "$WF" <<'PY'
import re, sys, yaml

wf = sys.argv[1]


def bad(msg):
    print("FAIL: w6: %s" % msg, file=sys.stderr)
    sys.exit(1)


text = open(wf).read()
d = yaml.safe_load(open(wf))
jobs = d.get("jobs", {})


def runs(job):
    return [s.get("run", "") or "" for s in job.get("steps", [])]


det = [j for j in jobs.values() if any("coder-template-detect.sh" in r for r in runs(j))]
if len(det) != 1:
    bad("expected exactly one job invoking scripts/coder-template-detect.sh, got %d" % len(det))
dj = det[0]
steps = dj.get("steps", [])
co = [s for s in steps if str(s.get("uses", "")).startswith("actions/checkout")]
if not co:
    bad("the detect job has no actions/checkout step")
if co[0].get("with", {}).get("fetch-depth") != 0:
    bad("the detect job's checkout fetch-depth is %s — it must pin 0: detection diffs the whole range (marker..sha when the marker exists, before..sha when it does not) and the marker's own reachability check (git cat-file -e) needs the same history; at the depth-1 default the endpoints do not exist locally (the build-containers.yaml rationale, the V-6-1 shallow-clone law)" % co[0].get("with", {}).get("fetch-depth"))
# The C04 resolver step: id: marker, inside the detect job, positioned
# between the diag step and the detect step (the upstream t17 position law).
marker_steps = [i for i, s in enumerate(steps)
               if isinstance(s, dict) and s.get("id") == "marker"]
if len(marker_steps) != 1:
    bad("the detect job carries %d run steps with id: marker, expected exactly one (the call-side-only resolve-last-pushed-marker step, the upstream :143-176 shape)" % len(marker_steps))
mi = marker_steps[0]
if not str(steps[mi].get("run", "")):
    bad("the id: marker step carries no run: body to stage (the resolver is the :143-176 shape — a non-trivial shell body)")
diag_idx = [i for i, s in enumerate(steps) if "diag" in str(s.get("name", "")).lower()]
det_idx = [i for i, s in enumerate(steps)
           if "coder-template-detect.sh detect" in str(s.get("run", ""))]
if not diag_idx or not det_idx:
    bad("harness cannot locate the diag/detect steps to pin the resolver position (harness fault, not a code red)")
if not (diag_idx[0] < mi < det_idx[0]):
    bad("the id: marker step sits at index %d, not between the diag (%d) and the detect step (%d) — the resolver position is law (it must resolve before detection reads its output)" % (mi, diag_idx[0], det_idx[0]))
# The detect step's env accessors: EXACTLY the five, byte-exact (the 5th =
# the marker, from steps.marker.outputs.sha; the PR keys stay absent —
# five, not the upstream's seven, the OQ2 ruling).
dstep = steps[det_idx[0]]
env = dstep.get("env", {})
EXPECT = {
    "EVENT_NAME": "${{ forgejo.event_name }}",
    "EVENT_BEFORE": "${{ forgejo.event.before }}",
    "SHA": "${{ forgejo.sha }}",
    "MANUAL_TEMPLATES": "${{ forgejo.event.inputs.templates }}",
    "MARKER_SHA": "${{ steps.marker.outputs.sha }}",
}
if set(env) != set(EXPECT):
    bad("the detect step's env: keys are %s — expected EXACTLY the five %s (the PR keys stay absent by the OQ2 ruling; a missing key would reach the script unset rather than empty)" % (sorted(env), sorted(EXPECT)))
for k, v in EXPECT.items():
    if str(env.get(k)) != v:
        bad("the detect step's %s accessor is %r — expected byte-exact %r (MARKER_SHA must read steps.marker.outputs.sha: a missing output key would reach the script *unset*, and an empty MARKER_SHA is exactly the state the payload arms are specified against)" % (k, env.get(k), v))
# The verdict echo names the marker endpoint (the upstream :197 shape).
if "marker=$MARKER_SHA" not in str(dstep.get("run", "")):
    bad("the detect step's verdict echo never names marker=$MARKER_SHA — a marker-fed run must read distinctly (the marker proves nothing was missed; the echo is where that shows)")
push = [j for j in jobs.values() if any("coder-template-push.sh" in r for r in runs(j))]
if len(push) != 1:
    bad("expected exactly one job invoking scripts/coder-template-push.sh, got %d" % len(push))
pj = push[0]
pstep = [r for r in runs(pj) if "coder-template-push.sh" in r]
if not any("matrix.template" in r for r in pstep):
    bad("the push step does not pass the matrix template to scripts/coder-template-push.sh — the per-template matrix cell is the isolation unit")
if not any("coder version" in r for r in runs(pj)):
    bad("the push job's diag does not call 'coder version' — the plain call IS the toolchain check (D43): a pre-bake runner image dies here loudly (the runbook's UA3/UA4 sequencing state, not a pipeline bug)")
# Header reword pins (the 20-line sweep's w-side teeth, in-file): zero bare
# old-name tokens anywhere, and the Trigger./Detection. header names the
# main-sync fan caller. Composed needles (the ci-surface t8 self-safety
# technique): this suite must never carry the plain tokens it bans.
for name, rx in (("release" + ".yaml", re.compile("release" + r"[.]" + "yaml")),
                 ("containers-build" + ".yaml", re.compile("containers-build" + r"[.]" + "yaml"))):
    for i, ln in enumerate(text.splitlines(), 1):
        if "os.path.join" in ln:
            continue
        for m in rx.finditer(ln):
            before = ln[:m.start()]
            if before.endswith("/") and re.search(r"(?i)github|renamed|moved to", ln):
                continue
            bad("line %d carries the bare %s token (%s...) — the 20-line sweep re-fences the file to the build-charts.yaml/build-containers.yaml citations (D24)" % (i, name, ln.strip()[:80]))
header = []
for ln in text.splitlines():
    if re.match(r"^name:", ln):
        break
    if ln.lstrip().startswith("#"):
        header.append(ln)
hb = "\n".join(header)
if "main-sync" not in hb:
    bad("the header never names main-sync — the Trigger./Detection. paragraphs must carry the fan story (the push arm died; main-sync's prod-main fan calls this workflow; a dispatch never advances the shared marker)")
print("ok: w6")
PY
  then
    fail "w6: the script wiring is violated (reason printed above)"
  fi
  ok "w6: the detect job runs 'bash scripts/coder-template-detect.sh detect' with fetch-depth: 0; the id: marker step sits between the diag and the detect step; the detect step carries the FIVE byte-exact accessors (MARKER_SHA from steps.marker.outputs.sha) and the verdict echo names marker=; the header carries the fan story with zero bare old-name tokens; the push job's diag calls coder version; the push step invokes scripts/coder-template-push.sh with the matrix template"
fi

# --- w7: resolver-step shape, executed offline (C04 AC5) -------------------
# The upstream forgejo-build-containers.sh t17 shape, minus the PR arm
# (the OQ2 ruling: the non-call event is workflow_dispatch): a scratch
# bare remote + clone, the staged resolver body, five cases — the gate
# stays network-free off the call side (a dispatch never reads the
# marker); the absent-marker bootstrap; the present+reachable hand-off;
# the orphaned-marker LOUD fail (the reset-or-delete owner note); the
# non-hex garbage fatal.
w7_stage() { # $1 = output script path
  if ! python3 - "$WF" "$1" <<'PY'
import sys, yaml

wf, out = sys.argv[1:3]
jobs = (yaml.safe_load(open(wf)) or {}).get("jobs") or {}
det = None
for job in jobs.values():
    for s in (job or {}).get("steps", []):
        if isinstance(s, dict) and "coder-template-detect.sh detect" in str(s.get("run", "")):
            det = job
            break
    if det is not None:
        break
if det is None:
    print("FAIL: w7: no detect job found to locate the resolver (harness fault)", file=sys.stderr)
    sys.exit(1)
steps = [s for s in det.get("steps", []) if isinstance(s, dict)]
mi = [i for i, s in enumerate(steps) if s.get("id") == "marker"]
if len(mi) != 1:
    print("FAIL: w7: the detect job carries %d id: marker steps, expected exactly one to stage (w6 owns the presence pin; this is the execution harness — designed-red until C04 lands the step)" % len(mi), file=sys.stderr)
    sys.exit(1)
body = str(steps[mi[0]].get("run", ""))
if not body:
    print("FAIL: w7: the id: marker step has no run body to stage", file=sys.stderr)
    sys.exit(1)
open(out, "w").write(body + "\n")
PY
  then
    return 1
  fi
}

leg_w7() {
  local sdir
  sdir=$(mktemp -d /tmp/opencode/coder-template-push-w7.XXXXXX) \
    || { printf 'FAIL: w7: harness could not stage the scratch dir\n' >&2; return 1; }
  w7_stage "$sdir/resolver.sh" \
    || { printf 'FAIL: w7: could not stage the resolver body from %s (designed-red: the marker step is not landed)\n' "$WF" >&2; return 1; }
  local R="$sdir/remote.git" W="$sdir/work" W2="$sdir/work2" W3="$sdir/work3"
  git init -q --bare "$R" >/dev/null 2>&1 \
    || { printf 'FAIL: w7: harness could not init the bare remote\n' >&2; return 1; }
  git clone -q "$R" "$W" 2>/dev/null \
    || { printf 'FAIL: w7: harness could not clone the empty remote\n' >&2; return 1; }
  git -C "$W" config user.email test@example.invalid && git -C "$W" config user.name test \
    || { printf 'FAIL: w7: harness could not configure the scratch clone\n' >&2; return 1; }
  echo keep > "$W/keep.txt"
  git -C "$W" add -A && git -C "$W" commit -qm a && git -C "$W" push -q origin HEAD:refs/heads/main \
    || { printf 'FAIL: w7: harness could not seed the scratch remote\n' >&2; return 1; }
  local HEAD1 HEAD2 rc garbage
  HEAD1=$(git -C "$W" rev-parse HEAD) || return 1
  garbage=$(printf 'z%.0s' {1..40})

  # (c1) non-call event (workflow_dispatch), DEAD origin: the gate must
  # short-circuit BEFORE any network read — the marker is call-side only;
  # a dispatch never reads it (any ls-remote here would die loudly).
  mkdir -p "$W3" \
    && ( cd "$W3" && git init -q . && git config user.email test@example.invalid && git config user.name test \
         && echo x > x.txt && git add -A && git commit -qm x && git remote add origin "$sdir/no-such-remote.git" ) \
    || { printf 'FAIL: w7: harness could not build the dead-origin clone\n' >&2; return 1; }
  rm -f "$sdir/out"; rc=0
  ( cd "$W3" && env GITHUB_OUTPUT="$sdir/out" EVENT_NAME=workflow_dispatch MARKER_SHA= bash "$sdir/resolver.sh" ) >"$sdir/w7-dispatch.log" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] \
    || { printf 'FAIL: w7: the resolver exited %d on a non-call event against a DEAD origin — the gate must stay network-free (the marker is call-side only: a dispatch never reads the marker)\n' "$rc" >&2; return 1; }
  grep -q '^sha=$' "$sdir/out" \
    || { printf 'FAIL: w7: the non-call resolver run wrote no empty sha= output — the output key must be DEFINED on every event (a missing key reaches the script UNSET, not empty)\n' >&2; return 1; }

  # (c2) call run, marker ABSENT: the bootstrap shape — exit 0, sha= empty
  # (the before-chain answers; main-sync's first green fan creates the ref).
  rm -f "$sdir/out"; rc=0
  ( cd "$W" && env GITHUB_OUTPUT="$sdir/out" EVENT_NAME=workflow_call MARKER_SHA= bash "$sdir/resolver.sh" ) >"$sdir/w7-absent.log" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] \
    || { printf 'FAIL: w7: the resolver exited %d with the marker absent on a call run — a missing marker is the bootstrap shape (emit sha= empty, exit 0) — see %s\n' "$rc" "$sdir/w7-absent.log" >&2; return 1; }
  grep -q '^sha=$' "$sdir/out" \
    || { printf 'FAIL: w7: the absent-marker output is not an empty sha= emission — see %s\n' "$(tr '\n' ';' < "$sdir/out" 2>/dev/null)" >&2; return 1; }

  # (c3) call run, marker present + reachable: hands detect the marker sha.
  git -C "$W" push -q origin "HEAD:refs/heads/ci/last-built" \
    || { printf 'FAIL: w7: harness could not seed the scratch marker (setup fault)\n' >&2; return 1; }
  rm -f "$sdir/out"; rc=0
  ( cd "$W" && env GITHUB_OUTPUT="$sdir/out" EVENT_NAME=workflow_call MARKER_SHA= bash "$sdir/resolver.sh" ) >"$sdir/w7-present.log" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] \
    || { printf 'FAIL: w7: the resolver exited %d with a present, reachable marker — see %s\n' "$rc" "$sdir/w7-present.log" >&2; return 1; }
  local GOT; GOT=$(sed -n 's/^sha=//p' "$sdir/out" | tail -n1)
  [ "$GOT" = "$HEAD1" ] \
    || { printf 'FAIL: w7: the resolver answered sha=%s, expected the marker oid %s (present+reachable must hand detect the marker, not an empty fallback)\n' "$GOT" "$HEAD1" >&2; return 1; }

  # (c4) call run, marker ORPHANED (advanced from a sibling clone the
  # checkout never fetched): LOUD fail naming the value + the owner verbs —
  # a silent downgrade to before..sha re-opens the hole the marker closes.
  cp -a "$W" "$W2" || { printf 'FAIL: w7: harness could not copy the scratch clone\n' >&2; return 1; }
  echo ahead > "$W2/ahead.txt"
  git -C "$W2" add -A && git -C "$W2" commit -qm ff-ahead || return 1
  HEAD2=$(git -C "$W2" rev-parse HEAD) || return 1
  git -C "$W2" push -q origin "HEAD:refs/heads/ci/last-built" \
    || { printf 'FAIL: w7: harness could not pre-move the scratch marker fast-forward (setup fault)\n' >&2; return 1; }
  rm -f "$sdir/out"; rc=0
  ( cd "$W" && env GITHUB_OUTPUT="$sdir/out" EVENT_NAME=workflow_call MARKER_SHA= bash "$sdir/resolver.sh" ) >"$sdir/w7-orphan.log" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] \
    || { printf 'FAIL: w7: the resolver exited 0 although the marker (%s) is unreachable from the checkout — an orphaned marker must fail loud, not downgrade this run to the payload fallback in silence\n' "$HEAD2" >&2; return 1; }
  grep -qF -- "$HEAD2" "$sdir/w7-orphan.log" \
    || { printf 'FAIL: w7: the orphaned-marker fail does not name the marker sha — a die that hides which value broke it is not diagnosable from the job log\n' >&2; return 1; }
  grep -qiE 'reset|delete' "$sdir/w7-orphan.log" \
    || { printf 'FAIL: w7: the orphaned-marker fail carries no owner note (reset or delete the ref) — the message must say what unblocks the run\n' >&2; return 1; }

  # (c5) call run, non-hex garbage from ls-remote (PATH shim answers the
  # read): fatal, naming the value.
  local shim="$sdir/shim" realgit
  mkdir -p "$shim" || return 1
  realgit=$(command -v git) || return 1
  printf '#!/bin/sh\nif [ "$1" = ls-remote ]; then printf "%%s\\trefs/heads/ci/last-built\\n" "%s"; exit 0; fi\nexec %s "$@"\n' \
    "$garbage" "$realgit" > "$shim/git" || return 1
  chmod +x "$shim/git" || return 1
  rm -f "$sdir/out"; rc=0
  ( cd "$W" && env PATH="$shim:$PATH" GITHUB_OUTPUT="$sdir/out" EVENT_NAME=workflow_call MARKER_SHA= bash "$sdir/resolver.sh" ) >"$sdir/w7-garbage.log" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] \
    || { printf 'FAIL: w7: the resolver accepted a non-hex ls-remote value (%s) with exit %d — garbage in the marker ref is fatal, not a bootstrap reinterpretation\n' "$garbage" "$rc" >&2; return 1; }
  grep -qF -- "$garbage" "$sdir/w7-garbage.log" \
    || { printf 'FAIL: w7: the non-hex resolver fail does not name the garbage value — the die must be self-describing\n' >&2; return 1; }

  rm -rf "$sdir"
  ok "w7: the resolver step executes offline on a scratch bare remote — a non-call event (workflow_dispatch) stays network-free and emits empty sha= + exit 0 (the marker is call-side only: a dispatch never reads the marker); an absent marker answers the bootstrap shape (empty sha=, exit 0); a present+reachable marker hands its sha; an orphaned marker fails LOUD naming the value with the reset-or-delete owner note; non-hex garbage fails naming the value"
}
if want w7; then
  leg_w7 || fail "w7: see the w7 detail above"
fi

# --- w8: fence shape — a READER, not a writer (C04 AC6) -------------------
if want w8; then
  [ -f "$WF" ] || fail "w8: $WF does not exist (designed-red)"
  if ! python3 - "$WF" <<'PY'
import re, sys, yaml

wf = sys.argv[1]
raw = open(wf).read()
d = yaml.safe_load(open(wf))
jobs = (d or {}).get("jobs") or {}
on = d.get("on", d.get(True))
REF = "refs/heads/ci/last-built"


def bad(msg):
    print("FAIL: w8: %s" % msg, file=sys.stderr)
    sys.exit(1)


adv = [n for n in jobs if "advance" in str(n).lower()]
if adv:
    bad("advance-named job(s) %s — the t16 fence shape bans them: a per-builder advance on the shared ci/last-built ref is the D54 poison (one green fire would swallow a sibling failed range); main-sync's aggregate is the single writer (w4 pins the job set; this pin is the fence half)" % adv)
pushes = [ln.strip() for ln in raw.splitlines()
          if re.search(r"git\s+push", ln) and REF in ln and not ln.strip().startswith("#")]
if pushes:
    bad("the file carries marker-push statement(s) %s — we are a READER of the shared marker, never a writer (the t16 single-writer fence: of the four-file allow-set, exactly main-sync.yaml pushes the ref)" % pushes[:2])
if REF not in raw:
    bad("the file never names %s — the resolver must read the SHARED ref (the OQ11 ruling: no own ref anywhere in the file); a workflow that stopped reading the marker hands every run the payload fallback and re-opens the delivery-loss class" % REF)
if not isinstance(on, dict) or "workflow_call" not in on:
    bad("the on: block does not carry workflow_call — the called-run trigger is the C15 called-run contract (w2 pins the exact key set; this is the fence's trigger half)")
print("ok: w8")
PY
  then
    fail "w8: the fence shape is violated (reason printed above)"
  fi
  ok "w8: fence shape — NO advance-named job; ZERO git push statements naming refs/heads/ci/last-built (a reader, not a writer); the resolver names the shared ref; the on: block carries workflow_call (the called-run trigger present)"
fi

# --- w9: step-owned warning law, executed (C04 AC8) ------------------------
# The upstream forgejo-build-containers.sh t14 shape, minus the PR arm
# (the OQ2 ruling) and re-scoped to the fan shape: the staged detect-step
# body + the shipped detector in a scratch git repo. The script's stderr
# (its two tip-only announces) is the script's channel and is discarded
# here; the STEP's stdout is the pin surface — the step-owned warning law
# (OQ12: one law governs, the C03 documented inversion retired).
# Scratch layout: commit a (all files), b (templates + chart), c (chart
# only), d (ungated-only) — so a..b and a..d are non-empty, b..c and c..d
# (and the marker ranges onto them) empty, and the marker-verified shapes
# have distinct endpoints (marker=b, before=c, sha=d: the before range
# differs from the marker's position, so the guard must read MARKER_SHA,
# not the before exemption).
w9_step() { # $1 sdir, $2 label, $3 expect(yes|no), $4.. env pairs
  local sdir="$1" label="$2" expect="$3"
  shift 3
  local out rc
  if out=$( cd "$sdir" && env GITHUB_OUTPUT="$sdir/output" EVENT_NAME= EVENT_BEFORE= SHA= \
      MANUAL_TEMPLATES= MARKER_SHA= "$@" bash step.sh 2>/dev/null ); then
    rc=0
  else
    rc=$?
  fi
  [ "$rc" -eq 0 ] || { printf 'FAIL: w9: the detect step exited %d when executed for the %s scenario — the run body must stay offline-executable for its warning scope to be pinnable (on the pre-C04 tree this is the designed-red: the C02 script dies on the call channel)\n' "$rc" "$label" >&2; return 1; }
  case "$out" in
    *"templates:"*) ;;
    *) printf 'FAIL: w9: the step run for the %s scenario printed no verdict line (a "…templates:" echo) — the verdict cannot be dropped: a green run that pushed nothing must read differently from a range that resolved to nothing\n' "$label" >&2; return 1 ;;
  esac
  case "$out" in
    *"event "*) ;;
    *) printf 'FAIL: w9: the %s scenario verdict line does not name the event — the echo must carry event + endpoints + the marker (legibility is the ruling)\n' "$label" >&2; return 1 ;;
  esac
  local warned=no
  case "$out" in *'::warning::'*) warned=yes ;; esac
  if [ "$expect" = yes ] && [ "$warned" = no ]; then
    printf 'FAIL: w9: the %s scenario resolved an empty set with NO ::warning:: — the step-owned warning (OQ12) was silenced for an arm that must warn (only the dispatch no-op, the before==sha no-op and the marker-verified empties are exempt)\n' "$label" >&2
    return 1
  fi
  if [ "$expect" = no ] && [ "$warned" = yes ]; then
    printf 'FAIL: w9: the %s scenario WARNED although it is an exempt shape — a silently dropped exemption (the dispatch no-op and the before==sha no-op are correct semantics; the call bootstrap signal is the SCRIPT announce, not a step warning)\n' "$label" >&2
    return 1
  fi
  return 0
}

w9_marker() { # $1 sdir, $2 label, $3 mode(info|visible), $4 marker value, $5.. env pairs
  local sdir="$1" label="$2" mode="$3" markval="$4"
  shift 4
  local out rc
  if out=$( cd "$sdir" && env GITHUB_OUTPUT="$sdir/output" EVENT_NAME= EVENT_BEFORE= SHA= \
      MANUAL_TEMPLATES= MARKER_SHA= "$@" bash step.sh 2>/dev/null ); then
    rc=0
  else
    rc=$?
  fi
  [ "$rc" -eq 0 ] || { printf 'FAIL: w9: the detect step exited %d in the %s marker scenario — the marker-set arms must stay executable offline\n' "$rc" "$label" >&2; return 1; }
  case "$out" in
    *"templates:"*) ;;
    *) printf 'FAIL: w9: the %s marker scenario printed no verdict line\n' "$label" >&2; return 1 ;;
  esac
  case "$out" in
    *'::warning::'*) printf 'FAIL: w9: the %s scenario WARNED — a marker-verified empty set is the GOOD case: an info line, never an anomaly annotation (the marker PROVES nothing was missed; a green run must never block the fan aggregate advance)\n' "$label" >&2; return 1 ;;
  esac
  case "$out" in
    *'::notice::'*) printf 'FAIL: w9: the %s scenario emitted a ::notice:: — the info line stays a plain echo on this runner (v13.2.0 does not interpret it, the cf-6 OQ-3 class)\n' "$label" >&2; return 1 ;;
  esac
  if [ "$mode" = info ]; then
    case "$out" in
      *'verified empty'*) ;;
      *) printf 'FAIL: w9: the %s scenario carries no verified-empty info line on stdout — the marker-empty exit must announce itself as informational, not fall silent (the "verified empty" token is the stable grep; a fresh owner wording re-pins the token, never the posture)\n' "$label" >&2; return 1 ;;
    esac
  fi
  case "$out" in
    *"marker=$markval"*) ;;
    *) printf 'FAIL: w9: the %s scenario echo does not name marker=%s — the marker endpoint must be visible in the verdict (a marker-fed run reads distinctly from a bootstrap one)\n' "$label" "$markval" >&2; return 1 ;;
  esac
  return 0
}

leg_w9() {
  [ -f "$WF" ] || { printf 'FAIL: w9: %s does not exist (designed-red)\n' "$WF" >&2; return 1; }
  [ -f "$DETECT" ] || { printf 'FAIL: w9: %s does not exist — the behavioral leg stages the SHIPPED detector\n' "$DETECT" >&2; return 1; }
  local sdir
  sdir=$(mktemp -d /tmp/opencode/coder-template-push-w9.XXXXXX) \
    || { printf 'FAIL: w9: harness could not stage the scratch dir\n' >&2; return 1; }
  mkdir -p "$sdir/charts/coder/coder-templates/kubernetes" \
           "$sdir/charts/coder/coder-templates/kubernetes-hardened" \
           "$sdir/charts/coder/coder-templates/ungated" "$sdir/scripts" \
    || { printf 'FAIL: w9: harness could not stage the scratch tree\n' >&2; return 1; }
  cp "$DETECT" "$sdir/scripts/coder-template-detect.sh" \
    || { printf 'FAIL: w9: harness could not copy the shipped detector into the scratch repo\n' >&2; return 1; }
  echo 'terraform' > "$sdir/charts/coder/coder-templates/kubernetes/main.tf"
  echo 'terraform' > "$sdir/charts/coder/coder-templates/kubernetes-hardened/main.tf"
  echo 'not a template' > "$sdir/charts/coder/coder-templates/ungated/README.md"
  echo 'chart' > "$sdir/charts/coder/Chart.yaml"
  git -C "$sdir" init -q . && git -C "$sdir" config user.email test@example.invalid && git -C "$sdir" config user.name test \
    && git -C "$sdir" add -A && git -C "$sdir" commit -qm a \
    || { printf 'FAIL: w9: harness could not init the scratch git repo (scratch trees must be their own repo)\n' >&2; return 1; }
  local S_A; S_A=$(git -C "$sdir" rev-parse HEAD) || return 1
  echo 'terraform c1' >> "$sdir/charts/coder/coder-templates/kubernetes/main.tf"
  echo 'terraform c1' >> "$sdir/charts/coder/coder-templates/kubernetes-hardened/main.tf"
  echo 'untouched' >> "$sdir/charts/coder/coder-templates/ungated/README.md"
  echo 'chart c1' >> "$sdir/charts/coder/Chart.yaml"
  git -C "$sdir" add -A && git -C "$sdir" commit -qm b || return 1
  local S_B; S_B=$(git -C "$sdir" rev-parse HEAD) || return 1
  echo 'chart c2' >> "$sdir/charts/coder/Chart.yaml"
  git -C "$sdir" add -A && git -C "$sdir" commit -qm c || return 1
  local S_C; S_C=$(git -C "$sdir" rev-parse HEAD) || return 1
  echo 'd' >> "$sdir/charts/coder/coder-templates/ungated/README.md"
  git -C "$sdir" add -A && git -C "$sdir" commit -qm d || return 1
  local S_D; S_D=$(git -C "$sdir" rev-parse HEAD) || return 1
  # Stage the detect step's run body (the emit step — the one carrying
  # changed-templates=).
  if ! python3 - "$WF" "$sdir/step.sh" <<'PY'
import sys, yaml

wf, out = sys.argv[1:3]
jobs = (yaml.safe_load(open(wf)) or {}).get("jobs") or {}
texts = []
for job in jobs.values():
    for s in (job or {}).get("steps", []):
        if isinstance(s, dict) and s.get("run") and "changed-templates=" in str(s.get("run", "")):
            texts.append(str(s.get("run", "")))
if len(texts) != 1:
    print("FAIL: w9: %d run bodies carry changed-templates=, expected the one emit step (the body is not staged for execution — designed-red until C04 lands the emit step)" % len(texts), file=sys.stderr)
    sys.exit(1)
open(out, "w").write(texts[0])
PY
  then
    printf 'FAIL: w9: could not stage the detect-step body from %s (designed-red: the emit step is not landed)\n' "$WF" >&2
    rm -rf "$sdir"
    return 1
  fi
  # The eight shapes (ten invocations): the dispatch pair (empty list +
  # all-ungated — the retired C02 divergence), the call bootstrap
  # (step-silent: the script's announce is the signal), the defensive
  # shapes (the real empty push range warns; the before==sha no-op stays
  # silent), the non-empty set (silent; marker-set: the echo names the
  # marker), the marker-verified-empty shapes (call, marker==sha, the
  # defensive push — the calm gate reads MARKER_SHA presence for any
  # event, the round-5 C15 M1 law).
  w9_step "$sdir" 'empty dispatch list'         no  EVENT_NAME=workflow_dispatch MANUAL_TEMPLATES= "SHA=$S_D" || return 1
  w9_step "$sdir" 'all-ungated dispatch list'   no  EVENT_NAME=workflow_dispatch MANUAL_TEMPLATES=ungated "SHA=$S_D" || return 1
  w9_step "$sdir" 'call bootstrap, no marker'   no  EVENT_NAME=workflow_call "EVENT_BEFORE=" "SHA=$S_D" || return 1
  w9_step "$sdir" 'real empty push range'      yes EVENT_NAME=push "EVENT_BEFORE=$S_C" "SHA=$S_D" || return 1
  w9_step "$sdir" 'before-equals-sha push'     no  EVENT_NAME=push "EVENT_BEFORE=$S_D" "SHA=$S_D" || return 1
  w9_step "$sdir" 'non-empty push set'         no  EVENT_NAME=push "EVENT_BEFORE=$S_A" "SHA=$S_B" || return 1
  w9_marker "$sdir" 'marker set, non-empty push' visible "$S_A" EVENT_NAME=push "EVENT_BEFORE=$S_B" "SHA=$S_D" "MARKER_SHA=$S_A" || return 1
  w9_marker "$sdir" 'call + marker + empty range' info  "$S_B" EVENT_NAME=workflow_call "EVENT_BEFORE=" "SHA=$S_D" "MARKER_SHA=$S_B" || return 1
  w9_marker "$sdir" 'marker-equals-sha push'    info  "$S_D" EVENT_NAME=push "EVENT_BEFORE=$S_D" "SHA=$S_D" "MARKER_SHA=$S_D" || return 1
  w9_marker "$sdir" 'defensive push + marker + empty' info "$S_B" EVENT_NAME=push "EVENT_BEFORE=$S_C" "SHA=$S_D" "MARKER_SHA=$S_B" || return 1
  rm -rf "$sdir"
  ok "w9: the step-owned warning law executes right on eight shapes — the dispatch pair (empty + all-ungated, the retired C02 divergence) stays silent, the call bootstrap is step-silent (the script's announce is the signal), the real empty push range without a marker warns, the before==sha no-op stays silent, the non-empty set stays silent (marker-set: the echo names the marker), and the marker-verified-empty shapes (call, marker==sha, the defensive push) exit with the plain verified-empty info line — no annotation, the calm gate reads MARKER_SHA presence for any event (the C15 M1 law; job-log legibility only, no UI-chip claim)"
}
if want w9; then
  leg_w9 || fail "w9: see the w9 detail above"
fi

printf 'PASS: coder template push workflow checks (%d ok)\n' "$checks"
