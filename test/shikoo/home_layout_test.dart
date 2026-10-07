import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
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

final _longList = [
  for (var i = 1; i <= 12; i++)
    ShikooServer(name: 'سرور $i', type: 'Vless', ping: 80 + i),
];

ShikooState _tv(
  ShikooConnection connection, {
  List<ShikooServer> servers = _servers,
  String selected = 'فنلاند ۲',
}) => ShikooState(
  connection: connection,
  connectedFor: const Duration(minutes: 12, seconds: 47),
  isTV: true,
  service: const ShikooService(
    name: 'user123 · الماس',
    usedBytes: 33 << 30,
    totalBytes: 100 << 30,
  ),
  servers: servers,
  selected: selected,
  lastError: connection == ShikooConnection.error
      ? ShikooError.connectTimeout
      : null,
);

Future<void> _pumpTvHome(WidgetTester tester, ShikooState state) async {
  await tester.pumpWidget(
    ProviderScope(
      key: ValueKey(state),
      overrides: [shikooStateProvider.overrideWithValue(state)],
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
  await tester.pump();
}

void _tvScreen(WidgetTester tester) {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = const Size(1920, 1080)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

/// What the remote is on: a server name, `power`, or a button label.
String? _focused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  final row = context.findAncestorWidgetOfExactType<ServerRow>();
  if (row != null) return row.server.name;
  if (context.findAncestorWidgetOfExactType<PowerButton>() != null) {
    return 'power';
  }
  return context.findAncestorWidgetOfExactType<ShikooButton>()?.label;
}

Future<String?> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
  return _focused();
}

void main() {
  testWidgets('the TV power button sits at 269dp in every connection state', (
    tester,
  ) async {
    _tvScreen(tester);
    final centres = <ShikooConnection, Offset>{};
    for (final connection in ShikooConnection.values) {
      await _pumpTvHome(tester, _tv(connection));
      centres[connection] = tester.getCenter(find.byType(PowerButton));
    }
    expect(centres.values.toSet(), hasLength(1), reason: '$centres');
    expect(centres.values.first.dy, closeTo(269, 0.5));
  });

  testWidgets('the remote moves between columns as laid out', (tester) async {
    _tvScreen(tester);
    await _pumpTvHome(tester, _tv(ShikooConnection.off));
    expect(_focused(), 'power');
    expect(await _press(tester, LogicalKeyboardKey.arrowDown), 'power');
    expect(await _press(tester, LogicalKeyboardKey.arrowUp), 'تنظیمات');
    expect(await _press(tester, LogicalKeyboardKey.arrowDown), 'power');
    for (final button in ['تمدید', 'پشتیبانی']) {
      expect(await _press(tester, LogicalKeyboardKey.arrowRight), 'فنلاند ۲');
      expect(await _press(tester, LogicalKeyboardKey.arrowDown), 'هلند ۱');
      expect(await _press(tester, LogicalKeyboardKey.arrowUp), 'فنلاند ۲');
      expect(await _press(tester, LogicalKeyboardKey.arrowUp), 'آلمان ۲');
      await _press(tester, LogicalKeyboardKey.arrowUp);
      for (final side in [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowLeft,
      ]) {
        if (_focused() != button) await _press(tester, side);
      }
      expect(_focused(), button);
      expect(await _press(tester, LogicalKeyboardKey.arrowUp), 'تنظیمات');
      expect(await _press(tester, LogicalKeyboardKey.arrowDown), 'power');
    }
  });

  testWidgets('the card column scrolls back up once the remote leaves it', (
    tester,
  ) async {
    _tvScreen(tester);
    await _pumpTvHome(
      tester,
      _tv(ShikooConnection.on, servers: _longList, selected: 'سرور 1'),
    );
    final column = find
        .ancestor(
          of: find.byType(ServiceCard),
          matching: find.byType(Scrollable),
        )
        .first;
    double offset() => tester.state<ScrollableState>(column).position.pixels;

    expect(await _press(tester, LogicalKeyboardKey.arrowRight), 'سرور 1');
    for (var i = 1; i < _longList.length; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focused(), 'سرور 12');
    expect(offset(), greaterThan(0));

    expect(await _press(tester, LogicalKeyboardKey.arrowLeft), 'power');
    expect(offset(), 0);
  });
}
