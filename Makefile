# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
.DEFAULT_GOAL := help
DIST_DIR ?= work/packages
.PHONY: help package package-discovery package-deployment check-packages
help:
	@echo 'make package             Build both RMS ZIPs from committed HEAD'
	@echo 'make package-discovery   Build the discovery stack ZIP'
	@echo 'make package-deployment  Build the deployment stack ZIP'
	@echo 'make check-packages      Build, extract and Terraform-validate both RMS ZIPs'
	@echo 'Optional: DIST_DIR=/path'
package: package-discovery package-deployment
package-discovery:
	@PACKAGE_STACK=discovery bash scripts/package-stack.sh "$(DIST_DIR)/oke-llm-discovery.zip"
	@echo 'RMS working directory: root (.)'
package-deployment:
	@PACKAGE_STACK=deployment bash scripts/package-stack.sh "$(DIST_DIR)/oke-llm-deployment.zip"
	@echo 'RMS working directory: root (.)'
check-packages: package
	@bash scripts/check-stack-package.sh "$(DIST_DIR)/oke-llm-discovery.zip"
	@bash scripts/check-stack-package.sh "$(DIST_DIR)/oke-llm-deployment.zip"
