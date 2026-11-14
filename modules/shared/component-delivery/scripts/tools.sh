#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Shell stages are ephemeral. Install verified helper binaries into this run only.
delivery_tools() {
  local version checksum
  for tool in oci jq curl tar sha256sum; do
    command -v "$tool" >/dev/null || { echo "Missing Shell runtime tool: $tool" >&2; return 2; }
  done
  mkdir -p .delivery-bin
  export PATH="$PWD/.delivery-bin:$PATH"
  export HELM_CACHE_HOME="$PWD/.delivery-helm/cache" HELM_CONFIG_HOME="$PWD/.delivery-helm/config" HELM_DATA_HOME="$PWD/.delivery-helm/data"
  version=$(jq -er .helm_version specification.json)
  curl -fsSL --retry 3 "https://get.helm.sh/helm-${version}-linux-amd64.tar.gz" -o helm.tgz
  curl -fsSL --retry 3 "https://get.helm.sh/helm-${version}-linux-amd64.tar.gz.sha256sum" -o helm.sha256
  checksum=$(cut -d ' ' -f 1 helm.sha256)
  printf '%s  helm.tgz\n' "$checksum" | sha256sum -c -
  tar -xzf helm.tgz linux-amd64/helm
  mv linux-amd64/helm .delivery-bin/helm
  version=$(oci ce cluster get --cluster-id "$cluster" --query 'data."kubernetes-version"' --raw-output)
  [[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Unexpected cluster Kubernetes version" >&2; return 2; }
  curl -fsSL --retry 3 "https://dl.k8s.io/release/$version/bin/linux/amd64/kubectl" -o .delivery-bin/kubectl
  curl -fsSL --retry 3 "https://dl.k8s.io/release/$version/bin/linux/amd64/kubectl.sha256" -o kubectl.sha256
  printf '%s  .delivery-bin/kubectl\n' "$(cat kubectl.sha256)" | sha256sum -c -
  curl -fsSL --retry 3 https://github.com/mikefarah/yq/releases/download/v4.47.2/yq_linux_amd64 -o .delivery-bin/yq
  printf '%s  .delivery-bin/yq\n' 1bb99e1019e23de33c7e6afc23e93dad72aad6cf2cb03c797f068ea79814ddb0 | sha256sum -c -
  chmod +x .delivery-bin/{helm,kubectl,yq}
  export KUBECONFIG="$PWD/.delivery-kubeconfig"
  oci ce cluster create-kubeconfig --cluster-id "$cluster" --file "$KUBECONFIG" --region "$DELIVERY_REGION" --token-version 2.0.0 --kube-endpoint PRIVATE_ENDPOINT
}
