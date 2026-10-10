# Contract test for the vendored b11515 convert_lora_to_gguf.py subset.
#
# Builds a synthetic PEFT LoRA adapter (tiny Qwen3-shaped safetensors) plus a
# minimal base config.json, runs the vendored script end-to-end, and asserts a
# GGUF comes out with the LoRA tensors preserved. No network access.
#
# Requires the converter's real dependencies (torch, transformers, safetensors,
# gguf) — skipped when they are not installed (see the GitHub workflow, which
# installs them).

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

CHART_DIR = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = CHART_DIR / "scripts"
CONVERTER = SCRIPTS_DIR / "convert_lora_to_gguf.py"

# Read outputs with the SAME gguf package the converter writes with: the
# repo-local gguf-py 0.19.0 vendored under scripts/ (PyPI gguf is older and
# lacks the arch constants b11515 uses).
sys.path.insert(0, str(SCRIPTS_DIR / "gguf-py"))
sys.path.insert(0, str(SCRIPTS_DIR))

pytestmark = pytest.mark.skipif(
    any(importlib.util.find_spec(m) is None for m in ("torch", "transformers", "safetensors")),
    reason="converter dependencies (torch/transformers/safetensors) not installed",
)

HIDDEN = 64
HEADS = 4
HEAD_DIM = 16
LAYERS = 2
VOCAB = 32
R = 4  # lora rank


@pytest.fixture(scope="module")
def adapter_env(tmp_path_factory):
    """Synthetic base config + PEFT adapter on disk; returns (base_dir, adapter_dir)."""
    import torch
    from safetensors.torch import save_file

    root = tmp_path_factory.mktemp("lora")
    base_dir = root / "base-config"
    base_dir.mkdir()
    adapter_dir = root / "adapter"
    adapter_dir.mkdir()

    config = {
        "architectures": ["Qwen3ForCausalLM"],
        "model_type": "qwen3",
        "hidden_size": HIDDEN,
        "intermediate_size": HIDDEN * 2,
        "num_hidden_layers": LAYERS,
        "num_attention_heads": HEADS,
        "num_key_value_heads": HEADS,
        "head_dim": HEAD_DIM,
        "vocab_size": VOCAB,
        "max_position_embeddings": 512,
        "rms_norm_eps": 1e-6,
        "rope_theta": 1000000.0,
        "tie_word_embeddings": False,
    }
    (base_dir / "config.json").write_text(json.dumps(config))

    (adapter_dir / "adapter_config.json").write_text(json.dumps({
        "peft_type": "LORA",
        "auto_mapping": {"base_model_class": "Qwen3ForCausalLM"},
        "base_model_name_or_path": "synthetic/qwen3-tiny",
        "r": R,
        "lora_alpha": 2 * R,
        "lora_dropout": 0.0,
        "target_modules": ["q_proj", "k_proj", "v_proj", "o_proj"],
        "task_type": "CAUSAL_LM",
        "bias": "none",
        "use_dora": False,
    }))

    torch.manual_seed(7)
    tensors = {}
    for i in range(LAYERS):
        for proj in ("q_proj", "k_proj", "v_proj", "o_proj"):
            prefix = f"base_model.model.model.layers.{i}.self_attn.{proj}"
            tensors[f"{prefix}.lora_A.weight"] = torch.randn(R, HIDDEN) * 0.02
            tensors[f"{prefix}.lora_B.weight"] = torch.randn(HIDDEN, R) * 0.02
    save_file(tensors, str(adapter_dir / "adapter_model.safetensors"))
    return base_dir, adapter_dir


def run_converter(base_dir: Path, adapter_dir: Path, outfile: Path) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env["PYTHONPATH"] = str(SCRIPTS_DIR) + os.pathsep + env.get("PYTHONPATH", "")
    return subprocess.run(
        [
            sys.executable, str(CONVERTER),
            "--outtype", "f16",
            "--base", str(base_dir),
            "--outfile", str(outfile),
            str(adapter_dir),
        ],
        env=env,
        capture_output=True,
        text=True,
        timeout=600,
    )


def test_vendored_subset_is_complete():
    """The lazy-import subset must cover the Qwen3 architecture end to end,
    including the repo-local gguf-py package the b11515 converter requires."""
    for rel in ("convert_lora_to_gguf.py", "conversion/__init__.py",
                "conversion/base.py", "conversion/qwen.py",
                "gguf-py/gguf/__init__.py", "gguf-py/gguf/constants.py",
                "gguf-py/gguf/gguf_writer.py", "gguf-py/gguf/tensor_mapping.py"):
        assert (SCRIPTS_DIR / rel).exists(), f"vendored file missing: {rel}"
    import gguf
    assert hasattr(gguf.MODEL_ARCH, "DFLASH"), \
        "imported gguf is not the vendored b11515 gguf-py (0.19.0)"


def test_converts_synthetic_adapter(adapter_env, tmp_path):
    base_dir, adapter_dir = adapter_env
    outfile = tmp_path / "lora.gguf"

    proc = run_converter(base_dir, adapter_dir, outfile)
    assert proc.returncode == 0, f"converter failed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
    assert outfile.exists() and outfile.stat().st_size > 0

    import gguf

    reader = gguf.GGUFReader(outfile, "r")

    fields = {f.name: f for f in reader.fields.values()}
    assert "general.architecture" in fields
    arch = bytes(fields["general.architecture"].parts[-1]).decode()
    assert arch == "qwen3"
    # adapter metadata written by the converter's set_type/set_gguf_parameters
    assert "adapter.type" in fields
    assert bytes(fields["adapter.type"].parts[-1]).decode() == "lora"
    assert "adapter.lora.alpha" in fields
    assert float(fields["adapter.lora.alpha"].parts[-1][0]) == pytest.approx(2 * R)

    names = {t.name for t in reader.tensors}
    # b11515 tensor naming includes the .weight segment: blk.N.attn_q.weight.lora_a
    for i in range(LAYERS):
        for proj in ("attn_q", "attn_k", "attn_v", "attn_output"):
            assert f"blk.{i}.{proj}.weight.lora_a" in names, \
                f"missing blk.{i}.{proj}.weight.lora_a in {sorted(names)[:20]}"
            assert f"blk.{i}.{proj}.weight.lora_b" in names
    # every A/B pair present, nothing silently dropped
    lora_tensors = {n for n in names if n.endswith((".lora_a", ".lora_b"))}
    assert len(lora_tensors) == LAYERS * 4 * 2, f"expected all LoRA pairs, got {sorted(lora_tensors)}"


def test_fails_loudly_on_non_lora_tensor(adapter_env, tmp_path):
    """An unexpected tensor (neither lora_A/lora_B nor norm) must abort the
    conversion — the converter exits non-zero instead of dropping it silently."""
    import torch
    from safetensors.torch import save_file

    base_dir, adapter_dir = adapter_env
    bad_dir = tmp_path / "bad-adapter"
    bad_dir.mkdir()
    (bad_dir / "adapter_config.json").write_bytes((adapter_dir / "adapter_config.json").read_bytes())
    save_file(
        {"base_model.model.model.layers.0.mystery.weight": torch.randn(HIDDEN, HIDDEN)},
        str(bad_dir / "adapter_model.safetensors"),
    )

    outfile = tmp_path / "bad.gguf"
    proc = run_converter(base_dir, bad_dir, outfile)
    assert proc.returncode != 0
    assert "Unexpected name" in (proc.stderr + proc.stdout)
    assert not outfile.exists(), "nothing may be published on failure"
