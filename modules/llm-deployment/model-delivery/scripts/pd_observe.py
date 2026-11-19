#!/usr/bin/env python3
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
"""Bounded native P/D observations; HTTP success is not evidence of KV transfer."""
import argparse
import hashlib
import json
import math
import re
import signal
import socket
import subprocess
import time
import urllib.request
import uuid
from contextlib import ExitStack

METRICS = {
    "bytes": "vllm:nixl_bytes_transferred_sum",
    "transfers": "vllm:nixl_bytes_transferred_count",
    "failures": "vllm:nixl_num_failed_transfers_total",
    "expired": "vllm:nixl_num_kv_expired_reqs_total",
    "late_notifications": "vllm:nixl_num_notifications_after_expiry_total",
}
SOURCE = "vllm:prompt_tokens_by_source_total"


class ObservationDeadline(BaseException):
    """Escape best-effort scrape handlers so the final report is still written."""


def parse_metrics(body):
    samples = {}
    for line in body.splitlines():
        match = re.fullmatch(r'([a-zA-Z_:][a-zA-Z0-9_:]*)(\{.*\})?\s+(\S+)(?:\s+\S+)?', line)
        if not match:
            continue
        name, labels, number = match.groups()
        if name not in set(METRICS.values()) | {SOURCE, "process_start_time_seconds"}:
            continue
        try:
            number = float(number)
        except ValueError:
            continue
        if math.isfinite(number) and number >= 0:
            samples[name + (labels or "")] = number
    return samples


def snapshot(targets):
    result = {}
    for target in targets:
        key = target.get("pod", target["url"])
        try:
            with urllib.request.urlopen(target["url"], timeout=4) as response:
                samples = parse_metrics(response.read(4_000_000).decode())
            result[key] = {"role": target["role"], "samples": samples}
        except Exception as exc:
            result[key] = {"role": target["role"], "samples": {}, "error": type(exc).__name__}
    return result


def delta(before, after):
    findings = {"status": "unknown", "transfer_health": "unknown", "roles": {}, "missing_or_reset": [],
                "interpretation": "Per-engine counter window includes other traffic and warmups; it is not per-request attribution. Local compute can include an untransferred tail, not just fallback."}
    for role in ("prefill", "decode"):
        pods = [key for key in set(before) | set(after)
                if after.get(key, before.get(key, {})).get("role") == role]
        totals = {}
        for field, metric in {**METRICS, **{source: SOURCE for source in
                              ("local_compute", "local_cache_hit", "external_kv_transfer")}}.items():
            values = []
            for pod in pods:
                old, new = before.get(pod, {}), after.get(pod, {})
                a, b = old.get("samples", {}), new.get("samples", {})
                select = lambda key: (key.split("{")[0] == metric and
                                      (metric != SOURCE or f'source="{field}"' in key))
                keys = {key for key in set(a) | set(b) if select(key)}
                restarted = a.get("process_start_time_seconds") != b.get("process_start_time_seconds")
                if (old.get("error") or new.get("error") or restarted or not keys or
                        any(key not in a or key not in b or b[key] < a[key] for key in keys)):
                    findings["missing_or_reset"].append(f"{pod}:{field}")
                else:
                    values.append(sum(b[key] - a[key] for key in keys))
            totals[field] = sum(values) if pods and len(values) == len(pods) else None
        findings["roles"][role] = totals
    decode = findings["roles"]["decode"]
    error_values = [findings["roles"][role][key] for role in ("prefill", "decode")
                    for key in ("failures", "expired", "late_notifications")]
    if any(value is not None and value > 0 for value in error_values):
        findings["transfer_health"] = "failures_observed"
    elif all(value is not None for value in error_values):
        findings["transfer_health"] = "no_failures_observed"
    if all(decode[key] is not None and decode[key] > 0 for key in ("bytes", "transfers", "external_kv_transfer")):
        findings["status"] = "transfer_observed"
        if findings["transfer_health"] == "failures_observed":
            findings["status"] = "transfer_observed_with_failures"
    elif (decode["external_kv_transfer"] == 0 and decode["local_cache_hit"] == 0 and
          decode["local_compute"] is not None and decode["local_compute"] > 0):
        findings["status"] = "recomputation_observed"
    return findings


def forward(stack, namespace, pod):
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    process = subprocess.Popen(["kubectl", "-n", namespace, "port-forward", f"pod/{pod}", f"{port}:8000"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    def stop():
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    stack.callback(stop)
    url = f"http://127.0.0.1:{port}/metrics"
    for _ in range(50):
        try:
            with urllib.request.urlopen(url.removesuffix("/metrics") + "/health", timeout=1):
                return url
        except Exception:
            if process.poll() is not None:
                break
            time.sleep(0.2)
    raise RuntimeError(f"Metrics port-forward failed for {pod}")


def probe_prompt(context_length):
    # A fresh first token sequence avoids reusing an earlier probe's prefix.
    words = max(4, min(256, (context_length - 64) // 8))
    return f"{uuid.uuid4().hex} " + "Explain a simple garden. " * words


def probe(base_url, model, kind, context_length, timeout, prompt=None, cache_salt=None):
    prompt = prompt or probe_prompt(context_length)
    payload = {"model": model, "max_tokens": 4, "temperature": 0, "stream": False}
    if cache_salt:
        payload["cache_salt"] = cache_salt
    if kind == "chat":
        payload["messages"] = [{"role": "user", "content": prompt}]
        endpoint = "/v1/chat/completions"
    else:
        payload["prompt"] = prompt
        endpoint = "/v1/completions"
    request = urllib.request.Request(base_url + endpoint, data=json.dumps(payload).encode(),
                                     headers={"Content-Type": "application/json"})
    start = time.monotonic()
    with urllib.request.urlopen(request, timeout=timeout) as response:
        result = json.load(response)
    if not result.get("choices"):
        raise RuntimeError("P/D probe returned no choices")
    return {"endpoint": kind, "elapsed_seconds": round(time.monotonic() - start, 4),
            "usage": result.get("usage"), "response": "choices_present; content_not_logged",
            "output_sha256": hashlib.sha256(json.dumps([choice.get("text", choice.get("message")) for choice in result["choices"]], sort_keys=True).encode()).hexdigest()}


def checkpoint_sources(namespace, pods):
    result = {"status": "unknown", "pods": {},
              "interpretation": "Startup config-source observations, not proof of exact loaded weights for a moving main ref."}
    for pod in pods:
        name = pod["metadata"]["name"]
        try:
            logs = subprocess.run(["kubectl", "-n", namespace, "logs", name, "-c", "vllm", "--tail=2000", "--limit-bytes=262144"],
                                  capture_output=True, text=True, timeout=10, check=True).stdout
            records = [json.loads(line.split("Native P/D checkpoint evidence: ", 1)[1])
                       for line in logs.splitlines() if "Native P/D checkpoint evidence: " in line]
            result["pods"][name] = records[-1] if records else {"status": "unavailable"}
        except Exception:
            result["pods"][name] = {"status": "unavailable"}
    records = list(result["pods"].values())
    if records and all(record.get("config_sha256") for record in records):
        if len({record["config_sha256"] for record in records}) > 1:
            result["status"] = "conflicting_config_sources"
        elif all(record.get("resolved_revision") for record in records):
            result["status"] = "consistent_config_sources" if len({record["resolved_revision"] for record in records}) == 1 else "conflicting_config_sources"
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pods", required=True)
    parser.add_argument("--namespace", required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--context-length", type=int, required=True)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--output", required=True)
    parser.add_argument("--chat", action="store_true")
    args = parser.parse_args()
    def deadline_expired(*_):
        raise ObservationDeadline("P/D observation exceeded its overall deadline")
    signal.signal(signal.SIGALRM, deadline_expired)
    signal.setitimer(signal.ITIMER_REAL, max(1, min(args.timeout, 900)))
    report = {"serving_status": "failed", "effectiveness": {"status": "unknown"}, "probes": []}
    code = 0
    try:
        with ExitStack() as stack:
            pods = json.load(open(args.pods))["items"]
            targets = []
            for pod in pods:
                role = pod["metadata"].get("labels", {}).get("oke-llm/role")
                if role in ("prefill", "decode") and not pod["metadata"].get("deletionTimestamp"):
                    name = pod["metadata"]["name"]
                    try:
                        url = forward(stack, args.namespace, name)
                        reachable = True
                    except Exception:
                        url = "http://127.0.0.1:1/metrics"
                        reachable = False
                    targets.append({"pod": name, "role": role, "url": url, "reachable": reachable})
            if {target["role"] for target in targets} != {"prefill", "decode"}:
                raise RuntimeError("Both ready role pools are required for native P/D validation")
            role_pods = [pod for pod in pods if pod["metadata"]["name"] in {target["pod"] for target in targets}]
            report["checkpoint_sources"] = checkpoint_sources(args.namespace, role_pods)
            if report["checkpoint_sources"]["status"] == "conflicting_config_sources":
                raise RuntimeError("Prefill/decode startup config sources disagree; do not transfer state across different model snapshots")
            probe_timeout = min(args.timeout, 300)
            warmup = probe(args.base_url, args.model, "completions", args.context_length, probe_timeout)
            warmup.pop("output_sha256")
            report["probes"].append(warmup)
            comparison_prompt = probe_prompt(args.context_length)
            decode_url = next((target["url"].removesuffix("/metrics") for target in targets if target["role"] == "decode" and target["reachable"]), None)
            baseline_digest = None
            report["decode_baseline"] = {"status": "unknown; direct decode forwarding unavailable"}
            if decode_url:
                baseline = probe(decode_url, args.model, "completions", args.context_length, probe_timeout,
                                 comparison_prompt, "baseline-" + uuid.uuid4().hex)
                baseline_digest = baseline.pop("output_sha256")
                report["decode_baseline"] = baseline
            time.sleep(12)  # Let the engine's periodic metric reporter publish the warmup.
            before = snapshot(targets)
            comparison_matches = None
            for kind in (["completions", "chat"] if args.chat else ["completions"]):
                result = probe(args.base_url, args.model, kind, args.context_length, probe_timeout,
                               comparison_prompt if kind == "completions" else None, "transfer-" + uuid.uuid4().hex)
                digest = result.pop("output_sha256")
                if kind == "completions" and baseline_digest is not None:
                    comparison_matches = digest == baseline_digest
                report["probes"].append(result)
            for _ in range(7):
                time.sleep(2)
                report["effectiveness"] = delta(before, snapshot(targets))
                if report["effectiveness"]["status"] != "unknown":
                    break
            report["greedy_completion_matches_decode_baseline"] = comparison_matches
            if comparison_matches is False:
                raise RuntimeError("P/D greedy completion differs from the same prompt through direct decode; investigate correctness before using this layout")
            report["serving_status"] = "ready"
    except (Exception, ObservationDeadline) as exc:
        # Do not emit response bodies, generated text, credentials or prompt data.
        report["error"] = type(exc).__name__ + ": " + str(exc)[:180]
        code = 2
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
    with open(args.output, "w") as output:
        json.dump(report, output)
    print("Native P/D findings: " + json.dumps(report), flush=True)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
