#!/usr/bin/env python3
"""Terraform external entry point; requires the repository bundle and OCI extra."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "src"))
from oke_llm_serving.cli import main

raise SystemExit(main(["terraform-oci"]))
