#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Maintainer/build hook only. No Terraform, Python or model code execution.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for tool in curl jq awk; do command -v "$tool" >/dev/null || exit 2; done
catalog_temp=$(mktemp -d)
trap 'rm -rf "$catalog_temp"' EXIT
policy="$repo/catalogs/model-policy.json"
limit=$(jq -r .candidate_limit "$policy")
[[ "$limit" -ge 1 && "$limit" -le 200 ]] || exit 2
fetch() { curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 --max-filesize 16777216 --proto '=https' --proto-redir '=https' "$1" -o "$2"; }
fetch "https://huggingface.co/api/models?pipeline_tag=text-generation&sort=downloads&direction=-1&limit=$limit" "$catalog_temp/list.json"
jq -e 'type=="array" and length>0' "$catalog_temp/list.json" >/dev/null
jq -r --slurpfile policy "$policy" '[.[] | . as $model | select(any($policy[0].publishers[]; .==($model.id|split("/")[0]))) | select(.id|test($policy[0].excluded_name_pattern)|not) | .id][]' "$catalog_temp/list.json" > "$catalog_temp/ids"
: > "$catalog_temp/accepted.jsonl"
: > "$catalog_temp/rejected.jsonl"
while IFS= read -r model_id; do
  [[ "$model_id" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || exit 2
  echo "Inspecting $model_id" >&2
  fetch "https://huggingface.co/api/models/$model_id" "$catalog_temp/info.json"
  sha=$(jq -er '.sha|select(test("^[a-f0-9]{40}$"))' "$catalog_temp/info.json")
  if ! jq -e '(.gated==false) and (.private!=true) and (.pipeline_tag=="text-generation")' "$catalog_temp/info.json" >/dev/null; then
    jq -nc --arg id "$model_id" '{id:$id,reason:"Gated/private or wrong task"}' >> "$catalog_temp/rejected.jsonl"; continue
  fi
  fetch "https://huggingface.co/$model_id/raw/$sha/config.json" "$catalog_temp/config.json"
  jq -n --slurpfile info "$catalog_temp/info.json" --slurpfile config "$catalog_temp/config.json" --slurpfile policy "$policy" --slurpfile engines "$repo/catalogs/engines.json" '
    $info[0] as $i | $config[0] as $c |
    [if ($policy[0].model_types|index($c.model_type))==null then "Estimator architecture unsupported" else empty end,
     if ($c.quantization_config!=null or $c.text_config!=null or $c.vision_config!=null or $c.auto_map!=null) then "Quantized/composite/custom checkpoint" else empty end,
     if ($i.safetensors.total // 0)<=0 or (all(($i.safetensors.parameters // {}|keys[]); .=="BF16" or .=="F16" or .=="F32" or .=="F64")|not) then "Missing or packed safetensors metadata" else empty end,
     if any($i.siblings[]?; .rfilename=="model.safetensors" or .rfilename=="model.safetensors.index.json")|not then "No canonical safetensors checkpoint" else empty end,
     if ($i.config.tokenizer_config.chat_template // ""|length)==0 then "No declared chat template" else empty end,
     if any($engines[0].engines[]; .architectures as $arches|any($c.architectures[]?; . as $arch|$arches|index($arch)))|not then "Engine architecture not catalogued" else empty end,
     if ($c.num_hidden_layers // 0)<=0 or ($c.num_attention_heads // 0)<=0 or ($c.hidden_size // 0)<=0 then "Missing attention dimensions" else empty end] as $reasons |
    {id:$i.id,sha:$i.sha,family:$c.model_type,tier:(if ($i.safetensors.total // 0)<8000000000 then "small" elif $i.safetensors.total<40000000000 then "medium" else "large" end),parameters:$i.safetensors.total,downloads:($i.downloads // 0),license:($i.cardData.license // null),support_evidence:"architecture_and_metadata_only",reasons:$reasons}
  ' > "$catalog_temp/result.json"
  if jq -e '.reasons|length==0' "$catalog_temp/result.json" >/dev/null; then
    jq -c 'del(.reasons)' "$catalog_temp/result.json" >> "$catalog_temp/accepted.jsonl"
  else jq -c . "$catalog_temp/result.json" >> "$catalog_temp/rejected.jsonl"; fi
done < "$catalog_temp/ids"
jq -s --slurpfile policy "$policy" --arg observed "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{schema_version:"1.0",observed_at:$observed,source:"https://huggingface.co/api/models",models:(group_by([.family,.tier])|map(sort_by(-.downloads)[:$policy[0].per_family_tier])|flatten|sort_by(-.downloads)[:$policy[0].maximum_models])}' "$catalog_temp/accepted.jsonl" > "$catalog_temp/models.json"
jq -e '.models|length>0' "$catalog_temp/models.json" >/dev/null || { echo 'No eligible models; existing catalog retained.' >&2; exit 1; }
# Validate/generate into a temporary schema before replacing either artifact.
cp "$repo/terraform/stacks/discovery/schema.yaml" "$catalog_temp/schema.yaml"
bash "$repo/scripts/generate-model-schema.sh" "$catalog_temp/models.json" "$catalog_temp/schema.yaml"
cp "$catalog_temp/models.json" "$repo/catalogs/models.json"
cp "$catalog_temp/schema.yaml" "$repo/terraform/stacks/discovery/schema.yaml"
mkdir -p "$repo/work"
jq -s . "$catalog_temp/rejected.jsonl" > "$repo/work/model-catalog-rejections.json"
echo 'Updated catalog and RMS dropdown; inspect the diff before packaging.' >&2
