# In-app update and APK delivery

Approved by the conductor 2026-10-06 (Sam: «شروع کن»). Defaults below stand until Sam says otherwise.

## Facts the design rests on

- FlClash's own GitHub update check is already off: `lib/shikoo/app/app.dart` writes `autoCheckUpdate: false` before
  `bootstrap.attach()`, and FlClash's About page is never mounted. No upstream edit needed.
- No FileProvider exists (FlClash removed it in `ed78682`); `openFile()` in `lib/plugins/app.dart` is a dead stub.
- Reusable: `dio` via `ShikooApi` (`lib/shikoo/engine/account.dart`, base failover), `crypto`, `path_provider`,
  `package_info_plus` (`buildNumber` = installed versionCode), `Abi.current()` from `dart:ffi`, and `keepApiDirect()`
  (files served from the app-door host need no new tunnel rule).
- Platform: `/api/v1/app/*` has `bodyLimit(1024)` and `no-store`, so uploads cannot live there. `serveStatic` from
  `@hono/node-server` answers `Range` with 206. The bot's `client_apps` table (panel Content page) already lists apps.
- Telegram Bot API upload cap is 50 MB; one APK is about 52 MB. Telegram is also blocked in Iran.

## Design: the app door serves its own APKs from a persistent volume

Reachable from Iran without a VPN (the app already reaches this host DIRECT); serving survives a national cut,
publishing waits for it to end. Rejected: a separate static Coolify app (same upload problem, a second host), Telegram
(blocked, 50 MB cap), public GitHub releases (dead during a cut).

### Door API (`apps/ingest-worker/src/appRelease.ts`, `ok` envelopes, ISO dates)

- `GET /api/v1/app/update` — public, `no-store`, reads one file, no database:
  `{ok:true, version_name:"1.0.57", published_at:"<ISO>", apks:{"arm64-v8a":{version_code:2057,
  min_version_code:2050, size:54321000, sha256:"…", url:"/dl/ShikooNet-1.0.57-arm64-v8a.apk"}, "armeabi-v7a":{…}}}`.
  Before the first publish: `404 {ok:false,error:"no_release"}`.
- `GET /dl/<file>.apk` — `serveStatic` with Range, `application/vnd.android.package-archive`,
  `Cache-Control: public, max-age=31536000, immutable`. Versioned names, never rewritten.
- `GET /dl/<abi>` — 302 to the current file; the stable link for the bot and a website.
- `PUT /dl/upload/<file>?offset=N` — `Authorization: Bearer RELEASE_TOKEN`, at most 16 MB per request. Offset 0
  truncates; N up to the current size writes at N; a larger N gives `409 {error:"offset", size}`. Idempotent.
- `POST /dl/publish` — Bearer. Body `{version_name, force, apks:[{abi, file, version_code, sha256}]}` (zod, strict).
  Hashes every file (mismatch → 422, nothing changes), moves files into place, sets `min_version_code` to the new
  `version_code` when `force`, else keeps the previous (or 0), writes `update.json` via tmp+rename, prunes files that
  neither the new nor the previous manifest references. Idempotent.
- Token: compare sha256 digests with `timingSafeEqual`; a wrong token is charged like `unauthorized` today. Without
  `RELEASE_TOKEN` the upload routes answer 404 and downloads still work. The app holds no secret.

### App

- `ShikooUpdate.check()` (`lib/shikoo/engine/update.dart`), called where `signIn.onForeground()` is (start, resume) and
  from the 1-minute TV timer; returns at once unless 6 hours passed since the last success. Goes through `ShikooApi`, so
  staging installs update from app-dev and production from app.
- ABI from `Abi.current()`; own code from `packageInfo.buildNumber`. Offer when own < `version_code`; force when own <
  `min_version_code`. Local builds (2026091401) are never offered one.
- UI: a card at the top of Home (phone and TV), D-pad reachable, never takes first focus from the power button. Forced:
  a full-screen page replacing Home; «پشتیبانی» sits beside the focused button in every state that can trap a customer
  (failed or broken download, no space, ready to install, installer did not open). The VPN keeps running. No system
  notification on phones and TVs; Windows has one, below.
- Download only on tap: stream GET with `Range: bytes=<have>-` into `<cache>/update/<file>.part` (206 appends, 200
  restarts, complete skips), sha256 in `Isolate.run`, mismatch deletes and says so, match renames to `.apk`. Progress
  in MB and percent; resumes after a restart; old files cleaned on each check.
- Install: `ShikooUpdate.kt` on channel `shikoo/update`: `canInstall` (below API 26 the global «Unknown sources»
  switch `INSTALL_NON_MARKET_APPS`, else `canRequestPackageInstalls()`), `openInstallSettings` (below API 26
  `ACTION_SECURITY_SETTINGS`, else `ACTION_MANAGE_UNKNOWN_APP_SOURCES` with `package:` URI; false on
  `ActivityNotFound`), `install` (FileProvider URI, `ACTION_VIEW`, `GRANT_READ | NEW_TASK`). Manifest:
  `REQUEST_INSTALL_PACKAGES`, provider `${applicationId}.update` → `<cache-path name="update" path="update/"/>`.
  Not PackageInstaller sessions (ceiling: no silent updates).
- HyperOS: if `canInstall` is false, one Persian explainer («turn it on, then press Back»), then the settings page; the
  `resumed` hook re-checks and opens the installer without another tap. Missing settings page (some TVs) → straight to
  `ACTION_VIEW`.
- VPN: check and download go DIRECT. Installing kills the app and its VPN; the explainer says so. No auto-reconnect
  (ceiling; add a `MY_PACKAGE_REPLACED` receiver if customers complain).

### Windows (`win/updater`)

- Entry `apks["windows-x64"]` (`Abi.windowsX64`; Windows on Arm has no entry and gets nothing). Its own
  `version_name` wins over the manifest's, which a Windows-only publish leaves at the Android version. Own code:
  `packageInfo.buildNumber`, the `+N` of the exe's ProductVersion (`--build-number`).
- The 1-minute timer checks with the window closed beside the clock too (`check(hidden: true)`); there a failed check
  waits `hiddenRetryEvery` (15 minutes) instead of a minute, so the card is ready when the window opens.
- Telling a closed window (Sam's «ج۱», `win-wave3/design/update-notice/variants.html`): while an offer stands, the menu
  beside the clock heads its rows with «نسخهٔ تازه آمده», which opens the window on Home with the card in view. A
  `version_code` new to this run, found while the window is hidden or minimized, also sends Windows' message from the
  tray icon (`_balloon`, the close notice's), once per version (`shikoo.updateNoticed` holds the last one), unless Settings ›
  Windows › «خبر نسخهٔ تازه با پیام ویندوز» is off (`shikoo.updateNotice`, on by default). A click on the message
  opens the window as the menu row does (`NIN_BALLOONUSERCLICK`, SHIKOO_PATCHES `tray_plugin.cpp`). The message has
  no buttons, so its text points at that switch; Windows hides it under Do not disturb or with notifications off,
  and the menu row stays.
- Seal (Sam: the Android signing keys, no key of its own): `sig` is base64 RSA PKCS#1 v1.5 over SHA-256, as
  `openssl dgst -sha256 -sign` makes it, of the ASCII `shikoonet-windows-update:<version_code>:<sha256 lowercase hex>`.
  The prefix keeps it apart from anything else the Android key signs; the number keeps an old build's seal off a newer
  one. The core's `checkSeal` (`core/shikoo_seal.go`: `x509.ParsePKIXPublicKey`, RSA of 2048 bits or more,
  `rsa.VerifyPKCS1v15`) checks it against `windowsSealKeyProduction` (`CN=ShikooNet`, RSA 4096) or
  `windowsSealKeyStaging` (`CN=ShikooNet Staging`, RSA 2048) in `lib/shikoo/engine/update.dart`: base64
  SubjectPublicKeyInfo, one line each, which CI greps. The key goes with the door: a build given `SHIKOO_API` (staging,
  or a local test) takes the staging key. No `sig`, or a wrong one: not offered at all (so never forced), one diag
  line `update <code> not sealed`. A core that does not answer fails the check as the network, asked again within a
  minute.
- Download as on Android, to `<cache>/update/<sha256>.exe` (`%LOCALAPPDATA%\ShikooNet\ShikooNet\update`).
- Install, one at a time: hash the file and check the seal while still connected (a refused seal leaves the
  connection alone), then the controller's `disconnect()`, then hash the file again synchronously and start the Inno
  installer with `/SILENT /SUPPRESSMSGBOXES /NORESTART` with no `await` in between. Any program of the user can write
  the cache, and the installer runs as admin. A small window remains: one turn of Dart's event loop, as `Process.start`
  hands the start to `Timer.run`, then Windows opening the file; only Authenticode signing closes it.
- A file gone, unreadable or changed at either hash (antivirus quarantine or lock, a cleaner, a check that dropped the
  release meanwhile) is a damaged one: deleted if it can be, so the next tap downloads it again, and the card says
  `checksum`. At the first hash the connection is left alone; at the second it comes back as below. Unlike Android,
  Windows has no separate «file gone» check before it. The hash reads the file itself rather than through `openRead`,
  whose failed read never closes the file and would keep it from being deleted.
- The loader is `asInvoker` and raises the UAC prompt itself;
  `PrepareToInstall` kills `ShikooNet.exe`, so the loader exiting while the app still runs means it did not install
  (UAC refused, or Windows would not start it): the connection comes back if it was on and nothing turned it on since,
  and the card shows `updateInstallFailed`. No Android permission dialog. Relaunch after a silent install is the
  installer's `[Run]` entry with `skipifnotsilent` (`win/brand`).

### Pipeline (`chore/release-pipeline`)

- `tools/publish_door.sh <api> <dir> <force>`: sha256 from `SHA256SUMS`, versionCodes from `aapt2 dump badging`,
  8 MB chunks with `curl --fail-with-body --retry 5 --retry-all-errors`, then publish with `jq`-built JSON.
- Staging: a separate job `door` after `build` (re-runnable without a rebuild): download the `-staging-` APKs from
  `staging-$VN`, `sha256sum -c`, publish to the staging door with `force=false`.
- Promote: new input `force` (`no`/`yes`). Door step after `sha256sum -c`, before `gh release create`; if it fails,
  nothing is published anywhere.
- Secrets `SHIKOO_STAGING_DOOR_TOKEN` and `SHIKOO_PRODUCTION_DOOR_TOKEN` = `RELEASE_TOKEN` on `shikoo-dev-app` /
  `shikoo-prod-app`. Update `docs/release-pipeline.md` §3, §4, §7, §8.

### Bot

No code: in each panel, Content → client apps, three rows: «شیکونت — گوشی» → `https://app.chopon.uk/dl/arm64-v8a`,
«شیکونت — تلویزیون و باکس» → `…/dl/armeabi-v7a`, and «شیکونت — کامپیوتر» (platform Windows) → `…/dl/windows-x64`
(staging: `app-dev`). Links never change between releases. Before the Windows row is added, shikoo-platform PR #770 must
be deployed on both doors.

## Defaults (conductor, until Sam objects)

1. Forced updates through a `force` input on Promote, default `no`.
2. Download only when the user taps.
3. Check at start and resume, at most once every 6 hours.
4. Promote fails if the production door is missing or unreachable (so `shikoo-prod-app` with its volume and
   `RELEASE_TOKEN` must exist before the first Promote).
5. Bot: panel rows only.
6. After an update the VPN stays off until the app is reopened.
7. Volume `/data/apk`, env `APK_DIR`, `RELEASE_TOKEN`: the conductor sets them on `shikoo-dev-app` via the Coolify API;
   production is created with Sam.

## Work packages

| WP | Where | Size | Depends on |
|---|---|---|---|
| 1 Door | shikoo-platform: new `appRelease.ts`, `appServer.ts`, `index.ts` (Env), `Dockerfile` (`mkdir -p /data/apk && chown node:node` before `USER node`), new `test/app-release.test.ts`, `docs/configuration-matrix.md` | M | — |
| 2 App engine | `feat/app`: new `lib/shikoo/engine/update.dart`, `account.dart` (`ShikooApi.update()`, relative URL against the base that answered), `lib/shikoo/app/app.dart` hooks, new `test/shikoo/update_test.dart` | M | WP1 only for end to end |
| 3 Android install | `feat/app`: new `ShikooUpdate.kt`, `MainActivity.kt` (one line), `AndroidManifest.xml`, new `res/xml/update_paths.xml`, `SHIKOO_PATCHES.md` rows | S | — |
| 4 UI | design frames first, then `lib/shikoo/ui/update.dart`, `home.dart`, arbs | M | WP2 state shape |
| 5 Pipeline | `tools/publish_door.sh`, `shikoo-staging.yml`, `shikoo-promote.yml`, `docs/release-pipeline.md` | S | WP1 contract |

## Must be proven on a real device

- Poco C85 (HyperOS, Android 15, font 1.45): no overflow on card, explainer and forced page; unknown-apps page opens
  for our package, Back returns, the installer opens by itself; Xiaomi's installer does not block; the sign-in token
  survives; download with the VPN on completes; airplane mode mid-download resumes; reconnect after update works.
- Mi Box (Android 9, 32-bit): v7a chosen; the settings intent or its fallback works; the installer works by remote;
  enough cache for 52 MB plus the installer's copy; sha256 time on its CPU; D-pad reaches the card.
- Android 7.1.1: FileProvider + `ACTION_VIEW` on an API 25 emulator. Proven 2026-10-07 (`5481948`, offer and forced,
  Unknown sources off → security page → Back → installer). Still open: an Android 7 TV or box.

## Risks

- Upload speed from GitHub runners to the Iranian box is unmeasured (chunks cover proxy and Node timeouts).
- A national cut: `app.chopon.uk` must still resolve, and its certificate cannot renew during a long cut (same as
  sign-in). Lever: a second base in `shikooApiBases`; `apiDirectRule` already handles an IP.
- No download rate limit on `/dl` (ceiling: add a per-address cap if the box saturates).
