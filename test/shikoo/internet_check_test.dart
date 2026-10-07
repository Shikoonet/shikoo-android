import 'dart:async';

import 'package:fl_clash/shikoo/app/app.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/update.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/internet_check.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Controller extends Mock implements ShikooController {}

class _Update extends Mock implements ShikooUpdate {}

/// What feat/app-report-ui passes in: its words, its icon and its page.
const _reportLabel = 'ارسال گزارش';

({String label, ShikooIcon icon, VoidCallback onPressed}) _entry(
  VoidCallback onPressed,
) => (label: _reportLabel, icon: ShikooIcon.check, onPressed: onPressed);

ProbeChecks _probe(String domestic, String international, String door) => (
  domestic: (result: domestic, ms: 40),
  international: (result: international, ms: 300),
  door: (result: door, ms: 60),
);

final _ok = _probe('ok', 'ok', 'ok');
final _offline = _probe('dns', 'dns', 'dns');
final _noAbroad = _probe('ok', 'timeout', 'ok');
final _noDoor = _probe('ok', 'ok', 'timeout');

ShikooState _failed({
  required bool tv,
  bool silent = false,
  ShikooError error = ShikooError.connectTimeout,
}) => ShikooState(
  connection: ShikooConnection.error,
  lastError: error,
  connectedFor: Duration.zero,
  isTV: tv,
  service: ShikooService(
    name: 'user123 · الماس',
    usedBytes: 33 << 30,
    totalBytes: 100 << 30,
    updatedAt: DateTime.now(),
  ),
  servers: [
    for (final (i, name) in ['آلمان ۲', 'فنلاند ۲', 'هلند ۱'].indexed)
      ShikooServer(name: name, type: 'Vless', ping: silent ? -1 : 80 + i),
  ],
  selected: 'آلمان ۲',
);

/// What the remote is on: a server name, `power`, or a button label.
String? _focused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  final row = context.findAncestorWidgetOfExactType<ServerRow>();
  if (row != null) return row.server.name;
  if (context.findAncestorWidgetOfExactType<PowerButton>() != null) {
    return 'power';
  }
  return context.findAncestorWidgetOfExactType<ShikooButton>()?.label;
}

bool _inCard() =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<InternetCheckCard>() !=
    null;

/// Home as the app shows it: inside [shikooFrame], whose TV canvas grows with the screen.
Future<ProviderContainer> _home(
  WidgetTester tester, {
  required ShikooState state,
  required Future<ProbeChecks> Function() probe,
  Size size = const Size(960, 540),
  String locale = 'fa',
  ShikooController? controller,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  FocusManager.instance.highlightStrategy = state.isTV
      ? FocusHighlightStrategy.alwaysTraditional
      : FocusHighlightStrategy.automatic;
  addTearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );
  final update = _Update();
  when(update.checkNow).thenAnswer((_) async => null);
  final container = ProviderContainer(
    overrides: [
      shikooStateProvider.overrideWithValue(state),
      shikooControllerProvider.overrideWithValue(controller ?? _Controller()),
      shikooUpdateProvider.overrideWithValue(update),
      shikooUpdateOfferProvider.overrideWith(() => ShikooCell(null)),
      shikooProbeProvider.overrideWith(() => ShikooProbes(probe)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      key: UniqueKey(),
      container: container,
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(Brightness.dark, tv: state.isTV),
        builder: (context, child) =>
            shikooFrame(context, child!, managers: (page) => page),
        home: const ShikooHome(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<String?> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
  return _focused();
}

Future<void> _show(ProviderContainer container, WidgetTester tester) async {
  unawaited(container.read(shikooProbeProvider.notifier).run());
  await tester.pumpAndSettle();
}

Finder _button(String label) => find.widgetWithText(ShikooButton, label);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadShikooFonts();
  });

  testWidgets('one sentence per reading, and only the buttons that help; '
      'report only once the door answered', (tester) async {
    final l = lookupShikooL10n(const Locale('fa'));
    final cases = <(ProbeChecks?, bool, String, List<String>)>[
      (null, false, l.probeChecking, []),
      (_ok, false, l.probeOk, [_reportLabel]),
      (_offline, false, l.probeOffline, [l.probeNetSettings]),
      (_noAbroad, false, l.probeNoAbroad, [_reportLabel]),
      (_noDoor, false, l.probeNoDoor, [l.support]),
      (_ok, true, l.probeNoServer, [_reportLabel, l.support, l.refreshServers]),
    ];
    for (final (checks, silent, sentence, buttons) in cases) {
      for (final report in [true, false]) {
        await tester.pumpWidget(
          bareApp(
            Scaffold(
              body: InternetCheckCard(
                check: checks == null
                    ? const AsyncLoading()
                    : AsyncData(checks),
                state: _failed(tv: false, silent: silent),
                controller: _Controller(),
                report: report ? _entry(() {}) : null,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text(sentence), findsOneWidget);
        expect(
          [
            for (final button in tester.widgetList<ShikooButton>(
              find.byType(ShikooButton),
            ))
              button.label,
          ],
          report ? buttons : buttons.where((b) => b != _reportLabel),
          reason: '$sentence, report $report',
        );
      }
    }
  });

  testWidgets('its buttons open the wireless settings, ask the subscription '
      'again, and send the report', (tester) async {
    final l = lookupShikooL10n(const Locale('fa'));
    final asked = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('shikoo/diag'),
      (call) async {
        asked.add(call.method);
        return true;
      },
    );
    final controller = _Controller();
    when(controller.refreshService).thenAnswer((_) async {});
    var reports = 0;
    Future<void> show(ProbeChecks checks, {bool silent = false}) async {
      await tester.pumpWidget(
        bareApp(
          Scaffold(
            body: InternetCheckCard(
              check: AsyncData(checks),
              state: _failed(tv: false, silent: silent),
              controller: controller,
              report: _entry(() => reports++),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await show(_offline);
    await tester.tap(_button(l.probeNetSettings));
    expect(asked, ['netSettings']);
    await show(_ok, silent: true);
    await tester.tap(_button(l.refreshServers));
    await tester.tap(_button(_reportLabel));
    verify(controller.refreshService).called(1);
    expect(reports, 1);
  });

  for (final tv in [false, true]) {
    testWidgets(
      '${tv ? 'TV' : 'phone'}: once the check has its card, the hint under '
      'the button no longer says to check the internet',
      (tester) async {
        final l = lookupShikooL10n(const Locale('fa'));
        final hint = tv
            ? l.noServerAnsweredHelpTv
            : l.noServerAnsweredHelpTouch;
        final container = await _home(
          tester,
          state: _failed(tv: tv, silent: true, error: ShikooError.noServer),
          probe: () async => _ok,
          size: tv ? const Size(960, 540) : const Size(412, 915),
        );
        expect(find.text(hint), findsOneWidget);
        await _show(container, tester);
        expect(find.text(l.probeNoServer), findsOneWidget);
        expect(find.text(hint), findsNothing);
      },
    );
  }

  testWidgets('on the phone it heads the cards, under the power button', (
    tester,
  ) async {
    final container = await _home(
      tester,
      state: _failed(tv: false),
      probe: () async => _noDoor,
      size: const Size(412, 915),
    );
    expect(find.byType(InternetCheckCard), findsNothing);
    await _show(container, tester);
    final card = tester.getRect(find.byType(InternetCheckCard));
    expect(
      card.top,
      greaterThan(tester.getRect(find.byType(PowerButton)).bottom),
    );
    expect(card.bottom, lessThan(tester.getRect(find.byType(ServiceCard)).top));
  });

  for (final size in const [
    Size(960, 540),
    Size(1280, 720),
    Size(1920, 1080),
  ]) {
    for (final locale in ['fa', 'en']) {
      final rtl = locale == 'fa';
      final towardCard = rtl
          ? LogicalKeyboardKey.arrowRight
          : LogicalKeyboardKey.arrowLeft;
      final towardPower = rtl
          ? LogicalKeyboardKey.arrowLeft
          : LogicalKeyboardKey.arrowRight;
      final where = '${size.width.round()}x${size.height.round()} $locale';

      testWidgets('TV $where: the card leaves the remote on the power button; '
          'toward the card it lands on its first button, steps along them, '
          'and back to power', (tester) async {
        final l = lookupShikooL10n(Locale(locale));
        final container = await _home(
          tester,
          state: _failed(tv: true, silent: true),
          probe: () async => _ok,
          size: size,
          locale: locale,
        );
        expect(_focused(), 'power');
        await _show(container, tester);
        expect(find.byType(InternetCheckCard), findsOneWidget);
        expect(_focused(), 'power');
        expect(await _press(tester, towardCard), l.reportSendShort);
        expect(await _press(tester, towardPower), l.support);
        expect(await _press(tester, towardPower), l.refreshServers);
        expect(await _press(tester, towardPower), 'power');
        expect(await _press(tester, towardCard), l.reportSendShort);
        await _press(tester, LogicalKeyboardKey.arrowDown);
        expect(_inCard(), isFalse);
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<ServiceCard>(),
          isNotNull,
        );
        await _press(tester, LogicalKeyboardKey.arrowUp);
        expect(_inCard(), isTrue);
      });

      testWidgets('TV $where: with no button on the card, toward the card is '
          'the chosen server, as before', (tester) async {
        final container = await _home(
          tester,
          state: _failed(tv: true),
          probe: () => Completer<ProbeChecks>().future,
          size: size,
          locale: locale,
        );
        await _show(container, tester);
        expect(find.byType(InternetCheckCard), findsOneWidget);
        expect(await _press(tester, towardCard), 'آلمان ۲');
      });
    }
  }
}
