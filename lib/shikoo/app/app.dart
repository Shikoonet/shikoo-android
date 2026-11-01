import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/application.dart';
import 'package:fl_clash/bootstrap.dart';
import 'package:fl_clash/common/string.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/status_manager.dart' show StatusManager;
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/app/alerts.dart';
import 'package:fl_clash/shikoo/app/desktop.dart';
import 'package:fl_clash/shikoo/app/windows_proxy.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:fl_clash/shikoo/engine/owner.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/update.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/login.dart';
import 'package:fl_clash/shikoo/ui/logs.dart' show LogsShortcut;
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart' show ringOnKeys;
import 'package:fl_clash/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:proxy/proxy_platform_interface.dart';

const _delegates = <LocalizationsDelegate<dynamic>>[
  ShikooL10n.delegate,
  _FlClashStrings(),
  ...GlobalMaterialLocalizations.delegates,
];

/// FlClash's hooks, filled before it starts: its service texts in the app's language, and its messages logged, never drawn.
void fillFlClashHooks() {
  serviceTexts = shikooServiceTexts;
  tunnelOwner = (ref) => ref.watch(shikooOwnerProvider);
  StatusManager.showMessages = false;
  if (Platform.isWindows) {
    ProxyPlatform.instance = ShikooSystemProxy(
      ProxyPlatform.instance,
      () => globalState.container.read(patchClashConfigProvider).mixedPort,
    );
  }
}

/// Run on every start, as FlClash's own shell does; AndroidManager only relabels it on a language change.
Future<bool?>? registerShortcut(App? plugin, String language) =>
    plugin?.initShortcuts(shikooServiceTexts(Locale(language)).toggle);

/// After [attached], before which the core has no config and FlClash toasts "config is not applied": the local port's
/// password, once per install, and the core's log, on every start. On a first install FlClash's own startLog and the
/// stopLog of its default wait for the core together, then race in goroutines of their own, and the report loses every core line.
Future<void> afterAttach(
  Future<void> attached,
  ProviderContainer container, {
  required bool desktop,
}) async {
  await attached;
  container.read(coreHandlerProvider).startLog();
  container
      .read(networkSettingProvider.notifier)
      .update((s) => portLock(s, desktop: desktop));
}

/// Windows' system proxy carries no password (a 407 for every app); `allow-lan` keeps the port local.
NetworkProps portLock(NetworkProps s, {required bool desktop}) {
  if (desktop) return s.copyWith(authentication: const AuthenticationProps());
  if (s.authentication.credentials.isNotEmpty) return s;
  return s.copyWith(
    authentication: AuthenticationProps(
      enable: true,
      username: generateRandomSecret(8),
      password: generateRandomSecret(16),
    ),
  );
}

/// Without FlClash's IP-lookup card on the dashboard, FlClash never looks the IP up; Shikoo shows no IP, and the lookup went out from the customer's own address.
AppSettingProps shikooAppSettings(AppSettingProps s) => s.copyWith(
  disclaimerAccepted: true,
  crashlyticsTip: true,
  crashlytics: false,
  autoCheckUpdate: false,
  dashboardWidgets: const [],
  openLogs: true,
  silentLaunch: shikooAutostarted,
);

/// FlClash asks Android which app owns every connection (`find-process-mode: always`) for per-app rules Shikoo never
/// has; without QUERY_ALL_PACKAGES the answer is empty for other apps anyway.
PatchClashConfig shikooClashConfig(
  PatchClashConfig c, {
  bool desktop = false,
}) => c.copyWith(
  logLevel: LogLevel.warning,
  findProcessMode: FindProcessMode.off,
  allowLan: false,
  mixedPort: desktop ? shikooDesktopPort : c.mixedPort,
);

const _reapplyOnNetworkChange = bool.fromEnvironment('SHIKOO_WG_REAPPLY');

/// A TV is often left on the home screen for hours: its services stay as fresh as on open.
void everyMinute(ProviderContainer container) {
  final controller = container.read(shikooControllerProvider);
  final update = container.read(shikooUpdateProvider);
  if (!controller.foreground) {
    if (shikooDesktop) unawaited(update.check(hidden: true));
    return;
  }
  unawaited(controller.refreshDue());
  container.read(shikooSignInProvider).onMinute();
  unawaited(update.check());
}

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
    } else if (system.isDesktop) {
      ringOnKeys();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (globalState.navigatorKey.currentContext == null) exit(0);
      // Saved only because AppStateManager is mounted by now (engine map section 1).
      ref.read(appSettingProvider.notifier).update(shikooAppSettings);
      await afterAttach(
        bootstrap.attach(),
        globalState.container,
        desktop: system.isDesktop,
      );
      ref
          .read(patchClashConfigProvider.notifier)
          .update((c) => shikooClashConfig(c, desktop: system.isDesktop));
      unawaited(shikooDiag.attach(globalState.container));
      shikooDiag.watchUi();
      _attached = true;
      unawaited(registerShortcut(app, ref.read(shikooLookProvider).language));
      ref.read(shikooControllerProvider).onForeground();
      ref.read(shikooSignInProvider).onForeground();
      unawaited(ref.read(shikooUpdateProvider).onForeground());
      if (system.isAndroid) unawaited(ref.read(shikooAlertsProvider).start());
      _due = Timer.periodic(
        const Duration(minutes: 1),
        (_) => everyMinute(globalState.container),
      );
      if (shikooDebug) _links = AppLinks().uriLinkStream.listen(_onDebugLink);
    });
  }

  /// The controller updates the subscription when the app comes back; Android TV apps are
  /// resumed far more often than started.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_attached) return;
    final resumed = state == AppLifecycleState.resumed;
    final controller = ref.read(shikooControllerProvider)..foreground = resumed;
    final signIn = ref.read(shikooSignInProvider)
      ..foreground = resumed || state == AppLifecycleState.inactive;
    if (resumed) {
      controller.onForeground();
      signIn.onForeground();
      unawaited(ref.read(shikooUpdateProvider).onForeground());
    }
    if (state == AppLifecycleState.paused) controller.onBackground();
  }

  /// Test builds only: `shikoo-debug://add?url=<encoded>&name=<label>[&outsourced=true]`, `lang?code=en`, `warp?on=true` and `crash`.
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
              .addService(url, query['name'])
              .then((failure) {
                if (!mounted ||
                    failure != null ||
                    query['outsourced'] != 'true') {
                  return;
                }
                ref
                    .read(shikooAccountProvider.notifier)
                    .set(
                      ShikooAccount(
                        services: [
                          LinkedService(
                            id: 0,
                            title: query['name'] ?? '',
                            status: 'active',
                            profileId: ref.read(currentProfileIdProvider),
                            outsourced: true,
                          ),
                        ],
                      ),
                    );
              }),
        );
      case 'lang':
        unawaited(
          ref
              .read(shikooLookProvider.notifier)
              .setLanguage(query['code'] ?? shikooDefaultLanguage),
        );
      case 'warp':
        unawaited(
          ref.read(shikooControllerProvider).setBridge(query['on'] == 'true'),
        );
      case 'crash':
        unawaited(coreController.crash());
    }
  }

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    shikooDiag.network(results);
    ref.read(shikooControllerProvider).onNetworkChange();
    unawaited(ref.read(systemActionProvider.notifier).updateLocalIp());
    final hasVpn = results.contains(ConnectivityResult.vpn);
    if (_hadVpn == hasVpn) ref.read(checkIpNumProvider.notifier).add();
    _hadVpn = hasVpn;
    // ponytail: off until a real WireGuard network switch in tunnel mode shows the new config's new sockets are needed.
    if (_reapplyOnNetworkChange &&
        system.isDesktop &&
        ref.read(runTimeProvider) != null &&
        ref.read(patchClashConfigProvider).tun.enable) {
      unawaited(
        ref
            .read(setupActionProvider.notifier)
            .applyProfile(force: true, silence: true),
      );
    }
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
      navigatorObservers: [shikooDiag.routes],
      onNavigationNotification: (_) => true,
      onGenerateTitle: (context) => ShikooL10n.of(context).appName,
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
          isDesktop: system.isDesktop,
          onConnectivityChanged: _onConnectivityChanged,
          desktopFrame: system.isWindows
              ? (page) => ShikooWindow(child: page)
              : null,
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
}) => RepaintBoundary(
  key: shikooDiag.appKey,
  child: NotificationListener<ScrollEndNotification>(
    onNotification: shikooDiag.onScrollEnd,
    // ignore: deprecated_member_use
    child: MaterialUiCompatibilityBridge(
      child: IconTheme(
        data: Theme.of(context).iconTheme,
        child: ShikooTvCanvas(
          child: managers(ShikooSystemUi(child: LogsShortcut(child: page))),
        ),
      ),
    ),
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
