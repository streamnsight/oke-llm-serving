#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Reads current ownership/attachments and renders a Run Command or one-shot Pod.
# Rendering never submits a command, creates a Pod or changes a node/pool/volume.
set -euo pipefail
fail() { echo "$*" >&2; exit 2; }
[[ $# -ge 4 && $# -le 6 ]] || fail 'Usage: render-root-repair-command.sh CLUSTER_OCID POOL_OCID NODE_NAME TRUSTED_MODEL_NAMESPACE [--apply] [--pod]'
cluster=$1 pool=$2 node=$3 namespace=$4 action=inspect format=command
shift 4
for option in "$@"; do case "$option" in --apply) action=--apply;; --pod) format=pod;; *) fail "Unknown option: $option";; esac; done
[[ $cluster =~ ^ocid1\.cluster\.[A-Za-z0-9._-]+$ && $pool =~ ^ocid1\.nodepool\.[A-Za-z0-9._-]+$ && $node =~ ^[A-Za-z0-9.-]+$ && $namespace =~ ^[a-z0-9-]+$ ]] || fail 'Supply exact cluster/pool identities and safe node/namespace names'
[[ $action == inspect || $action == --apply ]] || fail 'Select inspection or explicit --apply payload'
for tool in kubectl oci jq sha256sum; do command -v "$tool" >/dev/null || fail "Missing local tool: $tool"; done
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
region=$(cut -d. -f4 <<< "$pool")
kubectl get namespace "$namespace" -o json > "$work_dir/namespace.json"
platform=$(jq -er '.metadata.annotations["oke-llm/platform-name"]|select(test("^[a-z][a-z0-9-]+$"))' "$work_dir/namespace.json")
owner=$(printf '%s' "$platform/$cluster" | sha256sum | cut -c1-32)
jq -e --arg cluster "$cluster" --arg owner "$owner" '.metadata.annotations["oke-llm/cluster-id"]==$cluster and .metadata.labels["oke-llm/platform-owner"]==$owner and .metadata.labels["oke-llm/model-namespace"]=="true"' "$work_dir/namespace.json" >/dev/null || fail 'Current Kubernetes context is not the expected trusted platform cluster'
kubectl get node "$node" -o json > "$work_dir/node.json"
instance=$(jq -er '.spec.providerID|split("/")|last|select(test("^ocid1\\.instance\\.[A-Za-z0-9._-]+$"))' "$work_dir/node.json")
jq -e --arg node "$node" --arg platform "$platform" '.metadata.name==$node and (.metadata.uid|type=="string" and length>0) and .metadata.labels["oke-llm/allocation"]==$platform and (.status.allocatable["nvidia.com/gpu"]|tonumber)>0 and any(.status.conditions[];.type=="Ready" and .status=="True")' "$work_dir/node.json" >/dev/null || fail 'Node is not the exact Ready GPU node owned by this allocation'
oci ce node-pool get --node-pool-id "$pool" --region "$region" > "$work_dir/pool.json"
jq -e --arg cluster "$cluster" --arg instance "$instance" --arg platform "$platform" '.data|.["cluster-id"]==$cluster and .["lifecycle-state"]=="ACTIVE" and any(.nodes[];.id==$instance and .["lifecycle-state"]=="ACTIVE") and any(.["initial-node-labels"][];.key=="oke-llm/allocation" and .value==$platform) and (.["freeform-tags"]["oke-llm-allocation"]|type=="string" and length>0)' "$work_dir/pool.json" >/dev/null || fail 'OCI pool does not confirm this exact active cluster/instance/allocation membership'
oci compute instance get --instance-id "$instance" --region "$region" > "$work_dir/instance.json"
jq -e --arg instance "$instance" --slurpfile pool "$work_dir/pool.json" --slurpfile node "$work_dir/node.json" '.data.id==$instance and .data["lifecycle-state"]=="RUNNING" and .data.shape==$pool[0].data["node-shape"] and .data.shape==$node[0].metadata.labels["node.kubernetes.io/instance-type"]' "$work_dir/instance.json" >/dev/null || fail 'Compute instance identity/state/shape does not match the selected pool and node'
compartment=$(jq -er '.data["compartment-id"]' "$work_dir/instance.json")
ad=$(jq -er '.data["availability-domain"]' "$work_dir/instance.json")
oci compute boot-volume-attachment list --compartment-id "$compartment" --availability-domain "$ad" --instance-id "$instance" --region "$region" --all > "$work_dir/attachments.json"
boot=$(jq -er --arg instance "$instance" '[.data[]|select(.["instance-id"]==$instance and .["lifecycle-state"]=="ATTACHED")]|select(length==1)|.[0]["boot-volume-id"]' "$work_dir/attachments.json") || fail 'Expected exactly one currently attached boot volume'
oci bv boot-volume get --boot-volume-id "$boot" --region "$region" > "$work_dir/boot.json"
boot_gib=$(jq -er --arg boot "$boot" --slurpfile pool "$work_dir/pool.json" '.data|select(.id==$boot and .["lifecycle-state"]=="AVAILABLE" and .["size-in-gbs"]>=($pool[0].data["node-source-details"]["boot-volume-size-in-gbs"]//50))|.["size-in-gbs"]|select(type=="number" and .>=50 and floor==.)' "$work_dir/boot.json") || fail 'Actual attached boot volume is smaller than the pool setting; volume expansion needs separate approval'
if [[ $format == command ]]; then
  oci instance-agent plugin list --instanceagent-id "$instance" --compartment-id "$compartment" --region "$region" --all > "$work_dir/plugins.json"
  jq -e 'any(.data[];.name=="Compute Instance Run Command" and .status=="RUNNING")' "$work_dir/plugins.json" >/dev/null || fail 'Existing Run Command plugin is not running; inspect the rendered --pod alternative without changing plugin/sudo configuration'
fi
kubectl get pods --all-namespaces --field-selector "spec.nodeName=$node" -o json > "$work_dir/pods.json"
blockers=$(jq '[.items[]|select(.status.phase!="Succeeded" and .status.phase!="Failed" and (any(.metadata.ownerReferences[]?;.kind=="DaemonSet")|not))]|length' "$work_dir/pods.json")
[[ $action != --apply || $blockers == 0 ]] || fail 'Active non-DaemonSet workloads occupy this node; review them before preparing a repair payload'
boot_bytes=$((boot_gib * 1024 * 1024 * 1024))
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  if [[ $format == pod ]]; then
    printf 'exec /host/lib64/ld-linux-x86-64.so.2 --library-path /host/usr/lib64:/host/lib64 /host/usr/bin/nsenter --target 1 --mount --pid --net --root --wd -- '
  else
    printf 'sudo -n '
  fi
  printf '/bin/bash -s -- '\''%s'\'' '\''%s'\'' '\''%s'\'' <<'\''OKE_LLM_ROOT_REPAIR'\''\n' "$instance" "$boot_bytes" "$action"
  cat "$script_dir/repair-root-filesystem.sh"
  printf '\nOKE_LLM_ROOT_REPAIR\n'
} > "$work_dir/command.sh"
printf 'Rendered %s payload only: node=%s uid=%s instance=%s attached_boot=%s (%s GiB), non-DaemonSet workloads=%s. No command submitted.\n' "$action" "$node" "$(jq -r .metadata.uid "$work_dir/node.json")" "$instance" "$boot" "$boot_gib" "$blockers" >&2
if [[ $format == command ]]; then
  jq -n --arg compartment "$compartment" --arg instance "$instance" --rawfile script "$work_dir/command.sh" '{compartmentId:$compartment,target:{instanceId:$instance},displayName:"oke-llm-root-filesystem-maintenance",timeoutInSeconds:600,content:{source:{sourceType:"TEXT",text:$script},output:{outputType:"TEXT"}}}'
else
  # Official Oracle Linux 9-slim linux/amd64 manifest, verified from its registry.
  jq -n --arg node "$node" --arg uid "$(jq -r .metadata.uid "$work_dir/node.json")" --arg instance "$instance" --arg boot "$boot" --arg action "$action" --rawfile script "$work_dir/command.sh" '
    {apiVersion:"v1",kind:"Pod",metadata:{generateName:("oke-llm-root-"+(if $action=="inspect" then "inspect" else "apply" end)+"-"),namespace:"kube-system",labels:{"oke-llm/maintenance":"root-filesystem"},annotations:{"oke-llm/expected-node-uid":$uid,"oke-llm/expected-instance-id":$instance,"oke-llm/expected-boot-volume-id":$boot,"oke-llm/maintenance-action":$action}},spec:{nodeName:$node,hostPID:true,hostNetwork:true,dnsPolicy:"ClusterFirstWithHostNet",automountServiceAccountToken:false,restartPolicy:"Never",activeDeadlineSeconds:600,terminationGracePeriodSeconds:5,containers:[{name:"root-filesystem",image:"docker.io/library/oraclelinux@sha256:bb3d452d39d721b06733f754e1d4c5098915c7895e2cca9b33e6bd07696cbcaa",imagePullPolicy:"IfNotPresent",command:["/bin/bash","-c"],args:[$script],securityContext:{privileged:true,runAsUser:0,readOnlyRootFilesystem:true},resources:{requests:{cpu:"50m",memory:"64Mi","ephemeral-storage":"32Mi"},limits:{cpu:"1",memory:"512Mi","ephemeral-storage":"128Mi"}},volumeMounts:[{name:"host-root",mountPath:"/host",readOnly:true}]}],volumes:[{name:"host-root",hostPath:{path:"/",type:"Directory"}}]}}'
fi
