// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'shikoo_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class ShikooL10nFa extends ShikooL10n {
  ShikooL10nFa([String locale = 'fa']) : super(locale);

  @override
  String get appTitle => 'شیکو';

  @override
  String get brandMark => 'ش';

  @override
  String get settings => 'تنظیمات';

  @override
  String get renew => 'تمدید';

  @override
  String get support => 'پشتیبانی';

  @override
  String get statusActive => 'فعال';

  @override
  String get statusExpired => 'تاریخ انقضا گذشته';

  @override
  String get statusExhausted => 'حجم تمام شده';

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
    return '$day $month $year';
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
  String get tvHint => 'دکمهٔ وسطِ ریموت را بزن تا وصل شوی';

  @override
  String get noService => 'هنوز سرویسی اضافه نشده';

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
  String get errorAdd => 'سرویس اضافه نشد.';

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

    return '$countString دقیقه پیش';
  }

  @override
  String agoHours(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString ساعت پیش';
  }

  @override
  String agoDays(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString روز پیش';
  }

  @override
  String get updateFailedTitle => 'به‌روز نشد.';

  @override
  String get updateFailedTouch =>
      'اینترنت را بررسی کن و دوباره بزن. تا آن موقع با همین سرورها وصل شو.';

  @override
  String get updateFailedTv =>
      'اینترنت را بررسی کن و دکمهٔ وسط را دوباره بزن. تا آن موقع با همین سرورها وصل شو.';

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
  String get findingBest => 'در حال یافتن بهترین سرور…';

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
  String get pingAll => 'پینگ همه';

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
  String get renewHelp =>
      'با دوربین گوشی اسکن کن؛ ربات شیکو سرویس‌هایت را برای تمدید باز می‌کند.';

  @override
  String get supportTitle => 'پشتیبانی با گوشی';

  @override
  String get supportHelp =>
      'با دوربین گوشی اسکن کن تا گفتگو با پشتیبانی شیکو در تلگرام باز شود.';

  @override
  String get close => 'بستن';

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
  String get logoutHelpTv => 'سرویس‌ها از این تلویزیون پاک می‌شوند';

  @override
  String get logoutHelpTouch => 'سرویس‌ها از این گوشی پاک می‌شوند';

  @override
  String get logoutTitle => 'سرویس‌ها پاک شوند؟';

  @override
  String get logoutBodyTv =>
      'اتصال قطع می‌شود و سرویس‌ها از این تلویزیون پاک می‌شوند. اشتراکت در ربات شیکو سر جایش می‌ماند.';

  @override
  String get logoutBodyTouch =>
      'اتصال قطع می‌شود و سرویس‌ها از این گوشی پاک می‌شوند. اشتراکت در ربات شیکو سر جایش می‌ماند.';

  @override
  String get cancel => 'انصراف';

  @override
  String get appSection => 'اپ';

  @override
  String get version => 'نسخه';

  @override
  String get about => 'درباره';

  @override
  String get aboutSummary =>
      'نرم‌افزار آزاد با مجوز GPL-3.0، بر پایهٔ FlClash و mihomo';

  @override
  String get aboutFree =>
      'شیکو نرم‌افزار آزاد است و با مجوز GPL-3.0 منتشر می‌شود.';

  @override
  String get aboutBasedOn =>
      'بر پایهٔ FlClash (از chen08209) و هستهٔ اتصال mihomo (از MetaCubeX) ساخته شده است؛ سپاس از سازندگان هر دو.';

  @override
  String get aboutSource => 'سورس همین نسخه را می‌توانی از «پشتیبانی» بگیری.';

  @override
  String get aboutLicense => 'متن مجوز: gnu.org/licenses/gpl-3.0';

  @override
  String selectedDown(String name) {
    return '«$name» جواب نمی‌دهد.\nسرور دیگری را از فهرست انتخاب کن.';
  }

  @override
  String get vpnRefused =>
      'اجازهٔ VPN داده نشد.\nدوباره وصل شو و در پنجرهٔ اندروید اجازه بده.';

  @override
  String get vpnMissing =>
      'این دستگاه پنجرهٔ اجازهٔ VPN ندارد.\nاز «پشتیبانی» بپرس.';
}
