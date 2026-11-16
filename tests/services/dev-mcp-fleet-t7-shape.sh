#!/usr/bin/env bash
# cf-6 C01/C03 shape leg (2026/2026-11-cf-6-feat-forgejo-container-builds-3,
# chunks/C01.md "## Tests" — "the t7 extension verified by the C03 shape leg
# (offline python re check)" — + C03 task 2, AUTHORITATIVE): the
# tests/services/dev-mcp-fleet.sh t7 wekan-mcp image regex pinned offline.
# C01 widens it (post-approval ruling 5, EXTEND NOW in C01) from
# (main|v[0-9]+) to the calendar-accepting shape; the superset law is the
# pin: main and v<digits> must still match after the change, the calendar
# form (yy.mm.N) is what the extension adds, and card-134 leg B moves the
# pin onto exactly this shape owing NO test edit because of it (plan
# "Card-134 post-merge sequence").
#
# Why this file exists instead of a live t7 run: the targeted
# `bash tests/services/dev-mcp-fleet.sh t7` renders the hivetools chart via
# `helm dependency update` against the OCI registry — the suite's own rule is
# "registry-unreachable is skip-with-warning only … (t6-t8/t11 OCI toolhive
# deps)" — so a live t7 leg is non-deterministic in agent sessions and a
# skipped leg is not a bar pass (plan Commands). A live run stays OPTIONAL
# corroboration and a skip-with-warning never overrides this shape leg.
#
# The regex under test is extracted from tests/services/dev-mcp-fleet.sh at
# run time (never duplicated here, the dockerfile-pins.sh convention) and
# fullmatched in python re — the same call shape as the in-suite leg, so the
# rejection rows (1.2.3 / v1.2.3) test what the leg actually tests.
#
# AC trace: s1[C01 AC5-extraction] s2[C01 AC5-v-window] s3[C01 AC5-main]
# s4[C01 AC5-calendar] s5[C01 AC5-reject-single-digit] s6[C01 AC5-reject-v-dotted].
#
# Purely static — no network. Usage (from anywhere in the worktree):
#   bash tests/services/dev-mcp-fleet-t7-shape.sh
#   FLEET_SH=<path> bash tests/services/dev-mcp-fleet-t7-shape.sh
# FLEET_SH defaults to tests/services/dev-mcp-fleet.sh; the override runs the
# same contract against a simulated final file.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

FLEET="${FLEET_SH:-tests/services/dev-mcp-fleet.sh}"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

# The extraction anchor (shared by every leg; re-run per block, the
# forgejo-move-config house shape): the t7 region is the only
# re.fullmatch(<wekan-mcp image>, bd_image) call in the file, and the
# `', bd_image` tail keeps a re-quoted comment from double-matching.
# The prefix ghcr\.io/ownyourio/wekan-mcp: is invariant across the C01
# widening (only the tag alternation inside moves), so the anchor survives
# the edit and line re-wrapping alike.

# --- s1: the t7 image regex extracts (one call, compiling pattern) ----------
if ! python3 - "$FLEET" <<'PY'
import re, sys

text = open(sys.argv[1]).read()


def need(cond, msg):
    if not cond:
        print(f'FAIL: s1: {msg}', file=sys.stderr)
        sys.exit(1)


hits = re.findall(r"re\.fullmatch\(r'(ghcr\\\.io/ownyourio/wekan-mcp:[^']+)',\s*bd_image", text)
need(len(hits) == 1,
     f'expected exactly one wekan-mcp re.fullmatch(…, bd_image) call in {sys.argv[1]}, found {len(hits)}')
try:
    re.compile(hits[0])
except re.error as e:
    need(False, f'the extracted t7 image regex does not compile: {e}')
PY
then
  fail "s1: see the s1 detail above"
fi
ok "s1: the t7 wekan-mcp image regex extracts as exactly one compiling re.fullmatch(…, bd_image) call"

# --- s2: the v<digits> window survives the widening -------------------------
if ! python3 - "$FLEET" <<'PY'
import re, sys

text = open(sys.argv[1]).read()


def need(cond, msg):
    if not cond:
        print(f'FAIL: s2: {msg}', file=sys.stderr)
        sys.exit(1)


hits = re.findall(r"re\.fullmatch\(r'(ghcr\\\.io/ownyourio/wekan-mcp:[^']+)',\s*bd_image", text)
need(len(hits) == 1, f'expected exactly one wekan-mcp fullmatch call, found {len(hits)}')
rx = re.compile(hits[0])
# The superset law (post-approval ruling 5): the pre-existing window stays
# green on both sides of the C01 change. v162 is the live pin, v177 the
# live unpinned max (EXPLORE.md §2).
for tag in ('v162', 'v177'):
    need(rx.fullmatch(f'ghcr.io/ownyourio/wekan-mcp:{tag}') is not None,
         f'the t7 regex does not accept :{tag} — the v<digits> pin window must survive the '
         'calendar widening')
PY
then
  fail "s2: see the s2 detail above"
fi
ok "s2: the t7 regex still accepts the v<digits> window (:v162 the live pin, :v177 the live max)"

# --- s3: the rolling :main form survives -------------------------------------
if ! python3 - "$FLEET" <<'PY'
import re, sys

text = open(sys.argv[1]).read()


def need(cond, msg):
    if not cond:
        print(f'FAIL: s3: {msg}', file=sys.stderr)
        sys.exit(1)


hits = re.findall(r"re\.fullmatch\(r'(ghcr\\\.io/ownyourio/wekan-mcp:[^']+)',\s*bd_image", text)
need(len(hits) == 1, f'expected exactly one wekan-mcp fullmatch call, found {len(hits)}')
rx = re.compile(hits[0])
need(rx.fullmatch('ghcr.io/ownyourio/wekan-mcp:main') is not None,
     'the t7 regex does not accept :main — the rolling form must survive the calendar widening')
PY
then
  fail "s3: see the s3 detail above"
fi
ok "s3: the t7 regex still accepts the rolling :main form"

# --- s4: the calendar form (the C01 extension) ------------------------------
if ! python3 - "$FLEET" <<'PY'
import re, sys

text = open(sys.argv[1]).read()


def need(cond, msg):
    if not cond:
        print(f'FAIL: s4: {msg}', file=sys.stderr)
        sys.exit(1)


hits = re.findall(r"re\.fullmatch\(r'(ghcr\\\.io/ownyourio/wekan-mcp:[^']+)',\s*bd_image", text)
need(len(hits) == 1, f'expected exactly one wekan-mcp fullmatch call, found {len(hits)}')
rx = re.compile(hits[0])
# The yy.mm.N form the extension adds (C01, post-approval ruling 5): 26.11.1
# is the first calendar tag leg A mints, 26.11.2 the second — leg B moves
# the pin onto exactly this shape and owes no test edit.
for tag in ('26.11.1', '26.11.2'):
    need(rx.fullmatch(f'ghcr.io/ownyourio/wekan-mcp:{tag}') is not None,
         f'the t7 regex does not accept :{tag} — the calendar form yy.mm.N is the C01 '
         'extension (ruling 5) and card-134 leg B pins onto it')
PY
then
  fail "s4: see the s4 detail above"
fi
ok "s4: the t7 regex accepts the calendar form :26.11.1 and :26.11.2 (the C01 extension)"

# --- s5: one-digit dotted components must NOT match --------------------------
if ! python3 - "$FLEET" <<'PY'
import re, sys

text = open(sys.argv[1]).read()


def need(cond, msg):
    if not cond:
        print(f'FAIL: s5: {msg}', file=sys.stderr)
        sys.exit(1)


hits = re.findall(r"re\.fullmatch\(r'(ghcr\\\.io/ownyourio/wekan-mcp:[^']+)',\s*bd_image", text)
need(len(hits) == 1, f'expected exactly one wekan-mcp fullmatch call, found {len(hits)}')
rx = re.compile(hits[0])
# The plan shape leg: the calendar form is exactly two-digit yy.mm, so
# one-digit components must not match (fullmatch, not prefix).
need(rx.fullmatch('ghcr.io/ownyourio/wekan-mcp:1.2.3') is None,
     'the t7 regex accepts :1.2.3 — one-digit components must not match the calendar form')
PY
then
  fail "s5: see the s5 detail above"
fi
ok "s5: the t7 regex rejects :1.2.3 (one-digit components)"

# --- s6: the dotted v-form must NOT match ------------------------------------
if ! python3 - "$FLEET" <<'PY'
import re, sys

text = open(sys.argv[1]).read()


def need(cond, msg):
    if not cond:
        print(f'FAIL: s6: {msg}', file=sys.stderr)
        sys.exit(1)


hits = re.findall(r"re\.fullmatch\(r'(ghcr\\\.io/ownyourio/wekan-mcp:[^']+)',\s*bd_image", text)
need(len(hits) == 1, f'expected exactly one wekan-mcp fullmatch call, found {len(hits)}')
rx = re.compile(hits[0])
# The plan shape leg: the v-pin window is digits-only (v[0-9]+); the v1
# prefix of v1.2.3 is not a full match, so the dotted v-form must reject.
need(rx.fullmatch('ghcr.io/ownyourio/wekan-mcp:v1.2.3') is None,
     'the t7 regex accepts :v1.2.3 — the dotted v-form must not match (the v-pin window is digits-only)')
PY
then
  fail "s6: see the s6 detail above"
fi
ok "s6: the t7 regex rejects :v1.2.3 (the v-pin window stays digits-only)"

printf 'PASS: dev-mcp-fleet-t7-shape checks (%d ok)\n' "$checks"
