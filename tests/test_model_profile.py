import io
import json
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request

from oke_llm_serving.cli import main
from oke_llm_serving.model_profile import (
    GIB, HubClient, ProfileError, SafeRedirect, inspect_model, normalize_repo,
)

SHA = "a" * 40


class FakeHub:
    """Metadata-only fixture; sizes and tensor dimensions are intentionally tiny."""
    def __init__(self):
        self.config = {"model_type": "llama", "num_hidden_layers": 80,
                       "num_attention_heads": 64, "num_key_value_heads": 8,
                       "hidden_size": 8192, "max_position_embeddings": 32768}
        self.files = {"model.safetensors": {"size": 256}, "pytorch_model.bin": {"size": 9999},
                      "alternate/model.safetensors": {"size": 9999}}
        self.headers = {"model.safetensors": {"weight": {"dtype": "BF16", "shape": [8], "data_offsets": [0, 16]}}}
        self.reads = []

    def info(self, repo, revision):
        return {"sha": SHA, "siblings": [{"rfilename": n, **v} for n, v in self.files.items()]}

    def file(self, repo, sha, name):
        self.reads.append((sha, name))
        return self.config if name == "config.json" else self.index

    def header(self, repo, sha, name):
        self.reads.append((sha, name))
        return self.headers[name], 100


class ProfileTests(unittest.TestCase):
    def test_gqa_memory_and_no_duplicate_formats(self):
        hub = FakeHub()
        profile = inspect_model("org/model", context_length=32768, concurrency=2, hub=hub)
        self.assertEqual(profile["memory"]["kv_bytes"], 20 * GIB)
        self.assertEqual(profile["weights"]["tensor_data_bytes"], 16)
        self.assertEqual(profile["weights"]["checkpoint_file_bytes"], 256)
        self.assertEqual(profile["weights"]["files"], ["model.safetensors"])
        self.assertTrue(all(sha == SHA for sha, _ in hub.reads))

    def test_index_counts_all_experts_not_active_fraction(self):
        hub = FakeHub()
        hub.config.update(model_type="mixtral", num_local_experts=8, num_experts_per_tok=2)
        hub.files = {"model.safetensors.index.json": {}, "one.safetensors": {"size": 100}, "two.safetensors": {"size": 100}}
        hub.index = {"weight_map": {"expert0": "one.safetensors", "expert1": "two.safetensors"}}
        hub.headers = {n: {key: {"dtype": "BF16", "shape": [10], "data_offsets": [0, 20]}}
                       for n, key in [("one.safetensors", "expert0"), ("two.safetensors", "expert1")]}
        profile = inspect_model("org/moe", hub=hub)
        self.assertEqual(profile["architecture"]["kind"], "moe")
        self.assertEqual(profile["memory"]["weight_bytes"], 40)

    def test_quantized_weights_preserve_metadata_without_guessing_vram(self):
        hub = FakeHub()
        hub.config["quantization_config"] = {"quant_method": "gptq"}
        profile = inspect_model("org/model", hub=hub)
        self.assertEqual(profile["weights"]["tensor_data_bytes"], 16)
        self.assertEqual(profile["memory"]["status"], "unsupported")
        self.assertNotIn("recommended_aggregate_bytes", profile["memory"])

    def test_custom_and_composite_configs_are_not_generic_transformers(self):
        for config in [{"model_type": "new_hybrid"}, {"auto_map": {"AutoModel": "model.Code"}},
                       {"vision_config": {"model_type": "vision"}}]:
            hub = FakeHub()
            hub.config.update(config)
            self.assertEqual(inspect_model("org/model", hub=hub)["memory"]["status"], "unsupported")

    def test_context_extension_not_silently_assumed(self):
        profile = inspect_model("org/model", context_length=65536, hub=FakeHub())
        self.assertEqual(profile["memory"]["status"], "unsupported")

    def test_missing_kv_dimensions_does_not_invent_zero_memory(self):
        hub = FakeHub()
        del hub.config["num_hidden_layers"]
        self.assertEqual(inspect_model("org/model", hub=hub)["memory"]["status"], "unsupported")

    def test_weight_dtype_conversion(self):
        profile = inspect_model("org/model", weight_dtype="float32", hub=FakeHub())
        self.assertEqual(profile["memory"]["weight_bytes"], 32)

    def test_ambiguous_checkpoint_requires_selection(self):
        hub = FakeHub()
        hub.files = {"fp16.safetensors": {}, "bf16.safetensors": {}}
        with self.assertRaisesRegex(ProfileError, "unambiguous"):
            inspect_model("org/model", hub=hub)
        hub.headers["bf16.safetensors"] = hub.headers["model.safetensors"]
        self.assertEqual(inspect_model("org/model", checkpoint="bf16.safetensors", hub=hub)["weights"]["files"], ["bf16.safetensors"])

    def test_missing_index_tensor_is_error(self):
        hub = FakeHub()
        hub.files["model.safetensors.index.json"] = {}
        hub.index = {"weight_map": {"weight": "model.safetensors", "missing": "model.safetensors"}}
        with self.assertRaisesRegex(ProfileError, "absent"):
            inspect_model("org/model", hub=hub)

    def test_malformed_tensor_bytes_are_rejected(self):
        hub = FakeHub()
        hub.headers["model.safetensors"]["weight"]["data_offsets"] = [0, 999]
        with self.assertRaisesRegex(ProfileError, "byte length"):
            inspect_model("org/model", hub=hub)

    def test_url_and_invalid_inputs(self):
        self.assertEqual(normalize_repo("https://huggingface.co/org/model/"), "org/model")
        for model in ["https://evil.example/org/model", "org/model/tree/main", "../org/model"]:
            with self.assertRaises(ProfileError):
                normalize_repo(model)
        for params in [{"context_length": 0}, {"concurrency": -1}, {"margin": float("nan")}, {"runtime_gib": -1}]:
            with self.assertRaises(ProfileError):
                inspect_model("org/model", hub=FakeHub(), **params)

    def test_external_protocol_is_string_map(self):
        out = io.StringIO()
        with patch("sys.stdin", io.StringIO('{"model":"org/model","concurrency":"2"}')), \
                patch("oke_llm_serving.cli.inspect_model", return_value={"schema_version": "1.0"}), redirect_stdout(out):
            self.assertEqual(main(["terraform"]), 0)
        result = json.loads(out.getvalue())
        self.assertEqual(json.loads(result["profile_json"])["schema_version"], "1.0")

    def test_invalid_external_query_only_writes_stderr(self):
        out, err = io.StringIO(), io.StringIO()
        with patch("sys.stdin", io.StringIO('{"model":"org/model","token":"secret"}')), redirect_stdout(out), redirect_stderr(err):
            self.assertEqual(main(["terraform"]), 2)
        self.assertEqual(out.getvalue(), "")
        self.assertNotIn("secret", err.getvalue())


class TransportTests(unittest.TestCase):
    def test_range_ignored_never_reads_entire_weights(self):
        reads = []
        class Response(io.BytesIO):
            status = 200
            headers = {}

            def read(self, size=-1):
                reads.append(size)
                return super().read(size)

        response = Response(b"12345678HEADER" + b"w" * 10000)
        hub = HubClient()
        with patch.object(hub.opener, "open", return_value=response):
            self.assertEqual(hub.read("https://huggingface.co/file", start=8, end=13), b"HEADER")
        self.assertEqual(reads, [14])

    def test_gated_error_does_not_leak_credentials(self):
        hub = HubClient()
        error = HTTPError("https://huggingface.co/file", 403, "secret", {}, None)
        with patch.object(hub.opener, "open", side_effect=error):
            with self.assertRaisesRegex(ProfileError, "gated-model approval"):
                hub.read("https://huggingface.co/file")

    def test_redirect_strips_token_on_different_host(self):
        request = Request("https://huggingface.co/file", headers={"Authorization": "Bearer secret"})
        redirected = SafeRedirect().redirect_request(request, None, 302, "Found", {}, "https://cdn.example/file")
        self.assertIsNone(redirected.get_header("Authorization"))


if __name__ == "__main__":
    unittest.main()
