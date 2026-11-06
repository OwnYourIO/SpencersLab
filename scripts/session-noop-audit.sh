#!/usr/bin/env bash
# cf-106 C03a — read-only audit of how every board-coord session ended.
#
# One row per board-coord session in a window: verdict class, no-op marker,
# archive stamp, launch kind, model, title, and a short last-text excerpt. The
# planning pass produced this table by hand (2026-11-03-cf-106-feat-coord-fixes-
# noop-evidence.md); C03b's fix is judged by re-running this, never by memory.
#
# Posture (owner ruling OQ-11, tests/cf106-noop/readback.md): a HUMAN or an
# interactive session runs it. An unattended tick cannot — its call resolves to
# the ask posture and denies there — and no shell grant is added for it anywhere.
#
# Read-only by construction: the store opens through a file:…?mode=ro URI with
# python3's stdlib sqlite3 (no sqlite3 binary in this workspace). No session-API
# write (POST or PATCH), no board call, no lock-file or session-record write.
#
# Usage:
#   bash scripts/session-noop-audit.sh [--since ISO] [--until ISO]
#       [--repo <directory>] [--limit N] [--json] [--db <path>] [--help]
#
#   --since / --until  ISO date or datetime; naive values are UTC; --until is
#                      exclusive. Window and --limit select rows, they never
#                      change a verdict: classification is per session id, so a
#                      live store gaining sessions cannot move an old row.
#   --repo             exact match on session_v2.directory. Defaults to the
#                      canonical root of the checkout this script sits in when
#                      reading the host store; a --db snapshot/fixture store
#                      carries no implied project, so it is unfiltered unless
#                      --repo says otherwise.
#   --limit N          keep the newest N board-coord sessions in the window
#                      (0 = all). Verdicts are unaffected.
#   --json             print only a JSON array on stdout (the suite's contract).
#   --db               store path; defaults to ~/.local/share/opencode/opencode.db.
#                      A worktree session reads the same host store: sessions
#                      live per project/directory, which is what --repo filters.
#
# Verdict vocabulary — exactly one class per row, marker classes winning over
# stop shapes (that precedence is what makes C03b's fix visible in the table):
#   marked-archived | marked-unarchived | unmarked-archived | gate-stop |
#   abnormal-end | mcp-surface-absent | did-work
# `did-work` is also the fall-through, in two cases: a transcript that yields no
# parsed turn at all (no message rows, or rows the store's shape no longer
# matches) is reported neutrally — an unreadable transcript is never a crash and
# never a claimed death; and a run that parsed turns but reached no exit shape
# lands here too. `abnormal-end` requires evidence: raw call XML in the tail, a
# turn cut off below the floor, or a tail left with no text.
#
# Displayed stamps are workspace-local ISO with offset; the UTC Z spelling when
# TZ is unset, blank, or names a zone this runtime cannot resolve (the cf-96 OQ4
# rule, as `.opencode/plugin/pipeline-locks` implements it). The store's epoch-ms
# values are compared as
# values and are never reformatted for a comparison.
set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  # The whole header block, whatever its length: lines 2 up to the first non-comment.
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
  exit 0
fi

# The scheduled ticks run in the main checkout, so the useful default filter is
# the canonical root — a linked worktree's common dir is that checkout, not the
# worktree the reader happens to sit in.
canon=""
if command -v git >/dev/null 2>&1; then
  common=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  [ -n "$common" ] && canon="${common%/.git}"
fi

CANONICAL_REPO="$canon" python3 - "$@" <<'PY'
"""Classify board-coord sessions over a read-only pass of the session store."""
import argparse, datetime, json, os, re, sqlite3, sys
from zoneinfo import ZoneInfo

COORD_AGENTS = ("agent-board-coord", "agent-board-coord-local", "agent-board-coord-pr")
TURN_FLOOR = 3
EXCERPT_LEN = 160

# The end shape is read from the run's last word: a turn cut off mid-stream emits
# the call XML as text. Earlier turns are not judged — a run that recovered did
# reach an exit.
RAW_CALL = re.compile(r"<\s*/?\s*(?:tool_call|tool_response|function_call|function=|parameter=)", re.I)
MCP_ABSENT = re.compile(
    r"(?:dev-boards|wekan-mcp|board MCP|MCP surface|MCP tools)[^\n.]{0,120}?"
    r"(?:absent|not present|not available|missing|unavailable|unknown tool)"
    r"|(?:absent|missing|unavailable)[^\n.]{0,60}?(?:dev-boards|wekan-mcp|MCP surface)",
    re.I,
)
GATE_LINE = re.compile(r"^\s*(?:GATE:\s*(?:SKIP|LIVE)\b|board[- ]check unavailable|run skipped, fail-closed)", re.I)


def local_iso(ms_val):
    """Workspace-local ISO with an explicit offset, or the UTC Z spelling of the
    same instant when no zone resolves — the shape pipeline-locks' localIso
    stamps, so the two surfaces agree on one instant."""
    if ms_val is None:
        return None
    utc = datetime.datetime.fromtimestamp(ms_val / 1000, datetime.timezone.utc)
    zone = (os.environ.get("TZ") or "").strip()
    if zone:
        try:
            stamp = utc.astimezone(ZoneInfo(zone)).isoformat(timespec="seconds")
            # Z is that offset's own designator: one spelling per instant, so a
            # TZ=UTC workspace and the fallback never read as two stamp eras.
            return stamp.replace("+00:00", "Z")
        except (KeyError, ValueError):
            pass
    return utc.strftime("%Y-%m-%dT%H:%M:%SZ")


def model_label(raw):
    """The live store keeps `model` as a JSON object, older rows and fixtures as
    a bare string; the column has to read as one id either way."""
    if not raw:
        return None
    try:
        body = json.loads(raw)
    except (TypeError, ValueError):
        return raw
    if isinstance(body, dict):
        return body.get("id") or raw
    return raw


def parse_bound(text):
    """Instant in epoch-ms. A naive value names UTC; --until is exclusive at it."""
    try:
        dt = datetime.datetime.fromisoformat(text)
    except ValueError:
        raise SystemExit(f"not an ISO date/datetime: {text!r}")
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return int(dt.timestamp() * 1000)


def one_line(text, limit=EXCERPT_LEN):
    return " ".join((text or "").split())[:limit]


def texts(rows):
    """Split a session's transcript into (users, assistants, last_assistant)."""
    users, assistants = [], []
    for typ, _seq, data in rows:
        try:
            body = json.loads(data)
        except (TypeError, ValueError):
            continue
        if typ == "user":
            users.append(str(body.get("text") or ""))
        elif typ == "assistant":
            parts = [c.get("text") or "" for c in (body.get("content") or []) if c.get("type") == "text"]
            assistants.append(" ".join(p for p in parts if p).strip())
    return users, assistants, (assistants[-1] if assistants else "")


def classify(marker, archived, users, assistants, last):
    if marker:
        return "marked-archived" if archived else "marked-unarchived"
    if archived:
        return "unmarked-archived"
    if RAW_CALL.search(last):
        return "abnormal-end"
    if MCP_ABSENT.search(last):
        return "mcp-surface-absent"
    if any(GATE_LINE.match(line) for text in users for line in text.splitlines()):
        return "gate-stop"
    turns = len(users) + len(assistants)
    if turns == 0:
        # Nothing parsed: a store-shape change or an unreadable transcript must
        # read neutral, or schema drift would manufacture a wave of "died before
        # any exit" — the class the plan reads as a coverage gap.
        return "did-work"
    if turns < TURN_FLOOR or not last:
        # evidence of a death: too few turns to have reached an exit, or a turn
        # cut off mid-stream leaves the tail with no text
        return "abnormal-end"
    return "did-work"


def main(argv):
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--since")
    ap.add_argument("--until")
    ap.add_argument("--repo")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--json", action="store_true", dest="as_json")
    ap.add_argument("--db")
    ap.add_argument("--help", action="store_true")
    args, extra = ap.parse_known_args(argv)
    if args.help or extra:
        print(__doc__.strip() if args.help else f"unknown arguments: {' '.join(extra)}", file=sys.stderr)
        return 2

    default_db = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "opencode", "opencode.db")
    db = os.path.expanduser(args.db) if args.db else default_db
    repo = args.repo
    if repo is None and db == default_db:
        repo = os.environ.get("CANONICAL_REPO") or None

    since = parse_bound(args.since) if args.since else None
    until = parse_bound(args.until) if args.until else None

    where, params = [], []
    agents = ",".join("?" for _ in COORD_AGENTS)
    where.append(f"agent IN ({agents})")
    params += list(COORD_AGENTS)
    if since is not None:
        where.append("time_created >=?")
        params.append(since)
    if until is not None:
        where.append("time_created <?")
        params.append(until)
    if repo:
        where.append("directory = ?")
        params.append(repo)
    sql = ("select id, agent, directory, title, model, metadata, time_created, time_archived, idle_outcome"
           " from session_v2 where " + " and ".join(where) + " order by time_created desc")
    if args.limit > 0:
        sql += f" limit {int(args.limit)}"

    if not os.path.exists(db):
        print(f"store not found: {db}", file=sys.stderr)
        return 1
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    except sqlite3.Error as exc:
        print(f"cannot open {db} read-only: {exc}", file=sys.stderr)
        return 1
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    try:
        sessions = list(cur.execute(sql, tuple(params)))
    except sqlite3.Error as exc:
        print(f"store read failed: {exc}", file=sys.stderr)
        return 1

    out = []
    for s in sorted(sessions, key=lambda s: s["time_created"] or 0):
        try:
            meta = json.loads(s["metadata"]) if s["metadata"] else {}
        except ValueError:
            meta = {}
        noop = meta.get("pipelineNoop") or {}
        marker = noop.get("reason") or None
        rows = list(cur.execute("select type, seq, data from session_message where session_id=? order by seq",
                                (s["id"],)))
        users, assistants, last = texts(rows)
        archived = s["time_archived"] is not None
        out.append({
            "id": s["id"],
            "verdict": classify(marker, archived, users, assistants, last),
            "marker": marker,
            "markerAt": noop.get("at"),
            "archived": archived,
            "archivedAt": local_iso(s["time_archived"]),
            "kind": (meta.get("openchamber") or {}).get("kind"),
            "agent": s["agent"],
            "model": model_label(s["model"]),
            "title": s["title"],
            "directory": s["directory"],
            "created": local_iso(s["time_created"]),
            "turns": len(users) + len(assistants),
            "idle": s["idle_outcome"],
            "excerpt": one_line(last),
        })
    con.close()

    if args.as_json:
        json.dump(out, sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
        return 0

    print(f"store: {db}\nwindow: {args.since or '-'} .. {args.until or '-'}   repo: {repo or '(all)'}"
          f"   agents: {', '.join(COORD_AGENTS)}   sessions: {len(out)}")
    wide = ("created", "id", "verdict", "kind", "marker", "arch", "turns", "model", "title", "excerpt")
    def cell(r, key):
        if key == "arch":
            return "yes" if r["archived"] else "no"
        val = r.get(key)
        return "" if val is None else str(val)
    def width(key):
        return max(len(key), *(len(cell(r, key)) for r in out)) if out else len(key)
    cuts = {"title": 40, "excerpt": 90, "model": 30, "id": 24}
    header = "  ".join(k.ljust(min(width(k), cuts.get(k, 99))) for k in wide)
    print(header)
    for r in out:
        line = []
        for k in wide:
            w = min(width(k), cuts.get(k, 99))
            line.append(cell(r, k)[:w].ljust(w))
        print("  ".join(line).rstrip())
    tally = {}
    for r in out:
        tally[r["verdict"]] = tally.get(r["verdict"], 0) + 1
    print("tally: " + "  ".join(f"{k}={tally[k]}" for k in sorted(tally)))
    return 0


sys.exit(main(sys.argv[1:]))
PY
