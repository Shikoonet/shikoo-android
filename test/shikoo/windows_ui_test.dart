import 'package:fl_clash/shikoo/app/desktop.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/mode.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray/tray.dart';

import '../helpers/no_shots.dart';

final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

ShikooState _state(ShikooConnection connection) => ShikooState(
  connection: connection,
  connectedFor: const Duration(minutes: 12, seconds: 47),
  isTV: false,
  service: ShikooService(
    name: '5550123 · الماس',
    usedBytes: 33 << 30,
    totalBytes: 100 << 30,
    updatedAt: DateTime.now(),
  ),
  servers: const [
    ShikooServer(name: 'آلمان ۲', type: 'Vless', ping: 84),
    ShikooServer(name: 'هلند ۱', type: 'Vless', ping: 96),
  ],
  selected: 'آلمان ۲',
  sorted: true,
);

Future<void> _pumpHome(
  WidgetTester tester,
  Size window, {
  ShikooConnection connection = ShikooConnection.on,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = window
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        noShots,
        shikooStateProvider.overrideWithValue(_state(connection)),
      ],
      child: MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(Brightness.light, tv: false),
        home: const ShikooHome(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('880 wide: the card column at the start, the button beside it', (
    tester,
  ) async {
    await _pumpHome(tester, const Size(880, 508));
    final card = tester.getRect(find.byType(ServiceCard));
    final power = tester.getRect(find.byType(PowerButton));
    expect(card.width, ShikooSizes.desktop.pane);
    expect(card.right, 880 - ShikooSizes.desktop.safeX);
    expect(power.right, lessThan(card.left));
    expect(power.center.dx, closeTo((24 + card.left - 32) / 2, 1));
    expect(
      find.text('همهٔ برنامه‌ها از شیکونت می‌روند، حتی بازی‌ها.'),
      findsOne,
    );
  }, variant: _windows);

  testWidgets('under 620 wide: the phone column, the button over the card', (
    tester,
  ) async {
    await _pumpHome(tester, const Size(600, 508));
    final card = tester.getRect(find.byType(ServiceCard));
    final power = tester.getRect(find.byType(PowerButton));
    expect(card.left, ShikooSizes.desktop.safeX);
    expect(card.right, 600 - ShikooSizes.desktop.safeX);
    expect(power.bottom, lessThan(card.top));
    expect(power.center.dx, 300);
  }, variant: _windows);

  testWidgets('the mode switch: tunnel first, proxy on a tap, still while '
      'connecting', (tester) async {
    await _pumpHome(tester, const Size(880, 508));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShikooHome)),
    );
    expect(container.read(shikooModeProvider), ShikooMode.tunnel);
    await tester.tap(find.text('پروکسی'));
    await tester.pump();
    expect(container.read(shikooModeProvider), ShikooMode.proxy);
    expect(
      find.text('فقط مرورگر و برنامه‌هایی که از پروکسی ویندوز پیروی می‌کنند.'),
      findsOne,
    );

    await _pumpHome(
      tester,
      const Size(880, 508),
      connection: ShikooConnection.connecting,
    );
    final connecting = ProviderScope.containerOf(
      tester.element(find.byType(ShikooHome)),
    );
    await tester.tap(find.text('پروکسی'), warnIfMissed: false);
    await tester.pump();
    expect(connecting.read(shikooModeProvider), ShikooMode.tunnel);
  }, variant: _windows);

  test('the tray menu is frame win-t-c, and the fox is gold only when on', () {
    final l = lookupShikooL10n(const Locale('fa'));
    final picked = <String>[];
    final on = (
      connect: () => picked.add('connect'),
      disconnect: () => picked.add('disconnect'),
      mode: (ShikooMode mode) => picked.add(mode.name),
      open: () => picked.add('open'),
      exit: () => picked.add('exit'),
    );
    List<String> labels(TraySpec spec) => [
      for (final item in spec.menu)
        switch (item) {
          TrayMenuAction(:final label, :final enabled) =>
            enabled ? label : '($label)',
          TrayMenuCheckbox(:final label, :final checked) =>
            checked ? '• $label' : label,
          TrayMenuSeparator() => '-',
          TrayMenuSubmenu(:final label) => label,
        },
    ];
    final connected = shikooTraySpec(
      l,
      connection: ShikooConnection.on,
      server: 'آلمان ۲',
      canConnect: true,
      mode: ShikooMode.tunnel,
      on: on,
    );
    expect(labels(connected), [
      '(وصل · آلمان ۲)',
      '-',
      'قطع کردن',
      '-',
      '• تونل',
      'پروکسی',
      '-',
      'باز کردن شیکونت',
      'خروج',
    ]);
    expect(connected.toolTip, 'شیکونت · وصل، آلمان ۲');
    expect(connected.icon.asset, 'assets/images/tray/windows/status_3.ico');

    final off = shikooTraySpec(
      l,
      connection: ShikooConnection.off,
      server: 'آلمان ۲',
      canConnect: true,
      mode: ShikooMode.proxy,
      on: on,
    );
    expect(labels(off).take(5), ['(قطع)', '-', 'وصل شدن', '-', 'تونل']);
    expect(off.toolTip, 'شیکونت · قطع');
    expect(off.icon.asset, 'assets/images/tray/windows/status_1.ico');

    final connecting = shikooTraySpec(
      l,
      connection: ShikooConnection.connecting,
      server: 'آلمان ۲',
      canConnect: true,
      mode: ShikooMode.tunnel,
      on: on,
    );
    expect(connecting.toolTip, 'شیکونت · در حال اتصال');
    expect(connecting.icon.asset, 'assets/images/tray/windows/status_1.ico');
    expect(
      connecting.menu.whereType<TrayMenuCheckbox>().map((item) => item.enabled),
      everyElement(isFalse),
    );
    final proxy = connected.menu.whereType<TrayMenuCheckbox>().last;
    proxy.onSelected!();
    expect(picked, ['proxy']);
  });

  testWidgets('× closes through Windows, and only the first close says '
      'where the window went', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final calls = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final channel in const ['window_manager', 'tray']) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'getId' => 0,
          'show' => true,
          _ => false,
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(MethodChannel(channel), null),
      );
    }
    final notices = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shikooStateProvider.overrideWithValue(_state(ShikooConnection.on)),
        ],
        child: MaterialApp(
          locale: const Locale('fa'),
          supportedLocales: ShikooL10n.supportedLocales,
          localizationsDelegates: const [
            ShikooL10n.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: shikooThemeData(Brightness.light, tv: false),
          builder: (context, child) => ShikooWindow(
            notify: (title, body) async => notices.add(title),
            child: child!,
          ),
          home: const Scaffold(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, contains('show'));

    await tester.tap(find.byTooltip('بستن'));
    await tester.pump();
    expect(calls, contains('close'));

    Future<void> closed() => messenger.handlePlatformMessage(
      'window_manager',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onEvent', {'eventName': 'close'}),
      ),
      (_) {},
    );
    await closed();
    await tester.pumpAndSettle();
    await closed();
    await tester.pumpAndSettle();
    expect(notices, ['شیکونت کنار ساعت است']);
  }, variant: _windows);
}
