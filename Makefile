# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
.DEFAULT_GOAL := help
DIST_DIR ?= work/packages
.PHONY: help package package-discovery package-infrastructure package-model check-packages
help:
	@echo 'make package             Build discovery with embedded downstream templates'
	@echo 'make package-discovery   Build the discovery entry ZIP from committed HEAD'
	@echo 'make package-infrastructure Build the GPU infrastructure/bootstrap ZIP'
	@echo 'make package-model       Build the standalone model template ZIP'
	@echo 'make check-packages      Validate discovery and its embedded template roots'
	@echo 'Optional: DIST_DIR=/path'
package: package-discovery
package-discovery:
	@PACKAGE_STACK=discovery bash scripts/package-stack.sh "$(DIST_DIR)/oke-llm-discovery.zip"
	@echo 'RMS working directory: root (.)'
package-model:
	@PACKAGE_STACK=llm-deployment bash scripts/package-stack.sh "$(DIST_DIR)/oke-llm-model.zip"
	@echo 'RMS working directory: root (.)'
package-infrastructure:
	@PACKAGE_STACK=infrastructure bash scripts/package-stack.sh "$(DIST_DIR)/oke-llm-infrastructure.zip"
	@echo 'RMS working directory: root (.)'
check-packages: package
	@bash scripts/check-stack-package.sh "$(DIST_DIR)/oke-llm-discovery.zip"
