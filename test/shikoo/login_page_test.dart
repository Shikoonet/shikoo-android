import 'package:fl_clash/shikoo/app/app.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/clock.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/login.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignIn extends Mock implements ShikooSignIn {}

class _Controller extends Mock implements ShikooController {}

final _stateCell = NotifierProvider<ShikooCell<ShikooState>, ShikooState>(
  () => ShikooCell(_state(tv: false)),
);

const _waiting = ShikooLogin(
  LoginPhase.waiting,
  code: '482915',
  botUrl: 'https://t.me/Test_Shikoo_bot?start=app_482915',
);

const _maryam = TelegramAccount(name: 'مریم', username: 'maryam_k');

ShikooState _state({required bool tv}) => ShikooState(
  connection: ShikooConnection.off,
  connectedFor: Duration.zero,
  isTV: tv,
  servers: const [],
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required bool tv,
  ShikooLogin? login,
  ShikooAccount account = const ShikooAccount(),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = tv ? const Size(1920, 1080) : const Size(824, 1830)
    ..devicePixelRatio = 2;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final signIn = _SignIn();
  when(signIn.start).thenAnswer((_) async => null);
  when(signIn.notMine).thenAnswer((_) async {});
  final container = ProviderContainer(
    overrides: [
      shikooStateProvider.overrideWith((ref) => ref.watch(_stateCell)),
      shikooSignInProvider.overrideWithValue(signIn),
      shikooControllerProvider.overrideWithValue(_Controller()),
    ],
  );
  addTearDown(container.dispose);
  container.read(_stateCell.notifier).set(_state(tv: tv));
  container.read(shikooLoginProvider.notifier).set(login);
  container.read(shikooAccountProvider.notifier).set(account);
  if (tv) {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale(shikooDefaultLanguage),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(Brightness.light, tv: tv),
        home: const ShikooRoot(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

_SignIn _signInOf(ProviderContainer container) =>
    container.read(shikooSignInProvider) as _SignIn;

String? _focusedButton() =>
    (FocusManager.instance.primaryFocus?.context as Element?)
        ?.findAncestorWidgetOfExactType<ShikooButton>()
        ?.label;

void main() {
  testWidgets('a TV with nothing asks for a code at once', (tester) async {
    final container = await _pump(tester, tv: true);
    verify(_signInOf(container).start).called(1);
  });

  testWidgets('the TV shows the code in Persian digits, the bot and its QR, '
      'with the remote on support', (tester) async {
    await _pump(tester, tv: true, login: _waiting);
    expect(find.text('۴۸۲ ۹۱۵'), findsOneWidget);
    expect(find.text('@Test_Shikoo_bot'), findsOneWidget);
    expect(find.byType(QrTile), findsOneWidget);
    expect(_focusedButton(), 'پشتیبانی');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('an expired code stays struck through until «کد تازه», which the '
      'remote is on', (tester) async {
    final container = await _pump(
      tester,
      tv: true,
      login: ShikooLogin(
        LoginPhase.expired,
        code: _waiting.code,
        botUrl: _waiting.botUrl,
      ),
    );
    expect(find.text('این کد تمام شد'), findsOneWidget);
    expect(_focusedButton(), 'کد تازه');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    verify(_signInOf(container).start).called(1);
  });

  testWidgets('approved, the TV names the account and its services; «ادامه» '
      'goes home and the other button unlinks', (tester) async {
    final container = await _pump(
      tester,
      tv: true,
      login: const ShikooLogin(
        LoginPhase.approved,
        account: _maryam,
        services: ['user123 · الماس', 'user789 · معمولی'],
      ),
    );
    expect(find.text(bidiName('user123 · الماس')), findsOneWidget);
    expect(find.textContaining('مریم', findRichText: true), findsOneWidget);
    expect(_focusedButton(), 'ادامه');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_focusedButton(), 'این حساب من نیست');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    verify(_signInOf(container).notMine).called(1);
  });

  testWidgets('on the TV five services or more show three names and how many '
      'more, so the page never grows past four lines', (tester) async {
    await _pump(
      tester,
      tv: true,
      login: ShikooLogin(
        LoginPhase.approved,
        account: _maryam,
        services: [for (var i = 1; i <= 5; i++) 'user$i · پاسارگاد'],
      ),
    );
    expect(find.textContaining('user3'), findsOneWidget);
    expect(find.textContaining('user4'), findsNothing);
    expect(find.text('و ۲ سرویس دیگر'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a 960x540 box the sign-in result with four long names stays '
      'inside the safe area, «ادامه» and its focus ring too', (tester) async {
    await _pump(
      tester,
      tv: true,
      login: const ShikooLogin(
        LoginPhase.approved,
        account: _maryam,
        services: [
          'user5551234_a1f0 · پاسارگاد',
          'user5551234_e7f9 · پاسارگاد',
          'user5551234_f38a · پاسارگاد',
          'user5551234_5551234_2 · اولین خرید',
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    final go = tester.getRect(find.widgetWithText(ShikooButton, 'ادامه'));
    expect(
      go.bottom + ShikooSizes.ring,
      lessThanOrEqualTo(540 - ShikooSizes.tv.safeY),
    );
    final circle = find.ancestor(
      of: find.byWidgetPredicate(
        (w) => w is SvgIcon && w.icon == ShikooIcon.check,
      ),
      matching: find.byType(Container),
    );
    expect(tester.getSize(circle.first), const Size.square(64));
    final list = tester.getRect(
      find
          .ancestor(
            of: find.textContaining('5551234_2'),
            matching: find.byType(Container),
          )
          .first,
    );
    // The test font's tall lines shrink the page to fit; it keeps its proportions.
    final shrunk = tester.getRect(circle.first).height / 64;
    expect(
      go.top - list.bottom,
      closeTo(24 * shrunk, 0.5),
      reason: 'to the buttons',
    );
  });

  testWidgets('on a small phone with large text the sign-in result shows its '
      'four services in full and scrolls to the last, under «ادامه»', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.45;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(
      tester,
      tv: false,
      login: const ShikooLogin(
        LoginPhase.approved,
        account: _maryam,
        services: [
          'user5551234_a1f0 · پاسارگاد',
          'user5551234_e7f9 · پاسارگاد',
          'user5551234_f38a · پاسارگاد',
          'user5551234_5551234_2 · اولین خرید',
        ],
      ),
    );
    tester.view.physicalSize = const Size(686, 1524);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final last = find.textContaining('234_2');
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    final go = tester.getRect(find.widgetWithText(ShikooButton, 'ادامه'));
    final name = tester.getRect(last);
    expect(name.bottom, lessThanOrEqualTo(go.top), reason: '$name over $go');
    expect(name.bottom, lessThanOrEqualTo(762));
  });

  testWidgets('while services come there is no «ادامه» yet', (tester) async {
    await _pump(
      tester,
      tv: false,
      login: const ShikooLogin(LoginPhase.syncing, account: _maryam),
    );
    expect(find.text('سرویس‌هایت دارند می‌آیند…'), findsOneWidget);
    expect(find.text('ادامه'), findsNothing);
    expect(find.text('این حساب من نیست'), findsOneWidget);
  });

  testWidgets('the phone starts with Telegram, a paste and a way without '
      'Telegram, which shows the code', (tester) async {
    final container = await _pump(tester, tv: false);
    verifyNever(_signInOf(container).start);
    expect(find.text('ورود با تلگرام'), findsOneWidget);
    expect(find.text('چسباندن لینک اشتراک'), findsOneWidget);
    await tester.tap(find.text('تلگرام روی این گوشی نیست؟'));
    container.read(shikooLoginProvider.notifier).set(_waiting);
    await tester.pumpAndSettle();
    verify(_signInOf(container).start).called(1);
    expect(find.text('تأیید از دستگاه دیگر'), findsOneWidget);
    expect(find.text('۴۸۲ ۹۱۵'), findsOneWidget);
  });

  testWidgets(
    'signed in with nothing on the device is «این حساب سرویسی ندارد»',
    (tester) async {
      await _pump(
        tester,
        tv: false,
        account: const ShikooAccount(who: _maryam),
      );
      expect(find.text('این حساب سرویسی ندارد'), findsOneWidget);
      expect(find.text('ورود با حساب دیگر'), findsOneWidget);
    },
  );

  testWidgets('the TV puts the remote where each frame does when the screen '
      'changes by itself, even off the language key', (tester) async {
    final container = await _pump(
      tester,
      tv: true,
      login: const ShikooLogin(LoginPhase.starting),
    );
    final login = container.read(shikooLoginProvider.notifier);
    expect(find.text('در حال گرفتن کد…'), findsOneWidget);
    expect(_focusedButton(), 'پشتیبانی');
    login.set(_waiting);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_focusedButton(), isNull, reason: 'on the language key');
    login.set(
      ShikooLogin(
        LoginPhase.expired,
        code: _waiting.code,
        botUrl: _waiting.botUrl,
      ),
    );
    await tester.pumpAndSettle();
    expect(_focusedButton(), 'کد تازه');
    login.set(const ShikooLogin(LoginPhase.startFailed));
    await tester.pumpAndSettle();
    expect(find.text('کد ورود نرسید'), findsOneWidget);
    expect(_focusedButton(), 'دوباره');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_focusedButton(), 'پشتیبانی');
    login.set(const ShikooLogin(LoginPhase.starting));
    await tester.pumpAndSettle();
    expect(_focusedButton(), 'پشتیبانی');
  });

  testWidgets('the phone getting a code spins the blue button and greys out '
      'the rest; a code that did not come says so above it', (tester) async {
    final container = await _pump(
      tester,
      tv: false,
      login: const ShikooLogin(LoginPhase.starting),
    );
    ShikooButton button(String label) =>
        tester.widget(find.widgetWithText(ShikooButton, label));
    expect(button('در حال گرفتن کد…').busy, isTrue);
    expect(button('چسباندن لینک اشتراک').onPressed, isNull);
    container
        .read(shikooLoginProvider.notifier)
        .set(const ShikooLogin(LoginPhase.startFailed));
    await tester.pumpAndSettle();
    expect(find.textContaining('کد ورود نرسید.', findRichText: true), findsOne);
    expect(
      find.text('تلگرام باز می‌شود؛ در ربات شیکونت «تأیید» را بزن.'),
      findsNothing,
    );
    expect(find.widgetWithText(ShikooButton, 'دوباره'), findsNothing);
    expect(button('چسباندن لینک اشتراک').onPressed, isNotNull);
  });

  testWidgets('a code the clock kept away says so, with the date settings, on '
      'TV and phone', (tester) async {
    const clock = ShikooLogin(LoginPhase.startFailed, clock: true);
    for (final tv in [true, false]) {
      await _pump(tester, tv: tv, login: clock);
      expect(
        find.textContaining(
          'تاریخ و ساعت دستگاهت درست نیست.',
          findRichText: true,
        ),
        findsOne,
        reason: 'tv: $tv',
      );
      expect(find.textContaining('اینترنت', findRichText: true), findsNothing);
      expect(
        find.widgetWithText(ShikooButton, 'تنظیمات تاریخ و ساعت'),
        findsOne,
      );
    }
  });

  testWidgets('the clock page says why, the remote starts on the date settings '
      'and «دوباره» retries, saying so while the clock is still wrong', (
    tester,
  ) async {
    var retries = 0;
    var right = false;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(Brightness.light, tv: true),
        home: ClockPage(
          onRetry: () {
            retries++;
            return right;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'تاریخ و ساعت دستگاهت درست نیست.',
        findRichText: true,
      ),
      findsOne,
    );
    expect(_focusedButton(), 'تنظیمات تاریخ و ساعت');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_focusedButton(), 'دوباره');
    expect(find.text('ساعت هنوز درست نیست.'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(retries, 1);
    expect(find.text('ساعت هنوز درست نیست.'), findsOne);

    right = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(retries, 2);
    expect(find.text('ساعت هنوز درست نیست.'), findsNothing);
  });

  testWidgets('the clock page, before the app, draws on the same TV canvas', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(2560, 1440)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // bareApp's own builder, under the TV theme system.isTV would choose on a TV.
    final app = bareApp(ClockPage(onRetry: () => false));
    await tester.pumpWidget(
      MaterialApp(
        locale: app.locale,
        supportedLocales: app.supportedLocales,
        localizationsDelegates: app.localizationsDelegates,
        theme: shikooThemeData(Brightness.light, tv: true),
        builder: app.builder,
        home: app.home,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(ClockPage))),
      ShikooSizes.tvCanvas,
    );
  });

  testWidgets('a TV whose only service has no link shows its card, the remote '
      'on the bot, and moves to the power button once the link comes', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      tv: true,
      account: const ShikooAccount(
        who: _maryam,
        services: [
          LinkedService(id: 43, title: 'user456 · الماس', status: 'active'),
        ],
      ),
    );
    expect(find.text('بدون لینک'), findsNWidgets(2));
    expect(_focusedButton(), 'ربات شیکونت');
    container
        .read(shikooAccountProvider.notifier)
        .set(
          const ShikooAccount(
            who: _maryam,
            services: [
              LinkedService(
                id: 43,
                title: 'user456 · الماس',
                status: 'active',
                profileId: 1,
              ),
            ],
          ),
        );
    container
        .read(_stateCell.notifier)
        .set(
          const ShikooState(
            connection: ShikooConnection.off,
            connectedFor: Duration.zero,
            isTV: true,
            servers: [],
            service: ShikooService(
              name: 'user456 · الماس',
              usedBytes: 0,
              totalBytes: 0,
              id: 1,
            ),
          ),
        );
    await tester.pumpAndSettle();
    expect(
      (FocusManager.instance.primaryFocus?.context as Element?)
          ?.findAncestorWidgetOfExactType<PowerButton>(),
      isNotNull,
    );
  });

  testWidgets('an expired service with no link offers renewal, its own page '
      'in the bot', (tester) async {
    await _pump(
      tester,
      tv: true,
      account: const ShikooAccount(
        who: _maryam,
        bot: 'Test_Shikoo_bot',
        services: [
          LinkedService(id: 41, title: 'user123 · الماس', status: 'expired'),
        ],
      ),
    );
    expect(find.text('تاریخ انقضا گذشته'), findsOneWidget, reason: 'the chip');
    expect(find.text('اعتبار تمام شده'), findsOneWidget, reason: 'the button');
    expect(find.text('با «تمدید» دوباره وصل می‌شوی.'), findsOneWidget);
    expect(
      find.text('اعتبارش تمام شد. بعد از تمدید، «دوباره» را بزن.'),
      findsOneWidget,
    );
    for (final label in ['تمدید', 'پشتیبانی', 'دوباره']) {
      expect(find.widgetWithText(ShikooButton, label), findsOneWidget);
    }
    expect(_focusedButton(), 'تمدید');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(
      tester.widget<QrTile>(find.byType(QrTile)).data,
      'https://t.me/Test_Shikoo_bot?start=rnw_41',
    );
  });

  testWidgets('while a code comes the way without Telegram greys out too; a '
      'code that did not come takes the line about sending it', (tester) async {
    final container = await _pump(
      tester,
      tv: false,
      login: const ShikooLogin(LoginPhase.starting),
    );
    final link = tester.widget<Text>(find.text('تلگرام روی این گوشی نیست؟'));
    expect(link.style?.color, ShikooColors.light.textMuted);
    expect(link.style?.decorationColor, ShikooColors.light.textMuted);

    container.read(shikooLoginProvider.notifier).set(null);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تلگرام روی این گوشی نیست؟'));
    container
        .read(shikooLoginProvider.notifier)
        .set(const ShikooLogin(LoginPhase.startFailed));
    await tester.pumpAndSettle();
    expect(find.text('کد ورود نرسید'), findsOneWidget);
    expect(find.textContaining('این کد را برای ربات'), findsNothing);
    expect(find.textContaining('کد ۱۰ دقیقه کار می‌کند'), findsNothing);
    expect(find.text('اینترنت گوشی را بررسی کن و دوباره بزن.'), findsOneWidget);
  });

  testWidgets('on the phone a used-up service with no link has renew and '
      'support, and no try-again', (tester) async {
    await _pump(
      tester,
      tv: false,
      account: const ShikooAccount(
        who: _maryam,
        services: [
          LinkedService(id: 42, title: 'user789 · معمولی', status: 'exhausted'),
        ],
      ),
    );
    expect(find.text('حجم تمام شده'), findsNWidgets(2), reason: 'chip, button');
    expect(
      find.text('حجمش تمام شد. با تمدید دوباره فعال می‌شود.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(ShikooButton, 'تمدید'), findsOneWidget);
    expect(find.widgetWithText(ShikooButton, 'پشتیبانی'), findsOneWidget);
    expect(find.widgetWithText(ShikooButton, 'دوباره'), findsNothing);
  });
}
