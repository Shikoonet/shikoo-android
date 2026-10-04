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
      tester.getTopLeft(find.text('پشتیبانی')).dy,
      lessThan(tester.getTopLeft(find.text('چسباندن لینک اشتراک')).dy),
      reason: 'paste is the second button',
    );

    await tester.tap(find.text('چسباندن لینک اشتراک'));
    await tester.pump();
    expect(reads(), 1);
    verify(() => controller.pasteService(clip)).called(1);
    expect(find.text('در حال بررسی لینک…'), findsOneWidget);
    answer.complete(ShikooPasteError.empty);
    await tester.pumpAndSettle();

    for (final (error, strong) in [
      (ShikooPasteError.empty, 'کلیپ‌بورد خالی است.'),
      (ShikooPasteError.notShikoo, 'این لینک شیکو نیست.'),
      (ShikooPasteError.revoked, 'این لینک باطل شده یا منقضی است.'),
      (ShikooPasteError.serverDown, 'سرور شیکو الان جواب نمی‌دهد.'),
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
      'این لینک شیکو نیست.',
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
}
