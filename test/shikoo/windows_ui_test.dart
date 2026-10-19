import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/app/desktop.dart';
import 'package:fl_clash/shikoo/app/tray_popup.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/login.dart';
import 'package:fl_clash/shikoo/ui/mode.dart';
import 'package:fl_clash/shikoo/ui/paste.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart'
    show RenderParagraph, RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray/tray.dart';
import 'package:win32/win32.dart';

import '../helpers/no_shots.dart';

final _windows = TargetPlatformVariant.only(TargetPlatform.windows);
const _computerAndPhone = TargetPlatformVariant({
  TargetPlatform.windows,
  TargetPlatform.android,
});

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

class _Mode extends ShikooModeNotifier {
  _Mode(this.mode);

  final ShikooMode mode;

  @override
  ShikooMode build() => mode;
}

ShikooState _state(
  ShikooConnection connection, {
  int more = 0,
  Duration connectedFor = const Duration(minutes: 12, seconds: 47),
  bool service = true,
  bool ended = false,
  ShikooError? error,
  int? busyPort,
  bool helperFailed = false,
  ShikooNotice? notice,
  String? server,
}) => ShikooState(
  connection: connection,
  lastError: error,
  notice: notice,
  busyPort: busyPort,
  helperFailed: helperFailed,
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
    if (server != null) ShikooServer(name: server, type: 'Vless', ping: 84),
    const ShikooServer(name: 'آلمان ۲', type: 'Vless', ping: 84),
    const ShikooServer(name: 'هلند ۱', type: 'Vless', ping: 96),
    for (var i = 1; i <= more; i++)
      ShikooServer(name: 'سرور $i', type: 'Vless', ping: 100 + i),
  ],
  selected: server ?? 'آلمان ۲',
  sorted: true,
);

final _stateCell = NotifierProvider<ShikooCell<ShikooState>, ShikooState>(
  () => ShikooCell(_state(ShikooConnection.off)),
);

Widget _app(
  Widget home, {
  List<Override> overrides = const [],
  Locale locale = const Locale('fa'),
  Brightness brightness = Brightness.light,
}) => ProviderScope(
  key: UniqueKey(),
  overrides: [noShots, ...overrides],
  child: MaterialApp(
    locale: locale,
    supportedLocales: ShikooL10n.supportedLocales,
    localizationsDelegates: const [
      ShikooL10n.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    theme: shikooThemeData(brightness, tv: false),
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
  int? busyPort,
  bool helperFailed = false,
  ShikooNotice? notice,
  Locale locale = const Locale('fa'),
  List<Override> overrides = const [],
}) async {
  _window(tester, window);
  await tester.pumpWidget(
    _app(
      const ShikooHome(),
      locale: locale,
      overrides: [
        shikooStateProvider.overrideWithValue(
          _state(
            connection,
            more: more,
            error: error,
            busyPort: busyPort,
            helperFailed: helperFailed,
            notice: notice,
          ),
        ),
        ...overrides,
      ],
    ),
  );
  await tester.pump();
}

/// The colour at [at], as painted inside [boundary].
Future<Color> _pixel(WidgetTester tester, Finder boundary, Offset at) async {
  final render = tester.renderObject<RenderRepaintBoundary>(boundary);
  final p = at - render.localToGlobal(Offset.zero);
  final pixel = await tester.runAsync(() async {
    final image = await render.toImage();
    final data = (await image.toByteData())!;
    final i = 4 * (p.dy.floor() * image.width + p.dx.floor());
    image.dispose();
    return [for (var k = 0; k < 4; k++) data.getUint8(i + k)];
  });
  return Color.fromARGB(pixel![3], pixel[0], pixel[1], pixel[2]);
}

Matcher _looks(Color color) => isA<Color>().having(
  (c) => [
    for (final v in [c.r, c.g, c.b]) (v * 255).round(),
  ],
  'rgb',
  [
    for (final v in [color.r, color.g, color.b]) closeTo((v * 255).round(), 1),
  ],
);

Finder _lit(Color color) => find.byWidgetPredicate(
  (widget) =>
      widget is DecoratedBox &&
      widget.decoration is ShapeDecoration &&
      (widget.decoration as ShapeDecoration).color == color,
);

final _ring = find.byWidgetPredicate(
  (widget) =>
      widget is DecoratedBox &&
      widget.decoration is ShapeDecoration &&
      (widget.decoration as ShapeDecoration).shape is OutlinedBorder &&
      ((widget.decoration as ShapeDecoration).shape as OutlinedBorder)
              .side
              .color ==
          ShikooColors.light.focusRing,
);

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

  testWidgets('the mode switch shows the engine\'s mode, asks the engine for '
      'another on a tap, and asks nothing while connecting', (tester) async {
    registerFallbackValue(ShikooMode.tunnel);
    final controller = _Controller();
    when(() => controller.setMode(any())).thenAnswer((_) async {});
    final engine = [shikooControllerProvider.overrideWithValue(controller)];
    final l = lookupShikooL10n(const Locale('fa'));
    await _pumpHome(tester, const Size(880, 508), overrides: engine);
    expect(find.text(l.modeTunnelHint), findsOne);
    await tester.tap(find.text(l.modeProxy));
    await tester.pump();
    verify(() => controller.setMode(ShikooMode.proxy)).called(1);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShikooHome)),
    );
    await container.read(shikooModeProvider.notifier).save(ShikooMode.proxy);
    await tester.pump();
    expect(find.text(l.modeProxyHint), findsOne);

    await _pumpHome(
      tester,
      const Size(880, 508),
      connection: ShikooConnection.connecting,
      overrides: engine,
    );
    await tester.tap(find.text(l.modeProxy), warnIfMissed: false);
    await tester.pump();
    verifyNever(() => controller.setMode(any()));
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
      registerFallbackValue(ShikooMode.tunnel);
      when(() => controller.setMode(any())).thenAnswer(
        (call) => container
            .read(shikooModeProvider.notifier)
            .save(call.positionalArguments.single as ShikooMode),
      );
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
      verify(() => controller.setMode(ShikooMode.proxy)).called(1);
      expect(container.read(shikooModeProvider), ShikooMode.proxy);
      expect(icons.last, endsWith('status_2.ico'), reason: 'the proxy fox');
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
      expect(row('وصل شدن').enabled, isFalse);
      container
          .read(shikooAccountProvider.notifier)
          .set(const ShikooAccount(who: TelegramAccount(name: 'Sam')));
      await tester.idle();
      expect(popup.view?.menu.head, 'سرویسی نداری');
      expect(row('وصل شدن').enabled, isFalse);

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
      // The engine's mode, as setMode saves it only on a Windows host.
      await ProviderScope.containerOf(
        tester.element(find.byType(ShikooHome)),
      ).read(shikooModeProvider.notifier).save(ShikooMode.proxy);
      await tester.pump();
      expect(lines(l.modeProxyHint), closeTo(2, 0.1));
      final proxy = tester.getRect(find.byType(ModeSwitch));
      expect((proxy.top, proxy.bottom), (tunnel.top, tunnel.bottom));
      expect(tester.getRect(find.byType(PowerButton)), power);
    }, variant: _windows);

    testWidgets('in the smallest window a message under the mode switch '
        'scrolls into view: new, in place of another, or there from the '
        'start', (tester) async {
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
      final cell = ProviderScope.containerOf(
        tester.element(find.byType(ShikooHome)),
      ).read(_stateCell.notifier);
      cell.set(_state(ShikooConnection.error, error: ShikooError.vpnRefused));
      await tester.pump();
      await tester.pump();
      expect(message().top, greaterThanOrEqualTo(0));
      expect(message().bottom, lessThanOrEqualTo(448));

      Scrollable.of(
        tester.element(find.byType(PowerButton)),
      ).position.jumpTo(0);
      await tester.pump();
      expect(message().bottom, greaterThan(448));
      cell.set(_state(ShikooConnection.error, helperFailed: true));
      await tester.pump();
      await tester.pump();
      expect(
        tester.getRect(find.text(l.helperFailedDesktop)).bottom,
        lessThanOrEqualTo(448),
      );

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
      final lit = _lit(ShikooColors.light.hoverBg);
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

    testWidgets('the tunnel refusal fits its two lines whole, in Persian and '
        'English', (tester) async {
      for (final language in ['fa', 'en']) {
        final locale = Locale(language);
        await _pumpHome(
          tester,
          const Size(880, 508),
          connection: ShikooConnection.error,
          error: ShikooError.vpnRefused,
          locale: locale,
        );
        final text = lookupShikooL10n(locale).vpnRefusedDesktop;
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        expect(paragraph.didExceedMaxLines, isFalse, reason: language);
        expect(paragraph.size.width, ShikooSizes.desktop.powerRing * 1.5);
      }
    }, variant: _windows);

    testWidgets('the three refusals under the button are whole at 100 to 150%, '
        'in Persian and English, clear of the switch and the card; at 100% '
        'the button stays put', (tester) async {
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final language in ['fa', 'en']) {
        final locale = Locale(language);
        final l = lookupShikooL10n(locale);
        // The port is the proxy's: only the proxy mode can find it taken.
        final cases = [
          (
            l.vpnRefusedDesktop,
            ShikooError.vpnRefused,
            null,
            false,
            ShikooMode.tunnel,
          ),
          (l.busyPortDesktop, null, 7890, false, ShikooMode.proxy),
          (l.helperFailedDesktop, null, null, true, ShikooMode.tunnel),
        ];
        for (final window in const [Size(880, 508), Size(400, 448)]) {
          for (final scale in const [1.0, 1.1, 1.2, 1.25, 1.3, 1.4, 1.5]) {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            await _pumpHome(
              tester,
              window,
              connection: ShikooConnection.off,
              locale: locale,
            );
            final rest = tester.getRect(find.byType(PowerButton));
            for (final (text, error, port, helper, mode) in cases) {
              await _pumpHome(
                tester,
                window,
                connection: ShikooConnection.error,
                error: error,
                busyPort: port,
                helperFailed: helper,
                locale: locale,
                overrides: [shikooModeProvider.overrideWith(() => _Mode(mode))],
              );
              await tester.pump();
              final why = '$language $window ×$scale: $text';
              final message = find.text(text);
              final box = tester.getRect(message);
              final paragraph = tester.renderObject<RenderParagraph>(message);
              expect(paragraph.didExceedMaxLines, isFalse, reason: why);
              expect(
                paragraph.size.height,
                greaterThanOrEqualTo(
                  paragraph.getMaxIntrinsicHeight(paragraph.size.width) - 0.01,
                ),
                reason: '$why: cut short',
              );
              expect(
                paragraph.text.style?.color,
                ShikooColors.light.danger,
                reason: why,
              );
              expect(box.top, greaterThanOrEqualTo(0), reason: why);
              expect(box.bottom, lessThanOrEqualTo(window.height), reason: why);
              expect(
                tester.getRect(find.byType(ModeSwitch)).bottom,
                lessThanOrEqualTo(box.top),
                reason: why,
              );
              if (window.width < ShikooSizes.twoColumns) {
                expect(
                  tester.getRect(find.byType(ServiceCard)).top,
                  greaterThanOrEqualTo(box.bottom),
                  reason: why,
                );
              }
              // The narrow window keeps no slot: a message scrolls the page to show itself.
              if (scale == 1.0 && window.width >= ShikooSizes.twoColumns) {
                expect(
                  tester.getRect(find.byType(PowerButton)),
                  rest,
                  reason: why,
                );
                expect(
                  window.height - box.bottom,
                  greaterThan(20),
                  reason: why,
                );
              }
            }
          }
        }
      }
    }, variant: _windows);

    testWidgets('at 150% a long server name under the button keeps clear of '
        "the column's scrollbar, and the timeout message keeps «·» with its "
        'word', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const long = 'Germany Frankfurt Hetzner 2 · premium';
      for (final language in ['fa', 'en']) {
        _window(tester, const Size(880, 508));
        await tester.pumpWidget(
          _app(
            locale: Locale(language),
            const ShikooHome(),
            overrides: [
              shikooStateProvider.overrideWithValue(
                _state(
                  ShikooConnection.error,
                  error: ShikooError.connectTimeout,
                  server: long,
                ),
              ),
            ],
          ),
        );
        await tester.pump();
        // Where Flutter draws the thumb, wherever its side and margin put it.
        final bar = find
            .descendant(
              of: find
                  .ancestor(
                    of: find.byType(PowerButton),
                    matching: find.byType(SingleChildScrollView),
                  )
                  .first,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is CustomPaint && w.foregroundPainter is ScrollbarPainter,
              ),
            )
            .first;
        await tester.drag(
          find.byType(PowerButton),
          const Offset(0, -20),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 50));
        final painter =
            tester.widget<CustomPaint>(bar).foregroundPainter!
                as ScrollbarPainter;
        final box = tester.getRect(bar);
        final pill = tester.getRect(find.byType(NowPill));
        final thumb = [
          for (var x = box.left; x <= box.right; x++)
            if (painter.hitTestOnlyThumbInteractive(
              Offset(x - box.left, pill.center.dy - box.top),
              PointerDeviceKind.mouse,
            ))
              x,
        ];
        expect(
          thumb,
          isNotEmpty,
          reason: '$language: no thumb beside the pill',
        );
        expect(
          thumb.where((x) => x >= pill.left && x < pill.right),
          isEmpty,
          reason:
              '$language: pill ${pill.left}..${pill.right}, '
              'thumb ${thumb.first}..${thumb.last}',
        );
        final message = tester
            .widget<Text>(find.textContaining('\u2068premium'))
            .data!;
        expect(message, contains('\u00a0· \u2068premium'), reason: language);
        expect(message, isNot(contains(' ·')), reason: language);
      }
    }, variant: _windows);

    testWidgets('a server row under the mouse is fainter than the chosen one, '
        'and the chosen one keeps its colour', (tester) async {
      for (final brightness in Brightness.values) {
        final c = brightness == Brightness.light
            ? ShikooColors.light
            : ShikooColors.dark;
        _window(tester, const Size(400, 448));
        await tester.pumpWidget(
          _app(
            brightness: brightness,
            Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: const ValueKey('rows'),
                  child: ColoredBox(
                    color: c.surface,
                    child: SizedBox(
                      width: 352,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (name, chosen) in [
                            ('آلمان ۲', true),
                            ('هلند ۱', false),
                          ])
                            ServerRow(
                              server: ShikooServer(
                                name: name,
                                type: 'Vless',
                                ping: 84,
                              ),
                              selected: chosen,
                              onPressed: () {},
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final rows = find.byType(ServerRow);
        // The row's end padding, clear of every mark on it.
        Offset edge(int i) {
          final row = tester.getRect(rows.at(i));
          return Offset(row.left + 3, row.center.dy);
        }

        Future<Color> at(int i) =>
            _pixel(tester, find.byKey(const ValueKey('rows')), edge(i));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(1, 1));
        await tester.pump();
        expect(await at(1), _looks(c.surface));

        await mouse.moveTo(tester.getCenter(rows.at(1)));
        await tester.pump();
        final hovered = await at(1);
        expect(hovered, _looks(Color.alphaBlend(c.hoverBg, c.surface)));
        expect(hovered, isNot(_looks(c.selectedBg)));

        await mouse.moveTo(tester.getCenter(rows.at(0)));
        await tester.pump();
        expect(await at(0), _looks(c.selectedBg), reason: '$brightness');
        await mouse.removePointer();
      }
    }, variant: _windows);

    testWidgets('the maximised sign-in keeps the brand and the buttons one '
        'group, 24 apart, in the middle; the language in the page\'s corner', (
      tester,
    ) async {
      const window = Size(1920, 1032);
      _window(tester, window);
      await tester.pumpWidget(
        _app(
          const LoginPage(login: null),
          overrides: [
            shikooStateProvider.overrideWithValue(_state(ShikooConnection.off)),
          ],
        ),
      );
      await tester.pump();
      final language = tester.getRect(find.byType(Segmented<String>));
      final mark = tester.getRect(find.byType(BrandMark));
      final tagline = tester.getRect(find.text(l.loginTagline));
      final telegram = tester.getRect(
        find.ancestor(
          of: find.text(l.loginTelegram),
          matching: find.byType(ShikooButton),
        ),
      );
      final last = tester.getRect(find.byType(LinkButton));
      expect(telegram.top - tagline.bottom, Space.s6);
      // In the page's 960, centred: its start is 480 in, its end corner Space.s6 inside it.
      expect((language.left, language.top < Space.s8), (480 + Space.s6, true));
      // SafeArea's minimum keeps Space.s8 under the page.
      expect(
        mark.top - language.bottom,
        closeTo(window.height - Space.s8 - last.bottom, 1),
      );
    }, variant: _windows);
  });

  testWidgets('in English a computer says click where a phone says tap', (
    tester,
  ) async {
    const en = Locale('en');
    final l = lookupShikooL10n(en);
    String pick(String computer, String phone) =>
        shikooDesktop ? computer : phone;
    Future<void> home(
      ShikooConnection connection, {
      ShikooError? error,
      ShikooNotice? notice,
    }) => _pumpHome(
      tester,
      const Size(880, 508),
      connection: connection,
      error: error,
      notice: notice,
      locale: en,
    );
    await home(ShikooConnection.connecting);
    expect(find.text(pick(l.subCancelDesktop, l.subCancelTouch)), findsOne);
    await home(ShikooConnection.error, error: ShikooError.connectTimeout);
    expect(find.text(pick(l.subRetryDesktop, l.subRetryTouch)), findsOne);
    expect(
      find.textContaining(pick('seconds. Click again', 'seconds. Tap again')),
      findsOne,
    );
    await home(ShikooConnection.on, notice: const RefreshFailed());
    expect(
      find.textContaining(pick(l.updateFailedDesktop, l.updateFailedTouch)),
      findsOne,
    );
    await tester.pumpWidget(
      _app(
        locale: en,
        const LoginPage(
          login: ShikooLogin(
            LoginPhase.noService,
            account: TelegramAccount(name: 'Sam', username: 'sam'),
          ),
        ),
        overrides: [
          shikooStateProvider.overrideWithValue(_state(ShikooConnection.off)),
        ],
      ),
    );
    await tester.pump();
    expect(
      find.textContaining(pick(l.noServiceHelpDesktop, l.noServiceHelpTouch)),
      findsOne,
    );

    Future<void> page(
      Widget home, {
      ShikooState? state,
      List<Override> overrides = const [],
    }) async {
      await tester.pumpWidget(
        _app(
          locale: en,
          home,
          overrides: [
            shikooStateProvider.overrideWithValue(
              state ?? _state(ShikooConnection.off),
            ),
            ...overrides,
          ],
        ),
      );
      await tester.pump();
    }

    await page(const LoginPage(login: null));
    expect(
      find.text(pick(l.loginTelegramNoteDesktop, l.loginTelegramNote)),
      findsOne,
    );
    await page(
      const ShikooHome(),
      state: const ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: false,
        servers: [],
      ),
    );
    expect(
      find.text(pick(l.noServiceHelpPasteDesktop, l.noServiceHelpPaste)),
      findsOne,
    );
    final controller = _Controller();
    await page(
      Scaffold(
        body: ServiceCard(
          state: _state(ShikooConnection.on),
          controller: controller,
          focus: CardFocus(),
          other: true,
        ),
      ),
    );
    expect(
      find.text(pick(l.otherServiceHintDesktop, l.otherServiceHint)),
      findsWidgets,
    );
    when(() => controller.pasteService(any())).thenAnswer(
      (_) async => (error: ShikooPasteError.empty, id: null, added: false),
    );
    await page(
      const AddService(),
      overrides: [shikooControllerProvider.overrideWithValue(controller)],
    );
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData' ? {'text': ''} : null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.tap(find.text(l.pasteLink));
    await tester.pump();
    await tester.pump();
    expect(
      find.textContaining(pick(l.pasteEmptyHelpDesktop, l.pasteEmptyHelp)),
      findsOne,
    );
    for (final text in [
      l.subCancelDesktop,
      l.subRetryDesktop,
      l.errorConnectDesktop('x', 1),
      l.updateFailedDesktop,
      l.noServiceHelpDesktop,
      l.loginTelegramNoteDesktop,
      l.noServiceHelpPasteDesktop,
      l.otherServiceHintDesktop,
      l.pasteEmptyHelpDesktop,
    ]) {
      expect(text, isNot(contains(RegExp('[Tt]ap'))));
    }
  }, variant: _computerAndPhone);

  testWidgets('the other-device page asks a computer for a phone with '
      'Telegram, and a phone for another one', (tester) async {
    for (final language in ['fa', 'en']) {
      final locale = Locale(language);
      final l = lookupShikooL10n(locale);
      _window(tester, const Size(400, 800));
      await tester.pumpWidget(
        _app(
          locale: locale,
          const LoginPage(
            login: ShikooLogin(
              LoginPhase.waiting,
              code: '12345678',
              botUrl: 'https://t.me/shikoonet_bot?start=x',
            ),
          ),
          overrides: [
            shikooStateProvider.overrideWithValue(_state(ShikooConnection.off)),
          ],
        ),
      );
      await tester.pump();
      await tester.tap(find.text(l.approveElsewhere));
      await tester.pump();
      expect(
        find.text(shikooDesktop ? l.otherDeviceScanDesktop : l.otherDeviceScan),
        findsOne,
        reason: language,
      );
    }
  }, variant: _computerAndPhone);

  testWidgets('the mouse lights nothing that is greyed out: a button that '
      'keeps the ring, the mode switch while connecting', (tester) async {
    _window(tester, const Size(400, 448));
    final node = FocusNode();
    addTearDown(node.dispose);
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(
            child: ValueListenableBuilder(
              valueListenable: enabled,
              builder: (context, on, _) => ShikooButton(
                label: 'ارسال',
                autofocus: true,
                focusNode: node,
                onPressed: on ? () {} : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    enabled.value = false;
    await tester.pump();
    expect(node.hasFocus, isTrue);
    expect(find.byType(Pressable), findsOne);
    final lit = _lit(ShikooColors.light.hoverBg);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('ارسال')));
    await tester.pump();
    expect(lit, findsNothing);

    await _pumpHome(
      tester,
      const Size(880, 508),
      connection: ShikooConnection.connecting,
    );
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text('پروکسی')));
    await tester.pump();
    expect(lit, findsNothing);
  }, variant: _windows);

  testWidgets('a filled face fades to 90% under the mouse, with nothing '
      'behind it', (tester) async {
    _window(tester, const Size(400, 448));
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShikooButton(label: 'تمدید', primary: true, onPressed: () {}),
              PowerButton(
                connection: ShikooConnection.off,
                connectedFor: Duration.zero,
                isTV: false,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    Finder faded(Finder face) => find.ancestor(
      of: face,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Opacity && widget.opacity == ShikooColors.solidHover,
      ),
    );
    final connect = lookupShikooL10n(const Locale('fa')).powerConnect;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(399, 447));
    addTearDown(mouse.removePointer);
    await tester.pump();
    for (final face in [find.text('تمدید'), find.text(connect)]) {
      expect(faded(face), findsNothing);
      await mouse.moveTo(tester.getCenter(face));
      await tester.pump();
      expect(faded(face), findsOne);
      expect(_lit(ShikooColors.light.hoverBg), findsNothing);
      await mouse.moveTo(const Offset(399, 447));
      await tester.pump();
    }
  }, variant: _windows);

  testWidgets('in the 880 × 540 window the message under the mode switch '
      'keeps clear of the bottom, the column centred', (tester) async {
    const window = Size(880, 508);
    await _pumpHome(
      tester,
      window,
      connection: ShikooConnection.error,
      error: ShikooError.noServer,
    );
    final l = lookupShikooL10n(const Locale('fa'));
    final message = tester.getRect(find.text(l.noServerAnsweredHelpDesktop));
    final above =
        tester.getRect(find.byType(PowerButton)).top -
        ShikooSizes.desktop.appbar;
    final below = window.height - message.bottom;
    expect(below, greaterThan(20));
    expect(above, closeTo(below, 1));
  }, variant: _windows);

  testWidgets('a window wider than 960 keeps the 960 page, top bars too, '
      'centred', (tester) async {
    final l = lookupShikooL10n(const Locale('fa'));
    final settings = find.byWidgetPredicate(
      (widget) => widget is ShikooIconButton && widget.label == l.settings,
    );
    final back = find.byWidgetPredicate(
      (widget) => widget is ShikooIconButton && widget.label == l.back,
    );
    Future<List<Rect>> home(double width) async {
      await _pumpHome(tester, Size(width, 508));
      return [
        for (final part in [
          find.byType(ServiceCard),
          find.byType(PowerButton),
          find.byType(Brand),
          settings,
        ])
          tester.getRect(part),
      ];
    }

    Future<Rect> page(double width) async {
      _window(tester, Size(width, 508));
      await tester.pumpWidget(
        _app(
          const SubPage(
            title: 'تنظیمات',
            isTV: false,
            child: SizedBox(height: 40),
          ),
        ),
      );
      return tester.getRect(back);
    }

    const shift = Offset(480, 0);
    final narrow = await home(960);
    expect(await home(1920), [for (final r in narrow) r.shift(shift)]);
    final bar = await page(960);
    expect(await page(1920), bar.shift(shift));
  }, variant: _windows);

  testWidgets('after Tab, Tab and a click on «تیره», Tab goes on from «تیره», '
      'not from where the keys had left the focus', (tester) async {
    addTearDown(ringOnKeys());
    _window(tester, const Size(880, 508));
    await tester.pumpWidget(
      _app(
        const ShikooSettings(),
        overrides: [
          shikooStateProvider.overrideWithValue(_state(ShikooConnection.off)),
          shikooVersionProvider.overrideWithValue('1.0.57'),
        ],
      ),
    );
    await tester.pump();
    String? focused() {
      final context = FocusManager.instance.primaryFocus?.context;
      if (context == null) return null;
      return find
          .descendant(
            of: find.byElementPredicate((element) => element == context),
            matching: find.byType(Text),
          )
          .evaluate()
          .map((element) => (element.widget as Text).data)
          .firstOrNull;
    }

    Future<void> tab() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    expect(focused(), 'خودکار');
    await tab();
    await tab();
    expect(focused(), 'English');
    await tester.tap(find.text('تیره'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(focused(), 'تیره');
    await tab();
    expect(focused(), 'خودکار');
    await tab();
    expect(focused(), 'فارسی');
  }, variant: _windows);

  testWidgets('Enter or Space presses the round button only when the ring is '
      'on it: not after a click, yes after Tab', (tester) async {
    addTearDown(ringOnKeys());
    final controller = _Controller();
    when(controller.connect).thenAnswer((_) async {});
    Future<void> home() => _pumpHome(
      tester,
      const Size(880, 508),
      connection: ShikooConnection.off,
      overrides: [shikooControllerProvider.overrideWithValue(controller)],
    );
    bool onPower() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<PowerButton>() !=
        null;

    await home();
    await tester.tap(find.byType(PowerButton), kind: PointerDeviceKind.mouse);
    await tester.pump();
    verify(controller.connect).called(1);
    expect(onPower(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    verifyNever(controller.connect);

    await home();
    for (var i = 0; i < 30 && !onPower(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(onPower(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    verify(controller.connect).called(1);
  }, variant: _windows);

  testWidgets('the ring waits for Tab or an arrow, and a click hides it '
      'again', (tester) async {
    addTearDown(ringOnKeys());
    _window(tester, const Size(400, 448));
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShikooButton(label: 'یک', autofocus: true, onPressed: () {}),
                ShikooButton(label: 'دو', onPressed: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    String? focused() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<ShikooButton>()
        ?.label;
    expect(focused(), 'یک');
    expect(_ring, findsNothing);
    await tester.tap(find.text('دو'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(_ring, findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_ring, findsOne);
    await tester.tap(find.text('یک'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(_ring, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(_ring, findsOne);
  }, variant: _windows);
}
