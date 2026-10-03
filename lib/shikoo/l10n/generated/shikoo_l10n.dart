import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'shikoo_l10n_en.dart';
import 'shikoo_l10n_fa.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of ShikooL10n
/// returned by `ShikooL10n.of(context)`.
///
/// Applications need to include `ShikooL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/shikoo_l10n.dart';
///
/// return MaterialApp(
///   localizationsDelegates: ShikooL10n.localizationsDelegates,
///   supportedLocales: ShikooL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the ShikooL10n.supportedLocales
/// property.
abstract class ShikooL10n {
  ShikooL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static ShikooL10n of(BuildContext context) {
    return Localizations.of<ShikooL10n>(context, ShikooL10n)!;
  }

  static const LocalizationsDelegate<ShikooL10n> delegate =
      _ShikooL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fa'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Shikoo'**
  String get appTitle;

  /// No description provided for @brandMark.
  ///
  /// In en, this message translates to:
  /// **'S'**
  String get brandMark;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @renew.
  ///
  /// In en, this message translates to:
  /// **'Renew'**
  String get renew;

  /// No description provided for @support.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get support;

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusActive;

  /// No description provided for @statusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get statusExpired;

  /// No description provided for @statusExhausted.
  ///
  /// In en, this message translates to:
  /// **'Volume used up'**
  String get statusExhausted;

  /// No description provided for @usedLabel.
  ///
  /// In en, this message translates to:
  /// **'Used:'**
  String get usedLabel;

  /// No description provided for @ofTotalGb.
  ///
  /// In en, this message translates to:
  /// **'of {total} GB'**
  String ofTotalGb(String total);

  /// No description provided for @remainingLabel.
  ///
  /// In en, this message translates to:
  /// **'Left:'**
  String get remainingLabel;

  /// No description provided for @gb.
  ///
  /// In en, this message translates to:
  /// **'{amount} GB'**
  String gb(String amount);

  /// No description provided for @unlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get unlimited;

  /// No description provided for @validUntil.
  ///
  /// In en, this message translates to:
  /// **'Valid until {date}'**
  String validUntil(String date);

  /// No description provided for @daysLeft.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day left} other{{days} days left}}'**
  String daysLeft(int days);

  /// No description provided for @jalaliMonths.
  ///
  /// In en, this message translates to:
  /// **'Farvardin|Ordibehesht|Khordad|Tir|Mordad|Shahrivar|Mehr|Aban|Azar|Dey|Bahman|Esfand'**
  String get jalaliMonths;

  /// No description provided for @jalaliDate.
  ///
  /// In en, this message translates to:
  /// **'{day} {month} {year}'**
  String jalaliDate(String day, String month, String year);

  /// No description provided for @powerConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get powerConnect;

  /// No description provided for @powerOn.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get powerOn;

  /// No description provided for @powerConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get powerConnecting;

  /// No description provided for @powerFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t connect'**
  String get powerFailed;

  /// No description provided for @subCancelTv.
  ///
  /// In en, this message translates to:
  /// **'OK button: cancel'**
  String get subCancelTv;

  /// No description provided for @subCancelTouch.
  ///
  /// In en, this message translates to:
  /// **'Tap to cancel'**
  String get subCancelTouch;

  /// No description provided for @subRetryTv.
  ///
  /// In en, this message translates to:
  /// **'OK button: retry'**
  String get subRetryTv;

  /// No description provided for @subRetryTouch.
  ///
  /// In en, this message translates to:
  /// **'Tap to retry'**
  String get subRetryTouch;

  /// No description provided for @tvHint.
  ///
  /// In en, this message translates to:
  /// **'Press OK on the remote to connect'**
  String get tvHint;

  /// No description provided for @loadingServers.
  ///
  /// In en, this message translates to:
  /// **'Getting the server list…'**
  String get loadingServers;

  /// Unit after a ping. Empty where pings are written without one, as in Persian.
  ///
  /// In en, this message translates to:
  /// **'ms'**
  String get msUnit;

  /// No description provided for @noResponse.
  ///
  /// In en, this message translates to:
  /// **'No response'**
  String get noResponse;

  /// No description provided for @errorConnect.
  ///
  /// In en, this message translates to:
  /// **'{server} didn\'t answer in {seconds} seconds.\nTry another server.'**
  String errorConnect(String server, int seconds);

  /// No description provided for @errorServer.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t switch the server.'**
  String get errorServer;

  /// No description provided for @errorAdd.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add the service.'**
  String get errorAdd;

  /// No description provided for @initError.
  ///
  /// In en, this message translates to:
  /// **'The app couldn\'t start.'**
  String get initError;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get refresh;

  /// Accessibility label of the icon-only update button on the phone.
  ///
  /// In en, this message translates to:
  /// **'Update servers'**
  String get refreshServers;

  /// No description provided for @updatedAgo.
  ///
  /// In en, this message translates to:
  /// **'Updated · {ago}'**
  String updatedAgo(String ago);

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Not updated'**
  String get updateFailed;

  /// No description provided for @updating.
  ///
  /// In en, this message translates to:
  /// **'Updating…'**
  String get updating;

  /// No description provided for @updateFailedAgo.
  ///
  /// In en, this message translates to:
  /// **'Not updated · list from {ago}'**
  String updateFailedAgo(String ago);

  /// No description provided for @agoJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get agoJustNow;

  /// No description provided for @agoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute ago} other{{count} minutes ago}}'**
  String agoMinutes(int count);

  /// No description provided for @agoHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String agoHours(int count);

  /// No description provided for @agoDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day ago} other{{count} days ago}}'**
  String agoDays(int count);

  /// No description provided for @updateFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update.'**
  String get updateFailedTitle;

  /// No description provided for @updateFailedTouch.
  ///
  /// In en, this message translates to:
  /// **'Check your internet and tap again. Until then, connect with these servers.'**
  String get updateFailedTouch;

  /// No description provided for @updateFailedTv.
  ///
  /// In en, this message translates to:
  /// **'Check your internet and press OK again. Until then, connect with these servers.'**
  String get updateFailedTv;

  /// No description provided for @serversAdded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new server.} other{{count} new servers.}}'**
  String serversAdded(int count);

  /// No description provided for @serverRemoved.
  ///
  /// In en, this message translates to:
  /// **'“{name}” was removed.'**
  String serverRemoved(String name);

  /// No description provided for @serversRemoved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 server was removed.} other{{count} servers were removed.}}'**
  String serversRemoved(int count);

  /// No description provided for @selectedRemoved.
  ///
  /// In en, this message translates to:
  /// **'“{name}” is no longer in your subscription.'**
  String selectedRemoved(String name);

  /// No description provided for @selectedReplaced.
  ///
  /// In en, this message translates to:
  /// **'The fastest server, “{name}”, was picked instead.'**
  String selectedReplaced(String name);

  /// No description provided for @selectedMoved.
  ///
  /// In en, this message translates to:
  /// **'The connection moved to the fastest server, “{name}”, right away.'**
  String selectedMoved(String name);

  /// No description provided for @selectedMovedFirst.
  ///
  /// In en, this message translates to:
  /// **'The connection moved to “{name}” right away.'**
  String selectedMovedFirst(String name);

  /// First sentence when a server the app picked by itself stopped answering; followed by selectedReplaced when disconnected or selectedMoved when connected.
  ///
  /// In en, this message translates to:
  /// **'“{name}” didn\'t answer.'**
  String selectedNoAnswer(String name);

  /// No description provided for @findingBest.
  ///
  /// In en, this message translates to:
  /// **'Finding the best server…'**
  String get findingBest;

  /// No description provided for @connectsToFirst.
  ///
  /// In en, this message translates to:
  /// **'You\'ll connect to the first server that answers.'**
  String get connectsToFirst;

  /// No description provided for @noServerAnswered.
  ///
  /// In en, this message translates to:
  /// **'No server answered'**
  String get noServerAnswered;

  /// No description provided for @noServerAnsweredHelpTouch.
  ///
  /// In en, this message translates to:
  /// **'Check this phone\'s internet.\nIf it works, ask Support.'**
  String get noServerAnsweredHelpTouch;

  /// No description provided for @noServerAnsweredHelpTv.
  ///
  /// In en, this message translates to:
  /// **'Check this TV\'s internet.\nIf it works, ask Support.'**
  String get noServerAnsweredHelpTv;

  /// No description provided for @newBadge.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newBadge;

  /// No description provided for @serversTitle.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get serversTitle;

  /// No description provided for @fastestFirst.
  ///
  /// In en, this message translates to:
  /// **'Fastest first'**
  String get fastestFirst;

  /// No description provided for @sortsOnLeave.
  ///
  /// In en, this message translates to:
  /// **'Sorts when you leave the list'**
  String get sortsOnLeave;

  /// No description provided for @pingAll.
  ///
  /// In en, this message translates to:
  /// **'Ping all'**
  String get pingAll;

  /// No description provided for @pingProgress.
  ///
  /// In en, this message translates to:
  /// **'Ping {done} of {total}'**
  String pingProgress(int done, int total);

  /// Accessibility label of a ping that has not answered yet.
  ///
  /// In en, this message translates to:
  /// **'Measuring'**
  String get measuring;

  /// No description provided for @searchServers.
  ///
  /// In en, this message translates to:
  /// **'Search servers'**
  String get searchServers;

  /// No description provided for @searchNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No server with that name'**
  String get searchNoMatch;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @renewTitle.
  ///
  /// In en, this message translates to:
  /// **'Renew on your phone'**
  String get renewTitle;

  /// No description provided for @renewHelp.
  ///
  /// In en, this message translates to:
  /// **'Scan with your phone\'s camera; the Shikoo bot opens the renewal list of your services.'**
  String get renewHelp;

  /// No description provided for @supportTitle.
  ///
  /// In en, this message translates to:
  /// **'Support on your phone'**
  String get supportTitle;

  /// No description provided for @supportHelp.
  ///
  /// In en, this message translates to:
  /// **'Scan with your phone\'s camera to chat with Shikoo support on Telegram.'**
  String get supportHelp;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @backHintTv.
  ///
  /// In en, this message translates to:
  /// **'Press Back on the remote to go back'**
  String get backHintTv;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get themeAuto;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageFa.
  ///
  /// In en, this message translates to:
  /// **'فارسی'**
  String get languageFa;

  /// No description provided for @languageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logout;

  /// No description provided for @logoutHelpTv.
  ///
  /// In en, this message translates to:
  /// **'Removes the services from this TV.'**
  String get logoutHelpTv;

  /// No description provided for @logoutHelpTouch.
  ///
  /// In en, this message translates to:
  /// **'Removes the services from this phone.'**
  String get logoutHelpTouch;

  /// No description provided for @logoutBodyTv.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be disconnected and the services removed from this TV. Your subscription stays as it is in the Shikoo bot.'**
  String get logoutBodyTv;

  /// No description provided for @logoutBodyTouch.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be disconnected and the services removed from this phone. The services themselves stay as they are; they come back with the same link or with Telegram.'**
  String get logoutBodyTouch;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @appSection.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get appSection;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutSummary.
  ///
  /// In en, this message translates to:
  /// **'Free software under GPL-3.0, built on FlClash and mihomo'**
  String get aboutSummary;

  /// No description provided for @aboutFree.
  ///
  /// In en, this message translates to:
  /// **'Shikoo is free software, released under the GPL-3.0 license.'**
  String get aboutFree;

  /// No description provided for @aboutBasedOn.
  ///
  /// In en, this message translates to:
  /// **'It is built on two free programs: FlClash by chen08209 and the mihomo core by MetaCubeX. Thanks to their makers.'**
  String get aboutBasedOn;

  /// No description provided for @aboutSource.
  ///
  /// In en, this message translates to:
  /// **'You can get the source code of this version from Support.'**
  String get aboutSource;

  /// No description provided for @aboutLicense.
  ///
  /// In en, this message translates to:
  /// **'License text: gnu.org/licenses/gpl-3.0'**
  String get aboutLicense;

  /// Under the power button while connected to a server the user picked that does not answer.
  ///
  /// In en, this message translates to:
  /// **'“{name}” isn\'t answering.\nPick another server from the list.'**
  String selectedDown(String name);

  /// No description provided for @vpnRefused.
  ///
  /// In en, this message translates to:
  /// **'Permission to connect wasn\'t given.\nConnect again and allow it in Android\'s window.'**
  String get vpnRefused;

  /// No description provided for @vpnMissing.
  ///
  /// In en, this message translates to:
  /// **'This device doesn\'t show Android\'s permission window.\nAsk Support.'**
  String get vpnMissing;

  /// No description provided for @logoutTitleTv.
  ///
  /// In en, this message translates to:
  /// **'Remove the services from this TV?'**
  String get logoutTitleTv;

  /// No description provided for @logoutTitleTouch.
  ///
  /// In en, this message translates to:
  /// **'Remove the services from this phone?'**
  String get logoutTitleTouch;

  /// No description provided for @removeButton.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeButton;

  /// Under the renew QR. The username is shown bold; the bot's list pages and shortens names, so only the username is named.
  ///
  /// In en, this message translates to:
  /// **'In the bot\'s list, tap the service {username}; if it isn\'t there, check the next page of the list.'**
  String renewPickInList(String username);

  /// No description provided for @powerNoService.
  ///
  /// In en, this message translates to:
  /// **'No service'**
  String get powerNoService;

  /// No description provided for @noServiceTitleTv.
  ///
  /// In en, this message translates to:
  /// **'No service on this TV'**
  String get noServiceTitleTv;

  /// No description provided for @noServiceTitleTouch.
  ///
  /// In en, this message translates to:
  /// **'No service on this phone'**
  String get noServiceTitleTouch;

  /// No description provided for @noServiceHelp.
  ///
  /// In en, this message translates to:
  /// **'Ask Support to bring it back.'**
  String get noServiceHelp;
}

class _ShikooL10nDelegate extends LocalizationsDelegate<ShikooL10n> {
  const _ShikooL10nDelegate();

  @override
  Future<ShikooL10n> load(Locale locale) {
    return SynchronousFuture<ShikooL10n>(lookupShikooL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fa'].contains(locale.languageCode);

  @override
  bool shouldReload(_ShikooL10nDelegate old) => false;
}

ShikooL10n lookupShikooL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return ShikooL10nEn();
    case 'fa':
      return ShikooL10nFa();
  }

  throw FlutterError(
    'ShikooL10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
