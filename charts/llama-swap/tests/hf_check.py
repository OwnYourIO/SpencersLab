# Manual HuggingFace re-verification for the roster (chunks/C04.md task 1 /
# acceptance 1: "repos churn — re-verify every repo:TAG at implementation").
# NOT part of the default suite: run in review (`python3 hf_check.py`) or via
# the RUN_HF_CHECK=1-gated test. Stdlib-only (urllib) — CI already has network
# for the HF API; gated repos need HF_TOKEN in the environment.
#
# Tag resolution mirrors llama.cpp 889edf43 common/download.cpp (verified from
# the raw source 2026-10-23). -hf refs follow find_best_model(): case-
# insensitive
# regex `TAG[.-]` searched over the full sibling PATH, candidate files = *.gguf
# whose basename contains none of the case-SENSITIVE sidecar tokens
# (mmproj/imatrix/mtp-/eagle3-/dflash-/dspark-), multi-shard models matched only
# via their -00001-of-NNNNN primary, and an empty tag falls back Q4_K_M -> Q8_0
# -> first model file. -hfd refs follow the DRAFT path (find_best_sibling via
# opts.download_mtp): root-level .gguf containing the case-SENSITIVE "mtp-"
# keyword, with the named sidecar required for churn sensitivity (the loader
# would silently download a different draft otherwise). Existence check, not
# ordering: llama.cpp resolves to the first listing match, so a tag colliding
# inside another quant's name (Q2_K vs Q2_K_L) can pick the wrong FILE — churn
# detection (the real purpose) is unaffected. Exit 0 = every wired ref resolves.

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
import llama_swap_testlib as L  # noqa: E402

HF_API = "https://huggingface.co/api/models/"


def refs_from_renders(clusters=("gpu", "gpu-ai")) -> list[tuple[str, str, str, str]]:
    """(cluster, model_id, flag, repo:tag) for every -hf/-hfd token rendered."""
    refs = []
    for cluster in clusters:
        for mid, m in L.all_models_of(L.rendered_config(cluster)).items():
            cmd = m.get("cmd")
            if not isinstance(cmd, str):
                continue
            for flag in ("-hf", "-hfd"):
                val = L.cmd_flag_value(cmd, flag)
                if val and "/" in val:
                    refs.append((cluster, mid, flag, val))
    return refs


def _siblings(repo: str) -> tuple[list[str], str | None]:
    req = urllib.request.Request(HF_API + repo)
    token = os.environ.get("HF_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return [], f"HTTP {e.code}" + (" (gated? set HF_TOKEN)" if e.code in (401, 403) else "")
    except Exception as e:  # noqa: BLE001 - manual tool: report anything, never crash the loop
        return [], f"error: {e}"
    return [f.get("rfilename", "") for f in data.get("siblings", [])], None


_MODEL_SKIP = ("mmproj", "imatrix", "mtp-", "eagle3-", "dflash-", "dspark-")
_SPLIT = re.compile(r"^(.+)-([0-9]{5})-of-([0-9]{5})$", re.IGNORECASE)


def _is_model_candidate(path: str) -> bool:
    if not path.endswith(".gguf"):
        return False
    name = path.rsplit("/", 1)[-1]
    return not any(tok in name for tok in _MODEL_SKIP)  # loader: case-SENSITIVE


def _shard_primary_or_whole(path: str) -> bool:
    stem = path[: -len(".gguf")]
    m = _SPLIT.match(stem)
    return not (m and int(m.group(3)) > 1 and int(m.group(2)) != 1)


def _tag_resolves(tag: str, files: list[str]) -> bool:
    """MODEL rule for -hf refs (find_best_model)."""
    cands = [f for f in files if _is_model_candidate(f)]
    for t in ([tag] if tag else ["Q4_K_M", "Q8_0"]):
        pat = re.compile(re.escape(t) + r"[.-]", re.IGNORECASE)
        for f in cands:
            if pat.search(f) and _shard_primary_or_whole(f):
                return True
    if not tag:  # loader's final fallback: any first model file
        return any(_shard_primary_or_whole(f) for f in cands)
    return False


def _sidecar_resolves(tag: str, files: list[str], keyword: str = "mtp-") -> bool:
    """DRAFT rule for -hfd refs: llama.cpp routes a -hfd repo through
    find_best_sibling(files, primary=empty, "mtp-", tag) - root-level .gguf
    paths containing the CASE-SENSITIVE keyword; the tag only ranks the pick.
    For churn detection we require the specifically named sidecar to exist
    (the loader would silently download a different draft otherwise)."""
    base = tag.removesuffix(".gguf").upper()
    return any(
        "/" not in f
        and f.endswith(".gguf")
        and keyword in f  # loader: case-sensitive full-path find()
        and (not base or base in f.upper())
        for f in files
    )


def collect_problems(refs: list[tuple[str, str, str, str]]) -> list[str]:
    problems = []
    cache: dict[str, tuple[list[str], str | None]] = {}
    for cluster, mid, flag, ref in sorted(refs):
        repo, _, tag = ref.partition(":")
        if repo not in cache:
            cache[repo] = _siblings(repo)
        files, err = cache[repo]
        if err:
            problems.append(f"{cluster}/{mid} {flag} {ref}: repo lookup failed: {err}")
        else:
            ok = (_sidecar_resolves if flag == "-hfd" else _tag_resolves)(tag, files)
            if not ok:
                problems.append(f"{cluster}/{mid} {flag} {ref}: TAG resolves to no file in repo siblings")
    return problems


def main() -> int:
    refs = refs_from_renders()
    print(f"checking {len(refs)} -hf/-hfd refs across both cluster renders")
    problems = collect_problems(refs)
    for p in problems:
        print("MISSING:", p)
    print("OK" if not problems else f"{len(problems)} unresolved")
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())
