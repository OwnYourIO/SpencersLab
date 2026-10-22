# Manual HuggingFace re-verification for the roster (chunks/C04.md task 1 /
# acceptance 1: "repos churn — re-verify every repo:TAG at implementation").
# NOT part of the default suite: run in review (`python3 hf_check.py`) or via
# the RUN_HF_CHECK=1-gated test. Stdlib-only (urllib) — CI already has network
# for the HF API; gated repos need HF_TOKEN in the environment.
#
# Tag resolution rule mirrors llama.cpp's `-hf repo:TAG` matching (image audit
# 889edf43, RESEARCH §3): case-insensitive, TAG followed by '.', '-' or a path
# segment — deliberately loose here: this catches renamed/dropped quant FILES
# (the actual churn risk), while `-validate` / a serve test proves resolution
# semantics. Exit 0 = every ref resolves.

from __future__ import annotations

import json
import os
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


def _tag_resolves(tag: str, files: list[str]) -> bool:
    """llama.cpp-style loose match: TAG begins a filename/path segment (then
    '.', '-' or end), or is the exact file path. Empty tag = any model gguf."""
    names = [f.lower() for f in files]
    if not tag:
        return any(n.endswith(".gguf") for n in names)
    for n in names:
        base = n.rsplit("/", 1)[-1]
        stem = base.removesuffix(".gguf")
        segments = n.split("/")
        if stem.startswith(tag.lower()) and (
            len(stem) == len(tag) or stem[len(tag)] in ".-"
        ):
            return True
        if any(s.lower() == tag.lower() for s in segments[:-1]):
            return True
    return False


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
        elif not _tag_resolves(tag, files):
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
