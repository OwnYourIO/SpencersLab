# C01 container-image contract — containers/strata/ (chunks/C01.md AC1–AC4;
# plan "Commands": `docker build containers/strata/` is the chunk's live gate,
# the authoritative build is docker-build.yaml on the pushed PR branch).
#
# Plain pytest, no docker daemon required: these check the Dockerfile/README
# SURFACE (pins, digests, copy plan, entrypoint, documented runtime contract).
# The `# renovate:` parseability checks read renovate.json LIVE and simulate
# the built-in dockerfile manager's ARG-expansion rewrite rules faithfully to
# renovate's lib/modules/manager/dockerfile/extract.ts — so an escalation here
# tracks the real config, not a snapshot of it.

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

CONTAINER_DIR = Path(__file__).resolve().parent.parent      # containers/strata
REPO_ROOT = CONTAINER_DIR.parent.parent
DOCKERFILE = CONTAINER_DIR / "Dockerfile"
README = CONTAINER_DIR / "README.md"

STRATA_DEP = "ghcr.io/niko1221/strata"
LLAMA_SWAP_DEP = "ghcr.io/mostlygeek/llama-swap"
STRATA_VERSION = "0.2.7"
FLAVOR_PRIMARY = "rocm-gfx120x"
FLAVOR_STRIX = "rocm-gfx1151"
# RESEARCH §1 measured digests; recorded-comment requirement is the
# in-place-rebuild guard (the unified-vulkan-262 crash-loop class), with
# issue #3421 as the documented WHY (contradictions #6/#7).
FLAVOR_PINS = {
    # flavor tag suffix -> (expanded full tag, recorded digest)
    FLAVOR_PRIMARY: (f"{STRATA_VERSION}-{FLAVOR_PRIMARY}", "sha256:703efd51c040152e9fceb993688b01ca0374535a5bfd86c14a60b5e60c96407a"),
    FLAVOR_STRIX: (f"{STRATA_VERSION}-{FLAVOR_STRIX}", "sha256:29ecd5cf8b0e21525dbb5c0191d7743d62fa356da646cb6aaf0546e5a31a8b3f"),
}
ENGINE_ROOT = "/opt/strata/components/engine"
SERVE_ENTRY = "/opt/strata/terminal/bin/strata"
LABEL_PRIMARY_SUBSTR = "-hip-rx9070"
LABEL_STRIX_SUBSTR = "-hip-halo"


def _tag_of(expanded_ref: str) -> str:
    """Tag of an expanded image ref, digest stripped (`repo:tag@sha256:…`)."""
    without_digest = expanded_ref.split("@")[0]
    last = without_digest.rsplit("/", 1)[-1]
    return last.rsplit(":", 1)[-1] if ":" in last else ""


@pytest.fixture(scope="module")
def dockerfile() -> str:
    assert DOCKERFILE.is_file(), "containers/strata/Dockerfile missing — C01 not landed"
    return DOCKERFILE.read_text()


@pytest.fixture(scope="module")
def readme() -> str:
    assert README.is_file(), "containers/strata/README.md missing — C01 not landed"
    return README.read_text()


# ---------------------------------------------------------------------------
# Renovate extraction model (renovate.json read live)
# ---------------------------------------------------------------------------


def _to_py(pattern: str) -> str:
    """JS named-group syntax (?<name> → Python (?P<name>; renovate's regex
    managers compile matchStrings with gimu flags."""
    return pattern.replace("(?<", "(?P<")


def _managers_for(path: str) -> list[dict]:
    cfg = json.loads((REPO_ROOT / "renovate.json").read_text())
    out = []
    for m in cfg.get("customManagers", []):
        if m.get("customType") != "regex":
            continue
        for fp in m.get("managerFilePatterns", []):
            pat = fp.strip("/") if fp.startswith("/") and fp.endswith("/") else fp
            try:
                if re.search(_to_py(pat), path):
                    out.append(m)
                    break
            except re.error:
                continue
    return out


def _custom_claims(text: str, path: str) -> list[dict]:
    """(datasource, depName, currentValue) triples captured by the repo's
    applicable custom regex managers."""
    claims = []
    for m in _managers_for(path):
        for ms in m.get("matchStrings", []):
            try:
                rx = re.compile(_to_py(ms), re.M | re.S | re.I | re.U)
            except re.error:
                continue
            for match in rx.finditer(text):
                g = match.groupdict()
                if "datasource" in g or "depName" in g:
                    claims.append({
                        "datasource": g.get("datasource"),
                        "depName": g.get("depName"),
                        "currentValue": g.get("currentValue"),
                        "manager": m.get("description", "")[:40],
                    })
    return claims


_ARG_RE = re.compile(r"^\s*ARG\s+(\w+)(?:\s*=\s*(\S+))?", re.M)


def _builtin_dockerfile_deps(text: str) -> list[dict]:
    """Faithful slice of the built-in dockerfile manager's FROM handling
    (extract.ts): collect ARGs, expand ${VAR}/$VAR in FROM image refs, then
    rewritability per processDepForAutoReplace — the expanded currentValue
    must appear VERBATIM on a covered line (FROM itself, or the ARG line only
    when the whole tag is the variable). A partial-suffix tag like
    `repo:${VAR}-flavor` matches no covered line: the update can never land."""
    args = {m.group(1): m.group(2) or "" for m in _ARG_RE.finditer(text)}
    deps = []
    stage_names = set()
    for m in re.finditer(
        r"^\s*FROM\s+(?:--platform=\S+\s+)*(\S+)(?:\s+[Aa][Ss]\s+(?P<stage>\S+))?", text, re.M
    ):
        ref = m.group(1)
        if m.group("stage"):
            stage_names.add(m.group("stage"))
        if ref.lower() == "scratch" or ref in stage_names:
            continue
        if "$" not in ref:
            deps.append({"ref": ref, "expanded": ref, "writable": True})
            continue
        expanded = ref
        covered = [m.group(0)]
        for var_m in re.finditer(r"\$\{(\w+)(?::-[^}]*)?\}|\$(\w+)", ref):
            name = var_m.group(1) or var_m.group(2)
            if name in args:
                expanded = expanded.replace(var_m.group(0), args[name])
                covered.append(f"ARG {name}={args[name]}")
        tag = _tag_of(expanded)
        # whole-tag-variable form (repo:${VAR}) → the ARG line itself carries
        # the current value and renovate rewrites there (docs' alpine case)
        whole_tag_var = bool(re.fullmatch(r"[^:]+:\$\{\w+\}", ref.split("@")[0]))
        writable = whole_tag_var or bool(tag) and any(tag in c for c in covered)
        deps.append({"ref": ref, "expanded": expanded, "writable": writable})
    return deps


# ---------------------------------------------------------------------------
# AC1/AC2 — FROM lines, pins, digests
# ---------------------------------------------------------------------------


def test_ac2_strata_flavor_from_lines(dockerfile):
    deps = [d for d in _builtin_dockerfile_deps(dockerfile) if STRATA_DEP in d["expanded"]]
    assert len(deps) == 2, (
        f"expected two strata-flavor FROM lines (gfx120x + gfx1151), found {len(deps)}: "
        f"{[d['ref'] for d in deps]}"
    )
    tags = {_tag_of(d["expanded"]) for d in deps}
    want = {f"{STRATA_VERSION}-{FLAVOR_PRIMARY}", f"{STRATA_VERSION}-{FLAVOR_STRIX}"}
    assert tags == want, f"flavor tags {sorted(tags)} != pinned 0.2.7 pair (RESEARCH §1 pin amendment)"


def test_ac2_digests_recorded_next_to_flavor_pins(dockerfile):
    """Anchor on the FLAVOR SUFFIX, not the expanded full tag: under the shape
    C01 task 2 mandates (ARG STRATA_VERSION=0.2.7 + flavor suffix derived in
    the FROM lines) the literal "0.2.7-rocm-gfx120x" never appears on a
    non-comment line. The window around the pin line must carry the digest AND
    name the full tag it belongs to — the pairing is what makes the
    in-place-rebuild guard checkable."""
    lines = dockerfile.splitlines()
    for flavor, (full_tag, digest) in FLAVOR_PINS.items():
        anchor = next((i for i, ln in enumerate(lines)
                       if flavor in ln and not ln.strip().startswith("#")), None)
        assert anchor is not None, f"no non-comment line carries the {flavor} flavor"
        window = "\n".join(lines[max(0, anchor - 5): anchor + 4])
        assert digest in window, (
            f"{flavor}: RESEARCH §1 digest {digest[:19]}… not recorded adjacent to the pin "
            "(in-place-rebuild guard — the #3421 WHY)"
        )
        assert full_tag in window, f"{flavor}: digest recorded without naming {full_tag} beside it"


def test_ac2_strata_pin_comment_is_docker_datasource():
    """AC2, literal: datasource MUST be docker (container tags, not
    github-releases — 0.2.4–0.2.6 are releases with NO images; a github-
    releases pin would propose unshippable versions). A silent switch to a
    github datasource is the failure mode the chunk forbids; if the parseability
    tests below stay red, that is the renovate.json escalation, not a license
    to change the datasource here."""
    text = DOCKERFILE.read_text() if DOCKERFILE.is_file() else ""
    assert re.search(
        r"#\s*renovate:\s*datasource=docker\s+depName=" + re.escape(STRATA_DEP) + r"\b",
        text,
    ), f"no '# renovate: datasource=docker depName={STRATA_DEP}' comment in the Dockerfile"
    wrong = re.findall(r"#\s*renovate:\s*datasource=github-\S+\s+depName=" + re.escape(STRATA_DEP), text)
    assert not wrong, f"strata pin switched to a github datasource: {wrong}"


def test_ac2_all_arg_version_pins_carry_renovate_comments(dockerfile):
    offenders = []
    lines = dockerfile.splitlines()
    for i, ln in enumerate(lines):
        m = re.match(r"\s*ARG\s+(\w*VERSION\w*)=(\S+)", ln)
        if not m:
            continue
        prev = next((j for j in range(i - 1, -1, -1) if lines[j].strip()), None)
        if prev is None or not lines[prev].lstrip().startswith("#") or "renovate:" not in lines[prev]:
            offenders.append(ln.strip())
    assert not offenders, f"ARG *_VERSION lines without a renovate comment directly above: {offenders}"


# ---------------------------------------------------------------------------
# AC2 — manager parseability (the coordinator's residual 1, verified live)
# ---------------------------------------------------------------------------


def test_ac2_every_renovate_comment_is_claimed_by_a_repo_manager(dockerfile):
    claims = _custom_claims(dockerfile, "containers/strata/Dockerfile")
    file_deps = _builtin_dockerfile_deps(dockerfile)
    unclaimed = []
    lines = dockerfile.splitlines()
    for i, ln in enumerate(lines):
        cm = re.match(r"\s*#\s*renovate:(.+)", ln)
        if not cm:
            continue
        body = cm.group(1)
        ds = re.search(r"datasource=(\S+)", body)
        dep = re.search(r"depName=(\S+)", body)
        nxt = next((l for l in lines[i + 1:] if l.strip()), "")
        if ds and dep and any(
            c["datasource"] == ds.group(1) and c["depName"] == dep.group(1) for c in claims
        ):
            continue
        # FROM-annotation form: the built-in dockerfile manager extracts the
        # FROM ref itself (resolved with the WHOLE file's ARG context — an
        # isolated line would self-match its ${VAR} tag and fake writability);
        # the comment is advisory, the pin is tracked.
        if nxt.lstrip().upper().startswith("FROM"):
            ref = next((p for p in nxt.split()[1:] if not p.startswith("--")), "")
            if any(fd["ref"] == ref and fd["writable"] for fd in file_deps):
                continue
        unclaimed.append((ln.strip(), nxt.strip()[:60]))
    assert not unclaimed, (
        f"renovate comments no repo manager extracts: {unclaimed} — cross-check "
        "renovate.json customManagers datasource sets"
    )


def test_ac2_strata_docker_pin_is_tracked_by_a_repo_manager(dockerfile):
    """The escalation probe. The repo's ARG-pin custom managers narrow
    `datasource` captures to github-tags|github-releases|git-refs (Dockerfile
    git-pin) and node-version|golang-version|forgejo-releases|npm (containers
    tool-pin) — NEITHER accepts docker. The built-in dockerfile manager
    extracts the expanded FROM ref but can only rewrite a line containing the
    expanded currentValue verbatim: whole-tag variables (repo:${VAR}) work,
    partial-suffix tags (repo:${VAR}-flavor) never land. So the C01-mandated
    shape is tracked ONLY if renovate.json gains docker on one of those two
    managers, or the Dockerfile ships one of the tracked alternative shapes
    (per-flavor full-tag ARGs consumed as whole tags, or literal FROM tags).
    This test is the tripwire for the coordinator's decision — do NOT weaken
    it, and do NOT silently switch the strata pin to a github datasource."""
    claims = _custom_claims(dockerfile, "containers/strata/Dockerfile")
    custom_tracked = any(
        c["datasource"] == "docker" and c["depName"] == STRATA_DEP for c in claims
    )
    deps = [d for d in _builtin_dockerfile_deps(dockerfile) if STRATA_DEP in d["expanded"]]
    builtin_tracked = bool(deps) and all(d["writable"] for d in deps)
    assert custom_tracked or builtin_tracked, (
        f"{STRATA_DEP} docker-ARG pin extracted by NO repo manager: custom ARG-pin managers "
        "exclude datasource=docker and the built-in dockerfile manager cannot rewrite a "
        "partial-suffix variable tag. Coord decision needed (extend renovate.json datasource "
        "set vs restructure the pin per this test's docstring) — reported in the cf-77 test "
        "session RESULT open_questions."
    )


def test_ac2_llama_swap_supervisor_stage_pinned(dockerfile):
    deps = [d for d in _builtin_dockerfile_deps(dockerfile) if LLAMA_SWAP_DEP in d["expanded"]]
    assert deps, f"no FROM stage references {LLAMA_SWAP_DEP} (C01 task 1: COPY the llama-swap binary from it)"
    tag = _tag_of(deps[0]["expanded"])
    assert re.fullmatch(r"unified-vulkan-\d+", tag), (
        f"supervisor tag {tag!r}: pin the golden release-versioned family the existing chart "
        "rides (unified-vulkan-266), kept honest by the renovate.json versioning packageRule"
    )
    assert LLAMA_SWAP_DIGEST in dockerfile, "recorded unified-vulkan-266 digest (RESEARCH §3 re-verified) missing"
    assert deps[0]["writable"], "literal FROM tag required so the built-in manager can rewrite the stage"


LLAMA_SWAP_DIGEST = "sha256:0cc42f1024b54be3de100ae7a7a2730047ca5c27cf7a354f8a9f63142f00c045"


# ---------------------------------------------------------------------------
# AC3 — copy plan, entrypoint, build-time capture
# ---------------------------------------------------------------------------


def test_copy_plan_keeps_both_engine_roots_distinct(dockerfile):
    assert LABEL_PRIMARY_SUBSTR in dockerfile and LABEL_STRIX_SUBSTR in dockerfile, (
        "both flavor labels (rx9070 + halo) must appear in the copy plan — bundling "
        "keeps them as DISTINCT dirs under engine/ (C01 task 1)"
    )
    for m in re.finditer(r"^\s*COPY\s+(?:--from=\S+\s+)?(\S+)\s+(\S+)\s*$", dockerfile, re.M):
        src, dst = m.group(1), m.group(2)
        if LABEL_PRIMARY_SUBSTR in dst and LABEL_STRIX_SUBSTR in src:
            pytest.fail(f"COPY {src} -> {dst}: strix engine over the primary label dir")
        if LABEL_STRIX_SUBSTR in dst and LABEL_PRIMARY_SUBSTR in src:
            pytest.fail(f"COPY {src} -> {dst}: primary engine over the strix label dir")


def test_entrypoint_is_llama_swap_not_upstream_run(dockerfile):
    eps = re.findall(r"^\s*ENTRYPOINT\s+(.*)$", dockerfile, re.M)
    assert eps, "no ENTRYPOINT (upstream's tini+entrypoint.sh 'run' must NOT survive — C01 publishes llama-swap)"
    ep = eps[-1]
    assert not re.search(r"entrypoint\.sh|tini|\brun\b", ep), f"ENTRYPOINT carries the upstream launch path: {ep}"
    try:
        argv = json.loads(ep)
        first = str(argv[0])
    except json.JSONDecodeError:
        import shlex
        first = shlex.split(ep)[0]
    assert Path(first).name == "llama-swap", f"ENTRYPOINT argv[0]: {first!r}"


def test_terminal_binary_copied_once_and_executed_by_verify_step(dockerfile):
    assert re.search(r"/opt/strata/terminal\b", dockerfile), "terminal tree not copied from the upstream image"
    assert re.search(r"test\s+-x\s+\S*strata", dockerfile) or re.search(r"\[\s*-x\s+\S*strata\s*\]", dockerfile), (
        "C01 task 3: the build must test -x the serve entry — a broken interface should fail the build, not the pod"
    )
    assert re.search(r"(ls|find)\s+\S*components/engine", dockerfile), (
        "engine dir must be listed / binary name printed at build (the capture feeding the README exe contract)"
    )


# ---------------------------------------------------------------------------
# README interface contract + documented runtime posture
# ---------------------------------------------------------------------------


def test_readme_exe_contract_paths_shape(readme):
    """The C02/C05 seam: the README must document one full exe path per flavor
    under the matching label dir. The BINARY FILENAME is whatever the build-log
    capture found (source-build configs name it `strata`) — never invented, so
    only the FORM and label pairing are pinned here."""
    paths = set()
    for m in re.finditer(
        re.escape(ENGINE_ROOT) + r"/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)", readme
    ):
        label = m.group(1)
        if re.fullmatch(r"\d+\.\d+\.\d+-linux-x86_64-hip-(rx9070|halo)", label):
            paths.add((label, m.group(2)))
    labels = {p[0] for p in paths}
    assert any("rx9070" in l for l in labels) and any("halo" in l for l in labels), (
        f"README documents no rx9070+halo exe pair under {ENGINE_ROOT}/<label>/<binary>: {sorted(paths)}"
    )


def test_readme_documents_image_interface(readme):
    required = {
        "serve entry": SERVE_ENTRY,
        "config path injected by the chart": "/app/config/config.yaml",
        "update hazard (engine lives in the image)": "strata update",
        "CI immutable tag": ":v",
        "CI rolling tag": ":main",
        "CI workflow": "docker-build",
        "#3421 digest WHY": "#3421",
    }
    missing = [name for name, tok in required.items() if tok not in readme]
    assert not missing, f"README contract lines missing: {missing}"


def test_readme_documents_runtime_contract_split(readme):
    """DOCKER.md runtime requirements are the CHART's job (C02 consumes this
    section); `ulimit -n 524288` is the CMD wrapper's job (RESEARCH §2: no
    release self-raises, PR #2399 open). The split must stay documented or the
    chart dev will silently drop one side."""
    required = {
        "memlock": "memlock",
        "shm": "shm",
        "stop timeout 120": "120",
        "kfd device": "/dev/kfd",
        "dri device": "/dev/dri",
        "render group": "render",
        "video group": "video",
        "nofile wrapper": "524288",
        "no memory limit": "memory limit",
    }
    missing = [name for name, tok in required.items() if tok.lower() not in readme.lower()]
    assert not missing, f"runtime-contract facts missing from README: {missing}"
    assert re.search(r"root", readme, re.I), "root-user deviation must be documented (DECISIONS)"


def test_readme_records_2b_escalation_facts(readme, dockerfile):
    """RESEARCH §6: the guide-2B source path stays documented as the
    escalation — a future operator needs the tarball/no-sha and no-1201-table
    facts without re-deriving them."""
    blob = readme + dockerfile
    for tok in ("TheRock", "tune_hipblaslt", "100401"):
        assert tok in blob, f"2B escalation fact {tok!r} missing"


# ---------------------------------------------------------------------------
# AC4 — nothing forbidden in the image
# ---------------------------------------------------------------------------


def test_ac4_no_weights_packs_or_secrets_baked(dockerfile):
    forbidden = re.compile(r"\.(gguf|safetensors)\b|Strata-data|/models\b|packs/iq3|type=secret|API_KEY=", re.I)
    offenders = [ln.strip() for ln in dockerfile.splitlines() if forbidden.search(ln) and not ln.strip().startswith("#")]
    assert not offenders, f"AC4 violation (weights/packs/secrets in the build): {offenders}"


def test_ac4_base_images_are_tag_pinned(dockerfile):
    for d in _builtin_dockerfile_deps(dockerfile):
        if d["ref"].lower() == "scratch":
            continue
        tag = _tag_of(d["expanded"])
        assert tag and tag != "latest", f"unpinned/latest FROM ref: {d['ref']}"
