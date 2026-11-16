<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Benchmark defaults and tokenizer failure

## Phase 1: Diagnose
- [x] Confirm unsupported backend default prevents normal text benchmarking.
- [x] Reproduce empty tokenizer vocabulary in the digest-pinned CPU client.

## Phase 2: Fix
- [x] Default text benchmarking to openai-chat in Terraform and RMS.
- [x] Correct tokenizer loading using supported upstream client behavior.
- [x] Add focused executable regressions.

## Phase 3: Validate
- [x] Run shell/client regressions and Terraform tests.
- [ ] Validate generated RMS archives and commit changes.
- [x] Record runtime validation separately from local/mocked checks.

No GPU allocation, recycling, resizing or deletion is required.

## Diagnosis and validation record

The failed execution used `Qwen/Qwen3.8-27B`, revision `main`, backend
`openai-chat`. In the exact CPU image digest `827ef38187f9b52f2bb838695ef815ec5b65f4bf3e4c061b002b2b0a19cb0701`
(vLLM 0.32.0+cpu, Transformers 5.19.0, huggingface_hub 2.2.0),
`hf download` takes one pattern per `--include`. The old command interpreted
subsequent patterns as explicit filenames, ignored the first pattern
`tokenizer.json`, and downloaded only five files. The cached tokenizer had
vocab_size=1, leaving the random dataset with zero usable tokens.

A CPU-only diagnostic Job in the existing model namespace reproduced the exact
IndexError. Repeating `--include` for every pattern downloaded all six matching
files, including tokenizer.json. The same image then reported vocab_size=248044
and successfully generated two random requests with the configured token lengths.
No serving workload or GPU pool was modified. This verifies tokenizer download
and dataset generation, not full serving performance or an RMS benchmark run.
The observed Hub main commit during investigation was
`37561816e66b5b9153b1b64c10968c18c1e6f4a0`; main remains mutable.

Focused executable checks: 36 passed, one existing optional chart check skipped;
updated benchmark command/default checks: two passed. Initial model-delivery
Terraform tests: 33 passed using locked OCI provider 9.12.1. The final run also
covers changed inline benchmark source checksums and content limits.

The emulated local x86 VM cannot execute this image's native vLLM code (illegal
instruction); cluster CPU diagnostics supplied runtime evidence instead.
