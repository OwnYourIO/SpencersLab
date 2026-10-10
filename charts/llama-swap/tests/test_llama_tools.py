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
# prepare / stage
# ---------------------------------------------------------------------------

def test_stage_converter_maps_flat_keys_to_package_layout(workspace):
    src = llama_tools.TOOLS_SRC
    for name in llama_tools.CONVERTER_FILES:
        (src / name).write_text(f"content of {name}")

    llama_tools.stage_converter()

    conv = llama_tools.CONVERTER_DIR
    for name, rel in llama_tools.CONVERTER_FILES.items():
        assert (conv / rel).read_text() == f"content of {name}", f"bad staging for {name}"
    # spot-check the two package layouts the converter probes at runtime
    assert (conv / "conversion/__init__.py").exists()
    assert (conv / "gguf-py/gguf/__init__.py").exists()
    assert not any(p.name.startswith(".") for p in conv.rglob("*") if p.is_file()), \
        "no staging temp files left"


def test_stage_converter_fails_loudly_without_configmap(workspace, capsys):
    with pytest.raises(SystemExit, match="ConfigMap"):
        llama_tools.stage_converter()


def test_convert_cyber_requires_prepared_state(workspace):
    rc = llama_tools.main(["convert-cyber"])
    assert rc == 1, "convert-cyber must refuse to run before prepare"
