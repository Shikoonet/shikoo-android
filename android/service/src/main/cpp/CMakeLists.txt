cmake_minimum_required(VERSION 3.22.1)

# The official OpenVPN 3 client (MPL-2.0) on mbedTLS (SHIKOO_PATCHES.md): libovpn3.so with OpenVPN.kt's JNI bridge on
# Android, ShikooNetOvpn3.dll with the Go core's C bridge on Windows (tools/ovpn3-build.sh windows).
project(ovpn3 C CXX)

include(FetchContent)

# The release's sources, checked against these hashes before anything builds.
set(openvpn3_sha ae9849055aabf9ac70885097c14aa7abbe00e80fc7703944fb0f7f0c5bfe425f)
# Patches apply in place, so another patch set gets fresh sources in a folder of its own.
file(MD5 ${CMAKE_CURRENT_SOURCE_DIR}/openvpn3-mbedtls-hostname.patch hostname_patch)
file(MD5 ${CMAKE_CURRENT_SOURCE_DIR}/openvpn3-mbedtls-cbc-padding.patch padding_patch)
if (WIN32)
    # Ours: MSVC refuses an #if inside a log macro's arguments, which GCC and Clang take; dead lines on mbedTLS 3.
    file(MD5 ${CMAKE_CURRENT_SOURCE_DIR}/openvpn3-msvc-log-macro.patch msvc_patch)
    set(msvc_patch_command COMMAND patch -p1 -i ${CMAKE_CURRENT_SOURCE_DIR}/openvpn3-msvc-log-macro.patch)
    # transport/dco.hpp includes the Windows tun headers even with an external tun; this one is constants only (MIT).
    set(tap_windows_dir ${CMAKE_BINARY_DIR}/tap-windows6)
    file(DOWNLOAD https://raw.githubusercontent.com/OpenVPN/tap-windows6/9.27.0/src/tap-windows.h
            ${tap_windows_dir}/tap-windows.h
            EXPECTED_HASH SHA256=0b9ea5e4b4dc2c2764fde3383440af9a11a1ead3f2a4bbec674be40da384d10e)
    # The C runtime goes inside the DLL, so only Windows' own DLLs are needed beside it.
    set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreaded)
endif ()
string(MD5 patched "${openvpn3_sha}${hostname_patch}${padding_patch}${msvc_patch}")
FetchContent_Declare(openvpn3
        URL https://github.com/OpenVPN/openvpn3/archive/refs/tags/release/3.11.8.tar.gz
        URL_HASH SHA256=${openvpn3_sha}
        SOURCE_DIR ${FETCHCONTENT_BASE_DIR}/openvpn3-${patched}
        # Upstream ee481a02, after 3.11.8: mbedTLS 3.6.3 and later refuse a handshake without it.
        PATCH_COMMAND patch -p1 -i ${CMAKE_CURRENT_SOURCE_DIR}/openvpn3-mbedtls-hostname.patch
        # Ours, not upstream: AES-CBC sends empty packets on mbedTLS 3.5 and later without it.
        COMMAND patch -p1 -i ${CMAKE_CURRENT_SOURCE_DIR}/openvpn3-mbedtls-cbc-padding.patch
        ${msvc_patch_command})
FetchContent_Declare(lz4
        URL https://github.com/lz4/lz4/archive/v1.10.0.tar.gz
        URL_HASH SHA256=537512904744b35e232912055ccf8ec66d768639ff3abe5788d90d792ec5f48b)
FetchContent_Declare(mbedtls
        URL https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.7/mbedtls-3.6.7.tar.bz2
        URL_HASH SHA256=a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6)

FetchContent_GetProperties(openvpn3)
if (NOT openvpn3_POPULATED)
    FetchContent_Populate(openvpn3)
endif ()

# OpenVPN 3 calls into the asio fixes it ships beside its sources.
file(GLOB asio_patches ${openvpn3_SOURCE_DIR}/deps/asio/patches/*.patch)
list(SORT asio_patches)
set(asio_patch_command "")
foreach (asio_patch IN LISTS asio_patches)
    list(APPEND asio_patch_command COMMAND patch -p1 -i ${asio_patch})
endforeach ()
list(POP_FRONT asio_patch_command)
FetchContent_Declare(asio
        URL https://github.com/chriskohlhoff/asio/archive/asio-1-24-0.tar.gz
        URL_HASH SHA256=cbcaaba0f66722787b1a7c33afe1befb3a012b5af3ad7da7ff0f6b8c9b7a8a5b
        SOURCE_DIR ${FETCHCONTENT_BASE_DIR}/asio-${patched}
        PATCH_COMMAND ${asio_patch_command})

FetchContent_GetProperties(asio)
if (NOT asio_POPULATED)
    FetchContent_Populate(asio)
endif ()
FetchContent_GetProperties(lz4)
if (NOT lz4_POPULATED)
    FetchContent_Populate(lz4)
endif ()

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(ENABLE_TESTING OFF CACHE BOOL "" FORCE)
set(ENABLE_PROGRAMS OFF CACHE BOOL "" FORCE)
set(MBEDTLS_FATAL_WARNINGS OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(mbedtls)
# 3.6 never calls getrandom() on Android (its check needs __GLIBC__), so it reads /dev/random, which blocks on kernels before 5.6 while entropy is low.
target_compile_definitions(mbedcrypto PRIVATE MBEDTLS_PLATFORM_DEV_RANDOM="/dev/urandom")

if (WIN32)
    # ovpncli.cpp is compiled inside the bridge, as upstream's own test client (test/ovpncli/cli.cpp) does.
    add_library(ovpn3 SHARED
            shikoo_ovpn3_win.cpp
            ${openvpn3_SOURCE_DIR}/openvpn/crypto/data_epoch.cpp
            ${lz4_SOURCE_DIR}/lib/lz4.c)
    set_target_properties(ovpn3 PROPERTIES OUTPUT_NAME ShikooNetOvpn3)
else ()
    add_library(ovpn3 SHARED
            shikoo_ovpn3.cpp
            ${openvpn3_SOURCE_DIR}/client/ovpncli.cpp
            ${openvpn3_SOURCE_DIR}/openvpn/crypto/data_epoch.cpp
            ${lz4_SOURCE_DIR}/lib/lz4.c)
endif ()
target_compile_features(ovpn3 PRIVATE cxx_std_17)
target_compile_definitions(ovpn3 PRIVATE USE_MBEDTLS USE_ASIO ASIO_STANDALONE ASIO_NO_DEPRECATED HAVE_LZ4)
target_include_directories(ovpn3 PRIVATE
        ${openvpn3_SOURCE_DIR}
        ${openvpn3_SOURCE_DIR}/client
        ${asio_SOURCE_DIR}/asio/include
        ${lz4_SOURCE_DIR}/lib)
target_link_libraries(ovpn3 PRIVATE mbedtls mbedx509 mbedcrypto)
if (WIN32)
    # The Go core owns the tunnel (wintun, routes, DNS); OpenVPN 3 only hands packets across.
    target_compile_definitions(ovpn3 PRIVATE OPENVPN_EXTERNAL_TUN_FACTORY _WIN32_WINNT=0x0A00 _CRT_SECURE_NO_WARNINGS
            ASIO_DISABLE_LOCAL_SOCKETS TAP_WIN_COMPONENT_ID=tap0901)
    target_include_directories(ovpn3 PRIVATE ${tap_windows_dir})
    target_compile_options(ovpn3 PRIVATE /bigobj /W3 /wd4200 /wd4146 /Gy /Gw)
    target_link_options(ovpn3 PRIVATE /OPT:REF /OPT:ICF)
    target_link_libraries(ovpn3 PRIVATE ws2_32 iphlpapi)
else ()
    target_compile_options(ovpn3 PRIVATE -Os -fvisibility=hidden -fvisibility-inlines-hidden -ffunction-sections
            -fdata-sections -Wno-sign-compare -Wno-unused-parameter)
    target_link_options(ovpn3 PRIVATE -Wl,--gc-sections -Wl,--exclude-libs,ALL)
    target_link_libraries(ovpn3 PRIVATE log)
endif ()
