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
  /// **'ShikooNet'**
  String get appTitle;

  /// The staging app (com.shikoonet.app.dev) everywhere it names itself, as its launcher label does, so the two are never mixed up on one device.
  ///
  /// In en, this message translates to:
  /// **'ShikooNet Test'**
  String get appTitleTest;

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

  /// The service chip when it is past its date.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get chipExpired;

  /// The round button's label and the service chip when the data is used up.
  ///
  /// In en, this message translates to:
  /// **'Out of data'**
  String get stateExhausted;

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
  /// **'{count, plural, =1{1 minute ago} other{{count} minutes ago}}'**
  String agoMinutes(int count);

  /// No description provided for @agoHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String agoHours(int count);

  /// No description provided for @agoDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day ago} other{{count} days ago}}'**
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

  /// First sentence when a server the app picked by itself stopped answering; followed by selectedReplaced when disconnected or selectedMoved when connected. Also the first sentence of a failed switch on the phone, followed by switchKept.
  ///
  /// In en, this message translates to:
  /// **'“{name}” didn\'t answer.'**
  String selectedNoAnswer(String name);

  /// While connected, from tapping another server until it answers its own ping; the connection still goes through the previous server meanwhile. Phone: bottom snackbar. TV: under the server pill. In all three switch messages {name} goes through bidiName.
  ///
  /// In en, this message translates to:
  /// **'Moving to “{name}”…'**
  String switchingTo(String name);

  /// Replaces switchingTo once the tapped server answered and the connection moved to it. Hides after 4 seconds.
  ///
  /// In en, this message translates to:
  /// **'Now connected through “{name}”.'**
  String switchedTo(String name);

  /// Phone only (the TV says switchFailedTv). After selectedNoAnswer (the tapped server), when it did not answer and the connection stayed on {name}, the previous server.
  ///
  /// In en, this message translates to:
  /// **'Still on “{name}”. Try another server.'**
  String switchKept(String name);

  /// TV only, in the two-line slot under the server pill, when the tapped server {name} did not answer and the connection stayed where it was. The pill right above names that server, so only the tapped one is named here: two names did not fit two lines.
  ///
  /// In en, this message translates to:
  /// **'“{name}” didn\'t answer.\nTry another server.'**
  String switchFailedTv(String name);

  /// Under the round button only while a connect is waiting for the first server to answer; never at rest.
  ///
  /// In en, this message translates to:
  /// **'Finding the best server…'**
  String get findingBest;

  /// Under the round button while no server is chosen yet. Still, no spinner: nothing runs until Connect or Ping.
  ///
  /// In en, this message translates to:
  /// **'The server is picked automatically'**
  String get autoPick;

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

  /// TV list caption before this service has been pinged.
  ///
  /// In en, this message translates to:
  /// **'Press “Ping” to sort'**
  String get sortsOnPing;

  /// TV button beside “Update” in an open active service card.
  ///
  /// In en, this message translates to:
  /// **'Ping'**
  String get ping;

  /// Accessibility label of the icon-only ping button on the phone.
  ///
  /// In en, this message translates to:
  /// **'Ping servers'**
  String get pingServers;

  /// Small label above the name of the service the connection is on, with a bar on the card's start edge, open or folded; green when connected, grey otherwise (the service the round button connects). Only with two service cards or more.
  ///
  /// In en, this message translates to:
  /// **'In use'**
  String get inUseLabel;

  /// Phone, above the server list of an open card whose service is not the one in use, only while connected or connecting.
  ///
  /// In en, this message translates to:
  /// **'Tap a server to move your connection to this service.'**
  String get otherServiceHint;

  /// The same line after a server of that card took the connection. Both texts share one box as tall as the longer, so no row moves. Gone once the card folds or the app goes to the background.
  ///
  /// In en, this message translates to:
  /// **'You\'re now connected through this service.'**
  String get otherServiceNow;

  /// TV, the list caption of an open card whose service is not the one in use, while connected or connecting; it gives way to fastestFirst once a server there took the connection.
  ///
  /// In en, this message translates to:
  /// **'Press a server to move your connection here'**
  String get otherServiceCaptionTv;

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

  /// No description provided for @renewHelpList.
  ///
  /// In en, this message translates to:
  /// **'Scan with your phone\'s camera; the ShikooNet bot opens the renewal list of your services.'**
  String get renewHelpList;

  /// No description provided for @supportTitle.
  ///
  /// In en, this message translates to:
  /// **'Support on your phone'**
  String get supportTitle;

  /// No description provided for @supportHelpTv.
  ///
  /// In en, this message translates to:
  /// **'Scan with your phone\'s camera to open a chat with ShikooNet support in Telegram.'**
  String get supportHelpTv;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

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
  /// **'You\'ll be disconnected and the services removed from this TV. Your subscription stays as it is in the ShikooNet bot.'**
  String get logoutBodyTv;

  /// No description provided for @logoutBodyTouch.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be disconnected and the services removed from this phone. The services themselves stay as they are; they come back with the same link or with Telegram.'**
  String get logoutBodyTouch;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

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
  /// **'ShikooNet is free software, released under the GPL-3.0 license.'**
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

  /// No description provided for @noServiceHelpPaste.
  ///
  /// In en, this message translates to:
  /// **'Copy your subscription link, then tap “Paste subscription link”.\nNo link? Ask Support.'**
  String get noServiceHelpPaste;

  /// No description provided for @pasteLink.
  ///
  /// In en, this message translates to:
  /// **'Paste subscription link'**
  String get pasteLink;

  /// No description provided for @pasteChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking the link…'**
  String get pasteChecking;

  /// No description provided for @pasteEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'The clipboard is empty.'**
  String get pasteEmptyTitle;

  /// No description provided for @pasteEmptyHelp.
  ///
  /// In en, this message translates to:
  /// **'Copy your subscription link, then tap again.'**
  String get pasteEmptyHelp;

  /// No description provided for @pasteNotShikooTitle.
  ///
  /// In en, this message translates to:
  /// **'This isn\'t a ShikooNet link.'**
  String get pasteNotShikooTitle;

  /// No description provided for @pasteNotShikooHelp.
  ///
  /// In en, this message translates to:
  /// **'Only a ShikooNet subscription link works: the one you got from the ShikooNet bot or your reseller.'**
  String get pasteNotShikooHelp;

  /// No description provided for @pasteRevokedTitle.
  ///
  /// In en, this message translates to:
  /// **'This link was revoked or has expired.'**
  String get pasteRevokedTitle;

  /// No description provided for @pasteRevokedHelp.
  ///
  /// In en, this message translates to:
  /// **'Get a new link from the ShikooNet bot or your reseller.'**
  String get pasteRevokedHelp;

  /// No description provided for @pasteOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'No internet connection.'**
  String get pasteOfflineTitle;

  /// No description provided for @pasteOfflineHelp.
  ///
  /// In en, this message translates to:
  /// **'Check your phone\'s internet and tap again.'**
  String get pasteOfflineHelp;

  /// No description provided for @pasteAnother.
  ///
  /// In en, this message translates to:
  /// **'Paste another link'**
  String get pasteAnother;

  /// No description provided for @pasteAnotherHelp.
  ///
  /// In en, this message translates to:
  /// **'For another service you have'**
  String get pasteAnotherHelp;

  /// No description provided for @powerExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get powerExpired;

  /// Under the disabled round button of an out-of-data or expired service.
  ///
  /// In en, this message translates to:
  /// **'Renew to connect again.'**
  String get renewToConnect;

  /// No description provided for @serversAfterRenew.
  ///
  /// In en, this message translates to:
  /// **'The server list comes back after you renew.'**
  String get serversAfterRenew;

  /// In place of the days left, beside a past end date, in the danger colour.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get expiredEnded;

  /// No description provided for @summaryExhausted.
  ///
  /// In en, this message translates to:
  /// **'Out of data. Renew to use it again.'**
  String get summaryExhausted;

  /// The folded card's summary line. {date} is the end date, Gregorian in English.
  ///
  /// In en, this message translates to:
  /// **'Expired on {date}. Renew to use it again.'**
  String summaryExpired(String date);

  /// A server error (5xx), an empty answer, or a web page instead of a subscription. Only 404 and 410 say pasteRevokedTitle. Says nothing about a “server”: customers read that as the servers in the list.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link right now.'**
  String get pasteUnavailableTitle;

  /// No description provided for @pasteUnavailableHelp.
  ///
  /// In en, this message translates to:
  /// **'Try again in a bit; if it still won\'t open, ask Support.'**
  String get pasteUnavailableHelp;

  /// No description provided for @loginTagline.
  ///
  /// In en, this message translates to:
  /// **'For ShikooNet customers'**
  String get loginTagline;

  /// No description provided for @loginTelegram.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Telegram'**
  String get loginTelegram;

  /// No description provided for @loginTelegramNote.
  ///
  /// In en, this message translates to:
  /// **'Telegram opens; tap “Approve” in the ShikooNet bot.'**
  String get loginTelegramNote;

  /// No description provided for @noTelegramHere.
  ///
  /// In en, this message translates to:
  /// **'No Telegram on this phone?'**
  String get noTelegramHere;

  /// No description provided for @waitingTitle.
  ///
  /// In en, this message translates to:
  /// **'No approval yet.'**
  String get waitingTitle;

  /// No description provided for @waitingHelp.
  ///
  /// In en, this message translates to:
  /// **'If Telegram only opens with a VPN, turn that on first, then open Telegram again.'**
  String get waitingHelp;

  /// No description provided for @reopenTelegram.
  ///
  /// In en, this message translates to:
  /// **'Open Telegram again'**
  String get reopenTelegram;

  /// No description provided for @approveElsewhere.
  ///
  /// In en, this message translates to:
  /// **'Approve from another device'**
  String get approveElsewhere;

  /// No description provided for @codeExpiredNote.
  ///
  /// In en, this message translates to:
  /// **'This code has expired.'**
  String get codeExpiredNote;

  /// No description provided for @otherDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve from another device'**
  String get otherDeviceTitle;

  /// No description provided for @otherDeviceScan.
  ///
  /// In en, this message translates to:
  /// **'Have another phone with Telegram? Scan this code with its camera.'**
  String get otherDeviceScan;

  /// No description provided for @otherDeviceComputer.
  ///
  /// In en, this message translates to:
  /// **'Telegram on a computer? Send this code to the ShikooNet bot:'**
  String get otherDeviceComputer;

  /// No description provided for @codeOnlyYou.
  ///
  /// In en, this message translates to:
  /// **'Only type this code in the bot yourself; never give it to anyone.'**
  String get codeOnlyYou;

  /// No description provided for @otherDeviceFine.
  ///
  /// In en, this message translates to:
  /// **'The code works for 10 minutes. After you approve in the bot, this screen goes home by itself.'**
  String get otherDeviceFine;

  /// No description provided for @tvLoginLead.
  ///
  /// In en, this message translates to:
  /// **'Scan with your phone\'s camera and tap “Approve”'**
  String get tvLoginLead;

  /// No description provided for @tvLoginVpnHint.
  ///
  /// In en, this message translates to:
  /// **'Telegram only opens with a VPN? Turn it on on your phone, then scan.'**
  String get tvLoginVpnHint;

  /// No description provided for @tvLoginComputer.
  ///
  /// In en, this message translates to:
  /// **'Telegram on a computer?\nSend this code to the bot:'**
  String get tvLoginComputer;

  /// No description provided for @codeLifetime.
  ///
  /// In en, this message translates to:
  /// **'This code works for 10 minutes.'**
  String get codeLifetime;

  /// No description provided for @codeExpiredLead.
  ///
  /// In en, this message translates to:
  /// **'10 minutes passed and this code expired. Get a new one.'**
  String get codeExpiredLead;

  /// No description provided for @previousCode.
  ///
  /// In en, this message translates to:
  /// **'Previous code'**
  String get previousCode;

  /// No description provided for @newCode.
  ///
  /// In en, this message translates to:
  /// **'New code'**
  String get newCode;

  /// No description provided for @codeExpiredOverlay.
  ///
  /// In en, this message translates to:
  /// **'This code expired'**
  String get codeExpiredOverlay;

  /// A Telegram account as shown on the result screens. Without a username, {account} is the display name alone.
  ///
  /// In en, this message translates to:
  /// **'{name} ({username})'**
  String accountWithUsername(String name, String username);

  /// No description provided for @approvedTitle.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get approvedTitle;

  /// No description provided for @approvedBodyTv.
  ///
  /// In en, this message translates to:
  /// **'This TV is now linked to the Telegram account {account}, with these services:'**
  String approvedBodyTv(String account);

  /// No description provided for @approvedBodyTouch.
  ///
  /// In en, this message translates to:
  /// **'This phone is now linked to the Telegram account {account}, with these services:'**
  String approvedBodyTouch(String account);

  /// approvedBodyTv when the account has one service, which the list under it shows.
  ///
  /// In en, this message translates to:
  /// **'This TV is now linked to the Telegram account {account}, with this service:'**
  String approvedBodyOneTv(String account);

  /// No description provided for @approvedBodyOneTouch.
  ///
  /// In en, this message translates to:
  /// **'This phone is now linked to the Telegram account {account}, with this service:'**
  String approvedBodyOneTouch(String account);

  /// No description provided for @servicesComing.
  ///
  /// In en, this message translates to:
  /// **'Your services are on their way…'**
  String get servicesComing;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// Unlinks the device from the account that approved and goes back to sign-in with a new code.
  ///
  /// In en, this message translates to:
  /// **'This isn\'t my account'**
  String get notMyAccount;

  /// No description provided for @servicesFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your services didn\'t arrive'**
  String get servicesFailedTitle;

  /// No description provided for @servicesFailedBodyTv.
  ///
  /// In en, this message translates to:
  /// **'You signed in with the Telegram account {account}, but the list of services didn\'t come from the server. Check this TV\'s internet and try again.'**
  String servicesFailedBodyTv(String account);

  /// No description provided for @servicesFailedBodyTouch.
  ///
  /// In en, this message translates to:
  /// **'You signed in with the Telegram account {account}, but the list of services didn\'t come from the server. Check this phone\'s internet and try again.'**
  String servicesFailedBodyTouch(String account);

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @noServiceTitle.
  ///
  /// In en, this message translates to:
  /// **'This account has no service'**
  String get noServiceTitle;

  /// No description provided for @noServiceBodyTouch.
  ///
  /// In en, this message translates to:
  /// **'You signed in with the Telegram account {account}, but no ShikooNet service is linked to it.'**
  String noServiceBodyTouch(String account);

  /// No description provided for @noServiceBodyTv.
  ///
  /// In en, this message translates to:
  /// **'You signed in with the Telegram account {account}, but no service is linked to it.'**
  String noServiceBodyTv(String account);

  /// No description provided for @noServiceHelpTouch.
  ///
  /// In en, this message translates to:
  /// **'Is your service on another Telegram account? Switch to it in Telegram first, then tap “Use another account”.'**
  String get noServiceHelpTouch;

  /// No description provided for @noServiceHelpTv.
  ///
  /// In en, this message translates to:
  /// **'Is your service on another account? Switch to it in Telegram on your phone and scan again.'**
  String get noServiceHelpTv;

  /// No description provided for @otherAccount.
  ///
  /// In en, this message translates to:
  /// **'Use another account'**
  String get otherAccount;

  /// No description provided for @askSupportLink.
  ///
  /// In en, this message translates to:
  /// **'Think this is wrong? Ask Support'**
  String get askSupportLink;

  /// No description provided for @rejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign-in declined'**
  String get rejectedTitle;

  /// No description provided for @rejectedBodyTv.
  ///
  /// In en, this message translates to:
  /// **'“Decline” was tapped in Telegram, so this TV isn\'t linked. If that was a mistake, try again.'**
  String get rejectedBodyTv;

  /// No description provided for @rejectedBodyTouch.
  ///
  /// In en, this message translates to:
  /// **'“Decline” was tapped in Telegram, so this phone isn\'t linked. If that was a mistake, try again.'**
  String get rejectedBodyTouch;

  /// No description provided for @signedInWith.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {name}'**
  String signedInWith(String name);

  /// No description provided for @telegramAccount.
  ///
  /// In en, this message translates to:
  /// **'Telegram account'**
  String get telegramAccount;

  /// No description provided for @telegramAccountUsername.
  ///
  /// In en, this message translates to:
  /// **'Telegram account {username}'**
  String telegramAccountUsername(String username);

  /// No description provided for @logoutHelpSignedInTouch.
  ///
  /// In en, this message translates to:
  /// **'Removes this account\'s services from this device; your subscriptions stay as they are.'**
  String get logoutHelpSignedInTouch;

  /// No description provided for @logoutHelpSignedInTv.
  ///
  /// In en, this message translates to:
  /// **'Removes the services from this TV; your subscriptions stay as they are.'**
  String get logoutHelpSignedInTv;

  /// No description provided for @logoutSignedInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get logoutSignedInTitle;

  /// No description provided for @logoutSignedInBodyTouch.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be disconnected and this device unlinked from your Telegram account. This account\'s services are removed from it, but a service whose link you pasted yourself stays. Your subscriptions stay as they are.'**
  String get logoutSignedInBodyTouch;

  /// No description provided for @logoutSignedInBodyTv.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be disconnected, this TV will be unlinked from your Telegram account and the services removed from it. Your subscriptions stay as they are; sign in with Telegram again whenever you like.'**
  String get logoutSignedInBodyTv;

  /// No description provided for @signInRow.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Telegram'**
  String get signInRow;

  /// No description provided for @signInRowHelp.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t signed in yet. Signing in brings all your services automatically.'**
  String get signInRowHelp;

  /// No description provided for @renewHelpDirect.
  ///
  /// In en, this message translates to:
  /// **'Scan with your phone\'s camera; the ShikooNet bot opens the renewal page of this service.'**
  String get renewHelpDirect;

  /// No description provided for @codeFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'The sign-in code didn\'t arrive.'**
  String get codeFailedTitle;

  /// No description provided for @openBotTitleTv.
  ///
  /// In en, this message translates to:
  /// **'ShikooNet bot on your phone'**
  String get openBotTitleTv;

  /// No description provided for @openBotHelpTv.
  ///
  /// In en, this message translates to:
  /// **'Scan with your phone\'s camera to open the ShikooNet bot.'**
  String get openBotHelpTv;

  /// No description provided for @codeFetching.
  ///
  /// In en, this message translates to:
  /// **'Getting a code…'**
  String get codeFetching;

  /// No description provided for @codeFailedHelpTouch.
  ///
  /// In en, this message translates to:
  /// **'Check your phone\'s internet and tap again.'**
  String get codeFailedHelpTouch;

  /// No description provided for @codeFailedOverlay.
  ///
  /// In en, this message translates to:
  /// **'No sign-in code'**
  String get codeFailedOverlay;

  /// No description provided for @codeFailedLeadTv.
  ///
  /// In en, this message translates to:
  /// **'The sign-in code didn\'t come from the server. Check this TV\'s internet and try again.'**
  String get codeFailedLeadTv;

  /// No description provided for @noLinkChip.
  ///
  /// In en, this message translates to:
  /// **'No link'**
  String get noLinkChip;

  /// No description provided for @noLinkHelpTouch.
  ///
  /// In en, this message translates to:
  /// **'Open this service once in the bot'**
  String get noLinkHelpTouch;

  /// No description provided for @noLinkHelpTv.
  ///
  /// In en, this message translates to:
  /// **'Open this service once in the bot, then press “Try again”.'**
  String get noLinkHelpTv;

  /// A service the panel gave a link for, whose servers could not be fetched. Not the same as noLinkChip: the bot cannot help here.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t load'**
  String get loadFailedChip;

  /// No description provided for @loadFailedHelp.
  ///
  /// In en, this message translates to:
  /// **'This service has a link, but its servers didn\'t load just now. Check your internet and try again.'**
  String get loadFailedHelp;

  /// No description provided for @openBotTouch.
  ///
  /// In en, this message translates to:
  /// **'Open the bot'**
  String get openBotTouch;

  /// No description provided for @openBotTv.
  ///
  /// In en, this message translates to:
  /// **'ShikooNet bot'**
  String get openBotTv;

  /// Phone: summaryExpired for a service that came from the Telegram account without its end date.
  ///
  /// In en, this message translates to:
  /// **'Expired. Renew to use it again.'**
  String get summaryExpiredNoDate;

  /// No description provided for @summaryExpiredNoDateTv.
  ///
  /// In en, this message translates to:
  /// **'Expired. After renewing, press “Try again”.'**
  String get summaryExpiredNoDateTv;

  /// TV: the card has Renew, Support and Try again; the TV can't tell when the renewal happened on the phone.
  ///
  /// In en, this message translates to:
  /// **'Out of data. After renewing, press “Try again”.'**
  String get summaryExhaustedTv;

  /// No description provided for @summaryDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled. Renew to use it again.'**
  String get summaryDisabled;

  /// No description provided for @summaryDisabledTv.
  ///
  /// In en, this message translates to:
  /// **'Disabled. After renewing, press “Try again”.'**
  String get summaryDisabledTv;

  /// A service removed in the panel, or one that never started: the bot renews neither, so the card has Support instead of Renew.
  ///
  /// In en, this message translates to:
  /// **'Disabled, and it can\'t be renewed. Press “Support” to follow it up.'**
  String get summaryRemoved;

  /// A used-up or expired service the bot will not renew (the app door says renewable: false): the card has Support instead of Renew.
  ///
  /// In en, this message translates to:
  /// **'This service can\'t be renewed; ask “Support” to continue.'**
  String get summaryNotRenewable;

  /// Settings section, phone only. Lists only services whose sole source on this phone is a pasted link; absent when there are none.
  ///
  /// In en, this message translates to:
  /// **'Services added by link'**
  String get pastedServicesTitle;

  /// Each row of pastedServicesTitle, the revoked card's button, and the dialog's confirm button.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeService;

  /// Screen-reader label of a row's Remove button, so each one names its service.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String removeServiceLabel(String name);

  /// {name} is “username · tier”, as on the card. Isolate the Latin username (FSI…PDI) so it doesn't reorder the Persian title.
  ///
  /// In en, this message translates to:
  /// **'Remove “{name}”?'**
  String removeServiceTitle(String name);

  /// No description provided for @removeServiceBody.
  ///
  /// In en, this message translates to:
  /// **'It\'s removed from this phone. The service itself stays as it is and comes back with the same link.'**
  String get removeServiceBody;

  /// Instead of removeServiceBody when this service is the selected one and connected or connecting.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be disconnected and this service removed from this phone. The service itself stays as it is and comes back with the same link.'**
  String get removeServiceBodyConnected;

  /// Phone, pasted services only: the chip when a refresh got 404 or 410, and the disabled round button's label when that service is selected.
  ///
  /// In en, this message translates to:
  /// **'Link revoked'**
  String get chipRevoked;

  /// No description provided for @revokedTitle.
  ///
  /// In en, this message translates to:
  /// **'This link was revoked.'**
  String get revokedTitle;

  /// After revokedTitle in the open card's message, and alone as the folded card's summary.
  ///
  /// In en, this message translates to:
  /// **'Remove it, or get a new link from the bot or your reseller and paste it with the + at the top of the home screen.'**
  String get revokedHelp;

  /// Phone: errorConnect, which the TV keeps as two lines.
  ///
  /// In en, this message translates to:
  /// **'{server} didn\'t answer in {seconds} seconds. Tap again, or pick another server from the list.'**
  String errorConnectTouch(String server, int seconds);

  /// A service's name when the panel sends no title and there is no username or plan name.
  ///
  /// In en, this message translates to:
  /// **'ShikooNet service'**
  String get serviceUnnamed;

  /// The one folded row at the end of the home for every out-of-data or expired service (ended at most finishedMaxDays ago, a constant: 30). Folded on every start. Not for a revoked pasted link.
  ///
  /// In en, this message translates to:
  /// **'Finished services ({count})'**
  String finishedServices(int count);

  /// Second line of a row in finishedServices, beside a small Renew button.
  ///
  /// In en, this message translates to:
  /// **'Out of data'**
  String get finishedData;

  /// No description provided for @finishedToday.
  ///
  /// In en, this message translates to:
  /// **'Ended today'**
  String get finishedToday;

  /// No description provided for @finishedDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Ended 1 day ago} other{Ended {count} days ago}}'**
  String finishedDaysAgo(int count);

  /// An expired service from the account whose end date is not known.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get finishedNoDate;

  /// A service of the account the shop removed, disabled or that failed: whatever its end date, it comes last in finishedServices.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get finishedDisabled;

  /// Fourth line of the sign-in result list when there are five services or more: three names, then this, so the TV screen never grows past four lines.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{and 1 more service} other{and {count} more services}}'**
  String approvedMoreServices(int count);

  /// Above the checklist, when the account has two services or more; one service keeps approvedBodyTouch and its list.
  ///
  /// In en, this message translates to:
  /// **'This phone is now linked to the Telegram account {account}.'**
  String approvedBodyChooseTouch(String account);

  /// No description provided for @approvedBodyChooseTv.
  ///
  /// In en, this message translates to:
  /// **'This TV is now linked to the Telegram account {account}.'**
  String approvedBodyChooseTv(String account);

  /// No description provided for @chooseServicesTouch.
  ///
  /// In en, this message translates to:
  /// **'Which services should this phone have?'**
  String get chooseServicesTouch;

  /// No description provided for @chooseServicesTv.
  ///
  /// In en, this message translates to:
  /// **'Which services should this TV have?'**
  String get chooseServicesTv;

  /// Under the checklist while nothing is ticked; continueButton is disabled meanwhile.
  ///
  /// In en, this message translates to:
  /// **'Tick at least one service.'**
  String get chooseAtLeastOne;

  /// Settings, under the Account card, when some services were left out at sign-in; absent when the account has one service.
  ///
  /// In en, this message translates to:
  /// **'{shown} of your account\'s {total} services are on this phone. To change them, sign out and sign in again.'**
  String servicesHereTouch(int shown, int total);

  /// Settings, under the Account card, when the account has two services or more and none was left out.
  ///
  /// In en, this message translates to:
  /// **'All your account\'s services are on this phone. To change them, sign out and sign in again.'**
  String get servicesAllHereTouch;

  /// TV settings, under the Account card, when the account has two services or more; no count, so the column fits 540 dp.
  ///
  /// In en, this message translates to:
  /// **'To change this TV\'s services, sign out and sign in again.'**
  String get changeServicesTv;

  /// The button on Android's ongoing VPN notification.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get notificationStop;

  /// Android toast after the notification's button is pressed. A start from the Quick Settings tile shows powerConnecting.
  ///
  /// In en, this message translates to:
  /// **'Disconnecting…'**
  String get notificationStopping;

  /// The shortcut in the menu of a long-pressed launcher icon; it connects or disconnects. Android registers it after a language change.
  ///
  /// In en, this message translates to:
  /// **'Connect / Disconnect'**
  String get shortcutToggle;

  /// Instead of a sign-in, subscription update, paste, app update check or app download failure when the server's certificate was refused for this device's clock, and on the screen that stops the app before mid-2012 dates crash its core.
  ///
  /// In en, this message translates to:
  /// **'Your device\'s date and time are wrong.'**
  String get clockWrongTitle;

  /// No description provided for @clockWrongHelp.
  ///
  /// In en, this message translates to:
  /// **'In Settings › Date & time, turn on “Automatic” (or set them right), then try again.'**
  String get clockWrongHelp;

  /// Under “Try again” on the clock screen, when it was pressed and the clock is still before the floor.
  ///
  /// In en, this message translates to:
  /// **'The clock is still wrong.'**
  String get clockStillWrong;

  /// Opens Android's date and time settings, or its main settings when a TV box has none.
  ///
  /// In en, this message translates to:
  /// **'Date & time settings'**
  String get dateSettings;

  /// Card at the head of the home card list when the published versionCode is higher than this install. Reuses cancelButton, retry and continueButton.
  ///
  /// In en, this message translates to:
  /// **'A new version is out'**
  String get updateTitle;

  /// No description provided for @updateVersionSize.
  ///
  /// In en, this message translates to:
  /// **'Version {version}, {size} MB'**
  String updateVersionSize(String version, int size);

  /// No description provided for @updateGet.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get updateGet;

  /// No description provided for @updateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get updateDownloading;

  /// No description provided for @updateProgress.
  ///
  /// In en, this message translates to:
  /// **'{percent}%, {done} of {total} MB'**
  String updateProgress(int percent, int done, int total);

  /// No description provided for @updateReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to install'**
  String get updateReady;

  /// No description provided for @updateInstall.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get updateInstall;

  /// On the ready card, the forced page and the install-permission dialog.
  ///
  /// In en, this message translates to:
  /// **'Installing closes ShikooNet, and the connection if you\'re connected; open it again afterwards.'**
  String get updateClosesApp;

  /// No description provided for @updateDownloadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'The download stopped.'**
  String get updateDownloadFailedTitle;

  /// No description provided for @updateDownloadFailedHelp.
  ///
  /// In en, this message translates to:
  /// **'Check your internet and try again; it picks up where it stopped.'**
  String get updateDownloadFailedHelp;

  /// The finished file did not match the published sha256; it is deleted and the next try starts over.
  ///
  /// In en, this message translates to:
  /// **'The file arrived damaged.'**
  String get updateBadFileTitle;

  /// No description provided for @updateBadFileHelp.
  ///
  /// In en, this message translates to:
  /// **'Try again to download it from the start.'**
  String get updateBadFileHelp;

  /// Full-screen page replacing Home when this install is below min_version_code. Its one button is updateGet. After a failed download or a damaged file it shows the matching error with two buttons: retry (focused on TV) and Support, aimed like every other Support (on TV the QR dialog). Ready to install shows Install and Support side by side, always.
  ///
  /// In en, this message translates to:
  /// **'This version needs an update'**
  String get updateForcedTitle;

  /// No description provided for @updateForcedBody.
  ///
  /// In en, this message translates to:
  /// **'To keep using ShikooNet, download and install version {version} ({size} MB).'**
  String updateForcedBody(String version, int size);

  /// Dialog before Android’s “install unknown apps” page, only when the permission is missing. Buttons: cancelButton and continueButton.
  ///
  /// In en, this message translates to:
  /// **'Allow installing'**
  String get installPermissionTitle;

  /// No description provided for @installPermissionTouch.
  ///
  /// In en, this message translates to:
  /// **'On the next screen, turn on installing for “ShikooNet”, then press your phone’s Back button; the install starts by itself.'**
  String get installPermissionTouch;

  /// No description provided for @installPermissionTv.
  ///
  /// In en, this message translates to:
  /// **'On the next screen, turn on installing for “ShikooNet”, then press Back on the remote; the install starts by itself.'**
  String get installPermissionTv;

  /// Card and forced page when the file does not fit in storage. Same text on phone and TV; never mentions the internet.
  ///
  /// In en, this message translates to:
  /// **'Not enough space.'**
  String get updateNoSpaceTitle;

  /// No description provided for @updateNoSpaceHelp.
  ///
  /// In en, this message translates to:
  /// **'Remove a few apps or files from this device and try again.'**
  String get updateNoSpaceHelp;

  /// One red line when Android's installer did not open: under Install on the card, above the buttons on the forced page. Not a new state; the next Install clears it.
  ///
  /// In en, this message translates to:
  /// **'The installer didn\'t open; try again or ask Support.'**
  String get updateInstallFailed;

  /// Android 7 and older: the install-permission dialog's text, before the security settings page, where one Unknown sources switch covers every app.
  ///
  /// In en, this message translates to:
  /// **'On the next screen, turn on Unknown sources at the bottom of it, then press Back.'**
  String get installPermissionLegacy;

  /// No description provided for @installPermissionLegacyTv.
  ///
  /// In en, this message translates to:
  /// **'On the next screen, find and turn on Unknown sources, then press Back on the remote.'**
  String get installPermissionLegacyTv;

  /// No description provided for @settingsCore.
  ///
  /// In en, this message translates to:
  /// **'Core'**
  String get settingsCore;

  /// Under "Core" in Settings › App, whose value names the mihomo core by the core/Clash.Meta commit the release build stamps (e.g. mihomo 70f0570), or plain mihomo in a build without the stamp. There is no separate core download.
  ///
  /// In en, this message translates to:
  /// **'Updates together with the app.'**
  String get settingsCoreHelp;

  /// Settings › App row: checks now, bypassing the 6-hour cap of the automatic check. When an update is known, this row is replaced by the same update card as Home.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingsCheckUpdate;

  /// No description provided for @settingsChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get settingsChecking;

  /// No description provided for @settingsUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You have the latest version.'**
  String get settingsUpToDate;

  /// Red line under settingsCheckUpdate; tapping the row again retries.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check; check your internet and try again.'**
  String get settingsCheckFailed;

  /// Entry button under a failed login code, a failed paste, a failed manual refresh, in the TV support QR dialog, in the phone support sheet and on the Diagnostics page. Each entry first captures the screen it was pressed on, then opens the preview.
  ///
  /// In en, this message translates to:
  /// **'Send a report to Support'**
  String get reportSendToSupport;

  /// The same entry inside the internet-check card at the head of Home after a failed connect. Shown only when the check reached the Shikoo server.
  ///
  /// In en, this message translates to:
  /// **'Send a report'**
  String get reportSendShort;

  /// Settings row in a new «Support» group between Account and App, and the title of the page it opens. Uses the existing key support for the group title.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics and report'**
  String get diagTitle;

  /// No description provided for @diagRowHelp.
  ///
  /// In en, this message translates to:
  /// **'If the app isn\'t working right'**
  String get diagRowHelp;

  /// No description provided for @diagInternetGroup.
  ///
  /// In en, this message translates to:
  /// **'Internet'**
  String get diagInternetGroup;

  /// No description provided for @diagReportGroup.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get diagReportGroup;

  /// Above the full-width reportSendToSupport button on the Diagnostics page. The internet-check card above it has the reading's buttons plus retry.
  ///
  /// In en, this message translates to:
  /// **'If the app isn\'t working right, send Support a report. You see what is sent before it goes.'**
  String get diagReportHelp;

  /// Diagnostics page, instead of the reportSendToSupport button while the check did not reach the Shikoo server. Try again is the check card’s retry.
  ///
  /// In en, this message translates to:
  /// **'The report can’t get through now. When the internet is back, press Try again.'**
  String get diagReportLater;

  /// Phone only: the dialog every Support button opens, title support. Buttons: reportChatTelegram (primary), reportSendToSupport, cancelButton. TV keeps its support QR dialog with reportSendToSupport beside close.
  ///
  /// In en, this message translates to:
  /// **'If the app isn\'t working right, send a report first so Support can see what happened.'**
  String get reportSupportSheetBody;

  /// No description provided for @reportChatTelegram.
  ///
  /// In en, this message translates to:
  /// **'Chat on Telegram'**
  String get reportChatTelegram;

  /// Card at the head of the Home cards, once per crash or ANR found on the next start. Above the update card if both show. Never sends by itself.
  ///
  /// In en, this message translates to:
  /// **'The app closed suddenly last time.'**
  String get reportCrashTitle;

  /// No description provided for @reportCrashAsk.
  ///
  /// In en, this message translates to:
  /// **'Send us a report about it?'**
  String get reportCrashAsk;

  /// Opens the preview.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get reportCrashYes;

  /// Removes the card; the same crash is never asked about again.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get reportCrashNo;

  /// Title of the preview and of the sending, sent and failed states that replace it.
  ///
  /// In en, this message translates to:
  /// **'Report to Support'**
  String get reportTitle;

  /// Caption under the image the app drew itself, at the moment of the tap.
  ///
  /// In en, this message translates to:
  /// **'What the app drew'**
  String get reportImageApp;

  /// Caption under the image of what the device actually put on its screen, at the same moment.
  ///
  /// In en, this message translates to:
  /// **'What the screen showed'**
  String get reportImageScreen;

  /// On by default; off drops both images and shows reportImageOff over them.
  ///
  /// In en, this message translates to:
  /// **'Send the screen pictures too'**
  String get reportImagesSwitch;

  /// No description provided for @reportImageOff.
  ///
  /// In en, this message translates to:
  /// **'Not sent'**
  String get reportImageOff;

  /// No description provided for @reportWhatIsSent.
  ///
  /// In en, this message translates to:
  /// **'Sent: device model and settings, app version, your services’ names and data, your operator and internet status, and the app’s recent activity and errors.'**
  String get reportWhatIsSent;

  /// Bold, right after reportWhatIsSent in the same paragraph.
  ///
  /// In en, this message translates to:
  /// **'Your subscription link and passwords are never sent.'**
  String get reportNeverSent;

  /// Preview: Send (focused on TV) and cancelButton; stacked and pinned to the bottom on a phone, beside the switch on TV.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get reportSend;

  /// Its one button is cancelButton, which stops the send.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get reportSending;

  /// No description provided for @reportSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get reportSentTitle;

  /// Signed in: the report is linked to this device's Telegram account. Buttons: close (primary) and support, which opens the chat directly.
  ///
  /// In en, this message translates to:
  /// **'Support can see your report; you don\'t need to send anything.'**
  String get reportSentLinked;

  /// Not signed in: above the 8-digit code, shown large in two groups of four, e.g. 4821 9037. Buttons: support (primary, opens the chat directly) and close.
  ///
  /// In en, this message translates to:
  /// **'Report code'**
  String get reportCodeLabel;

  /// Signed in: the same code, small, for when Support asks.
  ///
  /// In en, this message translates to:
  /// **'Report code: {code}'**
  String reportCodeSmall(String code);

  /// No description provided for @reportGiveCode.
  ///
  /// In en, this message translates to:
  /// **'Give this code to Support.'**
  String get reportGiveCode;

  /// One sentence under it says why. When the server was not reached: reportFailedHelp; buttons retry (resends the same report and images) and cancelButton. When it answered without taking the report: reportFailedBusy or reportFailedRefused. When the server refused this device's clock: clockWrongTitle and clockWrongHelp in a red message, then dateSettings (primary) and retry.
  ///
  /// In en, this message translates to:
  /// **'Not sent'**
  String get reportFailedTitle;

  /// No answer at all: offline, timed out, or no door reached.
  ///
  /// In en, this message translates to:
  /// **'Check your internet and try again.'**
  String get reportFailedHelp;

  /// The server answered 429: six an hour per device, six per address before sign-in (a carrier may give one address to many phones), or 600 an hour in all. So it never says who sent them. The window is fixed, so an hour is the longest wait. Buttons as reportFailedRefused.
  ///
  /// In en, this message translates to:
  /// **'Too many reports right now. Try again in an hour.'**
  String get reportFailedBusy;

  /// The server answered with any other status: 400, 413, 422, 5xx, or 200 without a code. Over HTTPS only our own server or its front gives such an answer, so the fault is ours. Retry resends the very same report, so a 4xx refuses it again; hence no «try later» here. Buttons: support (primary; on a phone it opens the chat, on TV its QR dialog without the report button) and retry. No cancelButton: back leaves, as on the clock state.
  ///
  /// In en, this message translates to:
  /// **'The problem is on our side. Chat with Support on Telegram.'**
  String get reportFailedRefused;

  /// Internet-check card while the three direct probes run (an Iranian site, a small international address, the Shikoo server). No buttons yet.
  ///
  /// In en, this message translates to:
  /// **'Checking the internet…'**
  String get probeChecking;

  /// No description provided for @probeOk.
  ///
  /// In en, this message translates to:
  /// **'The internet works and the ShikooNet server is reachable.'**
  String get probeOk;

  /// All three probes failed. One button: probeNetSettings. No report button, since a report cannot arrive.
  ///
  /// In en, this message translates to:
  /// **'This device isn\'t connected to the internet.'**
  String get probeOffline;

  /// The Iranian site answered, the international address did not. The report button stays, because the Shikoo server is inside Iran.
  ///
  /// In en, this message translates to:
  /// **'International internet is cut on this line. The servers are outside Iran.'**
  String get probeNoAbroad;

  /// The Shikoo server was not reached and not every probe failed. Says nothing about whose fault it is: when the domestic site failed too, the customer's own line may be the cause. One button: support. No report button, since the report goes to that server.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t reach the ShikooNet server; try again in a few minutes.'**
  String get probeNoDoor;

  /// All probes fine but every server ping failed. Buttons: reportSendShort, support, refreshServers.
  ///
  /// In en, this message translates to:
  /// **'None of the servers answer.'**
  String get probeNoServer;

  /// Opens Android's wireless settings; falls back to the main settings on a TV without that page.
  ///
  /// In en, this message translates to:
  /// **'Internet settings'**
  String get probeNetSettings;

  /// Screen-reader label of the «+» in the phone home's top bar, beside Settings. Phone only, and only while the home shows at least one service card; never on the TV.
  ///
  /// In en, this message translates to:
  /// **'Add a service by link'**
  String get addServiceTooltip;

  /// Top bar title of the screen «+» opens: today's paste block (pasteLink, its messages, reportSendToSupport or dateSettings) under this bar and addServiceHelp.
  ///
  /// In en, this message translates to:
  /// **'Add a service'**
  String get addServiceTitle;

  /// No description provided for @addServiceHelp.
  ///
  /// In en, this message translates to:
  /// **'Copy the ShikooNet subscription link of your other service, then press this button. It joins the others on this phone.'**
  String get addServiceHelp;

  /// Home's bottom bar after a paste added a new service; the screen has closed and the new card is open at the end of the list. New: today a paste shows no message.
  ///
  /// In en, this message translates to:
  /// **'“{name}” was added.'**
  String serviceAdded(String name);

  /// Instead of serviceAdded when the pasted link matches a service on this phone (same normalised link, or the same username on the same host); that card opens. Needs a new result from the paste call, which today answers the same for both.
  ///
  /// In en, this message translates to:
  /// **'This service is already on this phone.'**
  String get serviceAlreadyHere;

  /// Settings group holding orderServices; shown with two services or more.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get servicesGroup;

  /// No description provided for @orderServices.
  ///
  /// In en, this message translates to:
  /// **'Order of services'**
  String get orderServices;

  /// No description provided for @orderServicesHelpTouch.
  ///
  /// In en, this message translates to:
  /// **'On this phone only'**
  String get orderServicesHelpTouch;

  /// No description provided for @orderServicesHelpTv.
  ///
  /// In en, this message translates to:
  /// **'On this TV only'**
  String get orderServicesHelpTv;

  /// No description provided for @orderScreenHelp.
  ///
  /// In en, this message translates to:
  /// **'Hold ≡ on a service and drag it up or down. The order is for this phone only and is saved at once.'**
  String get orderScreenHelp;

  /// Screen-reader label of a row's ≡ handle on the order screen.
  ///
  /// In en, this message translates to:
  /// **'Drag “{name}” to move it'**
  String orderHandleLabel(String name);

  /// TV order screen's top hint while no card is picked; up and down only move the focus then.
  ///
  /// In en, this message translates to:
  /// **'OK: pick up to move'**
  String get orderTvHintRest;

  /// No description provided for @orderTvHintMoving.
  ///
  /// In en, this message translates to:
  /// **'Up and down: move · OK: drop · Back: cancel'**
  String get orderTvHintMoving;

  /// On the picked card, beside its up and down marks; the card is filled with the primary colour.
  ///
  /// In en, this message translates to:
  /// **'Moving'**
  String get orderTvPicked;
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
