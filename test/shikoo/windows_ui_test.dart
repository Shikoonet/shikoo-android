import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/app/desktop.dart';
import 'package:fl_clash/shikoo/app/tray_popup.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/mode.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray/tray.dart';
import 'package:win32/win32.dart';

import '../helpers/no_shots.dart';

final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

class _Controller extends Mock implements ShikooController {}

class _Exits extends SystemAction {
  static int count = 0;

  @override
  Future<void> handleExit([bool needSave = true]) async => count++;
}

/// Keeps what Windows would be shown, and no window.
class _Popup extends TrayPopup {
  TrayView? view;
  VoidCallback? onShow;

  @override
  bool get isOpen => view != null;

  @override
  Future<void> show(TrayView view) async {
    this.view = view;
    onShow?.call();
  }

  @override
  void update(TrayView view) {
    if (isOpen) this.view = view;
  }

  @override
  void close() {
    if (!isOpen) return;
    view = null;
    onClose?.call();
  }
}

ShikooState _state(
  ShikooConnection connection, {
  int more = 0,
  Duration connectedFor = const Duration(minutes: 12, seconds: 47),
  bool service = true,
  bool ended = false,
}) => ShikooState(
  connection: connection,
  connectedFor: connectedFor,
  isTV: false,
  service: service
      ? ShikooService(
          name: '5550123 · الماس',
          usedBytes: (ended ? 100 : 33) << 30,
          totalBytes: 100 << 30,
          updatedAt: DateTime.now(),
        )
      : null,
  servers: [
    const ShikooServer(name: 'آلمان ۲', type: 'Vless', ping: 84),
    const ShikooServer(name: 'هلند ۱', type: 'Vless', ping: 96),
    for (var i = 1; i <= more; i++)
      ShikooServer(name: 'سرور $i', type: 'Vless', ping: 100 + i),
  ],
  selected: 'آلمان ۲',
  sorted: true,
);

Future<void> _pumpHome(
  WidgetTester tester,
  Size window, {
  ShikooConnection connection = ShikooConnection.on,
  int more = 0,
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
        shikooStateProvider.overrideWithValue(_state(connection, more: more)),
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

  group('the menu beside the clock', () {
    final l = lookupShikooL10n(const Locale('fa'));
    final picked = <String>[];
    final TrayActions on = (
      connect: () => picked.add('connect'),
      disconnect: () => picked.add('disconnect'),
      mode: (ShikooMode mode) => picked.add(mode.name),
      open: () => picked.add('open'),
      exit: () => picked.add('exit'),
    );
    TrayMenu menu(
      ShikooConnection connection, {
      ShikooMode mode = ShikooMode.tunnel,
      bool canConnect = true,
      bool hasService = true,
      bool signedIn = true,
    }) => shikooTrayMenu(
      l,
      connection: connection,
      server: 'آلمان ۲',
      connectedFor: const Duration(minutes: 12, seconds: 47),
      canConnect: canConnect,
      hasService: hasService,
      signedIn: signedIn,
      mode: mode,
      on: on,
    );
    List<String> labels(TrayMenu menu) => [
      for (final row in menu.rows)
        row == null
            ? '-'
            : [
                if (row.icon == ShikooIcon.power) 'power',
                if (row.dot) '•',
                row.enabled ? row.label : '(${row.label})',
              ].join(' '),
    ];

    test('is frame win-t-c, and the fox is gold only when on', () {
      final connected = menu(ShikooConnection.on);
      expect(connected.head, 'وصل · آلمان ۲');
      expect(connected.on, isTrue);
      expect(connected.time, '۰۰:۱۲:۴۷');
      expect(labels(connected), [
        'power قطع کردن',
        '-',
        '• تونل',
        'پروکسی',
        '-',
        'باز کردن شیکونت',
        'خروج',
      ]);

      expect(connected.muted, isFalse);
      final off = menu(ShikooConnection.off, mode: ShikooMode.proxy);
      expect(
        (off.head, off.on, off.muted, off.time),
        ('قطع', false, false, null),
      );
      expect(labels(off).take(4), ['power وصل شدن', '-', 'تونل', '• پروکسی']);
      final resting = menu(ShikooConnection.off, canConnect: false);
      expect(labels(resting).first, 'power (وصل شدن)');
      expect(
        (resting.head, resting.muted),
        ('قطع', false),
        reason: 'a service that is resting still is one',
      );

      final connecting = menu(ShikooConnection.connecting);
      expect(
        (connecting.head, connecting.on, connecting.time),
        ('در حال اتصال · آلمان ۲', false, null),
      );
      expect(labels(connecting).take(4), [
        'power قطع کردن',
        '-',
        '• (تونل)',
        '(پروکسی)',
      ]);

      TrayMenu bare({required bool signedIn}) => menu(
        ShikooConnection.off,
        canConnect: false,
        hasService: false,
        signedIn: signedIn,
      );
      final out = bare(signedIn: false);
      expect((out.head, out.on, out.muted), ('اول وارد شو', false, true));
      expect(labels(out), [
        'power (وصل شدن)',
        '-',
        '• تونل',
        'پروکسی',
        '-',
        'باز کردن شیکونت',
        'خروج',
      ]);
      final empty = bare(signedIn: true);
      expect((empty.head, empty.muted), ('سرویسی نداری', true));
      final en = shikooTrayMenu(
        lookupShikooL10n(const Locale('en')),
        connection: ShikooConnection.off,
        server: null,
        connectedFor: Duration.zero,
        canConnect: false,
        hasService: false,
        signedIn: false,
        mode: ShikooMode.tunnel,
        on: on,
      );
      expect(en.head, 'Sign in first');

      TraySpec spec(ShikooConnection connection, ShikooMode mode) =>
          shikooTraySpec(
            l,
            connection: connection,
            server: 'آلمان ۲',
            mode: mode,
          );
      final tunnel = spec(ShikooConnection.on, ShikooMode.tunnel);
      expect(tunnel.toolTip, 'شیکونت · وصل، آلمان ۲');
      expect(tunnel.icon.asset, 'assets/images/tray/windows/status_3.ico');
      expect(tunnel.menu, isEmpty);
      expect(
        spec(ShikooConnection.on, ShikooMode.proxy).icon.asset,
        'assets/images/tray/windows/status_2.ico',
      );
      final idle = spec(ShikooConnection.off, ShikooMode.tunnel);
      expect(idle.toolTip, 'شیکونت · قطع');
      expect(idle.icon.asset, 'assets/images/tray/windows/status_1.ico');
      final waiting = spec(ShikooConnection.connecting, ShikooMode.tunnel);
      expect(waiting.toolTip, 'شیکونت · در حال اتصال');
      expect(waiting.icon.asset, 'assets/images/tray/windows/status_1.ico');
    });

    test('the clock runs past an hour', () {
      expect(
        clockOf('en', const Duration(minutes: 61, seconds: 1)),
        '01:01:01',
      );
      expect(
        clockOf('fa', const Duration(hours: 25, minutes: 5, seconds: 9)),
        '۲۵:۰۵:۰۹',
      );
    });

    testWidgets('greys what cannot be used, and the reason on top', (
      tester,
    ) async {
      Future<void> draw(TrayMenu menu) => tester.pumpWidget(
        MaterialApp(
          theme: shikooThemeData(Brightness.light, tv: false),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Align(
              alignment: Alignment.topLeft,
              child: TrayMenuView(menu),
            ),
          ),
        ),
      );
      const c = ShikooColors.light;
      Color? ink(String data) =>
          tester.widget<Text>(find.text(data)).style?.color;
      Color? mark(String label) {
        final row = find.ancestor(
          of: find.text(label),
          matching: find.byType(MetaData),
        );
        final dot = find.descendant(
          of: row,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                (w.decoration as BoxDecoration?)?.shape == BoxShape.circle,
          ),
        );
        if (dot.evaluate().isNotEmpty) {
          return (tester.widget<Container>(dot).decoration as BoxDecoration)
              .color;
        }
        final glyph = tester.widget<CustomPaint>(
          find.descendant(of: row, matching: find.byType(CustomPaint)).first,
        );
        return (glyph.painter as dynamic).color as Color;
      }

      await draw(
        menu(
          ShikooConnection.off,
          canConnect: false,
          hasService: false,
          signedIn: false,
        ),
      );
      expect(ink('اول وارد شو'), c.textMuted);
      expect(ink('وصل شدن'), c.textMuted);
      expect(mark('وصل شدن'), c.iconDisabled);
      expect(ink('تونل'), c.text);
      expect(mark('تونل'), c.text);

      await draw(menu(ShikooConnection.connecting));
      expect(ink('در حال اتصال · آلمان ۲'), c.text);
      expect(ink('تونل'), c.textMuted);
      expect(mark('تونل'), c.iconDisabled);
      expect(mark('قطع کردن'), c.text);
    });

    test('every row does what it says', () {
      List<String> run(TrayMenu menu) {
        picked.clear();
        for (final row in menu.rows.nonNulls) {
          row.run();
        }
        return [...picked];
      }

      const rest = ['tunnel', 'proxy', 'open', 'exit'];
      expect(run(menu(ShikooConnection.off)), ['connect', ...rest]);
      expect(run(menu(ShikooConnection.on)), ['disconnect', ...rest]);
      expect(run(menu(ShikooConnection.connecting)), ['disconnect', ...rest]);
    });

    test('Esc, a click off the card and another window close it; keys and '
        'the pointer pick a row', () {
      final rows = menu(ShikooConnection.connecting).rows;
      // 0 disconnect, 1 rule, 2 tunnel and 3 proxy (both off while connecting), 4 rule,
      // 5 open, 6 exit.
      TrayStep key(int vk, [int? selected]) =>
          trayStep(rows, selected, WM_KEYDOWN, vk);
      TrayStep click(int? at) => trayStep(rows, 5, WM_LBUTTONUP, 0, at: at);

      expect(key(VK_ESCAPE, 5).close, isTrue);
      expect(key(VK_ESCAPE, 5).chosen, isNull);
      expect(trayStep(rows, 5, WM_ACTIVATE, 0).close, isTrue);
      expect(trayStep(rows, 5, WM_ACTIVATE, 1).close, isFalse);
      expect(
        trayStep(rows, 5, WM_ACTIVATE, 0x10000).close,
        isTrue,
        reason: 'the high word only says whether the window is minimised',
      );
      expect(trayStep(rows, 5, WM_ACTIVATE, 0x10001).close, isFalse);
      expect(click(-1).close, isTrue);
      expect(click(-1).chosen, isNull);

      expect(key(VK_DOWN).selected, 0);
      expect(key(VK_DOWN, 0).selected, 5);
      expect(key(VK_DOWN, 6).selected, 0);
      expect(key(VK_UP).selected, 6);
      expect(key(VK_UP, 0).selected, 6);
      expect(key(VK_END, 0).selected, 6);
      expect(key(VK_HOME, 6).selected, 0);
      expect(key(VK_RIGHT, 5).selected, 5);

      final enter = key(VK_RETURN, 6);
      expect((enter.close, enter.chosen?.label), (true, 'خروج'));
      expect(key(VK_SPACE, 0).chosen?.label, 'قطع کردن');
      expect(key(VK_RETURN).close, isFalse);

      final clicked = click(0);
      expect((clicked.close, clicked.chosen?.label), (true, 'قطع کردن'));
      expect(click(2).close, isFalse, reason: 'tunnel is off while connecting');
      expect(click(null).close, isFalse, reason: 'the status line');
      expect(
        trayStep(rows, null, WM_RBUTTONUP, 0, at: 6).chosen?.label,
        'خروج',
      );

      TrayStep move(int? at, {bool pointed = true, bool moved = true}) =>
          trayStep(
            rows,
            5,
            WM_MOUSEMOVE,
            0,
            at: at,
            pointed: pointed,
            moved: moved,
          );
      final hover = trayStep(rows, null, WM_MOUSEMOVE, 0, at: 6);
      expect((hover.selected, hover.pointed), (6, true));
      expect(move(3).selected, isNull, reason: 'tunnel is off');
      expect(move(null).selected, isNull, reason: 'the status line');
      expect(move(-1).selected, isNull, reason: 'onto the shadow');
      expect(trayStep(rows, 5, wmMouseLeave, 0, pointed: true).selected, null);
      for (final vk in [VK_DOWN, VK_UP, VK_HOME, VK_END]) {
        expect(
          trayStep(rows, 0, WM_KEYDOWN, vk, pointed: true).pointed,
          isFalse,
          reason: 'a key, not the pointer, chose the row',
        );
      }

      // A row the keys chose stays under a pointer that has not left the icon.
      expect(move(-1, pointed: false).selected, 5);
      expect(move(null, pointed: false).selected, 5);
      expect(trayStep(rows, 5, wmMouseLeave, 0).selected, 5);
      expect(move(6, pointed: false, moved: false).selected, 5);
      expect(move(6, pointed: false).selected, 6);
      final still = move(6, moved: false);
      expect((still.selected, still.pointed), (5, true));
    });

    test('opens at the pointer, clear of the taskbar on every edge', () {
      const card = Size(310, 300);
      Offset at(Offset pointer, Rect work, {bool rtl = true}) =>
          trayCardAt(pointer, card, work, rtl: rtl, gap: 10);

      const bottom = Rect.fromLTRB(0, 0, 1920, 1140);
      expect(at(const Offset(1800, 1170), bottom), const Offset(1490, 830));
      expect(
        at(const Offset(100, 1170), bottom, rtl: false),
        const Offset(100, 830),
      );
      expect(at(const Offset(100, 1170), bottom), const Offset(10, 830));
      expect(at(const Offset(1404, 992), bottom), const Offset(1094, 692));

      const top = Rect.fromLTRB(0, 60, 1920, 1200);
      expect(at(const Offset(1800, 30), top), const Offset(1490, 70));
      const right = Rect.fromLTRB(0, 0, 1860, 1200);
      expect(at(const Offset(1890, 1100), right), const Offset(1540, 800));
      const left = Rect.fromLTRB(60, 0, 1920, 1200);
      expect(at(const Offset(30, 1100), left), const Offset(70, 800));
    });

    testWidgets('is drawn right to left, as frame win-t-c', (tester) async {
      final selected = menu(
        ShikooConnection.on,
      ).rows.indexWhere((row) => row?.label == 'باز کردن شیکونت');
      await tester.pumpWidget(
        MaterialApp(
          theme: shikooThemeData(Brightness.dark, tv: false),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Align(
              alignment: Alignment.topLeft,
              child: TrayMenuView(
                menu(ShikooConnection.on),
                selected: selected,
              ),
            ),
          ),
        ),
      );
      const c = ShikooColors.dark;
      Text text(String data) => tester.widget<Text>(find.text(data));
      expect(text('وصل · آلمان ۲').style?.color, c.positive);
      expect(text('وصل · آلمان ۲').style?.fontWeight, FontWeight.w700);
      expect(text('۰۰:۱۲:۴۷').style?.color, c.textMuted);
      expect(text('قطع کردن').style?.color, c.text);
      expect(
        text('۰۰:۱۲:۴۷').style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(
        tester.getSize(find.byType(TrayMenuView)).width,
        ShikooSizes.trayMenu,
      );

      final rules = find.byWidgetPredicate(
        (w) => w is Container && w.color == c.border,
      );
      expect(rules, findsNWidgets(3));
      expect(
        tester.getRect(rules.first).top,
        greaterThan(tester.getRect(find.text('۰۰:۱۲:۴۷')).bottom),
      );
      expect(
        tester.getRect(rules.first).bottom,
        lessThan(tester.getRect(find.text('قطع کردن')).top),
      );

      final card = tester.getRect(find.byType(TrayMenuView));
      for (final label in ['وصل · آلمان ۲', 'قطع کردن', 'تونل', 'خروج']) {
        expect(
          card.right - tester.getRect(find.text(label)).right,
          lessThan(card.width / 2 - 40),
          reason: '$label sits at the right',
        );
      }

      Finder rowOf(String label) =>
          find.ancestor(of: find.text(label), matching: find.byType(MetaData));
      Color? fill(String label) =>
          ((tester
                      .widget<Container>(
                        find
                            .descendant(
                              of: rowOf(label),
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration?)
              ?.color);
      expect(fill('باز کردن شیکونت'), c.selectedBg);
      expect(fill('خروج'), isNull);

      Finder dotIn(String label) => find.descendant(
        of: rowOf(label),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              (w.decoration as BoxDecoration?)?.shape == BoxShape.circle,
        ),
      );
      expect(dotIn('تونل'), findsOneWidget);
      expect(dotIn('پروکسی'), findsNothing);
      final dot = tester.getRect(dotIn('تونل'));
      expect(dot.size, const Size.square(ShikooSizes.trayDot));
      expect(
        dot.left,
        greaterThan(tester.getRect(find.text('تونل')).right),
        reason: 'the dot is at the start, on the right',
      );
    });

    testWidgets('follows the state with the window hidden and no frame '
        'drawn, its rows reach the controller, and exit says nothing', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      Tray.instance.resetForTesting();
      final tips = <String>[];
      final icons = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      for (final channel in const ['window_manager', 'tray']) {
        messenger.setMockMethodCallHandler(MethodChannel(channel), (
          call,
        ) async {
          if (channel == 'tray' && call.method == 'show') {
            final shown = call.arguments as Map;
            tips.add(shown['toolTip'] as String);
            icons.add((shown['icon'] as Map)['path'] as String);
          }
          return switch (call.method) {
            'getId' => 0,
            'show' => true,
            _ => false,
          };
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(MethodChannel(channel), null),
        );
      }
      final controller = _Controller();
      when(controller.connect).thenAnswer((_) async {});
      when(controller.disconnect).thenAnswer((_) async {});
      _Exits.count = 0;
      final now = NotifierProvider<ShikooCell<ShikooState>, ShikooState>(
        () => ShikooCell(_state(ShikooConnection.off)),
      );
      final container = ProviderContainer(
        overrides: [
          shikooStateProvider.overrideWith((ref) => ref.watch(now)),
          shikooControllerProvider.overrideWithValue(controller),
          systemActionProvider.overrideWith(_Exits.new),
        ],
      );
      addTearDown(container.dispose);
      String? tipAtOpen;
      final popup = _Popup()..onShow = () => tipAtOpen = tips.last;
      final notices = <String>[];
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('fa'),
            supportedLocales: ShikooL10n.supportedLocales,
            localizationsDelegates: const [
              ShikooL10n.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            theme: shikooThemeData(Brightness.light, tv: false),
            builder: (context, child) => ShikooWindow(
              popup: popup,
              notify: (title, body) async => notices.add(title),
              child: child!,
            ),
            home: const Scaffold(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tips.last, 'شیکونت · قطع');

      Future<void> fromWindows(String channel, String method) =>
          messenger.handlePlatformMessage(
            channel,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, {'eventName': 'close'}),
            ),
            (_) {},
          );
      // Only timers run from here on, as when FlClash has stopped the frames.
      container.read(now.notifier).set(_state(ShikooConnection.on));
      await tester.idle();
      expect(tips.last, 'شیکونت · وصل، آلمان ۲');
      expect(icons.last, endsWith('status_3.ico'));

      await fromWindows('tray', 'onMenuRequested');
      await tester.idle();
      expect(popup.view?.menu.head, 'وصل · آلمان ۲');
      expect(popup.view?.menu.time, '۰۰:۱۲:۴۷');
      expect(popup.view?.direction, TextDirection.rtl);
      expect(popup.view?.brightness, Brightness.light);
      expect(tips.last, isEmpty, reason: "Windows' tip would cover the menu");
      expect(tipAtOpen, isEmpty, reason: 'gone before the menu shows');
      container
          .read(now.notifier)
          .set(
            _state(
              ShikooConnection.on,
              connectedFor: const Duration(minutes: 13),
            ),
          );
      await tester.idle();
      expect(popup.view?.menu.time, '۰۰:۱۳:۰۰');

      TrayRow row(String label) =>
          popup.view!.menu.rows.firstWhere((row) => row?.label == label)!;
      row('قطع کردن').run();
      verify(controller.disconnect).called(1);
      verifyNever(controller.connect);
      row('پروکسی').run();
      await tester.idle();
      expect(container.read(shikooModeProvider), ShikooMode.proxy);
      expect(popup.view?.menu.rows.map((row) => row?.dot), [
        false,
        null,
        false,
        true,
        null,
        false,
        false,
      ]);
      container.read(now.notifier).set(_state(ShikooConnection.off));
      await tester.idle();
      expect(popup.view?.menu.head, 'قطع');
      row('وصل شدن').run();
      verify(controller.connect).called(1);
      container
          .read(now.notifier)
          .set(_state(ShikooConnection.off, ended: true));
      await tester.idle();
      expect(row('وصل شدن').enabled, isFalse, reason: 'the service ran out');
      popup.close();
      await tester.idle();
      expect(tips.last, 'شیکونت · قطع');
      expect(icons.last, endsWith('status_1.ico'));

      final look = container.read(shikooLookProvider.notifier);
      await look.setLanguage('en');
      await tester.idle();
      expect(tips.last, 'ShikooNet · Off');
      await look.setLanguage('fa');
      await tester.idle();
      expect(tips.last, 'شیکونت · قطع');

      await fromWindows('tray', 'onMenuRequested');
      await tester.idle();
      await look.setTheme(ThemeMode.dark);
      await tester.idle();
      expect(popup.view?.brightness, Brightness.dark);
      await look.setTheme(ThemeMode.light);
      await tester.idle();
      expect(popup.view?.brightness, Brightness.light);
      container
          .read(now.notifier)
          .set(_state(ShikooConnection.off, service: false));
      await tester.idle();
      expect(popup.view?.menu.head, 'اول وارد شو');
      container
          .read(shikooAccountProvider.notifier)
          .set(const ShikooAccount(who: TelegramAccount(name: 'Sam')));
      await tester.idle();
      expect(popup.view?.menu.head, 'سرویسی نداری');

      row('خروج').run();
      expect(_Exits.count, 1);
      await fromWindows('window_manager', 'onEvent');
      await tester.pumpAndSettle();
      expect(notices, isEmpty);

      await tester.pumpWidget(const SizedBox());
      expect(popup.isOpen, isFalse, reason: 'the menu goes with the window');
    }, variant: _windows);
  });

  testWidgets('× closes through Windows, and only the first close says '
      'where the window went', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Tray.instance.resetForTesting();
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
