import 'dart:async';

import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/update.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/update.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/no_shots.dart';

class _Update extends Mock implements ShikooUpdate {}

class _Controller extends Mock implements ShikooController {}

const _check = 'بررسی به‌روزرسانی';
const _checking = 'در حال بررسی…';
const _latest = 'نسخهٔ تو تازه‌ترین است.';
const _failed = 'بررسی نشد؛ اینترنت را بررسی کن و دوباره بزن.';
const _clock =
    'تاریخ و ساعت دستگاهت درست نیست. '
    'از تنظیمات ← تاریخ و ساعت، «خودکار» را روشن کن (یا درستش کن) و دوباره امتحان کن.';
const _dateSettings = 'تنظیمات تاریخ و ساعت';

const _release = AppRelease(
  versionName: '1.0.58',
  versionCode: 2058,
  minVersionCode: 0,
  size: 52080629,
  sha256: '',
  url: '',
);

/// The seven states of phone-cards-update, as Settings shows them under «اپ».
const _cards = {
  'offered': UpdateOffer(_release),
  'downloading': UpdateOffer(
    _release,
    phase: UpdatePhase.downloading,
    received: 24500000,
  ),
  'ready': UpdateOffer(_release, phase: UpdatePhase.ready),
  'failed': UpdateOffer(_release, error: UpdateError.network),
  'bad file': UpdateOffer(_release, error: UpdateError.checksum),
  'no space': UpdateOffer(_release, error: UpdateError.noSpace),
  'install failed': UpdateOffer(
    _release,
    phase: UpdatePhase.ready,
    error: UpdateError.install,
  ),
};

late _Update _engine;

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool isTV = false,
  Size? size,
  double scale = 1,
  UpdateOffer? offer,
  double navigationBar = 0,
  String language = 'fa',
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize =
        size ?? (isTV ? const Size(1920, 1080) : const Size(824, 1830))
    ..devicePixelRatio = 2
    ..padding = FakeViewPadding(bottom: navigationBar * 2);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  _engine = _Update();
  when(_engine.checkNow).thenAnswer((_) async => null);
  final container = ProviderContainer(
    overrides: [
      noShots,
      shikooStateProvider.overrideWithValue(
        ShikooState(
          connection: ShikooConnection.off,
          connectedFor: Duration.zero,
          isTV: isTV,
          servers: const [],
          service: const ShikooService(
            name: 'user123 · الماس',
            usedBytes: 0,
            totalBytes: 0,
          ),
        ),
      ),
      shikooControllerProvider.overrideWithValue(_Controller()),
      shikooVersionProvider.overrideWithValue('1.0.57'),
      shikooUpdateOfferProvider.overrideWith(() => ShikooCell(offer)),
      shikooUpdateProvider.overrideWithValue(_engine),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      key: UniqueKey(),
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(Brightness.light, tv: isTV),
        home: const ShikooSettings(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The label under the remote: a button's, else the first text inside the focused item.
String? _focused() {
  final element = FocusManager.instance.primaryFocus?.context as Element?;
  if (element == null) return null;
  final button = element.findAncestorWidgetOfExactType<ShikooButton>();
  if (button != null) return button.label;
  String? first;
  void visit(Element child) {
    final widget = child.widget;
    if (first == null && widget is Text) first = widget.data;
    if (first == null) child.visitChildren(visit);
  }

  element.visitChildren(visit);
  return first;
}

Future<String?> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
  return _focused();
}

Future<void> _focus(WidgetTester tester, Finder inside) async {
  final node = Focus.of(
    tester.element(
      find
          .descendant(of: inside.first, matching: find.byType(GestureDetector))
          .first,
    ),
  );
  FocusTraversalGroup.of(node.context!).invalidateScopeData(node.nearestScope!);
  node.requestFocus();
  await tester.pumpAndSettle();
}

/// A press on the card moves it, as the engine would, to a taller state.
const _growths = [('offered', 'downloading'), ('ready', 'install failed')];

void _growOnPress(ProviderContainer container, String to) {
  void grow() =>
      container.read(shikooUpdateOfferProvider.notifier).set(_cards[to]);
  when(_engine.download).thenAnswer((_) async => grow());
  when(_engine.install).thenAnswer((_) async {
    grow();
    return InstallAsk.nothing;
  });
}

double _cardBottom(WidgetTester tester) =>
    tester.getRect(find.byType(UpdateCard)).bottom;

Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Pressable));

Finder get _cardButton => find.descendant(
  of: find.byType(UpdateCard),
  matching: find.byType(ShikooButton),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadShikooFonts();
  });

  testWidgets('the App section names the version, no core (it is in the '
      'report), and nothing under the check yet', (tester) async {
    for (final isTV in [false, true]) {
      await _pump(tester, isTV: isTV);
      expect(find.text('۱.۰.۵۷'), findsOneWidget, reason: 'TV $isTV');
      expect(_row(_check), findsOneWidget);
      expect(_row('درباره'), findsOneWidget);
      for (final line in [_checking, _latest, _failed]) {
        expect(find.text(line), findsNothing);
      }
      expect(find.text('هسته'), findsNothing);
    }
  });

  testWidgets('a press checks now: a spinner while it asks, then the latest '
      'or a red failure, and the row itself asks again', (tester) async {
    for (final isTV in [false, true]) {
      await _pump(tester, isTV: isTV);
      final asked = <Completer<UpdateError?>>[];
      when(_engine.checkNow).thenAnswer((_) {
        asked.add(Completer());
        return asked.last.future;
      });
      Future<void> press() async {
        if (isTV) {
          await _focus(tester, _row(_check));
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
        } else {
          await tester.ensureVisible(find.text(_check));
          await tester.tap(find.text(_check));
        }
        await tester.pump();
      }

      await press();
      expect(find.text(_checking), findsOneWidget, reason: 'TV $isTV');
      expect(
        find.descendant(of: _row(_check), matching: find.byType(Spinner)),
        findsOneWidget,
      );
      if (isTV) expect(_focused(), _check);
      asked.last.complete(null);
      await tester.pumpAndSettle();
      expect(find.text(_latest), findsOneWidget);

      await press();
      asked.last.complete(UpdateError.network);
      await tester.pumpAndSettle();
      final line = tester.widget<Text>(find.text(_failed));
      expect(
        line.style!.color,
        ShikooTheme.of(tester.element(find.text(_failed))).c.danger,
      );
      if (isTV) expect(_focused(), _check);
      verify(_engine.checkNow).called(2);
    }
  });

  testWidgets('a check the device\'s clock spoiled says so in red, with a date '
      'settings row under it; on the TV the remote goes check, it, About', (
    tester,
  ) async {
    for (final isTV in [false, true]) {
      await _pump(tester, isTV: isTV);
      when(_engine.checkNow).thenAnswer((_) async => UpdateError.clock);
      if (isTV) {
        await _focus(tester, _row(_check));
        await _press(tester, LogicalKeyboardKey.select);
      } else {
        await tester.ensureVisible(find.text(_check));
        await tester.tap(find.text(_check));
        await tester.pumpAndSettle();
      }
      expect(
        tester.widget<Text>(find.text(_clock)).style!.color,
        ShikooTheme.of(tester.element(find.text(_clock))).c.danger,
        reason: 'TV $isTV',
      );
      expect(find.text(_failed), findsNothing);
      expect(find.widgetWithText(ShikooButton, _dateSettings), findsNothing);
      final rows = [
        for (final title in [_check, _dateSettings, 'درباره'])
          tester.getRect(_row(title)),
      ];
      expect(rows[0].bottom, lessThanOrEqualTo(rows[1].top));
      expect(rows[1].bottom, lessThanOrEqualTo(rows[2].top));
      expect(rows[1].width, rows[0].width);
      if (!isTV) continue;
      expect(_focused(), _check);
      expect(await _press(tester, LogicalKeyboardKey.arrowDown), _dateSettings);
      expect(await _press(tester, LogicalKeyboardKey.arrowDown), 'درباره');
    }
  });

  testWidgets('in the TV\'s settings column the clock card stacks date '
      'settings over retry, equal in width', (tester) async {
    await _pump(
      tester,
      isTV: true,
      offer: const UpdateOffer(_release, error: UpdateError.clock),
    );
    Rect at(String label) => tester.getRect(
      find.descendant(
        of: find.byType(UpdateCard),
        matching: find.widgetWithText(ShikooButton, label),
      ),
    );
    expect(at(_dateSettings).bottom, lessThan(at('دوباره').top));
    expect(at(_dateSettings).width, at('دوباره').width);
  });

  testWidgets('an update found takes the row\'s place with Home\'s card; on '
      'the TV the remote goes to its button, and up from it to About', (
    tester,
  ) async {
    for (final isTV in [false, true]) {
      final container = await _pump(tester, isTV: isTV);
      when(_engine.checkNow).thenAnswer((_) async {
        container
            .read(shikooUpdateOfferProvider.notifier)
            .set(_cards['offered']);
        return null;
      });
      if (isTV) {
        // By keys, as on a TV: Up must not undo the Down that reached the row.
        expect(
          await _press(tester, LogicalKeyboardKey.arrowDown),
          'سایت‌های ایرانی بدون فیلترشکن',
        );
        expect(await _press(tester, LogicalKeyboardKey.arrowDown), _check);
        await _press(tester, LogicalKeyboardKey.select);
      } else {
        await tester.ensureVisible(find.text(_check));
        await tester.tap(find.text(_check));
        await tester.pumpAndSettle();
      }
      expect(find.byType(UpdateCard), findsOneWidget, reason: 'TV $isTV');
      expect(find.text(_check), findsNothing);
      expect(
        tester.getRect(find.byType(UpdateCard)).top,
        greaterThan(tester.getRect(_row('درباره')).bottom),
        reason: 'under the App card',
      );
      if (!isTV) continue;
      expect(_focused(), 'دریافت');
      expect(await _press(tester, LogicalKeyboardKey.arrowUp), 'درباره');
      expect(
        await _press(tester, LogicalKeyboardKey.arrowUp),
        'سایت‌های ایرانی بدون فیلترشکن',
        reason: 'version and core are only text',
      );
      expect(await _press(tester, LogicalKeyboardKey.arrowDown), 'درباره');
      expect(await _press(tester, LogicalKeyboardKey.arrowDown), 'دریافت');
    }
  });

  testWidgets('in a Windows window a click says the latest, a red failure, '
      'the clock with its date row, then a found update in the row\'s place, '
      'in view and with no ring', (tester) async {
    addTearDown(ringOnKeys());
    final container = await _pump(tester, size: const Size(1728, 984));
    final red = ShikooTheme.of(tester.element(find.text(_check))).c.danger;
    Future<void> press() async {
      await tester.ensureVisible(find.text(_check));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_check), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
    }

    for (final (UpdateError? answer, line) in const [
      (null, _latest),
      (UpdateError.network, _failed),
      (UpdateError.clock, _clock),
    ]) {
      when(_engine.checkNow).thenAnswer((_) async => answer);
      await press();
      expect(
        tester.widget<Text>(find.text(line)).style?.color == red,
        answer != null,
        reason: '$answer',
      );
      expect(
        _row(_dateSettings),
        answer == UpdateError.clock ? findsOneWidget : findsNothing,
      );
    }
    when(_engine.checkNow).thenAnswer((_) async {
      container.read(shikooUpdateOfferProvider.notifier).set(_cards['offered']);
      return null;
    });
    await press();
    expect(find.text(_check), findsNothing);
    expect(find.text('نسخهٔ تازه آمده'), findsOneWidget);
    expect(
      tester.getRect(find.byType(UpdateCard)).bottom,
      lessThanOrEqualTo(492),
    );
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(focused.findAncestorWidgetOfExactType<UpdateCard>(), isNotNull);
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
    verify(_engine.checkNow).called(4);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('on the TV an update or a sign-in coming above the remote '
      'leaves it on its row', (tester) async {
    final container = await _pump(tester, isTV: true);
    await _focus(tester, _row('درباره'));
    for (final offer in [_cards['offered'], null]) {
      container.read(shikooUpdateOfferProvider.notifier).set(offer);
      await tester.pumpAndSettle();
      expect(_focused(), 'درباره', reason: 'offer $offer');
    }
    await _focus(tester, _row('خروج'));
    container
        .read(shikooAccountProvider.notifier)
        .set(const ShikooAccount(who: TelegramAccount(name: 'Sam')));
    await tester.pumpAndSettle();
    expect(_focused(), 'خروج');
  });

  testWidgets('on the TV the remote stops at the check and About only', (
    tester,
  ) async {
    await _pump(tester, isTV: true);
    expect(_focused(), 'خودکار');
    expect(
      await _press(tester, LogicalKeyboardKey.arrowDown),
      'سایت‌های ایرانی بدون فیلترشکن',
    );
    expect(await _press(tester, LogicalKeyboardKey.arrowDown), _check);
    expect(await _press(tester, LogicalKeyboardKey.arrowDown), 'درباره');
  });

  testWidgets('on the TV every card state stays in the safe area at 960×540 '
      'and 1280×720, with font 1.0 and 1.3', (tester) async {
    const tv = ShikooSizes.tv;
    for (final size in const [Size(1920, 1080), Size(2560, 1440)]) {
      for (final scale in const [1.0, 1.3]) {
        for (final MapEntry(key: name, value: offer) in _cards.entries) {
          final why = '$name at ${size / 2} × $scale';
          await _pump(
            tester,
            isTV: true,
            size: size,
            scale: scale,
            offer: offer,
          );
          expect(tester.takeException(), isNull, reason: why);
          await _focus(tester, _cardButton);
          final card = tester.getRect(find.byType(UpdateCard));
          final screen = size / 2;
          expect(card.left, greaterThanOrEqualTo(tv.safeX - 0.5), reason: why);
          expect(
            card.right,
            lessThanOrEqualTo(screen.width - tv.safeX + 0.5),
            reason: why,
          );
          expect(
            card.bottom,
            lessThanOrEqualTo(screen.height - tv.safeY + 0.5),
            reason: why,
          );
        }
      }
    }
  });

  testWidgets('a card the remote pressed stays in the safe area as it grows: '
      'the bar of a started download, the line of a failed installer', (
    tester,
  ) async {
    const tv = ShikooSizes.tv;
    for (final (from, to) in _growths) {
      final container = await _pump(tester, isTV: true, offer: _cards[from]);
      _growOnPress(container, to);
      await _focus(tester, _cardButton);
      await _press(tester, LogicalKeyboardKey.select);
      expect(_focused(), isNot('دریافت'), reason: '$from to $to');
      expect(
        tester.getRect(find.byType(UpdateCard)).bottom,
        lessThanOrEqualTo(540 - tv.safeY + 0.5),
        reason: '$from to $to',
      );
    }
  });

  testWidgets('on a phone the card a press found, then a press grew, stays '
      'above the navigation bar', (tester) async {
    for (final scale in const [1.0, 1.45]) {
      for (final (from, to) in _growths) {
        final why = '$from to $to, font $scale';
        final container = await _pump(
          tester,
          size: const Size(720, 1600),
          scale: scale,
          navigationBar: 48,
        );
        when(_engine.checkNow).thenAnswer((_) async {
          container.read(shikooUpdateOfferProvider.notifier).set(_cards[from]);
          return null;
        });
        _growOnPress(container, to);
        await tester.dragUntilVisible(
          find.text(_check),
          find.byType(SingleChildScrollView),
          const Offset(0, -40),
        );
        await tester.tap(find.text(_check));
        await tester.pumpAndSettle();
        expect(_cardBottom(tester), lessThanOrEqualTo(800 - 48), reason: why);
        await tester.tap(_cardButton);
        await tester.pumpAndSettle();
        expect(find.text('دریافت'), findsNothing, reason: why);
        expect(_cardBottom(tester), lessThanOrEqualTo(800 - 48), reason: why);
      }
    }
  });

  testWidgets('on a phone the card a press found scrolls into view; one the '
      'page opened with leaves the page where it was', (tester) async {
    const phone = Size(720, 1600);
    for (final scale in const [1.0, 1.45]) {
      final container = await _pump(tester, size: phone, scale: scale);
      when(_engine.checkNow).thenAnswer((_) async {
        container
            .read(shikooUpdateOfferProvider.notifier)
            .set(_cards['install failed']);
        return null;
      });
      await tester.dragUntilVisible(
        find.text(_check),
        find.byType(SingleChildScrollView),
        const Offset(0, -40),
      );
      await tester.tap(find.text(_check));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(UpdateCard)).bottom,
        lessThanOrEqualTo(800),
        reason: 'font $scale',
      );

      await _pump(
        tester,
        size: phone,
        scale: scale,
        offer: _cards['install failed'],
      );
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scroll.position.pixels, 0, reason: 'font $scale');
    }
  });

  testWidgets('on a small phone with large text nothing overflows', (
    tester,
  ) async {
    const small = Size(720, 1600);
    await _pump(tester, size: small, scale: 1.45);
    expect(tester.takeException(), isNull);
    when(_engine.checkNow).thenAnswer((_) async => UpdateError.network);
    await tester.ensureVisible(find.text(_check));
    await tester.tap(find.text(_check));
    await tester.pumpAndSettle();
    expect(find.text(_failed), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final MapEntry(key: name, value: offer) in _cards.entries) {
      await _pump(tester, size: small, scale: 1.45, offer: offer);
      expect(tester.takeException(), isNull, reason: name);
    }
  });

  testWidgets('on the TV the page scrolls in its own column: room for the ring '
      'past the pane, and once scrolled a thumb', (tester) async {
    await _pump(
      tester,
      isTV: true,
      size: const Size(1920, 1080),
      scale: 1.3,
      offer: _cards['install failed'],
    );
    RawScrollbar bar() => tester.widget(find.byType(RawScrollbar));
    final column = tester.getRect(find.byType(TvScrollColumn));
    expect(
      tester.getRect(find.byType(Scrollable)),
      column.inflate(Space.s2),
      reason: 'a ring at the pane\x27s edge is not clipped',
    );
    expect(bar().thumbVisibility, isFalse);
    await _focus(tester, _cardButton);
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
    );
    expect(bar().thumbVisibility, isTrue);
  });

  test('red text reads on every surface it sits on, the remote\x27s too: at '
      'least 4.5:1', () {
    double contrast(Color a, Color b) {
      final [dark, light] = [a.computeLuminance(), b.computeLuminance()]
        ..sort();
      return (light + 0.05) / (dark + 0.05);
    }

    for (final c in [ShikooColors.light, ShikooColors.dark]) {
      for (final ground in [c.bg, c.surface, c.focusBg]) {
        expect(
          contrast(c.danger, ground),
          greaterThanOrEqualTo(4.5),
          reason: '${c.danger} on $ground',
        );
      }
    }
  });

  testWidgets(
    '«GPL-3.0» under About never breaks over two lines, by Unicode\x27s '
    'own rule (no break between a hyphen and a digit)',
    (tester) async {
      for (final language in ['fa', 'en']) {
        await _pump(tester, language: language);
        final finder = find.byWidgetPredicate(
          (widget) => widget is Text && (widget.data?.contains('GPL') ?? false),
        );
        final text = tester.widget<Text>(finder);
        final context = tester.element(finder);
        final data = text.data!;
        final start = data.indexOf('GPL');
        for (final scale in const [1.0, 1.45, 2.0]) {
          for (var width = 120.0; width <= 480; width += 1) {
            final painter = TextPainter(
              text: TextSpan(
                text: data,
                style: DefaultTextStyle.of(context).style.merge(text.style),
              ),
              textDirection: Directionality.of(context),
              textScaler: TextScaler.linear(scale),
            )..layout(maxWidth: width);
            expect(
              painter.getLineBoundary(TextPosition(offset: start)).end,
              greaterThanOrEqualTo(start + 'GPL-3.0'.length),
              reason: '$language at $width × $scale',
            );
            painter.dispose();
          }
        }
      }
    },
  );
}
