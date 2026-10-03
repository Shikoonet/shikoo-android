import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _servers = [
  ShikooServer(name: 'آلمان ۲', type: 'Vless', ping: 84),
  ShikooServer(name: 'فنلاند ۲', type: 'Vless', ping: 112),
  ShikooServer(name: 'هلند ۱', type: 'Vless', ping: 96),
  ShikooServer(name: 'آمریکا ۲', type: 'Vless', ping: 188),
];

ShikooState _tv(ShikooConnection connection) => ShikooState(
  connection: connection,
  connectedFor: const Duration(minutes: 12, seconds: 47),
  isTV: true,
  service: const ShikooService(
    name: 'user123 · الماس',
    usedBytes: 33 << 30,
    totalBytes: 100 << 30,
  ),
  servers: _servers,
  selected: 'فنلاند ۲',
  lastError: connection == ShikooConnection.error
      ? ShikooError.connectTimeout
      : null,
);

Future<void> _pumpTvHome(WidgetTester tester, ShikooConnection connection) {
  return tester.pumpWidget(
    ProviderScope(
      key: ValueKey(connection),
      overrides: [shikooStateProvider.overrideWithValue(_tv(connection))],
      child: MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(Brightness.dark, tv: true),
        home: const ShikooHome(),
      ),
    ),
  );
}

void _tvScreen(WidgetTester tester) {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = const Size(1920, 1080)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

String? _focusedServer() {
  final focused = FocusManager.instance.primaryFocus?.context;
  return focused?.findAncestorWidgetOfExactType<ServerRow>()?.server.name;
}

bool _powerFocused() =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<PowerButton>() !=
    null;

void main() {
  testWidgets('the TV power button stays put in every connection state', (
    tester,
  ) async {
    _tvScreen(tester);
    final centres = <ShikooConnection, Offset>{};
    for (final connection in ShikooConnection.values) {
      await _pumpTvHome(tester, connection);
      await tester.pump();
      centres[connection] = tester.getCenter(find.byType(PowerButton));
    }
    expect(centres.values.toSet(), hasLength(1), reason: '$centres');
  });

  testWidgets('the remote leaves the power button only towards a target', (
    tester,
  ) async {
    _tvScreen(tester);
    await _pumpTvHome(tester, ShikooConnection.off);
    await tester.pump();
    expect(_powerFocused(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_powerFocused(), isTrue, reason: 'nothing is below the button');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_focusedServer(), 'فنلاند ۲');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_focusedServer(), 'هلند ۱');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(_powerFocused(), isTrue);
  });
}
