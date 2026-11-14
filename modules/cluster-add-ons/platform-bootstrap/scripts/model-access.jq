# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
def metadata($name): {name:$name,labels:{"app.kubernetes.io/managed-by":"oke-llm-serving","oke-llm/platform-owner":$owner,"oke-llm/model-access":$namespace},annotations:{"oke-llm/model-namespace":$namespace,"oke-llm/platform-name":$platform,"oke-llm/cluster-id":$cluster}};
def namespaced($name): metadata($name)+{namespace:$namespace};
["get","list","watch","create","update","patch","delete"] as $manage |
{
 namespace:{apiVersion:"v1",kind:"Namespace",metadata:(metadata($namespace)|.labels["oke-llm/model-namespace"]="true")},
 role:{apiVersion:"rbac.authorization.k8s.io/v1",kind:"Role",metadata:namespaced("oke-llm-model"),rules:[
   {apiGroups:[""],resources:["configmaps","secrets","services","serviceaccounts","persistentvolumeclaims","pods"],verbs:$manage},
   {apiGroups:[""],resources:["pods/log","events","endpoints"],verbs:["get","list","watch"]},
   {apiGroups:[""],resources:["pods/portforward"],verbs:["create"]},
   {apiGroups:["apps"],resources:["deployments","statefulsets","replicasets"],verbs:$manage},
   {apiGroups:["batch"],resources:["jobs"],verbs:$manage},
   {apiGroups:["coordination.k8s.io"],resources:["leases"],verbs:$manage},
   {apiGroups:["autoscaling"],resources:["horizontalpodautoscalers"],verbs:$manage},
   {apiGroups:["policy"],resources:["poddisruptionbudgets"],verbs:$manage},
   {apiGroups:["leaderworkerset.x-k8s.io"],resources:["leaderworkersets"],verbs:$manage},
   {apiGroups:["disaggregatedset.x-k8s.io"],resources:["disaggregatedsets","disaggregatedsetrolescalers"],verbs:$manage},
   {apiGroups:["keda.sh"],resources:["scaledobjects","triggerauthentications"],verbs:$manage},
   {apiGroups:["monitoring.coreos.com"],resources:["servicemonitors","podmonitors","prometheusrules"],verbs:$manage},
   {apiGroups:["gateway.networking.k8s.io"],resources:["httproutes"],verbs:$manage},
   {apiGroups:["inference.networking.k8s.io"],resources:["inferencepools"],verbs:$manage}
 ]},
 router_account:{apiVersion:"v1",kind:"ServiceAccount",metadata:namespaced("oke-llm-router")},
 router_role:{apiVersion:"rbac.authorization.k8s.io/v1",kind:"Role",metadata:namespaced("oke-llm-router-discovery"),rules:[{apiGroups:[""],resources:["pods","services","endpoints"],verbs:["get","list","watch"]}]},
 router_binding:{apiVersion:"rbac.authorization.k8s.io/v1",kind:"RoleBinding",metadata:namespaced("oke-llm-router-discovery"),roleRef:{apiGroup:"rbac.authorization.k8s.io",kind:"Role",name:"oke-llm-router-discovery"},subjects:[{kind:"ServiceAccount",name:"oke-llm-router",namespace:$namespace}]},
 reader:{apiVersion:"rbac.authorization.k8s.io/v1",kind:"ClusterRole",metadata:metadata($namespace+"-platform-reader"),rules:[
   {apiGroups:[""],resources:["nodes"],verbs:["get","list","watch"]},
   {apiGroups:[""],resources:["namespaces"],resourceNames:[$namespace],verbs:["get"]},
   {apiGroups:["apiextensions.k8s.io"],resources:["customresourcedefinitions"],verbs:["get","list"]},
   {apiGroups:["apiregistration.k8s.io"],resources:["apiservices"],verbs:["get","list"]},
   {nonResourceURLs:["/api","/api/*","/apis","/apis/*","/version"],verbs:["get"]}
 ]}
}
