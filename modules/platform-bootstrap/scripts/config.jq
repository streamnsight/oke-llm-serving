# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Read only named non-secret settings, never the resource-principal environment.
def boolean($key): .[$key] | if .=="true" then true elif .=="false" then false else error($key+" must be true or false") end;
def positive($key): .[$key] | if test("^[1-9][0-9]*$") then tonumber else error($key+" must be a positive integer") end;
env | {
  PLATFORM_NAME, REGION, CLUSTER_ID, KUBERNETES_VERSION, HELM_VERSION,
  GPU_ALLOCATION_ENABLED, GPU_NODE_COUNT, GPUS_PER_HOST,
  REQUIRES_RDMA, RDMA_RESOURCE_NAME, ENABLE_LWS, LWS_CHART, LWS_VERSION, LWS_RELEASE, LWS_NAMESPACE
} as $s |
if any($s[]; type!="string") then error("Missing platform environment settings: "+([$s|to_entries[]|select(.value|type!="string")|.key]|join(", "))) else . end |
if ([env.PLATFORM_MODE]|inside(["deploy","validate"])|not) then error("PLATFORM_MODE must be deploy or validate") else . end |
if ([env.LWS_OPERATION]|inside(["ensure","upgrade"])|not) then error("LWS_OPERATION must be ensure or upgrade") else . end |
if all([$s.PLATFORM_NAME,$s.LWS_RELEASE,$s.LWS_NAMESPACE][]; test("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$")) | not then error("Platform/release/namespace must be Kubernetes names") else . end |
if all([$s.KUBERNETES_VERSION,$s.HELM_VERSION,$s.LWS_VERSION][]; test("^v?[0-9]+\\.[0-9]+\\.[0-9]+([-.][A-Za-z0-9.-]+)?$")) | not then error("Client/chart versions must be explicit release versions") else . end |
if ($s.LWS_CHART|test("^oci://[A-Za-z0-9./:_-]+$")|not) then error("LWS_CHART must be an OCI chart URL") else . end |
{
  settings:$s,
  config:{
    platform_name:$s.PLATFORM_NAME, region:$s.REGION, cluster_id:$s.CLUSTER_ID,
    target:{kubernetes_version:$s.KUBERNETES_VERSION},
    evidence_bucket:env.EVIDENCE_BUCKET, storage_namespace:env.STORAGE_NAMESPACE,
    gpu_allocation_enabled:($s|boolean("GPU_ALLOCATION_ENABLED")), node_count:($s|positive("GPU_NODE_COUNT")),
    gpu_count_per_host:($s|positive("GPUS_PER_HOST")),
    requires_rdma:($s|boolean("REQUIRES_RDMA")), rdma_resource_name:(if $s.RDMA_RESOURCE_NAME=="auto" then "" else $s.RDMA_RESOURCE_NAME end),
    enable_lws:($s|boolean("ENABLE_LWS")),
    components:{helm_version:$s.HELM_VERSION,lws:{chart:$s.LWS_CHART,version:$s.LWS_VERSION,release:$s.LWS_RELEASE,namespace:$s.LWS_NAMESPACE}}
  }
}
