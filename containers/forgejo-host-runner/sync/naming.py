"""Derivative filename derivation — chunks/C01.md contract §4/§5 (t1). The
name IS the idempotency mechanism: checksum-anchored, so re-runs are
diff-empty (§10) and same-name files are recognized without state."""

import base64
import re
import unicodedata
from pathlib import Path

MODE_AUTO = "auto"
MODE_MACHINE = "machine"


def capture_stamp(asset):
    # DTO fallback chain (RESEARCH.md R2.3): localDateTime is the v3 field;
    # exifInfo.dateTimeOriginal is the older-shape fallback; createdAt last.
    local = next(
        (str(value) for value in (
            asset.get("localDateTime"),
            (asset.get("exifInfo") or {}).get("dateTimeOriginal"),
            asset.get("createdAt"),
        ) if value),
        None,
    )
    if local is None:
        raise ValueError(f"asset {asset.get('id')} carries no capture time")
    local = local[:19]
    return re.sub(r"[-:]", "", local[:10]) + "-" + local[11:19].replace(":", "")


def checksum8(asset):
    # AssetResponseDto.checksum is base64 (RESEARCH.md R2.3); the first 8
    # hex chars make the name content-stable.
    return base64.b64decode(asset["checksum"]).hex()[:8]


def safe_original(original_file_name):
    stem = Path(original_file_name).stem
    folded = unicodedata.normalize("NFKD", stem).encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^A-Za-z0-9._-]", "_", folded).lower()


def base_name(asset):
    return f"{capture_stamp(asset)}_{checksum8(asset)}_{safe_original(asset['originalFileName'])}.jpg"


def album_slug(album_name):
    # Slug rule is frozen by the C01 test harness so C01's machine block and
    # C06's render-gate fixture agree byte-for-byte (conftest ALBUM_SLUG).
    return re.sub(r"[^a-z0-9]+", "-", album_name.lower()).strip("-")


def derivative_name(asset, mode, slug, prefix):
    if mode == MODE_MACHINE:
        return f"sync-{slug}-{base_name(asset)}"
    return f"{prefix}{base_name(asset)}"
