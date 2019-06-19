#!/usr/bin/env bash

set -e
set -o pipefail

REPO_URI='https://github.com/transmission/transmission'
RELEASE_BRANCH='master'
ENABLE_SIGNING=${ENABLE_SIGNING:-0}

THIS_DIR=`realpath $(dirname "$0")`

make_source()
{
    local REMOTE_DST_DIR='/root/dst'

    local SCRIPT=''
    SCRIPT+="REPO_URI='${REPO_URI}';"
    SCRIPT+="RELEASE_BRANCH='${RELEASE_BRANCH}';"
    SCRIPT+="RELEASE_VERSION='${RELEASE_VERSION}';"
    SCRIPT+="RELEASE_REVISION='${RELEASE_REVISION}';"
    SCRIPT+="DST_DIR='${REMOTE_DST_DIR}';"
    SCRIPT+=`cat "${THIS_DIR}/build-source.sh"`

    docker run --rm --volume "${DST_DIR}:${REMOTE_DST_DIR}" debian:stable bash -c "set -x; ${SCRIPT}"
}

make_macos()
{
    local CERT_FILE='Certificates.p12'
    local CERT_NAME=''
    local CERT_PASSWORD=''
    local REMOTE_DST_DIR='/Users/vagrant/dst'

    if [ "${ENABLE_SIGNING}" -ne 0 ]; then
        CERT_NAME=`vault kv get -field=name secret/transmission/macos-cert`
        CERT_PASSWORD=`vault kv get -field=password secret/transmission/macos-cert`
    fi

    local SCRIPT=''
    SCRIPT+="REPO_URI='${REPO_URI}';"
    SCRIPT+="RELEASE_BRANCH='${RELEASE_BRANCH}';"
    SCRIPT+="RELEASE_VERSION='${RELEASE_VERSION}';"
    SCRIPT+="RELEASE_REVISION='${RELEASE_REVISION}';"
    SCRIPT+="ENABLE_SIGNING='${ENABLE_SIGNING}';"
    SCRIPT+="CERT_FILE='/Users/vagrant/${CERT_FILE}';"
    SCRIPT+="CERT_NAME='${CERT_NAME}';"
    SCRIPT+="CERT_PASSWORD='${CERT_PASSWORD}';"
    SCRIPT+="DST_DIR='${REMOTE_DST_DIR}';"
    SCRIPT+=`cat "${THIS_DIR}/build-macos.sh"`

    pushd macos
    vagrant up
    vagrant ssh-config > ./vagrant.ssh.config

    if [ "${ENABLE_SIGNING}" -ne 0 ]; then
        vault kv get -field=file secret/transmission/macos-cert | base64 -d > "${PWD}/${CERT_FILE}"
        trap "{ shred -zvu '${PWD}/${CERT_FILE}'; }" EXIT

        scp -F ./vagrant.ssh.config "${PWD}/${CERT_FILE}" default:.

        shred -zvu "${PWD}/${CERT_FILE}"
        trap - EXIT
    fi

    vagrant ssh -c "set -x; $SCRIPT"

    scp -F ./vagrant.ssh.config "default:${REMOTE_DST_DIR}/Transmission.dmg" "$DST_DIR/Transmission-$RELEASE_VERSION.dmg"
    scp -F ./vagrant.ssh.config "default:${REMOTE_DST_DIR}/Transmission-dsym.zip" "$DST_DIR/Transmission-$RELEASE_VERSION-dsym.zip"

    if [ "${ENABLE_SIGNING}" -ne 0 ]; then
        openssl dgst -sha1 -binary < "$DST_DIR/Transmission-$RELEASE_VERSION.dmg" | \
        openssl dgst -sha1 -sign <(vault kv get -field=file secret/transmission/macos-sparkle-key | base64 -d) | \
        openssl enc -base64 > "$DST_DIR/Transmission-$RELEASE_VERSION.dmg.sig"

        openssl dgst -sha1 \
            -verify sparkle_dsa_pub.pem \
            -signature <(openssl base64 -d -in "$DST_DIR/Transmission-$RELEASE_VERSION.dmg.sig") \
            < <(openssl sha1 -binary "$DST_DIR/Transmission-$RELEASE_VERSION.dmg")
    fi

    vagrant ssh -c "set -x; rm -rf ${REMOTE_DST_DIR}"

    rm ./vagrant.ssh.config
    vagrant halt
    popd
}

make_windows()
{
    local CERT_FILE='Certificates.pfx'
    local CERT_NAME=''
    local CERT_SHA1=''
    local CERT_PASSWORD=''
    local REMOTE_DST_DIR='C:\vagrant\dst'

    if [ "${ENABLE_SIGNING}" -ne 0 ]; then
        CERT_NAME=`vault kv get -field=name secret/transmission/windows-cert`
        CERT_SHA1=`vault kv get -field=sha1 secret/transmission/windows-cert`
        CERT_PASSWORD=`vault kv get -field=password secret/transmission/windows-cert`
    fi

    local SCRIPT=''
    SCRIPT+="\$repo_uri = '${REPO_URI}';"
    SCRIPT+="\$release_branch = '${RELEASE_BRANCH}';"
    SCRIPT+="\$release_version = '${RELEASE_VERSION}';"
    SCRIPT+="\$release_revision = '${RELEASE_REVISION}';"
    SCRIPT+="\$enable_signing = $([ "${ENABLE_SIGNING}" -ne 0 ] && echo '$true' || echo '$false');"
    SCRIPT+="\$cert_file = 'C:\\vagrant\\${CERT_FILE}';"
    SCRIPT+="\$cert_name = '${CERT_NAME}';"
    SCRIPT+="\$cert_sha1 = '${CERT_SHA1}';"
    SCRIPT+="\$cert_password = '${CERT_PASSWORD}';"
    SCRIPT+="\$dst_dir = '${REMOTE_DST_DIR}';"
    SCRIPT+=`cat "${THIS_DIR}/build-windows.ps1"`

    pushd windows
    vagrant up # on non-Windows, may need to install `winrm` and `winrm-elevated` gems

    if [ "${ENABLE_SIGNING}" -ne 0 ]; then
        vault kv get -field=file secret/transmission/windows-cert | base64 -d > "${PWD}/${CERT_FILE}"
        trap "{ shred -zvu '${PWD}/${CERT_FILE}'; }" EXIT
    fi

    vagrant powershell -c "\$arch = 'x86'; $SCRIPT"
    vagrant powershell -c "\$arch = 'x64'; $SCRIPT"

    if [ "${ENABLE_SIGNING}" -ne 0 ]; then
        shred -zvu "${PWD}/${CERT_FILE}"
        trap - EXIT
    fi

    cp -f dst/transmission-*.{zip,msi} "${DST_DIR}/"
    rm -rf dst

    vagrant halt
    popd
}

if [ "${ENABLE_SIGNING}" -ne 0 ]; then
    vault status >/dev/null
fi

TMP_REPO_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_REPO_DIR}"' EXIT
git clone --branch "${RELEASE_BRANCH}" --depth 1 "${REPO_URI}" "${TMP_REPO_DIR}"
RELEASE_REVISION="$(cd "${TMP_REPO_DIR}" && git rev-list --max-count=1 "${RELEASE_BRANCH}" | head -c10)"
RELEASE_VERSION="$(fgrep -m1 TR_USER_AGENT_PREFIX "${TMP_REPO_DIR}/CMakeLists.txt" | cut -d'"' -f2)"
echo "${RELEASE_VERSION}" | fgrep -vq '+' || RELEASE_VERSION="${RELEASE_VERSION}-r${RELEASE_REVISION}"

echo "Release version: ${RELEASE_VERSION} / ${RELEASE_REVISION}"

DST_DIR="${THIS_DIR}/${RELEASE_VERSION}"
mkdir -p "${DST_DIR}"

make_source
make_macos
make_windows
