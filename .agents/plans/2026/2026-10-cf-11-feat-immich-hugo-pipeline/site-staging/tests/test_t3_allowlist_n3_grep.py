"""t3 (C06 Tests): sync-albums.yaml schema per the C01 contract (page:
REQUIRED, prefix: optional, ships EMPTY) and the N3 removals gate — NO
content/photos/ fallback posture anywhere in the staging: banned literals,
negated-only posture words, and zero photos-section/archetype ARTIFACTS.
DECISIONS R13 removed the secondary posture; this gate keeps it dead.
C06 AC4."""

import re

import pytest
from conftest import ALLOWLIST, load_yaml_text, read_text, require_artifact, staging_artifact_files, STAGING
from yaml.error import YAMLError

BANNED_LITERALS = ("content/photos", "PHOTOS_SECTION", "pageless")
# R13: "no archetype, no _index.md, no hugo.yaml edit" survives in the
# staging ONLY as negation (do-not-copy guidance). A line mentioning these
# words without a negation reads as a positive instruction and fails.
POSTURE_WORDS = ("archetype", "fallback", "photos section", "photos-section")
NEGATION = re.compile(r"\b(no|not|never|none|without|removed|dropped|absent)\b", re.IGNORECASE)


def test_allowlist_parses_and_ships_empty():
    require_artifact(ALLOWLIST, "t3")
    text = read_text(ALLOWLIST, "t3")
    try:
        doc = load_yaml_text(text)
    except YAMLError as ex:
        pytest.fail(f"t3: sync-albums.yaml is not parseable YAML: {ex}")
    assert isinstance(doc, dict) and "albums" in doc, "top level must be an albums: list"
    assert doc["albums"] == [], "ships EMPTY — nothing syncs until the owner curates (C06 §3)"


def test_allowlist_header_documents_page_required():
    """The shipped comment is the schema's only documentation for the owner;
    N3 requires it to state page: REQUIRED and the loud failure."""
    text = read_text(ALLOWLIST, "t3")
    assert re.search(r"REQUIRED", text), "the allowlist header does not state page: REQUIRED (N3)"
    assert re.search(r"(?i)fails? (the sync )?loud|loud(ly)? (error|fail)|error naming", text), \
        "the allowlist header does not document the loud schema failure (C01 §1)"
    commented = "\n".join(l for l in text.splitlines() if l.lstrip().startswith("#"))
    assert "prefix" in commented.lower(), "the optional prefix: path is undocumented"


def test_commented_examples_follow_the_schema():
    """§3 ships commented example entries; they must model the real schema
    (name + page, optional prefix) — owners copy them verbatim."""
    text = read_text(ALLOWLIST, "t3")
    ex = re.findall(r"#\s*-\s*name:\s*\"?([^\"\n]+)\"?\n((?:\s*#.*\n)+)", text)
    assert ex, "no commented example entries found"
    for name, tail in ex:
        assert re.search(r"#\s*page:", tail), f"example for {name!r} lacks the required page: key"


def test_zero_banned_literals_across_staging():
    """Grep gate over ALL staged files (the test suite itself is the scanner,
    not a staged artifact — excluded so its banned-term list cannot
    self-trip). content/photos is forbidden even in negation: R13 deleted
    the path from the design entirely."""
    hits = []
    for p in staging_artifact_files():
        try:
            text = p.read_text()
        except (UnicodeDecodeError, OSError):
            continue
        for lit in BANNED_LITERALS:
            if lit in text:
                hits.append(f"{p.relative_to(STAGING)}: {lit}")
    assert not hits, hits


def test_posture_words_only_in_negation():
    offenders = []
    for p in staging_artifact_files():
        try:
            lines = p.read_text().splitlines()
        except (UnicodeDecodeError, OSError):
            continue
        for i, line in enumerate(lines):
            low = line.lower()
            if any(w in low for w in POSTURE_WORDS) and not NEGATION.search(line):
                offenders.append(f"{p.relative_to(STAGING)}:{i + 1}: {line.strip()[:100]}")
    assert not offenders, "positive photos-section/archetype/fallback posture in staging: " + " | ".join(offenders)


def test_no_section_archetype_index_artifacts_exist():
    """N3 removals asserted on the filesystem, not just prose: staging ships
    ONLY workflows + sync-albums.yaml + APPLY-INSTRUCTIONS (+ tests)."""
    names = {p.name for p in staging_artifact_files()}
    assert "_index.md" not in names and "index.md" not in names
    for p in staging_artifact_files():
        rel = p.relative_to(STAGING)
        assert "archetypes" not in rel.parts, f"archetype artifact staged: {rel}"
        assert "content" not in rel.parts, f"content artifact staged: {rel}"
        assert p.name != "hugo.yaml", "a hugo.yaml change is staged (never shipped)"
    top = {p.name for p in STAGING.iterdir()
           if p.is_dir() and p.name not in {"tests", ".pytest_cache"}}
    assert top <= {".forgejo"}, f"unexpected staged directories: {sorted(top)}"


def test_apply_instructions_copy_list_final_fold():
    """C06 §4: the porting spec for C07 copies ONLY the workflows +
    sync-albums.yaml and records the LFS-migration caveat."""
    from conftest import APPLY, read_text
    text = read_text(APPLY, "t3")
    assert re.search(r"\.forgejo/workflows/(deploy|sync)\.(yml|yaml)", text), text[:200]
    assert "sync-albums.yaml" in text
    assert re.search(r"(?i)lfs", text), "no LFS-object caveat (broken aeroponics builds without them)"
