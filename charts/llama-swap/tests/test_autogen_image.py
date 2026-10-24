# C01 machinery contract for containers/llama-swap-autogen.
#
# The hard tests here are DETERMINISTIC PARSES of the Dockerfile against the
# repo's own renovate.json custom-manager regex and the plan's locked pins —
# they need no docker, no network, and run in CI wherever this suite runs.
# All are RED until C01 lands (the directory/Dockerfile does not exist).
#
# REPLAN rebase (amendment L, 2026-10-24, CR4): ENTRYPOINT flips from the raw
# console script to the repo-side entrypoint.sh (COPY + exec-form + shebang +
# exec bit); the console script must STAY on PATH (the gated docker checks and
# the chart's stub-based degrade contracts invoke it explicitly).
# Build+run+inspect checks (chunk acceptance 1-3) are gated on a live docker
# daemon + explicit opt-in (LLAMA_SWAP_IMAGE_EVIDENCE=1): the PR's own
# docker-build.yaml job is the CI build proof (chunks/C01.md "Tests" —
# "not required to run in CI"), so a hard test that CI never provisions would
# be faulty validation by construction.

from __future__ import annotations

import json
import os
import re
import subprocess
import uuid
from pathlib import Path

import pytest

import llama_swap_testlib as L

DOCKERFILE = L.REPO_ROOT / "containers" / "llama-swap-autogen" / "Dockerfile"

# ---------------------------------------------------------------------------
# Deterministic Dockerfile contract (hard tests)
# ---------------------------------------------------------------------------


def test_c01_dockerfile_exists():
    assert DOCKERFILE.is_file(), (
        f"{DOCKERFILE} missing — the C01 autogen image is not implemented"
    )


def test_c01_fleet_consistent_base_pin():
    """python:3.12.15-slim-bookworm — the fleet-consistent pin also used by
    the tools sidecar (DECISIONS delivery decision; plan: renovate bumps patch)."""
    text = DOCKERFILE.read_text()
    assert re.search(r"^FROM\s+python:3\.12\.15-slim-bookworm\s*$", text, re.M), (
        f"base pin wrong:\n{text[:400]}"
    )


def test_c01_renovate_gitrefs_pin_matches_repo_custom_manager():
    """Criterion 4: the annotation must be picked up by THIS repo's regex
    manager. We run renovate.json's own matchStrings against the Dockerfile
    so a format drift fails here, not silently in a Renovate PR gap."""
    text = DOCKERFILE.read_text()
    managers = json.loads((L.REPO_ROOT / "renovate.json").read_text())["customManagers"]
    gitrefs = [m for m in managers if "git-refs" in " ".join(m.get("matchStrings", []))]
    assert gitrefs, "renovate.json lost the git-refs manager — C01's premise"

    def to_python_regex(js: str) -> str:
        # Renovate's matchStrings are JS regexes: (?<name>...) -> Python (?P<name>...).
        return re.sub(r"\(\?<(\w+)>", r"(?P<\1>", js)

    applied = False
    for mgr in gitrefs:
        if not any("Dockerfile" in pat for pat in mgr.get("managerFilePatterns", [])):
            continue
        for ms in mgr["matchStrings"]:
            if "git-refs" not in ms:
                continue
            m = re.search(to_python_regex(ms), text)
            if m:
                applied = True
                assert m["datasource"] == "git-refs"
                assert m["depName"] == L.AUTOGEN_REPO
                assert m["currentValue"] == L.AUTOGEN_COMMIT, (
                    f"pin is {m['currentValue']}, plan locked {L.AUTOGEN_COMMIT} (DECISIONS)"
                )
    assert applied, "Dockerfile has no '# renovate: datasource=git-refs …'+ARG pair the " \
                    "repo manager's regex matches (comment must DIRECTLY precede the ARG line)"


def test_c01_immutable_install_from_pinned_commit():
    """pip install must fetch the archive tarball at ${AUTOGEN_COMMIT} — the
    no-git-at-boot, no-floating-ref supply-chain shape (DECISIONS; rejects
    runtime tarball install and vendored-source ConfigMap)."""
    text = DOCKERFILE.read_text()
    assert "ARG AUTOGEN_COMMIT=" + L.AUTOGEN_COMMIT in text or re.search(
        r"ARG\s+AUTOGEN_COMMIT=\{?\"?" + L.AUTOGEN_COMMIT, text
    ), "ARG AUTOGEN_COMMIT does not carry the pinned SHA"
    m = re.search(r"pip install[^\n]*archive/\\?\$\{AUTOGEN_COMMIT\}\.tar\.gz", text)
    assert m, "no pip install of the github archive tarball pinned via ${AUTOGEN_COMMIT}:\n" + text


def test_c01_nonroot_uid_and_path_cli():
    """uid/gid 65532 (container-creation convention — same as wekan-mcp's
    USER 65532); the console script stays on PATH via pip install (amendment
    L: ENTRYPOINT no longer names it — the gated docker checks call it with an
    explicit --entrypoint override)."""
    text = DOCKERFILE.read_text()
    user_lines = re.findall(r"^USER\s+(.+)$", text, re.M)
    assert user_lines, "no USER directive — image would run as root"
    assert any("65532" in u for u in user_lines), f"USER lines: {user_lines}"
    assert re.search(r"pip install[^\n]*llama-swap-config-autogen", text), \
        "console script install line vanished — PATH contract broken"


def test_c04_entrypoint_relocation_contract():
    """CR4: Dockerfile COPYs entrypoint.sh, sets exec-form ENTRYPOINT
    [\"/entrypoint.sh\"]; the repo file exists, is shebang-POSIX, and is
    marked executable (COPY --chmod or explicit chmod/RUN chmod). Red at CA1
    handoff on two counts: the file does not exist and the Dockerfile still
    ENTRYPOINTs the console script."""
    text = DOCKERFILE.read_text()
    assert re.search(r"^ENTRYPOINT\s+\[\s*\"/entrypoint\.sh\"\s*\]", text, re.M), (
        "ENTRYPOINT is not the exec-form [\"/entrypoint.sh\"] (CA4)"
    )
    assert re.search(r"^COPY\s+.*entrypoint\.sh", text, re.M), \
        "entrypoint.sh is not COPY'd into the image (CA4)"
    ep = L.ENTRYPOINT_FILE
    assert ep.is_file(), f"{ep} missing — CA4 has not landed the entrypoint (wiring tests need this file too)"
    first = ep.read_text().splitlines()[0].strip()
    assert first in ("#!/bin/sh", "#!/bin/sh -e", "#!/usr/bin/env sh"), f"bad shebang: {first!r}"
    assert os.access(ep, os.X_OK) or re.search(r"chmod\s+(0?755|a\+x)[^\n]*entrypoint\.sh", text) \
        or re.search(r"COPY\s+--chmod=[^\s]+\s+.*entrypoint\.sh", text), \
        "entrypoint.sh neither executable in-tree nor chmod'd in the Dockerfile"


# ---------------------------------------------------------------------------
# Gated build evidence (chunk acceptance 1-3): docker daemon + opt-in only.
# ---------------------------------------------------------------------------


def _image_evidence_enabled():
    if os.environ.get("LLAMA_SWAP_IMAGE_EVIDENCE") != "1":
        return None, "set LLAMA_SWAP_IMAGE_EVIDENCE=1 with a docker daemon to run the C01 build evidence (PR CI's docker-build.yaml is the build proof)"
    ok, reason = L.docker_ready()
    if not ok:
        return None, f"docker daemon unavailable: {reason}"
    return True, ""


@pytest.fixture(scope="module")
def built_image():
    enabled, reason = _image_evidence_enabled()
    if not enabled:
        pytest.skip(reason)
    tag = f"pytest-llama-swap-autogen:{uuid.uuid4().hex[:8]}"
    build = subprocess.run(["docker", "build", "-t", tag, str(DOCKERFILE.parent)],
                           capture_output=True, text=True, timeout=1800)
    assert build.returncode == 0, f"docker build failed:\n{build.stderr[-3000:]}"
    yield tag
    subprocess.run(["docker", "rmi", "-f", tag], capture_output=True, timeout=120)


@pytest.mark.parametrize("subcmd", ["init --help", "generate --help", "validate --help"])
def test_c01_console_script_on_path_with_importable_deps(built_image, subcmd):
    """Acceptance 2: `docker run --rm --entrypoint llama-swap-config-autogen
    <built> validate --help` exits 0 — proves the console script name AND that
    pydantic/gguf/jsonschema/PyYAML import at startup (chunk task 2:
    subcommands init|generate|validate)."""
    args = ["docker", "run", "--rm", "--entrypoint", "llama-swap-config-autogen",
            built_image] + subcmd.split()
    r = subprocess.run(args, capture_output=True, text=True, timeout=300)
    assert r.returncode == 0, f"{subcmd}: rc={r.returncode}\n{r.stdout}\n{r.stderr}"


def test_c01_runs_as_uid_65532(built_image):
    """Acceptance 3: non-zero uid 65532 baked in."""
    r = subprocess.run(
        ["docker", "run", "--rm", built_image, "sh", "-c", "id -u && id -g"],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0:
        # ENTRYPOINT is the autogen CLI, so a raw sh arg may not exec; fall
        # back to inspecting the image config instead.
        insp = subprocess.run(
            ["docker", "inspect", "--format", "{{.Config.User}}", built_image],
            capture_output=True, text=True, timeout=60,
        )
        assert "65532" in insp.stdout, f"neither runtime id nor Config.User shows 65532: {insp.stdout!r}"
        return
    uid, gid = r.stdout.split()
    assert uid == "65532" and gid == "65532", f"ran as {uid}:{gid}"
