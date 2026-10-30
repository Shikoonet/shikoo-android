import 'package:fl_clash/models/models.dart' show Traffic;
import 'package:fl_clash/providers/providers.dart'
    show profilesProvider, runTimeProvider, trafficsProvider;
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/mode.dart' show LocalProxy;
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/no_shots.dart';
import '../helpers/test_profiles.dart';

/// Bytes a second for megabits a second.
num _mbps(num mbps) => mbps * 1e6 / 8;

/// The admin's speed test: 32.5 down, 4.3 up.
final _load = (down: _mbps(32.5), up: _mbps(4.3));
final _wide = (down: _mbps(888), up: _mbps(888));
const _idle = (down: 0, up: 0);

/// Not the hidden row that holds each pill's room.
bool _seen(Element e) =>
    e.findAncestorWidgetOfExactType<Visibility>()?.visible ?? true;

Finder _icon(ShikooIcon icon) => find.byElementPredicate(
  (e) => e.widget is SvgIcon && (e.widget as SvgIcon).icon == icon && _seen(e),
);

Finder _text(String text) => find.byElementPredicate(
  (e) => e.widget is Text && (e.widget as Text).data == text && _seen(e),
);

Finder _inPills(Finder finder) =>
    find.descendant(of: find.byType(SpeedPills), matching: finder);

final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

const _streaming = '(رایگان) نماوا | فیلیمو | شیدا | گپ فیلم';

ShikooState _state(
  ShikooConnection connection, {
  bool tv = false,
  bool silent = false,
  bool streaming = false,
  ShikooError? error,
}) => ShikooState(
  connection: connection,
  connectedFor: const Duration(minutes: 12, seconds: 47),
  isTV: tv,
  service: ShikooService(
    name: '5550123 · الماس',
    usedBytes: 33 << 30,
    totalBytes: 100 << 30,
    updatedAt: DateTime.now(),
  ),
  servers: [
    ShikooServer(name: 'آلمان ۲', type: 'Vless', ping: silent ? -1 : 84),
    const ShikooServer(name: 'هلند ۱', type: 'Vless', ping: 96),
    const ShikooServer(name: _streaming, type: 'Shadowsocks', ping: 120),
  ],
  selected: streaming ? _streaming : 'آلمان ۲',
  connectedNoTraffic: streaming,
  sorted: true,
  lastError:
      error ??
      (connection == ShikooConnection.error
          ? ShikooError.connectTimeout
          : null),
);

/// [speed] null keeps the engine's own, fed from FlClash's samples.
Future<void> _pumpHome(
  WidgetTester tester,
  ShikooConnection connection, {
  Size window = const Size(360, 800),
  bool tv = false,
  String locale = 'fa',
  bool silent = false,
  bool streaming = false,
  ShikooError? error,
  ({num down, num up})? speed,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = tv ? const Size(1920, 1080) : window
    ..devicePixelRatio = tv ? 2 : 1;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        noShots,
        shikooStateProvider.overrideWithValue(
          _state(
            connection,
            tv: tv,
            silent: silent,
            streaming: streaming,
            error: error,
          ),
        ),
        if (speed != null) shikooSpeedProvider.overrideWithValue(speed),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(Brightness.light, tv: tv),
        builder: tv ? (_, child) => ShikooTvCanvas(child: child!) : null,
        home: const ShikooHome(),
      ),
    ),
  );
  await tester.pump();
}

Rect _pill(WidgetTester tester, ShikooIcon icon) => tester.getRect(
  find.ancestor(of: _icon(icon), matching: find.byType(Container)).first,
);

void main() {
  test('megabits a second: nothing is 0, any traffic at least 0.1, one '
      'decimal under 100 and none from there', () {
    for (final (mbps, language, shown) in [
      (0, 'fa', '۰'),
      (0.001, 'fa', '۰٫۱'),
      (0.06, 'fa', '۰٫۱'),
      (32.5, 'fa', '۳۲٫۵'),
      (4.3, 'fa', '۴٫۳'),
      (99.94, 'fa', '۹۹٫۹'),
      (99.96, 'fa', '۱۰۰'),
      (888, 'fa', '۸۸۸'),
      (32.5, 'en', '32.5'),
      (0, 'en', '0'),
    ]) {
      expect(speedOf(language, _mbps(mbps)), shown, reason: '$mbps $language');
    }
    expect(speedOf('fa', 1), '۰٫۱', reason: 'a single byte still moved');
  });

  group('with the real font', () {
    setUpAll(loadShikooFonts);

    testWidgets('connected, two pills stand between the button and the '
        'server; the circle keeps the label and the clock alone; in no other '
        'state are they there', (tester) async {
      for (final connection in ShikooConnection.values) {
        await _pumpHome(tester, connection, speed: _load);
        final on = connection == ShikooConnection.on;
        expect(find.byType(SpeedPills), on ? findsOne : findsNothing);
        expect(_text('مگ'), on ? findsNWidgets(2) : findsNothing);
        if (!on) continue;
        expect(find.text('۳۲٫۵'), findsOne);
        expect(find.text('۴٫۳'), findsOne);
        final circle = find.byType(PowerButton);
        expect(
          [
            for (final e
                in find
                    .descendant(of: circle, matching: find.byType(Text))
                    .evaluate())
              (e.widget as Text).data,
          ],
          ['وصل', '۰۰:۱۲:۴۷'],
        );
        expect(
          find.descendant(of: circle, matching: find.byType(SvgIcon)),
          findsNothing,
        );
        final pills = tester.getRect(find.byType(SpeedPills));
        expect(pills.top, greaterThan(tester.getRect(circle).bottom - 1));
        expect(
          pills.bottom,
          lessThan(tester.getRect(find.byType(NowPill)).top),
        );
        final number = tester.widget<Text>(find.text('۳۲٫۵')).style!;
        expect(number.fontFeatures, [const FontFeature.tabularFigures()]);
        expect(number.fontSize, ShikooSizes.phone.speedPillText);
        expect(
          _pill(tester, ShikooIcon.download).height,
          ShikooSizes.phone.speedPill,
        );
        final unit = tester.widget<Text>(_text('مگ').first).style!;
        expect(unit.color, ShikooColors.light.textMuted);
        final icon = tester.widget<SvgIcon>(_icon(ShikooIcon.upload));
        expect(
          (icon.size, icon.color),
          (ShikooSizes.phone.iconSm, ShikooColors.light.positive),
        );
      }
    });

    testWidgets('download comes first: on the right in Persian, on the left '
        'in English', (tester) async {
      for (final (locale, downOnRight) in [('fa', true), ('en', false)]) {
        await _pumpHome(
          tester,
          ShikooConnection.on,
          locale: locale,
          speed: _load,
        );
        final down = _pill(tester, ShikooIcon.download);
        final up = _pill(tester, ShikooIcon.upload);
        expect(down.top, up.top, reason: '$locale: one row');
        expect(down.center.dx > up.center.dx, downOnRight, reason: locale);
      }
    });

    testWidgets('idle, each pill reads 0 and its unit', (tester) async {
      await _pumpHome(tester, ShikooConnection.on, speed: _idle);
      expect(_inPills(find.text('۰')), findsNWidgets(2));
      expect(_inPills(_text('مگ')), findsNWidgets(2));
      await _pumpHome(tester, ShikooConnection.on, locale: 'en', speed: _idle);
      expect(_inPills(find.text('0')), findsNWidgets(2));
      expect(_inPills(_text('Mbps')), findsNWidgets(2));
    });

    testWidgets('icon, number and unit keep together at any speed: the room '
        'held for the widest goes to the pill\'s edges', (tester) async {
      for (final locale in ['fa', 'en']) {
        for (final speed in [_idle, _load]) {
          await _pumpHome(
            tester,
            ShikooConnection.on,
            locale: locale,
            speed: speed,
          );
          final icon = tester.getRect(_icon(ShikooIcon.download));
          final number = tester.getRect(
            _text(speedOf(locale, speed.down)).first,
          );
          final unit = tester.getRect(
            _text(locale == 'fa' ? 'مگ' : 'Mbps').first,
          );
          final gaps = locale == 'fa'
              ? [icon.left - number.right, number.left - unit.right]
              : [number.left - icon.right, unit.left - number.right];
          for (final gap in gaps) {
            expect(
              gap,
              closeTo(ShikooSizes.speedIconGap, 0.01),
              reason: '$locale $speed',
            );
          }
        }
      }
    });

    testWidgets('a pill keeps its width as the number moves', (tester) async {
      for (final locale in ['fa', 'en']) {
        final widths = <double>{};
        for (final speed in [_idle, _load, _wide]) {
          await _pumpHome(
            tester,
            ShikooConnection.on,
            locale: locale,
            speed: speed,
          );
          widths.add(_pill(tester, ShikooIcon.download).width);
        }
        expect(widths, hasLength(1), reason: '$locale $widths');
      }
    });

    testWidgets('a screen reader hears both speeds in words, in either '
        'language', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpHome(tester, ShikooConnection.on, speed: _load);
      expect(
        find.bySemanticsLabel(
          'سرعت دریافت ۳۲٫۵ مگابیت بر ثانیه، ارسال ۴٫۳ مگابیت بر ثانیه',
        ),
        findsOne,
      );
      await _pumpHome(tester, ShikooConnection.on, locale: 'en', speed: _load);
      expect(
        find.bySemanticsLabel(
          'Download 32.5 megabits per second, upload 4.3 megabits per second',
        ),
        findsOne,
      );
      semantics.dispose();
    });

    testWidgets('the narrowest phone at the largest text holds both pills at '
        'three digits in one row, inside the page, in either language', (
      tester,
    ) async {
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.platformDispatcher.textScaleFactorTestValue =
          ShikooSizes.roundTextScaleMax;
      for (final locale in ['fa', 'en']) {
        await _pumpHome(
          tester,
          ShikooConnection.on,
          window: const Size(320, 800),
          locale: locale,
          speed: _wide,
        );
        expect(tester.takeException(), isNull, reason: locale);
        final down = _pill(tester, ShikooIcon.download);
        final up = _pill(tester, ShikooIcon.upload);
        expect(down.top, up.top, reason: '$locale: one row');
        for (final pill in [down, up]) {
          expect(pill.left, greaterThanOrEqualTo(ShikooSizes.phone.safeX));
          expect(pill.right, lessThanOrEqualTo(320 - ShikooSizes.phone.safeX));
        }
      }
    });

    testWidgets('on the phone, connecting moves the server down by the pill '
        'row alone', (tester) async {
      await _pumpHome(tester, ShikooConnection.off, speed: _load);
      final off = tester.getTopLeft(find.byType(NowPill));
      await _pumpHome(tester, ShikooConnection.on, speed: _load);
      final on = tester.getTopLeft(find.byType(NowPill));
      expect(on - off, Offset(0, ShikooSizes.phone.speedPill + Space.s3));
    });

    testWidgets('on the TV the pills are bigger and the remote never stops on '
        'them', (tester) async {
      await _pumpHome(tester, ShikooConnection.on, tv: true, speed: _load);
      final pills = tester.getRect(find.byType(SpeedPills)).deflate(1);
      expect([
        for (final node in FocusManager.instance.rootScope.traversalDescendants)
          if (node is! FocusScopeNode &&
              node.canRequestFocus &&
              pills.overlaps(node.rect))
            node,
      ], isEmpty);
      expect(
        tester.widget<Text>(find.text('۳۲٫۵')).style!.fontSize,
        ShikooSizes.tv.speedPillText,
      );
      expect(
        _pill(tester, ShikooIcon.download).height,
        ShikooSizes.tv.speedPill,
      );
    });

    testWidgets('on the TV the pills take the message\'s room under the '
        'button and news takes theirs; the button stays at 274, but for the '
        'no-internet card, taller, which moves it up as design b draws', (
      tester,
    ) async {
      for (final (connection, silent) in [
        (ShikooConnection.off, false),
        (ShikooConnection.on, false),
        (ShikooConnection.on, true),
      ]) {
        await _pumpHome(
          tester,
          connection,
          tv: true,
          silent: silent,
          speed: _load,
        );
        final why = '$connection silent: $silent';
        expect(tester.takeException(), isNull, reason: why);
        final button = tester.getRect(find.byType(PowerButton));
        if (!silent) expect(button.center.dy, closeTo(274, 0.5), reason: why);
        if (connection != ShikooConnection.on) continue;
        final l = ShikooL10n.of(tester.element(find.byType(ShikooHome)));
        final news = _text(l.noInternetOther);
        expect(find.byType(SpeedPills), silent ? findsNothing : findsOne);
        final under = tester.getRect(silent ? news : find.byType(SpeedPills));
        expect(under.top, greaterThan(button.bottom), reason: why);
        expect(
          under.bottom,
          lessThan(tester.getRect(find.byType(NowPill)).top),
          reason: why,
        );
      }
      await _pumpHome(
        tester,
        ShikooConnection.on,
        tv: true,
        error: ShikooError.serverChange,
        speed: _load,
      );
      final l = ShikooL10n.of(tester.element(find.byType(ShikooHome)));
      expect(find.byType(SpeedPills), findsNothing);
      expect(
        tester.getCenter(_text(l.errorServer)).dy,
        closeTo(421, 1),
        reason: 'one line of news, in the middle of its room',
      );
    });

    testWidgets('in a window the pills take the message\'s room under the '
        'button, news takes theirs, and connecting moves no button nor '
        'scrolls the short window', (tester) async {
      for (final window in const [Size(864, 492), Size(880, 540)]) {
        await _pumpHome(
          tester,
          ShikooConnection.off,
          window: window,
          speed: _load,
        );
        final off = tester.getCenter(find.byType(PowerButton));
        for (final silent in [false, true]) {
          await _pumpHome(
            tester,
            ShikooConnection.on,
            window: window,
            silent: silent,
            speed: _load,
          );
          final why = '$window silent: $silent';
          expect(tester.takeException(), isNull, reason: why);
          expect(find.byType(SpeedPills), silent ? findsNothing : findsOne);
          expect(tester.getCenter(find.byType(PowerButton)), off, reason: why);
          expect(
            Scrollable.of(
              tester.element(find.byType(LocalProxy)),
            ).position.maxScrollExtent,
            0,
            reason: why,
          );
        }
      }
      await _pumpHome(
        tester,
        ShikooConnection.on,
        window: const Size(864, 492),
        error: ShikooError.serverChange,
        speed: _load,
      );
      final l = ShikooL10n.of(tester.element(find.byType(ShikooHome)));
      expect(
        tester.getCenter(_text(l.errorServer)).dy,
        closeTo(282, 1),
        reason: 'one line of news, in the middle of its room',
      );
    }, variant: _windows);

    testWidgets('in a window design b\'s card is one row in the message\'s '
        'room, its small button beside the line, and the streaming server\'s '
        'card two flat lines there', (tester) async {
      const window = Size(864, 492);
      await _pumpHome(tester, ShikooConnection.off, window: window);
      final off = tester.getCenter(find.byType(PowerButton));
      await _pumpHome(
        tester,
        ShikooConnection.on,
        window: window,
        silent: true,
      );
      final l = ShikooL10n.of(tester.element(find.byType(ShikooHome)));
      final title = _text(l.noInternetTitle(serverName('آلمان ۲')));
      final other = _text(l.noInternetOther);
      expect(tester.takeException(), isNull);
      expect(_text(l.powerNoInternet), findsOne);
      expect(
        tester.getCenter(other).dy,
        closeTo(tester.getCenter(title).dy, 2),
      );
      expect(
        tester.getRect(title).top,
        greaterThan(tester.getRect(find.byType(PowerButton)).bottom),
      );
      expect(
        tester.getRect(other).bottom,
        lessThan(tester.getRect(find.byType(NowPill)).top),
      );
      expect(_text(l.noInternetBody), findsNothing, reason: 'one row only');
      final room = ShikooSizes.desktop.dialog;
      final row = find.ancestor(of: title, matching: find.byType(Row)).first;
      expect(tester.getSize(row).width, lessThanOrEqualTo(room));

      await _pumpHome(
        tester,
        ShikooConnection.on,
        window: window,
        streaming: true,
      );
      expect(tester.takeException(), isNull);
      expect(_text(l.powerOn), findsOne);
      expect(_text(l.streamingTitle), findsOne);
      expect(_text(l.streamingBody), findsOne);
      expect(
        tester.getSize(_text(l.streamingBody)).width,
        lessThanOrEqualTo(room),
      );
      expect(tester.getCenter(find.byType(PowerButton)), off);
    }, variant: _windows);

    testWidgets('a new sample redraws the pills alone, not the home around '
        'them', (tester) async {
      await _pumpHome(tester, ShikooConnection.on);
      expect(_inPills(find.text('۰')), findsNWidgets(2));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShikooHome)),
      );
      final rebuilt = <String>{};
      debugOnRebuildDirtyWidget = (element, _) =>
          rebuilt.add('${element.widget.runtimeType}');
      try {
        container
            .read(trafficsProvider.notifier)
            .addTraffic(Traffic(down: _load.down, up: _load.up));
        await tester.pump();
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      expect(find.text('۳۲٫۵'), findsOne);
      expect(rebuilt, contains('SpeedPills'));
      for (final whole in ['ShikooHome', 'PowerButton', '_PowerZone']) {
        expect(rebuilt, isNot(contains(whole)), reason: '$rebuilt');
      }
    });
  });

  test('the engine passes on the core\'s latest one-second sample as it is, '
      'never an average; zero before one', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    ({num down, num up}) speed() => container.read(shikooSpeedProvider);
    final traffics = container.read(trafficsProvider.notifier);
    expect(speed(), (down: 0, up: 0));
    traffics.addTraffic(const Traffic(down: 2000, up: 100));
    expect(speed(), (down: 2000, up: 100));
    traffics.addTraffic(const Traffic(down: 3000, up: 200));
    traffics.addTraffic(const Traffic(down: 600, up: 50));
    expect(speed(), (down: 600, up: 50));
    traffics.clear();
    expect(speed(), (down: 0, up: 0));
  });

  test('the home\'s state hears nothing of a new sample: the home is not '
      'rebuilt for it', () {
    final container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    addTearDown(container.dispose);
    var heard = 0;
    container.listen(shikooStateProvider, (_, _) => heard++);
    container
        .read(trafficsProvider.notifier)
        .addTraffic(const Traffic(down: 2000, up: 100));
    container.read(shikooStateProvider);
    expect(heard, 0);
    container.read(runTimeProvider.notifier).value = 1000;
    container.read(shikooStateProvider);
    expect(heard, 1, reason: 'it does hear the clock');
  });
}
