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
  String get msUnit => 'ms';

  @override
  String get noResponse => 'بی‌پاسخ';

  @override
  String errorConnect(String server, int seconds) {
    final intl.NumberFormat secondsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String secondsString = secondsNumberFormat.format(seconds);

    return '$server تا $secondsString ثانیه جواب نداد. دوباره بزن، یا از فهرست سرور دیگری انتخاب کن.';
  }

  @override
  String get errorServer => 'سرور عوض نشد.';

  @override
  String get errorAdd => 'سرویس اضافه نشد.';

  @override
  String get initError => 'اپ باز نشد.';
}
