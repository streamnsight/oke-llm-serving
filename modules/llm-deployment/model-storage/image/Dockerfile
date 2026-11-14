# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Supply a reviewed ghcr.io/oracle/oci-cli@sha256:... base; no moving default.
ARG OCI_CLI_BASE
FROM ${OCI_CLI_BASE}
USER root
RUN dnf -y install bash curl jq coreutils ca-certificates \
    && dnf clean all \
    && for tool in bash curl jq sha256sum base64 oci; do command -v "$tool"; done \
    && OCI_CLI_PAGER=cat oci --help > /tmp/oci-help \
    && grep -q oke_workload_identity /tmp/oci-help \
    && rm -f /tmp/oci-help
ENV HOME=/tmp
USER 10001:10001
ENTRYPOINT ["/bin/bash"]
