// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'shikoo_l10n.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class ShikooL10nEn extends ShikooL10n {
  ShikooL10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Shikoo';

  @override
  String get brandMark => 'S';

  @override
  String get settings => 'Settings';

  @override
  String get renew => 'Renew';

  @override
  String get support => 'Support';

  @override
  String get statusActive => 'Active';

  @override
  String get statusExpired => 'Expired';

  @override
  String get statusExhausted => 'Volume used up';

  @override
  String get usedLabel => 'Used:';

  @override
  String ofTotalGb(String total) {
    return 'of $total GB';
  }

  @override
  String get remainingLabel => 'Left:';

  @override
  String gb(String amount) {
    return '$amount GB';
  }

  @override
  String get unlimited => 'Unlimited';

  @override
  String validUntil(String date) {
    return 'Valid until $date';
  }

  @override
  String daysLeft(int days) {
    final intl.NumberFormat daysNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String daysString = daysNumberFormat.format(days);

    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$daysString days left',
      one: '1 day left',
    );
    return '$_temp0';
  }

  @override
  String get jalaliMonths =>
      'Farvardin|Ordibehesht|Khordad|Tir|Mordad|Shahrivar|Mehr|Aban|Azar|Dey|Bahman|Esfand';

  @override
  String jalaliDate(String day, String month, String year) {
    return '$day $month $year';
  }

  @override
  String get powerConnect => 'Connect';

  @override
  String get powerOn => 'Connected';

  @override
  String get powerConnecting => 'Connecting…';

  @override
  String get powerFailed => 'Couldn\'t connect';

  @override
  String get subCancelTv => 'OK button: cancel';

  @override
  String get subCancelTouch => 'Tap to cancel';

  @override
  String get subRetryTv => 'OK button: retry';

  @override
  String get subRetryTouch => 'Tap to retry';

  @override
  String get tvHint => 'Press OK on the remote to connect';

  @override
  String get noService => 'No service yet';

  @override
  String get loadingServers => 'Getting the server list…';

  @override
  String get msUnit => 'ms';

  @override
  String get noResponse => 'No response';

  @override
  String errorConnect(String server, int seconds) {
    final intl.NumberFormat secondsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String secondsString = secondsNumberFormat.format(seconds);

    return '$server didn\'t answer in $secondsString seconds.\nTry another server.';
  }

  @override
  String get errorServer => 'Couldn\'t switch the server.';

  @override
  String get errorAdd => 'Couldn\'t add the service.';

  @override
  String get initError => 'The app couldn\'t start.';
}
