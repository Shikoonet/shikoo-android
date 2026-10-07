# Extensibility: changing the UI/UX and adding protocols

> **خلاصه برای سم**
> - **ظاهر و روند کار اپ را هر وقت بخواهیم می‌توانیم عوض کنیم.** شرطش این است که صفحه‌ها فقط با یک «کنترل‌گر» حرف بزنند.
> - **اوپن‌وی‌پی‌ان را هستهٔ فعلی خودش دارد.** ولی حساب‌های اوپن‌وی‌پی‌انی که فروشگاه امروز می‌فروشد، اول باید از فایل پیکربندی‌شان به شکلی برگردانده شوند که این هسته بفهمد. نسخهٔ هستهٔ داخل فلکلش هم هنوز یک اصلاح تازه را ندارد، پس بعضی از این فایل‌ها تا به‌روز شدن هسته وصل نمی‌شوند.
> - **تونل دی‌ان‌اس شدنی است،** اما یک بخش تازه داخل هسته لازم دارد. ال‌تو‌تی‌پی هم شدنی است، ولی موتور دوم می‌خواهد و سنگین است.

Code reading and web research, 2026-10-02, revised after review; nothing was built or run. § numbers point to `docs/flclash-engine-map.md`; FlClash paths are relative to `D:\dev\shikoo-spike\FlClash` (v0.8.98, `7c61c90`). **(guess)** marks anything without a source. License points are my reading of the license texts, not legal advice.

## 1. The boundary

**`lib/shikoo/` is split into three places, with one import rule:**

| Folder | May import FlClash? | Holds |
|---|---|---|
| `lib/shikoo/app/` (shell) | yes | The entry point (`lib/shikoo/app/main.dart`, built with `-t`; map §1) and `ShikooApp`, with everything map §1 requires: `navigatorKey: globalState.navigatorKey`, `buildManagerStack(…, onConnectivityChanged)`, `bootstrap.attach()`, the `builder` wrapped in `MaterialUiCompatibilityBridge`, `SystemNavigator.setFrameworkHandlesBack(true)`, the `fa` `AppLocalizations` delegate, the settings-flag write and the 20-minute profile timer. Its root widget is a UI page. |
| `lib/shikoo/engine/` (controller) | yes | `ShikooController` and `ShikooState` (below). |
| `lib/shikoo/ui/` (screens, theme) | **no** | Pages and widgets. They read `ShikooState` and call controller actions only; they don't import the shell either. |

- **"Importing FlClash"** means `package:fl_clash/…` outside `package:fl_clash/shikoo/`, **or a relative import that leaves `lib/shikoo/`** (e.g. `'../../providers/…'`). FlClash has no `always_use_package_imports` rule (grep of `lint_options.yaml`: nothing), so the guard test must resolve relative paths too. Model: FlClash's own `ui_layer_singleton_test.dart` (`.agents/architecture.md:252-256`).
- **Focus helpers:** copy `PageFocusScope` and `PageTraversalPolicy` (`lib/widgets/focus.dart:3-49`, depending only on `material_ui`) into `lib/shikoo/ui/`, with a note of origin (same GPL-3.0). Copying beats a lint exception because the rule stays exception-free and an upstream rename can't break our screens; the cost is 49 duplicated lines.

**`ShikooState`:**

| Field | Source |
|---|---|
| `connection`: off / connecting / on / error | `setRunning`, then polling `service.getRunTime()`. "Connecting", with a timeout, covers the consent dialog (§4, Gotchas). |
| `connectedFor` | `runTimeProvider` (§4) |
| `isTV` | `system.isTV` (`lib/common/system.dart:42-54`), set once at start |
| `service`: name, used/total volume, expiry | `currentProfileProvider` → `subscriptionInfo` (§2) |
| `servers`: name, protocol (`type`), group; `selected` | `currentGroupsStateProvider` and `selectedProxyNameProvider` (§3). The spike's two fake rows are filtered out here. |
| `ping`: ms / failed / testing | `delayProvider` and `delayTestPendingProvider` (§3) |
| `speed`, `total` | `trafficsProvider` and `totalTrafficProvider` (§5) |
| `lastError` | a failed start (§4), update (§2) or server change (below) |

**Actions:**
- `connect()` / `disconnect()` (§4).
- `refreshService()` → `updateProfile`; `addService(url, label)` → `Profile.normal(…).update()` + `putProfile`; `removeService()` → `deleteProfile` (§2).
- `selectServer(name)` → `changeProxy` (§3).
- `ping(servers)` → `proxyDelayTest`, one server at a time. This is a precaution only; what caused the spike's false Timeouts is **unproven** (map §3).

**Two notes on the controller:**
- **Server-change errors:** `changeProxy` swallows the failure, rolls the selection back and shows a FlClash toast (`lib/providers/actions/proxies.dart:150-160`). The controller re-reads `selectedProxyNameProvider(group)` after the await; if it isn't the requested name, it sets `lastError`.
- **A future capability, not for today:** "Automatic", which tries connection methods in order until one connects (frame `phone-future-settings`, `design/mockups/phone-states.html:340-380`). It would need one more action plus a state field for the method in use, and the screens already have a slot for it **(guess)**. Falling back to L2TP or IKEv2 would also mean engine switching (§2), which is the costly kind.

**Why a UX change stays inside `lib/shikoo/ui/`:**
- **Any layout is built from the same pieces.** The Happ-style phone, the TV or a new onboarding flow is a function of `ShikooState` plus the actions. The TV's only extra input is `isTV`, which the state carries from day one. Reordering, merging or moving screens adds no new data and no new action.
- **The other two places change for their own reasons.** The controller changes when we add a capability, for example the exit country from `networkDetectionProvider` (§5); that is a feature, not a UX change. The shell changes only when upstream changes its boot.
- **FlClash API changes stay contained.** When FlClash renames something (map risk 3), two files break, not every screen.
- **The protocol is data.** It comes from `Proxy.type` (`lib/models/clash_config.dart:144-152`), so anything the engine already knows shows up without UI work.

## 2. Future protocols

**Android runs one VPN at a time** ([Android VPN guide](https://developer.android.com/develop/connectivity/vpn)). An extra engine either sits **behind** mihomo as a local SOCKS/TCP port, keeping one tunnel (cheap), or **replaces** mihomo's tunnel while it runs, which needs engine switching (costly).

**Trap for every engine chained behind mihomo** (sing-box, an L2TP engine, dnstt): FlClash keeps its own app inside the VPN (`android/service/src/main/java/com/follow/clash/service/VpnService.kt:228,234`) and only protects sockets created through mihomo's dialer hook (`core/lib.go:148-160`). The extra engine's sockets must be protected too, or its traffic loops back into the tunnel.

**Already in today's engine:** `core/Clash.Meta/adapter/parser.go:29-212` accepts ss, ssr, socks5, http, vmess, vless, snell, trojan, hysteria, hysteria2, wireguard, tuic, shadowquic, gost-relay, ssh, mieru, anytls, sudoku, masque, trusttunnel, **openvpn**, tailscale and zerotier (plus direct, dns, reject and rematch).
- A grep of the core for `l2tp|pptp|ipsec|dnstt|iodine|slipstream` finds nothing.
- For anything on that list, only the panel and the subscription change: no app code, and the APK does not grow.
- **Two caveats from our spike (CLAUDE.md):**
  - XHTTP is in the core (`adapter/outbound/vless.go:27,47-48`) but still unproven: its only server connected with no core.
  - The UK Reality server (vision, alpn h2) connected 0 times out of 6 with mihomo, against 2 out of 3 with Xray.

### OpenVPN
- **mihomo has a native Go client.** First stable release with it: [v1.19.25](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.25) (2026-05-16, PR #2785 and #2787 for auth-user-pass and AES-256-GCM). [v1.19.26](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.26) added CBC, CHACHA20-POLY1305 and comp-lzo; the latest stable is v1.19.32 (2026-09-30, [releases](https://github.com/MetaCubeX/mihomo/releases)).
  - FlClash v0.8.98 parses it (`core/Clash.Meta/adapter/parser.go:198-204`) and includes the 2026-08-15 rekey fix ([commit 9b9dc8a, #3109](https://github.com/MetaCubeX/mihomo/commit/9b9dc8a0)). The evidence: the `tran-window` option that fix added (`adapter/outbound/openvpn.go:64`), and `transport/openvpn/rekey_test.go` at the post-fix version.
  - **It lacks two later fixes** (reviewer, by file hashes):
    - `061966e7` (2026-08-27): the client no longer relies on the connection deadline.
    - `6d179a1c` (#3189, 2026-09-08).
    - Without #3189, tls-auth is HMAC-SHA1 only (`transport/openvpn/tlsauth.go:93`: `hmac.New(sha1.New, key)`). Per the PR, a server with `auth SHA256` or `SHA512` fails the handshake ("TLS Error: cannot locate HMAC").
    - So an `.ovpn` with tls-auth and a non-SHA1 `auth` won't connect until FlClash ships a newer core. The wiki below describes current mihomo, not this core.
- **What the shop sells today** (shikoo-platform, read only): OpenVPN "shelf" accounts, delivered as a username and password plus an `.ovpn` file and used with OpenVPN Connect (`apps/bot/src/menu.ts:2040-2074`, `apps/admin-web/src/pages/StockPage.tsx:698-705,814,890`).
  - So for shelf accounts the real job is **converting the `.ovpn` plus username and password into mihomo YAML**. A panel plan can also be WireGuard or OpenVPN (`StockPage.tsx:698`); such a plan could arrive as `type: openvpn` in the subscription instead.
- **What the converter must handle** ([mihomo wiki](https://wiki.metacubex.one/en/config/proxies/openvpn/)): `ca`, `cert`, `key` and `tls-auth`/`tls-crypt(-v2)` as inline content; ciphers AES-128/256-GCM, AES-128/256-CBC and CHACHA20-POLY1305; `auth` MD5 to SHA512; `comp-lzo` yes/no/adaptive; `proto` udp/tcp.
  - **Explicitly unsupported:** `dev tap` ("currently only `tun`").
  - **Missing from the field list,** so treat as unsupported until tested: `compress lz4`/`lz4-v2`, BF-CBC, `fragment`, `pkcs12`, several `remote` lines or `remote-random`, `http-proxy`/`socks-proxy`, a static-key `secret`, `verify-x509-name` and `remote-cert-tls`.
  - Several `remote` lines could become a fallback group, and a proxy line could become a `dialer-proxy` **(guess)**.
  - Where to convert is still open; doing it on the server keeps the app simpler **(guess)**.
  - Whether it works with the shelf's servers is **unverified**. Test one real account first.
- **Fallback: sing-box ≥ 1.14.0,** with OpenVPN client and server endpoints ([changelog](https://sing-box.sagernet.org/changelog/), [client docs](https://sing-box.sagernet.org/configuration/endpoint/openvpn-client/)); latest stable [1.14.2](https://github.com/SagerNet/sing-box/releases/tag/v1.14.2) (2026-09-24), which also covers lz4 and a static key.
  - It is a second engine: about +25 MB per ABI **(guess)**, based on the 25.6 MB `sing-box-1.14.2-android-arm64.tar.gz` in that release.
  - Its license is GPL-3.0-or-later plus "no derivative work may use the name" ([LICENSE](https://github.com/SagerNet/sing-box/blob/testing/LICENSE)). My reading is that this is a GPLv3 §7(e) term, "Declining to grant rights under trademark law for use of some trade names…" ([GPLv3](https://www.gnu.org/licenses/gpl-3.0.en.html)). So it is compatible if our branding doesn't use the name.
- **Not ics-openvpn:** its author says it is "NOT about creating a library" ([README](https://github.com/schwabe/ics-openvpn)). OpenVPN 2 is GPL-2.0-only ([COPYING](https://github.com/OpenVPN/openvpn/blob/master/COPYING)), and that can't be combined with GPL-3.0 code; shipping it as a separate program is a grey area **(guess)**.

### L2TP/IPsec
- **Why it comes up:** the shop buys L2TP accounts in bulk too: "A bulk-bought account (ChatGPT, L2TP, …) is a username and a password" (`shikoo-platform/migrations/0057_shelf_of_accounts.sql:4`). "Bulk-bought" suggests another provider runs those servers, so we couldn't change their protocol **(guess)**; supporting them would mean a full L2TP/IPsec client in the app. Whether they also need an IPsec PSK is **unknown**.
- **The OS no longer helps** ([AOSP `ConfigDialog.java`, android12-release](https://android.googlesource.com/platform/packages/apps/Settings/+/refs/heads/android12-release/src/com/android/settings/vpn2/ConfigDialog.java)): on Android 12, devices with `FEATURE_IPSEC_TUNNELS` and the provider model block *new* PPTP, L2TP/IPsec and IPsec-Xauth profiles and default to IKEv2; devices without that feature lose the IKEv2 types instead. Apps get only IKEv2/IPsec natively, since Android 11 ([Android 11 features](https://developer.android.com/about/versions/11/features)).
- **A user-space client exists: TunnelForge** ([F-Droid](https://f-droid.org/en/packages/io.github.evokelektrique.tunnelforge/), [repo](https://github.com/evokelektrique/tunnel-forge)): GPL-3.0-only (compatible), L2TP with optional IKEv1 IPsec, no PPTP, Android 12+, 29–30 MiB APK.
  - Its engine is C. But per its README, the proxy-only mode we would chain behind mihomo (local HTTP + SOCKS5) also needs its Go/gVisor network stack and Netty (Java).
  - So it is a second engine spanning three runtimes, about 15–25 MB of APK per ABI **(guess)**: its 29–30 MiB single-ABI APK minus Flutter's engine, which is 5.6 MB compressed (13 MB uncompressed) in FlClash's APK (measured), minus its own UI.
- **Risk (guess):** L2TP/IPsec traffic is easy to spot and may be blocked in Iran. Then again, the shelf accounts are sold for use today, so Sam may already know they work.
- **IKEv2 instead:** built into Android 11+ with no APK growth, but it replaces mihomo's tunnel while it is on.

### DNS tunnel
- **No engine has one:** not mihomo (the grep above), not sing-box (its changelog).
- **Iran 2026, from net4people/bbs community reports:**
  - [#586](https://github.com/net4people/bbs/issues/586) covers the 2026-02-28 shutdown (۹ اسفند ۱۴۰۴): "DNS tunnels are the only thing that is so far known to work (at least a little)" ([2026-03-01](https://github.com/net4people/bbs/issues/586#issuecomment-3981010125)); later "the only way is dnstt" ([2026-03-13](https://github.com/net4people/bbs/issues/586#issuecomment-4058502697)).
  - [#626](https://github.com/net4people/bbs/issues/626) (2026-06-04): "usually the max speed was around 100kb/s and it would usually cut the connection off at usually around 1 minute mark". "kb/s" could mean kilobits or kilobytes. That this is about local DNS after outside resolvers were blocked is Lantern's reading; the original is ambiguous.
  - The Lantern corpus, which summarizes these threads, calls its own pages "auto-ingested".
  - **It is an emergency path, not a main protocol.**
- **Candidates:**
  - **dnstt:** Go, CC0-1.0, over DoH, DoT or UDP. The client listens on a local TCP port; the server forwards to SSH or SOCKS ([pkg.go.dev](https://pkg.go.dev/www.bamsoftware.com/git/dnstt.git)). Best fit, because it shares the core's Go toolchain.
  - **slipstream:** C, Apache-2.0, QUIC over DNS, "60% lower header overhead than DNSTT", TCP only, client flag `--tcp-listen-port` ([repo](https://github.com/EndPositive/slipstream), [usage](https://endpositive.github.io/slipstream/usage.html)).
    - Its Rust rewrite [slipstream-rust](https://github.com/Mygod/slipstream-rust) (Apache-2.0) has tests against the C version ([docs/interop.md](https://github.com/Mygod/slipstream-rust/blob/main/docs/interop.md)).
    - But it is **archived** (GitHub API: `archived: true`), and its README opens with a [deprecation notice](https://github.com/Mygod/slipstream-rust/discussions/111).
  - **iodine:** ISC, carries IPv4 through its own tun device ([repo](https://github.com/yarrick/iodine)). That makes it a second VPN, so **not a fit**.
  - **SlipNet:** an Android app with DNSTT, NoizDNS, VayDNS and Slipstream plus SSH. Its [LICENSE](https://github.com/anonvector/SlipNet/blob/main/LICENSE) is AGPL-3.0.
    - My reading is that it is compatible through GPLv3 §13: "permission to link or combine any covered work with a work licensed under version 3 of the GNU Affero General Public License".
    - The AGPL parts keep their clause about offering source to network users.
- **How to chain it:** run the dnstt client inside the Go core on 127.0.0.1:N, and point a `type: ssh` entry (`core/Clash.Meta/adapter/outbound/ssh.go:31-42`) or a `type: socks5` entry at it. Other protocols can ride on top with `dialer-proxy` (`adapter/outbound/base.go:199,212-213`). The protect trap above applies.
- **Cost:** no second engine, but a new piece in FlClash's `core/` wrapper (new SHIKOO_PATCHES entries), about +1–3 MB **(guess)**. Server side: a delegated domain plus dnstt-server **(guess)**.

### Summary

| Protocol | Possible? | 2nd engine | APK growth | Fits GPL-3.0 |
|---|---|---|---|---|
| VLESS/Reality, WireGuard, and the mihomo types above | yes, today (XHTTP and the UK Reality server unproven) | no | 0 | yes |
| OpenVPN through mihomo (shelf `.ovpn` converted) | yes; shelf servers untested; tls-auth SHA1-only until a newer core | no | 0 | yes |
| OpenVPN through sing-box ≥ 1.14 | yes, as a fallback | yes | ~+25 MB/ABI (guess) | yes (§7(e) name term) |
| L2TP/IPsec, TunnelForge-style | yes, but heavy | yes (C + Go + Netty) | ~15–25 MB/ABI (guess) | yes (GPL-3.0-only) |
| IKEv2 (built into Android) | yes, but it replaces mihomo while on | OS | 0 | not applicable |
| DNS tunnel (dnstt inside the core) | yes, emergency grade | no (a core piece) | +1–3 MB (guess) | yes (CC0) |
| PPTP | no: insecure, and not even TunnelForge offers it | — | — | — |

**Measured baseline:** the official FlClash x86_64 APK is 58.7 MB; `libclash.so` is 68.0 MB uncompressed (22.4 MB compressed). Dropping the QR scanner (`libbarhopper_v3.so`) saves about 2.4 MB of APK (2,442,177 bytes compressed; 5.9 MB uncompressed).

## 3. The minimum to build on day one

**Build now:**
1. The shell (`lib/shikoo/app/`) and `lib/shikoo/engine/controller.dart` with `ShikooState`: the only two places that import FlClash.
2. One guard test for the import rule, covering both package and relative imports.
3. The copied focus helpers in `lib/shikoo/ui/`.
4. Servers carry their protocol as data, and every colour, font and radius lives in one place (CLAUDE.md).

**Deliberately not built now:**
- **No `VpnEngine` interface, adapter or plugin registry.** With only one implementation, an interface adds nothing. The seam gets pulled out *inside the controller* on the day a second engine is real. Screens won't notice, because they only see `ShikooState`.
- **No sing-box, L2TP or DNS-tunnel code.** No settings screens per protocol, and no "Automatic" mode yet (§1, a future capability).
- **No screens driven from the server,** and no `.ovpn` handling in the app until we decide where conversion happens.

**Next cheap checks (no code):**
- Convert one real shelf `.ovpn` to mihomo YAML by hand and test it.
- Ask whether the L2TP shelf accounts need a PSK and whether they work from Iran.
- Find out whether a DNS-tunnel domain can be delegated to our server.
