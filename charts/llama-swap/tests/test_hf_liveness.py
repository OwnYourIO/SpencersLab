# CR6-retained keeper (re-homed from test_autogen_integration.py at CC1):
# live HF re-verification of every -hf/-hfd ref in both cluster renders —
# the roster-liveness machinery (hf_check.py, loader-mirror per §7(F)).
# Decoupled from the retired LLAMA_SWAP_EVIDENCE module gate (C04 friction:
# accidental coupling): it needs helm + network only, never docker/venv.
# This is the ticket's sole surviving evidence gate (CR6 ruling 2026-10-24).

from __future__ import annotations

import os
import sys

import pytest

import llama_swap_testlib as L

pytestmark = pytest.mark.skipif(
    os.environ.get("RUN_HF_CHECK") != "1",
    reason=(
        "evidence gate (deferred): RUN_HF_CHECK=1 re-verifies every wired -hf/-hfd ref "
        "against the live HF API (needs network; HF_TOKEN for gated repos) - chunks/C04.md task 1, CR6-retained"
    ),
)


def test_c04_1_hf_repo_tags_resolve():
    sys.path.insert(0, str(L.TESTS_DIR))
    import hf_check
    problems = hf_check.collect_problems(hf_check.refs_from_renders())
    assert not problems, "HF refs failed to resolve:\n" + "\n".join(problems)
