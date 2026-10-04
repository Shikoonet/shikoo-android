import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

abstract final class ShikooLinks {
  static const bot = 'shikoonet_bot';
  static const renew = 'https://t.me/$bot?start=renew';
  static const support = 'https://t.me/admiinturbo';

  /// [bot] as the server names it, so a test bot's sign-in renews in the test bot.
  static String renewOne(int serviceId, String? bot) =>
      'https://t.me/${bot ?? ShikooLinks.bot}?start=rnw_$serviceId';

  static String openBot(String? bot) =>
      'https://t.me/${bot ?? ShikooLinks.bot}';
}

// ponytail: Sam picks the app API's domains; the empty second one is the backup for when the
// first is blocked. A test build points both at one server with --dart-define=SHIKOO_API=<url>.
const _apiBases = ['https://app.chopon.uk', ''];
const _apiOverride = String.fromEnvironment('SHIKOO_API');

final shikooApiBases = [
  for (final base in _apiOverride.isEmpty ? _apiBases : const [_apiOverride])
    if (base.isNotEmpty) base,
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

final shikooVersionProvider = Provider<String>(
  (ref) => globalState.packageInfo.version,
);
