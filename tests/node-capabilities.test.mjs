// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {resolve} from 'node:path';
const script=resolve(import.meta.dirname,'../terraform/modules/devops-serving/scripts/node-capabilities.jq');
const node=(resources={},ready=true)=>({status:{conditions:[{type:'Ready',status:ready?'True':'False'}],allocatable:resources}});
function assess(nodes,config={}) {
 return JSON.parse(execFileSync('jq',['-f',script],{input:JSON.stringify({nodes:{items:nodes},config:{tensor_parallel_size:4,node_count:1,requires_rdma:false,...config}}),encoding:'utf8'}));
}
test('reuses node-image or managed-plugin GPUs without requiring an operator install',()=>{
 const r=assess([node({'nvidia.com/gpu':'4'})]);
 assert.equal(r.ready,true);assert.equal(r.ownership,'existing_cluster');assert.equal(r.rdma_resource_name,null);
});
test('missing GPUs, unready nodes or too few GPU hosts cannot pass preflight',()=>{
 for(const nodes of [[],[node({})],[node({'nvidia.com/gpu':'4'},false)],[node({'nvidia.com/gpu':'2'})]]) assert.equal(assess(nodes).ready,false);
 assert.equal(assess([node({'nvidia.com/gpu':'4'})],{node_count:2}).ready,false);
});
test('detects the actual managed RDMA resource and requires it on enough hosts',()=>{
 const nodes=[node({'nvidia.com/gpu':'8','nvidia.com/rdma_shared_device_a':'1'}),node({'nvidia.com/gpu':'8','nvidia.com/rdma_shared_device_a':'1'})];
 const r=assess(nodes,{requires_rdma:true,node_count:2});
 assert.equal(r.ready,true);assert.equal(r.rdma_resource_name,'nvidia.com/rdma_shared_device_a');
 assert.equal(assess(nodes.slice(0,1),{requires_rdma:true,node_count:2}).ready,false);
});
test('missing or ambiguous RDMA resources require configuration, never a plugin fallback',()=>{
 assert.equal(assess([node({'nvidia.com/gpu':'8'})],{requires_rdma:true}).ready,false);
 const nodes=[node({'nvidia.com/gpu':'8','rdma/resource_a':'1','rdma/resource_b':'1'})];
 assert.equal(assess(nodes,{requires_rdma:true}).ready,false);
 assert.equal(assess(nodes,{requires_rdma:true}).fatal,true);
 assert.equal(assess(nodes,{requires_rdma:true,rdma_resource_name:'rdma/resource_b'}).ready,true);
 assert.equal(assess(nodes,{requires_rdma:true,rdma_resource_name:'nvidia.com/missing'}).ready,false);
});
test('explicit configured SR-IOV resource names are checked without guessing their meaning',()=>{
 const nodes=[node({'nvidia.com/gpu':'8','nvidia.com/mlnx_vf':'2'})];
 assert.equal(assess(nodes,{requires_rdma:true}).ready,false);
 assert.equal(assess(nodes,{requires_rdma:true,rdma_resource_name:'nvidia.com/mlnx_vf'}).ready,true);
});
