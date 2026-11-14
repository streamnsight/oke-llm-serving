# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Input: {config, arguments: OCI deployment argument items}. Values remain data.
{BENCHMARK_REQUESTS:"benchmark_requests",BENCHMARK_INPUT_TOKENS:"benchmark_input_tokens",BENCHMARK_OUTPUT_TOKENS:"benchmark_output_tokens"} as $names |
.config as $config |
[.arguments[]? | select(.name as $n | $names | has($n))] as $args |
if ($args|map(.name)|unique|length)!=($args|length) then error("Duplicate benchmark parameter.") else . end |
reduce $args[] as $arg ($config; .[$names[$arg.name]]=($arg.value|tonumber)) |
if all([.benchmark_requests,.benchmark_input_tokens,.benchmark_output_tokens][]; type=="number" and .>=1 and floor==.) and .benchmark_requests<=10000 and (.benchmark_input_tokens+.benchmark_output_tokens+128)<=.context_length
then . + {benchmark_parameter_source:(if ($args|length)>0 then "devops_deployment_arguments" else "stack_defaults" end)}
else error("Benchmark parameters must be positive integers, requests <=10000, and token counts must fit context with 128 template tokens.") end
