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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Update extends Mock implements ShikooUpdate {}

class _Controller extends Mock implements ShikooController {}

const _check = 'بررسی به‌روزرسانی';
const _checking = 'در حال بررسی…';
const _latest = 'نسخهٔ تو تازه‌ترین است.';
const _failed = 'بررسی نشد؛ اینترنت را بررسی کن و دوباره بزن.';
const _core = '\u2066FlClash\u00A0$flclashVersion\u2069';

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
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize =
        size ?? (isTV ? const Size(1920, 1080) : const Size(824, 1830))
    ..devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  _engine = _Update();
  when(_engine.checkNow).thenAnswer((_) async => true);
  final container = ProviderContainer(
    overrides: [
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
        locale: const Locale('fa'),
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

  testWidgets('the App section names the version and the core, with nothing '
      'under the check yet', (tester) async {
    for (final isTV in [false, true]) {
      await _pump(tester, isTV: isTV);
      expect(find.text('۱.۰.۵۷'), findsOneWidget, reason: 'TV $isTV');
      expect(find.text(_core), findsOneWidget);
      expect(find.text('همراه خودِ برنامه به‌روز می‌شود.'), findsOneWidget);
      expect(_row(_check), findsOneWidget);
      expect(_row('درباره'), findsOneWidget);
      for (final line in [_checking, _latest, _failed]) {
        expect(find.text(line), findsNothing);
      }
      expect(
        _row('هسته'),
        findsNothing,
        reason: 'the version and the core are only text',
      );
    }
  });

  testWidgets('a press checks now: a spinner while it asks, then the latest '
      'or a red failure, and the row itself asks again', (tester) async {
    for (final isTV in [false, true]) {
      await _pump(tester, isTV: isTV);
      final asked = <Completer<bool>>[];
      when(_engine.checkNow).thenAnswer((_) {
        asked.add(Completer());
        return asked.last.future;
      });
      Future<void> press() async {
        if (isTV) {
          await _focus(tester, _row(_check));
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
        } else {
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
      asked.last.complete(true);
      await tester.pumpAndSettle();
      expect(find.text(_latest), findsOneWidget);

      await press();
      asked.last.complete(false);
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
        return true;
      });
      if (isTV) {
        // By keys, as on a TV: Up must not undo the Down that reached the row.
        await _press(tester, LogicalKeyboardKey.arrowLeft);
        expect(await _press(tester, LogicalKeyboardKey.arrowDown), _check);
        await _press(tester, LogicalKeyboardKey.select);
      } else {
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
      expect(await _press(tester, LogicalKeyboardKey.arrowDown), 'دریافت');
    }
  });

  testWidgets('on the TV the remote stops at the check and About only', (
    tester,
  ) async {
    await _pump(tester, isTV: true);
    expect(_focused(), 'خودکار');
    expect(await _press(tester, LogicalKeyboardKey.arrowLeft), 'فارسی');
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

  testWidgets('a card that grows under the remote stays in the safe area: '
      'the bar of a started download, the line of a failed installer', (
    tester,
  ) async {
    const tv = ShikooSizes.tv;
    for (final (from, to) in [
      ('offered', 'downloading'),
      ('ready', 'install failed'),
    ]) {
      final container = await _pump(tester, isTV: true, offer: _cards[from]);
      await _focus(tester, _cardButton);
      container.read(shikooUpdateOfferProvider.notifier).set(_cards[to]);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(UpdateCard)).bottom,
        lessThanOrEqualTo(540 - tv.safeY + 0.5),
        reason: '$from to $to',
      );
    }
  });

  testWidgets('on a small phone with large text nothing overflows, and the '
      'core\'s version goes under its label', (tester) async {
    const small = Size(720, 1600);
    await _pump(tester, size: small, scale: 1.45);
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.text(_core)).top,
      greaterThan(tester.getRect(find.text('هسته')).bottom),
    );
    when(_engine.checkNow).thenAnswer((_) async => false);
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
}
