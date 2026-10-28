# C01 container-image contract — containers/strata/ (chunks/C01.md AC1–AC4;
# plan "Commands": `docker build containers/strata/` is the chunk's live gate,
# the authoritative build is docker-build.yaml on the pushed PR branch).
#
# Plain pytest, no docker daemon required: these check the Dockerfile/README
# SURFACE (pins, digests, copy plan, entrypoint, documented runtime contract).
# Pin FORM = the 2026-10-27 coordination ruling (b) (DECISIONS "coordination
# round"): literal flavor-complete FROM tags, tag→digest pairing recorded in
# the README contract, NO renovate ARG-pin comment — no repo manager extracts
# a datasource=docker ARG pin (live-verified in both engines). The
# `# renovate:` claim model still reads renovate.json LIVE and simulates the
# built-in dockerfile manager's ARG-expansion rewrite rules faithfully to
# renovate's lib/modules/manager/dockerfile/extract.ts — load-bearing for the
# unclaimed-comment tripwire and the supervisor-stage pin.

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
# RESEARCH §1 measured digests — the pin VALUES that survive every ruling.
# Under the 2026-10-27 coordination ruling (b) their recorded home is the
# C01 README contract (in-place-rebuild guard, the unified-vulkan-262 crash-
# loop class; issue #3421 is the documented WHY, contradictions #6/#7).
FLAVOR_PINS = {
    # flavor tag suffix -> (full literal tag, recorded digest)
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


def test_ac2_strata_from_tags_are_literal(dockerfile):
    """Ruling (b) FORM tripwire: both strata FROM refs carry the literal
    flavor-complete tag (optionally @sha256-pinned) — no $-expansion anywhere
    in the ref. The retired ARG+suffix shape and the rejected per-flavor
    whole-tag ARG shape (a) both fail here; a future docker-manager migration
    must reopen this at coord through the test session, not as a silent
    Dockerfile edit. Tag VALUES and the pair stay pinned by
    test_ac2_strata_flavor_from_lines."""
    deps = [d for d in _builtin_dockerfile_deps(dockerfile) if STRATA_DEP in d["expanded"]]
    for d in deps:
        assert "$" not in d["ref"], (
            f"{d['ref']}: $-expansion-pinned strata tag — ruling (b) is literal tags "
            "(DECISIONS coordination round); variable pin shapes are a decision point, not an edit"
        )
        assert _tag_of(d["ref"]) in {
            f"{STRATA_VERSION}-{FLAVOR_PRIMARY}", f"{STRATA_VERSION}-{FLAVOR_STRIX}"
        }, f"{d['ref']}: literal FROM tag diverges from the ruled 0.2.7 flavor pair"


def test_ac2_no_strata_renovate_pin_comment(dockerfile):
    """Ruling (b): the strata pins carry NO renovate comment — none of the
    repo's managers extracts a datasource=docker ARG pin, and the silent
    switch to a github datasource the chunk forbade stays forbidden. Any
    renovate comment naming the strata depName reds here in either drift
    direction: the retired ARG-pin shape re-introduced, or an
    ahead-of-ticket automated-pin migration. Both are coord decisions."""
    offenders = re.findall(
        r"#\s*renovate:[^\n]*depName=" + re.escape(STRATA_DEP), dockerfile)
    assert not offenders, f"renovate comment(s) on the strata depName: {offenders} — ruling (b) retired them"


def test_ac2_readme_records_tag_digest_pairing(readme):
    """The in-place-rebuild guard's home under ruling (b): the README contract
    pairs each literal flavor tag with its RESEARCH §1 digest (#3421 is the
    WHY of recording at all — asserted by test_readme_documents_image_interface).
    Pairing must be legible: same line, or the digest within two lines of a
    line naming the tag."""
    lines = readme.splitlines()
    for flavor, (full_tag, digest) in FLAVOR_PINS.items():
        idxs = [i for i, ln in enumerate(lines) if full_tag in ln]
        assert idxs, f"README never names {full_tag} (ruling (b) records the pin contract here)"
        assert any(digest in "\n".join(lines[max(0, i - 2): i + 3]) for i in idxs), (
            f"{full_tag}: RESEARCH §1 digest {digest[:19]}… not paired with its tag in the README"
        )


def test_ac2_dockerfile_digest_pins_match_the_record(dockerfile):
    """A FROM line MAY pin @sha256 directly (belt over the README-only record)
    — then it must equal the recorded pair. Two surfaces carrying different
    digests is how an in-place rebuild survives re-recording of one of them."""
    recorded = {t: dg for t, dg in FLAVOR_PINS.values()}
    tags = "|".join(re.escape(t) for t in recorded)
    for tag, hex64 in re.findall(
        re.escape(STRATA_DEP) + r":(" + tags + r")@sha256:([0-9a-f]{64})", dockerfile
    ):
        assert recorded[tag] == f"sha256:{hex64}", (
            f"{tag}: FROM pins sha256:{hex64[:16]}… but the record says {recorded[tag][:22]}…"
        )


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
# AC2 — pin FORM + renovate-claim guards (residual 1 closed by the
# 2026-10-27 coordination ruling (b): literal tags, README digest record,
# no renovate ARG-pin comment; bump cadence manual until a future ticket)
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
        f"renovate comments no repo manager extracts: {unclaimed} — under ruling (b) the strata "
        "pins carry no renovate comment; an unclaimable comment is the retired ARG-pin shape or "
        "an unsupported datasource returning (route via coord — do NOT edit renovate.json here)"
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
