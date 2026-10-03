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

  /// No description provided for @noService.
  ///
  /// In en, this message translates to:
  /// **'No service yet'**
  String get noService;

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
  /// **'{server} didn\'t answer in {seconds} seconds. Try another server too.'**
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
