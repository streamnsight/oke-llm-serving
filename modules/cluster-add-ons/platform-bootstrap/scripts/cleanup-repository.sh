#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Runs only from the owning repository's Terraform destroy provisioner.
set -euo pipefail
set +x
umask 077
: "${REPOSITORY_ID:?Repository OCID is required}"
: "${COMPARTMENT_ID:?Repository compartment is required}"
IFS=. read -r prefix kind realm region remainder <<< "$REPOSITORY_ID"
[[ "$prefix" == ocid1 && "$kind" == artifactrepository && -n "$realm" && "$region" =~ ^[a-z0-9-]+$ && -n "$remainder" ]] || {
  echo 'Expected a regional Generic Artifact repository OCID.' >&2; exit 2;
}
for tool in oci jq; do command -v "$tool" >/dev/null || { echo "Repository cleanup requires $tool." >&2; exit 2; }; done
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

# Match discovery's local-profile and RMS delegated/principal authentication.
# Tokens are read at execution time, never interpolated into Terraform state.
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
        printf '[DEFAULT]\ndelegation_token_file=%s\n' "$token_path" > "$scratch/cli-config"
        auth_args=(--auth instance_obo_user --config-file "$scratch/cli-config" --profile DEFAULT)
        ;;
      false|'') auth_args=(--auth instance_principal);;
      *) echo 'use_obo_token must be true or false' >&2; exit 2;;
    esac;;
  ResourcePrincipal|resource_principal) auth_args=(--auth resource_principal);;
  APIKey|api_key) auth_args=(--auth api_key);;
  '') if [[ -n ${OCI_RESOURCE_PRINCIPAL_VERSION:-} && -z ${OCI_CLI_AUTH:-} ]]; then auth_args=(--auth resource_principal); fi;;
  *) echo 'Unsupported provider authentication mode for repository cleanup.' >&2; exit 2;;
esac
cli() {
  # The CLI resolves both full region names and short region keys from OCIDs.
  oci ${auth_args[@]+"${auth_args[@]}"} --region "$region" --output json --connection-timeout 10 --read-timeout 60 "$@"
}
: > "$scratch/requested"
for attempt in $(seq 1 12); do
  cli artifacts generic artifact list --compartment-id "$COMPARTMENT_ID" --repository-id "$REPOSITORY_ID" --all > "$scratch/list.json"
  jq -e --arg repository "$REPOSITORY_ID" '
    .data.items | if type != "array" then error("Expected artifact collection")
    elif any(.[]; ."repository-id" != $repository or (.id | type) != "string" or (.id | startswith("ocid1.genericartifact.") | not))
    then error("Artifact response does not belong to the requested repository")
    else [.[] | select(."lifecycle-state" != "DELETED")] end
  ' "$scratch/list.json" > "$scratch/pending.json"
  if [[ $(jq length "$scratch/pending.json") == 0 ]]; then
    echo 'Artifact repository is empty; Terraform can delete it.'
    exit 0
  fi
  while IFS= read -r artifact; do
    # A successful delete can remain visible while the service finishes it.
    if ! grep -Fxq "$artifact" "$scratch/requested"; then
      cli artifacts generic artifact delete --artifact-id "$artifact" --force >/dev/null
      printf '%s\n' "$artifact" >> "$scratch/requested"
    fi
  done < <(jq -r '.[] | select(."lifecycle-state" != "DELETING") | .id' "$scratch/pending.json")
  if (( attempt < 12 )); then sleep 5; fi
done
echo 'Repository still contains artifacts after cleanup retries; repository deletion stopped.' >&2
exit 1
