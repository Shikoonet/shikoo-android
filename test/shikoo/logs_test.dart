import 'dart:io';

import 'package:fl_clash/common/common.dart' show FixedList;
import 'package:fl_clash/models/models.dart' show Log;
import 'package:fl_clash/providers/providers.dart' show Logs, logsProvider;
import 'package:fl_clash/shikoo/app/app.dart' show shikooFrame;
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/update.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/icons.dart' show SvgIcon;
import 'package:fl_clash/shikoo/ui/jalali.dart';
import 'package:fl_clash/shikoo/ui/logs.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/no_shots.dart';

class _Controller extends Mock implements ShikooController {}

class _Update extends Mock implements ShikooUpdate {}

/// Any read of FlClash's own log list fails the test: it holds links and addresses uncleaned.
class _NoFlClashLogs extends Logs {
  @override
  FixedList<Log> build() =>
      throw StateError('the Logs page read FlClash logsProvider');
}

final _fa = lookupShikooL10n(const Locale('fa'));
final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

String _stamp(DateTime at) =>
    '${at.toUtc().toIso8601String().substring(0, 19)}Z';

const _dial =
    'C warning [TCP] dial PROXY (match ·) · --> · error: dial tcp ·: '
    'context deadline exceeded ×8';
const _timeout =
    'A [APP] helper ping failed: DioException [receive timeout]: The request '
    'took longer than · to receive data. It was aborted.';

final _now = DateTime.now();
final _t = _stamp(_now.subtract(const Duration(minutes: 5)));

/// One of each kind, as `diag.log` holds them: two errors, a warning in each of two tabs.
final _record = [
  '$_t T app start',
  '$_t U key char',
  '$_t T vpn connecting',
  '$_t T refresh timeout',
  '$_t A [APP] initAppLinksListen',
  '$_t $_dial',
  '$_t C error Start TUN listening error: configure tun interface: Access is denied.',
  '$_t A [APP] Core method getTraffic timed out after 10001ms',
  '$_t E Bad state: no element',
  '$_t T refresh ok',
  '$_t T vpn on',
];

Future<NoShots> _started(List<String> lines, WidgetTester? tester) async {
  final home = Directory.systemTemp.createTempSync('logs');
  addTearDown(() => home.deleteSync(recursive: true));
  File('${home.path}/shikoo/diag.log')
    ..createSync(recursive: true)
    ..writeAsStringSync(lines.map((line) => '$line\n').join());
  final diag = NoShots();
  await (tester?.runAsync(() => diag.start(home.path)) ??
      diag.start(home.path));
  return diag;
}

void _view(WidgetTester tester, Size size, double scale) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

MaterialApp _app(
  Widget home, {
  String language = 'fa',
  bool tv = false,
  TransitionBuilder? builder,
}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: ShikooL10n.supportedLocales,
  localizationsDelegates: const [
    ShikooL10n.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: shikooThemeData(Brightness.light, tv: tv),
  builder: builder,
  home: home,
);

ProviderContainer _container(ShikooDiag diag, {bool tv = false}) {
  final update = _Update();
  when(update.checkNow).thenAnswer((_) async => null);
  final container = ProviderContainer(
    overrides: [
      shikooDiagProvider.overrideWithValue(diag),
      logsProvider.overrideWith(_NoFlClashLogs.new),
      shikooStateProvider.overrideWithValue(
        ShikooState(
          connection: ShikooConnection.off,
          connectedFor: Duration.zero,
          isTV: tv,
          servers: const [],
        ),
      ),
      shikooControllerProvider.overrideWithValue(_Controller()),
      shikooVersionProvider.overrideWithValue('1.0.40'),
      shikooUpdateProvider.overrideWithValue(update),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<NoShots> _pump(
  WidgetTester tester, {
  List<String>? lines,
  Size size = const Size(360, 800),
  double scale = 1,
  String language = 'fa',
}) async {
  SharedPreferences.setMockInitialValues({});
  _view(tester, size, scale);
  final diag = await _started(lines ?? _record, tester);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      key: UniqueKey(),
      container: _container(diag),
      child: _app(const ShikooLogs(), language: language),
    ),
  );
  await tester.pumpAndSettle();
  return diag;
}

Finder _tab(String label) => find.descendant(
  of: find.byType(Segmented<LogTab>),
  matching: find.text(label),
);

Finder _button(String label) =>
    find.byWidgetPredicate((w) => w is ShikooButton && w.label == label);

List<String> _clipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

int _shownRows(WidgetTester tester) =>
    (tester.widget<SliverList>(find.byType(SliverList)).delegate
            as SliverChildBuilderDelegate)
        .childCount!;

/// Labels a narrower box cut: the tabs' and the two buttons'.
List<String> _cut(WidgetTester tester) => [
  for (final finder in [
    find.descendant(
      of: find.byType(Segmented<LogTab>),
      matching: find.byType(RichText),
    ),
    find.descendant(
      of: find.byType(ShikooButton),
      matching: find.byType(RichText),
    ),
  ])
    for (final element in finder.evaluate())
      if (element.renderObject case final RenderParagraph p
          when p.size.width + 0.5 < p.getMaxIntrinsicWidth(double.infinity) &&
              // A swap label kept only for its room is never seen.
              element.findAncestorWidgetOfExactType<Visibility>()?.visible !=
                  false)
        p.text.toPlainText(),
];

void main() {
  group('the record as the Logs page reads it', () {
    test('each line goes to its tab by its kind; U lines and an A line '
        'that is no error go nowhere', () {
      const cases = {
        'T vpn connecting': LogTab.connection,
        'T network wifi,other': LogTab.connection,
        'T probe domestic ok 72ms, international ok 196ms, door ok 130ms':
            LogTab.connection,
        'T refresh ok': LogTab.subscription,
        'T refresh http 500': LogTab.subscription,
        'C warning [TUN] default interface changed by monitor, => Wi-Fi':
            LogTab.core,
        'C info [DNS] hijack udp:53': LogTab.core,
        'E Bad state: no element': LogTab.errors,
        'E #0      CoreHandlerInterface._invokeMessage': LogTab.errors,
        'A [APP] helper ping failed: DioException [receive timeout]':
            LogTab.errors,
        'A [APP] Core method asyncTestDelay timed out after 10001ms':
            LogTab.errors,
        'A [APP] CoreMethodException(·, Core did not answer setupConfig, null)':
            LogTab.errors,
        'A [APP] message: Start TUN listening error: Access is denied.':
            LogTab.errors,
        'A [APP] initAppLinksListen': null,
        'A [APP] find · proxy: true': null,
        'U key char': null,
        'U push logs': null,
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(LogEntry.parse('$_t $key')!.tab, value, reason: key);
      }
    });

    test('red for an error, yellow for a warning, nothing for the rest', () {
      const cases = {
        'C error Start TUN listening error: Access is denied.': LogMark.error,
        'C warning [TCP] dial PROXY error: i/o timeout': LogMark.warning,
        'C info [DNS] hijack udp:53': LogMark.none,
        'E Bad state: no element': LogMark.error,
        'A [APP] init failed: x': LogMark.error,
        'T refresh timeout': LogMark.warning,
        'T refresh http 500': LogMark.warning,
        'T refresh ok': LogMark.none,
        'T vpn error connectTimeout': LogMark.warning,
        'T core died signal killed': LogMark.warning,
        'T vpn on': LogMark.none,
        'T ping 13 answered, 6 silent, best 71ms': LogMark.none,
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(LogEntry.parse('$_t $key')!.mark, value, reason: key);
      }
    });

    test('a line keeps its stamp in UTC, its count apart from its text, and '
        'itself whole for the copy', () {
      const line = '2026-10-19T14:41:40Z C warning dial tcp ·: refused ×5';
      final entry = LogEntry.parse(line)!;
      expect(entry.line, line);
      expect(entry.at, DateTime.utc(2026, 10, 19, 14, 41, 40));
      expect(entry.kind, 'C');
      expect(entry.text, 'warning dial tcp ·: refused');
      expect(entry.repeats, 5);
      expect(LogEntry.parse('2026-10-19T14:41:41Z E ')!.text, '');
      expect(LogEntry.parse('2026-10-19T14:41:41Z E ')!.repeats, 1);
      expect(LogEntry.parse('not a stamp T vpn on'), isNull);
    });

    test('the record gives seven days of diag.log as written, cleaned again, '
        'a pending repeat written first; a line and its count are both kept '
        'for «کپی»', () async {
      final old = _stamp(_now.subtract(const Duration(days: 8)));
      final diag = await _started([
        '$old T vpn on',
        '$_t T user ali-pc connected',
        '$_t U focus ShikooButton',
        '$_t A [APP] initAppLinksListen',
        '$_t C error dial failed',
      ], null);
      final machine = ShikooDiag(machine: {'ali-pc'});
      final home = Directory.systemTemp.createTempSync('logs');
      addTearDown(() => home.deleteSync(recursive: true));
      File('${home.path}/shikoo/diag.log')
        ..createSync(recursive: true)
        ..writeAsStringSync('$_t T user ali-pc connected\n');
      await machine.start(home.path);
      expect(machine.logEntries().single.line, '$_t T user · connected');

      diag
        ..release()
        ..add('T', 'vpn connecting')
        ..add('T', 'vpn connecting')
        ..add('T', 'vpn connecting');
      expect(
        [for (final e in diag.logEntries()) '${e.kind} ${e.text}'],
        [
          'T user ali-pc connected',
          'C error dial failed',
          'T app start',
          'T vpn connecting',
          'T vpn connecting',
        ],
      );
      expect(diag.logEntries().last.repeats, 3);
    });

    test('nothing under lib/shikoo reads FlClash\'s own logs, which keep links '
        'and addresses', () {
      final raw = RegExp(r'\b(logsProvider|exportLogs)\b');
      final readers = [
        for (final file in Directory('lib/shikoo').listSync(recursive: true))
          if (file is File &&
              file.path.endsWith('.dart') &&
              raw.hasMatch(file.readAsStringSync()))
            file.path,
      ];
      expect(readers, isEmpty);
    });
  });

  group('the Logs page', () {
    testWidgets('a tab shows its lines, the newest at the bottom; «خطاها» '
        'counts its lines in red', (tester) async {
      await _pump(tester);
      expect(find.text(_fa.logsTitle), findsOneWidget);
      expect(find.text(_fa.logsCaption), findsOneWidget);
      final connecting = find.textContaining('vpn connecting');
      final on = find.textContaining('vpn on');
      expect(
        tester.getTopLeft(on).dy,
        greaterThan(tester.getTopLeft(connecting).dy),
      );
      // A tab shorter than the page starts under the caption, not at the bottom.
      expect(
        tester.getTopLeft(find.textContaining('app start')).dy,
        lessThan(tester.getTopLeft(find.text(_fa.logsCaption)).dy + 120),
      );
      expect(find.textContaining('refresh'), findsNothing);
      expect(find.textContaining('app start'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Segmented<LogTab>),
          matching: find.text('۲'),
        ),
        findsOneWidget,
      );

      await tester.tap(_tab(_fa.logsErrors));
      await tester.pumpAndSettle();
      expect(find.textContaining('getTraffic timed out'), findsOneWidget);
      expect(find.textContaining('Bad state'), findsOneWidget);
      expect(find.textContaining('initAppLinksListen'), findsNothing);
      expect(find.textContaining('key char'), findsNothing);

      await tester.tap(_tab(_fa.logsCore));
      await tester.pumpAndSettle();
      expect(find.text('×۸'), findsOneWidget);
      final warning = tester
          .widget<Text>(find.textContaining('warning [TCP]'))
          .textSpan!;
      expect(
        (warning as TextSpan).children!.first,
        isA<TextSpan>()
            .having((s) => s.text, 'text', 'warning')
            .having((s) => s.style?.fontWeight, 'weight', FontWeight.w700)
            .having((s) => s.style?.color, 'color', ShikooColors.light.warning),
      );
    });

    testWidgets('«کپی» puts the open tab\'s lines on the clipboard exactly as '
        'written, says «کپی شد» for two seconds and keeps its width', (
      tester,
    ) async {
      final copied = _clipboard(tester);
      // Wide enough for the two buttons side by side: stacked, both fill the row whatever their label.
      await _pump(tester, size: const Size(900, 800));
      await tester.tap(_tab(_fa.logsCore));
      await tester.pumpAndSettle();
      final copy = _button(_fa.localProxyCopy);
      final width = tester.getSize(copy).width;
      // «کپی» sits by its icon, at the start of the room «کپی شد» keeps.
      final icon = tester.getRect(
        find.descendant(of: copy, matching: find.byType(SvgIcon)),
      );
      final label = tester.getRect(
        find.descendant(of: copy, matching: find.text(_fa.localProxyCopy)).last,
      );
      expect(icon.left - label.right, closeTo(Space.s2, 0.5));
      await tester.tap(copy);
      await tester.pump();
      expect(copied, [
        [
          for (final line in _record)
            if (line.contains(' C ')) line,
        ].join('\n'),
      ]);
      expect(_button(_fa.localProxyCopied), findsOneWidget);
      expect(tester.getSize(_button(_fa.localProxyCopied)).width, width);
      await tester.pump(const Duration(seconds: 2));
      expect(_button(_fa.localProxyCopy), findsOneWidget);
    });

    testWidgets('an empty tab says what will come and «کپی» is off; with no '
        'error there is no count', (tester) async {
      await _pump(tester, lines: ['$_t T vpn on']);
      expect(
        find.descendant(
          of: find.byType(Segmented<LogTab>),
          matching: find.text('۰'),
        ),
        findsNothing,
      );
      await tester.tap(_tab(_fa.logsErrors));
      await tester.pumpAndSettle();
      expect(find.text(_fa.logsEmptyTitle), findsOneWidget);
      expect(find.text(_fa.logsEmptyHelp(7)), findsOneWidget);
      expect(
        tester.widget<ShikooButton>(_button(_fa.localProxyCopy)).onPressed,
        isNull,
      );
      expect(
        tester.widget<ShikooButton>(_button(_fa.reportSendToSupport)).onPressed,
        isNotNull,
      );
    });

    testWidgets('a line shows the device\'s own time, under «امروز», «دیروز» '
        'or the Solar Hijri date', (tester) async {
      final midnight = DateTime(_now.year, _now.month, _now.day);
      final lines = [
        '${_stamp(midnight.subtract(const Duration(days: 3, hours: -12)))} T vpn a',
        '${_stamp(midnight.subtract(const Duration(seconds: 5)))} T vpn b',
        '${_stamp(midnight.add(const Duration(seconds: 5)))} T vpn c',
      ];
      await _pump(tester, lines: lines);
      expect(find.text('۲۳:۵۹:۵۵'), findsOneWidget);
      expect(find.text('۰۰:۰۰:۰۵'), findsOneWidget);
      expect(find.text('۱۲:۰۰:۰۰'), findsOneWidget);
      String date(DateTime day) {
        final j = toJalali(day);
        return '${DateFormat.EEEE('fa').format(day)} '
            '${NumberFormat('0', 'fa').format(j.day)} '
            '${_fa.jalaliMonths.split('|')[j.month - 1]}';
      }

      final yesterday = midnight.subtract(const Duration(seconds: 5));
      final old = midnight.subtract(const Duration(days: 3, hours: -12));
      expect(find.text('امروز · ${date(midnight)}'), findsOneWidget);
      expect(find.text('دیروز · ${date(yesterday)}'), findsOneWidget);
      expect(find.text(date(old)), findsOneWidget);
    });

    testWidgets('a line written once and again with its count is one row, '
        'counted once; «کپی» still takes both as written', (tester) async {
      final copied = _clipboard(tester);
      final lines = [
        '$_t T vpn connecting',
        '$_t T vpn connecting ×3',
        '$_t T vpn on',
        '$_t E Bad state: no element',
        '$_t E Bad state: no element ×2',
      ];
      await _pump(tester, lines: lines, size: const Size(900, 800));
      expect(find.textContaining('vpn connecting'), findsOneWidget);
      expect(find.text('×۳'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Segmented<LogTab>),
          matching: find.text('۱'),
        ),
        findsOneWidget,
      );
      await tester.tap(_button(_fa.localProxyCopy));
      await tester.pump();
      expect(copied, [lines.take(3).join('\n')]);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('five repeats read once mid-run show every count, five in '
        'all; «کپی» takes the file\'s lines', (tester) async {
      final copied = _clipboard(tester);
      SharedPreferences.setMockInitialValues({});
      _view(tester, const Size(900, 800), 1);
      final diag = await _started([], tester);
      diag.release();
      for (var i = 0; i < 3; i++) {
        diag.add('E', 'Bad state: X');
      }
      diag.logEntries();
      for (var i = 0; i < 2; i++) {
        diag.add('E', 'Bad state: X');
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          key: UniqueKey(),
          container: _container(diag),
          child: _app(const ShikooLogs()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_tab(_fa.logsErrors));
      await tester.pumpAndSettle();
      expect(find.textContaining('Bad state: X'), findsNWidgets(2));
      expect(find.text('×۳'), findsOneWidget);
      expect(find.text('×۲'), findsOneWidget);
      await tester.tap(_button(_fa.localProxyCopy));
      await tester.pump();
      final file = [
        for (final e in diag.logEntries())
          if (e.tab == LogTab.errors) e.line,
      ];
      expect(
        [for (final line in file) line.substring(21)],
        [
          'E Bad state: X',
          'E Bad state: X ×3',
          'E Bad state: X',
          'E Bad state: X ×2',
        ],
      );
      expect(copied, [file.join('\n')]);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a tab shows its newest 200 rows only, copies the file lines '
        'behind them, and counts at most 200 errors', (tester) async {
      final copied = _clipboard(tester);
      final start = _now.subtract(const Duration(hours: 5));
      String at(int i) => _stamp(start.add(Duration(seconds: i)));
      final connection = [
        for (var i = 0; i < 250; i++) ...[
          '${at(i)} T vpn step$i',
          // The oldest row shown is a count; its plain line goes with it into «کپی».
          if (i == 50) '${at(i)} T vpn step$i ×2',
        ],
      ];
      final errors = [for (var i = 0; i < 250; i++) '${at(i)} E failure $i'];
      await _pump(
        tester,
        lines: [...connection, ...errors],
        size: const Size(900, 800),
      );
      expect(
        find.descendant(
          of: find.byType(Segmented<LogTab>),
          matching: find.text('۲۰۰'),
        ),
        findsOneWidget,
      );
      for (var i = 0; i < 5; i++) {
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, 100000),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('×۲'), findsOneWidget);
      expect(find.textContaining('step49'), findsNothing);
      await tester.tap(_button(_fa.localProxyCopy));
      await tester.pump();
      expect(copied, [connection.sublist(50).join('\n')]);
      await tester.pump(const Duration(seconds: 2));
    });

    group('the rows shown and the lines «کپی» takes behind them', () {
      String at(int i) => _stamp(
        _now.subtract(const Duration(hours: 5)).add(Duration(seconds: i)),
      );

      Future<String> copy(WidgetTester tester, List<String> lines) async {
        final copied = _clipboard(tester);
        await _pump(tester, lines: lines, size: const Size(900, 800));
        await tester.tap(_button(_fa.localProxyCopy));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        return copied.single;
      }

      testWidgets('300 line and count pairs are 200 rows, their 400 lines', (
        tester,
      ) async {
        final lines = [
          for (var i = 0; i < 300; i++) ...[
            '${at(i)} T vpn s$i',
            '${at(i)} T vpn s$i ×2',
          ],
        ];
        final copied = await copy(tester, lines);
        expect(_shownRows(tester), 200);
        expect(copied, lines.sublist(200).join('\n'));
      });

      testWidgets('a pair just past the 200th row stays out of the copy', (
        tester,
      ) async {
        final lines = [
          '${at(0)} T vpn p',
          '${at(0)} T vpn p ×2',
          for (var i = 1; i <= 200; i++) '${at(i)} T vpn s$i',
        ];
        final copied = await copy(tester, lines);
        expect(_shownRows(tester), 200);
        expect(copied, lines.sublist(2).join('\n'));
      });

      testWidgets('an older recorder\'s line with two counts after it is '
          'copied whole', (tester) async {
        final lines = [
          '${at(0)} T vpn x',
          '${at(1)} T vpn x ×2',
          '${at(2)} T vpn x ×2',
          '${at(3)} T vpn y',
        ];
        final copied = await copy(tester, lines);
        expect(_shownRows(tester), 2);
        expect(copied, lines.join('\n'));
      });
    });

    testWidgets('a long tab opens on its newest line', (tester) async {
      final lines = [
        for (var i = 0; i < 80; i++)
          '${_stamp(_now.subtract(Duration(minutes: 200 - i)))} T vpn step$i',
      ];
      await _pump(tester, lines: lines);
      final foot = tester.getRect(_button(_fa.reportSendToSupport)).top;
      final newest = tester.getRect(find.textContaining('step79'));
      expect(newest.bottom, lessThanOrEqualTo(foot));
    });

    testWidgets('a screen reader hears only the label «کپی» shows', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      _clipboard(tester);
      await _pump(tester, size: const Size(900, 800));
      String heard(String label) => tester
          .getSemantics(
            find
                .descendant(of: _button(label), matching: find.byType(RichText))
                .last,
          )
          .label;
      expect(heard(_fa.localProxyCopy), _fa.localProxyCopy);
      await tester.tap(_button(_fa.localProxyCopy));
      await tester.pump();
      expect(heard(_fa.localProxyCopied), _fa.localProxyCopied);
      await tester.pump(const Duration(seconds: 2));
      semantics.dispose();
    });

    testWidgets('the tabs sit right under the bar, as `.logs-head`', (
      tester,
    ) async {
      await _pump(tester);
      expect(
        tester.getTopLeft(find.byType(Segmented<LogTab>)).dy,
        ShikooSizes.phone.appbar,
      );
    });

    testWidgets('«ارسال گزارش به پشتیبانی» opens the report preview', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(_button(_fa.reportSendToSupport));
      await tester.pumpAndSettle();
      expect(find.text(_fa.reportTitle), findsOneWidget);
    });
  });

  group('Settings › «گزارش‌ها»', () {
    Future<void> settings(WidgetTester tester, {bool tv = false}) async {
      SharedPreferences.setMockInitialValues({});
      _view(tester, tv ? const Size(1920, 1080) : const Size(412, 4000), 1);
      final diag = await _started(_record, tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          key: UniqueKey(),
          container: _container(diag, tv: tv),
          child: _app(const ShikooSettings(), tv: tv),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('on a phone it sits under «عیب‌یابی و گزارش» without keys '
        'and opens the page', (tester) async {
      await settings(tester);
      expect(find.text(_fa.logsRowHelp(7)), findsOneWidget);
      expect(find.text('Ctrl'), findsNothing);
      expect(
        tester.getTopLeft(find.text(_fa.logsTitle)).dy,
        greaterThan(tester.getTopLeft(find.text(_fa.diagTitle)).dy),
      );
      await tester.tap(find.text(_fa.logsTitle));
      await tester.pumpAndSettle();
      expect(find.byType(ShikooLogs), findsOneWidget);
    });

    testWidgets('on a computer it shows Ctrl R beside it, left to right', (
      tester,
    ) async {
      await settings(tester);
      expect(
        tester.getTopLeft(find.text('Ctrl')).dx,
        lessThan(tester.getTopLeft(find.text('R')).dx),
      );
    }, variant: _windows);

    testWidgets('a TV has no such row', (tester) async {
      await settings(tester, tv: true);
      expect(find.text(_fa.diagTitle), findsOneWidget);
      expect(find.text(_fa.logsTitle), findsNothing);
    });
  });

  group('Ctrl+R', () {
    Future<void> home(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      _view(tester, const Size(864, 492), 1);
      final diag = await _started(_record, tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          key: UniqueKey(),
          container: _container(diag),
          child: _app(
            const Scaffold(body: Text('home')),
            builder: (context, child) =>
                shikooFrame(context, child!, managers: (page) => page),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> ctrlR(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('opens the Logs page from wherever the app is, and only once', (
      tester,
    ) async {
      await home(tester);
      await ctrlR(tester);
      expect(find.byType(ShikooLogs), findsOneWidget);
      await ctrlR(tester);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ShikooLogs), findsNothing);
      expect(find.text('home'), findsOneWidget);
    }, variant: _windows);

    testWidgets('is nothing on a phone', (tester) async {
      await home(tester);
      await ctrlR(tester);
      expect(find.byType(ShikooLogs), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });

  group('with the real font, every label whole and nothing outside', () {
    setUpAll(loadShikooFonts);
    final long = [..._record, '$_t $_timeout'];

    Future<void> check(WidgetTester tester, Size size) async {
      for (final language in ['fa', 'en']) {
        for (final scale in [1.0, 1.45]) {
          for (final tab in [LogTab.connection, LogTab.errors]) {
            final at = '$language ${size.width}x${size.height} x$scale $tab';
            await _pump(
              tester,
              lines: long,
              size: size,
              scale: scale,
              language: language,
            );
            final l = lookupShikooL10n(Locale(language));
            if (tab == LogTab.errors) {
              await tester.tap(_tab(l.logsErrors));
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull, reason: at);
            expect(_cut(tester), isEmpty, reason: at);
            for (final button in [l.reportSendToSupport, l.localProxyCopy]) {
              final box = tester.getRect(_button(button));
              expect(box.bottom, lessThanOrEqualTo(size.height), reason: at);
              expect(box.left, greaterThanOrEqualTo(0), reason: at);
              expect(box.right, lessThanOrEqualTo(size.width), reason: at);
            }
          }
        }
      }
    }

    testWidgets('a 360 by 800 phone', (tester) async {
      await check(tester, const Size(360, 800));
    });

    testWidgets('an 864 by 492 window and an 1100 by 688 one', (tester) async {
      await check(tester, const Size(864, 492));
      await check(tester, const Size(1100, 688));
    }, variant: _windows);
  });
}
