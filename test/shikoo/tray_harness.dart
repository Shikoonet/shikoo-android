import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/render.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/app/desktop.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tray/tray.dart';
import 'package:win32/win32.dart' show SetCursorPos;

/// The real menu beside the clock over a made-up state, for its pictures and for a look after
/// a FlClash update; it never connects. Build it with
/// `flutter build windows -t test/shikoo/tray_harness.dart`, run
/// `ShikooNet.exe <off|connecting|on|signin|noservice> <light|dark> [fa|en]`, right-click. Its
/// window stays hidden and FlClash stops the frames after five seconds, as in the app.
/// A last word `open` opens the menu at 1400,900 after 7 s and quits after 30 s; no clicks.
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadShikooFonts();
  final shown = args.elementAtOrNull(0) ?? 'on';
  final service = !const {'signin', 'noservice'}.contains(shown);
  final connection = service
      ? ShikooConnection.values.byName(shown)
      : ShikooConnection.off;
  final ShikooLook look = (
    theme: ThemeMode.values.byName(args.elementAtOrNull(1) ?? 'light'),
    language: args.elementAtOrNull(2) ?? 'fa',
  );
  final up = DateTime.now().subtract(const Duration(minutes: 12, seconds: 47));
  ShikooState state() => ShikooState(
    connection: connection,
    connectedFor: DateTime.now().difference(up),
    isTV: false,
    service: service
        ? ShikooService(
            name: '5550123 · الماس',
            usedBytes: 33 << 30,
            totalBytes: 100 << 30,
            updatedAt: DateTime.now(),
          )
        : null,
    servers: const [ShikooServer(name: 'آلمان ۲', type: 'Vless', ping: 84)],
    selected: 'آلمان ۲',
  );
  final now = NotifierProvider<ShikooCell<ShikooState>, ShikooState>(
    () => ShikooCell(state()),
  );
  final container = ProviderContainer(
    overrides: [
      shikooStateProvider.overrideWith((ref) => ref.watch(now)),
      shikooLookProvider.overrideWith(() => _Look(look)),
      if (shown == 'noservice')
        shikooAccountProvider.overrideWith(
          () => ShikooCell(
            const ShikooAccount(who: TelegramAccount(name: 'Sam')),
          ),
        ),
      shikooControllerProvider.overrideWithValue(_Inert()),
      systemActionProvider.overrideWith(_Exit.new),
    ],
  );
  Timer.periodic(
    const Duration(seconds: 1),
    (_) => container.read(now.notifier).set(state()),
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(look.language),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(Brightness.light, tv: false),
        builder: (context, child) => ShikooWindow(child: child!),
        home: const SizedBox(),
      ),
    ),
  );
  render?.pause();
  if (args.contains('open')) {
    Timer(const Duration(seconds: 7), () {
      SetCursorPos(1400, 900);
      ServicesBinding.instance.channelBuffers.push(
        'tray',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onMenuRequested'),
        ),
        (_) {},
      );
    });
    Timer(const Duration(seconds: 30), () async {
      await Tray.instance.hide();
      exit(0);
    });
  }
}

class _Look extends ShikooLookNotifier {
  _Look(this.look);

  final ShikooLook look;

  @override
  ShikooLook build() => look;
}

class _Inert implements ShikooController {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _Exit extends SystemAction {
  @override
  Future<void> handleExit([bool needSave = true]) async {
    await Tray.instance.hide();
    exit(0);
  }
}
