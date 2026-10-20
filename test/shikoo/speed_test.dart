import 'package:fl_clash/models/models.dart' show Traffic;
import 'package:fl_clash/providers/providers.dart'
    show profilesProvider, runTimeProvider, trafficsProvider;
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/no_shots.dart';
import '../helpers/test_profiles.dart';

/// The design's `۲٫۴` and `۰٫۳`, in bytes a second.
const _design = (down: 2516582, up: 314573);

/// Three digits each way, every digit being as wide as any other.
const _wide = (down: 888.8 * mebibyte, up: 888.8 * mebibyte);

final _speed = find.byWidgetPredicate((w) => '${w.runtimeType}' == '_Speed');

Finder _icon(ShikooIcon icon) =>
    find.byWidgetPredicate((w) => w is SvgIcon && w.icon == icon);

ShikooState _state(ShikooConnection connection, {bool tv = false}) =>
    ShikooState(
      connection: connection,
      connectedFor: const Duration(minutes: 12, seconds: 47),
      isTV: tv,
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
      lastError: connection == ShikooConnection.error
          ? ShikooError.connectTimeout
          : null,
    );

/// [speed] null keeps the engine's own, fed from FlClash's samples.
Future<void> _pumpHome(
  WidgetTester tester,
  ShikooConnection connection, {
  Size window = const Size(360, 800),
  bool tv = false,
  String locale = 'fa',
  ({num down, num up})? speed = _design,
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
        shikooStateProvider.overrideWithValue(_state(connection, tv: tv)),
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

/// What moves when the speed comes: the button, the pill, the card and how far the page scrolls.
List<Object?> _layout(WidgetTester tester) => [
  tester.getRect(find.byType(PowerButton)),
  tester.getRect(find.byType(NowPill)),
  tester.getTopLeft(find.byType(ServiceCard)),
  Scrollable.maybeOf(
    tester.element(find.byType(PowerButton)),
  )?.position.maxScrollExtent,
];

void main() {
  test('one decimal of the card\'s MB, a GB being 1024 of them; under 50 KB '
      'a second reads 0.0', () {
    expect(speedOf('fa', _design.down), '۲٫۴', reason: 'not 2.5, as 10⁶ gives');
    expect(speedOf('fa', _design.up), '۰٫۳');
    expect(speedOf('en', _design.down), '2.4');
    expect(speedOf('fa', 0), '۰٫۰');
    expect(speedOf('fa', 50 * 1024 - 1), '۰٫۰');
    expect(speedOf('fa', 50 * 1024), '۰٫۰');
    expect(speedOf('fa', 52428), '۰٫۰', reason: 'the last byte under 0.05');
    expect(speedOf('fa', 52429), '۰٫۱');
    expect(speedOf('fa', 12 * mebibyte), '۱۲٫۰');
  });

  group('with the real font', () {
    setUpAll(loadShikooFonts);

    testWidgets('connected, the speed stands under the clock and the power '
        'icon gives it room; in no other state is it there', (tester) async {
      for (final connection in ShikooConnection.values) {
        await _pumpHome(tester, connection);
        final on = connection == ShikooConnection.on;
        final why = '$connection';
        expect(_speed, on ? findsOne : findsNothing, reason: why);
        expect(_icon(ShikooIcon.arrowDown), on ? findsOne : findsNothing);
        expect(find.text('مگ/ث'), on ? findsOne : findsNothing, reason: why);
        expect(
          _icon(ShikooIcon.power),
          on || connection == ShikooConnection.error ? findsNothing : findsOne,
          reason: why,
        );
        if (!on) continue;
        expect(find.text('۲٫۴'), findsOne);
        expect(find.text('۰٫۳'), findsOne);
        expect(
          tester.getRect(_speed).top,
          greaterThan(tester.getRect(find.text('۰۰:۱۲:۴۷')).bottom),
        );
        final digits = tester.widget<Text>(find.text('۲٫۴')).style!;
        expect(digits.fontFeatures, [const FontFeature.tabularFigures()]);
        expect(digits.fontSize, ShikooSizes.phone.caption);
      }
    });

    testWidgets('a screen reader hears both speeds in words, in either '
        'language', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpHome(tester, ShikooConnection.on);
      expect(
        find.bySemanticsLabel(
          RegExp(
            'سرعت دریافت ۲٫۴ مگابایت بر ثانیه، سرعت ارسال ۰٫۳ مگابایت بر ثانیه',
          ),
        ),
        findsOne,
      );
      await _pumpHome(tester, ShikooConnection.on, locale: 'en');
      expect(find.text('MB/s'), findsOne);
      expect(
        find.bySemanticsLabel(
          RegExp(
            'Download 2.4 megabytes per second, upload 0.3 megabytes per second',
          ),
        ),
        findsOne,
      );
      semantics.dispose();
    });

    testWidgets('the speed fits inside the circle and moves nothing around '
        'it: phone at 100 and 145%, TV, and the short windows, in both '
        'languages', (tester) async {
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final wrong = <String>[];
      final screens = <(String, Size, bool, double, TargetPlatform)>[
        ('phone', const Size(360, 800), false, 1, TargetPlatform.android),
        ('phone', const Size(360, 800), false, 1.45, TargetPlatform.android),
        ('tv', const Size(960, 540), true, 1, TargetPlatform.android),
        ('window', const Size(864, 492), false, 1, TargetPlatform.windows),
        ('window', const Size(880, 540), false, 1, TargetPlatform.windows),
      ];
      for (final (name, window, tv, scale, platform) in screens) {
        debugDefaultTargetPlatformOverride = platform;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        for (final locale in ['fa', 'en']) {
          for (final speed in [_design, _wide]) {
            final at = '$name $window ×$scale $locale ${speed.down}';
            await _pumpHome(
              tester,
              ShikooConnection.off,
              window: window,
              tv: tv,
              locale: locale,
              speed: speed,
            );
            final off = _layout(tester);
            await _pumpHome(
              tester,
              ShikooConnection.on,
              window: window,
              tv: tv,
              locale: locale,
              speed: speed,
            );
            final error = tester.takeException();
            if (error != null) wrong.add('$at: $error');
            if (_layout(tester).toString() != off.toString()) {
              wrong.add('$at: ${_layout(tester)} after $off');
            }
            final circle = tester.getRect(
              find
                  .descendant(
                    of: find.byType(PowerButton),
                    matching: find.byType(Container),
                  )
                  .first,
            );
            final line = tester.getRect(
              find.descendant(of: _speed, matching: find.byType(Row)).first,
            );
            for (final corner in [
              line.topLeft,
              line.topRight,
              line.bottomLeft,
              line.bottomRight,
            ]) {
              final out = (corner - circle.center).distance - circle.width / 2;
              if (out > 0.5) wrong.add('$at: $corner ${out}dp out of $circle');
            }
          }
        }
      }
      debugDefaultTargetPlatformOverride = null;
      expect(wrong, isEmpty, reason: wrong.join('\n'));
    });

    testWidgets('a new sample redraws the speed alone, not the home around '
        'it', (tester) async {
      await _pumpHome(tester, ShikooConnection.on, speed: null);
      expect(find.text('۰٫۰'), findsNWidgets(2));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShikooHome)),
      );
      final rebuilt = <String>{};
      debugOnRebuildDirtyWidget = (element, _) =>
          rebuilt.add('${element.widget.runtimeType}');
      try {
        container
            .read(trafficsProvider.notifier)
            .addTraffic(Traffic(down: _design.down, up: _design.up));
        await tester.pump();
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      expect(find.text('۲٫۴'), findsOne);
      expect(rebuilt, contains('_Speed'));
      for (final whole in ['ShikooHome', 'PowerButton', '_PowerZone']) {
        expect(rebuilt, isNot(contains(whole)), reason: '$rebuilt');
      }
    });
  });

  test('the engine passes on the core\'s latest sample, zero before one', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    ({num down, num up}) speed() => container.read(shikooSpeedProvider);
    final traffics = container.read(trafficsProvider.notifier);
    expect(speed(), (down: 0, up: 0));
    traffics.addTraffic(const Traffic(down: 2000, up: 100));
    expect(speed(), (down: 2000, up: 100));
    traffics.addTraffic(const Traffic(down: 3000, up: 200));
    expect(speed(), (down: 3000, up: 200));
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
