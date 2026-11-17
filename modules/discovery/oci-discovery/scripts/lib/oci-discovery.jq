# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
def gpu_shapes($q): [.[] | select(.gpus > 0) | select(($q.shape_names|length)==0 or (.shape as $s | $q.shape_names|index($s))) ] | sort_by(.shape);
def quota_names: [.[].quota_names[]?] | unique;
def inventory_shapes($catalog): [ .[] | . as $s | $catalog.shapes[.shape].memory_bytes_per_gpu as $memory | {
  shape, gpus, gpu_description, host_memory_gb:.memory_in_gbs, ocpus,
  local_disks_total_size_in_gbs, rdma_ports, rdma_bandwidth_in_gbps,
  quota_names:(.quota_names // [] | unique), gpu_memory_gib:(if $memory>0 then $memory/1073741824 else null end),
  gpu_memory_bytes_per_gpu:(if $memory>0 then $memory else null end),
  gpu_memory_source:(if $memory>0 then ($catalog.shape_sources[.shape] // $catalog.source) else null end), nvlink_topology:null
}];
def limit_plan($q; $defs; $quotas):
  [.[] | select(.name as $n | $quotas|index($n)) |
   . + {matched_shape_quota_name:(.name as $n | ($quotas|index($n))!=null), description:$defs[.name].description,
     availability_supported:($defs[.name].is_resource_availability_supported // false)}] |
  sort_by([if .matched_shape_quota_name then 0 else 1 end, .name,.scope_type,.availability_domain]);
def skip_reason($used): .scope_type as $scope |
  if (.availability_supported|not) or (["AD","REGION","GLOBAL"]|index($scope))==null then "Availability unsupported or scope unresolved."
  elif .scope_type=="AD" and ((.availability_domain // "")|length)==0 then "Availability unsupported or scope unresolved."
  elif $used>=1000 then "Query budget exhausted." else "" end;
def limit_observation($reason; $availability): {
  name, scope_type, availability_domain, tenancy_limit:.value, matched_shape_quota_name, description,
  resource_availability:(if $reason!="" then {
    status:"unknown", reason:$reason, available:null, used:null, fractional_availability:null,
    fractional_usage:null, effective_quota_value:null
  } else $availability | {status:(if .available!=null or .fractional_availability!=null then "observed" else "unknown" end),
    reason:null, available,used,fractional_availability,fractional_usage,effective_quota_value} end)
};
def capacity_names: map(.shape) | {visible:., assessed:., skipped:[]};
def capacity_assessment($q; $region; $ad; $names): . as $report |
  [$names[] as $name | $report.shape_availabilities[]? | select(.instance_shape==$name) | {
    shape:$name, fault_domain, availability_status, available_instances:.available_count, requested_instances:1,
    reported_sufficient:(if .availability_status=="OUT_OF_HOST_CAPACITY" then false
      elif .availability_status=="AVAILABLE" and .available_count!=null and .available_count>=0 then .available_count>=1 else null end)
  }] as $rows |
  [$names[] | select(. as $name | ($rows|map(.shape)|index($name))==null)] as $missing |
  {schema_version:"2.0",region:$region,availability_domain:$ad,fault_domain:null,report_compartment_id:$q.tenancy_ocid,
   observation_id:$q.observation_id,observed_at:.time_created,
   status:(if ($missing|length)>0 or any($rows[];.reported_sufficient==null) then "partial" else "complete" end),
   shapes:$rows,missing_shapes:$missing,warnings:["Fresh diagnostic report, not a reservation or launch guarantee.","Counts are instances; different shapes may share supply."]};
def regional_result($q; $region; $ads; $limits; $quotas; $used):
  [$limits[].name] as $mapped | [$quotas[]|select(. as $n|($mapped|index($n))==null)] as $unmapped |
  {inventory:{schema_version:"2.0",region:$region,tenancy_id:$q.tenancy_ocid,compartment_id:$q.compartment_id,
    status:(if ($ads|length)==0 or ($unmapped|length)>0 or any($limits[];.resource_availability.status!="observed") then "partial" else "complete" end),
    availability_domains:[$ads[]|{name,shapes}],limits:$limits,unmapped_shape_quota_names:$unmapped,headroom_queries_used:$used,
    warnings:["GPU VRAM uses the sourced catalog; unknown topology remains unknown.","Entitlement and physical capacity are separate observations."]},
   capacity:{schema_version:"1.0",region:$region,assessment_enabled:true,availability_domains:[$ads[]|.capacity]}};
