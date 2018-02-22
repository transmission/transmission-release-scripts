#!/usr/bin/env pwsh

$temp_dir = "C:\temp-${config}"
$prefix_dir = "${temp_dir}\prefix"

$cmake_opts = @(
    "-DCMAKE_SHARED_LINKER_FLAGS:STRING=/LTCG /INCREMENTAL:NO /OPT:REF",
    "-DCMAKE_EXE_LINKER_FLAGS:STRING=/LTCG /INCREMENTAL:NO /OPT:REF"
)

function download($url, $output) {
    if (!(Test-Path $output)) {
        Write-Host "Downloading ${url} to ${output}"
        Invoke-WebRequest -Uri $url -OutFile $output
    }
}

function vcenv() {
    & "C:\vagrant\vcenv-${config}" @args
}

function sign() {
    Write-Host "Signing $($args[-1])"
    psexec -nobanner -accepteula -s cmd /c "C:\vagrant\vcenv-${config}" signtool sign /f $cert_file /p $cert_password /sha1 $cert_sha1 /fd sha256 /tr "http://timestamp.digicert.com" /td sha256 @args
}

function do_cmake_build_install($source_dir, $build_dir, $opts) {
    mkdir -f $build_dir | Out-Null
    pushd $build_dir
    vcenv cmake $source_dir -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=RelWithDebInfo "-DCMAKE_INSTALL_PREFIX=${prefix_dir}" $opts $cmake_opts
    vcenv nmake
    vcenv nmake install/fast
    popd
}

function build_expat($version) {
    if (Test-Path "${prefix_dir}\bin\expat.pdb") {
        return
    }

    $url = "https://github.com/libexpat/libexpat/releases/download/R_$($version.replace(".", "_"))/expat-${version}.tar.gz"
    $opts = @(
        "-DBUILD_tools=OFF",
        "-DBUILD_examples=OFF",
        "-DBUILD_tests=OFF",
        "-DBUILD_static=OFF"
    )

    download $url "${temp_dir}\expat-${version}.tar.gz"
    pushd $temp_dir
    7z x "expat-${version}.tar.gz"
    7z x "expat-${version}.tar"
    popd

    $build_dir = "${temp_dir}\expat-${version}\.build-${config}"
    do_cmake_build_install .. $build_dir $opts
    Copy-Item -Path "${build_dir}\expat.pdb" -Destination "${prefix_dir}\bin"
}

function build_dbus($version) {
    if (Test-Path "${prefix_dir}\bin\dbus-1.pdb") {
        return
    }

    $url = "https://dbus.freedesktop.org/releases/dbus/dbus-${version}.tar.gz"
    $opts = @(
        "-DEXPAT_INCLUDE_DIR:PATH=${prefix_dir}\include",
        "-DEXPAT_LIBRARY:FILEPATH=${prefix_dir}\lib\expat.lib",
        "-DDBUS_BUILD_TESTS=OFF"
    )

    download $url "${temp_dir}\dbus-${version}.tar.gz"
    pushd $temp_dir
    7z x "dbus-${version}.tar.gz"
    7z x "dbus-${version}.tar"
    popd

    $build_dir = "${temp_dir}\dbus-${version}\.build-${config}"
    do_cmake_build_install ..\cmake $build_dir $opts
    Copy-Item -Path "${build_dir}\bin\dbus-1.pdb" -Destination "${prefix_dir}\bin"
}

function build_zlib($version) {
    if (Test-Path "${prefix_dir}\bin\zlib.pdb") {
        return
    }

    $url = "https://zlib.net/fossils/zlib-${version}.tar.gz"
    $opts = @()

    download $url "${temp_dir}\zlib-${version}.tar.gz"
    pushd $temp_dir
    7z x "zlib-${version}.tar.gz"
    7z x "zlib-${version}.tar"
    popd

    $build_dir = "${temp_dir}\zlib-${version}\.build-${config}"
    do_cmake_build_install .. $build_dir $opts
    Copy-Item -Path "${build_dir}\zlib.pdb" -Destination "${prefix_dir}\bin"
}

function build_openssl($version) {
    if (Test-Path "${prefix_dir}\bin\ssleay32.pdb") {
        return
    }

    $url = "https://www.openssl.org/source/old/$($version -replace '[a-z]$','')/openssl-${version}.tar.gz"
    $ossl_config = if ($config -eq "x86") { "VC-WIN32" } else { "VC-WIN64A" }
    $ossl_prep = if ($config -eq "x86") { "ms\do_nasm.bat" } else { "ms\do_win64a.bat" }

    download $url "${temp_dir}\openssl-${version}.tar.gz"
    pushd $temp_dir
    7z x "openssl-${version}.tar.gz"
    7z x "openssl-${version}.tar"
    popd

    $build_dir = "${temp_dir}\openssl-${version}"
    pushd $build_dir
    vcenv perl Configure "--prefix=${prefix_dir}" $ossl_config
    vcenv cmd /c $ossl_prep
    vcenv nmake -f ms\ntdll.mak
    vcenv nmake -f ms\ntdll.mak install
    popd

    Copy-Item -Path "${build_dir}\out32dll\libeay32.pdb" -Destination "${prefix_dir}\bin"
    Copy-Item -Path "${build_dir}\out32dll\ssleay32.pdb" -Destination "${prefix_dir}\bin"
}

function build_curl($version) {
    if (Test-Path "${prefix_dir}\bin\libcurl.pdb") {
        return
    }

    $url = "https://curl.haxx.se/download/curl-${version}.tar.gz"
    $opts = @(
        "-DCMAKE_USE_OPENSSL=ON",
        "-DCURL_WINDOWS_SSPI=OFF",
        "-DBUILD_CURL_TESTS=OFF",
        "-DCURL_DISABLE_DICT=ON",
        "-DCURL_DISABLE_GOPHER=ON",
        "-DCURL_DISABLE_IMAP=ON",
        "-DCURL_DISABLE_SMTP=ON",
        "-DCURL_DISABLE_POP3=ON",
        "-DCURL_DISABLE_RTSP=ON",
        "-DCURL_DISABLE_TFTP=ON",
        "-DCURL_DISABLE_TELNET=ON",
        "-DCURL_DISABLE_LDAP=ON",
        "-DCURL_DISABLE_LDAPS=ON",
        "-DENABLE_MANUAL=OFF"
    )

    download $url "${temp_dir}\curl-${version}.tar.gz"
    pushd $temp_dir
    7z x "curl-${version}.tar.gz"
    7z x "curl-${version}.tar"
    popd

    $build_dir = "${temp_dir}\curl-${version}\.build-${config}"
    do_cmake_build_install .. $build_dir $opts
    Copy-Item -Path "${build_dir}\lib\libcurl.pdb" -Destination "${prefix_dir}\bin"
}

function build_qt($version) {
    if (Test-Path "${prefix_dir}\bin\Qt5Core.pdb") {
        return
    }

    $url = "https://download.qt.io/archive/qt/$($version -replace '\.\d+$','')/${version}/single/qt-everywhere-opensource-src-${version}.tar.gz"
    $opts = @(
        "-platform", "win32-msvc2015",
        "-mp",
        "-ltcg",
        "-opensource",
        "-confirm-license",
        "-prefix", $prefix_dir,
        "-release",
        "-force-debug-info",
        "-no-opengl",
        "-dbus",
        "-skip", "connectivity",
        # "-skip", "declarative", # QTBUG-51409
        "-skip", "doc",
        "-skip", "enginio",
        "-skip", "graphicaleffects",
        "-skip", "location",
        "-skip", "multimedia",
        "-skip", "quickcontrols",
        "-skip", "script",
        "-skip", "sensors",
        "-skip", "serialport",
        "-skip", "webchannel",
        "-skip", "webengine",
        "-skip", "websockets",
        "-ssl",
        "-openssl",
        "-system-zlib",
        "-qt-pcre",
        "-qt-libpng",
        "-qt-libjpeg",
        "-no-harfbuzz",
        "-no-sse2",
        "-no-sse3",
        "-no-ssse3",
        "-no-sse4.1",
        "-no-sse4.2",
        "-no-avx",
        "-no-avx2",
        "-no-wmf-backend",
        "-no-qml-debug",
        "-nomake", "examples",
        "-nomake", "tests",
        "-nomake", "tools",
        "-I", "${prefix_dir}\include",
        "-L", "${prefix_dir}\lib",
        "OPENSSL_LIBS=libeay32.lib ssleay32.lib",
        "ZLIB_LIBS=zlib.lib"
    )

    download $url "${temp_dir}\qt-everywhere-opensource-src-${version}.tar.gz"
    pushd $temp_dir
    7z x "qt-everywhere-opensource-src-${version}.tar.gz"
    7z x "qt-everywhere-opensource-src-${version}.tar"
    popd

    $build_dir = "${temp_dir}\qt-everywhere-opensource-src-${version}\.build-${config}"
    cmake -E remove_directory $build_dir
    $env:PATH = "${prefix_dir}\bin;${build_dir}\qtbase\lib;${env:PATH}"
    md -f $build_dir | Out-Null

    pushd $build_dir
    vcenv cmd /c "..\configure.bat" $opts
    vcenv nmake
    vcenv nmake install
    popd

    # install target doesn't copy PDBs for release DLLs
    Get-Childitem -Path "${build_dir}\lib" | %% { if ($_ -is [System.IO.DirectoryInfo] -or $_.Name -like "*.pdb") { Copy-Item -Path $_.FullName -Destination "${prefix_dir}\lib" -Filter "*.pdb" -Recurse -Force } }
    Get-Childitem -Path "${build_dir}\plugins" | %% { if ($_ -is [System.IO.DirectoryInfo] -or $_.Name -like "*.pdb") { Copy-Item -Path $_.FullName -Destination "${prefix_dir}\plugins" -Filter "*.pdb" -Recurse -Force } }
}

function build_transmission() {
    $source_dir = "${env:USERPROFILE}\src"
    cmake -E remove_directory $source_dir
    mkdir $source_dir | Out-Null
    pushd $source_dir

    & git clone -b $release_branch $repo_uri . 2>&1 | %{ "$_" }
    & git submodule update --init 2>&1 | %{ "$_" }

    $build_dir = "${source_dir}\.build-${config}"
    mkdir $build_dir | Out-Null
    pushd $build_dir

    $env:PATH = "${prefix_dir}\bin;" + $env:PATH

    $tr_prefix_dir = "${build_dir}\dst"
    vcenv cmake .. -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=RelWithDebInfo "-DCMAKE_INSTALL_PREFIX=${tr_prefix_dir}" $cmake_opts -DUSE_QT5=ON
    vcenv nmake
    vcenv nmake test
    vcenv nmake install/fast

    $tr_wix_dir = "${build_dir}\wix"
    Copy-Item -Path C:\vagrant\wix -Destination $build_dir -Recurse

    $wix_config = @"
<?xml version='1.0' encoding='utf-8'?>
<Include xmlns='http://schemas.microsoft.com/wix/2006/wi'>
    <?define TrVersion = "${release_version}" ?>
    <?define TrVersionMsi = "${release_version}.0" ?>
    <?define TrVersionFull = "${release_version} (${release_revision})" ?>
</Include>
"@
    $wix_config | Out-File "$tr_wix_dir\TransmissionConfig.wxi" -Encoding utf8 -Force

    $tr_wix_prefix_dir = "${tr_wix_dir}\prefix"
    mkdir "${tr_wix_prefix_dir}\bin" | Out-Null
    mkdir "${tr_wix_prefix_dir}\etc" | Out-Null
    mkdir "${tr_wix_prefix_dir}\plugins\platforms" | Out-Null

    $dbg_dir = "${build_dir}\dbg"
    mkdir $dbg_dir | Out-Null

    $tr_pdb_names = @()

    foreach ($x in @("remote", "create", "edit", "show", "daemon", "qt")) {
        Copy-Item -Path "${tr_prefix_dir}\bin\transmission-${x}.exe" -Destination "${tr_wix_prefix_dir}\bin\"
        sign "${tr_wix_prefix_dir}\bin\transmission-${x}.exe"
        $tr_pdb_names += "transmission-${x}.pdb"
    }

    Get-Childitem -Path $build_dir -Filter "*.pdb" -Recurse | % {
        if ($tr_pdb_names -contains $_.Name) {
            Copy-Item -Path $_.FullName -Destination $dbg_dir
        }
    }

    foreach ($x in @("libcurl", "libeay32", "ssleay32", "zlib", "dbus-1-3", "expat")) {
        Copy-Item -Path "${prefix_dir}\bin\${x}.dll" -Destination "${tr_wix_prefix_dir}\bin\"
        sign "${tr_wix_prefix_dir}\bin\${x}.dll"

        if ($x -eq "dbus-1-3") {
            $x = "dbus-1"
        }

        Copy-Item -Path "${prefix_dir}\bin\${x}.pdb" -Destination $dbg_dir
    }

    foreach ($x in @("Core", "DBus", "Gui", "Network", "Widgets")) {
        Copy-Item -Path "${prefix_dir}\bin\Qt5${x}.dll" -Destination "${tr_wix_prefix_dir}\bin\"
        sign "${tr_wix_prefix_dir}\bin\Qt5${x}.dll"
        Copy-Item -Path "${prefix_dir}\bin\Qt5${x}.pdb" -Destination $dbg_dir
    }

    Copy-Item -Path "${prefix_dir}\plugins\platforms\qwindows.dll" -Destination "${tr_wix_prefix_dir}\plugins\platforms\"
    sign "${tr_wix_prefix_dir}\plugins\platforms\qwindows.dll"
    Copy-Item -Path "${prefix_dir}\plugins\platforms\qwindows.pdb" -Destination $dbg_dir

    Copy-Item -Path "${tr_prefix_dir}\share" -Destination "${tr_wix_prefix_dir}\" -Recurse

    New-Item -ItemType file "${tr_wix_prefix_dir}\etc\qt.conf"

    $arch = if ($config -eq "x86") { "x86" } else { "x64" }

    mkdir $dst_dir
    vcenv cmake -E chdir $tr_wix_dir nmake "VERSION=${release_version}" "ARCH=${arch}" "SRCDIR=${tr_wix_prefix_dir}" "OUTDIR=${dst_dir}" "OBJDIR=${tr_wix_prefix_dir}" "THIRDPARTYIDIR=${tr_wix_prefix_dir}" "QTDIR=${tr_wix_prefix_dir}" "QTQMSRCDIR=${prefix_dir}\translations"
    sign /d "Transmission BitTorrent Client" /du "https://transmissionbt.com/" "${dst_dir}\transmission-${release_version}-${arch}.msi"

    pushd $dbg_dir
    7z a "${dst_dir}\transmission-${release_version}-${arch}-pdb.zip" *
    popd

    popd
    popd
}

# cmake -E remove_directory $temp_dir
cmake -E make_directory $temp_dir

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

build_expat "2.1.0"
build_dbus "1.10.6"
build_zlib "1.2.8"
build_openssl "1.0.2g"
build_curl "7.47.1"
build_qt "5.6.0"

build_transmission
