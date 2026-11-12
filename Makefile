# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
.DEFAULT_GOAL := help
DIST_DIR ?= work/packages
REFRESH_CATALOG ?= false
PACKAGE_FLAGS = $(if $(filter true,$(REFRESH_CATALOG)),--refresh-catalog,)

.PHONY: help package package-discovery package-deployment refresh-model-catalog build-discovery-sdk test-discovery-sdk
help:
	@echo 'make package             Build both RMS ZIPs from committed HEAD'
	@echo 'make package-discovery   Build the discovery stack ZIP'
	@echo 'make package-deployment  Build the deployment stack ZIP'
	@echo 'make refresh-model-catalog Update all recipe models and RMS choices (requires npm ci)'
	@echo 'make build-discovery-sdk Build the local Go OCI SDK lookup executable'
	@echo 'Optional: DIST_DIR=/path REFRESH_CATALOG=true'

package: package-discovery package-deployment

package-discovery:
	@PACKAGE_STACK=discovery bash scripts/package-stack.sh "$(DIST_DIR)/oke-llm-discovery.zip" $(PACKAGE_FLAGS)
	@echo 'RMS working directory: terraform/stacks/discovery'

package-deployment:
	@PACKAGE_STACK=deployment bash scripts/package-stack.sh "$(DIST_DIR)/oke-llm-deployment.zip" $(PACKAGE_FLAGS)
	@echo 'RMS working directory: terraform/stacks/deployment'

refresh-model-catalog:
	@bash scripts/refresh-model-catalog.sh

build-discovery-sdk:
	@bash scripts/build-discovery-sdk.sh

test-discovery-sdk:
	@GOPATH="$(CURDIR)/work/go" GOCACHE="$(CURDIR)/work/go-build-cache" go -C tools/oci-discovery test ./...
