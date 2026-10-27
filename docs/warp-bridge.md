# The WARP bridge

> **خلاصه برای سم**
> - **پل وارپ** وقتی سرورهای شیکو از ایران بسته‌اند، راه رسیدن به آن‌هاست: گوشی ← وارپ کلادفلر ← سرور شیکو. ورود و به‌روزرسانی اشتراک هم وقتی راه‌های دیگر جواب ندهند، از همین پل می‌روند. اینترنت رایگان، سایفون و تور نه.
> - برنامهٔ پل (aether، ساخت خودمان، بی تور) جدا از هسته اجرا می‌شود و با بسته شدن اپ یا خاموش شدن پل، با هر چه راه انداخته بسته می‌شود.
> - هر درِ محلی پل رمز تصادفی دارد، تا اپ دیگری روی همان گوشی نتواند از آن بیرون بزند. گواهی دروازهٔ وارپ هم سنجیده می‌شود.
> - فعلاً یک کلید درونی است و پیش‌فرض خاموش؛ صفحه‌اش منتظر انتخاب سام است.

Package «ر۲», 2026-10-27, branch `mc/warp-bridge` from `mc/base` `78ceb30b`. Sam's decision (2026-10-27): aether (patterniha/Aether
v2.4.0, AGPL-3.0-only) only as a bridge to Shikoo's own servers and to the app's own requests. The name «Aether» stays out
of the app (`TRADEMARK.md`), except in the license list. Research and its review: `.notes/mc-aether-2026-10-27/`.

## 1. Shape

- **A process of its own**, never linked into the core: aether is Rust (BoringSSL, tokio), and its crash must not take
  the tunnel down. Android: `libshikoowarp.so` in the app's native library folder (`useLegacyPackaging`, so it is a file
  that can run), found from where `libclash.so` was loaded (`/proc/self/maps`). Windows: `ShikooNetWarp.exe` beside
  `ShikooNetCore.exe` (`windows/CMakeLists.txt`, installed only when the build made it).
- **Started by Go** as the core `warp` of the registry (`core/shikoo_warp.go`, `registerShikooCore`), so it lives with
  the applied config like the cores behind mihomo (`docs/multi-core.md` §4), while disconnected too: sign-in and updates
  need it then. One process serves every config generation: each holds a reference, the last one let go stops it.
  A config apply, the rebuild after Android's tunnel comes up, or a subscription update does not restart it.
- **Ended with all it started.** Linux and Android: its own process group, ended as a group (TERM, KILL after 2 s), and
  `Pdeathsig`, from one Go thread that never ends (Android calls Go from threads that come and go, and the signal follows
  the thread). Windows: a job object that kills on close, so a core that dies takes the bridge with it. A bridge that
  ends by itself is started again on the same port and password (5 s, doubling to a minute).
- **Its identity** (`aether.toml`, `aether-masque.toml`, `*-lastconn.toml`) stays in `<core home>/warp/` (mode 0700),
  the app's private folder. Its output reaches mihomo's log at warn level only, with UUIDs and long keys hidden
  (`redactWarp`): at info level aether prints the device ID.

## 2. Settings Go gives it

`--masque --h2 --tls-verify`, balanced scan, IPv4, quick reconnect, all as `AETHER_*` variables; no proxy variable of
the core's environment reaches it.

- **MASQUE over HTTP/2.** From this PC's direct line HTTP/3 found no gateway (research), and HTTP/2 is one TCP
  connection to 443 (`162.159.198.x`/`162.159.199.x`).
- **`--tls-verify`**: the MASQUE gateway's certificate must match one of the three SPKI pins aether carries
  (`consts.rs` `MASQUE_PINS`). Proven on free WARP from Iran (§6). It does **not** cover the calls to the WARP API
  (registration), which aether makes with no certificate check, nor **`--wg`**: WireGuard's peer key comes from that
  unchecked registration answer (`account.rs` `extract_wg_peer`). So WireGuard stays out of the app.
- Every other app on Android reaches `127.0.0.1`, so **every loopback listener has a random password**, new each time
  the core starts the bridge:
  - aether's socks5 (for mihomo) and its http proxy (for the app's own requests): `tools/warp/aether-proxy-auth.patch`
    adds `AETHER_PROXY_AUTH=user:pass`, RFC 1929 on socks5 and Basic on http. With a password the http proxy carries
    CONNECT only, since a plain request would take the `Proxy-Authorization` header on to the site.
  - **its way out** (`AETHER_UPSTREAM`): a socks5 server inside the core, CONNECT only with its own password, that dials
    with mihomo's `component/dialer`, so Android's protect and Windows' interface binding keep aether's sockets out of
    our tunnel. Not a mihomo listener: those skip the password for loopback clients unless `skip-auth-prefixes` is
    emptied, and their connections would count twice in the app's traffic.

## 3. Wiring

- **Dart marks the config** (`lib/shikoo/engine/warp.dart` `markWarp`, called in `getProfile` after `markCores`): while
  the bridge is on, every server gets `dialer-proxy: shikoo-warp` (a chain keeps its own first hop, which gets it), and
  a socks5 proxy `shikoo-warp` (port 1, `shikoo-core: warp`) joins the list. Go fills in the port and password; a build
  without the bridge leaves port 1, refused, so nothing goes around it. A server marked for a core behind mihomo (Xray,
  sing-box) stays with mihomo while the bridge is on: those engines dial their server themselves and would go around it.
  With no service yet, `getProfile` returns the bridge alone (`warpOnlyProfile`), so the first sign-in can use it.
- **The app's own requests** take the bridge last, through aether's http proxy (`PROXY user:pass@127.0.0.1:port`, read
  from `<core home>/warp/endpoint.json`, written 0600 by Go while the bridge runs):
  - updates (`_fetch`): after the existing ways (direct, then the server while connected) failed without an answer,
    only on the automatic way (`via == null`) and only while the switch is on (`warpLegWanted`). The panel's own answer,
    or a way the customer chose, never goes on to the bridge.
  - the door (`ShikooApi._call`): after every address failed without an answer.
  - Not the app's update downloads (`ShikooApi.download`).
- **The switch** (`shikooWarpProvider`, SharedPreferences `shikoo.warp`): off by default and with no screen; a test build
  turns it on with `--dart-define=SHIKOO_WARP=true`. When it turns on is Sam's choice of design; `warpLegWanted` and
  `markWarp(on:)` take it as one boolean.
- **No leg of its own** on the card yet: while the bridge carries an update the card keeps showing the leg before it.

## 4. Owner cores (official WireGuard, official OpenVPN): not in this round

They own the tunnel and leave our package out of the VPN on Android, so their sockets would not loop, but they dial their
server themselves, not through mihomo. To use the bridge they need their own dial through the bridge's socks5 (UDP
associate for WireGuard, TCP for OpenVPN), with the password from the replacement mapping or `endpoint.json`, and MTU
room for one more tunnel (WARP's is 1280). Not built.

## 5. Build

`tools/warp-build.sh android|windows|test|notices`, Aether at `d58f9d568083129ce2c767c85054021eb3ee6a38` (tag v2.4.0),
Rust 1.95.0, without the `tor` feature (psiphon is a separate program aether would start; we ship none).

- **API 24**, not the release's 29: Aether's `f425744` changed only the `--platform` flag, "the level PattNG builds
  aether, hev-socks5-tunnel and libv2ray for"; no code needs API 29, and the API 24 build links (NDK stubs) and runs on
  Android 7.1.1 (research).
- Windows: MSVC from `D:\dev\windows-toolchain`, NASM 3.02 (hash from Scoop's manifest; nasm.us publishes none) and
  libclang from PyPI's `libclang` 18.1.1 wheel (PyPI's hash), both fetched by the script.
- `notices` writes `assets/data/warp-LICENSE.txt` (aether's AGPL-3.0) and `assets/data/warp-NOTICES.txt` (the crates
  it links on every target), which `registerWarpLicenses` adds to Flutter's license list with the source address.

## 6. Proven, and not

See `.notes/mc-warp-2026-10-27/`. Not proven: the chain to a real Shikoo server (needs a test link), ARM devices, other
Iranian lines and hours, battery, and Cloudflare's response to many registrations from behind one operator NAT.
