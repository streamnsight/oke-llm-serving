<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->

# Credential-free module test CI

## Phase 1: Inventory

- [x] Inspect existing Terraform suites and JavaScript/shell tests for credential requirements.
- [x] Follow existing workflow action versions and Terraform 1.9.8.

## Phase 2: Implement

- [x] Run on pushes, pull requests, and manual dispatch on the current branch.
- [x] Discover modules and stacks with Terraform test suites automatically, running each independently with fail-fast disabled.
- [x] Initialize without remote backends and run mocked Terraform tests without cloud secrets.
- [x] Install Node.js dependencies and jq, then run the existing JavaScript/shell fixture tests.

## Phase 3: Verify

- [x] Validate workflow syntax with actionlint and YAML parsing; discovery covers 16 suites.
- [x] Run existing test suites locally without credentials; all 16 Terraform suites pass. Node 24 reports 31 passes, two platform-bootstrap failures caused by macOS sha256sum lacking the Linux invocation, and one optional Helm chart test skipped because HELM_CHART_FILE is unset. CI uses Ubuntu with GNU tools. The hosted Actions run remains pending a push.
- [x] Prepare only the workflow and this plan for a commit on the current branch.

Modules without Terraform test files are not separate matrix entries. The OCI discovery shell module is exercised through the JavaScript fixtures. Public dependency downloads still require network access. New suites must mock cloud providers before being added, since discovery includes every module/stack suite.
