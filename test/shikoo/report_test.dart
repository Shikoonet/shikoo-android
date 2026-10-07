import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/shikoo/app/app.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/login.dart';
import 'package:fl_clash/shikoo/ui/report.dart';
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

/// The real recorder and the real door call; only the device's pictures and its facts are made up.
class _Diag extends ShikooDiag {
  ShikooApiFailure? sendError;
  int built = 0;
  int shots = 0;

  @override
  Future<Map<String, Object?>> report({
    required String trigger,
    required Map<String, Object?> about,
    Uint8List? appImage,
    Uint8List? screenImage,
    bool images = true,
    ProbeChecks? checks,
  }) {
    built++;
    return super.report(
      trigger: trigger,
      about: about,
      appImage: appImage,
      screenImage: screenImage,
      images: images,
      checks: checks,
    );
  }

  @override
  Future<Uint8List?> captureApp() async => _png;

  @override
  Future<Uint8List?> captureScreen() async {
    shots++;
    return _png;
  }

  @override
  Future<Map<String, Object?>> about() async => const {
    'app': {'version': '1.0.57'},
  };

  @override
  Future<({String code, bool linked})> send(Map<String, Object?> report) {
    if (sendError case final error?) throw error;
    return super.send(report);
  }
}

final _png = base64.decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// shikoo-platform's `POST /api/v1/app/report`: each answer in turn, a status or no answer at all.
class _Door {
  final bodies = <Map<String, Object?>>[];
  final answers = <int?>[];
  bool linked = false;

  /// A 200 that holds no code, as a front page or a proxy might answer.
  bool coded = true;

  /// Holds every answer until completed, as a slow line does.
  Completer<void>? hold;

  late final dio = Dio(BaseOptions(validateStatus: (_) => true))
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          bodies.add((options.data as Map).cast<String, Object?>());
          await hold?.future;
          final status = answers.isEmpty ? 200 : answers.removeAt(0);
          if (status == null) {
            return handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: const SocketException('Failed host lookup'),
              ),
            );
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: status,
              data: status == 200 && coded
                  ? {'ok': true, 'code': '48219037', 'linked': linked}
                  : {'ok': false},
            ),
          );
        },
      ),
    );
}

final _now = DateTime.now();

const _noService = ShikooState(
  connection: ShikooConnection.off,
  connectedFor: Duration.zero,
  isTV: false,
  servers: [],
);

ShikooState _state({
  bool tv = false,
  ShikooConnection connection = ShikooConnection.off,
  ShikooNotice? notice,
}) => ShikooState(
  connection: connection,
  connectedFor: Duration.zero,
  isTV: tv,
  lastError: connection == ShikooConnection.error
      ? ShikooError.connectTimeout
      : null,
  notice: notice,
  service: ShikooService(
    name: 'user123 · الماس',
    usedBytes: 12 << 30,
    totalBytes: 50 << 30,
    expire: _now.add(const Duration(days: 67)),
    updatedAt: _now,
  ),
  servers: const [
    ShikooServer(name: 'آلمان ۳', type: 'Vless', ping: 92),
    ShikooServer(name: 'هلند ۱', type: 'Vless', ping: 71),
  ],
  selected: 'آلمان ۳',
);

typedef _Rig = ({ProviderContainer container, _Door door, _Diag diag});

/// Through ShikooApp's own frame, so a TV is drawn on its scaled canvas as on a device.
Future<_Rig> _pump(
  WidgetTester tester,
  Widget home, {
  bool tv = false,
  String locale = 'fa',
  Size? size,
  ShikooState? state,
  ShikooLogin? login,
}) async {
  SharedPreferences.setMockInitialValues({});
  _quietNative();
  final view = size ?? (tv ? const Size(960, 540) : const Size(412, 915));
  tester.view
    ..physicalSize = view * 2
    ..devicePixelRatio = 2;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  FocusManager.instance.highlightStrategy = tv
      ? FocusHighlightStrategy.alwaysTraditional
      : FocusHighlightStrategy.automatic;
  addTearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );
  final door = _Door();
  final diag = _Diag();
  final controller = _Controller();
  when(controller.refreshService).thenAnswer((_) async {});
  when(
    () => controller.pasteService(any()),
  ).thenAnswer((_) async => ShikooPasteError.notShikoo);
  final container = ProviderContainer(
    overrides: [
      shikooStateProvider.overrideWithValue(state ?? _state(tv: tv)),
      shikooApiProvider.overrideWithValue(
        ShikooApi(['http://door.test'], door.dio),
      ),
      shikooDiagProvider.overrideWithValue(diag),
      shikooControllerProvider.overrideWithValue(controller),
      shikooVersionProvider.overrideWithValue('1.0.57'),
      shikooProbeProvider.overrideWith(
        () => ShikooProbes(() async => _reached),
      ),
    ],
  );
  addTearDown(container.dispose);
  if (state?.connection == ShikooConnection.error) {
    unawaited(container.read(shikooProbeProvider.notifier).run());
  }
  container.read(shikooLoginProvider.notifier).set(login);
  final dir = Directory.systemTemp.createTempSync('report');
  addTearDown(() => dir.deleteSync(recursive: true));
  await diag.start(dir.path);
  await diag.attach(container);
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
        theme: shikooThemeData(Brightness.light, tv: tv),
        builder: (context, child) =>
            shikooFrame(context, child!, managers: (page) => page),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container: container, door: door, diag: diag);
}

const ProbeChecks _reached = (
  domestic: (result: 'ok', ms: 40),
  international: (result: 'ok', ms: 300),
  door: (result: 'ok', ms: 60),
);

/// Kotlin's half answers nothing here; unanswered, its replies would come outside fake time.
void _quietNative([List<Map<String, Object?>> exits = const []]) {
  const channel = MethodChannel('shikoo/diag');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    channel,
    (call) async => call.method == 'exits' ? exits : null,
  );
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

/// A page with one way into the report, as every entry has.
class _Launcher extends StatelessWidget {
  const _Launcher();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ShikooButton(
        label: 'open',
        onPressed: () => openReport(context, 'test'),
      ),
    ),
  );
}

ShikooL10n _l(String locale) => lookupShikooL10n(Locale(locale));

/// The first text inside what the remote is on.
String? _focused() {
  final context = FocusManager.instance.primaryFocus?.context as Element?;
  if (context == null) return null;
  String? found;
  void visit(Element element) {
    if (found != null) return;
    if (element.widget case final Text text) {
      found = text.data ?? text.textSpan?.toPlainText();
      return;
    }
    element.visitChildren(visit);
  }

  context.visitChildren(visit);
  return found;
}

/// The remote must show where it is, not only be there.
bool _ringed() {
  final context = FocusManager.instance.primaryFocus?.context as Element?;
  var found = false;
  void visit(Element element) {
    if (element.widget case DecoratedBox(
      decoration: ShapeDecoration(shape: final OutlinedBorder shape),
    ) when shape.side.width == ShikooSizes.focusRingWidth) {
      found = true;
    }
    if (!found) element.visitChildren(visit);
  }

  context?.visitChildren(visit);
  return found;
}

Future<String?> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
  return _focused();
}

Future<void> _focus(WidgetTester tester, String label) async {
  final owner = find.ancestor(
    of: find.text(label),
    matching: find.byType(Pressable),
  );
  final inside = find.descendant(
    of: owner.first,
    matching: find.byType(GestureDetector),
  );
  final node = Focus.of(tester.element(inside.first));
  FocusTraversalGroup.of(node.context!).invalidateScopeData(node.nearestScope!);
  node.requestFocus();
  await tester.pumpAndSettle();
  expect(_focused(), label);
}

Future<void> _openPreview(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _sendNow(WidgetTester tester, ShikooL10n l) async {
  await tester.tap(find.text(l.reportSend));
  await tester.pumpAndSettle();
}

const _left = LogicalKeyboardKey.arrowLeft;
const _right = LogicalKeyboardKey.arrowRight;
const _up = LogicalKeyboardKey.arrowUp;
const _down = LogicalKeyboardKey.arrowDown;
const _ok = LogicalKeyboardKey.select;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadShikooFonts();
  });

  group('sending', () {
    testWidgets('a sent report shows its code in two groups of four, large '
        'without sign-in and small with it', (tester) async {
      for (final linked in [false, true]) {
        final rig = await _pump(tester, const _Launcher());
        rig.door.linked = linked;
        final l = _l('fa');
        await _openPreview(tester);
        await _sendNow(tester, l);
        expect(rig.door.bodies, hasLength(1));
        expect(find.text(l.reportSentTitle), findsOneWidget);
        if (linked) {
          expect(find.text(l.reportSentLinked), findsOneWidget);
          expect(
            find.text(l.reportCodeSmall('\u2066۴۸۲۱ ۹۰۳۷\u2069')),
            findsOneWidget,
          );
        } else {
          expect(find.text('۴۸۲۱ ۹۰۳۷'), findsOneWidget);
          expect(find.text(l.reportGiveCode), findsOneWidget);
        }
      }
    });

    testWidgets('English shows the code in Latin digits', (tester) async {
      await _pump(tester, const _Launcher(), locale: 'en');
      await _openPreview(tester);
      await _sendNow(tester, _l('en'));
      expect(find.text('4821 9037'), findsOneWidget);
    });

    testWidgets('the pictures go along unless the switch is off', (
      tester,
    ) async {
      final l = _l('fa');
      final rig = await _pump(tester, const _Launcher());
      await _openPreview(tester);
      await _sendNow(tester, l);
      final on = rig.door.bodies.single['images']! as Map;
      expect(on.keys, containsAll(['app', 'screen']));

      final off = await _pump(tester, const _Launcher());
      await _openPreview(tester);
      await tester.tap(find.text(l.reportImagesSwitch));
      await tester.pumpAndSettle();
      expect(find.text(l.reportImageOff), findsNWidgets(2));
      await _sendNow(tester, l);
      expect(off.door.bodies.single['images'], {'note': 'off'});
    });

    testWidgets('what the door answers becomes one plain sentence: no '
        'answer, busy, or refused, which leads with Support', (tester) async {
      final l = _l('fa');
      final unreached = [l.retry, l.cancelButton];
      final answered = [l.support, l.retry];
      for (final (status, coded, sentence, buttons) in [
        (null, true, l.reportFailedHelp, unreached),
        (429, true, l.reportFailedBusy, answered),
        (200, false, l.reportFailedRefused, answered),
        for (final refused in const [400, 404, 413, 422, 500, 502, 503])
          (refused, true, l.reportFailedRefused, answered),
      ]) {
        final rig = await _pump(tester, const _Launcher());
        rig.door
          ..answers.add(status)
          ..coded = coded;
        await _openPreview(tester);
        await _sendNow(tester, l);
        expect(find.text(l.reportFailedTitle), findsOneWidget);
        expect(find.text(sentence), findsOneWidget, reason: '$status');
        expect(
          [
            for (final b in tester.widgetList<ShikooButton>(
              find.byType(ShikooButton),
            ))
              b.label,
          ],
          buttons,
          reason: '$status',
        );
      }
    });

    testWidgets('a refused clock says so and leads with date settings', (
      tester,
    ) async {
      final l = _l('fa');
      final rig = await _pump(tester, const _Launcher());
      rig.diag.sendError = const ShikooApiFailure(clock: true);
      await _openPreview(tester);
      await _sendNow(tester, l);
      expect(find.textContaining(l.clockWrongTitle), findsOneWidget);
      final buttons = tester
          .widgetList<ShikooButton>(find.byType(ShikooButton))
          .map((b) => b.label)
          .toList();
      expect(buttons, [l.dateSettings, l.retry]);
    });

    testWidgets('«دوباره» sends the very same report again', (tester) async {
      final l = _l('fa');
      final rig = await _pump(tester, const _Launcher());
      rig.door.answers.add(429);
      await _openPreview(tester);
      await _sendNow(tester, l);
      await tester.tap(find.text(l.retry));
      await tester.pumpAndSettle();
      expect(find.text('۴۸۲۱ ۹۰۳۷'), findsOneWidget);
      expect(rig.diag.built, 1);
      final [first, second] = rig.door.bodies;
      expect(jsonEncode(second), jsonEncode(first));
    });

    testWidgets('«انصراف» while sending goes back and shows no result', (
      tester,
    ) async {
      final l = _l('fa');
      final rig = await _pump(tester, const _Launcher());
      final hold = rig.door.hold = Completer<void>();
      await _openPreview(tester);
      await tester.tap(find.text(l.reportSend));
      await tester.pumpAndSettle();
      expect(find.text(l.reportSending), findsOneWidget);
      await tester.tap(find.text(l.cancelButton));
      await tester.pumpAndSettle();
      hold.complete();
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      expect(find.text(l.reportSentTitle), findsNothing);
    });
  });

  group('the crash card', () {
    Future<_Rig> start(
      Directory home, {
      List<Map<String, Object?>> exits = const [],
    }) async {
      _quietNative(exits);
      final door = _Door();
      final container = ProviderContainer(
        overrides: [
          shikooStateProvider.overrideWithValue(_state()),
          shikooApiProvider.overrideWithValue(
            ShikooApi(['http://door.test'], door.dio),
          ),
        ],
      );
      addTearDown(container.dispose);
      final diag = _Diag();
      await diag.start(home.path);
      await diag.attach(container);
      return (container: container, door: door, diag: diag);
    }

    test('an empty crash file is no crash: as the app leaves one once its '
        'report is sent', () async {
      SharedPreferences.setMockInitialValues({});
      final home = Directory.systemTemp.createTempSync('crash');
      addTearDown(() => home.deleteSync(recursive: true));
      await start(home);
      final java = File('${home.path}/shikoo/java-crash.txt')
        ..writeAsStringSync('');
      expect((await start(home)).container.read(shikooCrashProvider), isNull);
      java.deleteSync();
      final go = File('${home.path}/go-crash.txt')..writeAsStringSync('');
      expect((await start(home)).container.read(shikooCrashProvider), isNull);

      go.writeAsStringSync('panic: x');
      final crashed = await start(home);
      expect(crashed.container.read(shikooCrashProvider), isNotNull);
      await crashed.diag.crashAsked();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await crashed.diag.send(
        await crashed.diag.report(trigger: 'crash', about: const {}),
      );
      expect(go.lengthSync(), 0, reason: 'sent, emptied in place');
      expect((await start(home)).container.read(shikooCrashProvider), isNull);
    });

    test('a crash file or a crash record is offered once, never again '
        'once answered', () async {
      SharedPreferences.setMockInitialValues({});
      final home = Directory.systemTemp.createTempSync('crash');
      addTearDown(() => home.deleteSync(recursive: true));
      final first = await start(home);
      expect(first.container.read(shikooCrashProvider), isNull);

      File('${home.path}/shikoo/java-crash.txt').writeAsStringSync('--- 1 x');
      final crashed = await start(home);
      expect(crashed.container.read(shikooCrashProvider), isNotNull);
      await crashed.diag.crashAsked();
      expect(crashed.container.read(shikooCrashProvider), isNull);
      final again = await start(home);
      expect(again.container.read(shikooCrashProvider), isNull);

      final at = DateTime.now().add(const Duration(minutes: 1));
      final quit = await start(
        home,
        exits: [
          {'reason': 10, 'time': at.millisecondsSinceEpoch, 'status': 0},
        ],
      );
      expect(quit.container.read(shikooCrashProvider), isNull);
      final anr = await start(
        home,
        exits: [
          {'reason': 6, 'time': at.millisecondsSinceEpoch, 'status': 0},
        ],
      );
      expect(
        anr.container.read(shikooCrashProvider),
        at.millisecondsSinceEpoch,
      );
    });

    testWidgets('«نه» takes the card away and «بفرست» opens the preview', (
      tester,
    ) async {
      final l = _l('fa');
      for (final answer in [l.reportCrashNo, l.reportCrashYes]) {
        final rig = await _pump(tester, const ShikooHome());
        rig.container.read(shikooCrashProvider.notifier).set(1);
        await tester.pumpAndSettle();
        expect(find.text(l.reportCrashTitle), findsOneWidget);
        await tester.tap(find.text(answer));
        await tester.pumpAndSettle();
        expect(
          find.text(l.reportImagesSwitch),
          answer == l.reportCrashYes ? findsOneWidget : findsNothing,
        );
        if (answer == l.reportCrashYes) {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        }
        expect(find.text(l.reportCrashTitle), findsNothing);
      }
    });
  });

  group('entries on a phone', () {
    testWidgets('«پشتیبانی» asks first: chat or report', (tester) async {
      final l = _l('fa');
      await _pump(tester, const ShikooHome());
      await tester.tap(find.text(l.support));
      await tester.pumpAndSettle();
      expect(find.text(l.reportSupportSheetBody), findsOneWidget);
      expect(find.text(l.reportChatTelegram), findsOneWidget);
      await tester.tap(find.text(l.reportSendToSupport));
      await tester.pumpAndSettle();
      expect(find.text(l.reportImagesSwitch), findsOneWidget);
    });

    testWidgets('each failure has its report: login code, paste, manual '
        'refresh, connect', (tester) async {
      final l = _l('fa');
      await _pump(
        tester,
        const ShikooRoot(),
        login: const ShikooLogin(LoginPhase.startFailed),
      );
      expect(find.text(l.reportSendToSupport), findsOneWidget);

      // Not on the sign-in page, which offers its one report under a failed code.
      await _pump(tester, const ShikooHome(), state: _noService);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? {'text': 'https://example.com/not-ours'}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.text(l.pasteLink));
      await tester.pumpAndSettle();
      expect(find.text(l.reportSendToSupport), findsOneWidget);

      await _pump(
        tester,
        const ShikooHome(),
        state: _state(notice: const RefreshFailed()),
      );
      expect(find.text(l.reportSendToSupport), findsOneWidget);

      await _pump(
        tester,
        const ShikooHome(),
        state: _state(connection: ShikooConnection.error),
      );
      await tester.tap(find.text(l.reportSendShort));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ReportPage>(find.byType(ReportPage)).trigger,
        'connect',
      );
    });

    testWidgets('the sign-in page offers one report, only where no code '
        'shows: a failed paste adds none', (tester) async {
      final l = _l('fa');
      for (final (login, entries) in const [
        (
          ShikooLogin(
            LoginPhase.waiting,
            code: '482915',
            botUrl: 'https://t.me/Test_Shikoo_bot?start=app_482915',
          ),
          0,
        ),
        (ShikooLogin(LoginPhase.startFailed), 1),
      ]) {
        final rig = await _pump(
          tester,
          const ShikooRoot(),
          state: _noService,
          login: login,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => call.method == 'Clipboard.getData'
              ? {'text': 'https://example.com/not-ours'}
              : null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.tap(find.text(l.pasteLink));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(l.pasteNotShikooTitle, findRichText: true),
          findsOneWidget,
          reason: 'the paste did fail',
        );
        expect(
          find.text(l.reportSendToSupport),
          findsNWidgets(entries),
          reason: '${login.phase}',
        );
        expect(rig.diag.shots, 0);
      }
    });

    testWidgets('no report where it could not go through: a wrong clock', (
      tester,
    ) async {
      final l = _l('fa');
      await _pump(
        tester,
        const ShikooRoot(),
        login: const ShikooLogin(LoginPhase.startFailed, clock: true),
      );
      expect(find.text(l.reportSendToSupport), findsNothing);
      await _pump(
        tester,
        const ShikooHome(),
        state: _state(notice: const RefreshFailed(clock: true)),
      );
      expect(find.text(l.reportSendToSupport), findsNothing);
    });

    testWidgets('Settings › Support › Diagnostics opens the report', (
      tester,
    ) async {
      final l = _l('fa');
      await _pump(tester, const ShikooSettings());
      await tester.scrollUntilVisible(find.text(l.diagTitle), 100);
      await tester.tap(find.text(l.diagTitle));
      await tester.pumpAndSettle();
      expect(find.text(l.diagReportHelp), findsOneWidget);
      await tester.tap(find.text(l.reportSendToSupport));
      await tester.pumpAndSettle();
      expect(find.text(l.reportImagesSwitch), findsOneWidget);
    });
  });

  group('the remote', () {
    for (final (locale, size) in const [
      ('fa', Size(960, 540)),
      ('en', Size(960, 540)),
      ('fa', Size(1920, 1080)),
      ('en', Size(1280, 720)),
    ]) {
      final rtl = locale == 'fa';
      final toEnd = rtl ? _left : _right;
      final toStart = rtl ? _right : _left;
      final name = '$locale ${size.width.round()}';

      testWidgets('$name: the preview lands on Send, the switch one way and '
          'Cancel the other; OK flips the switch and stays', (tester) async {
        final l = _l(locale);
        await _pump(
          tester,
          const _Launcher(),
          tv: true,
          locale: locale,
          size: size,
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(_focused(), l.reportSend);
        expect(_ringed(), isTrue);
        expect(await _press(tester, toStart), l.reportImagesSwitch);
        expect(await _press(tester, _ok), l.reportImagesSwitch);
        expect(find.text(l.reportImageOff), findsNWidgets(2));
        expect(await _press(tester, toEnd), l.reportSend);
        expect(await _press(tester, toEnd), l.cancelButton);
        expect(await _press(tester, toStart), l.reportSend);
        await tester.sendKeyEvent(_ok);
        await tester.pumpAndSettle();
        expect(_focused(), l.support);
        expect(_ringed(), isTrue, reason: 'the ring moves with the remote');
      });

      testWidgets('$name: the support dialog keeps Close and puts the report '
          'beside it', (tester) async {
        final l = _l(locale);
        await _pump(
          tester,
          const ShikooHome(),
          tv: true,
          locale: locale,
          size: size,
        );
        await _focus(tester, l.support);
        await tester.sendKeyEvent(_ok);
        await tester.pumpAndSettle();
        expect(_focused(), l.close);
        expect(await _press(tester, toEnd), l.reportSendToSupport);
        await tester.sendKeyEvent(_ok);
        await tester.pumpAndSettle();
        expect(_focused(), l.reportSend);
      });

      testWidgets('$name: the crash card is the first stop toward the cards; '
          'its two buttons step to each other', (tester) async {
        final l = _l(locale);
        final rig = await _pump(
          tester,
          const ShikooHome(),
          tv: true,
          locale: locale,
          size: size,
        );
        rig.container.read(shikooCrashProvider.notifier).set(1);
        await tester.pumpAndSettle();
        expect(_focused(), l.powerConnect);
        expect(await _press(tester, toStart), l.reportCrashYes);
        expect(await _press(tester, toStart), l.reportCrashNo);
        expect(await _press(tester, toEnd), l.reportCrashYes);
        expect(await _press(tester, toEnd), l.powerConnect);
        await _focus(tester, l.reportCrashNo);
        await tester.sendKeyEvent(_ok);
        await tester.pumpAndSettle();
        expect(find.text(l.reportCrashTitle), findsNothing);
        expect(_focused(), l.refresh);
      });

      testWidgets('$name: after a failed connect the report is the first stop '
          'toward the cards', (tester) async {
        final l = _l(locale);
        await _pump(
          tester,
          const ShikooHome(),
          tv: true,
          locale: locale,
          size: size,
          state: _state(tv: true, connection: ShikooConnection.error),
        );
        expect(await _press(tester, toStart), l.reportSendShort);
      });

      testWidgets('$name: a failed manual refresh puts the report between '
          'refresh and renew', (tester) async {
        final l = _l(locale);
        await _pump(
          tester,
          const ShikooHome(),
          tv: true,
          locale: locale,
          size: size,
          state: _state(tv: true, notice: const RefreshFailed()),
        );
        await _focus(tester, l.refresh);
        expect(await _press(tester, _down), l.reportSendToSupport);
        expect(await _press(tester, _down), l.renew);
        expect(await _press(tester, _up), l.reportSendToSupport);
      });

      testWidgets('$name: no sign-in code, then retry, the report and support '
          'in a row', (tester) async {
        final l = _l(locale);
        await _pump(
          tester,
          const ShikooRoot(),
          tv: true,
          locale: locale,
          size: size,
          login: const ShikooLogin(LoginPhase.startFailed),
        );
        expect(_focused(), l.retry);
        expect(await _press(tester, toEnd), l.reportSendToSupport);
        expect(await _press(tester, toEnd), l.support);
      });

      testWidgets('$name: Settings reach Diagnostics below log-out, which '
          'opens on its report button', (tester) async {
        final l = _l(locale);
        await _pump(
          tester,
          const ShikooSettings(),
          tv: true,
          locale: locale,
          size: size,
        );
        await _focus(tester, l.logout);
        expect(await _press(tester, _down), l.diagTitle);
        await tester.sendKeyEvent(_ok);
        await tester.pumpAndSettle();
        expect(_focused(), l.reportSendToSupport);
      });
    }

    testWidgets('after the door answered, Support is first and opens chat '
        'only, as after a sent report', (tester) async {
      final l = _l('fa');
      for (final status in [200, 503]) {
        final rig = await _pump(tester, const _Launcher(), tv: true);
        rig.door.answers.add(status);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(_ok);
        await tester.pumpAndSettle();
        expect(_focused(), l.support, reason: '$status');
        expect(_ringed(), isTrue);
        await tester.sendKeyEvent(_ok);
        await tester.pumpAndSettle();
        expect(_focused(), l.close);
        expect(find.text(l.reportSendToSupport), findsNothing);
      }
    });

    testWidgets('on a TV the wrong-clock message is the result page\'s '
        'paragraph: its size and colour', (tester) async {
      final l = _l('fa');
      final rig = await _pump(tester, const _Launcher(), tv: true);
      rig.diag.sendError = const ShikooApiFailure(clock: true);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(_ok);
      await tester.pumpAndSettle();
      final message = tester.widget<RichText>(
        find.textContaining(l.clockWrongTitle, findRichText: true),
      );
      final t = ShikooTheme.of(
        tester.element(
          find.textContaining(l.clockWrongTitle, findRichText: true),
        ),
      );
      expect(message.text.style?.fontSize, ShikooSizes.tv.title);
      expect(message.text.style?.color, t.c.textMuted);
    });

    testWidgets('a live sign-in code: its support dialog offers no report', (
      tester,
    ) async {
      final l = _l('fa');
      await _pump(
        tester,
        const ShikooRoot(),
        tv: true,
        login: const ShikooLogin(
          LoginPhase.waiting,
          code: '482915',
          botUrl: 'https://t.me/Test_Shikoo_bot?start=app_482915',
        ),
      );
      await _focus(tester, l.support);
      await tester.sendKeyEvent(_ok);
      await tester.pumpAndSettle();
      expect(_focused(), l.close);
      expect(find.text(l.reportSendToSupport), findsNothing);
    });
  });
}
