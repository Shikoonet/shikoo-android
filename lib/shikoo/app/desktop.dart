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
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart' show restingFor;
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart' show BrandMark;
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  VoidCallback open,
  VoidCallback exit,
});

/// win-modes.html, frame `win-t-c`, and the line under `win-ic-a`: the tip and the fox tell
/// the state, grey until connected.
TraySpec shikooTraySpec(
  ShikooL10n l, {
  required ShikooConnection connection,
  required String? server,
  required bool canConnect,
  required ShikooMode mode,
  required TrayActions on,
}) {
  final app = l.appName;
  final connected = connection == ShikooConnection.on;
  final connecting = connection == ShikooConnection.connecting;
  final status = connected ? (mode == ShikooMode.tunnel ? 3 : 2) : 1;
  return TraySpec(
    icon: TrayIcon.asset('assets/images/tray/windows/status_$status.ico'),
    toolTip: switch (connection) {
      ShikooConnection.on => l.trayOn(app, server ?? ''),
      ShikooConnection.connecting => l.trayConnecting(app),
      _ => l.trayOff(app),
    },
    menu: [
      TrayMenuAction(
        label: switch ((connection, server)) {
          (ShikooConnection.on, final server?) => l.trayHeadOn(server),
          (ShikooConnection.on, null) => l.powerOn,
          (ShikooConnection.connecting, final server?) => l.trayHeadConnecting(
            server,
          ),
          (ShikooConnection.connecting, null) => l.powerConnecting,
          _ => l.trayHeadOff,
        },
        enabled: false,
      ),
      const TrayMenuSeparator(),
      if (connected || connecting)
        TrayMenuAction(label: l.trayDisconnect, onSelected: on.disconnect)
      else
        TrayMenuAction(
          label: l.trayConnect,
          enabled: canConnect,
          onSelected: on.connect,
        ),
      const TrayMenuSeparator(),
      for (final (choice, label) in [
        (ShikooMode.tunnel, l.modeTunnel),
        (ShikooMode.proxy, l.modeProxy),
      ])
        TrayMenuCheckbox(
          label: label,
          checked: mode == choice,
          enabled: !connecting,
          onSelected: () => on.mode(choice),
        ),
      const TrayMenuSeparator(),
      TrayMenuAction(label: l.trayOpen(app), onSelected: on.open),
      TrayMenuAction(label: l.trayExit, onSelected: on.exit),
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
  const ShikooWindow({super.key, required this.child, this.notify = _balloon});

  final Widget child;
  final Future<void> Function(String title, String body) notify;

  @override
  ConsumerState<ShikooWindow> createState() => _ShikooWindowState();
}

class _ShikooWindowState extends ConsumerState<ShikooWindow>
    with WindowListener {
  final _caption = WindowCaptionController();
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _caption.dispose();
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    final l = ShikooL10n.of(context);
    final (connection, server, canConnect) = ref.watch(
      shikooStateProvider.select(
        (s) => (
          s.connection,
          s.selectedServer?.label,
          s.service != null && restingFor(s) == null,
        ),
      ),
    );
    final controller = ref.read(shikooControllerProvider);
    final spec = shikooTraySpec(
      l,
      connection: connection,
      server: server,
      canConnect: canConnect,
      mode: ref.watch(shikooModeProvider),
      on: (
        connect: () => unawaited(controller.connect()),
        disconnect: () => unawaited(controller.disconnect()),
        mode: (mode) => unawaited(controller.setMode(mode)),
        open: () => unawaited(window?.show()),
        exit: _exit,
      ),
    );
    // The plugin skips a spec equal to the last one.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(shikooTray.show(spec)),
    );
    return Overlay.wrap(
      child: Column(
        children: [
          _TitleBar(caption: _caption),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
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
