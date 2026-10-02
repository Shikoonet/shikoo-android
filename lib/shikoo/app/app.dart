import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/application.dart';
import 'package:fl_clash/bootstrap.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Test builds only (`--dart-define=SHIKOO_DEBUG=true`): `shikoo-debug://add?url=<encoded>&name=<label>`
/// adds a service and `shikoo-debug://lang?code=en` switches the language. A build without the
/// define compiles the listener out.
const _debugLinks = bool.fromEnvironment('SHIKOO_DEBUG');

/// Persian unless a build asks otherwise (`--dart-define=SHIKOO_LANG=en`).
const _defaultLanguage = String.fromEnvironment(
  'SHIKOO_LANG',
  defaultValue: 'fa',
);

const _delegates = <LocalizationsDelegate<dynamic>>[
  ShikooL10n.delegate,
  _FlClashStrings(),
  ...GlobalMaterialLocalizations.delegates,
];

/// Replaces FlClash's `Application` (lib/application.dart) and keeps what its engine needs
/// from it: docs/flclash-engine-map.md section 1.
class ShikooApp extends ConsumerStatefulWidget {
  const ShikooApp({super.key});

  @override
  ConsumerState<ShikooApp> createState() => _ShikooAppState();
}

class _ShikooAppState extends ConsumerState<ShikooApp> {
  final _locale = ValueNotifier(const Locale(_defaultLanguage));
  Timer? _profilesTimer;
  StreamSubscription<Uri>? _links;
  bool _hadVpn = false;

  @override
  void initState() {
    super.initState();
    SystemNavigator.setFrameworkHandlesBack(true);
    if (system.isTV) {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (globalState.navigatorKey.currentContext == null) exit(0);
      // FlClash's own first-run dialogs (disclaimer, data collection) and its GitHub update
      // check stay off. AppStateManager is mounted by now, so the write is saved.
      ref
          .read(appSettingProvider.notifier)
          .update(
            (s) => s.copyWith(
              disclaimerAccepted: true,
              crashlyticsTip: true,
              crashlytics: false,
              autoCheckUpdate: false,
            ),
          );
      await bootstrap.attach();
      _scheduleProfileUpdates();
      if (_debugLinks) _links = AppLinks().uriLinkStream.listen(_onDebugLink);
    });
  }

  void _scheduleProfileUpdates() {
    _profilesTimer = Timer(const Duration(minutes: 20), () async {
      await ref.read(profilesActionProvider.notifier).autoUpdateProfiles();
      if (mounted) _scheduleProfileUpdates();
    });
  }

  /// The link carries a subscription url: never print or log it.
  void _onDebugLink(Uri uri) {
    if (uri.scheme != 'shikoo-debug') return;
    final query = uri.queryParameters;
    switch (uri.host) {
      case 'add':
        final url = query['url'];
        if (url == null) return;
        unawaited(
          ref
              .read(shikooControllerProvider)
              .addService(url, query['name'] ?? Uri.parse(url).host),
        );
      case 'lang':
        _locale.value = Locale(query['code'] ?? _defaultLanguage);
    }
  }

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    unawaited(ref.read(systemActionProvider.notifier).updateLocalIp());
    final hasVpn = results.contains(ConnectivityResult.vpn);
    if (_hadVpn == hasVpn) ref.read(checkIpNumProvider.notifier).add();
    _hadVpn = hasVpn;
  }

  @override
  void dispose() {
    _profilesTimer?.cancel();
    unawaited(_links?.cancel());
    _locale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _locale,
      builder: (_, locale, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: globalState.navigatorKey,
        onNavigationNotification: (_) => true,
        onGenerateTitle: (context) => ShikooL10n.of(context).appTitle,
        locale: locale,
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: _delegates,
        theme: shikooThemeData(Brightness.light, tv: system.isTV),
        darkTheme: shikooThemeData(Brightness.dark, tv: system.isTV),
        builder: (context, child) {
          // Same wrapping as FlClash's Application.build; see the note there.
          // ignore: deprecated_member_use
          return MaterialUiCompatibilityBridge(
            child: IconTheme(
              data: Theme.of(context).iconTheme,
              child: buildManagerStack(
                isDesktop: false,
                onConnectivityChanged: _onConnectivityChanged,
                child: child!,
              ),
            ),
          );
        },
        home: const ShikooHome(),
      ),
    );
  }
}

/// Shown when the engine fails to boot, instead of FlClash's InitErrorScreen.
class ShikooInitErrorApp extends StatelessWidget {
  const ShikooInitErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale(_defaultLanguage),
      supportedLocales: ShikooL10n.supportedLocales,
      localizationsDelegates: _delegates,
      theme: shikooThemeData(Brightness.light, tv: system.isTV),
      darkTheme: shikooThemeData(Brightness.dark, tv: system.isTV),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(child: Text(ShikooL10n.of(context).initError)),
        ),
      ),
    );
  }
}

/// FlClash's own delegate refuses `fa`, and its rare dialogs and toasts (engine map, risk 2)
/// read AppLocalizations; without one for every locale they would throw. They stay English.
class _FlClashStrings extends LocalizationsDelegate<AppLocalizations> {
  const _FlClashStrings();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      AppLocalizations.load(const Locale('en'));

  @override
  bool shouldReload(_FlClashStrings old) => false;
}
