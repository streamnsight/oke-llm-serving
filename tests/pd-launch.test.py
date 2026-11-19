#!/usr/bin/env python3
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
"""Execute the native launcher against fake bundled SDK/connector/CLI modules."""
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "modules/llm-deployment/model-delivery/chart/files/pd-launch.sh"
SHA = "a" * 40
DENSE = {"model_type": "qwen3", "architectures": ["Qwen3ForCausalLM"],
         "num_hidden_layers": 2, "layer_types": ["full_attention", "full_attention"]}


class LauncherFixture:
    def __init__(self, config):
        self.temp = tempfile.TemporaryDirectory(prefix="native-pd-launch-")
        self.path = pathlib.Path(self.temp.name)
        site = self.path / "site"
        files = {
            "huggingface_hub/__init__.py": '''import json, os
def hf_hub_download(**kwargs):
    with open(os.environ["HF_CAPTURE"], "w") as output: json.dump(kwargs, output)
    if os.environ.get("HF_FAIL"): raise RuntimeError(os.environ["PRIVATE_TEST_TOKEN"])
    return os.environ["RAW_CONFIG_PATH"]
''',
            "nixl.py": "",
            "vllm/__init__.py": "",
            "vllm/config.py": "class KVTransferConfig:\n    def __init__(self, **kwargs): pass\n",
            "vllm/distributed/__init__.py": "",
            "vllm/distributed/kv_transfer/__init__.py": "",
            "vllm/distributed/kv_transfer/kv_connector/__init__.py": "",
            "vllm/distributed/kv_transfer/kv_connector/factory.py": '''import os
class KVConnectorFactory:
    @staticmethod
    def get_connector_class(config):
        if os.environ.get("CONNECTOR_FAIL"): raise ImportError("fixture connector unavailable")
        return object
''',
            "vllm-0.32.0.dist-info/METADATA": "Name: vllm\nVersion: 0.32.0\n",
            "nixl-1.0.0.dist-info/METADATA": "Name: nixl\nVersion: 1.0.0\n",
        }
        for relative, content in files.items():
            target = site / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
        binary = self.path / "bin/vllm"
        binary.parent.mkdir()
        binary.write_text(f"#!{sys.executable}\nimport json, os, sys\nwith open(os.environ['ARGV_CAPTURE'], 'w') as output: json.dump(sys.argv[1:], output)\n")
        binary.chmod(0o755)
        self.raw = json.dumps(config).encode()
        blob = self.path / "cache/blobs/config"
        blob.parent.mkdir(parents=True)
        blob.write_bytes(self.raw)
        self.config = self.path / "cache/snapshots" / SHA / "config.json"
        self.config.parent.mkdir(parents=True)
        self.config.symlink_to(blob)
        self.env = {**os.environ, "PATH": f"{binary.parent}:{os.environ['PATH']}",
                    "PYTHONPATH": str(site), "PYTHONDONTWRITEBYTECODE": "1",
                    "RAW_CONFIG_PATH": str(self.config), "HF_CAPTURE": str(self.path / "download.json"),
                    "ARGV_CAPTURE": str(self.path / "argv.json"), "PRIVATE_TEST_TOKEN": "private-token-do-not-print"}

    def run(self, args=None, **env):
        return subprocess.run(["bash", str(LAUNCHER), *(args or ["org/model", "--revision", "main"])],
                              env={**self.env, **env}, capture_output=True, text=True, timeout=10)

    def evidence(self, result):
        line = next(line for line in result.stdout.splitlines() if line.startswith("Native P/D checkpoint evidence: "))
        return json.loads(line.split(": ", 1)[1])

    def close(self):
        self.temp.cleanup()


class LauncherTests(unittest.TestCase):
    def test_dense_main_config_emits_evidence_and_preserves_literal_arguments(self):
        fixture = LauncherFixture(DENSE)
        self.addCleanup(fixture.close)
        args = ["org/model", "--revision=" + "b" * 40, "--dtype", "bfloat16", "--revision", "main",
                "--literal", '{"value":"$token;$(do-not-execute)"}']
        result = fixture.run(args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads((fixture.path / "argv.json").read_text()), ["serve", *args])
        self.assertEqual(json.loads((fixture.path / "download.json").read_text()),
                         {"repo_id": "org/model", "filename": "config.json", "revision": "main"})
        self.assertEqual(fixture.evidence(result), {"requested_revision": "main", "resolved_revision": SHA,
                         "config_sha256": hashlib.sha256(fixture.raw).hexdigest(), "source": "huggingface_hub"})
        self.assertNotIn(str(fixture.path), result.stdout)
        self.assertNotIn(fixture.env["PRIVATE_TEST_TOKEN"], result.stdout + result.stderr)

    def test_stale_or_unverified_configs_fail_before_serving_weights(self):
        configs = [
            {**DENSE, "layer_types": ["full_attention", "linear_attention"]},
            {**DENSE, "layer_types": ["full_attention", "future_attention"]},
            {**DENSE, "layer_types": []},
            {**DENSE, "layer_types": "full_attention"},
            {**DENSE, "layer_types": ["full_attention"]},
            {**DENSE, "model_type": "future_model"},
            {**DENSE, "model_type": []},
            {**DENSE, "model_type": "qwen3_5_text"},
            {**DENSE, "architectures": ["Qwen3ForSequenceClassification"]},
            {**DENSE, "architectures": []},
            {**DENSE, "vision_config": {}},
            {**DENSE, "text_config": DENSE},
            {**DENSE, "is_encoder_decoder": True},
        ]
        for config in configs:
            with self.subTest(config=config):
                fixture = LauncherFixture(config)
                try:
                    result = fixture.run()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("Native P/D raw checkpoint", result.stderr)
                    self.assertFalse((fixture.path / "argv.json").exists())
                    self.assertNotIn("Native P/D checkpoint evidence:", result.stdout)
                finally:
                    fixture.close()

    def test_known_uniform_config_without_layer_types_remains_accepted(self):
        fixture = LauncherFixture({key: value for key, value in DENSE.items() if key != "layer_types"})
        self.addCleanup(fixture.close)
        result = fixture.run(["org/model", "--revision=" + SHA])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads((fixture.path / "download.json").read_text())["revision"], SHA)
        self.assertEqual(fixture.evidence(result)["resolved_revision"], SHA)

    def test_local_snapshot_emits_no_paths_or_invented_hub_revision(self):
        fixture = LauncherFixture(DENSE)
        self.addCleanup(fixture.close)
        model = fixture.path / "private-model"
        model.mkdir()
        (model / "config.json").write_bytes(fixture.raw)
        args = [str(model), "--revision", SHA]
        result = fixture.run(args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(fixture.evidence(result), {"requested_revision": SHA, "resolved_revision": None,
                         "config_sha256": hashlib.sha256(fixture.raw).hexdigest(), "source": "local_model_path"})
        self.assertFalse((fixture.path / "download.json").exists())
        self.assertNotIn(str(fixture.path), result.stdout + result.stderr)

    def test_missing_native_connector_fails_before_download_or_serving(self):
        fixture = LauncherFixture(DENSE)
        self.addCleanup(fixture.close)
        result = fixture.run(CONNECTOR_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("connector cannot load", result.stderr)
        self.assertFalse((fixture.path / "download.json").exists())
        self.assertFalse((fixture.path / "argv.json").exists())

    def test_sdk_failure_does_not_expose_private_error_details(self):
        fixture = LauncherFixture(DENSE)
        self.addCleanup(fixture.close)
        result = fixture.run(HF_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("RuntimeError", result.stderr)
        self.assertNotIn(fixture.env["PRIVATE_TEST_TOKEN"], result.stdout + result.stderr)
        self.assertFalse((fixture.path / "argv.json").exists())

    def test_alternate_config_inputs_cannot_bypass_the_guard(self):
        fixture = LauncherFixture(DENSE)
        self.addCleanup(fixture.close)
        for flag in ("--hf-config-path=other", "--hf-overrides={}", "--config=other"):
            with self.subTest(flag=flag):
                result = fixture.run(["org/model", "--revision", "main", flag])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("alternate config inputs", result.stderr)
                self.assertFalse((fixture.path / "argv.json").exists())


if __name__ == "__main__":
    unittest.main()
