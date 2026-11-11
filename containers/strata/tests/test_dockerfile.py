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
# cf-141 C05 (CORRECTED 2026-11-11; r3 SAME DAY) — CI-resilient apt step:
# the runtime stage re-points BOTH deb822 stanza hosts (Canonical) at the
# kernel.org mirror UNCONDITIONALLY before its single apt-get update, then
# installs the same gated set and cleans the lists — still exactly ONE ubuntu
# apt RUN. r3 (coord ruling, DECISIONS): the replacement endpoint is
# https://mirrors.edge.kernel.org — the landed http:// form fetched correctly
# in CI but the runner could not CONNECT on :80 (timeout after resolution);
# https answered 200 in the serveability probes. A plaintext re-point is now
# the regression this law reddens. Rackspace standby is a ruling
# contingency, not a law, and the CA-store pre-verify is the dev round's
# evidence obligation — neither gets a test.
# The official-first ||-guard shape this section first contracted is WITHDRAWN:
# CI (main build @ f58334ffe) proved `apt-get update` exits 0 even with every
# stanza host unresolvable ("... ignored, or old ones used instead"), so a ||
# branch never fires and the step dies at the install instead — the guard is
# structurally dead for the failure mode it was written for. Reinstated as the
# contract: the owner's verbatim unconditional re-point (DECISIONS "Coord
# rulings (2026-11-11)"). No version/label/marker/ledger literal moves here —
# the C04-era arms above are this chunk's preservation run, unchanged.
#
# All laws are structural regex over the Dockerfile/README text (the suite's
# idiom) and carry no network: the base-shape and suite-serveability evidence
# (ubuntu.sources deb822 on the 0.2.13 base; kernel.org serving noble +
# noble-security, both 200) is the dev round's live-probe job, recorded in its
# RESULT, never re-fetched from a test.
#
# Red-first posture at authoring: the guarded shape is what is LANDED, so the
# three shape legs below are DESIGNED RED naming C05 for exactly the withdrawn
# structure; the probes leg proves each law bites in both directions.
# ---------------------------------------------------------------------------

C05_MIRROR_HOST = "mirrors.edge.kernel.org"
C05_OFFICIAL_HOSTS = ("archive.ubuntu.com", "security.ubuntu.com")
C05_SOURCES_FILE = "/etc/apt/sources.list.d/ubuntu.sources"
# Claims of the withdrawn posture may survive nowhere in the shipped shape —
# not in the apt step's why-comment block, not in the README toolchain row.
# They describe a mechanism the CI evidence killed; keeping the prose would
# sell the dead guard as live protection.
C05_WITHDRAWN_CLAIMS = ("official-first", "official first", "never the primary",
                        "self-retir", "only a failed", "only on failure",
                        "only a non-zero", "fallback")
# The landed pre-C05 logical step sequence. The correction rewrites the ONE
# runtime apt RUN in place (the sed joins that same step), so the 18-keyword
# sequence holds for the guarded interim shape AND the corrected target — the
# parser's step model is the law being exercised here, so it is asserted, not
# assumed (test_c05_run_step_count_and_order_preserved).
C05_BASELINE_STEPS = [
    "FROM", "FROM", "FROM", "FROM", "COPY", "RUN", "FROM", "RUN",
    "COPY", "COPY", "COPY", "COPY", "COPY", "RUN", "RUN", "CMD",
    "ENTRYPOINT", "HEALTHCHECK",
]

_STEP_KW_RE = re.compile(r"^(FROM|RUN|COPY|CMD|ENTRYPOINT|ENV|ARG|WORKDIR|USER"
                         r"|LABEL|ADD|STOPSIGNAL|HEALTHCHECK|SHELL)\b")


def _dockerfile_steps(text: str) -> list[str]:
    """Logical steps with continuations joined (comment lines skipped), so an
    ordering claim speaks about one RUN, not the whole file."""
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


def _step_order_violations(steps: list[str]) -> list[str]:
    """One step rewritten in place: the logical keyword sequence (every
    stage's count and order) must equal the landed baseline — the rewrite
    edits the ONE apt RUN, it does not add, drop or reorder a step."""
    seq = [s.split(None, 1)[0] for s in steps]
    if seq != C05_BASELINE_STEPS:
        return [f"step sequence {seq} != the landed baseline {C05_BASELINE_STEPS} "
                "(C05 edits the ONE apt RUN in place — no added/removed/reordered step)"]
    return []


def _repoint_regex(host: str) -> str:
    """r3 (coord 2026-11-11): the replacement URL is exactly the https form —
    the runner's :80 egress to the mirror timed out after resolution
    succeeded, and https answered 200. The SOURCE side stays scheme-flexible
    (the base's deb822 URIs are Canonical http lines the sed must match)."""
    return (r"s\|https?://" + re.escape(host) + r"\|https://" + re.escape(C05_MIRROR_HOST))


def _plaintext_repoint_regex(host: str) -> str:
    return (r"s\|https?://" + re.escape(host) + r"\|http://" + re.escape(C05_MIRROR_HOST))


def _apt_repoint_violations(steps: list[str]) -> list[str]:
    """The unconditional-form law (r3 endpoint): inside the ONE ubuntu apt
    RUN, a sed re-points BOTH deb822 stanza hosts to the HTTPS kernel.org
    mirror in /etc/apt/sources.list.d/ubuntu.sources BEFORE the single
    apt-get update; no ||-guard text anywhere; install + lists-cleanup gated
    behind the pair with the shipped content unchanged. A plaintext
    (http://mirror) re-point is the r3 regression: the :80 path is exactly
    what the CI runner proved filtered."""
    apt = _apt_run_step(steps)
    if apt is None:
        return ["the runtime stage must keep exactly ONE ubuntu apt RUN step "
                "(the rewrite edits it in place — C05)"]
    out = []
    if re.search(r"\|\|", apt):
        out.append("|| fallback-guard structure present — ruled dead by CI: apt-get update "
                   "exits 0 on wholly-failed fetches, so the guard never fires (DECISIONS 2026-11-11)")
    sed_at = apt.find("sed")
    if sed_at < 0:
        out.append("no sed re-point in the apt RUN — the Canonical hosts are still on the fetch path")
    for host in C05_OFFICIAL_HOSTS:
        if re.search(_plaintext_repoint_regex(host), apt):
            out.append(f"stanza host {host} is re-pointed to PLAINTEXT http://{C05_MIRROR_HOST} — "
                       "r3 moved the endpoint to https:// (the runner's :80 egress timed out; "
                       "a plaintext fetch after the ruling is the regression)")
        elif not re.search(_repoint_regex(host), apt):
            out.append(f"stanza host {host} is not re-pointed to https://{C05_MIRROR_HOST} "
                       f"in {C05_SOURCES_FILE}")
    if C05_SOURCES_FILE not in apt:
        out.append(f"the re-point does not target the deb822 file {C05_SOURCES_FILE}")
    updates = [m.start() for m in re.finditer(r"apt-get update", apt)]
    if len(updates) != 1:
        out.append(f"{len(updates)} apt-get update invocations — the unconditional form "
                   "carries exactly ONE (a conditional retry pair is the withdrawn shape)")
    if sed_at >= 0 and updates and updates[0] < sed_at:
        out.append("the update precedes the re-point — Canonical hosts must be off the "
                   "fetch path BEFORE apt-get update runs")
    gi = apt.find("apt-get install")
    if gi < 0 or (updates and gi < updates[0]):
        out.append("the install must sit behind the single update")
    else:
        if "DEBIAN_FRONTEND=noninteractive" not in apt or "--no-install-recommends" not in apt:
            out.append("install flags must stay DEBIAN_FRONTEND=noninteractive + --no-install-recommends")
        if not re.search(r"build-essential\s+git\s+ccache", apt):
            out.append("the installed set must stay exactly build-essential git ccache")
    cl = apt.find("rm -rf /var/lib/apt/lists/")
    if cl < 0 or (gi >= 0 and cl < gi):
        out.append("the lists cleanup must stay after the install in the same step")
    return out


def _no_guard_structure_violations(steps: list[str]) -> list[str]:
    """What must NOT exist once the re-point is unconditional: any
    ||-guard remnant, any apt-get update reachable before the sed (the dead
    plain-attempt of the withdrawn shape), and any mirror/ubuntu-sources text
    outside the single apt RUN — the alpine apk step in particular is
    different mirror family, out of scope, untouched."""
    out = []
    apt = _apt_run_step(steps)
    if apt is not None:
        if re.search(r"\|\|", apt):
            out.append("|| guard text survives in the apt RUN (withdrawn C05 shape)")
        sed_at = apt.find("sed")
        updates = [m.start() for m in re.finditer(r"apt-get update", apt)]
        if updates and (sed_at < 0 or updates[0] < sed_at):
            out.append("an apt-get update is reachable before the re-point (pre-sed attempt — "
                       "the guard shape's corpse)")
    for s in steps:
        if s is apt:
            continue
        if C05_MIRROR_HOST in s:
            out.append(f"{C05_MIRROR_HOST} appears outside the apt RUN: {s[:70]!r}")
        if "apk" in s and (C05_SOURCES_FILE in s
                           or any(h in s for h in C05_OFFICIAL_HOSTS)
                           or re.search(r"\|\|", s)):
            out.append("the alpine apk step carries ubuntu-mirror or guard text — out of scope (C05)")
    return out


def _apt_comment_violations(text: str) -> list[str]:
    """The apt step's own why-comment block (contiguous # lines directly above
    its RUN) must document the unconditional re-point, not the withdrawn
    posture: no C05_WITHDRAWN_CLAIMS token survives, and the mirror choice is
    named. Constraint statement, no outage narration (repo comment law)."""
    lines = text.splitlines()
    starts = [i for i, ln in enumerate(lines) if _STEP_KW_RE.match(ln)]
    run_i = None
    for k, i in enumerate(starts):
        end = starts[k + 1] if k + 1 < len(starts) else len(lines)
        body = " ".join(ln.strip() for ln in lines[i:end] if not ln.strip().startswith("#"))
        if body.startswith("RUN") and "apt-get" in body and "apk" not in body:
            run_i = i
            break
    if run_i is None:
        return []          # the shape law owns a missing/multi apt step
    block: list[str] = []
    j = run_i - 1
    while j >= 0 and lines[j].strip().startswith("#"):
        block.append(lines[j].strip())
        j -= 1
    blob = "\n".join(block).lower()
    out = [f"the apt comment still claims the withdrawn posture ({c!r}) — a dead mechanism "
           "sold as live protection" for c in C05_WITHDRAWN_CLAIMS if c in blob]
    if "kernel.org" not in blob:
        out.append("the apt comment does not name the kernel.org mirror — the why of the "
                   "re-point must live where a reader of the sed looks")
    return out


def _readme_row_consistency(readme: str) -> list[str]:
    """Docs move with the law, same chunk: the README L26 toolchain row keeps
    the baked-at-build tokens AND states the corrected posture — mirror named,
    re-point unconditional, no withdrawn claim survives (an 'official-first'
    row beside an unconditional sed is the stale-doc class the runbook
    corrections ledger exists to catalogue)."""
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
    low = row.lower()
    stale = [c for c in C05_WITHDRAWN_CLAIMS if c in low]
    if stale:
        out.append(f"toolchain row still claims the withdrawn posture: {stale} "
                   "(move the row with the law — C05 correction)")
    if "https://mirrors.edge.kernel.org" not in low:
        out.append("the row does not name the https mirror endpoint (r3: https://mirrors.edge.kernel.org)")
    if "http://mirrors.edge.kernel.org" in low:
        out.append("the row still advertises the plaintext mirror endpoint — r3 replaced it with "
                   "https:// (the :80 path the runner proved filtered must not be documented as live)")
    if not re.search(r"unconditional", low):
        out.append("the row must state the re-point posture the step actually has (unconditional)")
    return out


def test_c05_apt_step_unconditional_repoint_before_single_update():
    """Corrected shape law (replaces the withdrawn
    test_c05_apt_step_official_first_with_fallback): the ONE ubuntu apt RUN
    sed-re-points both deb822 stanza hosts to the kernel.org mirror BEFORE
    its single apt-get update; no || guard; install and lists-cleanup gated
    behind, content unchanged. DESIGNED RED against the landed guarded step,
    naming C05 with the guard-presence body."""
    problems = _apt_repoint_violations(_dockerfile_steps(DOCKERFILE.read_text()))
    assert not problems, ("cf-141 C05 corrected shape not landed:\n" + "\n".join(problems))


def test_c05_no_guard_structure_or_pre_sed_update():
    """Inverted from the withdrawn prohibition leg: the unconditional re-point
    is now required (shape arm above); what must NOT exist is the || guard
    text, an apt-get update reachable before the sed, mirror text outside the
    apt RUN, or ubuntu-mirror/guard contamination of the alpine apk step."""
    problems = _no_guard_structure_violations(_dockerfile_steps(DOCKERFILE.read_text()))
    assert not problems, ("withdrawn-shape structure survives:\n" + "\n".join(problems))


def test_c05_run_step_count_and_order_preserved():
    """The rewrite occupies the ONE apt RUN in place: the logical keyword
    sequence equals the landed baseline (18 steps, RUNs 4). The correction
    does not move it (the sed joins the same step), so this leg is green for
    both shapes and stays the guard against a step added, dropped or
    reordered."""
    problems = _step_order_violations(_dockerfile_steps(DOCKERFILE.read_text()))
    assert not problems, "step order/count moved:\n" + "\n".join(problems)


def test_c05_readme_toolchain_row_tracks_the_apt_step():
    """The doc pair moves with the law in the same chunk: the apt step's
    why-comment block and the README L26 toolchain row must both state the
    corrected posture — mirror named, unconditional, no withdrawn claim (the
    guard's prose is as dead as its ||). Both surfaces read together because
    one shipped description split across them is the drift class."""
    text = DOCKERFILE.read_text()
    problems = _apt_comment_violations(text) + _readme_row_consistency(README.read_text())
    assert not problems, ("C05 docs disagree with the corrected law:\n" + "\n".join(problems))


# --- corrected-form target text: validated GREEN on scratch, and the
# non-vacuity probes that prove each law bites in both directions. The
# synthetic texts double as the dev round's byte-target (Task brief carries
# the exact RUN + comment + row text; the shapes below must satisfy every law
# so dev authors to a form the suite is already known to accept).
# ---

_C05_TARGET_COMMENT = (
    "# the base image's deb822 stanza hosts are re-pointed at the\n"
    "# kernel.org mirror unconditionally, before the single update: apt-get\n"
    "# update exits 0 even when every host is unresolvable, so a conditional\n"
    "# retry cannot detect the failure that matters (mirror serves noble and\n"
    "# noble-security, probed at adoption); throwaway toolchain layer.\n"
)
_C05_TARGET_RUN = (
    "RUN sed -i 's|http://archive.ubuntu.com|https://mirrors.edge.kernel.org|;\n"
    "        s|http://security.ubuntu.com|https://mirrors.edge.kernel.org|'\n"
    "        /etc/apt/sources.list.d/ubuntu.sources \\\n"
    "    && apt-get update \\\n"
    "    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends\n"
    "        build-essential git ccache \\\n"
    "    && rm -rf /var/lib/apt/lists/*\n"
)
_C05_GUARDED_RUN = (
    "RUN apt-get update \\\n"
    "    || { sed -i 's|http://archive.ubuntu.com|https://mirrors.edge.kernel.org|;\n"
    "           s|http://security.ubuntu.com|https://mirrors.edge.kernel.org|'\n"
    "           /etc/apt/sources.list.d/ubuntu.sources && apt-get update; } \\\n"
    "    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends\n"
    "        build-essential git ccache \\\n"
    "    && rm -rf /var/lib/apt/lists/*\n"
)


def test_c05_target_form_clears_every_law_and_guarded_mutants_redden():
    """Both-direction integrity (the §9.32 probes, re-pointed at the
    correction): the synthetic TARGET (unconditional sed + its comment block)
    satisfies shape, guard-removal, comment and row laws; the landed GUARDED
    run reddens shape and guard-removal alike; a hoisted update-before-sed
    reddens both too; the withdrawn-posture comment and the old README row
    redden the doc laws; apk contamination reddens the guard law; a step
    added reddens the count law."""
    steps_target = _dockerfile_steps(_C05_TARGET_RUN)
    assert _apt_repoint_violations(steps_target) == [], _apt_repoint_violations(steps_target)
    assert _no_guard_structure_violations(steps_target) == []
    assert _apt_comment_violations(_C05_TARGET_COMMENT + _C05_TARGET_RUN) == []
    assert _readme_row_consistency(
        "| Compile toolchain (baked, not runtime-installed) | build-essential, git, ccache "
        "via apt — stanza hosts re-pointed unconditionally to "
        "https://mirrors.edge.kernel.org before the single apt-get update; no pod-start apt |"
    ) == []

    plaintext = _C05_TARGET_RUN.replace("|https://mirrors", "|http://mirrors")
    pv = _apt_repoint_violations(_dockerfile_steps(plaintext))
    assert sum(1 for v in pv if "PLAINTEXT" in v) == 2, \
        f"both plaintext re-pointed hosts must redden the shape law (r3), got {pv}"

    steps_guarded = _dockerfile_steps(_C05_GUARDED_RUN)
    gv = _apt_repoint_violations(steps_guarded)
    assert gv and any("|| fallback-guard" in v for v in gv), "the landed guard must redden the shape law"
    assert any("|| guard text survives" in v for v in _no_guard_structure_violations(steps_guarded)), \
        "the landed guard must redden the guard-removal law"

    hoisted = _C05_TARGET_RUN.replace(
        "RUN sed -i", "RUN apt-get update && sed -i", 1).replace("    && apt-get update", "    && true", 1)
    hv = _apt_repoint_violations(_dockerfile_steps(hoisted))
    assert any("update precedes the re-point" in v for v in hv), "update-before-sed must redden the shape law"
    assert any("reachable before the re-point" in v for v in _no_guard_structure_violations(_dockerfile_steps(hoisted))), \
        "update-before-sed must redden the guard-removal law"

    stale_comment = ("# official-first with a fallback guard: only on failure re-point\n"
                     "# both stanza hosts at mirrors.edge.kernel.org and retry; never the primary path.\n")
    cv = _apt_comment_violations(stale_comment + _C05_TARGET_RUN)
    assert cv and all("withdrawn posture" in v for v in cv[:1]), "the withdrawn comment must redden"
    rv = _readme_row_consistency(
        "| Compile toolchain (baked, not runtime-installed) | official-first: only a failed "
        "update takes the fallback to http://mirrors.edge.kernel.org (never the primary path, "
        "self-retires); no pod-start apt |")
    assert rv and any("withdrawn posture" in v for v in rv), "the withdrawn README row must redden"

    apk_bad = ("RUN apk add --no-cache git ca-certificates http://archive.ubuntu.com\n"
               + _C05_TARGET_RUN)
    assert any("apk step" in v for v in _no_guard_structure_violations(_dockerfile_steps(apk_bad))), \
        "apk ubuntu-host contamination must redden the guard law"
    stray = ("COPY mirror /tmp/x http://mirrors.edge.kernel.org/file\n" + _C05_TARGET_RUN
             + "\nCMD [\"x\"]\n")
    assert any("outside the apt RUN" in v
               for v in _no_guard_structure_violations(_dockerfile_steps(stray))), \
        "the mirror host on any non-apt step must redden the guard law"
    extra = _C05_TARGET_RUN + "RUN echo noise\n"
    assert _step_order_violations(_dockerfile_steps(extra)), "an added step must redden the count law"
