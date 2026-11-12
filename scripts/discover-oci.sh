#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Terraform external data source. Only JSON goes to stdout; never launches Terraform.
set -euo pipefail
set +x
umask 077
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for tool in oci jq; do command -v "$tool" >/dev/null || { echo "Discovery requires $tool on the execution host." >&2; exit 2; }; done
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/input.json"
jq -e '
  if type!="object" or any(.[];type!="string") then error("Expected Terraform external string-map query") else . end |
  .regions=((.regions|fromjson)//[]|unique) | .shape_names=((.shape_names|fromjson)//[]|unique) |
  .gpu_catalog|=fromjson | .query_resource_availability|=fromjson | .only_shapes_with_limits|=fromjson |
  if (.tenancy_ocid|length)>0 and (.region|length)>0 and
    (.regions|type)=="array" and all(.regions[];type=="string") and
    (.shape_names|type)=="array" and all(.shape_names[];type=="string") and
    (.query_resource_availability|type)=="boolean" and (.only_shapes_with_limits|type)=="boolean" and
    (.gpu_catalog.shapes|type)=="object" then . else error("Invalid discovery query") end |
  .compartment_id=(if (.compartment_id//"")!="" then .compartment_id else .tenancy_ocid end)
' "$scratch/input.json" > "$scratch/query.json"
query="$scratch/query.json"
tenancy=$(jq -r .tenancy_ocid "$query"); compartment=$(jq -r .compartment_id "$query"); bootstrap=$(jq -r .region "$query")
# Native-provider auth settings are mapped explicitly; local CLI defaults/profile remain usable.
setting() { local key value; for key in "TF_VAR_$1" "OCI_$1" "$1"; do value=${!key:-}; if [[ -n "$value" ]]; then printf '%s' "$value"; return; fi; done; }
auth_args=()
mode=${TF_VAR_auth:-${OCI_AUTH:-}}
case "$mode" in
  InstancePrincipal|instance_principal)
    case "$(setting use_obo_token)" in
      true)
        token_path=$(setting obo_token_path)
        if [[ -z "$token_path" ]]; then
          token=$(setting obo_token)
          [[ -n "$token" ]] || { echo 'RMS delegated authentication requires its caller token.' >&2; exit 2; }
          token_path="$scratch/caller-token"; printf '%s' "$token" > "$token_path"; unset token
        fi
        [[ -r "$token_path" && -s "$token_path" ]] || { echo 'Cannot read RMS delegated caller token.' >&2; exit 2; }
        # The CLI takes a token-file reference, not the token in argv or Terraform state.
        printf '[DEFAULT]\nregion=%s\ndelegation_token_file=%s\n' "$bootstrap" "$token_path" > "$scratch/cli-config"
        auth_args=(--auth instance_obo_user --config-file "$scratch/cli-config" --profile DEFAULT)
        ;;
      false|'') auth_args=(--auth instance_principal);;
      *) echo 'use_obo_token must be true or false' >&2; exit 2;;
    esac;;
  ResourcePrincipal|resource_principal) auth_args=(--auth resource_principal);;
  APIKey|api_key) auth_args=(--auth api_key);;
  '') if [[ -n ${OCI_RESOURCE_PRINCIPAL_VERSION:-} && -z ${OCI_CLI_AUTH:-} ]]; then auth_args=(--auth resource_principal); fi;;
  *) echo 'Unsupported provider authentication mode for CLI discovery.' >&2; exit 2;;
esac
export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True
cli() {
  local region=$1 output=$2; shift 2
  # --all on list calls delegates service pagination to the CLI.
  oci ${auth_args[@]+"${auth_args[@]}"} --region "$region" --output json --connection-timeout 10 --read-timeout 60 "$@" > "$output.raw"
  jq -e 'if has("data") then .data else error("OCI CLI response has no data") end |
    walk(if type=="object" then with_entries(.key|=gsub("-";"_")) else . end)' "$output.raw" > "$output"
  rm "$output.raw"
}
jq_lib() { jq -L "$repo/scripts/lib" "$@"; }
cli "$bootstrap" "$scratch/subscriptions.json" iam region-subscription list --tenancy-id "$tenancy"
jq '[.[]|select(.status=="READY")|.region_name]|unique' "$scratch/subscriptions.json" > "$scratch/ready.json"
jq -en --slurpfile q "$query" --slurpfile ready "$scratch/ready.json" '
  (if ($q[0].regions|length)>0 then $q[0].regions else $ready[0] end) as $selected |
  if ($selected|length)==0 or any($selected[]; . as $r|($ready[0]|index($r))==null)
  then error("Requested regions must be READY tenancy subscriptions; at least one is required") else $selected end
' > "$scratch/selected.json"
scan_region() (
  set -euo pipefail
  region=$1; dir=$2; mkdir -p "$dir"
  cli "$region" "$dir/ads.json" iam availability-domain list --compartment-id "$tenancy"
  ad_index=0
  while IFS= read -r ad; do
    ad_dir="$dir/ad-$ad_index"; mkdir "$ad_dir"
    printf '%s' "$ad" > "$ad_dir/name"
    cli "$region" "$ad_dir/target.json" compute shape list --compartment-id "$compartment" --availability-domain "$ad" --all
    jq_lib --slurpfile q "$query" 'include "oci-discovery"; gpu_shapes($q[0])' "$ad_dir/target.json" > "$ad_dir/shapes.json"
    if [[ "$tenancy" == "$compartment" ]]; then cp "$ad_dir/shapes.json" "$ad_dir/physical.json"
    else
      cli "$region" "$ad_dir/root.json" compute shape list --compartment-id "$tenancy" --availability-domain "$ad" --all
      jq_lib --slurpfile q "$query" 'include "oci-discovery"; gpu_shapes($q[0])' "$ad_dir/root.json" > "$ad_dir/physical.json"
    fi
    ad_index=$((ad_index+1))
  done < <(jq -r 'sort_by(.name)[].name' "$dir/ads.json")
  if ((ad_index>0)); then jq -s 'add|[.[].quota_names[]?]|unique' "$dir"/ad-*/shapes.json > "$dir/quotas.json"
  else printf '[]' > "$dir/quotas.json"; fi
  cli "$region" "$dir/definitions.json" limits definition list --compartment-id "$tenancy" --service-name compute --all
  cli "$region" "$dir/values.json" limits value list --compartment-id "$tenancy" --service-name compute --all
  jq_lib --slurpfile q "$query" --slurpfile defs "$dir/definitions.json" --slurpfile quotas "$dir/quotas.json" 'include "oci-discovery"; limit_plan($q[0];($defs[0]|map({key:.name,value:.})|from_entries);$quotas[0])' "$dir/values.json" > "$dir/limit-plan.json"
  used=0; : > "$dir/observations.jsonl"
  while IFS= read -r limit; do
    printf '%s' "$limit" > "$dir/limit.json"
    reason=$(jq_lib -r --slurpfile q "$query" --argjson used "$used" 'include "oci-discovery"; skip_reason($q[0];$used)' "$dir/limit.json")
    printf '{}' > "$dir/availability.json"
    if [[ -z "$reason" ]]; then
      name=$(jq -r .name "$dir/limit.json"); scope=$(jq -r .scope_type "$dir/limit.json")
      ad_args=(); if [[ "$scope" == AD ]]; then ad_args=(--availability-domain "$(jq -r .availability_domain "$dir/limit.json")"); fi
      cli "$region" "$dir/availability.json" limits resource-availability get --compartment-id "$compartment" --service-name compute --limit-name "$name" ${ad_args[@]+"${ad_args[@]}"}
      used=$((used+1))
    fi
    jq_lib -c --arg reason "$reason" --slurpfile availability "$dir/availability.json" 'include "oci-discovery"; limit_observation($reason;$availability[0])' "$dir/limit.json" >> "$dir/observations.jsonl"
  done < <(jq -c '.[]' "$dir/limit-plan.json")
  jq -s '.' "$dir/observations.jsonl" > "$dir/observations.json"
  i=0; : > "$dir/combined.jsonl"
  while ((i<ad_index)); do
    ad_dir="$dir/ad-$i"; ad=$(cat "$ad_dir/name")
    jq_lib --slurpfile q "$query" --slurpfile limits "$dir/limit-plan.json" --arg ad "$ad" 'include "oci-discovery"; capacity_names($q[0];$limits[0];$ad)' "$ad_dir/physical.json" > "$ad_dir/names.json"
    count=$(jq '.assessed|length' "$ad_dir/names.json")
    if ((count>0)); then
      jq '[.assessed[]|{instanceShape:.}]' "$ad_dir/names.json" > "$ad_dir/request.json"
      cli "$region" "$ad_dir/report.json" compute compute-capacity-report create --compartment-id "$tenancy" --availability-domain "$ad" --shape-availabilities "file://$ad_dir/request.json"
      jq_lib --slurpfile q "$query" --arg region "$region" --arg ad "$ad" --slurpfile names "$ad_dir/names.json" 'include "oci-discovery"; capacity_assessment($q[0];$region;$ad;$names[0].assessed)' "$ad_dir/report.json" > "$ad_dir/assessment.json"
    else printf 'null' > "$ad_dir/assessment.json"; fi
    jq_lib -cn --slurpfile q "$query" --slurpfile names "$ad_dir/names.json" --slurpfile shapes "$ad_dir/shapes.json" --slurpfile assessment "$ad_dir/assessment.json" --arg ad "$ad" '
      include "oci-discovery"; {name:$ad,shapes:($shapes[0]|inventory_shapes($q[0].gpu_catalog)),
        capacity:{name:$ad,visible_gpu_shapes:$names[0].visible,assessed_gpu_shapes:$names[0].assessed,skipped_zero_limit_shapes:$names[0].skipped,assessment:$assessment[0],
          status:(if $assessment[0]!=null then $assessment[0].status elif ($names[0].visible|length)>0 then "skipped_zero_limits" else "no_gpu_shapes_listed" end)}}' >> "$dir/combined.jsonl"
    i=$((i+1))
  done
  jq_lib -n --slurpfile q "$query" --arg region "$region" --slurpfile ads "$dir/combined.jsonl" --slurpfile limits "$dir/observations.json" --slurpfile quotas "$dir/quotas.json" --argjson used "$used" 'include "oci-discovery"; regional_result($q[0];$region;$ads;$limits[0];$quotas[0];$used)' > "$dir/result.json"
)
# Batches of four bound CLI processes; a failed region prevents publishing a partial success.
pids=(); index=0
while IFS= read -r region; do
  scan_region "$region" "$scratch/region-$index" & pids+=("$!")
  index=$((index+1))
  if ((${#pids[@]}==4)); then
    failed=0; for pid in ${pids[@]+"${pids[@]}"}; do wait "$pid" || failed=1; done
    ((failed==0)) || { echo 'Regional discovery failed; no snapshot published.' >&2; exit 1; }; pids=()
  fi
done < <(jq -r '.[]' "$scratch/selected.json")
failed=0; for pid in ${pids[@]+"${pids[@]}"}; do wait "$pid" || failed=1; done
((failed==0)) || { echo 'Regional discovery failed; no snapshot published.' >&2; exit 1; }
jq -s --slurpfile ready "$scratch/ready.json" --slurpfile selected "$scratch/selected.json" '
  {schema_version:"1.0",subscribed_regions:$ready[0],assessed_regions:$selected[0],regions:sort_by(.inventory.region)} | {result:tojson}
' "$scratch"/region-*/result.json
