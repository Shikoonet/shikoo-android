#!/usr/bin/env bash
# Linux toolchain that builds FlClash for Android, inside WSL Ubuntu 24.04 (x86_64).
#
# Versions are FlClash v0.8.98's own: .github/workflows/build.yaml (Flutter, Go, NDK r28c),
# android/gradle/libs.versions.toml (SDK 36, NDK, CMake 3.22.1) and
# plugins/rust_api/rust/rust-toolchain.toml (Rust). Bump them here when upstream does.
#
# Run inside WSL. Re-runnable: each step skips what is already in place.
#   bash tools/wsl-toolchain.sh              # installs into ~/android-toolchain (ROOT=... to move it)
#   source ~/android-toolchain/env.sh
#   cd ~/src/FlClash && flutter pub get && dart setup.dart android --arch amd64 --env stable
#
# Rust and Go stay in their default homes (~/.rustup, ~/.cargo, ~/go, ~/.cache/go-build), not in ROOT:
# Flutter runs FlClash's Go and Rust build hooks with an allowlisted environment (hooks_runner 1.5.0:
# PATH, HOME, GOPATH, LIBCLANG_PATH, ANDROID_*, proxies ...), so RUSTUP_HOME, CARGO_HOME and GOCACHE
# never reach them; with ROOT homes the hook installed a second 2.4 GB Rust into ~/.rustup.
# Remove: rm -rf ~/android-toolchain ~/.rustup ~/.cargo ~/go ~/.cache/go-build
#         (Go's module cache is read-only: a non-root user needs chmod -R u+w ~/go first;
#          the apt packages unzip, zip, build-essential stay; ~/.android keeps the debug signing key)
#
# Network on Sam's machine (measured 2026-10-02):
# - WSL's NAT reaches nothing: DNS answers, every TCP connect times out.
# - The Windows proxy listens on Windows 127.0.0.1:10808 only, which NAT-mode WSL cannot reach.
# So when there is no direct internet, env.sh starts winproxy-bridge.py: it offers the same proxy
# at 127.0.0.1:10808 inside WSL and carries each connection over WSL interop (a Windows python.exe
# opens it). No Windows setting changes. It listens on 127.0.0.1 only and, once started (setsid nohup),
# stays up until WSL stops or until you run winproxy_stop (defined in env.sh).
# - dl.google.com answers 404 even through the proxy; Google's redirector.gvt1.com serves the same
#   Go, Android repository and Google Maven files.
# - Connections die now and then, for two reasons:
#   1. the proxy's far side cuts them mid-handshake or mid-transfer (the bridge's diagnostics showed
#      the Windows end receiving a clean EOF from the proxy);
#   2. WSL interop sometimes fails to start the Windows python.exe for a new connection
#      ("UtilAcceptVsock: accept4 failed 110" in winproxy-bridge.log, 61 of 63 lines after one day
#      of builds); that connection then closes at once, which a client sees as a cut handshake.
#   So big downloads resume, Gradle gets more retries, and a build that still fails on the network is
#   simply run again. (Untested idea for 2: cap how many python.exe start at the same time.)
set -euo pipefail

ROOT=${ROOT:-$HOME/android-toolchain}
GO_VERSION=1.27.3 # Xray needs 1.27 (docs/multi-core.md); 1.26.4 and older 32-bit runtimes crash on old boxes (golang/go#77621, #79612)
FLUTTER_VERSION=3.47.1
JDK_MAJOR=17
RUST_VERSION=1.95.0
# every target in FlClash's rust-toolchain.toml: rustup adds any missing one the first time cargo runs
# there (measured: a removed target came straight back), so take them now rather than mid-build
RUST_TARGETS=aarch64-linux-android,armv7-linux-androideabi,x86_64-linux-android,aarch64-apple-darwin,x86_64-apple-darwin,aarch64-pc-windows-msvc,x86_64-pc-windows-msvc,aarch64-unknown-linux-gnu,x86_64-unknown-linux-gnu
NDK_VERSION=28.2.13676358 # r28c
GRADLE_VERSION=9.2.1      # android/gradle/wrapper/gradle-wrapper.properties
# cmdline-tools 19.0: from 23.0 on, sdkmanager is a shim that fetches "Android CLI" from dl.google.com
CMDLINE_TOOLS=commandlinetools-linux-13114758_latest.zip
# android-35: a Flutter plugin compiles against it; AGP fetched it itself on the first build
SDK_PACKAGES=("platform-tools" "platforms;android-36" "platforms;android-35" "build-tools;36.0.0" "ndk;$NDK_VERSION" "cmake;3.22.1")
MIRROR=https://redirector.gvt1.com/edgedl
PROXY_PORT=10808
DL=$ROOT/_downloads
SDK=$ROOT/android-sdk

log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
# small index/checksum files; connections here get cut mid-transfer now and then (curl: (18))
get() { curl -fsSL --retry 5 --retry-all-errors --connect-timeout 30 --max-time 300 "$@"; }

mkdir -p "$DL" "$ROOT/bin"
# One run at a time. Children inherit the lock, so even a stray curl from a killed run blocks a new one:
# two curls writing one .part once corrupted a download on this machine.
exec 9>"$ROOT/.install.lock"
flock -n 9 || die "another run holds $ROOT/.install.lock (check: fuser $ROOT/.install.lock)"
START=$SECONDS

# fetch URL FILE SUM [sha256|sha1] — resumable, and a stalled transfer (<10 KB/s for 30 s) resumes.
fetch() {
  local url=$1 out=$DL/$2 want=$3 algo=${4:-sha256} i
  [ -n "$want" ] || die "$2: no official checksum found"
  if [ -s "$out" ] && [ "$("${algo}sum" "$out" | cut -d' ' -f1)" = "$want" ]; then log "cached $2"; return; fi
  rm -f "$out"
  log "download $2"
  local got; got=$("${algo}sum" "$out.part" 2>/dev/null | cut -d' ' -f1 || true) # no .part yet is fine
  if [ "$got" != "$want" ]; then # a complete .part from a cut run needs no request (and would get a 416)
    for i in $(seq 1 40); do
      curl -fL --connect-timeout 30 --speed-limit 10240 --speed-time 30 -sS -C - -o "$out.part" "$url" && break
      log "  $2: attempt $i stopped at $(stat -c %s "$out.part" 2>/dev/null || echo 0) bytes, resuming"
      sleep 5
    done
    got=$("${algo}sum" "$out.part" | cut -d' ' -f1 || true)
  fi
  [ "$got" = "$want" ] || { rm -f "$out.part"; die "$2: $algo mismatch, want $want got $got"; }
  mv "$out.part" "$out"
  log "  $2: $algo ok ($(du -h "$out" | cut -f1))"
}

# unpack ARCHIVE DEST — its single top directory becomes $ROOT/DEST; a cut extraction never looks installed.
unpack() {
  rm -rf "$ROOT/.unpack" "${ROOT:?}/$2"; mkdir -p "$ROOT/.unpack" "$(dirname "$ROOT/$2")"
  case $1 in
    *.zip) unzip -q "$DL/$1" -d "$ROOT/.unpack" ;;
    *) tar --no-same-owner -C "$ROOT/.unpack" -xf "$DL/$1" ;; # root keeps the archive's uids otherwise
  esac
  mv "$ROOT/.unpack"/* "$ROOT/$2"
  rmdir "$ROOT/.unpack"
}

# 1. Network and env.sh. Every later step runs with exactly the env.sh a build will use.
WIN_PYTHON=
if curl -fs -o /dev/null --noproxy '*' --connect-timeout 8 --max-time 20 https://github.com; then
  log "network: direct"
else
  WIN_PYTHON=$(command -v python.exe || command -v py.exe || true)
  [ -n "$WIN_PYTHON" ] || die "no direct internet, and no Windows python.exe for winproxy-bridge.py"
  log "network: no direct internet; the Windows proxy through winproxy-bridge.py ($WIN_PYTHON)"
  cat >"$ROOT/bin/winproxy-bridge.py" <<'PY'
#!/usr/bin/env python3
"""Offer the Windows-loopback proxy at 127.0.0.1:PORT inside WSL.

NAT-mode WSL cannot reach Windows 127.0.0.1, so each accepted connection is
carried over WSL interop instead of IP: a Windows python.exe opens the TCP
connection on the Windows side and relays it through its stdin and stdout.
"""
import os
import socket
import socketserver
import subprocess
import threading

PORT = int(os.environ.get("BRIDGE_PORT", "10808"))
WIN_PYTHON = os.environ["WIN_PYTHON"]
WINDOWS_SIDE = r"""
import msvcrt, os, socket, sys, threading
msvcrt.setmode(0, os.O_BINARY)
msvcrt.setmode(1, os.O_BINARY)
s = socket.create_connection(("127.0.0.1", int(sys.argv[1])))
def up():
    try:
        while d := os.read(0, 65536):
            s.sendall(d)
        s.shutdown(socket.SHUT_WR)
    except OSError:
        pass
threading.Thread(target=up, daemon=True).start()
try:
    while d := s.recv(65536):
        v = memoryview(d)
        while v:
            v = v[os.write(1, v):]
except OSError:
    pass
"""


def write_all(fd, data):
    view = memoryview(data)
    while view:
        view = view[os.write(fd, view):]


class Relay(socketserver.BaseRequestHandler):
    def handle(self):
        conn = self.request
        proc = subprocess.Popen(
            [WIN_PYTHON, "-c", WINDOWS_SIDE, str(PORT)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0,
            cwd=os.path.dirname(WIN_PYTHON),  # a Windows directory, not a \\wsl.localhost path
        )

        def upstream():
            try:
                while data := conn.recv(65536):
                    write_all(proc.stdin.fileno(), data)
            except OSError:
                pass
            finally:
                try:
                    proc.stdin.close()
                except OSError:
                    pass

        threading.Thread(target=upstream, daemon=True).start()
        try:
            while data := os.read(proc.stdout.fileno(), 65536):
                conn.sendall(data)
        except OSError:
            pass
        finally:
            # shutdown, not just close: close() does not wake the upstream thread's recv(), and while
            # that recv holds the socket the client never gets its FIN (apt-get update hung on this)
            try:
                conn.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            conn.close()
            proc.kill()
            proc.wait()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    with Server(("127.0.0.1", PORT), Relay) as server:
        print(f"bridge: WSL 127.0.0.1:{PORT} -> Windows 127.0.0.1:{PORT} via {WIN_PYTHON}", flush=True)
        server.serve_forever()
PY
fi

cat >"$ROOT/env.sh" <<EOF
# FlClash Android toolchain, written by tools/wsl-toolchain.sh. Use: source $ROOT/env.sh
export JAVA_HOME=$ROOT/jdk ANDROID_HOME=$SDK ANDROID_SDK_ROOT=$SDK ANDROID_NDK_HOME=$SDK/ndk/$NDK_VERSION
export GRADLE_USER_HOME=$ROOT/gradle-home PUB_CACHE=$ROOT/pub-cache # Rust and Go: default homes, see the script
export SDK_TEST_BASE_URL=$MIRROR/android/repository/ # sdkmanager reads its repository from here
# $ROOT/bin holds clang -> the NDK's clang, the one PATH entry the Rust hook's bindgen can find (see step 7)
export PATH=$ROOT/bin:$ROOT/go/bin:$ROOT/flutter/bin:$ROOT/pub-cache/bin:\$HOME/.cargo/bin:$ROOT/jdk/bin:$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:\$PATH
EOF
if [ -n "$WIN_PYTHON" ]; then
  cat >>"$ROOT/env.sh" <<EOF
# No direct internet in this WSL: the Windows proxy, carried over interop by winproxy-bridge.py.
export WIN_PYTHON=$WIN_PYTHON
if ! ss -Hltn 'sport = :$PROXY_PORT' | grep -q .; then
  # 9>&-: never let the long-lived bridge inherit wsl-toolchain.sh's install lock
  (cd / && setsid nohup python3 $ROOT/bin/winproxy-bridge.py >>$ROOT/winproxy-bridge.log 2>&1 </dev/null 9>&- &)
  for _ in 1 2 3 4 5 6 7 8 9 10; do ss -Hltn 'sport = :$PROXY_PORT' | grep -q . && break; sleep 0.5; done
fi
# the bridge outlives this shell (until WSL stops); to stop it by hand:
winproxy_stop() { pkill -f '[w]inproxy-bridge.py'; }
export http_proxy=http://127.0.0.1:$PROXY_PORT https_proxy=http://127.0.0.1:$PROXY_PORT
export HTTP_PROXY=\$http_proxy HTTPS_PROXY=\$https_proxy no_proxy=localhost,127.0.0.1,::1 NO_PROXY=localhost,127.0.0.1,::1
EOF
fi
# shellcheck source=/dev/null
source "$ROOT/env.sh"
[ -z "$WIN_PYTHON" ] || get -o /dev/null https://github.com || die "the proxy bridge does not reach github.com; see $ROOT/winproxy-bridge.log"

# 2. System packages: unzip/zip for Flutter and the SDK, a host C compiler for Rust build scripts
missing=()
for p in unzip zip build-essential; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
if [ ${#missing[@]} -gt 0 ]; then
  log "apt: ${missing[*]}"
  SUDO=; [ "$(id -u)" = 0 ] || SUDO=sudo
  $SUDO env http_proxy="${http_proxy:-}" https_proxy="${https_proxy:-}" DEBIAN_FRONTEND=noninteractive apt-get update -qq
  $SUDO env http_proxy="${http_proxy:-}" https_proxy="${https_proxy:-}" DEBIAN_FRONTEND=noninteractive \
    apt-get install -y -qq --no-install-recommends "${missing[@]}"
fi

# 3. Go, checked against go.dev
if [ "$("$ROOT/go/bin/go" env GOVERSION 2>/dev/null)" != "go$GO_VERSION" ]; then # ours, not a go on PATH
  f=go$GO_VERSION.linux-amd64.tar.gz
  sum=$(get 'https://go.dev/dl/?mode=json&include=all' | python3 -c "import sys,json
print(next(x['sha256'] for r in json.load(sys.stdin) for x in r['files'] if x['filename']=='$f'))")
  fetch "$MIRROR/go/$f" "$f" "$sum"
  unpack "$f" go
fi
log "go: $(go version)"

# 4. JDK 17 (Microsoft build, newest 17.x), checked against Microsoft's sha256 file
# test our own java: a system java on PATH would skip the install and leave JAVA_HOME=$ROOT/jdk empty
if ! "$ROOT/jdk/bin/java" -version >/dev/null 2>&1; then
  f=microsoft-jdk-$JDK_MAJOR-linux-x64.tar.gz
  sum=$(get "https://aka.ms/download-jdk/$f.sha256sum.txt" | cut -d' ' -f1)
  fetch "https://aka.ms/download-jdk/$f" "$f" "$sum"
  unpack "$f" jdk
fi
log "java: $("$ROOT/jdk/bin/java" -version 2>&1 | head -1)"

# 5. Flutter, checked against Flutter's release index
if [ ! -x "$ROOT/flutter/bin/flutter" ]; then
  f=flutter_linux_$FLUTTER_VERSION-stable.tar.xz
  sum=$(get https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json |
    python3 -c "import sys,json
print(next(r['sha256'] for r in json.load(sys.stdin)['releases'] if r['archive'].endswith('/$f')))")
  fetch "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/$f" "$f" "$sum"
  unpack "$f" flutter
fi
flutter --disable-analytics >/dev/null 2>&1 || true # cosmetic: no telemetry, no spinners in logs
flutter config --no-cli-animations >/dev/null 2>&1 || true
flutter precache --android
log "flutter: $(flutter --version | head -1)"

# 6. Android SDK: cmdline-tools (sha1 from Google's repository index), then packages through sdkmanager
if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
  # in the index the <checksum type="sha1"> line sits right above the archive's <url> line
  sum=$(get "$MIRROR/android/repository/repository2-3.xml" | grep -B1 "<url>$CMDLINE_TOOLS</url>" |
    sed -n 's/.*<checksum[^>]*>\([0-9a-f]\{40\}\)<.*/\1/p' || true) # not found: fetch stops with a message
  fetch "$MIRROR/android/repository/$CMDLINE_TOOLS" "$CMDLINE_TOOLS" "$sum" sha1
  unpack "$CMDLINE_TOOLS" android-sdk/cmdline-tools/latest
fi
SDK_PROXY=() # Java ignores http_proxy; sdkmanager takes the proxy as flags
[ -z "$WIN_PYTHON" ] || SDK_PROXY=(--proxy=http --proxy_host=127.0.0.1 --proxy_port=$PROXY_PORT)
yes | sdkmanager "${SDK_PROXY[@]}" --licenses >/dev/null 2>&1 || true
# sdkmanager has no stall timeout (once it sat 17 min at 78%), and a cut download shows only as a
# warning. So: one package per call, killed after 180 s without output, and a warning is a failure.
sdk_install() {
  local out=$ROOT/.sdkmanager.out i pid last still rc
  for i in 1 2 3 4 5 6; do
    sdkmanager "${SDK_PROXY[@]}" --install "$1" >"$out" 2>&1 &
    pid=$! last=-1 still=0
    while kill -0 "$pid" 2>/dev/null; do
      sleep 5
      sz=$(stat -c %s "$out")
      if [ "$sz" = "$last" ]; then still=$((still + 5)); else still=0 last=$sz; fi
      if [ "$still" -ge 180 ]; then log "  $1: silent for 180 s, killing"; pkill -P "$pid" || true; kill "$pid" || true; break; fi
    done
    rc=0; wait "$pid" || rc=$?
    if [ "$still" -lt 180 ] && [ "$rc" = 0 ] && ! grep -qE 'Warning: An error|Error:|Failed to' "$out"; then return 0; fi
    log "  $1: attempt $i failed (rc=$rc): $(tr '\r' '\n' <"$out" | grep -E 'Warning|Error|Failed' | tail -1)"
    sleep 5
  done
  die "$1: sdkmanager gave up after 6 attempts"
}
for p in "${SDK_PACKAGES[@]}"; do
  [ -f "$SDK/${p//;//}/package.xml" ] && continue
  log "sdk: $p"
  sdk_install "$p"
done

# 7. Rust: rustup (sha256 from rust-lang.org) in its default homes, and the pinned toolchain
if [ ! -x "$HOME/.cargo/bin/rustup" ]; then
  url=https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init
  fetch "$url" rustup-init "$(get "$url.sha256" | cut -d' ' -f1)"
  chmod +x "$DL/rustup-init" # run it under this exact name: rustup picks its role from argv[0]
  "$DL/rustup-init" -y -q --no-modify-path --profile minimal --default-toolchain none
fi
rustup toolchain install "$RUST_VERSION" --profile minimal --target "$RUST_TARGETS"
rustup default "$RUST_VERSION" >/dev/null
log "rust: $(rustc --version), targets: $(rustup target list --installed | tr '\n' ' ')"
# rquickjs-sys runs bindgen with the NDK's libclang, which resolves its own resource dir to a relative
# "lib/clang/19" and so misses stdbool.h ("fatal error: 'stdbool.h' file not found"). bindgen then asks a
# clang found on PATH (CLANG_PATH does not reach the hook) for the include dirs; give it the NDK's own clang.
# (FlClash's CI most likely gets this from the clang preinstalled on GitHub's Ubuntu runners.)
ln -sfn "$SDK/ndk/$NDK_VERSION/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" "$ROOT/bin/clang"
log "bindgen clang: $(clang --version | head -1)"

# 8. Gradle: google() → the same mirror, and the proxy (Java ignores http_proxy), only for this GRADLE_USER_HOME
mkdir -p "$GRADLE_USER_HOME/init.d"
cat >"$GRADLE_USER_HOME/init.d/google-mirror.gradle" <<'EOF'
// dl.google.com answers 404 on this network; Google serves the same Maven at redirector.gvt1.com.
def mirror = 'https://redirector.gvt1.com/edgedl/android/maven2/'
def swap = { RepositoryHandler repos ->
  repos.withType(MavenArtifactRepository).configureEach { r ->
    def u = r.url.toString()
    if (u.startsWith('https://dl.google.com/dl/android/maven2') || u.startsWith('https://maven.google.com')) r.url = mirror
  }
}
// beforeSettings, not settingsEvaluated: a settings plugins {} block (AGP in FlClash) resolves through
// pluginManagement before settingsEvaluated runs; configureEach also catches repositories added later
beforeSettings { s -> swap(s.pluginManagement.repositories); swap(s.dependencyResolutionManagement.repositories) }
allprojects { swap(buildscript.repositories); swap(repositories) }
// Stock FlClash uploads mapping.txt to Firebase Crashlytics on every release build (placeholder
// google-services.json, project_id "dev"). Skip that without touching FlClash's sources.
allprojects { tasks.matching { it.name.startsWith('uploadCrashlytics') }.configureEach { enabled = false } }
EOF
{
  # the network cuts some connections mid-handshake or mid-transfer; Gradle's default is 3 tries
  printf 'systemProp.org.gradle.internal.network.retry.%s\n' max.attempts=10 initial.backOff=1000
  [ -z "$WIN_PYTHON" ] || printf 'systemProp.%s\n' http.proxyHost=127.0.0.1 http.proxyPort=$PROXY_PORT \
    https.proxyHost=127.0.0.1 https.proxyPort=$PROXY_PORT 'http.nonProxyHosts=localhost|127.0.0.1'
} >"$GRADLE_USER_HOME/gradle.properties"

# 9. The Gradle that FlClash's wrapper asks for, put where the wrapper looks for it. The wrapper neither
# resumes nor checks a download: here it kept a cut 5 MB piece of the 234 MB zip, and every later
# build failed with "zip END header not found".
url=https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-all.zip
# wrapper dir name = MD5 of the distributionUrl in base 36 (Gradle's PathAssembler)
dist=$GRADLE_USER_HOME/wrapper/dists/gradle-$GRADLE_VERSION-all/$(python3 -c "import hashlib,sys
n = int(hashlib.md5(sys.argv[1].encode()).hexdigest(), 16); s = ''
while n: n, r = divmod(n, 36); s = '0123456789abcdefghijklmnopqrstuvwxyz'[r] + s
print(s)" "$url")
if [ ! -f "$dist/gradle-$GRADLE_VERSION-all.zip.ok" ]; then
  fetch "$url" "gradle-$GRADLE_VERSION-all.zip" "$(get "$url.sha256")"
  rm -rf "$dist" && mkdir -p "$dist"
  unzip -q "$DL/gradle-$GRADLE_VERSION-all.zip" -d "$dist"
  touch "$dist/gradle-$GRADLE_VERSION-all.zip.ok" # the wrapper's "unpacked" marker
fi
log "gradle: $("$dist/gradle-$GRADLE_VERSION/bin/gradle" --version 2>/dev/null | grep -m1 '^Gradle')"

log "sizes: $(du -sh "$ROOT"/{go,jdk,flutter,android-sdk,gradle-home,_downloads} ~/.rustup ~/.cargo 2>/dev/null |
  awk '{sub(".*/", "", $2); printf "%s=%s ", $2, $1}')"
log "done in $(((SECONDS - START) / 60)) min. Use: source $ROOT/env.sh"
