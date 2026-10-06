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
  a full-screen page replacing Home, its one button focused (on a failed download: «دوباره» first, then «پشتیبانی»);
  the VPN keeps running. No system notification.
- Download only on tap: stream GET with `Range: bytes=<have>-` into `<cache>/update/<file>.part` (206 appends, 200
  restarts, complete skips), sha256 in `Isolate.run`, mismatch deletes and says so, match renames to `.apk`. Progress
  in MB and percent; resumes after a restart; old files cleaned on each check.
- Install: `ShikooUpdate.kt` on channel `shikoo/update`: `canInstall` (true below API 26, else
  `canRequestPackageInstalls()`), `openInstallSettings` (`ACTION_MANAGE_UNKNOWN_APP_SOURCES` with `package:` URI; false
  on `ActivityNotFound`), `install` (FileProvider URI, `ACTION_VIEW`, `GRANT_READ | NEW_TASK`). Manifest:
  `REQUEST_INSTALL_PACKAGES`, provider `${applicationId}.update` → `<cache-path name="update" path="update/"/>`.
  Not PackageInstaller sessions (ceiling: no silent updates).
- HyperOS: if `canInstall` is false, one Persian explainer («turn it on, then press Back»), then the settings page; the
  `resumed` hook re-checks and opens the installer without another tap. Missing settings page (some TVs) → straight to
  `ACTION_VIEW`.
- VPN: check and download go DIRECT. Installing kills the app and its VPN; the explainer says so. No auto-reconnect
  (ceiling; add a `MY_PACKAGE_REPLACED` receiver if customers complain).

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

No code: in each panel, Content → client apps, two rows: «شیکونت — گوشی» → `https://app.chopon.uk/dl/arm64-v8a` and
«شیکونت — تلویزیون و باکس» → `…/dl/armeabi-v7a` (staging: `app-dev`). Links never change between releases.

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
- Android 7.1.1: FileProvider + `ACTION_VIEW` on an API 25 emulator.

## Risks

- Upload speed from GitHub runners to the Iranian box is unmeasured (chunks cover proxy and Node timeouts).
- A national cut: `app.chopon.uk` must still resolve, and its certificate cannot renew during a long cut (same as
  sign-in). Lever: a second base in `shikooApiBases`; `apiDirectRule` already handles an IP.
- No download rate limit on `/dl` (ceiling: add a per-address cap if the box saturates).
