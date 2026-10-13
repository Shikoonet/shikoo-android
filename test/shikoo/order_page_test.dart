import 'dart:async';

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/order.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/order.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShikooService _service(int id, String name, {int used = 0}) =>
    ShikooService(id: id, name: name, usedBytes: used, totalBytes: 1 << 30);

final _diamond = _service(1, 'user111 · الماس');
final _gold = _service(2, 'user222 · طلایی');
final _silver = _service(3, 'user333 · نقره‌ای');
final _usedUp = _service(4, 'user444 · برنزی', used: 2 << 30);

/// [_gold] is in use and connected; [_usedUp] stays in the finished row, off this screen.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool isTV = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = isTV ? const Size(1920, 1080) : const Size(824, 1830)
    ..devicePixelRatio = 2;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final container = ProviderContainer(
    overrides: [
      shikooStateProvider.overrideWithValue(
        ShikooState(
          connection: ShikooConnection.on,
          connectedFor: Duration.zero,
          isTV: isTV,
          servers: const [],
          service: _gold,
          others: [_diamond, _silver, _usedUp],
        ),
      ),
      serviceOrderProvider.overrideWith(
        (ref) => inOrder(ref.watch(savedOrderProvider), [1, 2, 3, 4]),
      ),
    ],
  );
  addTearDown(container.dispose);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: navigator,
        locale: const Locale('fa'),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(Brightness.light, tv: isTV),
        home: const SizedBox.shrink(),
      ),
    ),
  );
  unawaited(
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const ServiceOrder()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

List<String> _names(WidgetTester tester) => [
  for (final name in tester.widgetList<ServiceName>(find.byType(ServiceName)))
    name.name,
];

Future<List<String>?> _stored() async =>
    (await SharedPreferences.getInstance()).getStringList(shikooOrderKey);

Finder _inUseOn(int id) => find.descendant(
  of: find.byKey(ValueKey(id)),
  matching: find.text('در حال استفاده'),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadShikooFonts();
  });

  test('an order keeps its saved ids that still exist, then the rest', () {
    expect(inOrder([3, 9, 1], [1, 2, 3]), [3, 1, 2]);
    expect(inOrder([], [1, 2]), [1, 2]);
  });

  testWidgets('on the phone ≡ drags a card and the drop is saved at once; the '
      'in-use mark goes with its card', (tester) async {
    final container = await _pump(tester);
    expect(_names(tester), [_diamond.name, _gold.name, _silver.name]);
    expect(find.textContaining('هر سرویس را با ≡ بگیر'), findsOneWidget);
    expect(_inUseOn(2), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'کشیدن «user111 · الماس» برای جابه‌جایی',
      ),
      findsOneWidget,
    );

    final handle = find.byWidgetPredicate(
      (w) => w is ReorderableDragStartListener && w.index == 0,
    );
    // The list gives the second place once the dragged card's top is past the second card.
    final step =
        tester.getCenter(find.byKey(const ValueKey(3))).dy -
        tester.getTopLeft(find.byKey(const ValueKey(1))).dy +
        5;
    final drag = await tester.startGesture(tester.getCenter(handle));
    await drag.moveBy(const Offset(0, 10));
    await tester.pump();
    await drag.moveBy(Offset(0, step - 10));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(_names(tester), [_gold.name, _diamond.name, _silver.name]);
    expect(container.read(serviceOrderProvider), [2, 1, 3, 4]);
    expect(await _stored(), ['2', '1', '3']);
    expect(_inUseOn(2), findsOneWidget);
  });

  testWidgets('on the TV OK picks a card up, up and down carry it and OK puts '
      'it down; Back puts it back, and Back again leaves', (tester) async {
    final container = await _pump(tester, isTV: true);
    expect(find.text('تأیید: برداشتن برای جابه‌جایی'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.text('در حال جابه‌جایی'), findsOneWidget);
    expect(
      find.text('بالا و پایین: جابه‌جا کردن · تأیید: گذاشتن · بازگشت: لغو'),
      findsOneWidget,
    );
    final picked = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const ValueKey(1)),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (picked.decoration! as ShapeDecoration).color,
      ShikooColors.light.picked,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_names(tester), [_gold.name, _diamond.name, _silver.name]);
    expect(await _stored(), isNull, reason: 'saved only when put down');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(_names(tester), [_diamond.name, _gold.name, _silver.name]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.text('در حال جابه‌جایی'), findsNothing);
    expect(_names(tester), [_gold.name, _silver.name, _diamond.name]);
    expect(container.read(serviceOrderProvider), [2, 3, 1, 4]);
    expect(await _stored(), ['2', '3', '1']);
    expect(_inUseOn(2), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(_names(tester), [_gold.name, _diamond.name, _silver.name]);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ServiceOrder), findsOneWidget);
    expect(find.text('در حال جابه‌جایی'), findsNothing);
    expect(_names(tester), [_gold.name, _silver.name, _diamond.name]);
    expect(await _stored(), ['2', '3', '1']);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ServiceOrder), findsNothing);
  });
}
