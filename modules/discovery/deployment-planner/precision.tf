# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Hardware capability is independent of memory sizing. Unknown kernels fail closed.
# Sources: https://docs.vllm.ai/en/stable/features/quantization/fp8/
# Block FP8 MoE is screened conservatively for Hopper/Blackwell, not Ada.
locals {
  quant_method       = lower(try(coalesce(local.profile.architecture.quantization.quant_method, "none"), "none"))
  checkpoint_dtypes  = keys(try(local.profile.weights.elements_by_dtype, {}))
  fp8_required       = local.quant_method == "fp8" || anytrue([for dtype in local.checkpoint_dtypes : startswith(dtype, "F8_")])
  fp8_block          = try(length(local.profile.architecture.quantization.weight_block_size) > 0, false)
  precision_known    = !try(local.profile.architecture.checkpoint_variant_selected, false) && ((local.fp8_required && contains(["none", "fp8"], local.quant_method)) || (local.quant_method == "none" && (length(local.checkpoint_dtypes) > 0 ? alltrue([for dtype in local.checkpoint_dtypes : contains(["F16", "BF16", "F32", "F64"], dtype)]) : try(local.api_variant_metadata.precision == "bf16", false))))
  required_precision = local.fp8_required ? "fp8" : local.quant_method != "none" ? local.quant_method : contains(local.checkpoint_dtypes, "BF16") || try(local.api_variant_metadata.precision == "bf16", false) ? "bfloat16" : contains(local.checkpoint_dtypes, "F64") ? "float64" : contains(local.checkpoint_dtypes, "F32") ? "float32" : "float16"
  precision_checks = { for shape, gpu in local.catalog : shape => {
    required_precision = local.required_precision
    status = !local.precision_known || !try(gpu.compute_capability > 0, false) ? "not_verified" : (
      local.fp8_required ? (try(gpu.compute_capability >= (local.fp8_block ? 90 : 89), false) ? "compatible" : "not_compatible") :
      try(gpu.compute_capability >= (local.required_precision == "bfloat16" || try(local.profile.memory.assumptions.kv_dtype == "bfloat16", false) ? 80 : 75), false) ? "compatible" : "not_compatible"
    )
    reason = !local.precision_known ? "Checkpoint dtype/quantization kernels have no reviewed compatibility rule." : !try(gpu.compute_capability > 0, false) ? "GPU backend has no reviewed compatibility rule for the selected engine image." : local.fp8_required ? "FP8 requires a reviewed native FP8 kernel path; block FP8 is conservatively restricted to Hopper/Blackwell. No implicit W8A16 conversion." : "Floating compute and KV precision require the GPU capabilities checked here; engine/image support is checked separately."
    source = "https://docs.vllm.ai/en/stable/features/quantization/fp8/"
  } }
}
