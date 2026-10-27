cmake_minimum_required(VERSION 3.22.1)

# libovpn3.so: the official OpenVPN 3 client (MPL-2.0) on mbedTLS, with OpenVPN.kt's JNI bridge (SHIKOO_PATCHES.md).
project(ovpn3 C CXX)

include(FetchContent)

# The release's sources, checked against these hashes before anything builds.
FetchContent_Declare(openvpn3
        URL https://github.com/OpenVPN/openvpn3/archive/refs/tags/release/3.11.8.tar.gz
        URL_HASH SHA256=ae9849055aabf9ac70885097c14aa7abbe00e80fc7703944fb0f7f0c5bfe425f
        # Upstream ee481a02, after 3.11.8: mbedTLS 3.6.3 and later refuse a handshake without it.
        PATCH_COMMAND patch -p1 -i ${CMAKE_CURRENT_SOURCE_DIR}/openvpn3-mbedtls-hostname.patch
        # Ours, not upstream: AES-CBC sends empty packets on mbedTLS 3.5 and later without it.
        COMMAND patch -p1 -i ${CMAKE_CURRENT_SOURCE_DIR}/openvpn3-mbedtls-cbc-padding.patch)
FetchContent_Declare(lz4
        URL https://github.com/lz4/lz4/archive/v1.8.3.tar.gz
        URL_HASH SHA256=33af5936ac06536805f9745e0b6d61da606a1f8b4cc5c04dd3cbaca3b9b4fc43)
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

add_library(ovpn3 SHARED
        shikoo_ovpn3.cpp
        ${openvpn3_SOURCE_DIR}/client/ovpncli.cpp
        ${openvpn3_SOURCE_DIR}/openvpn/crypto/data_epoch.cpp
        ${lz4_SOURCE_DIR}/lib/lz4.c)
target_compile_features(ovpn3 PRIVATE cxx_std_17)
target_compile_definitions(ovpn3 PRIVATE USE_MBEDTLS USE_ASIO ASIO_STANDALONE ASIO_NO_DEPRECATED HAVE_LZ4)
target_include_directories(ovpn3 PRIVATE
        ${openvpn3_SOURCE_DIR}
        ${openvpn3_SOURCE_DIR}/client
        ${asio_SOURCE_DIR}/asio/include
        ${lz4_SOURCE_DIR}/lib)
target_compile_options(ovpn3 PRIVATE -Os -fvisibility=hidden -fvisibility-inlines-hidden -ffunction-sections -fdata-sections
        -Wno-sign-compare -Wno-unused-parameter)
target_link_options(ovpn3 PRIVATE -Wl,--gc-sections -Wl,--exclude-libs,ALL)
target_link_libraries(ovpn3 PRIVATE mbedtls mbedx509 mbedcrypto log)
