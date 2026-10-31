# cf-86 C07 (revision round 2, owner U9.4) — the staging laws RE-ANCHORED from
# the rendered init script to the baked image files (chunks/C07.md: "same
# laws, new source"). The byte-equivalence AC says the lift is pure: marker
# semantics, byte pins, downloader mechanism, redirect-trust law, guard-before-
# bytes ordering and the env contract all survive the move, so every arm below
# enforces a law the suite already ran — over containers/strata/files/* instead
# of the values.yaml heredoc.
#
# Red posture (test-first, the normal designed-red wave): every arm is RED from
# the test round until C06-dev's verbatim port lands the three files; the
# failure names the missing file, not a weakened law.
#
# C07 is a PURE lift: the SC117 (abliterated) code moves INTACT and dies only
# in C08, so this file pins the C07-ERA content — BOTH packs staged, four byte
# literals. Arms tagged "C07-era" are on the wave-retirement list (TEST_SPEC
# 9.14): C08's sweep replaces them with the absence arms in
# test_strata_c08_rung_shifts.py. The wave-neutral arms (downloader, wedge,
# trust law, markers, ordering, env contract) stay green through C08 — C08
# changes their URLs/bytes, never their shape (chunk Notes).

from __future__ import annotations

import re

import pytest

import strata_testlib as S

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)

# Byte literals: the same HF-tree pins the render-era arms carried (read
# 2026-10-30 anonymously; provenance recorded in test_strata_orca_rung.py).
# C07-era byte_pins.env carries all six; C08 rewrites it (SC117 lines die,
# orca pair becomes the three IQ4_XS literals pinned in the C08 file).
ABL_BYTES_C07 = (47342144896, 28800138432)
ORCA_BYTES_C07 = (44637691008, 40564977024)

# The shell-client ban the render-era arms ran line-scoped (comments NAME curl
# to forbid it; the image provably carries no curl — bake+verify law).
_HTTP_CLIENT = re.compile(r"\b(curl|wget|aria2c|axel)\b")

WHY = "cf-86 C07 init lift — chunks/C07.md verbatim port, baked + build-verified"


def _fetch_sh() -> str:
    return S.read(S.FETCH_SH, WHY)


def _hf_fetch() -> str:
    return S.read(S.HF_FETCH_PY, WHY)


def _pins() -> str:
    return S.read(S.BYTE_PINS_ENV, WHY)


# --- the lift landed: three files, wired together -----------------------------


@helm
def test_c07_image_carries_the_three_fetch_files_wired_together():
    """files/fetch_models.sh + hf_fetch.py + byte_pins.env exist and the driver
    actually uses its siblings: sourcing the pins and invoking the downloader
    by their baked /opt/strata/bin paths (the chart's exec-form command and the
    Dockerfile COPY pin the same three paths — one interface, three homes)."""
    script, downloader, pins = _fetch_sh(), _hf_fetch(), _pins()
    assert re.search(r"(?:^|[\s;&|])(?:source|\.)\s+\S*byte_pins\.env", script), (
        "fetch_models.sh does not source byte_pins.env — the byte literals "
        "would live in two unsynchronized places again"
    )
    assert f"{S.BIN}/hf_fetch.py" in script, (
        f"fetch_models.sh never invokes {S.BIN}/hf_fetch.py — the downloaders "
        "must be the baked file, not inline heredocs (build-verify covers files, not heredocs)"
    )
    assert "urllib.request" in downloader, "hf_fetch.py is no longer the stdlib urllib path"


# --- downloader law (C01/C02 addendum laws, same subjects) ---------------------


@helm
def test_c07_driver_body_carries_no_shell_http_client():
    body = S.body_lines(_fetch_sh())
    offenders = [ln.strip() for _, ln in body if _HTTP_CLIENT.search(ln)]
    assert not offenders, f"fetch_models.sh invokes a shell HTTP client: {offenders}"


@helm
def test_c07_downloader_call_shape_names_mode_and_pinned_want_bytes():
    """Call shape from the chunk: $SRC/.venv/bin/python /opt/strata/bin/hf_fetch.py
    <mode> <url> <part> <want-bytes> — still the checkout venv interpreter (same
    urllib/cert trust chain as shipped), and every invocation states a want-bytes
    leg (literal or a byte_pins.env var), never an un-pinned download."""
    body = S.body_lines(_fetch_sh())
    calls = [(n, ln.strip()) for n, ln in body if "hf_fetch.py" in ln]
    assert calls, "no hf_fetch.py invocation lines in the driver"
    shape = re.compile(
        r"\$SRC/\.venv/bin/python.*hf_fetch\.py\s+(anon|gated)\s+\S+\s+\S+\s+(\"?\$\{?\w+\}?\"?|\d{8,})"
    )
    unpinned = [ln for _, ln in calls if not shape.search(ln)]
    assert not unpinned, f"download invocation outside the mode+want-bytes shape: {unpinned}"


@helm
def test_c07_hf_fetch_is_one_file_two_modes_anon_and_gated():
    """Same file, two modes (chunk file split). DECISIONS keeps anon after C08
    too (deleting it re-opens the security-law source shape), so this arm is
    wave-neutral; the gated mode's token law is its own arm."""
    body = _hf_fetch()
    modes = re.findall(r"\b(anon|gated)\b", body)
    assert {"anon", "gated"} <= set(modes), (
        f"hf_fetch.py must dispatch on both modes (chunk file split); tokens seen: {sorted(set(modes))}"
    )
    assert re.search(r"sys\.argv", body), "hf_fetch.py takes no argv — the <mode> <url> <part> <want> call shape is gone"


# --- C07-era byte pins (C08-era replacement in test_strata_c08_rung_shifts.py) --


@helm
def test_c07_byte_pins_env_carries_the_c07_era_four_literals():
    """C07-era content: SC117 pair + orca IQ3_XXS pair, each as an assignment,
    Σ comments riding along (the ORCA.md 85,202,668,032 total). A literal that
    drifted from the HF-tree read is a silent truncated-shard acceptance."""
    pins = _pins()
    for size in ABL_BYTES_C07 + ORCA_BYTES_C07:
        assert re.search(rf"^[A-Z][A-Z0-9_]*={size}$", pins, re.M), (
            f"byte_pins.env has no NAME={size} assignment — the pin this pack "
            "contract was built on (HF tree API 2026-10-30) is missing or renamed"
        )
    assert "85202668032" in pins, "the ORCA.md total comment must ride with the orca pair"
    extra = set(re.findall(r"^[A-Z][A-Z0-9_]*=(\d{8,})$", pins, re.M))
    assert extra == {str(s) for s in ABL_BYTES_C07 + ORCA_BYTES_C07}, (
        f"byte_pins.env literals {sorted(extra)} != the C07-era four — a 5th byte "
        "literal needs a plan, C08's rewrite is not early (wave table TEST_SPEC 9.14)"
    )


@helm
def test_c07_pack_functions_stage_the_c07_era_paths_and_repos():
    """C07-era pairing source: abl_pack/orca_pack assignments live in the image
    script now; the repo literals and 2-shard paths ride with them verbatim."""
    script = _fetch_sh()
    abl = S.staged_paths(script, "abl_pack", "IQ3_XXS")
    orca = S.staged_paths(script, "orca_pack", "IQ3_XXS")
    assert "SC117/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-GGUF" in script, (
        "the SC117 repo literal left the lift — C07 is a PURE port (C08 deletes it)"
    )
    assert "orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF" in script, (
        "the orcarouter repo literal left the lift"
    )
    assert abl["pack"] == "/models/strata/Strata-data/packs/abliterated-iq3_xxs"
    assert orca["pack"] == "/models/strata/Strata-data/packs/orca-iq3_xxs"
    assert abl["s1"].endswith("-00001-of-00002.gguf") and abl["s2"].endswith("-00002-of-00002.gguf")
    assert orca["s1"].endswith("-00001-of-00002.gguf") and orca["s2"].endswith("-00002-of-00002.gguf")


# --- the redirect-trust law, baked (C02 review-adjudicated) --------------------


@helm
def test_c07_hf_fetch_gated_leg_keeps_the_redirect_trust_law():
    """The measured hazard (review-C02: urllib redirect_request FORWARDS
    Authorization cross-host): auto-follow must be refused, hops walked manually
    over an hf.co-family allowlist, Bearer ONLY at the token host, CDN leg on
    pre-signed signature + Range, hop cap 4. These facts live in the baked file
    now — a lift that "simplifies" them back to urlopen(url) re-opens the token
    leak the review closed."""
    body = _hf_fetch()
    handler = re.search(r"class (\w+)\(urllib\.request\.HTTPRedirectHandler\)", body)
    assert handler, "no HTTPRedirectHandler subclass — the default handler auto-follows"
    assert re.search(rf"build_opener\([^)]*{handler.group(1)}\(\)", body), (
        f"{handler.group(1)} is defined but not wired into build_opener — an unwired "
        "handler is the leak: urllib re-issues each hop and copies Authorization along"
    )
    rd = re.search(r"def redirect_request\(.*?\):\n((?:[ \t]+.*\n){1,6})", body)
    assert rd and re.search(r"^\s*return None\b", rd.group(1), re.M) and "super()" not in rd.group(1), (
        "redirect_request must return None (no super()) so the 302 surfaces as HTTPError — "
        "urllib's own handler re-issues the request and copies Authorization to the next host"
    )
    assert re.search(r'HF_TOKEN|Authorization.*Bearer', body), "the gated mode lost its token read"
    assert "TOKEN_HOST" in body and re.search(r'\.hf\.co.*\.huggingface\.co|\.huggingface\.co.*\.hf\.co', body, re.S), (
        "the hf.co-family allowlist / token-host scoping is gone"
    )
    assert re.search(r'(host\s*==\s*TOKEN_HOST|netloc\s*==\s*TOKEN_HOST)', body), (
        "Authorization is no longer gated to the token host — every hop would carry the Bearer"
    )
    assert re.search(r"depth\s*>=\s*4|depth\s*>\s*3", body), "the manual walk lost its 4-hop cap"
    assert "refusing off-platform redirect" in body or "refusing" in body, (
        "the off-platform refusal message is gone — a refused redirect must name itself"
    )


@helm
def test_c07_part_resume_and_wedge_semantics_survive_the_lift():
    """.part staging: exact-size rename, have> want restart (corrupt leftover),
    have== want break, Range-200 restart (ignored Range), fail-exit with the
    partial kept. These render-era arms are what makes an interrupted 85 GB
    download re-entrant; the boot guard's self-heal argument rests on them."""
    body = _hf_fetch()
    assert "os.remove(part); have = 0" in body or re.search(r"os\.remove\(part\).*have\s*=\s*0", body, re.S), (
        "the corrupt-leftover restart is gone — a .part larger than want would wedge every boot"
    )
    assert re.search(r"have\s*==\s*want\s*:?[\s\S]{0,80}?break|if have == want", body), "no complete-part short-circuit"
    assert re.search(r'status\s*==\s*200', body), "no ignored-Range restart (200 on a ranged request = corrupt merge otherwise)"
    assert re.search(r'final\s*=\s*os\.path\.getsize|getsize\(part\)', body), "the exact-size completion check is gone"


@helm
def test_c07_token_never_leaves_the_process_env_contract():
    """R-d download-only law across the split: the script passes the token to
    the downloader ONLY through its process env (the secretKeyRef already sits
    on the init container and must not move or wrap); the driver must not take
    the token as argv, and the driver must fail loudly on an empty token."""
    script, downloader = _fetch_sh(), _hf_fetch()
    assert "HF_TOKEN" in downloader and re.search(r'os\.environ', downloader), (
        "the downloader no longer reads HF_TOKEN from the environment"
    )
    assert not re.search(r'hf_fetch\.py\s+gated\s+[^\n]*\$\{?HF_TOKEN', script), (
        "the token was spelled into the call line — argv exposure in ps and logs; env passthrough only"
    )
    assert re.search(r'HF_TOKEN is empty|not token', downloader), "the empty-token loud fail is gone"


# --- marker / idempotency / ordering laws (render-era, relocated) ---------------


@helm
def test_c07_marker_law_survives_the_lift():
    """.setup-$TOK skip guard + touch-after, and the .pack-orca marker behind a
    -f guard touched only after orca_pack returns — the exact ordering the
    render-era arms pinned, now over the baked driver."""
    body = S.body_lines(_fetch_sh())
    assert "fail()" in "".join(ln for _, ln in body), "the loud-fail helper left the script"
    mark = [n for n, ln in body if re.match(r"^\s*MARK=\S*\.setup-", ln)]
    assert mark, "no /models/strata/.setup-$TOK marker assignment"
    assert any(re.search(r'\[\s*-f\s+"\$MARK', ln) for _, ln in body), "the .setup marker lost its -f skip guard"
    om = [n for n, ln in body if re.search(r'\.pack-orca', ln)]
    assert om, "no .pack-orca marker reference"
    oguard = [n for n, ln in body if re.search(r'\[\s*-f\s+"?\$\{?OMARK', ln)]
    otouch = [n for n, ln in body if re.search(r'touch\s+"?\$\{?OMARK', ln)]
    ocalls = [n for n, ln in body if re.match(r"^\s*orca_pack\b", ln)]
    assert oguard and otouch and ocalls, f"orca marker guard/touch/call missing (guard {oguard}, touch {otouch}, calls {ocalls})"
    assert min(otouch) > max(ocalls), "the orca marker is touched before orca_pack returns — a partial pack becomes permanent"
    for _, ln in body:
        assert "rm -rf /models/strata/Strata-data" not in ln, (
            f"destructive pack delete in the driver: {ln.strip()!r}"
        )


@helm
def test_c07_guard_before_bytes_ordering_survives_the_lift():
    """C01 review law: the venv + gguf-py guards sit ABOVE any download for
    each manual pack — 76/85 GB must never start for a pack this init cannot
    build. Order-checked, not presence-checked."""
    body = S.body_lines(_fetch_sh())
    for fn in ("abl_pack", "orca_pack"):
        start = next((k for k, (_, ln) in enumerate(body) if re.match(rf"^\s*{fn}\(\)", ln)), None)
        assert start is not None, f"no {fn}() definition in the driver"
        tail = body[start:]
        # the guard pair spans two lines in the shipped shape
        # ([ -x ... ] \n || fail ...), so scan line windows, not single lines
        windowed = [(n, a + " " + b) for (n, a), (_, b) in zip(tail, tail[1:])]
        # the -x/-d test is the guard; the download invocation also names the
        # venv interpreter, so match the test idiom, not the interpreter path
        venv_guard = re.compile(r"\[\s*-x\s+\"?\$?\{?\S*\.venv/bin/python")
        gguf_guard = re.compile(r"\[\s*-d\s+\"?\$?\{?\S*(ggufpy|gguf-py)")
        downloads = [n for n, ln in tail if re.search(r"_dl\s+\"https?://", ln)]
        assert downloads, f"{fn}: no download legs to order against"
        for label, rx in (("venv", venv_guard), ("gguf-py", gguf_guard)):
            guards = [n for n, ln in windowed if rx.search(ln) and "fail" in ln]
            assert guards, f"{fn}: no {label} fail-guard at all"
            assert min(guards) < min(downloads), (
                f"{fn}: {label} guard ({min(guards)}) sits below the bytes ({min(downloads)}) — "
                "76/85 GB must never start for a pack this init cannot build"
            )


@helm
def test_c07_env_contract_scalars_and_pseudo_family_routing_in_the_script():
    """The env contract lands inside the script now: IFS=, loop over
    STRATA_QUANTS (default q3), STRATA_MODEL_$TOK mapping, the abl/orca
    pseudo-family routing (C07-era: BOTH — C08 drops abl), and the verbatim
    `--backend hip` setup.sh line."""
    script = _fetch_sh()
    assert re.search(r"IFS=,", script), "the comma-split loop over STRATA_QUANTS is gone"
    assert re.search(r'STRATA_QUANTS:-q3', script), "the chart-side q3 default contract is gone"
    assert re.search(r'STRATA_MODEL_\$TOK|printenv "STRATA_MODEL_\$TOK"', script), (
        "the STRATA_MODEL_$TOK scalar mapping left the loop"
    )
    assert re.search(r'\[ "\$FAM" = abl \]', script), (
        "the abl pseudo-family arm is gone — C07 is a PURE lift; C08 owns that deletion"
    )
    assert re.search(r'\[ "\$FAM" = orca \]', script), "the orca pseudo-family arm left the lift"
    assert "--backend hip" in script, "the mandatory --backend hip leg (2026-10-29 deploy) left the setup.sh call"


@helm
def test_c07_sessions_dir_mkdir_now_lives_in_the_script():
    """C06 deviation-2 cured by the lift itself: the overlay could not hold the
    mkdir, so C06 put it chart-side; the verbatim port moves it INTO the driver
    (idempotent mkdir -p), and the chart-side copy leaves with the script body
    (pinned by test_strata_thin_init.py)."""
    assert "mkdir -p " + S.Q4_SLOT_SAVE_PATH in _fetch_sh(), (
        f"fetch_models.sh lacks the idempotent 'mkdir -p {S.Q4_SLOT_SAVE_PATH}' — "
        "the sessions dir law must land exactly once, in the driver"
    )


@helm
def test_c07_checkout_copy_setup_guards_and_python_discovery_ported():
    """The boot self-diagnose block ports verbatim: /opt/strata/src/Strata
    checkout guard, claim-copy with the no-overwrite fail, the terminal-python
    discovery loop, and the git/c++ bake-check (the same pair the Dockerfile
    verify step pins — bake+verify law)."""
    script = _fetch_sh()
    assert "/opt/strata/src/Strata" in script, "the image-checkout anchor left the script"
    assert "refusing to overwrite" in script, "the no-overwrite checkout guard is gone"
    assert re.search(r"/opt/strata/terminal/bin/python", script), "the terminal-python discovery loop is gone"
    assert re.search(r"command -v git", script) and re.search(r"command -v c\+\+", script), (
        "the git/c++ self-diagnose left the script — its build-side twin is the Dockerfile verify step"
    )
