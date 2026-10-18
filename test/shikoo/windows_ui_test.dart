import 'package:fl_clash/shikoo/app/desktop.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/login.dart';
import 'package:fl_clash/shikoo/ui/mode.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray/tray.dart';

import '../helpers/no_shots.dart';

final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

ShikooState _state(
  ShikooConnection connection, {
  int more = 0,
  ShikooError? error,
}) => ShikooState(
  connection: connection,
  lastError: error,
  connectedFor: const Duration(minutes: 12, seconds: 47),
  isTV: false,
  service: ShikooService(
    name: '5550123 · الماس',
    usedBytes: 33 << 30,
    totalBytes: 100 << 30,
    updatedAt: DateTime.now(),
  ),
  servers: [
    const ShikooServer(name: 'آلمان ۲', type: 'Vless', ping: 84),
    const ShikooServer(name: 'هلند ۱', type: 'Vless', ping: 96),
    for (var i = 1; i <= more; i++)
      ShikooServer(name: 'سرور $i', type: 'Vless', ping: 100 + i),
  ],
  selected: 'آلمان ۲',
  sorted: true,
);

final _stateCell = NotifierProvider<ShikooCell<ShikooState>, ShikooState>(
  () => ShikooCell(_state(ShikooConnection.off)),
);

Widget _app(Widget home, {List<Override> overrides = const []}) =>
    ProviderScope(
      key: UniqueKey(),
      overrides: [noShots, ...overrides],
      child: MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(Brightness.light, tv: false),
        home: home,
      ),
    );

void _window(WidgetTester tester, Size window) {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = window
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpHome(
  WidgetTester tester,
  Size window, {
  ShikooConnection connection = ShikooConnection.on,
  int more = 0,
  ShikooError? error,
}) async {
  _window(tester, window);
  await tester.pumpWidget(
    _app(
      const ShikooHome(),
      overrides: [
        shikooStateProvider.overrideWithValue(
          _state(connection, more: more, error: error),
        ),
      ],
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

  testWidgets('Tab in the wide window stops once at everything, the top bar '
      'too, though the card scrolls under it', (tester) async {
    await _pumpHome(tester, const Size(880, 508), more: 4);
    String stop() {
      final context = FocusManager.instance.primaryFocus!.context!;
      if (context.findAncestorWidgetOfExactType<PowerButton>() != null) {
        return 'power';
      }
      final button = context.findAncestorWidgetOfExactType<ShikooIconButton>();
      final box = context.findRenderObject()! as RenderBox;
      return button?.label ?? '${box.localToGlobal(Offset.zero).dx.round()}';
    }

    final stops = <String>[];
    for (var i = 0; i < 40; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      stops.add(stop());
    }
    final lap = stops.sublist(0, stops.indexOf(stops.first, 1));
    expect(lap.where((s) => s == 'تنظیمات'), hasLength(1));
    expect(lap.where((s) => s == 'power'), hasLength(1));
    expect(stops.sublist(lap.length, 2 * lap.length), lap);
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

  group('with the real font', () {
    setUpAll(loadShikooFonts);
    final l = lookupShikooL10n(const Locale('fa'));

    testWidgets('other pages keep to a centred column in a wide window, and '
        'fill a narrow one', (tester) async {
      Future<Rect> box(Size window, Widget page) async {
        _window(tester, window);
        await tester.pumpWidget(_app(page));
        await tester.pump();
        return tester.getRect(find.byKey(const ValueKey('box')));
      }

      const content = SizedBox(key: ValueKey('box'), height: 40);
      const pane = 400.0;
      final scrolled = await box(
        const Size(880, 508),
        const SubPage(title: 'تنظیمات', isTV: false, child: content),
      );
      expect(scrolled.width, pane);
      expect(scrolled.center.dx, 440);
      final own = await box(
        const Size(880, 508),
        const SubPage(
          title: 'گزارش',
          isTV: false,
          scrolls: false,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [content],
            ),
          ),
        ),
      );
      expect(own.width, pane);
      expect(own.center.dx, 440);
      final login = await box(
        const Size(880, 508),
        const FillPage(
          padding: EdgeInsets.symmetric(horizontal: 24),
          top: SizedBox.shrink(),
          middle: SizedBox.shrink(),
          bottom: [content],
        ),
      );
      expect(login.width, pane);
      expect(login.center.dx, 440);
      final narrow = await box(
        const Size(400, 448),
        const SubPage(title: 'تنظیمات', isTV: false, child: content),
      );
      expect(narrow.width, 400 - 2 * 24);
    }, variant: _windows);

    testWidgets('the first screen: Telegram button as wide as the column', (
      tester,
    ) async {
      _window(tester, const Size(880, 508));
      await tester.pumpWidget(
        _app(
          const LoginPage(login: null),
          overrides: [
            shikooStateProvider.overrideWithValue(_state(ShikooConnection.off)),
          ],
        ),
      );
      await tester.pump();
      final button = tester.getRect(
        find.ancestor(
          of: find.text(l.loginTelegram),
          matching: find.byType(ShikooButton),
        ),
      );
      expect(button.width, 400);
      expect(button.center.dx, 440);
    }, variant: _windows);

    testWidgets('the mode hint keeps two lines, so the button column does not '
        'jump as the mode changes', (tester) async {
      // Windows' text size at 110%: the proxy hint wraps, the tunnel one does not.
      tester.platformDispatcher.textScaleFactorTestValue = 1.1;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpHome(tester, const Size(880, 508));
      final line = 1.1 * ShikooSizes.desktop.bodySm * Leading.tight;
      double lines(String hint) {
        final text = tester.renderObject<RenderBox>(find.text(hint));
        return text.getMinIntrinsicHeight(text.size.width) / line;
      }

      expect(lines(l.modeTunnelHint), closeTo(1, 0.1));
      final power = tester.getRect(find.byType(PowerButton));
      final tunnel = tester.getRect(find.byType(ModeSwitch));
      await tester.tap(find.text(l.modeProxy));
      await tester.pump();
      expect(lines(l.modeProxyHint), closeTo(2, 0.1));
      final proxy = tester.getRect(find.byType(ModeSwitch));
      expect((proxy.top, proxy.bottom), (tunnel.top, tunnel.bottom));
      expect(tester.getRect(find.byType(PowerButton)), power);
    }, variant: _windows);

    testWidgets('in the smallest window a message under the mode switch '
        'scrolls into view, new or there from the start', (tester) async {
      _window(tester, const Size(400, 448));
      Rect message() => tester.getRect(find.text(l.vpnRefusedDesktop));
      await tester.pumpWidget(
        _app(
          const ShikooHome(),
          overrides: [
            shikooStateProvider.overrideWith((ref) => ref.watch(_stateCell)),
          ],
        ),
      );
      await tester.pump();
      ProviderScope.containerOf(tester.element(find.byType(ShikooHome)))
          .read(_stateCell.notifier)
          .set(_state(ShikooConnection.error, error: ShikooError.vpnRefused));
      await tester.pump();
      await tester.pump();
      expect(message().top, greaterThanOrEqualTo(0));
      expect(message().bottom, lessThanOrEqualTo(448));

      await _pumpHome(
        tester,
        const Size(400, 448),
        connection: ShikooConnection.error,
        error: ShikooError.vpnRefused,
      );
      await tester.pump();
      expect(message().bottom, lessThanOrEqualTo(448));
    }, variant: _windows);

    testWidgets('a mouse over a button lights it from behind, and leaving '
        'clears it', (tester) async {
      _window(tester, const Size(400, 448));
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Center(
              child: ShikooButton(label: 'پشتیبانی', onPressed: () {}),
            ),
          ),
        ),
      );
      final lit = find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is ShapeDecoration &&
            (widget.decoration as ShapeDecoration).color ==
                ShikooColors.light.selectedBg,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 440));
      addTearDown(mouse.removePointer);
      await tester.pump();
      expect(lit, findsNothing);
      await mouse.moveTo(tester.getCenter(find.text('پشتیبانی')));
      await tester.pump();
      expect(lit, findsOne);
      expect(
        tester.getRect(lit),
        tester.getRect(
          find
              .ancestor(
                of: find.text('پشتیبانی'),
                matching: find.byType(Pressable),
              )
              .first,
        ),
      );
      await mouse.moveTo(const Offset(1, 440));
      await tester.pump();
      expect(lit, findsNothing);
    }, variant: _windows);
  });
}
