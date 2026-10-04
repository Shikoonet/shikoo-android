import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
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
    expect(find.text('user123 · الماس'), findsOneWidget);
    expect(find.textContaining('مریم', findRichText: true), findsOneWidget);
    expect(_focusedButton(), 'ادامه');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_focusedButton(), 'این حساب من نیست');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    verify(_signInOf(container).notMine).called(1);
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
