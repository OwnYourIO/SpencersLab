import sys
from pathlib import Path

# The suite reuses charts/llama-swap/tests/llama_swap_testlib.py (outer-config
# renders, matrix helpers) instead of duplicating the render harness; pytest
# only auto-inserts each test file's own directory into sys.path.
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "llama-swap" / "tests"))
