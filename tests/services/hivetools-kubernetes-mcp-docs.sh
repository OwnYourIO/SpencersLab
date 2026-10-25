#!/usr/bin/env bash
# mcp-servers.md docs contract for the kubernetes-mcp TOML migration
# (2026/2026-10-bug-kubernetes-mcp-toml, C03):
#   The repo's own rules demand docs travel with the change, and this doc is
#   the implementation guide every future MCP-server onboarding follows. A doc
#   still describing `--read-only` as a live flag is a blueprint for
#   reproducing the 2026-10-25 crashloop on the next server. Assertions bind
#   to CONTENT markers, not line numbers — the doc will have shifted.
#
# Contract source: chunks/C03.md "Interface contract"-tasks + "## Tests".
# AC trace: d1[AC1] d2[AC2] d3[AC3] d4[AC4].
# d4 also runs `rulesync generate --check` because AGENTS.md is a GENERATED
# surface (Hard rule: never hand-edit): the contract is on the rules SOURCE +
# generator freshness — generated surfaces untouched AND fresh-from-source —
# not on hand-edited output. If rulesync is not resolvable offline the check
# is a skip-with-warning (dev-mcp-fleet.sh t14 convention; this machine has
# v37 cached).
#
# Usage (default all; unknown ids fail):
#   bash tests/services/hivetools-kubernetes-mcp-docs.sh
#   bash tests/services/hivetools-kubernetes-mcp-docs.sh d2
# Cross-chunk: after C03 lands, re-run sequentially
#   bash tests/services/hivetools-kubernetes-mcp-toml.sh t7   (docs edits must not disturb values)
#   bash tests/services/dev-mcp-fleet.sh                      (full suite at final review)
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

DOC="skills/helm-chart-creation/references/mcp-servers.md"
GENERATED_SURFACES=(AGENTS.md .opencode/ .rulesync/)

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
  for i in 1 2 3 4; do WANT["d$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^d[1-4]$ ]] ||
      fail "unknown test id '$a' (expected d1..d4)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

[ -f "$DOC" ] || fail "precondition: $DOC is missing (C03's file in scope)"

WORK=$(mktemp -d /tmp/opencode/hivetools-kubernetes-mcp-docs.XXXXXX)

# =========================================================================
# d1 [AC1] — field block documents configFile delivery + flag-less binaries
# =========================================================================
if want d1; then
  if python3 - "$DOC" "$WORK/d1-count" <<'PY'
import re, sys

doc_path, count_file = sys.argv[1:3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

def section(text, needle):
    """Text of the level-2 `##` section whose heading contains needle."""
    lines = text.splitlines()
    start = next((i for i, l in enumerate(lines) if l.startswith('## ') and needle in l), None)
    if start is None:
        return None
    end = next((j for j in range(start + 1, len(lines)) if lines[j].startswith('## ')), len(lines))
    return '\n'.join(lines[start:end])

try:
    text = open(doc_path).read()
    field = section(text, '`mcp.<name>` entry fields')
    if field is None:
        bad('d1: the "## `mcp.<name>` entry fields" section is gone — the field block AC1 binds to must stay findable')

    missing = [m for m in ('configFile', '/etc/kubernetes-mcp-server/config.toml', 'hostPath') if m not in field]
    if missing:
        bad(f'd1: the field block does not document config-file delivery — missing markers {missing} (configFile key, the mounted path, and WHY via podTemplateSpec: MCPServer spec.volumes is hostPath-only)')
    if not re.search(r'not\s*`?subPath', field, re.I):
        bad('d1: the field block must state the mount is "not subPath" (subPath projections never refresh on ConfigMap edits)')
    ok('d1: field block documents configFile, the mounted path, hostPath constraint, and the not-subPath mount (C03 AC1)')

    # "runtime flags no longer exist on kubernetes-mcp-server >= v0.0.68" in
    # some wording. Accept either the upstream-chart phrasing the C03 task
    # quotes ("Only bootstrap flags") or a v0.0.68 window that couples flags
    # with removal vocabulary.
    flat = ' '.join(text.split())
    stated = bool(re.search(r'only\s+bootstrap\s+flags?', flat, re.I))
    if not stated:
        for m in re.finditer(r'v0\.0\.68', flat):
            window = flat[max(0, m.start() - 300):m.end() + 300]
            if re.search(r'flag', window, re.I) and re.search(r'removed|dropped|deleted|no longer|gone|never', window, re.I):
                stated = True
                break
    if not stated:
        hints = [l for l in text.splitlines() if '0.0.68' in l or 'ootstrap' in l][:8]
        bad(f'd1: no statement that kubernetes-mcp-server >= v0.0.68 has no runtime flags ("Only bootstrap flags" or equivalent). Lines mentioning 0.0.68/bootstrap for context: {hints!r}')
    ok('d1: the doc states that runtime flags no longer exist on kubernetes-mcp-server >= v0.0.68 (C03 AC1)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f'd1: the docs file could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/d1-count")))
  else
    exit 1
  fi
fi

# =========================================================================
# d2 [AC2] — tier section presents the TOML mechanism; dead flags survive only
#            as marked history; RBAC-boundary and configuration_view kept
# =========================================================================
if want d2; then
  if python3 - "$DOC" "$WORK/d2-count" <<'PY'
import re, sys

doc_path, count_file = sys.argv[1:3]
ok_n = 0

def ok(msg):
    global ok_n
    ok_n += 1
    print(f'ok: {msg}')

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

try:
    lines = open(doc_path).read().splitlines()

    # Region: the kubernetes tier section, plus — if dev raised "Config-file
    # delivery" to `##` level — any such level-2 sections immediately after
    # it. A `###`/`####` subsection is already inside the section window.
    start = next((i for i, l in enumerate(lines) if l.startswith('## ') and 'Kubernetes MCP servers' in l), None)
    if start is None:
        bad('d2: the "## Kubernetes MCP servers" section is gone')
    end = next((j for j in range(start + 1, len(lines)) if lines[j].startswith('## ')), len(lines))
    # Extend through any directly-following config-file-delivery sections so
    # markers placed in that sanctioned subsection are not reported missing.
    while end < len(lines) and lines[end].startswith('## ') and re.search(r'config.file delivery', lines[end], re.I):
        end = next((j for j in range(end + 1, len(lines)) if lines[j].startswith('## ')), len(lines))
    region = '\n'.join(lines[start:end])

    for marker in ('read_only = true', 'config.toml', 'configuration_view', 'RBAC is the boundary'):
        if marker not in region:
            bad(f'd2: the tier region lacks {marker!r} — it must present TOML read_only = true as the mechanism (with the mounted config.toml), record the configuration_view HTTP-mode delta (disabled by default since v0.0.68), and keep "RBAC is the boundary" — read_only only hides write tools, it never enforced them')
    ok('d2: tier region presents read_only = true/config.toml, records the configuration_view delta, keeps "RBAC is the boundary" (C03 AC2)')

    # The chunk's history-marker rule: the deleted flags may appear ONLY as
    # history — every line mentioning them must also carry a marker. An
    # unmarked occurrence reads as a live-arg instruction.
    HISTORY = ('v0.0.65', 'before', 'pre-migration', 'incident', 'dropped', 'removed')
    viol = []
    for i, l in enumerate(lines):
        if re.search(r'--(?:port|stateless|read-only)', l) and not any(h in l.lower() for h in HISTORY):
            viol.append(f'{i + 1}: {l.strip()[:100]}')
    if viol:
        bad(f'd2: lines claim the deleted flags as live usage without a history marker {HISTORY}:\n  ' + '\n  '.join(viol))
    ok('d2: every --port/--stateless/--read-only occurrence in the doc is marked history (C03 AC2)')
    with open(count_file, 'w') as f:
        f.write(str(ok_n))
except SystemExit:
    raise
except Exception as ex:
    bad(f'd2: the docs file could not be evaluated ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/d2-count")))
  else
    exit 1
  fi
fi

# =========================================================================
# d3 [AC3] — the secrets[] list-map constraint note stays, un-duplicated
# =========================================================================
if want d3; then
  if python3 - "$DOC" "$WORK/d3-count" <<'PY'
import sys

doc_path, count_file = sys.argv[1:3]

def bad(msg):
    print(f'FAIL: {msg}', file=sys.stderr)
    sys.exit(1)

# The constraint already exists (added with the 2026-10-25 boards ruling).
# C03's new config-file note must sit beside the args/podTemplateSpec notes
# and must NOT restate it — a duplicated constraint drifts into a
# contradiction the next editor cannot resolve.
try:
    text = open(doc_path).read()
    n = text.count('x-kubernetes-list-type: map')
    if n != 1:
        bad(f'd3: "x-kubernetes-list-type: map" occurs {n} times, expected exactly 1 (constraint note present, un-duplicated)')
    print('ok: d3: the secrets[] list-map constraint appears exactly once (C03 AC3)')
    with open(count_file, 'w') as f:
        f.write('1')
except SystemExit:
    raise
except Exception as ex:
    bad(f'd3: the docs file could not be read ({type(ex).__name__}: {ex})')
PY
  then
    checks=$((checks + $(cat "$WORK/d3-count")))
  else
    exit 1
  fi
fi

# =========================================================================
# d4 [AC4] — generated surfaces untouched + generator freshness
# =========================================================================
# D7 decided AGENTS.md needs NO line for this change; C03 therefore VERIFIES
# rather than edits. Two halves: (1) nothing changed in AGENTS.md/.opencode/
# .rulesync/ since the branch base — including untracked additions, which
# plain `git diff` misses; (2) `rulesync generate --check` still clean, so
# the untouched output is also still what the sources generate (untouched
# but STALE output would equally fail the Hard rule).
if want d4; then
  base="${GIT_BASE:-}"
  if [ -z "$base" ]; then
    base=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD origin/main 2>/dev/null || true)
  fi
  [ -n "$base" ] ||
    fail "d4: cannot resolve the branch base (set GIT_BASE=<sha> so generated-surface drift since branching can be measured)"

  dirty=$(git diff --name-only "$base" -- "${GENERATED_SURFACES[@]}")
  if [ -n "$dirty" ]; then
    printf '%s\n' "$dirty" >&2
    fail "d4: AGENTS.md/.opencode//.rulesync/ changed on this branch (list above) — D7: this ticket adds no new skill or MCP server; if review overrules, the edit goes to .rulesync/rules/overview.md + regeneration, never the output (C03 AC4)"
  fi
  stray=$(git status --porcelain -- "${GENERATED_SURFACES[@]}")
  if [ -n "$stray" ]; then
    printf '%s\n' "$stray" >&2
    fail "d4: untracked/ignored-skip additions under the generated surfaces (list above) — git diff alone would miss them (C03 AC4)"
  fi
  ok "d4: AGENTS.md, .opencode/, .rulesync/ show no diff since base $(git rev-parse --short "$base") (C03 AC4)"

  if ! command -v npx >/dev/null 2>&1 || ! npx --no-install rulesync --version >"$WORK/rulesync-probe.log" 2>&1; then
    skip "d4: rulesync is not resolvable via npx --no-install here; the generator-freshness half of d4 was not run (the no-diff half passed)"
  else
    rs_version=$(cat "$WORK/rulesync-probe.log")
    check_log="$WORK/rulesync-check.log"
    if ! npx --no-install rulesync generate --check >"$check_log" 2>&1; then
      tail -n 30 "$check_log" >&2
      fail "d4: rulesync generate --check reports drift ($rs_version) — committed generated output is not fresh from the .rulesync/ sources; C03 verifies, never edits generated surfaces (C03 AC4)"
    fi
    ok "d4: rulesync generate --check is clean ($rs_version, offline via npx cache) — sources and committed output agree (C03 AC4)"
  fi
fi

rm -rf "$WORK"

printf 'PASS: hivetools-kubernetes-mcp-docs checks (%d ok)\n' "$checks"
