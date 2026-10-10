# Tests for charts/llama-swap/scripts/llama_tools.py
#
# Contract: atomic publish, interrupted-download resume, credential redaction,
# the download consent gate, and status/verify logic. All offline — network
# downloads are simulated with a local HTTP server (Range support included).

from __future__ import annotations

import hashlib
import http.server
import importlib
import io
import json
import os
import sys
import threading
from contextlib import redirect_stdout
from pathlib import Path

import pytest

CHART_DIR = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = CHART_DIR / "scripts"

sys.path.insert(0, str(SCRIPTS_DIR))
import llama_tools  # noqa: E402


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

PAYLOAD = bytes(range(256)) * 4096  # 1 MiB of deterministic bytes


@pytest.fixture()
def workspace(tmp_path, monkeypatch):
    """Redirect every llama_tools path constant into a tmp dir."""
    models = tmp_path / "models"
    models.mkdir()
    tools_src = tmp_path / "tools-src"
    tools_src.mkdir()

    monkeypatch.setattr(llama_tools, "MODELS_DIR", models)
    monkeypatch.setattr(llama_tools, "TOOLS_ROOT", models / ".tools")
    monkeypatch.setattr(llama_tools, "VENV_DIR", models / ".tools/venv")
    monkeypatch.setattr(llama_tools, "CONVERTER_DIR", models / ".tools/converter")
    monkeypatch.setattr(llama_tools, "CYBER_DIR", models / ".tools/cyber")
    monkeypatch.setattr(llama_tools, "ADAPTER_DIR", models / ".tools/cyber/adapter")
    monkeypatch.setattr(llama_tools, "BASE_CONFIG_DIR", models / ".tools/cyber/base-config")
    monkeypatch.setattr(llama_tools, "CYBER_LORA_GGUF", models / "qwen38-cyber-lora-f16.gguf")
    monkeypatch.setattr(llama_tools, "TOOLS_SRC", tools_src)
    monkeypatch.setattr(llama_tools, "ARTIFACTS", {
        "rana-mtp": {
            "url": "https://example.invalid/rana/mtp.gguf",
            "dest": models / "rana/mtp.gguf",
            "description": "test artifact",
        },
    })
    monkeypatch.delenv("HF_TOKEN", raising=False)
    return models


class RangeHandler(http.server.BaseHTTPRequestHandler):
    """Serves PAYLOAD with Range support; records seen headers."""

    seen_headers: list[dict] = []
    payload: bytes = PAYLOAD
    fail_after: int | None = None  # cut the connection mid-body (resume test)

    def log_message(self, *args):  # silence test output
        pass

    def do_GET(self):
        RangeHandler.seen_headers.append(dict(self.headers))
        start = 0
        rng = self.headers.get("Range")
        if rng and rng.startswith("bytes="):
            start = int(rng.split("=")[1].split("-")[0])
        body = self.payload[start:]
        if self.fail_after is not None and start == 0:
            body = body[: self.fail_after]
        status = 206 if start > 0 else 200
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        if status == 206:
            self.send_header(
                "Content-Range", f"bytes {start}-{len(self.payload)-1}/{len(self.payload)}"
            )
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass


@pytest.fixture()
def http_server():
    RangeHandler.seen_headers = []
    RangeHandler.fail_after = None
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), RangeHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield f"http://127.0.0.1:{server.server_address[1]}"
    server.shutdown()


# ---------------------------------------------------------------------------
# http_get: atomic publish + resume + redaction
# ---------------------------------------------------------------------------

def test_atomic_publish(workspace, http_server):
    dest = workspace / "downloads/model.gguf"
    llama_tools.http_get(f"{http_server}/model.gguf", dest, auth=False)

    assert dest.exists()
    assert dest.read_bytes() == PAYLOAD
    assert not (workspace / "downloads/model.gguf.part").exists(), "temp file must not survive"
    sidecar = dest.parent / (dest.name + ".sha256")
    assert sidecar.exists()
    assert sidecar.read_text().split()[0] == hashlib.sha256(PAYLOAD).hexdigest()


def test_interrupted_download_resumes(workspace, http_server):
    dest = workspace / "downloads/model.gguf"
    dest.parent.mkdir(parents=True, exist_ok=True)

    # Simulate an interrupted download: half the payload already in the .part file.
    half = len(PAYLOAD) // 2
    (dest.parent / (dest.name + ".part")).write_bytes(PAYLOAD[:half])

    llama_tools.http_get(f"{http_server}/model.gguf", dest, auth=False)

    assert dest.read_bytes() == PAYLOAD
    ranges = [h.get("Range") for h in RangeHandler.seen_headers if h.get("Range")]
    assert ranges == [f"bytes={half}-"], "second attempt must resume via Range"


def test_existing_dest_is_skipped(workspace, http_server, monkeypatch):
    dest = workspace / "downloads/model.gguf"
    dest.parent.mkdir(parents=True)
    dest.write_bytes(b"already here")

    def explode(*a, **k):
        raise AssertionError("must not hit the network for an existing artifact")

    monkeypatch.setattr(llama_tools.urllib.request, "urlopen", explode)
    llama_tools.http_get(f"{http_server}/model.gguf", dest, auth=False)
    assert dest.read_bytes() == b"already here"


def test_hf_token_sent_only_to_huggingface(workspace, monkeypatch):
    monkeypatch.setenv("HF_TOKEN", "hf_supersecret_123")
    captured: dict = {}

    class FakeResp(io.BytesIO):
        status = 200

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

    def fake_urlopen(req, timeout=None):
        captured["url"] = req.full_url
        captured["auth"] = req.get_header("Authorization")
        return FakeResp(b"xyz")

    monkeypatch.setattr(llama_tools.urllib.request, "urlopen", fake_urlopen)

    dest = workspace / "d/file.bin"
    llama_tools.http_get("https://huggingface.co/org/repo/resolve/main/file.bin", dest)
    assert captured["auth"] == "Bearer hf_supersecret_123"

    captured.clear()
    dest2 = workspace / "d/file2.bin"
    llama_tools.http_get("https://example.com/file2.bin", dest2)
    assert captured["auth"] is None, "token must never leave huggingface.co"


def test_token_never_appears_in_output(workspace, monkeypatch, http_server, capsys):
    token = "hf_supersecret_123"
    monkeypatch.setenv("HF_TOKEN", token)

    dest = workspace / "downloads/model.gguf"
    llama_tools.http_get(f"{http_server}/model.gguf", dest, desc="model", auth=False)
    out = capsys.readouterr().out
    assert token not in out
    assert "[REDACTED]" not in out  # nothing sensitive was even referenced

    # redact() masks the token if it ever sneaks into a message
    assert llama_tools.redact(f"error with {token} in it") == "error with [REDACTED] in it"


def test_http_401_exits_with_actionable_error(workspace, monkeypatch):
    import urllib.error

    def fake_urlopen(req, timeout=None):
        raise urllib.error.HTTPError(req.full_url, 401, "Unauthorized", {}, None)

    monkeypatch.setattr(llama_tools.urllib.request, "urlopen", fake_urlopen)
    dest = workspace / "downloads/gated.gguf"
    with pytest.raises(SystemExit, match="401 Unauthorized"):
        llama_tools.http_get("https://huggingface.co/org/repo/resolve/main/gated.gguf", dest)
    assert not dest.exists()


# ---------------------------------------------------------------------------
# download: consent gate
# ---------------------------------------------------------------------------

def test_download_requires_explicit_artifact(workspace, monkeypatch):
    def explode(*a, **k):
        raise AssertionError("download must refuse to run without an artifact name")

    monkeypatch.setattr(llama_tools, "http_get", explode)

    with pytest.raises(SystemExit) as ei:
        llama_tools.main(["download"])
    assert ei.value.code == 2, "argparse must reject a missing artifact"

    with pytest.raises(SystemExit) as ei:
        llama_tools.main(["download", "not-a-real-artifact"])
    assert ei.value.code == 2, "argparse must reject unknown artifacts"


def test_download_named_artifact(workspace, monkeypatch):
    fetched: list = []
    monkeypatch.setattr(
        llama_tools, "http_get", lambda url, dest, desc="": fetched.append((url, Path(dest)))
    )
    rc = llama_tools.main(["download", "rana-mtp"])
    assert rc == 0
    assert fetched == [("https://example.invalid/rana/mtp.gguf", workspace / "rana/mtp.gguf")]


def test_download_refuses_overwrite_without_force(workspace, monkeypatch):
    art = llama_tools.ARTIFACTS["rana-mtp"]
    dest = Path(art["dest"])
    dest.parent.mkdir(parents=True)
    dest.write_bytes(b"existing")

    monkeypatch.setattr(
        llama_tools, "http_get",
        lambda *a, **k: (_ for _ in ()).throw(AssertionError("must not re-download")),
    )
    rc = llama_tools.main(["download", "rana-mtp"])
    assert rc == 0
    assert dest.read_bytes() == b"existing"


# ---------------------------------------------------------------------------
# status / verify
# ---------------------------------------------------------------------------

def test_status_reports_missing_then_present(workspace, capsys):
    rc = llama_tools.main(["status"])
    assert rc == 0
    out = capsys.readouterr().out
    assert "missing" in out and "qwen38-cyber-lora-f16.gguf" in out

    # provision everything status checks for
    lora = llama_tools.CYBER_LORA_GGUF
    lora.write_bytes(b"gguf-bytes")
    llama_tools.write_sha256(lora)
    art = llama_tools.ARTIFACTS["rana-mtp"]
    Path(art["dest"]).parent.mkdir(parents=True)
    Path(art["dest"]).write_bytes(b"mtp-bytes")

    rc = llama_tools.main(["status"])
    assert rc == 0
    out = capsys.readouterr().out
    assert "All runtime artifacts present" in out


def test_verify_passes_on_good_artifacts(workspace):
    lora = llama_tools.CYBER_LORA_GGUF
    lora.write_bytes(b"gguf-bytes")
    llama_tools.write_sha256(lora)
    assert llama_tools.main(["verify"]) == 0


def test_verify_fails_on_corruption(workspace):
    lora = llama_tools.CYBER_LORA_GGUF
    lora.write_bytes(b"gguf-bytes")
    llama_tools.write_sha256(lora)
    lora.write_bytes(b"corrupted!")
    assert llama_tools.main(["verify"]) == 1


def test_verify_fails_on_empty_file(workspace):
    lora = llama_tools.CYBER_LORA_GGUF
    lora.write_bytes(b"")
    assert llama_tools.main(["verify"]) == 1


def test_verify_skips_missing(workspace):
    assert llama_tools.main(["verify"]) == 0  # nothing provisioned yet is not a failure


# ---------------------------------------------------------------------------
# prepare / stage (converter fetched from pinned URLs, sha256-verified)
# ---------------------------------------------------------------------------

def _write_provenance(files: dict[str, bytes], base_url: str, pins: dict[str, str] | None = None):
    """Write a converter-source.json pointing raw_url_pattern at base_url.

    files maps rel-path -> bytes the fake server will return (all served as
    PAYLOAD by RangeHandler, so content pins default to sha256(PAYLOAD)).
    pins optionally overrides the sha256 for a rel-path (to force a mismatch).
    """
    entries = {}
    for rel in files:
        upstream = "LICENSE" if rel == "LLAMA_CPP_LICENSE" else rel
        default = hashlib.sha256(PAYLOAD).hexdigest()
        entries[rel] = {"upstream_path": upstream, "sha256": (pins or {}).get(rel, default)}
    prov = {
        "repository": "https://github.com/ggml-org/llama.cpp",
        "tag": "b11515",
        "commit": "12127defda4f41b7679cb2477a4b0d65ee6a0c8f",
        "raw_url_pattern": base_url.rstrip("/") + "/{path}",
        "files": entries,
    }
    (llama_tools.TOOLS_SRC / llama_tools.PROVENANCE_FILE).write_text(json.dumps(prov))
    return prov


def test_stage_converter_fetches_verifies_and_lays_out(workspace, http_server):
    rels = ["convert_lora_to_gguf.py", "conversion/base.py", "gguf-py/gguf/__init__.py",
            "LLAMA_CPP_LICENSE"]
    _write_provenance({r: PAYLOAD for r in rels}, http_server)

    llama_tools.stage_converter()

    conv = llama_tools.CONVERTER_DIR
    # runtime files staged at their llama.cpp-tree layout, byte-exact
    assert (conv / "convert_lora_to_gguf.py").read_bytes() == PAYLOAD
    assert (conv / "conversion/base.py").read_bytes() == PAYLOAD
    assert (conv / "gguf-py/gguf/__init__.py").read_bytes() == PAYLOAD
    # the license is attribution-only and must NOT be staged
    assert not (conv / "LICENSE").exists()
    assert not (conv / "LLAMA_CPP_LICENSE").exists()
    # every staged file got a sha256 sidecar
    assert (conv / "convert_lora_to_gguf.py.sha256").exists()
    assert not any(p.name.endswith(".part") for p in conv.rglob("*")), "no temp files left"


def test_stage_converter_is_idempotent(workspace, http_server):
    _write_provenance({"convert_lora_to_gguf.py": PAYLOAD}, http_server)
    llama_tools.stage_converter()
    requests_first = len(RangeHandler.seen_headers)

    # second run: file present + hash matches pin -> no network hit
    llama_tools.stage_converter()
    assert len(RangeHandler.seen_headers) == requests_first, \
        "a hash-matching staged file must be reused, not re-downloaded"


def test_stage_converter_rejects_sha256_mismatch(workspace, http_server):
    # pin a hash the served PAYLOAD will not match
    _write_provenance({"convert_lora_to_gguf.py": PAYLOAD}, http_server,
                      pins={"convert_lora_to_gguf.py": "0" * 64})
    with pytest.raises(SystemExit, match="sha256 mismatch"):
        llama_tools.stage_converter()
    assert not (llama_tools.CONVERTER_DIR / "convert_lora_to_gguf.py").exists(), \
        "a mismatched file must not be published"
    assert not (llama_tools.CONVERTER_DIR / "convert_lora_to_gguf.py.part").exists()


def test_stage_converter_redownloads_tampered_file(workspace, http_server):
    _write_provenance({"convert_lora_to_gguf.py": PAYLOAD}, http_server)
    dest = llama_tools.CONVERTER_DIR / "convert_lora_to_gguf.py"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(b"tampered on disk")

    llama_tools.stage_converter()  # detects hash mismatch, re-fetches
    assert dest.read_bytes() == PAYLOAD


def test_stage_converter_fails_loudly_without_configmap(workspace, capsys):
    with pytest.raises(SystemExit, match="ConfigMap"):
        llama_tools.stage_converter()


def test_convert_cyber_requires_prepared_state(workspace):
    rc = llama_tools.main(["convert-cyber"])
    assert rc == 1, "convert-cyber must refuse to run before prepare"
