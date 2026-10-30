import 'dart:async';

import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/paste.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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

final _today = DateTime(2026, 10, 16, 12);

ShikooState _phone({
  List<ShikooServer> servers = _servers,
  bool isTV = false,
  ({int done, int total})? pinging,
}) => ShikooState(
  connection: ShikooConnection.off,
  connectedFor: Duration.zero,
  isTV: isTV,
  pinging: pinging,
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
  ShikooDiag? diag,
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
        diag == null ? noShots : shikooDiagProvider.overrideWithValue(diag),
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

ShikooPasted _failed(ShikooPasteError error) =>
    (error: error, id: null, added: false);

const ShikooPasted _added = (error: null, id: 7, added: true);

const _ended =
    'این سرویس تمام شده. از ربات شیکونت یا نماینده‌ات تمدیدش کن، بعد دوباره '
    'بچسبان.';

Finder _icon(ShikooIcon icon) =>
    find.byWidgetPredicate((w) => w is SvgIcon && w.icon == icon);

/// In «سرویس‌های تمام‌شده», apart from the top bar's renew and support.
Finder _inFinished(Finder matching) => find.descendant(
  of: find
      .ancestor(
        of: find.textContaining('سرویس‌های تمام‌شده'),
        matching: find.byType(Column),
      )
      .first,
  matching: matching,
);

final _small = find.byWidgetPredicate((w) => w is ShikooButton && w.small);

/// The button on the finished row named [name]; none on a row the bot does not renew.
String? _rowAction(WidgetTester tester, String name) => tester
    .widgetList<ShikooButton>(
      find.descendant(
        of: find.ancestor(
          of: find.textContaining(name).first,
          matching: find.byWidgetPredicate(
            (w) => w is Row && w.children.any((c) => c is ShikooButton),
          ),
        ),
        matching: find.byType(ShikooButton),
      ),
    )
    .firstOrNull
    ?.label;

List<String> _rowOrder(WidgetTester tester) => [
  for (final row in tester.widgetList<ServerRow>(find.byType(ServerRow)))
    row.server.name,
];

/// [_servers] after a round in which آلمان ۱ came first.
const _pinged = [
  ShikooServer(name: 'آلمان ۱', type: 'Vless', ping: 40),
  ShikooServer(name: 'هلند ۱', type: 'Vless', ping: 90),
  ShikooServer(name: 'آلمان ۲', type: 'Vless', ping: -1),
];

/// A screen too short for the home, so the page scrolls.
Future<void> _shortPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(824, 1100);
  await tester.pumpAndSettle();
}

ScrollPosition _page(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

Future<void> _refold(WidgetTester tester) async {
  await tester.ensureVisible(_icon(ShikooIcon.chevronUp));
  await tester.tap(_icon(ShikooIcon.chevronUp));
  await tester.pumpAndSettle();
  await tester.ensureVisible(_icon(ShikooIcon.chevronDown));
  await tester.tap(_icon(ShikooIcon.chevronDown));
  await tester.pumpAndSettle();
}

void main() {
  // As in the app: expiry counts on shikooNow(), updatedAt on DateTime.now().
  setUp(() => shikooSkew = _today.difference(DateTime.now()));
  tearDown(() => shikooSkew = Duration.zero);

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
    await _pump(tester, _phone(), controller: _Controller());
    await tester.tap(_icon(ShikooIcon.chevronUp));
    await tester.pumpAndSettle();
    expect(find.byType(ServerRow), findsNothing);
    expect(find.text('تمدید'), findsOneWidget, reason: "the top bar's alone");
    expect(
      find.text(
        '${_whole('مصرف شده: ۳۳ از ۱۰۰ گیگ')} '
        '${_whole('· اعتبار تا ۴ آبان ۱۴۰۵')}',
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

  testWidgets('an untouched list sorts as pings land; a scroll or a search '
      'holds it, and folding the card lets the fastest up again', (
    tester,
  ) async {
    final holder = await _pump(tester, _phone(), controller: _Controller());
    await _shortPage(tester);
    holder.value = _phone(servers: _pinged);
    await tester.pumpAndSettle();
    const sorted = ['آلمان ۱', 'هلند ۱', 'آلمان ۲'];
    expect(_rowOrder(tester), sorted, reason: 'untouched from a cold start');

    await tester.drag(find.byType(PowerButton), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(_page(tester).pixels, greaterThan(0));
    holder.value = _phone();
    await tester.pumpAndSettle();
    expect(_rowOrder(tester), sorted, reason: 'a scroll holds it');
    expect(
      tester.widget<ServerRow>(find.widgetWithText(ServerRow, 'آلمان ۱')),
      isA<ServerRow>().having((r) => r.server.ping, 'ping', 142),
    );

    await _refold(tester);
    expect(_rowOrder(tester), ['هلند ۱', 'آلمان ۲', 'آلمان ۱']);

    await tester.enterText(find.byType(TextField), 'آلمان');
    await tester.pump();
    holder.value = _phone(servers: _pinged);
    await tester.pumpAndSettle();
    expect(_rowOrder(tester), ['آلمان ۲', 'آلمان ۱'], reason: 'search holds');
    await tester.tap(find.bySemanticsLabel('پاک کردن جست‌وجو'));
    await tester.pump();
    expect(_rowOrder(tester), ['هلند ۱', 'آلمان ۲', 'آلمان ۱']);
  });

  testWidgets('after a wheel turn, a tap where the second row was when new '
      'pings land picks the server that row showed', (tester) async {
    final controller = _Controller();
    when(
      () => controller.selectServer(any(), service: any(named: 'service')),
    ).thenAnswer((_) async {});
    final holder = await _pump(tester, _phone(), controller: controller);
    await _shortPage(tester);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      mouse.hover(tester.getCenter(find.byType(PowerButton))),
    );
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 600)));
    await tester.pumpAndSettle();
    expect(_page(tester).pixels, greaterThan(0));
    final second = tester.getCenter(find.byType(ServerRow).at(1));
    expect(_rowOrder(tester)[1], 'آلمان ۲');

    holder.value = _phone(servers: _pinged);
    await tester.pumpAndSettle();
    await tester.tapAt(second);
    await tester.pumpAndSettle();
    verify(() => controller.selectServer('آلمان ۲')).called(1);
  });

  testWidgets('a held list sorts again once the app comes back from the '
      'background', (tester) async {
    final holder = await _pump(tester, _phone());
    await _shortPage(tester);
    await tester.drag(find.byType(PowerButton), const Offset(0, -80));
    await tester.pumpAndSettle();
    holder.value = _phone(servers: _pinged);
    await tester.pumpAndSettle();
    expect(_rowOrder(tester), ['هلند ۱', 'آلمان ۲', 'آلمان ۱']);

    for (final step in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(step);
    }
    await tester.pumpAndSettle();
    expect(_rowOrder(tester), ['آلمان ۱', 'هلند ۱', 'آلمان ۲']);
  });

  testWidgets("another service's open list sorts until a server there is "
      'pressed, then holds through its pings and the move to it', (
    tester,
  ) async {
    final controller = _Controller();
    when(
      () => controller.selectServer(any(), service: any(named: 'service')),
    ).thenAnswer((_) async {});
    const pinged = [
      ShikooServer(name: 'هلند ۱', type: 'Vless', ping: 50),
      ShikooServer(name: 'ترکیه ۱', type: 'Vless', ping: 80),
    ];
    final holder = await _pump(
      tester,
      _cards(open: 7, opened: 7),
      controller: controller,
    );
    holder.value = _cards(open: 7, opened: 7, openedServers: pinged);
    await tester.pumpAndSettle();
    expect(_rowOrder(tester), ['هلند ۱', 'ترکیه ۱']);

    final row = find.widgetWithText(ServerRow, 'ترکیه ۱');
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    holder.value = _cards(open: 7, opened: 7);
    await tester.pumpAndSettle();
    expect(_rowOrder(tester), ['هلند ۱', 'ترکیه ۱']);

    holder.value = _cards(
      open: 7,
      current: 7,
      servers: pinged.reversed.toList(),
    );
    await tester.pumpAndSettle();
    expect(_rowOrder(tester), ['هلند ۱', 'ترکیه ۱']);
  });

  testWidgets("the app's own scrolls, a jump, a slide and a reveal, are no "
      'touch: the list still sorts', (tester) async {
    final holder = await _pump(tester, _phone());
    await _shortPage(tester);
    final page = _page(tester);
    page.jumpTo(120);
    await tester.pumpAndSettle();
    unawaited(
      page.animateTo(
        40,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(ServerRow).last);
    await tester.pumpAndSettle();
    expect(page.pixels, greaterThan(0));
    holder.value = _phone(servers: _pinged);
    await tester.pumpAndSettle();
    expect(_rowOrder(tester), ['آلمان ۱', 'هلند ۱', 'آلمان ۲']);
  });

  group('«پینگ سرورها» on a held list', () {
    const held = ['هلند ۱', 'آلمان ۲', 'آلمان ۱'];
    const sorted = ['آلمان ۱', 'هلند ۱', 'آلمان ۲'];

    /// [starts] false: the press starts no round, as in the 15 s after an update.
    Future<ValueNotifier<ShikooState>> pingHeld(
      WidgetTester tester, {
      bool starts = true,
    }) async {
      final controller = _Controller();
      late final ValueNotifier<ShikooState> holder;
      when(() => controller.pingAll()).thenAnswer((_) async {
        if (starts) {
          holder.value = _phone(servers: _pinged, pinging: (done: 0, total: 3));
        }
      });
      when(
        () => controller.selectServer(any(), service: any(named: 'service')),
      ).thenAnswer((_) async {});
      holder = await _pump(tester, _phone(), controller: controller);
      await _shortPage(tester);
      await tester.drag(find.byType(PowerButton), const Offset(0, -80));
      await tester.pumpAndSettle();
      holder.value = _phone(servers: _pinged);
      await tester.pumpAndSettle();
      expect(_rowOrder(tester), held);

      await tester.tap(find.bySemanticsLabel('پینگ سرورها'));
      await tester.pumpAndSettle();
      verify(() => controller.pingAll()).called(1);
      expect(_rowOrder(tester), held, reason: 'not before its round ends');
      return holder;
    }

    testWidgets('sorts it once its round ends, then the list follows each '
        'round again', (tester) async {
      final holder = await pingHeld(tester);
      holder.value = _phone(servers: _pinged);
      await tester.pumpAndSettle();
      expect(_rowOrder(tester), sorted);

      holder.value = _phone();
      await tester.pumpAndSettle();
      expect(_rowOrder(tester), held);
    });

    testWidgets('a finger on a row in that round holds it again: the round '
        'ends and the row stays under it', (tester) async {
      final holder = await pingHeld(tester);
      final row = find.widgetWithText(ServerRow, 'هلند ۱');
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final finger = await tester.startGesture(tester.getCenter(row));
      holder.value = _phone(servers: _pinged);
      await tester.pump();
      expect(_rowOrder(tester), held);
      await finger.up();
      await tester.pumpAndSettle();
      expect(_rowOrder(tester), held);
    });

    testWidgets('a press that starts no round leaves it held through the next '
        'round nobody asked for', (tester) async {
      final holder = await pingHeld(tester, starts: false);
      holder.value = _phone(servers: _pinged, pinging: (done: 1, total: 3));
      await tester.pumpAndSettle();
      holder.value = _phone(servers: _pinged);
      await tester.pumpAndSettle();
      expect(_rowOrder(tester), held);
    });
  });

  testWidgets("a ping on another service's held list sorts it as that "
      'round ends, after the list empties for it', (tester) async {
    const first = [
      ShikooServer(name: 'ترکیه ۱', type: 'Vless', ping: 80),
      ShikooServer(name: 'هلند ۱', type: 'Vless', ping: 300),
    ];
    const next = [
      ShikooServer(name: 'هلند ۱', type: 'Vless', ping: 50),
      ShikooServer(name: 'ترکیه ۱', type: 'Vless', ping: 90),
    ];
    final controller = _Controller();
    late final ValueNotifier<ShikooState> holder;
    when(
      () => controller.openService(any()),
    ).thenAnswer((_) => holder.value = _cards(open: 7));
    holder = await _pump(
      tester,
      _cards(open: 7, opened: 7, openedServers: first),
      controller: controller,
    );
    await _shortPage(tester);
    await tester.drag(find.byType(PowerButton), const Offset(0, -80));
    await tester.pumpAndSettle();
    holder.value = _cards(open: 7, opened: 7, openedServers: next);
    await tester.pumpAndSettle();
    expect(_rowOrder(tester), ['ترکیه ۱', 'هلند ۱'], reason: 'held');

    await tester.tap(find.bySemanticsLabel('پینگ سرورها'));
    await tester.pumpAndSettle();
    verify(() => controller.openService(7)).called(1);
    holder.value = _cards(
      open: 7,
      opened: 7,
      openedServers: next,
      openedPinging: (done: 1, total: 2),
    );
    await tester.pumpAndSettle();
    expect(_rowOrder(tester), ['ترکیه ۱', 'هلند ۱'], reason: 'mid-round');
    holder.value = _cards(open: 7, opened: 7, openedServers: next);
    await tester.pumpAndSettle();
    expect(_rowOrder(tester), ['هلند ۱', 'ترکیه ۱'], reason: 'round ended');
  });

  testWidgets('on the TV a ping leaves the order to the remote: a row pressed '
      'as its round ends holds it until let go', (tester) async {
    final controller = _Controller();
    when(() => controller.pingAll()).thenAnswer((_) async {});
    final holder = await _pump(
      tester,
      _phone(isTV: true),
      controller: controller,
    );
    await tester.tap(find.widgetWithText(ShikooButton, 'پینگ'));
    verify(() => controller.pingAll()).called(1);
    holder.value = _phone(isTV: true, pinging: (done: 1, total: 3));
    await tester.pump();
    final finger = await tester.startGesture(
      tester.getCenter(find.widgetWithText(ServerRow, 'آلمان ۱')),
    );
    holder.value = _phone(servers: _pinged, isTV: true);
    await tester.pump();
    expect(_rowOrder(tester), ['هلند ۱', 'آلمان ۲', 'آلمان ۱']);
    await finger.cancel();
    await tester.pump();
    expect(_rowOrder(tester), ['آلمان ۱', 'هلند ۱', 'آلمان ۲']);
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
    final answer = Completer<ShikooPasted>();
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
    answer.complete(_failed(ShikooPasteError.empty));
    await tester.pumpAndSettle();

    for (final (error, strong) in [
      (ShikooPasteError.empty, 'کلیپ‌بورد خالی است.'),
      (ShikooPasteError.notShikoo, 'این لینک شیکونت نیست.'),
      (ShikooPasteError.revoked, 'این لینک باطل شده یا منقضی است.'),
      (ShikooPasteError.unavailable, 'لینک الان باز نشد.'),
      (ShikooPasteError.expired, _ended),
      (ShikooPasteError.exhausted, _ended),
      (ShikooPasteError.clock, 'تاریخ و ساعت دستگاهت درست نیست.'),
      (ShikooPasteError.offline, 'اینترنت وصل نیست.'),
    ]) {
      when(
        () => controller.pasteService(any()),
      ).thenAnswer((_) async => _failed(error));
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

    final last = Completer<ShikooPasted>();
    when(() => controller.pasteService(any())).thenAnswer((_) => last.future);
    await tester.tap(find.text('چسباندن لینک اشتراک'));
    await tester.pump();
    expect(
      find.textContaining('اینترنت وصل نیست.'),
      findsNothing,
      reason: 'the next paste clears the last refusal',
    );
    last.complete(_added);
    await tester.pumpAndSettle();
    expect(find.textContaining('اینترنت وصل نیست.'), findsNothing);
  });

  testWidgets("the phone's settings paste another link above log out, show a "
      'refusal over the card, and go home once it is in', (tester) async {
    _clipboard(tester, 'https://example.com/sub/x');
    final controller = _Controller();
    when(
      () => controller.pasteService(any()),
    ).thenAnswer((_) async => _failed(ShikooPasteError.notShikoo));
    await _pump(tester, _phone(), controller: controller);
    await tester.tap(_icon(ShikooIcon.gear));
    await tester.pumpAndSettle();
    final paste = find.text('چسباندن لینک دیگر');
    expect(find.text('برای سرویس دیگری که داری'), findsOneWidget);
    expect(
      tester.getTopLeft(paste).dy,
      lessThan(tester.getTopLeft(find.text('خروج')).dy),
    );

    // Connection's two switches push the account card below a phone's first screen.
    await tester.ensureVisible(paste);
    await tester.pumpAndSettle();
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

    when(() => controller.pasteService(any())).thenAnswer((_) async => _added);
    await tester.tap(paste);
    await tester.pumpAndSettle();
    expect(find.byType(ShikooSettings), findsNothing);
  });

  testWidgets('«+» is on a phone home with a service card, signed in or not, '
      'and never on the TV or beside the no-service paste card', (
    tester,
  ) async {
    final plus = find.bySemanticsLabel('افزودن سرویس با لینک');
    await _pump(tester, _phone());
    expect(plus, findsOneWidget);
    await _pump(
      tester,
      _noService,
      account: const ShikooAccount(
        services: [
          LinkedService(id: 50, title: 'user777 · نقره‌ای', status: 'active'),
        ],
      ),
    );
    expect(plus, findsOneWidget, reason: 'a card of the account, no link yet');
    await _pump(tester, _noService);
    expect(_icon(ShikooIcon.plus), findsNothing);
    await _pump(tester, _phone(isTV: true));
    expect(_icon(ShikooIcon.plus), findsNothing);
  });

  testWidgets('Settings show «ترتیب سرویس‌ها» with two running services: under '
      'the language on the phone, last in its column on the TV', (
    tester,
  ) async {
    const usedUp = ShikooService(
      id: 6,
      name: 'user666 · برنزی',
      usedBytes: 2,
      totalBytes: 1,
    );
    const other = ShikooService(
      id: 5,
      name: 'user555 · نقره‌ای',
      usedBytes: 0,
      totalBytes: 0,
    );
    ShikooState home(List<ShikooService> others, {bool isTV = false}) {
      final phone = _phone(isTV: isTV);
      return ShikooState(
        connection: phone.connection,
        connectedFor: phone.connectedFor,
        isTV: isTV,
        service: phone.service,
        servers: phone.servers,
        others: others,
      );
    }

    final row = find.text('ترتیب سرویس‌ها');
    double top(Finder finder) => tester.getTopLeft(finder.first).dy;
    await _pump(tester, home([usedUp]));
    await tester.tap(_icon(ShikooIcon.gear));
    await tester.pumpAndSettle();
    expect(row, findsNothing, reason: 'a used-up one is not ordered');

    await _pump(tester, home([usedUp, other]));
    await tester.tap(_icon(ShikooIcon.gear));
    await tester.pumpAndSettle();
    expect(find.text('فقط روی همین گوشی'), findsOneWidget);
    expect(top(row), greaterThan(top(find.text('English'))));
    expect(top(row), lessThan(top(find.text('خروج'))));

    await _pump(tester, home([other], isTV: true));
    await tester.tap(find.text('تنظیمات'));
    await tester.pumpAndSettle();
    expect(find.text('فقط روی همین تلویزیون'), findsOneWidget);
    expect(top(row), greaterThan(top(find.text('عیب‌یابی و گزارش'))));
  });

  group('«+» and the add screen', () {
    const other = ShikooService(
      id: 5,
      name: 'user555 · نقره‌ای',
      usedBytes: 0,
      totalBytes: 0,
    );
    const pasted = ShikooService(
      id: 9,
      name: 'user999 · طلایی',
      usedBytes: 0,
      totalBytes: 0,
    );
    ShikooState home(List<ShikooService> others, {int? open}) {
      final phone = _phone();
      return ShikooState(
        connection: ShikooConnection.on,
        connectedFor: Duration.zero,
        isTV: false,
        service: phone.service,
        servers: phone.servers,
        selected: phone.selected,
        others: others,
        open: open,
      );
    }

    /// Every card from the top, and the open one.
    (List<int>, int?) cards(WidgetTester tester) {
      final top = <int, double>{
        for (final card in tester.widgetList<FoldedServiceCard>(
          find.byType(FoldedServiceCard),
        ))
          card.service.id: tester.getTopLeft(find.byWidget(card)).dy,
        for (final card in tester.widgetList<ServiceCard>(
          find.byType(ServiceCard),
        ))
          card.state.service!.id: tester.getTopLeft(find.byWidget(card)).dy,
      };
      final open = tester.widgetList<ServiceCard>(find.byType(ServiceCard));
      return (
        top.keys.toList()..sort((a, b) => top[a]!.compareTo(top[b]!)),
        open.singleOrNull?.state.service?.id,
      );
    }

    /// Home with one other card; the paste answers [answer], having brought [after].
    Future<_Controller> add(
      WidgetTester tester,
      ShikooPasted answer,
      List<ShikooService> after,
    ) async {
      _clipboard(tester, 'https://s.4g3.uk/sub/secret-token');
      final controller = _Controller();
      late final ValueNotifier<ShikooState> holder;
      when(() => controller.pasteService(any())).thenAnswer((_) async {
        holder.value = home(after, open: answer.id);
        return answer;
      });
      holder = await _pump(tester, home([other]), controller: controller);
      await tester.tap(find.bySemanticsLabel('افزودن سرویس با لینک'));
      await tester.pumpAndSettle();
      expect(find.byType(AddService), findsOneWidget);
      expect(find.text('افزودن سرویس'), findsOneWidget);
      expect(find.textContaining('لینک اشتراک شیکونتِ'), findsOneWidget);
      await tester.tap(find.text('چسباندن لینک اشتراک'));
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('a new service closes the screen, the bar names it, and its '
        'card comes last, open', (tester) async {
      await add(tester, (error: null, id: 9, added: true), [other, pasted]);
      expect(find.byType(AddService), findsNothing);
      expect(
        find.text('سرویسِ «${bidiName('user999 · طلایی')}» اضافه شد.'),
        findsOneWidget,
      );
      final (order, open) = cards(tester);
      expect(order, [0, 5, 9]);
      expect(open, 9, reason: 'the pasted card opens');
      expect(find.textContaining('secret-token'), findsNothing);
    });

    testWidgets('a service already here says so and makes no second card', (
      tester,
    ) async {
      await add(tester, (error: null, id: 5, added: false), [other]);
      expect(find.byType(AddService), findsNothing);
      expect(find.text('این سرویس از قبل روی این گوشی هست.'), findsOneWidget);
      final (order, open) = cards(tester);
      expect(order, [0, 5]);
      expect(open, 5, reason: 'the pasted card opens');
    });

    testWidgets('a link that is not ShikooNet stays on the screen with its '
        'message', (tester) async {
      await add(
        tester,
        (error: ShikooPasteError.notShikoo, id: null, added: false),
        [other],
      );
      expect(find.byType(AddService), findsOneWidget);
      expect(
        find.textContaining('این لینک شیکونت نیست.', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('leaving mid-check still adds the service, with no error and '
        'no word from the screen that went', (tester) async {
      final clipboard = Completer<Object?>();
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) => call.method == 'Clipboard.getData'
            ? clipboard.future
            : Future.value(),
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final controller = _Controller();
      when(
        () => controller.pasteService(any()),
      ).thenAnswer((_) async => (error: null, id: 0, added: false));
      await _pump(tester, home([other]), controller: controller);
      await tester.tap(find.bySemanticsLabel('افزودن سرویس با لینک'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('چسباندن لینک اشتراک'));
      await tester.pump();
      await tester.tap(_icon(ShikooIcon.back));
      await tester.pumpAndSettle();
      expect(find.byType(AddService), findsNothing);

      clipboard.complete({'text': 'https://s.4g3.uk/sub/x'});
      await tester.pumpAndSettle();
      verify(() => controller.pasteService('https://s.4g3.uk/sub/x')).called(1);
      expect(tester.takeException(), isNull);
      expect(find.text('این سرویس از قبل روی این گوشی هست.'), findsNothing);
    });
  });

  testWidgets('the app is called ShikooNet, شیکونت in Persian, beside the fox '
      'mark in either language', (tester) async {
    for (final (locale, name, letter) in [
      ('fa', 'شیکونت', 'ش'),
      ('en', 'ShikooNet', 'S'),
    ]) {
      // With no service the bar has no renew or support: the test font's wide letters leave the word room.
      await _pump(tester, _noService, locale: locale);
      expect(find.text(name), findsOneWidget, reason: locale);
      expect(
        find.image(const AssetImage(shikooMarkAsset)),
        findsOneWidget,
        reason: locale,
      );
      expect(find.text(letter), findsNothing, reason: locale);
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
    await tester.tap(find.byType(BrandMark));
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

  testWidgets('a folded card has its name and summary and nothing else to '
      'press: a tap anywhere opens and pings it', (tester) async {
    final controller = _Controller();
    await _pump(tester, _phone(), controller: controller);
    expect(find.byType(ServiceCard), findsOneWidget, reason: 'one card: open');
    expect(find.text('در حال استفاده'), findsNothing, reason: 'one card');
    await tester.tap(_icon(ShikooIcon.chevronUp));
    await tester.pumpAndSettle();
    final folded = find.byType(FoldedServiceCard);
    expect(folded, findsOneWidget);
    for (final button in [ShikooIconButton, ShikooButton]) {
      expect(
        find.descendant(of: folded, matching: find.byType(button)),
        findsNothing,
        reason: 'no $button: no update, no ping',
      );
    }
    expect(
      find.descendant(of: folded, matching: find.byType(StatusChip)),
      findsOneWidget,
    );
    await tester.tap(find.textContaining('مصرف', findRichText: true));
    await tester.pumpAndSettle();
    verify(() => controller.openService(0)).called(1);
    expect(find.byType(ServerRow), findsNWidgets(3));
  });

  testWidgets('two services or more all start folded, in their own order with '
      'the one in use where it is; a tap opens one, the open one folds, and '
      'its arrow folds them all', (tester) async {
    final controller = _Controller();
    final holder = await _pump(
      tester,
      _cards(order: const [7, 0, 8]),
      controller: controller,
    );
    expect(find.byType(ServiceCard), findsNothing);
    expect(find.byType(FoldedServiceCard), findsNWidgets(3));
    double top(String user) => tester.getTopLeft(find.textContaining(user)).dy;
    expect(top('user789'), lessThan(top('user123')));
    expect(top('user123'), lessThan(top('user456')));

    await tester.tap(find.textContaining('user456'));
    await tester.pumpAndSettle();
    verify(() => controller.openService(8)).called(1);
    verifyNever(() => controller.selectService(any()));

    for (final (open, user) in [(8, 'user456'), (7, 'user789')]) {
      holder.value = _cards(order: const [7, 0, 8], open: open);
      await tester.pumpAndSettle();
      expect(find.byType(FoldedServiceCard), findsNWidgets(2));
      expect(
        find.ancestor(
          of: find.textContaining(user),
          matching: find.byType(ServiceCard),
        ),
        findsOneWidget,
        reason: 'only $user open',
      );
    }
    await tester.tap(_icon(ShikooIcon.chevronUp));
    verify(() => controller.openService(null)).called(1);
  });

  testWidgets('a card opened below the open one keeps its top under the '
      'finger while the other folds', (tester) async {
    final controller = _Controller();
    final long = [
      for (var i = 1; i <= 12; i++)
        ShikooServer(name: 'سرور $i', type: 'Vless', ping: 80 + i),
    ];
    final holder = await _pump(
      tester,
      _cards(order: const [7, 0, 8], open: 0, servers: long),
      controller: controller,
    );
    when(() => controller.openService(8)).thenAnswer((_) {
      holder.value = _cards(
        order: const [7, 0, 8],
        open: 8,
        servers: long,
        opened: 8,
        openedServers: long,
      );
    });
    tester.view.physicalSize = const Size(824, 1000);
    await tester.pumpAndSettle();
    final head = find.textContaining('user456');
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -10000),
    );
    await tester.pumpAndSettle();
    double top() => tester
        .getTopLeft(
          find.ancestor(
            of: head,
            matching: find.byWidgetPredicate(
              (w) => w is FoldedServiceCard || w is ServiceCard,
            ),
          ),
        )
        .dy;
    final before = top();
    await tester.tap(head);
    await tester.pumpAndSettle();
    expect(top(), closeTo(before, 0.5));
  });

  testWidgets('on the TV each folded card is one stop; toward the cards the '
      'power button goes to the one in use, OK opens it with the remote on its '
      'ping, down reaches the first server, and toward the power button goes '
      'back', (tester) async {
    final controller = _Controller();
    ShikooState tv([int? open]) => _cards(
      isTV: true,
      order: const [7, 8, 0],
      connection: ShikooConnection.on,
      open: open,
      pinging: open == null ? null : (done: 1, total: 3),
    );
    final holder = await _pump(tester, tv(), controller: controller);
    when(() => controller.openService(0)).thenAnswer((_) {
      holder.value = tv(0);
    });
    await tester.pumpAndSettle();
    String? focused() {
      final at = FocusManager.instance.primaryFocus?.context;
      if (at?.findAncestorWidgetOfExactType<PowerButton>() != null) {
        return 'power';
      }
      if (at?.findAncestorWidgetOfExactType<ServerRow>() case final row?) {
        return row.server.name;
      }
      if (at?.findAncestorWidgetOfExactType<FoldedServiceCard>()
          case final card?) {
        return card.service.name;
      }
      return at?.findAncestorWidgetOfExactType<ShikooButton>()?.label;
    }

    Future<String?> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      return focused();
    }

    expect(focused(), 'power');
    expect(
      await press(LogicalKeyboardKey.arrowRight),
      'user123 · الماس',
      reason: 'the card in use, not the first',
    );
    expect(await press(LogicalKeyboardKey.arrowUp), 'user456 · طلایی');
    expect(await press(LogicalKeyboardKey.arrowDown), 'user123 · الماس');
    expect(await press(LogicalKeyboardKey.select), 'پینگ');
    verify(() => controller.openService(0)).called(1);
    expect(
      find.descendant(
        of: find.widgetWithText(ShikooButton, 'پینگ'),
        matching: find.byType(Spinner),
      ),
      findsOneWidget,
      reason: 'it spins at once',
    );
    expect(await press(LogicalKeyboardKey.arrowDown), _servers.first.name);
    expect(await press(LogicalKeyboardKey.arrowLeft), 'power');
    expect(
      await press(LogicalKeyboardKey.arrowRight),
      'آلمان ۲',
      reason: 'open, its selected server',
    );
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

    final lastMonth = shikooNow().subtract(const Duration(days: 20));
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

  for (final isTV in [false, true]) {
    testWidgets('${isTV ? 'on the TV' : 'on the phone'} rows slide to a new '
        'order rather than jump', (tester) async {
      final holder = await _pump(tester, _phone(isTV: isTV));
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pump();
      double top(String name) =>
          tester.getTopLeft(find.widgetWithText(ServerRow, name)).dy;
      final from = top('آلمان ۱');
      final to = top('هلند ۱');

      holder.value = _phone(servers: _servers.reversed.toList(), isTV: isTV);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(top('آلمان ۱'), allOf(lessThan(from), greaterThan(to)));
      await tester.pumpAndSettle();
      expect(top('آلمان ۱'), to);
    });
  }

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
        open: 0,
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
    final now = shikooNow();
    ShikooState state(
      ShikooService current,
      List<ShikooService> others, {
      ShikooConnection connection = ShikooConnection.off,
      List<int> order = const [],
    }) => ShikooState(
      connection: connection,
      connectedFor: Duration.zero,
      isTV: false,
      servers: const [],
      service: current,
      others: others,
      order: order,
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
    const later = ShikooService(id: 5, name: 'e', usedBytes: 1, totalBytes: 9);
    expect(
      serviceInstead(state(usedUp, [active, later], order: [5, 1, 2])),
      5,
      reason: 'the first that can in the saved order',
    );
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
    final now = shikooNow();
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
    expect(_inFinished(_small), findsNWidgets(3));
    expect(
      find.text('با «تمدید» دوباره وصل می‌شوی.'),
      findsNothing,
      reason: 'the selected service works',
    );
  });

  testWidgets('with nothing to connect, the service of the full card is never '
      'in the finished row too, and the row counts the rest', (tester) async {
    final now = shikooNow();
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
      expect(_inFinished(_small), findsNWidgets(count));
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
    final now = shikooNow().toUtc();
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
    expect(
      {
        for (final row in ['acct6', 'acct1', 'acct2', 'acct3'])
          row: _rowAction(tester, row),
      },
      {'acct6': 'تمدید', 'acct1': null, 'acct2': 'تمدید', 'acct3': null},
      reason:
          'the bot renews neither a removed nor a failed service (#31); '
          "support is the top bar's",
    );
  });

  testWidgets('on the TV, OK on a removed service of the finished row opens '
      "nothing, never the bot's renewal (#31)", (tester) async {
    await _pump(
      tester,
      _phone(isTV: true),
      account: const ShikooAccount(
        bot: 'Test_Shikoo_bot',
        services: [
          LinkedService(id: 7, title: 'acct7 · removed', status: 'removed'),
        ],
      ),
    );
    final head = find.text('سرویس‌های تمام‌شده (۱)');
    Focus.of(tester.element(head)).requestFocus();
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('acct7'), findsOneWidget, reason: 'open');
    expect(find.byType(QrTile), findsNothing);
  });

  testWidgets('a finished row the door says the bot will not renew has '
      'support, on this device or not; one it will renew, or one it says '
      'nothing of, keeps renewal', (tester) async {
    final lastMonth = shikooNow().subtract(const Duration(days: 20));
    ShikooService device(int id) => ShikooService(
      id: id,
      name: 'dev$id · طلایی',
      usedBytes: 1,
      totalBytes: 100,
      expire: lastMonth,
    );
    await _pump(
      tester,
      ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: false,
        servers: _servers,
        service: _phone().service,
        others: [device(4), device(5)],
      ),
      account: const ShikooAccount(
        services: [
          LinkedService(
            id: 40,
            title: 'dev4 · طلایی',
            status: 'active',
            profileId: 4,
            renewable: false,
          ),
          LinkedService(
            id: 50,
            title: 'dev5 · طلایی',
            status: 'active',
            profileId: 5,
          ),
          LinkedService(
            id: 1,
            title: 'acct1 · off',
            status: 'disabled',
            renewable: false,
          ),
          LinkedService(
            id: 2,
            title: 'acct2 · late',
            status: 'expired',
            renewable: true,
          ),
          LinkedService(
            id: 3,
            title: 'acct3 · used',
            status: 'exhausted',
            renewable: false,
          ),
        ],
      ),
    );
    final head = find.text('سرویس‌های تمام‌شده (۵)');
    await tester.ensureVisible(head);
    await tester.tap(head);
    await tester.pumpAndSettle();
    expect(
      {
        for (final row in ['acct1', 'acct2', 'acct3', 'dev4', 'dev5'])
          row: _rowAction(tester, row),
      },
      {
        'acct1': null,
        'acct2': 'تمدید',
        'acct3': null,
        'dev4': null,
        'dev5': 'تمدید',
      },
    );
  });

  testWidgets('a card on this device the door says the bot will not renew has '
      'support alone, the remote resting on it and no line asking for '
      'renewal; without the word the card is as before', (tester) async {
    ShikooAccount account(bool? renewable) => ShikooAccount(
      bot: 'Test_Shikoo_bot',
      services: [
        LinkedService(
          id: 50,
          title: 'user123 · الماس',
          status: 'active',
          profileId: 0,
          renewable: renewable,
        ),
      ],
    );
    String? focused() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<ShikooButton>()
        ?.label;
    final usedUp = ShikooState(
      connection: ShikooConnection.off,
      connectedFor: Duration.zero,
      isTV: true,
      servers: _servers,
      selected: 'آلمان ۲',
      service: ShikooService(
        name: 'user123 · الماس',
        usedBytes: 100 << 30,
        totalBytes: 100 << 30,
        expire: DateTime(2099),
      ),
    );
    for (final renewable in [false, null]) {
      final renews = renewable == null;
      for (final tv in [false, true]) {
        final why = 'renewable $renewable, active, ${tv ? 'TV' : 'phone'}';
        await _pump(tester, _phone(isTV: tv), account: account(renewable));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(ShikooButton, 'تمدید'),
          renews ? findsOneWidget : findsNothing,
          reason: why,
        );
        expect(
          find.widgetWithText(ShikooButton, 'پشتیبانی'),
          findsOneWidget,
          reason: why,
        );
        if (!tv) continue;
        tester
            .widget<ServerRow>(find.byType(ServerRow).first)
            .focusNode!
            .requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(
          focused(),
          'به‌روزرسانی',
          reason: '$why, up from the first server: no row of buttons between',
        );
      }
      final why = 'renewable $renewable, used up, TV';
      await _pump(tester, usedUp, account: account(renewable));
      await tester.pumpAndSettle();
      expect(focused(), renews ? 'تمدید' : 'پشتیبانی', reason: why);
      expect(
        find.text('با «تمدید» دوباره وصل می‌شوی.'),
        renews ? findsOneWidget : findsNothing,
        reason: why,
      );
    }
    ProviderScope.containerOf(
      tester.element(find.byType(ShikooHome)),
    ).read(shikooAccountProvider.notifier).set(account(false));
    await tester.pumpAndSettle();
    expect(
      focused(),
      'پشتیبانی',
      reason: 'a sync takes renewal away under the remote',
    );
  });

  testWidgets('a used-up card on this device the bot will not renew says so, '
      'folded and open, instead of asking for renewal', (tester) async {
    const notRenewable =
        'این سرویس تمدید نمی‌شود؛ برای ادامه از «پشتیبانی» بپرس.';
    ShikooState usedUp({required int open}) => ShikooState(
      connection: ShikooConnection.off,
      connectedFor: Duration.zero,
      isTV: false,
      servers: _servers,
      service: const ShikooService(
        name: 'user123 · الماس',
        usedBytes: 100 << 30,
        totalBytes: 100 << 30,
      ),
      others: const [
        ShikooService(
          id: 7,
          name: 'user789 · معمولی',
          usedBytes: 0,
          totalBytes: 0,
        ),
      ],
      open: open,
    );
    for (final renewable in [false, null]) {
      final renews = renewable == null;
      final account = ShikooAccount(
        services: [
          LinkedService(
            id: 50,
            title: 'user123 · الماس',
            status: 'active',
            profileId: 0,
            renewable: renewable,
          ),
        ],
      );
      await _pump(tester, usedUp(open: 7), account: account);
      await tester.pumpAndSettle();
      expect(
        find.text('حجمش تمام شد. با تمدید دوباره فعال می‌شود.'),
        renews ? findsOneWidget : findsNothing,
        reason: 'renewable $renewable, folded',
      );
      expect(
        find.text(notRenewable),
        renews ? findsNothing : findsOneWidget,
        reason: 'renewable $renewable, folded',
      );
      await _pump(tester, usedUp(open: 0), account: account);
      await tester.pumpAndSettle();
      expect(
        find.text('فهرست سرورها بعد از تمدید برمی‌گردد.'),
        renews ? findsOneWidget : findsNothing,
        reason: 'renewable $renewable, open',
      );
      expect(
        find.text(notRenewable),
        renews ? findsNothing : findsOneWidget,
        reason: 'renewable $renewable, open',
      );
    }
  });

  testWidgets('a service the shop turned off reads «غیرفعال شد» and comes last '
      'whatever its date; hidden only 30 days after a past one', (
    tester,
  ) async {
    final now = shikooNow().toUtc();
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
    final now = shikooNow();
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
    final now = shikooNow();
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
          updatedAt: DateTime.now(),
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
    expect(
      name.style!.fontSize,
      ShikooSizes.phone.title * ShikooSizes.nameShrinkMin,
      reason: 'the font shrinks before the cut',
    );
    final card = tester.getRect(find.byType(ServiceCard));
    for (final label in ['به‌روزرسانی سرورها', 'پینگ سرورها']) {
      final button = tester.getRect(find.bySemanticsLabel(label));
      expect(
        card.left <= button.left && button.right <= card.right,
        isTrue,
        reason: '$label $button inside $card',
      );
    }
    expect(find.text('پینگ همه'), findsNothing);
  });

  testWidgets('a long name has a row of its own, two lines at most, the font '
      'at its smallest before any cut, and the status and buttons under it, '
      'the update time under them in full width when it does not fit: open '
      'or folded, in large text on a small phone and on the TV', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const tier = '🥇سرویس تیتانیوم - مولتی لوکیشن🎯';
    final now = shikooNow();
    for (final isTV in [false, true]) {
      tester.platformDispatcher.textScaleFactorTestValue = isTV ? 1 : 1.45;
      await _pump(
        tester,
        ShikooState(
          connection: ShikooConnection.off,
          connectedFor: Duration.zero,
          isTV: isTV,
          servers: _servers,
          selected: 'آلمان ۲',
          service: ShikooService(
            id: 1,
            name: '5550123_7000000123_101 · $tier',
            usedBytes: 41 << 30,
            totalBytes: 200 << 30,
            expire: now.add(const Duration(days: 30)),
            updatedAt: DateTime.now(),
          ),
          others: [
            ShikooService(
              id: 2,
              name: '2059054_7000000123_102 · $tier',
              usedBytes: 88 << 30,
              totalBytes: 200 << 30,
              expire: now.add(const Duration(days: 79)),
              updatedAt: DateTime.now(),
            ),
          ],
          open: 1,
        ),
      );
      if (!isTV) tester.view.physicalSize = const Size(686, 1524);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final title = isTV ? ShikooSizes.tv.title : ShikooSizes.phone.title;
      for (final (card, open) in [
        (find.byType(ServiceCard), true),
        (find.byType(FoldedServiceCard), false),
      ]) {
        final where = '${isTV ? 'TV' : 'phone'} ${open ? 'open' : 'folded'}';
        Finder inside(Finder finder) =>
            find.descendant(of: card, matching: finder);
        final text = inside(
          find.descendant(
            of: find.byType(ServiceName),
            matching: find.byType(Text),
          ),
        );
        final name = tester.widget<Text>(text);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: text, matching: find.byType(RichText)),
        );
        final lines = paragraph
            .getBoxesForSelection(
              TextSelection(
                baseOffset: 0,
                extentOffset: paragraph.text.toPlainText().length,
              ),
            )
            .map((box) => box.top.round())
            .toSet();
        expect(lines.length, lessThanOrEqualTo(2), reason: where);
        expect(name.data, contains('…'), reason: '$where: the test font');
        expect(
          name.style!.fontSize,
          title * ShikooSizes.nameShrinkMin,
          reason: '$where: at its smallest before the cut',
        );
        final box = tester.getRect(text);
        expect(
          tester.getRect(card).contains(box.topLeft) &&
              tester.getRect(card).contains(box.bottomRight),
          isTrue,
          reason: '$where: $box',
        );
        final ping = isTV
            ? find.widgetWithText(ShikooButton, 'پینگ')
            : find.bySemanticsLabel('پینگ سرورها');
        for (final under in [
          inside(find.byType(StatusChip)),
          if (open) inside(ping),
        ]) {
          expect(
            tester.getRect(under).top,
            greaterThanOrEqualTo(box.bottom),
            reason: '$where: $under under the name',
          );
        }
        if (!isTV && open) {
          final chip = tester.getRect(inside(find.byType(StatusChip)));
          final sub = tester.getRect(inside(find.textContaining('به‌روز شد')));
          expect(
            sub.top >= chip.bottom &&
                sub.left < tester.getRect(inside(ping)).right,
            isTrue,
            reason: '$where: the update time under the line, full width: $sub',
          );
        }
        final arrow = inside(
          _icon(open ? ShikooIcon.chevronUp : ShikooIcon.chevronDown),
        );
        if (isTV && open) {
          expect(arrow, findsNothing);
        } else {
          final y = tester.getCenter(arrow).dy;
          expect(
            box.top < y && y < box.bottom,
            isTrue,
            reason: '$where: the arrow beside the name',
          );
        }
      }
    }
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
    final de = bidiName('آلمان ۲');
    await _pump(tester, failed(isTV: false));
    expect(
      find.text(
        '$de تا ۳۰ ثانیه جواب نداد. دوباره بزن، یا از فهرست سرور دیگری '
        'انتخاب کن.',
      ),
      findsOneWidget,
    );
    await _pump(tester, failed(isTV: true));
    expect(
      find.text('$de تا ۳۰ ثانیه جواب نداد.\nسرور دیگری را امتحان کن.'),
      findsOneWidget,
    );
  });

  testWidgets("a server's name reads from its first letter, as Telegram shows "
      "it, at the layout's start edge, and stays whole inside a sentence", (
    tester,
  ) async {
    const names = {
      'NL 3 x ضریب مصرف ': TextDirection.ltr,
      'Spain (Netflix+Twitch بدون تبلیغ)': TextDirection.ltr,
      'Norway 🦄': TextDirection.ltr,
      'Ireland ♡': TextDirection.ltr,
      'Poland 1': TextDirection.ltr,
      '۲ Poland': TextDirection.ltr,
      '٢ Poland': TextDirection.ltr,
      '#۱ Poland': TextDirection.ltr,
      '\u200FPoland 3': TextDirection.rtl,
      '\u200Eهلند ۲': TextDirection.ltr,
      'سوئد ۳ Pro': TextDirection.rtl,
      '🔥 هلند ۱': TextDirection.rtl,
      'قبل از اتصال به‌روزرسانی کنید': TextDirection.rtl,
    };
    final mixed = names.keys.first;
    ShikooState phone({ShikooConnection connection = ShikooConnection.off}) =>
        ShikooState(
          connection: connection,
          connectedFor: Duration.zero,
          isTV: false,
          service: _phone().service,
          servers: [
            for (final name in names.keys)
              ShikooServer(
                name: name,
                type: 'Vless',
                ping: name == mixed ? -1 : 90,
              ),
          ],
          selected: mixed,
        );
    final wrong = <String>[];
    for (final (locale, start) in [
      ('fa', TextAlign.right),
      ('en', TextAlign.left),
    ]) {
      await _pump(tester, phone(), locale: locale);
      for (final MapEntry(key: name, value: direction) in names.entries) {
        final shown = tester.widgetList<Text>(find.text(name.trim()));
        if (shown.isEmpty) wrong.add('$locale $name: not shown');
        for (final text in shown) {
          if (text.textDirection != direction || text.textAlign != start) {
            wrong.add('$locale $name: ${text.textDirection} ${text.textAlign}');
          }
        }
      }
    }
    expect(wrong, isEmpty);

    await _pump(tester, phone(connection: ShikooConnection.on));
    expect(
      find.textContaining(
        'اینترنت از «\u2068NL\u00A03\u00A0x\u00A0ضریب\u00A0مصرف\u2069» رد نمی‌شود.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('connected with no internet: the amber button, the card in the '
      'speed pills\' place, and «انتخاب سرور دیگر» brings the fastest other '
      'server into view; the streaming server keeps the green button with '
      'its grey card, in English too', (tester) async {
    final many = [
      for (var i = 1; i <= 12; i++)
        ShikooServer(
          name: 'سرور $i',
          type: 'Vless',
          ping: i > 10 ? 70 + i : -1,
        ),
    ];
    ShikooState on(String selected, {List<ShikooServer>? servers}) =>
        ShikooState(
          connection: ShikooConnection.on,
          connectedFor: const Duration(minutes: 12, seconds: 47),
          isTV: false,
          service: _phone().service,
          servers: servers ?? many,
          selected: selected,
          sorted: true,
          connectedNoTraffic: true,
        );
    final controller = _Controller();
    await _pump(tester, on('سرور 1'), controller: controller);
    final label = find.text('وصل، بی‌اینترنت');
    expect(label, findsOneWidget);
    expect(
      tester.widget<Text>(label).style?.color,
      ShikooColors.light.onWarning,
    );
    expect(find.byType(SpeedPills), findsNothing);
    expect(
      find.text('اینترنت از «\u2068سرور\u00A01\u2069» رد نمی‌شود.'),
      findsOneWidget,
    );
    final fastest = find.widgetWithText(ServerRow, 'سرور 11');
    final screen = Offset.zero & tester.view.physicalSize / 2;
    expect(screen.contains(tester.getCenter(fastest)), isFalse);
    await tester.tap(find.text('انتخاب سرور دیگر'));
    await tester.pumpAndSettle();
    expect(screen.contains(tester.getCenter(fastest)), isTrue);
    verifyNever(
      () => controller.selectServer(any(), service: any(named: 'service')),
    );

    const free = '(رایگان) نماوا | فیلیمو | شیدا | گپ فیلم';
    final special = on(
      free,
      servers: [
        ...many,
        const ShikooServer(name: free, type: 'Shadowsocks', ping: 120),
      ],
    );
    await _pump(tester, special);
    expect(find.text('وصل'), findsOneWidget);
    expect(find.byType(SpeedPills), findsOneWidget);
    expect(find.text('فقط برای نماوا، فیلیمو، شیدا و گپ‌فیلم'), findsOneWidget);
    expect(find.textContaining('رد نمی‌شود'), findsNothing);

    await _pump(tester, special, locale: 'en');
    expect(
      find.text('Only for Namava, Filimo, Shayda and Gapfilm'),
      findsOneWidget,
    );
    await _pump(tester, on('سرور 1'), locale: 'en');
    expect(find.text('No internet'), findsOneWidget);
    expect(find.text('Choose another server'), findsOneWidget);
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
        others: [
          ShikooService(
            id: 6,
            name: 'user457 · طلایی',
            usedBytes: 1,
            totalBytes: 100,
            pasted: true,
            revoked: true,
          ),
        ],
        open: 4,
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
        'حذفش کن، یا لینک تازه را از ربات یا نماینده‌ات بگیر و با «+» بالای '
        'خانه بچسبان.',
      ),
      findsOneWidget,
      reason: 'the folded card; Settings has no paste row once signed in',
    );
    expect(
      find.bySemanticsLabel('افزودن سرویس با لینک'),
      findsOneWidget,
      reason: 'the «+» it names is there',
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

  testWidgets(
    'a revoked card says only «به‌روز نشد» open, and folded no update '
    'time at all; a service without a name is «سرویس شیکونت»',
    (tester) async {
      final updated = DateTime.now().subtract(const Duration(minutes: 10));
      ShikooService revoked(int id) => ShikooService(
        id: id,
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
          service: revoked(4),
          others: [
            revoked(6),
            const ShikooService(id: 5, name: '', usedBytes: 1, totalBytes: 100),
          ],
          open: 4,
        ),
      );
      expect(find.text('به‌روز نشد'), findsOneWidget);
      expect(find.textContaining('پیش'), findsNothing);
      expect(find.text(bidiName('سرویس شیکونت')), findsOneWidget);
    },
  );

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
    // The test font is wider than Vazirmatn: the folded card's name may be cut to fit.
    expect(
      tester
          .widgetList<ServiceName>(find.byType(ServiceName))
          .map((w) => w.name),
      ['سرویس شیکونت', 'سرویس شیکونت ۲'],
    );
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
        name: 'e7f9 · pasargard_100000009',
        usedBytes: 1,
        totalBytes: 100,
      ),
      others: [
        ShikooService(
          id: 2,
          name: 'firstbuy · 2_100000009_100000009',
          usedBytes: 1,
          totalBytes: 100,
        ),
        ShikooService(
          id: 3,
          name: 'user123 · الماس',
          usedBytes: 1,
          totalBytes: 100,
        ),
        ShikooService(id: 4, name: '7000123_2', usedBytes: 1, totalBytes: 100),
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
        reason: '$locale: pasargard_100000009 reads left to right',
      );
      expect(
        left('2_1000', '2') < left('2_1000', '_') &&
            left('2_1000', '_') < left('2_1000', '_', 1),
        isTrue,
        reason: '$locale: 2_100000009_100000009 keeps its order',
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
      expect(
        left('7000123_2', '7') < left('7000123_2', '_') &&
            left('7000123_2', '_') < left('7000123_2', '2', 1),
        isTrue,
        reason: '$locale: a pasted name without a tier keeps its order',
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

  testWidgets('the phone pings with a gauge beside update in the open card '
      'only; one runs at a time, and its count replaces the update time', (
    tester,
  ) async {
    final controller = _Controller();
    when(() => controller.pingAll()).thenAnswer((_) async {});
    when(controller.refreshService).thenAnswer((_) async {});
    final holder = await _pump(
      tester,
      _withOther(ShikooConnection.off),
      controller: controller,
    );
    final ping = find.bySemanticsLabel('پینگ سرورها');
    final update = find.bySemanticsLabel('به‌روزرسانی سرورها');
    expect(ping, findsOneWidget, reason: 'the open card, not the folded one');
    expect(find.text('پینگ'), findsNothing, reason: 'the gauge alone');
    expect(find.text('پینگ همه'), findsNothing);

    await tester.tap(ping);
    verify(() => controller.pingAll()).called(1);

    holder.value = _withOther(
      ShikooConnection.off,
      pinging: (done: 4, total: 9),
    );
    await tester.pump();
    expect(find.text('پینگ ۴ از ۹'), findsOneWidget);
    await tester.tap(update);
    await tester.tap(ping);
    verifyNever(controller.refreshService);
    verifyNever(() => controller.pingAll());

    holder.value = _withOther(
      ShikooConnection.off,
      refresh: ShikooRefresh.running,
    );
    await tester.pump();
    await tester.tap(ping);
    verifyNever(() => controller.pingAll());
  });

  testWidgets('connected, a tap on a folded card only opens it: no question, '
      'and the connection stays', (tester) async {
    final controller = _Controller();
    await _pump(
      tester,
      _withOther(ShikooConnection.on),
      controller: controller,
    );
    final folded = find.textContaining('user789');
    await tester.ensureVisible(folded);
    await tester.tap(folded);
    await tester.pumpAndSettle();
    verify(() => controller.openService(7)).called(1);
    verifyNever(() => controller.selectService(any()));
    verifyNever(
      () => controller.selectServer(any(), service: any(named: 'service')),
    );
    expect(
      ModalRoute.of(tester.element(find.byType(ShikooHome)))!.isCurrent,
      isTrue,
      reason: 'no dialog',
    );
  });

  testWidgets('connected, another open card says a server there moves the '
      'connection; a tap moves it with no question, and the same box then says '
      'it did; off, it says nothing', (tester) async {
    final controller = _Controller();
    when(
      () => controller.selectServer(any(), service: any(named: 'service')),
    ).thenAnswer((_) async {});
    const hint = 'با زدنِ یک سرور، اتصال به این سرویس می‌رود.';
    const now = 'اتصال حالا از همین سرویس است.';
    final holder = await _pump(
      tester,
      _cards(connection: ShikooConnection.on, open: 7, opened: 7),
      controller: controller,
    );
    expect(find.text(hint), findsOneWidget);
    expect(find.bySemanticsLabel(now), findsNothing, reason: 'held room only');
    expect(
      tester
          .widgetList<ServerRow>(find.byType(ServerRow))
          .where((r) => r.selected),
      isEmpty,
      reason: 'the connection is not on this service',
    );
    Rect box() => tester.getRect(
      find
          .ancestor(of: find.text(hint), matching: find.byType(Container))
          .first,
    );
    final before = box();
    final row = find.widgetWithText(ServerRow, 'ترکیه ۱');
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    verify(() => controller.selectServer('ترکیه ۱', service: 7)).called(1);
    expect(
      ModalRoute.of(tester.element(find.byType(ShikooHome)))!.isCurrent,
      isTrue,
      reason: 'no question',
    );

    holder.value = _cards(
      connection: ShikooConnection.on,
      open: 7,
      current: 7,
      landed: (id: 7, arrived: true),
    );
    await tester.pumpAndSettle();
    expect(find.text(now), findsOneWidget);
    expect(box().height, before.height, reason: 'one box for both');

    holder.value = _cards(open: 7, opened: 7);
    await tester.pumpAndSettle();
    expect(find.text(hint), findsNothing);
    expect(find.text(now), findsNothing);
  });

  testWidgets('on the TV ping is a text button in the open card, its width '
      'kept while it spins; a folded card has none; another card connected '
      'says in its caption what a server there does', (tester) async {
    final holder = await _pump(
      tester,
      _withOther(ShikooConnection.on, isTV: true),
      controller: _Controller(),
    );
    final pings = find.widgetWithText(ShikooButton, 'پینگ');
    expect(pings, findsOneWidget);
    expect(
      find.descendant(of: find.byType(FoldedServiceCard), matching: pings),
      findsNothing,
    );
    final width = tester.getSize(pings).width;
    holder.value = _withOther(
      ShikooConnection.on,
      isTV: true,
      pinging: (done: 4, total: 9),
    );
    await tester.pump();
    expect(find.text('پینگ ۴ از ۹'), findsOneWidget);
    expect(
      find.descendant(of: pings, matching: find.byType(Spinner)),
      findsOneWidget,
    );
    expect(
      find.textContaining('سریع‌ترین بالا', findRichText: true),
      findsOneWidget,
      reason: 'the ping an open card starts sorts the list',
    );
    expect(tester.getSize(pings).width, width);

    holder.value = _cards(
      isTV: true,
      connection: ShikooConnection.on,
      open: 7,
      opened: 7,
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'با زدنِ یک سرور، اتصال به این سرویس می‌رود',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('the card in use has «در حال استفاده» over its name and a bar on '
      'its start edge, open or folded: green connected, grey off, connecting '
      'or failed', (tester) async {
    for (final connection in ShikooConnection.values) {
      final on = connection == ShikooConnection.on;
      for (final open in [null, 0]) {
        final where = '${connection.name}, ${open == null ? 'folded' : 'open'}';
        await _pump(tester, _cards(connection: connection, open: open));
        final card = find.ancestor(
          of: find.textContaining('user123'),
          matching: find.byType(open == null ? FoldedServiceCard : ServiceCard),
        );
        final label = find.descendant(
          of: card,
          matching: find.text('در حال استفاده'),
        );
        expect(label, findsOneWidget, reason: where);
        expect(find.text('در حال استفاده'), findsOneWidget, reason: where);
        expect(
          tester.widget<Text>(label).style!.color,
          on ? ShikooColors.light.positive : ShikooColors.light.textMuted,
          reason: where,
        );
        final bar = find.descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (w) => w is PositionedDirectional && w.start == -Space.s4,
          ),
        );
        final color =
            ((tester.widget<PositionedDirectional>(bar).child as Container)
                        .decoration!
                    as ShapeDecoration)
                .color;
        expect(
          color,
          on ? ShikooColors.light.positive : ShikooColors.light.outline,
          reason: where,
        );
        expect(
          tester.getRect(bar).right,
          closeTo(tester.getRect(card).right, 0.5),
          reason: '$where: on the card\'s start edge',
        );
        expect(
          tester.getRect(label).bottom,
          lessThanOrEqualTo(
            tester
                .getRect(
                  find.descendant(of: card, matching: find.byType(ServiceName)),
                )
                .top,
          ),
          reason: '$where: over the name',
        );
      }
    }
  });

  testWidgets('a folded card on the phone is the button, so its arrow is an '
      'icon with no 48-dp row: the name starts at the inset, or right under '
      '«در حال استفاده»', (tester) async {
    await _pump(tester, _cards(connection: ShikooConnection.on));
    for (final (user, inUse) in [('user123', true), ('user789', false)]) {
      final card = find.ancestor(
        of: find.textContaining(user),
        matching: find.byType(FoldedServiceCard),
      );
      Finder inside(Finder finder) =>
          find.descendant(of: card, matching: finder);
      final above = inUse
          ? tester.getRect(inside(find.text('در حال استفاده'))).bottom
          : tester.getTopLeft(card).dy + Space.s4;
      expect(
        tester.getTopLeft(inside(find.byType(ServiceName))).dy,
        closeTo(above, 0.5),
        reason: user,
      );
      expect(
        tester.getSize(inside(_icon(ShikooIcon.chevronDown))).height,
        ShikooSizes.phone.icon,
      );
    }
  });

  testWidgets('on the phone a card opens with its name and arrow where they '
      'were, and from its top edge to under the name is one fold button, a '
      'finger tall, which TalkBack presses too', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final (id, user) in [(0, 'user123'), (7, 'user789')]) {
      final controller = _Controller();
      final holder = await _pump(
        tester,
        _cards(connection: ShikooConnection.on),
        controller: controller,
      );
      Finder card() => find
          .ancestor(
            of: find.textContaining(user),
            matching: find.byWidgetPredicate(
              (w) => w is FoldedServiceCard || w is ServiceCard,
            ),
          )
          .first;
      Finder inside(Finder finder) =>
          find.descendant(of: card(), matching: finder);
      final arrow = find.byWidgetPredicate(
        (w) =>
            w is SvgIcon &&
            {ShikooIcon.chevronDown, ShikooIcon.chevronUp}.contains(w.icon),
      );
      double nameTop() =>
          tester.getTopLeft(inside(find.byType(ServiceName))).dy -
          tester.getTopLeft(card()).dy;
      // First in the tree: the fold arrow, before the update's «▾».
      final folded = (nameTop(), tester.getCenter(inside(arrow).first));
      holder.value = _cards(connection: ShikooConnection.on, open: id);
      await tester.pumpAndSettle();
      expect(nameTop(), closeTo(folded.$1, 0.5), reason: '$user: the name');
      expect(
        tester.getCenter(inside(arrow).first),
        within(distance: 0.5, from: folded.$2),
        reason: '$user: the arrow',
      );
      final button = tester.getRect(
        find
            .ancestor(
              of: inside(_icon(ShikooIcon.chevronUp)),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(button.top, closeTo(tester.getTopLeft(card()).dy, 0.5));
      expect(button.height, greaterThanOrEqualTo(ShikooSizes.touch));
      expect(
        button.bottom,
        greaterThanOrEqualTo(
          tester.getRect(inside(find.byType(ServiceName))).bottom,
        ),
      );
      await tester.tapAt(button.topCenter + const Offset(0, 4));
      verify(() => controller.openService(null)).called(1);
      final head = tester.getSemantics(
        find.bySemanticsLabel(RegExp(user)).first,
      );
      expect(
        head,
        isSemantics(isButton: true, isExpanded: true, hasTapAction: true),
        reason: user,
      );
      head.owner!.performAction(head.id, SemanticsAction.tap);
      verify(() => controller.openService(null)).called(1);
    }
    semantics.dispose();
  });

  testWidgets('a folded summary breaks only before «·», whatever the width', (
    tester,
  ) async {
    await _pump(tester, _cards());
    var breaks = 0;
    for (final width in [1000.0, 1100.0, 1200.0, 1600.0]) {
      tester.view.physicalSize = Size(width, 1830);
      await tester.pumpAndSettle();
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.textContaining('مصرف', findRichText: true),
      )) {
        final text = paragraph.text.toPlainText();
        double top(int i) => paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: i, extentOffset: i + 1),
            )
            .first
            .top;
        for (var i = 1; i < text.length; i++) {
          if (top(i) > top(i - 1) + 1) {
            breaks++;
            expect(text[i], '·', reason: '$width: «$text» breaks at $i');
          }
        }
      }
    }
    expect(breaks, greaterThan(0), reason: 'some width broke the line');
  });

  testWidgets('a service whose link did not load has its own card: «باز نشد» '
      "and try again, support being the top bar's; only a link not made yet "
      'sends to the bot', (tester) async {
    const account = ShikooAccount(
      who: TelegramAccount(name: 'مریم'),
      services: [
        LinkedService(
          id: 43,
          title: 'user456 · طلایی',
          status: 'active',
          loadFailed: true,
        ),
        LinkedService(id: 44, title: 'الماس ۱ ماهه ۱۰ گیگ', status: 'active'),
      ],
    );
    for (final isTV in [false, true]) {
      await _pump(
        tester,
        ShikooState(
          connection: ShikooConnection.off,
          connectedFor: Duration.zero,
          isTV: isTV,
          servers: const [],
        ),
        account: account,
      );
      await tester.pumpAndSettle();
      expect(find.text('باز نشد'), findsNWidgets(2), reason: 'chip and power');
      expect(
        find.text(
          'لینکِ این سرویس هست، ولی سرورهایش الان باز نشد. اینترنت را بررسی '
          'کن و «دوباره» را بزن.',
        ),
        findsOneWidget,
      );
      final failed = find.ancestor(
        of: find.textContaining('لینکِ این سرویس هست'),
        matching: find.byType(Column),
      );
      for (final (label, count) in [('دوباره', 1), ('پشتیبانی', 0)]) {
        expect(
          find.descendant(
            of: failed.first,
            matching: find.widgetWithText(ShikooButton, label),
          ),
          findsNWidgets(count),
          reason: '$label, TV $isTV',
        );
      }
      expect(find.widgetWithText(ShikooButton, 'پشتیبانی'), findsOneWidget);
      expect(find.text('بدون لینک'), findsOneWidget);
      expect(find.text(isTV ? 'ربات شیکونت' : 'باز کردن ربات'), findsOneWidget);
      if (isTV) {
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<ShikooButton>()
              ?.label,
          'دوباره',
        );
      }
    }
  });

  testWidgets('the staging app names itself apart from the real one', (
    tester,
  ) async {
    addTearDown(() => shikooStaging = false);
    for (final (staging, fa, en) in [
      (false, 'شیکونت', 'ShikooNet'),
      (true, 'شیکونت آزمایشی', 'ShikooNet Test'),
    ]) {
      shikooStaging = staging;
      await _pump(tester, _noService);
      expect(find.text(fa), findsOneWidget, reason: 'staging $staging');
      await _pump(tester, _noService, locale: 'en');
      expect(find.text(en), findsOneWidget, reason: 'staging $staging');
    }
  });

  testWidgets('top-bar-actions «ج»: renew and support stand before «+» and '
      'Settings, small and plain on the phone, as Settings is on the TV with '
      'the QR icon; a home with no service has neither, its card keeping '
      'support', (tester) async {
    await _pump(tester, _phone());
    final renew = tester.widget<ShikooButton>(_top('تمدید'));
    final support = tester.widget<ShikooButton>(_top('پشتیبانی'));
    expect((renew.small, renew.primary, renew.icon), (true, true, null));
    expect((support.small, support.primary, support.icon), (true, false, null));
    expect(
      [
        tester.getRect(_top('تمدید')).left -
            tester.getRect(_top('پشتیبانی')).right,
        tester.getRect(_top('پشتیبانی')).left -
            tester.getRect(find.bySemanticsLabel('افزودن سرویس با لینک')).right,
      ],
      [Space.s2, Space.s1],
      reason: 'right to left: renew, support, «+», Settings',
    );
    for (final label in ['تمدید', 'پشتیبانی']) {
      expect(
        find.descendant(
          of: find.byType(ServiceCard),
          matching: find.widgetWithText(ShikooButton, label),
        ),
        findsNothing,
        reason: 'an active card has no row of buttons',
      );
    }

    await _pump(tester, _phone(isTV: true));
    final settings = tester.getRect(_top('تنظیمات'));
    for (final label in ['تمدید', 'پشتیبانی']) {
      expect(tester.widget<ShikooButton>(_top(label)).icon, ShikooIcon.qr);
      expect(tester.getRect(_top(label)).height, settings.height);
    }
    expect(tester.widget<ShikooButton>(_top('تمدید')).primary, isTrue);
    expect(
      tester.getRect(_top('تمدید')).left -
          tester.getRect(_top('پشتیبانی')).right,
      Space.s3,
    );
    expect(tester.getRect(_top('پشتیبانی')).left - settings.right, Space.s3);

    for (final tv in [false, true]) {
      await _pump(
        tester,
        ShikooState(
          connection: ShikooConnection.off,
          connectedFor: Duration.zero,
          isTV: tv,
          servers: const [],
        ),
      );
      expect(find.widgetWithText(ShikooButton, 'تمدید'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ServiceCard),
          matching: find.widgetWithText(ShikooButton, 'پشتیبانی'),
        ),
        findsOneWidget,
        reason: 'TV $tv',
      );
      expect(find.widgetWithText(ShikooButton, 'پشتیبانی'), findsOneWidget);
    }
  });

  testWidgets("renew at the top: one service opens the bot's page at once; "
      'more list every one the bot renews, in the home\'s order with the ended '
      'last, and a row opens its own; the remote starts on the first row', (
    tester,
  ) async {
    await _pump(tester, _phone(isTV: true));
    await tester.tap(_top('تمدید'));
    await tester.pumpAndSettle();
    expect(find.text('کدام سرویس را تمدید کنی؟'), findsNothing);
    expect(tester.widget<QrTile>(find.byType(QrTile)).data, ShikooLinks.renew);

    final (state, account) = _many();
    await _pump(tester, state, account: account);
    Future<List<(String, String?)>> open() async {
      await tester.tap(_top('تمدید'));
      await tester.pumpAndSettle();
      return _choices(tester, 'کدام سرویس را تمدید کنی؟');
    }

    expect(await open(), [
      ('user123', 'فعال'),
      ('7000000123_700a', 'فعال'),
      ('7000000123_c0e0', 'تمام‌شده'),
    ], reason: 'not the revoked one, nor the one the bot will not renew');
    expect(
      find.text('بعد یک کد تصویری می‌آید که با دوربین گوشی اسکنش می‌کنی.'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('کدام سرویس را تمدید کنی؟'), findsNothing);
    expect(tester.widget<QrTile>(find.byType(QrTile)).data, ShikooLinks.renew);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    for (final (name, link) in [
      ('7000000123_700a', 'https://t.me/Test_Shikoo_bot?start=rnw_70'),
      ('7000000123_c0e0', ShikooLinks.renew),
    ]) {
      await open();
      await tester.tap(find.text(bidiName(name)));
      await tester.pumpAndSettle();
      expect(tester.widget<QrTile>(find.byType(QrTile)).data, link);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('an ended card keeps its renew, which opens its own page, not '
      'the list; in the list it comes last though in use', (tester) async {
    final now = shikooNow();
    await _pump(
      tester,
      ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: true,
        servers: _servers,
        open: 0,
        service: ShikooService(
          name: 'user123 · الماس',
          usedBytes: 1 << 30,
          totalBytes: 50 << 30,
          expire: now.subtract(const Duration(days: 2)),
        ),
        others: [
          ShikooService(
            id: 7,
            name: 'user789 · معمولی',
            usedBytes: 1 << 30,
            totalBytes: 50 << 30,
            expire: now.add(const Duration(days: 20)),
          ),
        ],
      ),
      account: const ShikooAccount(
        bot: 'Test_Shikoo_bot',
        services: [
          LinkedService(
            id: 50,
            title: 'user123 · الماس',
            status: 'expired',
            profileId: 0,
          ),
        ],
      ),
    );
    final own = find.descendant(
      of: find.byType(ServiceCard),
      matching: find.widgetWithText(ShikooButton, 'تمدید'),
    );
    expect(own, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ServiceCard),
        matching: find.widgetWithText(ShikooButton, 'پشتیبانی'),
      ),
      findsNothing,
    );
    await tester.tap(own);
    await tester.pumpAndSettle();
    expect(find.text('کدام سرویس را تمدید کنی؟'), findsNothing);
    expect(
      tester.widget<QrTile>(find.byType(QrTile)).data,
      'https://t.me/Test_Shikoo_bot?start=rnw_50',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(_top('تمدید'));
    await tester.pumpAndSettle();
    expect(_choices(tester, 'کدام سرویس را تمدید کنی؟'), [
      ('user789', 'فعال'),
      ('user123', 'تمام‌شده'),
    ]);
  });

  testWidgets(
    'support at the top: one link for all opens it at once; links '
    'that differ list every service, and a row opens its own under its name',
    (tester) async {
      var (state, account) = _many();
      await _pump(tester, state, account: account);
      await tester.tap(_top('پشتیبانی'));
      await tester.pumpAndSettle();
      expect(find.text('برای کدام سرویس پشتیبانی می‌خواهی؟'), findsNothing);
      expect(
        tester.widget<QrTile>(find.byType(QrTile)).data,
        ShikooLinks.support,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      (state, account) = _many(helpOf7: 'https://t.me/help_b');
      await _pump(tester, state, account: account);
      await tester.tap(_top('پشتیبانی'));
      await tester.pumpAndSettle();
      expect(_choices(tester, 'برای کدام سرویس پشتیبانی می‌خواهی؟'), [
        ('user123', 'فعال'),
        ('7000000123_700a', 'فعال'),
        ('user456', 'لینک باطل شده'),
        ('7000000123_c0e0', 'تمام‌شده'),
        ('user999', 'تمام‌شده'),
      ], reason: "the home's order: the revoked card, then the finished row");
      await tester.tap(find.text(bidiName('7000000123_700a')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<QrTile>(find.byType(QrTile)).data,
        'https://t.me/help_b',
      );
      expect(
        find.descendant(
          of: find
              .ancestor(of: find.byType(QrTile), matching: find.byType(Column))
              .first,
          matching: find.textContaining('7000000123_700a', findRichText: true),
        ),
        findsOneWidget,
        reason: 'its name under the code',
      );
    },
  );

  testWidgets("renew at the top lists the account's services with no link "
      'here that the bot renews, each by its own id, one whose state the '
      'account does not name with no chip; one alone opens at once', (
    tester,
  ) async {
    await _pump(
      tester,
      _phone(isTV: true),
      account: const ShikooAccount(
        bot: 'Test_Shikoo_bot',
        services: [
          LinkedService(id: 44, title: 'acct44 · نقره‌ای', status: 'active'),
          LinkedService(id: 45, title: 'acct45 · برنزی', status: 'on_hold'),
          LinkedService(
            id: 46,
            title: 'acct46 · طلایی',
            status: 'active',
            renewable: false,
          ),
        ],
      ),
    );
    await tester.tap(_top('تمدید'));
    await tester.pumpAndSettle();
    expect(_choices(tester, 'کدام سرویس را تمدید کنی؟'), [
      ('user123', 'فعال'),
      ('acct44', 'فعال'),
      ('acct45', null),
    ], reason: 'not acct46, which the bot will not renew');
    await tester.tap(find.text(bidiName('acct44')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<QrTile>(find.byType(QrTile)).data,
      'https://t.me/Test_Shikoo_bot?start=rnw_44',
    );

    await _pump(
      tester,
      const ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: true,
        servers: [],
      ),
      account: const ShikooAccount(
        bot: 'Test_Shikoo_bot',
        services: [
          LinkedService(id: 44, title: 'acct44 · نقره‌ای', status: 'active'),
        ],
      ),
    );
    await tester.tap(_top('تمدید'));
    await tester.pumpAndSettle();
    expect(find.text('کدام سرویس را تمدید کنی؟'), findsNothing);
    expect(
      tester.widget<QrTile>(find.byType(QrTile)).data,
      'https://t.me/Test_Shikoo_bot?start=rnw_44',
    );
  });

  testWidgets('support at the top weighs only what the home shows: a service '
      'ended long ago, hidden there, neither makes a list with its own link '
      'nor stands in one', (tester) async {
    final now = shikooNow();
    ShikooService service(int id, String name, {int days = 20, String? help}) =>
        ShikooService(
          id: id,
          name: name,
          usedBytes: 1 << 30,
          totalBytes: 50 << 30,
          expire: now.add(Duration(days: days)),
          supportUrl: help,
        );
    final hidden = service(
      5,
      'user555 · طلایی',
      days: -40,
      help: 'https://t.me/help_old',
    );
    ShikooState home(List<ShikooService> more) => ShikooState(
      connection: ShikooConnection.off,
      connectedFor: Duration.zero,
      isTV: true,
      servers: _servers,
      selected: 'آلمان ۲',
      service: service(0, 'user123 · الماس'),
      others: [hidden, ...more],
    );
    await _pump(tester, home([]));
    expect(find.textContaining('user555'), findsNothing, reason: '40 days');
    await tester.tap(_top('پشتیبانی'));
    await tester.pumpAndSettle();
    expect(find.text('برای کدام سرویس پشتیبانی می‌خواهی؟'), findsNothing);
    expect(
      tester.widget<QrTile>(find.byType(QrTile)).data,
      ShikooLinks.support,
    );

    await _pump(
      tester,
      home([service(7, 'user789 · معمولی', help: 'https://t.me/help_b')]),
    );
    await tester.tap(_top('پشتیبانی'));
    await tester.pumpAndSettle();
    expect(_choices(tester, 'برای کدام سرویس پشتیبانی می‌خواهی؟'), [
      ('user123', 'فعال'),
      ('user789', 'فعال'),
    ]);
  });

  testWidgets("with the account's one service ended long ago and no link here, "
      "the home shows none: support at the top opens Shikoo's own, and there "
      'is no renew', (tester) async {
    await _pump(
      tester,
      const ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: true,
        servers: [],
      ),
      account: ShikooAccount(
        bot: 'Test_Shikoo_bot',
        services: [
          LinkedService(
            id: 61,
            title: 'acct61 · طلایی',
            status: 'expired',
            expiresAt: shikooNow().subtract(const Duration(days: 40)),
          ),
        ],
      ),
    );
    expect(find.widgetWithText(ShikooButton, 'تمدید'), findsNothing);
    await tester.tap(_top('پشتیبانی'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('برای کدام سرویس پشتیبانی می‌خواهی؟'), findsNothing);
    expect(
      tester.widget<QrTile>(find.byType(QrTile)).data,
      ShikooLinks.support,
    );
  });

  testWidgets('support picked from the list reports the screen as it was at '
      "the top bar's tap, never a second picture over the list", (
    tester,
  ) async {
    final shots = _CountShots();
    final (state, account) = _many(helpOf7: 'https://t.me/help_b');
    await _pump(tester, state, account: account, diag: shots);
    await tester.tap(_top('پشتیبانی'));
    await tester.pumpAndSettle();
    expect(shots.taken, 1, reason: 'at the tap, before the list');
    await tester.tap(find.text(bidiName('7000000123_700a')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<QrTile>(find.byType(QrTile)).data,
      'https://t.me/help_b',
    );
    expect(shots.taken, 1);
  });

  // Last, as the font stays for every test after: the widths are Vazirmatn's, as on a phone.
  group('in Vazirmatn', () {
    setUpAll(loadShikooFonts);

    testWidgets('a 360 phone hides «شیکونت» once less than 8 would stay '
        'beside renew, at text 1.45 but not 1, and in neither language '
        'anything overflows or shrinks', (tester) async {
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final (locale, scale, word) in [
        ('fa', 1.0, true),
        ('fa', 1.45, false),
        ('en', 1.0, false),
        ('en', 1.45, false),
      ]) {
        final why = '$locale $scale';
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await _pump(tester, _phone(), locale: locale);
        tester.view.physicalSize = const Size(720, 1600);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: why);
        final l = lookupShikooL10n(Locale(locale));
        final name = find.text(l.appName);
        expect(name, word ? findsOneWidget : findsNothing, reason: why);
        expect(find.byType(BrandMark), findsOneWidget, reason: why);
        if (!word) {
          expect(
            find.bySemanticsLabel(l.appName),
            findsOneWidget,
            reason: '$why: a screen reader still hears the name',
          );
        }
        final renew = tester.getRect(_top(l.renew));
        expect(renew.height, ShikooSizes.touch, reason: '$why: not shrunk');
        if (word) {
          final gap = locale == 'fa'
              ? tester.getRect(name).left - renew.right
              : renew.left - tester.getRect(name).right;
          expect(gap, greaterThanOrEqualTo(Space.s2), reason: why);
        }
      }
    });
  });

  testWidgets("a phone keeps the server's name in the no-internet card's "
      'first line, where the TV says «this server»', (tester) async {
    const name = 'آلمان ۵ Reality';
    await _pump(
      tester,
      ShikooState(
        connection: ShikooConnection.on,
        connectedFor: const Duration(minutes: 1),
        isTV: false,
        service: _phone().service,
        servers: const [ShikooServer(name: name, type: 'Vless', ping: 70)],
        selected: name,
        connectedNoTraffic: true,
      ),
    );
    expect(
      find.text(
        'اینترنت از «\u2068آلمان\u00A0۵\u00A0Reality\u2069» رد نمی‌شود.',
      ),
      findsOneWidget,
    );
    expect(find.text('اینترنت از این سرور رد نمی‌شود.'), findsNothing);
  });
}

/// On the TV: in use (0), active with the bot's id 70 (7), ended lately (8), revoked (9), and
/// ended for good, the bot will not renew it (10).
(ShikooState, ShikooAccount) _many({String? helpOf7}) {
  final now = shikooNow();
  final ended = now.subtract(const Duration(days: 2));
  ShikooService service(
    int id,
    String name, {
    DateTime? expire,
    bool revoked = false,
    String? help,
  }) => ShikooService(
    id: id,
    name: name,
    usedBytes: 1 << 30,
    totalBytes: 50 << 30,
    expire: expire ?? now.add(const Duration(days: 20)),
    revoked: revoked,
    pasted: revoked,
    supportUrl: help,
  );
  return (
    ShikooState(
      connection: ShikooConnection.off,
      connectedFor: Duration.zero,
      isTV: true,
      servers: _servers,
      selected: 'آلمان ۲',
      service: service(0, 'user123 · الماس'),
      others: [
        service(7, '7000000123_700a · وایرگارد-ترید', help: helpOf7),
        service(8, '7000000123_c0e0 · الماس', expire: ended),
        service(9, 'user456 · طلایی', revoked: true),
        service(10, 'user999 · طلایی', expire: ended),
      ],
    ),
    const ShikooAccount(
      bot: 'Test_Shikoo_bot',
      services: [
        LinkedService(
          id: 70,
          title: '7000000123_700a · وایرگارد-ترید',
          status: 'active',
          profileId: 7,
        ),
        LinkedService(
          id: 100,
          title: 'user999 · طلایی',
          status: 'expired',
          profileId: 10,
          renewable: false,
        ),
      ],
    ),
  );
}

class _CountShots extends NoShots {
  int taken = 0;

  @override
  Future<Uint8List?> captureScreen() async {
    taken++;
    return null;
  }
}

/// The top bar's own [label]: it comes before any card's.
Finder _top(String label) => find.widgetWithText(ShikooButton, label).first;

/// [title]'s list of services, top down: each row's name and its chip, for names with a tier.
List<(String, String?)> _choices(WidgetTester tester, String title) {
  final dialog = find
      .ancestor(of: find.text(title), matching: find.byType(Column))
      .first;
  final rows = find
      .descendant(of: dialog, matching: find.byType(Pressable))
      .evaluate()
      .toList();
  (String, String?) row(Element element) {
    final texts = [
      for (final text in tester.widgetList<Text>(
        find.descendant(
          of: find.byElementPredicate((e) => e == element),
          matching: find.byType(Text),
        ),
      ))
        text.data!,
    ];
    final isolates = {0x2068, 0x2069};
    final name = texts.first.runes.where((rune) => !isolates.contains(rune));
    return (String.fromCharCodes(name), texts.length > 2 ? texts.last : null);
  }

  // The last is «بستن».
  return [for (final element in rows.take(rows.length - 1)) row(element)];
}

/// The open service and a folded one, `user789 · معمولی` (id 7).
ShikooState _withOther(
  ShikooConnection connection, {
  bool isTV = false,
  ({int done, int total})? pinging,
  ShikooRefresh refresh = ShikooRefresh.idle,
}) {
  final state = _phone(isTV: isTV);
  return ShikooState(
    connection: connection,
    connectedFor: const Duration(minutes: 1),
    isTV: isTV,
    servers: state.servers,
    selected: state.selected,
    service: state.service,
    pinging: pinging,
    refresh: refresh,
    open: 0,
    others: [
      ShikooService(
        id: 7,
        name: 'user789 · معمولی',
        usedBytes: 12 << 30,
        totalBytes: 50 << 30,
        expire: DateTime(2026, 12, 1, 12),
        updatedAt: DateTime.now(),
      ),
    ],
  );
}

String _whole(String text) => text.replaceAll(' ', '\u00A0');

/// Three services: `user123 · الماس` (0) in use, `user789 · معمولی` (7) and
/// `user456 · طلایی` (8); [opened] is the card given [openedServers].
ShikooState _cards({
  ShikooConnection connection = ShikooConnection.off,
  bool isTV = false,
  int? open,
  int current = 0,
  List<int> order = const [],
  int? opened,
  List<ShikooServer> servers = _servers,
  List<ShikooServer> openedServers = const [
    ShikooServer(name: 'ترکیه ۱', type: 'Vless', ping: 80),
    ShikooServer(name: 'هلند ۱', type: 'Vless', ping: 300),
  ],
  ShikooLanded? landed,
  ({int done, int total})? pinging,
  ({int done, int total})? openedPinging,
}) {
  ShikooService service(int id, String name, int used) => ShikooService(
    id: id,
    name: name,
    usedBytes: used << 30,
    totalBytes: 50 << 30,
    expire: DateTime(2026, 12, 1, 12),
    updatedAt: DateTime.now(),
  );
  final all = [
    service(0, 'user123 · الماس', 33),
    service(7, 'user789 · معمولی', 12),
    service(8, 'user456 · طلایی', 3),
  ];
  return ShikooState(
    connection: connection,
    connectedFor: const Duration(minutes: 1),
    isTV: isTV,
    servers: servers,
    selected: 'آلمان ۲',
    service: all.firstWhere((s) => s.id == current),
    others: [
      for (final s in all)
        if (s.id != current) s,
    ],
    open: open,
    order: order,
    pinging: pinging,
    landed: landed,
    opened: opened == null
        ? null
        : (
            id: opened,
            servers: openedServers,
            pinging: openedPinging,
            sorted: true,
          ),
  );
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
