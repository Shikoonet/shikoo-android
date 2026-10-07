# وصله‌های شیکو روی FlClash

این مخزن فورک FlClash است (پایه: `v0.8.98`، کامیت `7c61c90`). هر تغییری در فایل‌های خود FlClash این‌جا ثبت می‌شود تا ادغام نسخه‌های تازهٔ FlClash ساده بماند.
فایل‌هایی که فقط مال شیکو هستند (`lib/shikoo/`، `design/`، `docs/`، `tools/`، `.claude/agents`، `.claude/skills`، `.claude/CLAUDE.md`) این‌جا نمی‌آیند.

| # | فایل FlClash | تغییر | چرا |
|---|---|---|---|
| ۱ | `CLAUDE.md` | یک خط آخر: `@.claude/CLAUDE.md` | راهنمای شیکو کنار `AGENTS.md` خود FlClash خوانده شود. اسناد Claude Code نمی‌گویند وقتی هر دو فایل هستند، هر دو خوانده می‌شوند یا نه. |

## نکته‌ها

- `.gitignore` خود FlClash پوشهٔ `docs/` را نادیده می‌گیرد. برای اینکه به آن دست نزنیم، یادداشت‌های شیکو با `git add -f docs/...` اضافه می‌شوند. فایل‌هایی که یک بار اضافه شده‌اند، بعد عادی دنبال می‌شوند.
- `.gitattributes` فایل تازهٔ شیکو است، نه وصله: همهٔ متن‌ها با پایان خط LF، تا اسکریپت‌ها داخل WSL هم درست اجرا شوند.
- `.github/workflows/build.yaml` خود FlClash با هر push اجرا می‌شود. GitHub Actions در این مخزن خاموش است تا CI خود شیکو ساخته شود.

## اپ شیکو بدون وصله

اپ شیکو هیچ فایل FlClash را عوض نمی‌کند. ورودی‌اش `lib/shikoo/app/main.dart` است و با `-t` ساخته می‌شود:

```bash
source ~/android-toolchain/env.sh
flutter build apk -t lib/shikoo/app/main.dart --split-per-abi --target-platform android-x64,android-arm \
  --dart-define=APP_ENV=stable                 # نسخهٔ آزمایشی: --dart-define=SHIKOO_DEBUG=true هم
```

- `dart setup.dart android` همچنان اپ خود FlClash را می‌سازد. برای اینکه آن هم اپ شیکو بسازد، یا `setup.dart` وصله می‌خورد (و دو تست `test/setup_test.dart`)، یا `lib/main.dart`. فعلاً لازم نیست.
- ترجمه‌ها: `lib/shikoo/l10n/*.arb`. بعد از هر تغییر: `bash tools/shikoo-l10n.sh` (پوشهٔ `generated/` را می‌سازد).

**فایل‌های تازهٔ شیکو داخل پوشه‌های FlClash** (فایلی از FlClash عوض نشده؛ در ادغام تداخلی نمی‌سازند):

| فایل | چرا |
|---|---|
| `assets/fonts/Vazirmatn-{Regular,Medium,Bold,ExtraBold}.ttf` | فونت وزیرمتن داخل APK. `assets/fonts/` در `pubspec.yaml` خود FlClash از قبل بسته‌بندی می‌شود، پس pubspec دست نخورد. با `FontLoader` بار می‌شود. |
| `assets/fonts/Vazirmatn-OFL.txt` | متن مجوز OFL، همراه فونت. |
| `test/shikoo/` | تست‌های شیکو: مرز import لایهٔ UI، و منطق وضعیت اتصال. |

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
- `lib/shikoo/app/app.dart` همان کارهای `ApplicationState` در `lib/application.dart` را تکرار می‌کند (`attach`، تایمر ۲۰ دقیقه‌ای، کار تغییر شبکه).

**وصله‌هایی که بعداً لازم می‌شوند:** `tool/check_coverage.dart` برای پوشهٔ تازهٔ `lib/shikoo` کف پوشش می‌خواهد، وگرنه CI خود FlClash رد می‌شود.
