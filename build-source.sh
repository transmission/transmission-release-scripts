#!/usr/bin/env bash

set -e
set -o pipefail

build_transmission() {
    cd
    git clone -b "${RELEASE_BRANCH}" "${REPO_URI}" src
    cd src
    git submodule update --init
    ./autogen.sh
    make distcheck
}

apt-get update
apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    bzip2 \
    g++ \
    gcc \
    gettext \
    git cmake \
    intltool \
    libcurl4-openssl-dev \
    libevent-dev \
    libglib2.0-dev \
    libssl-dev \
    libtool \
    make \
    patch \
    pkg-config \
    pkg-config \
    xz-utils \
    zlib1g-dev

build_transmission

mkdir -p "${DST_DIR}"
cp transmission-${RELEASE_VERSION}.tar* "${DST_DIR}/"
