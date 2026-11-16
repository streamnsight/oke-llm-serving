<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# vLLM frontend compatibility and startup validation

Success means generated model stacks default to the compatible Python API frontend, experts can explicitly opt into Rust, and the retained four-GPU model starts and passes its independent validation pipeline. Benchmarks remain manual; no GPU instance or node pool is replaced.

## Phase 1 — isolate the failures

- [x] Confirm the qualified image pulls after the existing node filesystem repair.
- [x] Identify the recipe-enabled Rust frontend rejecting the model's Jinja generation template and ignoring required tool/structured-output settings.
- [x] Test only `VLLM_USE_RUST_FRONTEND=0` on the existing Deployment, preserving the image digest, model commit and serving arguments.
- [x] Observe Python startup pass frontend/template processing and initialize all four GPU workers/NCCL.
- [x] Reproduce the subsequent tokenizer failure in the exact image: Hugging Face Hub 1.27.0 corrupts the revision string during pickle/copy; Transformers then misses downloaded files when the cache has no `main` ref. The same files and dependencies load using the plain commit or ordinary `main`. No packages or model assets were missing.

## Phase 2 — persist the frontend setting

- [x] Add a Python-default/Rust-opt-in model-stack setting and editable named pipeline parameter.
- [x] Apply only the selected frontend setting over the recipe environment, retaining the remaining recipe flags/environment and provenance.
- [x] Reject invalid pipeline values before Helm.
- [x] Verify module/runtime tests and configured ZIP tests, including explicit Rust opt-in and Terraform 1.5.7 compatibility.
- [x] Commit the frontend feature (`b52a517`), rebuild the entry ZIP and validate its embedded roots with Terraform 1.5.7. Validate the configured model ZIP with 4/4 root tests and Terraform 1.5.7, preserving all 25 existing schema defaults.
- [x] Upload configured source `76b1844` to the existing RMS model stack, preserving every Console value except the explicitly chosen `model_revision=main`. Its five generated-stack tests and Terraform 1.5.7 validation passed.

## Phase 3 — validate real deployment

- [x] Identify the exact tokenizer root cause without modifying the upstream image. Hugging Face PR 4692 fixes revision serialization in Hub 1.28.0; the recipe image has 1.27.0.
- [x] Test the user-requested `main` revision on the existing model and persist a normal direct-HF override. The serving cache resolves it to the same assessed commit. Retained snapshots still require an immutable commit.
- [x] Observe all four workers load the 51.75 GiB checkpoint, compile, allocate KV cache and warm up. The Pod became Ready at approximately 06:06 UTC on November 16 with zero restarts.
- [x] Send one bounded chat request: HTTP success, response `OK`, 17 prompt tokens and 2 generated tokens. This is a functional check, not a benchmark or a multimodal/conversation-persistence test.
- [x] Review the RMS Plan: 18 model metadata/source changes, zero GPU/Compute/node-pool mutations, only onboarding/workload/validation executions, and no benchmark execution.
- [x] Complete the automatic RMS sequence. Onboarding, workload prepare/native Helm/readiness and independent validation succeeded; RMS Apply completed successfully.
- [x] Verify actual API health and one successful text generation separately. The automatic inference probe remains disabled and must not be represented as a generation or benchmark test.
- [x] Verify independent pipeline completion and refreshed RMS Plan stability: zero managed resource changes and no repeated executions/artifact updates.

The recipe selected `vllm/vllm-openai:qwen38`; discovery froze its digest. The model commit pin was our reproducibility choice, not a recipe requirement. Hub `main` resolved to the same assessed commit, `37561816e66b5b9153b1b64c10968c18c1e6f4a0`, before the live test. Only `--revision` changed for that test; the image, Python frontend, model, TP4 and retained GPU pool stayed the same. No custom image, runtime package installation or model-specific monkeypatch is planned.

Primary fix reference: [Hugging Face Hub PR 4692](https://github.com/huggingface/huggingface_hub/pull/4692). A CPU-only test reproduced successful pinned/plain and main loads, the exact config/tokenizer failures after revision-object serialization, and success after populating the corresponding main cache ref.

Validation: the frontend snapshot passed the full development suite (157 tests passed, 3 optional skips). The subsequent generic main override passed 33 Terraform tests and 35 runtime tests (1 optional fixture skip); the actual configured ZIP passed all 5 root tests plus Terraform 1.5.7 validation. The rebuilt discovery entry and both embedded roots also validate with Terraform 1.5.7. RMS Apply succeeded, followed by a refreshed Plan with zero managed resource changes. Existing state/tfvars hashes and the GPU worker identity/OS boot ID are unchanged.
