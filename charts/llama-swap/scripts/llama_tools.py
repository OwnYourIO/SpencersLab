#!/usr/bin/env python3
"""llama-swap operator provisioning tools (gpu-ai tools sidecar).

Everything here is EXPLICIT, operator-run work (kubectl exec into the `tools`
container). Nothing runs automatically: no in-request downloads, no implicit
conversion, no smoke tests on startup.

Commands:
  status                 Report provisioning state of the known artifacts.
  prepare                Create/reuse the venv, stage the vendored converter,
                         fetch the cyber LoRA adapter + its base model config.
  convert-cyber          Convert the staged PEFT adapter to GGUF (f16),
                         atomic publish + SHA-256 record.
  download <artifact>    Fetch one explicitly named artifact (consent gate:
                         refuses to run without an artifact name).
  verify                 Size + SHA-256 checks of provisioned artifacts.
  smoke-test <model>     Pod-local check: /v1/models then a tiny chat
                         completion against the named model. Never runs
                         automatically.

Design rules:
  - HF_TOKEN (when set) is used for downloads but NEVER logged.
  - All downloads go to a temp file first, then atomic rename. Interrupted
    downloads resume via HTTP Range when the server supports it.
  - Conversion failures fail loudly (non-zero exit, converter output passed
    through); nothing is published unless the converter succeeded.
  - This script is stdlib-only on purpose: it must run in the slim sidecar
    image BEFORE `prepare` has built the venv.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

# ---------------------------------------------------------------------------
# Layout — everything hangs off the models PVC so it survives restarts.
# ---------------------------------------------------------------------------

MODELS_DIR = Path(os.environ.get("MODELS_DIR", "/models"))
TOOLS_ROOT = MODELS_DIR / ".tools"
VENV_DIR = TOOLS_ROOT / "venv"
CONVERTER_DIR = TOOLS_ROOT / "converter"
CYBER_DIR = TOOLS_ROOT / "cyber"
ADAPTER_DIR = CYBER_DIR / "adapter"
BASE_CONFIG_DIR = CYBER_DIR / "base-config"

# Where the chart mounts the read-only tool scripts (ConfigMap llama-swap-tools).
TOOLS_SRC = Path(os.environ.get("TOOLS_SRC", "/app/tools"))

# Vendored converter files as they appear in the ConfigMap (flat keys) mapped to
# their package layout under CONVERTER_DIR. The converter at llama.cpp b10015
# needs the repo-local `conversion` package AND the repo-local `gguf-py`
# package (PyPI's gguf stopped at 0.9.1; b10015 ships 0.19.0). The staged
# layout mirrors the llama.cpp tree so convert_lora_to_gguf.py's own
# `Path(__file__).parent / 'gguf-py'` probe finds it.
CONVERTER_FILES = {
    "convert_lora_to_gguf.py": Path("convert_lora_to_gguf.py"),
    "conversion__init__.py": Path("conversion/__init__.py"),
    "conversion__base.py": Path("conversion/base.py"),
    "conversion__qwen.py": Path("conversion/qwen.py"),
    "gguf_py__init__.py": Path("gguf-py/gguf/__init__.py"),
    "gguf_py__constants.py": Path("gguf-py/gguf/constants.py"),
    "gguf_py__gguf.py": Path("gguf-py/gguf/gguf.py"),
    "gguf_py__gguf_reader.py": Path("gguf-py/gguf/gguf_reader.py"),
    "gguf_py__gguf_writer.py": Path("gguf-py/gguf/gguf_writer.py"),
    "gguf_py__lazy.py": Path("gguf-py/gguf/lazy.py"),
    "gguf_py__metadata.py": Path("gguf-py/gguf/metadata.py"),
    "gguf_py__quants.py": Path("gguf-py/gguf/quants.py"),
    "gguf_py__tensor_mapping.py": Path("gguf-py/gguf/tensor_mapping.py"),
    "gguf_py__utility.py": Path("gguf-py/gguf/utility.py"),
    "gguf_py__vocab.py": Path("gguf-py/gguf/vocab.py"),
}

CYBER_ADAPTER_REPO = "nico248000000000/Qwen3.8-27B-Uncensored-cyber-LoRA"
CYBER_ADAPTER_FILES = ("adapter_config.json", "adapter_model.safetensors")
CYBER_BASE_REPO = "orcarouter/Qwen3.8-27B-Uncensored"
CYBER_BASE_FILES = ("config.json",)

CYBER_LORA_GGUF = MODELS_DIR / "qwen38-cyber-lora-f16.gguf"

# Explicitly downloadable artifacts (the `download` consent gate only accepts
# names listed here).
ARTIFACTS = {
    "rana-mtp": {
        "url": (
            "https://huggingface.co/aboliterant/Qwen3.8-27B-RANA-abliterated-GGUF"
            "/resolve/main/mtp-Qwen3.8-27B-RANA-abliterated-Q8_0.gguf"
        ),
        "dest": MODELS_DIR / "rana/mtp-Qwen3.8-27B-RANA-abliterated-Q8_0.gguf",
        "description": "RANA abliterated MTP draft model (Q8_0)",
    },
    "rana-mmproj": {
        "url": (
            "https://huggingface.co/aboliterant/Qwen3.8-27B-RANA-abliterated-GGUF"
            "/resolve/main/mmproj-Qwen3.8-27B-RANA-abliterated-F16.gguf"
        ),
        "dest": MODELS_DIR / "rana/mmproj-Qwen3.8-27B-RANA-abliterated-F16.gguf",
        "description": "RANA abliterated vision projector (F16)",
    },
}

# torch must come from the CPU wheel index; the sidecar has no GPU and the
# default PyPI torch wheel would drag in CUDA libraries. The gguf package is
# NOT pip-installed: b10015's converter needs the repo-local gguf-py 0.19.0,
# which is vendored in the chart and staged next to the converter.
TORCH_INDEX_URL = "https://download.pytorch.org/whl/cpu"
VENV_PACKAGES = ["transformers", "safetensors", "huggingface_hub", "numpy", "pyyaml", "tqdm"]

LLAMA_SWAP_URL = os.environ.get("LLAMA_SWAP_URL", "http://localhost:8080")

HF_API = "https://huggingface.co"


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

def log(msg: str) -> None:
    print(f"[llama-tools] {msg}", flush=True)


def hf_token() -> str | None:
    token = os.environ.get("HF_TOKEN", "").strip()
    return token or None


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_sha256(path: Path) -> str:
    digest = sha256_file(path)
    (path.parent / (path.name + ".sha256")).write_text(digest + "\n")
    return digest


def read_sha256(path: Path) -> str | None:
    sidecar = path.parent / (path.name + ".sha256")
    if not sidecar.exists():
        return None
    return sidecar.read_text().strip().split()[0]


def redact(text: str) -> str:
    """Belt-and-braces: never let the token reach stdout/stderr."""
    token = hf_token()
    if token:
        text = text.replace(token, "[REDACTED]")
    return text


def http_get(url: str, dest: Path, *, desc: str = "", auth: bool = True) -> None:
    """Download url to dest with temp-file + resume + atomic rename.

    The partial file lives at <dest>.part so an interrupted run can resume.
    The token is attached only for huggingface.co URLs and never logged.
    """
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        log(f"{desc or dest.name}: already present ({dest.stat().st_size} bytes), skipping")
        return

    tmp = dest.parent / (dest.name + ".part")
    resume_from = tmp.stat().st_size if tmp.exists() else 0

    headers = {"User-Agent": "llama-swap-tools/1.0"}
    token = hf_token()
    if auth and token and "huggingface.co" in url:
        headers["Authorization"] = f"Bearer {token}"
    if resume_from > 0:
        headers["Range"] = f"bytes={resume_from}-"
        log(f"{desc or dest.name}: resuming at byte {resume_from}")

    req = urllib.request.Request(url, headers=headers)
    try:
        resp = urllib.request.urlopen(req, timeout=60)
    except urllib.error.HTTPError as e:
        if e.code == 416 and resume_from > 0:
            # Range not satisfiable: the partial file is already complete.
            log(f"{desc or dest.name}: partial file already complete, finalizing")
            os.replace(tmp, dest)
            return
        if e.code == 401:
            raise SystemExit(
                f"[llama-tools] ERROR: 401 Unauthorized for {url} — this repo needs an "
                "HF token (HF_TOKEN env) and, for gated repos, accepted license terms."
            ) from e
        raise SystemExit(f"[llama-tools] ERROR: HTTP {e.code} for {url}") from e

    mode = "ab" if (resume_from > 0 and resp.status == 206) else "wb"
    if mode == "wb" and resume_from > 0:
        log(f"{desc or dest.name}: server ignored Range, restarting download")

    total = 0
    with open(tmp, mode) as f:
        while True:
            chunk = resp.read(8 * 1024 * 1024)
            if not chunk:
                break
            f.write(chunk)
            total += len(chunk)
    log(f"{desc or dest.name}: downloaded {total} bytes (now {tmp.stat().st_size})")

    os.replace(tmp, dest)  # atomic publish
    digest = write_sha256(dest)
    log(f"{desc or dest.name}: published sha256={digest[:16]}...")


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_status(_: argparse.Namespace) -> int:
    log("Provisioning status")
    log(f"  models dir: {MODELS_DIR} ({'exists' if MODELS_DIR.exists() else 'MISSING'})")

    def report(name: str, path: Path) -> bool:
        if not path.exists():
            log(f"  [missing ] {name}: {path}")
            return False
        digest = read_sha256(path)
        state = "ok" if digest else "present (no sha256 record)"
        log(f"  [present ] {name}: {path} ({path.stat().st_size} bytes, {state})")
        return True

    ok = True
    ok &= report("cyber LoRA GGUF (converted)", CYBER_LORA_GGUF)
    for key, art in ARTIFACTS.items():
        ok &= report(f"artifact {key}", Path(art["dest"]))

    log("  Tooling:")
    log(f"    venv:      {'ready' if (VENV_DIR / 'bin/python').exists() else 'not prepared (run: prepare)'}")
    staged = all((CONVERTER_DIR / dst).exists() for dst in CONVERTER_FILES.values())
    log(f"    converter: {'staged' if staged else 'not staged (run: prepare)'}")
    adapter = all((ADAPTER_DIR / f).exists() for f in CYBER_ADAPTER_FILES)
    log(f"    adapter:   {'fetched' if adapter else 'not fetched (run: prepare)'}")
    base = all((BASE_CONFIG_DIR / f).exists() for f in CYBER_BASE_FILES)
    log(f"    base cfg:  {'fetched' if base else 'not fetched (run: prepare)'}")
    log(f"  HF_TOKEN:    {'set' if hf_token() else 'NOT SET (gated repos will fail)'}")

    if ok:
        log("All runtime artifacts present.")
    else:
        log("Some artifacts are missing — see commands above. (This never blocks the pod.)")
    return 0


def ensure_venv() -> Path:
    py = VENV_DIR / "bin/python"
    if py.exists():
        log(f"venv exists at {VENV_DIR}, reusing")
        return VENV_DIR
    log(f"creating venv at {VENV_DIR}")
    TOOLS_ROOT.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, "-m", "venv", str(VENV_DIR)], check=True)
    log("installing torch (CPU wheel — this is the large one)")
    subprocess.run(
        [str(py), "-m", "pip", "install", "--quiet", "torch",
         "--index-url", TORCH_INDEX_URL],
        check=True,
    )
    log(f"installing {', '.join(VENV_PACKAGES)}")
    subprocess.run(
        [str(py), "-m", "pip", "install", "--quiet", *VENV_PACKAGES],
        check=True,
    )
    return VENV_DIR


def stage_converter() -> None:
    log(f"staging converter from {TOOLS_SRC} -> {CONVERTER_DIR}")
    for src_name, dst in CONVERTER_FILES.items():
        src = TOOLS_SRC / src_name
        if not src.exists():
            raise SystemExit(
                f"[llama-tools] ERROR: {src} missing — is the llama-swap-tools "
                "ConfigMap mounted at /app/tools?"
            )
        target = CONVERTER_DIR / dst
        target.parent.mkdir(parents=True, exist_ok=True)
        # Stage via temp + rename so a half-copied file never survives.
        fd, tmp_name = tempfile.mkstemp(dir=target.parent, prefix=f".{target.name}.")
        os.close(fd)
        shutil.copyfile(src, tmp_name)
        os.replace(tmp_name, target)
    log("converter staged")


def cmd_prepare(_: argparse.Namespace) -> int:
    ensure_venv()
    stage_converter()

    for name in CYBER_ADAPTER_FILES:
        http_get(
            f"{HF_API}/{CYBER_ADAPTER_REPO}/resolve/main/{name}",
            ADAPTER_DIR / name,
            desc=f"adapter {name}",
        )
    for name in CYBER_BASE_FILES:
        http_get(
            f"{HF_API}/{CYBER_BASE_REPO}/resolve/main/{name}",
            BASE_CONFIG_DIR / name,
            desc=f"base model {name}",
        )
    log("prepare complete: venv ready, converter staged, adapter + base config fetched")
    log("next: llama_tools.py convert-cyber")
    return 0


def cmd_convert_cyber(_: argparse.Namespace) -> int:
    missing = [
        what
        for what, present in (
            (f"venv (run prepare)", (VENV_DIR / "bin/python").exists()),
            ("converter (run prepare)", (CONVERTER_DIR / "convert_lora_to_gguf.py").exists()),
            (f"adapter in {ADAPTER_DIR} (run prepare)",
             all((ADAPTER_DIR / f).exists() for f in CYBER_ADAPTER_FILES)),
            (f"base config in {BASE_CONFIG_DIR} (run prepare)",
             all((BASE_CONFIG_DIR / f).exists() for f in CYBER_BASE_FILES)),
        )
        if not present
    ]
    if missing:
        log("ERROR: cannot convert, missing: " + "; ".join(missing))
        return 1

    outfile = MODELS_DIR / ".qwen38-cyber-lora-f16.tmp"
    if outfile.exists():
        outfile.unlink()  # never publish over a stale partial conversion

    cmd = [
        str(VENV_DIR / "bin/python"),
        str(CONVERTER_DIR / "convert_lora_to_gguf.py"),
        "--outtype", "f16",
        "--base", str(BASE_CONFIG_DIR),
        "--outfile", str(outfile),
        str(ADAPTER_DIR),
    ]
    env = dict(os.environ)
    env["PYTHONPATH"] = str(CONVERTER_DIR) + os.pathsep + env.get("PYTHONPATH", "")
    # gguf resolves via the vendored gguf-py staged under CONVERTER_DIR (the
    # converter script probes for it next to itself); no NO_LOCAL_GGUF here.
    log("running vendored convert_lora_to_gguf.py (b10015)")
    proc = subprocess.run(cmd, env=env)
    if proc.returncode != 0:
        if outfile.exists():
            outfile.unlink()
        log(f"ERROR: converter exited {proc.returncode} — nothing published")
        return proc.returncode

    os.replace(outfile, CYBER_LORA_GGUF)  # atomic publish
    digest = write_sha256(CYBER_LORA_GGUF)
    log(f"published {CYBER_LORA_GGUF} ({CYBER_LORA_GGUF.stat().st_size} bytes)")
    log(f"sha256={digest}")
    log("next: llama_tools.py verify, then enable qwen38-cyber in values.yaml (phase 2)")
    return 0


def cmd_download(args: argparse.Namespace) -> int:
    art = ARTIFACTS.get(args.artifact)
    if art is None:  # pragma: no cover - argparse choices guard this
        raise SystemExit(f"[llama-tools] unknown artifact {args.artifact!r}")
    dest = Path(art["dest"])
    if dest.exists() and not args.force:
        log(f"{args.artifact}: already present at {dest} (use --force to re-download)")
        return 0
    if dest.exists():
        dest.unlink()
    http_get(art["url"], dest, desc=args.artifact)
    return 0


def cmd_verify(_: argparse.Namespace) -> int:
    failures = 0
    targets = [CYBER_LORA_GGUF, *(Path(a["dest"]) for a in ARTIFACTS.values())]
    for path in targets:
        if not path.exists():
            log(f"[skip   ] {path} — not provisioned")
            continue
        size = path.stat().st_size
        if size == 0:
            log(f"[FAIL   ] {path} — empty file")
            failures += 1
            continue
        expected = read_sha256(path)
        if expected is None:
            log(f"[warn   ] {path} — present ({size} bytes) but no sha256 record")
            continue
        actual = sha256_file(path)
        if actual != expected:
            log(f"[FAIL   ] {path} — sha256 mismatch (expected {expected[:16]}..., got {actual[:16]}...)")
            failures += 1
        else:
            log(f"[ok     ] {path} — {size} bytes, sha256 matches")
    if failures:
        log(f"verify: {failures} artifact(s) FAILED")
        return 1
    log("verify: all present artifacts pass")
    return 0


def cmd_smoke_test(args: argparse.Namespace) -> int:
    model = args.model
    try:
        with urllib.request.urlopen(f"{LLAMA_SWAP_URL}/v1/models", timeout=30) as resp:
            models = json.load(resp)
    except Exception as e:  # noqa: BLE001 — report any connectivity failure verbatim
        log(f"ERROR: cannot reach llama-swap at {LLAMA_SWAP_URL}: {e}")
        return 1
    ids = [m.get("id") for m in models.get("data", [])]
    if model in ids:
        log(f"model {model!r} listed ({len(ids)} models total)")
    else:
        log(f"ERROR: model {model!r} NOT in /v1/models; available: {', '.join(sorted(ids))}")
        return 1

    payload = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": "Reply with exactly: OK"}],
        "max_tokens": 16,
        "stream": False,
    }).encode()
    req = urllib.request.Request(
        f"{LLAMA_SWAP_URL}/v1/chat/completions",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    log(f"requesting a tiny chat completion from {model!r} (may trigger a cold load)...")
    try:
        with urllib.request.urlopen(req, timeout=3600) as resp:
            completion = json.load(resp)
    except Exception as e:  # noqa: BLE001
        log(f"ERROR: chat completion failed: {e}")
        return 1
    choice = (completion.get("choices") or [{}])[0]
    text = (choice.get("message") or {}).get("content", "")
    log(f"smoke-test response: {text[:200]!r}")
    log("smoke-test complete")
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="llama_tools.py",
        description="Operator provisioning tools for llama-swap (gpu-ai). "
                    "Nothing here runs automatically.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status", help="report provisioning state").set_defaults(func=cmd_status)
    sub.add_parser("prepare", help="venv + converter + adapter staging").set_defaults(func=cmd_prepare)
    sub.add_parser("convert-cyber", help="convert the staged LoRA adapter to GGUF").set_defaults(func=cmd_convert_cyber)

    p_dl = sub.add_parser("download", help="fetch one explicitly named artifact")
    p_dl.add_argument("artifact", choices=sorted(ARTIFACTS),
                      help="artifact to download (required — consent gate)")
    p_dl.add_argument("--force", action="store_true", help="re-download even if present")
    p_dl.set_defaults(func=cmd_download)

    sub.add_parser("verify", help="size + sha256 checks").set_defaults(func=cmd_verify)

    p_smoke = sub.add_parser("smoke-test", help="pod-local llama-swap smoke check")
    p_smoke.add_argument("model", help="model ID to hit (e.g. qwen38-orca)")
    p_smoke.set_defaults(func=cmd_smoke_test)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001 — last-resort redaction of any message
        print(redact(f"[llama-tools] ERROR: {e}"), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())