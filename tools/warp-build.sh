#!/usr/bin/env bash
# The WARP bridge binary: patterniha/Aether (AGPL-3.0-only) at a fixed commit, without tor, plus
# tools/warp/aether-proxy-auth.patch. Prints each output's sha256.
# shortcut: Aether has no cargo feature for psiphon, so its launcher (src/psiphon.rs) is built in; it stays idle since
# the core passes no AETHER_PSIPHON* and no psiphon binary ships. Patch the module out if the binary must hold none of it.
#   bash tools/warp-build.sh android   # WSL, after ~/android-toolchain/env.sh: android/app/src/main/jniLibs/<abi>/libshikoowarp.so
#   bash tools/warp-build.sh windows   # Git Bash, after both env.sh files, with VS's CMake on PATH: libclash/windows/ShikooNetWarp.exe
#   bash tools/warp-build.sh test      # the patch's own tests, on this machine
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
aether_url=https://github.com/patterniha/Aether.git
aether_commit=d58f9d568083129ce2c767c85054021eb3ee6a38 # tag v2.4.0
rust=1.95.0
cargo_ndk=4.1.2
# API 24 (Android 7.0): the release builds for 29 only to match PattNG (Aether f425744), not for an API it uses.
android_api=24
# One fixed folder, whichever clone runs this: cargo hashes the absolute path of a path dependency (quiche) into the
# binary. On Windows a short one in the repo: the Visual Studio generator BoringSSL's CMake uses breaks past 260 characters.
work=/tmp/shikoo-warp-${aether_commit:0:12}
[ "${1:-}" = windows ] && work=$repo/build/warp
src=$work/src
export CARGO_TARGET_DIR=$work/target

if [ ! -d "$src/.git" ]; then
  git clone --quiet --filter=blob:none "$aether_url" "$src"
fi
git -C "$src" checkout --quiet --force "$aether_commit"
git -C "$src" clean -fdq
git -C "$src" apply "$repo/tools/warp/aether-proxy-auth.patch"
cd "$src/aether"
# Paths of this machine stay out of the binary, so two builds of the same commit can match.
export RUSTFLAGS="--remap-path-prefix=$src=/aether --remap-path-prefix=${CARGO_HOME:-$HOME/.cargo}=/cargo --remap-path-prefix=$CARGO_TARGET_DIR=/target"
# BoringSSL's build needs CMake and libclang: the Android SDK's in WSL; Windows sets its own below.
if [ "${1:-}" != windows ]; then
  export PATH=$ANDROID_HOME/cmake/3.22.1/bin:$PATH
  export LIBCLANG_PATH=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/lib
fi

case "${1:-}" in
android)
  [ "$(cargo ndk --version | awk '{print $2}')" = "$cargo_ndk" ] || { echo "cargo-ndk $cargo_ndk needed"; exit 1; }
  # boring-sys names err.h's anonymous enum from rustfmt's output; unformatted, armeabi-v7a gets the wrong name
  rustup component list --toolchain "$rust" --installed | grep -q '^rustfmt' || { echo "rustfmt for Rust $rust needed"; exit 1; }
  export ANDROID_NDK_ROOT=$ANDROID_NDK_HOME
  export CFLAGS="-ffile-prefix-map=$CARGO_TARGET_DIR=/target" CXXFLAGS="-ffile-prefix-map=$CARGO_TARGET_DIR=/target"
  for pair in arm64-v8a:aarch64-linux-android armeabi-v7a:armv7-linux-androideabi x86_64:x86_64-linux-android; do
    abi=${pair%%:*} target=${pair#*:}
    export "BORING_BSSL_RUST_CPPLIB_${target//-/_}=static:-bundle=c++"
    cargo "+$rust" ndk -t "$abi" --platform "$android_api" build --release --locked --bin aether
    out=$repo/android/app/src/main/jniLibs/$abi/libshikoowarp.so
    install -D -m 0755 "$CARGO_TARGET_DIR/$target/release/aether" "$out"
    sha256sum "$out"
  done
  ;;
windows)
  # BoringSSL's assembly needs NASM; nasm.us publishes no checksum, so the hash is Scoop's (bucket/nasm.json).
  nasm=$repo/build/warp-nasm/nasm-3.02
  if [ ! -x "$nasm/nasm.exe" ]; then
    mkdir -p "$repo/build/warp-nasm"
    curl -fsSL --speed-limit 10240 --speed-time 30 -o "$repo/build/warp-nasm/nasm.zip" \
      https://www.nasm.us/pub/nasm/releasebuilds/3.02/win64/nasm-3.02-win64.zip
    echo "161d0bfaff53c2f9e9f3e69fd0672323ebabafd1268976a5cec11be92a19aee7  $repo/build/warp-nasm/nasm.zip" | sha256sum -c -
    unzip -q -o "$repo/build/warp-nasm/nasm.zip" -d "$repo/build/warp-nasm"
  fi
  export PATH=$nasm:$PATH
  # bindgen needs libclang.dll; PyPI's libclang wheel carries one, checked against PyPI's own hash.
  clang=$repo/build/warp-libclang
  native=$clang/libclang-18.1.1.data/platlib/clang/native
  if [ ! -f "$native/libclang.dll" ]; then
    mkdir -p "$clang"
    curl -fsSL --speed-limit 10240 --speed-time 30 -o "$clang/libclang.whl" \
      https://files.pythonhosted.org/packages/0b/2d/3f480b1e1d31eb3d6de5e3ef641954e5c67430d5ac93b7fa7e07589576c7/libclang-18.1.1-py2.py3-none-win_amd64.whl
    echo "4dd2d3b82fab35e2bf9ca717d7b63ac990a3519c7e312f19fa8e86dcc712f7fb  $clang/libclang.whl" | sha256sum -c -
    unzip -q -o "$clang/libclang.whl" libclang-18.1.1.data/platlib/clang/native/libclang.dll -d "$clang"
  fi
  export LIBCLANG_PATH=$native
  cargo "+$rust" build --release --locked --bin aether --target x86_64-pc-windows-msvc
  out=$repo/libclash/windows/ShikooNetWarp.exe
  mkdir -p "$(dirname "$out")"
  cp "$CARGO_TARGET_DIR/x86_64-pc-windows-msvc/release/aether.exe" "$out"
  sha256sum "$out"
  ;;
test)
  cargo "+$rust" test --locked --lib auth_tests
  ;;
notices)
  # The license the app shows for the bridge (assets/data/warp-*.txt): AGPL-3.0 for aether, and the crates it links:
  # arm64's list, then the entries only the other targets add.
  cp ../LICENSE "$repo/assets/data/warp-LICENSE.txt"
  out=$repo/assets/data/warp-NOTICES.txt
  for t in aarch64-linux-android armv7-linux-androideabi x86_64-linux-android x86_64-pc-windows-msvc; do
    python3 -I ../third-party-notices.py --target "$t" --manifest-path Cargo.toml --output "$CARGO_TARGET_DIR/notices-$t.txt"
  done
  cp "$CARGO_TARGET_DIR/notices-aarch64-linux-android.txt" "$out"
  rule=$(printf '=%.0s' {1..80})
  for t in armv7-linux-androideabi x86_64-linux-android x86_64-pc-windows-msvc; do
    awk -v have="$out" -v rule="$rule" '
      BEGIN { RS = "\n=+\n"; ORS = ""; while ((getline entry < have) > 0) { split(entry, l, "\n"); seen[l[1]] = 1 } }
      { split($0, l, "\n"); if (!(l[1] in seen)) { seen[l[1]] = 1; print "\n" rule "\n" $0 } }
    ' "$CARGO_TARGET_DIR/notices-$t.txt" >>"$out"
  done
  sha256sum "$repo/assets/data/warp-LICENSE.txt" "$out"
  ;;
*)
  echo "usage: $0 android|windows|test|notices"
  exit 1
  ;;
esac
