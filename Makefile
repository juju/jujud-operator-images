# Copyright 2023 Canonical Ltd.
# Licensed under the AGPLv3, see LICENCE file for details.

SKIP_VERSIONS=3.2.0
JUJU_VERSIONS=bash -c '. "./make_functions.sh"; juju_versions "$$@"' juju_versions
CACHE_VERSION=bash -c '. "./make_functions.sh"; cache_version "$$@"' cache_version
PREPARE_BUILD=bash -c '. "./make_functions.sh"; prepare_build "$$@"' prepare_build
VALIDATE_BUILD=bash -c '. "./make_functions.sh"; validate_build "$$@"' validate_build

VERSIONS ?= $(shell $(JUJU_VERSIONS) $(SKIP_VERSIONS))
OCI_IMAGE_PLATFORMS ?= linux/amd64 linux/arm64 linux/s390x linux/ppc64el
OCI_REPOSITORIES ?= public.ecr.aws/juju ghcr.io/juju docker.io/jujusolutions
BOOTSTRAP_CLOUD ?= minikube

default: build

release: validate
## release: validate and push
	+$(MAKE) push

build: SUBMAKE_TARGET = "operator-image"
build: $(VERSIONS)
## push: for all VERSIONS build the operator-image target.

push: SUBMAKE_TARGET = "push-release-operator-image"
push: $(VERSIONS)
## push: for all VERSIONS build the push-release-operator-image target.

local: SUBMAKE_TARGET = "operator-image"
local: OCI_IMAGE_PLATFORMS = linux/amd64
local: $(VERSIONS)
## local: for all VERSIONS build the operator-image target with the local platform.

validate: $(addprefix _validate/,$(VERSIONS))
## validate: validate all VERSIONS

_validate/%: TEST_REPOSITORY=$(wordlist 1, 1, $(OCI_REPOSITORIES))
_validate/%: VERSION=$(@:_validate/%=%)
_validate/%: local
## _validate/%: validates a version of juju for the first repository.
	$(VALIDATE_BUILD) "$(VERSION)" "$(TEST_REPOSITORY)/jujud-operator:$(VERSION)" "$(BOOTSTRAP_CLOUD)" "$(TEST_REPOSITORY)"

%:
## %: SUBMAKE_TARGET a version of juju for each repository.
	$(CACHE_VERSION) "$@"
	$(PREPARE_BUILD) "$@"
	+cd "_build/$@/" && \
	$(foreach DOCKER_USERNAME,$(OCI_REPOSITORIES),\
		$(MAKE) $(SUBMAKE_TARGET) OPERATOR_IMAGE_BUILD_SRC=false OCI_IMAGE_PLATFORMS="$(OCI_IMAGE_PLATFORMS)" DOCKER_USERNAME="$(DOCKER_USERNAME)";\
	)

check:
	shellcheck ./*.sh

.PHONY: default
.PHONY: build
.PHONY: release
.PHONY: push
.PHONY: local
.PHONY: check
.PHONY: validate
.PHONY: _validate/%
.PHONY: %
