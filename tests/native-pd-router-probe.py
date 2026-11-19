#!/usr/bin/env python3
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Run inside the pinned Production Stack router image with its /opt/venv/bin/python.
import json, threading, subprocess, time, urllib.request, urllib.error, os, sys
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

records=[]
mode={'missing':False,'prefill_error':False}
kv={'do_remote_prefill':True,'do_remote_decode':False,'remote_engine_id':'mock-prefill-engine','remote_block_ids':[1,2,3],'remote_host':'192.0.2.5','remote_port':5600,'remote_request_id':'mock-request'}
class Backend(BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def do_GET(self):
        if self.path=='/metrics':
            body=b'# mock backend, no transfer metric claims\n'
            self.send_response(200); self.end_headers(); self.wfile.write(body);return
        obj={'data':[{'id':'fixture','object':'model','owned_by':'probe'}]}
        self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(json.dumps(obj).encode())
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        role='prefill' if self.server.server_port==8100 else 'decode'
        records.append({'role':role,'path':self.path,'body':body,'request_id':self.headers.get('X-Request-Id')})
        if role=='prefill' and mode['prefill_error']:
            self.send_response(503);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(b'{"error":"mock prefill unavailable"}');return
        self.send_response(200)
        if role=='decode' and body.get('stream'):
            self.send_header('Content-Type','text/event-stream');self.end_headers();self.wfile.write(b'data: {"choices":[{"delta":{"content":"ready"}}]}\n\ndata: [DONE]\n\n');return
        response={'id':'mock-'+role,'object':'chat.completion' if 'chat' in self.path else 'text_completion','model':'fixture','choices':[{'index':0,'text':'ready','message':{'role':'assistant','content':'ready'},'finish_reason':'stop'}],'usage':{'prompt_tokens':256,'completion_tokens':1,'total_tokens':257}}
        if role=='prefill' and not mode['missing']: response['kv_transfer_params']=dict(kv)
        self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(json.dumps(response).encode())
for port in [8100,8200]:
    server=ThreadingHTTPServer(('127.0.0.1',port),Backend)
    threading.Thread(target=server.serve_forever,daemon=True).start()
log=open('/tmp/native-pd-router.log','w')
command=[sys.executable,'-m','vllm_router.app','--port','8005','--service-discovery','static','--static-backends','http://127.0.0.1:8100,http://127.0.0.1:8200','--static-models','fixture,fixture','--static-model-labels','prefill,decode','--routing-logic','disaggregated_prefill_orchestrated','--prefill-model-labels','prefill','--decode-model-labels','decode']
proc=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT)
def post(path,payload,case):
    req=urllib.request.Request('http://127.0.0.1:8005'+path,data=json.dumps(payload).encode(),headers={'Content-Type':'application/json','X-Request-Id':case})
    try:
        with urllib.request.urlopen(req,timeout=30) as response: return response.status,response.read().decode()
    except urllib.error.HTTPError as e: return e.code,e.read().decode()
try:
    for _ in range(90):
        if proc.poll() is not None: raise RuntimeError('router exited before health '+str(proc.returncode))
        try:
            urllib.request.urlopen('http://127.0.0.1:8005/health',timeout=1).read();break
        except Exception: time.sleep(1)
    else: raise RuntimeError('router health deadline')
    results=[]
    for path in ['/v1/completions','/v1/chat/completions']:
        for stream in [False,True]:
            case=('chat' if 'chat' in path else 'completion')+('-stream' if stream else '-json')
            payload={'model':'fixture','max_tokens':16,'stream':stream}
            if 'chat' in path: payload.update(messages=[{'role':'user','content':'fixture prompt'}],max_completion_tokens=16)
            else:payload['prompt']='fixture prompt'
            if stream:payload['stream_options']={'include_usage':True}
            start=len(records);status,answer=post(path,payload,case);r=records[start:]
            assert status==200,(case,status,answer)
            assert [x['role'] for x in r]==['prefill','decode'],r
            p,d=[x['body'] for x in r]
            assert p['max_tokens']==1 and not p['stream'] and 'stream_options' not in p,p
            assert p['kv_transfer_params']['do_remote_decode'] is True and p['kv_transfer_params']['do_remote_prefill'] is False,p
            if 'chat' in path:assert p['max_completion_tokens']==1 and d['max_completion_tokens']==16
            assert d['max_tokens']==16 and d['stream']==stream,d
            assert d['kv_transfer_params']==dict(kv,remote_host='127.0.0.1'),d
            if stream:assert '[DONE]' in answer and d['stream_options']['include_usage'] is True
            else:assert json.loads(answer)['id']=='mock-decode'
            assert all(x['request_id']==case for x in r)
            results.append({'case':case,'status':status,'prefill_then_decode':True,'native_metadata_preserved':True,'streaming_preserved':True})
    mode['missing']=True;start=len(records)
    status,answer=post('/v1/chat/completions',{'model':'fixture','messages':[{'role':'user','content':'fixture prompt'}],'max_tokens':16},'missing-metadata')
    r=records[start:]
    assert status==200 and [x['role'] for x in r]==['prefill','decode']
    assert 'kv_transfer_params' not in r[-1]['body']
    results.append({'case':'missing-metadata','status':status,'decode_called_without_transfer_metadata':True,'silent_http_success_possible':True})
    mode['missing']=False;mode['prefill_error']=True;start=len(records)
    status,answer=post('/v1/completions',{'model':'fixture','prompt':'fixture prompt','max_tokens':16},'prefill-failure')
    assert status==503 and [x['role'] for x in records[start:]]==['prefill']
    results.append({'case':'prefill-failure','status':status,'decode_skipped':True})
    print(json.dumps({'router_image':os.environ.get('PROBE_IMAGE'),'cases':results,'real_kv_transfer_tested':False,'proof_scope':'actual router HTTP orchestration against mock engine endpoints'},indent=2),flush=True)
except BaseException:
    print(Path('/tmp/native-pd-router.log').read_text()[-18000:],flush=True)
    raise
finally:
    proc.terminate()
    try: proc.wait(timeout=10)
    except subprocess.TimeoutExpired:proc.kill()
    log.close()
    if Path('/tmp/native-pd-router.log').exists():
        warnings=[l for l in Path('/tmp/native-pd-router.log').read_text().splitlines() if 'did not contain kv_transfer_params' in l]
        print(json.dumps({'missing_metadata_warnings':warnings}),flush=True)
