"""Re-derive and guard the C03 delta fixtures (test-session machinery, not a test).

C03's proof changed shape twice since this fixture was minted. D35 made the
render MOVING on four ruled paths (the delta-budget era, rounds 1-2). D43
(2026-11-22, owner ruling) retired the budget's argv side: the render may
again move ONLY on env, command, args, volumes/mounts and the checksum
annotation, and the fixture is now the baseline of the PER-PROPERTY
INVARIANCE legs in test_c03_generic_shell.py (image@digest, probes,
securityContext, claim pair, memory, cpu, replicas, grace — byte-equal, pool
name folded). The fixture's duty is unchanged by all of it: it is the BASELINE
side, and the law below is what keeps it honest.

The fixture's authority is the pinned commit it records (captured_from_commit),
NOT the working tree: this script renders the chart and the service-roster
block AT THAT COMMIT via `git archive`, folds the pool name to `<POOL>`, and
REFUSES TO WRITE unless the re-derived deployment equals the committed fixture
exactly. The fold runs at the PIN's own canonical claim constant (loaded from
the pinned tree): the base predates the C01 rename, so the fixture is an
era-folded artifact, and folding a base render at today's constant would mint
`<POOL>-1` tokens that match nothing — that mismatch is the leg's teeth, not a
fold to reproduce here. It re-validates the evidence for the review tier; it
cannot launder
it. A mismatch means one of three things — the tree at the pin changed (it
must not), the app-template dependency drifted under the borrow (Chart.lock
guard below), or the fixture was hand-edited (the class this guard exists to
catch). The pre-move fixtures are never deleted and never re-pointed at a
newer commit.

Run from the repo root (the review tier's first step):

    export PATH=$HOME/.local/bin:$PATH
    python3 charts/radiance/tests/capture_c03_fixtures.py
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent.parent
sys.path.insert(0, str(HERE))

EVIDENCE = HERE / "evidence"

# release name == the derived Application name; the -f file is exactly what the
# ApplicationSet's per-app merge feeds helm (`index $.Values $appName`).
RELEASES = {
    "radiance": "gpu-ai-radiance",
    "radiance-q27": "gpu-ai-radiance-q27",
}


def pinned_claim(pinned: Path) -> str:
    """The canonical R9700 claim constant AS THE PINNED TREE SPELLS IT, loaded
    from that tree's own amd-gpu testlib (the ledger's home, single source for
    the names). The fold must run at the PIN's era: the base commit predates
    the C01 rename, so its render carries the then-canonical spelling and the
    original capture folded THAT to <POOL>. Folding a base-era render at
    today's constant instead turns the retired spelling into <POOL>-1 — a
    token no fixture key matches — which is the leg's teeth mechanism, not a
    fold to reproduce here. Loaded from git's pin, never from the fixture, so
    a hand-edited fixture cannot pick its own folding."""
    lib = pinned / "charts" / "amd-gpu" / "tests" / "amd_gpu_testlib.py"
    spec = importlib.util.spec_from_file_location("pinned_amd_gpu_testlib", lib)
    assert spec is not None and spec.loader is not None, f"cannot load pinned testlib at {lib}"
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.R9700_CLAIM


def fold_pool(text: str, claim: str) -> str:
    return text.replace(claim, "<POOL>")


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True, timeout=300)


def export_pin(commit: str, dest: Path) -> None:
    """Materialize the exact pinned tree — archive, not checkout: the working
    tree is the post-move side of the comparison and must stay untouched."""
    if git("cat-file", "-e", f"{commit}^{{commit}}").returncode != 0:
        raise SystemExit(f"C03 fixture guard: base commit {commit} is not in this repo's history — "
                         "the pin must stay reachable (never GC the base revision the fixtures bless)")
    proc = subprocess.run(f"git -C {REPO} archive --format=tar {commit} | tar -x -C {dest}",
                          shell=True, capture_output=True, text=True, timeout=300)
    if proc.returncode != 0:
        raise SystemExit(f"C03 fixture guard: git archive of {commit} failed:\n{proc.stderr}")


def borrow_dependencies(pinned: Path) -> None:
    """app-template ships as a packed tgz that is not tracked in git; borrow
    the working tree's tgz into the pinned tree. Sound only while Chart.lock
    is identical across the pin — guard that, or a dependency upgrade would
    silently bless a different render than the base produced."""
    lock_rel = "charts/radiance/Chart.lock"
    pinned_lock = pinned / lock_rel
    live_lock = REPO / lock_rel
    if pinned_lock.read_text() != live_lock.read_text():
        raise SystemExit(f"C03 fixture guard: {lock_rel} differs between the pinned tree and HEAD — "
                         "the tgz borrow is unsound (the pinned render would use a different app-template); "
                         "the fixtures must be re-explained by a fresh ruling, not silently re-derived")
    deps = pinned / "charts" / "radiance" / "charts"
    deps.mkdir(exist_ok=True)
    for tgz in sorted((REPO / "charts" / "radiance" / "charts").glob("*.tgz")):
        if not (deps / tgz.name).exists():
            shutil.copy2(tgz, deps / tgz.name)


def render(pinned: Path, key: str, release: str) -> dict:
    chart = pinned / "charts" / "radiance"
    block = yaml.safe_load((pinned / "services" / "gpu-ai" / "prod" / "values.yaml").read_text()).get(key) or {}
    with tempfile.TemporaryDirectory(prefix="radiance-c03-fix-") as tmp:
        vals = Path(tmp) / "vals.yaml"
        with vals.open("w") as fh:
            yaml.safe_dump(block, fh)
        out = subprocess.run(
            ["helm", "template", release, str(chart),
             "-f", str(vals), "--set", "domain=spencerslab.com", "--set", "clusterName=gpu-ai"],
            capture_output=True, text=True, timeout=300,
        )
        if out.returncode != 0:
            raise SystemExit(f"render failed for {release} at the pinned tree:\n{out.stderr}")
    docs = [d for d in yaml.safe_load_all(out.stdout) if d]
    deps = [d for d in docs if d.get("kind") == "Deployment"]
    assert len(deps) == 1, f"{release}: expected one Deployment, got {len(deps)}"
    return deps[0]


def head(commit: str, release: str) -> str:
    return (
        "# C03 delta fixture — the rendered Deployment of one radiance release at the PRE-MOVE\n"
        f"# base commit {commit}, re-derived by capture_c03_fixtures.py from `git archive`\n"
        "# of that commit (never the working tree; the payload guard refuses a write on any\n"
        "# difference, so this file's bytes ARE the pinned render, folded).\n"
        "#\n"
        "# DO NOT EDIT. This is the baseline side of the INTENTIONAL-DELTA proof in\n"
        "# test_c03_generic_shell.py under owner ruling D35: the block-fed render may now\n"
        "# differ on EXACTLY four ruled paths (the pod-template checksum/configMaps\n"
        "# annotation, spec.volumes, the init volumeMounts, the init command) and on\n"
        "# NOTHING ELSE. Pool names are folded to <POOL> here and in the leg (the C01\n"
        "# rename is the one difference C03 may inherit; a retired-pool spelling folds to\n"
        "# <POOL>-1 and fails). Re-validate by running the capture script — never\n"
        "# hand-edit, never re-point the commit, never delete this fixture.\n"
        f"# Release: {release} (the derived Application name).\n"
    )


def main() -> None:
    fixtures = {}
    for key in RELEASES:
        path = EVIDENCE / f"pre-move-render-{key}.yaml"
        if not path.is_file():
            raise SystemExit(f"C03 fixture guard: {path.relative_to(REPO)} is missing — the pre-move "
                             "fixture is historical evidence and was never re-creatable from the live "
                             "tree; restore it from git (git checkout -- <path>) and re-run")
        fixtures[key] = (path, yaml.safe_load(path.read_text()))
    pins = {fix["captured_from_commit"] for _path, fix in fixtures.values()}
    if len(pins) != 1:
        raise SystemExit(f"C03 fixture guard: the two fixtures pin different commits {pins} — the pair "
                         "must share one base revision or the delta budgets are incomparable")
    (pin,) = pins

    with tempfile.TemporaryDirectory(prefix="radiance-c03-pin-") as tmp:
        pinned = Path(tmp)
        export_pin(pin, pinned)
        borrow_dependencies(pinned)
        claim = pinned_claim(pinned)
        for key, release in RELEASES.items():
            folded = json.loads(fold_pool(json.dumps(render(pinned, key, release)), claim))
            _path, fix = fixtures[key]
            if folded != fix["deployment"]:
                raise SystemExit(
                    f"C03 fixture guard: the render at {pin[:9]} for {release} does NOT match the "
                    "committed fixture — refusing to write. Either the fixture was hand-edited, the "
                    "dependency borrow is unsound, or the pin is wrong; the delta baseline may only "
                    "change by a new owner ruling recorded in DECISIONS.md, never by re-capture."
                )
            print(f"guard OK: {release} re-derived at {pin[:9]} matches the committed fixture")

    for key, (path, fix) in fixtures.items():
        doc = {
            "captured_from_commit": fix["captured_from_commit"],
            "captured_at": fix["captured_at"],
            "revalidated_at": date.today().isoformat(),
            "pool_token": "<POOL>",
            "release": fix["release"],
            "deployment": fix["deployment"],
        }
        path.write_text(head(fix["captured_from_commit"], fix["release"]) + yaml.safe_dump(doc, sort_keys=True))
        print(f"wrote {path.relative_to(REPO)} (payload unchanged, header/attestation refreshed)")


if __name__ == "__main__":
    main()
