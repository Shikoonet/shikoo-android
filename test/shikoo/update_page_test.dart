import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/update.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/login.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/update.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Update extends Mock implements ShikooUpdate {}

const _release = AppRelease(
  versionName: '1.0.57',
  versionCode: 2057,
  minVersionCode: 2050,
  size: 52080629,
  sha256: '',
  url: 'https://door.test/dl/ShikooNet-1.0.57-arm64-v8a.apk',
);

UpdateOffer _offer(
  UpdatePhase phase, {
  int received = 0,
  UpdateError? error,
  bool forced = false,
}) => UpdateOffer(
  _release,
  forced: forced,
  phase: phase,
  received: received,
  error: error,
);

/// phone-cards-update, from the top: label → (title, the line under it, the button).
final _states = {
  'offered': (
    _offer(UpdatePhase.offered),
    'نسخهٔ تازه آمده',
    'نسخهٔ ۱.۰.۵۷، ۵۲ مگابایت',
    'دریافت',
  ),
  'downloading': (
    _offer(UpdatePhase.downloading, received: 24500000),
    'در حال دریافت…',
    '۴۷٪، ۲۴ از ۵۲ مگابایت',
    'انصراف',
  ),
  'ready': (
    _offer(UpdatePhase.ready, received: _release.size),
    'آمادهٔ نصب',
    'با نصب، شیکونت بسته می‌شود و اگر وصلی، اتصال هم؛ بعد دوباره بازش کن.',
    'نصب',
  ),
  'failed': (
    _offer(UpdatePhase.offered, received: 9000000, error: UpdateError.network),
    'دریافت نشد.',
    'اینترنت را بررسی کن و دوباره بزن؛ از همان‌جا ادامه می‌دهد.',
    'دوباره',
  ),
  'bad file': (
    _offer(UpdatePhase.offered, error: UpdateError.checksum),
    'فایل سالم نرسید.',
    'دوباره بزن تا از اول دریافت شود.',
    'دوباره',
  ),
};

ShikooState _state({bool isTV = false}) => ShikooState(
  connection: ShikooConnection.off,
  connectedFor: Duration.zero,
  isTV: isTV,
  service: ShikooService(
    name: 'user123 · الماس',
    usedBytes: 12 << 30,
    totalBytes: 50 << 30,
    expire: DateTime.now().add(const Duration(days: 67)),
    supportUrl: 'https://t.me/shikoo_panel_support',
    updatedAt: DateTime.now(),
  ),
  servers: const [
    ShikooServer(name: 'آلمان ۳', type: 'Vless', ping: 92),
    ShikooServer(name: 'فنلاند ۲', type: 'Vless', ping: 110),
  ],
  selected: 'آلمان ۳',
);

late _Update _engine;

/// [home] is Home, or the root that puts the forced page in its place.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  UpdateOffer offer, {
  bool isTV = false,
  bool root = false,
  Size? size,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize =
        size ?? (isTV ? const Size(1920, 1080) : const Size(824, 1830))
    ..devicePixelRatio = 2;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  _engine = _Update();
  when(_engine.download).thenAnswer((_) async {});
  when(_engine.cancel).thenAnswer((_) async {});
  when(_engine.install).thenAnswer((_) async => true);
  when(_engine.allow).thenAnswer((_) async {});
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        shikooVersionProvider.overrideWithValue('1.0.0'),
        shikooStateProvider.overrideWithValue(_state(isTV: isTV)),
        shikooUpdateOfferProvider.overrideWith(() => ShikooCell(offer)),
        shikooUpdateProvider.overrideWithValue(_engine),
      ],
      child: MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(Brightness.light, tv: isTV),
        home: root ? const ShikooRoot() : const ShikooHome(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

Future<void> _set(
  WidgetTester tester,
  ProviderContainer container,
  UpdateOffer offer,
) async {
  container.read(shikooUpdateOfferProvider.notifier).set(offer);
  await tester.pumpAndSettle();
}

/// What the remote is on: `power`, or a button's label.
String? _focused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  if (context.findAncestorWidgetOfExactType<PowerButton>() != null) {
    return 'power';
  }
  return context.findAncestorWidgetOfExactType<ShikooButton>()?.label;
}

Future<String?> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
  return _focused();
}

Future<void> _focus(WidgetTester tester, String label) async {
  final inside = find.descendant(
    of: find.widgetWithText(ShikooButton, label).first,
    matching: find.byType(GestureDetector),
  );
  final node = Focus.of(tester.element(inside.first));
  FocusTraversalGroup.of(node.context!).invalidateScopeData(node.nearestScope!);
  node.requestFocus();
  await tester.pumpAndSettle();
  expect(_focused(), label);
}

Finder _inCard(String text) =>
    find.descendant(of: find.byType(UpdateCard), matching: find.text(text));

const _up = LogicalKeyboardKey.arrowUp;
const _down = LogicalKeyboardKey.arrowDown;
const _towardPower = LogicalKeyboardKey.arrowLeft;
const _ok = LogicalKeyboardKey.select;

void main() {
  // Where the button goes depends on text widths; the test font's are not Vazirmatn's.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadShikooFonts();
  });

  testWidgets('the card shows each of its five states, and each button does '
      'its one thing', (tester) async {
    for (final MapEntry(key: name, value: (offer, title, sub, label))
        in _states.entries) {
      await _pump(tester, offer);
      expect(_inCard(title), findsOneWidget, reason: name);
      expect(_inCard(sub), findsOneWidget, reason: name);
      expect(
        find.descendant(
          of: find.byType(UpdateCard),
          matching: find.byType(ShikooButton),
        ),
        findsOneWidget,
        reason: name,
      );
      expect(
        find.descendant(
          of: find.byType(UpdateCard),
          matching: find.byType(MeterBar),
        ),
        name == 'downloading' ? findsOneWidget : findsNothing,
        reason: name,
      );
      final danger = ShikooTheme.of(tester.element(_inCard(title))).c.danger;
      final heading = tester.widget<Text>(_inCard(title));
      expect(
        heading.style!.color == danger,
        name == 'failed' || name == 'bad file',
        reason: name,
      );
      await tester.tap(_inCard(label));
      await tester.pumpAndSettle();
      switch (name) {
        case 'downloading':
          verify(_engine.cancel).called(1);
        case 'ready':
          verify(_engine.install).called(1);
        default:
          verify(_engine.download).called(1);
      }
    }
  });

  testWidgets('the card heads the cards, under the power button', (
    tester,
  ) async {
    await _pump(tester, _states['offered']!.$1);
    final card = tester.getRect(find.byType(UpdateCard));
    expect(
      card.top,
      greaterThan(tester.getRect(find.byType(PowerButton)).bottom),
    );
    expect(card.bottom, lessThan(tester.getRect(find.byType(ServiceCard)).top));
    final button = tester.getRect(
      find.descendant(
        of: find.byType(UpdateCard),
        matching: find.byType(ShikooButton),
      ),
    );
    expect(
      button.top,
      lessThan(tester.getRect(_inCard('نسخهٔ تازه آمده')).bottom),
      reason: 'at normal size the button sits beside the text',
    );
  });

  testWidgets('with large text on a small phone nothing overflows and every '
      'button goes under its text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.45;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final MapEntry(key: name, value: (offer, title, _, label))
        in _states.entries) {
      await _pump(tester, offer, size: const Size(686, 1524));
      expect(tester.takeException(), isNull, reason: name);
      expect(
        tester.getRect(_inCard(label)).top,
        greaterThan(tester.getRect(_inCard(title)).bottom),
        reason: name,
      );
    }
    for (final name in ['offered', 'downloading', 'failed']) {
      await _pump(
        tester,
        _forced(_states[name]!.$1),
        root: true,
        size: const Size(686, 1524),
      );
      expect(tester.takeException(), isNull, reason: 'forced $name');
    }
  });

  testWidgets('on the TV the power button keeps the first focus; the remote '
      'reaches the card from the service card and leaves it toward the power '
      'button', (tester) async {
    await _pump(tester, _states['offered']!.$1, isTV: true);
    expect(_focused(), 'power');
    await _focus(tester, 'به‌روزرسانی');
    expect(await _press(tester, _up), 'دریافت');
    expect(await _press(tester, _up), 'تنظیمات');
    await _focus(tester, 'دریافت');
    expect(await _press(tester, _down), 'به‌روزرسانی');
    await _focus(tester, 'دریافت');
    expect(await _press(tester, _towardPower), 'power');
  });

  testWidgets('a download ending by itself keeps the remote on the card: '
      'cancel becomes install', (tester) async {
    final container = await _pump(
      tester,
      _states['downloading']!.$1,
      isTV: true,
    );
    await _focus(tester, 'انصراف');
    await _set(tester, container, _states['ready']!.$1);
    expect(_focused(), 'نصب');
  });

  testWidgets('without the permission, install explains first; on the TV the '
      'remote is on Continue, which opens Android\'s page', (tester) async {
    await _pump(tester, _states['ready']!.$1, isTV: true);
    when(_engine.install).thenAnswer((_) async => false);
    await _focus(tester, 'نصب');
    await _press(tester, _ok);
    expect(find.text('اجازهٔ نصب'), findsOneWidget);
    expect(find.textContaining('دکمهٔ برگشتِ ریموت'), findsOneWidget);
    expect(
      find.textContaining('شیکونت بسته می‌شود'),
      findsNWidgets(2),
      reason: 'on the card and in the dialog',
    );
    expect(_focused(), 'ادامه');
    await _press(tester, _ok);
    verify(_engine.allow).called(1);
    expect(find.text('اجازهٔ نصب'), findsNothing);

    await _pump(tester, _states['ready']!.$1);
    when(_engine.install).thenAnswer((_) async => false);
    await tester.tap(_inCard('نصب'));
    await tester.pumpAndSettle();
    expect(find.textContaining('دکمهٔ برگشتِ گوشی'), findsOneWidget);
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
    verifyNever(_engine.allow);
  });

  testWidgets('a forced update takes the whole screen, one focused button on '
      'the TV, then cancel and install', (tester) async {
    final container = await _pump(
      tester,
      _forced(_states['offered']!.$1),
      isTV: true,
      root: true,
    );
    expect(find.byType(ForcedUpdatePage), findsOneWidget);
    expect(find.byType(ShikooHome), findsNothing);
    expect(find.text('نسخهٔ تازه لازم است'), findsOneWidget);
    expect(
      find.text('برای ادامه، نسخهٔ ۱.۰.۵۷ را دریافت و نصب کن (۵۲ مگابایت).'),
      findsOneWidget,
    );
    expect(find.textContaining('شیکونت بسته می‌شود'), findsOneWidget);
    expect(find.byType(ShikooButton), findsOneWidget);
    expect(_focused(), 'دریافت');
    await _press(tester, _ok);
    verify(_engine.download).called(1);

    await _set(tester, container, _forced(_states['downloading']!.$1));
    expect(find.text('۴۷٪، ۲۴ از ۵۲ مگابایت'), findsOneWidget);
    expect(find.byType(MeterBar), findsOneWidget);
    expect(_focused(), 'انصراف');
    await _set(tester, container, _forced(_states['ready']!.$1));
    expect(_focused(), 'نصب');
  });

  testWidgets('a forced download that failed offers support beside retry, '
      'aimed like the service card\'s', (tester) async {
    await _pump(tester, _forced(_states['failed']!.$1), isTV: true, root: true);
    expect(find.textContaining('دریافت نشد.'), findsOneWidget);
    expect(find.textContaining('شیکونت بسته می‌شود'), findsNothing);
    expect(_focused(), 'دوباره');
    expect(await _press(tester, _towardPower), 'پشتیبانی');
    await _press(tester, _ok);
    expect(
      tester.widget<QrTile>(find.byType(QrTile)).data,
      'https://t.me/shikoo_panel_support',
    );
    expect(await _press(tester, _ok), 'پشتیبانی');

    await _pump(tester, _forced(_states['bad file']!.$1), root: true);
    expect(find.textContaining('فایل سالم نرسید.'), findsOneWidget);
    for (final label in ['دوباره', 'پشتیبانی']) {
      expect(
        tester
            .widget<ShikooButton>(find.widgetWithText(ShikooButton, label))
            .icon,
        isNull,
        reason: 'no QR or icon on the phone: $label',
      );
    }
  });
}

UpdateOffer _forced(UpdateOffer offer) => UpdateOffer(
  offer.release,
  forced: true,
  phase: offer.phase,
  received: offer.received,
  error: offer.error,
);
