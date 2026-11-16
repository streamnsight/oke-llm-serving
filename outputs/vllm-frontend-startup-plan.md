<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# vLLM frontend compatibility and startup validation

Success means generated model stacks default to the compatible Python API frontend, experts can explicitly opt into Rust, and the retained four-GPU model starts and passes its independent validation pipeline. Benchmarks remain manual; no GPU instance or node pool is replaced.

## Phase 1 — isolate the failures

- [x] Confirm the qualified image pulls after the existing node filesystem repair.
- [x] Identify the recipe-enabled Rust frontend rejecting the model's Jinja generation template and ignoring required tool/structured-output settings.
- [x] Test only `VLLM_USE_RUST_FRONTEND=0` on the existing Deployment, preserving the image digest, model commit and serving arguments.
- [x] Observe Python startup pass frontend/template processing and initialize all four GPU workers/NCCL.
- [ ] Diagnose the subsequent tokenizer failure with the exact installed image and isolated CPU-only configuration/tokenizer tests, without downloading weights or changing packages speculatively.

## Phase 2 — persist the frontend setting

- [x] Add a Python-default/Rust-opt-in model-stack setting and editable named pipeline parameter.
- [x] Apply only the selected frontend setting over the recipe environment, retaining the remaining recipe flags/environment and provenance.
- [x] Reject invalid pipeline values before Helm.
- [x] Verify module/runtime tests and configured ZIP tests, including explicit Rust opt-in and Terraform 1.5.7 compatibility.
- [ ] Commit and rebuild the entry ZIP and configured RMS model source, preserving selected option defaults and existing Console values.

## Phase 3 — validate real deployment

- [ ] Resolve the tokenizer failure based on an exact-image reproduction and persist any resulting change.
- [ ] Review the RMS Plan for no GPU infrastructure mutations, then run automatic onboarding, workload deployment and separate validation.
- [ ] Verify model health/model identity and refreshed Plan stability. The current inference probe is disabled, so health checks alone do not establish token-generation correctness.

The current image already contains sentencepiece and tiktoken. Their presence rules out blindly installing the packages named by the generic tokenizer exception. The EngineCore revision display also needs inspection: the installed Hugging Face revision wrapper has serialization behavior that can affect its string representation. Neither observation establishes the tokenizer root cause yet.
