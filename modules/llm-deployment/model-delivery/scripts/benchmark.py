#!/usr/bin/env python3
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
"""Plan paired cache workloads; run the bundled native vLLM benchmark client."""
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import secrets
import statistics
import subprocess
import sys
import time
import urllib.request


def positive(name, default, maximum=1000000):
    value = os.environ.get(name, 'auto')
    if value == 'auto':
        return default
    if not re.fullmatch(r'[1-9][0-9]*', value) or int(value) > maximum:
        raise ValueError(f'{name} must be auto or an integer from 1 to {maximum}')
    return int(value)


def plan():
    mode = os.environ.get('BENCHMARK_MODE', 'quick')
    if mode not in ('quick', 'full'):
        raise ValueError('BENCHMARK_MODE must be quick or full')
    context = positive('CONTEXT_LENGTH', 4096, 2147483647)
    output = positive('BENCHMARK_OUTPUT_TOKENS', 128)
    maximum = context - output - 128  # Reserve chat-template/scaffolding tokens.
    if maximum < 2:
        raise ValueError('Context is too small for output and 128 template tokens')
    raw = os.environ.get('BENCHMARK_INPUT_TOKENS', 'auto')
    if raw == 'auto':
        defaults = [1024, 4096] if mode == 'quick' else [512, 1024, 2048, 4096, 8192, 16384]
        lengths = sorted(set(min(n, maximum) for n in defaults))
    else:
        if not re.fullmatch(r'[1-9][0-9]*(,[1-9][0-9]*)*', raw):
            raise ValueError('BENCHMARK_INPUT_TOKENS must be auto or comma-separated positive integers')
        lengths = sorted(set(map(int, raw.split(','))))
        if len(lengths) > 12 or min(lengths) < 2 or max(lengths) > maximum:
            raise ValueError('Benchmark input + output + 128 template tokens exceed context, or more than 12 lengths selected')
    samples = positive('BENCHMARK_REQUESTS', 64 if mode == 'quick' else 512, 10000)
    concurrency = positive('BENCHMARK_MAX_CONCURRENCY', positive('CONCURRENCY', 1) * positive('REPLICAS', 1), 1024)
    seconds = positive('BENCHMARK_MAX_SECONDS', 1800 if mode == 'quick' else 18000, 20000)
    prefix = os.environ.get('BENCHMARK_PREFIX_TOKENS', 'auto')
    if prefix != 'auto' and (not re.fullmatch(r'[1-9][0-9]*', prefix) or int(prefix) >= min(lengths)):
        raise ValueError('BENCHMARK_PREFIX_TOKENS must be auto or positive and smaller than every total input length')
    if 2 * (samples + 1) * max(lengths) > 64000000:
        raise ValueError('Per-cell dataset exceeds 64 million input tokens; reduce lengths or requests')
    return dict(mode=mode, input_tokens=lengths, output_tokens=output, requests=samples,
                concurrency=concurrency, max_seconds=seconds, job_seconds=seconds + 600,
                shared_prefix_tokens=[max(1, n * 3 // 4) if prefix == 'auto' else int(prefix) for n in lengths],
                measured_requests=2 * len(lengths) * samples,
                nominal_measured_tokens=2 * samples * sum(n + output for n in lengths),
                context_length=context, template_allowance=128,
                maximum_dataset_candidate_tokens=2 * (samples + 1) * max(lengths))


def emit(event, **data):
    print(json.dumps(dict(event=event, **data), allow_nan=False, separators=(',', ':')), flush=True)


def finite(value):
    return value if isinstance(value, (int, float)) and math.isfinite(value) else None


def distribution(values):
    values = [v for v in values if finite(v) is not None]
    return dict(min=min(values), mean=statistics.mean(values), max=max(values)) if values else None


def summarize(result, requested):
    completed = int(result.get('completed', 0))
    failed = int(result.get('failed', requested - completed))
    metrics = {}
    intervals_available = any(n > 1 for n in result.get('output_lens', []))
    for name in ('ttft', 'tpot', 'itl', 'e2el'):
        metrics[name + '_ms'] = {key: finite(result.get(f'{key}_{name}_ms')) if completed and (name not in ('tpot', 'itl') or intervals_available) else None
                                for key in ['mean', 'median'] + [f'p{p}' for p in range(90, 100)]}
    categories = {}
    for error in result.get('errors', []):
        if error:
            match = re.search(r'\b([45][0-9]{2})\b', str(error))
            category = 'http_' + match[1] if match else 'timeout' if 'timeout' in str(error).lower() else 'client_error'
            categories[category] = categories.get(category, 0) + 1
    return dict(completed=completed, failed=failed, failure_categories=categories,
                duration_seconds=finite(result.get('duration')),
                requests_per_second=finite(result.get('request_throughput')) if completed else None,
                output_tokens_per_second=finite(result.get('output_throughput')) if completed else None,
                total_tokens_per_second=finite(result.get('total_token_throughput')) if completed else None,
                actual_input_tokens=distribution(result.get('input_lens', [])),
                actual_output_tokens=distribution(result.get('output_lens', [])), latency=metrics)


def counters(urls):
    result = []
    pattern = re.compile(r'^vllm:(?:gpu_)?prefix_cache_(queries|hits)(?:_total)?(?:\{.*\})?\s+([0-9.eE+\-]+)(?:\s|$)')
    for url in urls:
        values = {'queries': 0.0, 'hits': 0.0}
        seen = set()
        try:
            with urllib.request.urlopen(url, timeout=3) as response:
                for line in response.read(4000000).decode().splitlines():
                    match = pattern.match(line)
                    if match:
                        value = float(match[2])
                        if not math.isfinite(value) or value < 0:
                            raise ValueError('Invalid counter')
                        values[match[1]] += value
                        seen.add(match[1])
            result.append(values if len(seen) == 2 else None)
        except (OSError, ValueError):
            result.append(None)
    return result


def counter_delta(before, after):
    if not before or len(before) != len(after) or any(v is None for v in before + after):
        return dict(status='unavailable', reason='One or more replica prefix counters unavailable')
    if any(b[key] > a[key] for b, a in zip(before, after) for key in b):
        return dict(status='reset', reason='A replica counter decreased during this case')
    delta = {key: sum(a[key] - b[key] for b, a in zip(before, after)) for key in ('queries', 'hits')}
    return dict(status='observed', **delta, hit_ratio=delta['hits'] / delta['queries'] if delta['queries'] else None,
                scope='All scraped replicas; includes warmup and other client traffic')


def native(dataset, count, output, target, deadline, env):
    endpoint = '/v1/chat/completions' if env['BENCHMARK_BACKEND'] == 'openai-chat' else '/v1/completions'
    command = ['vllm', 'bench', 'serve', '--backend', env['BENCHMARK_BACKEND'], '--base-url', env['BASE_URL'],
               '--endpoint', endpoint, '--model', env['MODEL_ID'], '--served-model-name', env['MODEL_ID'],
               '--tokenizer', env.get('BENCHMARK_TOKENIZER_DIR', '/tmp/tokenizer'), '--dataset-name', 'custom',
               '--dataset-path', str(dataset), '--custom-output-len', str(output), '--skip-chat-template',
               '--disable-shuffle', '--seed', '0', '--ignore-eos', '--num-prompts', str(count),
               '--max-concurrency', str(env['BENCHMARK_MAX_CONCURRENCY']), '--request-rate', 'inf',
               '--num-warmups', '0', '--ready-check-timeout-sec', '0', '--disable-tqdm',
               '--save-result', '--save-detailed', '--percentile-metrics', 'ttft,tpot,itl,e2el',
               '--metric-percentiles', ','.join(map(str, [50] + list(range(90, 100)))),
               '--result-dir', str(target.parent), '--result-filename', target.name]
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        return 124, {}
    # Native detailed results and diagnostic text stay in the disposable client;
    # their errors/generated_texts may contain prompt or response content.
    with target.with_suffix('.log').open('w') as diagnostic:
        try:
            code = subprocess.run(command, stdout=diagnostic, stderr=subprocess.STDOUT,
                                  timeout=remaining, env=env).returncode
        except subprocess.TimeoutExpired:
            code = 124
    try:
        result = json.loads(target.read_text())
    except (OSError, ValueError):
        result = {}
    return code, result


def datasets(tokenizer, length, prefix, count, output, seed, directory, context, backend):
    from vllm.benchmarks.datasets import RandomDataset
    requests = RandomDataset(random_seed=seed).sample(tokenizer=tokenizer, num_requests=2 * (count + 1),
                                                       prefix_len=prefix, input_len=length - prefix,
                                                       output_len=output, range_ratio=0)
    # Native random offsets can repeat. Keep distinct complete prompts so the
    # unique control does not accidentally replay measured/warmup requests.
    distinct = {}
    for request in requests:
        distinct.setdefault(request.prompt, request)
        if len(distinct) == count + 1:
            break
    requests = list(distinct.values())
    if len(requests) != count + 1:
        raise ValueError('Native dataset has too few distinct prompts; reduce request count')
    actual = []
    for request in requests:
        prompt = request.prompt
        if backend == 'openai-chat':
            tokens = tokenizer.apply_chat_template([{'role': 'user', 'content': prompt}], add_generation_prompt=True, tokenize=True, return_dict=False)
        else:
            tokens = tokenizer(prompt).input_ids
        actual.append(len(tokens))
        if len(tokens) + output > context:
            raise ValueError('Actual tokenized request exceeds deployed context; reduce BENCHMARK_INPUT_TOKENS')
    for path, items in [(directory / 'warmup.jsonl', requests[:1]), (directory / 'measured.jsonl', requests[1:])]:
        with path.open('w') as stream:
            for request in items:
                stream.write(json.dumps(dict(prompt=request.prompt, output_tokens=output)) + '\n')
    return distribution(actual)


def run(settings):
    from transformers import AutoTokenizer
    started = time.monotonic()
    deadline = started + settings['max_seconds']
    env = dict(os.environ, BENCHMARK_MAX_CONCURRENCY=str(settings['concurrency']))
    root = Path(env.get('BENCHMARK_RESULT_DIR', '/tmp/benchmark'))
    root.mkdir(parents=True, exist_ok=True)
    tokenizer = AutoTokenizer.from_pretrained(env.get('BENCHMARK_TOKENIZER_DIR', '/tmp/tokenizer'), local_files_only=True)
    seed = secrets.randbelow(2**31)
    urls = [u for u in env.get('BENCHMARK_METRICS_URLS', '').split(',') if u]
    emit('benchmark_plan', **settings, seed=seed,
         comparison='Unique content versus warmed shared prefix; caching stays enabled and chat scaffolding may be shared',
         warmup='One separate unmeasured request per cell; shares only shared-profile prefix; no measured prompt is replayed',
         percentile_caveat=f'p99 represents approximately {settings["requests"] * .01:.2f} upper-tail request observations per cell; ITL samples are token intervals; exploratory at small sample sizes')
    pd = None
    targets = []
    if env.get('BENCHMARK_PD_ENABLED') == 'true':
        helper = Path(__file__).with_name('pd_observe.py')
        if helper.is_file():
            spec = importlib.util.spec_from_file_location('pd_observe', helper)
            pd = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(pd)
            targets = json.loads(Path(env.get('BENCHMARK_METRICS_TARGETS_FILE', '/benchmark/metrics-targets.json')).read_text())
    status = 0
    for index, (length, prefix) in enumerate(zip(settings['input_tokens'], settings['shared_prefix_tokens'])):
        paired = {}
        for offset, profile in enumerate(('unique', 'shared')):
            directory = root / f'{length}-{profile}'
            directory.mkdir(exist_ok=True)
            case_seed = (seed + index * 2 + offset) % (2**31)
            emit('benchmark_case_start', input_tokens=length, profile=profile, seed=case_seed)
            actual = datasets(tokenizer, length, prefix if profile == 'shared' else 0,
                              settings['requests'], settings['output_tokens'], case_seed, directory,
                              settings['context_length'], env['BENCHMARK_BACKEND'])
            before = counters(urls)
            pd_before = pd.snapshot(targets) if pd else None
            code, warmup = native(directory / 'warmup.jsonl', 1, settings['output_tokens'], directory / 'warmup.json', deadline, env)
            if code or warmup.get('completed') != 1 or warmup.get('failed', 0):
                emit('benchmark_case_failed', input_tokens=length, profile=profile, phase='warmup', exit_code=code or 1,
                     completed=warmup.get('completed', 0), failed=warmup.get('failed', 1))
                return code or 1
            code, result = native(directory / 'measured.jsonl', settings['requests'], settings['output_tokens'], directory / 'result.json', deadline, env)
            summary = summarize(result, settings['requests'])
            summary.update(input_tokens=length, shared_prefix_tokens=prefix if profile == 'shared' else 0,
                           profile=profile, tokenized_input_tokens=actual, native_exit_code=code,
                           prefix_cache=counter_delta(before, counters(urls)))
            if env.get('BENCHMARK_PD_ENABLED') == 'true':
                summary['pd_transfer'] = pd.delta(pd_before, pd.snapshot(targets)) if pd else dict(status='unknown', interpretation='P/D observation helper unavailable')

            emit('benchmark_case_summary', **summary)
            for metric, values in summary['latency'].items():
                print(f'{length} tokens / {profile} / {metric}: ' + ' '.join(f'{k}={v:.3f}' if v is not None else f'{k}=N/A' for k, v in values.items()), flush=True)
            paired[profile] = summary
            if code or summary['failed'] or summary['completed'] != settings['requests']:
                status = status or code or 1
            if code == 124:
                emit('benchmark_finished', exit_code=status, reason='Overall benchmark deadline reached')
                return status
        unique, shared = paired['unique'], paired['shared']
        a, b = unique['latency']['ttft_ms']['median'], shared['latency']['ttft_ms']['median']
        emit('benchmark_cache_comparison', input_tokens=length,
             median_ttft_reduction_percent=100 * (a - b) / a if a and b is not None else None,
             comparable=not (unique['failed'] or shared['failed'] or unique['native_exit_code'] or shared['native_exit_code']),
             interpretation='Observed live-router workload difference; not cache-disabled or isolated cache-hit measurement')
    emit('benchmark_finished', exit_code=status, elapsed_seconds=round(time.monotonic() - started, 3))
    return status


if __name__ == '__main__':
    try:
        settings = plan()
        if '--plan' in sys.argv:
            print(json.dumps(settings))
        else:
            raise SystemExit(run(settings))
    except (ValueError, OSError, ImportError) as exc:
        print(f'Benchmark failed: {type(exc).__name__}: {exc}', file=sys.stderr, flush=True)
        raise SystemExit(2)
