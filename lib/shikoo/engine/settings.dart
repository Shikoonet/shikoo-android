import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

abstract final class ShikooLinks {
  static const bot = 'https://t.me/shikoonet_bot';

  // The customer's own services; the bot's link to one service, rnw_<id>, needs a bot row id.
  static const renew = '$bot?start=renew';
  static const support = 'https://t.me/admiinturbo';
}

String? usableLink(String? url) {
  final uri = url == null || url.length > 512 ? null : Uri.tryParse(url);
  if (uri == null || !{'https', 'http'}.contains(uri.scheme)) return null;
  final bareTelegram =
      {'t.me', 'telegram.me'}.contains(uri.host) &&
      uri.pathSegments.every((part) => part.isEmpty);
  return uri.host.isEmpty || bareTelegram ? null : uri.toString();
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

  /// Before the first frame, so the app never opens in the wrong theme or language.
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
