#!/usr/bin/env python3
"""Run the bundled library without an editable install or third-party packages."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "src"))
from oke_llm_serving.cli import main

raise SystemExit(main(["terraform"]))
