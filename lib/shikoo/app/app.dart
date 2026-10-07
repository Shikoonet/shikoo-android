import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/application.dart';
import 'package:fl_clash/bootstrap.dart';
import 'package:fl_clash/common/string.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/update.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/login.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const _delegates = <LocalizationsDelegate<dynamic>>[
  ShikooL10n.delegate,
  _FlClashStrings(),
  ...GlobalMaterialLocalizations.delegates,
];

/// Run on every start, as FlClash's own shell does; AndroidManager only relabels it on a language change.
Future<bool?>? registerShortcut(App? plugin, String language) =>
    plugin?.initShortcuts(shikooServiceTexts(Locale(language)).toggle);

/// Once per install, and only after [attached]: until then the core has no config, and FlClash toasts "config is not applied".
Future<void> lockLocalPortAfter(
  Future<void> attached,
  ProviderContainer container,
) async {
  await attached;
  container.read(networkSettingProvider.notifier).update((s) {
    if (s.authentication.credentials.isNotEmpty) return s;
    return s.copyWith(
      authentication: AuthenticationProps(
        enable: true,
        username: generateRandomSecret(8),
        password: generateRandomSecret(16),
      ),
    );
  });
}

/// Without FlClash's IP-lookup card on the dashboard, FlClash never looks the IP up; Shikoo shows no IP, and the lookup went out from the customer's own address.
AppSettingProps shikooAppSettings(AppSettingProps s) => s.copyWith(
  disclaimerAccepted: true,
  crashlyticsTip: true,
  crashlytics: false,
  autoCheckUpdate: false,
  dashboardWidgets: const [],
);

class ShikooApp extends ConsumerStatefulWidget {
  const ShikooApp({super.key});

  @override
  ConsumerState<ShikooApp> createState() => _ShikooAppState();
}

class _ShikooAppState extends ConsumerState<ShikooApp>
    with WidgetsBindingObserver {
  StreamSubscription<Uri>? _links;
  Timer? _due;
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
      ref.read(appSettingProvider.notifier).update(shikooAppSettings);
      await lockLocalPortAfter(bootstrap.attach(), globalState.container);
      _attached = true;
      unawaited(registerShortcut(app, ref.read(shikooLookProvider).language));
      ref.read(shikooControllerProvider).onForeground();
      ref.read(shikooSignInProvider).onForeground();
      unawaited(ref.read(shikooUpdateProvider).onForeground());
      // A TV is often left on the home screen for hours: its services stay as fresh as on open.
      _due = Timer.periodic(const Duration(minutes: 1), (_) {
        final controller = ref.read(shikooControllerProvider);
        if (!controller.foreground) return;
        unawaited(controller.refreshDue());
        unawaited(ref.read(shikooUpdateProvider).check());
      });
      if (shikooDebug) _links = AppLinks().uriLinkStream.listen(_onDebugLink);
    });
  }

  /// The controller updates the subscription and pings when the app comes back; Android TV
  /// apps are resumed far more often than started.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_attached) return;
    final resumed = state == AppLifecycleState.resumed;
    final controller = ref.read(shikooControllerProvider)..foreground = resumed;
    final signIn = ref.read(shikooSignInProvider)..foreground = resumed;
    if (resumed) {
      controller.onForeground();
      signIn.onForeground();
      unawaited(ref.read(shikooUpdateProvider).onForeground());
    }
    if (state == AppLifecycleState.paused) controller.clearNews();
  }

  /// Test builds only: `shikoo-debug://add?url=<encoded>&name=<label>` and `shikoo-debug://lang?code=en`.
  /// The link carries a subscription url: never print or log it.
  void _onDebugLink(Uri uri) {
    if (uri.scheme != 'shikoo-debug') return;
    final query = uri.queryParameters;
    switch (uri.host) {
      case 'add':
        final url = query['url'];
        if (url == null) return;
        unawaited(
          ref.read(shikooControllerProvider).addService(url, query['name']),
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
    _due?.cancel();
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
      builder: (context, child) => shikooFrame(
        context,
        child!,
        managers: (page) => buildManagerStack(
          isDesktop: false,
          onConnectivityChanged: _onConnectivityChanged,
          child: page,
        ),
      ),
      home: const ShikooRoot(),
    );
  }
}

/// [ShikooApp]'s builder; a test passes as [managers] only the FlClash managers it can run.
Widget shikooFrame(
  BuildContext context,
  Widget page, {
  required Widget Function(Widget page) managers,
}) =>
    // ignore: deprecated_member_use
    MaterialUiCompatibilityBridge(
      child: IconTheme(
        data: Theme.of(context).iconTheme,
        child: ShikooTvCanvas(child: managers(ShikooSystemUi(child: page))),
      ),
    );

MaterialApp bareApp(
  Widget home, {
  ShikooLook look = (theme: ThemeMode.system, language: shikooDefaultLanguage),
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: Locale(look.language),
  supportedLocales: ShikooL10n.supportedLocales,
  localizationsDelegates: _delegates,
  themeMode: look.theme,
  theme: shikooThemeData(Brightness.light, tv: system.isTV),
  darkTheme: shikooThemeData(Brightness.dark, tv: system.isTV),
  builder: (context, child) =>
      ShikooTvCanvas(child: ShikooSystemUi(child: child!)),
  home: home,
);

class ShikooInitErrorApp extends StatelessWidget {
  const ShikooInitErrorApp({super.key});

  @override
  Widget build(BuildContext context) => bareApp(
    Builder(
      builder: (context) =>
          Scaffold(body: Center(child: Text(ShikooL10n.of(context).initError))),
    ),
  );
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
