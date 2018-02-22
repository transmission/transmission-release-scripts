#!/usr/bin/env bash

set -e

build_transmission() {
    cd
    git clone -b "${RELEASE_BRANCH}" "${REPO_URI}" src
    cd src
    git submodule update --init
    ./autogen.sh
    make distcheck
}

apt-get update
apt-get install -y bzip2 xz-utils git cmake gcc g++ autoconf automake libtool intltool gettext patch pkg-config pkg-config libcurl4-openssl-dev libevent-dev zlib1g-dev libssl-dev libglib2.0-dev

build_transmission

mkdir -p "${DST_DIR}"
cp transmission-${RELEASE_VERSION}.tar* "${DST_DIR}/"
