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
# C09 (U10.2/U11) re-pin: v0.2.9 (app 0.2.9 + engine packages 0.1.55) rode
# the vendored-constants carry rebuild (chunks/C09.md a). cf-141 C04 re-pin
# (TEST_SPEC §9.28/§9.30 by-name move, executed at the C04 test round):
# STRATA_VERSION/ENGINE_VERSION/STALE_* now state the TARGET pair
# (0.2.13 / 0.1.59), so every tag/digest/label/stale arm below reads the
# bumped contract and reddens naming C04 until the Dockerfile/README land.
# The digest slot is deliberately NOT a constant: ledger digests are live
# re-reads the landing round owes (anonymous token + manifest HEAD — the
# README's recorded method), so the arms pin FRESHNESS STRUCTURE instead:
# 64-hex, paired, not a retired value (the copied-not-re-read class).
STRATA_VERSION = "0.2.13"
FLAVOR_PRIMARY = "rocm-gfx120x"
FLAVOR_STRIX = "rocm-gfx1151"
# The [C2]-era 0.2.9 pair — retired by the bump, kept as the guard every
# pairing arm checks a "new" digest against.
RETIRED_FLAVOR_PINS = {
    "0.2.9-rocm-gfx120x": "sha256:a0536d4b9e734a1d06b9b630362b95d01108382a4a39785e6abdc1dfe8326c39",
    "0.2.9-rocm-gfx1151": "sha256:2ac97575713efaa37299d914c628d3f1d40b68b893dd78430f7ea4bd18c5084a",
}
FLAVOR_PINS = {
    # flavor tag suffix -> (full literal tag, live-re-read obligation)
    FLAVOR_PRIMARY: (f"{STRATA_VERSION}-{FLAVOR_PRIMARY}", "live re-read day-of-ready"),
    FLAVOR_STRIX: (f"{STRATA_VERSION}-{FLAVOR_STRIX}", "live re-read day-of-ready"),
}
# C09 re-pin: engine package labels baked via COPY --from + verify test -x
# (0.1.54 retired with the v0.2.8 era), and the source-checkout clone tag the
# setup.sh provisioning runs against — the strata-src stage also applies
# carry/ornith-q36.patch (the two-hunk constants carry, re-cut at v0.2.13 per
# RESEARCH Round 3; its byte laws live in test_strata_c09_ornith_carry.py).
ENGINE_VERSION = "0.1.59"
STALE_STRATA_TAGS = ("0.2.4", "0.2.5", "0.2.6", "0.2.7", "0.2.8", "0.2.9")
STALE_ENGINE_VERSION = "0.1.55"
ENGINE_ROOT = "/opt/strata/components/engine"
SERVE_ENTRY = "/opt/strata/terminal/bin/strata"
FETCH_ENTRY = "/opt/strata/bin/fetch_models.sh"
BIN_DIR = "/opt/strata/bin"
LABEL_PRIMARY_SUBSTR = "-hip-rx9070"
LABEL_STRIX_SUBSTR = "-hip-halo"
# Executable (non-comment) lines only: comments carry the bump history that
# NAMES the old pins ("0.2.7 -> 0.2.8"), and pinning history-free comments
# would forbid the WHY. Same scoping law as the driver's shell-client ban.


def _exec_lines(text: str) -> list[str]:
    return [ln.strip() for ln in text.splitlines() if ln.strip() and not ln.strip().startswith("#")]



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
    assert tags == want, f"flavor tags {sorted(tags)} != pinned {STRATA_VERSION} pair (C07 re-pin over RESEARCH §1's amendment)"


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
        }, f"{d['ref']}: literal FROM tag diverges from the ruled {STRATA_VERSION} flavor pair"


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


def _readme_tag_digests(readme: str) -> dict[str, set]:
    """Parse the ledger: tag -> the 64-hex digest(s) recorded on its row or
    within two lines (the pairing legibility law). Shared by the pairing arms
    so the README is read as ONE source, never re-derived per arm."""
    lines = readme.splitlines()
    out: dict[str, set] = {}
    for flavor, (full_tag, _obligation) in FLAVOR_PINS.items():
        found: set = set()
        for i, ln in enumerate(lines):
            if full_tag in ln:
                found |= set(re.findall(r"sha256:[0-9a-f]{64}",
                                        "\n".join(lines[max(0, i - 2): i + 3])))
        out[full_tag] = found
    return out


def test_ac2_readme_records_tag_digest_pairing(readme):
    """The in-place-rebuild guard's home under ruling (b): the README contract
    pairs each literal flavor tag with a digest (#3421 is the WHY of recording
    at all — asserted by test_readme_documents_image_interface). Pairing must
    be legible: same line, or the digest within two lines of a line naming the
    tag. cf-141 C04 made the VALUES live re-reads (the constant keeps the
    obligation, not a remembered digest), so the pairing law is shape: a
    FRESH 64-hex digest — a retired-pair value under a bumped tag is the
    copied-not-re-read class the guard exists to catch."""
    pairing = _readme_tag_digests(readme)
    retired = set(RETIRED_FLAVOR_PINS.values())
    for full_tag, digests in pairing.items():
        assert full_tag in readme, f"README never names {full_tag} (ruling (b) records the pin contract here)"
        assert digests, f"{full_tag}: no 64-hex digest paired with its tag in the README"
        assert not digests <= retired, (
            f"{full_tag}: paired only with retired-pair digests {sorted(digests)[:1]} — "
            "a bump ledger re-reads live (anonymous token + manifest HEAD), it does not copy"
        )


def test_ac2_dockerfile_digest_pins_match_the_record(dockerfile, readme):
    """A FROM line MAY pin @sha256 directly (belt over the README-only record)
    — then it must equal the README's recorded pair. Two surfaces carrying
    different digests is how an in-place rebuild survives re-recording of one
    of them. Since cf-141 C04 the value is no longer a constant either side:
    the cross-check is README-ledger vs FROM-line directly (one fact, two
    surfaces — the comparison must not depend on a third remembered copy)."""
    pairing = _readme_tag_digests(readme)
    tags = "|".join(re.escape(t) for t in pairing)
    for tag, hex64 in re.findall(
        re.escape(STRATA_DEP) + r":(" + tags + r")@sha256:([0-9a-f]{64})", dockerfile
    ):
        assert f"sha256:{hex64}" in pairing[tag], (
            f"{tag}: FROM pins sha256:{hex64[:16]}… but the README ledger records "
            f"{sorted(pairing[tag])[:2]} — two surfaces, two truths"
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


# ---------------------------------------------------------------------------
# C07 (revision round 2, U9.4) — the v0.2.8 re-pin + the baked fetch files.
# Designed red until the re-pin + files land; each red names the surface that
# has not moved yet. The build itself stays CI-authoritative (docker-build.yaml
# on the pushed branch) — this suite checks the SURFACE, the honest posture the
# plan's Commands record.
# ---------------------------------------------------------------------------


def test_c07_re_pin_moves_every_strata_flavor_ref_to_the_pinned_pair(dockerfile):
    """Count-pin, honest for both waves: exactly one executable FROM line per
    flavor of the pinned pair, and no stale tag from the retired set anywhere in
    an executable line (a half-bumped build ships one flavor of each release —
    the two-stage image would carry two different apps)."""
    deps = [d for d in _builtin_dockerfile_deps(dockerfile) if STRATA_DEP in d["expanded"]]
    tags = [_tag_of(d["expanded"]) for d in deps]
    want = [t for t, _ in FLAVOR_PINS.values()]
    assert sorted(tags) == sorted(want), f"strata FROM tags {sorted(tags)} != the pinned {sorted(want)}"
    for d in deps:
        assert deps.count(d) == 1, f"duplicate FROM for {d['expanded']}"
    stale = [ln for ln in _exec_lines(dockerfile) if any(f":{t}" in ln for t in STALE_STRATA_TAGS)]
    assert not stale, f"stale strata tag in executable lines: {stale}"


def test_c07_source_checkout_clone_tracks_the_flavor_tag(dockerfile, readme):
    """The provisioning checkout (/opt/strata/src/Strata — the setup.py the init
    calls) clones at the SAME release as the packaged flavor tags; the README
    clone row is the human-facing twin. One release fact, three homes."""
    clone = re.findall(r"git clone[^\n&;]*--branch\s+(\S+)", dockerfile)
    assert clone == [f"v{STRATA_VERSION}"], (
        f"checkout clone tags {clone} — must be v{STRATA_VERSION}, matching the flavor FROM tags"
    )
    rows = [ln for ln in readme.splitlines() if "src/Strata" in ln]
    assert rows and all(f"v{STRATA_VERSION}" in r for r in rows), (
        f"README source-checkout row(s) {rows} not at v{STRATA_VERSION}"
    )


def test_c07_engine_package_labels_are_one_fact_across_four_surfaces(dockerfile, readme):
    """The engine package label (0.1.55-linux-x86_64-hip-{rx9070,halo}) must be
    the SAME literal on all four surfaces that name a packaged root: the
    Dockerfile (COPY --from + verify test -x), the containers README exe
    ledger, the chart's strix profile (values.yaml engine exe + lib_dirs —
    the only packaged root the CHART code names; the primary rides the
    claim-compiled version-free path), and the chart README engine-exe table
    (added by the §9.21 FINAL3 §2 widening — that table drifting a stale label
    was the drift root cause: operators read the chart README as truth). A
    pinned packaged root that drifts from the image's actual dirs is a profile
    pointing at a nonexistent path — a runtime strata error, not a build
    failure. Version-free arms (test_readme_exe_contract_paths_shape) stay
    green through both waves; this one is the re-pin's pin-set arm.
    (Renamed from ..._three_surfaces; the era-2 PROVENANCE prose still names
    the old arm name — correct for its era, era-3's PROVENANCE carries the
    new one.)"""
    surfaces = {
        "Dockerfile": dockerfile,
        "README": readme,
        "values.yaml": (REPO_ROOT / "charts" / "llama-swap" / "values.yaml").read_text(),
        "chart README": (REPO_ROOT / "charts" / "llama-swap" / "README.md").read_text(),
    }

    def labels(text: str) -> set[str]:
        return {m.group(0) for m in re.finditer(r"\d+\.\d+\.\d+-linux-x86_64-hip-\w+", text)}

    pair = {f"{ENGINE_VERSION}-linux-x86_64-hip-rx9070", f"{ENGINE_VERSION}-linux-x86_64-hip-halo"}
    chart_labels = set()
    for name, text in surfaces.items():
        found = labels(text)
        want = {f"{ENGINE_VERSION}-linux-x86_64-hip-halo"} if name == "values.yaml" else pair
        assert want <= found, f"{name} engine labels {sorted(found)} lack {sorted(want)}"
        assert found <= pair, f"{name} carries an engine label outside the pinned {ENGINE_VERSION} pair: {sorted(found - pair)}"
        stale = [ln for ln in _exec_lines(text) if STALE_ENGINE_VERSION in ln]
        assert not stale, f"{name} still pins {STALE_ENGINE_VERSION} in executable lines: {stale[:3]}"
        if name == "values.yaml":
            chart_labels = found
    assert chart_labels == {f"{ENGINE_VERSION}-linux-x86_64-hip-halo"}, (
        f"the chart names {sorted(chart_labels)} — only the halo root is chart-referenced, "
        "and it must be byte-identical to the image's strix label"
    )


def test_c07_build_copies_the_fetch_files_into_the_bin_dir(dockerfile):
    """The lift's build side: the three build-context files land under
    /opt/strata/bin and the driver is executable there (COPY --chmod or a chmod
    — either form; mode-644 + exec-form command = 'exec format error' at
    container start, which would make the boot guard loud but useless)."""
    copies = re.findall(r"^\s*COPY\s+(?:--from=\S+\s+)?(\S+)\s+(\S+)\s*$", dockerfile, re.M)
    landed = [(s, d) for s, d in copies if BIN_DIR in d]
    assert landed, f"no COPY lands anything in {BIN_DIR} — files/ not baked (C07 task 2)"
    chmod_ok = re.search(r"--chmod=\d*7\d\d", dockerfile) or re.search(r"chmod\s+([+x]|\d*7\d\d)\s+\S*fetch_models\.sh", dockerfile)
    assert chmod_ok, "fetch_models.sh is not made executable in the image"
    for f in ("fetch_models.sh", "hf_fetch.py", "byte_pins.env"):
        assert re.search(rf"(COPY[^\n]*{f}|files/{f})", dockerfile), f"{f} not copied/declared in the build"


def test_c07_verify_step_covers_the_baked_fetch_files(dockerfile):
    """Build-verify extension in the chunk's shape (same RUN after the existing
    test -f setup.sh && test -x strata checks): sh -n on the driver, py_compile
    on the downloader, test -x/-f on the three baked paths. A broken fetch
    script fails the BUILD, not the 85 GB download attempt hours later."""
    verify = re.search(r"^RUN(.*)$", dockerfile, re.M | re.S)
    blob = "\n".join(m.group(1) for m in re.finditer(r"^RUN(.*)$", dockerfile, re.M | re.S))
    assert verify, "no RUN verify step"
    assert re.search(r"sh\s+-n\s+\S*fetch_models\.sh", blob), "sh -n missing over fetch_models.sh"
    assert re.search(r"python\d?(\.\w+)*\s+-m\s+py_compile\s+\S*hf_fetch\.py", blob), "py_compile missing over hf_fetch.py"
    for f, kind in (("fetch_models.sh", "x"), ("hf_fetch.py", "f"), ("byte_pins.env", "f")):
        assert re.search(rf"test\s+-{kind}\s+\S*{f}", blob), f"test -{kind} missing for {f}"
    assert re.search(r"test\s+-f\s+\S*setup\.sh", blob), (
        "the C01 setup.sh verify (the reason the image carries the checkout) must survive the re-pin"
    )


def test_c07_build_never_executes_the_fetch_driver(dockerfile):
    """Verify by syntax + interface, never by running: executing the entrypoint
    at build time would start a ~183 GB download inside CI (the build context
    has no /models claim, no HF_TOKEN, and CI storage physics that DECISIONS
    already ruled out for pre-baked packs). cf-141 C05 scoping (chunk Task
    3): the blob excludes the runtime apt RUN step — this leg's subject is
    the weight-fetch machinery (fetch_models.sh invocations, huggingface.co
    URLs); the apt step's build-time mirror host is pinned by the test_c05_*
    shape legs instead, and a future mirror-text edit must not redden a leg
    that never spoke about apt. The executed-driver scan still spans every
    other step."""
    steps = _dockerfile_steps(dockerfile)
    non_apt = [s for s in steps if "RUN" not in s[:4] or "apt-get" not in s or "apk" in s]
    blob = "\n".join(s for s in non_apt if s.startswith("RUN"))
    executed = [ln for ln in _exec_lines(blob) if re.search(r"^\s*/opt/strata/bin/fetch_models\.sh|(?<!\w)hf_fetch\.py\s+(anon|gated)", ln)]
    assert not executed, f"build executes the fetch driver: {executed}"
    assert not re.search(r"huggingface\.co|resolve/main", blob), (
        "a fetch URL inside a RUN — downloads belong in the pod, never the build"
    )


def test_c07_readme_ledger_homes_the_moved_pins(readme):
    """The README ledger follows the re-pin honestly: the interface rows carrying
    version-specific facts (flavor tag→digest pair, engine exe labels, source-
    checkout tag) must show the moved values, and the fetch entry joins the
    interface freeze — the chart now binds to /opt/strata/bin/fetch_models.sh,
    so the image contract table is where an operator reads it (three-homes
    pairing with the Dockerfile pin the thin init's boot guard checks).
    cf-141 C04: the digest VALUES are the landing round's live re-reads, so
    the loop pins the FRESH-PAIR shape (non-retired 64-hex, dated re-read
    record, com.strata.engine 0.1.59 proof) plus the folded Q14 doc-truth
    spots (alpine 3.24, 110Gi) — everything the pre-bump constants no longer
    state. This is the moved arm of §9.28's inventory; the cf141_* siblings
    that duplicated it were retired into here (§9.30)."""
    pairing = _readme_tag_digests(readme)
    retired = set(RETIRED_FLAVOR_PINS.values())
    for tag, digests in pairing.items():
        assert tag in readme, f"README never names the moved flavor tag {tag}"
        assert digests, f"README never pairs a 64-hex digest with {tag}"
        assert not digests <= retired, f"{tag}: ledger digests are the retired 0.2.9 pair — copied, not re-read"
    if not re.search(r"com\.strata\.engine[^\n]{0,300}" + re.escape(ENGINE_VERSION)
                     + r"|" + re.escape(ENGINE_VERSION) + r"[^\n]{0,300}com\.strata\.engine",
                     readme, re.S):
        raise AssertionError(f"the ledger records no com.strata.engine {ENGINE_VERSION} label proof")
    if not re.search(r"(anonymous token|manifest HEAD|re-read)[^\n]{0,200}\d{4}-\d{2}-\d{2}"
                     r"|\d{4}-\d{2}-\d{2}[^\n]{0,200}(re-read|anonymous token|manifest HEAD)",
                     readme):
        raise AssertionError("no dated live re-read record for the bumped pair (the landing day's obligation)")
    assert FETCH_ENTRY in readme, f"README interface table lacks {FETCH_ENTRY}"
    assert "alpine:3.22" not in readme, "stale builder-base claim survives (Q14 fold, R2-E7)"
    assert "alpine:3.24" in readme, "the builder-base row must state the Dockerfile's 3.24 truth"
    assert "72Gi" not in readme, "the stale 'caps the container at 72Gi' claim survives (Q14 fold, R2-E7)"
    assert "110Gi" in readme, "the cgroup sentence must state the shipped 110Gi"
    stale_rows = [ln for ln in readme.splitlines() if STALE_ENGINE_VERSION in ln or "v0.2.7" in ln]
    assert not stale_rows, f"README rows still carry retired pins: {stale_rows}"


# ---------------------------------------------------------------------------
# cf-141 C04 — non-vacuity probes for the re-pinned constants above.
# The §9.28 landing-round move is DONE here: STRATA_VERSION/ENGINE_VERSION/
# STALE_* flipped and the digest slot converted to a live-re-read obligation,
# so the pre-existing arms (flavor pair, clone↔README pairing, four-surface
# label law, README ledger) ARE the bump-era contract — the earlier cf141_*
# twin arms and the local BUMP_* duplicate constants were retired into them
# (§9.30), keeping one generation of each law. These probes exercise the same
# parsers/shape the arms use, on synthetic states, so a half-moved mutant can
# never slip through the constant flip.
# ---------------------------------------------------------------------------


def _bump_flavor_pair(dockerfile: str) -> list[str]:
    """The FROM pair through the SAME parser test_ac2 uses (also the
    half-bump probe's eye)."""
    deps = [d for d in _builtin_dockerfile_deps(dockerfile) if STRATA_DEP in d["expanded"]]
    return sorted({str(_tag_of(d["expanded"])) for d in deps})


def test_cf141_c04_bump_era_probes_redden_the_owning_laws():
    """C04 non-vacuity (offline, pure): the half-moved FROM pair must not read
    as the flipped pair; a 0.2.13 row paired with a RETIRED digest must trip
    the freshness condition the pairing arms check; a synthetic fresh ledger
    must satisfy it."""
    want_pair = sorted(t for t, _ in FLAVOR_PINS.values())
    half = ("FROM ghcr.io/niko1221/strata:0.2.13-rocm-gfx120x AS a\n"
            "FROM ghcr.io/niko1221/strata:0.2.9-rocm-gfx1151 AS b\n")
    assert _bump_flavor_pair(half) != want_pair, "half-bump must never read as the pinned pair"
    retired = set(RETIRED_FLAVOR_PINS.values())
    copied = (f"| `ghcr.io/niko1221/strata:{want_pair[0]}` | "
              "sha256:a0536d4b9e734a1d06b9b630362b95d01108382a4a39785e6abdc1dfe8326c39 "
              "(re-read 2026-11-20; com.strata.engine label 0.1.59-linux-x86_64-hip-rx9070) |")
    pairing = _readme_tag_digests(copied)
    assert pairing[want_pair[0]] and pairing[want_pair[0]] <= retired, (
        "the copied-not-re-read mutant must be caught by the pairing arms' retired-guard condition"
    )
    fresh = (
        f"| `ghcr.io/niko1221/strata:{want_pair[0]}` | sha256:"
        "2222222222222222222222222222222222222222222222222222222222222222 "
        "(re-read 2026-11-20, anonymous token + manifest HEAD; com.strata.engine label "
        "0.1.59-linux-x86_64-hip-rx9070) |\n"
        f"| `ghcr.io/niko1221/strata:{want_pair[1]}` | sha256:"
        "3333333333333333333333333333333333333333333333333333333333333333 "
        "(same read; com.strata.engine label 0.1.59-linux-x86_64-hip-halo) |\n"
    )
    fresh_pairing = _readme_tag_digests(fresh)
    assert all(digs and not digs <= retired for digs in fresh_pairing.values()), \
        "the synthetic fresh ledger must satisfy the pairing law"



# ---------------------------------------------------------------------------
# cf-141 C05 — CI-resilient apt step: official-first, kernel.org fallback
# (owner directive 2026-11-11, coord shape ruling in DECISIONS). Red-first
# contract authored before the dev round: the guard legs are DESIGNED RED
# against the landed apt step; the prohibition/ordering/consistency legs are
# GREEN tripwires that redden on the wrong shapes the chunk's probe list
# names. All laws are structural regex over the Dockerfile text — the live
# mirror/base-shape probes (Task 2) are the dev round's evidence, never a
# test. No engine/version/label/marker/ledger literal moves here: the C04
# landed arms above are the preservation run.
# ---------------------------------------------------------------------------

C05_MIRROR_HOST = "mirrors.edge.kernel.org"
C05_OFFICIAL_HOSTS = ("archive.ubuntu.com", "security.ubuntu.com")
C05_SOURCES_FILE = "/etc/apt/sources.list.d/ubuntu.sources"
# The landed (pre-C05) logical step sequence, one rewrite-in-place away: the
# fallback must occupy the ONE runtime apt RUN step, never add or reorder
# (Dockerfile layer-cache + step-order laws; C04-era COPY/marker lines pinned
# by their own arms above).
C05_BASELINE_STEPS = [
    "FROM", "FROM", "FROM", "FROM", "COPY", "RUN", "FROM", "RUN",
    "COPY", "COPY", "COPY", "COPY", "COPY", "RUN", "RUN", "CMD",
    "ENTRYPOINT", "HEALTHCHECK",
]

_STEP_KW_RE = re.compile(r"^(FROM|RUN|COPY|CMD|ENTRYPOINT|ENV|ARG|WORKDIR|USER"
                         r"|LABEL|ADD|STOPSIGNAL|HEALTHCHECK|SHELL)\b")


def _dockerfile_steps(text: str) -> list[str]:
    """Logical steps with continuations joined (comment lines skipped). The
    suite's idiom is text regex; this just gives the regex a per-step
    subject so ordering claims are about one RUN, not the whole file."""
    steps: list[str] = []
    cur: list[str] | None = None
    for raw in text.splitlines():
        ln = raw.strip()
        if not ln:
            continue
        if _STEP_KW_RE.match(ln):
            if cur:
                steps.append(" ".join(cur))
            cur = [ln]
        elif cur is not None and not ln.startswith("#"):
            cur.append(ln)
    if cur:
        steps.append(" ".join(cur))
    return steps


def _apt_run_step(steps: list[str]) -> str | None:
    cands = [s for s in steps if s.startswith("RUN") and "apt-get" in s and "apk" not in s]
    return cands[0] if len(cands) == 1 else None


def _official_first_violations(steps: list[str]) -> list[str]:
    """C05 AC/Task 3 shape: exactly one ubuntu apt RUN; a BARE apt-get update
    precedes the || guard; inside the guard a single sed rewrites BOTH
    official stanza hosts to the kernel.org mirror in the deb822
    ubuntu.sources and retries apt-get update; install + lists-cleanup stay
    gated behind the update pair, unchanged in content."""
    out = []
    apt = _apt_run_step(steps)
    if apt is None:
        return ["the runtime stage must keep exactly ONE ubuntu apt RUN step "
                "(the rewrite edits it in place — C05 shape)"]
    guard = re.search(r"\|\|\s*\{", apt)
    if not guard:
        return ["no `|| {` fallback guard in the apt RUN — official-first-with-fallback not landed (C05)"]
    if apt.find("apt-get update") >= guard.start():
        out.append("the first apt-get update is not the plain official attempt before the guard")
    branch = apt[guard.start():]
    for host in C05_OFFICIAL_HOSTS:
        if not re.search(r"s\|https?://" + re.escape(host) + r"\|https?://" + re.escape(C05_MIRROR_HOST), branch):
            out.append(f"the fallback branch does not rewrite {host} to {C05_MIRROR_HOST} "
                       "(C05 default form — the probe-gated stanza-drop alternative routes through the test session, never a silent edit)")
    if C05_SOURCES_FILE not in branch:
        out.append(f"the fallback does not target the deb822 file {C05_SOURCES_FILE}")
    if "apt-get update" not in apt[guard.end():]:
        out.append("no retry apt-get update inside the fallback branch")
    if re.search(r"sed|kernel\.org", apt[:guard.start()]):
        out.append("mirror-rewrite machinery is reachable on the success path")
    gi = apt.find("apt-get install")
    if gi < guard.end():
        out.append("the install is not gated behind the update pair")
    else:
        if "DEBIAN_FRONTEND=noninteractive" not in apt or "--no-install-recommends" not in apt:
            out.append("install flags must stay DEBIAN_FRONTEND=noninteractive + --no-install-recommends")
        if not re.search(r"build-essential\s+git\s+ccache", apt):
            out.append("the installed set must stay exactly build-essential git ccache")
    if "rm -rf /var/lib/apt/lists/" not in apt or (gi >= 0 and apt.find("rm -rf /var/lib/apt/lists/") < gi):
        out.append("the lists cleanup must stay after the install in the same step")
    return out


def _unconditional_mirror_violations(steps: list[str]) -> list[str]:
    """The fallback is never the primary path: every kernel.org mention sits
    AFTER the guard of the apt step — none in any other step, none before
    the plain first update."""
    out = []
    apt = _apt_run_step(steps)
    guard = re.search(r"\|\|\s*\{", apt) if apt else None
    for i, s in enumerate(steps):
        start = 0
        while True:
            j = s.find(C05_MIRROR_HOST, start)
            if j < 0:
                break
            if s is not apt or guard is None or j < guard.end():
                out.append(f"step {i} puts {C05_MIRROR_HOST} on an unconditional path: {s[:70]!r}")
            start = j + 1
    for s in steps:
        if "apk" in s and (C05_MIRROR_HOST in s or any(h in s for h in C05_OFFICIAL_HOSTS)
                           or "sources.list.d" in s):
            out.append("the alpine apk step must stay untouched by the ubuntu mirror fallback")
    return out


def _step_order_violations(steps: list[str]) -> list[str]:
    """One step rewritten in place: the keyword sequence (and every stage's
    count) must equal the landed baseline."""
    seq = [s.split(None, 1)[0] for s in steps]
    if seq != C05_BASELINE_STEPS:
        return [f"step sequence {seq} != the landed baseline {C05_BASELINE_STEPS} "
                "(C05 edits the ONE apt RUN in place — no added/removed/reordered step)"]
    return []


def _readme_row_consistency(steps: list[str], readme: str) -> list[str]:
    """Docs move with the law (same chunk): the runtime-split toolchain row
    must describe the step that exists. With the guard landed, the row names
    the fallback; the baked-at-build doctrine tokens stay either way."""
    out = []
    rows = [ln for ln in readme.splitlines() if "Compile toolchain" in ln]
    if not rows:
        return ["the README lost the toolchain row entirely (its pinning home)"]
    row = rows[0]
    for tok, why in (("baked", "baked-at-build doctrine"),
                     ("apt", "the apt install mechanism"),
                     ("no pod-start apt", "the owner ruling the row carries")):
        if tok not in row:
            out.append(f"toolchain row no longer states {why} ({tok!r})")
    apt = _apt_run_step(steps)
    guarded = bool(apt and re.search(r"\|\|\s*\{", apt))
    if guarded and not (re.search(r"fallback", row, re.I)
                        and (C05_MIRROR_HOST in row or re.search(r"official", row, re.I))):
        out.append("the apt step carries the fallback but the README row does not — "
                   "the shipped description must stay render-true (move the row with its step, C05)")
    return out


def test_c05_apt_step_official_first_with_fallback():
    """DESIGNED RED until dev lands C05: the runtime apt RUN is official-first
    with the kernel.org fallback INSIDE a ||-guarded brace group against the
    deb822 ubuntu.sources, retrying the update; install flags/list-cleanup
    unchanged behind the pair (Task 3 arm 1)."""
    problems = _official_first_violations(_dockerfile_steps(DOCKERFILE.read_text()))
    assert not problems, ("cf-141 C05 apt-step shape not landed:\n" + "\n".join(problems))


def test_c05_no_unconditional_mirror_use():
    """Prohibition leg (Task 3 arm 2's shape pin, both directions): the
    kernel.org host is reachable ONLY on the failure path — never before the
    plain first update, never in another step, never in the apk step (green
    today; this is the leg that reddens if the fallback is ever mis-shipped
    as an unconditional mirror pin)."""
    problems = _unconditional_mirror_violations(_dockerfile_steps(DOCKERFILE.read_text()))
    assert not problems, ("unconditional mirror use detected:\n" + "\n".join(problems))


def test_c05_run_step_count_and_order_preserved():
    """Task 3 arm 3: the rewrite occupies the ONE apt RUN in place — the
    logical step sequence matches the landed baseline byte-for-keyword
    (today green; red on any added/removed/reordered step)."""
    problems = _step_order_violations(_dockerfile_steps(DOCKERFILE.read_text()))
    assert not problems, "step order/count moved:\n" + "\n".join(problems)


def test_c05_readme_toolchain_row_tracks_the_apt_step():
    """README runtime-split arm (L26 row, chunk Task 3): the row stays
    render-true — baked-at-build tokens always; once the apt step gains the
    guard, the row must carry the fallback clause in the same chunk. Green
    today (no guard), reddens if dev lands the step and forgets the row."""
    problems = _readme_row_consistency(_dockerfile_steps(DOCKERFILE.read_text()), README.read_text())
    assert not problems, "README toolchain-row consistency broken:\n" + "\n".join(problems)


def test_c05_shape_probes_redden_the_owning_legs():
    """The chunk's non-vacuity list, offline through the same validators:
    sed hoisted before the first update reddens BOTH the official-first and
    the unconditional legs; kernel.org on the primary path reddens the
    unconditional leg; a RUN added reddens the count leg; the landed-good
    synthetic shape clears all three."""
    good = ('FROM x\nRUN apt-get update \\\n'
            "    || { sed -i 's|http://archive.ubuntu.com|http://mirrors.edge.kernel.org|; "
            "s|http://security.ubuntu.com|http://mirrors.edge.kernel.org|' "
            "/etc/apt/sources.list.d/ubuntu.sources \\\n"
            "         && apt-get update; } \\\n"
            "    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "
            "build-essential git ccache \\\n"
            "    && rm -rf /var/lib/apt/lists/*\n")
    steps = _dockerfile_steps(good)
    assert _official_first_violations(steps) == [], _official_first_violations(steps)
    assert _unconditional_mirror_violations(steps) == []
    hoisted = good.replace(
        "RUN apt-get update",
        "RUN sed -i 's|http://archive.ubuntu.com|http://mirrors.edge.kernel.org|' "
        "/etc/apt/sources.list.d/ubuntu.sources && apt-get update")
    hs = _dockerfile_steps(hoisted)
    assert _official_first_violations(hs), "hoisted sed must redden the official-first leg"
    assert _unconditional_mirror_violations(hs), "hoisted sed must redden the unconditional leg"
    extra = good + "\nRUN echo noise\n"
    assert _step_order_violations(_dockerfile_steps(extra)), "an added RUN must redden the count leg"
    dropped = "\n".join(ln for ln in good.splitlines() if "&& apt-get update; }" in ln)
    assert _official_first_violations(_dockerfile_steps(dropped)), "a guard without its retry must redden"
    unguarded = good.replace("|| {", "{ ")
    assert _unconditional_mirror_violations(_dockerfile_steps(unguarded)), \
        "the fallback outside a || guard is unconditional use"
