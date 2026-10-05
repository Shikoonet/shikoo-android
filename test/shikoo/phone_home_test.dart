import 'dart:async';

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Controller extends Mock implements ShikooController {}

const _noService = ShikooState(
  connection: ShikooConnection.off,
  connectedFor: Duration.zero,
  isTV: false,
  servers: [],
);

const _servers = [
  ShikooServer(name: 'هلند ۱', type: 'Vless', ping: 71),
  ShikooServer(name: 'آلمان ۲', type: 'Vless', ping: 88),
  ShikooServer(name: 'آلمان ۱', type: 'Vless', ping: 142),
];

ShikooState _phone({
  List<ShikooServer> servers = _servers,
  bool isTV = false,
}) => ShikooState(
  connection: ShikooConnection.off,
  connectedFor: Duration.zero,
  isTV: isTV,
  service: ShikooService(
    name: 'user123 · الماس',
    usedBytes: 33 << 30,
    totalBytes: 100 << 30,
    expire: DateTime(2026, 10, 26, 12),
    updatedAt: DateTime.now(),
  ),
  servers: servers,
  selected: 'آلمان ۲',
);

/// Swapping the state through one ProviderScope keeps the page as it was.
Future<ValueNotifier<ShikooState>> _pump(
  WidgetTester tester,
  ShikooState state, {
  String locale = 'fa',
  ShikooController? controller,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = state.isTV ? const Size(1920, 1080) : const Size(824, 1830)
    ..devicePixelRatio = 2;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final holder = ValueNotifier(state);
  addTearDown(holder.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        shikooVersionProvider.overrideWithValue('1.0.0'),
        if (controller != null)
          shikooControllerProvider.overrideWithValue(controller),
        shikooStateProvider.overrideWith((ref) {
          void changed() => ref.invalidateSelf();
          holder.addListener(changed);
          ref.onDispose(() => holder.removeListener(changed));
          return holder.value;
        }),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(Brightness.light, tv: state.isTV),
        home: const ShikooHome(),
      ),
    ),
  );
  await tester.pump();
  return holder;
}

/// How many times the app read the clipboard, which holds [text].
ValueGetter<int> _clipboard(WidgetTester tester, String text) {
  var reads = 0;
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method != 'Clipboard.getData') return null;
    reads++;
    return {'text': text};
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return () => reads;
}

Finder _icon(ShikooIcon icon) =>
    find.byWidgetPredicate((w) => w is SvgIcon && w.icon == icon);

List<String> _rowOrder(WidgetTester tester) => [
  for (final row in tester.widgetList<ServerRow>(find.byType(ServerRow)))
    row.server.name,
];

void main() {
  testWidgets('on the phone renew and support open Telegram with no QR icon, '
      'and the update is an icon alone', (tester) async {
    await _pump(tester, _phone());
    for (final label in ['تمدید', 'پشتیبانی']) {
      final button = tester.widget<ShikooButton>(
        find.widgetWithText(ShikooButton, label),
      );
      expect(button.icon, isNull, reason: label);
    }
    expect(_icon(ShikooIcon.qr), findsNothing);
    expect(find.text('به‌روزرسانی'), findsNothing);
    expect(find.bySemanticsLabel('به‌روزرسانی سرورها'), findsOneWidget);
  });

  testWidgets('the arrow folds the card to one line, and back', (tester) async {
    await _pump(tester, _phone());
    await tester.tap(_icon(ShikooIcon.chevronUp));
    await tester.pumpAndSettle();
    expect(find.byType(ServerRow), findsNothing);
    expect(find.text('تمدید'), findsNothing);
    expect(
      find.text(
        'مصرف شده: ۳۳ از ۱۰۰ گیگ · اعتبار تا ۴ آبان ۱۴۰۵',
        findRichText: true,
      ),
      findsOneWidget,
    );

    await tester.tap(_icon(ShikooIcon.chevronDown));
    await tester.pumpAndSettle();
    expect(find.byType(ServerRow), findsNWidgets(3));
  });

  testWidgets('a server the last update brought says "new" on the phone only', (
    tester,
  ) async {
    const servers = [
      ShikooServer(name: 'هلند ۳', type: 'Vless', ping: 76, fresh: true),
      ..._servers,
    ];
    await _pump(tester, _phone(servers: servers));
    expect(find.text('تازه'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ServerRow, 'هلند ۳'),
        matching: find.text('تازه'),
      ),
      findsOneWidget,
    );
    await _pump(tester, _phone(servers: servers, isTV: true));
    expect(find.text('تازه'), findsNothing);
  });

  testWidgets('a finger on the list holds its order until it lifts', (
    tester,
  ) async {
    final holder = await _pump(tester, _phone());
    final finger = await tester.startGesture(
      tester.getCenter(find.text('آلمان ۱')),
    );
    holder.value = _phone(servers: _servers.reversed.toList());
    await tester.pump();
    expect(_rowOrder(tester), ['هلند ۱', 'آلمان ۲', 'آلمان ۱']);

    await finger.up();
    await tester.pump();
    expect(_rowOrder(tester), ['آلمان ۱', 'آلمان ۲', 'هلند ۱']);
  });

  testWidgets(
    'search narrows the list in ping order, and the cross clears it',
    (tester) async {
      await _pump(tester, _phone());
      expect(find.text('جست‌وجوی سرور'), findsOneWidget);
      expect(find.text('سریع‌ترین بالا', findRichText: true), findsNothing);

      await tester.enterText(find.byType(TextField), 'آلمان');
      await tester.pump();
      expect(_rowOrder(tester), ['آلمان ۲', 'آلمان ۱']);

      await tester.enterText(find.byType(TextField), 'فرانسه');
      await tester.pump();
      expect(find.byType(ServerRow), findsNothing);
      expect(find.text('سروری با این نام نیست'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('پاک کردن جست‌وجو'));
      await tester.pump();
      expect(find.byType(ServerRow), findsNWidgets(3));
      expect(find.bySemanticsLabel('پاک کردن جست‌وجو'), findsNothing);
    },
  );

  test('a search typed with Arabic letters or Latin digits still matches', () {
    expect(serverMatches('آلمان ۲', 'المان 2'), isTrue);
    expect(serverMatches('ترکیه ۱', 'تركيه'), isTrue);
    expect(serverMatches('USA 1', 'usa'), isTrue);
    expect(serverMatches('آلمان ۲', 'آلمان ۱'), isFalse);
    expect(serverMatches('هلند ۱', '  '), isTrue);
    expect(serverMatches('ترکیه ۱', 'ترکیه۱'), isTrue);
    expect(serverMatches('آلمان ۲', 'أَلمان'.replaceAll('\u064E', '')), isTrue);
    expect(serverMatches('ایتالیا', 'إیتالیا'), isTrue);
    expect(serverMatches('سرور ویژه', 'سرور ويژة'), isTrue);
    expect(serverMatches('سوئدی', 'سوئدى'), isTrue);
    expect(serverMatches('نیم\u200Cفاصله ۱', 'نیم فاصله'), isTrue);
  });

  testWidgets("the phone's settings have a back arrow, mirrored in English", (
    tester,
  ) async {
    for (final (locale, mirrored) in [('fa', 1.0), ('en', -1.0)]) {
      await _pump(tester, _phone(), locale: locale);
      await tester.tap(_icon(ShikooIcon.gear));
      await tester.pumpAndSettle();
      expect(find.byType(ShikooSettings), findsOneWidget);
      final arrow = find.ancestor(
        of: _icon(ShikooIcon.back),
        matching: find.byType(Transform),
      );
      expect(
        tester.widget<Transform>(arrow.first).transform.storage[0],
        mirrored,
        reason: locale,
      );
      await tester.tap(_icon(ShikooIcon.back));
      await tester.pumpAndSettle();
      expect(find.byType(ShikooSettings), findsNothing, reason: locale);
    }
  });

  testWidgets('the phone with no service reads the clipboard only on a press, '
      'and names each failure above the button', (tester) async {
    const clip = 'https://s.4g3.uk/sub/secret-token';
    final reads = _clipboard(tester, clip);
    final controller = _Controller();
    final answer = Completer<ShikooPasteError?>();
    when(() => controller.pasteService(any())).thenAnswer((_) => answer.future);
    await _pump(tester, _noService, controller: controller);
    expect(reads(), 0);
    expect(
      tester.getTopLeft(find.text('چسباندن لینک اشتراک')).dy,
      lessThan(tester.getTopLeft(find.text('پشتیبانی')).dy),
      reason: 'paste leads, Support follows',
    );
    expect(
      tester
          .widget<ShikooButton>(
            find.widgetWithText(ShikooButton, 'چسباندن لینک اشتراک'),
          )
          .primary,
      isTrue,
    );
    expect(find.textContaining('«چسباندن لینک اشتراک» را بزن'), findsOneWidget);

    await tester.tap(find.text('چسباندن لینک اشتراک'));
    await tester.pump();
    expect(reads(), 1);
    verify(() => controller.pasteService(clip)).called(1);
    expect(find.text('در حال بررسی لینک…'), findsOneWidget);
    answer.complete(ShikooPasteError.empty);
    await tester.pumpAndSettle();

    for (final (error, strong) in [
      (ShikooPasteError.empty, 'کلیپ‌بورد خالی است.'),
      (ShikooPasteError.notShikoo, 'این لینک شیکونت نیست.'),
      (ShikooPasteError.revoked, 'این لینک باطل شده یا منقضی است.'),
      (ShikooPasteError.unavailable, 'لینک الان باز نشد.'),
      (ShikooPasteError.offline, 'اینترنت وصل نیست.'),
    ]) {
      when(() => controller.pasteService(any())).thenAnswer((_) async => error);
      await tester.tap(find.text('چسباندن لینک اشتراک'));
      await tester.pumpAndSettle();
      final message = find.textContaining(strong, findRichText: true);
      expect(message, findsOneWidget, reason: error.name);
      expect(
        tester.getBottomLeft(message).dy,
        lessThan(tester.getTopLeft(find.text('چسباندن لینک اشتراک')).dy),
        reason: 'above the button that made it',
      );
      expect(find.textContaining('secret-token'), findsNothing);
    }

    final last = Completer<ShikooPasteError?>();
    when(() => controller.pasteService(any())).thenAnswer((_) => last.future);
    await tester.tap(find.text('چسباندن لینک اشتراک'));
    await tester.pump();
    expect(
      find.textContaining('اینترنت وصل نیست.'),
      findsNothing,
      reason: 'the next paste clears the last refusal',
    );
    last.complete(null);
    await tester.pumpAndSettle();
    expect(find.textContaining('اینترنت وصل نیست.'), findsNothing);
  });

  testWidgets("the phone's settings paste another link above log out, show a "
      'refusal over the card, and go home once it is in', (tester) async {
    _clipboard(tester, 'https://example.com/sub/x');
    final controller = _Controller();
    when(
      () => controller.pasteService(any()),
    ).thenAnswer((_) async => ShikooPasteError.notShikoo);
    await _pump(tester, _phone(), controller: controller);
    await tester.tap(_icon(ShikooIcon.gear));
    await tester.pumpAndSettle();
    final paste = find.text('چسباندن لینک دیگر');
    expect(find.text('برای سرویس دیگری که داری'), findsOneWidget);
    expect(
      tester.getTopLeft(paste).dy,
      lessThan(tester.getTopLeft(find.text('خروج')).dy),
    );

    await tester.tap(paste);
    await tester.pump();
    final refusal = find.textContaining(
      'این لینک شیکونت نیست.',
      findRichText: true,
    );
    expect(refusal, findsOneWidget);
    expect(
      tester.getBottomLeft(refusal).dy,
      lessThan(tester.getTopLeft(paste).dy),
    );

    when(() => controller.pasteService(any())).thenAnswer((_) async => null);
    await tester.tap(paste);
    await tester.pumpAndSettle();
    expect(find.byType(ShikooSettings), findsNothing);
  });

  testWidgets('the app is called ShikooNet, شیکونت in Persian', (tester) async {
    for (final (locale, name) in [('fa', 'شیکونت'), ('en', 'ShikooNet')]) {
      await _pump(tester, _phone(), locale: locale);
      expect(find.text(name), findsOneWidget, reason: locale);
    }
  });

  testWidgets(
    'with no usage header, no volume, validity or status is made up',
    (tester) async {
      final state = _phone();
      await _pump(
        tester,
        ShikooState(
          connection: state.connection,
          connectedFor: state.connectedFor,
          isTV: false,
          servers: state.servers,
          selected: state.selected,
          service: const ShikooService(
            name: 'user123 · الماس',
            usedBytes: 0,
            totalBytes: 0,
            usageKnown: false,
          ),
        ),
      );
      expect(find.text('user123 · الماس'), findsOneWidget);
      expect(find.text('فعال'), findsNothing);
      expect(find.textContaining('نامحدود', findRichText: true), findsNothing);
      expect(find.textContaining('مصرف شده', findRichText: true), findsNothing);
      expect(find.byType(ServerRow), findsNWidgets(3));
    },
  );

  testWidgets('the search lets go of focus with the keyboard or a tap '
      'elsewhere, and settings never bring it back', (tester) async {
    await _pump(tester, _phone());
    bool searching() => tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode
        .hasFocus;

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(searching(), isTrue);
    await tester.tap(find.text('شیکونت'));
    await tester.pump();
    expect(searching(), isFalse, reason: 'a tap outside the field');

    await tester.tap(find.byType(TextField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    await tester.pump();
    expect(searching(), isTrue);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(searching(), isFalse, reason: 'Back closed the keyboard');

    await tester.ensureVisible(_icon(ShikooIcon.gear));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.tap(_icon(ShikooIcon.gear));
    await tester.pumpAndSettle();
    await tester.tap(_icon(ShikooIcon.back));
    await tester.pumpAndSettle();
    expect(searching(), isFalse, reason: 'back from settings');
  });

  testWidgets('the home and settings run on under the gesture bar, with room '
      'to scroll the last row above it', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 48);
    await _pump(
      tester,
      _phone(
        servers: [
          for (var i = 1; i <= 12; i++)
            ShikooServer(name: 'سرور $i', type: 'Vless', ping: 80 + i),
        ],
      ),
    );
    double bottomOf(Finder f) => tester.getBottomLeft(f.first).dy;
    expect(bottomOf(find.byType(SingleChildScrollView)), 915);
    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView).first,
    );
    expect(scroll.padding?.vertical, Space.s6 + 24);

    await tester.tap(_icon(ShikooIcon.gear));
    await tester.pumpAndSettle();
    expect(
      bottomOf(
        find.descendant(
          of: find.byType(ShikooSettings),
          matching: find.byType(SingleChildScrollView),
        ),
      ),
      915,
    );
  });

  testWidgets('a folded card opens with a tap anywhere but its update button', (
    tester,
  ) async {
    final controller = _Controller();
    when(controller.refreshService).thenAnswer((_) async {});
    await _pump(tester, _phone(), controller: controller);
    await tester.tap(_icon(ShikooIcon.chevronUp));
    await tester.pumpAndSettle();
    expect(find.byType(FoldedServiceCard), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('به‌روزرسانی سرورها'));
    await tester.pumpAndSettle();
    verify(controller.refreshService).called(1);
    expect(find.byType(FoldedServiceCard), findsOneWidget, reason: 'update');

    await tester.tap(find.textContaining('مصرف شده', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.byType(FoldedServiceCard), findsNothing);
    expect(find.byType(ServerRow), findsNWidgets(3));

    await tester.tap(_icon(ShikooIcon.chevronUp));
    await tester.pumpAndSettle();
    await tester.tap(find.text('user123 · الماس'));
    await tester.pumpAndSettle();
    expect(find.byType(ServerRow), findsNWidgets(3), reason: 'the name');
  });

  testWidgets('other services fold under the one in use, and a tap on one '
      'puts it in use', (tester) async {
    final controller = _Controller();
    final state = _phone();
    await _pump(
      tester,
      ShikooState(
        connection: state.connection,
        connectedFor: state.connectedFor,
        isTV: false,
        servers: state.servers,
        selected: state.selected,
        service: state.service,
        others: [
          ShikooService(
            id: 7,
            name: 'user789 · معمولی',
            usedBytes: (49.8 * (1 << 30)).round(),
            totalBytes: 50 << 30,
            expire: DateTime(2026, 12, 1, 12),
          ),
        ],
      ),
      controller: controller,
    );
    expect(find.byType(FoldedServiceCard), findsOneWidget);
    final folded = find.text('user789 · معمولی');
    expect(
      tester.getTopLeft(folded).dy,
      greaterThan(tester.getBottomLeft(find.byType(ServerRow).last).dy),
    );
    await tester.ensureVisible(folded);
    await tester.tap(folded);
    verify(() => controller.selectService(7)).called(1);
  });

  testWidgets('on the TV another service is one remote item under the list, '
      'and OK puts it in use', (tester) async {
    final controller = _Controller();
    final state = _phone(isTV: true);
    await _pump(
      tester,
      ShikooState(
        connection: state.connection,
        connectedFor: state.connectedFor,
        isTV: true,
        servers: state.servers,
        selected: state.selected,
        service: state.service,
        others: const [
          ShikooService(
            id: 7,
            name: 'user789 · معمولی',
            usedBytes: 0,
            totalBytes: 0,
          ),
        ],
      ),
      controller: controller,
    );
    Focus.of(
      tester.element(
        find
            .descendant(
              of: find.widgetWithText(ServerRow, 'آلمان ۱'),
              matching: find.byType(GestureDetector),
            )
            .first,
      ),
    ).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<FoldedServiceCard>(),
      isNotNull,
    );
    expect(find.text('تازه'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    verify(() => controller.selectService(7)).called(1);
  });

  testWidgets('a used-up or expired service rests the power button and asks '
      'for renewal, on the phone and the TV', (tester) async {
    ShikooState ended({
      required int used,
      DateTime? expire,
      bool isTV = false,
      ShikooConnection connection = ShikooConnection.off,
      List<ShikooService> others = const [],
    }) => ShikooState(
      connection: connection,
      connectedFor: Duration.zero,
      isTV: isTV,
      servers: _servers,
      selected: 'آلمان ۲',
      service: ShikooService(
        name: 'user123 · الماس',
        usedBytes: used << 30,
        totalBytes: 100 << 30,
        expire: expire ?? DateTime(2099),
      ),
      others: others,
    );

    await _pump(tester, ended(used: 100));
    final power = tester.widget<PowerButton>(find.byType(PowerButton));
    expect(power.onPressed, isNull);
    expect(find.text('حجم تمام شده'), findsNWidgets(2), reason: 'chip, button');
    expect(find.text('با «تمدید» دوباره وصل می‌شوی.'), findsOneWidget);
    expect(find.byType(NowPill), findsNothing);
    expect(find.byType(ServerRow), findsNothing);
    expect(find.text('فهرست سرورها بعد از تمدید برمی‌گردد.'), findsOneWidget);
    final left = find.textContaining('باقی‌مانده:', findRichText: true);
    final spans = <TextSpan>[];
    tester.widget<RichText>(left).text.visitChildren((span) {
      if (span is TextSpan && (span.text ?? '').contains('۰')) spans.add(span);
      return true;
    });
    expect(spans.single.style?.color, ShikooColors.light.danger);

    final lastMonth = DateTime.now().subtract(const Duration(days: 30));
    await _pump(
      tester,
      ended(
        used: 58,
        expire: lastMonth,
        others: [
          ShikooService(
            id: 9,
            name: 'user456 · طلایی',
            usedBytes: 1,
            totalBytes: 100,
            expire: lastMonth,
          ),
        ],
      ),
    );
    expect(find.text('اعتبار تمام شده'), findsOneWidget);
    expect(find.text('تمام شده'), findsOneWidget);
    expect(
      find.textContaining('تمام شد. با تمدید دوباره فعال می‌شود.'),
      findsOneWidget,
      reason: 'the folded expired service',
    );

    await _pump(
      tester,
      ended(used: 58, expire: lastMonth, connection: ShikooConnection.on),
    );
    expect(
      tester.widget<PowerButton>(find.byType(PowerButton)).onPressed,
      isNotNull,
      reason: 'a live tunnel can still be stopped',
    );

    await _pump(tester, ended(used: 100, isTV: true));
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<ShikooButton>()
          ?.label,
      'تمدید',
      reason: 'tv-power-states: the remote starts on renew',
    );
  });

  testWidgets('rows slide to a new order rather than jump', (tester) async {
    final holder = await _pump(tester, _phone());
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await tester.pump();
    double top(String name) =>
        tester.getTopLeft(find.widgetWithText(ServerRow, name)).dy;
    final from = top('آلمان ۱');
    final to = top('هلند ۱');

    holder.value = _phone(servers: _servers.reversed.toList());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(top('آلمان ۱'), allOf(lessThan(from), greaterThan(to)));
    await tester.pumpAndSettle();
    expect(top('آلمان ۱'), to);
  });

  testWidgets('on the TV, down from renew of a used-up service reaches the '
      'services under it', (tester) async {
    final controller = _Controller();
    await _pump(
      tester,
      const ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: true,
        servers: _servers,
        service: ShikooService(
          name: 'user246 · طلایی',
          usedBytes: 100,
          totalBytes: 100,
        ),
        others: [
          ShikooService(
            id: 7,
            name: 'user789 · معمولی',
            usedBytes: 0,
            totalBytes: 0,
          ),
        ],
      ),
      controller: controller,
    );
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<ShikooButton>()
          ?.label,
      'تمدید',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<FoldedServiceCard>(),
      isNotNull,
    );
  });

  testWidgets('from 90% used, what is left turns amber', (tester) async {
    TextStyle? left() {
      TextStyle? style;
      final rich = find.textContaining('باقی‌مانده:', findRichText: true);
      tester.widget<RichText>(rich).text.visitChildren((span) {
        if (span is TextSpan && (span.text ?? '').contains('گیگ')) {
          style = span.style;
        }
        return true;
      });
      return style;
    }

    ShikooState using(int used) => ShikooState(
      connection: ShikooConnection.off,
      connectedFor: Duration.zero,
      isTV: false,
      servers: _servers,
      selected: 'آلمان ۲',
      service: ShikooService(
        name: 'user123 · الماس',
        usedBytes: used << 30,
        totalBytes: 100 << 30,
      ),
    );

    await _pump(tester, using(89));
    expect(left()?.color, isNot(ShikooColors.light.warning));
    await _pump(tester, using(90));
    expect(left()?.color, ShikooColors.light.warning);
  });

  testWidgets('a service name leads with its username in either language', (
    tester,
  ) async {
    for (final (locale, direction) in [
      ('fa', TextDirection.rtl),
      ('en', TextDirection.ltr),
    ]) {
      await _pump(tester, _phone(), locale: locale);
      final title = find.text('user123 · الماس');
      expect(
        tester.renderObject<RenderParagraph>(title).textDirection,
        direction,
        reason: locale,
      );
    }
  });

  testWidgets('a used-up service points to another one only while that one '
      'is active', (tester) async {
    ShikooState besides(ShikooService other) => ShikooState(
      connection: ShikooConnection.off,
      connectedFor: Duration.zero,
      isTV: false,
      servers: _servers,
      service: const ShikooService(
        name: 'user123 · الماس',
        usedBytes: 100,
        totalBytes: 100,
      ),
      others: [other],
    );
    const orSwitch =
        'با «تمدید» دوباره وصل می‌شوی،\nیا سرویس دیگرت را انتخاب کن.';

    await _pump(
      tester,
      besides(
        const ShikooService(
          id: 7,
          name: 'user789 · معمولی',
          usedBytes: 0,
          totalBytes: 0,
        ),
      ),
    );
    expect(find.text(orSwitch), findsOneWidget);

    await _pump(
      tester,
      besides(
        const ShikooService(
          id: 7,
          name: 'user789 · معمولی',
          usedBytes: 5,
          totalBytes: 5,
        ),
      ),
    );
    expect(find.text(orSwitch), findsNothing);
    expect(find.text('با «تمدید» دوباره وصل می‌شوی.'), findsOneWidget);
  });

  testWidgets('on the TV the remote starts on the first item of whatever '
      'the home now shows, and is never left on a dead button', (tester) async {
    String? focused() {
      final at = FocusManager.instance.primaryFocus?.context;
      if (at?.findAncestorWidgetOfExactType<PowerButton>() != null) {
        return 'power';
      }
      return at?.findAncestorWidgetOfExactType<ShikooButton>()?.label;
    }

    ShikooState tv(ShikooService? service, {bool on = false}) => ShikooState(
      connection: on ? ShikooConnection.on : ShikooConnection.off,
      connectedFor: Duration.zero,
      isTV: true,
      servers: service == null ? const [] : _servers,
      selected: service == null ? null : 'آلمان ۲',
      service: service,
    );
    const active = ShikooService(
      id: 1,
      name: 'user123 · الماس',
      usedBytes: 0,
      totalBytes: 0,
    );
    const usedUp = ShikooService(
      id: 2,
      name: 'user789 · معمولی',
      usedBytes: 5,
      totalBytes: 5,
    );

    final holder = await _pump(tester, tv(null));
    await tester.pumpAndSettle();
    expect(focused(), 'تنظیمات');

    holder.value = tv(active);
    await tester.pumpAndSettle();
    expect(focused(), 'power', reason: 'the first service arrived');

    holder.value = tv(usedUp);
    await tester.pumpAndSettle();
    expect(focused(), 'تمدید', reason: 'switched to a used-up service');

    holder.value = tv(active);
    await tester.pumpAndSettle();
    expect(focused(), 'power');

    holder.value = tv(usedUp, on: true);
    await tester.pumpAndSettle();
    expect(focused(), 'power', reason: 'a live tunnel can still be stopped');
    holder.value = tv(usedUp);
    await tester.pumpAndSettle();
    expect(focused(), 'تمدید', reason: 'stopped, the power button went dead');
  });

  testWidgets('a server that stays silent says how long it waited, the phone '
      'in one sentence with what to do', (tester) async {
    ShikooState failed({required bool isTV}) => ShikooState(
      connection: ShikooConnection.error,
      connectedFor: Duration.zero,
      isTV: isTV,
      servers: _servers,
      selected: 'آلمان ۲',
      lastError: ShikooError.connectTimeout,
      service: _phone().service,
    );
    await _pump(tester, failed(isTV: false));
    expect(
      find.text(
        'آلمان ۲ تا ۳۰ ثانیه جواب نداد. دوباره بزن، یا از فهرست سرور دیگری '
        'انتخاب کن.',
      ),
      findsOneWidget,
    );
    await _pump(tester, failed(isTV: true));
    expect(
      find.text('آلمان ۲ تا ۳۰ ثانیه جواب نداد.\nسرور دیگری را امتحان کن.'),
      findsOneWidget,
    );
  });

  testWidgets('a pasted link the panel no longer knows: its chip, the message, '
      'remove and support, and nothing of the old usage', (tester) async {
    final controller = _Controller();
    when(() => controller.removeService(any())).thenAnswer((_) async {});
    const revoked = ShikooService(
      id: 4,
      name: 'user456 · طلایی',
      usedBytes: 1,
      totalBytes: 100,
      pasted: true,
      revoked: true,
    );
    await _pump(
      tester,
      const ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: false,
        servers: _servers,
        selected: 'آلمان ۲',
        service: revoked,
        others: [revoked],
      ),
      controller: controller,
    );
    expect(
      find.text('لینک باطل شده'),
      findsNWidgets(3),
      reason: 'chips, button',
    );
    expect(
      find.textContaining('این لینک باطل شده.', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('باقی‌مانده', findRichText: true), findsNothing);
    expect(find.byType(ServerRow), findsNothing);
    expect(find.widgetWithText(ShikooButton, 'تمدید'), findsNothing);
    expect(find.widgetWithText(ShikooButton, 'پشتیبانی'), findsOneWidget);
    expect(
      find.text(
        'حذفش کن، یا لینک تازه را از ربات یا نماینده‌ات بگیر و در «تنظیمات» '
        'بچسبان.',
      ),
      findsOneWidget,
      reason: 'the folded card',
    );
    await tester.tap(find.widgetWithText(ShikooButton, 'حذف'));
    await tester.pumpAndSettle();
    expect(find.text('حذف «\u2068user456 · طلایی\u2069»؟'), findsOneWidget);
    await tester.tap(find.widgetWithText(ShikooButton, 'حذف').last);
    await tester.pumpAndSettle();
    verify(() => controller.removeService(4)).called(1);
  });

  testWidgets('Settings list only the pasted services, each with remove, and '
      'removing the connected one says it disconnects', (tester) async {
    final controller = _Controller();
    when(() => controller.removeService(any())).thenAnswer((_) async {});
    await _pump(
      tester,
      ShikooState(
        connection: ShikooConnection.on,
        connectedFor: Duration.zero,
        isTV: false,
        servers: _servers,
        selected: 'آلمان ۲',
        service: const ShikooService(
          id: 1,
          name: 'user123 · الماس',
          usedBytes: 1,
          totalBytes: 100,
          pasted: true,
        ),
        others: [
          ShikooService(
            id: 2,
            name: 'user456 · طلایی',
            usedBytes: 1,
            totalBytes: 100,
            expire: DateTime(2020),
            pasted: true,
          ),
          const ShikooService(
            id: 3,
            name: 'user789 · معمولی',
            usedBytes: 1,
            totalBytes: 100,
          ),
        ],
      ),
      controller: controller,
    );
    await tester.tap(_icon(ShikooIcon.gear));
    await tester.pumpAndSettle();
    expect(find.text('سرویس‌های اضافه‌شده با لینک'), findsOneWidget);
    expect(find.text('user123 · الماس'), findsOneWidget);
    expect(find.text('تاریخ انقضا گذشته'), findsOneWidget);
    expect(find.text('user789 · معمولی'), findsNothing, reason: 'not pasted');
    expect(find.bySemanticsLabel('حذف user123 · الماس'), findsOneWidget);

    await tester.tap(find.text('حذف').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('اتصال قطع می‌شود و این سرویس'), findsOneWidget);
    await tester.tap(find.widgetWithText(ShikooButton, 'انصراف'));
    await tester.pumpAndSettle();
    verifyNever(() => controller.removeService(any()));

    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('این سرویس از این گوشی پاک'), findsOneWidget);
    await tester.tap(find.widgetWithText(ShikooButton, 'حذف'));
    await tester.pumpAndSettle();
    verify(() => controller.removeService(2)).called(1);
  });

  testWidgets('a revoked card says only «به‌روز نشد», open or folded, and a '
      'service without a name is «سرویس شیکونت»', (tester) async {
    final updated = DateTime.now().subtract(const Duration(minutes: 10));
    final revoked = ShikooService(
      id: 4,
      name: 'user456 · طلایی',
      usedBytes: 1,
      totalBytes: 100,
      updatedAt: updated,
      refresh: ShikooRefresh.failed,
      pasted: true,
      revoked: true,
    );
    await _pump(
      tester,
      ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: false,
        servers: _servers,
        refresh: ShikooRefresh.failed,
        service: revoked,
        others: [
          revoked,
          const ShikooService(id: 5, name: '', usedBytes: 1, totalBytes: 100),
        ],
      ),
    );
    expect(find.text('به‌روز نشد'), findsNWidgets(2));
    expect(find.textContaining('پیش'), findsNothing);
    expect(find.text('سرویس شیکونت'), findsOneWidget);
  });
}
