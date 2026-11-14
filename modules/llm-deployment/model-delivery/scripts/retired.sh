#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
source runtime/common.sh
# Native garbage collection can outlive deletion of an LWS custom resource.
# Retire is complete only after the model's serving pods have disappeared.
kubectl -n "$namespace" wait --for=delete pods -l "oke-llm/model=$identity" --timeout="${timeout}s"
kubectl -n "$namespace" get pods -l "oke-llm/model=$identity" -o json | jq -e '.items|length==0' >/dev/null
