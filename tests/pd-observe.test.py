#!/usr/bin/env python3
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import importlib.util
import pathlib
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

path = pathlib.Path(__file__).resolve().parents[1] / "modules/llm-deployment/model-delivery/scripts/pd_observe.py"
spec = importlib.util.spec_from_file_location("pd_observe", path)
observer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(observer)


def metrics(byte_count=0, transfers=0, computed=0, external=0, cached=0, failed=0, start=100):
    return observer.parse_metrics(f'''process_start_time_seconds {start}
vllm:nixl_bytes_transferred_sum{{engine="0"}} {byte_count}
vllm:nixl_bytes_transferred_count{{engine="0"}} {transfers}
vllm:nixl_num_failed_transfers_total{{engine="0"}} {failed}
vllm:nixl_num_kv_expired_reqs_total{{engine="0"}} 0
vllm:nixl_num_notifications_after_expiry_total{{engine="0"}} 0
vllm:prompt_tokens_by_source_total{{model_name="public/model",source="local_compute"}} {computed}
vllm:prompt_tokens_by_source_total{{model_name="public/model",source="external_kv_transfer"}} {external}
vllm:prompt_tokens_by_source_total{{model_name="public/model",source="local_cache_hit"}} {cached}
''')


def snapshot(samples):
    return {"prefill-0": {"role": "prefill", "samples": metrics()},
            "decode-0": {"role": "decode", "samples": samples}}


class ObservationTests(unittest.TestCase):
    def test_http_success_and_computed_prompt_do_not_establish_transfer(self):
        result = observer.delta(snapshot(metrics()), snapshot(metrics(computed=512)))
        self.assertEqual(result["status"], "recomputation_observed")
        self.assertEqual(result["roles"]["decode"]["external_kv_transfer"], 0)

    def test_transfer_requires_bytes_operations_and_external_consumption(self):
        result = observer.delta(snapshot(metrics()), snapshot(metrics(byte_count=1024, transfers=1, external=496, computed=16)))
        self.assertEqual(result["status"], "transfer_observed")
        self.assertEqual(result["roles"]["decode"]["local_compute"], 16)
        no_consume = observer.delta(snapshot(metrics()), snapshot(metrics(byte_count=1024, transfers=1)))
        self.assertEqual(no_consume["status"], "unknown")

    def test_missing_metrics_or_scrape_failures_are_unknown(self):
        for after in ({"decode-0": {"role": "decode", "samples": {}, "error": "TimeoutError"}}, {}):
            result = observer.delta(snapshot(metrics()), after)
            self.assertEqual(result["status"], "unknown")
            self.assertIsNone(result["roles"]["decode"]["bytes"])
            self.assertTrue(result["missing_or_reset"])

    def test_restart_and_series_resets_do_not_make_false_deltas(self):
        before = snapshot(metrics(byte_count=100, transfers=1, external=100))
        for after in (metrics(byte_count=200, transfers=2, external=200, start=101), metrics()):
            result = observer.delta(before, snapshot(after))
            self.assertEqual(result["status"], "unknown")
            self.assertIsNone(result["roles"]["decode"]["bytes"])

    def test_failures_are_reported_without_double_counting_notification_alias(self):
        samples = metrics(byte_count=1024, transfers=1, external=512, failed=1)
        samples.update(observer.parse_metrics('vllm:nixl_num_failed_notifications_total 1'))
        result = observer.delta(snapshot(metrics()), snapshot(samples))
        self.assertEqual(result["status"], "transfer_observed_with_failures")
        self.assertEqual(result["roles"]["decode"]["failures"], 1)

    def test_local_prefix_reuse_is_not_mislabeled_as_full_recomputation(self):
        result = observer.delta(snapshot(metrics()), snapshot(metrics(cached=496, computed=16)))
        self.assertEqual(result["status"], "unknown")

    def test_every_decoder_is_observed_before_aggregating(self):
        before = snapshot(metrics())
        before["decode-1"] = {"role": "decode", "samples": metrics()}
        after = snapshot(metrics(byte_count=1024, transfers=1, external=512))
        after["decode-1"] = {"role": "decode", "samples": {}, "error": "TimeoutError"}
        result = observer.delta(before, after)
        self.assertEqual(result["status"], "unknown")
        self.assertIsNone(result["roles"]["decode"]["bytes"])

    def test_observed_transfer_does_not_hide_unknown_failure_counters(self):
        before, after = snapshot(metrics()), snapshot(metrics(byte_count=1024, transfers=1, external=512))
        before["prefill-0"]["samples"] = {}
        after["prefill-0"]["samples"] = {}
        result = observer.delta(before, after)
        self.assertEqual(result["status"], "transfer_observed")
        self.assertEqual(result["transfer_health"], "unknown")

    def test_observation_deadline_writes_partial_findings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            tool = root / "kubectl"
            tool.write_text(f"#!{sys.executable}\nimport time\ntime.sleep(60)\n")
            tool.chmod(0o755)
            pods = root / "pods.json"
            pods.write_text(json.dumps({"items": [{"metadata": {"name": "p-0", "labels": {"oke-llm/role": "prefill"}}}]}))
            output = root / "findings.json"
            start = time.monotonic()
            result = subprocess.run([sys.executable, str(path), "--pods", str(pods), "--namespace", "fixture", "--base-url", "http://127.0.0.1:1", "--model", "public/model", "--context-length", "4096", "--timeout", "1", "--output", str(output)],
                                    env={**os.environ, "PATH": directory + os.pathsep + os.environ["PATH"]}, capture_output=True, text=True, timeout=8)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertLess(time.monotonic() - start, 6)
            report = json.loads(output.read_text())
            self.assertEqual(report["serving_status"], "failed")
            self.assertEqual(report["effectiveness"]["status"], "unknown")
            self.assertIn("overall deadline", report["error"])


if __name__ == "__main__":
    unittest.main()
