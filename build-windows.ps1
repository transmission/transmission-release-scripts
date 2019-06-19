#!/usr/bin/env pwsh

$ErrorActionPreference = "Stop"
$PSDefaultParameterValues["*:ErrorAction"] = $ErrorActionPreference

# https://github.com/PowerShell/PowerShell/issues/2138
$ProgressPreference = "SilentlyContinue"

$dl_dir = "C:\tools"
$temp_dir = "C:\tools\msvc16-${arch}.build"
$prefix_dir = "C:\tools\msvc16-${arch}"

$cmake_build_type = "RelWithDebInfo"
$env:LDFLAGS = "/LTCG /INCREMENTAL:NO /OPT:REF /DEBUG /PDBALTPATH:%_PDB%"

function download($url, $output) {
    if (!(Test-Path $output)) {
        Write-Host "Downloading ${url} to ${output}"
        Invoke-WebRequest -Uri $url -OutFile $output
    }
}

function download_and_unpack($url, $name) {
    download $url "${dl_dir}\${name}"

    pushd $temp_dir

    if ($name -match '^(.+)(\.(?:gz|bz2|xz))$') {
        if (!(Test-Path "${dl_dir}\$($Matches[1])")) {
            7z x -y "${dl_dir}\${name}" "-o${dl_dir}"
        }
        $name = $Matches[1]
    }

    if ($name -match '^(.+)(\.(?:tar|zip))$') {
        7z x -y "${dl_dir}\${name}"
        $name = $Matches[1]
    }

    popd

    return "${temp_dir}\${name}"
}

function vcenv() {
    & "C:\vagrant\vcenv-${arch}" @args
}

function sign() {
    if ($enable_signing) {
        Write-Host "Signing $($args[-1])"
        cmd /c psexec -nobanner -accepteula -s cmd /c "C:\vagrant\vcenv-${arch}" signtool sign /f $cert_file /p $cert_password /sha1 $cert_sha1 /fd sha256 /tr "http://timestamp.digicert.com" /td sha256 @args "2>&1"
    }
}

function do_cmake_build_install($source_dir, $build_dir, $opts) {
    mkdir -f $build_dir | Out-Null
    pushd $build_dir
    vcenv cmake $source_dir -G "NMake Makefiles" "-DCMAKE_BUILD_TYPE=${cmake_build_type}" "-DCMAKE_INSTALL_PREFIX=${prefix_dir}" $opts $cmake_opts
    vcenv nmake
    vcenv nmake install/fast
    popd
}

function build_expat($version) {
    if (Test-Path "${prefix_dir}\bin\libexpat.pdb") {
        return
    }

    $url = "https://github.com/libexpat/libexpat/releases/download/R_$($version.replace(".", "_"))/expat-${version}.tar.bz2"
    $opts = @(
        "-DBUILD_tools=OFF",
        "-DBUILD_examples=OFF",
        "-DBUILD_tests=OFF"
    )

    $source_dir = (download_and_unpack $url "expat-${version}.tar.bz2")[-1]

    $build_dir = "${source_dir}\.build"
    do_cmake_build_install .. $build_dir $opts
    Copy-Item -Path "${build_dir}\libexpat.pdb" -Destination "${prefix_dir}\bin"
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

    $source_dir = (download_and_unpack $url "dbus-${version}.tar.gz")[-1]

    # Patch to remove "-3" (or whatever) revision suffix part from DLL name since Qt doesn't seem to support that and we don't really need it
    $patched_file = "${source_dir}\cmake\modules\MacrosAutotools.cmake"
    Get-Content $patched_file | Select-String -Pattern "_LIBRARY_REVISION" -NotMatch | Out-File "${patched_file}_new" -Encoding ascii
    Move-Item -Path "${patched_file}_new" -Destination $patched_file -Force

    $build_dir = "${source_dir}\.build"
    do_cmake_build_install ..\cmake $build_dir $opts
    Copy-Item -Path "${build_dir}\bin\dbus-1.pdb" -Destination "${prefix_dir}\bin"
}

function build_zlib($version) {
    if (Test-Path "${prefix_dir}\bin\zlib.pdb") {
        return
    }

    $url = "https://zlib.net/fossils/zlib-${version}.tar.gz"
    $opts = @()

    $source_dir = (download_and_unpack $url "zlib-${version}.tar.gz")[-1]

    $build_dir = "${source_dir}\.build"
    do_cmake_build_install .. $build_dir $opts
    Copy-Item -Path "${build_dir}\zlib.pdb" -Destination "${prefix_dir}\bin"
}

function build_openssl($version) {
    $lib_suffix = if ($arch -eq "x86") { "" } else { "-x64" }
    if (Test-Path "${prefix_dir}\bin\libssl-1_1${lib_suffix}.pdb") {
        return
    }

    $url = "https://www.openssl.org/source/openssl-${version}.tar.gz"
    $ossl_config = if ($arch -eq "x86") { "VC-WIN32" } else { "VC-WIN64A" }

    $source_dir = (download_and_unpack $url "openssl-${version}.tar.gz")[-1]

    $build_dir = $source_dir
    pushd $build_dir
    vcenv perl Configure "--prefix=${prefix_dir}" $ossl_config
    vcenv nmake
    vcenv nmake install_sw
    popd
}

function build_curl($version) {
    if (Test-Path "${prefix_dir}\bin\libcurl.pdb") {
        return
    }

    $url = "https://curl.haxx.se/download/curl-${version}.tar.gz"
    $opts = @(
        "-DCMAKE_USE_OPENSSL=ON",
        "-DCURL_WINDOWS_SSPI=OFF",
        "-DBUILD_CURL_EXE=OFF",
        "-DBUILD_TESTING=OFF",
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

    $source_dir = (download_and_unpack $url "curl-${version}.tar.gz")[-1]

    $build_dir = "${source_dir}\.build"
    do_cmake_build_install .. $build_dir $opts
    cmake -E remove_directory "${prefix_dir}/lib/cmake/CURL" # until we support it
    Copy-Item -Path "${build_dir}\lib\libcurl.pdb" -Destination "${prefix_dir}\bin"
}

function build_qt($version) {
    if (Test-Path "${prefix_dir}\bin\Qt5Core.pdb") {
        return
    }

    $url = "https://download.qt.io/archive/qt/$($version -replace '\.\d+$','')/${version}/single/qt-everywhere-src-${version}.zip" # tar.xz has some names truncated (e.g. .../double-conversion.h -> .../double-conv)
    $opts = @(
        "-platform", "win32-msvc",
        "-mp",
        # "-ltcg", # C1002 on VS 2019 16.5.4
        "-opensource",
        "-confirm-license",
        "-prefix", $prefix_dir,
        "-release",
        "-force-debug-info",
        "-no-opengl",
        "-dbus",
        "-skip", "connectivity",
        "-skip", "declarative",
        "-skip", "doc",
        "-skip", "gamepad",
        "-skip", "graphicaleffects",
        "-skip", "location",
        "-skip", "multimedia",
        "-skip", "purchasing",
        "-skip", "quickcontrols",
        "-skip", "remoteobjects",
        "-skip", "script",
        "-skip", "sensors",
        "-skip", "serialport",
        "-skip", "speech",
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
        "-nomake", "examples",
        "-nomake", "tests",
        "-nomake", "tools",
        "-I", "${prefix_dir}\include",
        "-L", "${prefix_dir}\lib"
    )

    $source_dir = (download_and_unpack $url "qt-everywhere-src-${version}.zip")[-1]

    # Patch to add our linker flags, mainly /PDBALTPATH
    $patched_file = "${source_dir}\qtbase\mkspecs\win32-msvc\qmake.conf"
    (Get-Content $patched_file) -Replace '(^QMAKE_CXXFLAGS\b.*)', ('$1' + "`nQMAKE_LFLAGS += ${env:LDFLAGS}") | Out-File "${patched_file}_new" -Encoding ascii
    Move-Item -Path "${patched_file}_new" -Destination $patched_file -Force

    $build_dir = "${source_dir}\.build"
    cmake -E remove_directory $build_dir
    $env:PATH = "${prefix_dir}\bin;${build_dir}\qtbase\lib;${env:PATH}"
    md -f $build_dir | Out-Null

    pushd $build_dir
    vcenv cmd /c "..\configure.bat" $opts
    vcenv nmake
    vcenv nmake install
    popd

    # install target doesn't copy PDBs for release DLLs
    Get-Childitem -Path "${build_dir}\qtbase\lib" | % { if ($_ -is [System.IO.DirectoryInfo] -or $_.Name -like "*.pdb") { Copy-Item -Path $_.FullName -Destination "${prefix_dir}\lib" -Filter "*.pdb" -Recurse -Force } }
    Get-Childitem -Path "${build_dir}\qtbase\plugins" | % { if ($_ -is [System.IO.DirectoryInfo] -or $_.Name -like "*.pdb") { Copy-Item -Path $_.FullName -Destination "${prefix_dir}\plugins" -Filter "*.pdb" -Recurse -Force } }
}

function build_transmission() {
    $source_dir = "C:\build"
    cmake -E remove_directory $source_dir
    mkdir -f $source_dir | Out-Null
    pushd $source_dir

    cmd /c git clone --branch $release_branch --depth 1 --recurse-submodules --shallow-submodules $repo_uri . "2>&1"

    $build_dir = "${source_dir}\.build"
    mkdir -f $build_dir | Out-Null
    pushd $build_dir

    $env:PATH = "${prefix_dir}\bin;" + $env:PATH

    $tr_prefix_dir = "${build_dir}\prefix"
    vcenv cmake .. -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=RelWithDebInfo "-DCMAKE_INSTALL_PREFIX=${tr_prefix_dir}" "-DTR_THIRD_PARTY_DIR:PATH=${tr_prefix_dir}" "-DTR_QT_DIR:PATH=${tr_prefix_dir}" $cmake_opts
    vcenv nmake
    vcenv nmake test
    vcenv nmake install/fast

    $dbg_dir = "${build_dir}\dbg"
    mkdir -f $dbg_dir | Out-Null

    $tr_pdb_names = @()

    foreach ($x in @("remote", "create", "edit", "show", "daemon", "qt")) {
        sign "${tr_prefix_dir}\bin\transmission-${x}.exe"
        $tr_pdb_names += "transmission-${x}.pdb"
    }

    $trPdbs = Get-Childitem -Path $build_dir -Filter "*.pdb" -Recurse | ? { $tr_pdb_names -contains $_.Name }
    $trPdbs | % { Copy-Item -Path $_.FullName -Destination $dbg_dir }

    $openssl_lib_suffix = if ($arch -eq "x86") { "" } else { "-x64" }
    foreach ($x in @("libcurl", "libcrypto-1_1${openssl_lib_suffix}", "libssl-1_1${openssl_lib_suffix}", "zlib", "dbus-1", "libexpat")) {
        Copy-Item -Path "${prefix_dir}\bin\${x}.dll" -Destination "${tr_prefix_dir}\bin\"
        sign "${tr_prefix_dir}\bin\${x}.dll"
        Copy-Item -Path "${prefix_dir}\bin\${x}.pdb" -Destination $dbg_dir
    }

    foreach ($x in @("Core", "DBus", "Gui", "Network", "Widgets", "WinExtras")) {
        Copy-Item -Path "${prefix_dir}\bin\Qt5${x}.dll" -Destination "${tr_prefix_dir}\bin\"
        sign "${tr_prefix_dir}\bin\Qt5${x}.dll"
        Copy-Item -Path "${prefix_dir}\bin\Qt5${x}.pdb" -Destination $dbg_dir
    }

    mkdir -f "${tr_prefix_dir}\plugins\platforms" | Out-Null
    Copy-Item -Path "${prefix_dir}\plugins\platforms\qwindows.dll" -Destination "${tr_prefix_dir}\plugins\platforms\"
    sign "${tr_prefix_dir}\plugins\platforms\qwindows.dll"
    Copy-Item -Path "${prefix_dir}\plugins\platforms\qwindows.pdb" -Destination $dbg_dir

    mkdir -f "${tr_prefix_dir}\plugins\styles" | Out-Null
    Copy-Item -Path "${prefix_dir}\plugins\styles\qwindowsvistastyle.dll" -Destination "${tr_prefix_dir}\plugins\styles\"
    sign "${tr_prefix_dir}\plugins\styles\qwindowsvistastyle.dll"
    Copy-Item -Path "${prefix_dir}\plugins\styles\qwindowsvistastyle.pdb" -Destination $dbg_dir

    Copy-Item -Path "${prefix_dir}\translations" -Destination "${tr_prefix_dir}" -Recurse

    vcenv nmake pack-msi

    mkdir -f $dst_dir | Out-Null
    Copy-Item -Path "${build_dir}\dist\msi\transmission-${release_version}-${arch}.msi" -Destination "${dst_dir}\"
    sign /d "Transmission BitTorrent Client" /du "https://transmissionbt.com/" "${dst_dir}\transmission-${release_version}-${arch}.msi"

    pushd $dbg_dir
    7z a "${dst_dir}\transmission-${release_version}-${arch}-pdb.zip" *
    popd

    popd
    popd
}

try {
    # cmake -E remove_directory $temp_dir
    cmake -E make_directory $temp_dir

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    build_expat "2.2.9"
    build_dbus "1.12.16"
    build_zlib "1.2.11"
    build_openssl "1.1.1g"
    build_curl "7.69.1"
    build_qt "5.14.2"

    build_transmission
}
catch {
    Write-Host
    Write-Host -ForegroundColor Red "Error: $_"
    Write-Host -ForegroundColor Red $_.InvocationInfo.PositionMessage
    Write-Host -ForegroundColor Red $_.Exception
    Write-Host -ForegroundColor Red $_.ScriptStackTrace
    exit 1
}
