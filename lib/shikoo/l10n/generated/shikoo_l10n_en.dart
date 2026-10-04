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

  @override
  String get refresh => 'Update';

  @override
  String get refreshServers => 'Update servers';

  @override
  String updatedAgo(String ago) {
    return 'Updated · $ago';
  }

  @override
  String get updateFailed => 'Not updated';

  @override
  String get updating => 'Updating…';

  @override
  String updateFailedAgo(String ago) {
    return 'Not updated · list from $ago';
  }

  @override
  String get agoJustNow => 'just now';

  @override
  String agoMinutes(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String agoHours(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String agoDays(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get updateFailedTitle => 'Couldn\'t update.';

  @override
  String get updateFailedTouch =>
      'Check your internet and tap again. Until then, connect with these servers.';

  @override
  String get updateFailedTv =>
      'Check your internet and press OK again. Until then, connect with these servers.';

  @override
  String serversAdded(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString new servers.',
      one: '1 new server.',
    );
    return '$_temp0';
  }

  @override
  String serverRemoved(String name) {
    return '“$name” was removed.';
  }

  @override
  String serversRemoved(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString servers were removed.',
      one: '1 server was removed.',
    );
    return '$_temp0';
  }

  @override
  String selectedRemoved(String name) {
    return '“$name” is no longer in your subscription.';
  }

  @override
  String selectedReplaced(String name) {
    return 'The fastest server, “$name”, was picked instead.';
  }

  @override
  String selectedMoved(String name) {
    return 'The connection moved to the fastest server, “$name”, right away.';
  }

  @override
  String selectedMovedFirst(String name) {
    return 'The connection moved to “$name” right away.';
  }

  @override
  String selectedNoAnswer(String name) {
    return '“$name” didn\'t answer.';
  }

  @override
  String get findingBest => 'Finding the best server…';

  @override
  String get connectsToFirst =>
      'You\'ll connect to the first server that answers.';

  @override
  String get noServerAnswered => 'No server answered';

  @override
  String get noServerAnsweredHelpTouch =>
      'Check this phone\'s internet.\nIf it works, ask Support.';

  @override
  String get noServerAnsweredHelpTv =>
      'Check this TV\'s internet.\nIf it works, ask Support.';

  @override
  String get newBadge => 'New';

  @override
  String get serversTitle => 'Servers';

  @override
  String get fastestFirst => 'Fastest first';

  @override
  String get sortsOnLeave => 'Sorts when you leave the list';

  @override
  String get pingAll => 'Ping all';

  @override
  String pingProgress(int done, int total) {
    final intl.NumberFormat doneNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String doneString = doneNumberFormat.format(done);
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return 'Ping $doneString of $totalString';
  }

  @override
  String get measuring => 'Measuring';

  @override
  String get searchServers => 'Search servers';

  @override
  String get searchNoMatch => 'No server with that name';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get renewTitle => 'Renew on your phone';

  @override
  String get renewHelp =>
      'Scan with your phone\'s camera; the Shikoo bot opens the renewal list of your services.';

  @override
  String get supportTitle => 'Support on your phone';

  @override
  String get supportHelp =>
      'Scan with your phone\'s camera to chat with Shikoo support on Telegram.';

  @override
  String get close => 'Close';

  @override
  String get back => 'Back';

  @override
  String get backHintTv => 'Press Back on the remote to go back';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeAuto => 'Auto';

  @override
  String get language => 'Language';

  @override
  String get languageFa => 'فارسی';

  @override
  String get languageEn => 'English';

  @override
  String get account => 'Account';

  @override
  String get logout => 'Log out';

  @override
  String get logoutHelpTv => 'Removes the services from this TV.';

  @override
  String get logoutHelpTouch => 'Removes the services from this phone.';

  @override
  String get logoutBodyTv =>
      'You\'ll be disconnected and the services removed from this TV. Your subscription stays as it is in the Shikoo bot.';

  @override
  String get logoutBodyTouch =>
      'You\'ll be disconnected and the services removed from this phone. The services themselves stay as they are; they come back with the same link or with Telegram.';

  @override
  String get cancel => 'Cancel';

  @override
  String get appSection => 'App';

  @override
  String get version => 'Version';

  @override
  String get about => 'About';

  @override
  String get aboutSummary =>
      'Free software under GPL-3.0, built on FlClash and mihomo';

  @override
  String get aboutFree =>
      'Shikoo is free software, released under the GPL-3.0 license.';

  @override
  String get aboutBasedOn =>
      'It is built on two free programs: FlClash by chen08209 and the mihomo core by MetaCubeX. Thanks to their makers.';

  @override
  String get aboutSource =>
      'You can get the source code of this version from Support.';

  @override
  String get aboutLicense => 'License text: gnu.org/licenses/gpl-3.0';

  @override
  String selectedDown(String name) {
    return '“$name” isn\'t answering.\nPick another server from the list.';
  }

  @override
  String get vpnRefused =>
      'Permission to connect wasn\'t given.\nConnect again and allow it in Android\'s window.';

  @override
  String get vpnMissing =>
      'This device doesn\'t show Android\'s permission window.\nAsk Support.';

  @override
  String get logoutTitleTv => 'Remove the services from this TV?';

  @override
  String get logoutTitleTouch => 'Remove the services from this phone?';

  @override
  String get removeButton => 'Remove';

  @override
  String renewPickInList(String username) {
    return 'In the bot\'s list, tap the service $username; if it isn\'t there, check the next page of the list.';
  }

  @override
  String get powerNoService => 'No service';

  @override
  String get noServiceTitleTv => 'No service on this TV';

  @override
  String get noServiceTitleTouch => 'No service on this phone';

  @override
  String get noServiceHelp => 'Ask Support to bring it back.';
}
