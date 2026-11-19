#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
# Check the actual image before downloading weights. No runtime package installs.
python3 - "$@" <<'PY'
import hashlib
import importlib.metadata as metadata
import json
import pathlib
import re
import sys

args = sys.argv[1:]
if not args:
    raise SystemExit("Native P/D requires a model and its effective revision before loading weights.")
revision = "main"
for index, arg in enumerate(args[1:], 1):
    if arg == "--revision":
        if index + 1 == len(args):
            raise SystemExit("Native P/D --revision requires a value.")
        revision = args[index + 1]
    elif arg.startswith("--revision="):
        revision = arg.split("=", 1)[1]
    if arg.split("=", 1)[0] in ("--hf-config-path", "--hf-overrides", "--config"):
        raise SystemExit("Native P/D raw-config validation does not support alternate config inputs or overrides.")
if not re.fullmatch(r"main|[a-f0-9]{40}", revision):
    raise SystemExit("Native P/D requires main or an immutable 40-character revision.")
try:
    import nixl
    from vllm.config import KVTransferConfig
    from vllm.distributed.kv_transfer.kv_connector.factory import KVConnectorFactory
    config = KVTransferConfig(kv_connector="NixlConnector", kv_role="kv_consumer", kv_load_failure_policy="recompute")
    KVConnectorFactory.get_connector_class(config)
except Exception as exc:
    raise SystemExit(f"Native P/D connector cannot load in this image: {type(exc).__name__}: {exc}. Select a complete compatible upstream image.")
def package_version(*names):
    for name in names:
        try:
            return metadata.version(name)
        except metadata.PackageNotFoundError:
            continue
    return "unreported"
print(f"Native P/D startup: vllm={package_version('vllm')} nixl={package_version('nixl', 'nixl-cu12', 'nixl-cu13')} connector=NixlConnector failure_policy=recompute; transfer is not yet validated", flush=True)

# main can change after discovery. Inspect the actual raw configuration without
# loading custom model code or assuming that the discovery SHA is still current.
try:
    model_path = pathlib.Path(args[0])
    source = "local_model_path" if model_path.is_dir() else "huggingface_hub"
    if source == "local_model_path":
        config_path = model_path / "config.json"
    else:
        from huggingface_hub import hf_hub_download
        config_path = pathlib.Path(hf_hub_download(repo_id=args[0], filename="config.json", revision=revision))
    raw = config_path.read_bytes()
    model_config = json.loads(raw)
except Exception as exc:
    # SDK errors can include private cache paths or request details.
    raise SystemExit(f"Native P/D raw checkpoint config could not be read ({type(exc).__name__}); no weights were started.")

uniform_types = {"llama", "mistral", "mixtral", "qwen2", "qwen2_moe", "qwen3", "qwen3_moe"}
if not isinstance(model_config, dict):
    raise SystemExit("Native P/D requires a raw model configuration object.")
if any(key in model_config for key in ("text_config", "vision_config", "audio_config", "encoder_config", "decoder_config")) or model_config.get("is_encoder_decoder", False):
    raise SystemExit("Native P/D raw checkpoint is composite or encoder-decoder; refresh discovery and select a supported adapter.")
architectures = model_config.get("architectures")
if not isinstance(architectures, list) or not architectures or not all(isinstance(name, str) and name.endswith("ForCausalLM") for name in architectures):
    raise SystemExit("Native P/D raw checkpoint has no unambiguous causal-generation architecture; refresh discovery.")
if not isinstance(model_config.get("model_type"), str) or model_config["model_type"] not in uniform_types:
    raise SystemExit("Native P/D raw checkpoint cache architecture is hybrid or unverified; refresh discovery and select a supported adapter.")
if any(key in model_config for key in ("kv_lora_rank", "qk_rope_head_dim", "linear_num_key_heads", "mamba_ssm_dtype")):
    raise SystemExit("Native P/D raw checkpoint has latent or recurrent cache fields outside this adapter's assessed layout.")
if "layer_types" in model_config:
    layers = model_config["layer_types"]
    if not isinstance(layers, list) or not layers or not all(kind in ("attention", "full_attention") for kind in layers) or ("num_hidden_layers" in model_config and len(layers) != model_config["num_hidden_layers"]):
        raise SystemExit("Native P/D raw checkpoint has hybrid, unknown or inconsistent attention layers; refresh discovery.")

resolved_revision = None
if source == "huggingface_hub":
    # Do not resolve config.json's symlink: its blob target loses the snapshot SHA.
    for parent in config_path.parents:
        if parent.parent.name == "snapshots" and re.fullmatch(r"[a-f0-9]{40}", parent.name):
            resolved_revision = parent.name
            break
print("Native P/D checkpoint evidence: " + json.dumps({
    "requested_revision": revision, "resolved_revision": resolved_revision,
    "config_sha256": hashlib.sha256(raw).hexdigest(), "source": source,
}), flush=True)
# This is a config-read observation. A moving main can advance before vLLM reads
# weights; role comparison and transfer observations must retain that limitation.
PY
exec vllm serve "$@"
