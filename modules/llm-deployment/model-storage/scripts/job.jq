# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
. as $c | {
  apiVersion:"batch/v1", kind:"Job",
  metadata:{name:$name, namespace:$c.namespace, labels:{"app.kubernetes.io/managed-by":"oke-llm-serving", "oke-llm/storage-owner":$c.owner}},
  # Keep orphaned finished Jobs beyond the maximum runner duration so TTL cannot release the fixed-name lock under an active runner.
  spec:{backoffLimit:0, activeDeadlineSeconds:($deadline|tonumber), ttlSecondsAfterFinished:43200,
    template:{metadata:{labels:{"oke-llm/storage-owner":$c.owner}}, spec:{
      restartPolicy:"Never", serviceAccountName:$c.service_account, automountServiceAccountToken:true,
      nodeSelector:($c.cpu_node_selector + {"kubernetes.io/arch":"amd64"}),
      affinity:{nodeAffinity:{requiredDuringSchedulingIgnoredDuringExecution:{nodeSelectorTerms:[{matchExpressions:[
        {key:"nvidia.com/gpu",operator:"DoesNotExist"},
        {key:"nvidia.com/gpu.present",operator:"DoesNotExist"},
        {key:"oke-llm/allocation",operator:"DoesNotExist"}
      ]}]}}},
      securityContext:{runAsNonRoot:true,runAsUser:10001,runAsGroup:10001,fsGroup:10001,seccompProfile:{type:"RuntimeDefault"}},
      containers:[{name:"download",image:$image,imagePullPolicy:"IfNotPresent",command:["bash","/input/download.sh"],
        env:[{name:"OCI_CLI_AUTH",value:"oke_workload_identity"},{name:"OCI_CLI_REGION",value:$c.region},
          {name:"HOME",value:"/tmp"},{name:"MODEL_INPUT_DIR",value:"/input"},{name:"MODEL_WORK_DIR",value:"/work"},
          {name:"STAGING_IMAGE",value:$image},{name:"MODEL_RUN_ID",value:$run_id}],
        resources:{requests:{cpu:"2",memory:"4Gi","ephemeral-storage":"512Mi"},limits:{cpu:"2",memory:"4Gi","ephemeral-storage":"1Gi"}},
        securityContext:{allowPrivilegeEscalation:false,readOnlyRootFilesystem:true,capabilities:{drop:["ALL"]}},
        volumeMounts:[{name:"input",mountPath:"/input",readOnly:true},{name:"scratch",mountPath:"/work"},{name:"tmp",mountPath:"/tmp"}]
      }],
      volumes:[{name:"input",configMap:{name:$configmap,defaultMode:292}},
        {name:"scratch",persistentVolumeClaim:{claimName:$c.pvc_name}}, {name:"tmp",emptyDir:{sizeLimit:"1Gi"}}]
    }}
  }
}
