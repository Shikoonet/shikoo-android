#!/usr/bin/env bash
# ShikooNetOvpn3.dll, the official OpenVPN 3 engine the Windows core loads: the CMake file, pins and patches of
# Android's libovpn3.so (android/service/src/main/cpp/CMakeLists.txt), which Gradle builds by itself. Prints its sha256.
#   bash tools/ovpn3-build.sh windows   # Git Bash, with VS's CMake on PATH: libclash/windows/ShikooNetOvpn3.dll
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
[ "${1:-}" = windows ] || { echo "usage: $0 windows"; exit 1; }
build=$repo/build/ovpn3
out=$repo/libclash/windows/ShikooNetOvpn3.dll

# Visual Studio's generator finds MSVC by itself, with no vcvars; --parallel is MSBuild's project count.
cmake -S "$repo/android/service/src/main/cpp" -B "$build" -G "Visual Studio 17 2022" -A x64
cmake --build "$build" --config MinSizeRel --parallel 2
mkdir -p "$(dirname "$out")"
cp "$build/MinSizeRel/ShikooNetOvpn3.dll" "$out"

# The core calls these three; a C runtime DLL would have to ship beside it.
for name in shikoo_ovpn3_run shikoo_ovpn3_halt shikoo_ovpn3_packet; do
  grep -qaF "$name" "$out" || { echo "$out: no export $name"; exit 1; }
done
runtime=$(grep -aoiE '(vcruntime|msvcp)[0-9_]*\.dll|api-ms-win-crt-[a-z0-9-]*\.dll' "$out" | sort -u || true)
[ -z "$runtime" ] || { echo "$out: needs $runtime"; exit 1; }
sha256sum "$out"
