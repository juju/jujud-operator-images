# Copyright 2023 Canonical Ltd.
# Licensed under the AGPLv3, see LICENCE file for details.

JUJU_VERSIONS=bash -c '. "./make_functions.sh"; juju_versions "$$@"' juju_versions
CACHE_VERSION=bash -c '. "./make_functions.sh"; cache_version "$$@"' cache_version
PREPARE_BUILD=bash -c '. "./make_functions.sh"; prepare_build "$$@"' prepare_build

VERSIONS ?= $(shell $(JUJU_VERSIONS))
OCI_IMAGE_PLATFORMS ?= linux/amd64 linux/arm64 linux/s390x linux/ppc64el
DOCKER_USERNAME ?= jujusolutions

default: build

build: SUBMAKE_TARGET = "operator-image"
build: $(VERSIONS)

push: SUBMAKE_TARGET = "push-release-operator-image"
push: $(VERSIONS)

local: SUBMAKE_TARGET = "operator-image"
local: OCI_IMAGE_PLATFORMS = linux/amd64
local: $(VERSIONS)

%:
	$(CACHE_VERSION) "$@"
	$(PREPARE_BUILD) "$@"
	+cd "_build/$@/" && $(MAKE) $(SUBMAKE_TARGET) OPERATOR_IMAGE_BUILD_SRC=false OCI_IMAGE_PLATFORMS="$(OCI_IMAGE_PLATFORMS)" DOCKER_USERNAME="$(DOCKER_USERNAME)"

check:
	shellcheck ./*.sh

.PHONY: default
.PHONY: build
.PHONY: push
.PHONY: local
.PHONY: check
.PHONY: %
