"""Capture the C03 equivalence fixtures (test-session machinery, not a test).

C03 moves the two existing lanes' DATA out of charts/radiance/values.yaml into
their service roster blocks and decides nothing. Its proof is that the rendered
Deployment does not change: this script stores the pre-move Deployment for both
releases at the revision it runs on, and test_c03_generic_shell.py compares the
post-move render against it.

Pool names are folded to the `<POOL>` token at the CURRENT canonical constant
(charts/amd-gpu/tests/amd_gpu_testlib.py). That is what lets a fixture captured
before the C01 rename bless a render after it: the rename is the one difference
C03 is allowed to inherit, and a claim still spelling the OLD pool folds to
`<POOL>-1`, which no fixture matches — the leg keeps its teeth across the rename.

Re-derive fresh (the review agent's first step), from the repo root:

    export PATH=$HOME/.local/bin:$PATH
    python3 charts/radiance/tests/capture_c03_fixtures.py
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(REPO / "charts" / "amd-gpu" / "tests"))

import amd_gpu_testlib as A  # noqa: E402

EVIDENCE = HERE / "evidence"
SERVICE_VALUES = REPO / "services" / "gpu-ai" / "prod" / "values.yaml"

# release name == the derived Application name; the -f file is exactly what the
# ApplicationSet's per-app merge feeds helm (`index $.Values $appName`).
RELEASES = {
    "radiance": "gpu-ai-radiance",
    "radiance-q27": "gpu-ai-radiance-q27",
}


def fold_pool(text: str) -> str:
    return text.replace(A.R9700_CLAIM, "<POOL>")


def render(key: str, release: str):
    block = yaml.safe_load(SERVICE_VALUES.read_text()).get(key) or {}
    with tempfile.TemporaryDirectory(prefix="radiance-c03-fix-") as tmp:
        vals = Path(tmp) / "vals.yaml"
        with vals.open("w") as fh:
            yaml.safe_dump(block, fh)
        out = subprocess.run(
            ["helm", "template", release, str(REPO / "charts" / "radiance"),
             "-f", str(vals), "--set", "domain=spencerslab.com", "--set", "clusterName=gpu-ai"],
            capture_output=True, text=True, timeout=300,
        )
        if out.returncode != 0:
            raise SystemExit(f"render failed for {release}:\n{out.stderr}")
    docs = [d for d in yaml.safe_load_all(out.stdout) if d]
    deps = [d for d in docs if d.get("kind") == "Deployment"]
    assert len(deps) == 1, f"{release}: expected one Deployment, got {len(deps)}"
    return deps[0]


def head(commit: str, release: str) -> str:
    return (
        "# C03 equivalence fixture — the rendered Deployment of one radiance release,\n"
        f"# captured from the tree at {commit} by capture_c03_fixtures.py.\n"
        "#\n"
        "# DO NOT EDIT. This is the pre-move side of the byte-equivalence proof in\n"
        "# test_c03_generic_shell.py: C03 relocates lane data from the chart into the\n"
        "# service block, so the render may not move. The only permitted difference is\n"
        "# the pool NAME, folded to <POOL> here and in the leg (the C01 rename rides the\n"
        "# same branch); a render that still spells the retired pool folds to <POOL>-1\n"
        "# and fails. Re-derive by running the capture script — never hand-edit.\n"
        f"# Release: {release} (the derived Application name).\n"
    )


def main() -> None:
    commit = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True,
                            cwd=REPO).stdout.strip() or "UNCOMMITTED-TREE"
    EVIDENCE.mkdir(exist_ok=True)
    for key, release in RELEASES.items():
        folded = json.loads(fold_pool(json.dumps(render(key, release))))
        doc = {
            "captured_from_commit": commit,
            "captured_at": date.today().isoformat(),
            "pool_token": "<POOL>",
            "release": release,
            "deployment": folded,
        }
        path = EVIDENCE / f"pre-move-render-{key}.yaml"
        path.write_text(head(commit, release) + yaml.safe_dump(doc, sort_keys=True))
        print(f"wrote {path.relative_to(REPO)}")


if __name__ == "__main__":
    main()
