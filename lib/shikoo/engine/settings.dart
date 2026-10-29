import 'dart:io' show File, FileSystemException;

import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/enum/enum.dart' show LogLevel;
import 'package:fl_clash/providers/config.dart' show appSettingProvider;
import 'package:fl_clash/providers/state.dart' show ServiceTexts;
import 'package:fl_clash/shikoo/engine/controller.dart' show ShikooCell;
import 'package:fl_clash/shikoo/engine/cores.dart';
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

const shikooTestDoor = _apiOverride != '';

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

/// This device only. A core this build no longer knows is skipped but its key kept, so going back a version loses nothing.
class ShikooCoresNotifier extends Notifier<ShikooChoices> {
  static String _key(ShikooProtocol protocol) => 'shikoo.core.${protocol.name}';

  @override
  ShikooChoices build() => const {};

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final known = ShikooCore.values.asNameMap();
    state = {
      for (final protocol in ShikooProtocol.values)
        protocol: ?known[prefs.getString(_key(protocol))],
    };
  }

  Future<void> set(ShikooProtocol protocol, ShikooCore core) async {
    state = {...state, protocol: core};
    await (await SharedPreferences.getInstance()).setString(
      _key(protocol),
      core.name,
    );
  }

  /// A core whose start took the app down would do it on every start, the pick being stored: it goes back to default.
  Future<void> forgetCrashed(String home) async {
    final file = File('$home/$shikooCoreStartingFile');
    final ShikooCore? core;
    try {
      if (!file.existsSync()) return;
      core = ShikooCore.values.asNameMap()[file.readAsStringSync()];
      file.deleteSync();
    } on FileSystemException catch (e) {
      commonPrint.log(
        'core start marker kept, picks untouched: $e',
        logLevel: LogLevel.warning,
      );
      return;
    }
    // shortcut: every pick of that core goes back, not only the protocol that crashed; name it in the file if a core
    // turns out bad for one protocol only.
    final picked = [
      for (final MapEntry(key: protocol, value: chosen) in state.entries)
        if (chosen == core) protocol,
    ];
    if (picked.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final protocol in picked) {
      await prefs.remove(_key(protocol));
    }
    state = {...state}..removeWhere((protocol, _) => picked.contains(protocol));
    ref.read(shikooCoreRevertedProvider.notifier).set(core);
  }
}

final shikooCoresProvider =
    NotifierProvider<ShikooCoresNotifier, ShikooChoices>(
      ShikooCoresNotifier.new,
    );

final shikooCoreRevertedProvider =
    NotifierProvider<ShikooCell<ShikooCore?>, ShikooCore?>(
      () => ShikooCell(null),
    );

/// FlClash's `autoLaunch`, which its WindowManager writes to Windows' Run key.
final shikooAutoStartProvider = Provider<bool>(
  (ref) => ref.watch(appSettingProvider.select((s) => s.autoLaunch)),
);

void setAutoStart(WidgetRef ref, bool on) => ref
    .read(appSettingProvider.notifier)
    .update((s) => s.copyWith(autoLaunch: on));

class ShikooSwitchNotifier extends Notifier<bool> {
  ShikooSwitchNotifier(this._key);

  final String _key;

  @override
  bool build() => true;

  Future<void> load() async =>
      state = (await SharedPreferences.getInstance()).getBool(_key) ?? true;

  Future<void> set(bool on) async {
    state = on;
    await (await SharedPreferences.getInstance()).setBool(_key, on);
  }
}

final shikooUpdateNoticeProvider = NotifierProvider<ShikooSwitchNotifier, bool>(
  () => ShikooSwitchNotifier('shikoo.updateNotice'),
);

/// Iranian sites bypass the VPN. Turned with `ShikooController.setIranDirect`, which moves the core too.
final shikooIranDirectProvider = NotifierProvider<ShikooSwitchNotifier, bool>(
  () => ShikooSwitchNotifier('shikoo.iranDirect'),
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

/// The staging app, `com.shikoonet.app.dev`; set once at start. On Sam's phone a code from one
/// app was typed into the other's bot while both bore the same name.
bool shikooStaging = false;

extension ShikooAppName on ShikooL10n {
  String get appName => shikooStaging ? appTitleTest : appTitle;
}

final shikooVersionProvider = Provider<String>(
  (ref) => globalState.packageInfo.version,
);

/// The FlClash under this build; a test holds it to `pubspec.yaml`, which each upstream tag raises.
const flclashVersion = '0.8.98';

/// The mihomo tag under `core/Clash.Meta`; a test holds it to the submodule commit. The fork's own
/// `constant.Version` is a stale "1.10.0" that no build sets, and the fork carries no mihomo tags.
const mihomoVersion = '1.19.33';

/// The version, then the `core/Clash.Meta` commit the release workflows stamp
/// (`--dart-define=SHIKOO_CORE`); a build without the stamp names the version alone.
String coreName([String stamp = const String.fromEnvironment('SHIKOO_CORE')]) =>
    'mihomo\u00A0$mihomoVersion${stamp.isEmpty ? '' : '\u00A0($stamp)'}';
