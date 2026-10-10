# Integrity test for the vendored llama.cpp b11515 converter subset.
#
# scripts/converter-source.json pins the upstream tag/commit and the sha256 of
# every vendored file. This test re-hashes the files that actually ship in the
# chart and fails if they drift from the recorded provenance (e.g. after a
# partial re-vendor). Stdlib-only — runs everywhere the suite runs.

from __future__ import annotations

import hashlib
import json
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent.parent / "scripts"


def test_provenance_file_exists_and_parses():
    meta = json.loads((SCRIPTS_DIR / "converter-source.json").read_text())
    assert meta["repository"] == "https://github.com/ggml-org/llama.cpp"
    assert meta["tag"] == "b11515"
    assert meta["files"], "provenance must list the vendored files"


def test_every_vendored_file_matches_recorded_sha256():
    meta = json.loads((SCRIPTS_DIR / "converter-source.json").read_text())
    mismatches = []
    for rel, info in meta["files"].items():
        path = SCRIPTS_DIR / rel
        if not path.exists():
            mismatches.append(f"{rel}: missing")
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != info["sha256"]:
            mismatches.append(f"{rel}: {digest} != {info['sha256']}")
    assert not mismatches, "vendored files drifted from b11515 provenance:\n" + "\n".join(mismatches)


def test_configmap_embeds_only_cli_and_provenance_pin():
    """The tools ConfigMap must embed ONLY llama_tools.py and
    converter-source.json. The vendored converter closure is ~870 KiB;
    embedding it breaks the 256 KiB last-applied-configuration annotation
    that client-side apply writes (ArgoCD sync failed with
    "metadata.annotations: Too long"). `prepare` fetches the pinned files
    at runtime instead, so re-embedding them is a regression."""
    meta = json.loads((SCRIPTS_DIR / "converter-source.json").read_text())
    cm = (SCRIPTS_DIR.parent / "templates" / "configmap-tools.yaml").read_text()
    assert 'scripts/llama_tools.py' in cm
    assert 'scripts/converter-source.json' in cm
    for rel in meta["files"]:
        # neither the chart-relative path nor any flattened form may be embedded
        assert f'"{rel}"' not in cm, f"{rel} must not be embedded in the ConfigMap"
        assert f"scripts/{rel}" not in cm, f"{rel} must not be embedded in the ConfigMap"
    for marker in ("conversion__", "gguf_py__"):
        assert marker not in cm, f"flattened vendored key ({marker}*) re-appeared in the ConfigMap"
