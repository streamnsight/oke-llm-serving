"""Inspect immutable Hub metadata and safetensors headers, never model code."""

import json
import math
import os
import re
import struct
from collections import Counter
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

GIB = 1024**3
MAX_JSON = 16 * 1024**2
MAX_SHARDS = 1024
MAX_HEADERS = 64 * 1024**2
FLOAT_BYTES = {"F64": 8, "F32": 4, "F16": 2, "BF16": 2}
RUNTIME_BYTES = {"float32": 4, "float16": 2, "bfloat16": 2}
SUPPORTED = {"llama", "mistral", "mixtral", "qwen2", "qwen2_moe", "qwen3", "qwen3_moe"}


class ProfileError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


class SafeRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urlparse(newurl).scheme != "https":
            raise ProfileError("unsafe_redirect", "Hub redirected to a non-HTTPS URL.")
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if redirected and urlparse(newurl).netloc != urlparse(req.full_url).netloc:
            redirected.remove_header("Authorization")
        return redirected


def normalize_repo(value):
    if value.startswith("https://huggingface.co/"):
        value = value.removeprefix("https://huggingface.co/").rstrip("/")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise ProfileError("invalid_model", "Use an owner/model identifier or its Hugging Face repository URL.")
    return value


def artifact_path(value):
    if not isinstance(value, str) or value.startswith("/") or any(p in {"", ".", ".."} for p in value.split("/")):
        raise ProfileError("invalid_artifact", "Checkpoint paths must be repository-relative paths without traversal.")
    return value


class HubClient:
    def __init__(self, timeout=30):
        self.timeout = timeout
        self.token = os.environ.get("HF_TOKEN")
        self.opener = build_opener(SafeRedirect())

    def read(self, url, *, start=None, end=None, optional=False):
        headers = {"User-Agent": "oke-llm-serving/0.1.0", "Accept-Encoding": "identity"}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        if start is not None:
            headers["Range"] = f"bytes={start}-{end}"
        try:
            with self.opener.open(Request(url, headers=headers), timeout=self.timeout) as response:
                if start is None:
                    data = response.read(MAX_JSON + 1)
                    if len(data) > MAX_JSON:
                        raise ProfileError("metadata_too_large", "Metadata exceeds the 16 MiB request bound.")
                    return data
                length = end - start + 1
                if response.status == 206:
                    content_range = response.headers.get("Content-Range", "")
                    if not content_range.startswith(f"bytes {start}-{end}/"):
                        raise ProfileError("invalid_range", "Hub returned an unexpected byte range.")
                    data = response.read(length)
                else:
                    # A server ignoring Range must still never cause a weight download.
                    data = response.read(end + 1)[start:]
                if len(data) != length:
                    raise ProfileError("invalid_range", "Checkpoint metadata range is truncated.")
                return data
        except HTTPError as exc:
            if exc.code == 404 and optional:
                return None
            if exc.code in (401, 403):
                raise ProfileError("access_denied", "Hub access denied. Check HF_TOKEN and gated-model approval.") from None
            if exc.code == 404:
                raise ProfileError("not_found", "Model, revision or required artifact was not found.") from None
            raise ProfileError("hub_http_error", f"Hub request failed with HTTP {exc.code}.") from None
        except (URLError, TimeoutError, OSError):
            raise ProfileError("hub_connection_error", "Could not read Hub metadata; check connectivity and retry.") from None

    def info(self, repo, revision):
        url = f"https://huggingface.co/api/models/{quote(repo, safe='/')}/revision/{quote(revision, safe='')}?blobs=true"
        return decode_json(self.read(url))

    def file(self, repo, sha, name, optional=False):
        name = artifact_path(name)
        url = f"https://huggingface.co/{quote(repo, safe='/')}/resolve/{quote(sha, safe='')}/{quote(name, safe='/')}"
        data = self.read(url, optional=optional)
        return None if data is None else decode_json(data)

    def header(self, repo, sha, name):
        name = artifact_path(name)
        url = f"https://huggingface.co/{quote(repo, safe='/')}/resolve/{quote(sha, safe='')}/{quote(name, safe='/')}"
        size = struct.unpack("<Q", self.read(url, start=0, end=7))[0]
        if not 2 <= size <= MAX_JSON:
            raise ProfileError("invalid_safetensors", "Safetensors header length is outside the supported bounds.")
        return decode_json(self.read(url, start=8, end=7 + size)), size


def decode_json(data):
    try:
        value = json.loads(data)
    except (ValueError, UnicodeError):
        raise ProfileError("invalid_metadata", "An artifact is not valid JSON metadata.") from None
    if not isinstance(value, dict):
        raise ProfileError("invalid_metadata", "Expected a JSON metadata object.")
    return value


def select_checkpoint(files, requested=None):
    names = set(files)
    if requested:
        selected = artifact_path(requested)
        if selected not in names:
            raise ProfileError("checkpoint_not_found", "The selected checkpoint is not listed in this revision.")
        if not selected.endswith((".safetensors", ".safetensors.index.json")):
            raise ProfileError("unsupported_checkpoint", "Only safetensors checkpoints are supported.")
        return selected
    for canonical in ("model.safetensors.index.json", "model.safetensors"):
        if canonical in names:
            return canonical
    indexes = sorted(n for n in names if n.endswith(".safetensors.index.json") and "/" not in n)
    tensors = sorted(n for n in names if n.endswith(".safetensors") and "/" not in n)
    candidates = indexes or tensors
    if len(candidates) != 1:
        raise ProfileError("checkpoint_selection_required", "No unambiguous root safetensors checkpoint. Specify --checkpoint explicitly.")
    return candidates[0]


def inspect_weights(hub, repo, sha, files, selected):
    weight_map = None
    if selected.endswith(".index.json"):
        index = hub.file(repo, sha, selected)
        weight_map = index.get("weight_map")
        if not isinstance(weight_map, dict) or not weight_map:
            raise ProfileError("invalid_index", "Safetensors index has no nonempty weight_map.")
        shards = sorted(set(weight_map.values()))
    else:
        shards = [selected]
    if len(shards) > MAX_SHARDS:
        raise ProfileError("too_many_shards", "Checkpoint exceeds the 1024-shard inspection bound.")
    dtypes = Counter()
    total_bytes = total_elements = total_headers = 0
    seen = set()
    for shard in shards:
        artifact_path(shard)
        if shard not in files:
            raise ProfileError("missing_shard", "A checkpoint shard is missing from the repository listing.")
        header, header_size = hub.header(repo, sha, shard)
        total_headers += header_size
        if total_headers > MAX_HEADERS:
            raise ProfileError("metadata_too_large", "Combined checkpoint headers exceed 64 MiB.")
        for name, tensor in header.items():
            if name == "__metadata__":
                continue
            if name in seen or not isinstance(tensor, dict):
                raise ProfileError("invalid_safetensors", "Duplicate tensor or invalid tensor metadata.")
            shape, offsets, dtype = tensor.get("shape"), tensor.get("data_offsets"), tensor.get("dtype")
            if (not isinstance(shape, list) or any(type(n) is not int or n < 0 for n in shape)
                    or not isinstance(offsets, list) or len(offsets) != 2
                    or any(type(n) is not int or n < 0 for n in offsets)
                    or offsets[1] < offsets[0] or not isinstance(dtype, str)):
                raise ProfileError("invalid_safetensors", "Invalid tensor shape, dtype or offsets.")
            if weight_map is not None and weight_map.get(name) != shard:
                raise ProfileError("invalid_index", "Tensor headers disagree with the checkpoint index.")
            elements = math.prod(shape)
            if dtype in FLOAT_BYTES and offsets[1] - offsets[0] != elements * FLOAT_BYTES[dtype]:
                raise ProfileError("invalid_safetensors", "Tensor byte length disagrees with its dtype and shape.")
            total_elements += elements
            total_bytes += offsets[1] - offsets[0]
            dtypes[dtype] += elements
            seen.add(name)
    if weight_map is not None and seen != set(weight_map):
        raise ProfileError("invalid_index", "Some indexed tensors are absent from checkpoint headers.")
    if not seen:
        raise ProfileError("invalid_safetensors", "Checkpoint contains no tensors.")
    sizes = [files[s].get("size") for s in shards]
    return {
        "selected_checkpoint": selected, "files": shards,
        "tensor_data_bytes": total_bytes, "tensor_elements": total_elements,
        "checkpoint_file_bytes": sum(sizes) if all(type(s) is int for s in sizes) else None,
        "elements_by_dtype": dict(sorted(dtypes.items())),
        "source": "selected safetensors headers", "confidence": "measured_metadata",
    }


def positive_int(value):
    return type(value) is int and value > 0


def estimate(config, weights, *, context_length, concurrency, kv_dtype, weight_dtype, runtime_gib, margin):
    text = config.get("text_config", config)
    if not isinstance(text, dict):
        raise ProfileError("invalid_config", "text_config must be a JSON object.")
    model_type = text.get("model_type", config.get("model_type"))
    experts = text.get("num_local_experts", text.get("num_experts"))
    architecture = {
        "model_type": model_type, "architectures": config.get("architectures", []),
        "kind": "moe" if model_type in {"mixtral", "qwen2_moe", "qwen3_moe"} or (positive_int(experts) and experts > 1) else "dense" if model_type in SUPPORTED else "unknown",
        "experts": experts, "experts_per_token": text.get("num_experts_per_tok"),
        "declared_context_length": text.get("max_position_embeddings"),
        "quantization": config.get("quantization_config", text.get("quantization_config")),
        "source": "config.json", "confidence": "declared_metadata",
    }
    warnings = []
    reasons = []
    if model_type not in SUPPORTED:
        reasons.append("Architecture is not in the validated conventional-attention estimator set.")
    if "text_config" in config or "vision_config" in config or config.get("auto_map"):
        reasons.append("Composite/multimodal or custom-code architectures require a dedicated estimator.")
    if architecture["quantization"] or not set(weights["elements_by_dtype"]).issubset(FLOAT_BYTES):
        reasons.append("Quantized/packed weights require an engine-specific resident-memory estimator.")
    layers, heads = text.get("num_hidden_layers"), text.get("num_attention_heads")
    kv_heads = text.get("num_key_value_heads", heads)
    head_dim = text.get("head_dim")
    if head_dim is None and positive_int(heads) and positive_int(text.get("hidden_size")):
        if text["hidden_size"] % heads == 0:
            head_dim = text["hidden_size"] // heads
    if not all(positive_int(n) for n in (layers, heads, kv_heads, head_dim)):
        reasons.append("Missing or invalid layer/attention dimensions for KV estimation.")
    elif kv_heads > heads or heads % kv_heads:
        reasons.append("Unsupported query-head to KV-head grouping.")
    maximum = architecture["declared_context_length"]
    if positive_int(maximum) and context_length > maximum:
        reasons.append("Requested context exceeds max_position_embeddings; no context extension is assumed.")
    if text.get("sliding_window"):
        warnings.append("KV estimate allocates full context for all layers; sliding-window savings are not assumed.")
    if architecture["kind"] == "moe":
        warnings.append("All selected expert weights are counted; active experts do not reduce resident weight memory.")
    assumptions = {
        "context_length": context_length, "concurrency": concurrency,
        "live_cached_tokens": context_length * concurrency, "kv_dtype": kv_dtype,
        "weight_dtype": weight_dtype, "runtime_allowance_gib": runtime_gib,
        "safety_margin_fraction": margin, "prefix_sharing": False,
        "offload": False, "parallelism": "unsharded aggregate; not a per-GPU fit assessment",
    }
    result = {"status": "unsupported" if reasons else "estimated", "reasons": reasons,
              "assumptions": assumptions, "confidence": "analytical_estimate" if not reasons else "unknown"}
    if not reasons:
        resident = (weights["tensor_data_bytes"] if weight_dtype == "checkpoint"
                    else weights["tensor_elements"] * RUNTIME_BYTES[weight_dtype])
        per_token = 2 * layers * kv_heads * head_dim * RUNTIME_BYTES[kv_dtype]
        kv = per_token * context_length * concurrency
        runtime = math.ceil(runtime_gib * GIB)
        subtotal = resident + kv + runtime
        total = math.ceil(subtotal * (1 + margin))
        result.update(weight_bytes=resident, kv_bytes_per_token=per_token, kv_bytes=kv,
                      runtime_allowance_bytes=runtime, minimum_aggregate_bytes=subtotal,
                      recommended_aggregate_bytes=total, recommended_aggregate_gib=total / GIB)
    warnings.append("Runtime allowance and margin are assumptions, not measured overhead or a performance guarantee.")
    warnings.append("GPU count, TP/PP layout, runtime compatibility and throughput require a subsequent deployment assessment.")
    return architecture, result, warnings


def inspect_model(model, *, revision="main", checkpoint=None, context_length=4096,
                  concurrency=1, kv_dtype="bfloat16", weight_dtype="checkpoint",
                  runtime_gib=2.0, margin=0.2, hub=None):
    repo = normalize_repo(model)
    if not revision or not positive_int(context_length) or not positive_int(concurrency):
        raise ProfileError("invalid_input", "Revision must be nonempty; context length and concurrency must be positive integers.")
    if kv_dtype not in RUNTIME_BYTES or weight_dtype not in {"checkpoint", *RUNTIME_BYTES}:
        raise ProfileError("invalid_input", "Unsupported weight or KV dtype.")
    if not math.isfinite(runtime_gib) or runtime_gib < 0 or not math.isfinite(margin) or not 0 <= margin <= 1:
        raise ProfileError("invalid_input", "Runtime allowance must be nonnegative and margin must be between zero and one.")
    hub = hub or HubClient()
    info = hub.info(repo, revision)
    sha = info.get("sha")
    if not isinstance(sha, str) or not re.fullmatch(r"[a-fA-F0-9]{40}", sha):
        raise ProfileError("invalid_revision", "Hub did not resolve an immutable model commit SHA.")
    config = hub.file(repo, sha, "config.json")
    files = {f["rfilename"]: f for f in info.get("siblings", []) if isinstance(f, dict) and "rfilename" in f}
    selected = select_checkpoint(files, checkpoint)
    weights = inspect_weights(hub, repo, sha, files, selected)
    architecture, memory, warnings = estimate(
        config, weights, context_length=context_length, concurrency=concurrency,
        kv_dtype=kv_dtype, weight_dtype=weight_dtype, runtime_gib=runtime_gib, margin=margin,
    )
    return {
        "schema_version": "1.0", "estimator_version": "0.1.0",
        "observed_at": datetime.now(timezone.utc).isoformat(),
        "model": {"repository": repo, "requested_revision": revision, "resolved_revision": sha,
                  "url": f"https://huggingface.co/{repo}/tree/{sha}",
                  "gated": info.get("gated", False), "pipeline_tag": info.get("pipeline_tag"),
                  "license": (info.get("cardData") or {}).get("license")},
        "architecture": architecture, "weights": weights, "memory": memory, "warnings": warnings,
    }
