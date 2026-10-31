import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/rendering.dart'
    show RenderParagraph, RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/no_shots.dart';

/// ovpn-shelf-card.html, design ب: a shelf account's card shows no date or volume and sends to the bot.
const _bot = 'Test_Shikoo_bot';

const _servers = [
  ShikooServer(name: 'آلمان ۱', type: 'OpenVPN', ping: 91),
  ShikooServer(name: 'آلمان ۲', type: 'OpenVPN', ping: 104),
];

final _bought = DateTime.utc(2026, 9, 30, 8);

ShikooService _shelf(
  int id, {
  bool refused = false,
  bool notHere = false,
  DateTime? bought,
  int? days,
}) => ShikooService(
  id: id,
  name: 'user1001',
  usedBytes: 0,
  totalBytes: 0,
  usageKnown: false,
  outsourced: true,
  loginRefused: refused,
  notHere: notHere,
  purchasedAt: bought,
  durationDays: days,
  updatedAt: DateTime.now(),
);

const _shelfLinked = LinkedService(
  id: 42,
  title: 'user1001',
  status: 'active',
  profileId: 2,
  renewable: false,
  outsourced: true,
);

ShikooService _usual() => ShikooService(
  id: 1,
  name: 'user123 · الماس',
  usedBytes: 34 << 30,
  totalBytes: 100 << 30,
  expire: DateTime.now().add(const Duration(days: 20)),
  updatedAt: DateTime.now(),
);

const _usualLinked = LinkedService(
  id: 50,
  title: 'user123 · الماس',
  status: 'active',
  profileId: 1,
);

ShikooState _besideUsual({bool isTV = false}) => ShikooState(
  connection: ShikooConnection.off,
  connectedFor: Duration.zero,
  isTV: isTV,
  service: _usual(),
  servers: _servers,
);

ShikooAccount _closedBeside(int daysAgo) => ShikooAccount(
  bot: _bot,
  services: [
    _usualLinked,
    LinkedService(
      id: 42,
      title: 'user1001',
      status: 'expired',
      renewable: false,
      outsourced: true,
      expiresAt: shikooNow().subtract(Duration(days: daysAgo)),
    ),
  ],
);

ShikooState _alone({
  bool isTV = false,
  bool refused = false,
  bool notHere = false,
  ShikooError? error,
  DateTime? bought,
  int? days,
}) => ShikooState(
  connection: error == null ? ShikooConnection.off : ShikooConnection.error,
  connectedFor: Duration.zero,
  isTV: isTV,
  service: _shelf(
    2,
    refused: refused,
    notHere: notHere,
    bought: bought,
    days: days,
  ),
  servers: _servers,
  selected: 'آلمان ۱',
  lastError: error,
);

Future<void> _pump(
  WidgetTester tester,
  ShikooState state,
  ShikooAccount account, {
  String locale = 'fa',
  Size? window,
  Brightness brightness = Brightness.light,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize =
        window ?? (state.isTV ? const Size(1920, 1080) : const Size(824, 1830))
    ..devicePixelRatio = window == null ? 2 : 1;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        noShots,
        shikooAccountProvider.overrideWith(() => ShikooCell(account)),
        shikooStateProvider.overrideWithValue(state),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(brightness, tv: state.isTV),
        builder: (_, child) => RepaintBoundary(key: _screen, child: child),
        home: const ShikooHome(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _screen = GlobalKey();

/// With `SHIKOO_SHOTS=<folder>`, the screen as a PNG there.
Future<void> _shot(WidgetTester tester, String name) async {
  final dir = Platform.environment['SHIKOO_SHOTS'];
  if (dir == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screen),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Finder _in<T>(Finder matching) =>
    find.descendant(of: find.byType(T), matching: matching);

Finder _button(String label) => find.widgetWithText(ShikooButton, label);

/// What the remote is on: a server name or a button label.
String? _focused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  final row = context.findAncestorWidgetOfExactType<ServerRow>();
  return row?.server.name ??
      context.findAncestorWidgetOfExactType<ShikooButton>()?.label;
}

Future<String?> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
  return _focused();
}

/// The TV's remote on «به‌روزرسانی», where it starts on a shelf account's card.
Future<void> _focusUpdate(WidgetTester tester) async {
  final update = find.ancestor(
    of: find.text('به‌روزرسانی'),
    matching: find.byType(Pressable),
  );
  Focus.of(
    tester.element(
      find.descendant(of: update, matching: find.byType(GestureDetector)),
    ),
  ).requestFocus();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('open on a phone: the protocol in grey, the guide and the bot, '
      'no volume, date or renew', (tester) async {
    await _pump(
      tester,
      _alone(),
      const ShikooAccount(bot: _bot, services: [_shelfLinked]),
    );
    expect(_in<ServiceCard>(find.text('OpenVPN')), findsOneWidget);
    expect(find.text('فعال'), findsNothing);
    expect(
      _in<ServiceCard>(
        find.text(
          'اعتبار و حجم این حساب این‌جا دیده نمی‌شود.\n'
          'اعتبارش از اولین اتصال شمرده می‌شود. برای حساب تازه، به ربات '
          'شیکونت برو.',
        ),
      ),
      findsOneWidget,
    );
    final bot = _in<ServiceCard>(_button('باز کردن ربات'));
    expect(bot, findsOneWidget);
    expect(tester.widget<ShikooButton>(bot).icon, ShikooIcon.plane);
    expect(find.byType(MeterBar), findsNothing);
    expect(find.textContaining('اعتبار تا'), findsNothing);
    expect(find.textContaining('روز باقی'), findsNothing);
    expect(_button('تمدید'), findsNothing, reason: 'nothing to renew');
    expect(_in<ServiceCard>(find.byType(ServerRow)), findsNWidgets(2));
  });

  testWidgets('folded beside a usual service: «اعتبار از اولین اتصال» in place '
      'of usage and date', (tester) async {
    await _pump(
      tester,
      ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: false,
        service: _usual(),
        others: [_shelf(2)],
        servers: _servers,
        open: 1,
      ),
      const ShikooAccount(bot: _bot, services: [_usualLinked, _shelfLinked]),
    );
    final folded = find.ancestor(
      of: find.text('اعتبار از اولین اتصال'),
      matching: find.byType(FoldedServiceCard),
    );
    expect(folded, findsOneWidget);
    expect(
      find.descendant(of: folded, matching: find.text('OpenVPN')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: folded, matching: find.textContaining('مصرف')),
      findsNothing,
    );
    expect(_button('تمدید'), findsOneWidget, reason: 'the usual one renews');
  });

  testWidgets('closed beside a usual service, it is a row of «سرویس‌های '
      'تمام‌شده» with no day and the bot, gone 30 days after the app saw it '
      'close', (tester) async {
    final state = _besideUsual();
    await _pump(tester, state, _closedBeside(2));
    final head = find.text('سرویس‌های تمام‌شده (۱)');
    await tester.ensureVisible(head);
    await tester.tap(head);
    await tester.pumpAndSettle();
    expect(find.text('اعتبارش تمام شد'), findsOneWidget);
    expect(find.textContaining('روز پیش'), findsNothing);
    final bot = _button('باز کردن ربات');
    expect(bot, findsOneWidget);
    expect(tester.widget<ShikooButton>(bot).icon, ShikooIcon.plane);
    await _pump(tester, state, _closedBeside(31));
    expect(find.textContaining('سرویس‌های تمام‌شده'), findsNothing);
  });

  testWidgets("on the TV that row is the remote's stop, and OK shows the "
      "bot's QR", (tester) async {
    await _pump(tester, _besideUsual(isTV: true), _closedBeside(2));
    final head = find.ancestor(
      of: find.text('سرویس‌های تمام‌شده (۱)'),
      matching: find.byType(Pressable),
    );
    Focus.of(
      tester.element(
        find.descendant(of: head, matching: find.byType(GestureDetector)),
      ),
    ).requestFocus();
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.select);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<Pressable>(),
      isNotNull,
    );
    expect(find.text('اعتبارش تمام شد'), findsOneWidget);
    expect(
      tester.widget<ShikooButton>(_button('ربات شیکونت')).icon,
      ShikooIcon.qr,
    );
    await _press(tester, LogicalKeyboardKey.select);
    expect(
      tester.widget<QrTile>(find.byType(QrTile)).data,
      'https://t.me/$_bot',
    );
  });

  testWidgets('closed: it ended, and the bot sells a new one', (tester) async {
    await _pump(
      tester,
      const ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: false,
        servers: [],
      ),
      const ShikooAccount(
        bot: _bot,
        services: [
          LinkedService(
            id: 42,
            title: 'user1001',
            status: 'expired',
            renewable: false,
            outsourced: true,
          ),
        ],
      ),
    );
    expect(
      find.text('اعتبارش تمام شد. برای حساب تازه، به ربات شیکونت برو.'),
      findsOneWidget,
    );
    expect(find.text('تمام‌شده'), findsOneWidget);
    expect(_button('باز کردن ربات'), findsOneWidget);
    expect(_button('تمدید'), findsNothing);
  });

  testWidgets('refused by its server, the box says so, with the same bot '
      'button', (tester) async {
    await _pump(
      tester,
      _alone(refused: true),
      const ShikooAccount(bot: _bot, services: [_shelfLinked]),
    );
    expect(
      _in<ServiceCard>(
        find.text(
          'این حساب دیگر پذیرفته نمی‌شود؛ احتمالاً زمانش تمام شده. برای حساب تازه به ربات برو.',
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('اعتبار و حجم'), findsNothing);
    expect(_in<ServiceCard>(_button('باز کردن ربات')), findsOneWidget);
  });

  testWidgets('refused, no server answering: no WARP line or offer, nor «check '
      "this phone's internet», above the card that says why", (tester) async {
    final l = lookupShikooL10n(const Locale('fa'));
    final aside = [
      find.text(l.warpOffTouch),
      _button(l.warpTurnOn),
      find.text(l.noServerAnsweredHelpTouch),
    ];
    await _pump(
      tester,
      _alone(error: ShikooError.noServer),
      const ShikooAccount(bot: _bot, services: [_shelfLinked]),
    );
    expect(
      [for (final f in aside) f.evaluate().length],
      [1, 1, 0],
      reason: 'not refused: WARP is offered, as for any service',
    );
    await _pump(
      tester,
      _alone(error: ShikooError.noServer, refused: true),
      const ShikooAccount(bot: _bot, services: [_shelfLinked]),
    );
    expect([for (final f in aside) f.evaluate().length], [0, 0, 0]);
    expect(
      find.text(
        'این حساب دیگر پذیرفته نمی‌شود؛ احتمالاً زمانش تمام شده. برای حساب تازه به ربات برو.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('in English, as the phone-b-en frame', (tester) async {
    await _pump(
      tester,
      _alone(),
      const ShikooAccount(bot: _bot, services: [_shelfLinked]),
      locale: 'en',
    );
    expect(
      find.text(
        "Validity and data aren't shown here.\n"
        'Its days count from the first connection. For a new one, go to the '
        'ShikooNet bot.',
      ),
      findsOneWidget,
    );
    expect(_button('Open the bot'), findsOneWidget);
  });

  testWidgets('on the TV the remote goes update, bot, first server, and the '
      "bot's button shows its QR", (tester) async {
    await _pump(
      tester,
      _alone(isTV: true),
      const ShikooAccount(bot: _bot, services: [_shelfLinked]),
    );
    final refresh = find.ancestor(
      of: find.text('به‌روزرسانی'),
      matching: find.byType(Pressable),
    );
    Focus.of(
      tester.element(
        find.descendant(of: refresh, matching: find.byType(GestureDetector)),
      ),
    ).requestFocus();
    await tester.pumpAndSettle();
    expect(_focused(), 'به‌روزرسانی');
    expect(await _press(tester, LogicalKeyboardKey.arrowDown), 'ربات شیکونت');
    expect(await _press(tester, LogicalKeyboardKey.arrowDown), 'آلمان ۱');
    expect(await _press(tester, LogicalKeyboardKey.arrowUp), 'ربات شیکونت');
    expect(await _press(tester, LogicalKeyboardKey.arrowUp), 'به‌روزرسانی');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    expect(
      tester.widget<QrTile>(find.byType(QrTile)).data,
      'https://t.me/$_bot',
    );
  });

  testWidgets('closed on the TV, the remote starts on the bot', (tester) async {
    await _pump(
      tester,
      const ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: true,
        servers: [],
      ),
      const ShikooAccount(
        bot: _bot,
        services: [
          LinkedService(
            id: 42,
            title: 'user1001',
            status: 'expired',
            renewable: false,
            outsourced: true,
          ),
        ],
      ),
    );
    expect(_focused(), 'ربات شیکونت');
    await _press(tester, LogicalKeyboardKey.select);
    expect(
      tester.widget<QrTile>(find.byType(QrTile)).data,
      'https://t.me/$_bot',
    );
  });

  group('the sale on a refused account', () {
    const refusedFa =
        'این حساب دیگر پذیرفته نمی‌شود؛ احتمالاً زمانش تمام شده. برای حساب تازه به ربات برو.';
    const refusedEn =
        'This account is no longer accepted; its time has probably run out. '
        'Go to the bot for a new account.';
    const account = ShikooAccount(bot: _bot, services: [_shelfLinked]);

    Finder inCard(String text) => _in<ServiceCard>(find.text(text));

    Future<void> refused(
      WidgetTester tester, {
      String locale = 'fa',
      DateTime? bought,
      int? days,
      bool isTV = false,
    }) => _pump(
      tester,
      _alone(refused: true, bought: bought, days: days, isTV: isTV),
      account,
      locale: locale,
    );

    testWidgets('a grey line under the red sentence, inside the same box: the '
        'date in Jalali with the plan in Persian, Gregorian in English, and '
        'the date alone when the plan is unknown', (tester) async {
      await refused(tester, bought: _bought, days: 30);
      expect(
        inCard('$refusedFa\nخرید ۸\u00A0مهر\u00A0۱۴۰۵ · یک‌ماهه'),
        findsOneWidget,
      );
      await refused(tester, bought: _bought);
      expect(inCard('$refusedFa\nخرید ۸\u00A0مهر\u00A0۱۴۰۵'), findsOneWidget);
      await refused(tester, locale: 'en', bought: _bought, days: 30);
      expect(
        inCard('$refusedEn\nBought Sep 30, 2026 · 1 month'),
        findsOneWidget,
      );
      await refused(tester, locale: 'en', bought: _bought);
      expect(inCard('$refusedEn\nBought Sep 30, 2026'), findsOneWidget);
      expect(_in<ServiceCard>(_button('Open the bot')), findsOneWidget);
    });

    testWidgets('the plan has its words, and any other length is its days', (
      tester,
    ) async {
      final seen = <String>[];
      for (final days in [30, 60, 90, 180, 360, 365, 45, 1]) {
        for (final locale in ['fa', 'en']) {
          await refused(tester, locale: locale, bought: _bought, days: days);
          final line = tester
              .widgetList<Text>(_in<ServiceCard>(find.byType(Text)))
              .map((text) => text.textSpan?.toPlainText() ?? '')
              .firstWhere(
                (text) =>
                    text.startsWith('این حساب') ||
                    text.startsWith('This account'),
              );
          seen.add(line.split('\n').last.split(' · ').last);
        }
      }
      expect(seen, [
        'یک‌ماهه',
        '1 month',
        'دوماهه',
        '2 months',
        'سه‌ماهه',
        '3 months',
        'شش‌ماهه',
        '6 months',
        'یک‌ساله',
        '1 year',
        'یک‌ساله',
        '1 year',
        '۴۵ روزه',
        '45 days',
        '۱ روزه',
        '1 day',
      ]);
    });

    testWidgets('no date, no line: a plan alone says nothing and the card is '
        'as it was', (tester) async {
      await refused(tester, days: 30);
      expect(inCard(refusedFa), findsOneWidget);
      expect(find.textContaining('خرید'), findsNothing);
      await refused(tester, locale: 'en', days: 30);
      expect(inCard(refusedEn), findsOneWidget);
      expect(find.textContaining('Bought'), findsNothing);
    });

    testWidgets('only the refused card has it: an open one, one that does not '
        'work here, a closed one and the folded summary keep their words', (
      tester,
    ) async {
      void noSale() {
        expect(find.textContaining('خرید'), findsNothing);
        expect(find.textContaining('۸\u00A0مهر'), findsNothing);
      }

      await _pump(tester, _alone(bought: _bought, days: 30), account);
      noSale();
      expect(find.textContaining('اعتبار و حجم'), findsOneWidget);

      await _pump(
        tester,
        _alone(refused: true, notHere: true, bought: _bought, days: 30),
        account,
      );
      noSale();
      expect(find.textContaining('روی ویندوز کار نمی‌کند'), findsOneWidget);

      await _pump(
        tester,
        const ShikooState(
          connection: ShikooConnection.off,
          connectedFor: Duration.zero,
          isTV: false,
          servers: [],
        ),
        ShikooAccount(
          bot: _bot,
          services: [
            LinkedService(
              id: 42,
              title: 'user1001',
              status: 'expired',
              renewable: false,
              outsourced: true,
              purchasedAt: _bought,
              durationDays: 30,
            ),
          ],
        ),
      );
      expect(
        find.text('اعتبارش تمام شد. برای حساب تازه، به ربات شیکونت برو.'),
        findsOneWidget,
      );
      noSale();

      await _pump(
        tester,
        ShikooState(
          connection: ShikooConnection.off,
          connectedFor: Duration.zero,
          isTV: false,
          service: _usual(),
          others: [_shelf(2, refused: true, bought: _bought, days: 30)],
          servers: _servers,
          open: 1,
        ),
        const ShikooAccount(bot: _bot, services: [_usualLinked, _shelfLinked]),
      );
      expect(find.text('اعتبار از اولین اتصال'), findsOneWidget);
      noSale();
    });

    testWidgets("on the TV the line is plain text: the remote's way and its "
        'ring are those of a card without it', (tester) async {
      Future<List<String?>> walk(DateTime? bought) async {
        await refused(tester, bought: bought, days: 30, isTV: true);
        await _focusUpdate(tester);
        return [
          _focused(),
          await _press(tester, LogicalKeyboardKey.arrowDown),
          await _press(tester, LogicalKeyboardKey.arrowDown),
          await _press(tester, LogicalKeyboardKey.arrowUp),
          await _press(tester, LogicalKeyboardKey.arrowUp),
        ];
      }

      final withoutSale = await walk(null);
      expect(find.textContaining('خرید'), findsNothing);
      final withSale = await walk(_bought);
      expect(
        inCard('$refusedFa\nخرید ۸\u00A0مهر\u00A0۱۴۰۵ · یک‌ماهه'),
        findsOneWidget,
      );
      expect(withSale, withoutSale);
      expect(withSale[1], 'ربات شیکونت');
    });
  });

  // Last, as the font stays for every test after: the widths are Vazirmatn's, as in the app.
  group('in Vazirmatn', () {
    setUpAll(loadShikooFonts);

    testWidgets('the refused card with its sale, in the frames the designer '
        'compares: the phone in both languages and themes, and the TV', (
      tester,
    ) async {
      const account = ShikooAccount(bot: _bot, services: [_shelfLinked]);
      for (final dark in [false, true]) {
        final theme = dark ? 'dark' : 'light';
        for (final language in ['fa', 'en']) {
          for (final (kind, days) in [('both', 30), ('date', null)]) {
            await _pump(
              tester,
              _alone(refused: true, bought: _bought, days: days),
              account,
              locale: language,
              brightness: dark ? Brightness.dark : Brightness.light,
            );
            expect(
              find.textContaining(language == 'fa' ? 'خرید' : 'Bought'),
              findsOneWidget,
            );
            await _shot(tester, 'phone-$language-$kind-$theme');
          }
        }
        await _pump(
          tester,
          _alone(isTV: true, refused: true, bought: _bought, days: 30),
          account,
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        expect(find.textContaining('خرید'), findsOneWidget);
        await _focusUpdate(tester);
        expect(
          await _press(tester, LogicalKeyboardKey.arrowDown),
          'ربات شیکونت',
        );
        await _shot(tester, 'tv-fa-both-$theme');
      }
    });

    testWidgets('in the 880 × 508 Windows page, open, folded and closed, in '
        'both languages at 100 and 150%: nothing overflows, no line is cut, '
        'and the bot button sits whole in its card', (tester) async {
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final closed = ShikooAccount(
        bot: _bot,
        services: [
          LinkedService(
            id: 42,
            title: 'user1001',
            status: 'expired',
            renewable: false,
            outsourced: true,
            expiresAt: shikooNow(),
          ),
        ],
      );
      final wrong = <String>[];
      for (final (name, state, account, bot) in [
        (
          'open',
          _alone(),
          const ShikooAccount(bot: _bot, services: [_shelfLinked]),
          true,
        ),
        (
          'folded',
          ShikooState(
            connection: ShikooConnection.off,
            connectedFor: Duration.zero,
            isTV: false,
            service: _usual(),
            others: [_shelf(2)],
            servers: _servers,
            open: 1,
          ),
          const ShikooAccount(
            bot: _bot,
            services: [_usualLinked, _shelfLinked],
          ),
          false,
        ),
        (
          'closed',
          const ShikooState(
            connection: ShikooConnection.off,
            connectedFor: Duration.zero,
            isTV: false,
            servers: [],
          ),
          closed,
          true,
        ),
        (
          'refused with its sale',
          _alone(refused: true, bought: _bought, days: 365),
          const ShikooAccount(bot: _bot, services: [_shelfLinked]),
          true,
        ),
      ]) {
        for (final language in ['fa', 'en']) {
          for (final scale in const [1.0, 1.5]) {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            await _pump(
              tester,
              state,
              account,
              locale: language,
              window: const Size(880, 508),
            );
            final at = '$name $language ×$scale';
            if (tester.takeException() case final error?) {
              wrong.add('$at: ${'$error'.split('\n').first}');
            }
            for (final paragraph in tester.renderObjectList<RenderParagraph>(
              find.byType(RichText),
            )) {
              if (paragraph.didExceedMaxLines) {
                wrong.add('$at cut: ${paragraph.text.toPlainText()}');
              }
            }
            final l = lookupShikooL10n(Locale(language));
            final button = _button(l.openBotTouch);
            if (bot != (button.evaluate().length == 1)) {
              wrong.add('$at: the bot button ${bot ? 'missing' : 'shown'}');
            } else if (bot) {
              await tester.ensureVisible(button);
              await tester.pumpAndSettle();
              final card = tester.getRect(
                find
                    .ancestor(
                      of: button,
                      matching: find.byWidgetPredicate(
                        (w) =>
                            w is Container &&
                            w.decoration is ShapeDecoration &&
                            (w.decoration! as ShapeDecoration).shadows != null,
                      ),
                    )
                    .first,
              );
              final rect = tester.getRect(button);
              if (rect.left < card.left || rect.right > card.right) {
                wrong.add('$at: the bot button $rect leaves its card $card');
              }
            }
          }
        }
      }
      expect(wrong, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets("on Windows a not-here account's round button is dimmed and "
        'passed over and its pill hidden, both in their usual places; a usual '
        'service has them back', (tester) async {
      final l = lookupShikooL10n(const Locale('fa'));
      final rects = <Rect>[];
      for (final notHere in [true, false]) {
        await _pump(
          tester,
          ShikooState(
            connection: ShikooConnection.off,
            connectedFor: Duration.zero,
            isTV: false,
            service: notHere ? _shelf(2, notHere: true) : _usual(),
            servers: notHere ? const [] : _servers,
            pick: ShikooPick.auto,
          ),
          const ShikooAccount(bot: _bot, services: [_shelfLinked]),
          window: const Size(880, 508),
        );
        final power = find.byType(PowerButton);
        final pill = find.ancestor(
          of: find.byType(NowPill),
          matching: find.byType(Visibility),
        );
        expect(
          (
            tester.widget<PowerButton>(power).onPressed == null,
            tester.widget<Visibility>(pill.first).visible,
          ),
          (notHere, !notHere),
          reason: 'not here: $notHere',
        );
        expect(
          find.descendant(of: power, matching: find.byType(Pressable)),
          notHere ? findsNothing : findsOneWidget,
        );
        expect(
          find.descendant(of: power, matching: find.text(l.powerConnect)),
          findsOneWidget,
        );
        final gauge = find.byWidgetPredicate(
          (w) => w is ShikooIconButton && w.icon == ShikooIcon.gauge,
        );
        expect(
          tester.widget<ShikooIconButton>(gauge).onPressed == null,
          notHere,
          reason: 'the ping button',
        );
        rects.add(tester.getRect(power));
      }
      expect(rects.first, rects.last);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    for (final b in Brightness.values) {
      for (final language in ['fa', 'en']) {
        testWidgets('on Windows, where no core runs OpenVPN yet, the card says '
            "so in the refused line's place, not in red, and keeps the bot "
            'button ($language, ${b.name})', (tester) async {
          // As the app has it there: its OpenVPN servers are not offered.
          await _pump(
            tester,
            ShikooState(
              connection: ShikooConnection.off,
              connectedFor: Duration.zero,
              isTV: false,
              service: _shelf(2, notHere: true),
              servers: const [],
              pick: ShikooPick.auto,
            ),
            const ShikooAccount(bot: _bot, services: [_shelfLinked]),
            locale: language,
            window: const Size(880, 508),
            brightness: b,
          );
          final l = lookupShikooL10n(Locale(language));
          final line = _in<ServiceCard>(find.text(l.outsourcedNotHere));
          expect(line, findsOneWidget);
          expect(find.textContaining(l.outsourcedTitle), findsNothing);
          expect(find.text(l.loadingServers), findsNothing);
          final colors = b == Brightness.light
              ? ShikooColors.light
              : ShikooColors.dark;
          final span = tester.widget<Text>(line).textSpan! as TextSpan;
          expect(span.children!.single.style!.color, colors.text);
          expect(_in<ServiceCard>(_button(l.openBotTouch)), findsOneWidget);
          await _shot(tester, 'w-not-here-$language-${b.name}');
        }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
      }
    }
  });
}
