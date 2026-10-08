import 'dart:async';

import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
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

import '../helpers/no_shots.dart';

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
  ShikooAccount? account,
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
        noShots,
        shikooVersionProvider.overrideWithValue('1.0.0'),
        if (controller != null)
          shikooControllerProvider.overrideWithValue(controller),
        if (account != null)
          shikooAccountProvider.overrideWith(() => ShikooCell(account)),
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
      (ShikooPasteError.clock, 'تاریخ و ساعت دستگاهت درست نیست.'),
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
      expect(
        find.text('تنظیمات تاریخ و ساعت'),
        error == ShikooPasteError.clock ? findsOneWidget : findsNothing,
        reason: error.name,
      );
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
      expect(find.text(bidiName('user123 · الماس')), findsOneWidget);
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
    await tester.tap(find.text(bidiName('user123 · الماس')));
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
    final folded = find.text(bidiName('user789 · معمولی'));
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

    final lastMonth = DateTime.now().subtract(const Duration(days: 20));
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
      find.text('سرویس‌های تمام‌شده (۱)'),
      findsOneWidget,
      reason: 'the other expired service, in the finished row',
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

  test('finished services: the latest end first and those without a date '
      'last; gone 30 days after the end, used up or not', () {
    final now = DateTime(2026, 10, 6, 12);
    Finished row(String name, {bool exhausted = false, DateTime? ended}) => (
      name: name,
      exhausted: exhausted,
      ended: ended,
      renewId: null,
      profileId: null,
      linked: null,
    );
    final order = finishedOrder([
      row('no date'),
      row('29 days', ended: now.subtract(const Duration(days: 29))),
      row('31 days', ended: now.subtract(const Duration(days: 31))),
      row(
        'used up, ends later',
        exhausted: true,
        ended: now.add(const Duration(days: 10)),
      ),
      row(
        'used up, ended 31 days ago',
        exhausted: true,
        ended: now.subtract(const Duration(days: 31)),
      ),
      row('used up, no date', exhausted: true),
      row('3 days', ended: now.subtract(const Duration(days: 3))),
      row('today', ended: now.subtract(const Duration(hours: 2))),
    ], now);
    expect(order.map((row) => row.name), [
      'used up, ends later',
      'today',
      '3 days',
      '29 days',
      'no date',
      'used up, no date',
    ]);
    final l = lookupShikooL10n(const Locale('fa'));
    expect(
      [for (final row in order) finishedStatus(l, row, now)],
      [
        'حجم تمام شد',
        'امروز تمام شد',
        '۳ روز پیش تمام شد',
        '۲۹ روز پیش تمام شد',
        'اعتبارش تمام شد',
        'حجم تمام شد',
      ],
    );
  });

  test('while off, a selection that cannot connect gives way to one that can, '
      'or with none to the one that ended last', () {
    final now = DateTime.now();
    ShikooState state(
      ShikooService current,
      List<ShikooService> others, {
      ShikooConnection connection = ShikooConnection.off,
    }) => ShikooState(
      connection: connection,
      connectedFor: Duration.zero,
      isTV: false,
      servers: const [],
      service: current,
      others: others,
    );
    const usedUp = ShikooService(
      id: 1,
      name: 'a',
      usedBytes: 100,
      totalBytes: 100,
    );
    const active = ShikooService(id: 2, name: 'b', usedBytes: 1, totalBytes: 9);
    final endedLong = ShikooService(
      id: 3,
      name: 'c',
      usedBytes: 0,
      totalBytes: 0,
      expire: now.subtract(const Duration(days: 20)),
    );
    final endedLately = ShikooService(
      id: 4,
      name: 'd',
      usedBytes: 0,
      totalBytes: 0,
      expire: now.subtract(const Duration(days: 2)),
    );
    expect(serviceInstead(state(usedUp, [endedLately, active])), 2);
    expect(
      serviceInstead(state(usedUp, [active], connection: ShikooConnection.on)),
      isNull,
      reason: 'a live tunnel is the user\'s',
    );
    expect(serviceInstead(state(active, [usedUp])), isNull);
    expect(serviceInstead(state(endedLong, [endedLately, usedUp])), 4);
    expect(serviceInstead(state(endedLately, [endedLong, usedUp])), isNull);
  });

  testWidgets('services that connect come first, then the ones waiting on '
      'the customer, and every finished one in one folded row at the end', (
    tester,
  ) async {
    final now = DateTime.now();
    ShikooService service(
      int id,
      String name, {
      int used = 1,
      DateTime? expire,
      bool revoked = false,
    }) => ShikooService(
      id: id,
      name: name,
      usedBytes: used << 30,
      totalBytes: 100 << 30,
      expire: expire ?? now.add(const Duration(days: 20)),
      revoked: revoked,
      pasted: revoked,
    );
    await _pump(
      tester,
      ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: false,
        servers: _servers,
        selected: 'آلمان ۲',
        service: service(1, 'user123 · الماس'),
        others: [
          service(9, 'user555 · طلایی', used: 100),
          service(7, 'user789 · معمولی'),
          service(8, 'user456 · طلایی', revoked: true),
          service(
            10,
            'user666 · طلایی',
            expire: now.subtract(const Duration(days: 3)),
          ),
          service(
            11,
            'user999 · طلایی',
            expire: now.subtract(const Duration(days: 40)),
          ),
        ],
      ),
      account: const ShikooAccount(
        services: [
          LinkedService(id: 50, title: 'user777 · نقره‌ای', status: 'active'),
          LinkedService(id: 51, title: 'user888 · برنزی', status: 'expired'),
        ],
      ),
    );
    double top(String text) =>
        tester.getTopLeft(find.textContaining(text).first).dy;
    final head = find.text('سرویس‌های تمام‌شده (۳)');
    expect(head, findsOneWidget);
    expect(
      [
        top('user123'),
        top('user789'),
        top('user777'),
        top('user456'),
        tester.getTopLeft(head).dy,
      ],
      orderedEquals(
        [
          ...[
            top('user123'),
            top('user789'),
            top('user777'),
            top('user456'),
            tester.getTopLeft(head).dy,
          ],
        ]..sort(),
      ),
    );
    for (final name in ['user555', 'user666', 'user888', 'user999']) {
      expect(find.textContaining(name), findsNothing, reason: 'folded: $name');
    }

    await tester.ensureVisible(head);
    await tester.tap(head);
    await tester.pumpAndSettle();
    expect(
      [
        for (final name in ['user555', 'user666', 'user888']) top(name),
      ],
      orderedEquals(
        [
          for (final name in ['user555', 'user666', 'user888']) top(name),
        ]..sort(),
      ),
    );
    expect(find.textContaining('user999'), findsNothing, reason: '40 days');
    for (final status in [
      'حجم تمام شد',
      '۳ روز پیش تمام شد',
      'اعتبارش تمام شد',
    ]) {
      expect(find.text(status), findsOneWidget);
    }
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ShikooButton && widget.small,
      ),
      findsNWidgets(3),
    );
    expect(
      find.text('با «تمدید» دوباره وصل می‌شوی.'),
      findsNothing,
      reason: 'the selected service works',
    );
  });

  testWidgets('with nothing to connect, the service of the full card is never '
      'in the finished row too, and the row counts the rest', (tester) async {
    final now = DateTime.now();
    ShikooService ended(
      int id,
      String name, {
      DateTime? expire,
      int used = 1,
    }) => ShikooService(
      id: id,
      name: name,
      usedBytes: used << 30,
      totalBytes: 50 << 30,
      expire: expire,
    );
    Future<void> expectRow(int count, String full) async {
      final head = find.text('سرویس‌های تمام‌شده (${localNumberFa(count)})');
      expect(head, findsOneWidget);
      expect(find.textContaining(full), findsOneWidget, reason: 'folded');
      await tester.ensureVisible(head);
      await tester.tap(head);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is ShikooButton && w.small),
        findsNWidgets(count),
      );
      expect(find.textContaining(full), findsOneWidget, reason: 'opened');
    }

    // The account of the design's frame: used up with its date still ahead,
    // then two that expired, and one of the account with no link.
    await _pump(
      tester,
      ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: false,
        servers: _servers,
        service: ended(
          1,
          '7000123_f38a · پاسارگاد',
          used: 50,
          expire: now.add(const Duration(days: 9)),
        ),
        others: [
          ended(
            2,
            '7000123_e7f9 · پاسارگاد',
            expire: now.subtract(const Duration(days: 3)),
          ),
          ended(
            3,
            '7000123_7000123_2 · اولین خرید',
            expire: now.subtract(const Duration(days: 12)),
          ),
        ],
      ),
      account: const ShikooAccount(
        services: [
          LinkedService(
            id: 9,
            title: '7000123_9c1d · پاسارگاد',
            status: 'expired',
          ),
        ],
      ),
    );
    await expectRow(3, 'f38a');

    await _pump(
      tester,
      _noService,
      account: const ShikooAccount(
        services: [
          LinkedService(id: 7, title: 'user700 · طلایی', status: 'exhausted'),
          LinkedService(id: 8, title: 'user800 · طلایی', status: 'expired'),
        ],
      ),
    );
    await expectRow(1, 'user700');
  });

  test('a name breaks only before «·», which goes down with the tier; a tier '
      'or a sign-in line never breaks inside', () {
    expect(
      bidiName('7000123_a1f0 · اولین خرید'),
      '\u20687000123_a1f0\u2069 ·\u00A0\u2068اولین\u00A0خرید\u2069',
    );
    for (final (lang, end) in [
      ('fa', 'با\u00A0این\u00A0سرویس‌ها:'),
      ('en', 'with\u00A0these\u00A0services:'),
    ]) {
      final l = lookupShikooL10n(Locale(lang));
      expect(l.approvedBodyTv('x'), endsWith(end));
      expect(l.approvedBodyTouch('x'), endsWith(end));
    }
  });

  testWidgets('what is left never splits from its unit', (tester) async {
    await _pump(tester, _phone());
    final left = find.textContaining('باقی‌مانده:', findRichText: true);
    final spans = <String>[];
    tester.widget<RichText>(left).text.visitChildren((span) {
      if (span is TextSpan && (span.text ?? '').contains('گیگ')) {
        spans.add(span.text!);
      }
      return true;
    });
    expect(spans.single, isNot(contains(' ')));
    expect(spans.single, contains('\u00A0'));
  });

  testWidgets('an ended service of the account counts by its status and its '
      'expires_at; one on hold is waiting, whatever its date', (tester) async {
    final now = DateTime.now().toUtc();
    LinkedService linked(int id, String status, {int? daysAgo}) =>
        LinkedService(
          id: id,
          title: 'acct$id · $status',
          status: status,
          expiresAt: daysAgo == null
              ? null
              : now.subtract(Duration(days: daysAgo)),
        );
    await _pump(
      tester,
      _phone(),
      account: ShikooAccount(
        services: [
          linked(1, 'removed', daysAgo: 12),
          linked(2, 'disabled', daysAgo: 3),
          linked(3, 'failed'),
          linked(4, 'expired', daysAgo: 40),
          linked(5, 'on_hold', daysAgo: 400),
          linked(6, 'exhausted', daysAgo: 1),
        ],
      ),
    );
    expect(find.textContaining('acct5'), findsOneWidget, reason: 'on hold');
    final head = find.text('سرویس‌های تمام‌شده (۴)');
    await tester.ensureVisible(head);
    await tester.tap(head);
    await tester.pumpAndSettle();
    double top(String name) =>
        tester.getTopLeft(find.textContaining(name).first).dy;
    expect(
      [top('acct6'), top('acct1'), top('acct2'), top('acct3')],
      orderedEquals(
        [top('acct6'), top('acct1'), top('acct2'), top('acct3')]..sort(),
      ),
      reason: 'by expires_at; the turned-off as if undated, last',
    );
    expect(find.textContaining('acct4'), findsNothing, reason: '40 days');
    expect(find.text('حجم تمام شد'), findsOneWidget);
    expect(find.text('غیرفعال شد'), findsNWidgets(3));
  });

  testWidgets('a service the shop turned off reads «غیرفعال شد» and comes last '
      'whatever its date; hidden only 30 days after a past one', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    await _pump(
      tester,
      _phone(),
      account: ShikooAccount(
        services: [
          LinkedService(
            id: 1,
            title: 'acct1 · disabled',
            status: 'disabled',
            expiresAt: now.add(const Duration(days: 20)),
          ),
          LinkedService(
            id: 2,
            title: 'acct2 · removed',
            status: 'removed',
            expiresAt: now.subtract(const Duration(days: 40)),
          ),
          const LinkedService(id: 3, title: 'acct3 · failed', status: 'failed'),
          LinkedService(
            id: 4,
            title: 'acct4 · expired',
            status: 'expired',
            expiresAt: now.subtract(const Duration(days: 2)),
          ),
        ],
      ),
    );
    final head = find.text('سرویس‌های تمام‌شده (۳)');
    await tester.ensureVisible(head);
    await tester.tap(head);
    await tester.pumpAndSettle();
    double top(String name) =>
        tester.getTopLeft(find.textContaining(name).first).dy;
    expect(top('acct4'), lessThan(top('acct1')), reason: 'the turned-off last');
    expect(find.textContaining('acct2'), findsNothing, reason: '40 days ago');
    expect(find.textContaining('acct3'), findsOneWidget, reason: 'no date');
    expect(find.text('غیرفعال شد'), findsNWidgets(2));
    expect(find.text('امروز تمام شد'), findsNothing);
  });

  testWidgets('a finished row opened at the end of the page scrolls itself '
      'into view', (tester) async {
    final now = DateTime.now();
    await _pump(
      tester,
      ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: false,
        servers: _servers,
        selected: 'آلمان ۲',
        service: _phone().service,
        others: [
          for (var i = 1; i <= 4; i++)
            ShikooService(
              id: 10 + i,
              name: 'user55$i · طلایی',
              usedBytes: 1,
              totalBytes: 100,
              expire: now.subtract(Duration(days: i)),
            ),
        ],
      ),
    );
    final head = find.text('سرویس‌های تمام‌شده (۴)');
    await tester.ensureVisible(head);
    await tester.pumpAndSettle();
    await tester.tap(head);
    await tester.pumpAndSettle();
    final last = tester.getRect(find.textContaining('user554'));
    expect(last.bottom, lessThanOrEqualTo(915), reason: '$last');
  });

  testWidgets('with large text on a small phone nothing overflows: the round '
      'button keeps its text inside, a long name wraps and keeps its tail', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.45;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final now = DateTime.now();
    await _pump(
      tester,
      ShikooState(
        connection: ShikooConnection.on,
        connectedFor: const Duration(minutes: 12, seconds: 47),
        isTV: false,
        servers: _servers,
        selected: 'آلمان ۲',
        service: ShikooService(
          id: 1,
          name: '7000123_7000123_2 · اولین خرید',
          usedBytes: 12 << 30,
          totalBytes: 50 << 30,
          expire: now.add(const Duration(days: 67)),
          updatedAt: now,
        ),
        others: [
          ShikooService(
            id: 2,
            name: '7000123_f38a · پاسارگاد',
            usedBytes: 50 << 30,
            totalBytes: 50 << 30,
            expire: now.add(const Duration(days: 9)),
          ),
        ],
      ),
    );
    tester.view.physicalSize = const Size(686, 1524);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final circle = tester.getRect(
      find
          .descendant(
            of: find.byType(PowerButton),
            matching: find.byType(Container),
          )
          .first,
    );
    final clock = find.text('۰۰:۱۲:۴۷');
    final timer = tester.getRect(clock);
    expect(
      MediaQuery.textScalerOf(tester.element(clock)).scale(26),
      closeTo(26 * ShikooSizes.roundTextScaleMax, 0.01),
    );
    expect(
      circle.inflate(1).contains(timer.topLeft) &&
          circle.inflate(1).contains(timer.bottomRight),
      isTrue,
      reason: '$timer inside $circle',
    );
    final name = tester.widget<Text>(
      find.descendant(
        of: find.byType(ServiceName),
        matching: find.textContaining('اولین'),
      ),
    );
    expect(name.overflow, isNot(TextOverflow.ellipsis));
    expect(name.data, contains('…'));
    expect(name.data, contains('123_2'), reason: 'the last five stay');
    final search = tester.getRect(find.text('جست‌وجوی سرور'));
    final pingAll = tester.getRect(find.text('پینگ همه'));
    expect(pingAll.top, greaterThan(search.bottom), reason: 'ping-all wraps');
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
    expect(
      find.text('حذف «${bidiName('user456 · طلایی')}»؟'),
      findsOneWidget,
      reason:
          'no isolate around the whole name, or its first part sets one direction',
    );
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
    expect(find.text(bidiName('user123 · الماس')), findsOneWidget);
    expect(find.text('تاریخ انقضا گذشته'), findsOneWidget);
    expect(
      find.text(bidiName('user789 · معمولی')),
      findsNothing,
      reason: 'not pasted',
    );
    expect(
      find.bySemanticsLabel('حذف ${bidiName('user123 · الماس')}'),
      findsOneWidget,
    );

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

  testWidgets('a second nameless service reads «سرویس شیکونت ۲»', (
    tester,
  ) async {
    await _pump(
      tester,
      const ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: false,
        servers: _servers,
        service: ShikooService(name: '', usedBytes: 1, totalBytes: 100),
        others: [
          ShikooService(
            id: 2,
            name: '',
            usedBytes: 1,
            totalBytes: 100,
            number: 2,
          ),
        ],
      ),
    );
    expect(find.text('سرویس شیکونت'), findsOneWidget);
    expect(find.text('سرویس شیکونت ۲'), findsOneWidget);
  });

  testWidgets('a Latin name keeps its own order in Persian and English, the '
      'username first', (tester) async {
    double left(String inText, String part, [int nth = 0]) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.textContaining(inText).first,
      );
      final text = paragraph.text.toPlainText();
      var i = -1;
      for (var n = 0; n <= nth; n++) {
        i = text.indexOf(part, i + 1);
      }
      expect(i, isNonNegative, reason: '$part in $text');
      return paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: i, extentOffset: i + 1),
          )
          .first
          .left;
    }

    const state = ShikooState(
      connection: ShikooConnection.off,
      connectedFor: Duration.zero,
      isTV: false,
      servers: _servers,
      selected: 'آلمان ۲',
      service: ShikooService(
        name: 'e7f9 · pasargard_111713193',
        usedBytes: 1,
        totalBytes: 100,
      ),
      others: [
        ShikooService(
          id: 2,
          name: 'firstbuy · 2_111713193_111713193',
          usedBytes: 1,
          totalBytes: 100,
        ),
        ShikooService(
          id: 3,
          name: 'user123 · الماس',
          usedBytes: 1,
          totalBytes: 100,
        ),
      ],
    );
    for (final locale in ['fa', 'en']) {
      await _pump(tester, state, locale: locale);
      tester.view.physicalSize = const Size(2400, 1830);
      await tester.pump();
      final rtl = locale == 'fa';
      expect(
        left('pasargard', 'p') < left('pasargard', '_') &&
            left('pasargard', '_') < left('pasargard', '1'),
        isTrue,
        reason: '$locale: pasargard_111713193 reads left to right',
      );
      expect(
        left('2_1117', '2') < left('2_1117', '_') &&
            left('2_1117', '_') < left('2_1117', '_', 1),
        isTrue,
        reason: '$locale: 2_111713193_111713193 keeps its order',
      );
      expect(
        left('pasargard', 'e') > left('pasargard', 'p'),
        rtl,
        reason: '$locale: the username leads in the reading direction',
      );
      expect(
        left('user123', 'u') > left('user123', 'ا'),
        rtl,
        reason: '$locale: a mixed name, the username first too',
      );
    }
  });

  testWidgets('on a clock 14 years ahead, a service the server ended 3 days '
      'ago is finished 3 days ago', (tester) async {
    const years14 = Duration(days: 14 * 365);
    shikooSkew = -years14;
    addTearDown(() => shikooSkew = Duration.zero);
    final phone = _phone();
    await _pump(
      tester,
      ShikooState(
        connection: phone.connection,
        connectedFor: phone.connectedFor,
        isTV: false,
        service: phone.service,
        servers: phone.servers,
        selected: phone.selected,
        others: [
          ShikooService(
            id: 7,
            name: 'user555 · الماس',
            usedBytes: 0,
            totalBytes: 0,
            expire: DateTime.now().subtract(years14 + const Duration(days: 3)),
          ),
        ],
      ),
    );
    final head = find.text('سرویس‌های تمام‌شده (۱)');
    await tester.ensureVisible(head);
    await tester.tap(head);
    await tester.pumpAndSettle();
    expect(find.text('۳ روز پیش تمام شد'), findsOneWidget);
  });

  testWidgets('connected, a tap on another server shows its move in one '
      'bottom bar whose words follow it, in Persian and English', (
    tester,
  ) async {
    final nl = bidiName('هلند ۱');
    final de = bidiName('آلمان ۲');
    for (final (locale, moving, done, strong, kept) in [
      (
        'fa',
        'در حال رفتن به «$nl»…',
        'حالا از «$nl» وصلی.',
        '«$nl» جواب نداد.',
        'هنوز از «$de» وصلی؛ سرور دیگری را امتحان کن.',
      ),
      (
        'en',
        'Moving to “$nl”…',
        'Now connected through “$nl”.',
        '“$nl” didn\'t answer.',
        'Still on “$de”. Try another server.',
      ),
    ]) {
      final failed = '$strong $kept';
      final holder = await _pump(tester, _switch(null), locale: locale);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byWidgetPredicate(_arc), findsNothing);

      holder.value = _switch(ShikooSwitchStage.moving);
      await tester.pumpAndSettle();
      expect(find.text(moving, findRichText: true), findsOneWidget);
      final bar = tester.element(find.byType(SnackBar));
      expect(
        find.descendant(
          of: find.widgetWithText(ServerRow, 'هلند ۱'),
          matching: find.byType(Spinner),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<ServerRow>(find.widgetWithText(ServerRow, 'آلمان ۲')),
        isA<ServerRow>().having((row) => row.selected, 'selected', isTrue),
      );
      expect(find.byWidgetPredicate(_arc), findsOneWidget);
      expect(find.text(locale == 'fa' ? 'وصل' : 'Connected'), findsOneWidget);

      holder.value = _switch(ShikooSwitchStage.done);
      await tester.pumpAndSettle();
      expect(find.text(done, findRichText: true), findsOneWidget);
      expect(
        tester.element(find.byType(SnackBar)),
        same(bar),
        reason: 'the same bar changes its words',
      );
      expect(find.byWidgetPredicate(_arc), findsNothing);

      holder.value = _switch(null);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      holder.value = _switch(ShikooSwitchStage.failed);
      await tester.pumpAndSettle();
      expect(find.text(failed, findRichText: true), findsOneWidget);
      final words = tester.widget<RichText>(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(failed, findRichText: true),
        ),
      );
      FontWeight? weight;
      words.text.visitChildren((span) {
        if (span is TextSpan && span.text == strong) {
          weight = span.style?.fontWeight;
        }
        return weight == null;
      });
      expect(weight, FontWeight.w700);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget, reason: 'no timer');
    }
  });

  testWidgets('while the bar is up the list ends above it, by its real height: '
      'three lines need more room than one', (tester) async {
    const long = '(Gemini) Italy 2 [WG] Milano';
    const old = 'Germany 3 [WG] Frankfurt';
    final servers = [
      const ShikooServer(name: old, type: 'WireGuard', ping: 80),
      for (var i = 1; i <= 12; i++)
        ShikooServer(name: 'سرور $i', type: 'Vless', ping: 90 + i),
      const ShikooServer(name: long, type: 'Vless', ping: -1),
    ];
    ShikooState state(ShikooSwitchStage? stage, String to) =>
        _switch(stage, to: to, from: old, servers: servers);
    double padding() =>
        (tester
                    .widget<SingleChildScrollView>(
                      find.byType(SingleChildScrollView).first,
                    )
                    .padding!
                as EdgeInsets)
            .bottom;
    Rect bar() => tester.getRect(
      find
          .descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Material),
          )
          .first,
    );

    final holder = await _pump(tester, state(null, long));
    final resting = padding();
    holder.value = state(ShikooSwitchStage.moving, 'سرور 1');
    await tester.pumpAndSettle();
    final oneLine = padding();
    holder.value = state(ShikooSwitchStage.failed, long);
    await tester.pumpAndSettle();
    final threeLines = padding();
    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(threeLines, closeTo(screen - bar().top + Space.s3, 1));
    expect(threeLines, greaterThan(oneLine));
    expect(oneLine, greaterThan(resting));

    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -10000),
    );
    await tester.pumpAndSettle();
    final last = tester.getRect(find.byType(ServerRow).last);
    expect(last.bottom, lessThanOrEqualTo(bar().top), reason: 'not under it');

    holder.value = state(null, long);
    await tester.pumpAndSettle();
    expect(padding(), resting);
  });
}

bool _arc(Widget widget) =>
    widget is CustomPaint && '${widget.painter.runtimeType}' == '_ArcPainter';

/// Connected through آلمان ۲; [stage] of a tap on [to].
ShikooState _switch(
  ShikooSwitchStage? stage, {
  String to = 'هلند ۱',
  String from = 'آلمان ۲',
  List<ShikooServer> servers = _servers,
}) => ShikooState(
  connection: ShikooConnection.on,
  connectedFor: const Duration(minutes: 12, seconds: 47),
  isTV: false,
  service: _phone().service,
  servers: [
    for (final server in servers)
      switch ((server.name == to, stage)) {
        (true, ShikooSwitchStage.moving) => ShikooServer(
          name: to,
          type: server.type,
          testing: true,
        ),
        (true, ShikooSwitchStage.failed) => ShikooServer(
          name: to,
          type: server.type,
          ping: -1,
        ),
        _ => server,
      },
  ],
  selected: stage == ShikooSwitchStage.done ? to : from,
  switching: stage == null ? null : (to: to, from: from, stage: stage),
);

String localNumberFa(int n) => '$n'.replaceAllMapped(
  RegExp('[0-9]'),
  (digit) => String.fromCharCode(0x06F0 + int.parse(digit[0]!)),
);
