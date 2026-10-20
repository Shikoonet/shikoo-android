// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'shikoo_l10n.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class ShikooL10nEn extends ShikooL10n {
  ShikooL10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'ShikooNet';

  @override
  String get appTitleTest => 'ShikooNet Test';

  @override
  String get settings => 'Settings';

  @override
  String get renew => 'Renew';

  @override
  String get support => 'Support';

  @override
  String get statusActive => 'Active';

  @override
  String get chipExpired => 'Expired';

  @override
  String get stateExhausted => 'Out of data';

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
      other: '$countString minutes ago',
      one: '1 minute ago',
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
      other: '$countString hours ago',
      one: '1 hour ago',
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
      other: '$countString days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get updateFailedTitle => 'Couldn\'t update.';

  @override
  String get refreshWays => 'Choose how to update';

  @override
  String get refreshDirect => 'Update directly';

  @override
  String get refreshDirectHint =>
      'Through this device\'s own internet, even while connected';

  @override
  String get refreshViaServer => 'Update through the server';

  @override
  String refreshViaServerHint(String server) {
    return 'Through $server';
  }

  @override
  String get refreshConnectFirst => 'Connect first';

  @override
  String get updatingDirect => 'Updating directly…';

  @override
  String get updatingViaServer => 'Updating through the server…';

  @override
  String get updatingFallback => 'No direct answer; trying the server…';

  @override
  String get updateFailedDirectOff =>
      'No answer through this device\'s own internet. Connect with these servers, then try through the server.';

  @override
  String get updateFailedDirect =>
      'No answer through this device\'s own internet. Try through the server.';

  @override
  String updateFailedViaServer(String server) {
    return 'No answer through $server. Try directly, or pick another server.';
  }

  @override
  String updateFailedBoth(String server) {
    return 'No answer directly or through $server. Pick another server and try again.';
  }

  @override
  String get updateFailedPanel =>
      'ShikooNet\'s subscription server isn\'t answering right now; it\'s not your device. These servers still work, and it tries again by itself shortly.';

  @override
  String get updateFailedConnectFirst => 'Connect first.';

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
  String switchingTo(String name) {
    return 'Moving to “$name”…';
  }

  @override
  String switchedTo(String name) {
    return 'Now connected through “$name”.';
  }

  @override
  String switchKept(String name) {
    return 'Still on “$name”. Try another server.';
  }

  @override
  String switchFailedTv(String name) {
    return '“$name” didn\'t answer.\nTry another server.';
  }

  @override
  String get findingBest => 'Finding the best server…';

  @override
  String get autoPick => 'The server is picked automatically';

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
  String get sortsOnPing => 'Press “Ping” to sort';

  @override
  String get ping => 'Ping';

  @override
  String get pingServers => 'Ping servers';

  @override
  String get inUseLabel => 'In use';

  @override
  String get otherServiceHint =>
      'Tap a server to move your connection to this service.';

  @override
  String get otherServiceNow => 'You\'re now connected through this service.';

  @override
  String get otherServiceCaptionTv =>
      'Press a server to move your connection here';

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
  String get renewHelpList =>
      'Scan with your phone\'s camera; the ShikooNet bot opens the renewal list of your services.';

  @override
  String get supportTitle => 'Support on your phone';

  @override
  String get supportHelpTv =>
      'Scan with your phone\'s camera to open a chat with ShikooNet support in Telegram.';

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
      'You\'ll be disconnected and the services removed from this TV. Your subscription stays as it is in the ShikooNet bot.';

  @override
  String get logoutBodyTouch =>
      'You\'ll be disconnected and the services removed from this phone. The services themselves stay as they are; they come back with the same link or with Telegram.';

  @override
  String get cancelButton => 'Cancel';

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
      'ShikooNet is free software, released under the GPL-3.0 license.';

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

  @override
  String get noServiceHelpPaste =>
      'Copy your subscription link, then tap “Paste subscription link”.\nNo link? Ask Support.';

  @override
  String get pasteLink => 'Paste subscription link';

  @override
  String get pasteChecking => 'Checking the link…';

  @override
  String get pasteEmptyTitle => 'The clipboard is empty.';

  @override
  String get pasteEmptyHelp => 'Copy your subscription link, then tap again.';

  @override
  String get pasteNotShikooTitle => 'This isn\'t a ShikooNet link.';

  @override
  String get pasteNotShikooHelp =>
      'Only a ShikooNet subscription link works: the one you got from the ShikooNet bot or your reseller.';

  @override
  String get pasteRevokedTitle => 'This link was revoked or has expired.';

  @override
  String get pasteRevokedHelp =>
      'Get a new link from the ShikooNet bot or your reseller.';

  @override
  String get pasteOfflineTitle => 'No internet connection.';

  @override
  String get pasteOfflineHelp => 'Check your phone\'s internet and tap again.';

  @override
  String get pasteAnother => 'Paste another link';

  @override
  String get pasteAnotherHelp => 'For another service you have';

  @override
  String get powerExpired => 'Expired';

  @override
  String get renewToConnect => 'Renew to connect again.';

  @override
  String get serversAfterRenew => 'The server list comes back after you renew.';

  @override
  String get expiredEnded => 'Ended';

  @override
  String get summaryExhausted => 'Out of data. Renew to use it again.';

  @override
  String summaryExpired(String date) {
    return 'Expired on $date. Renew to use it again.';
  }

  @override
  String get pasteUnavailableTitle => 'Couldn\'t open the link right now.';

  @override
  String get pasteUnavailableHelp =>
      'Try again in a bit; if it still won\'t open, ask Support.';

  @override
  String get loginTagline => 'For ShikooNet customers';

  @override
  String get loginTelegram => 'Sign in with Telegram';

  @override
  String get loginTelegramNote =>
      'Telegram opens; tap “Approve” in the ShikooNet bot.';

  @override
  String get noTelegramHere => 'No Telegram on this phone?';

  @override
  String get waitingTitle => 'No approval yet.';

  @override
  String get waitingHelp =>
      'If Telegram only opens with a VPN, turn that on first, then open Telegram again.';

  @override
  String get reopenTelegram => 'Open Telegram again';

  @override
  String get approveElsewhere => 'Approve from another device';

  @override
  String get codeExpiredNote => 'This code has expired.';

  @override
  String get otherDeviceTitle => 'Approve from another device';

  @override
  String get otherDeviceScan =>
      'Have another phone with Telegram? Scan this code with its camera.';

  @override
  String get otherDeviceComputer =>
      'Telegram on a computer? Send this code to the ShikooNet bot:';

  @override
  String get codeOnlyYou =>
      'Only type this code in the bot yourself; never give it to anyone.';

  @override
  String get otherDeviceFine =>
      'The code works for 10 minutes. After you approve in the bot, this screen goes home by itself.';

  @override
  String get tvLoginLead => 'Scan with your phone\'s camera and tap “Approve”';

  @override
  String get tvLoginVpnHint =>
      'Telegram only opens with a VPN? Turn it on on your phone, then scan.';

  @override
  String get tvLoginComputer =>
      'Telegram on a computer?\nSend this code to the bot:';

  @override
  String get codeLifetime => 'This code works for 10 minutes.';

  @override
  String get codeExpiredLead =>
      '10 minutes passed and this code expired. Get a new one.';

  @override
  String get previousCode => 'Previous code';

  @override
  String get newCode => 'New code';

  @override
  String get codeExpiredOverlay => 'This code expired';

  @override
  String accountWithUsername(String name, String username) {
    return '$name ($username)';
  }

  @override
  String get approvedTitle => 'Signed in';

  @override
  String approvedBodyTv(String account) {
    return 'This TV is now linked to the Telegram account $account, with these services:';
  }

  @override
  String approvedBodyTouch(String account) {
    return 'This phone is now linked to the Telegram account $account, with these services:';
  }

  @override
  String approvedBodyOneTv(String account) {
    return 'This TV is now linked to the Telegram account $account, with this service:';
  }

  @override
  String approvedBodyOneTouch(String account) {
    return 'This phone is now linked to the Telegram account $account, with this service:';
  }

  @override
  String get servicesComing => 'Your services are on their way…';

  @override
  String get continueButton => 'Continue';

  @override
  String get notMyAccount => 'This isn\'t my account';

  @override
  String get servicesFailedTitle => 'Your services didn\'t arrive';

  @override
  String servicesFailedBodyTv(String account) {
    return 'You signed in with the Telegram account $account, but the list of services didn\'t come from the server. Check this TV\'s internet and try again.';
  }

  @override
  String servicesFailedBodyTouch(String account) {
    return 'You signed in with the Telegram account $account, but the list of services didn\'t come from the server. Check this phone\'s internet and try again.';
  }

  @override
  String get retry => 'Try again';

  @override
  String get noServiceTitle => 'This account has no service';

  @override
  String noServiceBodyTouch(String account) {
    return 'You signed in with the Telegram account $account, but no ShikooNet service is linked to it.';
  }

  @override
  String noServiceBodyTv(String account) {
    return 'You signed in with the Telegram account $account, but no service is linked to it.';
  }

  @override
  String get noServiceHelpTouch =>
      'Is your service on another Telegram account? Switch to it in Telegram first, then tap “Use another account”.';

  @override
  String get noServiceHelpTv =>
      'Is your service on another account? Switch to it in Telegram on your phone and scan again.';

  @override
  String get otherAccount => 'Use another account';

  @override
  String get askSupportLink => 'Think this is wrong? Ask Support';

  @override
  String get rejectedTitle => 'Sign-in declined';

  @override
  String get rejectedBodyTv =>
      '“Decline” was tapped in Telegram, so this TV isn\'t linked. If that was a mistake, try again.';

  @override
  String get rejectedBodyTouch =>
      '“Decline” was tapped in Telegram, so this phone isn\'t linked. If that was a mistake, try again.';

  @override
  String signedInWith(String name) {
    return 'Signed in as $name';
  }

  @override
  String get telegramAccount => 'Telegram account';

  @override
  String telegramAccountUsername(String username) {
    return 'Telegram account $username';
  }

  @override
  String get logoutHelpSignedInTouch =>
      'Removes this account\'s services from this device; your subscriptions stay as they are.';

  @override
  String get logoutHelpSignedInTv =>
      'Removes the services from this TV; your subscriptions stay as they are.';

  @override
  String get logoutSignedInTitle => 'Sign out?';

  @override
  String get logoutSignedInBodyTouch =>
      'You\'ll be disconnected and this device unlinked from your Telegram account. This account\'s services are removed from it, but a service whose link you pasted yourself stays. Your subscriptions stay as they are.';

  @override
  String get logoutSignedInBodyTv =>
      'You\'ll be disconnected, this TV will be unlinked from your Telegram account and the services removed from it. Your subscriptions stay as they are; sign in with Telegram again whenever you like.';

  @override
  String get signInRow => 'Sign in with Telegram';

  @override
  String get signInRowHelp =>
      'You haven\'t signed in yet. Signing in brings all your services automatically.';

  @override
  String get renewHelpDirect =>
      'Scan with your phone\'s camera; the ShikooNet bot opens the renewal page of this service.';

  @override
  String get codeFailedTitle => 'The sign-in code didn\'t arrive.';

  @override
  String get openBotTitleTv => 'ShikooNet bot on your phone';

  @override
  String get openBotHelpTv =>
      'Scan with your phone\'s camera to open the ShikooNet bot.';

  @override
  String get codeFetching => 'Getting a code…';

  @override
  String get codeFailedHelpTouch =>
      'Check your phone\'s internet and tap again.';

  @override
  String get codeFailedOverlay => 'No sign-in code';

  @override
  String get codeFailedLeadTv =>
      'The sign-in code didn\'t come from the server. Check this TV\'s internet and try again.';

  @override
  String get noLinkChip => 'No link';

  @override
  String get noLinkHelpTouch => 'Open this service once in the bot';

  @override
  String get noLinkHelpTv =>
      'Open this service once in the bot, then press “Try again”.';

  @override
  String get loadFailedChip => 'Didn\'t load';

  @override
  String get loadFailedHelp =>
      'This service has a link, but its servers didn\'t load just now. Check your internet and try again.';

  @override
  String get openBotTouch => 'Open the bot';

  @override
  String get openBotTv => 'ShikooNet bot';

  @override
  String get summaryExpiredNoDate => 'Expired. Renew to use it again.';

  @override
  String get summaryExpiredNoDateTv =>
      'Expired. After renewing, press “Try again”.';

  @override
  String get summaryExhaustedTv =>
      'Out of data. After renewing, press “Try again”.';

  @override
  String get summaryDisabled => 'Disabled. Renew to use it again.';

  @override
  String get summaryDisabledTv =>
      'Disabled. After renewing, press “Try again”.';

  @override
  String get summaryRemoved =>
      'Disabled, and it can\'t be renewed. Press “Support” to follow it up.';

  @override
  String get summaryNotRenewable =>
      'This service can\'t be renewed; ask “Support” to continue.';

  @override
  String get pastedServicesTitle => 'Services added by link';

  @override
  String get removeService => 'Remove';

  @override
  String removeServiceLabel(String name) {
    return 'Remove $name';
  }

  @override
  String removeServiceTitle(String name) {
    return 'Remove “$name”?';
  }

  @override
  String get removeServiceBody =>
      'It\'s removed from this phone. The service itself stays as it is and comes back with the same link.';

  @override
  String get removeServiceBodyConnected =>
      'You\'ll be disconnected and this service removed from this phone. The service itself stays as it is and comes back with the same link.';

  @override
  String get chipRevoked => 'Link revoked';

  @override
  String get revokedTitle => 'This link was revoked.';

  @override
  String get revokedHelp =>
      'Remove it, or get a new link from the bot or your reseller and paste it with the + at the top of the home screen.';

  @override
  String errorConnectTouch(String server, int seconds) {
    final intl.NumberFormat secondsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String secondsString = secondsNumberFormat.format(seconds);

    return '$server didn\'t answer in $secondsString seconds. Tap again, or pick another server from the list.';
  }

  @override
  String get serviceUnnamed => 'ShikooNet service';

  @override
  String finishedServices(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Finished services ($countString)';
  }

  @override
  String get finishedData => 'Out of data';

  @override
  String get finishedToday => 'Ended today';

  @override
  String finishedDaysAgo(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ended $countString days ago',
      one: 'Ended 1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get finishedNoDate => 'Expired';

  @override
  String get finishedDisabled => 'Disabled';

  @override
  String approvedMoreServices(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'and $countString more services',
      one: 'and 1 more service',
    );
    return '$_temp0';
  }

  @override
  String approvedBodyChooseTouch(String account) {
    return 'This phone is now linked to the Telegram account $account.';
  }

  @override
  String approvedBodyChooseTv(String account) {
    return 'This TV is now linked to the Telegram account $account.';
  }

  @override
  String get chooseServicesTouch => 'Which services should this phone have?';

  @override
  String get chooseServicesTv => 'Which services should this TV have?';

  @override
  String get chooseAtLeastOne => 'Tick at least one service.';

  @override
  String servicesHereTouch(int shown, int total) {
    final intl.NumberFormat shownNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String shownString = shownNumberFormat.format(shown);
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return '$shownString of your account\'s $totalString services are on this phone. To change them, sign out and sign in again.';
  }

  @override
  String get servicesAllHereTouch =>
      'All your account\'s services are on this phone. To change them, sign out and sign in again.';

  @override
  String get changeServicesTv =>
      'To change this TV\'s services, sign out and sign in again.';

  @override
  String get notificationStop => 'Disconnect';

  @override
  String get notificationStopping => 'Disconnecting…';

  @override
  String get shortcutToggle => 'Connect / Disconnect';

  @override
  String get clockWrongTitle => 'Your device\'s date and time are wrong.';

  @override
  String get clockWrongHelp =>
      'In Settings › Date & time, turn on “Automatic” (or set them right), then try again.';

  @override
  String get clockStillWrong => 'The clock is still wrong.';

  @override
  String get dateSettings => 'Date & time settings';

  @override
  String get updateTitle => 'A new version is out';

  @override
  String updateVersionSize(String version, int size) {
    final intl.NumberFormat sizeNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String sizeString = sizeNumberFormat.format(size);

    return 'Version $version, $sizeString MB';
  }

  @override
  String get updateGet => 'Download';

  @override
  String get updateDownloading => 'Downloading…';

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

    return '$percentString%, $doneString of $totalString MB';
  }

  @override
  String get updateReady => 'Ready to install';

  @override
  String get updateInstall => 'Install';

  @override
  String get updateClosesApp =>
      'Installing closes ShikooNet, and the connection if you\'re connected; open it again afterwards.';

  @override
  String get updateDownloadFailedTitle => 'The download stopped.';

  @override
  String get updateDownloadFailedHelp =>
      'Check your internet and try again; it picks up where it stopped.';

  @override
  String get updateBadFileTitle => 'The file arrived damaged.';

  @override
  String get updateBadFileHelp => 'Try again to download it from the start.';

  @override
  String get updateForcedTitle => 'This version needs an update';

  @override
  String updateForcedBody(String version, int size) {
    final intl.NumberFormat sizeNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String sizeString = sizeNumberFormat.format(size);

    return 'To keep using ShikooNet, download and install version $version ($sizeString MB).';
  }

  @override
  String get installPermissionTitle => 'Allow installing';

  @override
  String get installPermissionTouch =>
      'On the next screen, turn on installing for “ShikooNet”, then press your phone’s Back button; the install starts by itself.';

  @override
  String get installPermissionTv =>
      'On the next screen, turn on installing for “ShikooNet”, then press Back on the remote; the install starts by itself.';

  @override
  String get updateNoSpaceTitle => 'Not enough space.';

  @override
  String get updateNoSpaceHelp =>
      'Remove a few apps or files from this device and try again.';

  @override
  String get updateInstallFailed =>
      'The installer didn\'t open; try again or ask Support.';

  @override
  String get installPermissionLegacy =>
      'On the next screen, turn on Unknown sources at the bottom of it, then press Back.';

  @override
  String get installPermissionLegacyTv =>
      'On the next screen, find and turn on Unknown sources, then press Back on the remote.';

  @override
  String get settingsCore => 'Core';

  @override
  String get settingsCoreHelp => 'Updates together with the app.';

  @override
  String get settingsCheckUpdate => 'Check for updates';

  @override
  String get settingsChecking => 'Checking…';

  @override
  String get settingsUpToDate => 'You have the latest version.';

  @override
  String get settingsCheckFailed =>
      'Couldn\'t check; check your internet and try again.';

  @override
  String get reportSendToSupport => 'Send a report to Support';

  @override
  String get reportSendShort => 'Send a report';

  @override
  String get diagTitle => 'Diagnostics and report';

  @override
  String get diagRowHelp => 'If the app isn\'t working right';

  @override
  String get diagInternetGroup => 'Internet';

  @override
  String get diagReportGroup => 'Report';

  @override
  String get diagReportHelp =>
      'If the app isn\'t working right, send Support a report. You see what is sent before it goes.';

  @override
  String get diagReportLater =>
      'The report can’t get through now. When the internet is back, press Try again.';

  @override
  String get reportSupportSheetBody =>
      'If the app isn\'t working right, send a report first so Support can see what happened.';

  @override
  String get reportChatTelegram => 'Chat on Telegram';

  @override
  String get reportCrashTitle => 'The app closed suddenly last time.';

  @override
  String get reportCrashAsk => 'Send us a report about it?';

  @override
  String get reportCrashYes => 'Send';

  @override
  String get reportCrashNo => 'No';

  @override
  String get reportTitle => 'Report to Support';

  @override
  String get reportImageApp => 'What the app drew';

  @override
  String get reportImageScreen => 'What the screen showed';

  @override
  String get reportImagesSwitch => 'Send the screen pictures too';

  @override
  String get reportImageOff => 'Not sent';

  @override
  String get reportWhatIsSent =>
      'Sent: device model and settings, app version, your services’ names and data, your operator and internet status, and the app’s recent activity and errors.';

  @override
  String get reportNeverSent =>
      'Your subscription link and passwords are never sent.';

  @override
  String get reportSend => 'Send';

  @override
  String get reportSending => 'Sending…';

  @override
  String get reportSentTitle => 'Sent';

  @override
  String get reportSentLinked =>
      'Support can see your report; you don\'t need to send anything.';

  @override
  String get reportCodeLabel => 'Report code';

  @override
  String reportCodeSmall(String code) {
    return 'Report code: $code';
  }

  @override
  String get reportGiveCode => 'Give this code to Support.';

  @override
  String get reportFailedTitle => 'Not sent';

  @override
  String get reportFailedHelp => 'Check your internet and try again.';

  @override
  String get reportFailedBusy =>
      'Too many reports right now. Try again in an hour.';

  @override
  String get reportFailedRefused =>
      'The problem is on our side. Chat with Support on Telegram.';

  @override
  String get probeChecking => 'Checking the internet…';

  @override
  String get probeOk =>
      'The internet works and the ShikooNet server is reachable.';

  @override
  String get probeOffline => 'This device isn\'t connected to the internet.';

  @override
  String get probeNoAbroad =>
      'International internet is cut on this line. The servers are outside Iran.';

  @override
  String get probeNoDoor =>
      'We couldn\'t reach the ShikooNet server; try again in a few minutes.';

  @override
  String get probeNoServer => 'None of the servers answer.';

  @override
  String get probeNetSettings => 'Internet settings';

  @override
  String get addServiceTooltip => 'Add a service by link';

  @override
  String get addServiceTitle => 'Add a service';

  @override
  String get addServiceHelp =>
      'Copy the ShikooNet subscription link of your other service, then press this button. It joins the others on this phone.';

  @override
  String serviceAdded(String name) {
    return '“$name” was added.';
  }

  @override
  String get serviceAlreadyHere => 'This service is already on this phone.';

  @override
  String get servicesGroup => 'Services';

  @override
  String get orderServices => 'Order of services';

  @override
  String get orderServicesHelpTouch => 'On this phone only';

  @override
  String get orderServicesHelpTv => 'On this TV only';

  @override
  String get orderScreenHelp =>
      'Hold ≡ on a service and drag it up or down. The order is for this phone only and is saved at once.';

  @override
  String orderHandleLabel(String name) {
    return 'Drag “$name” to move it';
  }

  @override
  String get orderTvHintRest => 'OK: pick up to move';

  @override
  String get orderTvHintMoving => 'Up and down: move · OK: drop · Back: cancel';

  @override
  String get orderTvPicked => 'Moving';
}
