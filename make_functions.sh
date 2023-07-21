#!/bin/bash
# Copyright 2023 Canonical Ltd.
# Licensed under the AGPLv3, see LICENCE file for details.
set -euf

BASE_DIR=$(realpath "$(dirname "$0")")
CACHE_DIR=${CACHE_DIR:-${BASE_DIR}/_cache}
BUILD_DIR=${BUILD_DIR:-${BASE_DIR}/_build}

OCI_IMAGE_PLATFORMS=${OCI_IMAGE_PLATFORMS:-linux/amd64 linux/arm64 linux/s390x linux/ppc64el}

mkdir -p "${CACHE_DIR}"
mkdir -p "${BUILD_DIR}"

juju_versions() {
  candidates=$(curl "https://api.snapcraft.io/v2/snaps/info/juju?fields=version" -s -H "Snap-Device-Series: 16" | yq -o=t '."channel-map" | map(select(.channel.risk=="stable" and .channel.track!="latest")) | map(.version) | unique')
  chosen=()
  for ver in ${candidates} ; do
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
  ver_cachedir="${CACHE_DIR}/${ver}"

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

  if [ -f "${ver_cachedir}/juju-core_${ver}.tar.gz" ]; then
    return 0
  fi

  return 1
}

cache_version() {
  ver=${1-""}
  majmin=$(echo "${ver}" | cut -d. -f1-2)
  ver_cachedir="${CACHE_DIR}/${ver}"
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

    (cd "${ver_cachedir}" && wget "https://launchpad.net/juju/${majmin}/${ver}/+download/juju-agents-${ver}-linux-${canonical_arch}.tar.xz")
  done

  if [ -f "${ver_cachedir}/juju-core_${ver}.tar.gz" ]; then
    echo "Found cached juju-core_${ver}.tar.gz"
  else
    (cd "${ver_cachedir}" && wget "https://launchpad.net/juju/${majmin}/${ver}/+download/juju-core_${ver}.tar.gz")
  fi
}

prepare_build() {
  ver=${1-""}
  if ! already_cached "${ver}" ; then
    echo "${ver} not available in cache"
    exit 1
  fi

  ver_cachedir="${CACHE_DIR}/${ver}"
  ver_builddir="${BUILD_DIR}/${ver}"

  tmp=$(mktemp -d)
  rm -rf "${ver_builddir}" || true
  (cd "${tmp}" && tar -xf "${ver_cachedir}/juju-core_${ver}.tar.gz" && mv "$(dirname "$(find . -type f -name "go.mod" | head -n1)")" "${ver_builddir}")
  rm -rf "${tmp}"

  if grep "${ver}" < "${ver_builddir}/version/version.go" ; then
    echo "version/version.go has correct version"
  else
    echo "version/version.go source does not match version"
    exit 1
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
    if [ "${canonical_arch}" != "${arch}" ]; then
      cp -r "${bbuild}/${os}_${canonical_arch}" "${bbuild}/${os}_${arch}"
    fi    
  done
}
