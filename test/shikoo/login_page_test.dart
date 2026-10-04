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
      shikooStateProvider.overrideWithValue(_state(tv: tv)),
      shikooSignInProvider.overrideWithValue(signIn),
    ],
  );
  addTearDown(container.dispose);
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
}
