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
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Test builds only: `shikoo-debug://add?url=<encoded>&name=<label>` and `shikoo-debug://lang?code=en`.
const _debugLinks = bool.fromEnvironment('SHIKOO_DEBUG');

const _delegates = <LocalizationsDelegate<dynamic>>[
  ShikooL10n.delegate,
  _FlClashStrings(),
  ...GlobalMaterialLocalizations.delegates,
];

class ShikooApp extends ConsumerStatefulWidget {
  const ShikooApp({super.key});

  @override
  ConsumerState<ShikooApp> createState() => _ShikooAppState();
}

class _ShikooAppState extends ConsumerState<ShikooApp>
    with WidgetsBindingObserver {
  StreamSubscription<Uri>? _links;
  bool _hadVpn = false;
  bool _attached = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemNavigator.setFrameworkHandlesBack(true);
    if (system.isTV) {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (globalState.navigatorKey.currentContext == null) exit(0);
      // Saved only because AppStateManager is mounted by now (engine map section 1).
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
      _attached = true;
      ref.read(shikooControllerProvider).onForeground();
      if (_debugLinks) _links = AppLinks().uriLinkStream.listen(_onDebugLink);
    });
  }

  /// The controller updates the subscription and pings when the app comes back; Android TV
  /// apps are resumed far more often than started.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_attached) return;
    final controller = ref.read(shikooControllerProvider);
    if (state == AppLifecycleState.resumed) controller.onForeground();
    if (state == AppLifecycleState.paused) controller.clearNews();
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
        unawaited(
          ref
              .read(shikooLookProvider.notifier)
              .setLanguage(query['code'] ?? shikooDefaultLanguage),
        );
    }
  }

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    unawaited(ref.read(systemActionProvider.notifier).updateLocalIp());
    final hasVpn = results.contains(ConnectivityResult.vpn);
    if (_hadVpn == hasVpn) ref.read(checkIpNumProvider.notifier).add();
    _hadVpn = hasVpn;
  }

  /// Flutter pushes every link the activity receives as a named route, and this app has
  /// none; `app_links` reads links on its own channel.
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) =>
      Future.value(true);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_links?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = ref.watch(shikooLookProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: globalState.navigatorKey,
      onNavigationNotification: (_) => true,
      onGenerateTitle: (context) => ShikooL10n.of(context).appTitle,
      locale: Locale(look.language),
      supportedLocales: ShikooL10n.supportedLocales,
      localizationsDelegates: _delegates,
      themeMode: look.theme,
      theme: shikooThemeData(Brightness.light, tv: system.isTV),
      darkTheme: shikooThemeData(Brightness.dark, tv: system.isTV),
      builder: (context, child) {
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
    );
  }
}

class ShikooInitErrorApp extends StatelessWidget {
  const ShikooInitErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale(shikooDefaultLanguage),
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

/// FlClash's rare dialogs and toasts throw without its strings, and its delegate refuses `fa`.
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
