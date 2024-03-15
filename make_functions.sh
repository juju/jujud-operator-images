#!/bin/bash
# Copyright 2023 Canonical Ltd.
# Licensed under the AGPLv3, see LICENCE file for details.
set -euf

BASE_DIR="$(realpath "$(dirname "$0")")"
IMG_CACHE_DIR="${BASE_DIR}/_cache"
IMG_BUILD_DIR="${BASE_DIR}/_build"
IMG_DATA_DIR="${BASE_DIR}/_data"
PATCH_DIR="${BASE_DIR}/patches"

OCI_BUILDER=${OCI_BUILDER:-docker}
OCI_IMAGE_PLATFORMS=${OCI_IMAGE_PLATFORMS:-linux/amd64 linux/arm64 linux/s390x linux/ppc64el}

DOCKER_BIN=${DOCKER_BIN:-$(which ${OCI_BUILDER} || true)}

mkdir -p "${IMG_CACHE_DIR}"
mkdir -p "${IMG_BUILD_DIR}"
mkdir -p "${IMG_DATA_DIR}"

juju_versions() {
  skip_versions=${1-""}
  candidates=$(curl "https://api.snapcraft.io/v2/snaps/info/juju?fields=version" -s -H "Snap-Device-Series: 16" | yq -o=t '."channel-map" | map(select(.channel.risk=="stable" and .channel.track!="latest")) | map(.version) | unique')
  chosen=()
  for ver in ${candidates} ; do
    if [[ "${skip_versions}" == *"${ver}"* ]]; then
      continue
    fi

    if already_cached "${ver}" ; then
      chosen+=("${ver}")
      continue
    fi

    majmin=$(echo "${ver}" | cut -d. -f1-2)
    for platform in ${OCI_IMAGE_PLATFORMS} ; do
      os=$(echo "${platform}" | cut -f1 -d/)
      if [ "${os}" != "linux" ]; then
        echo "${os} not supported"
        exit 1
      fi
      arch=$(echo "${platform}" | cut -f2 -d/)
      arch=${arch//ppc64el/ppc64le}
      canonical_arch=${arch//ppc64le/ppc64el}

      if ! curl --fail -s -I "https://launchpad.net/juju/${majmin}/${ver}/+download/juju-agents-${ver}-linux-${canonical_arch}.tar.xz" >/dev/null 2>&1 ; then
        continue 2
      fi
    done

    if ! curl --fail -s -I "https://launchpad.net/juju/${majmin}/${ver}/+download/juju-core_${ver}.tar.gz" >/dev/null 2>&1 ; then
      continue
    fi

    chosen+=("${ver}")
  done

  printf '%s' "${chosen[*]}"
}

already_cached() {
  ver=${1-""}
  ver_cachedir="${IMG_CACHE_DIR}/${ver}"

  for platform in ${OCI_IMAGE_PLATFORMS} ; do
    os=$(echo "${platform}" | cut -f1 -d/)
    if [ "${os}" != "linux" ]; then
      continue
    fi
    arch=$(echo "${platform}" | cut -f2 -d/)
    arch=${arch//ppc64el/ppc64le}
    canonical_arch=${arch//ppc64le/ppc64el}

    if [ -f "${ver_cachedir}/juju-agents-${ver}-linux-${canonical_arch}.tar.xz" ]; then
      continue
    fi

    return 1
  done

  if [ ! -f "${ver_cachedir}/juju-core_${ver}.tar.gz" ]; then
    return 1
  fi

  if [ ! -f "${ver_cachedir}/juju-${ver}-linux-amd64.tar.xz" ]; then
    return 1
  fi
  
  return 0
}

cache_version() {
  ver=${1-""}
  majmin=$(echo "${ver}" | cut -d. -f1-2)
  ver_cachedir="${IMG_CACHE_DIR}/${ver}"
  mkdir -p "${ver_cachedir}"
  
  for platform in ${OCI_IMAGE_PLATFORMS} ; do
    os=$(echo "${platform}" | cut -f1 -d/)
    if [ "${os}" != "linux" ]; then
      echo "${os} not supported"
      exit 1
    fi
    arch=$(echo "${platform}" | cut -f2 -d/)
    arch=${arch//ppc64el/ppc64le}
    canonical_arch=${arch//ppc64le/ppc64el}

    if [ -f "${ver_cachedir}/juju-agents-${ver}-linux-${canonical_arch}.tar.xz" ]; then
      echo "Found cached juju-agents-${ver}-linux-${canonical_arch}.tar.xz"
      continue
    fi

    (cd "${ver_cachedir}" && wget --no-verbose "https://launchpad.net/juju/${majmin}/${ver}/+download/juju-agents-${ver}-linux-${canonical_arch}.tar.xz")
  done

  if [ -f "${ver_cachedir}/juju-core_${ver}.tar.gz" ]; then
    echo "Found cached juju-core_${ver}.tar.gz"
  else
    (cd "${ver_cachedir}" && wget --no-verbose "https://launchpad.net/juju/${majmin}/${ver}/+download/juju-core_${ver}.tar.gz")
  fi

  if [ -f "${ver_cachedir}/juju-${ver}-linux-amd64.tar.xz" ]; then
    echo "Found cached juju-${ver}-linux-amd64.tar.xz"
  else
    (cd "${ver_cachedir}" && wget --no-verbose "https://launchpad.net/juju/${majmin}/${ver}/+download/juju-${ver}-linux-amd64.tar.xz")
  fi
}

prepare_build() {
  ver=${1-""}
  if ! already_cached "${ver}" ; then
    echo "${ver} not available in cache"
    exit 1
  fi

  ver_cachedir="${IMG_CACHE_DIR}/${ver}"
  ver_builddir="${IMG_BUILD_DIR}/${ver}"

  tmp=$(mktemp -d)
  rm -rf "${ver_builddir}" || true
  (cd "${tmp}" && tar -xf "${ver_cachedir}/juju-core_${ver}.tar.gz" && mv "$(dirname "$(find . -type f -name "go.mod" | awk --field-separator="/" '{ print NF, $0 }' | sort -n | head -n1 | cut -f2 -d" ")")" "${ver_builddir}")
  rm -rf "${tmp}"

  ls -lah "${ver_builddir}"

  if grep "${ver}" < "${ver_builddir}/version/version.go" ; then
    echo "version/version.go has correct version"
  else
    echo "version/version.go source does not match version"
    exit 1
  fi

  if [ -e "${PATCH_DIR}/${ver}/make_functions.sh.patch" ]; then
    patch "${ver_builddir}/make_functions.sh" "${PATCH_DIR}/${ver}/make_functions.sh.patch"
  fi

  bbuild="${ver_builddir}/_build"
  mkdir -p "${bbuild}"
  for platform in ${OCI_IMAGE_PLATFORMS} ; do
    os=$(echo "${platform}" | cut -f1 -d/)
    if [ "${os}" != "linux" ]; then
      echo "${os} not supported"
      exit 1
    fi
    arch=$(echo "${platform}" | cut -f2 -d/ | sed 's/ppc64el/ppc64le/g')
    canonical_arch=${arch//ppc64le/ppc64el}

    platform_bin_dir="${bbuild}/linux_${canonical_arch}/bin"
    mkdir -p "${platform_bin_dir}"
    (cd "${platform_bin_dir}" && tar -xf "${ver_cachedir}/juju-agents-${ver}-linux-${canonical_arch}.tar.xz")

    if [ -f "${ver_cachedir}/juju-${ver}-linux-${canonical_arch}.tar.xz" ]; then
      (cd "${platform_bin_dir}" && tar -xf "${ver_cachedir}/juju-${ver}-linux-${canonical_arch}.tar.xz")
    fi
    
    if [ "${canonical_arch}" != "${arch}" ]; then
      cp -r "${bbuild}/${os}_${canonical_arch}" "${bbuild}/${os}_${arch}"
    fi
  done
}

validate_build() {
  ver=${1-""}
  image=${2-""}
  cloud=${3-""}
  caas_image_repo=${4-""}

  bins="${IMG_BUILD_DIR}/${ver}/_build/linux_amd64/bin"
  data="${IMG_DATA_DIR}/${ver}"

  mkdir -p "${data}"

  if [ "${cloud}-$(uname -s)" = "microk8s-Darwin" ]; then
    tmp_docker_image="/tmp/juju-operator-image-${ver}.image"
    ${DOCKER_BIN} save "${image}" | multipass transfer - microk8s-vm:${tmp_docker_image}
    microk8s ctr --namespace k8s.io image import ${tmp_docker_image}
    multipass exec microk8s-vm rm "${tmp_docker_image}"
  elif [ "${cloud}" = "microk8s" ]; then
    ${DOCKER_BIN} save "${image}" | microk8s.ctr --namespace k8s.io image import -
  elif [ "${cloud}" = "minikube" ]; then
    ${DOCKER_BIN} save "${image}" | minikube image load --overwrite=true - 
  else
	  echo "${cloud} is not a supported local k8s"
    exit 1
  fi

  echo "Using JUJU_DATA=${data} ${bins}/juju"
  PATH="${bins}:${PATH}" JUJU_DATA="${data}" test_bootstrap "${cloud}" "${caas_image_repo}"
}

test_bootstrap() {
  cloud=${1-""}
  caas_image_repo=${2-""}

  controller="test-$(echo "$RANDOM" | sha1sum | head -c 6)"
  model="model-$(echo "$RANDOM" | sha1sum | head -c 6)"
  echo "$(juju --version) ${controller} ${model}"
  juju bootstrap "${cloud}" "${controller}" --config caas-image-repo="${caas_image_repo}"
  juju add-model "${model}"
  juju deploy snappass-test
  juju wait-for application snappass-test
  yes=""
  if juju destroy-controller --help | grep -e "--yes"; then
    yes="--yes"
  fi
  #juju destroy-controller ${yes} --no-prompt --destroy-storage --destroy-all-models --force "${controller}"
  juju kill-controller ${yes} --no-prompt --timeout 1m "${controller}"
}
