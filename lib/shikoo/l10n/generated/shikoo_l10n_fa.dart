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
}
