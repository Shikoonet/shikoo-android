# Diagnostics and support reports

Draft for the conductor, 2026-10-07. Phone and TV alike. Sam's order: (1) layout and drawing bugs on the customer's
own screen, (2) crashes, (3) which internet the customer is on, (4) why the connection drops, (5) a log that keeps
the evidence and goes with one tap, (6) the device, (7) whether there is internet at all. On-device «درستش کن»
checks come later. The wrong-clock message is built separately on `fix/wrong-clock`; here a report only records the
clock's offset.

## Facts the design rests on

App, `feat/app` at `cbe365e`:

- Logs live only in memory: `logsProvider` is a `FixedList` of 5000 (`lib/providers/app.dart:26-46`,
  `lib/common/constant.dart:119`), fed by `CommonPrint.log` (`lib/common/print.dart:28-37`). A crash loses them.
  `CommonPrint.log` calls `debugPrint` first and reaches `logsProvider` only once `globalState.isAttach`
  (`print.dart:30-31`), so anything before the first frame, such as `init failed` (`lib/shikoo/app/main.dart:48`),
  never gets there.
- Core logs reach Dart only when `openLogs` is on (`lib/manager/core_manager.dart:51-60`; default false,
  `lib/models/config.dart:76`), at the core's `log-level` (default `error`, `lib/models/clash_config.dart:533`;
  filter in `core/hub.go:564-600`). mihomo logs dial failures at warning, with the proxy name and the destination
  (`core/Clash.Meta/tunnel/tunnel.go:630,632`). A core error-level line pops FlClash's English toast
  (`core_manager.dart:82-89`).
- Links reach logs here: `lib/common/http.dart:25` logs every URL Dart fetches, subscription tokens included;
  `_hideLinksInLogs` (`lib/shikoo/app/main.dart:60-66`) scrubs only `debugPrint`, so `logsProvider` keeps the full
  link. `dart:io`'s `HttpException` prints `uri = …` inside error text. `[APP] onAppLink: …` (`lib/common/link.dart:48`)
  is not reached: only FlClash's own `Application._initLink` (`lib/application.dart:93`) listens, and Shikoo mounts
  `buildManagerStack` (`application.dart:21-50`) instead.
- Secrets the app holds: the sign-in token in SharedPreferences `shikoo.account` (`account.dart:492-518`), the poll
  secret and the live login code (`account.dart:521-579`), every profile's subscription URL, and the mixed-port
  username and password, 8 and 16 characters from `[A-Za-z0-9]` (`lib/shikoo/app/app.dart:77-78`,
  `lib/common/string.dart:140-148`), so either can be all letters. ShikooApi never logs (`account.dart:20-22`); the
  port credentials go into the proxy string after the log line (`lib/common/http.dart:25,35`), so they are not
  printed today.
- No Shikoo screen shows a link: `PasteLink` reads the clipboard and never shows it (`lib/shikoo/ui/paste.dart:13-14`).
  The only text field is the server search (`lib/shikoo/ui/service_card.dart:1106`).
- Errors are swallowed without a reason: `catch (_)` at `account.dart:534,556,693`, and `_call` turns every Dio
  failure into a bare `ShikooApiFailure` (`account.dart:286-290`), so a failed sign-in start (the TCL «در حال گرفتن
  کد…») leaves nothing behind. `fix/wrong-clock` adds an error kind there. A failed paste is a `ShikooPasteError`
  (`lib/shikoo/engine/paste.dart:69-78`) and a failed refresh the `RefreshFailed` notice (`controller.dart:179-180`).
- Dart errors: `FlutterError.onError` → a warning log (`main.dart:22-29`), zone errors via `runZonedGuarded`
  (`main.dart:18,52-56`); `PlatformDispatcher.onError` is not set.
- Java/Kotlin: no uncaught-exception handler since Crashlytics left; `didCrashOnPreviousExecution` is `false`
  (`android/common/.../GlobalState.kt:37-40`). Kotlin logs go only to logcat, tag `FlClash` (`GlobalState.kt:33-35`).
  The process can start without an Activity (tile, VPN service); the first app code that always runs is
  `FlClashApplication.attachBaseContext` (`android/app/.../FlClashApplication.kt:8-9`).
- A VPN revoke (another VPN app took over) reaches only logcat: `onRevoke` (`VpnService.kt:114`) →
  `notifyVpnRevoked` (`ManagedService.kt:19-21`) → an explicit broadcast to `ServiceBroadcastReceiver`
  (`common/Ext.kt:42-51`) → «VPN permission revoked» (`ServiceBroadcastReceiver.kt:42-44`). Being explicit, the
  broadcast cannot be heard by a receiver of our own.
- Exit reasons: `GlobalState.lastExitInfo()` (`GlobalState.kt:42-57`, API 30+) returns the newest record's reason,
  time and description only; Dart has `getLastExitInfo` and the reason names `AppExitReason`
  (`lib/plugins/app.dart:185`, `lib/common/boot_record.dart:3-37`). `BootGuard` covers only a launch that never
  finished (`lib/common/boot_guard.dart:36-75`).
- Go core: one process (no `android:process` in any manifest), so an unrecovered Go panic kills the UI too. FlClash
  recovers only its own method handlers (`core/method.go:104-123,288-296`, `core/lib.go:305-313`); mihomo's goroutines
  are unprotected. `logError` writes to stderr only with `debugStderr` (`core/common.go:414-419`). A deliberate panic
  exists for testing: `coreController.crash()` (`lib/core/controller.dart:242`) → `core/hub.go:635-637`. Init has the
  home dir: `core/hub.go:41-49`. `core/go.mod:3` says `go 1.21`; the build uses Go 1.26.4, and FlClash's CI runs
  `go vet` (`.github/workflows/build.yaml:119,139`, per the verifier).
- The app's own traffic always goes through the tunnel when connected (`VpnService.kt:228-235` never excludes our
  package); `keepApiDirect` makes the door DIRECT with a mihomo rule (`account.dart:388-402`), so the door sees the
  customer's real address.
- Reusable: `ShikooApi._call` with base failover (`account.dart:264-291`), connectivity events already arriving in
  `_onConnectivityChanged` (`app.dart:132-137`), FlClash battery calls (`lib/plugins/app.dart:154,159`) and
  `openAppSettings` (`:164`), `system.isTV` (`lib/common/system.dart:42`), `ShikooError.vpnRefused/vpnMissing`
  (`controller.dart:25-31,809-819`), `device_info_plus` 13.2.0 (brand, device, model, release, sdk, security patch,
  ABIs, `isLowRamDevice`, physical and available RAM, free disk), widget tests that already set the view size
  (`test/shikoo/phone_home_test.dart:65`, `login_page_test.dart:48`).
- The app door runs on the Iranian box and survives a national cut (this repo's `docs/app-update.md:19-20,117`).

Flutter 3.47.1 (the installed SDK):

- Release builds never report an overflow. `RenderFlex.paint` builds the hints and paints the stripes only inside
  `assert(() {…}())` (`packages/flutter/lib/src/rendering/flex.dart:1420-1452`), and `paintOverflowIndicator` is "only
  called … from within a debug build" (`debug_overflow_indicator.dart:279-282`). `Flex` clips with `Clip.none` by
  default (`flex.dart:430`), so in release an overflowing row paints over its neighbours, which looks like Sam's
  «آیکون‌ها روی هم».
- The release engine names its renderer once per start: `libflutter.so` (arm, arm64, x64 release jars) holds
  "Using the Impeller rendering backend (OpenGLES).", "(Vulkan)." and "(Vulkan with Validation Layers).", and logs it
  as `I/flutter … [IMPORTANT:flutter/shell/platform/android/android_context_gl_impeller.cc(104)] Using the Impeller
  rendering backend (OpenGLES).` (`D:\dev\shikoo-spike\tvdiag-logs\logcat-a-blackhole.log` and nine more emulator
  logs of 2026-10-07). No public Dart or Java API returns the backend. `FlutterEngineFlags` still knows the manifest
  key `ImpellerBackend` (a lever, not used here).
- docs.flutter.dev/perf/impeller: Impeller is the default on API 29+, and a device below that or without Vulkan
  "falls back to the legacy OpenGL renderer". Skia's removal for Android 10+ in 3.44 is in secondary write-ups only.
- Dart's `RegExp` `\w` and `\d` are ASCII only; `\p{L}`, `\p{Nd}` need `unicode: true` (verifier's
  `re_semantics.dart`).

Android (AOSP `frameworks/base` main, read 2026-10-07, unless named):

- `ApplicationExitInfo` (API 30, as `GlobalState.kt:43` gates), reason numbers at `ApplicationExitInfo.java:65-183`:
  `EXIT_SELF` 1, `SIGNALED` 2, `LOW_MEMORY` 3, `CRASH` 4 ("unhandled exception in Java code"), `CRASH_NATIVE` 5,
  `ANR` 6, `EXCESSIVE_RESOURCE_USAGE` 9, `USER_REQUESTED` 10, `OTHER` 13, `FREEZER` 14 among them. `getStatus()` is
  the exit status or signal. `getTraceInputStream()` gives the ANR trace; from API 31 a native crash's tombstone
  (`:828`). A Java crash's stack is not in it. Below API 30 none of this exists (`ActivityManager.java:4529`).
- Operators, no permission annotation on any of these, only `@RequiresFeature` (a TV without telephony may throw, so
  wrap them): `getNetworkOperatorName()` `getNetworkOperator()` `getSimOperatorName()` `getSimOperator()`
  (`TelephonyManager.java:2912,2940,4193,4108`), `createForSubscriptionId` (`:741`), `getActiveModemCount` (`:679`,
  API 30) and `getPhoneCount` (`:667`); `SubscriptionManager.getSubscriptionId(slot)` (`SubscriptionManager.java:2542`,
  API 34), the older `getSubscriptionIds(slot)` (`:2507`, API 29), `getActiveDataSubscriptionId` (`:4295`, API 30),
  `getDefaultDataSubscriptionId` (`:2706`, API 24), `getDefaultVoiceSubscriptionId` (`:2587`, API 24). So Android 7
  to 9 always take the fallback: the data SIM and the default voice SIM only. Without a sub id,
  `getNetworkOperatorName()` answers for the default subscription, not the data SIM (`TelephonyManager.java:2912-2913,
  8541-8545`; compare `getNetworkType` at `:3255`). `getActiveSubscriptionInfoList` needs `READ_PHONE_STATE` and is
  not used.
- Power and background, no permission annotation: `PowerManager.isPowerSaveMode` (`PowerManager.java:1939`),
  `isDeviceIdleMode` (`:2311`), `isIgnoringBatteryOptimizations` (`:2586`); `ActivityManager.isBackgroundRestricted`
  (`ActivityManager.java:4240`, API 28); `UsageStatsManager.getAppStandbyBucket` ("the calling app",
  `UsageStatsManager.java:735-753`, API 28); `ConnectivityManager.getRestrictBackgroundStatus` (Data Saver,
  `ConnectivityManager.java:4683` at `android-11.0.0_r1`, API 24).
- An app reads its own log lines without `READ_LOGS` (the verifier traced it: `logd/LogBuffer.cpp:938` on API 24,
  `LogReader.cpp:255-262` on main). Go writes a fatal panic to fd 2, and on Android its runtime copies the same text
  to logcat under the tag `Go` (`runtime/write_err_android.go`; three `E Go` lines on the API 35 emulator,
  2026-10-07). That copy is lost once the buffer turns over, and a report reads only its own `FlClash` tag, so the
  file below is what reaches support.
- Go `runtime/debug.SetCrashOutput(f, CrashOptions{})` (go1.23): "a single additional file where unhandled panics and
  other fatal errors are printed, in addition to standard error".
- HyperOS's autostart and background killer have no API. The only evidence a killed app gets is its exit record on
  the next start.

Platform (`shikoo-platform` `origin/main` `d5f86fc1`; read only):

- `/api/v1/app/*` has `bodyLimit(1024)` on every route and `no-store` (`apps/ingest-worker/src/appApi.ts:70-77`). The
  support door already gives one path a bigger limit by path (`integrations/support.ts:124-128`, `isLog`).
- Bearer → device: `bearer()` and the `token_hash` lookup (`appApi.ts:199-206,254-269`); `app_devices`
  (`migrations/0130_a_device_signs_in_through_the_bot.sql:32-54`, `user_id` → `users`). Address and device buckets
  (`appApi.ts:84-92`, `appServer.ts:53-58`); the door refuses to boot without `TRUSTED_PROXY_IP_HEADER`
  (`appServer.ts:38-44`). Sweep-on-write is the pattern (`SWEEP_DEAD_CODES`, `appApi.ts:107-108,130`). `/health` at
  `appServer.ts:28`. Last migration on main: `0132`.
- The APK branch (`wt-app-login`, `feat/app-door-serves-apks`, `d1c05ad4`) mounts its routes beside the API
  (`appServer.ts:34`).
- Panel: «گفتگوهای پشتیبانی» opens a customer's conversation (`apps/admin-web/src/pages/SupportChatsPage.tsx:312`)
  under the `supportChats` permission (`apps/dashboard-worker/src/access.ts:271-275`).
- `/login/start` codes are 6 digits with a Damm digit, and the shop bot reads a bare 6-digit app code (PR #699).

## Design: the app keeps a clean local record, and one tap sends it to the door

### App: what is recorded all the time (local, no network)

- One ring file, `<support dir>/shikoo/diag.log` plus `.1`, rotated at 256 KB, lines older than 7 days skipped on
  read. Each line: time, one-letter kind, text. Written by `lib/shikoo/engine/diag.dart`, started in `main()` before
  `bootstrap.init`. App lines come from the `debugPrint` wrapper Shikoo already installs (`main.dart:61-66`), which
  every `CommonPrint.log` passes through before attach and after; core lines come from a `logsProvider` listener. An
  identical line right after itself becomes a counter («×37»), so a dial-failure storm cannot push everything else out.
- **Sanitizer (allowlist).** Every line is cleaned before it enters the ring file. Three files are written raw by
  their own writers and cleaned when read: `go-crash.txt`, `java-crash.txt` and Kotlin's `events.txt` (below). The
  same steps run on every line, stack frames included; Dart `RegExp(…, unicode: true)`:
  1. Go crash text only: a path ending in `.go:<n>` is cut to its file name.
  2. Known values out: every secret listed in the facts that the app holds (port username and password, sign-in
     token, poll secret, live login code, each subscription URL, its host, each path segment of 4+ characters and
     each query value of 8+ characters, as a shorter one is a format such as `target=clash` that would turn
     «FlClash» into «Fl·») becomes `·`, case-insensitively. A value stays known for the life of the process once
     seen, so a crash file read later still loses a password or token since replaced. The list is read afresh on **every write**, from `shikoo.account`,
     `ShikooSignIn`, `profilesProvider` and the network setting's `authentication`, so a value made after the
     recorder started (the port password is made in a post-frame callback, `app.dart:72-80`) is covered too.
  3. Link shapes out, case-insensitively, before any splitting so a `,` `(` `)` inside a link cannot leave a tail:
     `\S*://\S*`, `\S*%[0-9a-f]{2}\S*`, and `host/path` = `[\p{L}\p{Nd}_.-]*[\p{L}\p{Nd}]\.\p{L}{2,}(:\d+)?/\S*`,
     each to `·`.
  4. Split at whitespace and at `(` `)` `,` `=`. Peel punctuation stuck to a token's ends (`[ ( { < " '` before,
     `] ) } > " ' : ; , . ! ? ، ؛ ؟` after).
  5. Keep the token only if all of it is: a word `\p{L}[\p{L}\p{M}\u200c]{0,23}` (ZWNJ inside a word is fine); a
     number `\p{Nd}{1,6}` with an optional `ms`, `s`, `%`, `x`; a letter-digit mix of ≤ 6; up to three of these joined
     by `-` (`DE-1`); a run of `- = < > |`; `#` + digits; a constant `[A-Z]{1,24}(_[A-Z]{1,24}){1,4}`
     (`CERTIFICATE_VERIFY_FAILED`); a code name with at least one dot and no digits,
     `([a-z][a-z0-9_]*\.)+_?[A-Z][A-Za-z_$]{0,39}(\.<?[A-Za-z_$]{1,40}>?){0,3}` or
     `_?[A-Z][A-Za-z_$]{0,39}(\.<?[A-Za-z_$]{1,40}>?){1,3}`; a code place `package:\w+(/\w+)*\.dart:\d+(:\d+)?`,
     `dart:[a-z_]+(/\w+\.dart)?(:\d+){0,2}` or `\w+\.(dart|kt|java|go):\d+(:\d+)?`. Anything else becomes `·`.

  Run on Dart's own engine (`scratchpad\san3\sanitize.dart`, 2026-10-07) over 22 secret cases: 19 of the round-2
  verifier's 23 and 3 new ones. 0 leaks. The verifier's other 4 (`cap domain`, `upper TLD`, `dotless host`,
  `short-id hex 6`) still pass and are the ceilings below. `ping ۱۲ جواب، ۳ بی‌جواب، بهترین ۱۸۰` stays whole;
  `[TCP] dial · --> · error: · timeout`; `Foo.bar(https://x.ir/s/Ab12,CdEf…)` becomes `·`; frames keep `file:line`;
  `status=404` stays. Ceilings:
  - a secret the app does not hold passes only as ≤ 24 letters, ≤ 6 digits or ≤ 6 letters-and-digits (a Reality
    short-id from the subscription is one);
  - a host it does not hold passes only when dotless, starting with a capital (`Shikoonet.ir`), or lower-case with a
    capitalised last label (`sub.shikoonet.IR`, `de1.shikoo2.Net`), never with a path, port or token;
  - a Java frame keeps its package unless its class has a digit (`Foo$1`), then it keeps only `file:line`; a Go frame
    loses its package path and its function name and keeps only `file.go:n`.
- Kinds of line: `A` app log, `C` core warning/error (turn on `openLogs` and core `log-level: warning` beside the
  existing settings in `app.dart:62-71`), `E` Dart error (`FlutterError.onError`, plus `PlatformDispatcher.instance.onError`;
  both write to the recorder directly, so errors before attach are kept; the stack follows as `E` lines, first 30
  frames), `T` timeline, `U` UI event.
- **Timeline (`T`)**, the «why did it drop» record:
  - network change from `_onConnectivityChanged` (wifi/mobile/ethernet/vpn/none) and airplane mode;
  - our VPN state changes and their `ShikooError`, and «revoked» when another VPN took over;
  - subscription refresh result as a kind (`ok`, `http_404`, `timeout`, `tls`, `dns`), and door failures as the
    error kind `fix/wrong-clock` adds (no second type);
  - one line per ping round («۱۲ جواب، ۳ بی‌جواب، بهترین ۱۸۰»);
  - screen on and off; app start, resume and pause; the renderer line once per start;
  - at each start, every new exit record with its reason name (`LOW_MEMORY`, `SIGNALED`, `USER_REQUESTED`, `OTHER`,
    `FREEZER`, `EXCESSIVE_RESOURCE_USAGE` and the rest, names from `AppExitReason`) and its time. That record is
    the only evidence of HyperOS's autostart or battery killer; there is no API for either;
  - below API 30, «alive ×n» every 5 minutes while our VPN runs, so the last one bounds when the process died;
  - every 10 minutes while visible, a frame summary from `SchedulerBinding.addTimingsCallback` (frames, slow
    raster > 32 ms, worst build and raster ms), written only when a frame was slow, so stutter is told apart from a
    layout jump. A connected screen redraws its timer every second, and a slow box has a slow frame in every
    minute: at most 144 lines, about 10 KB, a day.

  Events that can happen while no Dart runs (the VPN service alone keeps the process up) are written by Kotlin to
  `files/shikoo/events.txt` (append, 64 KB cap): screen on/off and airplane-mode changes from receivers registered at
  process start (`ACTION_SCREEN_ON/OFF` can only be registered dynamically), «revoked», «alive». Dart moves them into
  the ring as `T` on start and resume.
- **UI events (`U`)**, for «صفحه می‌پرد»: keys via `HardwareKeyboard.instance.addHandler` returning false (arrows,
  centre, back, enter, media; a printable key is logged as `char`, because no text field's content is ever recorded,
  the server search included), focus moves via `FocusManager.instance.addListener` (widget type and rounded rect),
  route push/pop via a `NavigatorObserver` (the page's widget type), `didChangeMetrics` (logical size, padding,
  insets), `didChangeTextScaleFactor`, and `ScrollEndNotification` (axis, offset, extent) from one listener at the
  root. A jump with no key before it is the finding.
- **Kotlin, from process start** (one line in `FlClashApplication.attachBaseContext`, upstream patch row, calling
  `ShikooDiag.install`): `Thread.setDefaultUncaughtExceptionHandler` writes the stack to `files/shikoo/java-crash.txt`
  and then calls the previous handler, so Android still records `REASON_CRASH`; the two receivers; the «alive» timer
  below API 30. «revoked» needs one line in `ServiceBroadcastReceiver.kt:42-44` (upstream patch row), the smallest hook
  since the broadcast is explicit; without it the only trace is our own logcat on the next start.
- **Go**: a new file `core/shikoo_crash.go` with `//go:build go1.23` holds `setCrashOutput(home)`
  (`debug.SetCrashOutput` on `<home>/go-crash.txt`, append); one line after `constant.SetHomeDir` in `core/hub.go:45`
  calls it (patch row). The build line raises that file's language version, so `go vet` accepts it without touching
  `go.mod`. Ceiling: a panic in a Go package `init` runs at `System.loadLibrary`, before that line, so it shows only as
  an exit record (API 30+); the pre-2012 clock case of `fix/wrong-clock` is one.
- **Exit records**, API 30+: `ShikooDiag.kt` returns those newer than the last seen (reason, status, time,
  description, PSS/RSS), with an ANR's `"main"` thread block (≤ 8192 characters). A native crash sends its record without the
  tombstone.
- **After a crash**: on the next start, if a crash file exists or a new record says crash, crash-native or ANR, Home
  shows one dismissible card: «برنامه دفعهٔ قبل ناگهان بسته شد. گزارشش را برای ما بفرستیم؟» [بفرست] [نه]. Asked once
  per crash, never sent by itself.

### App: the report (only when the customer taps)

Entry points (phone and TV, D-pad reachable): Settings → «عیب‌یابی و گزارش» (a «پشتیبانی» group between «حساب» and
«اپ», in every settings state); «پشتیبانی» on Home (phone: every «پشتیبانی» opens a sheet, [گفتگو در تلگرام] or
[ارسال گزارش به پشتیبانی]; TV: the support QR dialog gains [ارسال گزارش به پشتیبانی] beside [بستن]); the login's
«کد گرفته نشد» state; the connection-failed state (the internet-check card below); a failed «چسباندن لینک»; a failed
manual «به‌روزرسانی سرورها»; the crash card. Each first captures the screen it was pressed on; for «پشتیبانی» that is
the screen under the sheet or dialog, taken before it opens. Frames: `design/mockups/phone-report.html` and
`tv-report.html`, strings in `design/l10n/report_*.arb`.

| Section | Fields (nothing else; the server refuses unknown keys) |
|---|---|
| meta | schema 1, device time at send, trigger |
| app | version name, build number, core version (the value Settings › App shows), ABI, staging or production, signed in, language, theme |
| device | `tv` (from `system.isTV`), manufacturer, brand, model, device, Android release, SDK, security patch, ABIs, low-RAM flag, RAM total/free MB, disk free MB, time zone name and offset, locale |
| screen | logical size dp, device pixel ratio, text scale, padding and insets dp, bold text, navigation mode |
| graphics | Impeller backend (`vulkan`, `opengles` or `unknown`), read once per start from our own logcat (`logcat -d -s flutter:I`) |
| network | transports (connectivity_plus), airplane mode (`Settings.Global.AIRPLANE_MODE_ON`), SIM slots (`getActiveModemCount`, else `getPhoneCount`), per SIM: slot, network and SIM operator name, MCC/MNC, and which one carries data (`getActiveDataSubscriptionId` from API 30, else `getDefaultDataSubscriptionId`); slot ids from `getSubscriptionId(slot)` or `getSubscriptionIds(slot)`, and where neither exists the data SIM and the default voice SIM; Private DNS active and strict (no hostname); Data Saver status |
| power | battery saver, device idle, battery optimisation, background restricted, standby bucket |
| vpn | our state and last `ShikooError`, another VPN up while ours is off |
| checks | the three probes below: ok, or `dns`/`tcp`/`tls`/`timeout`/`http_<code>`, and ms |
| services | per service: the panel's account name (`ShikooService.account`, from `accountOf`: the content-disposition filename, else the 🆔 row, else the part of profile-title before « · »; not the label Home makes unique with « ۲»), falling back to that label while `account` is empty (`service.account ?? service.username`), so until its next refresh a service downloaded before this build sends its label when that passes the rule (usually the account name), and `·` for a label made unique with « ۲»; status, days left, used/total GB, last refresh kind, minutes since update. The name passes only as `^[A-Za-z0-9_-]{1,64}$` (the platform makes `[a-z0-9_]`, shelf rows `[a-z0-9_-]`; no dot, so a host or an IPv4 address fails) and when it equals none of the secrets the app holds, a subscription link's path segments and query values included; anything else is `·`. No link, no title beyond the name |
| servers | label (`ShikooServer.label`) and ping, no address |
| crashes | since the last sent report, ≤ 7 days: source (java, go, exit), time, reason, status, text ≤ 8192 characters after cleaning, each. Dart errors are the `E` lines |
| log | from the ring file, up to 700 lines: the newest `E` lines first, then the newest of the rest; plus the last 100 lines of our own logcat (Kotlin's `FlClash` tag), cleaned |
| images | optional: `app` and `screen` PNGs, below |

- Two images, taken together at the tap and both scaled to dp: `app`, a `RepaintBoundary` around the app in
  `ShikooApp.builder` with `toImage(pixelRatio: 1)` (Flutter's own offscreen drawing on this GPU), and `screen`,
  `PixelCopy.request` on the `FlutterSurfaceView` (API 24+, no permission; what Flutter actually put on the window).
  Support looks at them side by side, with the WP7 replay picture at the same size: a defect in all three is our
  layout, one only on the device is drawing or presenting. No screen shows a subscription link. The login page
  shows a live code and its bot-link QR (`lib/shikoo/ui/login.dart:65,439`), and no report entry point sits on it
  while a code is live: its only one is the «کد گرفته نشد» state, which has no code. If an entry is ever added
  there, its images are not taken while a code is live.
- **Within the server's limits, always** (otherwise the door refuses the whole report): every log line is cut to
  300 characters; the log keeps the newest `E` lines first, then the newest of the rest, up to 700; a crash text is
  cut to 8192 characters after cleaning, keeping the head; an image whose base64 string is over 400 KB is encoded
  once more at 0.5 of its size, and if still over it is dropped and `images.note` says `too_large`; if
  `jsonEncode(report)` is still over 1.4 MB, both images are dropped with the same note. One function builds the map
  from typed values; no `toJson` of FlClash objects, no preference dump.
- **Preview**, phone 343–412 dp at font 1.45 (343 is the Poco C85) and TV 960 and 1280 dp. The two images in one
  row, each half the width less the gap, at most 200 dp tall on a phone and 240 dp (16:9) on TV, with their names
  «آنچه برنامه کشید» and «آنچه روی صفحه بود» under them; then one switch «عکس صفحه‌ها هم فرستاده شود» (on) that drops
  both and marks them «فرستاده نمی‌شود»; then «فرستاده می‌شود: مدل و تنظیمات دستگاه، نسخهٔ برنامه، نام و حجم
  سرویس‌هایت، اپراتور و وضعیت اینترنت، و کارهای اخیر برنامه و خطاهایش. لینک اشتراک و رمزها هرگز فرستاده نمی‌شوند.»; then
  [ارسال] and [انصراف]. Phone: the middle scrolls and the two buttons are pinned, full width and stacked, at the
  bottom. TV: no scroll; the switch and the two buttons share the bottom row, three remote stops, [ارسال] focused.
  The sentence names the kinds of data, not every field; nothing outside the table above is sent.
- Send: `ShikooApi.report()` through `_call` (failover, DIRECT, the sign-in token as Bearer when there is one), its
  own `sendTimeout` of 60 s; while it runs, «در حال ارسال…» and [انصراف]. Result: signed in → «فرستاده شد»,
  «پشتیبانی گزارشت را می‌بیند؛ لازم نیست چیزی بفرستی.» and the code small, [بستن] [پشتیبانی]; not signed in → the
  8-digit code large in two groups of four, «این کد را به پشتیبانی بده.», [پشتیبانی] [بستن]. «پشتیبانی» there opens
  the chat (TV: the QR dialog) without the report button. Failed → «فرستاده نشد» [دوباره] [انصراف]; «دوباره» resends
  the same report and images. When the door refused the device's clock, the `fix/wrong-clock` message and
  [تنظیمات تاریخ و ساعت] [دوباره]. A sent report clears the crash files and remembers the last exit record.

### App: «اصلاً اینترنت دارد؟» — three DIRECT probes

Run from «عیب‌یابی و گزارش», after a failed connect, and inside every report. Each target gets a mihomo DIRECT rule
next to `keepApiDirect` (ids from 7470100), so the answer is the same with the VPN on or off.

| Probe | Target | Why |
|---|---|---|
| domestic | `HEAD http://www.aparat.com/`, then `http://www.digikala.com/`; any HTTP status counts | Large Iranian sites hosted inside Iran; plain HTTP so a wrong clock cannot fail it |
| international | `GET http://connectivitycheck.gstatic.com/generate_204`, expect 204 | Android's own connectivity check; tiny, plain HTTP; a non-204 means an injected page |
| door | `GET https://<base>/health` via `ShikooApi` bases | The real path, TLS included, on the Iranian box |

Reading, one card with one sentence; it is decided by the door first. While running: «در حال بررسی اینترنت…», no
button. Door not reached: all three fail → «این دستگاه به اینترنت وصل نیست.» [تنظیمات اینترنت]; otherwise → «به سرور
شیکونت نرسیدیم؛ چند دقیقهٔ دیگر دوباره امتحان کن.» [پشتیبانی]. Door reached: international fails → «اینترنت بین‌الملل روی این خط قطع
است. سرورها بیرون از ایران‌اند.»; every server ping fails → «هیچ‌کدام از سرورها جواب نمی‌دهند.» [به‌روزرسانی سرورها]
[پشتیبانی]; else → «اینترنت وصل است و سرور شیکونت در دسترس است.». A domestic failure with the door reached changes
no sentence and goes only into the report. [ارسال گزارش] is on the card exactly when the door was reached (the last
three), since a report cannot arrive otherwise. After a failed connect the card sits at the head of Home's cards
(TV: head of the card column, without taking focus), and the next connect removes it. On «عیب‌یابی و گزارش» the card
has [دوباره] instead of [ارسال گزارش], and the big [ارسال گزارش به پشتیبانی] below it is hidden while the door is not
reached, replaced by «گزارش الان نمی‌رسد. وقتی اینترنت برگشت، «دوباره» را بزن.».

### Door API (`apps/ingest-worker/src/appReport.ts`, new migration `0133_an_app_sends_a_report.sql`)

- `POST /api/v1/app/report`: Bearer optional. JSON ≤ 1.5 MB (its own `bodyLimit` by path, the `isLog` pattern; the
  rest of `/api/v1/app/*` keeps 1024). Zod `.strict()` on every section, so the allowlist is enforced on both sides;
  `log` ≤ 700 strings of ≤ 300 chars; crash texts ≤ 8192 characters; each image a base64 PNG string of ≤ 400 KB
  (the string's length, as the app measures it). After parsing, every
  string value is checked, case-insensitively, for `[a-z][a-z0-9+.-]*://` and `%3a%2f%2f`; a hit refuses the whole
  report with `422 contains_link` (parsed values, not the raw body, because `https:\/\/` is valid JSON). Answers
  `{ok:true, code:"48219037", linked:true}`.
- Linking: a live Bearer (same lookup as `/services`) stores `user_id` and `device_id`; a dead or absent one stores
  neither, the report is still kept. The code is 7 random digits + Damm (`dammDigit`), 8 in all, so the shop bot
  never mistakes it for a 6-digit sign-in code; unique among stored reports, retried like `/login/start`.
- Network owner: `clientIp()` from `TRUSTED_PROXY_IP_HEADER` → ASN, AS name and country from iptoasn's
  `ip2asn-combined.tsv.gz` (IPv4+IPv6, columns `range_start range_end AS_number country_code AS_description`, updated
  hourly, PDDL v1.0 public domain, no attribution). Loaded lazily from `ASN_DB` into sorted arrays, binary search. The
  IP itself is never stored. Fetched at image build with `|| true`; without it the three fields are null. Rejected:
  DB-IP Lite ASN (CC BY 4.0, must link back wherever results show), MaxMind GeoLite2 (account and EULA).
- Clock: the server stores `server_now - meta.device_time` as `clock_skew_s`; that is the report's only clock field.
- Limits: 6 per hour per address, 6 per hour per device, 600 per hour in all (`fixedWindowRateLimit`, as the door's
  buckets). Retention: `DELETE … WHERE created_at < now() - interval '30 days'` on every insert, the
  `SWEEP_DEAD_CODES` way.
- Table `app_reports`: `id, code, user_id, device_id, created_at, asn, as_name, as_country, clock_skew_s, report
  jsonb, app_png bytea, screen_png bytea`; indexes on `code` and `(user_id, created_at)`.

### Support view: the panel

Dashboard-worker `GET /api/v1/admin/app-reports?telegram_id=|code=` (list, newest 10) and `GET …/app-reports/:code`
(full; each image as `image/png` on its own path), under `supportChats`. Admin-web: a «گزارش‌های اپ» block inside
`SupportConversation` for that telegram id, and one code search box on «گفتگوهای پشتیبانی» that turns Persian and
Arabic digits into ASCII and drops spaces, since the app shows the code in Persian digits as two groups of four. A
report page: a summary
card (device, screen, graphics, network and ASN, SIMs, power, clock offset, the three probes, crashes), the two
images side by side, then the timeline and log collapsed.

## Defaults (conductor, until Sam objects)

1. Sent only on a tap; after a crash, one offer on the next start.
2. Both images on by default, both shown in the preview, one switch drops them.
3. Core logs on at `warning`, cleaned; the ring file is 2 × 256 KB and 7 days.
4. Report code 8 digits (not 6); retention 30 days; 6/hour per address and per device.
5. ASN from iptoasn; the IP is not stored.
6. Support reads reports in the panel only.

## Work packages

WP1 and WP6 write in shikoo-platform, outside the Telegram sign-in exception: each **needs Sam's explicit go-ahead
(rule 4)** before any branch is made there.

| WP | Where | Size | Depends on |
|---|---|---|---|
| 7 Replay (first) | new `test/shikoo/device_replay_test.dart` + `devices.json`: each layout report adds its size, ratio, text scale, TV and locale, and phones at 343 (Poco C85), 360 and 412 dp with font 1.45 are in from the start; home in every state, settings, login and the report preview are pumped, any overflow fails (the assert fires in tests), and each screen is written as the reference picture | S | — |
| 1 Door — **needs Sam's explicit go-ahead (rule 4)** | shikoo-platform: new `appReport.ts`, `appApi.ts` (per-path body limit), `appServer.ts`, migration `0133` + manifest, `Dockerfile` (iptoasn fetch), new `test/app-report.test.ts` (accept, unknown key 400, link in a parsed value 422 incl. `https:\/\/` and upper case, 413, a 301-char line and a 401 KB image refused, link to user, code shape and Damm, sweep, 429, ASN from a fixture TSV with no IP stored), `docs/configuration-matrix.md` | M | — |
| 3 Android and Go | new `ShikooDiag.kt` (`shikoo/diag`: install from process start, crash handler, `events.txt`, screen and airplane receivers, «alive» below API 30, exit records with traces, SIMs, power readables, Private DNS, Data Saver, own logcat tail and the renderer line, `PixelCopy` of the Flutter surface), `FlClashApplication.kt` (one line), `ServiceBroadcastReceiver.kt` (one line, «revoked»), `MainActivity.kt` (one line, channel), new `core/shikoo_crash.go`, `core/hub.go` (one line), `SHIKOO_PATCHES.md` rows | M | — |
| 2 Record and send | `feat/app`: new `lib/shikoo/engine/diag.dart` (ring file, sanitizer, timeline, frame summary, UI events, report map, limits, `app` image), `account.dart` (`ShikooApi.report()`; reuse the error kind `fix/wrong-clock` adds), `app.dart` (`openLogs`, core warning, hooks), `main.dart` (recorder before `bootstrap.init`, `PlatformDispatcher.onError`), new `test/shikoo/diag_test.dart` (below) | M | WP3; after `fix/wrong-clock` is merged; WP1 for end to end |
| 4 UI | design frames drawn (`design/mockups/phone-report.html`, `tv-report.html`, entries in the existing frames), including the phone preview at 343 dp and font 1.45 (`phone-report-preview-145`) and the TV one; `lib/shikoo/ui/report.dart` (preview, send, code), entry buttons (the seven above, and the phone «پشتیبانی» sheet), internet-check card, crash card, arbs (`design/l10n/report_*.arb`) | M | WP2, WP3 |
| 5 Probes | the three probes and their sentences in `diag.dart`, DIRECT rules beside `keepApiDirect` | S | WP2 |
| 6 Panel — **needs Sam's explicit go-ahead (rule 4)** | shikoo-platform: dashboard-worker routes + `access.ts`, admin-web block and code search (Persian digits and spaces normalised) | M | WP1 |
| 8 On-device checks (later) | in «عیب‌یابی و گزارش», one plain sentence and a settings button per finding of the report: service ended, VPN permission, another VPN, Private DNS, battery optimisation, storage, memory, Data Saver, background restricted | S | WP5 |

`test/shikoo/diag_test.dart`, under `flutter test` (Dart's own `RegExp`):

- Plants into every source (app log before and after attach, core line, Dart error, Java crash, Go crash, ANR text,
  `events.txt`, server label, service name): a link with `://`; one without it (`sub.example.ir/sub/<token>`); a
  percent-encoded one; a link containing `,` and `)` inside a call (`Foo.bar(https://x.ir/s/Ab12,CdEf…)`); a
  stack-frame-shaped line and a `Fetch.get(…)` shape holding a link; a server name that is a domain; IPv4 with port;
  IPv6; a UUID with and without dashes; a 43-char base64url token; a WireGuard key; the port username and password
  as all-letter strings, the sign-in token, the poll secret and the live login code; and a port password made
  *after* the recorder started (as the post-frame callback at `app.dart:72-80` does), written to the log after that.
  None of their hosts, paths, addresses or values may appear in `jsonEncode(report)`, and the test goes red with the
  filter removed.
- Readable: `ping ۱۲ جواب، ۳ بی‌جواب، بهترین ۱۸۰` unchanged; `[TCP] dial · --> · error: · timeout`; a
  `package:…dart:n` frame and its `<anonymous closure>`; `HandshakeException … CERTIFICATE_VERIFY_FAILED`.
- Limits: a 5000-character line, 2000 lines with 300 `E` lines, a 20 KB crash text and a 3 MB image give a report the
  door's limits accept, holding all 300 `E` lines and then the newest 400 of the rest, and `images.note` set when an
  image was dropped.
- The key set equals the table.

Internet is WP5; the clock message is `fix/wrong-clock`. Every settings intent falls back to `ACTION_SETTINGS` when a
TV lacks it.

## Must be proven on a real device

- Android 12 TV (the jumping one, spinner gone): the renderer line is readable by the app in a release build; the two
  images, the frame summary and the UI events show the jump; if it is layout, its numbers make WP7 fail before the fix.
- Mi Box (Android 9, 32-bit, API 28): `coreController.crash()` in a debug build leaves `go-crash.txt`; with the Go stack
  on the API 35 emulator, but only the panic's first line (27 bytes, no stack) on the API 25 emulator, sent report or
  not; on the Mi Box unproven. A forced Kotlin crash leaves `java-crash.txt`, also when started from the tile with no
  Activity; no exit records (below API 30) but «alive ×n» stops where the process died; the SIM fallback runs (only
  the data SIM and the default voice SIM) and, with no telephony, returns empty without throwing; both images work on
  its Mali GPU; D-pad keys and focus moves are recorded; the own-logcat tail
  returns our lines.
- Poco C85 (HyperOS, Android 15, font 1.45):
  - two SIMs: both slots named, the data SIM marked, and switching the data SIM changes the mark;
  - HyperOS killing the app in the background leaves an exit record whose reason we can name, and it reaches `T`;
  - the preview at font 1.45 fits, with both images, the switch and both buttons reachable;
  - `PixelCopy` returns the frame under Vulkan;
  - the Go panic's exit record (expected `EXIT_SELF` status 2, or a signal); a debug ANR gives a `main` trace;
  - another VPN app taking over leaves «revoked» in `T`; screen off and on, and airplane mode, appear in `T`.
- From an Iranian line: aparat, digikala and `generate_204` answer DIRECT; the door's ASN is the home ISP or the
  carrier, also while connected.

## Risks

- `openLogs` on: a core error line pops FlClash's English toast (`core_manager.dart:82-89`). Dial failures are
  warnings, so it should be rare; if seen, a one-line upstream patch drops the toast.
- The allowlist throws away hosts, addresses and Go/Java package paths that would sometimes help. Accepted; a new
  shape needs its own planted-link case.
- A secret that is never added to the known-values list is protected by the shape filter alone, with its ceilings.
- A clock far enough off breaks HTTPS, so that customer cannot send a report until `fix/wrong-clock` gets the clock
  right.
- Below API 30 (Mi Box, Android 7 boxes) native crashes and ANRs leave nothing but an unexplained restart, bounded
  by the last «alive».
- The images show the username and remaining volume (no links); the customer sees them first and can drop them.
- Anonymous uploads can fill the table: the caps and the 30-day sweep bound it (worst case ~600 × 1.5 MB an hour).
- The renderer comes from logcat; if a device's log buffer has already rotated past the start line, it reads `unknown`.
- The image build may not reach iptoasn.com; then ASN is null and MCC/MNC still names a mobile carrier.
- Four one-line upstream edits (`FlClashApplication.kt`, `ServiceBroadcastReceiver.kt`, `MainActivity.kt`,
  `core/hub.go`) and one new file in `core/` to carry through every FlClash merge.

Later: the bot half (a support-door `/app-reports` summary and an n8n tool) — **needs Sam's explicit go-ahead
(rule 4)**, both are outside this repo; GPU name and Vulkan version (`isShaderFilterSupported` if drawing bugs need
it); native tombstones (API 31+); a main-thread watchdog for ANRs below API 30; reports queued while offline; a
per-screen overflow probe in release.
