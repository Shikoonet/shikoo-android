import 'dart:io';

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/no_shots.dart';

class _Controller extends Mock implements ShikooController {}

const _tvState = ShikooState(
  connection: ShikooConnection.off,
  connectedFor: Duration.zero,
  isTV: true,
  servers: [],
);

Future<ProviderContainer> _pumpSettings(
  WidgetTester tester,
  ShikooController controller,
) async {
  tester.view
    ..physicalSize = const Size(1920, 1080)
    ..devicePixelRatio = 2;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final container = ProviderContainer(
    overrides: [
      noShots,
      shikooStateProvider.overrideWithValue(_tvState),
      shikooControllerProvider.overrideWithValue(controller),
      shikooVersionProvider.overrideWithValue('0.8.98'),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) {
          final look = ref.watch(shikooLookProvider);
          return MaterialApp(
            locale: Locale(look.language),
            themeMode: look.theme,
            supportedLocales: ShikooL10n.supportedLocales,
            localizationsDelegates: const [
              ShikooL10n.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            theme: shikooThemeData(Brightness.light, tv: true),
            darkTheme: shikooThemeData(Brightness.dark, tv: true),
            home: const ShikooSettings(),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The label under the remote: a button's, else the first text inside the focused item.
String? _focused() {
  final element = FocusManager.instance.primaryFocus?.context as Element?;
  if (element == null) return null;
  final button = element.findAncestorWidgetOfExactType<ShikooButton>();
  if (button != null) return button.label;
  String? first;
  void visit(Element child) {
    final widget = child.widget;
    if (first == null && widget is Text) first = widget.data;
    if (first == null) child.visitChildren(visit);
  }

  element.visitChildren(visit);
  return first;
}

Future<String?> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
  return _focused();
}

void main() {
  // The TV page fits one screen with Vazirmatn's widths, not the test font's.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadShikooFonts();
  });

  test('the support report names the FlClash in pubspec.yaml, which each '
      'upstream tag raises', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final name = RegExp(r'^version:\s*([^+\s]+)', multiLine: true);
    expect(flclashVersion, name.firstMatch(pubspec)![1]);
  });

  test(
    'the core name in the diagnostics report names the version and the commit the build stamped, and '
    'a build without the stamp the version alone (#32)',
    () {
      expect(coreName('70f0570'), 'mihomo\u00A0$mihomoVersion\u00A0(70f0570)');
      expect(coreName(''), 'mihomo\u00A0$mihomoVersion');
    },
  );

  test('the core name\'s version belongs to the commit core/Clash.Meta is '
      'pinned to', () {
    // The index, not HEAD: CI's comment-density step soft-resets HEAD to the PR's base.
    final git = Process.runSync('git', [
      'rev-parse',
      '--short=7',
      ':core/Clash.Meta',
    ]);
    expect(
      (git.stdout.toString().trim(), mihomoVersion),
      ('cd1023a', '1.19.33'),
      reason:
          'A moved core needs mihomoVersion set to its mihomo tag, then this '
          'pair. git rev-parse :core/Clash.Meta exit ${git.exitCode}: '
          '${git.stderr}',
    );
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the remote starts on the current look and changes it for good', (
    tester,
  ) async {
    final container = await _pumpSettings(tester, _Controller());
    expect(_focused(), 'خودکار');

    expect(await _press(tester, LogicalKeyboardKey.arrowRight), 'تیره');
    await _press(tester, LogicalKeyboardKey.select);
    expect(container.read(shikooLookProvider).theme, ThemeMode.dark);
    expect(await _press(tester, LogicalKeyboardKey.arrowLeft), 'خودکار');
    expect(
      (await SharedPreferences.getInstance()).getString('shikoo.theme'),
      'dark',
    );

    expect(await _press(tester, LogicalKeyboardKey.arrowLeft), 'فارسی');
    expect(await _press(tester, LogicalKeyboardKey.arrowLeft), 'English');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(_focused(), 'English', reason: 'the remote stays put');

    final reloaded = ProviderContainer();
    addTearDown(reloaded.dispose);
    await reloaded.read(shikooLookProvider.notifier).load();
    expect(reloaded.read(shikooLookProvider), (
      theme: ThemeMode.dark,
      language: 'en',
    ));
  });

  testWidgets('log out asks first, and only yes forgets the services', (
    tester,
  ) async {
    final controller = _Controller();
    when(controller.forgetServices).thenAnswer((_) async {});
    await _pumpSettings(tester, controller);
    expect(find.text('۰.۸.۹۸'), findsOneWidget);
    expect(find.text('سرویس‌ها از این تلویزیون پاک می‌شوند.'), findsOneWidget);

    expect(await _press(tester, LogicalKeyboardKey.arrowLeft), 'فارسی');
    expect(await _press(tester, LogicalKeyboardKey.arrowDown), 'خروج');
    expect(await _press(tester, LogicalKeyboardKey.select), 'انصراف');
    expect(find.text('سرویس‌ها از این تلویزیون پاک شوند؟'), findsOneWidget);
    expect(await _press(tester, LogicalKeyboardKey.select), 'خروج');
    verifyNever(controller.forgetServices);

    await _press(tester, LogicalKeyboardKey.select);
    expect(await _press(tester, LogicalKeyboardKey.arrowLeft), 'پاک کردن');
    await _press(tester, LogicalKeyboardKey.select);
    verify(controller.forgetServices).called(1);
    expect(find.text('سرویس‌ها از این تلویزیون پاک شوند؟'), findsNothing);
  });

  testWidgets('an open log-out dialog turns dark with the system', (
    tester,
  ) async {
    await _pumpSettings(tester, _Controller());
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    Color? title() => tester
        .widget<Text>(find.text('سرویس‌ها از این تلویزیون پاک شوند؟'))
        .style
        ?.color;
    expect(title(), ShikooColors.light.text);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpAndSettle();
    expect(title(), ShikooColors.dark.text);
  });

  testWidgets('About names the licence, both upstreams and the source', (
    tester,
  ) async {
    await _pumpSettings(tester, _Controller());
    expect(
      await _press(tester, LogicalKeyboardKey.arrowDown),
      'سایت‌های ایرانی بدون فیلترشکن',
    );
    expect(
      await _press(tester, LogicalKeyboardKey.arrowDown),
      'بررسی به‌روزرسانی',
    );
    expect(await _press(tester, LogicalKeyboardKey.arrowDown), 'درباره');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.textContaining('GPL-3.0'), findsOneWidget);
    expect(find.textContaining('FlClash'), findsOneWidget);
    expect(find.textContaining('mihomo'), findsOneWidget);
    expect(
      find.text('کد منبعِ همین نسخه را می‌توانی از «پشتیبانی» بگیری.'),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_focused(), 'درباره');
  });

  testWidgets('on the TV two columns, the remote crosses them and brings '
      'the row it lands on into view', (tester) async {
    await _pumpSettings(tester, _Controller());
    const left = LogicalKeyboardKey.arrowLeft;
    const right = LogicalKeyboardKey.arrowRight;
    const down = LogicalKeyboardKey.arrowDown;
    const up = LogicalKeyboardKey.arrowUp;
    expect(_focused(), 'خودکار');
    expect(await _press(tester, down), 'سایت‌های ایرانی بدون فیلترشکن');
    expect(await _press(tester, down), 'بررسی به‌روزرسانی');
    expect(await _press(tester, down), 'درباره');
    expect(await _press(tester, down), 'درباره', reason: 'the column ends');
    expect(
      tester.getRect(find.text('درباره')).bottom,
      lessThanOrEqualTo(540),
      reason: 'scrolled into view',
    );
    expect(await _press(tester, left), 'خروج');
    expect(await _press(tester, up), 'فارسی');
    expect(await _press(tester, down), 'خروج');
    expect(await _press(tester, right), 'سایت‌های ایرانی بدون فیلترشکن');
    expect(
      await _press(tester, up),
      'خودکار',
      reason: 'the chosen look, not the option nearest the row',
    );
    expect(await _press(tester, left), 'فارسی');
    expect(await _press(tester, down), 'خروج');
    expect(await _press(tester, down), 'عیب‌یابی و گزارش');
    expect(
      await _press(tester, down),
      'عیب‌یابی و گزارش',
      reason: 'not into the app column',
    );
  });

  testWidgets('Latin text keeps the font spacing, as the frames', (
    tester,
  ) async {
    await _pumpSettings(tester, _Controller());
    final english = tester.widget<RichText>(
      find.descendant(
        of: find.text('English'),
        matching: find.byType(RichText),
      ),
    );
    expect(english.text.style?.letterSpacing, 0);
  });

  testWidgets('English mirrors the log-out and forward icons', (tester) async {
    final container = await _pumpSettings(tester, _Controller());
    double mirrored(ShikooIcon icon) => tester
        .widget<Transform>(
          find
              .ancestor(
                of: find.byWidgetPredicate(
                  (w) => w is SvgIcon && w.icon == icon,
                ),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform
        .storage[0];
    expect(mirrored(ShikooIcon.logout), 1);
    await container.read(shikooLookProvider.notifier).setLanguage('en');
    await tester.pumpAndSettle();
    expect(mirrored(ShikooIcon.logout), -1);
    expect(mirrored(ShikooIcon.chevronFwd), -1);
  });

  testWidgets('the status bar follows the app theme, not FlClash setting', (
    tester,
  ) async {
    for (final (mode, icons) in [
      (ThemeMode.light, Brightness.dark),
      (ThemeMode.dark, Brightness.light),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          themeMode: mode,
          theme: shikooThemeData(Brightness.light, tv: false),
          darkTheme: shikooThemeData(Brightness.dark, tv: false),
          // FlClash's ThemeManager, on its default dark theme.
          builder: (context, child) => AnnotatedRegion(
            value: SystemUiOverlayStyle.light,
            child: ShikooSystemUi(child: child!),
          ),
          home: const Scaffold(),
        ),
      );
      await tester.pumpAndSettle();
      expect(SystemChrome.latestStyle?.statusBarIconBrightness, icons);
    }
  });
}
