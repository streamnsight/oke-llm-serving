#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Runs only in the CPU staging Job. No model code is executed.
set +x
set -euo pipefail
umask 077
for tool in bash curl jq sha256sum base64 oci wc; do command -v "$tool" >/dev/null || { echo "Staging image lacks $tool" >&2; exit 2; }; done
input_dir=${MODEL_INPUT_DIR:-/input}
work_dir=${MODEL_WORK_DIR:-/work}
jq -e -f "$input_dir/validate.jq" "$input_dir/model.json" >/dev/null
config=$input_dir/model.json
snapshot=$(jq -er .snapshot_sha256 "$config")
storage_namespace=$(jq -er .storage_namespace "$config")
bucket=$(jq -er .bucket "$config")
prefix=$(jq -er .prefix "$config")
model=$(jq -er .model.id "$config")
revision=$(jq -er .model.revision "$config")
export OCI_CLI_AUTH=oke_workload_identity OCI_CLI_REGION
OCI_CLI_REGION=$(jq -er .region "$config")
# This validates the Pod's service-account identity, never the DevOps runner's identity.
oci os bucket get --namespace-name "$storage_namespace" --bucket-name "$bucket" >/dev/null
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT
curl_auth=(--header 'Accept: application/octet-stream')
secret=$(jq -r '.hf_token_secret_id // empty' "$config")
if [[ -n "$secret" ]]; then
  oci secrets secret-bundle get --secret-id "$secret" --stage CURRENT --query 'data."secret-bundle-content".content' --raw-output > "$temp_dir/secret.b64"
  base64 --decode < "$temp_dir/secret.b64" > "$temp_dir/token"
  token=$(cat "$temp_dir/token")
  [[ "$token" =~ ^hf_[A-Za-z0-9]+$ ]] || { echo 'Vault secret must contain a Hugging Face hf_ token' >&2; exit 2; }
  printf 'Authorization: Bearer %s\n' "$token" > "$temp_dir/hf-header"
  unset token
  rm -f "$temp_dir/token" "$temp_dir/secret.b64"
  curl_auth+=(--header "@$temp_dir/hf-header")
fi
scratch=$work_dir/$snapshot
[[ ! -L "$scratch" ]] || { echo 'Refusing symlinked scratch directory' >&2; exit 2; }
mkdir -p "$scratch"
records=$temp_dir/files.jsonl
: > "$records"
head_object() { oci os object head --namespace-name "$storage_namespace" --bucket-name "$bucket" --name "$1"; }
verify_head() {
  jq -e --arg snapshot "$snapshot" --argjson size "$size" --arg expected "$expected" '
    (."content-length"|tonumber)==$size and ."opc-meta-snapshot-sha256"==$snapshot and
    (."opc-meta-sha256"|type=="string" and test("^[a-f0-9]{64}$")) and
    ($expected=="" or ."opc-meta-sha256"==$expected)' "$1" >/dev/null
}
while IFS= read -r item; do
  path=$(jq -er .path <<< "$item")
  size=$(jq -er .size_bytes <<< "$item")
  expected=$(jq -r '.sha256 // empty' <<< "$item")
  object=$prefix/files/$path
  part=$scratch/$(printf '%s' "$path" | sha256sum | cut -d ' ' -f 1).part
  [[ ! -L "$part" ]] || { echo 'Refusing symlinked partial download' >&2; exit 2; }
  encoded_path=$(jq -nr --arg path "$path" '$path|split("/")|map(@uri)|join("/")')
  url=https://huggingface.co/$model/resolve/$revision/$encoded_path
  # A successful exact-name listing distinguishes absence from permission/network failure.
  oci os object list --namespace-name "$storage_namespace" --bucket-name "$bucket" --prefix "$object" --fields name --all > "$temp_dir/objects.json"
  jq -e '.data|type=="array"' "$temp_dir/objects.json" >/dev/null
  if jq -e --arg object "$object" 'any(.data[]?; .name==$object)' "$temp_dir/objects.json" >/dev/null; then
    head_object "$object" > "$temp_dir/head.json"
    verify_head "$temp_dir/head.json" || { echo "Existing object differs from selected snapshot: $path" >&2; exit 1; }
    checksum=$(jq -er '."opc-meta-sha256"' "$temp_dir/head.json")
    rm -f "$part"
  else
    # Flat scratch filenames never materialize repository-controlled directories.
    for attempt in 1 2 3 4; do
      current=0
      [[ ! -f "$part" ]] || current=$(wc -c < "$part")
      [[ "$current" -le "$size" ]] || { echo "Partial download exceeds declared size: $path" >&2; exit 1; }
      [[ "$current" -ne "$size" ]] || break
      curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' \
        --connect-timeout 30 --max-time 3600 --max-filesize "$size" --continue-at - \
        "${curl_auth[@]}" --output "$part" "$url" && break
      [[ "$attempt" != 4 ]] || { echo "Download failed after bounded retries: $path" >&2; exit 1; }
      sleep 2
    done
    [[ "$size" != 0 || -f "$part" ]] || : > "$part"
    [[ $(wc -c < "$part") -eq "$size" ]] || { echo "Downloaded size mismatch: $path" >&2; exit 1; }
    checksum=$(sha256sum "$part" | cut -d ' ' -f 1)
    if [[ -n "$expected" && "$checksum" != "$expected" ]]; then
      rm -f "$part"
      echo "Hub checksum mismatch: $path" >&2
      exit 1
    fi
    metadata=$(jq -cn --arg checksum "$checksum" --arg snapshot "$snapshot" '{sha256:$checksum,"snapshot-sha256":$snapshot}')
    oci os object put --namespace-name "$storage_namespace" --bucket-name "$bucket" --name "$object" --file "$part" \
      --metadata "$metadata" --no-overwrite --verify-checksum --parallel-upload-count 2 --part-size 128 >/dev/null
    head_object "$object" > "$temp_dir/head.json"
    verify_head "$temp_dir/head.json" || { echo "Uploaded metadata/size verification failed: $path" >&2; exit 1; }
    [[ $(jq -er '."opc-meta-sha256"' "$temp_dir/head.json") == "$checksum" ]] || exit 1
    rm -f "$part"
  fi
  jq -cn --arg path "$path" --arg object "$object" --arg url "$url" --arg checksum "$checksum" --arg expected "$expected" --argjson size "$size" \
    '{path:$path,object_key:$object,size_bytes:$size,sha256:$checksum,source_url:$url,source_sha256:(if $expected=="" then null else $expected end)}' >> "$records"
  echo "Verified staged file: $path"
done < <(jq -c '.model.files[]' "$config")
jq -n --slurpfile config "$config" --slurpfile files "$records" --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg run_id "${MODEL_RUN_ID:-unknown}" --arg image "${STAGING_IMAGE:-unknown}" \
  '{schema_version:"1.0",status:"complete",snapshot_sha256:$config[0].snapshot_sha256,model:($config[0].model|del(.files)),files:$files,completed_at:$completed_at,run_id:$run_id,staging_image:$image,auth:"oke_workload_identity",source:"Hugging Face immutable revision; only allowlisted files",source_hashes:"Supplied Hub hashes checked when available; every staged file SHA256 computed"}' > "$temp_dir/manifest.json"
# Completion is published only after every remote object was verified; do not overwrite a completed snapshot.
oci os object put --namespace-name "$storage_namespace" --bucket-name "$bucket" --name "$prefix/manifest.json" \
  --file "$temp_dir/manifest.json" --content-type application/json --no-overwrite --verify-checksum >/dev/null
oci os object get --namespace-name "$storage_namespace" --bucket-name "$bucket" --name "$prefix/manifest.json" --file "$temp_dir/stored-manifest.json" >/dev/null
jq -e --arg snapshot "$snapshot" --slurpfile files "$records" '.status=="complete" and .snapshot_sha256==$snapshot and (.files|sort_by(.path))==($files|sort_by(.path))' "$temp_dir/stored-manifest.json" >/dev/null
echo "Snapshot verified: $snapshot"
