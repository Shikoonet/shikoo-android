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
import 'package:flutter/rendering.dart' show RenderParagraph;
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

ShikooService _shelf(int id, {bool refused = false}) => ShikooService(
  id: id,
  name: 'user1001',
  usedBytes: 0,
  totalBytes: 0,
  usageKnown: false,
  outsourced: true,
  loginRefused: refused,
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

ShikooState _alone({bool isTV = false, bool refused = false}) => ShikooState(
  connection: ShikooConnection.off,
  connectedFor: Duration.zero,
  isTV: isTV,
  service: _shelf(2, refused: refused),
  servers: _servers,
  selected: 'آلمان ۱',
);

Future<void> _pump(
  WidgetTester tester,
  ShikooState state,
  ShikooAccount account, {
  String locale = 'fa',
  Size? window,
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
        theme: shikooThemeData(Brightness.light, tv: state.isTV),
        home: const ShikooHome(),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
        find.text('این حساب دیگر پذیرفته نمی‌شود؛ برای حساب تازه به ربات برو.'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('اعتبار و حجم'), findsNothing);
    expect(_in<ServiceCard>(_button('باز کردن ربات')), findsOneWidget);
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

  // Last, as the font stays for every test after: the widths are Vazirmatn's, as in the app.
  group('in Vazirmatn', () {
    setUpAll(loadShikooFonts);

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
  });
}
