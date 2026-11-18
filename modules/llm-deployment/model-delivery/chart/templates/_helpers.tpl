{{/*
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
*/}}
{{- define "model.labels" -}}
app.kubernetes.io/name: oke-llm-model
app.kubernetes.io/instance: {{ .Release.Name }}
oke-llm/model: {{ .Values.identity | quote }}
{{- end -}}
{{- define "model.podSpec" -}}
{{- $root := .root -}}
{{- $worker := .worker -}}
automountServiceAccountToken: false
terminationGracePeriodSeconds: 120
nodeSelector:
  {{- toYaml $root.Values.nodeSelector | nindent 2 }}
tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
{{- if gt (int $root.Values.hosts) 1 }}
# Only pods in the SAME LWS replica must occupy different hosts. Different
# replica groups may pack spare GPU slots on the same host.
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - topologyKey: kubernetes.io/hostname
        matchLabelKeys: [leaderworkerset.sigs.k8s.io/group-index]
        labelSelector:
          matchLabels: {app.kubernetes.io/instance: {{ $root.Release.Name }}}
{{- end }}
containers:
  - name: vllm
    image: {{ required "A digest-pinned serving image is required" $root.Values.image | quote }}
    imagePullPolicy: IfNotPresent
    {{- if and $root.Values.lmcache $root.Values.lmcache.enabled }}
    command: ["bash", "/lmcache/launch.sh"]
    {{- else }}
    command: ["vllm", "serve"]
    {{- end }}
    args:
      - {{ $root.Values.modelPath | default $root.Values.model | quote }}
      {{- range $root.Values.recipeArgs }}
      - {{ . | quote }}
      {{- end }}
      - --revision
      - {{ $root.Values.revision | quote }}
      - --served-model-name
      - {{ $root.Values.model | quote }}
      - --host
      - "0.0.0.0"
      - --port
      - "8000"
      - --tensor-parallel-size
      - {{ $root.Values.tensorParallel | toString | quote }}
      - --pipeline-parallel-size
      - {{ $root.Values.pipelineParallel | toString | quote }}
      - --max-model-len
      - {{ $root.Values.contextLength | toString | quote }}
      - --max-num-seqs
      - {{ $root.Values.concurrency | toString | quote }}
      {{- if gt (int $root.Values.hosts) 1 }}
      - --distributed-executor-backend
      - mp
      - --nnodes
      - "$(LWS_GROUP_SIZE)"
      - --node-rank
      - "$(LWS_WORKER_INDEX)"
      - --master-addr
      - "$(LWS_LEADER_ADDRESS)"
      {{- if $worker }}
      - --headless
      {{- end }}
      {{- end }}
    env:
      {{- range $key, $value := $root.Values.recipeEnv }}
      - name: {{ $key }}
        value: {{ $value | quote }}
      {{- end }}
      {{- if and $root.Values.lmcache $root.Values.lmcache.enabled }}
      - {name: LMCACHE_ADAPTER, value: {{ $root.Values.lmcache.mode | quote }}}
      - {name: LMCACHE_REQUIRES_HMA, value: {{ $root.Values.lmcache.requires_hma | default false | toString | quote }}}
      - {name: LMCACHE_CPU_MEMORY_GB, value: {{ $root.Values.lmcache.cpu_memory_gb | toString | quote }}}
      {{- if $root.Values.lmcache.controller }}
      - name: LMCACHE_LMCACHE_INSTANCE_ID
        valueFrom: {fieldRef: {fieldPath: metadata.name}}
      - name: LMCACHE_P2P_HOST
        valueFrom: {fieldRef: {fieldPath: status.podIP}}
      {{- end }}
      {{- end }}
      - name: HF_HOME
        value: /cache/huggingface
      {{- if $root.Values.hfTokenSecret }}
      - name: HF_TOKEN
        valueFrom:
          secretKeyRef:
            name: {{ $root.Values.hfTokenSecret | quote }}
            key: token
      {{- end }}
    ports:
      - name: http
        containerPort: 8000
      {{- if and $root.Values.lmcache $root.Values.lmcache.enabled (eq $root.Values.lmcache.mode "mp") }}
      - name: cache-metrics
        containerPort: 9090
      {{- end }}
    {{- if not $worker }}
    startupProbe:
      httpGet: {path: /health, port: http}
      periodSeconds: 10
      failureThreshold: 180
    readinessProbe:
      httpGet: {path: /health, port: http}
      periodSeconds: 10
    {{- end }}
    resources:
      requests:
        cpu: {{ $root.Values.cpu | quote }}
        memory: {{ $root.Values.memory | quote }}
        ephemeral-storage: {{ $root.Values.workspace | quote }}
        nvidia.com/gpu: {{ int $root.Values.gpusPerPod }}
        {{- if $root.Values.rdmaResource }}
        {{ $root.Values.rdmaResource }}: 1
        {{- end }}
      limits:
        memory: {{ $root.Values.memory | quote }}
        ephemeral-storage: {{ $root.Values.workspace | quote }}
        nvidia.com/gpu: {{ int $root.Values.gpusPerPod }}
        {{- if $root.Values.rdmaResource }}
        {{ $root.Values.rdmaResource }}: 1
        {{- end }}
    volumeMounts:
      {{- if and $root.Values.lmcache $root.Values.lmcache.enabled }}
      - {name: lmcache, mountPath: /lmcache, readOnly: true}
      {{- end }}
      - {name: shm, mountPath: /dev/shm}
      - {name: cache, mountPath: /cache}
      {{- if $root.Values.pvcName }}
      - {name: model, mountPath: /models, readOnly: true}
      {{- end }}
volumes:
  {{- if and $root.Values.lmcache $root.Values.lmcache.enabled }}
  - name: lmcache
    configMap: {name: {{ $root.Release.Name }}-lmcache}
  {{- end }}
  - name: shm
    emptyDir: {medium: Memory, sizeLimit: {{ $root.Values.shm | quote }}}
  - name: cache
    emptyDir: {sizeLimit: {{ $root.Values.workspace | quote }}}
  {{- if $root.Values.pvcName }}
  - name: model
    persistentVolumeClaim: {claimName: {{ $root.Values.pvcName | quote }}, readOnly: true}
  {{- end }}
{{- end -}}
