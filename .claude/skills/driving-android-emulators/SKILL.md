---
name: driving-android-emulators
description: Use when testing FlClash, Happ or the Shikoo app on the shikoo-phone or shikoo-tv emulator — booting them, installing an APK, pressing remote (D-pad) keys because the TV ignores taps, finding which button has focus, getting past Android's VPN consent dialog, taking screenshots, or proving the app's traffic really goes through its tunnel without a real subscription link.
---

# گوشی و تلویزیون مجازی

دو ابزار کنار همین فایل:
- `emu.sh`: ریموت، عکس، فوکوس و آی‌پی بیرونی
- `fake-panel.py`: پنل ساختگی با اشتراک و هدرهای پنل، به‌علاوهٔ یک پروکسی آزمایشی

**لینک اشتراک واقعی لازم نیست و نباید به کار برود** (CLAUDE.md › قاعدهٔ ۳ و ۶).

## روشن کردن و نصب

```bash
source /d/dev/android-toolchain/env.sh
nohup emulator -avd shikoo-tv -port 5556 -no-window -no-snapshot-save -no-boot-anim > /d/dev/shikoo-spike/emulator-tv.log 2>&1 &
# گوشی: -avd shikoo-phone -port 5554
# -no-window: پنجره روی صفحهٔ Sam می‌آید و Sam کار تأییدنشده را نباید ببیند (۲۰۲۶-۱۰-۰۳). عکس با shot گرفته می‌شود.
source .claude/skills/driving-android-emulators/emu.sh   # پیش‌فرض تلویزیون؛ برای گوشی: D=emulator-5554
boot                                                      # حدود ۵۵ ثانیه
$A install -r /d/dev/shikoo-spike/apk/FlClash-0.8.98-android-x86_64.apk
```

## خاموش کردن (۲۰۲۶-۱۰-۱۳)

- فقط با `adb -s emulator-<پورت> emu kill`، نه با `Stop-Process`، `taskkill` یا بستن تسک.
  - با `-read-only` (چند نمونهٔ هم‌زمان از یک AVD) هر نوشتهٔ دستگاه در `%TEMP%\AndroidEmulator\TMP*.tmp.qcow2` روی درایو C می‌رود و در یک آزمون به ۱ تا ۳ گیگ می‌رسد.
  - آزمایش ۲۰۲۶-۱۰-۱۳ روی `shikoo-phone`: بعد از `emu kill`، ۰ از ۴ فایل ماند؛ بعد از `Stop-Process`، هر ۴ فایل ماند.
  - از ۲۰۲۶-۱۰-۰۶ تا ۱۳ این فایل‌ها ۸۹ گیگ جا گذاشتند.
- اگر دستگاه جواب نداد و ناچار شدی پروسه را بکشی، جامانده‌ها را در PowerShell پاک کن:
  `Get-ChildItem "$env:TEMP\AndroidEmulator" -Filter *.qcow2 | ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -ErrorAction Stop } catch {} }`
  فایل دستگاهی که هنوز روشن است قفل است و پاک نمی‌شود، پس به کار دستیار دیگر آسیبی نمی‌رسد (آزمایش ۲۰۲۶-۱۰-۱۳: ۳ از ۳ رد شد و دستگاه کار کرد).

## ریموت، عکس، فوکوس

| کار | دستور |
|---|---|
| دکمه‌ها (۰٫۸ ثانیه فاصله) | `k DPAD_DOWN DPAD_RIGHT DPAD_CENTER` (و `BACK`، `HOME`) |
| عکس بعد از ۲ ثانیه | `shot tv-01 2` |
| الان روی کدام دکمه‌ایم | `focus` |
| آی‌پی بیرونی دستگاه | `ip_out` |

- هر فراخوانی Bash یک شل تازه است. `source` و دستورها را در **یک** فراخوانی بزن: `source …/emu.sh && k DPAD_DOWN DPAD_CENTER`.
- تلویزیون `input tap` را نمی‌گیرد؛ فقط دکمه کار می‌کند.
- `focus` روی FlClash (Flutter) و پنجره‌های اندروید جواب می‌دهد.
  روی Happ خطای `could not get idle state` می‌دهد؛ آن‌جا با `shot` نگاه کن.
- در پنجره‌های FlClash گاهی `CENTER` کاری نمی‌کند تا اول یک `DOWN` بزنی.

## پنجرهٔ اجازهٔ VPN

- اول ببین پنجره آمده یا نه: `$A shell dumpsys activity activities | grep -m1 topResumedActivity`.
  اگر `com.android.vpndialogs/.ConfirmDialog` بود (عنوانش «Connection request» است)، فوکوس اول روی متن است، نه روی دکمه.
  پس: `k DPAD_DOWN DPAD_LEFT DPAD_CENTER` (DOWN → Cancel، LEFT → OK).
- بعد از یک بار تأیید، دیگر نمی‌آید؛ حتی وقتی اپ دیگری بعداً اجازه گرفته باشد.
  اگر نیامده بود و این سه کلید را زدی، کلیدها به خود اپ می‌رسند.
- تونل بالا آمد؟ `$A shell ip -4 addr show tun0`

## اثبات اینکه ترافیک از تونل می‌رود

1. `ip_out`: پیش از اتصال، کشور ایران است.
2. `python .claude/skills/driving-android-emulators/fake-panel.py` را در پس‌زمینه اجرا کن.
   خروجی پروکسی آزمایشی کشوری **غیر از ایران** است. کشورش ثابت نیست، چون از پروکسی محلی `10808` می‌رود؛ ترکیه و هلند هر دو دیده شده.
   هر اتصال یک خط `[TCP] ... using GLOBAL` در خروجی پنل می‌گذارد.
3. وارد کردن اشتراک در FlClash:
   `$A shell am start -a android.intent.action.VIEW -d "'clash://install-config?url=http%3A%2F%2F10.0.2.2%3A18089%2Fsub'"`
   - اگر FlClash بسته بود، اولین بار پنجرهٔ «Add profile» نمی‌آید. وقتی باز شد، همین دستور را دوباره بزن.
   - بعد `k DPAD_DOWN DPAD_RIGHT DPAD_CENTER` تا «Confirm» زده شود.
   - کارت پروفایل باید «33GB / 100GB» و تاریخ انقضا را نشان دهد. این‌ها را از هدر پنل خوانده است.
   - پروفایل تازه خودبه‌خود انتخاب نمی‌شود: با `focus` رویش برو و `CENTER` بزن.
4. برای رفتن به یک زبانه در FlClash، `LEFT` بزن و بعد `UP` تا `focus` بگوید «Dashboard / Tab 1 of 6».
   سپس `RIGHT` تا دکمهٔ اتصال (`focus` زمان را نشان می‌دهد، مثلاً «00:00:00»)، و `CENTER`.
5. حالا `ip_out` باید کشور خروجی را نشان دهد، و همان لحظه یک خط `[TCP] ... 104.16.133.229:80` در خروجی پنل بیاید.
   بعد از قطع، `ip_out` باید دوباره ایران باشد.
- **مدرک را در فایل نگه دار، نه فقط در گزارش:**
  - هر `ip_out` را با زمانش ذخیره کن، مثلاً `ip_out | tee -a <پوشهٔ لاگ>/ip_out.log`.
  - `$A shell pm path <نام بسته>` هم ذخیره شود، تا معلوم باشد کدام اپ نصب بود.
  - بازبین بدون این‌ها فقط می‌تواند به گفتهٔ تو تکیه کند.
6. پنل را ببند. اول شماره‌هایش را بخوان؛ خط اول خروجی‌اش `panel pid … proxy pid …` است.
   بعد هر دو را ببند. در PowerShell: `Stop-Process -Id <panel>,<proxy>`. در Git Bash: `taskkill //F //PID <panel> //PID <proxy>`.

## باکس واقعی Sam از روی شبکه (۲۰۲۶-۱۰-۰۳)

- **وصل کردن:**
  - Sam این‌ها را روی باکس روشن می‌کند: `Developer options` (هفت بار OK روی `Build`) و بعد `USB debugging`.
  - نشانی باکس را از `About` ← `Status` ← `IP address` می‌گیری.
  - بعد `adb connect <IP>:5555` بزن. Sam باید پنجرهٔ `Allow USB debugging?` را OK کند؛ تا آن موقع `unauthorized` است.
  - بعد `D=<IP>:5555` را بده و از `emu.sh` استفاده کن.
- **روی باکس واقعی:**
  - `input tap` کار می‌کند (روی تلویزیون مجازی نه). با عکس جای دکمه را پیدا کن.
  - `focus` جواب نمی‌دهد. نشانگر فوکوس فلکلش هم دیده نمی‌شود.
  - `nc` روی PATH نیست. `ip_out` از `toybox nc` استفاده می‌کند.
- **لینک اشتراک:**
  - پنجرهٔ «Add profile» فلکلش کل لینک را نشان می‌دهد. از آن عکس نگیر، یا عکس را فوراً پاک کن.
  - لینک را فقط داخل یک فرمان به `am start -d` بده؛ هیچ‌جا چاپ یا ذخیره نشود.

## تله‌ها

- **وای‌فای گوشی مجازی از پروکسی میزبان می‌رود:** بدون هیچ VPN، `ip_out` هلند نشان می‌دهد (۲۰۲۶-۱۰-۰۲).
  پیش از آزمایش تونل روی گوشی، `$A shell svc wifi disable` بزن تا فقط دادهٔ موبایل بماند. آخر کار `svc wifi enable`. تلویزیون وای‌فای ندارد.
- **حالت «Global» در FlClash با پنل ساختگی کاری نمی‌کند:** گروه GLOBAL روی DIRECT است. `tun0` بالا می‌آید ولی آی‌پی ایران می‌ماند.
  حالت «Rule» (پیش‌فرض اپ تازه‌نصب) را نگه دار. کلیدهای اشتباه پشت یک پنجره می‌توانند حالت را عوض کنند.
- **پنجرهٔ «Disclaimer» روی تلویزیون فوکوس نمی‌گیرد:** کلیدها به داشبورد پشتش می‌رسند و `BACK` از اپ بیرون می‌برد.
  یک بار `k DPAD_DOWN DPAD_DOWN DPAD_DOWN DPAD_RIGHT DPAD_RIGHT DPAD_CENTER` بستش. ثابت نشده که همیشه کار کند.
- **شناسهٔ اپ ما:** از `cf8089b` به بعد `com.shikoonet.app.dev` است (ساخت با کلید debug؛ با کلید اصلی `com.shikoonet.app`). ساخت‌های قبلی `com.follow.clash.dev` بودند و کنار آن نصب می‌مانند.
  کلاس‌ها بستهٔ جاوای FlClash را نگه داشته‌اند، پس صفحهٔ اصلی `com.shikoonet.app.dev/com.follow.clash.MainActivity` است.
  لینک آزمایشی (فقط ساخت `SHIKOO_DEBUG`): `am start -n com.shikoonet.app.dev/com.follow.clash.MainActivity -a android.intent.action.VIEW -d 'shikoo-debug://add?url=<encoded>'`.
- **اپ‌های فقط-ARM** (مثل Happ) نصب و باز می‌شوند، ولی هستهٔ Goشان لحظهٔ وصل شدن کرش می‌کند. اتصالشان روی امولاتور تست‌شدنی نیست.
- **اگر اپی روی گوشی مجازی به `10.0.2.2` نرسید:** Happ این‌طور بود و علتش پیدا نشد. این راه برای گرفتن اشتراک کار کرد:
  `adb -s emulator-5554 reverse tcp:18089 tcp:18089`، و بعد آدرس `127.0.0.1` به‌جای `10.0.2.2`.
  پنل ساختگی فقط قالب Clash می‌دهد و Happ قالب v2ray می‌خواهد. برای Happ لازم هم نیست، چون اتصالش روی امولاتور تست‌شدنی نیست.
- **سه مسیر به پوشهٔ دورریختنی `D:\dev\shikoo-spike` اشاره می‌کنند:**
  - `MIHOMO` در `fake-panel.py`
  - `SHOTS` در `emu.sh`
  - مسیر APK در همین فایل

  پیش از پاک کردن آن پوشه جابه‌جایشان کن.
- **بستن یک تسک پس‌زمینه، برنامهٔ داخلش را نمی‌بندد.** پروسه را با شماره‌اش ببند (`Stop-Process -Id`). گوشی ساختگی استثناست: بخش «خاموش کردن».
- اگر `ip_out` چیزی برنگرداند، `104.16.133.229` را با یک آی‌پی دیگرِ cloudflare.com عوض کن.
