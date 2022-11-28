#!/usr/bin/env bash

set -e
set -o pipefail

KEYCHAIN_CREATE_NEW=1
KEYCHAIN_NAME="${HOME}/Library/Keychains/transmission-db"
KEYCHAIN_PASSWORD='vagrant'
BUILD_TYPE='Release'

build_transmission() {
    cd
    rm -rf src "${DST_DIR}"
    mkdir -p src "${DST_DIR}"
    pushd src

    git clone --branch "${RELEASE_BRANCH}" --depth 1 --recurse-submodules --shallow-submodules "${REPO_URI}" .

    xcodebuild -project Transmission.xcodeproj clean
    xcodebuild -project Transmission.xcodeproj -target Transmission -configuration "${BUILD_TYPE}"

    mkdir -p dmg
    cp -R "build/${BUILD_TYPE}/Transmission.app" dmg/

    if [ "${ENABLE_SIGNING}" -ne 0 ]; then
        security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_NAME}"
        security set-key-partition-list -S 'apple:,codesign:' -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_NAME}"
        security dump-keychain -a "${KEYCHAIN_NAME}"
        security list-keychains -s "${KEYCHAIN_NAME}"
        
        codesign --force --timestamp --options runtime -v -s "${CERT_NAME}" dmg/Transmission.app/Contents/Library/QuickLook/QuickLookPlugin.qlgenerator/Contents/MacOS/QuickLookPlugin
        codesign --force --timestamp --options runtime -v -s "${CERT_NAME}" dmg/Transmission.app/Contents/Frameworks/Sparkle.framework/Versions/A/Resources/Autoupdate.app/Contents/MacOS/Autoupdate
        codesign --force --timestamp --options runtime -v -s "${CERT_NAME}" dmg/Transmission.app/Contents/Frameworks/Sparkle.framework/Versions/A/Resources/Autoupdate.app/Contents/MacOS/fileop
        codesign --force --timestamp --options runtime -v -s "${CERT_NAME}" dmg/Transmission.app/Contents/Frameworks/Sparkle.framework/Versions/A/Resources/Autoupdate.app
        codesign --force --deep --timestamp --options runtime -v -s "${CERT_NAME}" dmg/Transmission.app
        
        spctl -a -v dmg/Transmission.app
        security list-keychains -s login.keychain
    fi

    git clone https://github.com/create-dmg/create-dmg.git
    ./create-dmg/create-dmg \
        --volname "Transmission" \
        --background "./macos/dmg_background.png" \
        --window-pos 200 120 \
        --window-size 500 332 \
        --icon-size 120 \
        --text-size 14 \
        --icon "Transmission.app" 100 180 \
        --hide-extension "Transmission.app" \
        --format UDBZ \
        --app-drop-link 390 180 \
        "Transmission.dmg" \
        "./dmg/"

    rm -rf ./create-dmg
    mv "Transmission.dmg" "${DST_DIR}/Transmission.dmg"

    mkdir -p dsym
    cp -RPp "build/${BUILD_TYPE}/QuickLookPlugin.qlgenerator.dSYM" "build/${BUILD_TYPE}/Transmission.app.dSYM" dsym/
    (cd dsym && zip -r9 "${DST_DIR}/Transmission-dsym.zip" *)

    popd
    rm -rf src
}

ERR=0

if [ "${ENABLE_SIGNING}" -ne 0 ]; then
    if [ ${KEYCHAIN_CREATE_NEW} -ne 0 ]; then
        security delete-keychain "${KEYCHAIN_NAME}" || true
        security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_NAME}"
    fi

    security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_NAME}" && security import "${CERT_FILE}" -P "${CERT_PASSWORD}" -k "${KEYCHAIN_NAME}" -T /usr/bin/codesign || ERR=1
    rm -Pf "${CERT_FILE}"
    [ ${ERR} -eq 0 ] || exit ${ERR}
fi

build_transmission || ERR=1

if [ "${ENABLE_SIGNING}" -ne 0 ]; then
    security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_NAME}"
    security delete-identity -c "${CERT_NAME}" "${KEYCHAIN_NAME}"
    security lock-keychain "${KEYCHAIN_NAME}"

    if [ ${KEYCHAIN_CREATE_NEW} -ne 0 ]; then
        security delete-keychain "${KEYCHAIN_NAME}"
    fi
fi

[ ${ERR} -eq 0 ] || exit ${ERR}
