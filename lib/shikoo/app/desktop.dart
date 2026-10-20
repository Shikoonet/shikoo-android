import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:fl_clash/common/common.dart'
    show ProviderReader, TrayPort, appName, trayPort;
import 'package:fl_clash/common/launch.dart';
import 'package:fl_clash/common/window.dart';
import 'package:fl_clash/manager/window_manager.dart'
    show CaptionGlyph, CaptionIcon, WindowCaptionController;
import 'package:fl_clash/models/models.dart' show Traffic, TrayState;
import 'package:fl_clash/providers/providers.dart'
    show systemActionProvider, windowSettingProvider;
import 'package:fl_clash/shikoo/app/tray_popup.dart';
import 'package:fl_clash/shikoo/engine/account.dart' show shikooAccountProvider;
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/update.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/icons.dart' show ShikooIcon;
import 'package:fl_clash/shikoo/ui/service_card.dart' show restingFor;
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/update.dart' show homeUpdateCard;
import 'package:fl_clash/shikoo/ui/widgets.dart'
    show BrandMark, clockOf, revealWithRing;
import 'package:fl_clash/state.dart' show globalState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show Bidi;
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray/tray.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

const shikooAutostartArg = '--autostart';

/// Set from `main`'s arguments: Windows started the app, which then stays beside the clock.
bool shikooAutostarted = false;

/// After `bootstrap.init`, which opens FlClash's window at 680×580, lets it shrink to 380×400 and
/// hands the tray to FlClash's own menu.
Future<void> shikooWindowStart(ProviderContainer container) async {
  trayPort = shikooTray;
  if (autoLaunch != null) {
    // FlClash's AutoLaunch, built just now, set the launcher up without arguments.
    launchAtStartup.setup(
      appName: appName,
      appPath: Platform.resolvedExecutable,
      args: const [shikooAutostartArg],
    );
  }
  await windowManager.setMinimumSize(ShikooSizes.windowMin);
  if (container.read(windowSettingProvider).width == 0) {
    await windowManager.setSize(ShikooSizes.windowStart);
    await windowManager.center();
  }
}

class ShikooTray implements TrayPort {
  bool _down = false;

  Future<void> show(TraySpec spec) async {
    if (!_down) await Tray.instance.show(spec);
  }

  /// FlClash's menu; [ShikooWindow] shows this app's own.
  @override
  Future<void> update({
    required TrayState trayState,
    required Traffic traffic,
    required ProviderReader read,
  }) async {}

  @override
  Future<void> shutdown() async {
    _down = true;
    await Tray.instance.hide();
  }
}

final shikooTray = ShikooTray();

typedef TrayActions = ({
  VoidCallback connect,
  VoidCallback disconnect,
  ValueChanged<ShikooMode> mode,
  VoidCallback update,
  VoidCallback open,
  VoidCallback exit,
});

/// The tip and the fox tell the state, grey until connected (win-modes.html, `win-ic-a`).
TraySpec shikooTraySpec(
  ShikooL10n l, {
  required ShikooConnection connection,
  required String? server,
  required ShikooMode mode,
}) {
  final app = l.appName;
  final status = connection == ShikooConnection.on
      ? (mode == ShikooMode.tunnel ? 3 : 2)
      : 1;
  return TraySpec(
    icon: TrayIcon.asset('assets/images/tray/windows/status_$status.ico'),
    toolTip: switch (connection) {
      ShikooConnection.on => l.trayOn(app, server ?? ''),
      ShikooConnection.connecting => l.trayConnecting(app),
      _ => l.trayOff(app),
    },
  );
}

/// win-modes.html, frame `win-t-c`.
TrayMenu shikooTrayMenu(
  ShikooL10n l, {
  required ShikooConnection connection,
  required String? server,
  required Duration connectedFor,
  required bool canConnect,
  required bool hasService,
  required bool signedIn,
  required bool hasUpdate,
  required ShikooMode mode,
  required TrayActions on,
}) {
  final connected = connection == ShikooConnection.on;
  final connecting = connection == ShikooConnection.connecting;
  final idle = hasService
      ? null
      : (signedIn ? l.trayHeadNoService : l.trayHeadSignIn);
  TrayRow row(
    String label,
    VoidCallback run, {
    ShikooIcon? icon,
    bool dot = false,
    bool enabled = true,
  }) => (label: label, icon: icon, dot: dot, enabled: enabled, run: run);
  return (
    head:
        idle ??
        switch ((connection, server)) {
          (ShikooConnection.on, final server?) => l.trayHeadOn(server),
          (ShikooConnection.on, null) => l.powerOn,
          (ShikooConnection.connecting, final server?) => l.trayHeadConnecting(
            server,
          ),
          (ShikooConnection.connecting, null) => l.powerConnecting,
          _ => l.trayHeadOff,
        },
    on: connected,
    muted: idle != null,
    time: connected ? clockOf(l.localeName, connectedFor) : null,
    rows: [
      if (hasUpdate) ...[
        row(l.updateTitle, on.update, icon: ShikooIcon.download),
        null,
      ],
      if (connected || connecting)
        row(l.trayDisconnect, on.disconnect, icon: ShikooIcon.power)
      else
        row(
          l.trayConnect,
          on.connect,
          icon: ShikooIcon.power,
          enabled: canConnect,
        ),
      null,
      for (final (choice, label) in [
        (ShikooMode.tunnel, l.modeTunnel),
        (ShikooMode.proxy, l.modeProxy),
      ])
        row(
          label,
          () => on.mode(choice),
          dot: mode == choice,
          enabled: !connecting,
        ),
      null,
      row(l.trayOpen(l.appName), on.open),
      row(l.trayExit, on.exit),
    ],
  );
}

const _closeNoticeKey = 'shikoo.closeNotice';

/// win-c-a: the first close ever says where the window went; every later one says nothing.
@visibleForTesting
Future<void> noticeOnce(Future<void> Function() notify) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_closeNoticeKey) ?? false) return;
  await prefs.setBool(_closeNoticeKey, true);
  await notify();
}

const _updateNoticeKey = 'shikoo.updateNoticed';

/// Once per version, only with Settings' switch on and nobody seeing the window; true once sent.
@visibleForTesting
Future<bool> noticeUpdate(
  int code, {
  required bool on,
  required Future<bool> Function() hidden,
  required Future<void> Function() notify,
}) async {
  if (!on) return false;
  final prefs = await SharedPreferences.getInstance();
  if (code <= (prefs.getInt(_updateNoticeKey) ?? 0)) return false;
  if (!await hidden()) return false;
  await prefs.setInt(_updateNoticeKey, code);
  await notify();
  return true;
}

Future<bool> _windowHidden() async =>
    !await windowManager.isVisible() || await windowManager.isMinimized();

/// Windows' own notification, from the tray icon: the window is hidden by then.
Future<void> _balloon(String title, String body) async {
  final window = await windowManager.getId();
  final data = calloc<NOTIFYICONDATA>();
  try {
    data.ref
      ..cbSize = sizeOf<NOTIFYICONDATA>()
      ..hWnd = HWND(Pointer.fromAddress(window))
      // kTrayIconId in plugins/tray/windows/tray_plugin.cpp.
      ..uID = 1
      ..uFlags = NIF_INFO
      ..szInfoTitle = title
      ..szInfo = body
      ..dwInfoFlags = NIIF_USER;
    Shell_NotifyIcon(NIM_MODIFY, data);
  } finally {
    calloc.free(data);
  }
}

/// The window around every page: win-modes.html's `.titlebar`, the tray it keeps current, and
/// the close notice. FlClash's WindowManager hides the window on close (`minimizeOnExit`).
class ShikooWindow extends ConsumerStatefulWidget {
  const ShikooWindow({
    super.key,
    required this.child,
    this.notify = _balloon,
    this.hidden = _windowHidden,
    this.popup,
  });

  final Widget child;
  final Future<void> Function(String title, String body) notify;

  final Future<bool> Function() hidden;

  /// A test's stand-in for the menu beside the clock.
  final TrayPopup? popup;

  @override
  ConsumerState<ShikooWindow> createState() => _ShikooWindowState();
}

class _ShikooWindowState extends ConsumerState<ShikooWindow>
    with WindowListener {
  final _caption = WindowCaptionController();
  late final _popup = widget.popup ?? TrayPopup();
  StreamSubscription<TrayEvent>? _menuRequests;
  bool _exiting = false;

  /// The update message went out since the window last had the focus.
  bool _noticed = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _popup.onClose = _showTray;
    _menuRequests = Tray.instance.events.listen((event) {
      if (event is TrayMenuRequested) unawaited(_openMenu());
      // shortcut: a message click arrives as an icon click (tray_plugin.cpp); split them if that matters.
      if (event is TrayIconActivated && _noticed) unawaited(_openUpdate());
    });
    // Not from build: FlClash stops building frames once the window has been hidden a while.
    ref
      ..listenManual(shikooStateProvider, (_, _) => _showTray())
      ..listenManual(shikooModeProvider, (_, _) => _showTray())
      ..listenManual(shikooLookProvider, (_, _) => _showTray())
      ..listenManual(shikooAccountProvider, (_, _) => _showTray())
      ..listenManual<UpdateOffer?>(shikooUpdateOfferProvider, _onOffer);
    unawaited(ref.read(shikooUpdateNoticeProvider.notifier).load());
    _showTray();
  }

  void _onOffer(UpdateOffer? before, UpdateOffer? now) {
    _showTray();
    final code = now?.release.versionCode;
    if (code == null || code == before?.release.versionCode) return;
    final l = lookupShikooL10n(Locale(ref.read(shikooLookProvider).language));
    unawaited(
      noticeUpdate(
        code,
        on: ref.read(shikooUpdateNoticeProvider),
        hidden: widget.hidden,
        notify: () =>
            widget.notify(l.updateNoticeTitle(l.appName), l.updateNoticeBody),
      ).then((sent) => _noticed |= sent),
    );
  }

  Future<void> _openUpdate() async {
    _noticed = false;
    await window?.show();
    globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    // Home builds its card only in the frames after it is drawn again.
    for (var i = 0; i < 3 && homeUpdateCard.currentContext == null; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    final card = homeUpdateCard.currentContext;
    if (card != null && card.mounted) {
      revealWithRing(card);
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    unawaited(_menuRequests?.cancel());
    _popup
      ..onClose = null
      ..close();
    _caption.dispose();
    super.dispose();
  }

  @override
  void onWindowFocus() => _noticed = false;

  /// Exit closes the window too, and says nothing.
  @override
  void onWindowClose() {
    if (_exiting) return;
    final l = ShikooL10n.of(context);
    final app = l.appName;
    unawaited(
      noticeOnce(
        () => widget.notify(l.closedToTrayTitle(app), l.closedToTrayBody(app)),
      ),
    );
  }

  void _exit() {
    _exiting = true;
    unawaited(ref.read(systemActionProvider.notifier).handleExit());
  }

  /// Empties Windows' tip first; that waits behind FlClash's empty menu taking the foreground.
  Future<void> _openMenu() async {
    await shikooTray.show(TraySpec(icon: _spec().icon));
    _showTray(open: true);
  }

  TraySpec _spec() {
    final state = ref.read(shikooStateProvider);
    return shikooTraySpec(
      lookupShikooL10n(Locale(ref.read(shikooLookProvider).language)),
      connection: state.connection,
      server: state.selectedServer?.label,
      mode: ref.read(shikooModeProvider),
    );
  }

  void _showTray({bool open = false}) {
    final look = ref.read(shikooLookProvider);
    final l = lookupShikooL10n(Locale(look.language));
    final state = ref.read(shikooStateProvider);
    final mode = ref.read(shikooModeProvider);
    final server = state.selectedServer?.label;
    final controller = ref.read(shikooControllerProvider);
    final TrayView view = (
      menu: shikooTrayMenu(
        l,
        connection: state.connection,
        server: server,
        connectedFor: state.connectedFor,
        canConnect: state.service != null && restingFor(state) == null,
        hasService: state.service != null,
        signedIn: ref.read(shikooAccountProvider).who != null,
        hasUpdate: ref.read(shikooUpdateOfferProvider) != null,
        mode: mode,
        on: (
          connect: () => unawaited(controller.connect()),
          disconnect: () => unawaited(controller.disconnect()),
          mode: (mode) => unawaited(controller.setMode(mode)),
          update: () => unawaited(_openUpdate()),
          open: () => unawaited(window?.show()),
          exit: _exit,
        ),
      ),
      brightness: switch (look.theme) {
        ThemeMode.light => Brightness.light,
        ThemeMode.dark => Brightness.dark,
        ThemeMode.system =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
      },
      direction: Bidi.isRtlLanguage(look.language)
          ? TextDirection.rtl
          : TextDirection.ltr,
    );
    if (open) {
      unawaited(_popup.show(view));
    } else {
      _popup.update(view);
    }
    final spec = _spec();
    unawaited(
      shikooTray.show(_popup.isOpen ? TraySpec(icon: spec.icon) : spec),
    );
  }

  @override
  Widget build(BuildContext context) => Overlay.wrap(
    child: Column(
      children: [
        _TitleBar(caption: _caption),
        Expanded(child: widget.child),
      ],
    ),
  );
}

/// `.titlebar`: left to right in both languages, as Windows draws its own.
class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.caption});

  final WindowCaptionController caption;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    Widget button(
      CaptionGlyph glyph,
      String tip,
      VoidCallback onPressed, {
      bool close = false,
    }) => IconButton(
      tooltip: tip,
      onPressed: onPressed,
      style: ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        fixedSize: const WidgetStatePropertyAll(
          Size(ShikooSizes.captionButton, ShikooSizes.titleBar),
        ),
        minimumSize: const WidgetStatePropertyAll(
          Size(ShikooSizes.captionButton, ShikooSizes.titleBar),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: const WidgetStatePropertyAll(RoundedSuperellipseBorder()),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.pressed)
              ? (close ? t.c.danger : t.c.selectedBg)
              : null,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => close && states.contains(WidgetState.hovered)
              ? t.c.onDanger
              : t.c.text,
        ),
      ),
      icon: CaptionIcon(glyph),
    );
    return Material(
      color: t.c.surface,
      child: SizedBox(
        height: ShikooSizes.titleBar,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => unawaited(windowManager.startDragging()),
                  onDoubleTap: () => unawaited(caption.toggleMaximized()),
                  child: Padding(
                    padding: const EdgeInsets.only(left: Space.s3),
                    child: Row(
                      spacing: Space.s2,
                      children: [
                        const BrandMark(size: ShikooSizes.titleMark),
                        Expanded(
                          child: Text(
                            l.appName,
                            maxLines: 1,
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.left,
                            style: t.text(t.s.caption, height: 1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder(
                valueListenable: caption,
                builder: (context, state, _) {
                  final big = state.isMaximized || state.isFullScreen;
                  return Row(
                    children: [
                      button(
                        CaptionGlyph.minimize,
                        l.windowMinimize,
                        () => unawaited(windowManager.minimize()),
                      ),
                      button(
                        big ? CaptionGlyph.restore : CaptionGlyph.maximize,
                        big ? l.windowRestore : l.windowMaximize,
                        () => unawaited(caption.toggleMaximized()),
                      ),
                      button(
                        CaptionGlyph.close,
                        l.windowClose,
                        () => unawaited(windowManager.close()),
                        close: true,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
