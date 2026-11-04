#!/usr/bin/env python3
"""Doc<->registry tool-surface parity, one implementation for every wekan-mcp suite.

Each count literal a suite hard-coded was a third number between the docs and
server.py, so a sanctioned +1 left suites passing on prose that no longer
described the registry (cf-68 FRICTION: missed parity literals; cf-106 C07 grew
the registry 38->39 and re-exposed it). Exit 2 on a harness fault so a broken
invocation can never read as a contract red.

  counts <server.py>                      -> "<reads> <writes> <total>" on stdout
  claims <server.py> <doc>...             -> every "<n> tools"/"<n>-tool" claim must equal total
  rows <server.py> <doc>...               -> table rows must equal the registered name set
"""
import ast
import re
import sys

CLAIM = re.compile(
    # The house spellings of a tool-count claim. A bare "<n> tools" is left out on
    # purpose: it also matches subset prose ("the 5 dependency tools"), and every
    # doc that states the surface size uses one of these forms (the suites'
    # count-presence arms require one per doc, so a doc cannot dodge the scan by
    # rewording).
    r"(\d+)[- ](?:typed tools|tool surface)"
    r"|all (\d+) tools"
    r"|full, (\d+) tools"
    r"|(\d+)-tool"
)
ROW = re.compile(r"^\|\s*`([a-z_]+)`\s*\|", re.M)
# README lists tools in one section; its tier/deployment tables carry backticked
# names that are not tools, so the row check is scoped by section, not file name.
README_SECTION = re.compile(r"(?m)^## Tools exposed\n(.*?)(?=^## |\Z)")


def harness(msg):
    # Distinct exit code: a broken invocation must never read as a contract red.
    print(msg, file=sys.stderr)
    raise SystemExit(2)


def registry(path):
    try:
        tree = ast.parse(open(path).read())
    except OSError as exc:
        harness(f"cannot read {path}: {exc}")
    reads, writes = [], []
    for node in tree.body:
        if not isinstance(node, ast.FunctionDef):
            continue
        for dec in node.decorator_list:
            if (isinstance(dec, ast.Attribute) and dec.attr == "tool"
                    and isinstance(dec.value, ast.Name) and dec.value.id == "mcp"):
                reads.append(node.name)
            elif isinstance(dec, ast.Name) and dec.id == "_write_tool":
                writes.append(node.name)
    if not reads or not writes:
        # A registry that parses to nothing means the AST walk lost the
        # decorators, not that the surface is empty.
        harness(f"{path} registered {len(reads)} reads + {len(writes)} writes — the decorator walk is broken")
    return reads, writes


def section_of(text):
    # README documents tools in one section; its tier/deployment tables carry
    # backticked names that are not tools. Restricting by section keeps the
    # check name-based instead of file-name-based.
    m = README_SECTION.search(text)
    return m.group(1) if m else text


def main(argv):
    mode, server, docs = argv[1], argv[2], argv[3:]
    reads, writes = registry(server)
    names = set(reads) | set(writes)
    total = len(reads) + len(writes)

    if mode == "counts":
        print(f"{len(reads)} {len(writes)} {total}")
        return 0

    if mode == "claims":
        bad = []
        for doc in docs:
            text = open(doc).read()
            for m in CLAIM.finditer(text):
                n = int(next(g for g in m.groups() if g))
                if n != total:
                    where = text[max(0, m.start() - 45):m.end() + 15].replace("\n", " ")
                    bad.append(f"{doc} claims {n} ({where!r})")
        if bad:
            print(f"every tool-count claim must state the live registry count "
                  f"({total} = {len(reads)} reads + {len(writes)} writes) from {server}:")
            print("\n".join(f"  {b}" for b in bad))
            return 1
        return 0

    if mode == "rows":
        bad = []
        for doc in docs:
            found = ROW.findall(section_of(open(doc).read()))
            dupes = sorted({n for n in found if found.count(n) > 1})
            missing, extra = sorted(names - set(found)), sorted(set(found) - names)
            if missing:
                bad.append(f"{doc} documents no row for {missing}")
            if extra:
                bad.append(f"{doc} documents rows for unregistered tools {extra}")
            if dupes:
                bad.append(f"{doc} documents {dupes} more than once — one stamped row per tool")
        if bad:
            print(f"documented tool rows must equal the registry name set "
                  f"({total} names in {server}):")
            print("\n".join(f"  {b}" for b in bad))
            return 1
        return 0

    harness(f"unknown mode {mode!r} (want counts|claims|rows)")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
