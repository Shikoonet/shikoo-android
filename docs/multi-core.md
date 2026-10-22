# Several cores side by side

> **خلاصه برای سم**
> - **هر هسته یکی از دو شکل را دارد.** اکس‌ری و سینگ‌باکس «پشت میهومو» می‌نشینند: میهومو مثل دربان، تونل و قاعده‌ها و پینگ و آمار را نگه می‌دارد و فقط وصل شدن به سرور را به آن‌ها می‌سپارد. وایرگارد و اوپن‌وی‌پی‌ان رسمی «صاحب تونل»اند: وقتی روشن‌اند، کل تونل گوشی مال خودشان است.
> - **انتخاب کاربر فقط روی همان دستگاه می‌ماند،** برای هر پروتکل جدا. تا کاربر چیزی انتخاب نکرده، همه‌چیز مثل امروز با میهومو است.
> - **یک اصلاح در جدول نقشه:** سینگ‌باکس اکس‌اچ‌تی‌تی‌پی ندارد. سرورهای ویلسِ اکس‌اچ‌تی‌تی‌پی با سینگ‌باکس وصل نمی‌شوند و با میهومو می‌مانند.
> - **«صاحب تونل» دو ضعف دارد:** سایت‌های ایرانی را فقط از روی نشانی عددی‌شان می‌شناسد، نه از روی نامشان؛ و عوض کردن سرور یعنی یک قطع و وصل کوتاه.

Phase 1 of package «پ» (base), 2026-10-22: design only, nothing built or run. It replaces the 2026-10-20 decision (Xray
automatic and invisible, as a fallback; `docs/xray-study.md`) with Sam's 2026-10-22 one: the user picks, per protocol,
one of the cores that can carry it. Line numbers are at `5c6f159f`; mihomo paths are at `chen08209/Clash.Meta@8380d0e7`.
"(guess)" marks a claim without a source.

## 1. Types

**Cores** (`ShikooCore`). Each has one shape:

| Core | Shape | Lives in | Package |
|---|---|---|---|
| `mihomo` | itself | `libclash.so` / `ShikooNetCore.exe`, today | — |
| `xray` | behind mihomo | linked into the same Go core (route ب of `docs/xray-study.md`) | ه۱ |
| `singBox` | behind mihomo | the same Go core, or its own process if «س» finds the modules clash | ه۴ |
| `wireguard` (official, wireguard-go) | owns the tunnel | the Go core, reading the TUN fd itself (guess) | ه۲ |
| `openvpn` (official, OpenVPN 3 core, C++) | owns the tunnel | its own native library; a driver on Windows («س») | ه۳ |

mihomo's own OpenVPN and SSH (ه۵) are mihomo, not a new core.

**Protocols** (`ShikooProtocol`) are the rows a user picks a core for: `vless`, `wireguard`, `openvpn`, `ssh`. Every
other type (vmess, trojan, hysteria, …) is `other` and always mihomo.
- Read from the profile's **source mapping**, the one `mainGroupOf` returns (`controller.dart:482-501`), by its `type`
  lower-cased. mihomo names them `Vless`, `WireGuard`, `OpenVPN`, `Ssh` (`constant/adapters.go`).
- **Not** from `ShikooServer.type` (`controller.dart:76-99`), the running core's `Proxy.type`: once a server is handed
  to Xray, mihomo holds a `Socks5` under that name. For the same reason WireGuard's ping exception
  (`controller.dart:1430-1436`) must read the source protocol.
- VLESS details a core may lack, from the same mapping: `network` (`xhttp`), `encryption` (anything but `none`),
  `reality-opts`, `flow` (`adapter/outbound/vless.go:64-82`).

**Capability.** ✓* means "with a per-server limit" (below the table).

| | vless | wireguard | openvpn | ssh |
|---|---|---|---|---|
| mihomo | ✓ | ✓ | ✓* | ✓ |
| xray | ✓ | ✓ | | |
| singBox | ✓* | ✓ | ✓ | ✓ |
| wireguard | | ✓ | | |
| openvpn | | | ✓ | |

- mihomo OpenVPN: tls-auth is HMAC-SHA1 only in our core (`docs/extensibility.md:68-72`).
- sing-box VLESS: v1.14.3 (latest stable, 2026-10-09) has no XHTTP (its transports are http, ws, quic, grpc and
  httpupgrade: `docs/configuration/shared/v2ray-transport.md`) and no `encryption` field (`outbound/vless.md`). **The
  plan's table marks it ✓ for XHTTP; that is wrong.**
- A server the chosen core can't carry, or a core that isn't `ready` in this build, stays on mihomo, for that server
  only. The stored choice is kept.

## 2. Where the choice lives

- A `ShikooCoresNotifier` in `lib/shikoo/engine/settings.dart`, beside `ShikooLookNotifier` (`:52-89`): one
  SharedPreferences key per row, `shikoo.core.<protocol>` = the core's name.
- Device only: never sent to the server, and not backed up (`allowBackup="false"`, `SHIKOO_PATCHES.md` row 10).
- No key means mihomo. A stored core that this build lacks is kept and ignored, so going back a version loses nothing.
- Loaded in the shell before `runApp`, as the look is (`lib/shikoo/app/main.dart:62`), so the first config apply already
  sees it.

## 3. The two shapes

| | Behind mihomo (xray, singBox) | Owns the tunnel (wireguard, openvpn) |
|---|---|---|
| TUN, DNS and rules | mihomo, unchanged | the engine |
| Our rules: the door and subscriptions (`account.dart:560-613`), Iranian sites | unchanged: they are DIRECT in mihomo, so the engine never sees them | **Android:** our own package is left out of the VPN, which FlClash forbids today (`VpnService.kt:238`, `rejectList - packageName`). The door, subscriptions, pings and mihomo's sockets then go direct. Iranian sites by IP only: GEOIP IR as excluded routes (`excludeRoute` on Android 13+; below that, the complement through `routeAddress`). No GEOSITE, no domain rule. **Windows:** routes for the door and the IR ranges, by IP. |
| Ping | mihomo's URL test through the replacement `socks5`, then the engine, then the server: end to end. Unopened services (`_probeOther`, `testProxyDelay`) stay on mihomo (shortcut). | Before connecting: mihomo's adapter for the same server, or a probe the engine registers. Connected: `trafficPassesProvider` (`controller.dart:711`) uses the app's own IP check, which goes direct once the app is outside the VPN, so it must use the engine's handshake state instead. |
| Speed and total | mihomo's trackers count the `socks5` connections: nothing to do | A Go engine pushes into `statistic.DefaultManager.PushUploaded/PushDownloaded` (`tunnel/statistic/manager.go:70-86`), so `getTraffic` stays as it is. A C++ engine needs its own bridge. |
| Its sockets out of the tunnel | it dials through mihomo's `component/dialer`, which brings Android's protect (`core/lib.go:148-160`), Windows' interface binding and real DNS instead of fake-ip. Xray takes a dialer through `internet.UseAlternativeSystemDialer`; its `RegisterDialerController` has `DefaultSocketHook`'s signature. | Android: by leaving our package out. Windows: by binding to the physical interface. |
| Changing the core | re-apply the config (`applyProfile(silence: true)`, as `followSubscriptions` does, `account.dart:616-623`); the tunnel stays up and the old engine stops after mihomo holds the new config | disconnect, then connect, as `setMode` does (`controller.dart:1231-1239`) |
| Changing the server | a selector change, as today, even between two engines | a reconnect whenever an owner core is involved: new peer, new tunnel address |
| Lifecycle | lives with the applied config, inside `applyConfig` (Go). It runs while disconnected too, so pings work. | started and stopped by `VpnService` on Android, and by the core in TUN mode on Windows |
| Windows proxy mode | works (mihomo's mixed port) | impossible without a TUN: falls back to mihomo (question 3) |

## 4. The seam, layer by layer

**One rule:** the choice travels as data inside what each owner already receives: the config file for mihomo, and
`VpnOptions` for the VPN service. There is no new start or stop path, so `ServiceState` and `lib/core/desktop` keep sole
ownership (`AGENTS.md`). A start from the tile or always-on, without Flutter, goes through `quickSetup` →
`handleSetupConfig` → `applyConfig` on the `config.yaml` already on disk (`core/lib.go:306-330`), so it keeps the
markers; that `VpnOptions` survives the same way is a guess for ه۲ to check.

**Dart** (`lib/shikoo/engine/`; screens see only `ShikooState`, so `test/shikoo/ui_boundary_test.dart` needs no change)
- `cores.dart` (new): the types, `protocolOf(mapping)`, `coreFor(mapping, choices)` and `markCores(rawConfig, choices)`.
- One spec file per new core (new; base creates them as stubs): `core_xray.dart`, `core_sing_box.dart`,
  `core_wireguard.dart`, `core_openvpn.dart`. Each holds one record: `ready` (false until its package lands), its shape,
  and `serves(protocol, mapping)`. A package edits only its own file.
- `markCores` adds `shikoo-core: <name>` to each proxy mapping that goes to a behind-mihomo core. It runs in
  `lib/providers/actions/setup.dart` `getProfile`, after the script step and before `makeRealProfileTask`
  (`:350-355`). `task.dart` runs in an isolate without the providers, so it can't go there. A new upstream patch, like
  row 21.
- The controller stays the only door (`controller.dart:31`):
  - `ShikooServer.protocol` and `ShikooServer.core`, from the source mapping, read with `getConfig` as `_mainGroupOf`
    already does for other services (`:1969-1975`);
  - `ShikooState.cores`, and the action `setCore(protocol, core)`;
  - the reconnect rule in `selectServer` (`:1368`), `selectService` (`:1871`) and `setCore`: while connected, reconnect
    when the selected server's *tunnel key* changes. The key is `mihomo` for mihomo and for behind-mihomo cores, and
    `<core>/<server>` for an owner core.

**Go** (`core/`)
- `core/shikoo_cores.go` (new): `registerShikooCore(name, start)`, called from `init()` in each `core/shikoo_<core>.go`,
  the way `registerMethod` is (`core/method.go:277`, `core/shikoo_probe.go:19-30`). So `hub.go`, `method.go` and
  `constant.go` stay untouched.
  - `start(proxies []map[string]any) (replacements []map[string]any, stop func(), err error)`: the marked mappings in,
    mihomo mappings out, in the same order. The expected replacement is a `socks5` on `127.0.0.1` with a random port and
    password.
  - A core that isn't registered, or that fails, leaves its mappings to mihomo with the marker removed, and logs one
    line. The marker never reaches mihomo's parser.
- `core/common.go` (already patched, row 24): `loadConfig` (`:368-374`) becomes `UnmarshalRawConfig`, then
  `shikooCoresRewrite(raw)`, then `ParseRawConfig`, which is what `executor.ParseWithBytes` does through
  `config.Parse` (`config/config.go:474-481`). After `hub.ApplyConfig(cfg)` (`:402`), one `shikooCoresCommit()` stops
  the previous generation, beside `closeWireGuard(previous)`.
- An owner core in Go (ه۲) branches inside `handleStartTun` (`core/lib.go:219`): the fd goes to the engine instead of
  sing-tun, and the TunHandler's protect callback stays for mihomo's own sockets. ه۲ designs it.
- `go.mod`/`go.sum`: Go 1.27 and the `go 1.27` line come from base (build-engineer); each package adds its own
  requires.

**Android**
- Behind mihomo: nothing.
- Owner (ه۲ builds it, ه۳ reuses it): `VpnOptions` (Kotlin `service/models/VpnOptions.kt:15-26`, Dart
  `lib/models/core.dart:44`, filled at `lib/providers/state/system.dart:214-228`) gains the core and the tunnel's
  address, DNS, MTU and routes. `handleStart` (`VpnService.kt:119-170`) uses them instead of `IPV4_ADDRESS`, `DNS` and
  `MTU` (`:292-300`), leaves our package out (`:238`), and hands the fd to the engine instead of `Core.startTun`. A C++
  engine (OpenVPN 3) configures the builder through its own Kotlin class and its `tun_builder` callbacks (ه۳).
- A separate-process core, only if «س» says sing-box must be one: `lib<name>.so` run as a program
  (`useLegacyPackaging = true`, `android/app/build.gradle.kts:56`), started and stopped by the service, never by
  Flutter. Its sockets also need our package out of the VPN.

**Windows**
- Behind mihomo, linked into the core: nothing. The helper's hash is set at build (`services/helper/build.rs:2-6`).
- Owner, linked into the core (wireguard-go on wintun): nothing in the helper; TUN mode only
  (`lib/shikoo/engine/mode.dart:14-22`).
- A second executable (OpenVPN 3, or sing-box on its own): the helper knows one core. It has one
  `EXPECTED_CORE_SHA256` (`hub.rs:51`), one verified file (`:301-310`), one `MANAGED_CORE` (`:348`), and `StartParams`
  with `deny_unknown_fields` (`:58`). It would need a hash and a slot per binary, a `core` field, and `PROTOCOL_VERSION`
  6 → 7 (`:50`). Built once, and only after «س» says a second binary is needed (question 4).

## 5. Who changes which file

**Shared; only «پ» edits these.** A package that needs a change here asks the lead.

| File | Change |
|---|---|
| `lib/shikoo/engine/cores.dart` (new) | types, `protocolOf`, `coreFor`, `markCores` |
| `lib/shikoo/engine/core_{xray,sing_box,wireguard,openvpn}.dart` (new) | stubs; afterwards each belongs to its package |
| `lib/shikoo/engine/settings.dart` | `ShikooCoresNotifier` |
| `lib/shikoo/engine/controller.dart` | protocol and core per server, `ShikooState.cores`, `setCore`, the reconnect rule, WireGuard's exception by source protocol |
| `lib/shikoo/app/main.dart` | load the choice before `runApp` |
| `lib/shikoo/engine/diag.dart` | the chosen cores in the report (proposed) |
| `lib/providers/actions/setup.dart` (upstream) | the `markCores` call |
| `core/shikoo_cores.go` (new), `core/common.go` | registry, rewrite, commit |
| `core/go.mod` (`go` line), `build_config.yaml` (`-checklinkname=0`), the Go version in `tools/wsl-toolchain.sh:41`, `.github/workflows/shikoo-ci.yml:19`, `shikoo-staging.yml:19` and the Windows toolchain | Go 1.27 (build-engineer) |

**Shared; ه۲ owns them, ه۳ builds on ه۲'s branch:** `VpnOptions` (Kotlin, Dart and its generated file,
`system.dart`), `VpnService.kt` `handleStart`, the `startTun` path (`Core.kt`, `core/lib.go`), and
`trafficPassesProvider` for owner cores.

**New files per package, and nothing else:**

| Package | Files |
|---|---|
| ه۱ xray | `core/shikoo_xray.go` and its test; `core_xray.dart` filled in |
| ه۲ wireguard | `core/shikoo_wg.go` and its test; `core_wireguard.dart`; the owner road above |
| ه۳ openvpn | `core_openvpn.dart`; a Kotlin class under `android/service/`; the native build files («س») |
| ه۴ sing-box | `core/shikoo_singbox.go` and its test, or process files if «س» says so; `core_sing_box.dart` |
| ه۵ mihomo OpenVPN and SSH | tests, and an `.ovpn` converter file if conversion lands in the app |

**Overlaps no split avoids:** `core/go.mod` and `go.sum` (resolve with `go mod tidy`, never by hand),
`SHIKOO_PATCHES.md` rows (keep them all, renumber at integration), and translations (the screens package «ص» owns them;
core packages add none).

## 6. What base builds in phase 2

1. `cores.dart` and the four stubs (`ready: false`), with `protocolOf`, `coreFor` and `markCores`.
2. `ShikooCoresNotifier`, loaded in the shell.
3. The controller: protocol and core per server, `ShikooState.cores`, `setCore`, the reconnect rule, and WireGuard's
   ping exception by source protocol.
4. The `setup.dart` line; the Go registry and the `loadConfig` and commit hooks.
5. The chosen cores in the diagnostics report (proposed).
6. Go 1.27 (build-engineer), with a re-test of every mihomo protocol on phone, TV and Windows: the old `go 1.21` line's
   runtime defaults go away (`docs/xray-study.md` §5), and loop variables become per-iteration.
7. Tests:
   - `test/shikoo/cores_test.dart`: `protocolOf` on panel-shaped mappings (REALITY, XHTTP, WireGuard, OpenVPN, SSH,
     vmess); `coreFor` falling back (core not ready, XHTTP on sing-box, an owner core in Windows proxy mode);
     `markCores` marking only behind-mihomo choices and leaving the config equal to its input when everything is
     mihomo; the choice surviving a reload; and a check that every `ready` Go core has a
     `registerShikooCore("<name>"` in `core/*.go`.
   - The controller: the reconnect rule with a fake owner spec; WireGuard's exception still working when the running
     type is `Socks5`.
   - `core/shikoo_cores_test.go`: a fake registered core replaces the marked proxies; an unregistered one leaves them to
     mihomo; the marker never reaches `ParseRawConfig`; the previous generation stops at commit.
   - `flutter test` and `go test ./...` green in WSL, and a smoke test on phone and TV: with every choice at mihomo,
     connecting, switching servers and pinging behave as today.

**Not built by base:** any engine, the owner road, the helper, the screens («ص»), and pinging unopened services through
another core.

## 7. Open questions

1. **VLESS:** one choice for all VLESS servers, or REALITY and XHTTP apart? With one, sing-box silently leaves XHTTP
   servers on mihomo. (Sam, through the designs of «ط».)
2. Should a screen say when a server fell back to mihomo (core not ready, or unable to carry it)? The state carries it
   either way.
3. **Windows proxy mode** with an owner core chosen: fall back to mihomo (proposed), or use tunnel mode for that
   connection?
4. If «س» finds a second executable is needed (OpenVPN 3 on Windows, or sing-box on its own): does base build the
   helper's multi-binary form before ه۳ and ه۴ start, or the first package that needs it?
5. **Go 1.27:** in base (proposed: one re-test for every package), or inside ه۱?
6. Owner cores take the whole app out of the VPN on Android, against FlClash's deliberate choice to keep it in
   (`VpnService.kt:232,238`), and they change the "traffic passes" check. Acceptable for owner cores only?

## 8. Not proven, and risks

- Nothing here was built or run; every line was read on 2026-10-22.
- Owner cores on Android below 13: the complement of GEOIP IR may be a long route list (guess), and the tunnel address
  and DNS must come from the panel's WireGuard fields.
- Whether sing-box and mihomo fit in one binary («س»).
- Xray answers SOCKS before it dials (`docs/xray-study.md` §7): a dead server behind Xray shows only in ping, not as a
  dial error.
- Behind-mihomo cores start with every config apply, even while disconnected: memory on the 2 GB box is unmeasured.
