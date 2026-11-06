# cf-86 C09 — the ornith-on-Strata CARRY, image side (chunks/C09.md a;
# RESEARCH R5 §Q3/Q4 is the technical authority). The vendored 2-hunk
# constants patch, the claim-checkout migration step (the landmine R5 resolved
# from our shipped copy-once-never-refresh law), and the GGUF-direct ornith
# download leg. Red posture: every arm whose subject is C09-new content is
# designed-red until dev lands (patch file absent, driver step absent, pins
# absent); the live tree arms (RUN_HF_CHECK=1) are green TODAY — they re-read
# the public HF tree the pins came from, and they keep proving the pins while
# the file-side arms wait for dev. The negative arms (data-state preservation,
# no bare `rm -rf "$SRC"`, no pack/token on the orn leg) guard the dev edit and
# stay green before it — their teeth are probe-proven (TEST_SPEC §9.19).
#
# Landmine law (AC2, suite-pinned): the migration syncs SOURCE paths only.
# packs (Strata-data/), strata-*.json run configs, $SRC/.venv, $SRC/engine/,
# every .setup-*/.pack-* marker and .done file SURVIVE the migration; a naive
# `rm -rf "$SRC"` re-downloads and re-packs the ~290 GB arena set and is the
# forbidden shape. The marker names the image version + carry-N so a future
# bump re-fires, and it is touched ONLY after a green recompile (loud-fail
# law: a crash mid-compile re-enters rather than serving a half-built engine).
#
# Chart-side companion: test_strata_c09_ornith_arena.py. The Dockerfile tag
# pair / clone branch / engine-label trio live in the containers suite's
# flipped constants (containers/strata/tests/test_dockerfile.py) — this file
# owns the C09-NEW surfaces: the patch shape, the verify-layer carry greps
# (the ONLY pre-merge proof — CI never compiles HIP), the README digest rows
# and the driver laws.

from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request

import pytest

import strata_testlib as S

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)
hf_live = pytest.mark.skipif(
    os.environ.get("RUN_HF_CHECK") != "1",
    reason="evidence gate: RUN_HF_CHECK=1 re-reads the ungated HF tree the ornith pins come from",
)

CARRY_PATCH = S.CONTAINER_DIR / "carry" / "ornith-q36.patch"
DOCKERFILE = S.CONTAINER_DIR / "Dockerfile"
IMAGE_README = S.CONTAINER_DIR / "README.md"

# The two hunks R5 verified (§Q3): constants-only, no new kernels. Values are
# byte-exact law; only context lines may drift with v0.2.9 line numbers.
PATCH_HUNK_TARGETS = {
    "include/strata/kernels/cpu/native_expert.hpp",
    "src/kernels/cuda/iq_kernels.cu",
}
# R5 [C2] — verbatim GHCR pair for 0.2.9, chained re-verification (R3 law).
TAG_DIGEST_029 = {
    "0.2.9-rocm-gfx120x": "sha256:a0536d4b9e734a1d06b9b630362b95d01108382a4a39785e6abdc1dfe8326c39",
    "0.2.9-rocm-gfx1151": "sha256:2ac97575713efaa37299d914c628d3f1d40b68b893dd78430f7ea4bd18c5084a",
}


def _driver() -> str:
    return S.read(S.FETCH_SH, "C09 edits the baked driver (migration step + orn leg)")


def _pins() -> str:
    return S.read(S.BYTE_PINS_ENV, "C09 adds the three ornith shard literals")


def _dockerfile() -> str:
    return S.read(DOCKERFILE, "C09 re-pins 0.2.9 and applies the carry in the build")


def _image_readme() -> str:
    return S.read(IMAGE_README, "C09 extends the README pin ledger")


def _body() -> list:
    return S.body_lines(_driver())


# --- the vendored patch: shape, content, per-hunk provenance ------------------


def test_c09_carry_patch_exists_with_exactly_two_hunks():
    """The two-hunk claim is R5-verified; a third hunk means reality moved
    (dev STOPs and NEEDS_INFO, never improvises), so the hunk COUNT is law,
    not just the content. The header regex must match REAL unified-diff
    headers — the `+c,d` side is not optional (§9.19 authored a `+`-less
    pattern that matched no real header: a vacuous zero-count read as
    absence; repaired and probe-checked against the landed v0.2.9 patch and
    a synthetic 3-hunk drift)."""
    text = S.read(CARRY_PATCH, "C09 vendors carry/ornith-q36.patch — exactly 2 hunks")
    hunks = re.findall(r"^@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@.*$", text, re.M)
    assert len(hunks) == 2, (
        f"patch carries {len(hunks)} hunk headers, want exactly 2 "
        "(a third = re-research, chunks/C09.md Notes; a zero = malformed diff)"
    )
    targets = set(re.findall(r"^diff --git a/(\S+) b/\S+$", text, re.M))
    assert targets == PATCH_HUNK_TARGETS, f"patch targets {sorted(targets)}, want the two R5 files"


def test_c09_hunk1_bumps_kNativeHBytes_from_1024_to_2048():
    """Ornith's FF-1024 down activation is Q8_K = 1,168 B > the 1024 B pool
    buffer — the pool constant moves, byte-exact (native_expert.cpp L219 class
    failure; the WHY comment must ride)."""
    text = S.read(CARRY_PATCH, "hunk 1 of the carry")
    hunk1 = text.split("src/kernels/cuda/iq_kernels.cu")[0]
    assert re.search(r"^-\+?[^\n]*kNativeHBytes\s*=\s*1024", hunk1, re.M) or \
        re.search(r"^-[^\n]*kNativeHBytes\s*=\s*1024", hunk1, re.M), \
        "no removal of the 1024 constant in the native_expert hunk"
    assert re.search(r"^\+[^\n]*kNativeHBytes\s*=\s*2048", hunk1, re.M), \
        "no kNativeHBytes = 2048 addition — the pool would still refuse ornith's 1,168 B activation"


def test_c09_hunk2_adds_X12_to_STRATA_D_FMTS():
    """UD-Q4_K_XL's routed expert downs need Q4_K (fmt 12 — X(12))
    down-supported (checkpoint census: routed downs ∈ {Q4_K(12), Q5_K(13)},
    no Q3_K anywhere — the r1-finding-1 correction the landing commit carried;
    the first wording said Q3_K_M). GU already instantiates 12 for gate/up —
    only the down list is short: exactly ONE addition per branch."""
    text = S.read(CARRY_PATCH, "hunk 2 of the carry")
    hunk2 = text.split("iq_kernels.cu")[-1]
    assert re.search(r"STRATA_D_FMTS", hunk2), "the D_FMTS macro left the hunk"
    assert re.search(r"^\+[^\n]*X\(12\)", hunk2, re.M), "no + line adding X(12) — the D_FMTS gap stays"


def test_c09_each_hunk_is_commented_with_3574_and_the_rewatch_trigger():
    """Upstream will not merge this (#3574 closed not_planned); the carry is
    only honest while every hunk names the upstream issue AND the drop
    trigger (merged-upstream or #4460-first-class ⇒ drop at the next pin
    bump). Provenance is what makes a vendored patch auditable, not folklore."""
    text = S.read(CARRY_PATCH, "carry provenance comments")
    comments = [ln for ln in text.splitlines() if ln.lstrip().startswith("#")]
    citing = [ln for ln in comments if "3574" in ln]
    assert len(citing) >= 2, (
        f"{len(citing)} comment lines cite #3574, want >= 2 (one per hunk — chunks/C09.md a)"
    )
    blob = "\n".join(comments)
    assert re.search(r"#4460|merged|drop", blob, re.I), (
        "no re-watch/drop trigger recorded — the tripwire that makes the carry self-retiring"
    )


# --- the build applies it, and the VERIFY layer re-proves it ------------------


def test_c09_build_copies_and_applies_the_carry_before_dotgit_removal():
    text = _dockerfile()
    assert re.search(r"COPY\s+\S*carry/ornith-q36\.patch", text), (
        "the patch is not copied into the strata-src build context"
    )
    apply_at = next((i for i, ln in enumerate(text.splitlines())
                     if re.search(r"git\s+apply[^\n]*ornith-q36\.patch", ln)), None)
    assert apply_at is not None, "no git apply of the carry patch in the build"
    dotgit_rm = [i for i, ln in enumerate(text.splitlines())
                 if re.search(r"rm\s+-rf\s+\S*\.git\b", ln)]
    assert not dotgit_rm or apply_at < min(dotgit_rm), (
        "git apply runs after the .git removal — apply must run against the checkout (C09 a)"
    )


def test_c09_verify_layer_reproves_the_carry_at_build_time():
    """CI does NOT compile HIP code — these greps are the ONLY pre-merge proof
    the patched tree is what compiled (the C01 curl-law class: fail the BUILD,
    not the boot). `--check --reverse` against the applied tree proves the
    patch applied EXACTLY once with no upstream drift swallowed."""
    blob = "\n".join(m.group(1) for m in re.finditer(r"^RUN(.*)$", _dockerfile(), re.M | re.S))
    assert re.search(r"git\s+apply\s+--check\s+--reverse[^\n]*ornith-q36\.patch", blob), (
        "no git apply --check --reverse of the carry over the applied tree"
    )
    assert re.search(r"grep[^\n]*kNativeHBytes[^\n]*2048", blob), (
        "no grep assertion for kNativeHBytes = 2048 (native_expert.hpp)"
    )
    assert re.search(r"grep[^\n]*X\(12\)[^\n]*iq_kernels\.cu|grep[^\n]*iq_kernels\.cu[^\n]*X\(12\)", blob), (
        "no grep assertion for X(12) in the D_FMTS line (iq_kernels.cu)"
    )


def test_c09_readme_ledger_carries_the_029_digest_pair_and_0155_exe_rows():
    """README is the recorded home of the tag→digest pairing (ruling (b)) —
    the [C2] digests verbatim — and the 0.1.55 exe rows the engine bump moves
    (the containers suite's three-surface arm pairs them; this arm pins the
    digest VALUES themselves, which only the README carries)."""
    readme = _image_readme()
    for tag, digest in TAG_DIGEST_029.items():
        assert tag in readme, f"README never names the 0.2.9 flavor tag {tag}"
        assert digest in readme, f"README never records the [C2] digest {digest[:19]}… for {tag}"
    for label in ("0.1.55-linux-x86_64-hip-rx9070", "0.1.55-linux-x86_64-hip-halo"):
        assert label in readme, f"README exe ledger lacks the 0.1.55 row {label}"


# --- THE claim-checkout migration step (the landmine) -------------------------


def test_c09_migration_step_is_marker_keyed_and_rearming():
    """Marker-gated, content-compared (a name-only `-f` test would never
    re-fire on a bump — the name carries version+carryN precisely so the
    COMPARISON re-arms the step at the next bump). Variable-extracted like the
    C01 marker law so the guard/write shape can name the marker through a
    variable, not only inline."""
    text = _driver()
    body = _body()
    m = re.search(r'^\s*(\w+)\s*=\s*"?[^\n"]*\.checkout-0\.2\.9-carry(\d+)?', text, re.M)
    assert m, f"no marker assignment carrying .checkout-0.2.9-carryN (want {S.CHECKOUT_MARKER}) — the copy-once claim never refreshes"
    var = m.group(1)
    assert m.group(2), "the marker name lacks the carry-N counter — future carries must re-fire it"
    guards = [ln for _, ln in body
              if re.search(r"(cat|cmp|diff)[^\n]*\$?\{?" + var, ln)
              or re.search(r'\[\s*"[^"]*\$\{?' + var, ln)]
    assert guards, "the marker is only existence-tested, never content-compared — bumps would not re-fire"


def test_c09_migration_syncs_image_tree_except_claim_data_state():
    """2026-10-31 second-boot law: the sync ENUMERATES the image checkout — a
    hard-coded source allowlist goes stale the day upstream adds a build input
    (v0.2.9's CMakeLists compiles tests/hip/gdn_stage_bench.cpp; the allowlist
    kept the claim's old tests/ and cmake configure died "Cannot find source
    file"). Data state is the closed skip-case set; drift there is drift in
    THIS arm, by design. cp -a stays the tool (rsync is not baked — C09 a),
    and third_party keeps merging AFTER the loop."""
    text = _driver()
    assert re.search(r'for entry in /opt/strata/src/Strata/\*', text), (
        "sync must enumerate the image tree, not a fixed allowlist"
    )
    assert 'case "$b" in data|Strata-data|third_party|engine|build-hip) continue ;;' in text, (
        "the data-state skip set changed — each member is a claim artifact "
        "(expert-profile / weights+packs / merged llama.cpp unpack / built "
        "engine / stale cache); adding or removing one is a contract change"
    )
    cp_after_loop = re.search(r'cp -a /opt/strata/src/Strata/third_party "\$SRC"/', text)
    loop_at = text.index('for entry in /opt/strata/src/Strata/*')
    assert cp_after_loop and cp_after_loop.start() > loop_at, "third_party must merge after the loop, never inside its rm"
    assert 'rm -rf "$SRC"/src ' not in text, (
        "the retired hard-coded allowlist is back — it missed tests/ on 2026-10-31"
    )
    assert not re.search(r"^\s*rsync\b", text, re.M), (
        "rsync appears in the driver — not baked into the image (C09 a baked-tool law)"
    )


def test_c09_migration_wipes_build_hip_before_recompiling():
    body = _body()
    wipe = [n for n, ln in body if re.search(r'rm\s+-rf\s+"?\$?\{?SRC\}?/build-hip"?', ln)]
    assert wipe, 'no rm -rf "$SRC/build-hip" — the stale cmake cache would rebuild from the old tree'
    compile_at = _compile_line(body)
    assert wipe[0] < compile_at, "build-hip wipe runs after the recompile — the cache still wins"


def _compile_line(body) -> int:
    hits = [n for n, ln in body if re.search(r"(cmake|ninja)[^\n]*build-hip", ln)]
    assert hits, "the migration step never invokes the engine recompile (the .setup-* markers skip setup.sh — nobody else will recompile)"
    return hits[0]


def test_c09_migration_marker_is_written_only_after_a_green_recompile():
    """The loud-fail ordering law: guard < sync < recompile < marker. A marker
    written early makes the half-built engine permanent — crash mid-compile
    must RE-ENTER (engine dir absent ⇒ no serving on a broken binary)."""
    body = _body()
    m = re.search(r'^\s*(\w+)\s*=\s*"?[^\n"]*\.checkout-0\.2\.9-carry(\d+)?', _driver(), re.M)
    assert m, "no marker assignment to order against"
    var = m.group(1)
    guards = [n for n, ln in body
              if re.search(r"(cat|cmp|diff)[^\n]*\$?\{?" + var, ln)
              or re.search(r'\[\s*"[^"]*\$\{?' + var, ln)]
    syncs = [n for n, ln in body if re.search(r"\bcp\s+-a\b", ln)]
    assert guards and syncs, f"no content-compare guard for ${var} or no cp -a step to order against"
    sync = min(syncs)
    compile_at = _compile_line(body)
    writes = [n for n, ln in body
              if re.search(r"touch[^\n]*\$?\{?" + var + r"\}?" + r"|>[^\n]*\$?\{?" + var + r"\}?", ln)]
    assert writes, f"${var} is never written — the migration would re-run on every boot"
    assert min(guards) < sync < compile_at < min(writes), (
        f"migration order violated: guard {min(guards)}, first cp -a {sync}, "
        f"recompile {compile_at}, marker write {min(writes)}"
    )


def test_c09_migration_never_deletes_data_state():
    """AC's negative law, executable over the WHOLE script: the forbidden
    shapes are a bare `rm -rf "$SRC"` and any rm targeting the data state the
    migration must preserve (packs, .venv, run-config JSONs, every marker
    family, .done files, engine/). Green before dev AND after — its teeth are
    probe-proven by injecting the forbidden shape (§9.19)."""
    offenders = []
    for n, ln in _body():
        if re.search(r'rm\s+-rf\s+"?\$?\{?SRC\}?"?\s*$', ln):
            offenders.append((n, ln.strip(), 'bare rm -rf "$SRC" re-downloads/re-packs the ~290 GB arena set'))
            continue
        if re.search(r"\brm\s+-\w*[rf]", ln) and re.search(
                r"Strata-data|packs/|\.venv|strata-\w+\.json|\.dl-|\.pack-|\.setup-|\.done|\{?SRC\}?/engine", ln):
            offenders.append((n, ln.strip(), "migration deletes data state C09 must preserve"))
    assert not offenders, f"data-state deletion in the driver: {offenders}"


def test_c09_migration_heals_a_claim_venv_whose_python_dangles_at_the_image():
    # 2026-10-31 first-boot law: $SRC/.venv/bin/python is a symlink into the
    # provisioning image's interpreter — an image swap can dangle it while the
    # wheel-installed cmake/ninja keep working, and setup.sh never re-runs on a
    # marker-provisioned claim. The migration must HEAL it (ln -sfn only, never
    # touching .venv content; site-packages minor gate), fall back to the image
    # interpreter otherwise, and never shell a bare claim-venv python for
    # BUILD.json metadata. Static-shape arm; behaviour proven by the harness
    # recorded in the fix round (TEST_SPEC).
    text = _driver()
    assert text.count("/opt/strata/terminal/bin/python3") == 1, (
        "terminal interpreter candidates live in exactly one resolver (find_python3)"
    )
    assert '! -x "$SRC/.venv/bin/python"' in text, (
        "heal must test executability — a dangling symlink is not -x"
    )
    assert re.search(r'ln -sfn "\$imgpy" "\$SRC/\.venv/bin/python3?"', text), (
        "heal re-points via ln -sfn (no content rewrite of the venv)"
    )
    assert 'ln -sfn "$imgpy" "$SRC/.venv/bin/python3"' in text, (
        "both interpreter names are re-pointed"
    )
    assert "site-packages" in text, "the minor-match gate reads the venv's site-packages dir"
    assert '"$SRC/.venv/bin/python" -c' not in text, (
        'migration metadata reads go through "$PY" (venv-first, image-fallback) — '
        "a bare claim-venv python dangles across image swaps (2026-10-31 boot)"
    )
    assert 'PY="$SRC/.venv/bin/python"' in text and "PY=$(find_python3)" in text, (
        "explicit $PY resolution: claim venv first, image python3 fallback"
    )


# --- the GGUF-direct ornith leg (NO pack) -------------------------------------


def _orn_window() -> list:
    """Driver lines of the orn pseudo-family arm, from the case test to the
    next elif/fi — the window the pack/token negatives scan."""
    body = _driver().splitlines()
    start = next((i for i, ln in enumerate(body) if re.search(r'\[\s*"\$FAM"\s*=\s*orn\s*\]', ln)), None)
    assert start is not None, 'no [ "$FAM" = orn ] pseudo-family arm (the orca pattern C09 must copy)'
    end = next((i for i in range(start + 1, len(body)) if re.match(r"\s*(elif|fi)\b", body[i])), len(body))
    return [(i + 1, body[i]) for i in range(start, end)]


def test_c09_orn_legs_are_three_anon_calls_with_the_exact_repo_paths():
    """Ungated by live proof (gated=false, ranged resolve 206 + GGUF magic,
    no Bearer challenge) — so the legs ride hf_fetch's ANON mode and cite the
    DECISIONS 2026-10-31 keep-both-modes decision that finally earns its keep.
    The three repo paths are verbatim from the 2026-10-31 anonymous tree read
    (dev does not guess — same posture as C08's orca read)."""
    body = _body()
    for path in S.ORNITH_SHARD_PATHS:
        legs = [ln for _, ln in body if path in ln]
        assert legs, f"driver never fetches {path} — the pinned 3-shard set is not staged"
        assert any(re.search(r"hf_fetch\.py[^\n]*\banon\b", ln) for ln in legs), (
            f"{path}: leg is not an anon-mode hf_fetch call (bytes ungated — a gated leg invents a token need)"
        )
    window = _orn_window()
    cite = [ln for _, ln in window if re.search(r"ungated|anon", ln)]
    assert cite, "the orn arm records no ungated/anon-mode rationale"
    assert re.search(r"DECISIONS", _driver()), (
        "no DECISIONS citation for the anon-mode posture (the keep-both-modes decision)"
    )


def test_c09_byte_pins_env_carries_the_three_ornith_literals_and_the_sum():
    """Each literal is an assignment (the downloader loops until that exact
    size and mv's only on a match — the pin is what keeps a truncated shard
    out of the profile), and the Σ comment must equal the sum of the three
    pinned literals (the anti-slip law the q4/orca totals arms carry — a cited
    total that is not the sum of its parts is the 398,000 B class)."""
    pins = _pins()
    for size in S.ORNITH_SHARD_BYTES:
        assert re.search(rf"^[A-Z][A-Z0-9_]*={size}$", pins, re.M), (
            f"byte_pins.env has no NAME={size} assignment — the pin from the live tree read is missing"
        )
    assert str(S.ORNITH_TOTAL_BYTES) in pins, f"Σ {S.ORNITH_TOTAL_BYTES} total comment missing"
    named = {m.group(1): int(m.group(2)) for m in
             re.finditer(r"^([A-Z][A-Z0-9_]*)=(\d+)$", pins, re.M)}
    orn = [v for v in named.values() if v in S.ORNITH_SHARD_BYTES]
    assert sum(orn) == S.ORNITH_TOTAL_BYTES, (
        f"the three pinned literals sum to {sum(orn)}, not the recorded Σ {S.ORNITH_TOTAL_BYTES} — re-run the live tree arm"
    )


def test_c09_dl_ornith_marker_skips_when_present_and_fires_after_the_complete_set():
    """.dl-* completeness law WITHOUT a pack: skip-guard before the legs,
    marker written only after all three legs (q36 has no iq_pack step — the
    .pack-* law is not applicable; the profile pointers + this marker cover
    completeness)."""
    body = _body()
    marker = S.ORNITH_DL_MARKER
    legs = [n for n, ln in body if any(p in ln for p in S.ORNITH_SHARD_PATHS)]
    assert len(legs) >= 3, f"fewer than 3 ornith legs: {legs}"
    guard = [n for n, ln in body if re.search(rf'\[\s*-f\s+"?{re.escape(marker)}', ln)]
    assert guard and guard[0] < min(legs), f"no -f skip guard before the legs for {marker}"
    writes = [n for n, ln in body if re.search(rf"(touch|printf|echo)[^\n]*\.dl-ornith", ln)]
    assert writes and max(legs) < min(writes), (
        f".dl-ornith not written after the complete file set (legs {legs}, writes {writes})"
    )


def test_c09_ornith_leg_gets_no_pack_step_and_no_token():
    """FORBIDDEN shapes (chunk forbidden list): pack steps for q36 (there is
    no iq_pack path for GGUF-direct serving) and HF_TOKEN involvement (bytes
    ungated — a token on this leg would also break the keyless-serve posture
    the C-A arms enforce)."""
    window = _orn_window()
    blob = "\n".join(ln for _, ln in window)
    assert not re.search(r"iq_pack|orca_pack\b|pack_", blob), (
        "a pack step appears in the orn arm — q36 GGUF-direct has none (C09 forbidden list)"
    )
    assert not re.search(r"HF_TOKEN|\bgated\b", blob), (
        "token machinery appears in the orn arm — the bytes are ungated (forbidden list)"
    )


def test_c09_ornith_stages_under_original_repo_names_under_Strata_data():
    """Staged under ORIGINAL names (the profile points at the same three
    files; a rename here silently breaks every profile-side shard law), under
    the Strata-data claim root like every other arena's weights."""
    body = _body()
    staged = [ln for _, ln in body
              if re.search(r"/models/strata/Strata-data/[^\n]*Ornith-1\.5-122B-UD-Q4_K_XL-0000\d-of-00003\.gguf", ln)]
    assert len(staged) >= 3, (
        "the three shards are not staged with their original names under /models/strata/Strata-data/"
    )


# --- live arms: the pins stay honest against the public tree -------------------


@hf_live
def test_c09_ornith_pins_match_the_live_tree_and_the_ungated_premise():
    """Re-reads the public tree anonymously: paths + sizes == the constants,
    and a ranged resolve of the middle shard answers 200/206 with GGUF magic —
    NOT 401/403 — which is the premise that keeps HF_TOKEN out of this leg
    (the mirror-image of orca's gated-trio law). If unsloth ever gates, this
    arm reddens and the token question goes back through coord, not a dev
    edit."""
    url = f"https://huggingface.co/api/models/{S.HF_REPO_ORNITH}/tree/main?recursive=true"
    with urllib.request.urlopen(url, timeout=30) as resp:
        tree = json.loads(resp.read())
    gguf = {f["path"]: f.get("size") or (f.get("lfs") or {}).get("size")
            for f in tree if str(f.get("path", "")).endswith(".gguf") and "UD-Q4_K_XL" in str(f.get("path", ""))}
    want = dict(zip(S.ORNITH_SHARD_PATHS, S.ORNITH_SHARD_BYTES))
    assert gguf == want, f"live UD-Q4_K_XL tree {gguf} diverged from the pinned set — re-pin through the test session"

    req = urllib.request.Request(
        f"https://huggingface.co/{S.HF_REPO_ORNITH}/resolve/main/{S.ORNITH_SHARD_PATHS[1]}",
        headers={"Range": "bytes=0-15"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            head = resp.read(4)
            status = resp.status
    except urllib.error.HTTPError as err:
        raise AssertionError(
            f"resolve of shard 2 answered {err.code} — the ungated premise behind the anon legs is gone; "
            "the token question re-opens at coord (never a silent gated edit)"
        )
    assert status in (200, 206) and head == b"GGUF", f"resolve answered {status} with magic {head!r}"
