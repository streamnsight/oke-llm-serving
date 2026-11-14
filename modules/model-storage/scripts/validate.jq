# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
def safe_name: type == "string" and test("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$");
def safe_path: type == "string" and test("^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$") and (split("/") | all(. != "." and . != ".."));
if .schema_version != "1.0" or
  (.model.id | type != "string" or (test("^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$") | not)) or
  (.model.revision | type != "string" or (test("^[a-f0-9]{40}$") | not)) or
  (.model.variant | type != "string" or (test("^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$") | not)) or
  (.snapshot_sha256 | type != "string" or (test("^[a-f0-9]{64}$") | not)) or
  (.owner | type != "string" or (test("^[a-f0-9]{24}$") | not)) or
  ([.namespace, .service_account, .pvc_name] | all(safe_name) | not) or
  (.region | type != "string" or (test("^[a-z0-9-]+$") | not)) or
  (.storage_namespace | type != "string" or (test("^[A-Za-z0-9]+$") | not)) or
  (.bucket | type != "string" or (test("^[A-Za-z0-9_.-]+$") | not)) or
  (.prefix | safe_path | not) or
  (.scratch_gib | type != "number" or . < 50 or floor != .) or
  (.storage_class | type != "string" or (test("^[A-Za-z0-9][A-Za-z0-9.-]*$") | not)) or
  (.cpu_node_selector | type != "object" or length == 0 or (to_entries | all((.key | test("^[A-Za-z0-9./_-]+$")) and (.value | type == "string" and test("^[A-Za-z0-9._-]+$"))) | not)) or
  (.hf_token_secret_id != null and (.hf_token_secret_id | type != "string" or (test("^ocid1\\.vaultsecret\\.[A-Za-z0-9._-]+$") | not))) or
  (.model.files | type != "array" or length == 0) or
  (.model.files | all((.path | safe_path) and (.size_bytes | type == "number" and . >= 0 and floor == .) and (.sha256 == null or (.sha256 | type == "string" and test("^[a-f0-9]{64}$")))) | not) or
  (([.model.files[].path] | unique | length) != (.model.files | length)) or
  (([.model.files[].size_bytes] | max) * 1.1 + 67108864 > .scratch_gib * 1073741824)
then error("Invalid pinned model-storage configuration; require an allowlisted snapshot, safe paths, CPU selector and sufficient scratch space") else . end
