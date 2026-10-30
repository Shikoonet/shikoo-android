// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'shikoo_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class ShikooL10nFa extends ShikooL10n {
  ShikooL10nFa([String locale = 'fa']) : super(locale);

  @override
  String get appTitle => 'شیکونت';

  @override
  String get appTitleTest => 'شیکونت آزمایشی';

  @override
  String get settings => 'تنظیمات';

  @override
  String get renew => 'تمدید';

  @override
  String get support => 'پشتیبانی';

  @override
  String get statusActive => 'فعال';

  @override
  String get chipExpired => 'تاریخ انقضا گذشته';

  @override
  String get stateExhausted => 'حجم تمام شده';

  @override
  String get usedLabel => 'مصرف شده:';

  @override
  String ofTotalGb(String total) {
    return 'از $total گیگ';
  }

  @override
  String get remainingLabel => 'باقی‌مانده:';

  @override
  String gb(String amount) {
    return '$amount گیگ';
  }

  @override
  String get unlimited => 'نامحدود';

  @override
  String validUntil(String date) {
    return 'اعتبار تا $date';
  }

  @override
  String daysLeft(int days) {
    final intl.NumberFormat daysNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String daysString = daysNumberFormat.format(days);

    return '$daysString روز باقی‌مانده';
  }

  @override
  String get jalaliMonths =>
      'فروردین|اردیبهشت|خرداد|تیر|مرداد|شهریور|مهر|آبان|آذر|دی|بهمن|اسفند';

  @override
  String jalaliDate(String day, String month, String year) {
    return '$day $month $year';
  }

  @override
  String get powerConnect => 'اتصال';

  @override
  String get powerOn => 'وصل';

  @override
  String get powerConnecting => 'در حال اتصال…';

  @override
  String get powerFailed => 'وصل نشد';

  @override
  String get subCancelTv => 'دکمهٔ وسط: لغو';

  @override
  String get subCancelTouch => 'برای لغو بزن';

  @override
  String get subRetryTv => 'دکمهٔ وسط: دوباره';

  @override
  String get subRetryTouch => 'دوباره بزن';

  @override
  String get speedUnit => 'مگ';

  @override
  String speedLabel(String down, String up) {
    return 'سرعت دریافت $down مگابیت بر ثانیه، ارسال $up مگابیت بر ثانیه';
  }

  @override
  String get tvHint => 'دکمهٔ وسطِ ریموت را بزن تا وصل شوی';

  @override
  String get loadingServers => 'در حال گرفتن فهرست سرورها…';

  @override
  String get msUnit => '';

  @override
  String get noResponse => 'بی‌پاسخ';

  @override
  String errorConnect(String server, int seconds) {
    final intl.NumberFormat secondsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String secondsString = secondsNumberFormat.format(seconds);

    return '$server تا $secondsString ثانیه جواب نداد.\nسرور دیگری را امتحان کن.';
  }

  @override
  String get errorServer => 'سرور عوض نشد.';

  @override
  String get initError => 'اپ باز نشد.';

  @override
  String get refresh => 'به‌روزرسانی';

  @override
  String get refreshServers => 'به‌روزرسانی سرورها';

  @override
  String updatedAgo(String ago) {
    return 'به‌روز شد، $ago';
  }

  @override
  String get updateFailed => 'به‌روز نشد';

  @override
  String get updating => 'در حال به‌روزرسانی…';

  @override
  String updateFailedAgo(String ago) {
    return 'به‌روز نشد، فهرستِ $ago';
  }

  @override
  String get agoJustNow => 'همین الان';

  @override
  String agoMinutes(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString دقیقه پیش';
  }

  @override
  String agoHours(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString ساعت پیش';
  }

  @override
  String agoDays(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString روز پیش';
  }

  @override
  String get updateFailedTitle => 'به‌روز نشد.';

  @override
  String get refreshWays => 'انتخاب راه به‌روزرسانی';

  @override
  String get refreshDirect => 'به‌روزرسانی مستقیم';

  @override
  String get refreshDirectHint => 'از اینترنتِ خودِ دستگاه، حتی وقتی وصلی';

  @override
  String get refreshViaServer => 'به‌روزرسانی از راه سرور';

  @override
  String refreshViaServerHint(String server) {
    return 'از راه «$server»';
  }

  @override
  String get refreshConnectFirst => 'اول وصل شو';

  @override
  String get updatingDirect => 'به‌روزرسانی مستقیم…';

  @override
  String get updatingViaServer => 'به‌روزرسانی از راه سرور…';

  @override
  String get updatingFallback => 'مستقیم نشد؛ از راه سرور…';

  @override
  String get updateFailedDirectOff =>
      'از اینترنتِ خودِ دستگاه جواب نیامد. با همین سرورها وصل شو، بعد از راه سرور امتحان کن.';

  @override
  String get updateFailedDirect =>
      'از اینترنتِ خودِ دستگاه جواب نیامد. از راه سرور امتحان کن.';

  @override
  String updateFailedViaServer(String server) {
    return 'از راه «$server» جواب نیامد. مستقیم امتحان کن، یا سرور دیگری انتخاب کن.';
  }

  @override
  String updateFailedBoth(String server) {
    return 'نه مستقیم جواب آمد، نه از راه «$server». سرور دیگری انتخاب کن و دوباره امتحان کن.';
  }

  @override
  String get updateFailedPanel =>
      'سرور اشتراکِ شیکو الان جواب نمی‌دهد؛ ایراد از دستگاهِ تو نیست. همین سرورها کار می‌کنند و خودش کمی بعد دوباره امتحان می‌کند.';

  @override
  String get updateFailedConnectFirst => 'اول وصل شو.';

  @override
  String serversAdded(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString سرور تازه آمد.';
  }

  @override
  String serverRemoved(String name) {
    return '«$name» حذف شد.';
  }

  @override
  String serversRemoved(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString سرور حذف شد.';
  }

  @override
  String selectedRemoved(String name) {
    return '«$name» دیگر در اشتراکت نیست.';
  }

  @override
  String selectedReplaced(String name) {
    return 'سریع‌ترین سرور، «$name»، جایش انتخاب شد.';
  }

  @override
  String selectedMoved(String name) {
    return 'اتصال همان لحظه به سریع‌ترین سرور، «$name»، رفت.';
  }

  @override
  String selectedMovedFirst(String name) {
    return 'اتصال همان لحظه به «$name» رفت.';
  }

  @override
  String selectedNoAnswer(String name) {
    return '«$name» جواب نداد.';
  }

  @override
  String switchingTo(String name) {
    return 'در حال رفتن به «$name»…';
  }

  @override
  String switchedTo(String name) {
    return 'حالا از «$name» وصلی.';
  }

  @override
  String switchKept(String name) {
    return 'هنوز از «$name» وصلی؛ سرور دیگری را امتحان کن.';
  }

  @override
  String switchFailedTv(String name) {
    return '«$name» جواب نداد.\nسرور دیگری را امتحان کن.';
  }

  @override
  String get findingBest => 'در حال یافتن بهترین سرور…';

  @override
  String get autoPick => 'سرور خودکار انتخاب می‌شود';

  @override
  String get connectsToFirst => 'اولین سروری که جواب بدهد، وصل می‌شوی.';

  @override
  String get noServerAnswered => 'هیچ سروری جواب نداد';

  @override
  String get noServerAnsweredHelpTouch =>
      'اینترنت این گوشی را بررسی کن.\nاگر وصل بود، از «پشتیبانی» بپرس.';

  @override
  String get noServerAnsweredHelpTv =>
      'اینترنت این تلویزیون را بررسی کن.\nاگر وصل بود، از «پشتیبانی» بپرس.';

  @override
  String get newBadge => 'تازه';

  @override
  String get serversTitle => 'سرورها';

  @override
  String get fastestFirst => 'سریع‌ترین بالا';

  @override
  String get sortsOnLeave => 'وقتی از فهرست بیرون بروی، مرتب می‌شود';

  @override
  String get sortsOnPing => 'با «پینگ» مرتب می‌شوند';

  @override
  String get ping => 'پینگ';

  @override
  String get pingServers => 'پینگ سرورها';

  @override
  String get inUseLabel => 'در حال استفاده';

  @override
  String get otherServiceHint => 'با زدنِ یک سرور، اتصال به این سرویس می‌رود.';

  @override
  String get otherServiceNow => 'اتصال حالا از همین سرویس است.';

  @override
  String get otherServiceCaptionTv =>
      'با زدنِ یک سرور، اتصال به این سرویس می‌رود';

  @override
  String pingProgress(int done, int total) {
    final intl.NumberFormat doneNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String doneString = doneNumberFormat.format(done);
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return 'پینگ $doneString از $totalString';
  }

  @override
  String get measuring => 'در حال سنجش';

  @override
  String get searchServers => 'جست‌وجوی سرور';

  @override
  String get searchNoMatch => 'سروری با این نام نیست';

  @override
  String get clearSearch => 'پاک کردن جست‌وجو';

  @override
  String get renewTitle => 'تمدید با گوشی';

  @override
  String get renewHelpList =>
      'با دوربین گوشی اسکن کن؛ ربات شیکونت فهرست تمدید سرویس‌هایت را باز می‌کند.';

  @override
  String get supportTitle => 'پشتیبانی با گوشی';

  @override
  String get supportHelpTv =>
      'با دوربین گوشی اسکن کن تا گفتگو با پشتیبانی شیکونت در تلگرام باز شود.';

  @override
  String get close => 'بستن';

  @override
  String get chipFinished => 'تمام‌شده';

  @override
  String get renewPickTitle => 'کدام سرویس را تمدید کنی؟';

  @override
  String get renewPickHelp =>
      'ربات شیکونت در تلگرام صفحهٔ تمدید همان سرویس را باز می‌کند.';

  @override
  String get pickHelpTv =>
      'بعد یک کد تصویری می‌آید که با دوربین گوشی اسکنش می‌کنی.';

  @override
  String get supportPickTitle => 'برای کدام سرویس پشتیبانی می‌خواهی؟';

  @override
  String get supportPickHelp => 'پشتیبانی همان سرویس باز می‌شود.';

  @override
  String get back => 'بازگشت';

  @override
  String get backHintTv => 'برای برگشت، دکمهٔ برگشتِ ریموت را بزن';

  @override
  String get appearance => 'ظاهر';

  @override
  String get themeLight => 'روشن';

  @override
  String get themeDark => 'تیره';

  @override
  String get themeAuto => 'خودکار';

  @override
  String get language => 'زبان';

  @override
  String get languageFa => 'فارسی';

  @override
  String get languageEn => 'English';

  @override
  String get account => 'حساب';

  @override
  String get logout => 'خروج';

  @override
  String get logoutHelpTv => 'سرویس‌ها از این تلویزیون پاک می‌شوند.';

  @override
  String get logoutHelpTouch => 'سرویس‌ها از این گوشی پاک می‌شوند.';

  @override
  String get logoutBodyTv =>
      'اتصال قطع می‌شود و سرویس‌ها از این تلویزیون پاک می‌شوند. اشتراکت در ربات شیکونت سر جایش می‌ماند.';

  @override
  String get logoutBodyTouch =>
      'اتصال قطع می‌شود و سرویس‌ها از این گوشی پاک می‌شوند. خودِ سرویس‌ها سر جایشان‌اند؛ با همان لینک یا با تلگرام برمی‌گردند.';

  @override
  String get cancelButton => 'انصراف';

  @override
  String get appSection => 'اپ';

  @override
  String get version => 'نسخه';

  @override
  String get about => 'درباره';

  @override
  String get aboutSummary =>
      'نرم‌افزار آزاد با مجوز ⁨GPL-3.0⁩، بر پایهٔ ⁨FlClash⁩ و چند نرم‌افزار آزاد دیگر';

  @override
  String get aboutFree =>
      'شیکونت نرم‌افزار آزاد است و با مجوز GPL-3.0 منتشر می‌شود.';

  @override
  String get aboutBasedOn =>
      'شیکونت بر پایهٔ ⁨FlClash⁩ از ⁨chen08209⁩ و چند نرم‌افزار آزاد دیگر است. سپاس از سازندگانشان.';

  @override
  String get aboutSource =>
      'کد منبعِ همین نسخه را می‌توانی از «پشتیبانی» بگیری.';

  @override
  String get aboutLicense => 'متن مجوز: gnu.org/licenses/gpl-3.0';

  @override
  String selectedDown(String name) {
    return '«$name» جواب نمی‌دهد.\nسرور دیگری را از فهرست انتخاب کن.';
  }

  @override
  String get powerNoInternet => 'وصل، بی‌اینترنت';

  @override
  String noInternetTitle(String name) {
    return 'اینترنت از «$name» رد نمی‌شود.';
  }

  @override
  String get noInternetBody => 'شاید این سرور روی اینترنت تو بسته باشد.';

  @override
  String get noInternetOther => 'انتخاب سرور دیگر';

  @override
  String get streamingTitle => 'فقط برای نماوا، فیلیمو، شیدا و گپ‌فیلم';

  @override
  String get streamingBody =>
      'سایت‌ها و برنامه‌های دیگر از این سرور باز نمی‌شوند.';

  @override
  String get vpnRefused =>
      'اجازهٔ اتصال داده نشد.\nدوباره وصل شو و در پنجرهٔ اندروید اجازه بده.';

  @override
  String get vpnMissing =>
      'این دستگاه پنجرهٔ اجازهٔ اتصال را ندارد.\nاز «پشتیبانی» بپرس.';

  @override
  String get logoutTitleTv => 'سرویس‌ها از این تلویزیون پاک شوند؟';

  @override
  String get logoutTitleTouch => 'سرویس‌ها از این گوشی پاک شوند؟';

  @override
  String get removeButton => 'پاک کردن';

  @override
  String renewPickInList(String username) {
    return 'در فهرست ربات، سرویسِ $username را بزن؛ اگر نبود، صفحهٔ بعدِ فهرست را ببین.';
  }

  @override
  String get powerNoService => 'سرویسی نیست';

  @override
  String get noServiceTitleTv => 'سرویسی روی این تلویزیون نیست';

  @override
  String get noServiceTitleTouch => 'سرویسی روی این گوشی نیست';

  @override
  String get noServiceHelp => 'برای برگرداندنش از «پشتیبانی» بپرس.';

  @override
  String get noServiceHelpPaste =>
      'لینک اشتراکت را کپی کن، بعد «چسباندن لینک اشتراک» را بزن.\nلینک نداری؟ از «پشتیبانی» بپرس.';

  @override
  String get pasteLink => 'چسباندن لینک اشتراک';

  @override
  String get pasteChecking => 'در حال بررسی لینک…';

  @override
  String get pasteEmptyTitle => 'کلیپ‌بورد خالی است.';

  @override
  String get pasteEmptyHelp => 'لینک اشتراکت را کپی کن، بعد دوباره بزن.';

  @override
  String get pasteNotShikooTitle => 'این لینک شیکونت نیست.';

  @override
  String get pasteNotShikooHelp =>
      'فقط لینک اشتراک شیکونت کار می‌کند؛ همان که از ربات شیکونت یا نماینده‌ات گرفتی.';

  @override
  String get pasteRevokedTitle => 'این لینک باطل شده یا منقضی است.';

  @override
  String get pasteRevokedHelp =>
      'لینک تازه را از ربات شیکونت یا نماینده‌ات بگیر.';

  @override
  String get pasteOfflineTitle => 'اینترنت وصل نیست.';

  @override
  String get pasteOfflineHelp => 'اینترنت گوشی را بررسی کن و دوباره بزن.';

  @override
  String get pasteAnother => 'چسباندن لینک دیگر';

  @override
  String get pasteAnotherHelp => 'برای سرویس دیگری که داری';

  @override
  String get powerExpired => 'اعتبار تمام شده';

  @override
  String get renewToConnect => 'با «تمدید» دوباره وصل می‌شوی.';

  @override
  String get serversAfterRenew => 'فهرست سرورها بعد از تمدید برمی‌گردد.';

  @override
  String get expiredEnded => 'تمام شده';

  @override
  String get summaryExhausted => 'حجمش تمام شد. با تمدید دوباره فعال می‌شود.';

  @override
  String summaryExpired(String date) {
    return 'اعتبارش $date تمام شد. با تمدید دوباره فعال می‌شود.';
  }

  @override
  String get pasteUnavailableTitle => 'لینک الان باز نشد.';

  @override
  String get pasteUnavailableHelp =>
      'کمی بعد دوباره بزن؛ اگر باز نشد، از «پشتیبانی» بپرس.';

  @override
  String get pasteEndedTitle => 'این سرویس تمام شده.';

  @override
  String get pasteEndedHelp =>
      'از ربات شیکونت یا نماینده‌ات تمدیدش کن، بعد دوباره بچسبان.';

  @override
  String get loginTagline => 'مخصوص مشتری‌های شیکونت';

  @override
  String get loginTelegram => 'ورود با تلگرام';

  @override
  String get loginTelegramNote =>
      'تلگرام باز می‌شود؛ در ربات شیکونت «تأیید» را بزن.';

  @override
  String get noTelegramHere => 'تلگرام روی این گوشی نیست؟';

  @override
  String get waitingTitle => 'هنوز «تأیید» نرسیده.';

  @override
  String get waitingHelp =>
      'اگر تلگرامت فقط با فیلترشکن باز می‌شود، اول آن را روشن کن، بعد دوباره تلگرام را باز کن.';

  @override
  String get reopenTelegram => 'باز کردن دوبارهٔ تلگرام';

  @override
  String get approveElsewhere => 'از دستگاه دیگری تأیید کن';

  @override
  String get codeExpiredNote => 'این کد تمام شد.';

  @override
  String get otherDeviceTitle => 'تأیید از دستگاه دیگر';

  @override
  String get otherDeviceScan =>
      'گوشی دیگری با تلگرام داری؟ این کد تصویری را با دوربینش اسکن کن.';

  @override
  String get otherDeviceComputer =>
      'تلگرامت روی کامپیوتر است؟ این کد را برای ربات شیکونت بفرست:';

  @override
  String get codeOnlyYou => 'این کد را فقط خودت در ربات بزن؛ به هیچ‌کس نده.';

  @override
  String get otherDeviceFine =>
      'کد ۱۰ دقیقه کار می‌کند. بعد از «تأیید» در ربات، این صفحه خودش به خانه می‌رود.';

  @override
  String get tvLoginLead => 'با دوربین گوشی اسکن کن و «تأیید» را بزن';

  @override
  String get tvLoginVpnHint =>
      'تلگرامت فقط با فیلترشکن باز می‌شود؟ روی گوشی روشنش کن، بعد اسکن کن.';

  @override
  String get tvLoginComputer =>
      'تلگرامت روی کامپیوتر است؟\nاین کد را برای ربات بفرست:';

  @override
  String get codeLifetime => 'این کد ۱۰ دقیقه کار می‌کند.';

  @override
  String get codeExpiredLead =>
      '۱۰ دقیقه گذشت و این کد تمام شد. یک کد تازه بگیر.';

  @override
  String get previousCode => 'کد قبلی';

  @override
  String get newCode => 'کد تازه';

  @override
  String get codeExpiredOverlay => 'این کد تمام شد';

  @override
  String accountWithUsername(String name, String username) {
    return '$name ($username)';
  }

  @override
  String get approvedTitle => 'ورود انجام شد';

  @override
  String approvedBodyTv(String account) {
    return 'این تلویزیون به حساب تلگرامِ $account وصل شد، با این سرویس‌ها:';
  }

  @override
  String approvedBodyTouch(String account) {
    return 'این گوشی به حساب تلگرامِ $account وصل شد، با این سرویس‌ها:';
  }

  @override
  String approvedBodyOneTv(String account) {
    return 'این تلویزیون به حساب تلگرامِ $account وصل شد، با این سرویس:';
  }

  @override
  String approvedBodyOneTouch(String account) {
    return 'این گوشی به حساب تلگرامِ $account وصل شد، با این سرویس:';
  }

  @override
  String get servicesComing => 'سرویس‌هایت دارند می‌آیند…';

  @override
  String get continueButton => 'ادامه';

  @override
  String get notMyAccount => 'این حساب من نیست';

  @override
  String get servicesFailedTitle => 'سرویس‌ها نرسیدند';

  @override
  String servicesFailedBodyTv(String account) {
    return 'ورود با حساب تلگرامِ $account انجام شد، ولی فهرست سرویس‌ها از سرور نرسید. اینترنت این تلویزیون را بررسی کن و دوباره امتحان کن.';
  }

  @override
  String servicesFailedBodyTouch(String account) {
    return 'ورود با حساب تلگرامِ $account انجام شد، ولی فهرست سرویس‌ها از سرور نرسید. اینترنت این گوشی را بررسی کن و دوباره امتحان کن.';
  }

  @override
  String get retry => 'دوباره';

  @override
  String get noServiceTitle => 'این حساب سرویسی ندارد';

  @override
  String noServiceBodyTouch(String account) {
    return 'با حساب تلگرامِ $account وارد شدی، ولی هیچ سرویس شیکونت به آن وصل نیست.';
  }

  @override
  String noServiceBodyTv(String account) {
    return 'با حساب تلگرامِ $account وارد شدی، ولی سرویسی به آن وصل نیست.';
  }

  @override
  String get noServiceHelpTouch =>
      'سرویست روی حساب تلگرام دیگری است؟ اول در خودِ تلگرام به همان حساب برو، بعد «ورود با حساب دیگر» را بزن.';

  @override
  String get noServiceHelpTv =>
      'سرویست روی حساب دیگری است؟ در تلگرامِ گوشی به همان حساب برو و دوباره اسکن کن.';

  @override
  String get otherAccount => 'ورود با حساب دیگر';

  @override
  String get askSupportLink => 'فکر می‌کنی اشتباه شده؟ از پشتیبانی بپرس';

  @override
  String get rejectedTitle => 'ورود رد شد';

  @override
  String get rejectedBodyTv =>
      'در تلگرام «رد» زده شد، پس این تلویزیون وصل نشد. اگر اشتباهی بود، دوباره امتحان کن.';

  @override
  String get rejectedBodyTouch =>
      'در تلگرام «رد» زده شد، پس این گوشی وصل نشد. اگر اشتباهی بود، دوباره امتحان کن.';

  @override
  String signedInWith(String name) {
    return 'وارد شده با $name';
  }

  @override
  String get telegramAccount => 'حساب تلگرام';

  @override
  String telegramAccountUsername(String username) {
    return 'حساب تلگرامِ $username';
  }

  @override
  String get logoutHelpSignedInTouch =>
      'سرویس‌های این حساب از این دستگاه برداشته می‌شوند؛ خودِ اشتراک‌هایت سر جایشان‌اند.';

  @override
  String get logoutHelpSignedInTv =>
      'سرویس‌ها از این تلویزیون برداشته می‌شوند؛ خودِ اشتراک‌هایت سر جایشان‌اند.';

  @override
  String get logoutSignedInTitle => 'از حساب خارج می‌شوی؟';

  @override
  String get logoutSignedInBodyTouch =>
      'اتصال قطع می‌شود و این دستگاه از حساب تلگرامت جدا می‌شود. سرویس‌های این حساب از آن برداشته می‌شوند، ولی سرویسی که لینکش را خودت چسبانده‌ای می‌ماند. خودِ اشتراک‌هایت سر جایشان‌اند.';

  @override
  String get logoutSignedInBodyTv =>
      'اتصال قطع می‌شود، این تلویزیون از حساب تلگرامت جدا می‌شود و سرویس‌ها از آن برداشته می‌شوند. خودِ اشتراک‌هایت سر جایشان‌اند؛ هر وقت خواستی، دوباره با تلگرام وارد شو.';

  @override
  String get signInRow => 'ورود با تلگرام';

  @override
  String get signInRowHelp =>
      'هنوز وارد نشده‌ای. با ورود، همهٔ سرویس‌هایت خودکار می‌آیند.';

  @override
  String get renewHelpDirect =>
      'با دوربین گوشی اسکن کن؛ ربات شیکونت صفحهٔ تمدیدِ همین سرویس را باز می‌کند.';

  @override
  String get codeFailedTitle => 'کد ورود نرسید.';

  @override
  String get openBotTitleTv => 'ربات شیکونت با گوشی';

  @override
  String get openBotHelpTv => 'با دوربین گوشی اسکن کن تا ربات شیکونت باز شود.';

  @override
  String get codeFetching => 'در حال گرفتن کد…';

  @override
  String get codeFailedHelpTouch => 'اینترنت گوشی را بررسی کن و دوباره بزن.';

  @override
  String get codeFailedOverlay => 'کد ورود نرسید';

  @override
  String get codeFailedLeadTv =>
      'کد ورود از سرور نرسید. اینترنت این تلویزیون را بررسی کن و دوباره امتحان کن.';

  @override
  String get noLinkChip => 'بدون لینک';

  @override
  String get noLinkHelpTouch => 'یک بار از ربات سرویس را باز کن';

  @override
  String get noLinkHelpTv =>
      'یک بار از ربات سرویس را باز کن، بعد «دوباره» را بزن.';

  @override
  String get loadFailedChip => 'باز نشد';

  @override
  String get loadFailedHelp =>
      'لینکِ این سرویس هست، ولی سرورهایش الان باز نشد. اینترنت را بررسی کن و «دوباره» را بزن.';

  @override
  String get openBotTouch => 'باز کردن ربات';

  @override
  String get openBotTv => 'ربات شیکونت';

  @override
  String get summaryExpiredNoDate =>
      'اعتبارش تمام شد. با تمدید دوباره فعال می‌شود.';

  @override
  String get summaryExpiredNoDateTv =>
      'اعتبارش تمام شد. بعد از تمدید، «دوباره» را بزن.';

  @override
  String get summaryExhaustedTv =>
      'حجمش تمام شد. بعد از تمدید، «دوباره» را بزن.';

  @override
  String get summaryDisabled => 'غیرفعال شد. با تمدید دوباره فعال می‌شود.';

  @override
  String get summaryDisabledTv => 'غیرفعال شد. بعد از تمدید، «دوباره» را بزن.';

  @override
  String get summaryRemoved =>
      'غیرفعال شد و تمدید نمی‌شود. برای پیگیری، «پشتیبانی» را بزن.';

  @override
  String get summaryNotRenewable =>
      'این سرویس تمدید نمی‌شود؛ برای ادامه از «پشتیبانی» بپرس.';

  @override
  String get pastedServicesTitle => 'سرویس‌های اضافه‌شده با لینک';

  @override
  String get removeService => 'حذف';

  @override
  String removeServiceLabel(String name) {
    return 'حذف $name';
  }

  @override
  String removeServiceTitle(String name) {
    return 'حذف «$name»؟';
  }

  @override
  String get removeServiceBody =>
      'این سرویس از این گوشی پاک می‌شود. خودِ سرویس سر جایش است و با همان لینک برمی‌گردد.';

  @override
  String get removeServiceBodyConnected =>
      'اتصال قطع می‌شود و این سرویس از این گوشی پاک می‌شود. خودِ سرویس سر جایش است و با همان لینک برمی‌گردد.';

  @override
  String get chipRevoked => 'لینک باطل شده';

  @override
  String get revokedTitle => 'این لینک باطل شده.';

  @override
  String get revokedHelp =>
      'حذفش کن، یا لینک تازه را از ربات یا نماینده‌ات بگیر و با «+» بالای خانه بچسبان.';

  @override
  String errorConnectTouch(String server, int seconds) {
    final intl.NumberFormat secondsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String secondsString = secondsNumberFormat.format(seconds);

    return '$server تا $secondsString ثانیه جواب نداد. دوباره بزن، یا از فهرست سرور دیگری انتخاب کن.';
  }

  @override
  String get serviceUnnamed => 'سرویس شیکونت';

  @override
  String finishedServices(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'سرویس‌های تمام‌شده ($countString)';
  }

  @override
  String get finishedData => 'حجم تمام شد';

  @override
  String get finishedToday => 'امروز تمام شد';

  @override
  String finishedDaysAgo(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString روز پیش تمام شد';
  }

  @override
  String get finishedNoDate => 'اعتبارش تمام شد';

  @override
  String get finishedDisabled => 'غیرفعال شد';

  @override
  String approvedMoreServices(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'و $countString سرویس دیگر';
  }

  @override
  String approvedBodyChooseTouch(String account) {
    return 'این گوشی به حساب تلگرامِ $account وصل شد.';
  }

  @override
  String approvedBodyChooseTv(String account) {
    return 'این تلویزیون به حساب تلگرامِ $account وصل شد.';
  }

  @override
  String get chooseServicesTouch => 'کدام سرویس‌ها روی این گوشی باشد؟';

  @override
  String get chooseServicesTv => 'کدام سرویس‌ها روی این تلویزیون باشد؟';

  @override
  String get chooseAtLeastOne => 'دست‌کم یک سرویس را تیک بزن.';

  @override
  String servicesHereTouch(int shown, int total) {
    final intl.NumberFormat shownNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String shownString = shownNumberFormat.format(shown);
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return 'روی این گوشی $shownString سرویس از $totalString سرویسِ حسابت هست. برای عوض کردن، خارج شو و دوباره وارد شو.';
  }

  @override
  String get servicesAllHereTouch =>
      'همهٔ سرویس‌های حسابت روی این گوشی است. برای عوض کردن، خارج شو و دوباره وارد شو.';

  @override
  String get changeServicesTv =>
      'برای عوض کردن سرویس‌های این تلویزیون، خارج شو و دوباره وارد شو.';

  @override
  String get notificationStop => 'قطع اتصال';

  @override
  String get notificationStopping => 'در حال قطع اتصال…';

  @override
  String get shortcutToggle => 'وصل / قطع';

  @override
  String get clockWrongTitle => 'تاریخ و ساعت دستگاهت درست نیست.';

  @override
  String get clockWrongHelp =>
      'از تنظیمات ← تاریخ و ساعت، «خودکار» را روشن کن (یا درستش کن) و دوباره امتحان کن.';

  @override
  String get clockStillWrong => 'ساعت هنوز درست نیست.';

  @override
  String get dateSettings => 'تنظیمات تاریخ و ساعت';

  @override
  String get updateTitle => 'نسخهٔ تازه آمده';

  @override
  String updateVersionSize(String version, int size) {
    final intl.NumberFormat sizeNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String sizeString = sizeNumberFormat.format(size);

    return 'نسخهٔ $version، $sizeString مگابایت';
  }

  @override
  String get updateGet => 'دریافت';

  @override
  String get updateDownloading => 'در حال دریافت…';

  @override
  String updateProgress(int percent, int done, int total) {
    final intl.NumberFormat percentNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String percentString = percentNumberFormat.format(percent);
    final intl.NumberFormat doneNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String doneString = doneNumberFormat.format(done);
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return '$percentString٪، $doneString از $totalString مگابایت';
  }

  @override
  String get updateReady => 'آمادهٔ نصب';

  @override
  String get updateInstall => 'نصب';

  @override
  String get updateClosesApp =>
      'با نصب، شیکونت بسته می‌شود و اگر وصلی، اتصال هم؛ بعد دوباره بازش کن.';

  @override
  String get updateClosesAppDesktop =>
      'با نصب، ویندوز اجازه می‌خواهد و شیکونت بسته می‌شود؛ اگر وصلی، اتصال هم. بعد خودش باز می‌شود.';

  @override
  String get updateDownloadFailedTitle => 'دریافت نشد.';

  @override
  String get updateDownloadFailedHelp =>
      'اینترنت را بررسی کن و دوباره بزن؛ از همان‌جا ادامه می‌دهد.';

  @override
  String get updateBadFileTitle => 'فایل سالم نرسید.';

  @override
  String get updateBadFileHelp => 'دوباره بزن تا از اول دریافت شود.';

  @override
  String get updateForcedTitle => 'نسخهٔ تازه لازم است';

  @override
  String updateForcedBody(String version, int size) {
    final intl.NumberFormat sizeNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String sizeString = sizeNumberFormat.format(size);

    return 'برای ادامه، نسخهٔ $version را دریافت و نصب کن ($sizeString مگابایت).';
  }

  @override
  String get installPermissionTitle => 'اجازهٔ نصب';

  @override
  String get installPermissionTouch =>
      'در صفحهٔ بعد، کنار «شیکونت» اجازهٔ نصب را روشن کن، بعد دکمهٔ برگشتِ گوشی را بزن؛ نصب خودش شروع می‌شود.';

  @override
  String get installPermissionTv =>
      'در صفحهٔ بعد، کنار «شیکونت» اجازهٔ نصب را روشن کن، بعد دکمهٔ برگشتِ ریموت را بزن؛ نصب خودش شروع می‌شود.';

  @override
  String get updateNoSpaceTitle => 'جا کم است.';

  @override
  String get updateNoSpaceHelp =>
      'چند برنامه یا فایل را از این دستگاه پاک کن و دوباره بزن.';

  @override
  String get updateInstallFailed =>
      'نصب‌کننده باز نشد؛ دوباره بزن یا از «پشتیبانی» بپرس.';

  @override
  String get installPermissionLegacy =>
      'در صفحهٔ بعد، پایین همان صفحه «منابع ناشناس» را روشن کن، بعد دکمهٔ برگشت را بزن.';

  @override
  String get installPermissionLegacyTv =>
      'در صفحهٔ بعد «منابع ناشناس» را پیدا و روشن کن، بعد دکمهٔ برگشتِ ریموت را بزن.';

  @override
  String get settingsCheckUpdate => 'بررسی به‌روزرسانی';

  @override
  String get settingsChecking => 'در حال بررسی…';

  @override
  String get settingsUpToDate => 'نسخهٔ تو تازه‌ترین است.';

  @override
  String get settingsCheckFailed =>
      'بررسی نشد؛ اینترنت را بررسی کن و دوباره بزن.';

  @override
  String get reportSendToSupport => 'ارسال گزارش به پشتیبانی';

  @override
  String get reportSendShort => 'ارسال گزارش';

  @override
  String get diagTitle => 'عیب‌یابی و گزارش';

  @override
  String get diagRowHelp => 'اگر برنامه درست کار نمی‌کند';

  @override
  String get diagInternetGroup => 'اینترنت';

  @override
  String get diagReportGroup => 'گزارش';

  @override
  String get diagReportHelp =>
      'اگر برنامه درست کار نمی‌کند، یک گزارش برای پشتیبانی بفرست. پیش از ارسال می‌بینی چه فرستاده می‌شود.';

  @override
  String get diagReportLater =>
      'گزارش الان نمی‌رسد. وقتی اینترنت برگشت، «دوباره» را بزن.';

  @override
  String get reportSupportSheetBody =>
      'اگر برنامه درست کار نمی‌کند، اول یک گزارش بفرست تا پشتیبانی ببیند چه شده.';

  @override
  String get reportChatTelegram => 'گفتگو در تلگرام';

  @override
  String get reportCrashTitle => 'برنامه دفعهٔ قبل ناگهان بسته شد.';

  @override
  String get reportCrashAsk => 'گزارشش را برای ما بفرستیم؟';

  @override
  String get reportCrashYes => 'بفرست';

  @override
  String get reportCrashNo => 'نه';

  @override
  String get reportTitle => 'گزارش برای پشتیبانی';

  @override
  String get reportImageApp => 'آنچه برنامه کشید';

  @override
  String get reportImageScreen => 'آنچه روی صفحه بود';

  @override
  String get reportImagesSwitch => 'عکس صفحه‌ها هم فرستاده شود';

  @override
  String get reportImageOff => 'فرستاده نمی‌شود';

  @override
  String get reportWhatIsSent =>
      'فرستاده می‌شود: مدل و تنظیمات دستگاه، نسخهٔ برنامه، نام و حجم سرویس‌هایت، اپراتور و وضعیت اینترنت، و کارهای اخیر برنامه و خطاهایش.';

  @override
  String get reportNeverSent => 'لینک اشتراک و رمزها هرگز فرستاده نمی‌شوند.';

  @override
  String get reportSend => 'ارسال';

  @override
  String get reportSending => 'در حال ارسال…';

  @override
  String get reportSentTitle => 'فرستاده شد';

  @override
  String get reportSentLinked =>
      'پشتیبانی گزارشت را می‌بیند؛ لازم نیست چیزی بفرستی.';

  @override
  String get reportCodeLabel => 'کد گزارش';

  @override
  String reportCodeSmall(String code) {
    return 'کد گزارش: $code';
  }

  @override
  String get reportGiveCode => 'این کد را به پشتیبانی بده.';

  @override
  String get reportFailedTitle => 'فرستاده نشد';

  @override
  String get reportFailedHelp => 'اینترنت را بررسی کن و دوباره بزن.';

  @override
  String get reportFailedBusy =>
      'الان گزارش‌های زیادی رسیده. یک ساعت دیگر دوباره بزن.';

  @override
  String get reportFailedRefused =>
      'ایراد از سمت ماست. در تلگرام با پشتیبانی گفتگو کن.';

  @override
  String get probeChecking => 'در حال بررسی اینترنت…';

  @override
  String get probeOk => 'اینترنت وصل است و سرور شیکونت در دسترس است.';

  @override
  String get probeOffline => 'این دستگاه به اینترنت وصل نیست.';

  @override
  String get probeNoAbroad =>
      'اینترنت بین‌الملل روی این خط قطع است. سرورها بیرون از ایران‌اند.';

  @override
  String get probeNoDoor =>
      'به سرور شیکونت نرسیدیم؛ چند دقیقهٔ دیگر دوباره امتحان کن.';

  @override
  String get probeNoServer => 'هیچ‌کدام از سرورها جواب نمی‌دهند.';

  @override
  String get probeNetSettings => 'تنظیمات اینترنت';

  @override
  String get addServiceTooltip => 'افزودن سرویس با لینک';

  @override
  String get addServiceTitle => 'افزودن سرویس';

  @override
  String get addServiceHelp =>
      'لینک اشتراک شیکونتِ سرویسِ دیگرت را کپی کن، بعد این دکمه را بزن. سرویس کنار بقیه، روی همین گوشی می‌آید.';

  @override
  String serviceAdded(String name) {
    return 'سرویسِ «$name» اضافه شد.';
  }

  @override
  String get serviceAlreadyHere => 'این سرویس از قبل روی این گوشی هست.';

  @override
  String get servicesGroup => 'سرویس‌ها';

  @override
  String get orderServices => 'ترتیب سرویس‌ها';

  @override
  String get orderServicesHelpTouch => 'فقط روی همین گوشی';

  @override
  String get orderServicesHelpTv => 'فقط روی همین تلویزیون';

  @override
  String get orderScreenHelp =>
      'هر سرویس را با ≡ بگیر و بالا یا پایین ببر. ترتیب فقط روی همین گوشی است و همان لحظه ذخیره می‌شود.';

  @override
  String orderHandleLabel(String name) {
    return 'کشیدن «$name» برای جابه‌جایی';
  }

  @override
  String get orderTvHintRest => 'تأیید: برداشتن برای جابه‌جایی';

  @override
  String get orderTvHintMoving =>
      'بالا و پایین: جابه‌جا کردن · تأیید: گذاشتن · بازگشت: لغو';

  @override
  String get orderTvPicked => 'در حال جابه‌جایی';

  @override
  String get noServerAnsweredHelpDesktop =>
      'اینترنت این کامپیوتر را بررسی کن.\nاگر وصل بود، از «پشتیبانی» بپرس.';

  @override
  String get logoutHelpDesktop => 'سرویس‌ها از این کامپیوتر پاک می‌شوند.';

  @override
  String get logoutBodyDesktop =>
      'اتصال قطع می‌شود و سرویس‌ها از این کامپیوتر پاک می‌شوند. خودِ سرویس‌ها سر جایشان‌اند؛ با همان لینک یا با تلگرام برمی‌گردند.';

  @override
  String get logoutTitleDesktop => 'سرویس‌ها از این کامپیوتر پاک شوند؟';

  @override
  String get noServiceTitleDesktop => 'سرویسی روی این کامپیوتر نیست';

  @override
  String approvedBodyDesktop(String account) {
    return 'این کامپیوتر به حساب تلگرامِ $account وصل شد، با این سرویس‌ها:';
  }

  @override
  String approvedBodyOneDesktop(String account) {
    return 'این کامپیوتر به حساب تلگرامِ $account وصل شد، با این سرویس:';
  }

  @override
  String servicesFailedBodyDesktop(String account) {
    return 'ورود با حساب تلگرامِ $account انجام شد، ولی فهرست سرویس‌ها از سرور نرسید. اینترنت این کامپیوتر را بررسی کن و دوباره امتحان کن.';
  }

  @override
  String get rejectedBodyDesktop =>
      'در تلگرام «رد» زده شد، پس این کامپیوتر وصل نشد. اگر اشتباهی بود، دوباره امتحان کن.';

  @override
  String get codeFailedHelpDesktop =>
      'اینترنت کامپیوتر را بررسی کن و دوباره بزن.';

  @override
  String approvedBodyChooseDesktop(String account) {
    return 'این کامپیوتر به حساب تلگرامِ $account وصل شد.';
  }

  @override
  String get chooseServicesDesktop => 'کدام سرویس‌ها روی این کامپیوتر باشد؟';

  @override
  String servicesHereDesktop(int shown, int total) {
    final intl.NumberFormat shownNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String shownString = shownNumberFormat.format(shown);
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return 'روی این کامپیوتر $shownString سرویس از $totalString سرویسِ حسابت هست. برای عوض کردن، خارج شو و دوباره وارد شو.';
  }

  @override
  String get servicesAllHereDesktop =>
      'همهٔ سرویس‌های حسابت روی این کامپیوتر است. برای عوض کردن، خارج شو و دوباره وارد شو.';

  @override
  String get orderServicesHelpDesktop => 'فقط روی همین کامپیوتر';

  @override
  String get noTelegramHereDesktop => 'تلگرام روی این کامپیوتر نیست؟';

  @override
  String get pasteOfflineHelpDesktop =>
      'اینترنت کامپیوتر را بررسی کن و دوباره بزن.';

  @override
  String get addServiceHelpDesktop =>
      'لینک اشتراک شیکونتِ سرویسِ دیگرت را کپی کن، بعد این دکمه را بزن. سرویس کنار بقیه، روی همین کامپیوتر می‌آید.';

  @override
  String get serviceAlreadyHereDesktop =>
      'این سرویس از قبل روی این کامپیوتر هست.';

  @override
  String get removeServiceBodyDesktop =>
      'این سرویس از این کامپیوتر پاک می‌شود. خودِ سرویس سر جایش است و با همان لینک برمی‌گردد.';

  @override
  String get removeServiceBodyConnectedDesktop =>
      'اتصال قطع می‌شود و این سرویس از این کامپیوتر پاک می‌شود. خودِ سرویس سر جایش است و با همان لینک برمی‌گردد.';

  @override
  String get orderScreenHelpDesktop =>
      'هر سرویس را با ≡ بگیر و بالا یا پایین ببر. ترتیب فقط روی همین کامپیوتر است و همان لحظه ذخیره می‌شود.';

  @override
  String get vpnRefusedDesktop =>
      'اجازهٔ تونل داده نشد.\nدوباره وصل شو و «بله» را بزن، یا «پروکسی» را انتخاب کن.';

  @override
  String get vpnMissingDesktop =>
      'تونل روی این کامپیوتر راه نیفتاد.\n«پروکسی» را انتخاب کن، یا از «پشتیبانی» بپرس.';

  @override
  String get busyPortDesktop =>
      'برنامهٔ دیگری جای پروکسی شیکونت را گرفته است.\nآن برنامه را ببند و دوباره وصل شو، یا «تونل» را انتخاب کن.';

  @override
  String get helperFailedDesktop =>
      'تونل روشن نشد.\nدوباره وصل شو، یا «پروکسی» را انتخاب کن.';

  @override
  String get coreDownDesktop =>
      'اتصال شیکونت ناگهان قطع شد.\nدوباره وصل شو. اگر باز قطع شد، از «پشتیبانی» بپرس.';

  @override
  String get coreStartDesktop =>
      'اتصال شیکونت راه نیفتاد.\nدوباره وصل شو. اگر باز هم نشد، از «پشتیبانی» بپرس.';

  @override
  String get subCancelDesktop => 'برای لغو بزن';

  @override
  String get subRetryDesktop => 'دوباره بزن';

  @override
  String get noServiceHelpDesktop =>
      'سرویست روی حساب تلگرام دیگری است؟ اول در خودِ تلگرام به همان حساب برو، بعد «ورود با حساب دیگر» را بزن.';

  @override
  String errorConnectDesktop(String server, int seconds) {
    final intl.NumberFormat secondsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String secondsString = secondsNumberFormat.format(seconds);

    return '$server تا $secondsString ثانیه جواب نداد. دوباره بزن، یا از فهرست سرور دیگری انتخاب کن.';
  }

  @override
  String get loginTelegramNoteDesktop =>
      'تلگرام باز می‌شود؛ در ربات شیکونت «تأیید» را بزن.';

  @override
  String get noServiceHelpPasteDesktop =>
      'لینک اشتراکت را کپی کن، بعد «چسباندن لینک اشتراک» را بزن.\nلینک نداری؟ از «پشتیبانی» بپرس.';

  @override
  String get otherServiceHintDesktop =>
      'با زدنِ یک سرور، اتصال به این سرویس می‌رود.';

  @override
  String get pasteEmptyHelpDesktop => 'لینک اشتراکت را کپی کن، بعد دوباره بزن.';

  @override
  String get otherDeviceScanDesktop =>
      'گوشی‌ای با تلگرام داری؟ این کد تصویری را با دوربینش اسکن کن.';

  @override
  String get refreshDirectHintDesktop =>
      'از اینترنتِ خودِ این کامپیوتر، حتی وقتی وصلی';

  @override
  String get updateFailedDirectOffDesktop =>
      'از اینترنتِ خودِ این کامپیوتر جواب نیامد. با همین سرورها وصل شو، بعد از راه سرور امتحان کن.';

  @override
  String get updateFailedDirectDesktop =>
      'از اینترنتِ خودِ این کامپیوتر جواب نیامد. از راه سرور امتحان کن.';

  @override
  String get updateFailedPanelDesktop =>
      'سرور اشتراکِ شیکو الان جواب نمی‌دهد؛ ایراد از این کامپیوتر نیست. همین سرورها کار می‌کنند و خودش کمی بعد دوباره امتحان می‌کند.';

  @override
  String get modeLabel => 'روش اتصال';

  @override
  String get modeProxy => 'پروکسی';

  @override
  String get modeTunnel => 'تونل';

  @override
  String get modeProxyHint =>
      'فقط مرورگر و برنامه‌هایی که از پروکسی ویندوز پیروی می‌کنند.';

  @override
  String get modeTunnelHint => 'همهٔ برنامه‌ها از شیکونت می‌روند، حتی بازی‌ها.';

  @override
  String get localProxyLabel => 'پروکسی:';

  @override
  String get localProxyCopy => 'کپی';

  @override
  String get localProxyCopied => 'کپی شد';

  @override
  String trayOff(String app) {
    return '$app · قطع';
  }

  @override
  String trayConnecting(String app) {
    return '$app · در حال اتصال';
  }

  @override
  String trayOn(String app, String server) {
    return '$app · وصل، $server';
  }

  @override
  String get trayHeadOff => 'قطع';

  @override
  String get trayHeadSignIn => 'اول وارد شو';

  @override
  String get trayHeadNoService => 'سرویسی نداری';

  @override
  String trayHeadConnecting(String server) {
    return 'در حال اتصال · $server';
  }

  @override
  String trayHeadOn(String server) {
    return 'وصل · $server';
  }

  @override
  String get trayConnect => 'وصل شدن';

  @override
  String get trayDisconnect => 'قطع کردن';

  @override
  String trayOpen(String app) {
    return 'باز کردن $app';
  }

  @override
  String get trayExit => 'خروج';

  @override
  String closedToTrayTitle(String app) {
    return '$app کنار ساعت است';
  }

  @override
  String closedToTrayBody(String app) {
    return 'اتصال برقرار می‌ماند. برای باز کردن، روی نماد $app کنار ساعت دوبار کلیک کن. برای بستن کامل، روی نماد کلیک راست کن و «خروج» را بزن.';
  }

  @override
  String get windowMinimize => 'کوچک کردن';

  @override
  String get windowMaximize => 'بزرگ کردن';

  @override
  String get windowRestore => 'اندازهٔ قبلی';

  @override
  String get windowClose => 'بستن';

  @override
  String get windowsGroup => 'ویندوز';

  @override
  String get autoStart => 'با ویندوز باز شود';

  @override
  String get autoStartHelp => 'کنار ساعت، بی‌اتصال';

  @override
  String get updateNotice => 'خبر نسخهٔ تازه با پیام ویندوز';

  @override
  String get updateNoticeHelp => 'یک بار برای هر نسخه';

  @override
  String updateNoticeTitle(String app) {
    return 'نسخهٔ تازهٔ $app آمده';
  }

  @override
  String get updateNoticeBody =>
      'برای دیدن و نصب، روی همین پیام کلیک کن. اگر این پیام را نمی‌خواهی، در «تنظیمات»، بخش «ویندوز»، خاموشش کن.';

  @override
  String get logsTitle => 'گزارش‌ها';

  @override
  String logsRowHelp(int days) {
    final intl.NumberFormat daysNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String daysString = daysNumberFormat.format(days);

    return 'آنچه برنامه در $daysString روز گذشته ثبت کرده';
  }

  @override
  String get logsConnection => 'اتصال';

  @override
  String get logsSubscription => 'اشتراک';

  @override
  String get logsCore => 'هسته';

  @override
  String get logsErrors => 'خطاها';

  @override
  String get logsCaption => 'برای پشتیبانی؛ متن خط‌ها انگلیسی و فنی است.';

  @override
  String logsToday(String date) {
    return 'امروز · $date';
  }

  @override
  String logsYesterday(String date) {
    return 'دیروز · $date';
  }

  @override
  String logsJalaliDay(String weekday, String day, String month) {
    return '$weekday $day $month';
  }

  @override
  String get logsEmptyTitle => 'هنوز چیزی ثبت نشده';

  @override
  String logsEmptyHelp(int days) {
    final intl.NumberFormat daysNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String daysString = daysNumberFormat.format(days);

    return 'هر چه برنامه در این بخش ثبت کند، تا $daysString روز این‌جا می‌ماند.';
  }

  @override
  String get connectionGroup => 'اتصال';

  @override
  String get iranDirect => 'سایت‌های ایرانی بدون فیلترشکن';

  @override
  String get iranDirectHelp =>
      'بانک، درگاه پرداخت و سایت‌های ایرانی مستقیم باز می‌شوند، حتی وقتی وصلی.';

  @override
  String get coresGroup => 'هسته‌ها';

  @override
  String get coresNote =>
      'هر نوع سرور با کدام هسته وصل شود. اگر مطمئن نیستی، دست نزن.';

  @override
  String get protocolVless => 'VLESS';

  @override
  String get protocolWireguard => 'WireGuard';

  @override
  String get protocolOpenvpn => 'OpenVPN';

  @override
  String get protocolSsh => 'SSH';

  @override
  String get coreMihomo => 'mihomo';

  @override
  String get coreXray => 'Xray';

  @override
  String get coreSingBox => 'sing-box';

  @override
  String get coreWireguard => '⁨WireGuard⁩ رسمی';

  @override
  String get coreOpenvpn => '⁨OpenVPN⁩ رسمی';

  @override
  String get coreDefault => 'پیش‌فرض';

  @override
  String get coreWireguardHelp => 'موتور برنامهٔ رسمی ⁨WireGuard⁩';

  @override
  String get coreOpenvpnHelp => 'موتور برنامهٔ رسمی ⁨OpenVPN⁩';

  @override
  String get coreSoon => 'به‌زودی';

  @override
  String get coreSingBoxVless =>
      'بعضی سرورهای ⁨VLESS⁩ را بلد نیست؛ آن‌ها با ⁨mihomo⁩ وصل می‌شوند.';

  @override
  String coreTunnelOnly(String mode) {
    return 'فقط در حالت «$mode»';
  }

  @override
  String coreProxyNow(String mode) {
    return 'الان حالت «$mode» است.';
  }

  @override
  String coreProxyFallback(
    String proxy,
    String protocol,
    String tunnel,
    String core,
  ) {
    return 'در حالت «$proxy»، سرورهای $protocol با ⁨mihomo⁩ وصل می‌شوند؛ در «$tunnel»، با $core.';
  }

  @override
  String corePickTitle(String protocol) {
    return '$protocol با کدام هسته وصل شود؟';
  }

  @override
  String corePickForAll(String protocol) {
    return 'انتخابت برای همهٔ سرورهای $protocol است.';
  }

  @override
  String get corePickAgain => 'اگر وصلی، چند ثانیه قطع و دوباره وصل می‌شوی.';

  @override
  String viaCore(String core) {
    return 'با $core';
  }

  @override
  String coreSwitching(String core) {
    return 'در حال وصل شدن با «$core»…';
  }

  @override
  String coreSwitched(String core) {
    return 'حالا با «$core» وصلی.';
  }

  @override
  String get aboutLicenses => 'مجوز نرم‌افزارهای دیگر';

  @override
  String get aboutLicensesHelp =>
      'هسته‌ها و کتابخانه‌هایی که شیکونت با آن‌ها ساخته شده';

  @override
  String get licensesTitle => 'مجوزها';

  @override
  String get licensesOthers => 'نرم‌افزارهای دیگر';

  @override
  String get licenseScrollTv => 'بالا و پایینِ ریموت متن را می‌برد';

  @override
  String licenseCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString مجوز';
  }

  @override
  String get warpVia => 'از راه ⁨WARP⁩';

  @override
  String get warpSwitch => '⁨WARP⁩، وقتی سرورها بسته‌اند';

  @override
  String get warpSwitchHelp =>
      'سرورهایی که مستقیم جواب ندهند، از راه شبکهٔ ⁨Cloudflare⁩ وصل می‌شوند. در این اتصال‌ها ⁨Cloudflare⁩ آی‌پی تو را می‌بیند.';

  @override
  String warpFirst(String server) {
    return '‏«$server» مستقیم جواب نداد؛ از راه ⁨WARP⁩ وصل می‌شوی.\nبار اول ممکن است نیم دقیقه طول بکشد.';
  }

  @override
  String get warpAgain => 'از راه ⁨WARP⁩ وصل می‌شوی…';

  @override
  String get warpFailBothTouch =>
      'نه مستقیم جواب آمد، نه از راه ⁨WARP⁩.\nاینترنت این گوشی را بررسی کن. اگر وصل بود، از «پشتیبانی» بپرس.';

  @override
  String get warpOffTouch =>
      'سرورها از اینترنت این گوشی جواب ندادند، و ⁨WARP⁩ خاموش است.';

  @override
  String get warpFailBothTv =>
      'نه مستقیم جواب آمد، نه از راه ⁨WARP⁩.\nاینترنت این تلویزیون را بررسی کن. اگر وصل بود، از «پشتیبانی» بپرس.';

  @override
  String get warpOffTv =>
      'سرورها از اینترنت این تلویزیون جواب ندادند، و ⁨WARP⁩ خاموش است.';

  @override
  String get warpFailBothDesktop =>
      'نه مستقیم جواب آمد، نه از راه ⁨WARP⁩.\nاینترنت این کامپیوتر را بررسی کن. اگر وصل بود، از «پشتیبانی» بپرس.';

  @override
  String get warpOffDesktop =>
      'سرورها از اینترنت این کامپیوتر جواب ندادند، و ⁨WARP⁩ خاموش است.';

  @override
  String get warpTurnOn => 'روشن کردن ⁨WARP⁩';

  @override
  String get warpNote => 'با این کار، ⁨Cloudflare⁩ آی‌پی تو را می‌بیند.';

  @override
  String get warpLoginWaitTitle => 'سرور شیکونت مستقیم جواب نداد.';

  @override
  String get warpLoginWait =>
      'کد ورود را از راه ⁨WARP⁩ می‌گیریم؛ بار اول ممکن است نیم دقیقه طول بکشد.';

  @override
  String get warpLoginFailTouch =>
      'سرور شیکونت از اینترنت این گوشی جواب نداد. شاید بسته است؛ از راه ⁨WARP⁩ امتحان کن.';

  @override
  String get warpLoginFailTv =>
      'سرور شیکونت از اینترنت این تلویزیون جواب نداد. شاید بسته است؛ از راه ⁨WARP⁩ امتحان کن.';

  @override
  String get warpLoginFailDesktop =>
      'سرور شیکونت از اینترنت این کامپیوتر جواب نداد. شاید بسته است؛ از راه ⁨WARP⁩ امتحان کن.';

  @override
  String get warpTry => 'امتحان از راه ⁨WARP⁩';

  @override
  String get aboutWarp =>
      'اگر ⁨WARP⁩ را روشن کنی، سرورهایی که مستقیم جواب ندهند از راه شبکهٔ ⁨Cloudflare⁩ وصل می‌شوند؛ ورود و به‌روزرسانی اشتراک هم اگر مستقیم نشوند، از همین راه می‌روند. ⁨Cloudflare⁩ فقط در همین اتصال‌ها آی‌پی تو را می‌بیند.';

  @override
  String get updatingWarp => 'مستقیم نشد؛ از راه ⁨WARP⁩…';

  @override
  String get updateFailedWarp =>
      'نه مستقیم جواب آمد، نه از راه ⁨WARP⁩. با همین سرورها وصل شو، بعد از راه سرور امتحان کن؛ اگر باز نشد، از «پشتیبانی» بپرس.';
}
