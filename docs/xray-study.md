# Xray beside mihomo: the 2026-10-20 study and its review

> **خلاصه برای سم**
> - ۲۰۲۶-۱۰-۲۰ سنجیدیم اکس‌ری چطور کنار میهومو بیاید. راه پذیرفته این بود: اکس‌ری داخل همان فایل هستهٔ برنامه، پشت میهومو.
> - بازبین آن را واقعاً ساخت: هر نسخهٔ برنامه حدود ۶ مگ بزرگ‌تر می‌شود و جای نصب روی دستگاه حدود ۱۷ مگ.
> - رفتار آن روز («خودکار، و اگر نشد با هستهٔ دیگر») دیگر برنامه نیست. از ۲۰۲۶-۱۰-۲۲ کاربر خودش برای هر پروتکل هسته را انتخاب می‌کند. طرح تازه در `docs/multi-core.md` است.

Sources: two saved agent conversations of 2026-10-20, the study (`agent-a491d76b383d3eeab`) and its review
(`agent-a7fee20390dbf244c`). Both read branch `win/w3-all` at `78c010e2`, and the server side read-only. Nothing here
was re-run on 2026-10-22: the numbers are theirs. The review **accepted** the study with five corrections, folded in
below and marked *(review)*.

**Superseded part:** the study designed for Sam's 2026-10-20 pick, "automatic per server, and the other core if it
fails". On 2026-10-22 Sam replaced it with a per-protocol choice by the user. §7 stays only for what it found about
Xray's SOCKS behaviour.

## 1. Version, Go and the 32-bit crash

- **Correction, 2026-10-22:** v26.10.17 was withdrawn: its release and its tag now answer 404 on GitHub's API. The
  release to use is **v26.10.21** (2026-10-21, not a prerelease, `go 1.27` in its `go.mod`). Package «س» built it;
  the lines below are the study's, about v26.10.17.
- Newest release **v26.10.17** (2026-10-17, `prerelease=true`). GitHub's `releases/latest` is v26.3.27 (2026-03-27).
  *(review)* All 16 releases after v26.3.27 are prereleases, not "almost all".
- v26.10.17 says `go 1.27` in `go.mod`; its official binaries report `go1.27.2`. v26.3.27 was built with Go 1.26.1
  (release note line 56, and `go version` on its v7a binary).
- golang/go#77621 (32-bit Android ≤ 10 crash) was closed 2026-03-02, milestone Go1.27, backported in #77880
  (Go1.26.3). *(review)* `a5f474fc` is in go1.27.2 and not in go1.26.1. So Xray's own v26.3.27 binaries crash on
  32-bit boxes; it does not matter when we build Xray ourselves with Go ≥ 1.27.
- There is no official 32-bit Android build, only `linux-arm32-v7a` (`CGO_ENABLED=0`).
- v26.10.17 has no Go module tag (the last is `v1.260327.0`), so `go get` resolves a pseudo-version:
  `v1.260327.1-0.20261017152356-92ccc939aaf4`.

## 2. License

MPL-2.0. No file outside `LICENSE` carries Exhibit B ("Incompatible With Secondary Licenses"), so MPL §3.3 lets it be
combined with GPL-3.0 code in a Larger Work. Xray's files stay MPL, and its license text ships with the app.
*(review)* Embedded third-party files are BSD or MIT. This is a reading, not legal advice.

## 3. How other apps pair two cores

In all of them Xray dials the server; another core, or Xray itself, holds the tunnel.

| App | Holds the tunnel | Source |
|---|---|---|
| v2rayN 7.25.6 (Windows) | sing-box by default, or Xray TUN | `ConfigHandler.cs#L1579-1610`, `CoreManager.cs#L65-104`. *(review)* The core is picked per profile; nothing switches cores automatically. |
| PattN 7.25.6-P34 | Xray TUN, one process | `ConfigHandler.cs#L96` |
| v2rayNG 2.3.11 (Android) | hev-socks5-tunnel (JNI, same process) into Xray's SOCKS; Xray TUN by fd as an option | `TProxyService.kt#L15-102`. It keeps its own app out of the VPN instead of protecting sockets (`CoreVpnService.kt#L266-299`). |
| Happ (closed source) | Android: hev, or Xray TUN; desktop: Xray TUN with an admin service | its release notes |
| Hiddify core v3.2 | sing-box, with Xray in the same binary | *(review)* No SOCKS: `inbounds = nil` and `core.Dial(ctx, instance, dest)` (`outbound/xray.go`), on an old Xray fork (v1.8.21). |

Xray itself has a `tun` inbound since v26.1.13 (Wintun on Windows, an fd on Android).

## 4. Three routes for Shikoonet

| Route | Windows | Android | Days | Risk |
|---|---|---|---|---|
| **الف** two processes: mihomo in front, `xray` beside it on a local SOCKS | a second exe: the helper holds one core with one hash (`hub.rs:51,301-307,348`), or a new process owner outside `lib/core/desktop` | `libxray.so` run as a program; its sockets are not protected | 12–16 | medium to high |
| **ب** Xray linked into the same Go core | the same `ShikooNetCore.exe`; the helper is untouched (its hash is set at build) | one file, one Go runtime; protect is one line | 10.5–14 | medium: module bumps, Go 1.27 |
| **پ** Xray replaces mihomo for some servers, with its own tunnel | Xray TUN; a core change means a tunnel restart | the fd must reach Xray; none of FlClash's providers or our rules exist for it | 20+ | high |

**Chosen: ب.** No new process lifecycle, so `lib/core/desktop` and `ServiceState` keep their ownership.

## 5. Linking Xray into our core (route ب)

- **No module-path collisions.** The forks have their own paths: quic-go (`metacubex` vs `apernet`), utls (`metacubex`
  vs `refraction-networking`), gvisor (`metacubex` vs `gvisor.dev`), wireguard (`metacubex/wireguard-go` vs
  `golang.zx2c4.com/wireguard`). Protobuf package names differ (`mihomo.*` vs `xray.*`). Xray has no `sing`.
  *(review)* The Windows core with Xray reached `main` without a panic at init.
- **Modules that move up:** `x/crypto` 0.33→0.58, `x/net` 0.35→0.61, `x/sys` 0.30→0.49, `protobuf` 1.34.2→1.36.12,
  `miekg/dns` 1.1.63→1.1.73, `klauspost/compress` 1.17.9→1.20.0. *(review)* Also `andybalholm/brotli` 1.1.1→1.2.3,
  `google/go-cmp` 0.6→0.7, `klauspost/cpuid/v2` 2.2.6→2.4.0, `pires/go-proxyproto` 0.8.0→0.15.0, `x/sync`, `x/term`,
  `x/text`, `x/time`, and the `go` line 1.21→1.27.
- *(review)* **`-checklinkname=0` is required on Android**, not "maybe". Without it all four Android links fail with
  `link: github.com/wlynxg/anet: invalid reference to net.zoneCache` (chain: `main/json → infra/conf → finalmask/realm
  → pion/stun → pion/transport/stdnet → anet`). Windows does not need it.
- *(review)* **Raising the `go` line changes mihomo's runtime defaults.** Today's build carries
  `DefaultGODEBUG=…tlsmlkem=0,tlssha1=1,rsa1024min=0,x509negativeserial=1,multipathtcp=0,httpmuxgo121=1…`; the build
  with Xray has none of it, so Go 1.27's defaults apply. It does not break the build, but every mihomo protocol needs a
  re-test.
- *(review)* Built for arm64 and armv7 with go1.27.2; `go vet` clean; 136 core tests passed on Windows (Android cgo and
  Linux tests not run).
- **Protect:** Xray's `internet.RegisterDialerController(func(network, address string, c syscall.RawConn) error)` has the
  signature of mihomo's `dialer.DefaultSocketHook` (`core/lib.go:150`).
- **Windows TUN:** Xray's sockets must bind to the physical interface (`sockopt_windows.go:35-50`). Unproven.
- **DNS:** Xray must resolve server names with real DNS, not the tunnel's fake-ip. Unproven.

## 6. Where Xray's config comes from

- The panel is PasarGuard 5.2.1. Its default UA rule (`^(?:FlClashX?|…)`) sends our app `clash_meta` YAML.
- That YAML has `uuid`, `flow`, `encryption`, `servername`, `client-fingerprint`, `alpn`, `reality-opts` (`public-key`,
  `short-id`), `xhttp-opts` and WireGuard. It lacks `spiderX` and `mldsa65Verify` (dropped on purpose,
  `clash.py:312,616`), and finalmask, fragment and noise.
- The panel also serves `<sub>/xray`: full Xray JSON per host (`ConfigFormat.xray`; `manual_sub_request.xray` defaults
  to true in the source). The platform already calls `<sub>/links` (`provision.ts:450-460`). Whether the live panels
  have it on is **unverified**: no real link was opened.
- *(review)* Pairing two formats has traps: `clash_meta` drops hosts that `/xray` keeps (kcp, non-VLESS
  xhttp/splithttp, quic with a header; `clash.py:760-770`), clash renames a duplicate to "(2)", and the default xray
  template carries an unauthenticated SOCKS on `0.0.0.0:10808`, so only outbounds may be taken from it.

## 7. The fallback design (superseded) and what it found

- Each server would have had two members under a mihomo `fallback` group named after it: mihomo's own and a `socks5`
  to Xray on `127.0.0.1` with a random password.
- *(review, measured)* **Xray answers the SOCKS request with success before it dials the server**
  (`proxy/socks/protocol.go:221`). In a smoke test a dead target looked like a dial that succeeded after 612 µs and
  failed about 1 s later on the first read; mihomo's direct dial to it was refused at once. So mihomo's
  `onDialFailed` (`groupbase.go:269-304`; 5 failures in 5000 ms) never sees an Xray failure, and the periodic check
  (300 s, lazy; `parser.go:54,173-174`) is the only detector.
- Still true under a user choice: a dead server behind Xray shows in ping (URL test), not as a dial error.

## 8. Effects

- **APK** *(review, measured, compressed `libclash.so`)*: arm64 20.98 → 26.70 MB (**+5.7**), v7a about 21.46 → 27.75 MB
  (**+6.3**). Xray adds about 8.8 MB; the bumped modules take about 2.8 MB off the rest. Baseline APKs (v1.0.36): arm64
  51,129,639 and v7a 51,479,231 bytes.
- *(review)* **Install size about +17 MB** (64.2 → 80.9 MB): `useLegacyPackaging = true`
  (`android/app/build.gradle.kts:56`) unpacks the `.so`. It matters on small boxes.
- **Windows installer** (38,836,793 bytes, `out-1003`): guess +5–9 MB.
- **Memory:** unmeasured; guess +10–25 MB in-process (PSS was about 116 MB on the Mi Box, 2026-10-07).
- **Diagnostics:** a SOCKS password is a new secret for `diag.dart`'s `_secrets`; Xray's log goes into mihomo's at
  `warning`.
- **Antivirus:** Defender once flagged Xray (XTLS/Xray-core#4928, 2025-07-24). Route ب adds no new exe.
- **Patches:** `core/go.mod` and `go.sum`, one line in an already patched Go file, maybe `build_config.yaml`; new files
  for the glue. **Toolchain:** the Go version in `tools/wsl-toolchain.sh:41`, `shikoo-ci.yml:19`, `shikoo-staging.yml:19`
  and the Windows toolchain.

## 9. Cost

The study: 10.5–14 working days (Go 1.27 in the toolchain 1.5–2, Go glue 2, Dart 3–4, Windows 1, Android 1, devices
2–3, server 0 if `/xray` is on). *(review)* Likely 2–4 more for what the estimate left out: the Go bump and its
re-test (Android 7, the 32-bit box, WireGuard, REALITY), pinging unopened services (`core/shikoo_probe.go` only knows
mihomo's `adapter.ParseProxy`), pairing the two panel formats, the slow failure detection of §7, and Windows TUN
binding.

## 10. Not proven (as of 2026-10-20)

- A real Android run: loading the `.so`, protect, memory on the 2 GB 32-bit box.
- The live panels' settings.
- A build inside WSL (the reviewer built on Windows with the Windows NDK).
- Which servers Xray actually serves better. The only evidence is the old UK REALITY test, 0 of 6 with mihomo against
  2 of 3 with Xray, from before patch 33.
