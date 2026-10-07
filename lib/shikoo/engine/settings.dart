import 'package:fl_clash/providers/state.dart' show ServiceTexts;
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show Locale, ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

abstract final class ShikooLinks {
  /// staging builds name their own bot, as the release workflow checks (`shikoo-staging.yml`).
  static const bot = String.fromEnvironment(
    'SHIKOO_BOT',
    defaultValue: 'shikoonet_bot',
  );
  static const renew = 'https://t.me/$bot?start=renew';
  static const support = 'https://t.me/admiinturbo';

  static String renewOne(int serviceId, String? bot) =>
      'https://t.me/${bot ?? ShikooLinks.bot}?start=rnw_$serviceId';

  static String openBot(String? bot) =>
      'https://t.me/${bot ?? ShikooLinks.bot}';
}

// ponytail: one address until Sam names a backup; ShikooApi tries a second one in turn.
const _apiOverride = String.fromEnvironment('SHIKOO_API');

const shikooApiBases = [
  _apiOverride == '' ? 'https://app.chopon.uk' : _apiOverride,
];

/// Capped once percent-encoded, as the QR carries it: a Persian letter takes six characters.
String? usableLink(String? url) {
  final uri = Uri.tryParse(url ?? '');
  if (uri == null || !{'https', 'http'}.contains(uri.scheme)) return null;
  final link = uri.toString();
  final bareTelegram =
      {'t.me', 'telegram.me'}.contains(uri.host) &&
      uri.pathSegments.every((part) => part.isEmpty);
  return uri.host.isEmpty || bareTelegram || link.length > 512 ? null : link;
}

const shikooDefaultLanguage = String.fromEnvironment(
  'SHIKOO_LANG',
  defaultValue: 'fa',
);

typedef ShikooLook = ({ThemeMode theme, String language});

class ShikooLookNotifier extends Notifier<ShikooLook> {
  static const _themeKey = 'shikoo.theme';
  static const _languageKey = 'shikoo.language';

  @override
  ShikooLook build() =>
      (theme: ThemeMode.system, language: shikooDefaultLanguage);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = (
      theme:
          ThemeMode.values.asNameMap()[prefs.getString(_themeKey)] ??
          state.theme,
      language: prefs.getString(_languageKey) ?? state.language,
    );
  }

  Future<void> setTheme(ThemeMode theme) async {
    state = (theme: theme, language: state.language);
    await (await SharedPreferences.getInstance()).setString(
      _themeKey,
      theme.name,
    );
  }

  Future<void> setLanguage(String language) async {
    state = (theme: state.theme, language: language);
    await (await SharedPreferences.getInstance()).setString(
      _languageKey,
      language,
    );
  }
}

final shikooLookProvider = NotifierProvider<ShikooLookNotifier, ShikooLook>(
  ShikooLookNotifier.new,
);

/// FlClash's l10n has no Persian, so the VPN notification, its toasts and the launcher shortcut
/// take these. [locale] is null before ShikooApp's first frame.
ServiceTexts shikooServiceTexts(Locale? locale) {
  final l = lookupShikooL10n(
    locale != null && ShikooL10n.delegate.isSupported(locale)
        ? locale
        : const Locale(shikooDefaultLanguage),
  );
  return (
    stop: l.notificationStop,
    startTip: l.powerConnecting,
    stopTip: l.notificationStopping,
    toggle: l.shortcutToggle,
  );
}

final shikooVersionProvider = Provider<String>(
  (ref) => globalState.packageInfo.version,
);
