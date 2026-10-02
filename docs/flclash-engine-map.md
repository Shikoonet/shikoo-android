# FlClash engine map for the Shikoo UI

Phase-0 question 4: can a separate Shikoo UI drive FlClash's engine without showing any FlClash screen?
Source: FlClash v0.8.98 (`7c61c90`, `D:\dev\shikoo-spike\FlClash`), read on 2026-10-02 and revised after the verifier's review. Nothing was built or run on a device.
Paths are relative to the FlClash root. "Ours" means code we will write under `lib/shikoo/`.

**Answer: yes.** Every need below is met by a Riverpod provider or a notifier method in `lib/providers/`.
- The engine never opens a FlClash page by itself. A grep for `Navigator.of`, `push(` and `showModalBottomSheet` in `lib/providers`, `lib/manager`, `lib/core` and `lib/common` (dialog helpers excluded) finds only a `pop` helper (`lib/common/context.dart:30`).
- Dialogs and toasts can still appear (§1, risk 2).

## 1. Boot

- **Startup chain (`lib/main.dart:31-41`):** `RustLib.init()` → `system.init()` (device info, TV flag) → `bootstrap.init()` → `HttpOverrides` + `request.attach` → `runApp(UncontrolledProviderScope(container, const Application()))`. If init fails, FlClash's `InitErrorScreen` appears (`:42-49`).
- **`bootstrap.init` (`lib/bootstrap.dart:38-136`):** `APP_ENV` defaults to `'pre'` (`:39-42`). Config comes from `migration.run()` (`:93`), then `bootGuard.evaluate` runs (`:94-97`). The container gets config and app-state overrides (`:112-117`). Profiles load from Drift (`:125-126`), then `AppLocalizations.load` (`:127-130`).
- **After the first frame:** `ApplicationState` calls `bootstrap.attach()` only if `globalState.navigatorKey.currentContext != null`; otherwise it calls `exit(0)` (`lib/application.dart:80-89`).
- **`_initApp` (`lib/bootstrap.dart:148-173`), in order:**
  - profile auto-update (`:151`) and the GitHub update check (`:153`);
  - awaited dialogs: corrupt-prefs (`:162`); **disclaimer** (`:163` → `:238-251` → `dialogs.showDisclaimer`, `lib/common/dialog.dart:115`); crash-recovery tip (`:164`); **Firebase data-collection tip** (`:165` → `:221-236`, Android only, once);
  - `startCore()` (`:166`), `initStatus()` (`:168`), `initProvider = true` (`:170`).
- **Swap point: `lib/main.dart:39`.** One file, about 3 lines: `const Application()` becomes `const ShikooApp()`, `:45` gets our error screen, and one import is added.
  - Swapping only `HomePage` (`lib/application.dart:195`) is not enough, because FlClash's `MaterialApp` would remain. That means no `fa` locale and so no RTL (`:178`; `lib/l10n/l10n.dart:5122-5129`), the title "FlClash" in Android's recent apps (`:176`), FlClash's colours (`:180-191`), and the listener that installs any `clash://install-config` URL after a FlClash dialog (`:87`, `:92-119`).
- **Zero-patch alternative: `lib/shikoo/main.dart`, built with `-t`.** It repeats `main()` (`lib/main.dart:15-57`) with `ShikooApp`.
  - Everything it calls is public: `RustLib.init`, `system.init` (`lib/common/system.dart:44`), `bootstrap` (`lib/bootstrap.dart:254`), `FlClashHttpOverrides` (`lib/common/http.dart:10`), `request.attach` (`lib/common/request.dart:19`).
  - `setup.dart` passes flutter_distributor only `dart-define-from-file=env.json,split-per-abi` (`setup.dart:113-125,209-210`). Adding `target=lib/shikoo/main.dart` there is itself a patch, and how the distributor fork maps it is unverified.
  - A direct build needs no patch: `flutter build apk -t lib/shikoo/main.dart --split-per-abi --dart-define=APP_ENV=stable`. The build hook still builds the Go core (`.agents/commands.md:20-26`).
  - Cost: upstream edits to `lib/main.dart` must be copied by hand. Keep top-level classes out of that file, or `test/lint/dead_file_test.dart:5,67-76` flags it.
- **`ShikooApp` must:**
  - set `navigatorKey: globalState.navigatorKey`; the attach gate and `lib/common/dialog.dart:14` use it;
  - wrap `builder:` in `MaterialUiCompatibilityBridge` (`lib/application.dart:164`) and in the public `buildManagerStack(isDesktop: false, …)` (`:21-50`), which wires up the Core, the VPN, the tile and shared state;
  - pass the required `onConnectivityChanged` (`:23-24`). FlClash's private handler (`:131-142`) re-syncs system DNS (desktop only), refreshes the local IP and re-checks the IP; ours does the last two;
  - call `SystemNavigator.setFrameworkHandlesBack(true)` (`:79`) and, after the first frame, `bootstrap.attach()`. `app?.initShortcuts()` (`:88`) is optional (D2 in §8);
  - recreate the 20-minute `autoUpdateProfiles` timer (`:121-129`);
  - register an `AppLocalizations` delegate that accepts `fa` and loads FlClash's strings. FlClash's own delegate rejects `fa` (`lib/l10n/l10n.dart:5132-5145`). Without one, `dialogs.showMessage` (`lib/common/dialog.dart:48`) reaches the null check at `lib/l10n/l10n.dart:45-51` and throws (by reading; not run).
- **Turning the dialogs off without a patch.** After the first frame, just before `attach()`, set the flags `_initApp` checks (`lib/bootstrap.dart:223-226,239-242`; `lib/providers/actions/common.dart:77`; fields at `lib/models/config.dart:80-84`).
  - The settings providers are auto-dispose (`lib/providers/config.dart:7-8`). Write to them only while `AppStateManager` listens to `configProvider` (`lib/manager/app_manager.dart:36-40`), or the write is lost.
  - `ref.read(appSettingProvider.notifier).update((s) => s.copyWith(disclaimerAccepted: true, crashlyticsTip: true, crashlytics: false, autoCheckUpdate: false));`
- **Reaching the Core:** use `coreHandlerProvider` (`lib/providers/core.dart:6-7`), never the `coreController` global. This is upstream's rule for UI code (`.agents/architecture.md:228-231,252-256`).

## 2. Profiles

- **Adding a profile with our label.** Skip `addProfileFormURL` (`lib/providers/actions/profiles.dart:119-136`). It has no label parameter, it pops our navigator to the root and changes FlClash's page state (`:120-123`), and its errors open a FlClash dialog because `loadingRun` is non-silent by default (`lib/state.dart:50-71,94-99`). Ours uses the same engine path (`lib/models/profile.dart:66-74,179-190`; `lib/providers/actions/profiles.dart:59-63`):
  `final p = await Profile.normal(label: serviceLabel, url: url).update(validate: ref.read(coreHandlerProvider).validateConfig);`
  `ref.read(profilesActionProvider.notifier).putProfile(p); // also selects it when none is current`
- **How the name is chosen.** `update()` keeps a non-empty label. Otherwise it takes the file name from `content-disposition`, and failing that the snowflake id (`lib/models/profile.dart:184-187`). That id is probably the number we saw (unverified).
  - Nothing reads `profile-title`, `profile-update-interval` or `support-url` (grep of `lib/` and `core/*.go`).
  - `put` renames a duplicate label (`lib/providers/database.dart:120-126` → `lib/models/profile.dart:123-139`), so after a re-login we update the existing profile instead of adding one.
- **Update one:** `updateProfile(p, showLoading: true)` (`lib/providers/actions/profiles.dart:72-97`). It throws on error; the spinner is `isUpdatingProvider(p.updatingKey)` (`lib/providers/app.dart:471`).
  - All: `updateProfiles()` (`:65-70`); it stops at the first error.
  - Only those that are due, with errors swallowed: `autoUpdateProfiles()` (`:42-57`); the period is 1 day (`lib/common/constant.dart:67`).
- **Delete:** `deleteProfile(id)` (`:22-36`) removes the file and the Core cache, then selects the first remaining profile or stops the VPN.
- **List and current:** `profilesProvider` (`lib/providers/database.dart:95-98`) and `currentProfileProvider` (`lib/providers/state/profile.dart:10-16`).
- **Select:** `ref.read(currentProfileIdProvider.notifier).value = id` (`lib/providers/config.dart:48-54`). `CoreManager` then runs `fullSetup()` (`lib/manager/core_manager.dart:40-45`).
- **Volume and expiry:** `profile.subscriptionInfo` (`lib/models/profile.dart:15-42,53`).
  - Fields: `upload`, `download` and `total` in bytes; `expire` in Unix seconds, 0 = unset.
  - It is parsed from `subscription-userinfo` on each `update()` (`:182,188`) and stored in the Drift column `Profiles.subscriptionInfo` (`lib/database/profiles.dart:26`), so it is only as fresh as the last update.
- **Gotchas:**
  - The header parser throws `RangeError` on a segment without `=` (for example a trailing `;`), which fails the whole add or update (`lib/models/profile.dart:31-33`).
  - The download has no timeout (`lib/common/request.dart:42-55`); wrap it in `.timeout()`.
  - The UA is `'$appName/v$version clash-verge Platform/android'` (`lib/common/package.dart:8-12`, `lib/state.dart:46-48`). Renaming `appName` (`lib/common/constant.dart:12`) or changing our pubspec `version` changes it, and whether the panel then still returns the Clash format is unverified. So keep `appName`, and if the version changes, pin `patchClashConfig.globalUa` (a setting, not a patch).

## 3. Proxies

- **Groups:** `currentGroupsStateProvider` (`lib/providers/state/proxies.dart:3-29`). It is filtered by mode: rule mode hides `hidden` groups and `GLOBAL`, and `now` is blanked.
  - The raw list is `groupsProvider` (`lib/providers/app.dart:244`), refilled by `updateGroups()` after each setup (`lib/providers/actions/proxies.dart:74-115`, `lib/providers/actions/setup.dart:291-294`).
  - The current pick is `selectedProxyNameProvider(group.name)` (`lib/providers/state/proxies.dart:233-240`). Models: `lib/models/common.dart:401-413` and `lib/models/clash_config.dart:144-152`.
- **Select:** `ref.read(proxiesActionProvider.notifier).changeProxyDebounce(group.name, proxy.name)` (`lib/providers/actions/proxies.dart:53-68`) is optimistic; `changeProxy()` (`:137-175`) can be awaited.
  - It closes every connection, because `closeConnections` defaults to true (`:163-167`). On failure it rolls back and shows a FlClash toast (`:150-160`).
  - It works on Selector groups and pins URLTest/Fallback (`core/hub.go:174-206`, `core/Clash.Meta/adapter/outboundgroup/util.go:30-36`).
- **Delay:** one proxy with `proxyDelayTest(proxy, group.testUrl)` (`:233-235`); all with `delayTest(group.all, group.testUrl)` (`:237-240`).
  - Read the result from `delayProvider(proxyName:, testUrl:)` (`lib/providers/state/proxies.dart:174-185`): null = not tested, -1 = the probe failed or timed out, otherwise milliseconds. A test that timed out while queued changes nothing (see Gotchas).
  - Progress is in `delayTestPendingProvider` (`:187-196`).
- **Timeout:**
  - Each probe gets 8 s, which is sent to the Core (`lib/common/constant.dart:55`, `lib/core/interface.dart:345-357`). The Dart guard is 30 s (`constant.dart:57`).
  - Dart runs 16 probes at once (`constant.dart:63`, `proxies.dart:26`). Waiting in the queue and probing each get the full 8 s (`core/hub.go:262-303`). This may explain the spike's false Timeouts (unverified).
  - The no-patch fix is for our UI to test one proxy at a time, or in small batches. A longer timeout needs a 1-line patch at `constant.dart:55`; keep the guard above twice the timeout (`:52-54`).

## 4. VPN

- **Start and stop:** `ref.read(setupActionProvider.notifier).setRunning(on, initialize: on && !ref.read(initProvider))` (`lib/providers/actions/setup.dart:112-128`).
  - Without `initialize`, a start requested before boot finishes is silently ignored (`:113-115`); FlClash's own toggle does the same (`lib/providers/actions/common.dart:11-23`).
  - Auto-connect at launch is `appSetting.autoRun` (`setup.dart:104`).
  - The path is `startListener` → `service.start()` (`lib/core/lib.dart:114-118`) → `ServiceState.requestStart()`, which **returns true immediately** (`android/app/src/main/kotlin/com/follow/clash/plugins/ServicePlugin.kt:100-103`).
- **Watchable state:**
  - `isStartProvider` is `runTimeProvider != null` (`lib/providers/state/proxies.dart:122-125`). `runTimeProvider` is the connected time in ms; it ticks every second (`lib/providers/app.dart:147`, `setup.dart:60-89`) and is restored from native at boot (`setup.dart:91-106`).
  - `coreStatusProvider` (`connecting/connected/disconnected`, `lib/providers/app.dart:333-339`) is the link to the Go core, not the tunnel. `initProvider` (`app.dart:191`) means boot has finished.
- **Flutter never sees "starting" or "error":**
  - native `RunState` (STOPPED/STARTING/STARTED/STOPPING, `ServiceStateMachine.kt:40,49`) only feeds the Quick Settings tile (`TileService.kt:24,43-48`);
  - if consent is denied, native resets silently (`ServiceStateMachine.kt:229-233,320-322`) while Flutter still says "running".
- **Our fix:** after a start, poll `service?.getRunTime()` through our own provider (null = stopped, `lib/plugins/service.dart:93-99`). Derive connecting/running/error, allowing a timeout for the consent wait (see Gotchas), and call `setRunning(false)` on failure.
- **Consent:** `ServiceStateMachine.kt:229,286-305` → `AppPlugin.prepareVpn` → `VpnService.prepare` + `startActivityForResult` (`android/app/src/main/kotlin/com/follow/clash/plugins/AppPlugin.kt:337-355`); the result comes back at `:432-438`. This is automatic, so our UI does nothing. `:350` has no try/catch, so a box without the system VPN dialog may crash.

## 5. Live data (home screen)

- **Speed:** `ref.watch(trafficsProvider.select((s) => s.list.safeLast(const Traffic())))`, the same as `lib/providers/state/system.dart:74-76`. **Total since start:** `totalTrafficProvider`.
  - Both are in `lib/providers/app.dart:104-129`; `Traffic(up, down)` is in bytes (`lib/models/common.dart:367-381`).
  - They are filled every second only while connected (`setup.dart:72-81` → `common.dart:40-62`) and cleared on stop (`setup.dart:169-171`).
- **Connections:** `ref.read(coreHandlerProvider).getConnections()` (`lib/core/controller.dart:147-149`), polled each second as `lib/views/connection/connections.dart:30,67` does. Close them through `coreActionProvider` (`lib/providers/actions/core.dart:66-72`).
- **Exit IP and country:** `networkDetectionProvider` (`lib/providers/app.dart:476`).
  - `AppStateManager` runs it while `dashboardWidgets` contains `networkDetection`, which it does by default (`lib/models/config.dart:45`, `lib/manager/app_manager.dart:31-35`). It calls 7 third-party IP services (`lib/common/request.dart:92-100`).
  - Keep it to show the country, or remove that entry from the setting.

## 6. TV

- **Detection:** `system.isTV` checks for `android.hardware.type.television` or `android.software.leanback` (`lib/common/system.dart:42-54`). FlClash only uses it to place the FAB (`lib/widgets/scaffold.dart:319-326`, `lib/widgets/float_layout.dart:20`).
- **Remote control (D-pad):** FlClash has some, written with plain Flutter focus APIs.
  - **Reusable as-is:** `PageFocusScope` and `PageTraversalPolicy` (`lib/widgets/focus.dart:3-49`), used at `lib/pages/home.dart:72-73,130`. The first is a page-level `FocusScope`. The second is a reading-order policy that, at a page edge, moves focus to the enclosing scope (for example from content to the side menu). Both are public and import only `material_ui`, so our TV shell can wrap its pages and menu in them.
  - **Copy the pattern, not the widget:** the right arrow moving from a card to its actions (`lib/widgets/card.dart:282-299`), and keeping focus on the `NavigationRail` after a page switch (`lib/manager/app_manager.dart:200-214`). Both live inside FlClash-styled widgets.
- **Launcher entry:** `LEANBACK_LAUNCHER` (`android/app/src/main/AndroidManifest.xml:53`) and `android:banner="@mipmap/ic_banner"` (`:33`; file `android/app/src/main/res/mipmap-xhdpi/ic_banner.png`). Touchscreen and leanback are `required="false"` (`:5-13`), so one APK serves both phone and TV.

## 7. Firebase Crashlytics

All five CLAUDE.md points are confirmed: `android/app/build.gradle.kts:7-8,110-112`, `android/common/build.gradle.kts:35-37`, `android/settings.gradle.kts:24-25`, `lib/bootstrap.dart:96,165,221-236`, `lib/common/boot_guard.dart:30,46`. Other places:

- `android/app/google-services.json` holds the config of the FlClash author's Firebase project.
- `android/gradle/libs.versions.toml:2,19-21` declares the BOM, `crashlytics-ndk` and **`firebase-analytics`**.
- `android/common/src/main/java/com/follow/clash/common/GlobalState.kt:7-8,39-50` holds the only SDK calls. `setCrashlytics` runs `FirebaseApp.initializeApp` even when switching off (`:40`).
- **Native callers:** `ServiceStateMachine.kt:179-180` (every setup), `ServiceStateHost.kt:93`, `AppPlugin.kt:183-184`. The native default is `crashlytics = true` (`android/app/src/main/kotlin/com/follow/clash/models/State.kt:9`); the Dart default is false (`lib/models/config.dart:84`).
- **Dart plumbing**, inert once native is stubbed: `lib/common/system.dart:63-66`, `lib/plugins/app.dart:166-170`, `lib/providers/state/system.dart:162,189,198`, and the toggle at `lib/views/application_setting.dart:97-100`.
- **Official APK manifest** (`aapt2 dump xmltree`, 2026-10-02): it declares `FirebaseInitProvider`, Firebase Sessions and the Analytics `AppMeasurementService`/`Receiver`/`JobService`, and requests `com.google.android.gms.permission.AD_ID`, `ACCESS_ADSERVICES_AD_ID`, `ACCESS_ADSERVICES_ATTRIBUTION` and install-referrer.
  - It has no `*_collection_enabled` meta-data. These components are declared to start with the process, outside the in-app switch; whether anything is sent while the switch is off is unverified.
- **Google, but not Firebase:** ML Kit (`MlKitInitProvider`, datatransport, `CAMERA`) from `mobile_scanner` (`pubspec.yaml:37`; `lib/common/picker.dart`, `lib/pages/scan.dart`) for QR import, and location permissions from `plugins/wifi_ssid/android/src/main/AndroidManifest.xml:6`.

## 8. `SHIKOO_PATCHES.md`: first proposal

| # | Upstream file | Why |
|---|---|---|
| 1 | `lib/main.dart:39,45` + 1 import | Mount `ShikooApp` and our error screen: 1 Dart file, about 3 lines. Not needed with the `-t` entry point and a direct build (§1). |
| 2 | `android/app/build.gradle.kts:7-8,38,110-112` | Our `applicationId` (Sam decides); remove the Firebase plugins and dependencies. |
| 3 | `android/settings.gradle.kts:24-25` | Remove the Firebase Gradle plugins. |
| 4 | `android/common/build.gradle.kts:35-37` | Remove the Firebase dependencies. |
| 5 | `android/common/src/main/java/com/follow/clash/common/GlobalState.kt:7-8,39-50` | Make `setCrashlytics` a no-op and `didCrashOnPreviousExecution()` return false, so the callers still compile. |
| 6 | `android/app/google-services.json` | Delete it: it belongs to someone else's Firebase project. |
| 7 | `android/app/src/main/AndroidManifest.xml:58-69` | Remove the `clash`/`clashmeta`/`flclash://install-config` link, because users must not add arbitrary links. |
| 8 | `android/common/src/main/res/values/strings.xml:3-4` | App name (shown in the launcher, the TV row and the VPN session, `android/service/src/main/java/com/follow/clash/service/VpnService.kt:125`) and the notification-channel name. |
| 9 | `tool/check_coverage.dart:20-34` | CI only: add a floor for the new `shikoo` group, or the coverage gate fails. |
| — | Branding resources | Adaptive icons `android/app/src/main/res/drawable/ic_launcher_foreground.xml`, `ic_launcher_foreground_tv.xml` and `values/ic_launcher_background.xml`. API 26+ launchers draw them through `mipmap-anydpi-v26/ic_launcher.xml` and `mipmap-television-anydpi-v26/ic_launcher.xml`, so swapping only the bitmaps leaves FlClash's logo. Also the `mipmap-*` bitmaps, `mipmap-xhdpi/ic_banner.png`, and `android/service/src/main/res/drawable/ic_service.xml` and `ic.xml`. Debug builds only: the "FlClash Debug" label at `android/app/src/debug/AndroidManifest.xml:5,9`. |
| D1 | Decision: `lib/common/constant.dart:87` `repository = 'chen08209/FlClash'` | It feeds the update check (`lib/common/request.dart:75`) and its link (`lib/providers/actions/common.dart:140`); today it is only switched off via `autoCheckUpdate: false` (§1). Proposal: no patch, and our own update check comes in roadmap step 8. |
| D2 | Decision: English text outside FlClash's screens | Notification "Stop" (`lib/providers/state/system.dart:197`), native tile toasts (`:199-200`), tile toasts (`lib/manager/tile_manager.dart:34,44`), launcher shortcut "Toggle" (`lib/plugins/app.dart:138-142`). Either accept English in v1, or add `fa` to FlClash's l10n (`arb/intl_fa.arb` plus a regenerated `lib/l10n/`, which conflicts whenever upstream strings change). |

- **Keep the channel names:** `packageName` and `Components.PACKAGE_NAME` stay `com.follow.clash` (`lib/common/constant.dart:18`, `android/common/src/main/java/com/follow/clash/common/Components.kt:6`). They name MethodChannels, not the app.
- **Only if tests demand it:** `constant.dart:55` (the delay timeout), a cleanup of `libs.versions.toml`, and dropping ML Kit and the location permissions (pubspec + 2 Dart files + manifest).
- **For build-engineer:** if `android/app/keystore.jks` and the `local.properties` keys are missing, a release build is silently signed with the debug key and gets `.dev` added to the app id (`android/app/build.gradle.kts:18-25,68-76`).

## Gotchas

- **Consent wait:** while the consent dialog is open, `getRunTime()` stays null. Native `refresh()` returns `runTimeMillis` (`ServiceStateMachine.kt:62-66`), which is set only when the service starts (`:248-249`), after consent (`:229`); Dart maps 0 to null (`lib/plugins/service.dart:93-99`). So the UI needs a "connecting" state with a timeout, not an instant error.
- **Theme:** `ThemeManager` clamps the text scale to 0.8–1.4 (`lib/manager/theme_manager.dart:50-56`, `lib/common/constant.dart:25-26`), makes the system bars transparent and picks the status-bar icon colours by brightness (`theme_manager.dart:19-43`).
- **Build env:** `setup.dart` defaults to `--env pre` (`setup.dart:88-92`). Build with `--env stable` (or `--dart-define=APP_ENV=stable` for a direct build), or `AppEnvManager` shows a "PRE" banner (`lib/manager/app_manager.dart:121-127`).
- **Delay tests in Go:** up to 50 run at once (`core/common.go:41`). A test that times out while queued returns nil, not -1 (`core/hub.go:287-291`), and Dart keeps the previous value (`lib/providers/actions/proxies.dart:306-309`).

## Verdict

**Feasible with 9 small patches:** 1 Dart file (about 3 lines), 7 Android files (one is a deletion) and 1 CI file, plus branding resources. With the `-t` entry point and a direct `flutter build` it is 8, with no Dart patch at all. No FlClash screen is needed.

**Top 3 risks**
1. **The VPN state Flutter sees is optimistic.** Native start failures are not reported back (`ServicePlugin.kt:100-103`, `ServiceStateMachine.kt:229-233`), so our UI must confirm with `service.getRunTime()`, allowing for the consent wait. `AppPlugin.kt:350` may crash on a box without the system VPN dialog; test on the real box.
2. **FlClash UI can still surface.** This means English `StatusManager` toasts in FlClash style (`lib/state.dart:91-92`, `lib/providers/actions/core.dart:32`, `lib/providers/actions/proxies.dart:156`, `lib/manager/vpn_manager.dart:37`), rare dialogs (`lib/bootstrap.dart:162,164`) that by our reading throw under `fa` unless we add the §1 delegate, and the English notification and tile text (D2). For v1 we accept these; later we can build our own stack from the public managers, without `StatusManager` and `VpnManager`.
3. **We depend on internals with no API promise:** provider and action names, auto-dispose timing, and the subscription quirks (the UA from pubspec, the throwing header parser). A rename breaks the build; a behaviour change does not. Upstream lint tests also cover our code: `material_ui` only (`test/lint/design_package_test.dart:12-13`), disposed controllers, icon tooltips, coverage floors. Re-run our provider tests on every upstream merge.

**Not proven yet** (code reading only, nothing run): that the snowflake id is the number we saw; that 16 parallel probes cause the false Timeouts, or that testing one at a time fixes them; that denied consent leaves Flutter saying "running"; that Firebase or Analytics sends anything while the switch is off; the crash on TV; the dialog throw under `fa`; that the panel still returns the Clash format with a different `appName` or version in the UA; how flutter_distributor maps `target=`.
