# وصله‌های شیکو روی FlClash

این مخزن فورک FlClash است (پایه: `v0.8.98`، کامیت `7c61c90`). هر تغییری در فایل‌های خود FlClash این‌جا ثبت می‌شود تا ادغام نسخه‌های تازهٔ FlClash ساده بماند.
فایل‌هایی که فقط مال شیکو هستند (`lib/shikoo/`، `design/`، `docs/`، `tools/`، `.claude/agents`، `.claude/skills`، `.claude/CLAUDE.md`) این‌جا نمی‌آیند.

| # | فایل FlClash | تغییر | چرا |
|---|---|---|---|
| ۱ | `CLAUDE.md` | یک خط آخر: `@.claude/CLAUDE.md` | راهنمای شیکو کنار `AGENTS.md` خود FlClash خوانده شود. اسناد Claude Code نمی‌گویند وقتی هر دو فایل هستند، هر دو خوانده می‌شوند یا نه. |
| ۲ | `pubspec.yaml`، `pubspec.lock` | وابستگی تازهٔ `qr: ^4.0.0` (با `flutter pub add qr`) | QR «تمدید» و «پشتیبانی» تلویزیون. FlClash و وابستگی‌هایش سازندهٔ QR ندارند (`mobile_scanner` فقط می‌خواند). `qr` خالص Dart است، مجوز BSD-3، و جز `meta` وابستگی ندارد. |
| ۳ | `android/app/src/main/kotlin/com/follow/clash/plugins/AppPlugin.kt` | `startActivityForResult` پنجرهٔ اجازهٔ VPN داخل try/catch؛ اگر پنجره نبود یا کاربر رد کرد، پیام `vpnConsent` (`missing` یا `refused`) به Dart می‌رود. | باکس‌هایی که پنجرهٔ اجازه ندارند کرش نکنند، و اپ رد شدن اجازه را بفهمد. شروع سرویس خوش‌بینانه است و این خبر را به Dart نمی‌داد. |
| ۴ | `lib/plugins/app.dart` | `onVpnConsent` و `case 'vpnConsent'` در گیرندهٔ کانال. | پیام وصلهٔ ۳ به کنترل‌گر شیکو برسد. |
| ۵ | `android/settings.gradle.kts`، `android/app/build.gradle.kts`، `android/common/build.gradle.kts`، `android/gradle/libs.versions.toml`، `android/app/google-services.json` | افزونه‌های `com.google.gms.google-services` و `com.google.firebase.crashlytics`، وابستگی‌های `firebase-bom`، `firebase-crashlytics-ndk` و `firebase-analytics`، و نام‌هایشان در فهرست نسخه‌ها حذف شدند. `google-services.json` (پروژهٔ جای‌نگه‌دار `dev`) پاک شد. | حذف Firebase، تصمیم Sam: اپ نه Firebase را راه بیندازد، نه به آن وصل شود، نه کتابخانه‌اش را داشته باشد. ارسال `mapping.txt` هنگام ساخت هم با افزونه می‌رود. |
| ۶ | `android/common/src/main/java/com/follow/clash/common/GlobalState.kt` | importهای Firebase رفت. `setCrashlytics` کاری نمی‌کند و `didCrashOnPreviousExecution()` همیشه `false` می‌دهد. | صدازننده‌ها (`ServiceStateHost.kt`، `ServiceStateMachine.kt`، `AppPlugin.kt` و کانال Dart) و تست‌هایشان بی‌وصله بمانند. سمت Dart دست نخورد: `crashlytics` در شیکو `false` است و `bootGuard` بدون آن کاوشگر کار می‌کند. |
| ۷ | `android/settings.gradle.kts` | یک خط دیگر: `project(":mobile_scanner").projectDir = file("shikoo/mobile_scanner")`. | اسکنر QR فلکلش (تصمیم رهبر، ۲۰۲۶-۱۰-۰۴): بخش اندرویدیِ پلاگین `mobile_scanner` با یک پلاگین خالی عوض می‌شود. پس ML Kit، کتابخانه‌های Google datatransport (که آمار ML Kit را به گوگل می‌فرستند)، کتابخانه‌های دوربین androidx و مجوز `CAMERA` داخل APK نمی‌آیند. کد Dart فلکلش (`lib/pages/scan.dart`، `lib/common/picker.dart`) و تستش دست نخوردند؛ شیکو آن صفحه‌ها را باز نمی‌کند. |
| ۸ | `android/app/src/main/AndroidManifest.xml` | سه خط `tools:node="remove"` برای `ACCESS_COARSE_LOCATION`، `ACCESS_FINE_LOCATION` و `ACCESS_BACKGROUND_LOCATION`. | این‌ها از پلاگین `plugins/wifi_ssid` می‌آمدند، برای قاعدهٔ «Wi-Fiهای مستثنا» در صفحهٔ on-demand فلکلش. شیکو آن صفحه را ندارد، پس `excludeSSIDs` خالی می‌ماند و اپ هیچ‌وقت اجازه نمی‌خواهد. هزینه: اگر روزی آن قاعده لازم شد، `getSsid` همیشه `null` می‌دهد و درخواست اجازه بی‌پنجره رد می‌شود. |
| ۹ | `android/common/src/main/res/values/strings.xml` | `app_name` از `FlClash` به `ShikooNet`. نسخهٔ فارسی، «شیکونت»، در فایل تازهٔ `values-fa/strings.xml` کنار آن است. | اسم اپ، تصمیم Sam (۲۰۲۶-۱۰-۰۴). همین متن برچسب اپ در منوی دستگاه، کاشی تنظیمات سریع، پنجرهٔ اجازهٔ VPN و نام نشست VPN (`VpnService.kt:125`) است. `service_channel_name` («FlClash Service»، نام کانال اعلان) دست نخورد؛ منابع خود ماژول اپ آن را override می‌کنند (جدول فایل‌های تازه، پایین). `applicationId`: وصلهٔ ۱۱. |
| ۱۰ | `android/app/src/main/AndroidManifest.xml` | `android:allowBackup="false"` روی `<application>`. | پیش‌فرض اندروید پشتیبان‌گیری است: داده‌های خصوصی اپ به `adb backup` و پشتیبان ابری گوگل می‌رفت. توکن ورود شیکو (`shikoo.account` در SharedPreferences) و لینک‌های اشتراکی که خود فلکلش نگه می‌دارد، هر دو رمز دسترسی‌اند و نباید بیرون از دستگاه کپی شوند. هزینه: با عوض کردن گوشی، ورود و سرویس‌ها منتقل نمی‌شوند و مشتری دوباره با تلگرام وارد می‌شود. |
| ۱۱ | `android/app/build.gradle.kts` | `applicationId` از `com.follow.clash` به `com.shikoonet.app`. منطق `.dev` خود FlClash دست نخورد: ساختِ بی‌کلید امضای اصلی `com.shikoonet.app.dev` می‌شود. `namespace`، بسته‌های Kotlin، `Components.PACKAGE_NAME` و `packageName` در `lib/common/constant.dart` همان `com.follow.clash` ماندند. | شناسهٔ دائمی، تصمیم Sam (۲۰۲۶-۱۰-۰۶). بعد از اولین نصب واقعی دیگر عوض‌شدنی نیست. آن دو ثابت نام کلاس‌ها (`ComponentName`) و نام کانال‌های Flutter را می‌سازند، نه شناسهٔ اپ را. هر چه به شناسه بسته است از آن مشتق می‌شود: `${applicationId}` در مانیفست‌ها (اکشن‌ها، مجوز broadcast، authority فایل‌ها) و `packageName` زمان اجرا در `Ext.kt` و `GlobalState.kt`. هزینه: نصب‌های قدیمی `com.follow.clash(.dev)` جدا می‌مانند و داده‌شان منتقل نمی‌شود. |
| ۱۲ | `lib/providers/state/system.dart` (و خط hash در `lib/providers/generated/state.g.dart`)، `lib/manager/tile_manager.dart`، `lib/manager/android_manager.dart`، `lib/plugins/app.dart` (فایل وصلهٔ ۴) | یک قلاب تازه کنار `sharedState`: `serviceTexts`، که برای زبانِ بارشده (`loadedLocaleProvider`) چهار متن می‌دهد. اگر پر باشد، دکمهٔ اعلان (`stopText`) و دو toast سرویس (`startTip`، `stopTip`) از آن می‌آیند، وگرنه همان متن‌های FlClash. toastهای کاشی (`tile_manager.dart`) همان دو متن را از `sharedStateProvider` می‌خوانند. برچسب میان‌بُر لانچر هم از آن می‌آید: `initShortcuts([label])` در `app.dart`. `lib/shikoo/app/app.dart` میان‌بُر را با هر باز شدن اپ ثبت می‌کند و `android_manager.dart` با هر تغییر زبان. شیکو قلاب را در `lib/shikoo/app/main.dart` با `shikooServiceTexts` (`lib/shikoo/engine/settings.dart`) پر می‌کند. | ترجمه‌های FlClash فارسی ندارند و شیکو همیشه انگلیسی‌شان را بار می‌کند. پس اعلان «Stop»، toastهای کاشی «Starting VPN...» و میان‌بُر «Toggle» نشان می‌داد. متن‌ها از `lib/shikoo/l10n/` و به زبان اپ می‌آیند. `LocaleManager` زبانِ `ShikooApp` را در `loadedLocaleProvider` می‌گذارد؛ این زبان `sharedState` را دوباره می‌سازد، `AndroidManager` آن را به سرویس می‌فرستد (`android_manager.dart:38-45`) و میان‌بُر را دوباره ثبت می‌کند (`:33-37`). hash را `build_runner` می‌سازد؛ در ادغام، کد تولیدی را دوباره بساز. |
| ۱۳ | `android/app/src/main/kotlin/com/follow/clash/ServiceStateMachine.kt`، `android/app/src/main/kotlin/com/follow/clash/plugins/AppPlugin.kt` (فایل وصلهٔ ۳)، `android/tests/app/ServiceStateMachineTest.kt` | **ساعت غلط.** در `ServiceStateMachine.kt` دو ثابت تازه آمده: `CLOCK_FLOOR_MILLIS` (۲۰۲۶-۰۹-۰۱) و `CLOCK_WRONG_MESSAGE` (toast فارسی). `loadPreferencesAndStart` اگر ساعت از کف کمتر باشد، پیش از `setupCore` همان toast را نشان می‌دهد و هسته را راه نمی‌اندازد. ساعتش را از پارامتر تازهٔ سازنده می‌گیرد، `nowMillis` (پیش‌فرض `System::currentTimeMillis`)، تا تست تازهٔ `handleStartAction on a clock before the floor never sets the core up` (۱۲ خط در `android/tests/app/ServiceStateMachineTest.kt`) زیر کف شروع کند و ببیند هسته راه نیفتاده است. در `AppPlugin.kt` کار تازهٔ `openDateSettings` آمده: اول `Settings.ACTION_DATE_SETTINGS` را باز می‌کند، و اگر نبود، `Settings.ACTION_SETTINGS`. | هستهٔ Go با ساعت پیش از حدود ۲۰۱۲-۰۷ همان لحظهٔ بار شدن `libcore.so` کرش می‌کند (`core/Clash.Meta/transport/xhttp/browser.go:71`، از `init()`). اپ این را در `lib/shikoo/app/main.dart` پیش از بار شدن هسته می‌گیرد. ولی کاشی تنظیمات سریع، میان‌بُر لانچر، broadcast `VPN_START_REQUESTED` و VPN همیشه‌روشن بی Dart از همین تابع به `quickSetup` می‌رسند. کف با `shikooClockFloor` در `lib/shikoo/engine/clock.dart` جفت است و `test/shikoo/clock_test.dart` برابری‌شان را می‌سنجد. FlClash کانالی برای صفحهٔ تاریخ و ساعت نداشت. هزینه: toast همیشه فارسی است، چون ماشین وضعیت زبان اپ را نمی‌داند. |
| ۱۴ | `android/app/src/main/kotlin/com/follow/clash/MainActivity.kt` | یک خط: `ShikooUpdate.attach(this, flutterEngine)`. | کانال `shikoo/update` به‌روزرسانی داخل اپ (`docs/app-update.md`): اجازهٔ نصب، صفحهٔ «نصب برنامه‌های ناشناس» اندروید، و باز کردن نصب‌کننده. خود کد در فایل تازهٔ `ShikooUpdate.kt` است. |
| ۱۵ | `android/app/src/main/AndroidManifest.xml` | مجوز `REQUEST_INSTALL_PACKAGES`، و یک `provider` از `androidx.core.content.FileProvider` با authority `${applicationId}.update` و مسیرهای `@xml/update_paths`. | بی این مجوز، اندروید ۸ به بالا اجازهٔ نصب را حتی نمی‌پرسد. FileProvider فایل APK دانلودشده در `<cache>/update/` را فقط برای خواندن به نصب‌کننده می‌دهد (اندروید ۷ به بالا مسیر `file://` را نمی‌پذیرد). نام کلاس `FileProvider` با provider زیرکلاس‌شدهٔ `image_picker` تداخل ندارد. `check_apk_clean.sh` این مجوز را رد نمی‌کند. |
| ۱۶ | `lib/manager/status_manager.dart` | دو خط در `build`: حاشیهٔ چپ و راستِ پیام‌ها از `MediaQuery.viewPaddingOf(context)`، کنار همان `top` که از قبل `viewPadding` را می‌خواند. | پیام‌های FlClash (مثل «config is not applied») در اپ شیکو دیده می‌شوند؛ در فارسی سمت چپ، چون ستونشان `crossAxisAlignment.end` است. روی تلویزیون، `ShikooTvCanvas` (`lib/shikoo/ui/theme.dart`) حاشیهٔ امن را به `viewPadding` اضافه می‌کند؛ بالا را خود FlClash رعایت می‌کرد و پهلوها را نه، و پیام ۴dp از لبه می‌ماند. روی گوشیِ ایستاده `viewPadding` پهلو صفر است و چیزی عوض نمی‌شود. |

## نکته‌ها

- `.gitignore` خود FlClash پوشهٔ `docs/` را نادیده می‌گیرد. برای اینکه به آن دست نزنیم، یادداشت‌های شیکو با `git add -f docs/...` اضافه می‌شوند. فایل‌هایی که یک بار اضافه شده‌اند، بعد عادی دنبال می‌شوند.
- `.gitattributes` فایل تازهٔ شیکو است، نه وصله: همهٔ متن‌ها با پایان خط LF، تا اسکریپت‌ها داخل WSL هم درست اجرا شوند.
- `.github/workflows/build.yaml` خود FlClash با هر push اجرا می‌شود. GitHub Actions در این مخزن خاموش است تا CI خود شیکو ساخته شود.
  آن فایل `google-services.json` را از راز `SERVICE_JSON` می‌سازد (`:280`)؛ CI شیکو این گام را نمی‌خواهد.
- **ادغام FlClash و وصلهٔ ۵:** FlClash نسخهٔ `firebaseBom` و دو افزونه را گاهی بالا می‌برد و آن‌جا تداخل پیش می‌آید. حذف ما را نگه دار.
- **ادغام FlClash و وصلهٔ ۷:** اگر FlClash `mobile_scanner` را بردارد، خط وصله با `UnknownProjectException` می‌شکند؛ آن خط و `android/shikoo/mobile_scanner/` را پاک کن. اگر نام کلاس یا بستهٔ پلاگین عوض شود، `GeneratedPluginRegistrant.java` کامپایل نمی‌شود؛ کلاس پلاگین خالی را هم‌نام کن.
- **سنجه:** بعد از هر ساخت، و حتماً بعد از هر ادغام FlClash: `bash tools/check_apk_clean.sh build/app/outputs/flutter-apk/app-*-release.apk`.
  اگر Firebase، Crashlytics، ML Kit، datatransport، دوربین androidx یا Google Play services (یا اجزای مانیفستشان)، یا مجوزهای تبلیغ، دوربین یا موقعیت برگشته باشند، رد می‌شود و آن‌ها را نام می‌برد.
- **مجوزهایی که با وصله‌های ۵ تا ۸ رفتند:**
  - با ۵: `com.google.android.gms.permission.AD_ID`، `android.permission.ACCESS_ADSERVICES_AD_ID`، `android.permission.ACCESS_ADSERVICES_ATTRIBUTION`، `com.google.android.finsky.permission.BIND_GET_INSTALL_REFERRER_SERVICE`، `android.permission.WAKE_LOCK`، و کتابخانهٔ `android.ext.adservices`. خود FlClash هیچ wake lock نمی‌گیرد.
  - با ۷: `android.permission.CAMERA`.
  - با ۸: `ACCESS_COARSE_LOCATION`، `ACCESS_FINE_LOCATION`، `ACCESS_BACKGROUND_LOCATION`، و ویژگی ضمنی `android.hardware.location`.
- **اجزای مانیفست که با وصله‌های ۵ و ۷ رفتند:**
  - با ۵: `com.google.firebase.provider.FirebaseInitProvider`، `com.google.firebase.components.ComponentDiscoveryService` با ثبت‌کننده‌های Crashlytics، Analytics، Sessions و Installations، `com.google.firebase.sessions.SessionLifecycleService`، و `com.google.android.gms.measurement.AppMeasurementService`، `AppMeasurementReceiver` و `AppMeasurementJobService`.
  - با ۷: `com.google.mlkit.common.internal.MlKitInitProvider`، `MlKitComponentDiscoveryService`، `com.google.android.datatransport.runtime.backends.TransportBackendDiscovery`، `JobInfoSchedulerService`، `AlarmManagerSchedulerBroadcastReceiver`، `com.google.android.gms.common.api.GoogleApiActivity`، meta-data `com.google.android.gms.version`، و `androidx.camera.core.impl.MetadataHolderService`.
- **کد Dart اسکنر داخل APK نیست:** ورودی شیکو به `lib/pages/scan.dart` و `lib/common/picker.dart` نمی‌رسد، پس کامپایلر Dart آن را دور می‌ریزد. نام کانال‌های اسکنر (`dev.steenbakker.mobile_scanner`) در `libapp.so` صفر بار آمده است (سنجش ۲۰۲۶-۱۰-۰۴).
- **چیزهای گوگل یا Firebase که در APK مانده‌اند** (سنجش ۲۰۲۶-۱۰-۰۴):
  - `uses-feature android.hardware.camera` با `required="false"` در مانیفست خود FlClash (`android/app/src/main/AndroidManifest.xml:8-10`). این مجوز نیست.
  - سرویس غیرفعال `com.google.android.gms.metadata.ModuleDependencies` با `photopicker_activity:0:required` از `image_picker`. کلاسی ندارد و فقط از Google Play services نسخهٔ پشتیبان «انتخاب عکس» را می‌خواهد.
  - کتابخانهٔ رابط کاربری Material Components (`com.google.android.material`). شبکه ندارد.
  - متن‌های ترجمهٔ FlClash دربارهٔ Firebase (`dataCollectionContent`) و کلید `crashlytics` تنظیمات FlClash، به شکل متن و دادهٔ بی‌کار.

## ساختن اپ شیکو

اپ شیکو جز وصله‌های بالا فایلی از FlClash را عوض نمی‌کند. ورودی‌اش `lib/shikoo/app/main.dart` است و با `-t` ساخته می‌شود:

```bash
source ~/android-toolchain/env.sh
flutter build apk -t lib/shikoo/app/main.dart --split-per-abi --target-platform android-x64,android-arm \
  --dart-define=APP_ENV=stable                 # نسخهٔ آزمایشی: --dart-define=SHIKOO_DEBUG=true هم
bash tools/check_apk_clean.sh build/app/outputs/flutter-apk/app-*-release.apk
```

- `dart setup.dart android` همچنان اپ خود FlClash را می‌سازد. برای اینکه آن هم اپ شیکو بسازد، یا `setup.dart` وصله می‌خورد (و دو تست `test/setup_test.dart`)، یا `lib/main.dart`. فعلاً لازم نیست.
- ترجمه‌ها: `lib/shikoo/l10n/*.arb`. بعد از هر تغییر: `bash tools/shikoo-l10n.sh` (پوشهٔ `generated/` را می‌سازد).

**فایل‌های تازهٔ شیکو داخل پوشه‌های FlClash** (فایلی از FlClash عوض نشده؛ در ادغام تداخلی نمی‌سازند):

| فایل | چرا |
|---|---|
| `assets/fonts/Vazirmatn-{Regular,Medium,Bold,ExtraBold}.ttf` | فونت وزیرمتن داخل APK. `assets/fonts/` در `pubspec.yaml` خود FlClash از قبل بسته‌بندی می‌شود، پس pubspec دست نخورد. با `FontLoader` بار می‌شود. |
| `assets/fonts/Vazirmatn-OFL.txt` | متن مجوز OFL، همراه فونت. |
| `test/shikoo/` | تست‌های شیکو: مرز import لایهٔ UI، و منطق وضعیت اتصال. |
| `android/shikoo/mobile_scanner/` (`build.gradle.kts` و `MobileScannerPlugin.java`) | پلاگین خالیِ جایگزین `mobile_scanner` روی اندروید (وصلهٔ ۷). هم‌نام کلاسی است که `GeneratedPluginRegistrant` ثبت می‌کند. |
| `android/common/src/main/res/values-fa/strings.xml` | اسم فارسی اپ، «شیکونت»، برای دستگاهی که زبانش فارسی است (وصلهٔ ۹). |
| `android/app/src/main/res/values/strings.xml`، `android/app/src/main/res/values-fa/strings.xml` | نام کانال اعلان (`service_channel_name`): «ShikooNet» و «شیکونت». منابع ماژول اپ بر منابع کتابخانهٔ `common` مقدم‌اند، پس «FlClash Service» خود FlClash بی‌وصله کنار می‌رود. اندروید کانال را فقط بار اول می‌سازد (`Ext.kt:65-72`)، به زبان دستگاهِ همان لحظه. نصبی که کانالش را از قبل دارد، اسم قبلی را نگه می‌دارد تا اپ پاک و دوباره نصب شود یا داده‌اش پاک شود. |
| `android/app/src/main/kotlin/com/follow/clash/ShikooUpdate.kt` | کانال `shikoo/update` (وصلهٔ ۱۴): `canInstall`، `openInstallSettings` و `install`. زیر اندروید ۸ یک کلید «منابع ناشناس» (`Settings.Secure.INSTALL_NON_MARKET_APPS`) برای همهٔ اپ‌هاست، پس صفحهٔ `ACTION_SECURITY_SETTINGS` باز می‌شود. سمت Dart: `lib/shikoo/engine/update.dart`. |
| `android/app/src/main/res/xml/update_paths.xml` | تنها مسیری که FileProvider وصلهٔ ۱۵ می‌دهد: `<cache>/update/`. |

**منبع فونت:** `rastikerdar/vazirmatn` تگ `v33.003`، مسیر `fonts/ttf/`. شناسهٔ گیتِ هر فایل با API گیت‌هاب یکی بود.

| فایل | sha256 |
|---|---|
| `Vazirmatn-Regular.ttf` | `b69fd4c680b8f3f225feabcc655a2c585d97627b8f5f5c0f9985e894069f3a56` |
| `Vazirmatn-Medium.ttf` | `b986623e4ddef10755e04be39f8ea7bcb1dc08bfe8dd0aa6af395736f256ad4a` |
| `Vazirmatn-Bold.ttf` | `f635fdbea28f265de395ba83b4b1570dcf2f58d13c65469e61903b1c2d2ae723` |
| `Vazirmatn-ExtraBold.ttf` | `5181c2e436cf1d5cf1c5631821b43d81881dca040a12c9a442ef5dc0007001cf` |
| `Vazirmatn-OFL.txt` (از `OFL.txt`) | `17e355067c8284f47743a1ee3b1ef7ff684ff0601eda357f9353b10b3016ab31` |

**کپی‌هایی که با ادغام FlClash باید دستی هم‌گام شوند:**
- `lib/shikoo/app/main.dart` تکرار `lib/main.dart` است، با `ShikooApp` به‌جای `Application`.
- `lib/shikoo/ui/focus.dart` کپی `lib/widgets/focus.dart` است، تا UI شیکو هرگز FlClash را import نکند.
- `lib/shikoo/app/app.dart` همان کارهای `ApplicationState` در `lib/application.dart` را تکرار می‌کند (`attach`، تایمر ۲۰ دقیقه‌ای، کار تغییر شبکه، `initShortcuts`).

**وصله‌هایی که بعداً لازم می‌شوند:** `tool/check_coverage.dart` برای پوشهٔ تازهٔ `lib/shikoo` کف پوشش می‌خواهد، وگرنه CI خود FlClash رد می‌شود.
