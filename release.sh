#!/usr/bin/env bash

set -e
set -o pipefail

REPO_URI='https://github.com/transmission/transmission'
RELEASE_BRANCH='2.9x'
RELEASE_VERSION='2.94'
RELEASE_REVISION=`git ls-remote "${REPO_URI}" "refs/heads/${RELEASE_BRANCH}" | cut -f1 | head -c10`

THIS_DIR=`realpath $(dirname "$0")`
DST_DIR="${THIS_DIR}/${RELEASE_VERSION}"

make_source()
{
    local REMOTE_DST_DIR='/root/dst'

    local SCRIPT=`cat "${THIS_DIR}/build-source.sh"`
    SCRIPT="REPO_URI='${REPO_URI}'; ${SCRIPT}"
    SCRIPT="RELEASE_BRANCH='${RELEASE_BRANCH}'; ${SCRIPT}"
    SCRIPT="RELEASE_VERSION='${RELEASE_VERSION}'; ${SCRIPT}"
    SCRIPT="RELEASE_REVISION='${RELEASE_REVISION}'; ${SCRIPT}"
    SCRIPT="DST_DIR='${REMOTE_DST_DIR}'; ${SCRIPT}"

    docker run --rm --volume "${DST_DIR}:${REMOTE_DST_DIR}" debian:stable bash -c "set -x; ${SCRIPT}"
}

make_macos()
{
    local CERT_FILE='Certificates.p12'
    local CERT_NAME=`vault read -field=name secret/transmission/macos-cert`
    local CERT_PASSWORD=`vault read -field=password secret/transmission/macos-cert`
    local REMOTE_DST_DIR='/Users/vagrant/dst'

    local SCRIPT=`cat "${THIS_DIR}/build-macos.sh"`
    SCRIPT="REPO_URI='${REPO_URI}'; ${SCRIPT}"
    SCRIPT="RELEASE_BRANCH='${RELEASE_BRANCH}'; ${SCRIPT}"
    SCRIPT="RELEASE_VERSION='${RELEASE_VERSION}'; ${SCRIPT}"
    SCRIPT="RELEASE_REVISION='${RELEASE_REVISION}'; ${SCRIPT}"
    SCRIPT="CERT_FILE='/Users/vagrant/${CERT_FILE}'; ${SCRIPT}"
    SCRIPT="CERT_NAME='${CERT_NAME}'; ${SCRIPT}"
    SCRIPT="CERT_PASSWORD='${CERT_PASSWORD}'; ${SCRIPT}"
    SCRIPT="DST_DIR='${REMOTE_DST_DIR}'; ${SCRIPT}"

    pushd macos
    vagrant up --provision
    vagrant ssh-config > ./vagrant.ssh.config

    vault read -field=file secret/transmission/macos-cert | base64 -d > "${PWD}/${CERT_FILE}"
    trap "{ shred -zvu '${PWD}/${CERT_FILE}'; }" EXIT

    scp -F ./vagrant.ssh.config "${PWD}/${CERT_FILE}" default:.

    shred -zvu "${PWD}/${CERT_FILE}"
    trap - EXIT

    vagrant ssh -c "set -x; $SCRIPT"

    scp -F ./vagrant.ssh.config "default:${REMOTE_DST_DIR}/Transmission.dmg" "$DST_DIR/Transmission-$RELEASE_VERSION.dmg"
    scp -F ./vagrant.ssh.config "default:${REMOTE_DST_DIR}/Transmission-dsym.zip" "$DST_DIR/Transmission-$RELEASE_VERSION-dsym.zip"

    openssl dgst -sha1 -binary < "$DST_DIR/Transmission-$RELEASE_VERSION.dmg" | \
    openssl dgst -dss1 -sign <(vault read -field=file secret/transmission/macos-sparkle-key | base64 -d) | \
    openssl enc -base64 > "$DST_DIR/Transmission-$RELEASE_VERSION.dmg.sig"

    openssl dgst -dss1 \
        -verify sparkle_dsa_pub.pem \
        -signature <(openssl base64 -d -in "$DST_DIR/Transmission-$RELEASE_VERSION.dmg.sig") \
        < <(openssl sha1 -binary "$DST_DIR/Transmission-$RELEASE_VERSION.dmg")

    vagrant ssh -c "set -x; rm -rf ${REMOTE_DST_DIR}"

    rm ./vagrant.ssh.config
    vagrant halt
    popd
}

make_windows()
{
    local CERT_FILE='Certificates.pfx'
    local CERT_NAME=`vault read -field=name secret/transmission/windows-cert`
    local CERT_SHA1=`vault read -field=sha1 secret/transmission/windows-cert`
    local CERT_PASSWORD=`vault read -field=password secret/transmission/windows-cert`
    local REMOTE_DST_DIR='C:\vagrant\dst'

    local SCRIPT=`cat "${THIS_DIR}/build-windows.ps1"`
    SCRIPT="\$repo_uri = '${REPO_URI}'; ${SCRIPT}"
    SCRIPT="\$release_branch = '${RELEASE_BRANCH}'; ${SCRIPT}"
    SCRIPT="\$release_version = '${RELEASE_VERSION}'; ${SCRIPT}"
    SCRIPT="\$release_revision = '${RELEASE_REVISION}'; ${SCRIPT}"
    SCRIPT="\$cert_file = 'C:\\vagrant\\${CERT_FILE}'; ${SCRIPT}"
    SCRIPT="\$cert_name = '${CERT_NAME}'; ${SCRIPT}"
    SCRIPT="\$cert_sha1 = '${CERT_SHA1}'; ${SCRIPT}"
    SCRIPT="\$cert_password = '${CERT_PASSWORD}'; ${SCRIPT}"
    SCRIPT="\$dst_dir = '${REMOTE_DST_DIR}'; ${SCRIPT}"

    pushd windows
    vagrant up

    vault read -field=file secret/transmission/windows-cert | base64 -d > "${PWD}/${CERT_FILE}"
    trap "{ shred -zvu '${PWD}/${CERT_FILE}'; }" EXIT

    vagrant powershell -c "\$config = 'x86'; $SCRIPT"
    vagrant powershell -c "\$config = 'x86-64'; $SCRIPT"

    shred -zvu "${PWD}/${CERT_FILE}"
    trap - EXIT

    cp -f dst/transmission-*.{zip,msi} "${DST_DIR}/"
    rm -rf dst

    vagrant halt
    popd
}

vault status >/dev/null

mkdir -p "${DST_DIR}"

make_source
make_macos
make_windows
