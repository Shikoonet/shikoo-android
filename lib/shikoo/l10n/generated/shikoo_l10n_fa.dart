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
}
