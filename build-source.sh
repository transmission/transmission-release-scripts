#!/usr/bin/env bash

set -e
set -o pipefail

build_transmission() {
    cd
    git clone --branch "${RELEASE_BRANCH}" --depth 1 --recurse-submodules --shallow-submodules "${REPO_URI}" src
    cd src

    # Patch version to support non-release builds
    sed -ri "s|^(\s*AC_INIT\(\[([^]]*)\],)\[([^]]*)\]|\1[${RELEASE_VERSION}]|" configure.ac

    ./autogen.sh
    make distcheck
}

apt-get update
apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    bzip2 \
    cmake \
    g++ \
    gcc \
    gettext \
    git \
    intltool \
    libcurl4-openssl-dev \
    libevent-dev \
    libglib2.0-dev \
    libssl-dev \
    libtool \
    make \
    pkg-config \
    xz-utils \
    zlib1g-dev

build_transmission

mkdir -p "${DST_DIR}"
cp transmission-${RELEASE_VERSION}.tar* "${DST_DIR}/"
