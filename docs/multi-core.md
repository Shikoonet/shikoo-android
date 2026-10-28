# Several cores side by side

> **خلاصه برای سم**
> - **هر هسته یکی از دو شکل را دارد.** اکس‌ری و سینگ‌باکس «پشت میهومو» می‌نشینند: میهومو مثل دربان، تونل و قاعده‌ها و پینگ و آمار را نگه می‌دارد و فقط وصل شدن به سرور را به آن‌ها می‌سپارد. وایرگارد و اوپن‌وی‌پی‌ان رسمی «صاحب تونل»اند: وقتی روشن‌اند، کل تونل گوشی مال خودشان است.
> - **انتخاب کاربر فقط روی همان دستگاه می‌ماند،** برای هر پروتکل جدا. تا کاربر چیزی انتخاب نکرده، همه‌چیز مثل امروز با میهومو است.
> - **یک اصلاح در جدول نقشه:** سینگ‌باکس اکس‌اچ‌تی‌تی‌پی ندارد. سرورهای ویلسِ اکس‌اچ‌تی‌تی‌پی با سینگ‌باکس وصل نمی‌شوند و با میهومو می‌مانند.
> - **«صاحب تونل» دو ضعف دارد:** سایت‌های ایرانی را فقط از روی نشانی عددی‌شان می‌شناسد، نه از روی نامشان؛ و عوض کردن سرور یعنی یک قطع و وصل کوتاه.

Package «پ» (base), 2026-10-22: the design (phase 1), and what phase 2 built (§6). It replaces the 2026-10-20 decision (Xray
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

- mihomo OpenVPN: tls-auth follows `auth` since the core moved to mihomo v1.19.32 (`docs/extensibility.md:68-69`;
  package ه۵, 2026-10-27). Its per-server limits are others now (`.notes/mc-movpn-2026-10-27/for-doc.md`): a server
  that relies on OpenVPN's defaults needs `auth` (else mihomo's SHA256) and `data-ciphers` (else AES-128-GCM only)
  written out, and there is no `compress lz4` and no `dev tap`.
- sing-box VLESS: v1.14.3 (latest stable, 2026-10-09) has no XHTTP (its transports are http, ws, quic, grpc and
  httpupgrade: `docs/configuration/shared/v2ray-transport.md`) and no `encryption` field (`outbound/vless.md`). **The
  plan's table marks it ✓ for XHTTP; that is wrong.** Package «س» found the same in 1.15-alpha.
- sing-box build tags (package «س»): `openvpn-client` needs `with_openvpn`, and REALITY needs `with_utls`.
- A server the chosen core can't carry, or a core that isn't `ready` in this build, stays on mihomo, for that server
  only. The stored choice is kept.

## 2. Where the choice lives

- A `ShikooCoresNotifier` in `lib/shikoo/engine/settings.dart`, beside `ShikooLookNotifier` (`:52-89`): one
  SharedPreferences key per row, `shikoo.core.<protocol>` = the core's name.
- Device only: never sent to the server, and not backed up (`allowBackup="false"`, `SHIKOO_PATCHES.md` row 10).
- No key means the protocol's default, `shikooDefaultCores` in `cores.dart`: **OpenVPN defaults to the official core**
  (Sam, 2026-10-23), every other protocol to mihomo. Changing a default is one line there; WireGuard's waits for the
  phone test. A default this build does not have ready, or one a server cannot use, means mihomo until it is, with
  nothing for the user to do. A pick of the user's, mihomo included, is stored and always wins over the default.
- A stored core that this build lacks is kept and ignored, so going back a version loses nothing.
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
| "Update through the server" (`_fetch`, `ShikooRoute.server`) | unchanged: the request goes to mihomo's local port, then the selected server, through the core the user picked | **Android: it fails while the owner core carries the server:** the request goes to mihomo's local port, and mihomo's own client of that server is gated (§4, "one identity, one session"), since a second session with the same key or username would take the owner's. Only "direct" works then. **Windows:** a plain request, which the owner's tunnel carries by the server (`ownerAside`). "Direct" is unchanged: with our package out of the VPN, every request of the app goes direct anyway. |
| Changing the core | re-apply the config (`applyProfile(silence: true)`, as `followSubscriptions` does, `account.dart:616-623`); the tunnel stays up and the old engine stops after mihomo holds the new config | disconnect, then connect, as `setMode` does (`controller.dart:1231-1239`) |
| Changing the server | a selector change, as today, even between two engines | a reconnect whenever an owner core is involved: new peer, new tunnel address |
| Lifecycle | lives with the applied config, inside `applyConfig` (Go). It runs while disconnected too, so pings work. | started and stopped by `VpnService` on Android, and by the core in TUN mode on Windows |
| Windows proxy mode | works (mihomo's mixed port) | impossible without a TUN: the servers stay on mihomo (decided, §7), the official OpenVPN default included |

**Sam's behaviour decisions (2026-10-22, through the lead):**
- A core this build lacks shows switched off with «به‌زودی». So the state carries every core that can carry a protocol,
  with `ready`, rather than dropping the ones that are not ready.
- If the new core does not connect, the customer sees only «وصل نشد». There is no automatic way back to the old core.
- **2026-10-23:** if the picked core's engine does not start at all, Go leaves its servers to mihomo, which keeps
  carrying them: the customer sees «وصل نشد», the server shows «با میهومو» (`ShikooServer.core`), and the pick stays.
  For owner cores the same rule is package h2's to build.
- Changing the core while connected uses today's server-switch notices («در حال رفتن به…» / «حالا از … وصلی»), named
  after the core. The state's `coreSwitch` carries it.
- Screens: design «الف», a «هسته‌ها» group in settings with one row per protocol the customer's services hold
  (package «ص», branch `mc/ui`).

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
  and `serves(protocol, mapping)`. A package edits only its own file, but for one line: a ready core whose engine runs
  on some platforms only adds `core: {platforms}` to `shikooReadyOn` in `cores.dart`, and `shikooCoreSpecsProvider`
  shows it not ready elsewhere (`readyHere`).
- `markCores` adds `shikoo-core: <name>` to each proxy mapping that goes to a behind-mihomo core. It runs in
  `lib/providers/actions/setup.dart` `getProfile`, after the script step and before `makeRealProfileTask`
  (`:350-355`). `task.dart` runs in an isolate without the providers, so it can't go there. A new upstream patch, like
  row 21.
- `markCores` marks a server an owner core takes with `shikoo-owner: <core>` instead. Go does not remove it: the
  Windows engine reads it from the applied `config.yaml`, and mihomo's parser ignores the key
  (`TestMihomosParserIgnoresTheOwnerMark`). On Android the engine finds its server through `VpnOptions`; the mark
  costs it nothing.
- The controller stays the only door (`controller.dart:31`). Built in phase 2 (`1644b16a`):
  - `ShikooServer.protocol` from the profile's own mapping, and `ShikooServer.core`, the core really carrying it. For a
    core behind mihomo that is known from the running type: Go replaces a server it handed over, so one it left to
    mihomo keeps its own type.
  - Every service's mappings are read with `getConfig`, as `_mainGroupOf` does for other services, once FlClash's boot
    has finished (`initProvider`): profile files are readable only then.
  - `ShikooState.cores`: one row per protocol the customer's services hold (`other` excluded), each with:
    - `defaultCore`: what the protocol gets with no pick in the current mode; mihomo while that core is not ready, or
      for an owner core in Windows' proxy mode.
    - `chosen`: the user's pick, kept even in proxy mode (mihomo while the pick is not ready); with no pick, the
      `defaultCore` above.
    - `carrier`: what carries it in the current mode, by the rule `markCores` marks with: mihomo for an owner core in
      Windows' proxy mode.
    - `options`: every core that can carry it, with `ready`.
    `shikooTunnelProvider` is that mode, `shikooReadyOnProvider` the platform rule (`shikooReadyOn`).
  - `ShikooState.coreSwitch`: `(protocol, to, stage)` while a core change moves the server in use.
  - `setCore(protocol, core)`: stores the pick, writes a timeline line for diagnostics, and re-applies the config.
    Connected, if the server in use changes core, it shows `moving`, then `done` only when, with the groups read again
    after the apply, that server's `ShikooServer.core` is the new core and it answers (or real traffic passes); else
    `failed`, and the pick stays. The answer alone proves nothing: a server Go left to mihomo answers through mihomo.
  - The reconnect rule, in `selectServer` and `setCore`: while connected, reconnect when the selected server's *tunnel
    key* changes. The key is `mihomo` for mihomo and for behind-mihomo cores, and `<core>/<server>` for an owner core.
    `selectService` needs none: it runs only while off (`serviceInstead` returns null when on or connecting).
  - `ownerAside(read, url)` (route «ج», Windows only): while an owner core carries the server in use, the app's own
    "direct" requests take mihomo's local port, whose DIRECT rules leave by the physical card, since Windows cannot
    keep the app out of that tunnel. It covers `_fetch`'s direct leg and every internet check (`ownerProbes`), where
    that port's own 502 or 407 counts as a failure, not a site's answer. The server leg, asked for or as the fallback,
    is then a plain request: the owner's tunnel holds the app, so it leaves by the server in use, and mihomo's gated
    client stays shut. So a freshly pasted link, which has no DIRECT rule yet, still arrives by the server. Before
    these legs the app asks Go again (two seconds at most): an engine that stopped since connect leaves them to
    mihomo. Null on Android, whose VPN leaves our package out, and whenever mihomo carries the server.
  - Not done: the diagnostics report keeps its keys. The door refuses a whole report over a key it does not know
    (`diag.dart`), so the choice goes into the timeline instead.

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
  `shikooCoresParse(raw)`, which rewrites and then calls `ParseRawConfig`, what `executor.ParseWithBytes` does through
  `config.Parse` (`config/config.go:474-481`); a config that fails to parse stops the cores it started. After
  `hub.ApplyConfig(cfg)` (`:402`), one `shikooCoresCommit()` stops the previous generation, beside
  `closeWireGuard(previous)`. Built in phase 2 (`054f8d25`, `SHIKOO_PATCHES.md` rows 50 and 51).
- Once Android's tunnel is up, `startTUN` runs `shikooCoresAfterTun` (`core/lib.go`, row 24): if a core behind mihomo
  is running, the config Go last applied is applied again, from memory (`shikooLastConfig`), never from `config.yaml`,
  which Dart writes in place and may be writing right then. The group picks are those of that apply (a url-test group
  the user fixed among them), with every select group as it stands now (`liveSelections`). A core opens its server sockets at apply (sing-box's WireGuard and OpenVPN endpoints at once;
  Xray's pre-tunnel sockets likely too), and `DefaultSocketHook` protects nothing until the tun handler exists, so a
  socket opened before the VPN consent stayed unprotected and its packets looped into our own `tun0` (h4's verifier
  on the emulator: `wg-tun0 pkts=9`). mihomo's own clients dial lazily and need none of this. For a core's builder
  nothing changes but one rule: every socket goes through mihomo's dialer (`component/dialer`), so the new
  generation's are protected.
  - Cost: for cores behind mihomo this apply and FlClash's own forced apply after a start (debounced 600 ms,
    `setup.dart`) mean two interruptions in the first second. Neither is cheap to drop: FlClash's runs for every
    profile and serves more than the cores, and on the consent path it did not rebuild the generation after the tunnel
    (h4's verifier), so only this one is sure to.
- An owner core in Go (ه۲) branches inside `handleStartTun` (`core/lib.go:219`): the fd goes to the engine instead of
  sing-tun, and the TunHandler's protect callback stays for mihomo's own sockets. ه۲ designs it.
- `core/shikoo_owner.go` (new; built 2026-10-23): the core method `shikooOwner` answers `{"core": …, "server": …}`, the
  core that owns the tunnel and the server it carries now, both empty when none does. Each owner engine registers from
  its own `init()`: `registerShikooOwner(core string, carrying func() string, ping func(*TestDelayParams) *Delay)`.
  Neither callback assumes the engine runs in this process.
  - `carrying` returns the server the engine carries now, `""` for none. It runs on every dial through a gated server
    and on each question from Dart, so it returns at once: no I/O, and no lock held across I/O or across the engine's
    own start and stop (an atomic value is enough). It may run while `applyConfig` holds `configMu`, so it never takes
    `configMu`. Its synchronisation is the engine's.
  - `ping` answers a delay test of that server from the engine's own session, on a goroutine of its own, within the
    test's timeout. **It is required in practice:** with nil, mihomo answers, the gate below makes that a failure, so
    the server in use shows dead and every `setCore` to the owner core ends `failed`.
  - When `carrying` first returns a server, the engine calls `shikooOwnerTakes(server)` (below).
  - The app asks after the tunnel is up and again before its own requests take an owner's road
    (`ownerCarryingProvider`). Dart caps the wait at two seconds (`ownerAnswerLimit`), since the desktop RPC restarts
    its own timer whenever the core answers anything else, up to about six seconds. No answer reads as none. The
    answer counts for the server in use only: an owner engine that never started leaves that server shown on mihomo,
    and a core switch to it reads failed (Sam, 2026-10-23). Dart reaches it through `CoreMethod.shikooOwner`
    (`SHIKOO_PATCHES.md` row 54).
  - **One identity, one session:** `shikooCoresParse` puts `shikooOwnerGate` on every proxy marked `shikoo-owner`. While
    an owner carries that server, mihomo's own client of it refuses to dial or listen, so mihomo opens no new session
    with the same key or username: not for FlClash's `checkIp`, not for "update through the server" through mihomo's
    port (it fails on Android; Windows sends a plain request instead, see `ownerAside`), not for its own delay test.
    Package ه۲ saw such a session cut the owner's own connection for about 40 s. Not carried (the engine never
    started, or it is another server), the gate passes everything through, and `rebindWireGuard` reaches the client
    behind it.
  - A session the client opened before the owner took the server (a ping round while off) is not the gate's:
    WireGuard keeps it alive with handshakes and keepalives. So `shikooOwnerTakes` closes that client, and a closed
    client stays dead until the next apply. When the owner lets go (disconnect, or the tunnel stopping by itself), the
    app forces one (`applyProfile(force: true)`; the config is unchanged), so pings while off reach that server again.
    Whether to force it is a flag set for the session (`_ownerRoad`) whenever the server in use is picked for an owner
    core or Go says an owner carries one, and cleared only by that apply: Go's later "none" (an engine that died, or
    one that took the server after the question) cannot undo a client already closed.
  - **Known limits:** `testProxyDelay`, the ping of servers of a service not opened, builds its own client from the
    mapping and has no gate; it reaches the carried server only if another service holds the same key or username. And
    the gate knows a server by its name: two servers under different names with one key or username both pass it. The
    panel sends no such pair today (h2's verifier).
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
| `core/shikoo_cores.go` (new), `core/common.go`, `core/hub.go` | registry, rewrite, commit, stop on shutdown |
| `core/go.mod` (`go` and `godebug` lines), the Go version in `tools/wsl-toolchain.sh:41`, `.github/workflows/shikoo-ci.yml:19`, `shikoo-staging.yml:19` and the Windows toolchain | Go 1.27 (build-engineer) |

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


## 6. What base built in phase 2

1. `cores.dart` and the four stubs (`ready: false`), with `protocolOf`, `coreFor`, `runningCore`, `coreRows`,
   `tunnelKey` and `markCores`.
2. `ShikooCoresNotifier`, loaded in the shell.
3. The controller: protocol and core per server, `ShikooState.cores` and `coreSwitch`, `setCore`, the reconnect rule,
   and WireGuard's ping exception by the profile's protocol (§4).
4. The `setup.dart` line; the Go registry and the `loadConfig` and commit hooks.
5. Go 1.27.3: the `go 1.27` line with `toolchain go1.27.3` and `godebug default=go1.21`, and the version in the WSL and Windows toolchain
   scripts and both Shikoo workflows (`SHIKOO_PATCHES.md` row 52). The `godebug` line keeps the 24 runtime defaults of
   `go 1.21` that Go 1.27 still has, `tlsmlkem=0` included (package «س»'s advice); REALITY does not read that setting, since
   `metacubex/utls` v1.8.8 has the read commented out (`defaults.go:15,21`). `-checklinkname=0` is not in the base: no
   dependency here needs it. The first of h1 (Xray) and h4 (sing-box) to land adds it to `go_ldflags` in
   `build_config.yaml`; the other makes the same one-line change, which git merges cleanly. The Windows script now installs its own Go under
   `D:\dev\windows-toolchain\go`; the shared `D:\dev\android-toolchain` is left alone.
6. Tests: `test/shikoo/cores_test.dart`, `test/shikoo/cores_wiring_test.dart`, `test/shikoo/cores_config_test.dart`
   (FlClash's own `getProfile` marks a ready core's servers), `core/shikoo_cores_test.go` (a replacement under
   another name, the old generation stopped only after `hub.ApplyConfig`, shutdown), and the
   profile-folder fixture in `test/shikoo/core_recover_test.dart` (a test that finishes FlClash's boot now reads profile
   files).

**Not built by base:** any engine, the owner road, the helper, the screens («ص»), the chosen cores as a report key (the
door would refuse the report), and pinging unopened services through another core.

## 7. Decisions on the phase-1 questions (the lead, 2026-10-22)

1. **VLESS:** one choice for all VLESS servers. A server the chosen core cannot carry stays on mihomo, that server only
   (XHTTP on sing-box, for example).
2. Whether a screen says a server fell back to mihomo is the design's call. The state carries the real core of every
   server (`ShikooServer.core`).
3. **Windows proxy mode** with an owner core chosen: the servers stay on mihomo. How that shows is the design's call.
4. The helper's multi-binary form waits for «س»'s result. Not built.
5. **Go 1.27** is in base, with one re-test of every mihomo protocol.
6. Leaving our package out of the VPN on Android, for owner cores only: accepted. Its effect on "update through the
   server" is in §3; the lead tells Sam.

## 8. Not proven, and risks

- Owner cores on Android below 13: the complement of GEOIP IR may be a long route list (guess), and the tunnel address
  and DNS must come from the panel's WireGuard fields.
- Whether sing-box and mihomo fit in one binary («س»).
- Xray answers SOCKS before it dials (`docs/xray-study.md` §7): a dead server behind Xray shows only in ping, not as a
  dial error.
- Behind-mihomo cores start with every config apply, even while disconnected: memory on the 2 GB box is unmeasured.
- Go 1.27 no longer has seven settings the core had under `go 1.21`, so `godebug default=go1.21` cannot keep them:
  `asynctimerchan` (timer channels), `tls10server`, `tls3des`, `tlsrsakex` and `tlsunsafeekm` (old TLS suites and
  key export), `x509keypairleaf` and `gotypesalias`. The base build has 31 GODEBUG keys and the new core 26: the
  24 Go 1.27 still has, with the same values, plus `tracebacklabels` and `x509sslcertoverrideplatform`, new in Go 1.27.
  **They touch only Go's standard `crypto/tls` and its timers.** VLESS+TLS and DoH go through `metacubex/tls` v0.1.8,
  which always leaves RSA key exchange and 3DES out and always offers the ML-KEM curves, whatever GODEBUG says
  (`defaults.go:16-21,52-58`); the verifier saw the same plain-TLS ClientHello (`rsa_kex=[] 3des=[]`) on the base build
  with Go 1.26.10. Whatever in the core still uses the standard `crypto/tls` no longer offers RSA key exchange or
  3DES; which parts those are was not listed.
- Tested with Go 1.27.3 on 2026-10-22 (emulator, local servers): the core's unit tests; HTTP servers through the fake
  panel (ping, connect, switch, a dead server, disconnect); and a real VLESS REALITY handshake and a real VLESS+TLS
  one against a local mihomo v1.19.32, both pinging, both carrying traffic, a switch between them while connected.
  REALITY's ClientHello offered `X25519MLKEM768` in its key share, so ML-KEM stays on. **Not tested:** the panel's
  real servers, WireGuard, the 32-bit box, and Windows.
- The Windows toolchain change was not run: no Windows build with Go 1.27 yet.

## 9. From the packages, not yet verified (از بسته‌ها، هنوز سنجیده نشده)

What the packages report about their own branches, copied here before their verifiers have checked it.

**sing-box (h4, `mc/singbox` at `83fe5f44`; evidence in `.notes/mc-singbox-2026-10-22/`)**
- In process, not a second binary: sing-box 1.14.3 runs inside the Go core, one instance per config apply, behind a
  SOCKS inbound on `127.0.0.1` with a random port and one user and password per server. The previous instance stops at
  the next `shikooCoresCommit`. So the Windows helper needs no second binary for sing-box (§4, decision 4).
- A minimal registry instead of sing-box's `include`: the socks inbound; vless, ssh, block and a `mihomo` outbound;
  the wireguard and openvpn endpoints; two `mihomo` DNS transports. `libclash.so` grows about 15 MB raw, about 5 MB in
  the APK; the spike, which linked all of `include`, grew about 26 MB.
- Build tags: only `with_utls` was added (REALITY and the uTLS fingerprints). The package found that `with_wireguard`
  and `with_openvpn` only enable `include/` files, which this registry does not use; package «س» had said
  `openvpn-client` needs `with_openvpn` (§1). `with_gvisor` was already there.
- No `-checklinkname=0`: android/arm64, android/arm and windows/amd64 linked without it.
- Sockets: every server is dialed through the `mihomo` outbound (mihomo's `dialer.DialContext` and `ListenPacket`), so
  Android's protect and Windows' interface binding apply. Server names resolve with mihomo's resolvers, never the
  tunnel's fake-ip.
- Servers left on mihomo (`singBoxServes`, the Dart `serves`, kept equal by `core/testdata/sing_box_serves.json`): any
  key outside the type's list; VLESS networks other than tcp, ws and grpc (XHTTP and h2 included); VLESS
  `encryption`; a flow other than `xtls-rprx-vision`; an unknown fingerprint; `remote-dns-resolve: true` on OpenVPN, and on WireGuard unless its first `dns` is an address (since 2026-10-28
  sing-box asks that one through the server, by a `udp` DNS server whose `detour` is the endpoint); OpenVPN with
  `dev tap`.
- **Open risk, REALITY:** sing-box 1.14.3, 1.15.0-alpha.12 and `testing` strip X25519MLKEM768 from a REALITY
  ClientHello, and Xray-core v26.9.8 and later reject such a ClientHello, so sing-box cannot reach current Xray REALITY
  servers (SagerNet/sing-box#4520, open since 2026-09-11). Measured: against Xray 26.10.21 sing-box 1.14.3 fails and
  mihomo connects; with the fix `dfd19d10` sing-box connects too. Against Xray 25.4.30 with a target that prefers
  X25519MLKEM768, mihomo fails and sing-box connects.
- OpenVPN: the endpoint connects at start, once per server, and keeps the session while the app is disconnected. Until
  its handshake ends, dials fail with `endpoint is not ready yet`, so a ping or a core switch right after an apply can
  show a false "no answer".
- A dead server shows as a failed ping, not a dial error: sing-box answers SOCKS first, as Xray does.
- Memory (Linux amd64 RSS): 35.2 MB on base and 41.3 MB with sing-box after init, the difference file-backed; a
  running instance adds about 5 MB with 3 servers and 7.5 MB with 30.
- MVS raised mihomo's dependencies (for example `x/net` 0.35→0.57, `x/crypto` 0.33→0.54, `miekg/dns` 1.1.63→1.1.72).
  The core tests pass; mihomo's protocols are not re-tested on real servers.
- Its WireGuard and OpenVPN server names are resolved by DNS, not from mihomo's `hosts:` table (h4's verifier).
- Trying each of 60 WireGuard servers with a separate `Start` raised the apply from 260 to 842 ms (h4's verifier).

**Official WireGuard (h2):** its notes (`D:\dev\shikoo-spike\wgo-logs\for-doc.md`) did not exist on 2026-10-23, so
nothing is copied yet.
